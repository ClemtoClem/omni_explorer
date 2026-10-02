/* @file core/widgets/trash_sheet.dart */

/// @file trash_sheet.dart
/// @brief Feuille modale de gestion de la corbeille (restaurer / supprimer
/// / vider). Partagée par StorageScreen.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/file_operations_service.dart';
import '../../../core/services/trash_service.dart';
import '../../../core/widgets/file_op_dialogs.dart';

/// Affiche la corbeille en feuille modale glissable.
Future<void> showTrashSheet(BuildContext context) {
  final trash = context.read<TrashService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ChangeNotifierProvider.value(
      value: trash,
      child: const TrashSheet(),
    ),
  );
}

class TrashSheet extends StatelessWidget {
  const TrashSheet({super.key});

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
      if (ctx.mounted) {
        await _showMessage(ctx, 'Restauration impossible', e.message);
      }
    }
  }

  Future<void> _delete(BuildContext ctx, TrashService t, TrashItem item) async {
    try {
      await t.deletePermanently(item);
    } on FileOpException catch (e) {
      if (ctx.mounted) {
        await _showMessage(ctx, 'Suppression impossible', e.message);
      }
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
    return Consumer<TrashService>(
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
                                icon:
                                    const Icon(Icons.delete_forever_rounded),
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
    );
  }
}