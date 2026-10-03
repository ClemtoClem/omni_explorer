/// Outils communs aux tests de widget de l'éditeur unifié, qui lit et écrit
/// de vrais fichiers.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';
import 'package:omni_explorer/features/text_editor/services/editor_drafts.dart';

/// Prépare un test : pas de téléchargement de polices, préférences simulées.
void setUpEditorTest() {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  // Pas de trousseau système en test : stockage sécurisé simulé.
  FlutterSecureStorage.setMockInitialValues({});
  // Brouillons dans un dossier jetable (pas de path_provider en test).
  final drafts = Directory.systemTemp.createTempSync('editor_drafts_');
  EditorDrafts.directory = () async => drafts;
  addTearDown(() => drafts.delete(recursive: true));
}

/// Laisse aboutir les entrées/sorties réelles déclenchées depuis la zone de
/// temps simulé du test : chaque étape (open, length, read…) a besoin d'un
/// tour de boucle réel puis d'un `pump` pour livrer son résultat.
///
/// Avec [until], on attend que la condition soit vraie (jusqu'à [timeout]) :
/// une durée fixe dépendrait de la charge de la machine (tests en parallèle,
/// CI). Sans condition, on laisse passer un nombre fixe de tours.
Future<void> settleIo(
  WidgetTester tester, {
  bool Function()? until,
  // Plafond seulement : l'attente s'arrête dès que [until] est vrai. Sous
  // forte charge (suites lancées en parallèle), 10 s ne suffisaient pas.
  Duration timeout = const Duration(seconds: 30),
}) async {
  const step = Duration(milliseconds: 20);
  final maxRounds = until == null ? 20 : timeout.inMilliseconds ~/ 20;
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
    if (until != null && until()) {
      // Quelques tours de plus pour les étapes qui suivent la condition.
      for (var j = 0; j < 5; j++) {
        await tester.runAsync(() => Future<void>.delayed(step));
        await tester.pump();
      }
      return;
    }
  }
}

/// Ouvre [path] dans l'éditeur et attend la fin de la lecture disque : par
/// défaut, qu'un onglet soit actif ; sinon, que [until] soit vrai (ex. un
/// dialogue affiché).
Future<void> openEditor(
  WidgetTester tester,
  UnifiedEditorProvider editor,
  String path, {
  bool forceHex = false,
  bool Function()? until,
}) async {
  final settings = SettingsService();
  await tester.runAsync(() async {
    await settings.init();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: editor),
      ],
      child: MaterialApp(
        home: UnifiedEditorScreen(filePaths: [path], forceHex: forceHex),
      ),
    ));
  });
  await settleIo(tester, until: until ?? () => activeTab(editor) != null);
}

/// Choisit [label] dans le menu « Mode d'interprétation », puis attend que
/// [until] soit vrai (lecture disque terminée) ou un nombre fixe de tours.
Future<void> switchMode(WidgetTester tester, String label,
    {bool Function()? until}) async {
  await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  await settleIo(tester, until: until);
}

/// Onglet actif. C'est une classe privée de l'écran : accès dynamique pour
/// les vérifications internes.
dynamic activeTab(UnifiedEditorProvider editor) =>
    (editor as dynamic).activeTab;
