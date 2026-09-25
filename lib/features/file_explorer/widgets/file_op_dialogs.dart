/// @file file_op_dialogs.dart
/// @brief Dialogues des opérations sur les fichiers : conflit de noms,
/// renommage, bilan d'une opération groupée.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/services/file_operations_service.dart';

/// Résolveur de conflits qui interroge l'utilisateur, avec une option
/// « appliquer aux éléments suivants » valable pour toute l'opération.
ConflictResolver askingConflictResolver(BuildContext context) {
  ConflictAction? forAll;
  return (source, destination) async {
    if (forAll != null) return forAll!;
    if (!context.mounted) return ConflictAction.skip;
    final choice = await showDialog<(ConflictAction, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConflictDialog(destination: destination),
    );
    // Fermeture inattendue : on ne touche à rien.
    if (choice == null) return ConflictAction.skip;
    if (choice.$2) forAll = choice.$1;
    return choice.$1;
  };
}

class _ConflictDialog extends StatefulWidget {
  final String destination;
  const _ConflictDialog({required this.destination});

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  bool _applyToAll = false;

  void _pick(ConflictAction action) =>
      Navigator.pop(context, (action, _applyToAll));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Élément déjà présent'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('« ${p.basename(widget.destination)} » existe déjà dans ce '
              'dossier.'),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _applyToAll,
            onChanged: (v) => setState(() => _applyToAll = v ?? false),
            title: const Text('Appliquer aux éléments suivants'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _pick(ConflictAction.skip),
          child: const Text('Ignorer'),
        ),
        TextButton(
          onPressed: () => _pick(ConflictAction.keepBoth),
          child: const Text('Garder les deux'),
        ),
        TextButton(
          onPressed: () => _pick(ConflictAction.replace),
          child:
              const Text('Remplacer', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}

/// Dialogue de renommage. [onSubmit] effectue le renommage et lève
/// [FileOpException] en cas de refus : le message s'affiche sous le champ et
/// le dialogue reste ouvert pour corriger le nom.
Future<void> showRenameDialog(
  BuildContext context, {
  required String currentName,
  required Future<void> Function(String newName) onSubmit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName, onSubmit: onSubmit),
  );
}

class _RenameDialog extends StatefulWidget {
  final String currentName;
  final Future<void> Function(String newName) onSubmit;
  const _RenameDialog({required this.currentName, required this.onSubmit});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentName);
    // Présélectionne le nom sans l'extension, comme les gestionnaires usuels.
    final ext = p.extension(widget.currentName);
    final end = widget.currentName.startsWith('.') || ext.isEmpty
        ? widget.currentName.length
        : widget.currentName.length - ext.length;
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: end);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name == widget.currentName) {
      Navigator.pop(context);
      return;
    }
    final invalid = FileNameValidator.validate(name);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(name);
      if (mounted) Navigator.pop(context);
    } on FileOpException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renommer'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: 'Nouveau nom',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Renommer'),
        ),
      ],
    );
  }
}

/// Affiche le bilan d'une opération groupée : un message court, et le
/// détail des échecs sur demande. [verb] est au participe passé
/// (« copié(s) », « supprimé(s) »…).
void showFileOpReport(
  BuildContext context,
  FileOpReport report, {
  required String verb,
}) {
  final parts = <String>[
    '${report.succeeded.length} élément(s) $verb',
    if (report.skipped.isNotEmpty) '${report.skipped.length} ignoré(s)',
    if (report.hasFailures) '${report.failures.length} en échec',
  ];
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(parts.join(' · ')),
    backgroundColor: report.hasFailures ? AppColors.error : null,
    duration: Duration(seconds: report.hasFailures ? 8 : 3),
    action: report.hasFailures
        ? SnackBarAction(
            label: 'Détails',
            textColor: Colors.white,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Éléments en échec'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in report.failures)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('${p.basename(f.path)} : ${f.reason}'),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          )
        : null,
  ));
}
