/// @file filter_bar.dart
/// @brief Barre de filtres pour l'explorateur de fichiers : champ de
/// recherche, chips de catégorie multi-sélectionnables, extensions, option
/// « sous-dossiers » et état de la recherche.

import 'package:flutter/material.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_filter.dart';

class FilterBar extends StatefulWidget {
  final String query;

  /// Catégories actuellement actives. Vide = aucun filtre catégorie.
  final Set<FileCategory> selectedCategories;

  /// Extensions actives (sans point). Vide = toutes.
  final Set<String> extensions;

  /// Recherche dans les sous-dossiers.
  final bool recursive;

  /// Recherche récursive en cours / plafond de résultats atteint.
  final bool searching;
  final bool truncated;

  /// Nombre d'éléments affichés (affiché pendant une recherche récursive).
  final int resultCount;

  final ValueChanged<String> onQueryChanged;

  /// Bascule une catégorie (ajout si absente, retrait sinon).
  final ValueChanged<FileCategory> onCategoryToggled;
  final ValueChanged<Set<String>> onExtensionsChanged;
  final ValueChanged<bool> onRecursiveChanged;
  final VoidCallback onClear;

  const FilterBar({
    super.key,
    required this.query,
    required this.selectedCategories,
    required this.onQueryChanged,
    required this.onCategoryToggled,
    required this.onClear,
    this.extensions = const {},
    this.recursive = false,
    this.searching = false,
    this.truncated = false,
    this.resultCount = 0,
    required this.onExtensionsChanged,
    required this.onRecursiveChanged,
  });

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _query =
      TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(FilterBar old) {
    super.didUpdateWidget(old);
    // Filtre changé ailleurs (raccourci, « effacer ») : refléter la valeur.
    if (widget.query != _query.text) _query.text = widget.query;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _editExtensions() async {
    final ctrl = TextEditingController(
        text: widget.extensions.map((e) => '.$e').join(' '));
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Extensions'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ex. pdf docx odt',
            helperText: 'Séparées par des espaces ou des virgules',
          ),
          onSubmitted: (v) =>
              Navigator.pop(dCtx, FileFilter.parseExtensions(v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dCtx, FileFilter.parseExtensions(ctrl.text)),
              child: const Text('Appliquer')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) widget.onExtensionsChanged(result);
  }

  Widget _chip(String label,
      {required bool selected,
      required VoidCallback onTap,
      IconData? icon,
      VoidCallback? onDeleted}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: icon == null ? null : Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => onTap(),
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close_rounded, size: 14),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        selectedColor: AppColors.accent.withValues(alpha: 0.2),
        checkmarkColor: AppColors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasActiveFilter = w.query.isNotEmpty ||
        w.selectedCategories.isNotEmpty ||
        w.extensions.isNotEmpty ||
        w.recursive;
    final theme = Theme.of(context);
    final searchActive = w.recursive &&
        (w.query.trim().isNotEmpty ||
            w.selectedCategories.isNotEmpty ||
            w.extensions.isNotEmpty);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Champ de recherche ────────────────────────────────────────────
          TextField(
            controller: _query,
            onChanged: w.onQueryChanged,
            decoration: InputDecoration(
              hintText: w.recursive
                  ? 'Rechercher ici et dans les sous-dossiers…'
                  : 'Rechercher dans ce répertoire...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: hasActiveFilter
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Effacer les filtres',
                      onPressed: w.onClear,
                    )
                  : null,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          // ── Options et chips de catégorie (multi-sélection) ───────────────
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip('Sous-dossiers',
                    icon: Icons.account_tree_outlined,
                    selected: w.recursive,
                    onTap: () => w.onRecursiveChanged(!w.recursive)),
                _chip(
                  w.extensions.isEmpty
                      ? 'Extensions…'
                      : w.extensions.map((e) => '.$e').join(' '),
                  icon: Icons.label_outline_rounded,
                  selected: w.extensions.isNotEmpty,
                  onTap: _editExtensions,
                  onDeleted: w.extensions.isEmpty
                      ? null
                      : () => w.onExtensionsChanged(const {}),
                ),
                for (final e in FileFilter.categoryLabels.entries)
                  _chip(e.value,
                      selected: w.selectedCategories.contains(e.key),
                      onTap: () => w.onCategoryToggled(e.key)),
              ],
            ),
          ),
          if (searchActive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (w.searching) ...[
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      w.searching
                          ? 'Recherche… ${w.resultCount} résultat(s)'
                          : w.truncated
                              ? '${w.resultCount} résultats affichés (limite '
                                  'atteinte : précisez la recherche)'
                              : '${w.resultCount} résultat(s) dans les '
                                  'sous-dossiers',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
