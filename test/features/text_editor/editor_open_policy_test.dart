import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/text_editor/models/editor_view_mode.dart';
import 'package:omni_explorer/features/text_editor/services/editor_open_policy.dart';

void main() {
  const mb = 1024 * 1024;

  group('détection du binaire', () {
    test('texte ASCII et UTF-8 accentué : texte', () {
      expect(FileProbe.looksBinaryBytes(utf8.encode('hello')), isFalse);
      expect(FileProbe.looksBinaryBytes(utf8.encode('Été à Noël 🎄')), isFalse);
      expect(FileProbe.looksBinaryBytes(const []), isFalse);
    });

    test('octet nul ou UTF-8 invalide : binaire', () {
      expect(FileProbe.looksBinaryBytes([0x41, 0x00, 0x42]), isTrue);
      expect(FileProbe.looksBinaryBytes([0xFF, 0xFE, 0x41]), isTrue);
      // Latin-1 « é » seul : UTF-8 invalide.
      expect(FileProbe.looksBinaryBytes([0x63, 0x61, 0x66, 0xE9]), isTrue);
    });

    test('caractère coupé par la lecture partielle : reste du texte', () {
      final bytes = utf8.encode('aé'); // [0x61, 0xC3, 0xA9]
      final cut = bytes.sublist(0, 2); // « é » coupé en deux
      expect(FileProbe.looksBinaryBytes(cut, truncated: true), isFalse);
      expect(FileProbe.looksBinaryBytes(cut), isTrue);
    });
  });

  group('FileProbe.of', () {
    late Directory sandbox;
    setUp(() async =>
        sandbox = await Directory.systemTemp.createTemp('open_policy_test_'));
    tearDown(() => sandbox.delete(recursive: true));

    test('lit la taille sans charger le fichier', () async {
      final f = File(p.join(sandbox.path, 'big.log'));
      final raf = await f.open(mode: FileMode.write);
      await raf.writeFrom(utf8.encode('début du journal\n'));
      await raf.truncate(3 * 1024 * mb); // 3 Gio (creux)
      await raf.close();

      final probe = await FileProbe.of(f.path);

      expect(probe.size, 3 * 1024 * mb);
      // Octets nuls après le texte, dans les 8 premiers Kio.
      expect(probe.looksBinary, isTrue);
    });

    test('ligne trop longue, y compris à cheval sur deux blocs de lecture',
        () async {
      // 50 Kio de lignes courtes, puis une ligne de 40 Kio qui franchit la
      // limite de bloc (64 Kio).
      final short = '${'x' * 99}\n' * 512; // 51 200 octets
      final f = File(p.join(sandbox.path, 'min.js'))
        ..writeAsStringSync('$short${'y' * (40 * 1024)}\nfin\n');

      final probe = await FileProbe.of(f.path);

      expect(probe.looksBinary, isFalse);
      expect(probe.hasLongLines, isTrue);
    });

    test('lignes juste sous la limite : acceptées', () async {
      final line = '${'z' * (EditorLimits.maxLineBytes - 1)}\n';
      final f = File(p.join(sandbox.path, 'ok.txt'))
        ..writeAsStringSync(line * 4);
      expect((await FileProbe.of(f.path)).hasLongLines, isFalse);
    });

    test('texte en mémoire', () {
      expect(FileProbe.ofText('a\nb').hasLongLines, isFalse);
      expect(
          FileProbe.ofText('x' * (EditorLimits.maxLineBytes + 1)).hasLongLines,
          isTrue);
    });

    test('fichier texte', () async {
      final f = File(p.join(sandbox.path, 'a.txt'))
        ..writeAsStringSync('x' * 10000);
      final probe = await FileProbe.of(f.path);
      expect(probe.size, 10000);
      expect(probe.looksBinary, isFalse);
    });
  });

  group('décision d\'ouverture', () {
    FileProbe text(int size) => FileProbe(size: size, looksBinary: false);

    test('fichier normal : mode détecté', () {
      final d = EditorOpenPolicy.decide(text(1000), EditorViewMode.code);
      expect(d.mode, EditorViewMode.code);
      expect(d.notice, isNull);
      expect(d.needsHexConfirmation, isFalse);
    });

    test('forçage hexadécimal', () {
      expect(
          EditorOpenPolicy.decide(text(10), EditorViewMode.text, forceHex: true)
              .mode,
          EditorViewMode.hex);
    });

    test('contenu binaire : hexadécimal, avec un message', () {
      final d = EditorOpenPolicy.decide(
          const FileProbe(size: 100, looksBinary: true), EditorViewMode.text);
      expect(d.mode, EditorViewMode.hex);
      expect(d.notice, isNotNull);
    });

    test('au-delà de 10 Mio : confirmation avant l\'hexadécimal', () {
      final d = EditorOpenPolicy.decide(
          text(EditorLimits.textMaxBytes + 1), EditorViewMode.text);
      expect(d.mode, EditorViewMode.hex);
      expect(d.needsHexConfirmation, isTrue);
    });

    test('code au-delà de 2 Mio : texte brut', () {
      for (final mode in [EditorViewMode.code, EditorViewMode.markdown]) {
        final d = EditorOpenPolicy.decide(
            text(EditorLimits.highlightMaxBytes + 1), mode);
        expect(d.mode, EditorViewMode.text);
        expect(d.notice, isNotNull);
      }
    });

    test('ligne trop longue : confirmation avant l\'hexadécimal', () {
      final d = EditorOpenPolicy.decide(
          const FileProbe(size: 1000, looksBinary: false, hasLongLines: true),
          EditorViewMode.code);
      expect(d.mode, EditorViewMode.hex);
      expect(d.block, TextBlock.longLines);
    });

    test('texte brut de 5 Mio : ouvert normalement', () {
      final d = EditorOpenPolicy.decide(text(5 * mb), EditorViewMode.text);
      expect(d.mode, EditorViewMode.text);
      expect(d.needsHexConfirmation, isFalse);
    });
  });

  group('changement de mode', () {
    FileProbe text(int size, {bool longLines = false}) =>
        FileProbe(size: size, looksBinary: false, hasLongLines: longLines);

    test('limites de taille', () {
      expect(EditorOpenPolicy.refuseSwitch(text(3 * mb), EditorViewMode.code),
          isNotNull);
      expect(
          EditorOpenPolicy.refuseSwitch(text(mb), EditorViewMode.code), isNull);
      expect(EditorOpenPolicy.refuseSwitch(text(11 * mb), EditorViewMode.text),
          isNotNull);
      expect(EditorOpenPolicy.refuseSwitch(text(5 * mb), EditorViewMode.text),
          isNull);
      expect(EditorOpenPolicy.refuseSwitch(text(5000 * mb), EditorViewMode.hex),
          isNull);
    });

    test('lignes trop longues : texte refusé, hex accepté', () {
      final probe = text(100 * 1024, longLines: true);
      expect(
          EditorOpenPolicy.refuseSwitch(probe, EditorViewMode.text), isNotNull);
      expect(
          EditorOpenPolicy.refuseSwitch(probe, EditorViewMode.code), isNotNull);
      expect(EditorOpenPolicy.refuseSwitch(probe, EditorViewMode.hex), isNull);
    });
  });
}
