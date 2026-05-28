import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart' as p;

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../models/archive_entry.dart';
import '../services/archive_service.dart';

// ─── Écran d'archive ─────────────────────────────────────────────────────────

class ArchiveScreen extends StatefulWidget {
  final String archivePath;
  const ArchiveScreen({super.key, required this.archivePath});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  // ── État ──────────────────────────────────────────────────────────────────
  List<ArchiveEntryInfo> _entries = [];
  final Set<String> _expandedDirs = {};
  final Set<String> _selected     = {};
  bool _selectMode   = false;

  ArchiveType _type = ArchiveType.unknown;
  bool  _loading         = true;
  String? _error;
  bool  _needsPassword   = false;
  String? _password;

  String _searchQuery = '';
  bool   _showSearch  = false;

  _SortField _sortField = _SortField.name;
  bool       _sortAsc   = true;

  double _operationProgress = -1; // -1 = aucune opération en cours

  @override
  void initState() {
    super.initState();
    _type = ArchiveService.detectType(widget.archivePath);
    _load();
  }

  // ── Chargement ────────────────────────────────────────────────────────────

  Future<void> _load({String? password}) async {
    setState(() { _loading = true; _error = null; _needsPassword = false; });
    try {
      final entries = await ArchiveService.listEntries(
        widget.archivePath,
        password: password ?? _password,
      );
      // Trier par chemin complet pour respecter l'arborescence
      entries.sort((a, b) => a.fullPath.compareTo(b.fullPath));
      setState(() { _entries = entries; _loading = false; });
    } on ArchiveOpException catch (e) {
      if (e.isPasswordRequired) {
        setState(() { _loading = false; _needsPassword = true; });
      } else {
        setState(() { _loading = false; _error = e.message; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Entrées visibles (filtre arborescence + recherche) ────────────────────

  List<ArchiveEntryInfo> get _visible {
    var list = _entries.where((e) {
      // Filtre arborescence : affiche seulement si le parent est ouvert
      final parent = e.parentPath;
      if (parent.isNotEmpty && !_expandedDirs.contains(parent)) return false;
      return true;
    }).toList();

    // Filtre recherche : on montre tout en mode recherche
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = _entries
          .where((e) => e.fullPath.toLowerCase().contains(q))
          .toList();
    }

    // Tri
    list.sort((a, b) {
      // Dossiers en premier
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      int cmp;
      switch (_sortField) {
        case _SortField.name: cmp = a.name.compareTo(b.name); break;
        case _SortField.size: cmp = a.size.compareTo(b.size); break;
        case _SortField.date:
          cmp = (a.modified ?? DateTime(0)).compareTo(b.modified ?? DateTime(0));
          break;
        case _SortField.type: cmp = a.ext.compareTo(b.ext); break;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _extractAll() async {
    final dest = await _pickDestDir();
    if (dest == null) return;
    await _runOp(() => ArchiveService.extractAll(
      widget.archivePath, dest,
      password: _password,
      onProgress: (v) => setState(() => _operationProgress = v),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extrait dans $dest')));
    }
  }

  Future<void> _extractSelected() async {
    if (_selected.isEmpty) return;
    final dest = await _pickDestDir();
    if (dest == null) return;
    await _runOp(() async {
      var done = 0;
      for (final ep in _selected) {
        await ArchiveService.extractEntry(
            widget.archivePath, ep, dest, password: _password);
        done++;
        setState(() => _operationProgress = done / _selected.length);
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrées extraites.')));
    }
    setState(() { _selected.clear(); _selectMode = false; });
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final paths = result.files.map((f) => f.path!).toList();
    await _runOp(() async {
      var done = 0;
      for (final path in paths) {
        await ArchiveService.addFilesToZip(widget.archivePath, [path]);
        done++;
        setState(() => _operationProgress = done / paths.length);
      }
    });
    await _load();
  }

  Future<void> _removeSelected() async {
    if (_selected.isEmpty) return;
    final ok = await _confirm(
      'Supprimer ${_selected.length} entrée(s) de l\'archive ?',
    );
    if (ok != true) return;
    await _runOp(() => ArchiveService.removeFromZip(
      widget.archivePath, _selected.toList()));
    await _load();
    setState(() { _selected.clear(); _selectMode = false; });
  }

  Future<void> _managePassword(_PasswordAction action) async {
    switch (action) {
      case _PasswordAction.set:
        await _showSetPasswordDialog();
        break;
      case _PasswordAction.remove:
        await _showRemovePasswordDialog();
        break;
      case _PasswordAction.change:
        await _showChangePasswordDialog();
        break;
    }
  }

  Future<void> _showSetPasswordDialog() async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Définir un mot de passe',
        ctrl1: ctrl1, label1: 'Nouveau mot de passe',
        ctrl2: ctrl2, label2: 'Confirmer',
      ),
    );
    if (ok != true) return;
    if (ctrl1.text != ctrl2.text) {
      _showError('Les mots de passe ne correspondent pas.');
      return;
    }
    await _runOp(() => ArchiveService.setPassword(widget.archivePath, ctrl1.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe défini.')));
    }
  }

  Future<void> _showRemovePasswordDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Supprimer le mot de passe',
        ctrl1: ctrl, label1: 'Mot de passe actuel',
      ),
    );
    if (ok != true) return;
    await _runOp(() => ArchiveService.removePassword(widget.archivePath, ctrl.text));
    _password = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe supprimé.')));
    }
    await _load();
  }

  Future<void> _showChangePasswordDialog() async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    final ctrl3 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Modifier le mot de passe',
        ctrl1: ctrl1, label1: 'Mot de passe actuel',
        ctrl2: ctrl2, label2: 'Nouveau mot de passe',
        ctrl3: ctrl3, label3: 'Confirmer le nouveau',
      ),
    );
    if (ok != true) return;
    if (ctrl2.text != ctrl3.text) {
      _showError('Les mots de passe ne correspondent pas.');
      return;
    }
    await _runOp(() async {
      await ArchiveService.removePassword(widget.archivePath, ctrl1.text);
      await ArchiveService.setPassword(widget.archivePath, ctrl2.text);
    });
    _password = ctrl2.text;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié.')));
    }
  }

  Future<void> _unlockWithPassword() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Archive protégée',
        ctrl1: ctrl, label1: 'Mot de passe',
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return;
    _password = ctrl.text;
    await _load(password: ctrl.text);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _runOp(Future<void> Function() op) async {
    setState(() => _operationProgress = 0);
    try {
      await op();
    } on ArchiveOpException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _operationProgress = -1);
    }
  }

  Future<String?> _pickDestDir() {
    final ctrl = TextEditingController(
      text: p.dirname(widget.archivePath),
    );
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dossier de destination'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/chemin/du/dossier'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final path = ctrl.text.trim();
              if (path.isNotEmpty) Navigator.pop(context, path);
            },
            child: const Text('Choisir'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleExpand(ArchiveEntryInfo entry) {
    setState(() {
      final key = entry.fullPath;
      if (_expandedDirs.contains(key)) {
        // Fermer aussi tous les sous-dossiers
        _expandedDirs.removeWhere((k) => k == key || k.startsWith('$key/'));
      } else {
        _expandedDirs.add(key);
      }
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(path);
      }
    });
  }

  void _enterSelectMode(String path) {
    setState(() {
      _selectMode = true;
      _selected.add(path);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          if (_showSearch) _buildSearchBar(theme),
          if (_operationProgress >= 0) LinearProgressIndicator(value: _operationProgress),
          const Divider(height: 1),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(theme),
      floatingActionButton: (!_selectMode && !_loading && _error == null && !_needsPassword)
          ? _buildFab()
          : null,
    );
  }

  AppBar _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  p.basename(widget.archivePath),
                  overflow: TextOverflow.ellipsis,
                  style: theme.appBarTheme.titleTextStyle,
                ),
              ),
              const SizedBox(width: 8),
              _FormatBadge(type: _type),
              if (_password != null) ...[
                const SizedBox(width: 6),
                Icon(MdiIcons.lockOpen, size: 14, color: AppColors.success),
              ],
            ],
          ),
          if (!_loading && _error == null && !_needsPassword)
            Text(
              '${_entries.length} élément${_entries.length > 1 ? "s" : ""}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_showSearch ? Icons.search_off : Icons.search_rounded),
          tooltip: 'Rechercher',
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) _searchQuery = '';
          }),
        ),
        _buildSortBtn(),
        if (!_loading && _error == null && !_needsPassword)
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _MenuAction.info,
                child: _MenuItem(Icons.info_outline_rounded, 'Informations'),
              ),
              if (_type.supportsPassword) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: _MenuAction.setPassword,
                  child: _MenuItem(Icons.lock_outline_rounded, 'Définir un mot de passe'),
                ),
                if (_password != null)
                  const PopupMenuItem(
                    value: _MenuAction.removePassword,
                    child: _MenuItem(Icons.lock_open_rounded, 'Supprimer le mot de passe'),
                  ),
                if (_password != null)
                  const PopupMenuItem(
                    value: _MenuAction.changePassword,
                    child: _MenuItem(Icons.lock_reset_rounded, 'Modifier le mot de passe'),
                  ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _MenuAction.selectAll,
                child: _MenuItem(Icons.select_all_rounded, 'Tout sélectionner'),
              ),
              const PopupMenuItem(
                value: _MenuAction.refresh,
                child: _MenuItem(Icons.refresh_rounded, 'Actualiser'),
              ),
            ],
          ),
      ],
    );
  }

  void _onMenuAction(_MenuAction action) {
    switch (action) {
      case _MenuAction.info:        _showInfo(); break;
      case _MenuAction.setPassword: _managePassword(_PasswordAction.set); break;
      case _MenuAction.removePassword: _managePassword(_PasswordAction.remove); break;
      case _MenuAction.changePassword: _managePassword(_PasswordAction.change); break;
      case _MenuAction.selectAll:
        setState(() {
          _selectMode = true;
          _selected.addAll(_entries.map((e) => e.fullPath));
        });
        break;
      case _MenuAction.refresh: _load(); break;
    }
  }

  Widget _buildSortBtn() {
    return PopupMenuButton<_SortField>(
      icon: const Icon(Icons.sort_rounded),
      tooltip: 'Trier',
      onSelected: (f) => setState(() {
        if (_sortField == f) { _sortAsc = !_sortAsc; } else { _sortField = f; _sortAsc = true; }
      }),
      itemBuilder: (_) => _SortField.values.map((f) {
        final labels = {
          _SortField.name: 'Nom',
          _SortField.size: 'Taille',
          _SortField.date: 'Date',
          _SortField.type: 'Type',
        };
        return PopupMenuItem(
          value: f,
          child: Row(children: [
            Icon(_sortField == f
                ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.sort, size: 16),
            const SizedBox(width: 8),
            Text(labels[f]!),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Rechercher dans l\'archive…',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          isDense: true,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_needsPassword) {
      return _buildPasswordPrompt(theme);
    }
    if (_error != null) {
      return _buildError(theme);
    }
    final entries = _visible;
    if (entries.isEmpty) {
      return Center(
        child: Text('Archive vide', style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (_, i) => _buildEntry(entries[i], theme),
    );
  }

  Widget _buildPasswordPrompt(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MdiIcons.archiveLock, size: 56, color: AppColors.warning),
            const SizedBox(height: 16),
            Text('Archive protégée par mot de passe',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Entrer le mot de passe'),
              onPressed: _unlockWithPassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56,
                color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(ArchiveEntryInfo entry, ThemeData theme) {
    final isSelected = _selected.contains(entry.fullPath);
    final isExpanded = _expandedDirs.contains(entry.fullPath);
    final hasChildren = entry.isDirectory &&
        _entries.any((e) => e.parentPath == entry.fullPath);

    final indent = _searchQuery.isNotEmpty ? 0.0 : entry.depth * 16.0;
    final color  = entry.isDirectory
        ? AppColors.colorFolder
        : FileUtils.colorOf(_categoryFromExt(entry.ext));

    return InkWell(
      onTap: () {
        if (_selectMode) {
          _toggleSelect(entry.fullPath);
        } else if (entry.isDirectory) {
          _toggleExpand(entry);
        }
      },
      onLongPress: () => _enterSelectMode(entry.fullPath),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: EdgeInsets.fromLTRB(12 + indent, 6, 8, 6),
        child: Row(
          children: [
            // Expand indicator
            if (entry.isDirectory && hasChildren && _searchQuery.isEmpty)
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 16,
                color: theme.iconTheme.color,
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 4),
            // Select checkbox
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? AppColors.accent : theme.iconTheme.color,
                  size: 20,
                ),
              ),
            // Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                entry.isDirectory
                    ? (isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded)
                    : FileUtils.iconOf(_categoryFromExt(entry.ext),
                        path: entry.name),
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            // Name + metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: entry.isDirectory ? FontWeight.w600 : null,
                    ),
                  ),
                  if (!entry.isDirectory)
                    Row(children: [
                      Text(FileUtils.formatSize(entry.size),
                          style: theme.textTheme.bodySmall),
                      if (entry.compressionRatio > 0) ...[
                        Text('  •  ', style: theme.textTheme.bodySmall),
                        Text(
                          '${(entry.compressionRatio * 100).toStringAsFixed(0)}% économisé',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.success),
                        ),
                      ],
                      if (entry.modified != null) ...[
                        Text('  •  ', style: theme.textTheme.bodySmall),
                        Text(FileUtils.formatDate(entry.modified!),
                            style: theme.textTheme.bodySmall),
                      ],
                    ]),
                ],
              ),
            ),
            // Context actions
            if (!_selectMode)
              _EntryMenu(
                entry: entry,
                archivePath: widget.archivePath,
                canRemove: _type.supportsInPlaceEdit,
                password: _password,
                onExtract: () {
                  setState(() { _selectMode = true; });
                  _toggleSelect(entry.fullPath);
                  _extractSelected();
                },
                onRemove: () {
                  setState(() { _selectMode = true; });
                  _toggleSelect(entry.fullPath);
                  _removeSelected();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomBar(ThemeData theme) {
    if (!_selectMode || _selected.isEmpty) return null;
    return SafeArea(
      child: Container(
        height: 56,
        color: theme.colorScheme.surface,
        child: Row(
          children: [
            _BarBtn(
              Icons.close_rounded, 'Annuler',
              () => setState(() { _selectMode = false; _selected.clear(); }),
            ),
            _BarBtn(
              Icons.download_rounded, 'Extraire (${_selected.length})',
              _extractSelected,
            ),
            if (_type.supportsInPlaceEdit)
              _BarBtn(
                Icons.delete_outline_rounded, 'Supprimer',
                _removeSelected,
                color: AppColors.error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    if (!_type.supportsInPlaceEdit) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.download_rounded),
        label: const Text('Extraire tout'),
        onPressed: _extractAll,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'add',
          tooltip: 'Ajouter des fichiers',
          onPressed: _addFiles,
          child: const Icon(Icons.add_rounded),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'extract',
          icon: const Icon(Icons.download_rounded),
          label: const Text('Extraire tout'),
          onPressed: _extractAll,
        ),
      ],
    );
  }

  void _showInfo() {
    final totalSize = _entries.fold(0, (s, e) => s + e.size);
    final archiveFile = File(widget.archivePath);
    final archiveSize = archiveFile.existsSync() ? archiveFile.lengthSync() : 0;
    final ratio = totalSize > 0 ? 1.0 - archiveSize / totalSize : 0.0;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Informations'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InfoRow('Fichier', p.basename(widget.archivePath)),
            _InfoRow('Format', _type.label),
            _InfoRow('Entrées', '${_entries.length}'),
            _InfoRow('Taille originale', FileUtils.formatSize(totalSize)),
            _InfoRow('Taille archive', FileUtils.formatSize(archiveSize)),
            if (ratio > 0)
              _InfoRow('Compression', '${(ratio * 100).toStringAsFixed(1)}%'),
            if (_password != null)
              const _InfoRow('Chiffrement', 'Oui (déverrouillé)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  // Mappe une extension vers une FileCategory approximative pour l'icône
  static FileCategory _categoryFromExt(String ext) {
    if (ext.isEmpty) return FileCategory.unknown;
    if (AppConstants.codeExtensions.contains(ext)) return FileCategory.code;
    if (AppConstants.textExtensions.contains(ext)) return FileCategory.text;
    if (AppConstants.markdownExtensions.contains(ext)) return FileCategory.markdown;
    if (AppConstants.imageExtensions.contains(ext)) return FileCategory.image;
    if (AppConstants.audioExtensions.contains(ext)) return FileCategory.audio;
    if (AppConstants.videoExtensions.contains(ext)) return FileCategory.video;
    if (AppConstants.pdfExtensions.contains(ext)) return FileCategory.pdf;
    if (AppConstants.archiveExtensions.contains(ext)) return FileCategory.archive;
    return FileCategory.binary;
  }
}

// ─── Widgets auxiliaires ──────────────────────────────────────────────────────

enum _SortField  { name, size, date, type }
enum _MenuAction { info, setPassword, removePassword, changePassword, selectAll, refresh }
enum _PasswordAction { set, remove, change }

class _FormatBadge extends StatelessWidget {
  final ArchiveType type;
  const _FormatBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: type.color.withValues(alpha: 0.4)),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: type.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EntryMenu extends StatelessWidget {
  final ArchiveEntryInfo entry;
  final String archivePath;
  final bool canRemove;
  final String? password;
  final VoidCallback onExtract;
  final VoidCallback onRemove;

  const _EntryMenu({
    required this.entry,
    required this.archivePath,
    required this.canRemove,
    required this.password,
    required this.onExtract,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_EntryAction>(
      icon: Icon(Icons.more_vert_rounded,
          size: 18, color: Theme.of(context).iconTheme.color),
      onSelected: (a) {
        if (a == _EntryAction.extract) onExtract();
        if (a == _EntryAction.remove) onRemove();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _EntryAction.extract,
          child: _MenuItem(Icons.download_rounded, 'Extraire'),
        ),
        if (canRemove)
          const PopupMenuItem(
            value: _EntryAction.remove,
            child: _MenuItem(Icons.delete_outline_rounded, 'Supprimer',
                color: AppColors.error),
          ),
      ],
    );
  }
}

enum _EntryAction { extract, remove }

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MenuItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).iconTheme.color;
    return Row(children: [
      Icon(icon, size: 18, color: c),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: c)),
    ]);
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _BarBtn(this.icon, this.label, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final String title;
  final TextEditingController ctrl1;
  final String label1;
  final TextEditingController? ctrl2;
  final String? label2;
  final TextEditingController? ctrl3;
  final String? label3;

  const _PasswordDialog({
    required this.title,
    required this.ctrl1,
    required this.label1,
    this.ctrl2, this.label2,
    this.ctrl3, this.label3,
  });

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(widget.ctrl1, widget.label1),
          if (widget.ctrl2 != null) ...[
            const SizedBox(height: 12),
            _field(widget.ctrl2!, widget.label2!),
          ],
          if (widget.ctrl3 != null) ...[
            const SizedBox(height: 12),
            _field(widget.ctrl3!, widget.label3!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Valider'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: _obscure,
      autofocus: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ─── Dialogue de compression (utilisé depuis l'explorateur) ──────────────────

/// Affiche un dialogue pour créer une nouvelle archive à partir de [sourcePaths].
/// Retourne `true` si l'archive a été créée avec succès.
Future<bool> showCompressDialog(
  BuildContext context, {
  required List<String> sourcePaths,
  required String destDir,
  void Function()? onDone,
}) async {
  return await showDialog<bool>(
    context: context,
    builder: (_) => _CompressDialog(
      sourcePaths: sourcePaths,
      destDir: destDir,
    ),
  ) ?? false;
}

class _CompressDialog extends StatefulWidget {
  final List<String> sourcePaths;
  final String destDir;
  const _CompressDialog({required this.sourcePaths, required this.destDir});

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  _CompressFormat _format = _CompressFormat.zip;
  final _nameCtrl = TextEditingController();
  final _pwCtrl   = TextEditingController();
  bool _withPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.sourcePaths.length == 1
        ? p.basenameWithoutExtension(widget.sourcePaths.first)
        : 'archive';
    _nameCtrl.text = base;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Compresser'),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom de l\'archive'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text('Format', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _CompressFormat.values.map((f) {
                    return ChoiceChip(
                      label: Text(f.label),
                      selected: _format == f,
                      onSelected: (_) => setState(() => _format = f),
                    );
                  }).toList(),
                ),
                if (_format == _CompressFormat.zip || _format == _CompressFormat.sevenZip) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Protéger par mot de passe'),
                    value: _withPassword,
                    onChanged: (v) => setState(() => _withPassword = v!),
                  ),
                  if (_withPassword)
                    TextField(
                      controller: _pwCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mot de passe'),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ],
              ],
            ),
      actions: _loading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _create,
                child: const Text('Créer'),
              ),
            ],
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final ext  = _format.ext;
    final dest = p.join(widget.destDir, '$name.$ext');
    final pw   = (_withPassword && _pwCtrl.text.isNotEmpty) ? _pwCtrl.text : null;
    setState(() { _loading = true; _error = null; });
    try {
      switch (_format) {
        case _CompressFormat.zip:
          await ArchiveService.createZip(dest, widget.sourcePaths, password: pw);
          break;
        case _CompressFormat.tarGz:
          await ArchiveService.createTarGz(dest, widget.sourcePaths);
          break;
        case _CompressFormat.sevenZip:
          await ArchiveService.create7z(dest, widget.sourcePaths, password: pw);
          break;
      }
      if (mounted) Navigator.pop(context, true);
    } on ArchiveOpException catch (e) {
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }
}

enum _CompressFormat {
  zip('ZIP', 'zip'),
  tarGz('TAR.GZ', 'tar.gz'),
  sevenZip('7Z', '7z');

  final String label;
  final String ext;
  const _CompressFormat(this.label, this.ext);
}
