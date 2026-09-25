
/// @file main.dart
/// @brief Point d'entree principal de l'application OmniExplorer.
///
/// Plateformes supportées : Android, Linux, Windows.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/theme/app_theme.dart';
import 'core/services/app_state_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/trash_service.dart';
import 'core/utils/system_ui.dart';
import 'features/home/screens/feature_launcher_screen.dart';
import 'features/text_editor/screens/unified_editor_screen.dart';
import 'features/media_player/providers/media_player_provider.dart';
import 'features/password_vault/providers/vault_session.dart';
import 'features/video_editor/services/video_export_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enregistre fvp comme implémentation video_player sur Linux/Windows/macOS
  // (binaires FFmpeg/mpv précompilés — aucune dépendance système requise).
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    fvp.registerWith();
  }

  await initializeDateFormatting('fr_FR', null);

  // SQLite via FFI sur Linux/Windows/macOS.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Orientations autorisées — no-op sur desktop via SystemUI.
  await SystemUI.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Masquer la barre de navigation Android pour maximiser l'espace.
  SystemUI.hideBottomBar();

  // Service de notification audio — Android uniquement.
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.omniexplorer.channel.audio',
        androidNotificationChannelName: 'OmniExplorer Audio',
        androidNotificationOngoing: true,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[Audio] Initialisation background ignorée : $e');
    }
  }

  final settings = SettingsService();
  try { await settings.init(); } catch (e) {
    debugPrint('[Settings] init error : $e');
  }

  final trash = TrashService();
  try { await trash.init(); } catch (e) {
    debugPrint('[Trash] init error : $e');
  }

  final appState = AppStateService();
  try { await appState.init(); } catch (e) {
    debugPrint('[AppState] init error : $e');
  }

  // Service d'export vidéo en arrière-plan + notifications.
  try { await VideoExportService.init(); } catch (e) {
    debugPrint('[VideoExport] init error : $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: trash),
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => UnifiedEditorProvider()),
        ChangeNotifierProvider(create: (_) => MediaPlayerProvider()),
        // Session du coffre-fort : créée à la première ouverture du coffre,
        // puis conservée (le verrouillage automatique la protège).
        ChangeNotifierProvider(create: (_) => VaultSession()),
      ],
      child: const OmniExplorerApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class OmniExplorerApp extends StatelessWidget {
  const OmniExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return MaterialApp(
      title:                    'OmniExplorer',
      debugShowCheckedModeBanner: false,
      themeMode:                settings.themeMode,
      theme:                    AppTheme.light(),
      darkTheme:                AppTheme.dark(),
      home:                     const FeatureLauncherScreen(),
    );
  }
}
