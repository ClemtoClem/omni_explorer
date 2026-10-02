/// @file vault_transfer_dialogs.dart
/// @brief Export et import du coffre-fort par paquet verrouillé.
///
/// Le paquet (`.omnivault`) est chiffré comme le coffre, avec son mot de
/// passe maître : il peut être conservé ailleurs (clé USB, autre appareil)
/// et réimporté dans ce coffre ou dans un autre.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/atomic_write.dart';
import '../../file_explorer/explorer_picker.dart';
import '../models/vault_errors.dart';
import '../providers/vault_session.dart';
import '../services/vault_merge.dart';
import '../services/vault_repository.dart';

String _message(Object e) => e is VaultException
    ? e.message
    : 'Opération impossible : le coffre n\'a pas été modifié.';

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: error ? AppColors.error : null));
}

/// Dialogue de mot de passe qui exécute [action] : un mauvais mot de passe
/// s'affiche sous le champ sans fermer le dialogue. Renvoie le résultat de
/// [action], ou `null` si l'utilisateur annule.
Future<T?> _passwordDialog<T>(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required Future<T> Function(String password) run,
}) {
  final ctrl = TextEditingController();
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (dCtx) {
      String? error;
      var busy = false;
      var visible = false;
      return StatefulBuilder(builder: (dCtx, setLocal) {
        Future<void> submit() async {
          if (ctrl.text.isEmpty || busy) return;
          setLocal(() {
            busy = true;
            error = null;
          });
          try {
            final result = await run(ctrl.text);
            if (dCtx.mounted) Navigator.pop(dCtx, result);
          } on WrongPasswordException catch (e) {
            setLocal(() {
              busy = false;
              error = e.message;
            });
            ctrl.clear();
          }
        }

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                key: const Key('transfer-password'),
                controller: ctrl,
                obscureText: !visible,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  errorText: error,
                  suffixIcon: IconButton(
                    icon: Icon(visible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () => setLocal(() => visible = !visible),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(dCtx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(action),
            ),
          ],
        );
      });
    },
  ).whenComplete(ctrl.dispose);
}

// ── Export ──────────────────────────────────────────────────────────────────

/// Exporte le coffre dans un paquet verrouillé choisi par l'utilisateur.
Future<void> exportVault(BuildContext context) async {
  final session = context.read<VaultSession>();
  final Uint8List? bytes;
  try {
    bytes = await _passwordDialog<Uint8List>(
      context,
      title: 'Exporter le coffre',
      message: 'Le paquet sera verrouillé par le mot de passe maître actuel. '
          'Il faudra ce mot de passe pour l\'importer : conservez-le avec '
          'le fichier.',
      action: 'Exporter',
      run: session.exportPackage,
    );
  } catch (e) {
    if (context.mounted) _snack(context, _message(e), error: true);
    return;
  }
  if (bytes == null || !context.mounted) return;

  final now = DateTime.now();
  final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final fileName = 'coffre-omniexplorer-$date.omnivault';
  try {
    // L'explorateur renvoie un chemin (remplacement déjà confirmé) : le
    // paquet y est écrit de façon atomique, sur Android comme sur Linux.
    final path = await ExplorerPicker.saveFile(
      context,
      title: 'Enregistrer l\'export du coffre',
      fileName: fileName,
      extensions: {'omnivault'},
    );
    if (path == null) {
      if (context.mounted) _snack(context, 'Export annulé.');
      return;
    }
    await AtomicWrite.bytes(path, bytes);
    if (context.mounted) {
      _snack(context, 'Export enregistré : ${path.split('/').last}');
    }
  } catch (e) {
    if (context.mounted) {
      _snack(context, 'Enregistrement de l\'export impossible.', error: true);
    }
  }
}

// ── Import ──────────────────────────────────────────────────────────────────

/// Importe les entrées d'un paquet verrouillé dans le coffre ouvert.
Future<void> importVault(BuildContext context) async {
  final session = context.read<VaultSession>();
  try {
    // Le fichier est lu sur place : aucune copie laissée dans un cache.
    final path = await ExplorerPicker.pickFile(context,
        title: 'Choisir un export de coffre');
    if (path == null || !context.mounted) return;

    final file = File(path);
    if (await file.length() > VaultRepository.maxExportBytes) {
      throw const ExportTooLargeException();
    }
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;

    final plan = await _passwordDialog<ImportPlan>(
      context,
      title: 'Importer un export',
      message: 'Mot de passe du coffre qui a créé cet export (celui en '
          'vigueur au moment de l\'export).',
      action: 'Déverrouiller',
      run: (pw) => session.previewImport(bytes, pw),
    );
    if (plan == null || !context.mounted) return;

    final choice = await _confirmImport(context, plan);
    if (choice == null || !context.mounted) return;
    final before = session.entries.length;
    await session.applyImport(plan, choice);
    if (!context.mounted) return;
    final added = session.entries.length - before;
    final replaced =
        choice == ImportConflictChoice.replace ? plan.conflicts.length : 0;
    _snack(
        context,
        [
          '$added entrée(s) ajoutée(s)',
          if (replaced > 0) '$replaced remplacée(s)',
          if (plan.identical.isNotEmpty)
            '${plan.identical.length} déjà présente(s)',
        ].join(' · '));
  } catch (e) {
    if (context.mounted) _snack(context, _message(e), error: true);
  }
}

/// Résumé de l'import et choix pour les entrées en conflit. `null` : annulé.
Future<ImportConflictChoice?> _confirmImport(
    BuildContext context, ImportPlan plan) {
  if (plan.added.isEmpty && plan.conflicts.isEmpty) {
    _snack(
        context,
        plan.total == 0
            ? 'Cet export ne contient aucune entrée.'
            : 'Toutes les entrées de l\'export sont déjà dans le coffre.');
    return Future.value(null);
  }
  var choice = ImportConflictChoice.keepBoth;
  return showDialog<ImportConflictChoice>(
    context: context,
    builder: (dCtx) => StatefulBuilder(
      builder: (dCtx, setLocal) => AlertDialog(
        title: const Text('Importer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${plan.added.length} nouvelle(s) entrée(s)'),
              if (plan.identical.isNotEmpty)
                Text('${plan.identical.length} déjà présente(s), ignorée(s)'),
              if (plan.conflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${plan.conflicts.length} entrée(s) existent déjà avec un '
                    'contenu différent :'),
                for (final c in plan.conflicts.take(5))
                  Text('• ${c.existing.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (plan.conflicts.length > 5)
                  Text('… et ${plan.conflicts.length - 5} autre(s)'),
                RadioGroup<ImportConflictChoice>(
                  groupValue: choice,
                  onChanged: (v) => setLocal(() => choice = v ?? choice),
                  child: const Column(
                    children: [
                      RadioListTile(
                        contentPadding: EdgeInsets.zero,
                        value: ImportConflictChoice.keepBoth,
                        title: Text('Garder les deux'),
                        subtitle: Text('L\'entrée importée est ajoutée avec '
                            '« (importé) » dans son titre'),
                      ),
                      RadioListTile(
                        contentPadding: EdgeInsets.zero,
                        value: ImportConflictChoice.replace,
                        title: Text('Remplacer par l\'entrée importée'),
                      ),
                      RadioListTile(
                        contentPadding: EdgeInsets.zero,
                        value: ImportConflictChoice.skip,
                        title: Text('Garder les entrées du coffre'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, choice),
              child: const Text('Importer')),
        ],
      ),
    ),
  );
}
