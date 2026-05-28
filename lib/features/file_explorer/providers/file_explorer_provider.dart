/// @file file_explorer_provider.dart
/// @brief Provider de l'explorateur de fichiers (navigation, tri, filtre).
///
/// Gère l'historique de navigation (undo/redo), le chargement des entrées
/// d'un répertoire, le tri, le filtrage et la sélection multiple.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:omni_explorer/core/services/permissions_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../app/constants/app_constants.dart';
import '../../../core/models/file_item.dart';
import '../../../core/services/settings_service.dart';
import 'dart:developer' as developer;

/// @class FileExplorerProvider
/// @brief Provider principal de l'explorateur de fichiers.
class FileExplorerProvider extends ChangeNotifier {
  final SettingsService _settings;

  FileExplorerProvider(this._settings) {
    _settings.addListener(_onSettingsChanged);
  }

  // ── État de navigation ────────────────────────────────────────────────────
  String       _currentPath  = '';
  String       _rootPath     = '/';     // Chemin minimum : bloque navigateUp()
  final List<String> _history    = [];   // Historique undo
  final List<String> _redoStack  = [];   // Pile redo
  List<FileItem>     _entries    = [];
  List<FileItem>?    _cachedEntries;     // Cache des entrées filtrées/triées
  bool               _loading    = false;
  String?            _error;
  bool               _needsFullStoragePermission = false;

  // ── Sélection ─────────────────────────────────────────────────────────────
  final Set<String>  _selected   = {};
  bool               _selectMode = false;

  // ── Filtre ────────────────────────────────────────────────────────────────
  String        _filterQuery     = '';
  final Set<FileCategory> _filterCategories = <FileCategory>{};

  // ── Presse-papiers (copier / couper / coller) ─────────────────────────────
  final List<String> _clipboard = [];
  bool               _clipboardCut = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  String         get currentPath    => _currentPath;
  bool           get loading        => _loading;
  String?        get error          => _error;
  bool           get selectMode     => _selectMode;
  Set<String>    get selected       => Set.unmodifiable(_selected);
  String         get filterQuery    => _filterQuery;
  Set<FileCategory> get filterCategories =>
      Set.unmodifiable(_filterCategories);
  bool           get canUndo        => _history.isNotEmpty;
  bool           get canRedo        => _redoStack.isNotEmpty;
  bool           get needsFullStoragePermission => _needsFullStoragePermission;
  String         get rootPath       => _rootPath;
  bool           get hasClipboard   => _clipboard.isNotEmpty;
  int            get clipboardCount => _clipboard.length;
  bool           get clipboardIsCut => _clipboardCut;

  /// Vrai si on est déjà à la racine et qu'on ne peut plus remonter.
  bool           get isAtRoot       => _currentPath == _rootPath;

  /// Segments du chemin pour la barre de navigation interactive.
  List<String> get pathSegments {
    if (_currentPath.isEmpty) return [];
    final all = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final rootSegs = _rootPath.split('/').where((s) => s.isNotEmpty).toList();
    final offset = (rootSegs.length - 1).clamp(0, all.length);
    return all.sublist(offset);
  }

  /// Chemin complet reconstruit à partir d'un index dans [pathSegments].
  String _segmentPath(int segmentIndex) {
    final all = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final rootSegs = _rootPath.split('/').where((s) => s.isNotEmpty).toList();
    final offset = rootSegs.length > 1 ? rootSegs.length - 1 : 0;
    final realIndex = (offset + segmentIndex).clamp(0, all.length - 1);
    return '/${all.sublist(0, realIndex + 1).join('/')}';
  }

  /// Entrées filtrées et triées (résultat mis en cache).
  List<FileItem> get entries => _cachedEntries ??= _buildEntries();

  List<FileItem> _buildEntries() {
    final q = _filterQuery.isEmpty ? null : _filterQuery.toLowerCase();

    final list = _entries.where((f) {
      if (!_settings.showHidden && f.isHidden) return false;
      if (q != null && !f.name.toLowerCase().contains(q)) return false;
      if (_filterCategories.isNotEmpty &&
          !_filterCategories.contains(f.category)) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      int cmp;
      switch (_settings.sortMode) {
        case SortMode.name: cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.date: cmp = a.modified.compareTo(b.modified);
        case SortMode.size: cmp = a.size.compareTo(b.size);
        case SortMode.type: cmp = a.extension.compareTo(b.extension);
      }
      return _settings.sortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _invalidateCache() {
    _cachedEntries = null;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// @brief Initialise l'explorateur. On tente TOUJOURS de lister le contenu,
  /// même avec des permissions partielles (Android renvoie alors un sous-
  /// ensemble) ; la bannière dans l'UI informe sur ce qui manque.
  Future<PermissionsResult> init() async {
    final result = await PermissionsService.requestAll();
    _needsFullStoragePermission =
        !await PermissionsService.hasManageExternalStorage();
    _rootPath = await _getRootPath();
    await navigateTo(_rootPath, addToHistory: false);
    return result;
  }

  /// Re-vérifie les permissions au retour des Paramètres système.
  /// Si MANAGE_EXTERNAL_STORAGE vient d'être accordée, ré-initialise
  /// l'explorateur sans redemander les permissions déjà acquises.
  Future<void> recheckAndInit() async {
    if (!Platform.isAndroid) return;
    
    final wasBlocked = _needsFullStoragePermission;
    
    // On check l'état actuel des permissions de façon passive
    final statuses = await PermissionsService.checkCurrentStatuses();
    _needsFullStoragePermission = !await PermissionsService.hasManageExternalStorage();

    if (wasBlocked && !_needsFullStoragePermission) {
      // Permission nouvellement accordée → ré-initialiser le chemin racine et effacer l'erreur s'il y en avait une
      _error = null;
      _rootPath = await _getRootPath();
      await navigateTo(_rootPath, addToHistory: false);
    } else if (wasBlocked != _needsFullStoragePermission || _error != null) {
      if (statuses.allGranted) _error = null;
      notifyListeners();
    }
  }

  Future<String> _getRootPath() async {
    if (Platform.isAndroid) {
      try {
        final dirs = await getExternalStorageDirectories();
        if (dirs != null && dirs.isNotEmpty) {
          var path = dirs.first.path;
          while (path.contains('/Android')) {
            path = p.dirname(path);
          }
          if (Directory(path).existsSync()) return path;
        }
      } catch (_) {}

      for (final candidate in ['/storage/emulated/0', '/storage/self/primary']) {
        if (Directory(candidate).existsSync()) return candidate;
      }
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) return home;
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && Directory(userProfile).existsSync()) {
        return userProfile;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// @brief Navigue vers un répertoire.
  Future<void> navigateTo(String path, {bool addToHistory = true}) async {
    if (_rootPath.isNotEmpty && !_isAncestorOrEqual(_rootPath, path)) {
      path = _rootPath;
    }
    if (path == _currentPath) return;
    if (addToHistory && _currentPath.isNotEmpty) {
      _history.add(_currentPath);
      if (_history.length > AppConstants.maxUndoHistory) _history.removeAt(0);
      _redoStack.clear();
    }
    _currentPath = path;
    _selected.clear();
    _selectMode = false;
    await _loadEntries();
  }

  /// @brief Remonte au répertoire parent, sans dépasser [_rootPath].
  Future<void> navigateUp() async {
    if (_currentPath.isEmpty || _currentPath == _rootPath) return;
    final parent = p.dirname(_currentPath);
    if (parent == _currentPath) return;
    final dest = _isAncestorOrEqual(_rootPath, parent) ? parent : _rootPath;
    await navigateTo(dest);
  }

  bool _isAncestorOrEqual(String ancestor, String path) {
    if (ancestor == path) return true;
    final a = ancestor.endsWith('/') ? ancestor : '$ancestor/';
    return path.startsWith(a);
  }

  /// @brief Annule la dernière navigation (undo).
  Future<void> undo() async {
    if (!canUndo) return;
    _redoStack.add(_currentPath);
    final prev = _history.removeLast();
    _currentPath = _isAncestorOrEqual(_rootPath, prev) ? prev : _rootPath;
    _selected.clear();
    _selectMode = false;
    await _loadEntries();
  }

  /// @brief Refait la navigation annulée (redo).
  Future<void> redo() async {
    if (!canRedo) return;
    _history.add(_currentPath);
    final next = _redoStack.removeLast();
    _currentPath = _isAncestorOrEqual(_rootPath, next) ? next : _rootPath;
    _selected.clear();
    _selectMode = false;
    await _loadEntries();
  }

  /// @brief Navigue vers un segment de chemin (clic sur barre de navigation).
  Future<void> navigateToSegment(int segmentIndex) async {
    if (segmentIndex >= pathSegments.length) return;
    await navigateTo(_segmentPath(segmentIndex));
  }

  // ── Chargement du répertoire ──────────────────────────────────────────────

  Future<void> _loadEntries() async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      // Sécurité : Avant de tenter de lister un répertoire, on s'assure qu'on n'a pas perdu l'accès critique
      if (await PermissionsService.hasMissingCriticalPermissions()) {
        throw const FileSystemException("Accès refusé : Permissions de stockage manquantes.");
      }

      final dir = Directory(_currentPath);
      if (!dir.existsSync()) {
        _error = 'Répertoire introuvable : $_currentPath';
        _entries = [];
      } else {
        final entities = await dir.list().toList();
        final futures = entities.map((e) async {
          try {
            return await FileItem.fromEntity(e);
          } catch (_) {
            return null;
          }
        }).toList();
        final results = await Future.wait(futures);
        _entries = results.whereType<FileItem>().toList();
        
        developer.log('Entries loaded: ${_entries.length}', name: 'FileExplorerProvider');
      }
    } catch (e) {
      _error   = e.toString().replaceAll("FileSystemException: ", "");
      _entries = [];
    }

    _loading = false;
    _invalidateCache();
    notifyListeners();
  }

  /// @brief Recharge le répertoire courant.
  Future<void> refresh() => _loadEntries();

  // ── Filtre ────────────────────────────────────────────────────────────────

  void setFilterQuery(String q) {
    _filterQuery = q;
    _invalidateCache();
    notifyListeners();
  }

  /// Remplace l'ensemble des catégories sélectionnées (vide = pas de filtre).
  void setFilterCategories(Iterable<FileCategory> cats) {
    _filterCategories
      ..clear()
      ..addAll(cats);
    _invalidateCache();
    notifyListeners();
  }

  /// Bascule une catégorie dans la sélection (ajout / retrait).
  void toggleFilterCategory(FileCategory cat) {
    if (!_filterCategories.remove(cat)) _filterCategories.add(cat);
    _invalidateCache();
    notifyListeners();
  }

  void clearFilter() {
    _filterQuery = '';
    _filterCategories.clear();
    _invalidateCache();
    notifyListeners();
  }

  // ── Sélection ─────────────────────────────────────────────────────────────

  void toggleSelectMode() {
    _selectMode = !_selectMode;
    if (!_selectMode) _selected.clear();
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (_selected.contains(path)) {
      _selected.remove(path);
    } else {
      _selected.add(path);
    }
    if (_selected.isEmpty) _selectMode = false;
    notifyListeners();
  }

  void selectAll() {
    _selected.addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    _selectMode = false;
    notifyListeners();
  }

  // ── Opérations sur fichiers ───────────────────────────────────────────────

  Future<void> createDirectory(String name) async {
    final newDir = Directory(p.join(_currentPath, name));
    if (!newDir.existsSync()) await newDir.create();
    await _loadEntries();
  }

  Future<void> createFile(String name) async {
    final newFile = File(p.join(_currentPath, name));
    if (!newFile.existsSync()) await newFile.create();
    await _loadEntries();
  }

  Future<void> rename(String oldPath, String newName) async {
    final newPath = p.join(p.dirname(oldPath), newName);
    final type = FileSystemEntity.typeSync(oldPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
    await _loadEntries();
  }

  Future<void> copyTo(String sourcePath, String destDir) async {
    final name = p.basename(sourcePath);
    final dest = p.join(destDir, name);
    if (_isFile(sourcePath)) {
      await File(sourcePath).copy(dest);
    } else {
      await _copyDirectory(Directory(sourcePath), Directory(dest));
    }
    await _loadEntries();
  }

  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list()) {
      if (e is File) {
        await e.copy(p.join(dst.path, p.basename(e.path)));
      } else if (e is Directory) {
        await _copyDirectory(e, Directory(p.join(dst.path, p.basename(e.path))));
      }
    }
  }

  // ── Presse-papiers ─────────────────────────────────────────────────────────

  void copyToClipboard(Iterable<String> paths) {
    _clipboard
      ..clear()
      ..addAll(paths);
    _clipboardCut = false;
    notifyListeners();
  }

  void cutToClipboard(Iterable<String> paths) {
    _clipboard
      ..clear()
      ..addAll(paths);
    _clipboardCut = true;
    notifyListeners();
  }

  void clearClipboard() {
    _clipboard.clear();
    _clipboardCut = false;
    notifyListeners();
  }

  Future<int> pasteClipboard() async {
    if (_clipboard.isEmpty) return 0;
    int count = 0;
    final wasCut = _clipboardCut;
    for (final src in List<String>.of(_clipboard)) {
      if (!_pathExists(src)) continue;
      if (_isAncestorOrEqual(src, _currentPath)) continue;
      final dest = _uniqueDestPath(_currentPath, p.basename(src));
      try {
        if (wasCut) {
          await _moveEntity(src, dest);
        } else {
          await _copyEntity(src, dest);
        }
        count++;
      } catch (e) {
        developer.log('Paste error for $src: $e', name: 'FileExplorerProvider');
      }
    }
    if (wasCut) {
      clearClipboard();
    }
    await _loadEntries();
    return count;
  }

  bool _pathExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  bool _isDirectory(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.directory;

  bool _isFile(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.file;

  String _uniqueDestPath(String dir, String name) {
    var dest = p.join(dir, name);
    if (!_pathExists(dest)) return dest;
    final ext  = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    int i = 1;
    while (_pathExists(dest)) {
      final suffix = i == 1 ? ' (copie)' : ' (copie $i)';
      dest = p.join(dir, '$base$suffix$ext');
      i++;
    }
    return dest;
  }

  Future<void> _copyEntity(String src, String dest) async {
    if (_isDirectory(src)) {
      await _copyDirectory(Directory(src), Directory(dest));
    } else {
      await File(src).copy(dest);
    }
  }

  Future<void> _moveEntity(String src, String dest) async {
    final isDir = _isDirectory(src);
    try {
      if (isDir) {
        await Directory(src).rename(dest);
      } else {
        await File(src).rename(dest);
      }
    } on FileSystemException {
      await _copyEntity(src, dest);
      if (isDir) {
        await Directory(src).delete(recursive: true);
      } else {
        await File(src).delete();
      }
    }
  }

  // ── Stockages externes ────────────────────────────────────────────────────

  Future<List<Map<String, String>>> getStorages() async {
    final result = <Map<String, String>>[];

    if (Platform.isAndroid) {
      try {
        final dirs = await getExternalStorageDirectories();
        if (dirs != null) {
          for (int i = 0; i < dirs.length; i++) {
            var path = dirs[i].path;
            while (path.contains('/Android')) { path = p.dirname(path); }
            result.add({
              'name': i == 0 ? 'Stockage interne' : 'Carte SD $i',
              'path': path,
            });
          }
        }
      } catch (_) {}
    }

    if (result.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      result.add({'name': 'Documents', 'path': dir.path});
    }

    return result;
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _onSettingsChanged() {
    _invalidateCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}