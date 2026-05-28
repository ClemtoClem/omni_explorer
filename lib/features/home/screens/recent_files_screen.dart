/// @file recent_files_screen.dart
/// @brief Liste des fichiers récemment ouverts ; tap pour rouvrir dans
/// l'écran adapté à la catégorie du fichier.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/constants/app_constants.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../image_viewer/screens/image_viewer_screen.dart';
import '../../media_player/providers/media_player_provider.dart';
import '../../media_player/screens/media_player_screen.dart';
import '../../pdf_viewer/screens/pdf_viewer_screen.dart';
import '../../text_editor/screens/unified_editor_screen.dart';

class RecentFilesScreen extends StatelessWidget {
  const RecentFilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme    = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fichiers récents'),
        actions: [
          if (settings.recentFiles.isNotEmpty)
            TextButton(
              onPressed: settings.clearRecentFiles,
              child: const Text('Effacer'),
            ),
        ],
      ),
      body: settings.recentFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded,
                      size: 64,
                      color: theme.iconTheme.color?.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('Aucun fichier récent',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.textTheme.bodySmall?.color)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: settings.recentFiles.length,
              itemBuilder: (ctx, i) {
                final path = settings.recentFiles[i];
                final name = path.split('/').last.split(r'\').last;
                final cat  = FileUtils.categoryOfPath(path);
                return ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: FileUtils.colorOf(cat).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      FileUtils.iconOf(cat, path: path),
                      color: FileUtils.colorOf(cat),
                      size: 20,
                    ),
                  ),
                  title:
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                  onTap: () => _openFile(ctx, path, cat),
                );
              },
            ),
    );
  }

  void _openFile(BuildContext ctx, String path, FileCategory cat) {
    switch (cat) {
      case FileCategory.audio:
      case FileCategory.video:
        ctx.read<MediaPlayerProvider>().openMedia([path]);
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => const MediaPlayerScreen()));
        break;
      case FileCategory.image:
        Navigator.push(ctx, MaterialPageRoute(
            builder: (_) =>
                ImageViewerScreen(imagePath: path, allImages: [path])));
        break;
      case FileCategory.pdf:
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => PdfViewerScreen(filePaths: [path])));
        break;
      case FileCategory.binary:
      case FileCategory.markdown:
      default:
        Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => UnifiedEditorScreen(filePaths: [path])));
        break;
    }
  }
}
