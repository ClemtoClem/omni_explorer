/// @file app_theme.dart
/// @brief Thèmes clair/sombre de l'application OmniExplorer.
///
/// [AppColors] expose des champs statiques **mutables** mis à jour à chaque
/// changement de preset via [AppColors.apply]. Les méthodes [AppTheme.dark]
/// et [AppTheme.light] lisent ces champs pour générer le [ThemeData] Flutter.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme_presets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppColors
// ─────────────────────────────────────────────────────────────────────────────

/// @class AppColors
/// @brief Palette de couleurs partagée entre les composants de l'application.
///
/// Les champs dynamiques (accent, surfaces) sont mis à jour par [apply] lors
/// du changement de preset. Les couleurs sémantiques (error, file types…)
/// sont des constantes et ne varient pas avec le thème.
class AppColors {
  AppColors._();

  // ── Couleurs dynamiques (varient selon le preset) ─────────────────────────

  static Color accent        = const Color(0xFF4F9CF9);
  static Color accentVariant = const Color(0xFF2979FF);

  // Mode sombre
  static Color darkBg        = const Color(0xFF0F1117);
  static Color darkSurface   = const Color(0xFF1A1D27);
  static Color darkSurface2  = const Color(0xFF22263A);
  static Color darkBorder    = const Color(0xFF2E3248);
  static Color darkText      = const Color(0xFFE8EAF6);
  static Color darkSubtext   = const Color(0xFF8B9CC8);

  // Mode clair
  static Color lightBg       = const Color(0xFFF5F7FF);
  static Color lightSurface  = const Color(0xFFFFFFFF);
  static Color lightSurface2 = const Color(0xFFEEF1FA);
  static Color lightBorder   = const Color(0xFFDDE2F0);
  static Color lightText     = const Color(0xFF1A1D2E);
  static Color lightSubtext  = const Color(0xFF5A6480);

  // ── Couleurs sémantiques (constantes) ─────────────────────────────────────

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error   = Color(0xFFEF5350);
  static const Color info    = Color(0xFF29B6F6);

  // Couleurs par type de fichier (sémantiques, ne varient pas)
  static const Color colorAudio   = Color(0xFF9C27B0);
  static const Color colorVideo   = Color(0xFFE91E63);
  static const Color colorImage   = Color(0xFF00BCD4);
  static const Color colorPdf     = Color(0xFFF44336);
  static const Color colorDoc     = Color(0xFF2196F3);
  static const Color colorCode    = Color(0xFF4CAF50);
  static const Color colorArchive = Color(0xFFFF9800);
  static const Color colorFolder  = Color(0xFFFFC107);
  static const Color colorText    = Color(0xFF78909C);
  static const Color colorUnknown = Color(0xFF607D8B);

  // ── Application d'un preset ───────────────────────────────────────────────

  /// @brief Met à jour tous les champs dynamiques à partir d'un [ThemePreset].
  ///
  /// À appeler **avant** `notifyListeners()` dans [SettingsService] afin que
  /// les [ThemeData] générés lors du prochain build reflètent le nouveau thème.
  static void apply(ThemePreset p) {
    accent        = p.accent;
    accentVariant = p.accentVariant;
    darkBg        = p.darkBg;
    darkSurface   = p.darkSurface;
    darkSurface2  = p.darkSurface2;
    darkBorder    = p.darkBorder;
    darkText      = p.darkText;
    darkSubtext   = p.darkSubtext;
    lightBg       = p.lightBg;
    lightSurface  = p.lightSurface;
    lightSurface2 = p.lightSurface2;
    lightBorder   = p.lightBorder;
    lightText     = p.lightText;
    lightSubtext  = p.lightSubtext;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppFonts
// ─────────────────────────────────────────────────────────────────────────────

/// @class AppFonts
/// @brief Police de l'interface globale — mise à jour par [SettingsService].
///
/// Stocke la famille (nom Google Fonts) et l'échelle de taille courantes.
/// [AppTheme._textTheme] lit ces champs pour générer le [TextTheme].
class AppFonts {
  AppFonts._();

  static String uiFamily = 'Inter';
  static double uiScale  = 1.0;

  static void apply({required String family, required double scale}) {
    uiFamily = family;
    uiScale  = scale;
  }

  /// Construit un [TextStyle] avec la police d'interface en cours.
  static TextStyle of({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) {
    final s = size * uiScale;
    try {
      return GoogleFonts.getFont(uiFamily,
          fontSize: s, fontWeight: weight, color: color);
    } catch (_) {
      return GoogleFonts.inter(fontSize: s, fontWeight: weight, color: color);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppSpacing / AppRadius
// ─────────────────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xs  =  4.0;
  static const double sm  =  8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;
}

class AppRadius {
  AppRadius._();
  static const double xs   =  4.0;
  static const double sm   =  8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 24.0;
  static const double full = 100.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme
// ─────────────────────────────────────────────────────────────────────────────

/// @class AppTheme
/// @brief Fournit les [ThemeData] pour les modes sombre et clair.
///
/// Les couleurs sont lues depuis [AppColors] au moment de l'appel, permettant
/// le changement de palette sans recréer le widget tree.
class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge:   AppFonts.of(size: 32, weight: FontWeight.w700, color: primary),
      headlineLarge:  AppFonts.of(size: 20, weight: FontWeight.w600, color: primary),
      headlineMedium: AppFonts.of(size: 18, weight: FontWeight.w500, color: primary),
      headlineSmall:  AppFonts.of(size: 16, weight: FontWeight.w500, color: primary),
      titleLarge:     AppFonts.of(size: 15, weight: FontWeight.w600, color: primary),
      titleMedium:    AppFonts.of(size: 14, weight: FontWeight.w500, color: primary),
      titleSmall:     AppFonts.of(size: 13, weight: FontWeight.w500, color: secondary),
      bodyLarge:      AppFonts.of(size: 14, color: primary),
      bodyMedium:     AppFonts.of(size: 13, color: primary),
      bodySmall:      AppFonts.of(size: 11, color: secondary),
      labelLarge:     AppFonts.of(size: 13, weight: FontWeight.w600, color: primary),
      labelMedium:    AppFonts.of(size: 12, weight: FontWeight.w500, color: primary),
      labelSmall:     AppFonts.of(size: 10, weight: FontWeight.w500, color: secondary),
    );
  }

  /// @brief Retourne le [ThemeData] sombre en lisant les couleurs courantes d'[AppColors].
  static ThemeData dark() {
    final bg        = AppColors.darkBg;
    final surface   = AppColors.darkSurface;
    final surface2  = AppColors.darkSurface2;
    final border    = AppColors.darkBorder;
    final text      = AppColors.darkText;
    final subtext   = AppColors.darkSubtext;
    final accent    = AppColors.accent;
    final accentVar = AppColors.accentVariant;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary:   accent,
        secondary: accentVar,
        surface:   surface,
        error:     AppColors.error,
        onPrimary: Colors.white,
        onSurface: text,
      ),
      textTheme: _textTheme(text, subtext),
      iconTheme: IconThemeData(color: subtext, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: text, size: 22),
        titleTextStyle: AppFonts.of(size: 17, weight: FontWeight.w600, color: text),
        toolbarHeight: 56,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: subtext,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: AppFonts.of(size: 13, color: subtext),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 24,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: AppFonts.of(size: 13, color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: subtext, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.20),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(
              color: s.contains(WidgetState.selected) ? accent : subtext,
              size: 22,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            AppFonts.of(
              size: 11,
              weight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: s.contains(WidgetState.selected) ? accent : subtext,
            )),
      ),
    );
  }

  /// @brief Retourne le [ThemeData] clair en lisant les couleurs courantes d'[AppColors].
  static ThemeData light() {
    final bg        = AppColors.lightBg;
    final surface   = AppColors.lightSurface;
    final surface2  = AppColors.lightSurface2;
    final border    = AppColors.lightBorder;
    final text      = AppColors.lightText;
    final subtext   = AppColors.lightSubtext;
    final accent    = AppColors.accent;
    final accentVar = AppColors.accentVariant;

    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.light(
        primary:   accent,
        secondary: accentVar,
        surface:   surface,
        error:     AppColors.error,
        onPrimary: Colors.white,
        onSurface: text,
      ),
      textTheme: _textTheme(text, subtext),
      iconTheme: IconThemeData(color: subtext, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: border,
        iconTheme: IconThemeData(color: text, size: 22),
        titleTextStyle: AppFonts.of(size: 17, weight: FontWeight.w600, color: text),
        toolbarHeight: 56,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: subtext,
        type: BottomNavigationBarType.fixed,
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: AppFonts.of(size: 13, color: subtext),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        elevation: 8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 12,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: AppFonts.of(size: 13, color: surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(
              color: s.contains(WidgetState.selected) ? accent : subtext,
              size: 22,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) =>
            AppFonts.of(
              size: 11,
              weight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: s.contains(WidgetState.selected) ? accent : subtext,
            )),
      ),
    );
  }
}
