/// @file system_ui.dart
/// @brief Abstraction multi-plateforme pour la gestion de l'interface système.
///
/// Sur Android / iOS : utilise SystemChrome pour contrôler la barre de statut,
/// la barre de navigation et l'orientation.
/// Sur Desktop (Linux, Windows, macOS) et Web : no-op absolu.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/services.dart'
    show
        SystemChrome,
        SystemUiMode,
        SystemUiOverlay,
        DeviceOrientation;

abstract final class SystemUI {
  /// Cache la barre de navigation Android pour maximiser l'espace éditeur.
  /// Sans effet sur iOS, desktop ou web.
  static void hideBottomBar() {
    if (!_isAndroid) return;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  /// Restaure toutes les barres système (à appeler dans dispose).
  /// Sans effet sur iOS, desktop ou web.
  static void restoreAllBars() {
    if (!_isAndroid) return;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  /// Verrouille les orientations autorisées sur mobile.
  /// Sans effet sur desktop ou web (les fenêtres sont redimensionnables librement).
  static Future<void> setPreferredOrientations(
      List<DeviceOrientation> orientations) async {
    if (!_isMobile) return;
    await SystemChrome.setPreferredOrientations(orientations);
  }

  // ─── Sécurisation des vérifications de plateforme ──────────────────────────

  // Utilisation de defaultTargetPlatform au lieu de dart:io (Platform.isAndroid).
  // Cela empêche les crashs sur Linux et garantit la compatibilité Web.
  static bool get _isAndroid => 
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isMobile =>
      !kIsWeb && 
      (defaultTargetPlatform == TargetPlatform.android || 
       defaultTargetPlatform == TargetPlatform.iOS);
}