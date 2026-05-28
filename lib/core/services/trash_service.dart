/// @file trash_service.dart
/// @brief Service de gestion de la corbeille d'OmniExplorer.
///
/// Gère le déplacement des fichiers vers la corbeille, leur restauration
/// et leur suppression définitive. Si l'OS ne dispose pas d'une corbeille
/// native, le service crée un répertoire caché ".omni_trash".

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../app/constants/app_constants.dart';
import '../models/file_item.dart';

/// @class TrashService
/// @brief Singleton gérant la corbeille de l'application.
class TrashService extends ChangeNotifier {
  static final TrashService _instance = TrashService._();
  factory TrashService() => _instance;
  TrashService._();

  final _uuid = const Uuid();
  Directory? _trashDir;
  final List<TrashItem> _items = [];

  /// Liste des éléments en corbeille.
  List<TrashItem> get items => List.unmodifiable(_items);

  /// Chemin du répertoire de la corbeille (initialise le service si besoin).
  Future<String> get trashDirectory async {
    await _ensureInit();
    return _trashDir!.path;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// @brief Initialise le répertoire de la corbeille et charge les métadonnées.
  Future<void> init() async {
    final base = await getExternalStorageDirectory() ??
                 await getApplicationDocumentsDirectory();
    _trashDir = Directory(p.join(base.path, AppConstants.trashFolderName));
    if (!await _trashDir!.exists()) await _trashDir!.create(recursive: true);
    await _loadMeta();
  }

  // ── Déplacement vers la corbeille ─────────────────────────────────────────

  /// @brief Déplace un fichier ou répertoire vers la corbeille.
  /// @param path Chemin de l'élément à supprimer.
  /// @return Le [TrashItem] créé.
  Future<TrashItem?> moveToTrash(String path) async {
    await _ensureInit();
    final entity = FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);
    if (!entity.existsSync()) return null;

    final id         = _uuid.v4();
    final ext        = p.extension(path);
    final trashedName= '$id$ext';
    final trashedPath= p.join(_trashDir!.path, trashedName);

    try {
      await entity.rename(trashedPath);
    } catch (_) {
      // Si rename échoue (partitions différentes), on copie puis supprime
      if (entity is File) {
        await (entity).copy(trashedPath);
        await entity.delete();
      } else {
        await _copyDir(entity as Directory, Directory(trashedPath));
        await (entity).delete(recursive: true);
      }
    }

    final stat = await FileStat.stat(trashedPath);
    final item = TrashItem(
      trashedPath:  trashedPath,
      originalPath: path,
      deletedAt:    DateTime.now(),
      isDirectory:  entity is Directory,
      size:         stat.size < 0 ? 0 : stat.size,
    );
    _items.add(item);
    await _saveMeta();
    notifyListeners();
    return item;
  }

  // ── Restauration ──────────────────────────────────────────────────────────

  /// @brief Restaure un élément de la corbeille vers son chemin d'origine.
  /// @param item L'élément à restaurer.
  Future<bool> restore(TrashItem item) async {
    final entity = item.isDirectory
        ? Directory(item.trashedPath) as FileSystemEntity
        : File(item.trashedPath);
    if (!entity.existsSync()) {
      _items.remove(item);
      await _saveMeta();
      notifyListeners();
      return false;
    }

    // Crée le répertoire parent si nécessaire
    final parent = Directory(p.dirname(item.originalPath));
    if (!parent.existsSync()) await parent.create(recursive: true);

    try {
      await entity.rename(item.originalPath);
    } catch (_) {
      if (entity is File) {
        await entity.copy(item.originalPath);
        await entity.delete();
      }
    }

    _items.remove(item);
    await _saveMeta();
    notifyListeners();
    return true;
  }

  // ── Suppression définitive ────────────────────────────────────────────────

  /// @brief Supprime définitivement un élément de la corbeille.
  Future<void> deletePermanently(TrashItem item) async {
    final entity = item.isDirectory
        ? Directory(item.trashedPath) as FileSystemEntity
        : File(item.trashedPath);
    if (entity.existsSync()) {
      await entity.delete(recursive: true);
    }
    _items.remove(item);
    await _saveMeta();
    notifyListeners();
  }

  /// @brief Vide complètement la corbeille.
  Future<void> emptyTrash() async {
    for (final item in List.from(_items)) {
      await deletePermanently(item);
    }
  }

  // ── Taille totale ─────────────────────────────────────────────────────────

  /// @brief Retourne la taille totale des éléments en corbeille.
  int get totalSize => _items.fold(0, (s, i) => s + i.size);

  // ── Persistance ───────────────────────────────────────────────────────────

  Future<void> _loadMeta() async {
    final metaFile = File(p.join(_trashDir!.path, AppConstants.trashMetaFile));
    if (!metaFile.existsSync()) return;
    try {
      final json = jsonDecode(await metaFile.readAsString()) as List;
      _items.clear();
      _items.addAll(json.map((e) => TrashItem.fromMap(e as Map<String, dynamic>)));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveMeta() async {
    final metaFile = File(p.join(_trashDir!.path, AppConstants.trashMetaFile));
    await metaFile.writeAsString(jsonEncode(_items.map((e) => e.toMap()).toList()));
  }

  Future<void> _ensureInit() async {
    if (_trashDir == null) await init();
  }

  // ── Copie récursive ───────────────────────────────────────────────────────

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      if (entity is File) {
        await entity.copy(p.join(dst.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDir(entity,
            Directory(p.join(dst.path, p.basename(entity.path))));
      }
    }
  }
}
