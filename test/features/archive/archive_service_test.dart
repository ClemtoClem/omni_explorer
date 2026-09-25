import 'dart:io';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/models/archive_entry.dart';
import 'package:omni_explorer/features/archive/services/archive_service.dart';

/// Fichier d'archive dont le contenu est [text].
arc.ArchiveFile _file(String name, String text) =>
    arc.ArchiveFile(name, text.length, text.codeUnits);

void main() {
  late Directory sandbox;
  late String dest;
  late String outside;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('archive_service_test_');
    dest = p.join(sandbox.path, 'dest');
    outside = p.join(sandbox.path, 'outside');
    await Directory(outside).create();
  });

  tearDown(() => sandbox.delete(recursive: true));

  Future<String> writeZip(List<arc.ArchiveFile> files) async {
    final archive = arc.Archive();
    files.forEach(archive.addFile);
    final path = p.join(sandbox.path, 'test.zip');
    await File(path).writeAsBytes(arc.ZipEncoder().encode(archive)!);
    return path;
  }

  Future<String> writeTarGz(List<arc.ArchiveFile> files) async {
    final archive = arc.Archive();
    files.forEach(archive.addFile);
    final tar = arc.TarEncoder().encode(archive);
    final path = p.join(sandbox.path, 'test.tar.gz');
    await File(path).writeAsBytes(arc.GZipEncoder().encode(tar)!);
    return path;
  }

  /// Tous les fichiers présents sous [dir] (chemins relatifs).
  List<String> filesUnder(String dir) => Directory(dir).existsSync()
      ? Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: dir))
          .toList()
      : <String>[];

  group('extractAll', () {
    test('extrait une archive saine', () async {
      final zip = await writeZip([
        _file('a.txt', 'A'),
        _file('dir/b.txt', 'B'),
      ]);
      final result = await ArchiveService.extractAll(zip, dest);

      expect(result.filesWritten, 2);
      expect(File(p.join(dest, 'a.txt')).readAsStringSync(), 'A');
      expect(File(p.join(dest, 'dir', 'b.txt')).readAsStringSync(), 'B');
    });

    for (final evil in [
      '../outside/evil.txt',
      'dir/../../outside/evil.txt',
      r'..\outside\evil.txt',
    ]) {
      test('refuse en bloc une entrée « $evil » (ZIP)', () async {
        final zip = await writeZip([_file('ok.txt', 'ok'), _file(evil, 'x')]);

        await expectLater(ArchiveService.extractAll(zip, dest),
            throwsA(isA<ArchiveOpException>()));
        expect(filesUnder(outside), isEmpty);
        // Tout ou rien : l'entrée saine n'a pas été écrite non plus.
        expect(filesUnder(dest), isEmpty);
      });
    }

    test('refuse un chemin absolu (ZIP)', () async {
      final target = p.join(outside, 'abs.txt');
      final zip = await writeZip([_file(target, 'x')]);

      await expectLater(ArchiveService.extractAll(zip, dest),
          throwsA(isA<ArchiveOpException>()));
      expect(File(target).existsSync(), isFalse);
    });

    test('refuse une entrée dangereuse (TAR.GZ)', () async {
      final tgz = await writeTarGz([_file('../outside/evil.txt', 'x')]);

      await expectLater(ArchiveService.extractAll(tgz, dest),
          throwsA(isA<ArchiveOpException>()));
      expect(filesUnder(outside), isEmpty);
    });

    test('ne recrée jamais les liens symboliques de l\'archive', () async {
      final link = arc.ArchiveFile('link', 0, <int>[])
        ..isSymbolicLink = true
        ..nameOfLinkedFile = outside;
      final tgz = await writeTarGz([link, _file('link/evil.txt', 'x')]);

      final result = await ArchiveService.extractAll(tgz, dest);

      expect(result.skippedLinks, 1);
      expect(FileSystemEntity.isLinkSync(p.join(dest, 'link')), isFalse);
      // « link/evil.txt » atterrit dans un vrai dossier de la destination.
      expect(File(p.join(dest, 'link', 'evil.txt')).existsSync(), isTrue);
      expect(filesUnder(outside), isEmpty);
    });

    test('refuse d\'écrire à travers un lien existant dans la destination',
        () async {
      await Directory(dest).create();
      await Link(p.join(dest, 'escape')).create(outside);
      final zip = await writeZip([_file('escape/evil.txt', 'x')]);

      await expectLater(ArchiveService.extractAll(zip, dest),
          throwsA(isA<ArchiveOpException>()));
      expect(filesUnder(outside), isEmpty);
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);

    test('.gz : refuse d\'écraser la cible d\'un lien existant', () async {
      final gz = p.join(sandbox.path, 'note.txt.gz');
      await File(gz).writeAsBytes(arc.GZipEncoder().encode('new'.codeUnits)!);
      final victim = File(p.join(outside, 'victim.txt'))
        ..writeAsStringSync('original');
      await Directory(dest).create();
      await Link(p.join(dest, 'note.txt')).create(victim.path);

      await expectLater(ArchiveService.extractAll(gz, dest),
          throwsA(isA<ArchiveOpException>()));
      expect(victim.readAsStringSync(), 'original');
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);

    test('.gz : extrait le fichier décompressé', () async {
      final gz = p.join(sandbox.path, 'note.txt.gz');
      await File(gz).writeAsBytes(arc.GZipEncoder().encode('hello'.codeUnits)!);

      final result = await ArchiveService.extractAll(gz, dest);

      expect(result.filesWritten, 1);
      expect(File(p.join(dest, 'note.txt')).readAsStringSync(), 'hello');
    });
  });

  group('extractEntry', () {
    test('n\'extrait que l\'entrée demandée et ses descendants', () async {
      final zip = await writeZip([
        _file('doc/a.txt', 'A'),
        _file('docs/b.txt', 'B'), // même préfixe de caractères
        _file('other.txt', 'C'),
      ]);

      await ArchiveService.extractEntry(zip, 'doc', dest);

      expect(filesUnder(dest), [p.join('doc', 'a.txt')]);
    });

    test('refuse une entrée sélectionnée dangereuse', () async {
      final zip = await writeZip([_file('../outside/evil.txt', 'x')]);

      await expectLater(
          ArchiveService.extractEntry(zip, '../outside/evil.txt', dest),
          throwsA(isA<ArchiveOpException>()));
      expect(filesUnder(outside), isEmpty);
    });
  });
}
