import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_explorer/core/services/file_operations_service.dart';
import 'package:omni_explorer/core/widgets/file_op_dialogs.dart';

void main() {
  /// Application minimale : un bouton qui exécute [onPressed].
  Widget host(void Function(BuildContext) onPressed) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => onPressed(ctx),
              child: const Text('go'),
            ),
          ),
        ),
      );

  group('showRenameDialog', () {
    testWidgets('affiche le refus du service sans fermer le dialogue',
        (tester) async {
      await tester.pumpWidget(host((ctx) => showRenameDialog(ctx,
          currentName: 'a.txt',
          onSubmit: (_) async => throw const FileOpException(
              'Un élément « b.txt » existe déjà.'))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'b.txt');
      await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
      await tester.pumpAndSettle();

      expect(find.text('Un élément « b.txt » existe déjà.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('refuse un nom invalide avant tout appel', (tester) async {
      var called = false;
      await tester.pumpWidget(host((ctx) => showRenameDialog(ctx,
          currentName: 'a.txt', onSubmit: (_) async => called = true)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '../a.txt');
      await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.textContaining('« / »'), findsOneWidget);
    });

    testWidgets('renomme puis ferme', (tester) async {
      String? received;
      await tester.pumpWidget(host((ctx) => showRenameDialog(ctx,
          currentName: 'a.txt', onSubmit: (n) async => received = n)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'b.txt');
      await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
      await tester.pumpAndSettle();

      expect(received, 'b.txt');
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('askingConflictResolver', () {
    testWidgets('renvoie le choix, puis l\'applique aux suivants',
        (tester) async {
      late ConflictResolver resolver;
      await tester
          .pumpWidget(host((ctx) => resolver = askingConflictResolver(ctx)));
      await tester.tap(find.text('go'));
      await tester.pump();

      final first = resolver('/a/f.txt', '/b/f.txt');
      await tester.pumpAndSettle();
      expect(find.textContaining('« f.txt » existe déjà'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      expect(await first, ConflictAction.replace);

      // « Appliquer aux suivants » : plus de dialogue.
      final second = resolver('/a/g.txt', '/b/g.txt');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(await second, ConflictAction.replace);
    });

    testWidgets('« Ignorer » sans case cochée : redemande ensuite',
        (tester) async {
      late ConflictResolver resolver;
      await tester
          .pumpWidget(host((ctx) => resolver = askingConflictResolver(ctx)));
      await tester.tap(find.text('go'));
      await tester.pump();

      final first = resolver('/a/f.txt', '/b/f.txt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignorer'));
      await tester.pumpAndSettle();
      expect(await first, ConflictAction.skip);

      resolver('/a/g.txt', '/b/g.txt');
      await tester.pumpAndSettle();
      expect(find.textContaining('« g.txt » existe déjà'), findsOneWidget);
    });
  });
}
