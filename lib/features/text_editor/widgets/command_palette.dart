/// @file command_palette.dart
/// @brief Palette de commandes (Ctrl+Maj+P) et ouverture rapide de fichier
/// (Ctrl+P) : une liste filtrée par saisie approximative.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';

/// Entrée de la palette.
class PaletteItem {
  final String label;

  /// Texte secondaire (catégorie, dossier d'un fichier).
  final String? detail;
  final IconData? icon;

  /// Raccourci affiché à droite (« Ctrl+G »).
  final String? shortcut;

  /// Faux : affiché grisé, non sélectionnable (ex. « Sauvegarder » sans
  /// modification).
  final bool enabled;
  final VoidCallback run;

  const PaletteItem({
    required this.label,
    required this.run,
    this.detail,
    this.icon,
    this.shortcut,
    this.enabled = true,
  });
}

/// Score de [query] dans [text] (saisie approximative : lettres de la
/// requête dans l'ordre, pas forcément contiguës), ou `null` sans
/// correspondance. Plus le score est haut, meilleure est la correspondance :
/// lettres consécutives et débuts de mots favorisés.
int? paletteScore(String text, String query) {
  if (query.isEmpty) return 0;
  final t = text.toLowerCase(), q = query.toLowerCase();
  var score = 0, ti = 0, streak = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q[qi];
    if (c == ' ') continue;
    final found = t.indexOf(c, ti);
    if (found < 0) return null;
    final wordStart = found == 0 || ' /._-'.contains(t[found - 1]);
    streak = found == ti ? streak + 1 : 0;
    score += 1 + streak * 3 + (wordStart ? 5 : 0) - (found - ti).clamp(0, 5);
    ti = found + 1;
  }
  // Contient la requête telle quelle : nettement mieux.
  if (t.contains(q)) score += 20;
  return score;
}

/// Ouvre la palette ; l'entrée choisie est exécutée après la fermeture.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteItem> items,
  String hint = 'Commande…',
}) async {
  final picked = await showDialog<PaletteItem>(
    context: context,
    builder: (_) => CommandPalette(items: items, hint: hint),
  );
  picked?.run();
}

class CommandPalette extends StatefulWidget {
  final List<PaletteItem> items;
  final String hint;

  const CommandPalette({super.key, required this.items, this.hint = ''});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  List<PaletteItem> _shown = const [];
  int _selected = 0;

  static const _rowHeight = 48.0;
  static const _maxShown = 200;

  @override
  void initState() {
    super.initState();
    _filter('');
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final scored = <(PaletteItem, int)>[];
    for (final item in widget.items) {
      final s = paletteScore('${item.label} ${item.detail ?? ''}', q);
      if (s != null) scored.add((item, s));
    }
    // Tri stable : à score égal, l'ordre d'origine est conservé.
    if (q.isNotEmpty) {
      final indexed = scored.indexed.toList()
        ..sort((a, b) {
          final byScore = b.$2.$2.compareTo(a.$2.$2);
          return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
        });
      scored
        ..clear()
        ..addAll(indexed.map((e) => e.$2));
    }
    setState(() {
      _shown = scored.take(_maxShown).map((e) => e.$1).toList();
      _selected = _shown.indexWhere((i) => i.enabled);
      if (_selected < 0) _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _move(int delta) {
    if (_shown.isEmpty) return;
    var i = _selected;
    for (var n = 0; n < _shown.length; n++) {
      i = (i + delta) % _shown.length;
      if (_shown[i].enabled) break;
    }
    setState(() => _selected = i);
    if (_scroll.hasClients) {
      final top = i * _rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowHeight - view);
      }
    }
  }

  void _choose(int i) {
    if (i < 0 || i >= _shown.length || !_shown[i].enabled) return;
    Navigator.pop(context, _shown[i]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  ),
                  onChanged: _filter,
                  onSubmitted: (_) => _choose(_selected),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: _shown.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Aucun résultat'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: _shown.length,
                        itemBuilder: (_, i) {
                          final item = _shown[i];
                          final fg = item.enabled ? null : theme.disabledColor;
                          return Material(
                            color: i == _selected
                                ? AppColors.accent.withValues(alpha: 0.12)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: item.enabled ? () => _choose(i) : null,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Icon(item.icon ?? Icons.chevron_right,
                                        size: 18, color: fg),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: fg)),
                                          if (item.detail != null)
                                            Text(item.detail!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(color: fg)),
                                        ],
                                      ),
                                    ),
                                    if (item.shortcut != null)
                                      Text(item.shortcut!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  fontFamily: 'monospace',
                                                  color: fg)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
