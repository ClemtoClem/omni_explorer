/// @file app_state_service.dart
/// @brief Service de persistance de l'état global de l'application
/// (macro-app).
///
/// Mémorise :
///   - la dernière fonctionnalité visitée (pour la rouvrir au démarrage) ;
///   - le dernier chemin de l'explorateur de fichiers ;
///   - la liste des onglets ouverts dans l'éditeur de texte/code ;
///   - la dernière catégorie de filtre utilisée (image / pdf…).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifiant stable des fonctionnalités exposées dans le launcher.
enum AppFeature {
  fileExplorer,
  textEditor,
  videoEditor,
  passwordVault,
  settings,
}

class AppStateService extends ChangeNotifier {
  static const _kLastFeature      = 'app_state.last_feature';
  static const _kLastExplorerPath = 'app_state.last_explorer_path';
  static const _kEditorTabs       = 'app_state.editor_tabs';
  static const _kRestoreOnLaunch  = 'app_state.restore_on_launch';

  SharedPreferences? _prefs;
  AppFeature?   _lastFeature;
  String?       _lastExplorerPath;
  List<String>  _editorTabs = const [];
  bool          _restoreOnLaunch = true;

  AppFeature?  get lastFeature      => _lastFeature;
  String?      get lastExplorerPath => _lastExplorerPath;
  List<String> get editorTabs       => List.unmodifiable(_editorTabs);
  bool         get restoreOnLaunch  => _restoreOnLaunch;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final name = _prefs!.getString(_kLastFeature);
    if (name != null) {
      _lastFeature = AppFeature.values
          .where((f) => f.name == name)
          .cast<AppFeature?>()
          .firstWhere((_) => true, orElse: () => null);
    }
    _lastExplorerPath = _prefs!.getString(_kLastExplorerPath);
    _editorTabs       = _prefs!.getStringList(_kEditorTabs) ?? const [];
    _restoreOnLaunch  = _prefs!.getBool(_kRestoreOnLaunch) ?? true;
  }

  /// Garantit la disponibilité de `_prefs` même si `init()` n'a pas été
  /// appelé (ou a échoué) — sinon les écritures sont silencieusement perdues.
  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Setters persistants ───────────────────────────────────────────────────

  Future<void> setLastFeature(AppFeature? feature) async {
    if (_lastFeature == feature) return;
    _lastFeature = feature;
    notifyListeners();
    final prefs = await _ensurePrefs();
    if (feature == null) {
      await prefs.remove(_kLastFeature);
    } else {
      await prefs.setString(_kLastFeature, feature.name);
    }
  }

  Future<void> setLastExplorerPath(String path) async {
    if (_lastExplorerPath == path) return;
    _lastExplorerPath = path;
    notifyListeners();
    final prefs = await _ensurePrefs();
    await prefs.setString(_kLastExplorerPath, path);
  }

  Future<void> setEditorTabs(List<String> paths) async {
    final p = List<String>.from(paths);
    // Évite le re-write si rien n'a changé.
    if (listEquals(p, _editorTabs)) return;
    _editorTabs = p;
    notifyListeners();
    final prefs = await _ensurePrefs();
    await prefs.setStringList(_kEditorTabs, p);
  }

  Future<void> setRestoreOnLaunch(bool value) async {
    if (_restoreOnLaunch == value) return;
    _restoreOnLaunch = value;
    notifyListeners();
    final prefs = await _ensurePrefs();
    await prefs.setBool(_kRestoreOnLaunch, value);
  }
}
