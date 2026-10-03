/// Lecture des archives 7z en Dart pur, sur des archives produites par
/// 7-Zip (test/fixtures/seven_zip, une par méthode ou option).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/services/seven_zip/seven_zip_reader.dart';

const fixtures = 'test/fixtures/seven_zip';

SevenZipArchive open(String name, {String? password}) =>
    SevenZipArchive.open(File(p.join(fixtures, name)).readAsBytesSync(),
        password: password);

String text(SevenZipArchive a, String name) =>
    utf8.decode(a.read(a.entries.firstWhere((e) => e.name == name)));

/// Contenu attendu de l'arborescence source des fixtures.
void expectSourceTree(SevenZipArchive a) {
  final byName = {for (final e in a.entries) e.name: e};
  expect(byName.keys.toSet(), {
    'a.txt',
    'sub',
    'sub/b.txt',
    'sub/été.txt',
    'sub/empty.txt',
    'vide',
  });
  expect(byName['sub']!.isDirectory, isTrue);
  expect(byName['vide']!.isDirectory, isTrue);
  expect(byName['sub/empty.txt']!.isDirectory, isFalse);
  expect(byName['sub/empty.txt']!.size, 0);
  expect(text(a, 'a.txt'), 'Bonjour 7z\n');
  expect(text(a, 'sub/été.txt'), 'accents é à ç\n');
  final b = text(a, 'sub/b.txt');
  expect(b.startsWith('ligne 0 : 0\nligne 1 : 1\n'), isTrue);
  expect(b.endsWith('ligne 2999 : 8994001\n'), isTrue);
  expect(byName['a.txt']!.modified, DateTime.utc(2024, 5, 6, 7, 8, 9));
}

void main() {
  for (final name in [
    'lzma2.7z',
    'lzma.7z',
    'copy.7z',
    'deflate.7z',
    'bzip2.7z',
    'delta.7z',
    'nonsolid.7z',
    'plainheader.7z',
  ]) {
    test('lit $name', () => expectSourceTree(open(name)));
  }

  test('filtre BCJ x86 (binaire, CRC vérifié)', () {
    final a = open('bcj.7z');
    final exe = a.entries.single;
    expect(exe.name, 'bin.exe');
    expect(a.read(exe).length, 60000);
  });

  test('données chiffrées : liste lisible, contenu avec mot de passe', () {
    final a = open('encrypted.7z');
    expect(a.entries.map((e) => e.name), contains('sub/b.txt'));
    expect(
        () => a.read(a.entries.firstWhere((e) => e.name == 'a.txt')),
        throwsA(isA<SevenZipPasswordException>()
            .having((e) => e.missing, 'missing', isTrue)));
    expectSourceTree(open('encrypted.7z', password: 'Secret'));
    final wrong = open('encrypted.7z', password: 'faux');
    expect(
        () => wrong.read(wrong.entries.firstWhere((e) => e.name == 'a.txt')),
        throwsA(isA<SevenZipPasswordException>()
            .having((e) => e.missing, 'missing', isFalse)));
  });

  test('en-tête chiffré : noms illisibles sans mot de passe', () {
    expect(() => open('encrypted_header.7z'),
        throwsA(isA<SevenZipPasswordException>()));
    expect(() => open('encrypted_header.7z', password: 'faux'),
        throwsA(isA<SevenZipPasswordException>()));
    expectSourceTree(open('encrypted_header.7z', password: 'Secret'));
  });

  test('lien symbolique reconnu (jamais recréé à l\'extraction)', () {
    final a = open('symlink.7z');
    final link = a.entries.firstWhere((e) => e.name == 'lien');
    expect(link.isSymbolicLink, isTrue);
    expect(utf8.decode(a.read(link)), 'a.txt');
    expect(
        a.toArchive().files.firstWhere((f) => f.name == 'lien').isSymbolicLink,
        isTrue);
  });

  test('PPMd : liste lisible, contenu signalé non pris en charge', () {
    final a = open('ppmd.7z');
    expect(a.entries, hasLength(6));
    expect(
        () => a.read(a.entries.firstWhere((e) => e.name == 'a.txt')),
        throwsA(isA<SevenZipUnsupportedException>()
            .having((e) => e.method, 'method', 'PPMd')));
  });

  test('pas une archive 7z', () {
    expect(() => SevenZipArchive.open(utf8.encode('PK\x03\x04 bonjour' * 4)),
        throwsFormatException);
  });
}
