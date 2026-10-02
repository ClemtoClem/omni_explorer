/// @file trash_service.dart
/// @brief Service de gestion de la corbeille d'OmniExplorer.
///
/// Gère le déplacement des fichiers vers la corbeille, leur restauration
/// et leur suppression définitive :
/// - **Linux** : corbeille du système ([XdgTrash], spécification
///   freedesktop), partagée avec le gestionnaire de fichiers du bureau ; ce
///   qu'un autre logiciel y met apparaît dans l'application (relecture à
///   chaque modification du dossier `info/`) ;
/// - **Android** (et tests) : répertoire caché ".omni_trash" de
///   l'application, avec son index.
///
/// Garanties de la corbeille de l'application :
/// Garanties :
/// - l'index (chemins d'origine) est écrit de façon atomique ; un index
///   illisible est conservé de côté au lieu d'être perdu ;
/// - l'index est cohérent avec le disque : une entrée est ajoutée AVANT le
///   déplacement et retirée APRÈS la restauration, et le contenu réel est
///   réconcilié au chargement (fichiers « orphelins » listés, entrées
///   fantômes retirées) ;
/// - restaurer n'écrase jamais un élément sans décision de l'utilisateur ;
/// - chaque échec est levé ([FileOpException]) ou rapporté ([FileOpReport]).

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../app/constants/app_constants.dart';
import '../models/file_item.dart';
import '../utils/atomic_write.dart';
import 'file_operations_service.dart';
import 'xdg_trash.dart';

/// @class TrashService
/// @brief Singleton gérant la corbeille de l'application.
class TrashService extends ChangeNotifier {
  static final TrashService _instance = TrashService._();
  factory TrashService() => _instance;
  TrashService._();

  final _uuid = const Uuid();
  final _ops = const FileOperationsService();
  Directory? _trashDir;
  final List<TrashItem> _items = [];

  /// Corbeille du système (Linux) ; `null` : corbeille de l'application.
  XdgTrash? _system;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _reloadDebounce;

  /// Vrai si la corbeille utilisée est celle du système (Linux).
  bool get usesSystemTrash => _system != null;

  /// Liste des éléments en corbeille.
  List<TrashItem> get items => List.unmodifiable(_items);

  /// Chemin du répertoire de la corbeille (initialise le service si besoin).
  Future<String> get trashDirectory async {
    await _ensureInit();
    return _system?.homeTrash ?? _trashDir!.path;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// @brief Initialise le répertoire de la corbeille et charge l'index.
  ///
  /// [directory] impose la corbeille de l'application à cet emplacement
  /// (tests) ; [systemTrash] impose une corbeille du système (tests). Sans
  /// l'un ni l'autre : corbeille du système sous Linux, de l'application
  /// ailleurs.
  Future<void> init({String? directory, XdgTrash? systemTrash}) async {
    await _stopWatching();
    if (directory == null && (systemTrash != null || Platform.isLinux)) {
      _system = systemTrash ?? XdgTrash.forCurrentUser();
      _trashDir = null;
      await reload();
      _startWatching();
      return;
    }
    _system = null;
    final String path;
    if (directory != null) {
      path = directory;
    } else {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      path = p.join(base.path, AppConstants.trashFolderName);
    }
    _trashDir = Directory(path);
    if (!await _trashDir!.exists()) await _trashDir!.create(recursive: true);
    await _loadMeta();
  }

  // ── Déplacement vers la corbeille ─────────────────────────────────────────

  /// @brief Déplace un fichier ou répertoire vers la corbeille.
  /// @param path Chemin de l'élément à supprimer.
  /// @return Le [TrashItem] créé. Lève [FileOpException] en cas d'échec
  /// (l'élément reste alors à sa place).
  Future<TrashItem> moveToTrash(String path) async {
    await _ensureInit();
    if (_system case final system?) {
      final item = await system.trash(path);
      _items.insert(0, item);
      notifyListeners();
      return item;
    }
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileOpException('« ${p.basename(path)} » n\'existe plus.');
    }
    final trashRoot = _trashDir!.path;
    if (p.equals(path, trashRoot) || p.isWithin(trashRoot, path)) {
      throw const FileOpException('Cet élément est déjà dans la corbeille.');
    }
    if (p.isWithin(path, trashRoot)) {
      throw FileOpException('« ${p.basename(path)} » contient la corbeille de '
          'l\'application : il ne peut pas y être déplacé.');
    }

    final trashedPath = p.join(trashRoot, '${_uuid.v4()}${p.extension(path)}');
    final item = TrashItem(
      trashedPath: trashedPath,
      originalPath: path,
      deletedAt: DateTime.now(),
      isDirectory: type == FileSystemEntityType.directory,
      size: type == FileSystemEntityType.file ? File(path).lengthSync() : 0,
    );

    // 1. Index d'abord : si l'application est tuée pendant le déplacement,
    //    le chemin d'origine n'est pas perdu (une entrée sans fichier est
    //    simplement retirée au prochain chargement).
    _items.add(item);
    try {
      await _saveMeta();
    } catch (e) {
      _items.remove(item);
      throw FileOpException('Corbeille indisponible : ${_describe(e)}');
    }

    // 2. Déplacement (copie + suppression si autre stockage).
    try {
      await _ops.relocate(path, trashedPath, move: true);
    } on PartialMoveException catch (e) {
      // La copie dans la corbeille est complète : elle reste indexée (la
      // retirer ferait perdre le seul exemplaire complet).
      notifyListeners();
      throw FileOpException('« ${p.basename(path)} » a été copié dans la '
          'corbeille, mais l\'original n\'a pas pu être supprimé : '
          '${e.message}');
    } catch (e) {
      _items.remove(item);
      await _saveMetaQuietly();
      throw FileOpException(
          'Impossible de mettre « ${p.basename(path)} » à la corbeille : '
          '${_describe(e)}');
    }
    notifyListeners();
    return item;
  }

  /// Met plusieurs éléments à la corbeille et rapporte le résultat de chacun.
  Future<FileOpReport> moveAllToTrash(Iterable<String> paths) async {
    final report = FileOpReport();
    for (final path in paths) {
      try {
        await moveToTrash(path);
        report.succeeded.add(path);
      } on FileOpException catch (e) {
        report.failures.add(FileOpFailure(path, e.message));
      }
    }
    return report;
  }

  // ── Restauration ──────────────────────────────────────────────────────────

  /// @brief Restaure un élément vers son chemin d'origine.
  ///
  /// Si un élément occupe déjà ce chemin, [onConflict] décide (sans
  /// résolveur : les deux sont gardés, l'élément restauré recevant un nom
  /// libre). Retourne le chemin de restauration, ou `null` si l'utilisateur
  /// a choisi d'ignorer. Lève [FileOpException] en cas d'échec : l'élément
  /// reste alors dans la corbeille.
  Future<String?> restore(TrashItem item,
      {ConflictResolver? onConflict}) async {
    if (item.isOrphan) {
      throw const FileOpException(
          'Origine inconnue : cet élément ne peut pas être restauré '
          'automatiquement.');
    }
    if (FileSystemEntity.typeSync(item.trashedPath, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await _forget(item);
      throw const FileOpException(
          'Le contenu de cet élément a disparu de la corbeille.');
    }
    final String? restoredTo;
    try {
      if (_system case final system?) {
        restoredTo = await system.restore(item, onConflict: onConflict);
      } else {
        await Directory(p.dirname(item.originalPath)).create(recursive: true);
        restoredTo = await _ops.relocate(item.trashedPath, item.originalPath,
            move: true, onConflict: onConflict);
      }
    } catch (e) {
      throw FileOpException(
          'Impossible de restaurer « ${item.name} » : ${_describe(e)}');
    }
    if (restoredTo != null) await _forget(item);
    return restoredTo;
  }

  // ── Suppression définitive ────────────────────────────────────────────────

  /// @brief Supprime définitivement un élément de la corbeille.
  /// Lève [FileOpException] en cas d'échec (l'élément reste listé).
  Future<void> deletePermanently(TrashItem item) async {
    if (_system case final system?) {
      await system.delete(item);
      await _forget(item);
      return;
    }
    final report = await _ops.deletePermanently([item.trashedPath]);
    if (report.hasFailures) {
      throw FileOpException('Impossible de supprimer « ${item.name} » : '
          '${report.failures.single.reason}');
    }
    await _forget(item);
  }

  /// @brief Vide la corbeille ; les éléments en échec y restent.
  Future<FileOpReport> emptyTrash() async {
    final report = FileOpReport();
    for (final item in List<TrashItem>.of(_items)) {
      try {
        await deletePermanently(item);
        report.succeeded.add(item.originalPath);
      } on FileOpException catch (e) {
        report.failures.add(FileOpFailure(item.trashedPath, e.message));
      }
    }
    return report;
  }

  // ── Taille totale ─────────────────────────────────────────────────────────

  /// @brief Retourne la taille totale des éléments en corbeille.
  int get totalSize => _items.fold(0, (s, i) => s + i.size);

  // ── Relecture ─────────────────────────────────────────────────────────────

  /// Relit le contenu de la corbeille (modifiée par un autre logiciel,
  /// réconciliation de l'index).
  Future<void> reload() async {
    if (_system case final system?) {
      final items = await Future(system.list);
      _items
        ..clear()
        ..addAll(items);
      notifyListeners();
    } else if (_trashDir != null) {
      await _loadMeta();
    }
  }

  /// Surveille `info/` de la corbeille personnelle : un élément mis à la
  /// corbeille (ou restauré) par le gestionnaire de fichiers apparaît sans
  /// relancer l'application.
  void _startWatching() {
    final info = Directory(p.join(_system!.homeTrash, 'info'));
    try {
      info.createSync(recursive: true);
      _watch = info.watch().listen((_) {
        _reloadDebounce?.cancel();
        _reloadDebounce =
            Timer(const Duration(milliseconds: 300), () => reload());
      }, onError: (_) {});
    } catch (e) {
      debugPrint('[Trash] surveillance impossible : $e');
    }
  }

  Future<void> _stopWatching() async {
    _reloadDebounce?.cancel();
    await _watch?.cancel();
    _watch = null;
  }

  // ── Persistance ───────────────────────────────────────────────────────────

  File get _metaFile =>
      File(p.join(_trashDir!.path, AppConstants.trashMetaFile));

  /// Charge l'index puis le réconcilie avec le contenu réel du dossier.
  Future<void> _loadMeta() async {
    _items.clear();
    final metaFile = _metaFile;
    var changed = false;
    if (metaFile.existsSync()) {
      try {
        final json = jsonDecode(await metaFile.readAsString()) as List;
        _items.addAll(
            json.map((e) => TrashItem.fromMap(e as Map<String, dynamic>)));
      } catch (e) {
        // Index illisible : on le met de côté (jamais écrasé) ; les fichiers
        // de la corbeille réapparaissent comme orphelins ci-dessous.
        final aside = '${metaFile.path}.corrupt-'
            '${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('[Trash] index illisible, conservé dans $aside');
        await metaFile.rename(aside);
        changed = true;
      }
    }

    // Entrées dont le fichier a disparu (application tuée avant le
    // déplacement, suppression externe…).
    final before = _items.length;
    _items.removeWhere((i) =>
        FileSystemEntity.typeSync(i.trashedPath, followLinks: false) ==
        FileSystemEntityType.notFound);
    changed |= _items.length != before;

    // Fichiers présents mais absents de l'index : listés comme orphelins
    // pour pouvoir au moins les supprimer.
    final known = _items.map((i) => i.trashedPath).toSet();
    for (final e in _trashDir!.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      // Fichiers cachés : index, temporaires, index mis de côté.
      if (name.startsWith('.')) continue;
      if (known.contains(e.path)) continue;
      final type = FileSystemEntity.typeSync(e.path, followLinks: false);
      _items.add(TrashItem(
        trashedPath: e.path,
        originalPath: '',
        deletedAt: e.statSync().modified,
        isDirectory: type == FileSystemEntityType.directory,
        size: type == FileSystemEntityType.file ? e.statSync().size : 0,
      ));
      changed = true;
    }

    if (changed) await _saveMetaQuietly();
    notifyListeners();
  }

  Future<void> _saveMeta() => AtomicWrite.string(
      _metaFile.path, jsonEncode(_items.map((e) => e.toMap()).toList()));

  /// Sauvegarde de l'index quand l'échec ne doit pas masquer l'erreur
  /// principale : au pire, la réconciliation corrigera au prochain lancement.
  Future<void> _saveMetaQuietly() async {
    try {
      await _saveMeta();
    } catch (e) {
      debugPrint('[Trash] index non sauvegardé : $e');
    }
  }

  /// Retire [item] de l'index (son contenu n'est plus dans la corbeille).
  Future<void> _forget(TrashItem item) async {
    _items.remove(item);
    if (_system == null) await _saveMetaQuietly();
    notifyListeners();
  }

  Future<void> _ensureInit() async {
    if (_trashDir == null && _system == null) await init();
  }

  static String _describe(Object e) => switch (e) {
        FileOpException(:final message) => message,
        FileSystemException(:final message, :final osError) =>
          osError?.message.isNotEmpty == true ? osError!.message : message,
        _ => e.toString(),
      };
}
