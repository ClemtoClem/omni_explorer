/// @file project_search_screen.dart
/// @brief Recherche dans tous les fichiers du projet. Toucher un résultat
/// ferme l'écran et le renvoie (fichier, ligne, colonne) à l'éditeur.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../services/project_search.dart';
import '../services/text_search.dart';

class ProjectSearchScreen extends StatefulWidget {
  final String root;
  final List<String> exclude;
  final TextSearchQuery initialQuery;

  const ProjectSearchScreen({
    super.key,
    required this.root,
    this.exclude = const [],
    this.initialQuery = const TextSearchQuery(''),
  });

  @override
  State<ProjectSearchScreen> createState() => _ProjectSearchScreenState();
}

class _ProjectSearchScreenState extends State<ProjectSearchScreen> {
  late final TextEditingController _ctrl;
  late TextSearchQuery _query;

  /// Résultats groupés par fichier, dans l'ordre de découverte.
  final Map<String, List<ProjectSearchHit>> _byFile = {};
  StreamSubscription<ProjectSearchHit>? _sub;
  ProjectSearchSummary? _summary;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _ctrl = TextEditingController(text: _query.pattern);
    if (!_query.isEmpty) _run();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _run() {
    _sub?.cancel();
    setState(() {
      _byFile.clear();
      _summary = null;
      _running = !_query.isEmpty && _query.error == null;
    });
    if (!_running) return;
    _sub = ProjectSearch.search(
      widget.root,
      _query,
      exclude: widget.exclude,
      onDone: (s) {
        if (mounted) setState(() => _summary = s);
      },
    ).listen(
      (hit) {
        if (!mounted) return;
        setState(() => (_byFile[hit.path] ??= []).add(hit));
      },
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
    );
  }

  void _setOption(TextSearchQuery q) {
    setState(() => _query = q);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = _byFile.values.fold<int>(0, (n, l) => n + l.length);
    final error = _query.error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher dans le projet'),
        bottom: _running
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Texte à chercher',
                prefixIcon: const Icon(Icons.search_rounded),
                errorText: error,
              ),
              onSubmitted: (v) => _setOption(_query.copyWith(pattern: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Casse'),
                  selected: _query.caseSensitive,
                  onSelected: (v) =>
                      _setOption(_query.copyWith(caseSensitive: v)),
                ),
                FilterChip(
                  label: const Text('Mot entier'),
                  selected: _query.wholeWord,
                  onSelected: (v) => _setOption(_query.copyWith(wholeWord: v)),
                ),
                FilterChip(
                  label: const Text('Expression'),
                  selected: _query.regex,
                  onSelected: (v) => _setOption(_query.copyWith(regex: v)),
                ),
              ],
            ),
          ),
          if (_summary != null || hits > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$hits résultat${hits > 1 ? 's' : ''} dans '
                  '${_byFile.length} fichier${_byFile.length > 1 ? 's' : ''}'
                  '${_summary?.truncated == true ? ' — recherche limitée, '
                      'affinez la requête' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final entry in _byFile.entries) ...[
                  _FileHeader(
                    path: entry.key,
                    root: widget.root,
                    count: entry.value.length,
                  ),
                  for (final hit in entry.value)
                    _HitTile(
                      hit: hit,
                      onTap: () => Navigator.pop(context, hit),
                    ),
                ],
                if (_summary != null && hits == 0)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Aucun résultat')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  final String path;
  final String root;
  final int count;

  const _FileHeader(
      {required this.path, required this.root, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rel = p.relative(path, from: root);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: p.basename(rel),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p.dirname(rel) != '.')
                  TextSpan(
                      text: '  ${p.dirname(rel)}',
                      style: theme.textTheme.bodySmall),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$count', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  final ProjectSearchHit hit;
  final VoidCallback onTap;

  const _HitTile({required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final text = hit.preview;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 6, 16, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text('${hit.line}',
                  style: mono?.copyWith(color: theme.disabledColor)),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(style: mono, children: [
                  TextSpan(text: text.substring(0, hit.previewStart)),
                  TextSpan(
                    text: text.substring(hit.previewStart, hit.previewEnd),
                    style: TextStyle(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.25),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: text.substring(hit.previewEnd)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
