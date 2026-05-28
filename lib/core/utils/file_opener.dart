/// @file file_opener.dart
/// @brief Point d'entrée unique pour ouvrir un fichier selon sa catégorie.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../../features/archive/screens/archive_screen.dart';
import '../../features/image_viewer/screens/image_viewer_screen.dart';
import '../../features/media_player/providers/media_player_provider.dart';
import '../../features/media_player/screens/media_player_screen.dart';
import '../../features/pdf_viewer/screens/pdf_viewer_screen.dart';
import '../../features/text_editor/screens/unified_editor_screen.dart';
import '../models/file_item.dart';

class FileOpener {
  FileOpener._();

  /// Ouvre [item] dans l'écran approprié à sa catégorie.
  ///
  /// Pour les formats non reconnus ([FileCategory.unknown], [FileCategory.archive])
  /// un panneau invite l'utilisateur à choisir comment interpréter le fichier.
  static void open(
    BuildContext context,
    FileItem item, {
    List<String>? allImages,
    List<String>? playlist,
  }) {
    if (item.isDirectory) return;

    switch (item.category) {
      case FileCategory.audio:
      case FileCategory.video:
        final list = playlist ?? [item.path];
        context.read<MediaPlayerProvider>().openMedia(
          list,
          index: list.indexOf(item.path).clamp(0, list.length - 1),
        );
        _push(context, const MediaPlayerScreen());

      case FileCategory.image:
        _push(context, ImageViewerScreen(
          imagePath: item.path,
          allImages: allImages ?? [item.path],
        ));

      case FileCategory.pdf:
        _push(context, PdfViewerScreen(filePaths: [item.path]));

      case FileCategory.markdown:
      case FileCategory.text:
      case FileCategory.code:
      case FileCategory.binary:
        _push(context, UnifiedEditorScreen(filePaths: [item.path]));

      case FileCategory.archive:
        _push(context, ArchiveScreen(archivePath: item.path));

      case FileCategory.unknown:
      case FileCategory.folder:
        _showFormatPicker(context, item.path);
    }
  }

  /// Ouvre plusieurs fichiers dans l'écran approprié selon leurs catégories.
  /// Groupe les fichiers par catégorie et ouvre un écran pour chaque groupe.
  static void openMany(
    BuildContext context,
    List<FileItem> items,
  ) {
    final files = items.where((i) => !i.isDirectory).toList();
    if (files.isEmpty) return;

    // Grouper par catégorie
    final byCategory = <FileCategory, List<String>>{};
    for (final item in files) {
      byCategory.putIfAbsent(item.category, () => []).add(item.path);
    }

    // Ouvrir un écran par catégorie
    for (final MapEntry(:key, :value) in byCategory.entries) {
      switch (key) {
        case FileCategory.audio:
        case FileCategory.video:
          context.read<MediaPlayerProvider>().openMedia(value);
          _push(context, const MediaPlayerScreen());
          break;

        case FileCategory.image:
          _push(context, ImageViewerScreen(
            imagePath: value[0],
            allImages: value,
          ));
          break;

        case FileCategory.pdf:
          _push(context, PdfViewerScreen(filePaths: value));
          break;

        case FileCategory.markdown:
        case FileCategory.text:
        case FileCategory.code:
        case FileCategory.binary:
          _push(context, UnifiedEditorScreen(filePaths: value));
          break;

        case FileCategory.archive:
          // Ouvrir chaque archive individuellement
          for (final path in value) {
            _push(context, ArchiveScreen(archivePath: path));
          }
          break;

        case FileCategory.unknown:
        case FileCategory.folder:
          if (value.isNotEmpty) {
            _showFormatPicker(context, value[0]);
          }
          break;
      }
    }
  }

  static bool canOpen(FileItem item) {
    if (item.isDirectory) return false;
    switch (item.category) {
      case FileCategory.audio:
      case FileCategory.video:
      case FileCategory.image:
      case FileCategory.pdf:
      case FileCategory.markdown:
      case FileCategory.code:
      case FileCategory.text:
      case FileCategory.binary:
      case FileCategory.archive:
        return true;
      default:
        return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// Panneau de sélection du format pour les fichiers non reconnus.
  static void _showFormatPicker(BuildContext context, String path) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FormatPickerSheet(path: path),
    );
  }
}

// ─── Feuille de sélection de format ──────────────────────────────────────────

class _FormatPickerSheet extends StatelessWidget {
  final String path;
  const _FormatPickerSheet({required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  color: AppColors.warning, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Format non reconnu',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cette application ne permet pas de lire ce format de fichier. '
            'Veuillez préciser le format de ce fichier.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          // Options
          _Option(
            icon: Icons.memory_rounded,
            color: AppColors.colorUnknown,
            label: 'Binaire (hex)',
            subtitle: 'Éditeur hexadécimal',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => UnifiedEditorScreen(filePaths: [path], forceHex: true)));
            },
          ),
          _Option(
            icon: Icons.text_snippet_outlined,
            color: AppColors.colorText,
            label: 'Texte',
            subtitle: 'Ouvrir comme fichier texte brut',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => UnifiedEditorScreen(filePaths: [path])));
            },
          ),
          _Option(
            icon: Icons.code_rounded,
            color: AppColors.colorCode,
            label: 'Code',
            subtitle: 'Éditeur avec coloration syntaxique',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => UnifiedEditorScreen(filePaths: [path])));
            },
          ),
          _Option(
            icon: Icons.article_outlined,
            color: AppColors.colorDoc,
            label: 'Markdown',
            subtitle: 'Visionneur Markdown',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => UnifiedEditorScreen(filePaths: [path])));
            },
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    );
  }
}
