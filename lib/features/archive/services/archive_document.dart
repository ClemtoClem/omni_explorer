/// @file archive_document.dart
/// @brief Archive ouverte et modifiable, comme un dossier de l'explorateur :
/// ajouter des fichiers et dossiers, créer un dossier, renommer, déplacer,
/// dupliquer, supprimer, mettre à jour depuis un dossier du disque.
///
/// Les opérations modifient le document en mémoire ; [ArchiveDocument.save]
/// réécrit l'archive de façon atomique (l'ancienne reste intacte en cas
/// d'échec). Le contenu des entrées n'est lu qu'à l'enregistrement (depuis
/// l'archive d'origine ou depuis le disque pour les fichiers ajoutés).
///
/// Formats modifiables : ZIP (et dérivés), TAR, TAR.GZ, TAR.BZ2 — voir
/// [ArchiveTypeExt.canEdit]. Chemins internes normalisés comme dans
/// [ArchiveTree] ; les noms saisis sont validés ([FileNameValidator]).

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:path/path.dart' as p;

import '../../../core/services/file_operations_service.dart';
import '../../../core/utils/atomic_write.dart';
import '../../../core/utils/file_naming.dart';
import '../models/archive_entry.dart';
import '../models/archive_tree.dart';
import 'archive_service.dart';

/// Contenu d'un fichier, lu seulement quand il faut l'écrire ou le comparer.
abstract class _Content {
  Uint8List read();
}

class _FromArchive implements _Content {
  final arc.ArchiveFile file;
  _FromArchive(this.file);
  @override
  Uint8List read() => file.readBytes() ?? Uint8List(0);
}

class _FromDisk implements _Content {
  final String path;
  _FromDisk(this.path);
  @override
  Uint8List read() => File(path).readAsBytesSync();
}

class _Entry {
  final String path;
  final bool isDirectory;
  final _Content? content;
  final int size;
  final DateTime modified;
  final int? mode;

  const _Entry({
    required this.path,
    required this.isDirectory,
    this.content,
    this.size = 0,
    required this.modified,
    this.mode,
  });

  _Entry movedTo(String newPath) => _Entry(
        path: newPath,
        isDirectory: isDirectory,
        content: content,
        size: size,
        modified: modified,
        mode: mode,
      );
}

/// Bilan d'une opération sur les entrées.
class ArchiveEditReport {
  int added = 0;
  int replaced = 0;
  int skipped = 0;

  /// Éléments non traités, avec la raison.
  final List<String> failures = [];
}

/// Bilan d'une mise à jour depuis un dossier.
class ArchiveSyncReport {
  int added = 0;
  int updated = 0;
  int unchanged = 0;

  /// Liens symboliques et éléments exclus, non ajoutés.
  int skipped = 0;
}

class ArchiveDocument {
  final String path;
  final ArchiveType type;
  String? _password;

  /// Entrées explicites (fichiers et dossiers), par chemin normalisé.
  final Map<String, _Entry> _entries;

  ArchiveDocument._(this.path, this.type, this._password, this._entries);

  bool get canEdit => type.canEdit;
  String? get password => _password;

  // ── Ouverture ───────────────────────────────────────────────────────────

  /// Ouvre [archivePath] (formats lisibles par le paquet `archive`).
  static Future<ArchiveDocument> open(String archivePath,
      {String? password}) async {
    final type = ArchiveService.detectType(archivePath);
    final bytes = await File(archivePath).readAsBytes();
    final entries = <String, _Entry>{};
    if (type.isSingleFile) {
      final data = switch (type) {
        ArchiveType.gz => const arc.GZipDecoder().decodeBytes(bytes),
        ArchiveType.bz2 => arc.BZip2Decoder().decodeBytes(bytes),
        _ => arc.XZDecoder().decodeBytes(bytes),
      };
      final name = p.basenameWithoutExtension(archivePath);
      entries[name] = _Entry(
        path: name,
        isDirectory: false,
        content: _FromArchive(arc.ArchiveFile.bytes(name, data)),
        size: data.length,
        modified: File(archivePath).statSync().modified,
      );
      return ArchiveDocument._(archivePath, type, password, entries);
    }

    final archive = _decode(type, bytes, password);
    if (type == ArchiveType.zip || type == ArchiveType.jar) {
      _checkPassword(archive, password);
    }
    for (final f in archive.files) {
      if (f.isSymbolicLink) continue; // jamais recréés (voir P0.1)
      final key = ArchiveTree.normalize(f.name);
      if (key.isEmpty) continue;
      entries[key] = _Entry(
        path: key,
        isDirectory: !f.isFile,
        content: f.isFile ? _FromArchive(f) : null,
        size: f.isFile ? f.size : 0,
        modified: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000),
        mode: f.mode,
      );
    }
    return ArchiveDocument._(archivePath, type, password, entries);
  }

  /// Lit un fichier et contrôle son CRC32 : un ZIP chiffré ouvert sans
  /// mot de passe, ou avec un mauvais, échoue ici plutôt qu'à l'extraction
  /// (ZipCrypto peut produire un contenu faux sans lever d'erreur).
  static void _checkPassword(arc.Archive archive, String? password) {
    final probe = archive.files
        .where((f) => f.isFile && !f.isSymbolicLink && f.size > 0)
        .firstOrNull;
    if (probe == null) return;
    bool ok;
    try {
      final data = probe.readBytes();
      ok = data != null &&
          (probe.crc32 == null || arc.getCrc32(data) == probe.crc32);
    } catch (_) {
      ok = false; // déchiffrement impossible : mot de passe absent ou faux
    }
    if (!ok) {
      throw ArchiveOpException(
          password == null
              ? 'Cette archive est protégée par un mot de passe.'
              : 'Mot de passe incorrect.',
          isPasswordRequired: true);
    }
  }

  static arc.Archive _decode(ArchiveType type, List<int> bytes, String? pw) {
    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
        return arc.ZipDecoder().decodeBytes(bytes, password: pw);
      case ArchiveType.tar:
        return arc.TarDecoder().decodeBytes(bytes);
      case ArchiveType.tarGz:
        return arc.TarDecoder()
            .decodeBytes(const arc.GZipDecoder().decodeBytes(bytes));
      case ArchiveType.tarBz2:
        return arc.TarDecoder()
            .decodeBytes(arc.BZip2Decoder().decodeBytes(bytes));
      case ArchiveType.tarXz:
        return arc.TarDecoder().decodeBytes(arc.XZDecoder().decodeBytes(bytes));
      default:
        throw ArchiveOpException(
            '${type.label} : format non pris en charge ici.');
    }
  }

  // ── Lecture ─────────────────────────────────────────────────────────────

  /// Arborescence actuelle (dossiers implicites compris).
  ArchiveTree get tree =>
      ArchiveTree.fromEntries(_entries.values.map((e) => RawArchiveEntry(
          name: e.path,
          isDirectory: e.isDirectory,
          size: e.size,
          modified: e.modified)));

  bool _isDir(String path) =>
      path.isEmpty ||
      (_entries[path]?.isDirectory ?? false) ||
      _entries.keys.any((k) => k.startsWith('$path/'));

  bool exists(String path) {
    final key = ArchiveTree.normalize(path);
    return _entries.containsKey(key) || _isDir(key) && key.isNotEmpty;
  }

  /// Contenu du fichier [path] de l'archive.
  Uint8List readFile(String path) {
    final e = _entries[ArchiveTree.normalize(path)];
    if (e == null || e.isDirectory) {
      throw ArchiveOpException('« $path » n\'est pas un fichier.');
    }
    return e.content!.read();
  }

  // ── Opérations ──────────────────────────────────────────────────────────

  void _requireEditable() {
    if (!canEdit) {
      throw ArchiveOpException(type.readOnlyReason ?? 'Lecture seule.');
    }
  }

  static String _join(String dir, String name) =>
      dir.isEmpty ? name : '$dir/$name';

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  String _validName(String name) {
    final error = FileNameValidator.validate(name);
    if (error != null) throw ArchiveOpException(error);
    return name;
  }

  /// Chemins de [path] et de tout son contenu.
  List<String> _subtree(String path) =>
      _entries.keys.where((k) => k == path || k.startsWith('$path/')).toList();

  void _removeSubtree(String path) {
    for (final k in _subtree(path)) {
      _entries.remove(k);
    }
  }

  /// Déplace [from] (et son contenu) vers [to], en copiant avec [copy].
  void _relocate(String from, String to, {required bool copy}) {
    final keys = _subtree(from);
    final isImplicitDir = keys.isEmpty && _isDir(from);
    if (keys.isEmpty && !isImplicitDir) {
      throw ArchiveOpException('« $from » n\'existe pas dans l\'archive.');
    }
    final moved = <String, _Entry>{
      for (final k in keys) to + k.substring(from.length): _entries[k]!,
    };
    if (!copy) {
      for (final k in keys) {
        _entries.remove(k);
      }
    }
    moved.forEach((k, e) => _entries[k] = e.movedTo(k));
  }

  /// Crée le dossier [name] dans [parent].
  void createFolder(String parent, String name) {
    _requireEditable();
    final dir = ArchiveTree.normalize(parent);
    final path = _join(dir, _validName(name));
    if (exists(path)) {
      throw ArchiveOpException('« $name » existe déjà dans ce dossier.');
    }
    _entries[path] =
        _Entry(path: path, isDirectory: true, modified: DateTime.now());
  }

  /// Renomme [path] (fichier ou dossier) en [newName], dans le même dossier.
  void rename(String path, String newName) {
    _requireEditable();
    final from = ArchiveTree.normalize(path);
    final to = _join(_parentOf(from), _validName(newName));
    if (to == from) return;
    if (exists(to)) {
      throw ArchiveOpException('« $newName » existe déjà dans ce dossier.');
    }
    _relocate(from, to, copy: false);
  }

  /// Supprime [paths] (et le contenu des dossiers).
  void delete(Iterable<String> paths) {
    _requireEditable();
    for (final path in paths) {
      _removeSubtree(ArchiveTree.normalize(path));
    }
  }

  /// Duplique [paths] dans leur dossier : « rapport.copy.1.txt ».
  ArchiveEditReport duplicate(Iterable<String> paths) {
    _requireEditable();
    final report = ArchiveEditReport();
    for (final path in paths) {
      final from = ArchiveTree.normalize(path);
      final name = FileNaming.copy(
          _nameOf(from), (c) => exists(_join(_parentOf(from), c)),
          isDirectory: _isDir(from));
      _relocate(from, _join(_parentOf(from), name), copy: true);
      report.added++;
    }
    return report;
  }

  /// Déplace [paths] dans le dossier [targetDir] de l'archive. Si le nom
  /// existe déjà, [onConflict] décide (sans résolveur : renommer en
  /// « nom.1.ext »).
  Future<ArchiveEditReport> move(Iterable<String> paths, String targetDir,
      {ConflictResolver? onConflict}) async {
    _requireEditable();
    final target = ArchiveTree.normalize(targetDir);
    final report = ArchiveEditReport();
    for (final path in paths) {
      final from = ArchiveTree.normalize(path);
      if (_parentOf(from) == target) {
        report.skipped++; // déjà dans ce dossier
        continue;
      }
      if (target == from || target.startsWith('$from/')) {
        report.failures.add('« ${_nameOf(from)} » : impossible de placer un '
            'dossier dans lui-même');
        continue;
      }
      var to = _join(target, _nameOf(from));
      if (exists(to)) {
        final action = await (onConflict?.call(from, to) ??
            Future.value(ConflictAction.keepBoth));
        switch (action) {
          case ConflictAction.skip:
            report.skipped++;
            continue;
          case ConflictAction.keepBoth:
            to = _join(
                target,
                FileNaming.numbered(
                    _nameOf(from), (c) => exists(_join(target, c)),
                    isDirectory: _isDir(from)));
          case ConflictAction.replace:
            _removeSubtree(to);
            report.replaced++;
        }
      }
      _relocate(from, to, copy: false);
      report.added++;
    }
    return report;
  }

  /// Ajoute les fichiers et dossiers du disque [diskPaths] dans [targetDir].
  /// Un dossier déjà présent est fusionné ; un fichier déjà présent est
  /// soumis à [onConflict] (sans résolveur : renommer en « nom.1.ext »). Les
  /// liens symboliques ne sont pas ajoutés.
  Future<ArchiveEditReport> addFromDisk(
      Iterable<String> diskPaths, String targetDir,
      {ConflictResolver? onConflict}) async {
    _requireEditable();
    final report = ArchiveEditReport();
    final target = ArchiveTree.normalize(targetDir);

    Future<void> add(String disk, String dir) async {
      final type = FileSystemEntity.typeSync(disk, followLinks: false);
      final name = p.basename(disk);
      switch (type) {
        case FileSystemEntityType.directory:
          final inArchive = _join(dir, name);
          if (_entries.containsKey(inArchive) &&
              !_entries[inArchive]!.isDirectory) {
            report.failures.add('« $name » : un fichier porte déjà ce nom');
            return;
          }
          final stat = FileStat.statSync(disk);
          _entries.putIfAbsent(
              inArchive,
              () => _Entry(
                  path: inArchive,
                  isDirectory: true,
                  modified: stat.modified,
                  mode: stat.mode & 0x1FF));
          final children = Directory(disk).listSync(followLinks: false)
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final child in children) {
            await add(child.path, inArchive);
          }
        case FileSystemEntityType.file:
          var to = _join(dir, name);
          if (exists(to)) {
            final action = _isDir(to)
                ? ConflictAction.keepBoth // un dossier n'est jamais remplacé
                : await (onConflict?.call(disk, to) ??
                    Future.value(ConflictAction.keepBoth));
            switch (action) {
              case ConflictAction.skip:
                report.skipped++;
                return;
              case ConflictAction.keepBoth:
                to = _join(
                    dir,
                    FileNaming.numbered(name, (c) => exists(_join(dir, c)),
                        isDirectory: false));
              case ConflictAction.replace:
                _entries[to] = _fileFromDisk(disk, to);
                report.replaced++;
                return;
            }
          }
          _entries[to] = _fileFromDisk(disk, to);
          report.added++;
        case FileSystemEntityType.link:
          report.skipped++;
        default:
          report.failures.add('« $name » : élément introuvable');
      }
    }

    for (final disk in diskPaths) {
      await add(disk, target);
    }
    return report;
  }

  _Entry _fileFromDisk(String disk, String path) {
    final stat = FileStat.statSync(disk);
    return _Entry(
      path: path,
      isDirectory: false,
      content: _FromDisk(disk),
      size: stat.size,
      modified: stat.modified,
      mode: stat.mode & 0x1FF,
    );
  }

  /// Met à jour l'archive depuis le dossier [diskDir] (sauvegarde d'un
  /// projet) : ajoute les fichiers absents, remplace ceux dont le contenu a
  /// changé, ne supprime rien. Le contenu de [diskDir] est placé dans
  /// [targetDir] (racine par défaut). Les noms présents dans [exclude]
  /// (ex. `build`, `.dart_tool`) sont ignorés à tous les niveaux.
  ArchiveSyncReport syncFromDirectory(String diskDir,
      {String targetDir = '', Set<String> exclude = const {}}) {
    _requireEditable();
    final report = ArchiveSyncReport();
    final root = ArchiveTree.normalize(targetDir);

    void walk(String dir, String inArchive) {
      final children = Directory(dir).listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final child in children) {
        final name = p.basename(child.path);
        final to = _join(inArchive, name);
        final type = FileSystemEntity.typeSync(child.path, followLinks: false);
        if (exclude.contains(name) || type == FileSystemEntityType.link) {
          report.skipped++;
          continue;
        }
        if (type == FileSystemEntityType.directory) {
          if (!_isDir(to)) {
            if (_entries.containsKey(to)) {
              // Un fichier de l'archive porte le nom d'un dossier du disque.
              report.skipped++;
              continue;
            }
            _entries[to] =
                _Entry(path: to, isDirectory: true, modified: DateTime.now());
          }
          walk(child.path, to);
        } else if (type == FileSystemEntityType.file) {
          final existing = _entries[to];
          if (existing == null) {
            if (_isDir(to)) {
              report.skipped++; // un dossier de l'archive porte ce nom
              continue;
            }
            _entries[to] = _fileFromDisk(child.path, to);
            report.added++;
          } else if (existing.isDirectory) {
            report.skipped++;
          } else if (_sameContent(existing, child.path)) {
            report.unchanged++;
          } else {
            _entries[to] = _fileFromDisk(child.path, to);
            report.updated++;
          }
        }
      }
    }

    walk(diskDir, root);
    return report;
  }

  static bool _sameContent(_Entry entry, String diskPath) {
    if (FileStat.statSync(diskPath).size != entry.size) return false;
    final a = entry.content!.read();
    final b = File(diskPath).readAsBytesSync();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Change le mot de passe (ZIP : chiffrement AES) ; `null` le retire.
  void setPassword(String? password) {
    _requireEditable();
    if (!(type == ArchiveType.zip || type == ArchiveType.jar)) {
      throw ArchiveOpException(
          '${type.label} : mot de passe non pris en charge.');
    }
    _password = (password == null || password.isEmpty) ? null : password;
  }

  // ── Enregistrement ──────────────────────────────────────────────────────

  /// Réécrit l'archive (atomique : l'ancienne reste intacte en cas d'échec).
  Future<void> save() async {
    _requireEditable();
    final archive = arc.Archive();
    final paths = _entries.keys.toList()..sort();
    for (final path in paths) {
      final e = _entries[path]!;
      final arc.ArchiveFile file;
      if (e.isDirectory) {
        file = arc.ArchiveFile.directory('$path/');
      } else {
        file = arc.ArchiveFile.bytes(path, e.content!.read());
      }
      file.lastModTime = e.modified.millisecondsSinceEpoch ~/ 1000;
      if (e.mode != null) file.mode = e.mode!;
      archive.addFile(file);
    }
    final Uint8List bytes = switch (type) {
      ArchiveType.zip ||
      ArchiveType.jar =>
        arc.ZipEncoder(password: _password).encodeBytes(archive),
      ArchiveType.tar => arc.TarEncoder().encodeBytes(archive),
      ArchiveType.tarGz => const arc.GZipEncoder()
          .encodeBytes(arc.TarEncoder().encodeBytes(archive)),
      ArchiveType.tarBz2 =>
        arc.BZip2Encoder().encodeBytes(arc.TarEncoder().encodeBytes(archive)),
      _ => throw ArchiveOpException(type.readOnlyReason ?? 'Lecture seule.'),
    };
    await AtomicWrite.bytes(path, bytes);
  }
}
