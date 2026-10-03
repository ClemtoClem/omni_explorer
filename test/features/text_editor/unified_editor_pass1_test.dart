/// Éditeur unifié, refonte passe 1 : cycle de vie (pas de setState pendant
/// build), encodages, barre d'état, « Aller à la ligne », menu des onglets,
/// brouillons des modifications non sauvegardées.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';
import 'package:omni_explorer/features/text_editor/services/editor_drafts.dart';
import 'package:omni_explorer/features/text_editor/services/editor_encoding.dart';
import 'package:omni_explorer/features/text_editor/widgets/editor_tab_bar.dart';

import '../../helpers/editor_harness.dart' as h;

void main() {
  late Directory sandbox;
  late UnifiedEditorProvider editor;

  setUp(() async {
    h.setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('editor_pass1_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  dynamic tab() => h.activeTab(editor);
  List<dynamic> tabs() => (editor as dynamic).tabs as List<dynamic>;

  File write(String name, String text) =>
      File(p.join(sandbox.path, name))..writeAsStringSync(text);

  /// Ouvre plusieurs fichiers d'un coup et attend le dernier onglet.
  Future<void> openAll(WidgetTester tester, List<String> paths) async {
    final settings = SettingsService();
    await tester.runAsync(() async {
      await settings.init();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: editor),
        ],
        child: MaterialApp(home: UnifiedEditorScreen(filePaths: paths)),
      ));
    });
    await h.settleIo(tester, until: () => tabs().length == paths.length);
  }

  /// Laisse partir les minuteries `Duration.zero` (barre d'état,
  /// autocomplétion) : `pump()` sans durée n'avance pas l'horloge simulée.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  /// L'éditeur de code laisse une minuterie de clignotement du curseur
  /// après sa destruction : démonter l'écran et la laisser expirer.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// Onglet [name] dans la barre d'onglets (le titre de la barre
  /// d'application affiche aussi le nom de l'onglet actif).
  Finder tabLabel(String name) =>
      find.descendant(of: find.byType(EditorTabBar), matching: find.text(name));

  /// Modifie le texte de l'onglet actif (mode texte) comme une saisie : le
  /// champ marque l'onglet modifié, et l'écran se reconstruit.
  Future<void> edit(WidgetTester tester, String text) async {
    tab().isReadOnly = false;
    tab().textCtrl.text = text;
    tab().isDirty = true;
    editor.setActiveTabIndex(editor.activeTabIndex); // notifie l'écran
    await tick(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.save_rounded));
    await tester.pump();
    await h.settleIo(tester, until: () => tab().isDirty == false);
  }

  group('cycle de vie', () {
    testWidgets(
        'ouvrir un fichier de code ne lève pas « setState during build »',
        (tester) async {
      final f = write('main.dart', 'void main() {\n  print("hi");\n}\n');
      await h.openEditor(tester, editor, f.path);

      expect(tab().viewMode, EditorViewMode.code);
      // Une erreur de construction serait remontée ici.
      expect(tester.takeException(), isNull);

      // Passage en édition et frappe : l'autocomplétion se met à jour.
      tab().isReadOnly = false;
      tab().codeCtrl.text = 'void main() {\n  pr\n}\n';
      await tick(tester);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });

  group('encodages', () {
    testWidgets(
        'un fichier Latin-1 s\'ouvre en texte et se réenregistre en '
        'Windows-1252', (tester) async {
      final f = File(p.join(sandbox.path, 'ancien.txt'))
        ..writeAsBytesSync(latin1.encode('Résumé : café\n'));
      await h.openEditor(tester, editor, f.path);

      expect(tab().viewMode, EditorViewMode.text);
      expect(tab().encoding, EditorEncoding.windows1252);
      expect(tab().textCtrl.text, 'Résumé : café\n');
      await tick(tester);
      expect(find.text('Windows-1252'), findsOneWidget); // barre d'état

      await edit(tester, 'Résumé : thé — 3 €\n');
      await save(tester);

      expect(
          f.readAsBytesSync(),
          EditorEncodingCodec.encode(
              'Résumé : thé — 3 €\n', EditorEncoding.windows1252));
    });

    testWidgets(
        'caractère absent de Windows-1252 : sauvegarde refusée, '
        'fichier intact', (tester) async {
      final original = latin1.encode('café\n');
      final f = File(p.join(sandbox.path, 'ancien.txt'))
        ..writeAsBytesSync(original);
      await h.openEditor(tester, editor, f.path);

      await edit(tester, 'café 中文\n');
      await tester.tap(find.byIcon(Icons.save_rounded));
      await h.settleIo(tester);

      expect(
          find.textContaining('n\'existe pas en Windows-1252'), findsOneWidget);
      expect(f.readAsBytesSync(), original);
      expect(tab().isDirty, isTrue);
    });

    testWidgets('UTF-16 avec BOM : ouvert en texte, réécrit en UTF-16',
        (tester) async {
      final f = File(p.join(sandbox.path, 'win.txt'))
        ..writeAsBytesSync(
            EditorEncodingCodec.encode('Hello\r\n', EditorEncoding.utf16Le));
      await h.openEditor(tester, editor, f.path);

      expect(tab().viewMode, EditorViewMode.text);
      expect(tab().textCtrl.text, 'Hello\r\n');

      await edit(tester, 'Bye\r\n');
      await save(tester);

      expect(f.readAsBytesSync(),
          EditorEncodingCodec.encode('Bye\r\n', EditorEncoding.utf16Le));
    });
  });

  group('barre d\'état et « Aller à la ligne »', () {
    testWidgets('position du curseur et taille du document', (tester) async {
      final f = write('notes.txt', 'un\ndeux\ntrois');
      await h.openEditor(tester, editor, f.path);
      await tick(tester);

      expect(find.text('Ln 1, Col 1'), findsOneWidget);
      expect(find.text('3 lignes · 13 car.'), findsOneWidget);
      expect(find.text('UTF-8'), findsOneWidget);

      tab().textCtrl.selection = const TextSelection.collapsed(offset: 5);
      await tick(tester);
      expect(find.text('Ln 2, Col 3'), findsOneWidget);
    });

    testWidgets('code : aller à la ligne 3 depuis la barre d\'état',
        (tester) async {
      final f = write('main.dart', 'a\nb\nc\nd\n');
      await h.openEditor(tester, editor, f.path);
      tab().isReadOnly = false;
      await tick(tester);

      await tester.tap(find.text('Ln 1, Col 1'));
      await tester.pumpAndSettle();
      expect(find.text('Aller à la ligne'), findsOneWidget);

      // Hors limites : message, le dialogue reste ouvert.
      await tester.enterText(find.byType(TextField).last, '99');
      await tester.tap(find.text('Aller'));
      await tester.pump();
      expect(find.text('Numéro entre 1 et 5'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '3');
      await tester.tap(find.text('Aller'));
      await tester.pumpAndSettle();
      await tick(tester);

      expect(find.text('Aller à la ligne'), findsNothing);
      expect(tab().codeCtrl.selection.extentIndex, 2);
      expect(find.text('Ln 3, Col 1'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('menu des onglets', () {
    testWidgets('« Fermer les autres » garde l\'onglet choisi', (tester) async {
      final paths = [
        for (final n in ['a.txt', 'b.txt', 'c.txt']) write(n, n).path,
      ];
      await openAll(tester, paths);

      await tester.longPress(tabLabel('b.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fermer les autres'));
      await tester.pumpAndSettle();
      await h.settleIo(tester);

      expect(tabs().map((t) => t.name), ['b.txt']);
      expect(tab().name, 'b.txt');

      // « Rouvrir le dernier fermé » : c.txt, fermé après a.txt.
      await tester.longPress(tabLabel('b.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rouvrir le dernier fermé'));
      await tester.pumpAndSettle();
      await h.settleIo(tester, until: () => tabs().length == 2);
      expect(tabs().map((t) => t.name), ['b.txt', 'c.txt']);
    });

    testWidgets(
        '« Tout fermer » : « Annuler » sur un onglet modifié '
        'interrompt la série', (tester) async {
      final paths = [
        for (final n in ['a.txt', 'b.txt', 'c.txt']) write(n, n).path,
      ];
      await openAll(tester, paths);
      tabs()[1].isDirty = true;
      editor.setActiveTabIndex(editor.activeTabIndex);
      await tick(tester);

      await tester.longPress(tabLabel('c.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout fermer'));
      await tester.pumpAndSettle();
      await h.settleIo(tester,
          until: () => find
              .text('Modifications non sauvegardées')
              .evaluate()
              .isNotEmpty);

      expect(tabs().map((t) => t.name), ['b.txt', 'c.txt']);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(tabs().map((t) => t.name), ['b.txt', 'c.txt']);
      expect(tab().name, 'b.txt'); // l'onglet en question est montré
    });
  });

  group('brouillons', () {
    testWidgets(
        'passage en arrière-plan : brouillon, sans toucher au fichier, '
        'proposé à la réouverture', (tester) async {
      final f = write('todo.txt', 'original');
      await h.openEditor(tester, editor, f.path);
      await edit(tester, 'modifié');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      EditorDraft? draft;
      for (var i = 0; i < 100 && draft == null; i++) {
        await h.settleIo(tester);
        await tester
            .runAsync(() async => draft = await EditorDrafts.load(f.path));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(draft!.content, 'modifié');
      expect(f.readAsStringSync(), 'original');

      // Application tuée : nouvel écran, nouvel état, le fichier est rouvert.
      await tester.pumpWidget(const SizedBox());
      editor = UnifiedEditorProvider();
      await h.openEditor(tester, editor, f.path,
          until: () => find.text('Reprendre').evaluate().isNotEmpty);
      await tester.tap(find.text('Reprendre'));
      await tester.pumpAndSettle();
      await h.settleIo(tester, until: () => tab() != null);

      expect(tab().textCtrl.text, 'modifié');
      expect(tab().isDirty, isTrue);
      expect(tab().isReadOnly, isFalse);

      // Sauvegarder supprime le brouillon.
      await save(tester);
      expect(f.readAsStringSync(), 'modifié');
      EditorDraft? after = draft;
      await tester
          .runAsync(() async => after = await EditorDrafts.load(f.path));
      expect(after, isNull);
    });
  });
}
