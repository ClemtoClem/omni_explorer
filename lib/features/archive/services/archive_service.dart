import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart' as arc;
import 'package:path/path.dart' as p;
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

  static Future<void> extractAll(
    String archivePath,
    String destDir, {
    String? password,
    void Function(double)? onProgress,
  }) async {
    await Directory(destDir).create(recursive: true);
    final type = detectType(archivePath);
    final bytes = await File(archivePath).readAsBytes();

    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
        final archive = arc.ZipDecoder().decodeBytes(bytes, password: password);
        await _writeArchive(archive, destDir, onProgress);
        break;
      case ArchiveType.tar:
        await _writeArchive(arc.TarDecoder().decodeBytes(bytes), destDir, onProgress);
        break;
      case ArchiveType.tarGz:
        await _writeArchive(
            arc.TarDecoder().decodeBytes(arc.GZipDecoder().decodeBytes(bytes)),
            destDir, onProgress);
        break;
      case ArchiveType.tarBz2:
        await _writeArchive(
            arc.TarDecoder().decodeBytes(arc.BZip2Decoder().decodeBytes(bytes)),
            destDir, onProgress);
        break;
      case ArchiveType.tarXz:
        await _writeArchive(
            arc.TarDecoder().decodeBytes(arc.XZDecoder().decodeBytes(bytes)),
            destDir, onProgress);
        break;
      case ArchiveType.gz:
        await _writeSingle(path: archivePath,
            decoded: arc.GZipDecoder().decodeBytes(bytes), destDir: destDir);
        break;
      case ArchiveType.bz2:
        await _writeSingle(path: archivePath,
            decoded: arc.BZip2Decoder().decodeBytes(bytes), destDir: destDir);
        break;
      case ArchiveType.xz:
        await _writeSingle(path: archivePath,
            decoded: arc.XZDecoder().decodeBytes(bytes), destDir: destDir);
        break;
      case ArchiveType.sevenZip:
        await _extract7z(archivePath, destDir, password: password);
        break;
      case ArchiveType.rar:
        await _extractRar(archivePath, destDir, password: password);
        break;
      case ArchiveType.unknown:
        throw const ArchiveOpException('Format d\'archive non reconnu.');
    }
  }

  static Future<void> _writeArchive(
    arc.Archive archive,
    String dest,
    void Function(double)? onProgress,
  ) async {
    final total = archive.files.length;
    var done = 0;
    for (final file in archive.files) {
      final filePath = p.join(dest, file.name);
      if (file.isFile) {
        final f = File(filePath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
      done++;
      onProgress?.call(done / total);
    }
  }

  static Future<void> _writeSingle({
    required String path,
    required List<int> decoded,
    required String destDir,
  }) async {
    final name = p.basenameWithoutExtension(path);
    await File(p.join(destDir, name)).writeAsBytes(decoded);
  }

  static Future<void> _extract7z(
    String path,
    String dest, {
    String? password,
  }) async {
    final cmd = await find7z();
    if (cmd == null) throw const ArchiveOpException('p7zip non installé.');
    final args = ['x', '-y', '-o$dest', if (password != null) '-p$password', '--', path];
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw ArchiveOpException('Erreur 7z : ${r.stderr}');
  }

  static Future<void> _extractRar(
    String path,
    String dest, {
    String? password,
  }) async {
    final cmd = await findUnrar();
    if (cmd == null) throw const ArchiveOpException('unrar non installé.');
    final args = ['x', '-y', if (password != null) '-p$password', path, '$dest/'];
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw ArchiveOpException('Erreur unrar : ${r.stderr}');
  }

  // ── Extraction d'une entrée individuelle ──────────────────────────────────

  static Future<void> extractEntry(
    String archivePath,
    String entryPath,
    String destDir, {
    String? password,
  }) async {
    final type = detectType(archivePath);
    final bytes = await File(archivePath).readAsBytes();
    arc.Archive archive;

    switch (type) {
      case ArchiveType.zip:
      case ArchiveType.jar:
        archive = arc.ZipDecoder().decodeBytes(bytes, password: password);
        break;
      case ArchiveType.tar:
        archive = arc.TarDecoder().decodeBytes(bytes);
        break;
      case ArchiveType.tarGz:
        archive = arc.TarDecoder().decodeBytes(arc.GZipDecoder().decodeBytes(bytes));
        break;
      case ArchiveType.tarBz2:
        archive = arc.TarDecoder().decodeBytes(arc.BZip2Decoder().decodeBytes(bytes));
        break;
      case ArchiveType.tarXz:
        archive = arc.TarDecoder().decodeBytes(arc.XZDecoder().decodeBytes(bytes));
        break;
      default:
        // Pour 7z/RAR, extraire tout dans un sous-dossier
        await extractAll(archivePath, destDir, password: password);
        return;
    }

    for (final file in archive.files) {
      final norm = file.name.endsWith('/')
          ? file.name.substring(0, file.name.length - 1)
          : file.name;
      if (!norm.startsWith(entryPath)) continue;
      final filePath = p.join(destDir, file.name);
      if (file.isFile) {
        final f = File(filePath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
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
