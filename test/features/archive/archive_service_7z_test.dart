/// 7z dans le service d'archives : création depuis le disque, liste,
/// extraction (complète ou partielle) avec les protections communes, et
/// secours par l'outil `7z` pour une méthode non gérée.

import 'dart:io';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/models/archive_entry.dart';
import 'package:omni_explorer/features/archive/services/archive_service.dart';
import 'package:omni_explorer/features/archive/services/seven_zip/seven_zip_writer.dart';

void main() {
  late Directory sandbox;
  setUp(() async =>
      sandbox = await Directory.systemTemp.createTemp('archive_7z_test_'));
  tearDown(() => sandbox.delete(recursive: true));

  String path(String rel) => p.join(sandbox.path, rel);

  /// Arborescence source : projet/{lisez-moi.txt, src/app.dart, vide/}.
  String makeSource() {
    File(path('projet/lisez-moi.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('Bonjour');
    File(path('projet/src/app.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n' * 100);
    Directory(path('projet/vide')).createSync();
    return path('projet');
  }

  test('le 7z fait partie des formats de création', () async {
    expect(
        await ArchiveService.creatableTypes(), contains(ArchiveType.sevenZip));
    expect(ArchiveType.sevenZip.canEdit, isTrue);
    expect(ArchiveType.sevenZip.isDartNative, isTrue);
  });

  test('créer, lister, extraire', () async {
    final out = path('projet.7z');
    await ArchiveService.createArchive(
        out, [makeSource()], ArchiveType.sevenZip);
    expect(ArchiveService.detectType(out), ArchiveType.sevenZip);

    final entries = await ArchiveService.listEntries(out);
    expect(entries.map((e) => e.fullPath).toSet(), {
      'projet',
      'projet/lisez-moi.txt',
      'projet/src',
      'projet/src/app.dart',
      'projet/vide',
    });

    final dest = path('x');
    final r = await ArchiveService.extractAll(out, dest);
    expect(r.filesWritten, 2);
    expect(File(p.join(dest, 'projet', 'lisez-moi.txt')).readAsStringSync(),
        'Bonjour');
    expect(Directory(p.join(dest, 'projet', 'vide')).existsSync(), isTrue);

    // Seconde extraction : rien n'est écrasé, les deux sont gardés.
    final again = await ArchiveService.extractAll(out, dest);
    expect(again.keptBoth, 2);
  });

  test('gros contenu : compression et extraction dans un isolat', () async {
    // Au-delà de 2 Mio, le travail part dans un isolat : tout ce qui y est
    // envoyé doit pouvoir l'être.
    final big = File(path('gros/data.bin'))..createSync(recursive: true);
    big.writeAsBytesSync(List.generate(3 << 20, (i) => (i * 13) % 251));
    final out = path('gros.7z');
    await ArchiveService.createArchive(
        out, [path('gros')], ArchiveType.sevenZip,
        password: 'p');
    await ArchiveService.extractAll(out, path('x'), password: 'p');
    expect(File(path('x/gros/data.bin')).readAsBytesSync(),
        big.readAsBytesSync());
  });

  test('extraction d\'une seule entrée', () async {
    final out = path('projet.7z');
    await ArchiveService.createArchive(
        out, [makeSource()], ArchiveType.sevenZip);
    final dest = path('x');
    await ArchiveService.extractEntry(out, 'projet/src', dest);
    expect(
        File(p.join(dest, 'projet', 'src', 'app.dart')).existsSync(), isTrue);
    expect(File(p.join(dest, 'projet', 'lisez-moi.txt')).existsSync(), isFalse);
  });

  test('mot de passe et noms chiffrés', () async {
    final out = path('secret.7z');
    await ArchiveService.createArchive(
        out, [makeSource()], ArchiveType.sevenZip,
        password: 'clé', encryptNames: true);
    await expectLater(
        ArchiveService.listEntries(out),
        throwsA(isA<ArchiveOpException>()
            .having((e) => e.isPasswordRequired, 'mot de passe', isTrue)));
    expect(
        await ArchiveService.listEntries(out, password: 'clé'), hasLength(5));
    await expectLater(
        ArchiveService.extractAll(out, path('x'), password: 'non'),
        throwsA(isA<ArchiveOpException>()));
    expect(File(path('x/projet/lisez-moi.txt')).existsSync(), isFalse);
    await ArchiveService.extractAll(out, path('x'), password: 'clé');
    expect(File(path('x/projet/lisez-moi.txt')).readAsStringSync(), 'Bonjour');
  });

  test('entrée dangereuse : archive refusée en bloc', () async {
    final evil = arc.Archive()
      ..addFile(arc.ArchiveFile.string('ok.txt', 'ok'))
      ..addFile(arc.ArchiveFile.string('../evade.txt', 'non'));
    final out = path('evil.7z');
    File(out).writeAsBytesSync(SevenZipWriter.encode(evil));
    await expectLater(ArchiveService.extractAll(out, path('x')),
        throwsA(isA<ArchiveOpException>()));
    expect(File(path('evade.txt')).existsSync(), isFalse);
    expect(File(path('x/ok.txt')).existsSync(), isFalse);
  });

  test('les liens symboliques de l\'archive ne sont pas recréés', () async {
    final r = await ArchiveService.extractAll(
        'test/fixtures/seven_zip/symlink.7z', path('x'));
    expect(r.skippedLinks, 1);
    expect(FileSystemEntity.typeSync(path('x/lien'), followLinks: false),
        FileSystemEntityType.notFound);
    expect(File(path('x/a.txt')).readAsStringSync(), 'Bonjour 7z\n');
  }, skip: Platform.isWindows);

  test('PPMd : liste intégrée, extraction par 7z s\'il est installé', () async {
    const ppmd = 'test/fixtures/seven_zip/ppmd.7z';
    expect(await ArchiveService.listEntries(ppmd), hasLength(6));
    final has7z = await ArchiveService.find7z() != null;
    if (has7z) {
      await ArchiveService.extractAll(ppmd, path('x'));
      expect(File(path('x/a.txt')).readAsStringSync(), 'Bonjour 7z\n');
    } else {
      await expectLater(
          ArchiveService.extractAll(ppmd, path('x')),
          throwsA(isA<ArchiveOpException>()
              .having((e) => e.message, 'message', contains('PPMd'))));
    }
  });
}
