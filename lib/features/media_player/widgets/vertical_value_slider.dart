/// @file vertical_value_slider.dart
/// @brief Indicateur vertical (luminosité / volume) avec une icône à chaque
/// extrémité et un remplissage proportionnel à la valeur (0..1).
///
/// Affiché brièvement pendant un geste de glissement vertical sur la vidéo.

import 'package:flutter/material.dart';

class VerticalValueSlider extends StatelessWidget {
  final IconData topIcon;
  final IconData bottomIcon;
  /// Valeur courante 0..1 (1 = plein, 0 = vide).
  final double value;
  /// Couleur du remplissage.
  final Color fillColor;
  /// Alignement vertical du slider (au centre de la moitié visée).
  final Alignment alignment;
  /// Hauteur en pixels logiques.
  final double height;
  /// Étiquette en pourcentage affichée sous le slider.
  final bool showPercent;

  const VerticalValueSlider({
    super.key,
    required this.topIcon,
    required this.bottomIcon,
    required this.value,
    required this.alignment,
    this.fillColor = Colors.white,
    this.height = 220,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(topIcon, color: Colors.white, size: 20),
              const SizedBox(height: 10),
              SizedBox(
                height: height,
                width: 8,
                child: _VerticalBar(value: value, fillColor: fillColor),
              ),
              const SizedBox(height: 10),
              Icon(bottomIcon, color: Colors.white70, size: 20),
              if (showPercent) ...[
                const SizedBox(height: 6),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalBar extends StatelessWidget {
  final double value;
  final Color fillColor;
  const _VerticalBar({required this.value, required this.fillColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(color: Colors.white24),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1.0, // Aligné sur toute la largeur (8px)
              heightFactor: value.clamp(0.0, 1.0),
              child: Container(color: fillColor),
            ),
          ),
        ],
      ),
    );
  }
}
