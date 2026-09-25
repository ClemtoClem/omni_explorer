/// Ouverture dans l'éditeur unifié : un fichier binaire ou trop volumineux
/// ne doit jamais être chargé en entier comme texte.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';
import 'package:omni_explorer/features/text_editor/services/editor_open_policy.dart';

import '../../helpers/editor_harness.dart' as h;

void main() {
  late Directory sandbox;
  late UnifiedEditorProvider editor;

  setUp(() async {
    h.setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('editor_open_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  dynamic tab() => h.activeTab(editor);
  bool dialogShown() => find.text('Fichier volumineux').evaluate().isNotEmpty;

  /// Écrit [size] octets de texte en lignes de 80 caractères, sans passer
  /// par une chaîne géante.
  Future<File> writeText(WidgetTester tester, String name, int size) async {
    final f = File(p.join(sandbox.path, name));
    await tester.runAsync(() async {
      final raf = await f.open(mode: FileMode.write);
      final chunk = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 0x61);
      for (var i = 79; i < chunk.length; i += 80) {
        chunk[i] = 0x0A; // fin de ligne
      }
      var left = size;
      while (left > 0) {
        final n = left < chunk.length ? left : chunk.length;
        await raf.writeFrom(chunk, 0, n);
        left -= n;
      }
      await raf.close();
    });
    return f;
  }

  testWidgets('un fichier binaire s\'ouvre en hexadécimal', (tester) async {
    final f = File(p.join(sandbox.path, 'data.txt'))
      ..writeAsBytesSync([0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01, 0x02]);
    await h.openEditor(tester, editor, f.path);

    expect(tab().viewMode, EditorViewMode.hex);
    expect(find.text('OFFSET'), findsOneWidget);
    expect(find.textContaining('Contenu binaire'), findsOneWidget);
  });

  testWidgets('un .docx (archive ZIP) s\'ouvre en hexadécimal, pas en texte',
      (tester) async {
    final zip = arc.Archive()
      ..addFile(arc.ArchiveFile('word/document.xml', 3, 'abc'.codeUnits));
    final f = File(p.join(sandbox.path, 'rapport.docx'))
      ..writeAsBytesSync(arc.ZipEncoder().encode(zip)!);
    await h.openEditor(tester, editor, f.path);

    expect(tab().viewMode, EditorViewMode.hex);
  });

  testWidgets('au-delà de 10 Mio : dialogue, « Annuler » n\'ouvre rien',
      (tester) async {
    final f =
        await writeText(tester, 'huge.log', EditorLimits.textMaxBytes + 1024);
    await h.openEditor(tester, editor, f.path, until: dialogShown);

    expect(find.text('Fichier volumineux'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await h.settleIo(tester);

    expect(tab(), isNull);
  });

  testWidgets('au-delà de 10 Mio : « Hexadécimal » ouvre l\'aperçu',
      (tester) async {
    final f =
        await writeText(tester, 'huge.log', EditorLimits.textMaxBytes + 1024);
    await h.openEditor(tester, editor, f.path, until: dialogShown);

    await tester.tap(find.text('Hexadécimal'));
    await h.settleIo(tester, until: () => tab() != null);

    expect(tab().viewMode, EditorViewMode.hex);
    expect(tab().textCtrl, isNull); // jamais chargé comme texte
  });

  testWidgets('code au-delà de 2 Mio : texte brut, sans coloration',
      (tester) async {
    final f = await writeText(
        tester, 'bundle.js', EditorLimits.highlightMaxBytes + 1024);
    await h.openEditor(tester, editor, f.path);

    expect(tab().viewMode, EditorViewMode.text);
    expect(tab().codeCtrl, isNull);
    expect(find.textContaining('sans coloration'), findsOneWidget);

    // Repasser en « Code » est refusé. Le message d'ouverture doit d'abord
    // expirer : les SnackBar s'affichent l'une après l'autre.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final refusal = find.textContaining('trop volumineux pour la coloration');
    await h.switchMode(tester, 'Code',
        until: () => refusal.evaluate().isNotEmpty);
    expect(tab().viewMode, EditorViewMode.text);
    expect(refusal, findsOneWidget);
  });

  testWidgets('fichier minifié (une ligne de 100 Kio) : dialogue',
      (tester) async {
    final f = File(p.join(sandbox.path, 'app.min.js'))
      ..writeAsStringSync('var a=1;' * (100 * 1024 ~/ 8));
    await h.openEditor(tester, editor, f.path, until: dialogShown);

    expect(
        find.textContaining('contient une ligne de plus de'), findsOneWidget);
    await tester.tap(find.text('Hexadécimal'));
    await h.settleIo(tester, until: () => tab() != null);
    expect(tab().viewMode, EditorViewMode.hex);
  });

  testWidgets('hex → texte refusé au-delà de 10 Mio', (tester) async {
    final f =
        await writeText(tester, 'huge.log', EditorLimits.textMaxBytes + 1024);
    await h.openEditor(tester, editor, f.path, until: dialogShown);
    await tester.tap(find.text('Hexadécimal'));
    await h.settleIo(tester, until: () => tab() != null);

    await h.switchMode(tester, 'Texte');

    expect(tab().viewMode, EditorViewMode.hex);
    expect(find.textContaining('trop volumineux pour l\'affichage en texte'),
        findsOneWidget);
  });
}
