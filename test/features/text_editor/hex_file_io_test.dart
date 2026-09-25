import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/text_editor/services/hex_file_io.dart';

void main() {
  late Directory sandbox;
  late File file;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('hex_file_io_test_');
    file = File(p.join(sandbox.path, 'data.bin'));
  });

  tearDown(() => sandbox.delete(recursive: true));

  Uint8List pattern(int length) =>
      Uint8List.fromList(List<int>.generate(length, (i) => i % 251));

  group('load', () {
    test('charge entièrement un petit fichier', () async {
      await file.writeAsBytes(pattern(1000));

      final r = await HexFileIO.load(file.path);

      expect(r.bytes, pattern(1000));
      expect(r.fileLength, 1000);
      expect(r.isTruncated, isFalse);
    });

    test('ne charge que le début d\'un gros fichier', () async {
      await file.writeAsBytes(pattern(10000));

      final r = await HexFileIO.load(file.path, maxBytes: 4096);

      expect(r.bytes.length, 4096);
      expect(r.bytes, pattern(10000).sublist(0, 4096));
      expect(r.fileLength, 10000);
      expect(r.isTruncated, isTrue);
    });

    test('fichier vide', () async {
      await file.writeAsBytes(const []);

      final r = await HexFileIO.load(file.path);

      expect(r.bytes, isEmpty);
      expect(r.isTruncated, isFalse);
    });

    test('limite par défaut : 32 Mio', () async {
      final big = await file.open(mode: FileMode.write);
      await big.truncate(HexFileIO.maxLoadedBytes + 1); // fichier creux
      await big.close();

      final r = await HexFileIO.load(file.path);

      expect(r.bytes.length, HexFileIO.maxLoadedBytes);
      expect(r.isTruncated, isTrue);
    });
  });

  group('save', () {
    test('enregistre une modification d\'octet', () async {
      await file.writeAsBytes(pattern(1000));
      final r = await HexFileIO.load(file.path);
      r.bytes[10] = 0xFF;

      await HexFileIO.save(file.path, r.bytes, loadedFileLength: r.fileLength);

      final saved = await file.readAsBytes();
      expect(saved.length, 1000);
      expect(saved[10], 0xFF);
    });

    test('refuse un tampon partiel et laisse le fichier intact', () async {
      final original = pattern(10000);
      await file.writeAsBytes(original);
      final r = await HexFileIO.load(file.path, maxBytes: 4096);
      r.bytes[0] = 0xAA;

      await expectLater(
          HexFileIO.save(file.path, r.bytes, loadedFileLength: r.fileLength),
          throwsA(isA<HexSaveRefused>()));
      expect(await file.readAsBytes(), original);
    });

    test('refuse si le fichier a changé de taille sur le disque', () async {
      await file.writeAsBytes(pattern(1000));
      final r = await HexFileIO.load(file.path);
      await file.writeAsBytes(pattern(2000)); // modifié par une autre app

      await expectLater(
          HexFileIO.save(file.path, r.bytes, loadedFileLength: r.fileLength),
          throwsA(isA<HexSaveRefused>()));
      expect((await file.readAsBytes()).length, 2000);
    });
  });
}
