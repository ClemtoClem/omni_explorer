import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart' as arc;
import 'package:path/path.dart' as p;
import '../../../core/utils/safe_path.dart';
import '../models/archive_entry.dart';

typedef _ByteDecoder = List<int> Function(List<int>);

/// Service statique pour lire, extraire et créer des archives.
///
/// - ZIP / JAR / WAR / APK    → package Dart `archive`
/// - TAR / TAR.GZ / BZ2 / XZ  → package Dart `archive`
/// - 7Z                        → CLI `7z` / `7za`
/// - RAR                       → CLI `unrar` / `rar`
class ArchiveService {
  ArchiveService._();

  // ── Détection du format ───────────────────────────────────────────────────

  static ArchiveType detectType(String path) {
    final lo = path.toLowerCase();
    if (lo.endsWith('.tar.gz')  || lo.endsWith('.tgz'))  return ArchiveType.tarGz;
    if (lo.endsWith('.tar.bz2') || lo.endsWith('.tbz2')) return ArchiveType.tarBz2;
    if (lo.endsWith('.tar.xz')  || lo.endsWith('.txz'))  return ArchiveType.tarXz;
    final ext = p.extension(lo).replaceFirst('.', '');
    switch (ext) {
      case 'zip':                       return ArchiveType.zip;
      case 'jar': case 'war':
      case 'ear': case 'apk':          return ArchiveType.jar;
      case 'tar':                       return ArchiveType.tar;
      case 'gz':                        return ArchiveType.gz;
      case 'bz2':                       return ArchiveType.bz2;
      case 'xz':                        return ArchiveType.xz;
      case '7z':                        return ArchiveType.sevenZip;
      case 'rar':                       return ArchiveType.rar;
      default:                          return ArchiveType.unknown;
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
        return _listSingle(path, (b) => arc.GZipDecoder().decodeBytes(b));
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
    final raw = f.name.endsWith('/') ? f.name.substring(0, f.name.length - 1) : f.name;
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
    return _archiveToEntries(
        arc.TarDecoder().decodeBytes(arc.GZipDecoder().decodeBytes(bytes)));
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

  static Future<List<ArchiveEntryInfo>> _list7z(
    String path, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) {
      throw const ArchiveOpException(
        'p7zip n\'est pas installé.\nInstallez-le avec : sudo apt install p7zip-full',
      );
    }
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
  static Future<ExtractResult> extractAll(
    String archivePath,
    String destDir, {
    String? password,
    void Function(double)? onProgress,
  }) async {
    final type = detectType(archivePath);
    switch (type) {
      case ArchiveType.sevenZip:
        return _extract7z(archivePath, destDir, password: password);
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
        return _writeSingle(path: archivePath,
            decoded: arc.GZipDecoder().decodeBytes(bytes), destDir: destDir);
      case ArchiveType.bz2:
        return _writeSingle(path: archivePath,
            decoded: arc.BZip2Decoder().decodeBytes(bytes), destDir: destDir);
      case ArchiveType.xz:
        return _writeSingle(path: archivePath,
            decoded: arc.XZDecoder().decodeBytes(bytes), destDir: destDir);
      default:
        final archive = _decodeMulti(type, bytes, password: password);
        return _writeArchive(archive.files, destDir, onProgress);
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
        return arc.TarDecoder().decodeBytes(arc.GZipDecoder().decodeBytes(bytes));
      case ArchiveType.tarBz2:
        return arc.TarDecoder().decodeBytes(arc.BZip2Decoder().decodeBytes(bytes));
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
    void Function(double)? onProgress,
  ) async {
    // 1. Validation lexicale de TOUTES les entrées avant d'écrire quoi que
    //    ce soit : une archive piégée est refusée en bloc.
    _validateNames(dest, files.map((f) => f.name));

    // 2. Écriture ; la racine vérifie en plus les liens symboliques déjà
    //    présents sur le disque.
    final root = await SafeExtractionRoot.open(dest);
    final total = files.length;
    var done = 0, written = 0, skippedLinks = 0;
    for (final file in files) {
      if (file.isSymbolicLink) {
        skippedLinks++;
      } else if (file.isFile) {
        final path = await _guardAsync(() => root.prepareFile(file.name));
        await File(path).writeAsBytes(file.content as List<int>);
        written++;
      } else {
        await _guardAsync(() => root.prepareDirectory(file.name));
      }
      done++;
      onProgress?.call(done / total);
    }
    return ExtractResult(filesWritten: written, skippedLinks: skippedLinks);
  }

  static Future<ExtractResult> _writeSingle({
    required String path,
    required List<int> decoded,
    required String destDir,
  }) async {
    // Nom dérivé du fichier local (pas de l'archive), vérifié quand même :
    // un lien symbolique existant à cet emplacement serait suivi.
    final root = await SafeExtractionRoot.open(destDir);
    final out = await _guardAsync(
        () => root.prepareFile(p.basenameWithoutExtension(path)));
    await File(out).writeAsBytes(decoded);
    return const ExtractResult(filesWritten: 1);
  }

  // Pour 7z/RAR, l'extraction est faite par l'outil externe : on liste
  // d'abord les entrées et on refuse l'archive si un nom est dangereux.
  // Limite : les liens symboliques contenus dans ces archives ne sont pas
  // détectés par la liste (on s'appuie sur les protections de 7-Zip/unrar).

  static Future<ExtractResult> _extract7z(
    String path,
    String dest, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) throw const ArchiveOpException('p7zip non installé.');
    final entries = await _list7z(path, password: password);
    _validateNames(dest, entries.map((e) => e.fullPath));
    await Directory(dest).create(recursive: true);
    final args = ['x', '-y', '-o$dest', if (password != null) '-p$password', '--', path];
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
    final args = ['x', '-y', if (password != null) '-p$password', path, '$dest/'];
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
  }) async {
    final type = detectType(archivePath);
    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
      case ArchiveType.tar:
      case ArchiveType.tarGz:
      case ArchiveType.tarBz2:
      case ArchiveType.tarXz:
        break;
      default:
        // Formats mono-fichier et 7z/RAR : extraction complète.
        return extractAll(archivePath, destDir, password: password);
    }

    final bytes = await File(archivePath).readAsBytes();
    final archive = _decodeMulti(type, bytes, password: password);
    // L'entrée elle-même ou ses descendants — et non tout nom qui commence
    // par les mêmes caractères (« doc » ne doit pas inclure « docs/… »).
    final selected = archive.files.where((f) {
      final norm = f.name.endsWith('/')
          ? f.name.substring(0, f.name.length - 1)
          : f.name;
      return norm == entryPath || norm.startsWith('$entryPath/');
    }).toList();
    return _writeArchive(selected, destDir, null);
  }

  // ── Création d'archive ────────────────────────────────────────────────────

  static Future<void> createZip(
    String destPath,
    List<String> sourcePaths, {
    String? password,
    void Function(double)? onProgress,
  }) async {
    if (password != null) {
      final cmd = await find7z();
      if (cmd == null) {
        throw const ArchiveOpException(
          'p7zip requis pour chiffrer les archives ZIP.',
        );
      }
      final args = ['a', '-tzip', '-p$password', '-mem=AES256', destPath, ...sourcePaths];
      final r = await Process.run(cmd, args);
      if (r.exitCode != 0) throw ArchiveOpException('Erreur 7z : ${r.stderr}');
      return;
    }
    final archive = arc.Archive();
    final total = sourcePaths.length;
    var done = 0;
    for (final src in sourcePaths) {
      await _addToArchive(archive, src, p.basename(src));
      done++;
      onProgress?.call(done / total);
    }
    final encoded = arc.ZipEncoder().encode(archive);
    if (encoded != null) await File(destPath).writeAsBytes(encoded);
  }

  static Future<void> createTarGz(
    String destPath,
    List<String> sourcePaths, {
    void Function(double)? onProgress,
  }) async {
    final archive = arc.Archive();
    final total = sourcePaths.length;
    var done = 0;
    for (final src in sourcePaths) {
      await _addToArchive(archive, src, p.basename(src));
      done++;
      onProgress?.call(done / total);
    }
    final tarBytes = arc.TarEncoder().encode(archive);
    final gzBytes = arc.GZipEncoder().encode(Uint8List.fromList(tarBytes));
    await File(destPath).writeAsBytes(gzBytes!);
  }

  static Future<void> create7z(
    String destPath,
    List<String> sourcePaths, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) throw const ArchiveOpException('p7zip non installé.');
    final args = [
      'a',
      if (password != null) '-p$password',
      destPath,
      ...sourcePaths,
    ];
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw ArchiveOpException('Erreur 7z : ${r.stderr}');
  }

  // ── Modification ZIP ──────────────────────────────────────────────────────

  static Future<void> addFilesToZip(
    String archivePath,
    List<String> filePaths,
  ) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = arc.ZipDecoder().decodeBytes(bytes);
    for (final path in filePaths) {
      await _addToArchive(archive, path, p.basename(path));
    }
    final encoded = arc.ZipEncoder().encode(archive);
    if (encoded != null) await File(archivePath).writeAsBytes(encoded);
  }

  static Future<void> removeFromZip(
    String archivePath,
    List<String> entryPaths,
  ) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = arc.ZipDecoder().decodeBytes(bytes);
    final newArchive = arc.Archive();
    for (final file in archive.files) {
      final norm = file.name.endsWith('/')
          ? file.name.substring(0, file.name.length - 1)
          : file.name;
      if (!entryPaths.contains(norm)) {
        newArchive.addFile(file);
      }
    }
    final encoded = arc.ZipEncoder().encode(newArchive);
    if (encoded != null) await File(archivePath).writeAsBytes(encoded);
  }

  // ── Gestion du mot de passe (ZIP seulement) ───────────────────────────────

  static Future<void> setPassword(
    String archivePath,
    String newPassword,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('omni_arch_');
    try {
      await extractAll(archivePath, tempDir.path);
      final sources = await tempDir.list().map((e) => e.path).toList();
      final tmpOut = '$archivePath.tmp';
      await createZip(tmpOut, sources, password: newPassword);
      await File(archivePath).delete();
      await File(tmpOut).rename(archivePath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  static Future<void> removePassword(
    String archivePath,
    String currentPassword,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('omni_arch_');
    try {
      await extractAll(archivePath, tempDir.path, password: currentPassword);
      final sources = await tempDir.list().map((e) => e.path).toList();
      final tmpOut = '$archivePath.tmp';
      await createZip(tmpOut, sources);
      await File(archivePath).delete();
      await File(tmpOut).rename(archivePath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

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

  static Future<void> _addToArchive(
    arc.Archive archive,
    String path,
    String archivePath,
  ) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      final bytes = await File(path).readAsBytes();
      archive.addFile(arc.ArchiveFile(archivePath, bytes.length, bytes));
    } else if (type == FileSystemEntityType.directory) {
      archive.addFile(arc.ArchiveFile('$archivePath/', 0, <int>[]));
      await for (final entity in Directory(path).list()) {
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
        if (t.startsWith('Path = '))         name    = t.substring(7);
        if (t.startsWith('Size = '))         size    = int.tryParse(t.substring(7)) ?? 0;
        if (t.startsWith('Packed Size = '))  packed  = int.tryParse(t.substring(14)) ?? 0;
        if (t.startsWith('Attributes = '))   isDir   = t.contains('D');
        if (t.startsWith('Modified = '))     modified = DateTime.tryParse(t.substring(11).trim());
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
        final size   = meta.isNotEmpty ? int.tryParse(meta[0]) ?? 0 : 0;
        final packed = meta.length > 1  ? int.tryParse(meta[1]) ?? 0 : 0;
        final isDir  = meta.length > 4  ? meta[4].contains('D') : false;
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
