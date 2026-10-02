/// @file file_grid_item.dart
/// @brief Item de la vue grille de l'explorateur de fichiers.

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/file_item.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';

/// @class FileGridItem
/// @brief Tuile pour la vue grille de l'explorateur.
class FileGridItem extends StatelessWidget {
  final FileItem item;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelect;

  const FileGridItem({
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
    final theme = Theme.of(context);
    final color = FileUtils.colorOf(item.category);
    final icon = FileUtils.iconOf(item.category, path: item.path);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : (theme.brightness == Brightness.dark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder),
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Thumbnail ou icône ────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildThumbnail(color, icon),
                  ),
                ),
                // ── Nom ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            // ── Indicateur de sélection ────────────────────────────────────
            if (selectMode)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onSelect,
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color:
                        isSelected ? AppColors.accent : theme.iconTheme.color,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(Color color, IconData icon) {
    // Pour les images, afficher une miniature
    if (item.category == FileCategory.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(icon, color: color, size: 40),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 36),
    );
  }
}
