/// Tests de l'éditeur unifié autour de l'hexadécimal : aucun changement de
/// représentation ne doit pouvoir faire écraser le fichier par un contenu
/// vide, périmé ou tronqué.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';

void main() {
  late Directory sandbox;
  late UnifiedEditorProvider editor;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('editor_hex_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  /// Laisse aboutir les entrées/sorties réelles déclenchées depuis la zone de
  /// temps simulé du test : chaque étape (open, length, read…) a besoin d'un
  /// tour de boucle réel puis d'un `pump` pour livrer son résultat.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  /// Ouvre [path] dans l'éditeur et attend la fin de la lecture disque.
  Future<void> openEditor(WidgetTester tester, String path,
      {bool forceHex = false}) async {
    final settings = SettingsService();
    await tester.runAsync(() async {
      await settings.init();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: editor),
        ],
        child: MaterialApp(
          home: UnifiedEditorScreen(filePaths: [path], forceHex: forceHex),
        ),
      ));
    });
    await settleIo(tester);
  }

  /// Choisit [label] dans le menu « Mode d'interprétation ».
  Future<void> switchMode(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    await settleIo(tester);
  }

  // L'onglet est une classe privée de l'écran : accès dynamique pour les
  // vérifications internes.
  dynamic activeTab() => (editor as dynamic).activeTab;

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
