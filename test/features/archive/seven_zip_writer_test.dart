/// Écriture d'archives 7z : relues par le lecteur intégré, et validées par
/// 7-Zip lui-même quand il est installé (`7z t`, `7z x`).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/services/seven_zip/seven_zip_reader.dart';
import 'package:omni_explorer/features/archive/services/seven_zip/seven_zip_writer.dart';

arc.Archive sample() {
  final a = arc.Archive();
  a.addFile(arc.ArchiveFile.directory('docs/'));
  a.addFile(arc.ArchiveFile.bytes('docs/note.txt', utf8.encode('Bonjour\n'))
    ..lastModTime =
        DateTime.utc(2023, 1, 2, 3, 4, 5).millisecondsSinceEpoch ~/ 1000
    ..mode = 0x1ED); // 0755
  a.addFile(arc.ArchiveFile.bytes(
      'docs/long.txt', utf8.encode('répétition ' * 5000)));
  a.addFile(arc.ArchiveFile.bytes('vide.txt', Uint8List(0)));
  a.addFile(arc.ArchiveFile.directory('dossier vide/'));
  a.addFile(arc.ArchiveFile.bytes('données.bin',
      Uint8List.fromList(List.generate(70000, (i) => (i * 7919) & 0xFF))));
  return a;
}

void expectSample(SevenZipArchive r) {
  final byName = {for (final e in r.entries) e.name: e};
  expect(byName.keys.toSet(), {
    'docs',
    'docs/note.txt',
    'docs/long.txt',
    'vide.txt',
    'dossier vide',
    'données.bin',
  });
  expect(byName['docs']!.isDirectory, isTrue);
  expect(byName['dossier vide']!.isDirectory, isTrue);
  expect(byName['vide.txt']!.isDirectory, isFalse);
  expect(utf8.decode(r.read(byName['docs/note.txt']!)), 'Bonjour\n');
  expect(utf8.decode(r.read(byName['docs/long.txt']!)), 'répétition ' * 5000);
  expect(r.read(byName['données.bin']!).length, 70000);
  expect(byName['docs/note.txt']!.modified, DateTime.utc(2023, 1, 2, 3, 4, 5));
  expect(byName['docs/note.txt']!.unixMode! & 0x1FF, 0x1ED);
}

void main() {
  test('aller-retour avec le lecteur', () {
    final bytes = SevenZipWriter.encode(sample());
    expectSample(SevenZipArchive.open(bytes));
    // Compression effective : le texte répété ne pèse presque rien.
    expect(bytes.length, lessThan(70000 + 2000));
  });

  test('avec mot de passe : contenu chiffré, noms visibles', () {
    final bytes = SevenZipWriter.encode(sample(), password: 'clé');
    final locked = SevenZipArchive.open(bytes);
    expect(locked.entries, hasLength(6));
    expect(() => locked.read(locked.entries.firstWhere((e) => e.size > 0)),
        throwsA(isA<SevenZipPasswordException>()));
    expectSample(SevenZipArchive.open(bytes, password: 'clé'));
  });

  test('en-tête chiffré : rien de lisible sans mot de passe', () {
    final bytes =
        SevenZipWriter.encode(sample(), password: 'clé', encryptHeader: true);
    expect(utf8.decode(bytes, allowMalformed: true).contains('note'), isFalse);
    expect(() => SevenZipArchive.open(bytes),
        throwsA(isA<SevenZipPasswordException>()));
    expectSample(SevenZipArchive.open(bytes, password: 'clé'));
  });

  test('archive vide', () {
    final bytes = SevenZipWriter.encode(arc.Archive());
    expect(SevenZipArchive.open(bytes).entries, isEmpty);
  });

  group('validé par 7-Zip', () {
    late Directory tmp;
    late bool has7z;
    setUpAll(() async {
      has7z = (await Process.run('which', ['7z'])).exitCode == 0;
    });
    setUp(() async {
      final base = Directory(p.join(Directory.current.path, 'build'))
        ..createSync(recursive: true);
      tmp = await base.createTemp('seven_zip_writer_test_');
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> check({String? password, bool encryptHeader = false}) async {
      if (!has7z) return; // 7-Zip absent : seule la relecture interne compte
      final file = File(p.join(tmp.path, 'out.7z'))
        ..writeAsBytesSync(SevenZipWriter.encode(sample(),
            password: password, encryptHeader: encryptHeader));
      final pw = password == null ? <String>[] : ['-p$password'];
      final t = await Process.run('7z', ['t', ...pw, file.path]);
      expect(t.exitCode, 0, reason: '${t.stdout}\n${t.stderr}');
      final out = p.join(tmp.path, 'x');
      final x = await Process.run('7z', ['x', ...pw, '-o$out', file.path]);
      expect(x.exitCode, 0, reason: '${x.stdout}\n${x.stderr}');
      expect(File(p.join(out, 'docs', 'note.txt')).readAsStringSync(),
          'Bonjour\n');
      expect(File(p.join(out, 'docs', 'long.txt')).readAsStringSync(),
          'répétition ' * 5000);
      expect(File(p.join(out, 'vide.txt')).lengthSync(), 0);
      expect(Directory(p.join(out, 'dossier vide')).existsSync(), isTrue);
      expect(File(p.join(out, 'données.bin')).readAsBytesSync(),
          List.generate(70000, (i) => (i * 7919) & 0xFF));
    }

    test('sans mot de passe', () => check());
    test('avec mot de passe', () => check(password: 'clé ç'));
    test('en-tête chiffré', () => check(password: 'x', encryptHeader: true));
  });
}
