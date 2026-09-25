/// @file file_item.dart
/// @brief Modèles de données représentant les éléments du système de fichiers.
///
/// Contient [FileItem], [ShortcutItem] et [TrashItem].
/// Chaque modèle expose une unique sérialisation JSON (Map<String, dynamic>)
/// utilisée aussi bien pour la persistance SQLite que pour les SharedPreferences,
/// évitant ainsi la duplication entre `toJson`/`toMap` et `fromJson`/`fromMap`.

import 'dart:io';
import 'package:path/path.dart' as p;
import '../../app/constants/app_constants.dart';
import '../utils/file_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// @class FileItem
/// @brief Représente un fichier ou un répertoire avec ses métadonnées.
class FileItem {
  /// Chemin absolu de l'élément.
  final String path;

  /// Nom du fichier ou du répertoire.
  final String name;

  /// Vrai si c'est un répertoire.
  final bool isDirectory;

  /// Taille en octets (0 pour les répertoires).
  final int size;

  /// Date de dernière modification.
  final DateTime modified;

  /// Catégorie du fichier.
  final FileCategory category;

  /// Vrai si l'élément est caché (commence par '.').
  final bool isHidden;

  const FileItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.category,
    required this.isHidden,
  });

  /// @brief Crée un [FileItem] depuis une [FileSystemEntity].
  static Future<FileItem> fromEntity(FileSystemEntity entity,
      {FileStat? stat}) async {
    FileStat? s;
    try {
      s = stat ?? await entity.stat();
    } catch (_) {
      s = null;
    }
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    return FileItem(
      path:        entity.path,
      name:        name,
      isDirectory: isDir,
      size:        isDir ? 0 : (s?.size ?? 0),
      modified:    s?.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
      category:    FileUtils.categoryOf(entity),
      isHidden:    name.startsWith('.'),
    );
  }

  /// @brief Crée une copie avec des champs modifiés.
  FileItem copyWith({String? path, String? name, int? size, DateTime? modified}) {
    return FileItem(
      path:        path     ?? this.path,
      name:        name     ?? this.name,
      isDirectory: isDirectory,
      size:        size     ?? this.size,
      modified:    modified ?? this.modified,
      category:    category,
      isHidden:    isHidden,
    );
  }

  /// Extension du fichier (sans le point, en minuscule).
  String get extension => FileUtils.extOf(path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FileItem && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileItem($path)';

  String toStringDebug() => 
      '[${isDirectory ? "DIR " : "FILE"}] '
      '$name '
      '(${size}o) '
      '${isHidden ? "[hidden]" : ""}';
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class ShortcutItem
/// @brief Raccourci vers un répertoire favori.
///
/// Utilise une unique représentation sérialisée [toMap] / [fromMap] qui sert
/// à la fois pour SQLite et pour les SharedPreferences (JSON).
class ShortcutItem {
  final String  id;
  final String  name;
  final String  path;
  final String? iconName;

  const ShortcutItem({
    required this.id,
    required this.name,
    required this.path,
    this.iconName,
  });

  // ── Sérialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    'id':   id,
    'name': name,
    'path': path,
    'icon': iconName,
  };

  factory ShortcutItem.fromMap(Map<String, dynamic> map) => ShortcutItem(
    id:       map['id']   as String,
    name:     map['name'] as String,
    path:     map['path'] as String,
    iconName: map['icon'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ShortcutItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ShortcutItem($name → $path)';
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class TrashItem
/// @brief Entrée de la corbeille : fichier supprimé avec son chemin d'origine.
///
/// Utilise une unique représentation sérialisée [toMap] / [fromMap].
/// Le champ `isDirectory` est stocké en entier (0/1) pour SQLite ;
/// il est converti en booléen à la désérialisation.
class TrashItem {
  final String   trashedPath;    // Chemin dans la corbeille
  final String   originalPath;   // Chemin d'origine
  final DateTime deletedAt;
  final bool     isDirectory;
  final int      size;

  const TrashItem({
    required this.trashedPath,
    required this.originalPath,
    required this.deletedAt,
    required this.isDirectory,
    required this.size,
  });

  /// Élément présent dans la corbeille mais absent de son index (index
  /// perdu ou corrompu) : son emplacement d'origine est inconnu.
  bool get isOrphan => originalPath.isEmpty;

  /// Nom affiché : le nom d'origine, ou le nom interne pour un orphelin.
  String get name => p.basename(isOrphan ? trashedPath : originalPath);

  // ── Sérialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    'trashedPath':  trashedPath,
    'originalPath': originalPath,
    'deletedAt':    deletedAt.toIso8601String(),
    'isDirectory':  isDirectory ? 1 : 0,
    'size':         size,
  };

  factory TrashItem.fromMap(Map<String, dynamic> map) => TrashItem(
    trashedPath:  map['trashedPath']  as String,
    originalPath: map['originalPath'] as String,
    deletedAt:    DateTime.parse(map['deletedAt'] as String),
    isDirectory:  (map['isDirectory'] is bool)
                      ? map['isDirectory'] as bool
                      : (map['isDirectory'] as int) == 1,
    size:         map['size'] as int,
  );

  @override
  String toString() => 'TrashItem($originalPath)';
}
