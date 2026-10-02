/* @file features/home/screens/storage_home_screen.dart */

/// @file storage_home_screen.dart
/// @brief Première page : aperçu des espaces de stockage (occupé / libre,
/// barre de progression en GB) et raccourcis vers les répertoires courants.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/file_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/utils/storage_stats.dart';
import '../../file_explorer/screens/file_explorer_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../home/screens/feature_launcher_screen.dart';
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

class StorageHomeScreen extends StatefulWidget {
  const StorageHomeScreen({super.key});

  @override
  State<StorageHomeScreen> createState() => _StorageHomeScreenState();
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

class _StorageHomeScreenState extends State<StorageHomeScreen> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stockage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.apps_rounded),
            tooltip: 'Fonctionnalités',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FeatureLauncherScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Paramètres',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
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
    final shortcuts = _buildShortcuts(primary.path);

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

        // ── Favoris utilisateur ─────────────────────────────────────────────
        Consumer<SettingsService>(
          builder: (context, settings, _) {
            if (settings.shortcuts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Favoris', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final s in settings.shortcuts)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.bookmark_outline_rounded,
                          color: AppColors.colorFolder),
                      title: Text(s.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        tooltip: 'Retirer des favoris',
                        onPressed: () => settings.removeShortcut(s.id),
                      ),
                      onTap: () => _openExplorer(s.path),
                    ),
                  ),
              ],
            );
          },
        ),

        // ── Raccourcis standards ────────────────────────────────────────────
        if (shortcuts.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Raccourcis', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _ShortcutGrid(shortcuts: shortcuts, onOpen: _openExplorer),
        ],

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

  /// Construit la liste des raccourcis en ne gardant que les dossiers
  /// réellement présents sur la machine.
  List<_Shortcut> _buildShortcuts(String root) {
    _Shortcut? first(
        List<String> paths, String label, IconData icon, Color color) {
      for (final path in paths) {
        if (Directory(path).existsSync()) {
          return _Shortcut(label: label, icon: icon, color: color, path: path);
        }
      }
      return null;
    }

    final candidates = <_Shortcut?>[
      first(
        [
          p.join(root, 'DCIM'),
          p.join(root, 'Pictures'),
          p.join(root, 'Images')
        ],
        'Images',
        Icons.image_rounded,
        AppColors.colorImage,
      ),
      first(
        [p.join(root, 'Movies'), p.join(root, 'Videos')],
        'Vidéos',
        Icons.videocam_rounded,
        AppColors.colorVideo,
      ),
      first(
        [p.join(root, 'Documents')],
        'Documents',
        Icons.description_rounded,
        AppColors.colorDoc,
      ),
      first(
        [p.join(root, 'Music')],
        'Musique',
        Icons.music_note_rounded,
        AppColors.colorAudio,
      ),
      first(
        [p.join(root, 'Download'), p.join(root, 'Downloads')],
        'Téléchargements',
        Icons.download_rounded,
        AppColors.colorDoc,
      ),
      if (Platform.isAndroid)
        first(['/system/app', '/system/priv-app'], 'Apps', Icons.apps_rounded,
            AppColors.accent),
      if (Platform.isLinux)
        first(['/usr/share/applications', '/usr/bin'], 'Apps',
            Icons.apps_rounded, AppColors.accent),
    ];
    return [
      ...candidates.whereType<_Shortcut>(),
      // Accès direct à la racine du stockage principal.
      _Shortcut(
        label: 'Tout',
        icon: Icons.folder_special_rounded,
        color: AppColors.colorFolder,
        path: root,
      ),
    ];
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

class _Shortcut {
  final String label;
  final IconData icon;
  final Color color;
  final String path;

  const _Shortcut({
    required this.label,
    required this.icon,
    required this.color,
    required this.path,
  });
}

class _ShortcutGrid extends StatelessWidget {
  final List<_Shortcut> shortcuts;
  final void Function(String path) onOpen;

  const _ShortcutGrid({required this.shortcuts, required this.onOpen});

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
          itemCount: shortcuts.length,
          itemBuilder: (_, i) {
            final s = shortcuts[i];
            return _ShortcutTile(shortcut: s, onTap: () => onOpen(s.path));
          },
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final _Shortcut shortcut;
  final VoidCallback onTap;

  const _ShortcutTile({required this.shortcut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? shortcut.color.withValues(alpha: 0.15)
          : shortcut.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: shortcut.color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(shortcut.icon, color: shortcut.color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                shortcut.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
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
