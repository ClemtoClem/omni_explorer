/// @file subtitle_settings.dart
/// @brief Réglages visuels pour l'affichage des sous-titres.

import 'package:flutter/material.dart';

class SubtitleSettings {
  /// Taille de police en points logiques.
  final double fontSize;
  /// Position verticale relative (0 = haut, 1 = bas) — 0.9 = près du bas.
  final double verticalAlignment;
  /// Décalage horizontal en pixels logiques (drag).
  final double horizontalOffsetPx;
  /// Couleur du texte.
  final Color textColor;
  /// Couleur de surbrillance (boîte derrière le texte).
  final Color highlightColor;
  /// Activer le contour de texte (ombre noire) pour lisibilité.
  final bool textOutline;

  const SubtitleSettings({
    this.fontSize = 18,
    this.verticalAlignment = 0.88,
    this.horizontalOffsetPx = 0,
    this.textColor = Colors.white,
    this.highlightColor = const Color(0x80000000),
    this.textOutline = true,
  });

  SubtitleSettings copyWith({
    double? fontSize,
    double? verticalAlignment,
    double? horizontalOffsetPx,
    Color? textColor,
    Color? highlightColor,
    bool? textOutline,
  }) =>
      SubtitleSettings(
        fontSize: fontSize ?? this.fontSize,
        verticalAlignment: verticalAlignment ?? this.verticalAlignment,
        horizontalOffsetPx: horizontalOffsetPx ?? this.horizontalOffsetPx,
        textColor: textColor ?? this.textColor,
        highlightColor: highlightColor ?? this.highlightColor,
        textOutline: textOutline ?? this.textOutline,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'verticalAlignment': verticalAlignment,
        'horizontalOffsetPx': horizontalOffsetPx,
        // ignore: deprecated_member_use
        'textColor': textColor.value,
        // ignore: deprecated_member_use
        'highlightColor': highlightColor.value,
        'textOutline': textOutline,
      };

  factory SubtitleSettings.fromJson(Map<String, dynamic> json) => SubtitleSettings(
        fontSize: (json['fontSize'] as num).toDouble(),
        verticalAlignment: (json['verticalAlignment'] as num).toDouble(),
        horizontalOffsetPx: (json['horizontalOffsetPx'] as num).toDouble(),
        textColor: Color(json['textColor'] as int),
        highlightColor: Color(json['highlightColor'] as int),
        textOutline: json['textOutline'] as bool,
      );
}
