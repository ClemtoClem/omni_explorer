/// @file file_service.dart
/// @brief Service principal pour les opérations sur le système de fichiers.
///
/// Fournit toutes les opérations CRUD sur les fichiers :
/// - Liste, copie, déplacement, renommage
/// - Création de dossiers
/// - Détection des stockages disponibles (interne + SD)
/// - Intégration avec la corbeille
///
/// @author OmniExplorer
/// @version 1.0

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';
import '../../app/constants/app_constants.dart';
import '../models/file_item.dart';
import '../utils/file_utils.dart';
import 'trash_service.dart';

/// Service singleton pour les opérations fichier.
class FileService {
  FileService._();
  static final FileService instance = FileService._();

  late final TrashService _trashService;
  bool _initialized = false;

  // ─── Initialisation ───────────────────────────────────────────────────────

  /// Initialise le service (à appeler au démarrage de l'app).
  Future<void> initialize() async {
    if (_initialized) return;
    _trashService = TrashService();
    await _trashService.init();
    _initialized = true;
  }

  // ─── Répertoires système ──────────────────────────────────────────────────

  /// Retourne tous les points de montage disponibles (interne + SD cards).
  ///
  /// @returns Liste des répertoires racines accessibles.
  Future<List<StorageInfo>> getAvailableStorages() async {
    final storages = <StorageInfo>[];

    // ── Stockage interne ──────────────────────────────────────────────────
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        // Remonter jusqu'à la racine du stockage interne (/storage/emulated/0)
        String internalRoot = extDir.path;
        final parts = internalRoot.split('/');
        // /storage/emulated/0/Android/... → /storage/emulated/0
        final idx = parts.indexOf('Android');
        if (idx > 0) {
          internalRoot = parts.sublist(0, idx).join('/');
        }
        storages.add(StorageInfo(
          path: internalRoot,
          label: 'Stockage interne',
          isExternal: false,
          isAvailable: Directory(internalRoot).existsSync(),
        ));
      }
    } catch (e) {
      debugPrint('[FileService] Erreur stockage interne: $e');
    }

    // ── Stockages externes (SD cards) ─────────────────────────────────────
    try {
      final extDirs = await ExternalPath.getExternalStorageDirectories();
      if (extDirs != null) {
        for (int i = 0; i < extDirs.length; i++) {
          String sdPath = extDirs[i];
          final parts = sdPath.split('/');
          final idx = parts.indexOf('Android');
          if (idx > 0) sdPath = parts.sublist(0, idx).join('/');

          // Éviter les doublons
          if (storages.any((s) => s.path == sdPath)) continue;

          storages.add(StorageInfo(
            path: sdPath,
            label: 'Carte SD ${i + 1}',
            isExternal: true,
            isAvailable: Directory(sdPath).existsSync(),
          ));
        }
      }
    } catch (e) {
      debugPrint('[FileService] Erreur stockages externes: $e');
    }

    // ── Linux : pas de stockage « externe » Android, le dossier personnel
    // sert d'espace principal (même racine que l'explorateur).
    if (storages.isEmpty && Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        storages.add(StorageInfo(
          path: home,
          label: 'Dossier personnel',
          isExternal: false,
          isAvailable: true,
        ));
      }
    }

    return storages;
  }

  /// Retourne les répertoires par défaut (Documents, Téléchargements, etc.).
  ///
  /// @returns Liste des [DefaultDirectory] disponibles.
  Future<List<DefaultDirectory>> getDefaultDirectories() async {
    final dirs = <DefaultDirectory>[];
    final storages = await getAvailableStorages();
    if (storages.isEmpty) return dirs;

    final base = storages.first.path;

    final candidates = [
      DefaultDirectory(
        path: p.join(base, 'Download'),
        label: 'Téléchargements',
        icon: 'download',
        storageType: StorageDirectory.downloads,
      ),
      DefaultDirectory(
        path: p.join(base, 'Documents'),
        label: 'Documents',
        icon: 'description',
        storageType: StorageDirectory.documents,
      ),
      DefaultDirectory(
        path: p.join(base, 'DCIM'),
        label: 'Photos',
        icon: 'photo_camera',
        storageType: StorageDirectory.dcim,
      ),
      DefaultDirectory(
        path: p.join(base, 'Pictures'),
        label: 'Images',
        icon: 'image',
        storageType: StorageDirectory.pictures,
      ),
      DefaultDirectory(
        path: p.join(base, 'Music'),
        label: 'Musique',
        icon: 'music_note',
        storageType: StorageDirectory.music,
      ),
      DefaultDirectory(
        path: p.join(base, 'Movies'),
        label: 'Vidéos',
        icon: 'movie',
        storageType: StorageDirectory.movies,
      ),
      DefaultDirectory(
        path: await _trashService.trashDirectory,  // getter ajouté dans TrashService
        label: 'Corbeille',
        icon: 'delete',
        storageType: null,
        isTrash: true,
      ),
    ];

    // N'inclure que les dossiers existants (sauf la corbeille toujours présente)
    for (final dir in candidates) {
      if (dir.isTrash || Directory(dir.path).existsSync()) {
        dirs.add(dir);
      }
    }

    return dirs;
  }

  // ─── Listage ──────────────────────────────────────────────────────────────

  /// Liste le contenu d'un répertoire.
  ///
  /// @param dirPath Chemin du répertoire à lister.
  /// @param showHidden Inclure les fichiers cachés (commençant par '.').
  /// @param typeFilter Filtre optionnel par catégorie de fichier.
  /// @param extensionFilter Filtre par extension ou nom.
  /// @param sortMode Ordre de tri.
  /// @param sortAsc Tri ascendant si vrai.
  /// @returns Liste des [FileItem] du répertoire.
  Future<List<FileItem>> listDirectory(
    String dirPath, {
    bool showHidden = false,
    Set<FileCategory>? typeFilter,
    String? extensionFilter,
    SortMode sortMode = SortMode.name,
    bool sortAsc = true,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final items = <FileItem>[];

    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final name = p.basename(entity.path);
          // Masquer les fichiers cachés si demandé
          if (!showHidden && name.startsWith('.')) continue;

          final item = await FileItem.fromEntity(entity);

          // Appliquer les filtres de type
          if (typeFilter != null && typeFilter.isNotEmpty) {
            if (!typeFilter.contains(item.category)) continue;
          }

          // Appliquer le filtre d'extension
          if (extensionFilter != null && extensionFilter.isNotEmpty) {
            if (!item.name.toLowerCase().contains(extensionFilter.toLowerCase())) {
              continue;
            }
          }

          items.add(item);
        } catch (_) {
          // Ignorer les fichiers inaccessibles
        }
      }
    } catch (e) {
      debugPrint('[FileService] Erreur listage $dirPath: $e');
    }

    // Tri : répertoires en tête, puis selon sortMode
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      int cmp;
      switch (sortMode) {
        case SortMode.date: cmp = a.modified.compareTo(b.modified); break;
        case SortMode.size: cmp = a.size.compareTo(b.size); break;
        case SortMode.type: cmp = a.extension.compareTo(b.extension); break;
        case SortMode.name: cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return sortAsc ? cmp : -cmp;
    });
    return items;
  }

  /// Recherche récursive dans un répertoire.
  ///
  /// @param rootPath Répertoire de départ.
  /// @param query Terme de recherche (insensible à la casse).
  /// @param maxResults Limite du nombre de résultats.
  /// @returns Liste des [FileItem] correspondants.
  Future<List<FileItem>> search(
    String rootPath,
    String query, {
    int maxResults = 200,
  }) async {
    final results = <FileItem>[];
    final lowerQuery = query.toLowerCase();

    try {
      final dir = Directory(rootPath);
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (results.length >= maxResults) break;
        final name = p.basename(entity.path).toLowerCase();
        if (name.contains(lowerQuery)) {
          try {
            results.add(await FileItem.fromEntity(entity));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[FileService] Erreur recherche: $e');
    }

    return results;
  }

  // ─── Opérations ───────────────────────────────────────────────────────────

  /// Crée un nouveau répertoire.
  ///
  /// @param parentPath Chemin du dossier parent.
  /// @param name Nom du nouveau dossier.
  /// @returns Le [FileItem] créé, ou null en cas d'erreur.
  Future<FileItem?> createDirectory(String parentPath, String name) async {
    try {
      final newPath = FileUtils.resolveNameConflict(p.join(parentPath, name));
      final dir = await Directory(newPath).create(recursive: true);
      return await FileItem.fromEntity(dir);
    } catch (e) {
      debugPrint('[FileService] Erreur création dossier: $e');
      return null;
    }
  }

  /// Renomme un fichier ou dossier.
  ///
  /// @param item L'élément à renommer.
  /// @param newName Nouveau nom.
  /// @returns Le nouveau [FileItem], ou null en cas d'erreur.
  Future<FileItem?> rename(FileItem item, String newName) async {
    try {
      final newPath = p.join(p.dirname(item.path), newName);
      if (item.isDirectory) {
        final renamed = await Directory(item.path).rename(newPath);
        return await FileItem.fromEntity(renamed);
      } else {
        final renamed = await File(item.path).rename(newPath);
        return await FileItem.fromEntity(renamed);
      }
    } catch (e) {
      debugPrint('[FileService] Erreur renommage: $e');
      return null;
    }
  }

  /// Copie un fichier vers une destination.
  ///
  /// @param item L'élément source.
  /// @param destinationDir Répertoire de destination.
  /// @returns Le nouveau [FileItem] copié.
  Future<FileItem?> copy(FileItem item, String destinationDir) async {
    try {
      final destPath = FileUtils.resolveNameConflict(
          p.join(destinationDir, item.name));

      if (item.isDirectory) {
        await _copyDirectory(Directory(item.path), Directory(destPath));
        return await FileItem.fromEntity(Directory(destPath));
      } else {
        final copied = await File(item.path).copy(destPath);
        return await FileItem.fromEntity(copied);
      }
    } catch (e) {
      debugPrint('[FileService] Erreur copie: $e');
      return null;
    }
  }

  /// Copie récursive d'un dossier.
  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  /// Déplace un fichier ou dossier.
  ///
  /// @param item L'élément à déplacer.
  /// @param destinationDir Répertoire de destination.
  /// @returns Le nouveau [FileItem] déplacé.
  Future<FileItem?> move(FileItem item, String destinationDir) async {
    try {
      final destPath = FileUtils.resolveNameConflict(
          p.join(destinationDir, item.name));

      if (item.isDirectory) {
        final moved = await Directory(item.path).rename(destPath);
        return await FileItem.fromEntity(moved);
      } else {
        final moved = await File(item.path).rename(destPath);
        return await FileItem.fromEntity(moved);
      }
    } catch (e) {
      // Si rename échoue (cross-device), fallback copy+delete
      final copied = await copy(item, destinationDir);
      if (copied != null) await delete(item, permanent: true);
      return copied;
    }
  }

  /// Supprime un élément (vers la corbeille ou définitivement).
  ///
  /// @param item L'élément à supprimer.
  /// @param permanent Si true, suppression définitive sans corbeille.
  Future<bool> delete(FileItem item, {bool permanent = false}) async {
    try {
      if (permanent) {
        if (item.isDirectory) {
          await Directory(item.path).delete(recursive: true);
        } else {
          await File(item.path).delete();
        }
        return true;
      } else {
        await _trashService.moveToTrash(item.path);
        return true;
      }
    } catch (e) {
      debugPrint('[FileService] Erreur suppression: $e');
      return false;
    }
  }

  /// Suppression multiple d'éléments.
  ///
  /// @param items Les éléments à supprimer.
  /// @param permanent Suppression définitive.
  /// @returns Nombre d'éléments supprimés avec succès.
  Future<int> deleteMultiple(
    List<FileItem> items, {
    bool permanent = false,
  }) async {
    int count = 0;
    for (final item in items) {
      if (await delete(item, permanent: permanent)) count++;
    }
    return count;
  }

  /// Lit le contenu textuel d'un fichier.
  ///
  /// @param path Chemin du fichier texte.
  /// @returns Contenu du fichier.
  Future<String?> readTextFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (e) {
      debugPrint('[FileService] Erreur lecture $path: $e');
      return null;
    }
  }

  /// Écrit du contenu dans un fichier texte.
  ///
  /// @param path Chemin de destination.
  /// @param content Contenu à écrire.
  Future<bool> writeTextFile(String path, String content) async {
    try {
      await File(path).writeAsString(content);
      return true;
    } catch (e) {
      debugPrint('[FileService] Erreur écriture $path: $e');
      return false;
    }
  }

  // ─── Métadonnées ──────────────────────────────────────────────────────────

  /// Retourne les informations détaillées d'un fichier.
  ///
  /// @param path Chemin du fichier.
  /// @returns [FileItem] ou null.
  Future<FileItem?> getFileInfo(String path) async {
    try {
      final entity = FileSystemEntity.typeSync(path) ==
              FileSystemEntityType.directory
          ? Directory(path)
          : File(path);
      return await FileItem.fromEntity(entity);
    } catch (_) {
      return null;
    }
  }
}

// ─── Modèles auxiliaires ──────────────────────────────────────────────────────

/// Informations sur un point de montage de stockage.
class StorageInfo {
  final String path;
  final String label;
  final bool isExternal;
  final bool isAvailable;

  /// Espace total en octets (0 si non disponible).
  final int totalBytes;

  /// Espace libre en octets (0 si non disponible).
  final int freeBytes;

  const StorageInfo({
    required this.path,
    required this.label,
    required this.isExternal,
    required this.isAvailable,
    this.totalBytes = 0,
    this.freeBytes = 0,
  });
}

/// Répertoire par défaut du système.
class DefaultDirectory {
  final String path;
  final String label;
  final String icon;
  final StorageDirectory? storageType;
  final bool isTrash;

  const DefaultDirectory({
    required this.path,
    required this.label,
    required this.icon,
    required this.storageType,
    this.isTrash = false,
  });
}
