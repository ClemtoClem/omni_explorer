/// Écran d'archive : navigation par dossier, sélection, opérations.

import 'dart:io';

import 'package:archive/archive.dart' as arc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/archive/screens/archive_screen.dart';
import 'package:omni_explorer/features/archive/services/archive_document.dart';

import '../../helpers/editor_harness.dart' show settleIo, setUpEditorTest;

void main() {
  late Directory sandbox;

  setUp(() async {
    setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('archive_screen_test_');
  });
  tearDown(() => sandbox.delete(recursive: true));

  /// ZIP sans aucune entrée « dossier » (cas qui cassait l'ancien écran).
  String makeZip({String? password}) {
    final a = arc.Archive()
      ..addFile(arc.ArchiveFile.string('a/b/c.txt', 'c'))
      ..addFile(arc.ArchiveFile.string('a/d.txt', 'd'))
      ..addFile(arc.ArchiveFile.string('e.txt', 'e'));
    final path = p.join(sandbox.path, 'test.zip');
    File(path)
        .writeAsBytesSync(arc.ZipEncoder(password: password).encodeBytes(a));
    return path;
  }

  Finder text(String t) => find.text(t);
  bool shown(String t) => text(t).evaluate().isNotEmpty;

  /// Plus d'opération en cours (enregistrement de l'archive terminé).
  bool idle() => find.byType(LinearProgressIndicator).evaluate().isEmpty;

  Future<void> open(WidgetTester tester, String path,
      {required String waitFor}) async {
    await tester
        .pumpWidget(MaterialApp(home: ArchiveScreen(archivePath: path)));
    await settleIo(tester, until: () => shown(waitFor));
  }

  testWidgets('navigation dans les dossiers implicites, fil d\'Ariane, retour',
      (tester) async {
    await open(tester, makeZip(), waitFor: 'e.txt');
    expect(text('a'), findsOneWidget);

    await tester.tap(text('a'));
    await tester.pumpAndSettle();
    expect(text('d.txt'), findsOneWidget);
    expect(text('b'), findsOneWidget);
    expect(text('e.txt'), findsNothing);

    await tester.tap(text('b'));
    await tester.pumpAndSettle();
    expect(text('c.txt'), findsOneWidget);

    // Retour arrière : remonte d'un dossier, pas de sortie de l'écran.
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(text('d.txt'), findsOneWidget);

    // Fil d'Ariane : retour à la racine.
    await tester.tap(find.byIcon(Icons.archive_rounded));
    await tester.pumpAndSettle();
    expect(text('e.txt'), findsOneWidget);
  });

  testWidgets('dupliquer puis supprimer une sélection (enregistré sur disque)',
      (tester) async {
    final zip = makeZip();
    await open(tester, zip, waitFor: 'e.txt');

    await tester.longPress(text('e.txt'));
    await tester.pumpAndSettle();
    await tester.tap(text('Dupliquer'));
    await settleIo(tester, until: () => shown('e.copy.1.txt') && idle());
    expect(text('e.copy.1.txt'), findsOneWidget);

    await tester.longPress(text('e.txt'));
    await tester.pumpAndSettle();
    await tester.tap(text('Supprimer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await settleIo(tester, until: () => !shown('e.txt') && idle());

    late ArchiveDocument doc;
    await tester.runAsync(() async => doc = await ArchiveDocument.open(zip));
    expect(doc.exists('e.txt'), isFalse);
    expect(String.fromCharCodes(doc.readFile('e.copy.1.txt')), 'e');
  });

  testWidgets('recherche dans toute l\'archive', (tester) async {
    await open(tester, makeZip(), waitFor: 'e.txt');
    await tester.tap(find.byTooltip('Rechercher'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'c.tx');
    await tester.pumpAndSettle();
    expect(text('c.txt'), findsOneWidget);
    expect(text('a/b/c.txt'), findsOneWidget); // chemin complet affiché
  });

  testWidgets(
      'format en lecture seule : bandeau, pas d\'action de modification',
      (tester) async {
    final a = arc.Archive()..addFile(arc.ArchiveFile.string('x.txt', 'x'));
    final txz = p.join(sandbox.path, 'r.tar.xz');
    File(txz).writeAsBytesSync(
        arc.XZEncoder().encodeBytes(arc.TarEncoder().encodeBytes(a)));
    await open(tester, txz, waitFor: 'x.txt');

    expect(find.textContaining('Lecture seule'), findsOneWidget);
    await tester.longPress(text('x.txt'));
    await tester.pumpAndSettle();
    expect(text('Extraire'), findsOneWidget);
    expect(text('Dupliquer'), findsNothing);
  });

  testWidgets('ZIP chiffré : mot de passe demandé, mauvais refusé',
      (tester) async {
    await open(tester, makeZip(password: 'secret'),
        waitFor: 'Cette archive est protégée par un mot de passe.');

    await tester.enterText(find.byKey(const Key('archive-password')), 'faux');
    await tester.tap(text('Ouvrir'));
    await settleIo(tester, until: () => shown('Mot de passe incorrect.'));
    expect(text('Mot de passe incorrect.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('archive-password')), 'secret');
    await tester.tap(text('Ouvrir'));
    await settleIo(tester, until: () => shown('e.txt'));
    expect(text('a'), findsOneWidget);
  });
}
