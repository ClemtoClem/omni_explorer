/// @file settings_screen.dart
/// @brief Écran « Paramètres » (apparence, explorateur, claviers, SSH,
/// corbeille, démarrage, à propos).

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state_service.dart';
import '../../../core/services/permissions_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/widgets/file_op_dialogs.dart';
import '../../text_editor/services/ssh_known_hosts.dart';
import 'font_settings_screen.dart';
import 'theme_picker_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final trash    = context.watch<TrashService>();
    final appState = context.watch<AppStateService>();
    final theme    = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          const _SectionHeader('APPARENCE'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Thème'),
            subtitle: Text(
              '${settings.themePreset.emoji} ${settings.themePreset.name}  ·  ${_themeLabel(settings.themeMode)}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ThemePickerScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('Polices'),
            subtitle: Text(
              '${settings.uiFontFamily}  ·  ${(settings.uiFontScale * 100).round()}%',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FontSettingsScreen())),
          ),
          const Divider(height: 1),
          const _SectionHeader('DÉMARRAGE'),
          SwitchListTile(
            secondary: const Icon(Icons.restart_alt_rounded),
            title: const Text('Reprendre où vous en étiez'),
            subtitle: const Text(
                'Rouvre automatiquement la dernière fonctionnalité utilisée'),
            value: appState.restoreOnLaunch,
            onChanged: appState.setRestoreOnLaunch,
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Autorisations'),
            subtitle: const Text(
                'Redemander toutes les autorisations (stockage, médias, notifications…)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await PermissionsService.requestAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Autorisations re-demandées')));
              }
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('EXPLORATEUR'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Fichiers cachés'),
            subtitle: const Text('Afficher les fichiers et dossiers cachés'),
            value: settings.showHidden,
            onChanged: settings.setShowHidden,
          ),
          ListTile(
            leading: const Icon(Icons.sort_rounded),
            title: const Text('Tri par défaut'),
            subtitle: Text(_sortLabel(settings.sortMode)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickSort(context, settings),
          ),
          const Divider(height: 1),
          const _SectionHeader('CLAVIERS'),
          SwitchListTile(
            secondary: const Icon(Icons.keyboard_rounded),
            title: const Text('Clavier personnalisé'),
            subtitle: const Text(
                'Utiliser le clavier AZERTY personnalisé dans les éditeurs'),
            value: settings.useCustomKeyboard,
            onChanged: settings.setUseCustomKeyboard,
          ),
          const Divider(height: 1),
          const _SectionHeader('DEBIAN VM (SSH)'),
          ListTile(
            leading: const Icon(Icons.terminal_rounded),
            title: const Text('Connexion SSH'),
            subtitle: Text(
                '${settings.sshUsername}@${settings.sshHost}:${settings.sshPort}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showSshSettingsDialog(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Dossier partagé (VM)'),
            subtitle: Text(settings.sshSharedPath),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showSshSettingsDialog(context, settings),
          ),
          const Divider(height: 1),
          const _SectionHeader('CORBEILLE'),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Éléments en corbeille'),
            trailing: Chip(
              label: Text('${trash.items.length}'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (trash.items.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded,
                  color: AppColors.error),
              title: const Text('Vider la corbeille',
                  style: TextStyle(color: AppColors.error)),
              subtitle:
                  Text(_formatSize(trash.totalSize), style: theme.textTheme.bodySmall),
              onTap: () => _confirmEmptyTrash(context, trash),
            ),
          const Divider(height: 1),
          const _SectionHeader('À PROPOS'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('OmniExplorer'),
            subtitle: Text('Version 1.0.0 — Flutter · ${_platformLabel()}'),
          ),
        ],
      ),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux)   return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS)   return 'macOS';
    return 'Autre';
  }

  String _themeLabel(ThemeMode m) => {
        ThemeMode.system: 'Système',
        ThemeMode.light: 'Clair',
        ThemeMode.dark: 'Sombre',
      }[m]!;

  String _sortLabel(SortMode m) => {
        SortMode.name: 'Nom',
        SortMode.date: 'Date',
        SortMode.size: 'Taille',
        SortMode.type: 'Type',
      }[m]!;

  String _formatSize(int bytes) {
    if (bytes < 1024)    return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  void _pickSort(BuildContext ctx, SettingsService s) {
    showDialog(
      context: ctx,
      builder: (_) => SimpleDialog(
        title: const Text('Trier par'),
        children: [
          for (final m in SortMode.values)
            SimpleDialogOption(
              onPressed: () { s.setSortMode(m); Navigator.pop(ctx); },
              child: Text(_sortLabel(m)),
            ),
        ],
      ),
    );
  }

  void _showSshSettingsDialog(BuildContext ctx, SettingsService s) {
    final hostCtrl   = TextEditingController(text: s.sshHost);
    final portCtrl   = TextEditingController(text: s.sshPort.toString());
    final userCtrl   = TextEditingController(text: s.sshUsername);
    final passCtrl   = TextEditingController(text: s.sshPassword);
    final sharedCtrl = TextEditingController(text: s.sshSharedPath);
    bool obscurePass = true;

    showDialog(
      context: ctx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('VM Debian — SSH'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Hôte', hintText: 'localhost'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Utilisateur'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    suffixIcon: IconButton(
                      icon: Icon(obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setLocal(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sharedCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Dossier partagé (VM)', hintText: '/mnt/shared'),
                ),
              ],
            ),
          ),
          actions: [
            // Serveur réinstallé : sa nouvelle clé serait refusée tant que
            // l'ancienne est mémorisée.
            TextButton(
              onPressed: () async {
                final host = hostCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ?? 2222;
                final messenger = ScaffoldMessenger.of(ctx);
                await SshKnownHosts(await SharedPreferences.getInstance())
                    .forget(host, port);
                messenger.showSnackBar(SnackBar(
                    content: Text('Clé de $host:$port oubliée : elle sera '
                        'redemandée à la prochaine connexion.')));
              },
              child: const Text('Oublier la clé du serveur'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                s.setSshHost(hostCtrl.text.trim());
                s.setSshPort(int.tryParse(portCtrl.text.trim()) ?? 2222);
                s.setSshUsername(userCtrl.text.trim());
                s.setSshPassword(passCtrl.text);
                s.setSshSharedPath(sharedCtrl.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmEmptyTrash(BuildContext ctx, TrashService trash) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Vider la corbeille'),
        content: const Text(
            'Supprimer définitivement tous les éléments ? '
            'Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vider',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final report = await trash.emptyTrash();
    if (ctx.mounted) showFileOpReport(ctx, report, verb: 'supprimé(s)');
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(ctx)
              .textTheme
              .labelSmall
              ?.copyWith(letterSpacing: 1.5),
        ),
      );
}
