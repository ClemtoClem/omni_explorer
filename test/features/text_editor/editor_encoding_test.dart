/// Détection et conversion d'encodage de l'éditeur, et position du curseur.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/features/text_editor/models/editor_cursor.dart';
import 'package:omni_explorer/features/text_editor/services/editor_encoding.dart';

void main() {
  /// [text] en UTF-16, sans BOM.
  List<int> utf16(String text, {required bool le}) => [
        for (final u in text.codeUnits)
          ...(le ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF]),
      ];

  group('détection', () {
    EditorEncoding detect(List<int> b, {bool truncated = false}) =>
        EditorEncodingDetector.detect(b, truncated: truncated);

    test('UTF-8 sans BOM, ASCII et vide', () {
      expect(detect(utf8.encode('bonjour, éàç 🎄')), EditorEncoding.utf8);
      expect(detect(utf8.encode('plain ascii')), EditorEncoding.utf8);
      expect(detect(const []), EditorEncoding.utf8);
    });

    test('BOM UTF-8, UTF-16 LE et BE', () {
      expect(detect([0xEF, 0xBB, 0xBF, ...utf8.encode('héllo')]),
          EditorEncoding.utf8Bom);
      expect(detect([0xFF, 0xFE, 0x68, 0x00]), EditorEncoding.utf16Le);
      expect(detect([0xFE, 0xFF, 0x00, 0x68]), EditorEncoding.utf16Be);
    });

    test('UTF-16 sans BOM : parité des octets nuls', () {
      const text = 'Bonjour le monde,\r\nligne deux';
      expect(detect(utf16(text, le: true)), EditorEncoding.utf16Le);
      expect(detect(utf16(text, le: false)), EditorEncoding.utf16Be);
    });

    test('entiers 16 bits (échantillons audio) : pas de l\'UTF-16', () {
      // Petites valeurs : octet de poids fort nul, comme de l'ASCII en
      // UTF-16 LE, mais presque toutes inférieures à 0x20.
      final samples = [
        for (var i = 0; i < 256; i++) ...[i % 16, 0]
      ];
      expect(detect(samples), isNot(EditorEncoding.utf16Le));
    });

    test('Latin-1 : accents isolés, UTF-8 invalide', () {
      expect(detect(latin1.encode('café été')), EditorEncoding.windows1252);
      expect(detect(List.filled(200, 0xE9)), EditorEncoding.windows1252);
    });

    test('caractère UTF-8 coupé en fin de lecture partielle', () {
      final cut = utf8.encode('aé').sublist(0, 2);
      expect(detect(cut, truncated: true), EditorEncoding.utf8);
      expect(detect(cut), EditorEncoding.windows1252);
    });
  });

  group('binaire 8 bits', () {
    test('texte Latin-1 : pas binaire', () {
      expect(
          EditorEncodingDetector.looksBinary8Bit(
              latin1.encode('Résumé\tdes données\r\n\x1B[31mrouge\x1B[0m')),
          isFalse);
    });

    test('octet nul ou contrôles nombreux : binaire', () {
      expect(
          EditorEncodingDetector.looksBinary8Bit([0xE9, 0x00, 0x41]), isTrue);
      final noisy = [for (var i = 0; i < 100; i++) i.isEven ? 0xE9 : 0x02];
      expect(EditorEncodingDetector.looksBinary8Bit(noisy), isTrue);
    });
  });

  group('aller-retour', () {
    const unicode = 'Bonjour,\nÉàçüö\n第三行 🎄';
    for (final enc in EditorEncoding.values
        .where((e) => e != EditorEncoding.windows1252)) {
      test(enc.label, () {
        final bytes = EditorEncodingCodec.encode(unicode, enc);
        expect(EditorEncodingCodec.decode(bytes, enc), unicode);
      });
    }

    test('Windows-1252 : accents et typographie (€, …, « »)', () {
      const text = 'Bonjour, Éàçüö ñ — 12 € … « ok » œ';
      final bytes =
          EditorEncodingCodec.encode(text, EditorEncoding.windows1252);
      expect(bytes.length, text.length); // un octet par caractère
      expect(bytes[text.indexOf('€')], 0x80);
      expect(
          EditorEncodingCodec.decode(bytes, EditorEncoding.windows1252), text);
    });

    test('Windows-1252 : les 256 octets font l\'aller-retour', () {
      final all = Uint8List.fromList(List.generate(256, (i) => i));
      final text = EditorEncodingCodec.decode(all, EditorEncoding.windows1252);
      expect(EditorEncodingCodec.encode(text, EditorEncoding.windows1252), all);
    });

    test('Windows-1252 : refuse un caractère non représentable', () {
      expect(
        () => EditorEncodingCodec.encode('中文', EditorEncoding.windows1252),
        throwsA(isA<EditorEncodingException>()),
      );
    });

    test('UTF-8 invalide : exception dédiée', () {
      expect(
        () => EditorEncodingCodec.decode([0x63, 0xE9], EditorEncoding.utf8),
        throwsA(isA<EditorEncodingException>()),
      );
    });

    test('UTF-16 : nombre d\'octets impair refusé', () {
      expect(
        () => EditorEncodingCodec.decode(
            [0xFF, 0xFE, 0x61, 0x00, 0x62], EditorEncoding.utf16Le),
        throwsA(isA<EditorEncodingException>()),
      );
    });
  });

  group('BOM', () {
    test('retiré du texte décodé', () {
      expect(
          EditorEncodingCodec.decode([0xEF, 0xBB, 0xBF, ...utf8.encode('abc')],
              EditorEncoding.utf8Bom),
          'abc');
      expect(
          EditorEncodingCodec.decode(
              [0xFF, 0xFE, 0x61, 0x00, 0x62, 0x00], EditorEncoding.utf16Le),
          'ab');
    });

    test('UTF-16 sans BOM décodé tel quel, réécrit avec BOM', () {
      expect(
          EditorEncodingCodec.decode(
              utf16('ab', le: false), EditorEncoding.utf16Be),
          'ab');
      expect(EditorEncodingCodec.encode('ab', EditorEncoding.utf16Be),
          [0xFE, 0xFF, 0x00, 0x61, 0x00, 0x62]);
    });

    test('UTF-8 avec BOM : BOM réécrit à l\'identique', () {
      final original = [0xEF, 0xBB, 0xBF, ...utf8.encode('x = 1\n')];
      final text = EditorEncodingCodec.decode(original, EditorEncoding.utf8Bom);
      expect(
          EditorEncodingCodec.encode(text, EditorEncoding.utf8Bom), original);
    });
  });

  group('EditorCursor', () {
    const text = 'ab\ncde\n\nf';

    test('fromOffset', () {
      expect(EditorCursor.fromOffset(text, 0), EditorCursor.start);
      expect(EditorCursor.fromOffset(text, -1), EditorCursor.start);
      expect(EditorCursor.fromOffset(text, 2),
          const EditorCursor(line: 1, column: 3));
      expect(EditorCursor.fromOffset(text, 3),
          const EditorCursor(line: 2, column: 1));
      expect(EditorCursor.fromOffset(text, 999),
          const EditorCursor(line: 4, column: 2));
    });

    test('offsetOfLine et lineCountOf', () {
      expect(EditorCursor.offsetOfLine(text, 1), 0);
      expect(EditorCursor.offsetOfLine(text, 2), 3);
      expect(EditorCursor.offsetOfLine(text, 3), 7);
      expect(EditorCursor.offsetOfLine(text, 4), 8);
      expect(EditorCursor.offsetOfLine(text, 5), -1);
      expect(EditorCursor.offsetOfLine(text, 0), -1);
      expect(EditorCursor.lineCountOf(text), 4);
      expect(EditorCursor.lineCountOf(''), 1);
    });
  });
}
