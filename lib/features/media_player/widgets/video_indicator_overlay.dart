/// @file video_indicator_overlay.dart
/// @brief HUD éphémère pour la luminosité, le volume, le delta de recherche
/// et la vitesse (apparaît brièvement lors des gestes).

import 'package:flutter/material.dart';

class VideoHudIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  /// Valeur 0..1 pour la barre de progression interne (ou null si pas de barre).
  final double? value;
  final Alignment alignment;

  const VideoHudIndicator({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ],
            ),
            if (value != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 140,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value!.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
