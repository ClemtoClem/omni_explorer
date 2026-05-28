/// @file subtitle_search_dialog.dart
/// @brief Recherche d'une occurrence dans les sous-titres → seek à la position.

import 'package:flutter/material.dart';

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleEntry({required this.start, required this.end, required this.text});
}

class SubtitleSearchDialog extends StatefulWidget {
  final List<SubtitleEntry> entries;
  final void Function(Duration) onSeek;

  const SubtitleSearchDialog({
    super.key,
    required this.entries,
    required this.onSeek,
  });

  @override
  State<SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog> {
  final _ctrl = TextEditingController();
  List<SubtitleEntry> _matches = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _matches = const []);
      return;
    }
    setState(() {
      _matches = widget.entries
          .where((e) => e.text.toLowerCase().contains(query))
          .take(200)
          .toList();
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.search_rounded, size: 20),
        SizedBox(width: 8),
        Text('Rechercher dans les sous-titres'),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.entries.isEmpty
                    ? 'Aucun sous-titre disponible…'
                    : '${widget.entries.length} lignes',
                prefixIcon: const Icon(Icons.text_fields_rounded),
              ),
              onChanged: _search,
              enabled: widget.entries.isNotEmpty,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _matches.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _matches.length,
                      itemBuilder: (_, i) {
                        final m = _matches[i];
                        return ListTile(
                          dense: true,
                          leading: Text(_fmt(m.start),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                          title: Text(m.text,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSeek(m.start);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
