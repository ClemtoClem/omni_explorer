/// @file filter_bar.dart
/// @brief Barre de filtres pour l'explorateur de fichiers : champ de
/// recherche + chips de catégorie multi-sélectionnables.

import 'package:flutter/material.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';

class FilterBar extends StatelessWidget {
  final String query;
  /// Catégories actuellement actives. Vide = aucun filtre catégorie.
  final Set<FileCategory> selectedCategories;
  final ValueChanged<String> onQueryChanged;
  /// Bascule une catégorie (ajout si absente, retrait sinon).
  final ValueChanged<FileCategory> onCategoryToggled;
  final VoidCallback onClear;

  const FilterBar({
    super.key,
    required this.query,
    required this.selectedCategories,
    required this.onQueryChanged,
    required this.onCategoryToggled,
    required this.onClear,
  });

  static const _categories = <FileCategory, String>{
    FileCategory.folder:  'Dossiers',
    FileCategory.audio:   'Audio',
    FileCategory.video:   'Vidéo',
    FileCategory.image:   'Images',
    FileCategory.pdf:     'PDF',
    FileCategory.code:    'Code',
    FileCategory.text:    'Texte',
    FileCategory.archive: 'Archives',
  };

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = query.isNotEmpty || selectedCategories.isNotEmpty;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Champ de recherche ────────────────────────────────────────────
          TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Rechercher dans ce répertoire...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: hasActiveFilter
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Effacer les filtres',
                      onPressed: onClear,
                    )
                  : null,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          // ── Chips de catégorie (multi-sélection) ──────────────────────────
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categories.entries.map((e) {
                final isSelected = selectedCategories.contains(e.key);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (_) => onCategoryToggled(e.key),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.accent,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
