/// Sauvegarde depuis l'éditeur unifié : atomique, sans casser les liens
/// symboliques ni les permissions du fichier.

import 'dart:io';

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
    sandbox = await Directory.systemTemp.createTemp('editor_save_test_');
    editor = UnifiedEditorProvider();
  });

  tearDown(() => sandbox.delete(recursive: true));

  /// Modifie le texte de l'onglet actif puis clique sur « Sauvegarder ».
  Future<void> editAndSave(WidgetTester tester, String text) async {
    final tab = h.activeTab(editor);
    tab.isReadOnly = false;
    tab.textCtrl.text = text;
    tab.isDirty = true;
    // Comme une saisie : l'écran se reconstruit et active « Sauvegarder ».
    editor.setActiveTabIndex(editor.activeTabIndex);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_rounded));
    await tester.pump();
    await h.settleIo(tester, until: () => h.activeTab(editor).isDirty == false);
  }

  testWidgets('sauvegarde le texte sans laisser de temporaire', (tester) async {
    final f = File(p.join(sandbox.path, 'note.txt'))
      ..writeAsStringSync('ancien');
    await h.openEditor(tester, editor, f.path);

    await editAndSave(tester, 'nouveau contenu');

    expect(f.readAsStringSync(), 'nouveau contenu');
    expect(sandbox.listSync().map((e) => p.basename(e.path)), ['note.txt']);
    expect(h.activeTab(editor).isDirty, isFalse);
  });

  testWidgets('un fichier ouvert via un lien reste un lien après sauvegarde',
      (tester) async {
    final target = File(p.join(sandbox.path, 'real.txt'))
      ..writeAsStringSync('ancien');
    final link = Link(p.join(sandbox.path, 'alias.txt'))
      ..createSync(target.path);
    await h.openEditor(tester, editor, link.path);

    await editAndSave(tester, 'nouveau');

    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(target.readAsStringSync(), 'nouveau');
  }, skip: Platform.isWindows);

  testWidgets('un fichier exécutable garde ses permissions', (tester) async {
    final f = File(p.join(sandbox.path, 'run.txt'))
      ..writeAsStringSync('ancien');
    await tester.runAsync(() => Process.run('chmod', ['755', f.path]));
    await h.openEditor(tester, editor, f.path);

    await editAndSave(tester, 'nouveau');

    expect(f.readAsStringSync(), 'nouveau');
    expect((f.statSync().mode & 0xFFF).toRadixString(8), '755');
  }, skip: Platform.isWindows);
}
