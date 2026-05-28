/// @file media_playlist_panel.dart
/// @brief Panneau de playlist réordonnable (style VLC).

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../app/theme/app_theme.dart';

/// Liste réordonnable des pistes de la playlist courante.
///
/// Glisser-déposer pour réordonner, croix pour retirer, tap pour lire.
class MediaPlaylistPanel extends StatelessWidget {
  final List<String> paths;
  final int currentIndex;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;
  final void Function(int index) onSelect;

  const MediaPlaylistPanel({
    super.key,
    required this.paths,
    required this.currentIndex,
    required this.onReorder,
    required this.onRemove,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? AppColors.darkSubtext : AppColors.lightSubtext;

    return Container(
      color: isDark ? AppColors.darkSurface2 : AppColors.lightSurface2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text('Playlist (${paths.length})',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text('Maintenir pour réordonner',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: subColor)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              itemCount: paths.length,
              onReorderItem: onReorder,
              itemBuilder: (ctx, idx) {
                final isActive = idx == currentIndex;
                final name = p.basenameWithoutExtension(paths[idx]);
                return ListTile(
                  key: ValueKey('${paths[idx]}#$idx'),
                  selected: isActive,
                  selectedColor: AppColors.accent,
                  selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
                  leading: isActive
                      ? Icon(Icons.volume_up_rounded,
                          color: AppColors.accent, size: 20)
                      : Text('${idx + 1}',
                          style: Theme.of(ctx).textTheme.bodySmall),
                  title: Text(name,
                      style: TextStyle(
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => onRemove(idx),
                  ),
                  onTap: () => onSelect(idx),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
