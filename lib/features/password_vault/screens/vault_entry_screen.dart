/// @file vault_entry_screen.dart
/// @brief Ajout ou modification d'une entrée du coffre-fort.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../models/vault_entry.dart';
import '../models/vault_errors.dart';
import '../providers/vault_session.dart';
import '../widgets/password_generator_sheet.dart';

class VaultEntryScreen extends StatefulWidget {
  /// Entrée à modifier ; `null` pour en créer une.
  final VaultEntry? entry;
  const VaultEntryScreen({super.key, this.entry});

  @override
  State<VaultEntryScreen> createState() => _VaultEntryScreenState();
}

class _VaultEntryScreenState extends State<VaultEntryScreen> {
  late final _title = TextEditingController(text: widget.entry?.title);
  late final _username = TextEditingController(text: widget.entry?.username);
  late final _password = TextEditingController(text: widget.entry?.password);
  late final _url = TextEditingController(text: widget.entry?.url);
  late final _notes = TextEditingController(text: widget.entry?.notes);
  bool _showPassword = false;
  bool _dirty = false;
  bool _closing = false;
  String? _titleError;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _username, _password, _url, _notes]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  VaultSession get _session => context.read<VaultSession>();

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Le titre est obligatoire.');
      return;
    }
    try {
      if (_isNew) {
        await _session.addEntry(
          title: title,
          username: _username.text,
          password: _password.text,
          url: _url.text.trim(),
          notes: _notes.text,
        );
      } else {
        await _session.updateEntry(widget.entry!.copyWith(
          title: title,
          username: _username.text,
          password: _password.text,
          url: _url.text.trim(),
          notes: _notes.text,
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Supprimer l\'entrée'),
        content: Text('Supprimer « ${widget.entry!.title} » du coffre ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _session.deleteEntry(widget.entry!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _generate() async {
    final generated = await showPasswordGeneratorSheet(context);
    if (generated != null) {
      _password.text = generated;
      setState(() => _showPassword = true);
    }
  }

  Future<void> _copy(String value, String what) async {
    if (value.isEmpty) return;
    await _session.clipboard.copy(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$what copié — effacé du presse-papiers dans '
            '${_session.clipboard.clearAfter.inSeconds} s')));
  }

  void _showError(Object e) {
    if (!mounted) return;
    final msg = e is VaultException
        ? e.message
        : 'Enregistrement impossible : le coffre n\'a pas été modifié.';
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Abandonner les modifications ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Continuer l\'édition')),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Abandonner')),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VaultSession>();
    // Coffre verrouillé (délai, arrière-plan) : l'écran se ferme, une seule
    // fois, sans enregistrer (les champs ne quittent pas la mémoire du
    // widget, détruit avec l'écran).
    if (session.status != VaultStatus.unlocked && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Nouvelle entrée' : 'Modifier'),
          actions: [
            if (!_isNew)
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: session.busy ? null : _delete,
              ),
            IconButton(
              tooltip: 'Enregistrer',
              icon: const Icon(Icons.check_rounded),
              onPressed: session.busy ? null : _save,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('entry-title'),
              controller: _title,
              decoration:
                  InputDecoration(labelText: 'Titre *', errorText: _titleError),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-username'),
              controller: _username,
              decoration: InputDecoration(
                labelText: 'Identifiant',
                suffixIcon: IconButton(
                  tooltip: 'Copier l\'identifiant',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => _copy(_username.text, 'Identifiant'),
                ),
              ),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-password'),
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _showPassword ? 'Masquer' : 'Afficher',
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                    IconButton(
                      tooltip: 'Générer',
                      icon: const Icon(Icons.casino_rounded),
                      onPressed: _generate,
                    ),
                    IconButton(
                      tooltip: 'Copier le mot de passe',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copy(_password.text, 'Mot de passe'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Adresse (URL)'),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 3,
              maxLines: 8,
              enableIMEPersonalizedLearning: false,
            ),
          ],
        ),
      ),
    );
  }
}
