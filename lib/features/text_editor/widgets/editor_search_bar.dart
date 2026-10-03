/// @file editor_search_bar.dart
/// @brief Barre de recherche / remplacement de l'éditeur : casse, mot entier,
/// expression régulière, compteur, occurrence précédente / suivante.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../services/text_search.dart';

class EditorSearchBar extends StatefulWidget {
  /// Requête initiale (réouverture de la barre, texte sélectionné).
  final TextSearchQuery initialQuery;

  /// Occurrence courante (0-indexée, -1 : aucune) et nombre d'occurrences.
  final int matchIndex;
  final int matchCount;

  /// Affiche la ligne « Remplacer » à l'ouverture.
  final bool initialReplace;

  /// Faux pour un onglet en lecture seule : pas de remplacement.
  final bool canReplace;

  final ValueChanged<TextSearchQuery> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<String> onReplace;
  final ValueChanged<String> onReplaceAll;
  final VoidCallback onClose;

  const EditorSearchBar({
    super.key,
    this.initialQuery = const TextSearchQuery(''),
    required this.matchIndex,
    required this.matchCount,
    this.initialReplace = false,
    this.canReplace = true,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onClose,
  });

  @override
  State<EditorSearchBar> createState() => EditorSearchBarState();
}

class EditorSearchBarState extends State<EditorSearchBar> {
  late final TextEditingController _find;
  final _replace = TextEditingController();
  final _findFocus = FocusNode();
  late TextSearchQuery _query;
  late bool _showReplace;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _find = TextEditingController(text: _query.pattern)
      ..selection =
          TextSelection(baseOffset: 0, extentOffset: _query.pattern.length);
    _showReplace = widget.initialReplace && widget.canReplace;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  /// Donne le focus au champ de recherche (Ctrl+F alors que la barre est
  /// déjà ouverte), avec éventuellement un nouveau motif.
  void focus({String? pattern, bool? replace}) {
    if (pattern != null && pattern.isNotEmpty) {
      _find.text = pattern;
      _update(_query.copyWith(pattern: pattern));
    }
    if (replace != null && widget.canReplace) {
      setState(() => _showReplace = replace);
    }
    _find.selection =
        TextSelection(baseOffset: 0, extentOffset: _find.text.length);
    _findFocus.requestFocus();
  }

  void _update(TextSearchQuery q) {
    if (q == _query) return;
    setState(() => _query = q);
    widget.onQueryChanged(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _query.error;
    final count = widget.matchCount;
    final counter = _query.isEmpty
        ? ''
        : count == 0
            ? 'Aucun'
            : '${widget.matchIndex + 1}/${count >= TextSearch.maxMatches ? '${TextSearch.maxMatches}+' : count}';

    return Material(
      color: theme.colorScheme.surface,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true):
              widget.onPrevious,
          const SingleActivator(LogicalKeyboardKey.f3): widget.onNext,
          const SingleActivator(LogicalKeyboardKey.f3, shift: true):
              widget.onPrevious,
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (widget.canReplace)
                    _IconBtn(
                      icon: _showReplace
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      tip: _showReplace
                          ? 'Masquer le remplacement'
                          : 'Remplacer…',
                      onTap: () => setState(() => _showReplace = !_showReplace),
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('editor-search-find'),
                      controller: _find,
                      focusNode: _findFocus,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Rechercher',
                        isDense: true,
                        errorText: error,
                        errorMaxLines: 2,
                        suffixText: counter,
                        suffixStyle: theme.textTheme.bodySmall,
                      ),
                      onChanged: (v) => _update(_query.copyWith(pattern: v)),
                      onSubmitted: (_) {
                        widget.onNext();
                        _findFocus.requestFocus();
                      },
                    ),
                  ),
                  _Toggle(
                    label: 'Aa',
                    tip: 'Respecter la casse',
                    value: _query.caseSensitive,
                    onTap: () => _update(
                        _query.copyWith(caseSensitive: !_query.caseSensitive)),
                  ),
                  _Toggle(
                    label: 'ab',
                    underline: true,
                    tip: 'Mot entier',
                    value: _query.wholeWord,
                    onTap: () =>
                        _update(_query.copyWith(wholeWord: !_query.wholeWord)),
                  ),
                  _Toggle(
                    label: '.*',
                    tip: 'Expression régulière',
                    value: _query.regex,
                    onTap: () => _update(_query.copyWith(regex: !_query.regex)),
                  ),
                  _IconBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tip: 'Précédent (Maj+Entrée)',
                    onTap: count > 0 ? widget.onPrevious : null,
                  ),
                  _IconBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tip: 'Suivant (Entrée)',
                    onTap: count > 0 ? widget.onNext : null,
                  ),
                  _IconBtn(
                    icon: Icons.close_rounded,
                    tip: 'Fermer (Échap)',
                    onTap: widget.onClose,
                  ),
                ],
              ),
              if (_showReplace && widget.canReplace)
                Row(
                  children: [
                    const SizedBox(width: 32),
                    Expanded(
                      child: TextField(
                        key: const Key('editor-search-replace'),
                        controller: _replace,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: _query.regex
                              ? r'Remplacer ($1 : groupe)'
                              : 'Remplacer',
                          isDense: true,
                        ),
                        onSubmitted: (_) => widget.onReplace(_replace.text),
                      ),
                    ),
                    TextButton(
                      onPressed: count > 0
                          ? () => widget.onReplace(_replace.text)
                          : null,
                      child: const Text('Remplacer'),
                    ),
                    TextButton(
                      onPressed: count > 0
                          ? () => widget.onReplaceAll(_replace.text)
                          : null,
                      child: const Text('Tout'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  const _IconBtn({required this.icon, required this.tip, this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      );
}

/// Option de recherche activable (Aa, mot entier, .*).
class _Toggle extends StatelessWidget {
  final String label;
  final String tip;
  final bool value;
  final bool underline;
  final VoidCallback onTap;

  const _Toggle({
    required this.label,
    required this.tip,
    required this.value,
    required this.onTap,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = value ? AppColors.accent : null;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 30,
          height: 28,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: value ? AppColors.accent.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: value ? AppColors.accent : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}
