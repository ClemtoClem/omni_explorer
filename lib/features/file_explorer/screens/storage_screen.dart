/* @file features/home/screens/storage_home_screen.dart */

/// @file storage_home_screen.dart
/// @brief Première page : aperçu des espaces de stockage (occupé / libre,
/// barre de progression en GB) et raccourcis de répertoire personnalisables
/// (ajout, modification du nom / répertoire / icône / couleur, ordre,
/// retrait).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/file_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/utils/storage_stats.dart';
import '../../file_explorer/screens/file_explorer_screen.dart';
import '../widgets/shortcut_editor_dialog.dart';
import '../widgets/trash_sheet.dart';

// ── Carte Corbeille ──────────────────────────────────────────────────────────

class _TrashCard extends StatelessWidget {
  final TrashService trash;
  final VoidCallback onOpen;

  const _TrashCard({required this.trash, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final count = trash.items.length;
    final isEmpty = count == 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Corbeille', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      isEmpty
                          ? 'Aucun élément'
                          : '$count élément${count > 1 ? "s" : ""} · '
                              '${_formatGb(trash.totalSize)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpen,
                child: Text(isEmpty ? 'Ouvrir' : 'Gérer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageEntry {
  final String path;
  final String label;
  final bool isExternal;
  final StorageStats stats;

  const _StorageEntry({
    required this.path,
    required this.label,
    required this.isExternal,
    required this.stats,
  });
}

class _StorageScreenState extends State<StorageScreen> {
  bool _loading = true;
  List<_StorageEntry> _storages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final list = await FileService.instance.getAvailableStorages();
    final entries = <_StorageEntry>[];
    for (final s in list) {
      final stats = await getStorageStats(s.path);
      entries.add(_StorageEntry(
        path: s.path,
        label: s.label,
        isExternal: s.isExternal,
        stats: stats,
      ));
    }
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    if (entries.isNotEmpty && settings.needsDefaultShortcuts) {
      await settings
          .seedDefaultShortcuts(_defaultShortcuts(entries.first.path));
      if (!mounted) return;
    }
    setState(() {
      _storages = entries;
      _loading = false;
    });
  }

  void _openExplorer(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FileExplorerScreen(initialPath: path)),
    );
  }

  // ── Raccourcis ─────────────────────────────────────────────────────────────

  void _openShortcut(ShortcutItem s) {
    final type = FileSystemEntity.typeSync(s.path);
    if (type == FileSystemEntityType.notFound) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${s.name} » : répertoire introuvable'),
        action: SnackBarAction(
            label: 'Modifier', onPressed: () => _editShortcut(s)),
      ));
      return;
    }
    // Anciens favoris pointant sur un fichier : ouvrir son dossier.
    _openExplorer(
        type == FileSystemEntityType.directory ? s.path : p.dirname(s.path));
  }

  Future<void> _addShortcut() async {
    final draft = await showShortcutEditor(context,
        initialPath: _storages.isEmpty ? null : _storages.first.path);
    if (draft == null || !mounted) return;
    final added = await context.read<SettingsService>().addShortcut(
          draft.name,
          draft.path,
          iconName: draft.iconName,
          colorValue: draft.colorValue,
        );
    if (!added) _snack('Ce répertoire a déjà un raccourci');
  }

  Future<void> _editShortcut(ShortcutItem s) async {
    final draft = await showShortcutEditor(context, initial: s);
    if (draft == null || !mounted) return;
    final ok = await context.read<SettingsService>().updateShortcut(s.copyWith(
          name: draft.name,
          path: draft.path,
          iconName: draft.iconName,
          colorValue: draft.colorValue,
        ));
    if (!ok) _snack('Un autre raccourci pointe déjà sur ce répertoire');
  }

  Future<void> _removeShortcut(ShortcutItem s) async {
    final settings = context.read<SettingsService>();
    final index = settings.shortcuts.indexOf(s);
    await settings.removeShortcut(s.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Raccourci « ${s.name} » retiré'),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () async {
          await settings.addShortcut(s.name, s.path,
              iconName: s.iconName, colorValue: s.colorValue);
          // Remettre le raccourci à sa place d'origine.
          final back = settings.shortcuts.last;
          await settings.moveShortcut(
              back.id, index - (settings.shortcuts.length - 1));
        },
      ),
    ));
  }

  Future<void> _shortcutActions(ShortcutItem s) async {
    final settings = context.read<SettingsService>();
    final index = settings.shortcuts.indexOf(s);
    final last = settings.shortcuts.length - 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(shortcutIconOf(s), color: shortcutColorOf(s)),
              title: Text(s.name),
              subtitle:
                  Text(s.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Modifier'),
              onTap: () => Navigator.pop(sheetCtx, 'edit'),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_back_rounded),
                title: const Text('Déplacer avant'),
                onTap: () => Navigator.pop(sheetCtx, 'before'),
              ),
            if (index < last)
              ListTile(
                leading: const Icon(Icons.arrow_forward_rounded),
                title: const Text('Déplacer après'),
                onTap: () => Navigator.pop(sheetCtx, 'after'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text('Retirer',
                  style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(sheetCtx, 'remove'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        await _editShortcut(s);
      case 'before':
        await settings.moveShortcut(s.id, -1);
      case 'after':
        await settings.moveShortcut(s.id, 1);
      case 'remove':
        await _removeShortcut(s);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stockage'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _storages.isEmpty ? _empty(theme) : _content(theme),
            ),
    );
  }

  Widget _empty(ThemeData theme) => ListView(
        children: [
          const SizedBox(height: 200),
          Center(
            child: Text(
              'Aucun espace de stockage détecté',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );

  Widget _content(ThemeData theme) {
    final primary = _storages.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Vue d'ensemble (anneau) ─────────────────────────────────────────
        _RingCard(entry: primary),
        const SizedBox(height: 16),

        // ── Cartes de chaque espace de stockage ─────────────────────────────
        for (final e in _storages) ...[
          _StorageCard(entry: e, onExplore: () => _openExplorer(e.path)),
          const SizedBox(height: 12),
        ],

        // ── Raccourcis (personnalisables) ───────────────────────────────────
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: Text('Raccourcis', style: theme.textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Ajouter un raccourci',
              onPressed: _addShortcut,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Consumer<SettingsService>(
          builder: (context, settings, _) => _ShortcutGrid(
            shortcuts: settings.shortcuts,
            onOpen: _openShortcut,
            onActions: _shortcutActions,
            onAdd: _addShortcut,
          ),
        ),
        if (context.watch<SettingsService>().shortcuts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Appui long sur un raccourci : modifier, déplacer, retirer.',
              style: theme.textTheme.bodySmall,
            ),
          ),

        // ── Corbeille ───────────────────────────────────────────────────────
        const SizedBox(height: 20),
        Consumer<TrashService>(
          builder: (context, trash, _) => _TrashCard(
            trash: trash,
            onOpen: () => showTrashSheet(context),
          ),
        ),
      ],
    );
  }

  /// Raccourcis proposés au premier affichage, limités aux dossiers
  /// réellement présents sur la machine. Ensuite, l'utilisateur les gère.
  List<ShortcutItem> _defaultShortcuts(String root) {
    ShortcutItem? first(
        List<String> paths, String name, String icon, Color color) {
      for (final path in paths) {
        if (Directory(path).existsSync()) {
          return ShortcutItem(
            id: '',
            name: name,
            path: path,
            iconName: icon,
            colorValue: color.toARGB32(),
          );
        }
      }
      return null;
    }

    return [
      first(
        [
          p.join(root, 'DCIM'),
          p.join(root, 'Pictures'),
          p.join(root, 'Images')
        ],
        'Images',
        'image',
        AppColors.colorImage,
      ),
      first([p.join(root, 'Movies'), p.join(root, 'Videos')], 'Vidéos', 'video',
          AppColors.colorVideo),
      first([p.join(root, 'Documents')], 'Documents', 'document',
          AppColors.colorDoc),
      first([p.join(root, 'Music')], 'Musique', 'music', AppColors.colorAudio),
      first([p.join(root, 'Download'), p.join(root, 'Downloads')],
          'Téléchargements', 'download', AppColors.colorDoc),
      if (Platform.isAndroid)
        first(['/system/app', '/system/priv-app'], 'Apps', 'apps',
            AppColors.info),
      if (Platform.isLinux)
        first(['/usr/share/applications', '/usr/bin'], 'Apps', 'apps',
            AppColors.info),
      // Accès direct à la racine du stockage principal.
      first([root], 'Tout', 'folder_special', AppColors.colorFolder),
    ].whereType<ShortcutItem>().toList();
  }
}

// ── Carte anneau (espace principal) ──────────────────────────────────────────

class _RingCard extends StatelessWidget {
  final _StorageEntry entry;
  const _RingCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final stats = entry.stats;
    final usedPct = stats.hasData ? (stats.usedRatio * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.08)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _pill(theme, 'Occupé', _formatGb(stats.usedBytes)),
              const Spacer(),
              _pill(theme, 'Libre', _formatGb(stats.freeBytes)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: stats.hasData ? stats.usedRatio : 0,
                    strokeWidth: 14,
                    strokeCap: StrokeCap.round,
                    backgroundColor: accent.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatGb(stats.totalBytes),
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text('$usedPct % utilisé',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Carte d'un espace de stockage ────────────────────────────────────────────

class _StorageCard extends StatelessWidget {
  final _StorageEntry entry;
  final VoidCallback onExplore;
  const _StorageCard({required this.entry, required this.onExplore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final stats = entry.stats;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? accent.withValues(alpha: 0.08)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  entry.isExternal
                      ? Icons.sd_card_rounded
                      : Icons.storage_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(entry.label, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stats.hasData ? stats.usedRatio : 0,
              minHeight: 8,
              backgroundColor: accent.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  stats.hasData
                      ? 'Libre : ${_formatGb(stats.freeBytes)} sur '
                          '${_formatGb(stats.totalBytes)}'
                      : 'Espace non disponible',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: onExplore, child: const Text('Explorer')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Grille de raccourcis ─────────────────────────────────────────────────────

class _ShortcutGrid extends StatelessWidget {
  final List<ShortcutItem> shortcuts;
  final void Function(ShortcutItem) onOpen;
  final void Function(ShortcutItem) onActions;
  final VoidCallback onAdd;

  const _ShortcutGrid({
    required this.shortcuts,
    required this.onOpen,
    required this.onActions,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          // Dernière case : ajout d'un raccourci.
          itemCount: shortcuts.length + 1,
          itemBuilder: (_, i) {
            if (i == shortcuts.length) {
              return _ShortcutTile(
                label: 'Ajouter',
                icon: Icons.add_rounded,
                color: Theme.of(context).colorScheme.primary,
                onTap: onAdd,
              );
            }
            final s = shortcuts[i];
            return _ShortcutTile(
              key: ValueKey(s.id),
              label: s.name,
              icon: shortcutIconOf(s),
              color: shortcutColorOf(s),
              missing: !FileSystemEntity.isDirectorySync(s.path) &&
                  !File(s.path).existsSync(),
              onTap: () => onOpen(s),
              onLongPress: () => onActions(s),
            );
          },
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool missing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ShortcutTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.missing = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Opacity(
      opacity: missing ? 0.45 : 1,
      child: Material(
        color: isDark
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(missing ? Icons.folder_off_rounded : icon,
                      color: color, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Formatage ────────────────────────────────────────────────────────────────

String _formatGb(int bytes) {
  if (bytes <= 0) return '—';
  const gb = 1024 * 1024 * 1024;
  final value = bytes / gb;
  if (value >= 1) return '${value.toStringAsFixed(0)} GB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(0)} MB';
}
