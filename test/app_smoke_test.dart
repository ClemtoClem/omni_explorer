/// @file app_smoke_test.dart
/// @brief Test de démarrage : l'application se construit avec ses vrais
/// providers et affiche l'écran d'accueil (menu des fonctionnalités).

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omni_explorer/core/services/app_state_service.dart';
import 'package:omni_explorer/core/services/settings_service.dart';
import 'package:omni_explorer/core/services/trash_service.dart';
import 'package:omni_explorer/features/media_player/providers/media_player_provider.dart';
import 'package:omni_explorer/features/text_editor/screens/unified_editor_screen.dart';
import 'package:omni_explorer/main.dart';

void main() {
  setUp(() {
    // Pas d'accès réseau pendant les tests : polices de repli.
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('l\'application démarre sur le menu des fonctionnalités',
      (tester) async {
    final settings = SettingsService();
    await settings.init();
    final appState = AppStateService();
    await appState.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: TrashService()),
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider(create: (_) => UnifiedEditorProvider()),
          ChangeNotifierProvider(create: (_) => MediaPlayerProvider()),
        ],
        child: const OmniExplorerApp(),
      ),
    );
    await tester.pump();

    expect(find.text('OmniExplorer'), findsOneWidget);
    for (final title in [
      'Explorateur',
      'Images',
      'Lecteur multimédia',
      'PDF'
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'carte « $title »');
    }
    // Les cartes du bas de la grille sont construites paresseusement :
    // on fait défiler pour les atteindre.
    await tester.scrollUntilVisible(find.text('Coffre-fort'), 300);
    expect(find.text('Coffre-fort'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
