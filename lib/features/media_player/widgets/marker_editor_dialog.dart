/// @file marker_editor_dialog.dart
/// @brief Dialogue d'édition d'un marqueur (créer / renommer / supprimer).

import 'package:flutter/material.dart';
import '../models/video_marker.dart';

class MarkerEditorResult {
  final String label;
  final bool delete;
  const MarkerEditorResult({required this.label, this.delete = false});
}

Future<MarkerEditorResult?> showMarkerEditorDialog(
  BuildContext context, {
  VideoMarker? existing,
  required Duration position,
}) {
  final ctrl = TextEditingController(text: existing?.label ?? '');
  final isEdit = existing != null;
  return showDialog<MarkerEditorResult>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(isEdit ? 'Modifier le marqueur' : 'Nouveau marqueur'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Position : ${_fmt(position)}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Libellé'),
          ),
        ],
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: () => Navigator.pop(
                context, const MarkerEditorResult(label: '', delete: true)),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, MarkerEditorResult(label: ctrl.text.trim())),
          child: Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    ),
  );
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
