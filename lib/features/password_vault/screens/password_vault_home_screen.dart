/// @file password_vault_home_screen.dart
/// @brief Coffre-fort de mots de passe : création, déverrouillage, liste des
/// entrées.
///
/// Tant que cet écran est affiché, les captures d'écran sont bloquées
/// (Android) et chaque interaction repousse le verrouillage automatique.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/secure_window.dart';
import '../models/vault_entry.dart';
import '../models/vault_errors.dart';
import '../providers/vault_session.dart';
import '../services/vault_repository.dart';
import '../services/vault_sort.dart';
import '../widgets/vault_transfer_dialogs.dart';
import 'vault_entry_screen.dart';

class PasswordVaultHomeScreen extends StatefulWidget {
  const PasswordVaultHomeScreen({super.key});

  @override
  State<PasswordVaultHomeScreen> createState() =>
      _PasswordVaultHomeScreenState();
}

class _PasswordVaultHomeScreenState extends State<PasswordVaultHomeScreen> {
  late final VaultSession _session = context.read<VaultSession>();

  @override
  void initState() {
    super.initState();
    SecureWindow.acquire();
    _session.ensureInitialized();
  }

  @override
  void dispose() {
    SecureWindow.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VaultSession>();
    return Listener(
      // Toute interaction repousse le verrouillage pour inactivité.
      onPointerDown: (_) => session.touch(),
      child: switch (session.status) {
        VaultStatus.loading =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        VaultStatus.unavailable => _UnavailableView(session.initError),
        VaultStatus.absent => const _CreateVaultView(),
        VaultStatus.locked => const _UnlockView(),
        VaultStatus.unlocked => const _VaultListView(),
      },
    );
  }
}

// ── Messages d'erreur ───────────────────────────────────────────────────────

String _describe(Object e) => e is VaultException
    ? e.message
    : 'Opération impossible : le coffre n\'a pas été modifié.';

void _snackError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_describe(e)), backgroundColor: AppColors.error));
}

// ── Coffre indisponible ─────────────────────────────────────────────────────

class _UnavailableView extends StatelessWidget {
  final String? error;
  const _UnavailableView(this.error);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coffre-fort')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error ?? 'Coffre-fort indisponible.',
              textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// ── Champ de mot de passe maître ────────────────────────────────────────────

class _MasterPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  const _MasterPasswordField({
    required this.controller,
    required this.label,
    this.errorText,
    this.autofocus = false,
    this.onSubmitted,
    this.fieldKey,
  });

  @override
  State<_MasterPasswordField> createState() => _MasterPasswordFieldState();
}

class _MasterPasswordFieldState extends State<_MasterPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Masquer' : 'Afficher',
          icon: Icon(_visible
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

// ── Création ────────────────────────────────────────────────────────────────

class _CreateVaultView extends StatefulWidget {
  const _CreateVaultView();

  @override
  State<_CreateVaultView> createState() => _CreateVaultViewState();
}

class _CreateVaultViewState extends State<_CreateVaultView> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final invalid = VaultRepository.validatePassword(_pw.text);
    if (invalid != null) return setState(() => _error = invalid);
    if (_pw.text != _confirm.text) {
      return setState(() => _error = 'Les deux mots de passe diffèrent.');
    }
    setState(() => _error = null);
    try {
      await context.read<VaultSession>().create(_pw.text);
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<VaultSession>().busy;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Coffre-fort')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.shield_rounded,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Créer le coffre-fort',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Vos mots de passe sont chiffrés sur cet appareil avec un mot de '
            'passe maître (Argon2id et XChaCha20-Poly1305). Il n\'est stocké '
            'nulle part : s\'il est oublié, le coffre ne peut pas être '
            'récupéré.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _MasterPasswordField(
            fieldKey: const Key('create-password'),
            controller: _pw,
            label: 'Mot de passe maître',
            autofocus: true,
          ),
          const SizedBox(height: 12),
          _MasterPasswordField(
            fieldKey: const Key('create-confirm'),
            controller: _confirm,
            label: 'Confirmer le mot de passe',
            errorText: _error,
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _create,
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Créer'),
          ),
        ],
      ),
    );
  }
}

// ── Déverrouillage ──────────────────────────────────────────────────────────

class _UnlockView extends StatefulWidget {
  const _UnlockView();

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final _pw = TextEditingController();
  String? _error;
  bool _corrupted = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _unlock({bool fromBackup = false}) async {
    if (_pw.text.isEmpty) return;
    setState(() => _error = null);
    try {
      await context
          .read<VaultSession>()
          .unlock(_pw.text, fromBackup: fromBackup);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _describe(e);
        _corrupted = e is VaultCorruptedException && !fromBackup;
      });
      _pw.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VaultSession>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coffre-fort'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _confirmDeleteVault(context),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'delete', child: Text('Mot de passe oublié…')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.lock_rounded, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Coffre verrouillé',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          _MasterPasswordField(
            fieldKey: const Key('unlock-password'),
            controller: _pw,
            label: 'Mot de passe maître',
            errorText: _error,
            autofocus: true,
            onSubmitted: (_) => _unlock(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: session.busy ? null : () => _unlock(),
            child: session.busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Déverrouiller'),
          ),
          if (_corrupted && session.hasBackup) ...[
            const SizedBox(height: 20),
            const Text(
              'Une version précédente du coffre a été conservée. Elle peut '
              'demander l\'ancien mot de passe maître si celui-ci a été changé '
              'depuis.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: session.busy ? null : () => _unlock(fromBackup: true),
              child: const Text('Ouvrir la version précédente'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Suppression définitive du coffre (mot de passe oublié) : saisie de
/// confirmation obligatoire.
Future<void> _confirmDeleteVault(BuildContext context) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dCtx) => StatefulBuilder(
      builder: (dCtx, setLocal) => AlertDialog(
        title: const Text('Supprimer le coffre-fort'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Toutes les entrées seront définitivement perdues. '
                'Tapez SUPPRIMER pour confirmer.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              onChanged: (_) => setLocal(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: ctrl.text == 'SUPPRIMER'
                ? () => Navigator.pop(dCtx, true)
                : null,
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  if (ok != true || !context.mounted) return;
  try {
    await context.read<VaultSession>().deleteVault();
  } catch (e) {
    if (context.mounted) _snackError(context, e);
  }
}

// ── Liste des entrées ───────────────────────────────────────────────────────

class _VaultListView extends StatefulWidget {
  const _VaultListView();

  @override
  State<_VaultListView> createState() => _VaultListViewState();
}

class _VaultListViewState extends State<_VaultListView> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(VaultEntry entry) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => VaultEntryScreen(entry: entry)));
  }

  /// Nouvelle entrée : choix de la catégorie, puis formulaire.
  Future<void> _add() async {
    final category = await showModalBottomSheet<VaultCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Quel type d\'information ?',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final c in VaultCategory.values)
                ListTile(
                  leading: _CategoryIcon(c),
                  title: Text(c.label),
                  subtitle: Text(
                    c.fields
                        .where((f) => f.key != 'notes')
                        .map((f) => f.label)
                        .join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(sheetCtx, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (category == null || !mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => VaultEntryScreen(category: category)));
  }

  Future<void> _copy(String value, String what) async {
    if (value.isEmpty) return;
    final session = context.read<VaultSession>();
    await session.clipboard.copy(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$what copié — effacé du presse-papiers dans '
            '${session.clipboard.clearAfter.inSeconds} s')));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VaultSession>();
    final mode = session.sortMode;
    final entries = sortVaultEntries(
        session.entries.where((e) => e.matches(_query)), mode);

    // Liste à plat : en-têtes de catégorie (tri par catégorie) et entrées.
    final rows = <Object>[];
    for (final e in entries) {
      if (mode == VaultSortMode.category &&
          (rows.isEmpty ||
              (rows.last is VaultEntry &&
                  (rows.last as VaultEntry).category != e.category))) {
        rows.add(e.category);
      }
      rows.add(e);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coffre-fort'),
        actions: [
          PopupMenuButton<VaultSortMode>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort_rounded),
            initialValue: mode,
            onSelected: session.setSortMode,
            itemBuilder: (_) => [
              for (final m in VaultSortMode.values)
                CheckedPopupMenuItem(
                  value: m,
                  checked: m == mode,
                  child: Text(m.label),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Verrouiller',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: session.lock,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') exportVault(context);
              if (v == 'import') importVault(context);
              if (v == 'password') _changePassword(context);
              if (v == 'delete') _confirmDeleteVault(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Exporter…')),
              PopupMenuItem(value: 'import', child: Text('Importer…')),
              PopupMenuItem(
                  value: 'password',
                  child: Text('Changer le mot de passe maître')),
              PopupMenuItem(
                  value: 'delete', child: Text('Supprimer le coffre')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter',
        onPressed: _add,
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Rechercher (tag, catégorie, champs non secrets)',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(session.entries.isEmpty
                        ? 'Aucune entrée. Ajoutez-en une avec +.'
                        : 'Aucun résultat.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      if (row is VaultCategory) return _CategoryHeader(row);
                      return _entryTile(
                          row as VaultEntry,
                          showCategory: mode != VaultSortMode.category);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(VaultEntry e, {required bool showCategory}) {
    final c = e.category;
    final summary = e.summary;
    final secretField = c.secret == null ? null : c.field(c.secret!);
    final summaryField = c.summary == null ? null : c.field(c.summary!);
    final subtitle = [
      if (showCategory) c.label,
      if (summary.isNotEmpty) summary,
    ].join(' · ');
    return ListTile(
      key: ValueKey(e.id),
      leading: _CategoryIcon(c),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _open(e),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (summary.isNotEmpty && summaryField != null)
            IconButton(
              tooltip: 'Copier : ${summaryField.label}',
              icon: const Icon(Icons.person_outline_rounded),
              onPressed: () => _copy(summary, summaryField.label),
            ),
          if (e.primarySecret.isNotEmpty && secretField != null)
            IconButton(
              tooltip: 'Copier : ${secretField.label}',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copy(e.primarySecret, secretField.label),
            ),
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final VaultCategory category;
  const _CategoryIcon(this.category);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(category.icon, color: category.color, size: 22),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final VaultCategory category;
  const _CategoryHeader(this.category);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(category.icon, size: 16, color: category.color),
          const SizedBox(width: 8),
          Text(
            category.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: category.color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Changement du mot de passe maître.
Future<void> _changePassword(BuildContext context) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dCtx) => StatefulBuilder(
      builder: (dCtx, setLocal) {
        final busy = dCtx.watch<VaultSession>().busy;
        Future<void> submit() async {
          final invalid = VaultRepository.validatePassword(next.text);
          if (invalid != null) return setLocal(() => error = invalid);
          if (next.text != confirm.text) {
            return setLocal(() => error = 'Les deux mots de passe diffèrent.');
          }
          try {
            await dCtx
                .read<VaultSession>()
                .changePassword(current.text, next.text);
            if (dCtx.mounted) Navigator.pop(dCtx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mot de passe maître changé.')));
            }
          } catch (e) {
            setLocal(() => error = _describe(e));
          }
        }

        return AlertDialog(
          title: const Text('Changer le mot de passe maître'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MasterPasswordField(
                    controller: current, label: 'Mot de passe actuel'),
                const SizedBox(height: 8),
                _MasterPasswordField(
                    controller: next, label: 'Nouveau mot de passe'),
                const SizedBox(height: 8),
                _MasterPasswordField(
                    controller: confirm,
                    label: 'Confirmer le nouveau',
                    errorText: error),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(dCtx),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: busy ? null : submit, child: const Text('Changer')),
          ],
        );
      },
    ),
  );
  current.dispose();
  next.dispose();
  confirm.dispose();
}
