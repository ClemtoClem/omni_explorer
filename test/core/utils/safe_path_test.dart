import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/core/utils/safe_path.dart';

void main() {
  group('SafePath.resolveWithin', () {
    final root = p.normalize(p.absolute('dest'));

    test('accepte les chemins relatifs normaux', () {
      expect(
          SafePath.resolveWithin(root, 'a/b.txt'), p.join(root, 'a', 'b.txt'));
      expect(SafePath.resolveWithin(root, './a//b.txt'),
          p.join(root, 'a', 'b.txt'));
      expect(SafePath.resolveWithin(root, 'dir/'), p.join(root, 'dir'));
    });

    test('traite « \\ » comme un séparateur', () {
      expect(
          SafePath.resolveWithin(root, r'a\b.txt'), p.join(root, 'a', 'b.txt'));
    });

    test('une entrée vide désigne la racine', () {
      expect(SafePath.resolveWithin(root, ''), root);
      expect(SafePath.resolveWithin(root, './'), root);
    });

    for (final evil in [
      '../evil.txt',
      'a/../../evil.txt',
      'a/../b.txt', // refusé même s'il resterait dans la racine
      '..',
      r'..\evil.txt',
      r'a\..\..\evil.txt',
      '/etc/passwd',
      r'\\server\share\evil',
      'C:/Windows/evil',
      r'c:\evil',
      'c:evil',
      'a\u0000b',
    ]) {
      test('refuse « $evil »', () {
        expect(() => SafePath.resolveWithin(root, evil),
            throwsA(isA<UnsafePathException>()));
      });
    }
  });

  group('SafeExtractionRoot', () {
    late Directory sandbox;
    late String dest;
    late String outside;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('safe_path_test_');
      dest = p.join(sandbox.path, 'dest');
      outside = p.join(sandbox.path, 'outside');
      await Directory(outside).create();
    });

    tearDown(() => sandbox.delete(recursive: true));

    test('crée la racine et les dossiers parents', () async {
      final root = await SafeExtractionRoot.open(dest);
      final path = await root.prepareFile('a/b/c.txt');
      expect(path, p.join(dest, 'a', 'b', 'c.txt'));
      expect(Directory(p.join(dest, 'a', 'b')).existsSync(), isTrue);
    });

    test('refuse un lien symbolique existant qui mène hors de la racine',
        () async {
      await Directory(dest).create();
      await Link(p.join(dest, 'escape')).create(outside);
      final root = await SafeExtractionRoot.open(dest);

      await expectLater(root.prepareFile('escape/a/b/evil.txt'),
          throwsA(isA<UnsafePathException>()));
      await expectLater(root.prepareDirectory('escape/sub'),
          throwsA(isA<UnsafePathException>()));
      // Rien n'a été créé à l'extérieur, pas même des dossiers vides.
      expect(Directory(outside).listSync(), isEmpty);
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);

    test('refuse d\'écrire à travers un lien symbolique vers un fichier',
        () async {
      await Directory(dest).create();
      final victim = File(p.join(outside, 'victim.txt'))
        ..writeAsStringSync('original');
      await Link(p.join(dest, 'file.txt')).create(victim.path);
      final root = await SafeExtractionRoot.open(dest);

      await expectLater(
          root.prepareFile('file.txt'), throwsA(isA<UnsafePathException>()));
      expect(victim.readAsStringSync(), 'original');
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);

    test('accepte une racine qui est elle-même un lien (ex. /sdcard)',
        () async {
      final real = p.join(sandbox.path, 'real');
      await Directory(real).create();
      await Link(dest).create(real);
      final root = await SafeExtractionRoot.open(dest);

      final path = await root.prepareFile('a/b.txt');
      File(path).writeAsStringSync('ok');
      expect(File(p.join(real, 'a', 'b.txt')).readAsStringSync(), 'ok');
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);

    test('accepte un lien interne qui reste dans la racine', () async {
      await Directory(p.join(dest, 'inner')).create(recursive: true);
      await Link(p.join(dest, 'alias')).create(p.join(dest, 'inner'));
      final root = await SafeExtractionRoot.open(dest);

      final path = await root.prepareFile('alias/x.txt');
      File(path).writeAsStringSync('ok');
      expect(File(p.join(dest, 'inner', 'x.txt')).existsSync(), isTrue);
    }, skip: Platform.isWindows ? 'liens symboliques non garantis' : null);
  });
}
