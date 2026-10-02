/// Écran de la corbeille sur la corbeille du système (bac à sable).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:omni_explorer/core/services/trash_service.dart';
import 'package:omni_explorer/core/services/xdg_trash.dart';
import 'package:omni_explorer/features/file_explorer/screens/trash_screen.dart';

import '../../helpers/editor_harness.dart' show settleIo, setUpEditorTest;

void main() {
  late Directory sandbox;
  late String home, homeTrash;
  late TrashService trash;

  setUp(() async {
    setUpEditorTest();
    sandbox = await Directory.systemTemp.createTemp('trash_screen_test_');
    home = p.join(sandbox.path, 'home');
    homeTrash = p.join(home, '.local', 'share', 'Trash');
    trash = TrashService();
  });
  tearDown(() async {
    await trash.init(directory: p.join(sandbox.path, 'app_trash'));
    await sandbox.delete(recursive: true);
  });

  File write(String path, [String text = 'x']) {
    File(path).parent.createSync(recursive: true);
    return File(path)..writeAsStringSync(text);
  }

  bool shown(String t) => find.text(t).evaluate().isNotEmpty;

  testWidgets('liste, restaure et vide la corbeille du système',
      (tester) async {
    final doc = p.join(home, 'Documents', 'rapport.pdf');
    await tester.runAsync(() async {
      await trash.init(
          systemTrash: XdgTrash(
              homeTrash: homeTrash, uid: 1000, mountPoints: () => ['/']));
      await trash.moveToTrash(write(doc).path);
      // Mis à la corbeille par le gestionnaire de fichiers du bureau.
      write(p.join(homeTrash, 'files', 'photo.jpg'));
      write(
          p.join(homeTrash, 'info', 'photo.jpg.trashinfo'),
          '[Trash Info]\nPath=${p.join(home, 'Images', 'photo.jpg')}\n'
          'DeletionDate=2026-10-01T08:00:00\n');
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: trash,
        child: const MaterialApp(home: TrashScreen()),
      ));
    });
    await settleIo(tester, until: () => shown('photo.jpg'));

    expect(find.text('rapport.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.textContaining('Corbeille du système'), findsOneWidget);

    // Restaurer le PDF.
    await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, 'rapport.pdf'),
        matching: find.byTooltip('Restaurer')));
    await settleIo(tester, until: () => !shown('rapport.pdf'));
    expect(File(doc).existsSync(), isTrue);

    // Vider.
    await tester.tap(find.text('Vider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vider').last);
    await settleIo(tester, until: () => shown('Corbeille vide'));
    expect(Directory(p.join(homeTrash, 'files')).listSync(), isEmpty);
  });
}
