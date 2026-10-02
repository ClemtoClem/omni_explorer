/// @file archive_screen.dart
/// @brief Exploration et modification d'une archive, comme un dossier de
/// l'explorateur : navigation dossier par dossier, sélection multiple,
/// extraction, ajout, création de dossier, renommage, déplacement,
/// duplication, suppression, mise à jour depuis un dossier.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/services/file_operations_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/file_op_dialogs.dart';
import '../../file_explorer/explorer_picker.dart';
import '../models/archive_entry.dart';
import '../models/archive_tree.dart';
import '../services/archive_document.dart';
import '../services/archive_service.dart';

export '../widgets/compress_dialog.dart' show showCompressDialog;

class ArchiveScreen extends StatefulWidget {
  final String archivePath;
  const ArchiveScreen({super.key, required this.archivePath});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  late final ArchiveType _type = ArchiveService.detectType(widget.archivePath);

  /// Document modifiable (formats lus par le paquet `archive`).
  ArchiveDocument? _doc;

  /// Arborescence en lecture seule (7z / RAR via l'outil externe).
  ArchiveTree? _cliTree;

  String? _password;
  bool _loading = true;
  bool _needsPassword = false;
  String? _error;
  bool _busy = false;

  /// Dossier affiché (`''` : racine).
  String _dir = '';
  final Set<String> _selected = {};
  String? _search;

  ArchiveTree get _tree => _doc?.tree ?? _cliTree!;
  bool get _canEdit => _doc?.canEdit ?? false;
  String get _archiveName => p.basename(widget.archivePath);

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Chargement ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsPassword = false;
    });
    try {
      if (_type.isDartNative) {
        _doc =
            await ArchiveDocument.open(widget.archivePath, password: _password);
      } else {
        final entries = await ArchiveService.listEntries(widget.archivePath,
            password: _password);
        _cliTree = ArchiveTree.fromEntries(entries.map((e) => RawArchiveEntry(
            name: e.fullPath,
            isDirectory: e.isDirectory,
            size: e.size,
            compressedSize: e.compressedSize,
            modified: e.modified)));
      }
      if (!_tree.isDirectory(_dir)) _dir = '';
      _selected.removeWhere((path) => _tree[path] == null);
    } on ArchiveOpException catch (e) {
      _needsPassword = e.isPasswordRequired;
      _error = e.message;
    } catch (e) {
      _error = 'Archive illisible : $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Opérations ──────────────────────────────────────────────────────────

  /// Applique [op] au document puis enregistre l'archive. En cas d'échec,
  /// l'archive est relue depuis le disque (rien n'a été écrit).
  Future<void> _edit(Future<String?> Function(ArchiveDocument doc) op) async {
    final doc = _doc;
    if (doc == null || !_canEdit) return;
    setState(() => _busy = true);
    try {
      final message = await op(doc);
      await doc.save();
      _selected.clear();
      if (message != null) _snack(message);
    } catch (e) {
      _snack(_describe(e), error: true);
      await _load(); // annule les modifications en mémoire
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object e) => switch (e) {
        ArchiveOpException(:final message) => message,
        FileOpException(:final message) => message,
        FileSystemException(:final message) => 'Erreur d\'écriture : $message',
        _ => 'Opération impossible : $e',
      };

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text), backgroundColor: error ? AppColors.error : null));
  }

  String _reportText(ArchiveEditReport r, String verb) => [
        if (r.added > 0) '${r.added} élément(s) $verb',
        if (r.replaced > 0) '${r.replaced} remplacé(s)',
        if (r.skipped > 0) '${r.skipped} ignoré(s)',
        if (r.failures.isNotEmpty) r.failures.join(' ; '),
      ].join(' · ');

  /// Dossier qui contient l'archive : point de départ des sélecteurs.
  String get _hostDir => p.dirname(widget.archivePath);

  Future<void> _addFiles() async {
    final paths = await ExplorerPicker.pickFiles(context,
        title: 'Fichiers à ajouter', initialPath: _hostDir);
    if (paths.isEmpty || !mounted) return;
    final resolver = askingConflictResolver(context);
    await _edit((doc) async => _reportText(
        await doc.addFromDisk(paths, _dir, onConflict: resolver), 'ajouté(s)'));
  }

  Future<void> _addFolder() async {
    final dir = await ExplorerPicker.pickDirectory(context,
        title: 'Dossier à ajouter', initialPath: _hostDir);
    if (dir == null || !mounted) return;
    final resolver = askingConflictResolver(context);
    await _edit((doc) async => _reportText(
        await doc.addFromDisk([dir], _dir, onConflict: resolver), 'ajouté(s)'));
  }

  Future<void> _newFolder() async {
    final name = await _askName('Nouveau dossier', '');
    if (name == null) return;
    await _edit((doc) async {
      doc.createFolder(_dir, name);
      return 'Dossier « $name » créé';
    });
  }

  Future<void> _rename(String path) async {
    final node = _tree[path];
    if (node == null) return;
    await showRenameDialog(context, currentName: node.name,
        onSubmit: (newName) async {
      // Validation avant de fermer le dialogue (message sous le champ).
      try {
        _doc!.rename(path, newName);
      } on ArchiveOpException catch (e) {
        throw FileOpException(e.message);
      }
    });
    // Le renommage a eu lieu en mémoire si le dialogue s'est fermé sur un
    // succès : on enregistre (sans effet si rien n'a changé).
    if (_tree[path] == null) await _edit((_) async => null);
  }

  Future<void> _duplicate(List<String> paths) =>
      _edit((doc) async => _reportText(doc.duplicate(paths), 'dupliqué(s)'));

  Future<void> _delete(List<String> paths) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Supprimer de l\'archive'),
        content: Text(paths.length == 1
            ? 'Supprimer « ${p.basename(paths.single)} » de l\'archive ?'
            : 'Supprimer ${paths.length} éléments de l\'archive ?'),
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
    await _edit((doc) async {
      doc.delete(paths);
      return '${paths.length} élément(s) supprimé(s)';
    });
  }

  Future<void> _move(List<String> paths) async {
    final target = await _pickArchiveFolder(exclude: paths);
    if (target == null || !mounted) return;
    final resolver = askingConflictResolver(context);
    await _edit((doc) async => _reportText(
        await doc.move(paths, target, onConflict: resolver), 'déplacé(s)'));
  }

  Future<void> _sync() async {
    final source = await ExplorerPicker.pickDirectory(context,
        title: 'Dossier source de la mise à jour', initialPath: _hostDir);
    if (source == null || !mounted) return;
    final exclude = await _askExclusions(source);
    if (exclude == null) return;
    await _edit((doc) async {
      final r =
          doc.syncFromDirectory(source, targetDir: _dir, exclude: exclude);
      return '${r.added} ajouté(s) · ${r.updated} mis à jour · '
          '${r.unchanged} inchangé(s)'
          '${r.skipped > 0 ? ' · ${r.skipped} ignoré(s)' : ''}';
    });
  }

  Future<void> _extract(List<String> paths, {required bool here}) async {
    final dest = here
        ? _hostDir
        : await ExplorerPicker.pickDirectory(context,
            title: 'Extraire vers…', initialPath: _hostDir);
    if (dest == null || !mounted) return;
    final resolver = askingConflictResolver(context);
    setState(() => _busy = true);
    try {
      var result = const ExtractResult();
      if (paths.isEmpty) {
        result = await ArchiveService.extractAll(widget.archivePath, dest,
            password: _password, onConflict: resolver);
      } else {
        for (final path in paths) {
          result += await ArchiveService.extractEntry(
              widget.archivePath, path, dest,
              password: _password, onConflict: resolver);
        }
      }
      _selected.clear();
      _snack('Extrait dans $dest${result.notes}');
    } catch (e) {
      _snack(_describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _managePassword() async {
    final ctrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Mot de passe de l\'archive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_doc?.password == null
                ? 'L\'archive n\'est pas chiffrée. Un mot de passe la chiffrera '
                    'en AES.'
                : 'L\'archive est chiffrée. Laissez vide pour retirer le mot '
                    'de passe.'),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Nouveau mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, ctrl.text),
              child: const Text('Appliquer')),
        ],
      ),
    );
    ctrl.dispose();
    if (action == null) return;
    await _edit((doc) async {
      doc.setPassword(action.isEmpty ? null : action);
      _password = doc.password;
      return action.isEmpty ? 'Mot de passe retiré' : 'Archive chiffrée (AES)';
    });
  }

  // ── Dialogues ───────────────────────────────────────────────────────────

  Future<String?> _askName(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(dCtx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
              child: const Text('Créer')),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<Set<String>?> _askExclusions(String source) {
    final ctrl = TextEditingController();
    return showDialog<Set<String>>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Mettre à jour depuis un dossier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Depuis : $source\nVers : '
                '${_dir.isEmpty ? '(racine de l\'archive)' : _dir}\n\n'
                'Ajoute les fichiers absents de l\'archive et remplace ceux '
                'dont le contenu a changé. Rien n\'est supprimé.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Noms à ignorer (séparés par des virgules)',
                hintText: 'build, .dart_tool, node_modules',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, {
              for (final s in ctrl.text.split(','))
                if (s.trim().isNotEmpty) s.trim(),
            }),
            child: const Text('Mettre à jour'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// Choix d'un dossier de l'archive (destination d'un déplacement).
  Future<String?> _pickArchiveFolder({required List<String> exclude}) {
    bool excluded(String dir) =>
        exclude.any((e) => dir == e || dir.startsWith('$e/'));
    final dirs = ['', ..._tree.directories.where((d) => !excluded(d))];
    return showDialog<String>(
      context: context,
      builder: (dCtx) => SimpleDialog(
        title: const Text('Déplacer vers…'),
        children: [
          for (final d in dirs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dCtx, d),
              child: Row(children: [
                Icon(d.isEmpty ? Icons.home_rounded : Icons.folder_rounded,
                    size: 18, color: AppColors.colorFolder),
                const SizedBox(width: 8),
                Expanded(child: Text(d.isEmpty ? '(racine)' : d)),
              ]),
            ),
        ],
      ),
    );
  }

  void _showInfo() {
    final t = _tree;
    final size = File(widget.archivePath).lengthSync();
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(_archiveName),
        content: Text([
          'Format : ${_type.label}',
          'Taille de l\'archive : ${FileUtils.formatSize(size)}',
          'Fichiers : ${t.fileCount}',
          'Taille décompressée : ${FileUtils.formatSize(t.totalSize)}',
          if (_password != null) 'Chiffrée (mot de passe)',
          if (!_canEdit) 'Lecture seule : ${_type.readOnlyReason}',
        ].join('\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Fermer')),
        ],
      ),
    );
  }

  /// Actions sur un seul élément (appui sur un fichier).
  Future<void> _itemSheet(ArchiveNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title:
                  Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(node.isDirectory
                  ? 'Dossier'
                  : FileUtils.formatSize(node.size)),
            ),
            const Divider(height: 1),
            for (final (value, icon, label, editOnly) in [
              ('extractHere', Icons.unarchive_rounded, 'Extraire ici', false),
              (
                'extractTo',
                Icons.drive_folder_upload_rounded,
                'Extraire vers…',
                false
              ),
              (
                'rename',
                Icons.drive_file_rename_outline_rounded,
                'Renommer',
                true
              ),
              (
                'duplicate',
                Icons.control_point_duplicate_rounded,
                'Dupliquer',
                true
              ),
              ('move', Icons.drive_file_move_rounded, 'Déplacer…', true),
              ('delete', Icons.delete_outline_rounded, 'Supprimer', true),
            ])
              if (!editOnly || _canEdit)
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () => Navigator.pop(sCtx, value),
                ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'extractHere':
        await _extract([node.path], here: true);
      case 'extractTo':
        await _extract([node.path], here: false);
      case 'rename':
        await _rename(node.path);
      case 'duplicate':
        await _duplicate([node.path]);
      case 'move':
        await _move([node.path]);
      case 'delete':
        await _delete([node.path]);
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  void _open(ArchiveNode node) {
    if (_selected.isNotEmpty) return _toggle(node.path);
    if (node.isDirectory) {
      setState(() {
        _dir = node.path;
        _search = null;
      });
    } else {
      _itemSheet(node);
    }
  }

  void _toggle(String path) => setState(() {
        if (!_selected.remove(path)) _selected.add(path);
      });

  void _goUp() => setState(() {
        final i = _dir.lastIndexOf('/');
        _dir = i < 0 ? '' : _dir.substring(0, i);
      });

  // ── Construction ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canGoBack =
        _selected.isNotEmpty || _search != null || _dir.isNotEmpty;
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected.isNotEmpty) return setState(_selected.clear);
        if (_search != null) return setState(() => _search = null);
        _goUp();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (!_loading && _error == null) ...[
              if (!_canEdit) _readOnlyBanner(),
              if (_search == null) _breadcrumb(),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: _selected.isEmpty ? null : _selectionBar(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selected.isNotEmpty) {
      return AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(_selected.clear)),
        title: Text('${_selected.length} sélectionné(s)'),
        actions: [
          IconButton(
            tooltip: 'Tout sélectionner',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () => setState(() =>
                _selected.addAll(_tree.children(_dir).map((n) => n.path))),
          ),
        ],
      );
    }
    if (_search != null) {
      return AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Rechercher dans l\'archive', border: InputBorder.none),
          onChanged: (v) => setState(() => _search = v),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _search = null)),
        ],
      );
    }
    final ready = !_loading && _error == null;
    return AppBar(
      title: Text(_archiveName, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        if (ready)
          IconButton(
            tooltip: 'Rechercher',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => setState(() => _search = ''),
          ),
        if (ready)
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (v) => switch (v) {
              'addFiles' => _addFiles(),
              'addFolder' => _addFolder(),
              'newFolder' => _newFolder(),
              'sync' => _sync(),
              'extractHere' => _extract(const [], here: true),
              'extractTo' => _extract(const [], here: false),
              'password' => _managePassword(),
              _ => Future(_showInfo),
            },
            itemBuilder: (_) => [
              if (_canEdit) ...const [
                PopupMenuItem(
                    value: 'addFiles', child: Text('Ajouter des fichiers…')),
                PopupMenuItem(
                    value: 'addFolder', child: Text('Ajouter un dossier…')),
                PopupMenuItem(
                    value: 'newFolder', child: Text('Nouveau dossier')),
                PopupMenuItem(
                    value: 'sync',
                    child: Text('Mettre à jour depuis un dossier…')),
              ],
              const PopupMenuItem(
                  value: 'extractHere', child: Text('Tout extraire ici')),
              const PopupMenuItem(
                  value: 'extractTo', child: Text('Tout extraire vers…')),
              if (_canEdit &&
                  (_type == ArchiveType.zip || _type == ArchiveType.jar))
                const PopupMenuItem(
                    value: 'password', child: Text('Mot de passe…')),
              const PopupMenuItem(value: 'info', child: Text('Informations')),
            ],
          ),
      ],
    );
  }

  Widget _readOnlyBanner() => Container(
        width: double.infinity,
        color: AppColors.warning.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text('Lecture seule — ${_type.readOnlyReason}',
            style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _breadcrumb() {
    final parts = _dir.isEmpty ? const <String>[] : _dir.split('/');
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            icon: const Icon(Icons.archive_rounded, size: 16),
            label: Text(_archiveName, overflow: TextOverflow.ellipsis),
            onPressed: () => setState(() => _dir = ''),
          ),
          for (var i = 0; i < parts.length; i++) ...[
            const Icon(Icons.chevron_right_rounded, size: 16),
            TextButton(
              onPressed: () =>
                  setState(() => _dir = parts.sublist(0, i + 1).join('/')),
              child: Text(parts[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_needsPassword) return _passwordPrompt();
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)));
    }
    final nodes =
        _search != null ? _tree.search(_search!) : _tree.children(_dir);
    if (nodes.isEmpty) {
      return Center(
          child: Text(_search != null ? 'Aucun résultat.' : 'Dossier vide.'));
    }
    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (_, i) => _tile(nodes[i]),
    );
  }

  Widget _tile(ArchiveNode n) {
    final selected = _selected.contains(n.path);
    return ListTile(
      selected: selected,
      leading: Icon(
        n.isDirectory
            ? Icons.folder_rounded
            : FileUtils.iconOf(FileUtils.categoryOfPath(n.name), path: n.name),
        color: n.isDirectory ? AppColors.colorFolder : null,
      ),
      title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _search != null
            ? n.path
            : n.isDirectory
                ? '${_tree.children(n.path).length} élément(s)'
                : FileUtils.formatSize(n.size),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _selected.isNotEmpty
          ? Checkbox(value: selected, onChanged: (_) => _toggle(n.path))
          : null,
      onTap: () => _open(n),
      onLongPress: () => _toggle(n.path),
    );
  }

  Widget _selectionBar() {
    final paths = _selected.toList();
    Widget btn(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: _busy ? null : onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
    return SafeArea(
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            btn(Icons.unarchive_rounded, 'Extraire',
                () => _extract(paths, here: false)),
            if (_canEdit) ...[
              btn(Icons.control_point_duplicate_rounded, 'Dupliquer',
                  () => _duplicate(paths)),
              btn(Icons.drive_file_move_rounded, 'Déplacer',
                  () => _move(paths)),
              btn(Icons.drive_file_rename_outline_rounded, 'Renommer',
                  paths.length == 1 ? () => _rename(paths.single) : null),
              btn(Icons.delete_outline_rounded, 'Supprimer',
                  () => _delete(paths)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _passwordPrompt() {
    final ctrl = TextEditingController();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'Mot de passe requis.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              key: const Key('archive-password'),
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
              onSubmitted: (v) {
                _password = v;
                _load();
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                _password = ctrl.text;
                _load();
              },
              child: const Text('Ouvrir'),
            ),
          ],
        ),
      ),
    );
  }
}
