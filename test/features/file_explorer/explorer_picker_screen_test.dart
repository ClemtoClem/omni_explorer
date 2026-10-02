/// Sélecteur de l'explorateur, piloté par l'interface : fichier unique,
/// fichiers multiples, dossier, enregistrement avec remplacement confirmé.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/services/app_state_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/file_explorer/explorer_picker.dart';

import '../../helpers/editor_harness.dart' show settleIo, setUpEditorTest;

void main() {
  late Directory sandbox;

  setUp(() async {
    setUpEditorTest();
    // Sous Linux, la racine de l'explorateur est le dossier personnel : le
    // bac à sable doit s'y trouver (build/ du projet, ignoré par git).
    final base = Directory(p.join(Directory.current.path, 'build'));
    await base.create(recursive: true);
    sandbox = await base.createTemp('explorer_picker_screen_test_');
    await Directory(p.join(sandbox.path, 'clips')).create();
    File(p.join(sandbox.path, 'clips', 'a.mp4')).writeAsStringSync('a');
    File(p.join(sandbox.path, 'clips', 'b.mp4')).writeAsStringSync('b');
    File(p.join(sandbox.path, 'notes.txt')).writeAsStringSync('n');
  });
  tearDown(() => sandbox.delete(recursive: true));

  /// Ouvre une page dont le bouton lance [pick] ; le résultat est rangé
  /// dans [result] quand le sélecteur se ferme.
  Future<void> launch(
    WidgetTester tester,
    Future<Object?> Function(BuildContext) pick,
    void Function(Object?) result,
  ) async {
    final settings = SettingsService();
    final appState = AppStateService();
    await tester.runAsync(() async {
      await settings.init();
      await appState.init();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async => result(await pick(ctx)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
    });
    await tester.tap(find.text('go'));
    await settleIo(tester,
        until: () => find.byTooltip('Annuler').evaluate().isNotEmpty);
    // Termine l'animation d'ouverture (settleIo n'avance pas l'horloge).
    await tester.pump(const Duration(seconds: 1));
  }

  bool shown(String t) => find.text(t).evaluate().isNotEmpty;

  Future<void> tapAndSettle(WidgetTester tester, Finder f,
      {required bool Function() until}) async {
    await tester.tap(f);
    await settleIo(tester, until: until);
  }

  testWidgets('fichier unique : seuls les fichiers acceptés sont proposés',
      (tester) async {
    Object? picked = 'pending';
    await launch(
      tester,
      (ctx) => ExplorerPicker.pickFile(ctx,
          title: 'Vidéo à éditer',
          categories: {FileCategory.video},
          initialPath: sandbox.path),
      (r) => picked = r,
    );
    await settleIo(tester, until: () => shown('clips'));
    expect(find.text('Vidéo à éditer'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);

    await tapAndSettle(tester, find.text('clips'), until: () => shown('a.mp4'));
    await tapAndSettle(tester, find.text('a.mp4'), until: () => shown('go'));
    expect(picked, p.join(sandbox.path, 'clips', 'a.mp4'));
  });

  testWidgets('fichiers multiples : sélection puis « Valider »',
      (tester) async {
    Object? picked;
    await launch(
      tester,
      (ctx) => ExplorerPicker.pickFiles(ctx,
          initialPath: p.join(sandbox.path, 'clips')),
      (r) => picked = r,
    );
    await settleIo(tester, until: () => shown('b.mp4'));
    await tester.tap(find.text('a.mp4'));
    await tester.pump();
    await tester.tap(find.text('b.mp4'));
    await tester.pump();
    expect(find.text('2 fichier(s) sélectionné(s)'), findsOneWidget);

    await tapAndSettle(tester, find.text('Valider'), until: () => shown('go'));
    expect(
        picked,
        unorderedEquals([
          p.join(sandbox.path, 'clips', 'a.mp4'),
          p.join(sandbox.path, 'clips', 'b.mp4'),
        ]));
  });

  testWidgets('dossier : fichiers masqués, « Choisir ce dossier »',
      (tester) async {
    Object? picked;
    await launch(
      tester,
      (ctx) => ExplorerPicker.pickDirectory(ctx, initialPath: sandbox.path),
      (r) => picked = r,
    );
    await settleIo(tester, until: () => shown('clips'));
    expect(find.text('notes.txt'), findsNothing);

    await tapAndSettle(tester, find.text('clips'),
        until: () => shown('Répertoire vide'));
    await tapAndSettle(tester, find.text('Choisir ce dossier'),
        until: () => shown('go'));
    expect(picked, p.join(sandbox.path, 'clips'));
  });

  testWidgets('annuler renvoie null', (tester) async {
    Object? picked = 'pending';
    await launch(
      tester,
      (ctx) => ExplorerPicker.pickDirectory(ctx, initialPath: sandbox.path),
      (r) => picked = r,
    );
    await settleIo(tester, until: () => shown('clips'));
    await tapAndSettle(tester, find.byTooltip('Annuler'),
        until: () => shown('go'));
    expect(picked, isNull);
  });

  testWidgets('enregistrer : remplacer un fichier existant est confirmé',
      (tester) async {
    Object? picked;
    await launch(
      tester,
      (ctx) => ExplorerPicker.saveFile(ctx,
          fileName: 'export.txt', initialPath: sandbox.path),
      (r) => picked = r,
    );
    await settleIo(tester, until: () => shown('notes.txt'));

    // Toucher un fichier reprend son nom ; il existe : confirmation.
    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Remplacer le fichier ?'), findsOneWidget);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(picked, isNull);

    await tester.enterText(find.byType(TextField), 'neuf.txt');
    await tapAndSettle(tester, find.text('Enregistrer'),
        until: () => shown('go'));
    expect(picked, p.join(sandbox.path, 'neuf.txt'));
  });
}
