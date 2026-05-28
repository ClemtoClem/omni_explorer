/// @file file_list_item.dart
/// @brief Item de la vue liste de l'explorateur de fichiers.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../features/archive/screens/archive_screen.dart';
import '../../../features/archive/services/archive_service.dart';
import '../../../features/media_player/providers/media_player_provider.dart';
import '../../../features/video_editor/screens/video_editor_screen.dart';
import '../providers/file_explorer_provider.dart';
import 'file_properties_dialog.dart';

/// @class FileListItem
/// @brief Ligne de l'explorateur en vue liste.
class FileListItem extends StatelessWidget {
  final FileItem    item;
  final bool        isSelected;
  final bool        selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;

  const FileListItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final color  = FileUtils.colorOf(item.category);
    final icon   = FileUtils.iconOf(item.category, path: item.path);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppColors.accent.withValues(alpha:0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // ── Checkbox / Icône ────────────────────────────────────────────
            if (selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: onSelect,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: AppColors.accent, size: 22, key: const ValueKey(true))
                        : Icon(Icons.radio_button_unchecked_rounded,
                            color: theme.iconTheme.color, size: 22, key: const ValueKey(false)),
                  ),
                ),
              ),
            // ── Icône du fichier ────────────────────────────────────────────
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            // ── Nom + infos ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: item.isHidden
                          ? theme.textTheme.bodySmall?.color
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isDirectory
                        ? FileUtils.formatDate(item.modified)
                        : '${FileUtils.formatSize(item.size)}  •  ${FileUtils.formatDate(item.modified)}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // ── Menu contextuel ─────────────────────────────────────────────
            if (!selectMode)
              Theme(
                data: Theme.of(context).copyWith(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _ContextMenuBtn(item: item),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class _ContextMenuBtn
/// @brief Bouton "..." avec menu contextuel pour un fichier.
class _ContextMenuBtn extends StatelessWidget {
  final FileItem item;
  const _ContextMenuBtn({required this.item});

  bool get _isArchive => item.category == FileCategory.archive;
  bool get _isMedia =>
      item.category == FileCategory.audio ||
      item.category == FileCategory.video;
  bool get _isVideo => item.category == FileCategory.video;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ContextAction>(
      icon: Icon(Icons.more_vert_rounded,
          size: 20, color: Theme.of(context).iconTheme.color),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tooltip: 'Options',
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _ContextAction.open,
            child: _MenuItem(Icons.open_in_new_rounded, 'Ouvrir')),
        // ── Actions spécifiques aux archives ───────────────────────────────
        if (_isArchive) ...[
          const PopupMenuItem(
            value: _ContextAction.extractHere,
            child: _MenuItem(Icons.download_rounded, 'Extraire ici'),
          ),
          const PopupMenuItem(
            value: _ContextAction.extractTo,
            child: _MenuItem(Icons.folder_zip_outlined, 'Extraire vers…'),
          ),
          const PopupMenuDivider(),
        ],
        // ── Action spécifique aux médias ────────────────────────────────────
        if (_isMedia) ...[
          const PopupMenuItem(
            value: _ContextAction.addToPlaylist,
            child: _MenuItem(Icons.playlist_add_rounded, 'Ajouter à la playlist'),
          ),
          if (_isVideo)
            const PopupMenuItem(
              value: _ContextAction.editVideo,
              child: _MenuItem(Icons.movie_filter_rounded, 'Éditer la vidéo'),
            ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: _ContextAction.rename,
            child: _MenuItem(Icons.drive_file_rename_outline_rounded, 'Renommer')),
        const PopupMenuItem(value: _ContextAction.copy,
            child: _MenuItem(Icons.copy_rounded, 'Copier')),
        const PopupMenuItem(value: _ContextAction.cut,
            child: _MenuItem(Icons.cut_rounded, 'Couper')),
        const PopupMenuItem(
          value: _ContextAction.compress,
          child: _MenuItem(Icons.compress_rounded, 'Compresser…'),
        ),
        const PopupMenuItem(value: _ContextAction.shortcut,
            child: _MenuItem(Icons.bookmark_add_outlined, 'Ajouter aux raccourcis')),
        const PopupMenuItem(value: _ContextAction.properties,
            child: _MenuItem(Icons.info_outline_rounded, 'Propriétés…')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: _ContextAction.trash,
            child: _MenuItem(Icons.delete_outline_rounded, 'Mettre à la corbeille',
                color: AppColors.error)),
      ],
    );
  }

  void _handleAction(BuildContext ctx, _ContextAction action) {
    switch (action) {
      case _ContextAction.open:
        Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => ArchiveScreen(archivePath: item.path)));
        break;

      case _ContextAction.extractHere:
        _extractTo(ctx, p.dirname(item.path));
        break;

      case _ContextAction.extractTo:
        _showExtractToDialog(ctx);
        break;

      case _ContextAction.compress:
        _showCompressDialog(ctx);
        break;

      case _ContextAction.addToPlaylist:
        ctx.read<MediaPlayerProvider>().addPathToPlaylist(item.path);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('« ${item.name} » ajouté à la playlist')));
        break;

      case _ContextAction.editVideo:
        Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => VideoEditorScreen(file: File(item.path)),
        ));
        break;

      case _ContextAction.rename:
        _showRenameDialog(ctx);
        break;

      case _ContextAction.shortcut:
        ctx.read<SettingsService>().addShortcut(item.name, item.path);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Raccourci créé pour « ${item.name} »')));
        break;

      case _ContextAction.trash:
        ctx.read<TrashService>().moveToTrash(item.path);
        ctx.read<FileExplorerProvider>().refresh();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('« ${item.name} » déplacé vers la corbeille')));
        break;

      case _ContextAction.copy:
        ctx.read<FileExplorerProvider>().copyToClipboard([item.path]);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('« ${item.name} » copié — collez-le ailleurs')));
        break;

      case _ContextAction.cut:
        ctx.read<FileExplorerProvider>().cutToClipboard([item.path]);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('« ${item.name} » coupé — collez-le ailleurs')));
        break;

      case _ContextAction.properties:
        showFilePropertiesDialog(ctx, item);
        break;
    }
  }

  Future<void> _extractTo(BuildContext ctx, String dest) async {
    try {
      await ArchiveService.extractAll(item.path, dest);
      ctx.read<FileExplorerProvider>().refresh();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Extrait dans $dest')));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Erreur : $e'),
              backgroundColor: AppColors.error));
      }
    }
  }

  void _showExtractToDialog(BuildContext ctx) {
    final ctrl = TextEditingController(text: p.dirname(item.path));
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Extraire vers…'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/chemin/destination'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final dest = ctrl.text.trim();
              if (dest.isNotEmpty) {
                Navigator.pop(ctx);
                _extractTo(ctx, dest);
              }
            },
            child: const Text('Extraire'),
          ),
        ],
      ),
    );
  }

  void _showCompressDialog(BuildContext ctx) {
    final currentDir = p.dirname(item.path);
    showCompressDialog(ctx,
      sourcePaths: [item.path],
      destDir: currentDir,
    ).then((created) {
      if (created) ctx.read<FileExplorerProvider>().refresh();
    });
  }

  void _showRenameDialog(BuildContext ctx) {
    final ctrl = TextEditingController(text: item.name);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
  }
}

enum _ContextAction {
  open, rename, copy, cut, trash, shortcut,
  extractHere, extractTo, compress, addToPlaylist, properties, editVideo,
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _MenuItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).iconTheme.color;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: c)),
      ],
    );
  }
}
