/// @file responsive.dart
/// @brief Utilitaires de mise en page responsive et détection de plateforme.
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

// ── Détection de plateforme ───────────────────────────────────────────────────

/// Vrai sur Linux, Windows et macOS.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Vrai sur Android et iOS.
bool get isMobilePlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// ── Breakpoints ───────────────────────────────────────────────────────────────

/// Catégories de taille d'écran.
enum ScreenLayout { mobile, tablet, desktop }

/// Retourne le layout adapté à la largeur disponible.
ScreenLayout layoutOf(double width) {
  if (width >= 1024) return ScreenLayout.desktop;
  if (width >= 600)  return ScreenLayout.tablet;
  return ScreenLayout.mobile;
}

/// Vrai si la largeur justifie un NavigationRail latéral plutôt qu'une
/// barre de navigation inférieure.
bool useNavigationRail(double width) => width >= 720;

/// Nombre de colonnes recommandé pour la grille de fichiers.
int gridColumnsFor(double width) {
  if (width >= 1400) return 8;
  if (width >= 1100) return 6;
  if (width >= 800)  return 5;
  if (width >= 600)  return 4;
  return 3;
}
