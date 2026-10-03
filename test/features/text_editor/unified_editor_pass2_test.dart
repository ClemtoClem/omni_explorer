/// Éditeur unifié, refonte passe 2 : recherche / remplacement, palette de
/// commandes, raccourcis et opérations sur les lignes, position du curseur
/// rétablie, numéros de ligne.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import 'package:omni_explorer/core/services/app_state_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';

import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';
import 'package:omni_explorer/features/text_editor/widgets/command_palette.dart';

import '../../helpers/editor_harness.dart' as h;

void main() {
  late Directory sandbox;
  late UnifiedEditorProvider editor;

  setUp(() async {
    h.setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('editor_pass2_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  dynamic tab() => h.activeTab(editor);

  File write(String name, String text) =>
      File(p.join(sandbox.path, name))..writeAsStringSync(text);

  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  /// Passe l'onglet actif en édition et reconstruit l'écran.
  Future<void> editable(WidgetTester tester) async {
    tab().isReadOnly = false;
    editor.setActiveTabIndex(editor.activeTabIndex);
    await tick(tester);
  }

  Future<void> keys(WidgetTester tester, List<LogicalKeyboardKey> combo) async {
    for (final k in combo) {
      await tester.sendKeyDownEvent(k);
    }
    for (final k in combo.reversed) {
      await tester.sendKeyUpEvent(k);
    }
    await tester.pumpAndSettle();
  }

  Finder findField() => find.byKey(const Key('editor-search-find'));

  group('recherche', () {
    testWidgets('compteur, navigation, casse, remplacer tout', (tester) async {
      final f = write('a.txt', 'chat chien chat CHAT');
      await h.openEditor(tester, editor, f.path);
      await editable(tester);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(findField(), 'chat');
      await tick(tester);
      expect(find.text('1/3'), findsOneWidget);
      expect(tab().textCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4));

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tick(tester);
      expect(find.text('2/3'), findsOneWidget);
      expect(tab().textCtrl.selection.start, 11);

      await tester.tap(find.text('Aa'));
      await tick(tester);
      expect(find.textContaining('/2'), findsOneWidget);

      await tester.tap(find.text('Aa')); // casse ignorée de nouveau
      await tick(tester);
      await tester.tap(find.byIcon(Icons.expand_more_rounded)); // remplacer
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('editor-search-replace')), 'cat');
      await tester.tap(find.text('Tout'));
      await tick(tester);

      expect(tab().textCtrl.text, 'cat chien cat cat');
      expect(tab().isDirty, isTrue);
      expect(find.text('3 remplacements'), findsOneWidget);
      expect(find.text('Aucun'), findsOneWidget);
    });

    testWidgets('expression invalide : message, aucun résultat',
        (tester) async {
      final f = write('a.txt', 'x(y)');
      await h.openEditor(tester, editor, f.path);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('.*'));
      await tester.enterText(findField(), '(');
      await tick(tester);
      expect(find.textContaining('Expression invalide'), findsOneWidget);
    });

    testWidgets('code : Ctrl+F ouvre la barre avec le mot sélectionné',
        (tester) async {
      final f = write('main.dart', 'var total = 1;\ntotal++;\n');
      await h.openEditor(tester, editor, f.path);
      await editable(tester);
      tab().codeCtrl.selection = const CodeLineSelection(
          baseIndex: 0, baseOffset: 4, extentIndex: 0, extentOffset: 9);
      await tester.tap(find.byType(CodeEditor));
      tab().codeCtrl.selection = const CodeLineSelection(
          baseIndex: 0, baseOffset: 4, extentIndex: 0, extentOffset: 9);
      await tick(tester);

      await keys(
          tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF]);
      await tick(tester);

      expect(findField(), findsOneWidget);
      expect(tester.widget<TextField>(findField()).controller!.text, 'total');
      expect(find.text('1/2'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('palette et lignes', () {
    testWidgets('Ctrl+Maj+P puis « dupl » : duplique la ligne', (tester) async {
      final f = write('a.txt', 'un\ndeux');
      await h.openEditor(tester, editor, f.path);
      await editable(tester);
      await tester.tap(find.byType(TextField));
      tab().textCtrl.selection = const TextSelection.collapsed(offset: 1);
      await tick(tester);

      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyP,
      ]);
      expect(find.byType(CommandPalette), findsOneWidget);
      await tester.enterText(
          find.descendant(
              of: find.byType(CommandPalette),
              matching: find.byType(TextField)),
          'dupl');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      expect(tab().textCtrl.text, 'un\nun\ndeux');
    });

    testWidgets('raccourcis de lignes en mode texte', (tester) async {
      final f = write('a.txt', 'un\ndeux\ntrois');
      await h.openEditor(tester, editor, f.path);
      await editable(tester);
      await tester.tap(find.byType(TextField));
      tab().textCtrl.selection = const TextSelection.collapsed(offset: 4);
      await tick(tester);

      await keys(
          tester, [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowUp]);
      expect(tab().textCtrl.text, 'deux\nun\ntrois');

      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyK,
      ]);
      expect(tab().textCtrl.text, 'un\ntrois');
    });

    testWidgets('code : Ctrl+/ commente avec la syntaxe du langage',
        (tester) async {
      final f = write('script.py', 'x = 1\n');
      await h.openEditor(tester, editor, f.path);
      await editable(tester);
      await tester.tap(find.byType(CodeEditor));
      // Le toucher place le curseur ; le ramener sur la ligne de code.
      tab().codeCtrl.selection =
          const CodeLineSelection.collapsed(index: 0, offset: 1);
      await tick(tester);

      await keys(
          tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.slash]);
      expect(tab().codeCtrl.text, '# x = 1\n');
      expect(tab().isDirty, isTrue);
      await unmount(tester);
    });

    testWidgets('lecture seule : pas d\'opération de ligne', (tester) async {
      final f = write('a.txt', 'un\ndeux');
      await h.openEditor(tester, editor, f.path);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Dupliquer les lignes'), findsNothing);
      expect(find.text('Nouveau fichier…'), findsOneWidget);
    });
  });

  group('onglets', () {
    testWidgets('le curseur revient où il était à la réouverture',
        (tester) async {
      final f = write('a.txt', 'un\ndeux\ntrois');
      await h.openEditor(tester, editor, f.path);
      tab().textCtrl.selection = const TextSelection.collapsed(offset: 10);
      await tick(tester);
      expect(find.text('Ln 3, Col 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await h.settleIo(tester, until: () => tab() == null);

      await keys(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyT,
      ]);
      await h.settleIo(tester, until: () => tab() != null);
      await tick(tester);

      expect(tab().textCtrl.selection.baseOffset, 10);
      expect(find.text('Ln 3, Col 3'), findsOneWidget);
    });

    testWidgets(
        'ouvrir et fermer un onglet prévient les abonnés du '
        'fournisseur', (tester) async {
      var notified = 0;
      editor.addListener(() => notified++);
      final f = write('a.txt', 'x');
      await h.openEditor(tester, editor, f.path);
      expect(notified, greaterThan(0));

      final before = notified;
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      // Le double appui de l'onglet retient le geste 300 ms.
      await tester.pump(const Duration(milliseconds: 400));
      await h.settleIo(tester, until: () => tab() == null);
      expect(notified, greaterThan(before));
      expect(editor.tabs, isEmpty);
    });
  });

  testWidgets('numéros de ligne en mode code', (tester) async {
    final f = write('main.dart', 'a\nb\n');
    await h.openEditor(tester, editor, f.path);
    expect(find.byType(DefaultCodeLineNumber), findsOneWidget);
    await unmount(tester);
  });

  group('fichiers (via l\'explorateur)', () {
    late Directory home;

    setUp(() async {
      // Sous Linux, la racine de l'explorateur est le dossier personnel :
      // bac à sable dans build/ du projet (ignoré par git).
      final base = Directory(p.join(Directory.current.path, 'build'));
      await base.create(recursive: true);
      home = await base.createTemp('editor_files_test_');
    });
    tearDown(() => home.delete(recursive: true));

    bool shown(String t) => find.text(t).evaluate().isNotEmpty;

    /// Éditeur avec les services dont l'explorateur a besoin.
    Future<void> open(WidgetTester tester, String path) async {
      final settings = SettingsService();
      final appState = AppStateService();
      await tester.runAsync(() async {
        await settings.init();
        await appState.init();
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: editor),
          ],
          child: MaterialApp(home: UnifiedEditorScreen(filePaths: [path])),
        ));
      });
      await h.settleIo(tester, until: () => tab() != null);
    }

    /// Choisit [action] dans le menu ⋮, puis saisit [name] dans
    /// l'explorateur ouvert en mode « enregistrer ».
    Future<void> pickSave(
        WidgetTester tester, String action, String name) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await h.settleIo(tester,
          until: () => find.byTooltip('Annuler').evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.text('Enregistrer'));
      await h.settleIo(tester, until: () => tab()?.name == name);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets(
        'enregistrer sous : nouveau fichier dans l\'onglet, '
        'original intact', (tester) async {
      final a = File(p.join(home.path, 'a.txt'))..writeAsStringSync('original');
      await open(tester, a.path);
      tab().isReadOnly = false;
      tab().textCtrl.text = 'modifié';
      tab().isDirty = true;
      editor.setActiveTabIndex(0);
      await tick(tester);

      await pickSave(tester, 'Enregistrer sous…', 'b.txt');

      expect(shown('Enregistré sous b.txt'), isTrue);
      expect(File(p.join(home.path, 'b.txt')).readAsStringSync(), 'modifié');
      expect(a.readAsStringSync(), 'original');
      expect(editor.tabs.map((t) => t.name), ['b.txt']);
      expect(tab().isDirty, isFalse);
      expect(tab().isReadOnly, isFalse);
    });

    testWidgets('nouveau fichier : créé vide et ouvert en édition',
        (tester) async {
      final a = File(p.join(home.path, 'a.txt'))..writeAsStringSync('x');
      await open(tester, a.path);

      await pickSave(tester, 'Nouveau fichier…', 'neuf.dart');

      final created = File(p.join(home.path, 'neuf.dart'));
      expect(created.existsSync(), isTrue);
      expect(created.readAsStringSync(), '');
      expect(editor.tabs.map((t) => t.name), ['a.txt', 'neuf.dart']);
      expect(tab().isReadOnly, isFalse);
      await unmount(tester);
    });
  });
}
