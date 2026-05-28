/// @file circular_spectrum_visualizer.dart
/// @brief Visualiseurs circulaires : barres radiales, anneaux lumineux,
/// pulsation.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';

class CircularSpectrumVisualizer extends StatelessWidget {
  final List<double> magnitudes;
  final bool isPlaying;
  final CircularMode mode;
  final double phase;

  const CircularSpectrumVisualizer({
    super.key,
    required this.magnitudes,
    required this.isPlaying,
    required this.mode,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: CustomPaint(
        painter: _CircularPainter(
          mags: magnitudes,
          isPlaying: isPlaying,
          mode: mode,
          phase: phase,
        ),
      ),
    );
  }
}

class _CircularPainter extends CustomPainter {
  final List<double> mags;
  final bool isPlaying;
  final CircularMode mode;
  final double phase;

  _CircularPainter({
    required this.mags,
    required this.isPlaying,
    required this.mode,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy) - 4;
    final innerR = maxR * 0.45;
    switch (mode) {
      case CircularMode.radialBars:
        _paintRadialBars(canvas, cx, cy, innerR, maxR);
        break;
      case CircularMode.glowingRings:
        _paintGlowingRings(canvas, cx, cy, maxR);
        break;
      case CircularMode.pulsation:
        _paintPulsation(canvas, cx, cy, innerR, maxR);
        break;
    }
  }

  // ── Barres radiales : segments depuis le cercle intérieur vers l'extérieur.
  void _paintRadialBars(
      Canvas canvas, double cx, double cy, double innerR, double maxR) {
    final n = mags.length;
    final p = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < n; i++) {
      final ang = 2 * math.pi * i / n - math.pi / 2 + phase * 0.3;
      final mag = isPlaying ? mags[i] : 0.05;
      final outer = innerR + (maxR - innerR) * mag;
      final p1 = Offset(cx + math.cos(ang) * innerR,
          cy + math.sin(ang) * innerR);
      final p2 = Offset(cx + math.cos(ang) * outer,
          cy + math.sin(ang) * outer);
      final hue = (i * 360 / n) % 360;
      p
        ..color = HSLColor.fromAHSL(1, hue, 0.7, 0.6).toColor()
        ..strokeWidth = 3;
      canvas.drawLine(p1, p2, p);
    }
    canvas.drawCircle(
        Offset(cx, cy),
        innerR - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white24);
  }

  // ── Anneaux lumineux : plusieurs cercles concentriques pulsant. ──────────
  void _paintGlowingRings(Canvas canvas, double cx, double cy, double maxR) {
    const ringCount = 6;
    for (int i = 0; i < ringCount; i++) {
      final bandStart = (i * mags.length / ringCount).toInt();
      final bandEnd =
          ((i + 1) * mags.length / ringCount).toInt().clamp(0, mags.length);
      double avg = 0;
      for (int k = bandStart; k < bandEnd; k++) {
        avg += mags[k];
      }
      avg = bandEnd == bandStart ? 0 : avg / (bandEnd - bandStart);
      final pulse = isPlaying ? avg : 0.05;
      final r = maxR * (0.4 + i * 0.1) + pulse * 12;
      final hue = (i * 60 + phase * 80) % 360;
      final c = HSLColor.fromAHSL(0.8, hue, 0.7, 0.55).toColor();
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + pulse * 6
        ..color = c
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + pulse * 8);
      canvas.drawCircle(Offset(cx, cy), r, p);
    }
  }

  // ── Pulsation : un seul disque qui « respire » avec le niveau global. ────
  void _paintPulsation(
      Canvas canvas, double cx, double cy, double innerR, double maxR) {
    double avg = 0;
    for (final m in mags) {
      avg += m;
    }
    avg = mags.isEmpty ? 0 : avg / mags.length;
    final level = isPlaying ? avg : 0.05;
    final r = innerR + (maxR - innerR) * (0.3 + level);
    final color = HSLColor.fromAHSL(
            1, (260 + phase * 50) % 360, 0.65, 0.55 + level * 0.25)
        .toColor();
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(Offset(cx, cy), r * 1.05, glow);
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(
              center: Offset(cx, cy), radius: r)));
    // Petite couronne contour
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _CircularPainter old) => true;
}
