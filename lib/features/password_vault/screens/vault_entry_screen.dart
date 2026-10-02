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

  /// Catégorie d'une nouvelle entrée (ignorée en modification).
  final VaultCategory category;

  const VaultEntryScreen({
    super.key,
    this.entry,
    this.category = VaultCategory.website,
  });

  @override
  State<VaultEntryScreen> createState() => _VaultEntryScreenState();
}

class _VaultEntryScreenState extends State<VaultEntryScreen> {
  late final _title = TextEditingController(text: widget.entry?.title);
  late VaultCategory _category = widget.entry?.category ?? widget.category;

  /// Un contrôleur par clé de champ, créé à la demande : changer de
  /// catégorie garde les valeurs des clés communes (mot de passe, notes…).
  final Map<String, TextEditingController> _fields = {};

  /// Champs secrets affichés en clair.
  final Set<String> _revealed = {};
  bool _dirty = false;
  bool _closing = false;
  String? _titleError;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    _title.addListener(_markDirty);
  }

  TextEditingController _ctrl(String key) => _fields.putIfAbsent(key, () {
        final c = TextEditingController(text: widget.entry?[key] ?? '');
        c.addListener(_markDirty);
        return c;
      });

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  VaultSession get _session => context.read<VaultSession>();

  /// Valeurs à enregistrer : champs de la catégorie choisie. Les champs
  /// inconnus de cette version (coffre plus récent) sont conservés tant que
  /// la catégorie ne change pas.
  Map<String, String> _values() {
    final original = widget.entry;
    return {
      if (original != null && original.categoryKey == _category.key)
        for (final e in original.fields.entries)
          if (_category.field(e.key) == null) e.key: e.value,
      for (final f in _category.fields)
        f.key: f.kind == VaultFieldKind.url || f.kind == VaultFieldKind.email
            ? _ctrl(f.key).text.trim()
            : _ctrl(f.key).text,
    };
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Le tag est obligatoire.');
      return;
    }
    try {
      if (_isNew) {
        await _session.addEntry(
            title: title, category: _category, fields: _values());
      } else {
        final original = widget.entry!;
        await _session.updateEntry(original.copyWith(
          title: title,
          category: original.categoryKey == _category.key ? null : _category,
          fields: _values(),
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

  Future<void> _generate(String key) async {
    final generated = await showPasswordGeneratorSheet(context);
    if (generated != null) {
      _ctrl(key).text = generated;
      setState(() => _revealed.add(key));
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
          title: Text(_isNew
              ? 'Nouvelle entrée · ${_category.label}'
              : 'Modifier · ${_category.label}'),
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
            DropdownButtonFormField<VaultCategory>(
              key: const Key('entry-category'),
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                for (final c in VaultCategory.values)
                  DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(c.icon, color: c.color, size: 20),
                        const SizedBox(width: 12),
                        Text(c.label),
                      ],
                    ),
                  ),
              ],
              onChanged: (c) {
                if (c == null || c == _category) return;
                setState(() {
                  _category = c;
                  _dirty = true;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry-title'),
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Tag *',
                helperText: 'Nom de l\'entrée, utilisé pour le tri',
                errorText: _titleError,
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            for (final f in _category.fields) ...[
              const SizedBox(height: 12),
              _fieldInput(f),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fieldInput(VaultField f) {
    final ctrl = _ctrl(f.key);
    final hidden = f.isSecret && !_revealed.contains(f.key);
    // Un champ masqué tient sur une ligne (contrainte de Flutter) ; affiché,
    // un champ long retrouve sa hauteur.
    final multiline = f.isMultiline && !hidden;
    return TextField(
      key: Key('field-${f.key}'),
      controller: ctrl,
      obscureText: hidden,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 8 : 1,
      autocorrect: false,
      enableSuggestions: !f.isSecret && f.kind == VaultFieldKind.multiline,
      enableIMEPersonalizedLearning: false,
      keyboardType: switch (f.kind) {
        VaultFieldKind.email => TextInputType.emailAddress,
        VaultFieldKind.url => TextInputType.url,
        VaultFieldKind.pin => TextInputType.number,
        _ when multiline => TextInputType.multiline,
        _ => TextInputType.text,
      },
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(
        labelText: f.label,
        helperText: f.hint,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (f.isSecret)
              IconButton(
                tooltip: hidden ? 'Afficher' : 'Masquer',
                icon: Icon(hidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() =>
                    hidden ? _revealed.add(f.key) : _revealed.remove(f.key)),
              ),
            if (f.kind == VaultFieldKind.password)
              IconButton(
                tooltip: 'Générer',
                icon: const Icon(Icons.casino_rounded),
                onPressed: () => _generate(f.key),
              ),
            if (f.key != 'notes')
              IconButton(
                tooltip: 'Copier : ${f.label}',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => _copy(ctrl.text, f.label),
              ),
          ],
        ),
      ),
    );
  }
}
