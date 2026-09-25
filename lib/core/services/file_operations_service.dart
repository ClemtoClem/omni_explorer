/// @file file_operations_service.dart
/// @brief Opérations sur les fichiers (créer, renommer, copier, déplacer,
/// supprimer) sans écrasement silencieux ni perte de données.
///
/// Règles appliquées partout :
/// - les noms saisis sont validés (pas de `/`, `..`, caractère nul…) ;
/// - un élément existant n'est jamais écrasé sans décision explicite
///   ([ConflictAction.replace]) ;
/// - les liens symboliques sont copiés / déplacés / supprimés en tant que
///   liens : leur cible n'est jamais parcourue ni modifiée ;
/// - une copie ratée ne laisse pas de résultat partiel ;
/// - chaque échec est rapporté (chemin + raison) au lieu d'être ignoré.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Erreur d'une opération unitaire, avec un message destiné à l'utilisateur.
class FileOpException implements Exception {
  final String message;
  const FileOpException(this.message);

  @override
  String toString() => message;
}

/// Déplacement entre stockages dont la copie a réussi mais dont l'original
/// n'a pas pu être (entièrement) supprimé. La copie à [destination] est
/// complète et conservée : l'original a pu être partiellement supprimé,
/// la copie est alors le seul exemplaire complet.
class PartialMoveException extends FileOpException {
  final String destination;
  const PartialMoveException(super.message, this.destination);
}

/// Décision quand la destination existe déjà.
enum ConflictAction {
  /// Garder les deux : la copie reçoit un nom libre (« x (copie).txt »).
  keepBoth,

  /// Remplacer l'élément existant.
  replace,

  /// Ne pas traiter cet élément.
  skip,
}

/// Demande à l'utilisateur quoi faire pour [source] → [destination] existante.
typedef ConflictResolver = Future<ConflictAction> Function(
    String source, String destination);

/// Échec d'un élément dans une opération groupée.
class FileOpFailure {
  final String path;
  final String reason;
  const FileOpFailure(this.path, this.reason);

  @override
  String toString() => '$path : $reason';
}

/// Bilan d'une opération groupée.
class FileOpReport {
  /// Chemins sources traités avec succès.
  final List<String> succeeded = [];

  /// Chemins sources volontairement non traités (conflit « ignorer », déjà
  /// à destination…).
  final List<String> skipped = [];

  final List<FileOpFailure> failures = [];

  bool get hasFailures => failures.isNotEmpty;
}

/// Validation des noms de fichiers saisis par l'utilisateur.
class FileNameValidator {
  FileNameValidator._();

  /// Longueur maximale d'un nom sur les systèmes de fichiers courants.
  static const int maxNameBytes = 255;

  /// Retourne un message d'erreur, ou `null` si [name] est valide.
  static String? validate(String name) {
    if (name.trim().isEmpty) return 'Le nom ne peut pas être vide.';
    if (name == '.' || name == '..') return 'Nom réservé.';
    if (name.contains('/')) return 'Le nom ne peut pas contenir « / ».';
    if (name.contains('\u0000')) return 'Caractère non autorisé.';
    if (utf8.encode(name).length > maxNameBytes) return 'Nom trop long.';
    return null;
  }
}

class FileOperationsService {
  const FileOperationsService();

  // ── Création ──────────────────────────────────────────────────────────────

  /// Crée le dossier [name] dans [parent] ; erreur s'il existe déjà.
  Future<String> createDirectory(String parent, String name) async {
    final path = _validatedChild(parent, name);
    _ensureAbsent(path, name);
    try {
      // Non récursif : échoue plutôt que de créer des parents inattendus.
      await Directory(path).create();
    } on FileSystemException catch (e) {
      throw FileOpException('Impossible de créer « $name » : ${_reason(e)}');
    }
    return path;
  }

  /// Crée le fichier vide [name] dans [parent] ; erreur s'il existe déjà.
  Future<String> createFile(String parent, String name) async {
    final path = _validatedChild(parent, name);
    _ensureAbsent(path, name);
    try {
      // exclusive : échoue si un fichier est apparu entre-temps.
      await File(path).create(exclusive: true);
    } on FileSystemException catch (e) {
      throw FileOpException('Impossible de créer « $name » : ${_reason(e)}');
    }
    return path;
  }

  // ── Renommage ─────────────────────────────────────────────────────────────

  /// Renomme [path] en [newName] (même dossier) et retourne le nouveau chemin.
  ///
  /// Refuse si un autre élément porte déjà ce nom : `rename` l'écraserait
  /// sans avertissement. Un changement de casse seule (`a.txt` → `A.txt`)
  /// est permis, y compris sur les stockages insensibles à la casse.
  Future<String> rename(String path, String newName) async {
    final type = _typeOf(path);
    if (type == FileSystemEntityType.notFound) {
      throw FileOpException('« ${p.basename(path)} » n\'existe plus.');
    }
    final dest = _validatedChild(p.dirname(path), newName);
    if (dest == path) return path;

    try {
      if (_typeOf(dest) != FileSystemEntityType.notFound) {
        if (!_isSameEntry(path, dest)) {
          throw FileOpException('Un élément « $newName » existe déjà.');
        }
        // Même entrée sous une autre casse : passage par un nom temporaire.
        final tmp = _freeTempPath(p.dirname(path), newName);
        await _entity(path, type).rename(tmp);
        await _entity(tmp, type).rename(dest);
      } else {
        await _entity(path, type).rename(dest);
      }
    } on FileSystemException catch (e) {
      throw FileOpException(
          'Impossible de renommer « ${p.basename(path)} » : ${_reason(e)}');
    }
    return dest;
  }

  // ── Copie / déplacement ───────────────────────────────────────────────────

  /// Copie ([move] = false) ou déplace [sources] dans [destDir].
  ///
  /// En cas de conflit, [onConflict] décide ; sans résolveur, les deux
  /// éléments sont gardés. Copier un élément dans son propre dossier crée
  /// toujours une copie nommée « (copie) ».
  Future<FileOpReport> transfer(
    List<String> sources,
    String destDir, {
    required bool move,
    ConflictResolver? onConflict,
  }) async {
    final report = FileOpReport();
    for (final src in sources) {
      try {
        final done = await _transferOne(src, destDir,
            move: move, onConflict: onConflict);
        (done ? report.succeeded : report.skipped).add(src);
      } on FileOpException catch (e) {
        report.failures.add(FileOpFailure(src, e.message));
      } on FileSystemException catch (e) {
        report.failures.add(FileOpFailure(src, _reason(e)));
      }
    }
    return report;
  }

  /// Retourne `false` si l'élément a été volontairement ignoré.
  Future<bool> _transferOne(
    String src,
    String destDir, {
    required bool move,
    ConflictResolver? onConflict,
  }) async {
    if (_typeOf(src) == FileSystemEntityType.notFound) {
      throw const FileOpException('élément introuvable');
    }
    // Déplacer vers son propre dossier : rien à faire.
    if (move && p.equals(p.dirname(src), destDir)) return false;
    final dest = p.join(destDir, p.basename(src));
    // Copie dans le même dossier : toujours une nouvelle copie, sans demander.
    final sameEntry = p.equals(dest, src);
    final placed = await relocate(src, dest,
        move: move,
        onConflict:
            sameEntry ? (_, __) async => ConflictAction.keepBoth : onConflict);
    return placed != null;
  }

  /// Copie ou déplace [src] vers le chemin exact [dest].
  ///
  /// Si [dest] existe, [onConflict] décide (sans résolveur : garder les deux,
  /// la copie recevant un nom libre). Retourne le chemin final, ou `null` si
  /// l'élément a été ignoré. Lève [FileOpException] ou
  /// [FileSystemException] en cas d'échec, sans jamais laisser de copie
  /// partielle ni écraser un élément sans décision explicite.
  Future<String?> relocate(
    String src,
    String dest, {
    required bool move,
    ConflictResolver? onConflict,
  }) async {
    final type = _typeOf(src);
    if (type == FileSystemEntityType.notFound) {
      throw const FileOpException('élément introuvable');
    }
    if (type == FileSystemEntityType.directory &&
        _isInside(p.dirname(dest), src)) {
      throw const FileOpException(
          'impossible de placer un dossier dans lui-même');
    }
    if (_typeOf(dest) != FileSystemEntityType.notFound) {
      final action = await (onConflict?.call(src, dest) ??
          Future.value(ConflictAction.keepBoth));
      switch (action) {
        case ConflictAction.skip:
          return null;
        case ConflictAction.keepBoth:
          dest = uniqueDestination(p.dirname(dest), p.basename(dest),
              keepExtension: type != FileSystemEntityType.directory);
        case ConflictAction.replace:
          await _replace(src, dest, type, move: move);
          return dest;
      }
    }
    await _place(src, dest, type, move: move);
    return dest;
  }

  /// Copie ou déplace [src] vers [dest], qui n'existe pas.
  Future<void> _place(String src, String dest, FileSystemEntityType type,
      {required bool move}) async {
    if (move) {
      try {
        await _entity(src, type).rename(dest);
        return;
      } on FileSystemException catch (e) {
        // Seul un changement de stockage (carte SD…) justifie le repli
        // « copie puis suppression » ; toute autre erreur (permission,
        // lecture seule…) est remontée telle quelle, sans rien copier.
        if (!_isCrossDevice(e)) rethrow;
      }
    }
    await _copyOrClean(src, dest, type);
    if (move) {
      try {
        await _deleteEntity(src, type);
      } on FileSystemException catch (e) {
        throw PartialMoveException(
            'copié, mais l\'original n\'a pas pu être supprimé '
            '(${_reason(e)})',
            dest);
      }
    }
  }

  /// Vrai si [e] signale un `rename` entre deux systèmes de fichiers.
  static bool _isCrossDevice(FileSystemException e) {
    final code = e.osError?.errorCode;
    // EXDEV = 18 (Linux, Android, macOS) ; ERROR_NOT_SAME_DEVICE = 17.
    return code == (Platform.isWindows ? 17 : 18);
  }

  /// Remplace [dest] (existant) par [src] sans jamais perdre les deux : la
  /// source est d'abord placée sous un nom temporaire, puis l'ancien élément
  /// est supprimé, puis le temporaire prend le nom définitif.
  Future<void> _replace(String src, String dest, FileSystemEntityType type,
      {required bool move}) async {
    if (p.isWithin(dest, src)) {
      throw const FileOpException('l\'élément à remplacer contient la source');
    }
    final tmp = _freeTempPath(p.dirname(dest), p.basename(dest));
    await _place(src, tmp, type, move: move);
    try {
      await _deleteEntity(dest, _typeOf(dest));
    } on FileSystemException catch (e) {
      // Annule : la source retrouve sa place (déplacement) ou la copie
      // temporaire est retirée (copie).
      if (move) {
        await _place(tmp, src, type, move: true);
      } else {
        await _deleteEntity(tmp, type);
      }
      throw FileOpException('impossible de remplacer : ${_reason(e)}');
    }
    await _entity(tmp, type).rename(dest);
  }

  /// Copie [src] vers [dest] ; en cas d'échec, retire la copie partielle
  /// ([dest] n'existait pas, elle n'appartient qu'à cette opération).
  Future<void> _copyOrClean(
      String src, String dest, FileSystemEntityType type) async {
    try {
      await _copyEntity(src, dest, type);
    } catch (_) {
      final created = _typeOf(dest);
      if (created != FileSystemEntityType.notFound) {
        await _deleteEntity(dest, created);
      }
      rethrow;
    }
  }

  Future<void> _copyEntity(
      String src, String dest, FileSystemEntityType type) async {
    switch (type) {
      case FileSystemEntityType.link:
        // Le lien est recréé tel quel ; sa cible n'est pas copiée.
        await Link(dest).create(await Link(src).target());
      case FileSystemEntityType.directory:
        await Directory(dest).create();
        await for (final child in Directory(src).list(followLinks: false)) {
          final childType = _typeOf(child.path);
          await _copyEntity(
              child.path, p.join(dest, p.basename(child.path)), childType);
        }
      default:
        await File(src).copy(dest);
    }
  }

  // ── Suppression définitive ────────────────────────────────────────────────

  /// Supprime définitivement [paths] (sans corbeille).
  Future<FileOpReport> deletePermanently(List<String> paths) async {
    final report = FileOpReport();
    for (final path in paths) {
      final type = _typeOf(path);
      if (type == FileSystemEntityType.notFound) {
        report.skipped.add(path);
        continue;
      }
      try {
        await _deleteEntity(path, type);
        report.succeeded.add(path);
      } on FileSystemException catch (e) {
        report.failures.add(FileOpFailure(path, _reason(e)));
      }
    }
    return report;
  }

  Future<void> _deleteEntity(String path, FileSystemEntityType type) async {
    switch (type) {
      case FileSystemEntityType.link:
        await Link(path).delete(); // supprime le lien, pas sa cible
      case FileSystemEntityType.directory:
        // Les liens contenus sont supprimés, jamais suivis.
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.notFound:
        return;
      default:
        await File(path).delete();
    }
  }

  // ── Noms ──────────────────────────────────────────────────────────────────

  /// Premier chemin libre dans [dir] pour [name] : « x (copie).txt »,
  /// « x (copie 2).txt »… Avec [keepExtension] à `false` (dossiers), le
  /// suffixe va à la fin : « photos.2023 (copie) ».
  static String uniqueDestination(String dir, String name,
      {bool keepExtension = true}) {
    var dest = p.join(dir, name);
    if (_typeOf(dest) == FileSystemEntityType.notFound) return dest;
    // « .bashrc » n'a pas d'extension, « .config.json » a « .json ».
    final hasExt =
        keepExtension && (!name.startsWith('.') || name.indexOf('.', 1) > 0);
    final ext = hasExt ? p.extension(name) : '';
    final base = name.substring(0, name.length - ext.length);
    for (var i = 1;; i++) {
      final suffix = i == 1 ? ' (copie)' : ' (copie $i)';
      dest = p.join(dir, '$base$suffix$ext');
      if (_typeOf(dest) == FileSystemEntityType.notFound) return dest;
    }
  }

  static String _freeTempPath(String dir, String name) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0;; i++) {
      final tmp = p.join(dir, '.$name.omni-tmp-$stamp-$i');
      if (_typeOf(tmp) == FileSystemEntityType.notFound) return tmp;
    }
  }

  String _validatedChild(String parent, String name) {
    final error = FileNameValidator.validate(name);
    if (error != null) throw FileOpException(error);
    return p.join(parent, name);
  }

  void _ensureAbsent(String path, String name) {
    if (_typeOf(path) != FileSystemEntityType.notFound) {
      throw FileOpException('Un élément « $name » existe déjà.');
    }
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────

  /// Type SANS suivre les liens : un lien est vu comme un lien.
  static FileSystemEntityType _typeOf(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false);

  static FileSystemEntity _entity(String path, FileSystemEntityType type) =>
      switch (type) {
        FileSystemEntityType.link => Link(path),
        FileSystemEntityType.directory => Directory(path),
        _ => File(path),
      };

  /// Vrai si [a] et [b] sont la même entrée vue sous deux casses (stockage
  /// insensible à la casse). Les liens sont exclus : `identicalSync` les
  /// suivrait et confondrait un lien avec sa cible.
  static bool _isSameEntry(String a, String b) {
    if (p.basename(a).toLowerCase() != p.basename(b).toLowerCase()) {
      return false;
    }
    if (_typeOf(a) == FileSystemEntityType.link ||
        _typeOf(b) == FileSystemEntityType.link) {
      return false;
    }
    try {
      return FileSystemEntity.identicalSync(a, b);
    } on FileSystemException {
      return false;
    }
  }

  /// Vrai si [path] est [dir] ou se trouve dedans, en comparant les chemins
  /// réels (le dossier courant peut avoir été atteint par un lien).
  static bool _isInside(String path, String dir) {
    String real(String x) {
      try {
        return Directory(x).resolveSymbolicLinksSync();
      } on FileSystemException {
        return p.normalize(p.absolute(x));
      }
    }

    final rp = real(path), rd = real(dir);
    return p.equals(rp, rd) || p.isWithin(rd, rp);
  }

  static String _reason(FileSystemException e) {
    final os = e.osError;
    if (os == null) return e.message;
    switch (os.errorCode) {
      case 13: // EACCES
      case 1: // EPERM
        return 'permission refusée';
      case 28: // ENOSPC
        return 'espace de stockage insuffisant';
      case 30: // EROFS
        return 'stockage en lecture seule';
      case 2: // ENOENT
        return 'élément introuvable';
      default:
        return os.message.isEmpty ? e.message : os.message;
    }
  }
}
