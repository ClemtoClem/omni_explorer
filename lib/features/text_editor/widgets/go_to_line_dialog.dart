/// @file go_to_line_dialog.dart
/// @brief Dialogue « Aller à la ligne ».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Retourne le numéro de ligne (1-indexé) saisi, ou `null` si annulé.
Future<int?> showGoToLineDialog(
  BuildContext context, {
  required int lineCount,
  int currentLine = 1,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        GoToLineDialog(lineCount: lineCount, currentLine: currentLine),
  );
}

class GoToLineDialog extends StatefulWidget {
  final int lineCount;
  final int currentLine;

  const GoToLineDialog({
    super.key,
    required this.lineCount,
    this.currentLine = 1,
  });

  @override
  State<GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<GoToLineDialog> {
  // Possédé par l'état : libéré seulement quand le dialogue quitte l'arbre,
  // après son animation de fermeture.
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    final text = widget.currentLine.toString();
    _ctrl = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == null || n < 1 || n > widget.lineCount) {
      setState(() => _error = 'Numéro entre 1 et ${widget.lineCount}');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aller à la ligne'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Numéro de ligne',
          helperText: '1 – ${widget.lineCount}',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Aller')),
      ],
    );
  }
}
