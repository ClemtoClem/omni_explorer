/// @file xdg_trash.dart
/// @brief Corbeille du système sous Linux (spécification freedesktop.org
/// « Trash »), partagée avec Nautilus, Dolphin, Nemo, `gio trash`…
///
/// - Corbeille personnelle : `$XDG_DATA_HOME/Trash` (par défaut
///   `~/.local/share/Trash`), avec `files/` (le contenu) et `info/` (un
///   fichier `.trashinfo` par élément : chemin d'origine et date).
/// - Un élément d'un autre disque (partition, clé USB…) va dans la corbeille
///   de ce disque, `<point de montage>/.Trash/<uid>` (si l'administrateur l'a
///   préparée) ou `<point de montage>/.Trash-<uid>` : pas de copie d'un
///   disque à l'autre.
/// - Le `.trashinfo` est créé AVANT le déplacement (création exclusive, qui
///   réserve aussi le nom) et supprimé APRÈS la restauration : le chemin
///   d'origine n'est jamais perdu.
///
/// Tout ce qu'un autre logiciel a mis dans ces corbeilles est listé.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../utils/file_naming.dart';
import 'file_operations_service.dart';

class XdgTrash {
  /// Corbeille personnelle (contient `files/` et `info/`).
  final String homeTrash;

  /// Identifiant numérique de l'utilisateur (noms `.Trash-<uid>`).
  final int uid;

  /// Points de montage du système (`/proc/self/mounts`), pour trouver le
  /// disque d'un fichier et les corbeilles des autres disques.
  final List<String> Function() _mountPoints;

  final _ops = const FileOperationsService();

  XdgTrash({
    required this.homeTrash,
    required this.uid,
    List<String> Function()? mountPoints,
  }) : _mountPoints = mountPoints ?? readMountPoints;

  /// Corbeille de l'utilisateur courant, d'après l'environnement.
  factory XdgTrash.forCurrentUser() {
    final env = Platform.environment;
    final home = env['HOME'] ?? '/';
    final dataHome = (env['XDG_DATA_HOME']?.isNotEmpty ?? false)
        ? env['XDG_DATA_HOME']!
        : p.join(home, '.local', 'share');
    return XdgTrash(homeTrash: p.join(dataHome, 'Trash'), uid: currentUid());
  }

  /// Uid réel, lu dans `/proc/self/status` (`Uid:  1000 1000 …`).
  static int currentUid() {
    try {
      for (final line in File('/proc/self/status').readAsLinesSync()) {
        if (line.startsWith('Uid:')) {
          return int.parse(line.split(RegExp(r'\s+'))[1]);
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Tous les points de montage (deuxième colonne de `/proc/self/mounts`).
  static List<String> readMountPoints() {
    try {
      return [
        for (final line in File('/proc/self/mounts').readAsLinesSync())
          if (line.split(' ') case [_, final mp, ...])
            mp.replaceAllMapped(RegExp(r'\\([0-7]{3})'),
                (m) => String.fromCharCode(int.parse(m[1]!, radix: 8))),
      ];
    } catch (_) {
      return const ['/'];
    }
  }

  // ── Emplacements ─────────────────────────────────────────────────────────

  /// Point de montage qui contient [path] (le plus long préfixe).
  String mountPointOf(String path) {
    var best = '/';
    for (final mp in _mountPoints()) {
      if ((mp == path || p.isWithin(mp, path)) && mp.length > best.length) {
        best = mp;
      }
    }
    return best;
  }

  /// Corbeille à utiliser pour [path] : la personnelle s'il est sur le même
  /// disque, sinon celle de son disque (créée au besoin), à défaut la
  /// personnelle (copie).
  String trashFor(String path) {
    final mp = mountPointOf(path);
    if (mp == mountPointOf(homeTrash)) return homeTrash;
    for (final candidate in [_adminTrash(mp), p.join(mp, '.Trash-$uid')]) {
      if (candidate == null) continue;
      try {
        for (final sub in ['files', 'info']) {
          Directory(p.join(candidate, sub)).createSync(recursive: true);
        }
        if (candidate.endsWith('.Trash-$uid')) {
          Process.runSync('chmod', ['700', candidate]);
        }
        return candidate;
      } catch (_) {
        // Disque en lecture seule, droits : essayer la suivante.
      }
    }
    return homeTrash;
  }

  /// `<mp>/.Trash/<uid>` si `<mp>/.Trash` est un vrai dossier avec le bit
  /// « sticky » (règle de sécurité de la spécification).
  String? _adminTrash(String mp) {
    final shared = p.join(mp, '.Trash');
    if (FileSystemEntity.typeSync(shared, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    final sticky = (FileStat.statSync(shared).mode & 0x200) != 0;
    return sticky ? p.join(shared, '$uid') : null;
  }

  /// Corbeilles existantes : la personnelle et celles des disques montés.
  List<String> existingTrashes() {
    final result = <String>[homeTrash];
    for (final mp in _mountPoints().toSet()) {
      for (final candidate in [
        _adminTrash(mp),
        p.join(mp, '.Trash-$uid'),
      ]) {
        if (candidate == null || result.contains(candidate)) continue;
        if (Directory(p.join(candidate, 'info')).existsSync()) {
          result.add(candidate);
        }
      }
    }
    return result;
  }

  /// Vrai si [path] est une corbeille ou se trouve dans l'une d'elles.
  bool isInsideTrash(String path) =>
      existingTrashes().any((t) => p.equals(t, path) || p.isWithin(t, path));

  // ── Lecture ──────────────────────────────────────────────────────────────

  /// Contenu de toutes les corbeilles, le plus récent d'abord. Un fichier
  /// sans `.trashinfo` est listé comme orphelin (origine inconnue).
  List<TrashItem> list() {
    final items = <TrashItem>[];
    for (final trash in existingTrashes()) {
      final topdir = trash == homeTrash ? null : _topdirOf(trash);
      final filesDir = p.join(trash, 'files');
      final infoDir = Directory(p.join(trash, 'info'));
      final described = <String>{};
      if (infoDir.existsSync()) {
        for (final e in infoDir.listSync(followLinks: false)) {
          if (e is! File || !e.path.endsWith('.trashinfo')) continue;
          final name = p.basenameWithoutExtension(e.path);
          final trashed = p.join(filesDir, name);
          final type = FileSystemEntity.typeSync(trashed, followLinks: false);
          // .trashinfo sans contenu (corbeille vidée par un autre logiciel
          // interrompu) : ignoré.
          if (type == FileSystemEntityType.notFound) continue;
          final info = parseTrashInfo(e.readAsStringSync());
          if (info == null) continue;
          described.add(name);
          var origin = info.path;
          if (!p.isAbsolute(origin)) {
            origin = p.join(topdir ?? '/', origin);
          }
          items.add(_item(trashed, type, origin, info.deletedAt, e.path));
        }
      }
      final filesDirectory = Directory(filesDir);
      if (filesDirectory.existsSync()) {
        for (final e in filesDirectory.listSync(followLinks: false)) {
          if (described.contains(p.basename(e.path))) continue;
          final type = FileSystemEntity.typeSync(e.path, followLinks: false);
          items.add(_item(e.path, type, '', null, null));
        }
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  TrashItem _item(String trashed, FileSystemEntityType type, String origin,
      DateTime? deletedAt, String? infoPath) {
    FileStat? stat;
    try {
      stat = FileStat.statSync(trashed);
    } catch (_) {}
    return TrashItem(
      trashedPath: trashed,
      originalPath: origin,
      deletedAt: deletedAt ?? stat?.modified ?? DateTime(1970),
      isDirectory: type == FileSystemEntityType.directory,
      size: type == FileSystemEntityType.file ? (stat?.size ?? 0) : 0,
      infoPath: infoPath,
    );
  }

  /// Dossier racine du disque d'une corbeille `.Trash-<uid>` ou
  /// `.Trash/<uid>`.
  String _topdirOf(String trash) {
    final parent = p.dirname(trash);
    return p.basename(parent) == '.Trash' ? p.dirname(parent) : parent;
  }

  // ── Écriture ─────────────────────────────────────────────────────────────

  /// Met [path] à la corbeille de son disque. Lève [FileOpException] en cas
  /// d'échec : l'élément reste alors à sa place.
  Future<TrashItem> trash(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileOpException('« ${p.basename(path)} » n\'existe plus.');
    }
    if (isInsideTrash(path)) {
      throw const FileOpException('Cet élément est déjà dans la corbeille.');
    }
    if (p.isWithin(path, homeTrash)) {
      throw FileOpException('« ${p.basename(path)} » contient la corbeille : '
          'il ne peut pas y être déplacé.');
    }

    final trash = trashFor(path);
    final filesDir = p.join(trash, 'files');
    final infoDir = p.join(trash, 'info');
    await Directory(filesDir).create(recursive: true);
    await Directory(infoDir).create(recursive: true);

    // Chemin enregistré : relatif au disque pour une corbeille de disque
    // (le disque peut être monté ailleurs la prochaine fois).
    final stored =
        trash == homeTrash ? path : p.relative(path, from: _topdirOf(trash));
    final deletedAt = DateTime.now();
    final size =
        type == FileSystemEntityType.file ? File(path).lengthSync() : 0;

    // 1. Réserver le nom en créant le .trashinfo (création exclusive).
    final name = p.basename(path);
    late String chosen;
    late File info;
    for (var candidate = name;;) {
      final f = File(p.join(infoDir, '$candidate.trashinfo'));
      final taken = FileSystemEntity.typeSync(p.join(filesDir, candidate),
              followLinks: false) !=
          FileSystemEntityType.notFound;
      if (!taken) {
        try {
          await f.create(exclusive: true);
          chosen = candidate;
          info = f;
          break;
        } on FileSystemException {
          // Nom pris entre-temps (autre logiciel) : suivant.
        }
      }
      candidate = FileNaming.numbered(
          candidate,
          (c) =>
              File(p.join(infoDir, '$c.trashinfo')).existsSync() ||
              FileSystemEntity.typeSync(p.join(filesDir, c),
                      followLinks: false) !=
                  FileSystemEntityType.notFound,
          isDirectory: type == FileSystemEntityType.directory);
    }
    try {
      await info.writeAsString(formatTrashInfo(stored, deletedAt), flush: true);
    } catch (e) {
      await _deleteQuietly(info);
      throw FileOpException('Corbeille indisponible : ${_describe(e)}');
    }

    // 2. Déplacer le contenu (renommage sur le même disque ; copie puis
    //    suppression vers la corbeille personnelle sinon).
    final target = p.join(filesDir, chosen);
    try {
      await _ops.relocate(path, target, move: true);
    } on PartialMoveException catch (e) {
      // Copie complète dans la corbeille : on la garde (seul exemplaire
      // complet), avec son .trashinfo.
      throw FileOpException('« $name » a été copié dans la corbeille, mais '
          'l\'original n\'a pas pu être supprimé : ${e.message}');
    } catch (e) {
      await _deleteQuietly(info);
      throw FileOpException(
          'Impossible de mettre « $name » à la corbeille : ${_describe(e)}');
    }
    return TrashItem(
      trashedPath: target,
      originalPath: path,
      deletedAt: deletedAt,
      isDirectory: type == FileSystemEntityType.directory,
      size: size,
      infoPath: info.path,
    );
  }

  /// Restaure [item] à son emplacement d'origine. Retourne le chemin de
  /// restauration, ou `null` si l'utilisateur a choisi d'ignorer.
  Future<String?> restore(TrashItem item,
      {ConflictResolver? onConflict}) async {
    await Directory(p.dirname(item.originalPath)).create(recursive: true);
    final restoredTo = await _ops.relocate(item.trashedPath, item.originalPath,
        move: true, onConflict: onConflict);
    if (restoredTo != null && item.infoPath != null) {
      await _deleteQuietly(File(item.infoPath!));
    }
    return restoredTo;
  }

  /// Supprime définitivement [item] (contenu puis description).
  Future<void> delete(TrashItem item) async {
    final report = await _ops.deletePermanently([item.trashedPath]);
    if (report.hasFailures) {
      throw FileOpException('Impossible de supprimer « ${item.name} » : '
          '${report.failures.single.reason}');
    }
    if (item.infoPath != null) await _deleteQuietly(File(item.infoPath!));
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static String _describe(Object e) => switch (e) {
        FileOpException(:final message) => message,
        FileSystemException(:final message, :final osError) =>
          osError?.message.isNotEmpty == true ? osError!.message : message,
        _ => e.toString(),
      };

  // ── Format .trashinfo ────────────────────────────────────────────────────

  /// Contenu d'un `.trashinfo` : chemin encodé comme une URL, date locale
  /// `AAAA-MM-JJThh:mm:ss`.
  static String formatTrashInfo(String path, DateTime deletedAt) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    String two(int v) => v.toString().padLeft(2, '0');
    final d = deletedAt.toLocal();
    final date = '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-'
        '${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    return '[Trash Info]\nPath=$encoded\nDeletionDate=$date\n';
  }

  /// Lit un `.trashinfo` ; `null` s'il est invalide.
  static ({String path, DateTime? deletedAt})? parseTrashInfo(String text) {
    var inSection = false;
    String? path;
    DateTime? date;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inSection = line == '[Trash Info]';
        continue;
      }
      if (!inSection) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (key == 'Path' && path == null) {
        try {
          path = Uri.decodeComponent(value);
        } catch (_) {
          path = value;
        }
      } else if (key == 'DeletionDate' && date == null) {
        date = DateTime.tryParse(value);
      }
    }
    if (path == null || path.isEmpty) return null;
    return (path: path, deletedAt: date);
  }
}
