/// @file trash_screen.dart
/// @brief Écran de la corbeille : contenu (y compris ce que d'autres
/// logiciels y ont mis sous Linux), restauration, suppression définitive,
/// vidage.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/file_operations_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/file_op_dialogs.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Contenu à jour (éléments ajoutés ou retirés par un autre logiciel).
    context.read<TrashService>().reload();
  }

  Future<void> _showMessage(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restore(TrashService t, TrashItem item) async {
    try {
      final restoredTo =
          await t.restore(item, onConflict: askingConflictResolver(context));
      if (!mounted || restoredTo == null) return;
      if (!p.equals(restoredTo, item.originalPath)) {
        await _showMessage(
            'Élément restauré',
            'Un élément portait déjà ce nom : « ${item.name} » a été '
                'restauré sous le nom « ${p.basename(restoredTo)} ».');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('« ${item.name} » restauré dans '
                '${p.dirname(restoredTo)}')));
      }
    } on FileOpException catch (e) {
      if (mounted) await _showMessage('Restauration impossible', e.message);
    }
  }

  Future<void> _delete(TrashService t, TrashItem item) async {
    final ok = await _confirm(
      'Supprimer définitivement',
      'Supprimer « ${item.name} » ? Cette action est irréversible.',
      'Supprimer',
    );
    if (!ok) return;
    try {
      await t.deletePermanently(item);
    } on FileOpException catch (e) {
      if (mounted) await _showMessage('Suppression impossible', e.message);
    }
  }

  Future<void> _empty(TrashService t) async {
    final ok = await _confirm(
      'Vider la corbeille',
      'Supprimer définitivement ${t.items.length} élément(s) ? '
          'Cette action est irréversible.',
      'Vider',
    );
    if (!ok) return;
    final report = await t.emptyTrash();
    if (mounted && report.hasFailures) {
      await _showMessage('${report.failures.length} élément(s) non supprimé(s)',
          report.failures.map((f) => f.reason).join('\n'));
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(action, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrashService>();
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final items = t.items
        .where((i) =>
            q.isEmpty ||
            i.name.toLowerCase().contains(q) ||
            i.originalPath.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Corbeille'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: t.reload,
          ),
          if (t.items.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Vider'),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: () => _empty(t),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(
                    t.usesSystemTrash
                        ? Icons.desktop_windows_outlined
                        : Icons.phone_android_rounded,
                    size: 16,
                    color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      t.usesSystemTrash
                          ? 'Corbeille du système, partagée avec le '
                              'gestionnaire de fichiers'
                          : 'Corbeille de l\'application',
                      '${t.items.length} élément(s) · '
                          '${FileUtils.formatSize(t.totalSize)}',
                    ].join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (t.items.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Rechercher (nom, emplacement d\'origine)',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: t.reload,
              child: items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(Icons.delete_outline_rounded,
                            size: 64,
                            color:
                                theme.iconTheme.color?.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                              t.items.isEmpty
                                  ? 'Corbeille vide'
                                  : 'Aucun résultat',
                              style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => _tile(t, items[i], theme),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(TrashService t, TrashItem item, ThemeData theme) {
    final cat = item.isDirectory
        ? FileCategory.folder
        : FileUtils.categoryOfPath(item.name);
    final color = FileUtils.colorOf(cat);
    final d = item.deletedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(d.day)}/${two(d.month)}/${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
    return ListTile(
      key: ValueKey(item.trashedPath),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
            item.isDirectory
                ? Icons.folder_rounded
                : FileUtils.iconOf(cat, path: item.name),
            color: item.isDirectory ? AppColors.colorFolder : color,
            size: 20),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          item.isOrphan ? 'Origine inconnue' : p.dirname(item.originalPath),
          date,
          if (!item.isDirectory) FileUtils.formatSize(item.size),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: item.isOrphan ? 'Origine inconnue' : 'Restaurer',
            onPressed: item.isOrphan ? null : () => _restore(t, item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded),
            tooltip: 'Supprimer définitivement',
            onPressed: () => _delete(t, item),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}
