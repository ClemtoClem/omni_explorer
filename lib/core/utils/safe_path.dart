/// @file safe_path.dart
/// @brief Validation des chemins provenant de sources non fiables (entrées
/// d'archive, chemins relatifs demandés au serveur Go Live…).
///
/// Empêche l'écriture ou la lecture hors d'un dossier racine :
/// - « Zip Slip » : entrée `../../x`, chemin absolu `/x`, lecteur `C:\x` ;
/// - liens symboliques déjà présents dans la racine qui pointent ailleurs.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Levée quand un chemin sortirait du dossier racine autorisé.
class UnsafePathException implements Exception {
  /// Chemin tel que fourni par la source non fiable.
  final String entry;

  /// Raison lisible (français), destinée à l'utilisateur.
  final String reason;

  const UnsafePathException(this.entry, this.reason);

  @override
  String toString() => 'Chemin refusé « $entry » : $reason';
}

/// Fonctions de validation purement lexicales (sans accès disque).
class SafePath {
  SafePath._();

  static final RegExp _drivePrefix = RegExp(r'^[A-Za-z]:');

  /// Découpe [entry] en segments sûrs, ou lève [UnsafePathException].
  ///
  /// `\` est traité comme un séparateur (archives créées sous Windows ou
  /// forgées). Les segments vides et `.` sont ignorés ; tout segment `..` est
  /// refusé, même s'il resterait dans la racine (`a/../b`) : une archive
  /// légitime n'en contient pas.
  static List<String> segments(String entry) {
    if (entry.contains('\u0000')) {
      throw UnsafePathException(entry, 'caractère nul');
    }
    final unified = entry.replaceAll('\\', '/');
    if (unified.startsWith('/')) {
      throw UnsafePathException(entry, 'chemin absolu');
    }
    if (_drivePrefix.hasMatch(unified)) {
      throw UnsafePathException(entry, 'chemin absolu (lecteur)');
    }
    final parts = <String>[];
    for (final s in unified.split('/')) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        throw UnsafePathException(entry, 'remonte au-dessus du dossier');
      }
      parts.add(s);
    }
    return parts;
  }

  /// Chemin absolu de [entry] dans [root], ou [UnsafePathException].
  ///
  /// Un [entry] vide ou réduit à `.` désigne la racine elle-même.
  static String resolveWithin(String root, String entry) {
    final base = p.normalize(p.absolute(root));
    final parts = segments(entry);
    if (parts.isEmpty) return base;
    final resolved = p.normalize(p.joinAll([base, ...parts]));
    // Garde-fou : segments() rend déjà ce cas impossible.
    if (!p.isWithin(base, resolved)) {
      throw UnsafePathException(entry, 'sort du dossier de destination');
    }
    return resolved;
  }
}

/// Dossier de destination d'une extraction, protégé contre les liens
/// symboliques qui pointeraient hors de la racine.
///
/// Usage : valider tous les noms avec [SafePath.resolveWithin] avant d'écrire,
/// puis obtenir chaque chemin d'écriture via [prepareFile] / [prepareDirectory].
class SafeExtractionRoot {
  /// Racine telle que demandée (normalisée, absolue).
  final String root;

  /// Racine après résolution des liens (`/sdcard` → `/storage/emulated/0`).
  final String _realRoot;

  /// Dossiers déjà vérifiés (évite de résoudre les liens à chaque entrée).
  final Set<String> _verifiedDirs = {};

  SafeExtractionRoot._(this.root, this._realRoot);

  /// Crée la racine si besoin et résout son chemin réel.
  static Future<SafeExtractionRoot> open(String root) async {
    final base = p.normalize(p.absolute(root));
    await Directory(base).create(recursive: true);
    final real = await Directory(base).resolveSymbolicLinks();
    return SafeExtractionRoot._(base, p.normalize(real));
  }

  /// Prépare l'écriture du fichier [entry] : valide le nom, crée les dossiers
  /// parents et vérifie qu'aucun lien symbolique ne fait sortir de la racine.
  /// Retourne le chemin à écrire.
  Future<String> prepareFile(String entry) async {
    final target = SafePath.resolveWithin(root, entry);
    if (target == root) {
      throw UnsafePathException(entry, 'nom de fichier vide');
    }
    await _ensureDirectory(p.dirname(target), entry);
    // Un lien existant à cet emplacement serait suivi par l'écriture.
    if (await FileSystemEntity.isLink(target)) {
      throw UnsafePathException(entry, 'la destination est un lien symbolique');
    }
    return target;
  }

  /// Prépare le dossier [entry] (le crée) et retourne son chemin.
  Future<String> prepareDirectory(String entry) async {
    final target = SafePath.resolveWithin(root, entry);
    await _ensureDirectory(target, entry);
    return target;
  }

  /// Crée [dir] (dans la racine) après avoir vérifié son plus proche ancêtre
  /// existant : la vérification a lieu AVANT la création, pour ne jamais
  /// créer de dossier hors de la racine à travers un lien.
  Future<void> _ensureDirectory(String dir, String entry) async {
    if (_verifiedDirs.contains(dir)) return;
    var existing = dir;
    while (existing != root &&
        await FileSystemEntity.type(existing) ==
            FileSystemEntityType.notFound) {
      existing = p.dirname(existing);
    }
    if (await FileSystemEntity.type(existing) !=
        FileSystemEntityType.directory) {
      // Un fichier (ou un lien vers un fichier) occupe la place d'un dossier.
      throw UnsafePathException(entry, 'un fichier bloque le chemin');
    }
    final real = p.normalize(await Directory(existing).resolveSymbolicLinks());
    if (real != _realRoot && !p.isWithin(_realRoot, real)) {
      throw UnsafePathException(
          entry, 'un lien symbolique mène hors du dossier de destination');
    }
    if (existing != dir) await Directory(dir).create(recursive: true);
    _verifiedDirs.add(dir);
  }
}
