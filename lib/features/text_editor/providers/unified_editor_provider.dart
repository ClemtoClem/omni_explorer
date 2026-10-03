/// @file unified_editor_provider.dart
/// @brief État de l'éditeur unifié qui survit aux navigations : onglets
/// ouverts, projet, arborescence, onglets récemment fermés.

import 'package:flutter/foundation.dart';

import '../models/editor_cursor.dart';
import '../models/editor_tab.dart';
import '../models/project_node.dart';
import '../models/workspace_settings.dart';

/// Conserve les onglets ouverts entre les navigations vers l'explorateur.
class UnifiedEditorProvider extends ChangeNotifier {
  final List<EditorTab> tabs = [];
  int activeTabIndex = 0;
  bool isWorkspace = false;
  String workspacePath = '';
  WorkspaceSettings ws = const WorkspaceSettings();
  List<ProjectNode> tree = [];
  bool showTree = true;

  /// Chemins des onglets fermés, le plus récent en dernier (« Rouvrir le
  /// dernier fermé »).
  final List<String> closedPaths = [];

  /// Dernière position du curseur des fichiers fermés pendant la session :
  /// rétablie à la réouverture.
  final Map<String, EditorCursor> cursors = {};

  EditorTab? get activeTab => tabs.isEmpty || activeTabIndex >= tabs.length
      ? null
      : tabs[activeTabIndex];

  int indexOfPath(String path) => tabs.indexWhere((t) => t.path == path);

  void addTab(EditorTab tab) {
    tabs.add(tab);
    activeTabIndex = tabs.length - 1;
    notifyListeners();
  }

  void removeTab(int index) {
    tabs[index].dispose();
    tabs.removeAt(index);
    if (activeTabIndex >= tabs.length && activeTabIndex > 0) {
      activeTabIndex = tabs.length - 1;
    }
    notifyListeners();
  }

  /// À appeler après avoir modifié [tabs] directement (ajout, fermeture) :
  /// les abonnés (liste des onglets restaurés au démarrage) sont prévenus.
  void tabsChanged() => notifyListeners();

  void setActiveTabIndex(int index) {
    if (index >= 0 && index < tabs.length) {
      activeTabIndex = index;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    super.dispose();
  }
}
