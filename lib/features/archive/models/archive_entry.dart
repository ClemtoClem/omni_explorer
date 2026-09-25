import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

// ── Format de l'archive ───────────────────────────────────────────────────────

enum ArchiveType {
  zip,
  jar,    // ZIP-based : .jar, .war, .ear, .apk
  tar,
  tarGz,
  tarBz2,
  tarXz,
  gz,
  bz2,
  xz,
  sevenZip,
  rar,
  unknown,
}

extension ArchiveTypeExt on ArchiveType {
  String get label {
    switch (this) {
      case ArchiveType.zip:     return 'ZIP';
      case ArchiveType.jar:     return 'JAR';
      case ArchiveType.tar:     return 'TAR';
      case ArchiveType.tarGz:   return 'TAR.GZ';
      case ArchiveType.tarBz2:  return 'TAR.BZ2';
      case ArchiveType.tarXz:   return 'TAR.XZ';
      case ArchiveType.gz:      return 'GZ';
      case ArchiveType.bz2:     return 'BZ2';
      case ArchiveType.xz:      return 'XZ';
      case ArchiveType.sevenZip:return '7Z';
      case ArchiveType.rar:     return 'RAR';
      case ArchiveType.unknown: return '?';
    }
  }

  /// Pris en charge nativement par le package Dart `archive`.
  bool get isDartNative =>
      this != ArchiveType.sevenZip && this != ArchiveType.rar;

  /// Permet d'ajouter / supprimer des entrées sans recréer de zéro.
  bool get supportsInPlaceEdit =>
      this == ArchiveType.zip || this == ArchiveType.jar;

  /// Prend en charge un mot de passe.
  bool get supportsPassword =>
      this == ArchiveType.zip || this == ArchiveType.sevenZip ||
      this == ArchiveType.rar || this == ArchiveType.jar;

  IconData get icon {
    switch (this) {
      case ArchiveType.zip:      return MdiIcons.zipBox;
      case ArchiveType.jar:      return MdiIcons.languageJava;
      case ArchiveType.tar:      return MdiIcons.packageVariantClosed;
      case ArchiveType.tarGz:
      case ArchiveType.tarBz2:
      case ArchiveType.tarXz:   return MdiIcons.packageVariantClosedCheck;
      case ArchiveType.gz:
      case ArchiveType.bz2:
      case ArchiveType.xz:      return MdiIcons.archiveArrowDownOutline;
      case ArchiveType.sevenZip:return MdiIcons.archiveArrowDown;
      case ArchiveType.rar:     return MdiIcons.zipBoxOutline;
      case ArchiveType.unknown: return MdiIcons.fileOutline;
    }
  }

  Color get color {
    switch (this) {
      case ArchiveType.zip:      return const Color(0xFFFF9800);
      case ArchiveType.jar:      return const Color(0xFFF44336);
      case ArchiveType.tar:      return const Color(0xFF8D6E63);
      case ArchiveType.tarGz:
      case ArchiveType.tarBz2:
      case ArchiveType.tarXz:   return const Color(0xFFFF8F00);
      case ArchiveType.gz:
      case ArchiveType.bz2:
      case ArchiveType.xz:      return const Color(0xFF4CAF50);
      case ArchiveType.sevenZip:return const Color(0xFF2196F3);
      case ArchiveType.rar:     return const Color(0xFF9C27B0);
      case ArchiveType.unknown: return const Color(0xFF607D8B);
    }
  }
}

// ── Entrée dans l'archive ─────────────────────────────────────────────────────

class ArchiveEntryInfo {
  final String name;
  final String fullPath;
  final int size;
  final int compressedSize; // 0 si inconnu
  final DateTime? modified;
  final bool isDirectory;

  const ArchiveEntryInfo({
    required this.name,
    required this.fullPath,
    required this.size,
    required this.compressedSize,
    this.modified,
    required this.isDirectory,
  });

  String get ext {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  /// Chemin du répertoire parent à l'intérieur de l'archive.
  String get parentPath {
    final n = _normalized;
    final slash = n.lastIndexOf('/');
    return slash >= 0 ? n.substring(0, slash) : '';
  }

  /// Profondeur dans l'arborescence (0 = racine).
  int get depth => _normalized.split('/').length - 1;

  /// Pourcentage de compression (0..1), négatif = inconnu.
  double get compressionRatio =>
      (compressedSize > 0 && size > 0) ? 1.0 - compressedSize / size : -1;

  String get _normalized =>
      fullPath.endsWith('/') ? fullPath.substring(0, fullPath.length - 1) : fullPath;
}

// ── Exception d'archive ───────────────────────────────────────────────────────

/// Erreur d'opération sur une archive (listing, extraction, création…).
/// Distincte de [ArchiveException] du package `archive` (erreur de format bas-niveau).
class ArchiveOpException implements Exception {
  final String message;
  final bool isPasswordRequired;

  const ArchiveOpException(this.message, {this.isPasswordRequired = false});

  @override
  String toString() => message;
}

/// Bilan d'une extraction.
class ExtractResult {
  /// Nombre de fichiers écrits.
  final int filesWritten;

  /// Entrées « lien symbolique » ignorées : elles pourraient pointer hors du
  /// dossier de destination, elles ne sont donc jamais recréées.
  final int skippedLinks;

  const ExtractResult({this.filesWritten = 0, this.skippedLinks = 0});
}
