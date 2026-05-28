
/// @file file_utils.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart' as p;
import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../../features/archive/models/archive_entry.dart';
import '../../features/archive/services/archive_service.dart';

class FileUtils {
  FileUtils._();
  static FileCategory categoryOfPath(String path) {
    if (!path.contains('.')) return FileCategory.folder;
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (AppConstants.audioExtensions.contains(ext))    return FileCategory.audio;
    if (AppConstants.videoExtensions.contains(ext))    return FileCategory.video;
    if (AppConstants.imageExtensions.contains(ext))    return FileCategory.image;
    if (AppConstants.pdfExtensions.contains(ext))      return FileCategory.pdf;
    if (AppConstants.markdownExtensions.contains(ext)) return FileCategory.markdown;
    if (AppConstants.codeExtensions.contains(ext))     return FileCategory.code;
    if (AppConstants.textExtensions.contains(ext))     return FileCategory.text;
    if (AppConstants.archiveExtensions.contains(ext))  return FileCategory.archive;
    if (AppConstants.binaryExtensions.contains(ext))   return FileCategory.binary;
    return FileCategory.unknown;
  }
  static FileCategory categoryOf(FileSystemEntity entity) {
    if (entity is Directory) return FileCategory.folder;
    return categoryOfPath(entity.path);
  }
  static IconData iconOf(FileCategory cat, {String? path}) {
    switch (cat) {
      case FileCategory.folder:   return Icons.folder_rounded;
      case FileCategory.audio:    return MdiIcons.musicNote;
      case FileCategory.video:    return MdiIcons.filmstrip;
      case FileCategory.image:    return Icons.image_outlined;
      case FileCategory.pdf:      return MdiIcons.filePdfBox;
      case FileCategory.markdown: return MdiIcons.languageMarkdown;
      case FileCategory.code:     return _codeIcon(path != null ? p.extension(path).toLowerCase().replaceFirst('.', '') : '');
      case FileCategory.text:     return MdiIcons.fileDocumentOutline;
      case FileCategory.archive:
        return path != null
            ? ArchiveService.detectType(path).icon
            : MdiIcons.zipBox;
      case FileCategory.binary:   return MdiIcons.hexadecimal;
      case FileCategory.unknown:  return MdiIcons.fileOutline;
    }
  }
  static IconData _codeIcon(String ext) {
    switch (ext) {
      case 'dart':   return MdiIcons.codeBraces;
      case 'py':     return MdiIcons.languagePython;
      case 'js': case 'jsx': return MdiIcons.languageJavascript;
      case 'ts': case 'tsx': return MdiIcons.languageTypescript;
      case 'html': case 'htm': return MdiIcons.languageHtml5;
      case 'css': case 'scss': return MdiIcons.languageCss3;
      case 'json':   return MdiIcons.codeJson;
      case 'java':   return MdiIcons.languageJava;
      case 'kt':     return MdiIcons.languageKotlin;
      case 'c': case 'cpp': case 'h': return MdiIcons.languageC;
      case 'cs':     return MdiIcons.languageCsharp;
      case 'go':     return MdiIcons.languageGo;
      case 'rs':     return MdiIcons.languageRust;
      case 'php':    return MdiIcons.languagePhp;
      case 'rb':     return MdiIcons.languageRuby;
      case 'swift':  return MdiIcons.languageSwift;
      case 'sh': case 'bash': return Icons.terminal_rounded;
      case 'xml':    return MdiIcons.xml;
      case 'sql':    return MdiIcons.database;
      default:       return MdiIcons.codeTagsCheck;
    }
  }
  static Color colorOf(FileCategory cat) {
    switch (cat) {
      case FileCategory.folder:   return AppColors.colorFolder;
      case FileCategory.audio:    return AppColors.colorAudio;
      case FileCategory.video:    return AppColors.colorVideo;
      case FileCategory.image:    return AppColors.colorImage;
      case FileCategory.pdf:      return AppColors.colorPdf;
      case FileCategory.markdown: return AppColors.colorDoc;
      case FileCategory.code:     return AppColors.colorCode;
      case FileCategory.text:     return AppColors.colorText;
      case FileCategory.archive:  return AppColors.colorArchive; // couleur par défaut; l'icône est différenciée par format
      case FileCategory.binary:   return AppColors.colorUnknown;
      case FileCategory.unknown:  return AppColors.colorUnknown;
    }
  }
  static String formatSize(int bytes) {
    if (bytes < 1024)       return '$bytes B';
    if (bytes < 1048576)    return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
  static String formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "Aujourd'hui ${DateFormat('HH:mm').format(dt)}";
    }
    if (now.difference(dt).inDays < 7) {
      return DateFormat('EEE HH:mm', 'fr_FR').format(dt);
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
  static String nameOf(String path) => p.basename(path);
  static String extOf(String path)  => p.extension(path).toLowerCase().replaceFirst('.','');
  static bool isHidden(String path) => p.basename(path).startsWith('.');
  static bool isEditable(String path) {
    final ext = extOf(path);
    return AppConstants.codeExtensions.contains(ext) ||
           AppConstants.textExtensions.contains(ext) ||
           AppConstants.markdownExtensions.contains(ext);
  }

  /// Retourne un chemin unique en ajoutant un suffixe `(n)` si le fichier existe.
  static String resolveNameConflict(String path) {
    if (!FileSystemEntity.isFileSync(path) && !FileSystemEntity.isDirectorySync(path)) {
      return path;
    }
    final ext  = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    final dir  = p.dirname(path);
    int counter = 1;
    while (true) {
      final candidate = p.join(dir, '$base ($counter)$ext');
      if (!FileSystemEntity.isFileSync(candidate) &&
          !FileSystemEntity.isDirectorySync(candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  /// Détecte la [FileCategory] d'un fichier à partir de son extension.
  static FileCategory detectType(String ext) => categoryOfPath('.$ext');

}
