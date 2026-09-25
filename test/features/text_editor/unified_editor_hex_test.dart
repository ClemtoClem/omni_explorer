/// Tests de l'éditeur unifié autour de l'hexadécimal : aucun changement de
/// représentation ne doit pouvoir faire écraser le fichier par un contenu
/// vide, périmé ou tronqué.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';

import '../../helpers/editor_harness.dart' as h;

void main() {
  late Directory sandbox;
  late UnifiedEditorProvider editor;

  setUp(() async {
    h.setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('editor_hex_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  Future<void> openEditor(WidgetTester tester, String path,
          {bool forceHex = false}) =>
      h.openEditor(tester, editor, path, forceHex: forceHex);
  Future<void> switchMode(WidgetTester tester, String label) =>
      h.switchMode(tester, label);
  dynamic activeTab() => h.activeTab(editor);

  testWidgets('hex → texte affiche le vrai contenu, pas un document vide',
      (tester) async {
    final file = File(p.join(sandbox.path, 'note.txt'))
      ..writeAsStringSync('bonjour le monde');
    await openEditor(tester, file.path, forceHex: true);
    expect(find.text('OFFSET'), findsOneWidget);

    await switchMode(tester, 'Texte');

    expect(find.text('OFFSET'), findsNothing);
    expect(activeTab().textCtrl.text, 'bonjour le monde');
  });

  testWidgets('hex → texte est refusé pour un fichier binaire', (tester) async {
    final file = File(p.join(sandbox.path, 'data.bin'))
      ..writeAsBytesSync(Uint8List.fromList([0xFF, 0xFE, 0x00, 0xC3, 0x28]));
    await openEditor(tester, file.path, forceHex: true);

    await switchMode(tester, 'Texte');

    expect(find.textContaining('pas du texte UTF-8'), findsOneWidget);
    expect(find.text('OFFSET'), findsOneWidget); // toujours en hexadécimal
  });

  testWidgets('texte → hex charge les octets du fichier', (tester) async {
    final file = File(p.join(sandbox.path, 'note.txt'))
      ..writeAsStringSync('ABC');
    await openEditor(tester, file.path);
    expect(find.text('OFFSET'), findsNothing);

    await switchMode(tester, 'Hexadécimal');

    expect(find.text('OFFSET'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(activeTab().bytes, [0x41, 0x42, 0x43]);
  });

  testWidgets('changement refusé tant que l\'hex n\'est pas sauvegardé',
      (tester) async {
    final file = File(p.join(sandbox.path, 'note.txt'))
      ..writeAsStringSync('ABC');
    await openEditor(tester, file.path, forceHex: true);
    activeTab().bytes[0] = 0x5A;
    activeTab().hexModified = true;

    await switchMode(tester, 'Texte');

    expect(find.textContaining('Sauvegardez d\'abord'), findsOneWidget);
    expect(find.text('OFFSET'), findsOneWidget);
    expect(file.readAsStringSync(), 'ABC');
  });

  testWidgets('un gros fichier tronqué reste en lecture seule', (tester) async {
    final file = File(p.join(sandbox.path, 'big.bin'));
    await tester.runAsync(() async {
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(32 * 1024 * 1024 + 10); // fichier creux > 32 Mio
      await raf.close();
    });
    await openEditor(tester, file.path, forceHex: true);

    expect(find.textContaining('lecture seule pour ne pas tronquer'),
        findsOneWidget);
    expect(activeTab().isReadOnly, isTrue);

    // Double-tap sur l'onglet = demande d'édition : refusée.
    final tabLabel = find.text('big.bin').first;
    await tester.tap(tabLabel);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(tabLabel);
    await tester.pumpAndSettle();
    expect(activeTab().isReadOnly, isTrue);
  });
}
