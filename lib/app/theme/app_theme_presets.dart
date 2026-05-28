/// @file app_theme_presets.dart
/// @brief Définition des thèmes de couleur prédéfinis et de la classe [ThemePreset].
///
/// Chaque [ThemePreset] contient la palette complète (accent, surfaces sombre
/// et clair) utilisée par [AppTheme] pour générer les [ThemeData] Flutter.
/// La méthode [ThemePreset.fromAccent] dérive automatiquement des surfaces
/// harmonieuses à partir d'une seule couleur d'accentuation.

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// @class ThemePreset
/// @brief Palette de couleurs complète pour un thème OmniExplorer.
class ThemePreset {
  final String id;
  final String name;
  final String emoji;

  // Accent
  final Color accent;
  final Color accentVariant;

  // Mode sombre
  final Color darkBg;
  final Color darkSurface;
  final Color darkSurface2;
  final Color darkBorder;
  final Color darkText;
  final Color darkSubtext;

  // Mode clair
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurface2;
  final Color lightBorder;
  final Color lightText;
  final Color lightSubtext;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.accent,
    required this.accentVariant,
    required this.darkBg,
    required this.darkSurface,
    required this.darkSurface2,
    required this.darkBorder,
    required this.darkText,
    required this.darkSubtext,
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurface2,
    required this.lightBorder,
    required this.lightText,
    required this.lightSubtext,
  });

  // ── Factory : thème personnalisé dérivé d'une couleur d'accent ─────────────

  /// @brief Génère un thème complet à partir d'une seule couleur d'accentuation.
  ///
  /// Les surfaces sombre et clair sont calculées en conservant la teinte (hue)
  /// de [accent] et en ajustant la luminosité et la saturation.
  factory ThemePreset.fromAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);

    Color dark(double sat, double lig) =>
        HSLColor.fromAHSL(1, hsl.hue, sat.clamp(0, 1), lig.clamp(0.01, 0.99))
            .toColor();
    Color light(double sat, double lig) =>
        HSLColor.fromAHSL(1, hsl.hue, sat.clamp(0, 1), lig.clamp(0.01, 0.99))
            .toColor();

    // accentVariant = version légèrement plus sombre
    final varL = (hsl.lightness - 0.10).clamp(0.20, 0.80);
    final accentVariant =
        HSLColor.fromAHSL(1, hsl.hue, hsl.saturation, varL).toColor();

    return ThemePreset(
      id:            'custom',
      name:          'Personnalisé',
      emoji:         '🎨',
      accent:        accent,
      accentVariant: accentVariant,
      // Surfaces sombre
      darkBg:       dark(0.35, 0.04),
      darkSurface:  dark(0.28, 0.08),
      darkSurface2: dark(0.22, 0.12),
      darkBorder:   dark(0.18, 0.17),
      darkText:     const Color(0xFFE8EAF6),
      darkSubtext:  const Color(0xFF8B9CC8),
      // Surfaces clair
      lightBg:       light(0.35, 0.97),
      lightSurface:  const Color(0xFFFFFFFF),
      lightSurface2: light(0.28, 0.94),
      lightBorder:   light(0.25, 0.88),
      lightText:     const Color(0xFF1A1D2E),
      lightSubtext:  const Color(0xFF5A6480),
    );
  }

  // ── Sérialisation ──────────────────────────────────────────────────────────

  // ignore: deprecated_member_use
  Map<String, dynamic> toMap() => {
    'id':            id,
    'name':          name,
    'emoji':         emoji,
    'accent':        accent.toARGB32,
    'accentVariant': accentVariant.toARGB32,
    'darkBg':        darkBg.toARGB32,
    'darkSurface':   darkSurface.toARGB32,
    'darkSurface2':  darkSurface2.toARGB32,
    'darkBorder':    darkBorder.toARGB32,
    'darkText':      darkText.toARGB32,
    'darkSubtext':   darkSubtext.toARGB32,
    'lightBg':       lightBg.toARGB32,
    'lightSurface':  lightSurface.toARGB32,
    'lightSurface2': lightSurface2.toARGB32,
    'lightBorder':   lightBorder.toARGB32,
    'lightText':     lightText.toARGB32,
    'lightSubtext':  lightSubtext.toARGB32,
  };

  factory ThemePreset.fromMap(Map<String, dynamic> m) => ThemePreset(
    id:            m['id']            as String,
    name:          m['name']          as String,
    emoji:         m['emoji']         as String? ?? '🎨',
    accent:        Color(m['accent']        as int),
    accentVariant: Color(m['accentVariant'] as int),
    darkBg:        Color(m['darkBg']        as int),
    darkSurface:   Color(m['darkSurface']   as int),
    darkSurface2:  Color(m['darkSurface2']  as int),
    darkBorder:    Color(m['darkBorder']    as int),
    darkText:      Color(m['darkText']      as int),
    darkSubtext:   Color(m['darkSubtext']   as int),
    lightBg:       Color(m['lightBg']       as int),
    lightSurface:  Color(m['lightSurface']  as int),
    lightSurface2: Color(m['lightSurface2'] as int),
    lightBorder:   Color(m['lightBorder']   as int),
    lightText:     Color(m['lightText']     as int),
    lightSubtext:  Color(m['lightSubtext']  as int),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThemePreset && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class AppThemePresets
/// @brief Catalogue des 10 thèmes prédéfinis de l'application.
class AppThemePresets {
  AppThemePresets._();

  /// Thème par défaut (Cosmos – Bleu).
  static const ThemePreset defaultPreset = cosmos;

  // ── 10 presets ─────────────────────────────────────────────────────────────

  /// 1 – Cosmos : bleu spatial (défaut).
  static const ThemePreset cosmos = ThemePreset(
    id: 'cosmos', name: 'Cosmos', emoji: '🌌',
    accent:        Color(0xFF4F9CF9), accentVariant: Color(0xFF2979FF),
    darkBg:        Color(0xFF0F1117), darkSurface:   Color(0xFF1A1D27),
    darkSurface2:  Color(0xFF22263A), darkBorder:    Color(0xFF2E3248),
    darkText:      Color(0xFFE8EAF6), darkSubtext:   Color(0xFF8B9CC8),
    lightBg:       Color(0xFFF5F7FF), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFEEF1FA), lightBorder:   Color(0xFFDDE2F0),
    lightText:     Color(0xFF1A1D2E), lightSubtext:  Color(0xFF5A6480),
  );

  /// 2 – Forêt : vert émeraude.
  static const ThemePreset foret = ThemePreset(
    id: 'foret', name: 'Forêt', emoji: '🌿',
    accent:        Color(0xFF34D399), accentVariant: Color(0xFF059669),
    darkBg:        Color(0xFF061210), darkSurface:   Color(0xFF0E231C),
    darkSurface2:  Color(0xFF163529), darkBorder:    Color(0xFF1E4737),
    darkText:      Color(0xFFE0F7F1), darkSubtext:   Color(0xFF7EC8B0),
    lightBg:       Color(0xFFF0FDF9), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFDCFCED), lightBorder:   Color(0xFFBBF7D0),
    lightText:     Color(0xFF0D2820), lightSubtext:  Color(0xFF3B7A60),
  );

  /// 3 – Rubis : rouge cramoisi.
  static const ThemePreset rubis = ThemePreset(
    id: 'rubis', name: 'Rubis', emoji: '💎',
    accent:        Color(0xFFF43F5E), accentVariant: Color(0xFFE11D48),
    darkBg:        Color(0xFF12080C), darkSurface:   Color(0xFF1E1015),
    darkSurface2:  Color(0xFF2C1820), darkBorder:    Color(0xFF3E222E),
    darkText:      Color(0xFFF9E8EC), darkSubtext:   Color(0xFFCA8896),
    lightBg:       Color(0xFFFFF1F2), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFFFE4E6), lightBorder:   Color(0xFFFECDD3),
    lightText:     Color(0xFF2D0A12), lightSubtext:  Color(0xFF8B3344),
  );

  /// 4 – Soleil : ambre doré.
  static const ThemePreset soleil = ThemePreset(
    id: 'soleil', name: 'Soleil', emoji: '☀️',
    accent:        Color(0xFFF59E0B), accentVariant: Color(0xFFD97706),
    darkBg:        Color(0xFF12100A), darkSurface:   Color(0xFF1F1A0E),
    darkSurface2:  Color(0xFF2C2515), darkBorder:    Color(0xFF3E331C),
    darkText:      Color(0xFFFDF6E3), darkSubtext:   Color(0xFFCCA854),
    lightBg:       Color(0xFFFFFBEB), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFFEF3C7), lightBorder:   Color(0xFFFDE68A),
    lightText:     Color(0xFF2C200A), lightSubtext:  Color(0xFF7A5A1A),
  );

  /// 5 – Galaxie : violet profond.
  static const ThemePreset galaxie = ThemePreset(
    id: 'galaxie', name: 'Galaxie', emoji: '🔮',
    accent:        Color(0xFFA855F7), accentVariant: Color(0xFF7C3AED),
    darkBg:        Color(0xFF0C0A14), darkSurface:   Color(0xFF151220),
    darkSurface2:  Color(0xFF1D1830), darkBorder:    Color(0xFF2B2245),
    darkText:      Color(0xFFF0EAFF), darkSubtext:   Color(0xFF9B82CC),
    lightBg:       Color(0xFFFAF5FF), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFF3E8FF), lightBorder:   Color(0xFFE9D5FF),
    lightText:     Color(0xFF1C1030), lightSubtext:  Color(0xFF6B4A8A),
  );

  /// 6 – Arctique : cyan glacé.
  static const ThemePreset arctique = ThemePreset(
    id: 'arctique', name: 'Arctique', emoji: '❄️',
    accent:        Color(0xFF06B6D4), accentVariant: Color(0xFF0891B2),
    darkBg:        Color(0xFF060E12), darkSurface:   Color(0xFF0D1B21),
    darkSurface2:  Color(0xFF132833), darkBorder:    Color(0xFF1A3646),
    darkText:      Color(0xFFE8F9FF), darkSubtext:   Color(0xFF6BB8CC),
    lightBg:       Color(0xFFECFEFF), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFCFFAFE), lightBorder:   Color(0xFFA5F3FC),
    lightText:     Color(0xFF041E28), lightSubtext:  Color(0xFF1F7890),
  );

  /// 7 – Sakura : rose délicat.
  static const ThemePreset sakura = ThemePreset(
    id: 'sakura', name: 'Sakura', emoji: '🌸',
    accent:        Color(0xFFEC4899), accentVariant: Color(0xFFDB2777),
    darkBg:        Color(0xFF12080E), darkSurface:   Color(0xFF1F1018),
    darkSurface2:  Color(0xFF2D1525), darkBorder:    Color(0xFF3E1F33),
    darkText:      Color(0xFFFDE8F4), darkSubtext:   Color(0xFFCC82AA),
    lightBg:       Color(0xFFFDF2F8), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFFCE7F3), lightBorder:   Color(0xFFFBCFE8),
    lightText:     Color(0xFF2D0A20), lightSubtext:  Color(0xFF8B3366),
  );

  /// 8 – Minuit : AMOLED noir absolu.
  static const ThemePreset minuit = ThemePreset(
    id: 'minuit', name: 'Minuit', emoji: '🌑',
    accent:        Color(0xFFCBD5E1), accentVariant: Color(0xFF94A3B8),
    darkBg:        Color(0xFF000000), darkSurface:   Color(0xFF0A0A0A),
    darkSurface2:  Color(0xFF141414), darkBorder:    Color(0xFF1E1E1E),
    darkText:      Color(0xFFF1F5F9), darkSubtext:   Color(0xFF94A3B8),
    lightBg:       Color(0xFFF8FAFC), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFF1F5F9), lightBorder:   Color(0xFFE2E8F0),
    lightText:     Color(0xFF0F172A), lightSubtext:  Color(0xFF64748B),
  );

  /// 9 – Sépia : chaleur vintage.
  static const ThemePreset sepia = ThemePreset(
    id: 'sepia', name: 'Sépia', emoji: '📜',
    accent:        Color(0xFFD97706), accentVariant: Color(0xFFB45309),
    darkBg:        Color(0xFF120E08), darkSurface:   Color(0xFF1E170F),
    darkSurface2:  Color(0xFF2C2218), darkBorder:    Color(0xFF3D3020),
    darkText:      Color(0xFFFDF3E0), darkSubtext:   Color(0xFFBB9464),
    lightBg:       Color(0xFFFDF8EF), lightSurface:  Color(0xFFFEFCF5),
    lightSurface2: Color(0xFFFEF0D0), lightBorder:   Color(0xFFFDE0A0),
    lightText:     Color(0xFF2C1F08), lightSubtext:  Color(0xFF7A5A1A),
  );

  /// 10 – Menthe : fraîcheur teal.
  static const ThemePreset menthe = ThemePreset(
    id: 'menthe', name: 'Menthe', emoji: '🍃',
    accent:        Color(0xFF14B8A6), accentVariant: Color(0xFF0D9488),
    darkBg:        Color(0xFF06120F), darkSurface:   Color(0xFF0D1F1A),
    darkSurface2:  Color(0xFF142E26), darkBorder:    Color(0xFF1A3E32),
    darkText:      Color(0xFFE0F7F4), darkSubtext:   Color(0xFF6BBFB3),
    lightBg:       Color(0xFFF0FDFA), lightSurface:  Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFCCFBF1), lightBorder:   Color(0xFF99F6E4),
    lightText:     Color(0xFF0A2420), lightSubtext:  Color(0xFF267A6E),
  );

  // ── Catalogue ──────────────────────────────────────────────────────────────

  /// Liste ordonnée des 10 thèmes prédéfinis.
  static const List<ThemePreset> all = [
    cosmos, foret, rubis, soleil, galaxie,
    arctique, sakura, minuit, sepia, menthe,
  ];

  /// Recherche un preset par [id]. Retourne [defaultPreset] si introuvable.
  static ThemePreset findById(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => defaultPreset);
}
