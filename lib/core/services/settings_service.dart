/// @file settings_service.dart
/// @brief Service de persistance des préférences utilisateur.
///
/// Gère le mode d'affichage, le tri, les raccourcis, les fichiers récents
/// et le **thème de couleur** (preset prédéfini ou personnalisé).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_theme_presets.dart';
import '../models/file_item.dart';

/// @class SettingsService
/// @brief Singleton gérant les préférences de l'application avec SharedPreferences.
class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  late SharedPreferences _prefs;
  final _uuid = const Uuid();

  // ── État local ─────────────────────────────────────────────────────────────
  ThemeMode          _themeMode           = ThemeMode.dark;
  ThemePreset        _themePreset         = AppThemePresets.defaultPreset;
  ViewMode           _viewMode            = ViewMode.list;
  SortMode           _sortMode            = SortMode.name;
  bool               _sortAsc             = true;
  bool               _showHidden          = false;
  bool               _useCustomKeyboard   = true;
  List<ShortcutItem> _shortcuts           = [];
  List<String>       _recentFiles         = [];

  // ── Polices ────────────────────────────────────────────────────────────────
  String _uiFontFamily       = 'Inter';
  double _uiFontScale        = 1.0;
  String _codeFontFamily     = 'JetBrains Mono';
  int    _codeFontSize       = 13;
  String _markdownFontFamily = 'Inter';
  int    _markdownFontSize   = 15;
  String _textFontFamily     = 'Roboto Mono';
  int    _textFontSize       = 13;
  String _richFontFamily     = 'Inter';
  int    _richFontSize       = 14;
  String _hexFontFamily      = 'Roboto Mono';
  int    _hexFontSize        = 12;

  // ── Getters ────────────────────────────────────────────────────────────────
  ThemeMode          get themeMode          => _themeMode;
  ThemePreset        get themePreset        => _themePreset;
  ViewMode           get viewMode           => _viewMode;
  SortMode           get sortMode           => _sortMode;
  bool               get sortAsc            => _sortAsc;
  bool               get showHidden         => _showHidden;
  bool               get useCustomKeyboard  => _useCustomKeyboard;
  List<ShortcutItem> get shortcuts         => List.unmodifiable(_shortcuts);
  List<String>       get recentFiles        => List.unmodifiable(_recentFiles);

  String get uiFontFamily       => _uiFontFamily;
  double get uiFontScale        => _uiFontScale;
  String get codeFontFamily     => _codeFontFamily;
  int    get codeFontSize       => _codeFontSize;
  String get markdownFontFamily => _markdownFontFamily;
  int    get markdownFontSize   => _markdownFontSize;
  String get textFontFamily     => _textFontFamily;
  int    get textFontSize       => _textFontSize;
  String get richFontFamily     => _richFontFamily;
  int    get richFontSize       => _richFontSize;
  String get hexFontFamily      => _hexFontFamily;
  int    get hexFontSize        => _hexFontSize;

  // ── SSH / Debian VM ────────────────────────────────────────────────────────
  String _sshHost       = 'localhost';
  int    _sshPort       = 2222;
  String _sshUsername   = 'user';
  String _sshPassword   = '';
  String _sshSharedPath = '/mnt/shared';

  String get sshHost       => _sshHost;
  int    get sshPort       => _sshPort;
  String get sshUsername   => _sshUsername;
  String get sshPassword   => _sshPassword;
  String get sshSharedPath => _sshSharedPath;

  void setSshHost(String v) {
    _sshHost = v;
    _prefs.setString(AppConstants.prefSshHost, v);
    notifyListeners();
  }
  void setSshPort(int v) {
    _sshPort = v;
    _prefs.setInt(AppConstants.prefSshPort, v);
    notifyListeners();
  }
  void setSshUsername(String v) {
    _sshUsername = v;
    _prefs.setString(AppConstants.prefSshUsername, v);
    notifyListeners();
  }
  void setSshPassword(String v) {
    _sshPassword = v;
    _prefs.setString(AppConstants.prefSshPassword, v);
    notifyListeners();
  }
  void setSshSharedPath(String v) {
    _sshSharedPath = v;
    _prefs.setString(AppConstants.prefSshSharedPath, v);
    notifyListeners();
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// @brief Initialise le service en chargeant les préférences depuis le stockage.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _themeMode = ThemeMode.values[
        _prefs.getInt(AppConstants.prefThemeMode) ?? ThemeMode.dark.index];
    _viewMode  = ViewMode.values[
        _prefs.getInt(AppConstants.prefViewMode) ?? 0];
    _sortMode  = SortMode.values[
        _prefs.getInt(AppConstants.prefSortBy) ?? 0];
    _sortAsc           = _prefs.getBool(AppConstants.prefSortAsc)           ?? true;
    _showHidden        = _prefs.getBool(AppConstants.prefShowHidden)        ?? false;
    _useCustomKeyboard = _prefs.getBool(AppConstants.prefUseCustomKeyboard) ?? true;

    _loadThemePreset();
    _loadShortcuts();
    _loadRecentFiles();
    _loadFonts();
    _loadSsh();

    // Applique le preset chargé aux couleurs et la police à l'interface
    AppColors.apply(_themePreset);
    AppFonts.apply(family: _uiFontFamily, scale: _uiFontScale);
  }

  // ── Thème de couleur ────────────────────────────────────────────────────────

  void _loadThemePreset() {
    final presetId = _prefs.getString(AppConstants.prefThemePreset);
    if (presetId == null) {
      _themePreset = AppThemePresets.defaultPreset;
      return;
    }
    if (presetId == 'custom') {
      final accentValue = _prefs.getInt(AppConstants.prefCustomAccent);
      if (accentValue != null) {
        _themePreset = ThemePreset.fromAccent(Color(accentValue));
      } else {
        _themePreset = AppThemePresets.defaultPreset;
      }
    } else {
      _themePreset = AppThemePresets.findById(presetId);
    }
  }

  /// @brief Applique un [ThemePreset] prédéfini.
  Future<void> setThemePreset(ThemePreset preset) async {
    _themePreset = preset;
    AppColors.apply(preset);
    await _prefs.setString(AppConstants.prefThemePreset, preset.id);
    notifyListeners();
  }

  /// @brief Applique un thème personnalisé dérivé d'une couleur d'accent.
  Future<void> setCustomAccent(Color accent) async {
    _themePreset = ThemePreset.fromAccent(accent);
    AppColors.apply(_themePreset);
    await _prefs.setString(AppConstants.prefThemePreset, 'custom');
    // ignore: deprecated_member_use
    await _prefs.setInt(AppConstants.prefCustomAccent, accent.value);
    notifyListeners();
  }

  // ── Mode clair/sombre ──────────────────────────────────────────────────────

  /// @brief Change le mode de luminosité (clair/sombre/système).
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(AppConstants.prefThemeMode, mode.index);
    notifyListeners();
  }

  // ── Affichage ──────────────────────────────────────────────────────────────

  Future<void> setViewMode(ViewMode mode) async {
    _viewMode = mode;
    await _prefs.setInt(AppConstants.prefViewMode, mode.index);
    notifyListeners();
  }

  Future<void> setSortMode(SortMode mode) async {
    _sortMode = mode;
    await _prefs.setInt(AppConstants.prefSortBy, mode.index);
    notifyListeners();
  }

  Future<void> setSortAsc(bool asc) async {
    _sortAsc = asc;
    await _prefs.setBool(AppConstants.prefSortAsc, asc);
    notifyListeners();
  }

  Future<void> setShowHidden(bool show) async {
    _showHidden = show;
    await _prefs.setBool(AppConstants.prefShowHidden, show);
    notifyListeners();
  }

  Future<void> setUseCustomKeyboard(bool use) async {
    _useCustomKeyboard = use;
    await _prefs.setBool(AppConstants.prefUseCustomKeyboard, use);
    notifyListeners();
  }

  // ── Polices ────────────────────────────────────────────────────────────────

  void _loadFonts() {
    _uiFontFamily       = _prefs.getString(AppConstants.prefUiFontFamily)       ?? 'Inter';
    _uiFontScale        = _prefs.getDouble(AppConstants.prefUiFontScale)         ?? 1.0;
    _codeFontFamily     = _prefs.getString(AppConstants.prefCodeFontFamily)      ?? 'JetBrains Mono';
    _codeFontSize       = _prefs.getInt(AppConstants.prefCodeFontSize)           ?? 13;
    _markdownFontFamily = _prefs.getString(AppConstants.prefMarkdownFontFamily)  ?? 'Inter';
    _markdownFontSize   = _prefs.getInt(AppConstants.prefMarkdownFontSize)       ?? 15;
    _textFontFamily     = _prefs.getString(AppConstants.prefTextFontFamily)      ?? 'Roboto Mono';
    _textFontSize       = _prefs.getInt(AppConstants.prefTextFontSize)           ?? 13;
    _richFontFamily     = _prefs.getString(AppConstants.prefRichFontFamily)      ?? 'Inter';
    _richFontSize       = _prefs.getInt(AppConstants.prefRichFontSize)           ?? 14;
    _hexFontFamily      = _prefs.getString(AppConstants.prefHexFontFamily)       ?? 'Roboto Mono';
    _hexFontSize        = _prefs.getInt(AppConstants.prefHexFontSize)            ?? 12;
  }

  void _loadSsh() {
    _sshHost       = _prefs.getString(AppConstants.prefSshHost)       ?? 'localhost';
    _sshPort       = _prefs.getInt(AppConstants.prefSshPort)          ?? 2222;
    _sshUsername   = _prefs.getString(AppConstants.prefSshUsername)   ?? 'user';
    _sshPassword   = _prefs.getString(AppConstants.prefSshPassword)   ?? '';
    _sshSharedPath = _prefs.getString(AppConstants.prefSshSharedPath) ?? '/mnt/shared';
  }

  Future<void> setUiFontFamily(String f) async {
    _uiFontFamily = f;
    AppFonts.apply(family: f, scale: _uiFontScale);
    await _prefs.setString(AppConstants.prefUiFontFamily, f);
    notifyListeners();
  }

  Future<void> setUiFontScale(double s) async {
    _uiFontScale = s;
    AppFonts.apply(family: _uiFontFamily, scale: s);
    await _prefs.setDouble(AppConstants.prefUiFontScale, s);
    notifyListeners();
  }

  Future<void> setCodeFontFamily(String f) async {
    _codeFontFamily = f;
    await _prefs.setString(AppConstants.prefCodeFontFamily, f);
    notifyListeners();
  }

  Future<void> setCodeFontSize(int s) async {
    _codeFontSize = s;
    await _prefs.setInt(AppConstants.prefCodeFontSize, s);
    notifyListeners();
  }

  Future<void> setMarkdownFontFamily(String f) async {
    _markdownFontFamily = f;
    await _prefs.setString(AppConstants.prefMarkdownFontFamily, f);
    notifyListeners();
  }

  Future<void> setMarkdownFontSize(int s) async {
    _markdownFontSize = s;
    await _prefs.setInt(AppConstants.prefMarkdownFontSize, s);
    notifyListeners();
  }

  Future<void> setTextFontFamily(String f) async {
    _textFontFamily = f;
    await _prefs.setString(AppConstants.prefTextFontFamily, f);
    notifyListeners();
  }

  Future<void> setTextFontSize(int s) async {
    _textFontSize = s;
    await _prefs.setInt(AppConstants.prefTextFontSize, s);
    notifyListeners();
  }

  Future<void> setRichFontFamily(String f) async {
    _richFontFamily = f;
    await _prefs.setString(AppConstants.prefRichFontFamily, f);
    notifyListeners();
  }

  Future<void> setRichFontSize(int s) async {
    _richFontSize = s;
    await _prefs.setInt(AppConstants.prefRichFontSize, s);
    notifyListeners();
  }

  Future<void> setHexFontFamily(String f) async {
    _hexFontFamily = f;
    await _prefs.setString(AppConstants.prefHexFontFamily, f);
    notifyListeners();
  }

  Future<void> setHexFontSize(int s) async {
    _hexFontSize = s;
    await _prefs.setInt(AppConstants.prefHexFontSize, s);
    notifyListeners();
  }

  // ── Raccourcis ─────────────────────────────────────────────────────────────

  void _loadShortcuts() {
    final raw = _prefs.getString(AppConstants.prefShortcuts);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _shortcuts =
          list.map((e) => ShortcutItem.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {}
  }

  Future<void> _saveShortcuts() async {
    await _prefs.setString(
      AppConstants.prefShortcuts,
      jsonEncode(_shortcuts.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> addShortcut(String name, String path) async {
    if (_shortcuts.any((s) => s.path == path)) return;
    _shortcuts.add(ShortcutItem(id: _uuid.v4(), name: name, path: path));
    await _saveShortcuts();
    notifyListeners();
  }

  Future<void> removeShortcut(String id) async {
    _shortcuts.removeWhere((s) => s.id == id);
    await _saveShortcuts();
    notifyListeners();
  }

  // ── Fichiers récents ───────────────────────────────────────────────────────

  void _loadRecentFiles() {
    _recentFiles = _prefs.getStringList(AppConstants.prefRecentFiles) ?? [];
  }

  Future<void> addRecentFile(String path) async {
    _recentFiles.remove(path);
    _recentFiles.insert(0, path);
    if (_recentFiles.length > AppConstants.maxRecentFiles) {
      _recentFiles = _recentFiles.sublist(0, AppConstants.maxRecentFiles);
    }
    await _prefs.setStringList(AppConstants.prefRecentFiles, _recentFiles);
    notifyListeners();
  }

  Future<void> clearRecentFiles() async {
    _recentFiles.clear();
    await _prefs.setStringList(AppConstants.prefRecentFiles, []);
    notifyListeners();
  }
}