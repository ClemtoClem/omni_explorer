/// @file shortcut_panel.dart
/// @brief Panneau latéral des raccourcis et répertoires prédéfinis.

import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../app/theme/app_theme.dart';

/// @class ShortcutPanel
/// @brief Drawer affichant les emplacements prédéfinis et les raccourcis utilisateur.
class ShortcutPanel extends StatefulWidget {
  final void Function(String path) onNavigate;
  const ShortcutPanel({super.key, required this.onNavigate});

  @override
  State<ShortcutPanel> createState() => _ShortcutPanelState();
}

class _ShortcutPanelState extends State<ShortcutPanel> {
  // Emplacements prédéfinis chargés dynamiquement
  List<_Location> _defaultLocations = [];

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    String base = '/storage/emulated/0';
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null && dirs.isNotEmpty) {
        var p = dirs.first.path;
        while (p.contains('/Android')) { p = p.substring(0, p.lastIndexOf('/')); }
        base = p;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _defaultLocations = [
          _Location(MdiIcons.homeOutline,          'Accueil',          base,               AppColors.accent),
          _Location(Icons.download_rounded,        'Téléchargements', '$base/Download',  AppColors.colorDoc),
          _Location(Icons.image_outlined,          'Images',          '$base/DCIM',      AppColors.colorImage),
          _Location(MdiIcons.filmstrip,            'Vidéos',          '$base/Movies',    AppColors.colorVideo),
          _Location(MdiIcons.musicNote,            'Musique',         '$base/Music',     AppColors.colorAudio),
          _Location(Icons.description_outlined,    'Documents',       '$base/Documents', AppColors.colorDoc),
          _Location(Icons.photo_library_outlined,  'Captures',        '$base/Pictures/Screenshots', AppColors.colorImage),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final trash    = context.watch<TrashService>();
    final theme    = Theme.of(context);

    return Drawer(
      child: Column(
        children: [
          // ── En-tête ────────────────────────────────────────────────────────
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(MdiIcons.folderMultipleOutline,
                    size: 40, color: AppColors.accent),
                const SizedBox(height: 8),
                Text('OmniExplorer',
                    style: theme.textTheme.headlineSmall),
                Text('Emplacements rapides',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // ── Emplacements par défaut ────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                const _SectionTitle('STOCKAGE'),
                ..._defaultLocations.map((loc) => _LocationTile(
                  icon:  loc.icon,
                  label: loc.label,
                  color: loc.color,
                  onTap: () => widget.onNavigate(loc.path),
                )),
                const Divider(height: 16),
                const _SectionTitle('CORBEILLE'),
                _LocationTile(
                  icon:  Icons.delete_outline_rounded,
                  label: 'Corbeille (${trash.items.length})',
                  color: AppColors.error,
                  onTap: () => _openTrash(context, trash),
                ),
                const Divider(height: 16),
                const _SectionTitle('RACCOURCIS'),
                if (settings.shortcuts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Aucun raccourci',
                        style: theme.textTheme.bodySmall),
                  ),
                ...settings.shortcuts.map((s) => _LocationTile(
                  icon:  Icons.bookmark_outline_rounded,
                  label: s.name,
                  color: AppColors.colorFolder,
                  onTap: () => widget.onNavigate(s.path),
                  onDelete: () => settings.removeShortcut(s.id),
                )),
              ],
            ),
          ),
          // ── Bas : thème ───────────────────────────────────────────────────
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              settings.themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded),
            title: Text(
              settings.themeMode == ThemeMode.dark ? 'Mode clair' : 'Mode sombre'),
            onTap: () => settings.setThemeMode(
              settings.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
          ),
        ],
      ),
    );
  }

  void _openTrash(BuildContext ctx, TrashService trash) {
    widget.onNavigate('');
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TrashSheet(trash: trash),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Location {
  final IconData icon;
  final String   label;
  final String   path;
  final Color    color;
  _Location(this.icon, this.label, this.path, this.color);
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(letterSpacing: 1.2)),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _LocationTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall),
      onTap: onTap,
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class _TrashSheet
/// @brief Bottom sheet de gestion de la corbeille.
class _TrashSheet extends StatelessWidget {
  final TrashService trash;
  const _TrashSheet({required this.trash});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: trash,
      child: Consumer<TrashService>(
        builder: (ctx, t, _) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          minChildSize: 0.3,
          expand: false,
          builder: (_, ctrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Corbeille',
                        style: Theme.of(ctx).textTheme.headlineSmall),
                    if (t.items.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_forever_rounded, size: 16),
                        label: const Text('Vider'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.error),
                        onPressed: () async {
                          await t.emptyTrash();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: t.items.isEmpty
                    ? const Center(child: Text('Corbeille vide'))
                    : ListView.builder(
                        controller: ctrl,
                        itemCount: t.items.length,
                        itemBuilder: (_, i) {
                          final item = t.items[i];
                          return ListTile(
                            leading: Icon(
                              item.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined),
                            title: Text(item.originalPath.split('/').last,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              'Supprimé le ${item.deletedAt.day}/${item.deletedAt.month}/${item.deletedAt.year}',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.restore_rounded),
                                  tooltip: 'Restaurer',
                                  onPressed: () => t.restore(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever_rounded),
                                  tooltip: 'Supprimer définitivement',
                                  onPressed: () => t.deletePermanently(item),
                                  color: AppColors.error,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
