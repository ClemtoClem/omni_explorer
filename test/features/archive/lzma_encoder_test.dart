/// Encodeur LZMA : aller-retour avec le décodeur du paquet `archive`, et
/// flux lisible par l'implémentation de référence (xz / liblzma).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/services/seven_zip/lzma_encoder.dart';

Uint8List decode(Uint8List packed, LzmaProperties props, int size) {
  final d = arc.LzmaDecoder()
    ..reset(
        literalContextBits: props.lc,
        literalPositionBits: props.lp,
        positionBits: props.pb,
        resetDictionary: true);
  return d.decode(arc.InputMemoryStream(packed), size);
}

void main() {
  final samples = <String, Uint8List>{
    'vide': Uint8List(0),
    'un octet': Uint8List.fromList([42]),
    'texte répété': Uint8List.fromList(
        utf8.encode('Le chat mange la souris. ' * 2000 + 'Fin.')),
    'aléatoire': Uint8List.fromList(
        List.generate(200000, (_) => Random(7).nextInt(256))),
    'zéros': Uint8List(300000),
    'mélange': Uint8List.fromList([
      for (var i = 0; i < 150000; i++)
        i % 1000 < 500 ? (i * 31) & 0xFF : Random(i).nextInt(4) + 65,
    ]),
  };

  for (final e in samples.entries) {
    test('aller-retour : ${e.key}', () {
      final props = LzmaProperties(
          dictionarySize: LzmaProperties.dictionaryFor(e.value.length));
      final packed = LzmaEncoder.encode(e.value, props);
      expect(decode(packed, props, e.value.length), e.value);
    });
  }

  test('compresse vraiment un texte répétitif', () {
    final data = samples['texte répété']!;
    const props = LzmaProperties(dictionarySize: 1 << 16);
    expect(LzmaEncoder.encode(data, props).length, lessThan(data.length ~/ 50));
  });

  test('flux lu par liblzma (Python)', () async {
    final python = await Process.run('which', ['python3']);
    if (python.exitCode != 0) return; // outil absent : test sauté
    final data = Uint8List.fromList(
        utf8.encode(List.generate(5000, (i) => 'ligne $i : ${i * i}\n').join()));
    const props = LzmaProperties(dictionarySize: 1 << 20);
    final packed = LzmaEncoder.encode(data, props);
    final dir = Directory(p.join(Directory.current.path, 'build'))
      ..createSync(recursive: true);
    final tmp = await dir.createTemp('lzma_test_');
    addTearDown(() => tmp.delete(recursive: true));
    // En-tête « .lzma » (props + taille 64 bits) pour FORMAT_ALONE.
    final header = BytesBuilder()
      ..add(props.toBytes())
      ..add((ByteData(8)..setUint64(0, data.length, Endian.little))
          .buffer
          .asUint8List());
    final f = File(p.join(tmp.path, 'x.lzma'))
      ..writeAsBytesSync([...header.toBytes(), ...packed]);
    final r = await Process.run('python3', [
      '-c',
      'import lzma,sys;sys.stdout.buffer.write('
          'lzma.decompress(open(sys.argv[1],"rb").read(),'
          'format=lzma.FORMAT_ALONE))',
      f.path,
    ], stdoutEncoding: null);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout as List<int>, data);
  });
}
