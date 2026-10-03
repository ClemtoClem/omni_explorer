import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart' as arc;
import 'package:path/path.dart' as p;
import '../../../core/services/file_operations_service.dart';
import '../../../core/utils/atomic_write.dart';
import '../../../core/utils/safe_path.dart';
import '../models/archive_entry.dart';
import '../models/archive_tree.dart';
import 'seven_zip/seven_zip_reader.dart';
import 'seven_zip/seven_zip_writer.dart';

typedef _ByteDecoder = List<int> Function(List<int>);

/// Service statique pour lire, extraire et créer des archives.
///
/// - ZIP / JAR / WAR / APK    → package Dart `archive`
/// - TAR / TAR.GZ / BZ2 / XZ  → package Dart `archive`
/// - 7Z                        → lecteur / écrivain intégrés (Dart pur) ;
///                               CLI `7z` en secours pour les méthodes
///                               rares (PPMd, BCJ2…), sous Linux
/// - RAR                       → CLI `unrar` / `rar`
class ArchiveService {
  ArchiveService._();

  // ── Détection du format ───────────────────────────────────────────────────

  /// Format de [path], d'après sa signature binaire (les 512 premiers
  /// octets), l'extension ne servant qu'en complément : un `.docx`, `.apk`
  /// ou `.epub` est reconnu comme ZIP, un fichier mal nommé aussi.
  static ArchiveType detectType(String path) {
    final byName = detectTypeByName(path);
    final List<int> head;
    try {
      final raf = File(path).openSync();
      try {
        head = raf.readSync(512);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return byName; // fichier absent ou illisible : l'extension seule
    }
    return detectTypeFromHeader(head, byName);
  }

  /// Format d'après l'en-tête [head], [byName] départageant les cas que la
  /// signature ne tranche pas (TAR compressé ou fichier compressé seul).
  static ArchiveType detectTypeFromHeader(List<int> head, ArchiveType byName) {
    bool starts(List<int> sig, [int at = 0]) {
      if (head.length < at + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (head[at + i] != sig[i]) return false;
      }
      return true;
    }

    ArchiveType compressed(ArchiveType single, ArchiveType tarred) =>
        byName == tarred ? tarred : single;

    if (starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06])) {
      return byName == ArchiveType.jar ? ArchiveType.jar : ArchiveType.zip;
    }
    if (starts([0x1F, 0x8B])) {
      return compressed(ArchiveType.gz, ArchiveType.tarGz);
    }
    if (starts([0x42, 0x5A, 0x68])) {
      return compressed(ArchiveType.bz2, ArchiveType.tarBz2);
    }
    if (starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
      return compressed(ArchiveType.xz, ArchiveType.tarXz);
    }
    if (starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
      return ArchiveType.sevenZip;
    }
    if (starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) return ArchiveType.rar;
    if (starts('ustar'.codeUnits, 257) || _isTarHeader(head)) {
      return ArchiveType.tar;
    }
    return byName;
  }

  /// En-tête TAR valide, y compris l'ancien format V7 sans marque « ustar »
  /// (celui qu'écrit le paquet `archive`) : la somme de contrôle (octets
  /// 148-155, en octal) égale la somme des 512 octets, ce champ compté comme
  /// des espaces.
  static bool _isTarHeader(List<int> head) {
    if (head.length < 512 || head[0] == 0) return false;
    final field = String.fromCharCodes(head.sublist(148, 156))
        .replaceAll('\u0000', ' ')
        .trim();
    final expected = int.tryParse(field, radix: 8);
    if (expected == null) return false;
    var sum = 0;
    for (var i = 0; i < 512; i++) {
      sum += (i >= 148 && i < 156) ? 0x20 : head[i];
    }
    return sum == expected;
  }

  /// Format d'après l'extension seule (fichier à créer, ou illisible).
  static ArchiveType detectTypeByName(String path) {
    final lo = path.toLowerCase();
    if (lo.endsWith('.tar.gz') || lo.endsWith('.tgz')) return ArchiveType.tarGz;
    if (lo.endsWith('.tar.bz2') ||
        lo.endsWith('.tbz2') ||
        lo.endsWith('.tbz')) {
      return ArchiveType.tarBz2;
    }
    if (lo.endsWith('.tar.xz') || lo.endsWith('.txz')) return ArchiveType.tarXz;
    final ext = p.extension(lo).replaceFirst('.', '');
    switch (ext) {
      case 'zip':
        return ArchiveType.zip;
      case 'jar':
      case 'war':
      case 'ear':
      case 'apk':
        return ArchiveType.jar;
      case 'tar':
        return ArchiveType.tar;
      case 'gz':
        return ArchiveType.gz;
      case 'bz2':
        return ArchiveType.bz2;
      case 'xz':
        return ArchiveType.xz;
      case '7z':
        return ArchiveType.sevenZip;
      case 'rar':
        return ArchiveType.rar;
      default:
        return ArchiveType.unknown;
    }
  }

  // ── Listing ───────────────────────────────────────────────────────────────

  static Future<List<ArchiveEntryInfo>> listEntries(
    String path, {
    String? password,
  }) async {
    final type = detectType(path);
    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
        return _listZip(path, password: password);
      case ArchiveType.tar:
        return _listTar(path);
      case ArchiveType.tarGz:
        return _listTarGz(path);
      case ArchiveType.tarBz2:
        return _listTarBz2(path);
      case ArchiveType.tarXz:
        return _listTarXz(path);
      case ArchiveType.gz:
        return _listSingle(path, (b) => const arc.GZipDecoder().decodeBytes(b));
      case ArchiveType.bz2:
        return _listSingle(path, (b) => arc.BZip2Decoder().decodeBytes(b));
      case ArchiveType.xz:
        return _listSingle(path, (b) => arc.XZDecoder().decodeBytes(b));
      case ArchiveType.sevenZip:
        return _list7z(path, password: password);
      case ArchiveType.rar:
        return _listRar(path, password: password);
      case ArchiveType.unknown:
        throw const ArchiveOpException('Format d\'archive non reconnu.');
    }
  }

  static Future<List<ArchiveEntryInfo>> _listZip(
    String path, {
    String? password,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = arc.ZipDecoder().decodeBytes(bytes, password: password);
      return archive.files.map(_zipFileToEntry).toList();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Bad state') ||
          msg.contains('password') ||
          msg.contains('AES') ||
          msg.contains('decrypt')) {
        throw const ArchiveOpException(
          'Mot de passe requis ou invalide.',
          isPasswordRequired: true,
        );
      }
      throw ArchiveOpException('Impossible de lire l\'archive : $msg');
    }
  }

  static ArchiveEntryInfo _zipFileToEntry(arc.ArchiveFile f) {
    final raw =
        f.name.endsWith('/') ? f.name.substring(0, f.name.length - 1) : f.name;
    return ArchiveEntryInfo(
      name: p.basename(raw),
      fullPath: raw,
      size: f.size,
      compressedSize: 0,
      modified: f.lastModTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000)
          : null,
      isDirectory: !f.isFile,
    );
  }

  static Future<List<ArchiveEntryInfo>> _listTar(String path) async {
    final bytes = await File(path).readAsBytes();
    return _archiveToEntries(arc.TarDecoder().decodeBytes(bytes));
  }

  static Future<List<ArchiveEntryInfo>> _listTarGz(String path) async {
    final bytes = await File(path).readAsBytes();
    return _archiveToEntries(arc.TarDecoder()
        .decodeBytes(const arc.GZipDecoder().decodeBytes(bytes)));
  }

  static Future<List<ArchiveEntryInfo>> _listTarBz2(String path) async {
    final bytes = await File(path).readAsBytes();
    return _archiveToEntries(
        arc.TarDecoder().decodeBytes(arc.BZip2Decoder().decodeBytes(bytes)));
  }

  static Future<List<ArchiveEntryInfo>> _listTarXz(String path) async {
    final bytes = await File(path).readAsBytes();
    return _archiveToEntries(
        arc.TarDecoder().decodeBytes(arc.XZDecoder().decodeBytes(bytes)));
  }

  static Future<List<ArchiveEntryInfo>> _listSingle(
    String path,
    _ByteDecoder decoder,
  ) async {
    final bytes = await File(path).readAsBytes();
    final decoded = decoder(bytes);
    final name = p.basenameWithoutExtension(path);
    return [
      ArchiveEntryInfo(
        name: name,
        fullPath: name,
        size: decoded.length,
        compressedSize: bytes.length,
        isDirectory: false,
      ),
    ];
  }

  static List<ArchiveEntryInfo> _archiveToEntries(arc.Archive archive) {
    return archive.files.map((f) {
      final raw = f.name.endsWith('/')
          ? f.name.substring(0, f.name.length - 1)
          : f.name;
      return ArchiveEntryInfo(
        name: p.basename(raw),
        fullPath: raw,
        size: f.size,
        compressedSize: 0,
        isDirectory: !f.isFile,
      );
    }).toList();
  }

  // ── Listing via CLI ───────────────────────────────────────────────────────

  /// 7z : en-tête lu par le lecteur intégré (rien n'est décompressé, sauf
  /// un en-tête compressé) ; l'outil `7z` en secours.
  static Future<List<ArchiveEntryInfo>> _list7z(
    String path, {
    String? password,
  }) async {
    final bytes = await File(path).readAsBytes();
    try {
      final archive =
          _sevenZipGuard(() => SevenZipArchive.open(bytes, password: password));
      return [
        for (final e in archive.entries)
          ArchiveEntryInfo(
            name: p.basename(e.name),
            fullPath: e.name,
            size: e.size,
            compressedSize: 0,
            modified: e.modified,
            isDirectory: e.isDirectory,
          ),
      ];
    } on SevenZipUnsupportedException catch (e) {
      if (await find7z() == null) throw _unsupported7z(e);
      return _list7zCli(path, password: password);
    }
  }

  static Future<List<ArchiveEntryInfo>> _list7zCli(
    String path, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) throw const ArchiveOpException('p7zip non installé.');
    final args = ['l', '-slt', if (password != null) '-p$password', '--', path];
    final r = await Process.run(cmd, args);
    if (r.exitCode == 2) {
      throw const ArchiveOpException(
        'Mot de passe requis ou invalide.',
        isPasswordRequired: true,
      );
    }
    if (r.exitCode != 0) {
      throw ArchiveOpException('Erreur 7z (${r.exitCode}) : ${r.stderr}');
    }
    return _parse7zList(r.stdout as String);
  }

  /// Exécute [body] (lecteur 7z) en traduisant ses erreurs pour
  /// l'utilisateur ; [SevenZipUnsupportedException] passe, pour le secours.
  static T _sevenZipGuard<T>(T Function() body) {
    try {
      return body();
    } on SevenZipPasswordException catch (e) {
      throw ArchiveOpException(e.toString(), isPasswordRequired: true);
    } on FormatException catch (e) {
      throw ArchiveOpException('Archive 7z illisible : ${e.message}');
    }
  }

  static ArchiveOpException _unsupported7z(SevenZipUnsupportedException e) =>
      ArchiveOpException('7z : la méthode « ${e.method} » n\'est pas prise '
          'en charge par l\'application'
          '${Platform.isAndroid ? '.' : ' (installez p7zip pour l\'extraire).'}');

  /// Au-delà de cette taille, compression et décompression 7z partent dans
  /// un isolat : l'interface reste fluide.
  static const int _isolateThreshold = 2 << 20;

  static Future<T> _heavy<T>(int size, T Function() work) =>
      size > _isolateThreshold ? Isolate.run(work) : Future.sync(work);

  static Future<List<ArchiveEntryInfo>> _listRar(
    String path, {
    String? password,
  }) async {
    final cmd = await findUnrar();
    if (cmd == null) {
      throw const ArchiveOpException(
        'unrar n\'est pas installé.\nInstallez-le avec : sudo apt install unrar',
      );
    }
    final args = ['v', if (password != null) '-p$password', path];
    final r = await Process.run(cmd, args);
    if (r.exitCode == 11) {
      throw const ArchiveOpException(
        'Mot de passe requis ou invalide.',
        isPasswordRequired: true,
      );
    }
    if (r.exitCode != 0) {
      throw ArchiveOpException('Erreur unrar (${r.exitCode}) : ${r.stderr}');
    }
    return _parseRarList(r.stdout as String);
  }

  // ── Extraction ────────────────────────────────────────────────────────────

  /// Extrait toute l'archive dans [destDir].
  ///
  /// Sécurité (« Zip Slip ») : tous les noms d'entrée sont validés AVANT la
  /// moindre écriture ; une seule entrée dangereuse (`..`, chemin absolu…)
  /// fait refuser toute l'archive. Les liens symboliques contenus dans
  /// l'archive ne sont jamais recréés (voir [ExtractResult.skippedLinks]).
  ///
  /// Un fichier déjà présent n'est jamais écrasé sans décision : [onConflict]
  /// choisit (sans résolveur, les deux sont gardés et le fichier extrait
  /// reçoit un nom libre). 7z/RAR : renommage automatique.
  static Future<ExtractResult> extractAll(
    String archivePath,
    String destDir, {
    String? password,
    void Function(double)? onProgress,
    ConflictResolver? onConflict,
  }) async {
    final type = detectType(archivePath);
    switch (type) {
      case ArchiveType.sevenZip:
        return _extract7z(archivePath, destDir,
            password: password, onProgress: onProgress, onConflict: onConflict);
      case ArchiveType.rar:
        return _extractRar(archivePath, destDir, password: password);
      case ArchiveType.unknown:
        throw const ArchiveOpException('Format d\'archive non reconnu.');
      default:
        break;
    }

    final bytes = await File(archivePath).readAsBytes();
    switch (type) {
      case ArchiveType.gz:
        return _writeSingle(
            path: archivePath,
            decoded: const arc.GZipDecoder().decodeBytes(bytes),
            destDir: destDir,
            onConflict: onConflict);
      case ArchiveType.bz2:
        return _writeSingle(
            path: archivePath,
            decoded: arc.BZip2Decoder().decodeBytes(bytes),
            destDir: destDir,
            onConflict: onConflict);
      case ArchiveType.xz:
        return _writeSingle(
            path: archivePath,
            decoded: arc.XZDecoder().decodeBytes(bytes),
            destDir: destDir,
            onConflict: onConflict);
      default:
        final archive = _decodeMulti(type, bytes, password: password);
        return _writeArchive(archive.files, destDir, onProgress,
            onConflict: onConflict);
    }
  }

  /// Décode une archive multi-fichiers (ZIP/JAR/TAR/TAR.*) déjà lue.
  static arc.Archive _decodeMulti(
    ArchiveType type,
    List<int> bytes, {
    String? password,
  }) {
    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
        return arc.ZipDecoder().decodeBytes(bytes, password: password);
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
        throw ArchiveOpException('Format non géré ici : $type');
    }
  }

  /// Valide tous les [names] (sans écrire) : lève [ArchiveOpException] au
  /// premier nom qui sortirait de [destDir].
  static void _validateNames(String destDir, Iterable<String> names) {
    for (final name in names) {
      _guard(() => SafePath.resolveWithin(destDir, name));
    }
  }

  /// Traduit un [UnsafePathException] en message d'archive pour l'utilisateur.
  static T _guard<T>(T Function() body) {
    try {
      return body();
    } on UnsafePathException catch (e) {
      throw ArchiveOpException(
          'Archive refusée : l\'entrée « ${e.entry} » est dangereuse '
          '(${e.reason}). Rien n\'a été extrait.');
    }
  }

  static Future<T> _guardAsync<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on UnsafePathException catch (e) {
      throw ArchiveOpException(
          'Extraction interrompue : l\'entrée « ${e.entry} » est dangereuse '
          '(${e.reason}).');
    }
  }

  static Future<ExtractResult> _writeArchive(
    List<arc.ArchiveFile> files,
    String dest,
    void Function(double)? onProgress, {
    ConflictResolver? onConflict,
  }) async {
    // 1. Validation lexicale de TOUTES les entrées avant d'écrire quoi que
    //    ce soit : une archive piégée est refusée en bloc.
    _validateNames(dest, files.map((f) => f.name));

    // 2. Écriture ; la racine vérifie en plus les liens symboliques déjà
    //    présents sur le disque.
    final root = await SafeExtractionRoot.open(dest);
    final total = files.length;
    var done = 0, skippedLinks = 0;
    var result = const ExtractResult();
    for (final file in files) {
      if (file.isSymbolicLink) {
        skippedLinks++;
      } else if (file.isFile) {
        result += await _writeEntry(
            root, file.name, file.content as List<int>, onConflict);
      } else {
        await _guardAsync(() => root.prepareDirectory(file.name));
      }
      done++;
      onProgress?.call(done / total);
    }
    return result + ExtractResult(skippedLinks: skippedLinks);
  }

  /// Écrit une entrée [name] : jamais d'écrasement sans décision, écriture
  /// atomique (pas de fichier tronqué si l'extraction est interrompue).
  static Future<ExtractResult> _writeEntry(
    SafeExtractionRoot root,
    String name,
    List<int> content,
    ConflictResolver? onConflict,
  ) async {
    var path = await _guardAsync(() => root.prepareFile(name));
    var keptBoth = 0;
    final existing = FileSystemEntity.typeSync(path, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      // Un dossier occupe la place : on ne le remplace jamais par un fichier.
      final action = existing == FileSystemEntityType.directory
          ? ConflictAction.keepBoth
          : await (onConflict?.call(name, path) ??
              Future.value(ConflictAction.keepBoth));
      switch (action) {
        case ConflictAction.skip:
          return const ExtractResult(skippedExisting: 1);
        case ConflictAction.keepBoth:
          path = FileOperationsService.uniqueDestination(
              p.dirname(path), p.basename(path));
          keptBoth = 1;
        case ConflictAction.replace:
          break; // écriture atomique par-dessus l'existant
      }
    }
    await AtomicWrite.bytes(path, content);
    return ExtractResult(filesWritten: 1, keptBoth: keptBoth);
  }

  static Future<ExtractResult> _writeSingle({
    required String path,
    required List<int> decoded,
    required String destDir,
    ConflictResolver? onConflict,
  }) async {
    // Nom dérivé du fichier local (pas de l'archive), vérifié quand même :
    // un lien symbolique existant à cet emplacement serait suivi.
    final root = await SafeExtractionRoot.open(destDir);
    return _writeEntry(
        root, p.basenameWithoutExtension(path), decoded, onConflict);
  }

  // Pour RAR (et 7z en secours), l'extraction est faite par l'outil externe :
  // on liste d'abord les entrées et on refuse l'archive si un nom est
  // dangereux. Limite : les liens symboliques contenus dans ces archives ne
  // sont pas détectés par la liste (on s'appuie sur les protections de
  // 7-Zip/unrar).

  /// 7z : décompression intégrée, puis écriture commune (noms validés,
  /// liens symboliques jamais recréés, conflits arbitrés). [where] limite
  /// l'extraction à certaines entrées. Méthode non gérée : outil `7z` (toute
  /// l'archive, renommage automatique des fichiers existants).
  static Future<ExtractResult> _extract7z(
    String path,
    String dest, {
    String? password,
    void Function(double)? onProgress,
    ConflictResolver? onConflict,
    bool Function(String name)? where,
  }) async {
    final bytes = await File(path).readAsBytes();
    final arc.Archive archive;
    try {
      archive = await _heavy(
          bytes.length,
          () => _sevenZipGuard(() =>
              SevenZipArchive.open(bytes, password: password).toArchive(
                  where: where == null ? null : (e) => where(e.name))));
    } on SevenZipUnsupportedException catch (e) {
      if (where != null || await find7z() == null) throw _unsupported7z(e);
      return _extract7zCli(path, dest, password: password);
    }
    return _writeArchive(archive.files, dest, onProgress,
        onConflict: onConflict);
  }

  static Future<ExtractResult> _extract7zCli(
    String path,
    String dest, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) throw const ArchiveOpException('p7zip non installé.');
    final entries = await _list7zCli(path, password: password);
    _validateNames(dest, entries.map((e) => e.fullPath));
    await Directory(dest).create(recursive: true);
    // -aou : renomme automatiquement les fichiers déjà présents (au lieu de
    // les écraser avec -y seul).
    final args = [
      'x',
      '-y',
      '-aou',
      '-o$dest',
      if (password != null) '-p$password',
      '--',
      path
    ];
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw ArchiveOpException('Erreur 7z : ${r.stderr}');
    return ExtractResult(
        filesWritten: entries.where((e) => !e.isDirectory).length);
  }

  static Future<ExtractResult> _extractRar(
    String path,
    String dest, {
    String? password,
  }) async {
    final cmd = await findUnrar();
    if (cmd == null) throw const ArchiveOpException('unrar non installé.');
    final entries = await _listRar(path, password: password);
    _validateNames(dest, entries.map((e) => e.fullPath));
    await Directory(dest).create(recursive: true);
    // -or : renomme automatiquement les fichiers déjà présents.
    final args = [
      'x',
      '-y',
      '-or',
      if (password != null) '-p$password',
      path,
      '$dest/'
    ];
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw ArchiveOpException('Erreur unrar : ${r.stderr}');
    return ExtractResult(
        filesWritten: entries.where((e) => !e.isDirectory).length);
  }

  // ── Extraction d'une entrée individuelle ──────────────────────────────────

  /// Extrait l'entrée [entryPath] (fichier, ou dossier avec son contenu).
  static Future<ExtractResult> extractEntry(
    String archivePath,
    String entryPath,
    String destDir, {
    String? password,
    ConflictResolver? onConflict,
  }) async {
    final type = detectType(archivePath);
    final wanted = ArchiveTree.normalize(entryPath);
    bool selected(String name) {
      final norm = ArchiveTree.normalize(name);
      return norm == wanted || norm.startsWith('$wanted/');
    }

    switch (type) {
      case ArchiveType.sevenZip:
        return _extract7z(archivePath, destDir,
            password: password, onConflict: onConflict, where: selected);
      case ArchiveType.zip:
      case ArchiveType.jar:
      case ArchiveType.tar:
      case ArchiveType.tarGz:
      case ArchiveType.tarBz2:
      case ArchiveType.tarXz:
        break;
      default:
        // Formats mono-fichier et 7z/RAR : extraction complète.
        return extractAll(archivePath, destDir,
            password: password, onConflict: onConflict);
    }

    final bytes = await File(archivePath).readAsBytes();
    final archive = _decodeMulti(type, bytes, password: password);
    // L'entrée elle-même ou ses descendants — et non tout nom qui commence
    // par les mêmes caractères (« doc » ne doit pas inclure « docs/… »).
    // Comparaison sur les chemins normalisés (« ./src/a.txt » = « src/a.txt »),
    // comme dans l'arborescence affichée ; l'entrée elle-même ou ses
    // descendants, pas un simple préfixe de caractères (« doc » ≠ « docs/… »).
    final files = archive.files.where((f) => selected(f.name)).toList();
    return _writeArchive(files, destDir, null, onConflict: onConflict);
  }

  // ── Création d'archive ────────────────────────────────────────────────────

  /// Formats de création proposés. GZ et BZ2 ne compressent qu'un fichier
  /// unique.
  static Future<List<ArchiveType>> creatableTypes() async => [
        ArchiveType.zip,
        ArchiveType.sevenZip,
        ArchiveType.tar,
        ArchiveType.tarGz,
        ArchiveType.tarBz2,
        ArchiveType.gz,
        ArchiveType.bz2,
      ];

  /// Extension de fichier conventionnelle de [type].
  static String extensionOf(ArchiveType type) => switch (type) {
        ArchiveType.zip || ArchiveType.jar => 'zip',
        ArchiveType.tar => 'tar',
        ArchiveType.tarGz => 'tar.gz',
        ArchiveType.tarBz2 => 'tar.bz2',
        ArchiveType.tarXz => 'tar.xz',
        ArchiveType.gz => 'gz',
        ArchiveType.bz2 => 'bz2',
        ArchiveType.xz => 'xz',
        ArchiveType.sevenZip => '7z',
        ArchiveType.rar => 'rar',
        ArchiveType.unknown => '',
      };

  /// Crée l'archive [destPath] au format [type] à partir de [sourcePaths]
  /// (fichiers et dossiers, récursivement ; les liens symboliques ne sont
  /// pas suivis). Refuse d'écraser une archive existante. [password] :
  /// ZIP ou 7z chiffré en AES (natif, toutes plateformes) ; avec
  /// [encryptNames], un 7z chiffre aussi la liste des fichiers.
  static Future<void> createArchive(
    String destPath,
    List<String> sourcePaths,
    ArchiveType type, {
    String? password,
    bool encryptNames = false,
    void Function(double)? onProgress,
  }) async {
    _ensureNewArchive(destPath);
    if (type == ArchiveType.sevenZip) {
      final archive = arc.Archive();
      for (var i = 0; i < sourcePaths.length; i++) {
        await _addToArchive(
            archive, sourcePaths[i], p.basename(sourcePaths[i]));
        onProgress?.call((i + 1) / sourcePaths.length * 0.5);
      }
      final total = archive.files.fold<int>(0, (n, f) => n + f.size);
      final bytes = await _heavy(
          total,
          () => SevenZipWriter.encode(archive,
              password: password, encryptHeader: encryptNames));
      await AtomicWrite.bytes(destPath, bytes);
      onProgress?.call(1);
      return;
    }
    if (password != null &&
        !(type == ArchiveType.zip || type == ArchiveType.jar)) {
      throw ArchiveOpException('${type.label} : pas de mot de passe possible.');
    }
    if (type.isSingleFile) {
      if (sourcePaths.length != 1 ||
          FileSystemEntity.typeSync(sourcePaths.single, followLinks: false) !=
              FileSystemEntityType.file) {
        throw ArchiveOpException('${type.label} compresse un seul fichier : '
            'choisissez TAR.GZ ou ZIP pour plusieurs éléments.');
      }
      final data = await File(sourcePaths.single).readAsBytes();
      final out = switch (type) {
        ArchiveType.gz => const arc.GZipEncoder().encodeBytes(data),
        ArchiveType.bz2 => arc.BZip2Encoder().encodeBytes(data),
        _ => throw ArchiveOpException('${type.label} : création impossible.'),
      };
      onProgress?.call(1);
      return AtomicWrite.bytes(destPath, out);
    }

    final archive = arc.Archive();
    for (var i = 0; i < sourcePaths.length; i++) {
      await _addToArchive(archive, sourcePaths[i], p.basename(sourcePaths[i]));
      onProgress?.call((i + 1) / sourcePaths.length);
    }
    final Uint8List bytes = switch (type) {
      ArchiveType.zip ||
      ArchiveType.jar =>
        arc.ZipEncoder(password: password).encodeBytes(archive),
      ArchiveType.tar => arc.TarEncoder().encodeBytes(archive),
      ArchiveType.tarGz => const arc.GZipEncoder()
          .encodeBytes(arc.TarEncoder().encodeBytes(archive)),
      ArchiveType.tarBz2 =>
        arc.BZip2Encoder().encodeBytes(arc.TarEncoder().encodeBytes(archive)),
      _ => throw ArchiveOpException(
          '${type.label} : création non disponible (${type.readOnlyReason})'),
    };
    await AtomicWrite.bytes(destPath, bytes);
  }

  /// ZIP (chiffré en AES si [password]).
  static Future<void> createZip(
    String destPath,
    List<String> sourcePaths, {
    String? password,
    void Function(double)? onProgress,
  }) =>
      createArchive(destPath, sourcePaths, ArchiveType.zip,
          password: password, onProgress: onProgress);

  static Future<void> createTarGz(
    String destPath,
    List<String> sourcePaths, {
    void Function(double)? onProgress,
  }) =>
      createArchive(destPath, sourcePaths, ArchiveType.tarGz,
          onProgress: onProgress);

  /// 7z (chiffré en AES si [password]).
  static Future<void> create7z(
    String destPath,
    List<String> sourcePaths, {
    String? password,
    bool encryptNames = false,
    void Function(double)? onProgress,
  }) =>
      createArchive(destPath, sourcePaths, ArchiveType.sevenZip,
          password: password,
          encryptNames: encryptNames,
          onProgress: onProgress);

  /// Refuse d'écraser (ou de compléter) une archive existante.
  static void _ensureNewArchive(String destPath) {
    if (FileSystemEntity.typeSync(destPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ArchiveOpException(
          '« ${p.basename(destPath)} » existe déjà : choisissez un autre nom.');
    }
  }

  // Modification d'archive : voir ArchiveDocument (ajout, renommage,
  // déplacement, suppression, mot de passe…).

  // ── CLI helpers ───────────────────────────────────────────────────────────

  static Future<String?> find7z() async {
    for (final cmd in ['7z', '7za', '7zz']) {
      try {
        final r = await Process.run('which', [cmd]);
        if (r.exitCode == 0) return cmd;
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> findUnrar() async {
    for (final cmd in ['unrar', 'rar']) {
      try {
        final r = await Process.run('which', [cmd]);
        if (r.exitCode == 0) return cmd;
      } catch (_) {}
    }
    return null;
  }

  // ── Helpers internes ──────────────────────────────────────────────────────

  /// Ajoute [path] (fichier ou dossier, récursivement) sous [archivePath].
  /// Les liens symboliques ne sont pas suivis (un lien vers un dossier
  /// parent bouclerait) : ils sont ignorés.
  static Future<void> _addToArchive(
    arc.Archive archive,
    String path,
    String archivePath,
  ) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      final bytes = await File(path).readAsBytes();
      final file = arc.ArchiveFile.bytes(archivePath, bytes);
      final stat = FileStat.statSync(path);
      file.lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000;
      file.mode = stat.mode & 0x1FF;
      archive.addFile(file);
    } else if (type == FileSystemEntityType.directory) {
      archive.addFile(arc.ArchiveFile.directory('$archivePath/'));
      final children = await Directory(path).list(followLinks: false).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entity in children) {
        await _addToArchive(
          archive,
          entity.path,
          '$archivePath/${p.basename(entity.path)}',
        );
      }
    }
  }

  static List<ArchiveEntryInfo> _parse7zList(String output) {
    final entries = <ArchiveEntryInfo>[];
    for (final block in output.split('\n----------\n')) {
      String? name;
      int size = 0;
      int packed = 0;
      bool isDir = false;
      DateTime? modified;
      for (final line in block.split('\n')) {
        final t = line.trim();
        if (t.startsWith('Path = ')) name = t.substring(7);
        if (t.startsWith('Size = ')) size = int.tryParse(t.substring(7)) ?? 0;
        if (t.startsWith('Packed Size = ')) {
          packed = int.tryParse(t.substring(14)) ?? 0;
        }
        if (t.startsWith('Attributes = ')) isDir = t.contains('D');
        if (t.startsWith('Modified = ')) {
          modified = DateTime.tryParse(t.substring(11).trim());
        }
      }
      if (name != null && name.isNotEmpty) {
        entries.add(ArchiveEntryInfo(
          name: p.basename(name),
          fullPath: name,
          size: size,
          compressedSize: packed,
          modified: modified,
          isDirectory: isDir,
        ));
      }
    }
    return entries;
  }

  static List<ArchiveEntryInfo> _parseRarList(String output) {
    final entries = <ArchiveEntryInfo>[];
    final lines = output.split('\n');
    bool inBlock = false;
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.startsWith('-------')) {
        inBlock = !inBlock;
        continue;
      }
      if (!inBlock || l.isEmpty) continue;
      final name = l;
      if (i + 1 < lines.length) {
        final meta = lines[i + 1].trim().split(RegExp(r'\s+'));
        final size = meta.isNotEmpty ? int.tryParse(meta[0]) ?? 0 : 0;
        final packed = meta.length > 1 ? int.tryParse(meta[1]) ?? 0 : 0;
        final isDir = meta.length > 4 ? meta[4].contains('D') : false;
        entries.add(ArchiveEntryInfo(
          name: p.basename(name),
          fullPath: name,
          size: size,
          compressedSize: packed,
          isDirectory: isDir,
        ));
        i++;
      }
    }
    return entries;
  }
}
