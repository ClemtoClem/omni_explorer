/// @file shortcut_panel.dart
/// @brief Panneau latéral des raccourcis et répertoires prédéfinis.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/file_operations_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../app/theme/app_theme.dart';
import 'file_op_dialogs.dart';

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
    final locs = await _platformLocations();
    if (mounted) setState(() => _defaultLocations = locs);
  }

  Future<List<_Location>> _platformLocations() async {
    if (Platform.isAndroid) return _androidLocations();
    if (Platform.isLinux)   return _filter(_linuxLocations());
    if (Platform.isWindows) return _filter(_windowsLocations());
    if (Platform.isMacOS)   return _filter(_macosLocations());
    if (Platform.isIOS)     return _iosLocations();
    return const [];
  }

  // Garde uniquement les répertoires qui existent sur le disque.
  List<_Location> _filter(List<_Location> locs) =>
      locs.where((l) => Directory(l.path).existsSync()).toList();

  // ── Android ───────────────────────────────────────────────────────────────

  Future<List<_Location>> _androidLocations() async {
    String base = '/storage/emulated/0';
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null && dirs.isNotEmpty) {
        var root = dirs.first.path;
        while (root.contains('/Android')) {
          root = root.substring(0, root.lastIndexOf('/'));
        }
        base = root;
      }
    } catch (_) {}

    return _filter([
      _Location(MdiIcons.homeOutline,         'Accueil',         base,                              AppColors.accent),
      _Location(Icons.download_rounded,       'Téléchargements', p.join(base, 'Download'),          AppColors.colorDoc),
      _Location(Icons.image_outlined,         'Images',          p.join(base, 'DCIM'),              AppColors.colorImage),
      _Location(MdiIcons.filmstrip,           'Vidéos',          p.join(base, 'Movies'),            AppColors.colorVideo),
      _Location(MdiIcons.musicNote,           'Musique',         p.join(base, 'Music'),             AppColors.colorAudio),
      _Location(Icons.description_outlined,   'Documents',       p.join(base, 'Documents'),         AppColors.colorDoc),
      _Location(Icons.photo_library_outlined, 'Captures',        p.join(base, 'Pictures', 'Screenshots'), AppColors.colorImage),
    ]);
  }

  // ── Linux ─────────────────────────────────────────────────────────────────

  // Fonction utilitaire pour lire le fichier de configuration XDG
  Map<String, String> _loadXdgUserDirs(String home) {
    final configPath = p.join(home, '.config', 'user-dirs.dirs');
    final file = File(configPath);
    final dirs = <String, String>{};

    if (file.existsSync()) {
      final lines = file.readAsLinesSync();
      for (var line in lines) {
        line = line.trim();
        // On ignore les commentaires et on cherche les lignes d'assignation
        if (line.startsWith('XDG_') && line.contains('=')) {
          final parts = line.split('=');
          final key = parts[0].trim();
          // On récupère la valeur, on retire les guillemets et on remplace la variable $HOME
          var value = parts.sublist(1).join('=').replaceAll('"', '').trim();
          value = value.replaceAll(r'$HOME', home);
          dirs[key] = value;
        }
      }
    }
    return dirs;
  }

  List<_Location> _linuxLocations() {
    final home = Platform.environment['HOME'] ?? '/home';
    
    // On charge les répertoires XDG depuis le fichier Linux standard
    final xdgDirs = _loadXdgUserDirs(home);

    // Fonction pour récupérer le chemin : Environnement > Fichier XDG > Fallback
    String xdg(String key, String fallback) {
      return Platform.environment[key] ?? xdgDirs[key] ?? p.join(home, fallback);
    }

    return [
      _Location(MdiIcons.homeOutline,       'Accueil',         home,                                   AppColors.accent),
      _Location(Icons.download_rounded,     'Téléchargements', xdg('XDG_DOWNLOAD_DIR',  'Downloads'),  AppColors.colorDoc),
      _Location(Icons.image_outlined,       'Images',          xdg('XDG_PICTURES_DIR',  'Pictures'),   AppColors.colorImage),
      _Location(MdiIcons.filmstrip,         'Vidéos',          xdg('XDG_VIDEOS_DIR',    'Videos'),     AppColors.colorVideo),
      _Location(MdiIcons.musicNote,         'Musique',         xdg('XDG_MUSIC_DIR',     'Music'),      AppColors.colorAudio),
      _Location(Icons.description_outlined, 'Documents',       xdg('XDG_DOCUMENTS_DIR', 'Documents'),  AppColors.colorDoc),
      _Location(Icons.desktop_mac_rounded,  'Bureau',          xdg('XDG_DESKTOP_DIR',   'Desktop'),    AppColors.colorFolder),
      _Location(Icons.storage_rounded,      'Racine',          '/',                                    AppColors.colorFolder),
    ];
  }

  // ── Windows ───────────────────────────────────────────────────────────────

  List<_Location> _windowsLocations() {
    final home = Platform.environment['USERPROFILE'] ??
        (Platform.environment['HOMEDRIVE'] != null
            ? '${Platform.environment['HOMEDRIVE']}${Platform.environment['HOMEPATH'] ?? ''}'
            : 'C:\\Users\\User');

    return [
      _Location(MdiIcons.homeOutline,         'Accueil',         home,                              AppColors.accent),
      _Location(Icons.download_rounded,       'Téléchargements', p.join(home, 'Downloads'),          AppColors.colorDoc),
      _Location(Icons.image_outlined,         'Images',          p.join(home, 'Pictures'),           AppColors.colorImage),
      _Location(MdiIcons.filmstrip,           'Vidéos',          p.join(home, 'Videos'),             AppColors.colorVideo),
      _Location(MdiIcons.musicNote,           'Musique',         p.join(home, 'Music'),              AppColors.colorAudio),
      _Location(Icons.description_outlined,   'Documents',       p.join(home, 'Documents'),          AppColors.colorDoc),
      _Location(Icons.desktop_mac_rounded,    'Bureau',          p.join(home, 'Desktop'),            AppColors.colorFolder),
      _Location(Icons.storage_rounded,        'Lecteur C:',      'C:\\',                            AppColors.colorFolder),
    ];
  }

  // ── macOS ─────────────────────────────────────────────────────────────────

  List<_Location> _macosLocations() {
    final home = Platform.environment['HOME'] ?? '/Users/user';

    return [
      _Location(MdiIcons.homeOutline,         'Accueil',         home,                          AppColors.accent),
      _Location(Icons.download_rounded,       'Téléchargements', p.join(home, 'Downloads'),      AppColors.colorDoc),
      _Location(Icons.image_outlined,         'Images',          p.join(home, 'Pictures'),       AppColors.colorImage),
      _Location(MdiIcons.filmstrip,           'Vidéos',          p.join(home, 'Movies'),         AppColors.colorVideo),
      _Location(MdiIcons.musicNote,           'Musique',         p.join(home, 'Music'),          AppColors.colorAudio),
      _Location(Icons.description_outlined,   'Documents',       p.join(home, 'Documents'),      AppColors.colorDoc),
      _Location(Icons.desktop_mac_rounded,    'Bureau',          p.join(home, 'Desktop'),        AppColors.colorFolder),
      _Location(Icons.storage_rounded,        'Macintosh HD',    '/',                           AppColors.colorFolder),
    ];
  }

  // ── iOS ───────────────────────────────────────────────────────────────────

  Future<List<_Location>> _iosLocations() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return [
        _Location(Icons.description_outlined, 'Documents', docs.path, AppColors.colorDoc),
      ];
    } catch (_) {
      return const [];
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
///
/// Les échecs sont présentés dans un dialogue : un SnackBar resterait caché
/// derrière la feuille modale.
class _TrashSheet extends StatelessWidget {
  final TrashService trash;
  const _TrashSheet({required this.trash});

  Future<void> _showMessage(BuildContext ctx, String title, String message) {
    return showDialog<void>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext ctx, TrashService t, TrashItem item) async {
    try {
      final restoredTo =
          await t.restore(item, onConflict: askingConflictResolver(ctx));
      if (restoredTo != null &&
          !p.equals(restoredTo, item.originalPath) &&
          ctx.mounted) {
        await _showMessage(ctx, 'Élément restauré',
            'Un élément portait déjà ce nom : « ${item.name} » a été '
            'restauré sous le nom « ${p.basename(restoredTo)} ».');
      }
    } on FileOpException catch (e) {
      if (ctx.mounted) await _showMessage(ctx, 'Restauration impossible', e.message);
    }
  }

  Future<void> _delete(BuildContext ctx, TrashService t, TrashItem item) async {
    try {
      await t.deletePermanently(item);
    } on FileOpException catch (e) {
      if (ctx.mounted) await _showMessage(ctx, 'Suppression impossible', e.message);
    }
  }

  Future<void> _empty(BuildContext ctx, TrashService t) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Vider la corbeille'),
        content: Text('Supprimer définitivement ${t.items.length} élément(s) ? '
            'Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Vider',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final report = await t.emptyTrash();
    if (!ctx.mounted) return;
    if (report.hasFailures) {
      await _showMessage(
          ctx,
          '${report.failures.length} élément(s) non supprimé(s)',
          report.failures.map((f) => f.reason).join('\n'));
    } else {
      Navigator.pop(ctx);
    }
  }

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
                        onPressed: () => _empty(ctx, t),
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
                          final date = '${item.deletedAt.day}/'
                              '${item.deletedAt.month}/${item.deletedAt.year}';
                          return ListTile(
                            leading: Icon(
                              item.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined),
                            title: Text(item.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              item.isOrphan
                                  ? 'Origine inconnue · $date'
                                  : '${p.dirname(item.originalPath)} · $date',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.restore_rounded),
                                  tooltip: item.isOrphan
                                      ? 'Origine inconnue'
                                      : 'Restaurer',
                                  onPressed: item.isOrphan
                                      ? null
                                      : () => _restore(ctx, t, item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever_rounded),
                                  tooltip: 'Supprimer définitivement',
                                  onPressed: () => _delete(ctx, t, item),
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
