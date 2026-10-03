/// @file editor_tab_bar.dart
/// @brief Barre d'onglets de l'éditeur, avec menu contextuel (appui long ou
/// clic droit).

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// Action demandée depuis le menu contextuel d'un onglet.
enum TabAction {
  close,
  closeOthers,
  closeToRight,
  closeToLeft,
  closeAllUnmodified,
  closeAll,
  reopenClosed,
}

/// Ce que la barre affiche d'un onglet : évite de lui exposer le modèle
/// interne de l'écran.
class EditorTabInfo {
  final String path;
  final String name;
  final bool isDirty;
  final bool isReadOnly;

  const EditorTabInfo({
    required this.path,
    required this.name,
    required this.isDirty,
    required this.isReadOnly,
  });
}

class EditorTabBar extends StatelessWidget {
  final List<EditorTabInfo> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// Double appui : passer l'onglet en édition.
  final ValueChanged<int> onDoubleTap;
  final ValueChanged<int> onClose;
  final void Function(int index, TabAction action) onAction;

  /// Vrai si un onglet fermé peut être rouvert.
  final bool canReopenClosed;

  const EditorTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onDoubleTap,
    required this.onClose,
    required this.onAction,
    this.canReopenClosed = false,
  });

  Future<void> _openContextMenu(BuildContext context, int index) async {
    final tab = tabs[index];
    final action = await showModalBottomSheet<TabAction>(
      context: context,
      showDragHandle: true,
      // Hauteur du contenu, au-delà des 9/16 d'écran par défaut : sinon
      // « Tout fermer » passe sous le pli sur téléphone en paysage.
      isScrollControlled: true,
      builder: (sCtx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(tab.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  tab.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sCtx).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 1),
              _item(sCtx, TabAction.close, Icons.close_rounded, 'Fermer'),
              if (tabs.length > 1)
                _item(sCtx, TabAction.closeOthers,
                    Icons.cancel_presentation_rounded, 'Fermer les autres'),
              if (index < tabs.length - 1)
                _item(sCtx, TabAction.closeToRight, Icons.last_page_rounded,
                    'Fermer à droite'),
              if (index > 0)
                _item(sCtx, TabAction.closeToLeft, Icons.first_page_rounded,
                    'Fermer à gauche'),
              if (tabs.any((t) => !t.isDirty))
                _item(sCtx, TabAction.closeAllUnmodified,
                    Icons.cleaning_services_rounded, 'Fermer les non modifiés'),
              _item(sCtx, TabAction.closeAll, Icons.delete_sweep_rounded,
                  'Tout fermer',
                  color: AppColors.error),
              if (canReopenClosed) ...[
                const Divider(height: 1),
                _item(sCtx, TabAction.reopenClosed, Icons.restore_rounded,
                    'Rouvrir le dernier fermé'),
              ],
            ],
          ),
        ),
      ),
    );
    if (action != null) onAction(index, action);
  }

  Widget _item(BuildContext c, TabAction a, IconData icon, String label,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(c, a),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      color: theme.colorScheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (_, i) {
          final tab = tabs[i];
          final isActive = i == activeIndex;
          return GestureDetector(
            onTap: () {
              if (!isActive) onSelect(i);
            },
            onDoubleTap: () => onDoubleTap(i),
            onLongPress: () => _openContextMenu(context, i),
            onSecondaryTap: () => _openContextMenu(context, i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.scaffoldBackgroundColor
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isDirty)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                    ),
                  if (tab.isReadOnly)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.lock_outline_rounded, size: 10),
                    ),
                  Text(
                    tab.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isActive ? null : theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onClose(i),
                    child: const Icon(Icons.close_rounded, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
