/// Pied de page du presse-papiers de l'explorateur : copier ou déplacer la
/// sélection, puis valider dans le dossier courant.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:omni_explorer/core/services/app_state_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/core/services/trash_service.dart';
import 'package:omni_explorer/features/file_explorer/screens/file_explorer_screen.dart';

import '../../helpers/editor_harness.dart' show settleIo, setUpEditorTest;

void main() {
  late Directory sandbox;

  setUp(() async {
    setUpEditorTest();
    // Sous Linux, la racine de l'explorateur est le dossier personnel : le
    // bac à sable doit s'y trouver (build/ du projet, ignoré par git).
    final base = Directory(p.join(Directory.current.path, 'build'));
    await base.create(recursive: true);
    sandbox = await base.createTemp('explorer_paste_bar_test_');
    await Directory(p.join(sandbox.path, 'clips')).create();
    File(p.join(sandbox.path, 'notes.txt')).writeAsStringSync('n');
  });
  tearDown(() => sandbox.delete(recursive: true));

  bool shown(String t) => find.text(t).evaluate().isNotEmpty;

  Future<void> open(WidgetTester tester) async {
    final settings = SettingsService();
    final appState = AppStateService();
    await tester.runAsync(() async {
      await settings.init();
      await appState.init();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: TrashService()),
        ],
        child: MaterialApp(home: FileExplorerScreen(initialPath: sandbox.path)),
      ));
    });
    await settleIo(tester, until: () => shown('notes.txt'));
  }

  /// Sélectionne [name] (appui long) puis choisit [action] dans la barre de
  /// sélection.
  Future<void> selectThen(
      WidgetTester tester, String name, String action) async {
    await tester.longPress(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('copier : pied de page, changer de dossier, « Copier ici »',
      (tester) async {
    await open(tester);
    await selectThen(tester, 'notes.txt', 'Copier');

    expect(find.text('Copier notes.txt'), findsOneWidget);
    expect(find.text('Copier ici'), findsOneWidget);

    await tester.tap(find.text('clips'));
    await settleIo(tester, until: () => shown('vers « clips »'));

    await tester.tap(find.text('Copier ici'));
    await settleIo(tester, until: () => !shown('Copier ici'));

    expect(
        File(p.join(sandbox.path, 'clips', 'notes.txt')).existsSync(), isTrue);
    expect(File(p.join(sandbox.path, 'notes.txt')).existsSync(), isTrue);
    expect(find.text('Copier notes.txt'), findsNothing); // pied de page fermé
  });

  testWidgets('déplacer : bloqué dans le dossier d\'origine, puis validé',
      (tester) async {
    await open(tester);
    await selectThen(tester, 'notes.txt', 'Déplacer');

    expect(find.text('Déplacer notes.txt'), findsOneWidget);
    expect(find.text('Déjà dans ce dossier'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Déplacer ici');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.text('clips'));
    await settleIo(tester, until: () => shown('vers « clips »'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await settleIo(tester, until: () => !shown('Déplacer ici'));

    expect(
        File(p.join(sandbox.path, 'clips', 'notes.txt')).existsSync(), isTrue);
    expect(File(p.join(sandbox.path, 'notes.txt')).existsSync(), isFalse);
  });

  testWidgets('« Annuler » vide le presse-papiers', (tester) async {
    await open(tester);
    await selectThen(tester, 'clips', 'Copier');
    await tester.tap(find.text('clips'));
    await settleIo(tester, until: () => shown('vers « clips »'));
    expect(find.text('Un dossier ne peut pas aller dans lui-même'),
        findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Copier clips'), findsNothing);
  });
}
