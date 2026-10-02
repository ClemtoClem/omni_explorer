/// Page Stockage : ajout (répertoire choisi dans l'explorateur), modification
/// de l'icône, retrait annulable des raccourcis de répertoire.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/app/constants/app_constants.dart';
import 'package:omni_explorer/core/models/file_filter.dart';
import 'package:omni_explorer/core/services/app_state_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/core/services/trash_service.dart';
import 'package:omni_explorer/features/file_explorer/screens/storage_screen.dart';
import 'package:omni_explorer/features/file_explorer/widgets/path_bar.dart';

import '../../helpers/editor_harness.dart' show settleIo, setUpEditorTest;

void main() {
  late Directory sandbox;
  late SettingsService settings;

  setUp(() async {
    setUpEditorTest();
    // Racine de l'explorateur sous Linux : le dossier personnel.
    final base = Directory(p.join(Directory.current.path, 'build'));
    await base.create(recursive: true);
    sandbox = await base.createTemp('storage_home_test_');
    await Directory(p.join(sandbox.path, 'Projets')).create();
    await Directory(p.join(sandbox.path, 'Musique')).create();
    SharedPreferences.setMockInitialValues({
      // Défauts déjà proposés : la page ne dépend pas du poste de test.
      AppConstants.prefShortcutsSeeded: true,
      AppConstants.prefShortcuts: jsonEncode([
        {'id': 'p', 'name': 'Projets', 'path': p.join(sandbox.path, 'Projets')},
      ]),
    });
  });
  tearDown(() => sandbox.delete(recursive: true));

  bool shown(String t) => find.text(t).evaluate().isNotEmpty;

  Future<void> open(WidgetTester tester) async {
    settings = SettingsService();
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
        child: const MaterialApp(home: StorageScreen()),
      ));
    });
    // Page chargée (la liste des raccourcis peut être sous les cartes des
    // supports, donc pas encore construite).
    await settleIo(tester, until: () => shown('Explorer'));
  }

  /// L'explorateur affiche le contenu chargé du dossier [name] du bac à sable.
  bool explorerAt(WidgetTester tester, String name) {
    final bar = find.byType(PathBar);
    return bar.evaluate().isNotEmpty &&
        tester.widget<PathBar>(bar).currentPath == p.join(sandbox.path, name) &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty;
  }

  /// Amène [f] à l'écran : construit (zone de cache) ne suffit pas pour
  /// le toucher.
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  testWidgets('modifier l\'icône et le nom d\'un raccourci', (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('Projets'));
    await tester.longPress(find.text('Projets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    expect(find.text('Modifier le raccourci'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.enterText(
        find.widgetWithText(TextField, 'Nom'), 'Code source');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final s = settings.shortcuts.single;
    expect((s.id, s.name, s.iconName), ('p', 'Code source', 'code'));
    expect(find.text('Code source'), findsOneWidget);
  });

  testWidgets('retirer un raccourci, puis annuler', (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('Projets'));
    await tester.longPress(find.text('Projets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer'));
    await tester.pumpAndSettle();
    expect(settings.shortcuts, isEmpty);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(settings.shortcuts.single.path, p.join(sandbox.path, 'Projets'));
  });

  testWidgets('changer le répertoire via l\'explorateur', (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('Projets'));
    await tester.longPress(find.text('Projets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    // L'explorateur s'ouvre sur le répertoire actuel du raccourci.
    await tester.tap(find.byKey(const ValueKey('shortcut-path')));
    await settleIo(tester, until: () => explorerAt(tester, 'Projets'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Répertoire parent'));
    await settleIo(tester, until: () => shown('Musique'));
    await tester.tap(find.text('Musique'));
    await settleIo(tester, until: () => explorerAt(tester, 'Musique'));
    await tester.tap(find.text('Choisir ce dossier'));
    await settleIo(tester, until: () => shown(p.join(sandbox.path, 'Musique')));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(settings.shortcuts.single.path, p.join(sandbox.path, 'Musique'));
  });

  testWidgets('ajouter : nom et répertoire obligatoires', (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('Ajouter'));
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau raccourci'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await tester.pump();
    expect(find.text('Donnez un nom au raccourci'), findsOneWidget);
    expect(find.text('Choisissez un répertoire'), findsOneWidget);
    expect(settings.shortcuts, hasLength(1));
  });

  testWidgets('bouton « Fichiers récents »', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Fichiers récents'));
    await tester.pumpAndSettle();
    expect(find.text('Fichiers récents'), findsOneWidget);
    expect(find.text('Aucun fichier récent'), findsOneWidget);
  });

  testWidgets('configurer les filtres de recherche d\'un raccourci',
      (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('Projets'));
    await tester.longPress(find.text('Projets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    // Le dialogue défile : chaque champ est amené à l'écran avant usage.
    Future<void> visible(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    await visible(find.text('Filtres de recherche'));
    await tester.tap(find.text('Filtres de recherche'));
    await tester.pumpAndSettle();
    await visible(find.byKey(const ValueKey('filter-query')));
    await tester.enterText(
        find.byKey(const ValueKey('filter-query')), 'rapport');
    await visible(find.byKey(const ValueKey('filter-extensions')));
    await tester.enterText(
        find.byKey(const ValueKey('filter-extensions')), '.PDF, odt');
    await visible(find.widgetWithText(FilterChip, 'PDF'));
    await tester.tap(find.widgetWithText(FilterChip, 'PDF'));
    await visible(find.byKey(const ValueKey('filter-recursive')));
    await tester.tap(find.byKey(const ValueKey('filter-recursive')));
    await tester.pumpAndSettle();
    // Le résumé de la section reflète la saisie.
    expect(find.text('« rapport » · PDF · .pdf .odt · sous-dossiers'),
        findsOneWidget);

    await visible(find.text('Enregistrer'));
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
        settings.shortcuts.single.filter,
        const FileFilter(
          query: 'rapport',
          categories: {FileCategory.pdf},
          extensions: {'pdf', 'odt'},
          recursive: true,
        ));
  });

  testWidgets('un raccourci filtré ouvre l\'explorateur sur sa recherche',
      (tester) async {
    File(p.join(sandbox.path, 'Projets', 'a', 'b', 'devis.pdf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    File(p.join(sandbox.path, 'Projets', 'notes.txt')).writeAsStringSync('n');
    await open(tester);
    await tester.runAsync(() => settings.updateShortcut(
        settings.shortcuts.single.copyWith(
            filter: const FileFilter(extensions: {'pdf'}, recursive: true))));
    await tester.pump();

    await scrollTo(tester, find.text('Projets'));
    await tester.tap(find.text('Projets'));
    await settleIo(tester, until: () => shown('devis.pdf'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('devis.pdf'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(find.textContaining('a/b'), findsOneWidget); // emplacement
    final chip = tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, 'Sous-dossiers'));
    expect(chip.selected, isTrue);
  });
}
