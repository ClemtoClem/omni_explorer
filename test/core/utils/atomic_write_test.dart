import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/core/utils/atomic_write.dart';

void main() {
  late Directory sandbox;

  final noLinks = Platform.isWindows ? 'liens symboliques non garantis' : null;
  final noChmod = Platform.isWindows
      ? 'permissions POSIX indisponibles'
      : (Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'root ignore les permissions'
          : null);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('atomic_write_test_');
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', sandbox.path]);
    await sandbox.delete(recursive: true);
  });

  String path(String name) => p.join(sandbox.path, name);
  List<String> names() =>
      sandbox.listSync().map((e) => p.basename(e.path)).toList()..sort();
  int mode(String f) => File(f).statSync().mode & 0xFFF;

  test('crée un nouveau fichier sans laisser de temporaire', () async {
    await AtomicWrite.string(path('a.txt'), 'bonjour');
    expect(File(path('a.txt')).readAsStringSync(), 'bonjour');
    expect(names(), ['a.txt']);
  });

  test('remplace le contenu d\'un fichier existant', () async {
    File(path('a.txt')).writeAsStringSync('un contenu bien plus long');
    await AtomicWrite.string(path('a.txt'), 'court');
    expect(File(path('a.txt')).readAsStringSync(), 'court');
    expect(names(), ['a.txt']);
  });

  test('conserve les permissions (script exécutable)', () async {
    final f = File(path('run.sh'))..writeAsStringSync('#!/bin/sh\n');
    await Process.run('chmod', ['750', f.path]);

    await AtomicWrite.string(f.path, '#!/bin/sh\necho ok\n');

    expect(mode(f.path).toRadixString(8), '750');
  }, skip: noChmod);

  test('conserve un fichier privé (600)', () async {
    final f = File(path('secret.txt'))..writeAsStringSync('x');
    await Process.run('chmod', ['600', f.path]);

    await AtomicWrite.string(f.path, 'y');

    expect(mode(f.path).toRadixString(8), '600');
  }, skip: noChmod);

  test('écrit dans la cible d\'un lien, qui reste un lien', () async {
    await Directory(path('real')).create();
    File(path('real/target.txt')).writeAsStringSync('ancien');
    // Lien relatif, puis lien vers ce lien (chaîne).
    await Link(path('link.txt')).create('real/target.txt');
    await Link(path('link2.txt')).create(path('link.txt'));

    await AtomicWrite.string(path('link2.txt'), 'nouveau');

    expect(FileSystemEntity.isLinkSync(path('link.txt')), isTrue);
    expect(FileSystemEntity.isLinkSync(path('link2.txt')), isTrue);
    expect(File(path('real/target.txt')).readAsStringSync(), 'nouveau');
  }, skip: noLinks);

  test('cycle de liens : erreur, rien n\'est écrit', () async {
    await Link(path('a')).create(path('b'));
    await Link(path('b')).create(path('a'));

    await expectLater(AtomicWrite.string(path('a'), 'x'),
        throwsA(isA<FileSystemException>()));
    expect(names(), ['a', 'b']);
  }, skip: noLinks);

  test('échec du renommage : cible intacte, aucun temporaire', () async {
    // Un dossier occupe le chemin : le renommage final échoue.
    await Directory(path('occupe')).create();
    File(path('occupe/keep.txt')).writeAsStringSync('x');

    await expectLater(AtomicWrite.string(path('occupe'), 'contenu'),
        throwsA(isA<FileSystemException>()));
    expect(names(), ['occupe']);
    expect(File(path('occupe/keep.txt')).readAsStringSync(), 'x');
  });

  test('dossier non modifiable, fichier modifiable : écriture directe',
      () async {
    await Directory(path('ro')).create();
    final f = File(path('ro/f.txt'))..writeAsStringSync('ancien');
    await Process.run('chmod', ['555', path('ro')]);

    await AtomicWrite.string(f.path, 'nouveau');

    expect(f.readAsStringSync(), 'nouveau');
  }, skip: noChmod);

  test('nouveau fichier dans un dossier non modifiable : erreur', () async {
    await Directory(path('ro')).create();
    await Process.run('chmod', ['555', path('ro')]);

    await expectLater(AtomicWrite.string(path('ro/new.txt'), 'x'),
        throwsA(isA<FileSystemException>()));
  }, skip: noChmod);
}
