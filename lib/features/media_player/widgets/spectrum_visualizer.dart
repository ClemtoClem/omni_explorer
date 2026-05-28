/// @file spectrum_visualizer.dart
/// @brief Visualiseurs de spectre : barres, colonnes, fréquentiel avec
/// graduation. Mono ou stéréo (canal droit affiché en miroir avec déphasage).

import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';

class SpectrumVisualizer extends StatelessWidget {
  /// Magnitudes 0..1 du canal gauche (ou unique en mono).
  final List<double> magnitudesL;
  /// Magnitudes 0..1 du canal droit (ignoré en mono).
  final List<double> magnitudesR;
  final bool isPlaying;
  final SpectrumMode mode;
  final bool stereo;
  final Color color;

  const SpectrumVisualizer({
    super.key,
    required this.magnitudesL,
    required this.magnitudesR,
    required this.isPlaying,
    required this.mode,
    required this.stereo,
    this.color = const Color(0xFF89B4FA),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: CustomPaint(
        painter: _SpectrumPainter(
          left: magnitudesL,
          right: magnitudesR,
          isPlaying: isPlaying,
          mode: mode,
          stereo: stereo,
          color: color,
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> left;
  final List<double> right;
  final bool isPlaying;
  final SpectrumMode mode;
  final bool stereo;
  final Color color;

  _SpectrumPainter({
    required this.left,
    required this.right,
    required this.isPlaying,
    required this.mode,
    required this.stereo,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case SpectrumMode.bars:
        _paintBars(canvas, size);
        break;
      case SpectrumMode.columns:
        _paintColumns(canvas, size);
        break;
      case SpectrumMode.frequency:
        _paintFrequency(canvas, size);
        break;
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final bandH = stereo ? mid : size.height;
    final baseY = stereo ? mid : size.height;
    _drawBars(canvas, size, left, baseY, bandH, mirrorTop: stereo);
    if (stereo) {
      _drawBars(canvas, size, right, baseY, bandH, mirrorTop: false);
    }
  }

  void _drawBars(Canvas canvas, Size size, List<double> mags,
      double baseY, double bandH,
      {required bool mirrorTop}) {
    final n = mags.length;
    final barW = size.width / n;
    for (int i = 0; i < n; i++) {
      final h = (isPlaying ? mags[i] : 0.05) * bandH;
      final rect = mirrorTop
          ? Rect.fromLTWH(i * barW + barW * 0.15, baseY - h - bandH,
              barW * 0.7, h)
          : Rect.fromLTWH(i * barW + barW * 0.15, baseY - h,
              barW * 0.7, h);
      final hue = (220 + i * 360 / n) % 360;
      final c = HSLColor.fromAHSL(1, hue, 0.7, 0.55).toColor();
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [color, c],
        ).createShader(rect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    }
  }

  void _paintColumns(Canvas canvas, Size size) {
    // Colonnes segmentées « LED » : empilées par paliers.
    final n = left.length;
    final colW = size.width / n;
    const segs = 14;
    final segH = size.height / segs;
    for (int i = 0; i < n; i++) {
      final mag = isPlaying ? left[i] : 0.05;
      final lit = (mag * segs).round();
      for (int s = 0; s < segs; s++) {
        final isLit = s < lit;
        final y = size.height - (s + 1) * segH + 2;
        final rect = Rect.fromLTWH(i * colW + colW * 0.2, y,
            colW * 0.6, segH - 4);
        final c = !isLit
            ? Colors.white12
            : (s > segs * 0.8
                ? Colors.redAccent
                : (s > segs * 0.55 ? Colors.amber : color));
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
            Paint()..color = c);
      }
      if (stereo) {
        // Demi-largeur pour le canal droit, légèrement à droite.
        final magR = isPlaying ? right[i] : 0.05;
        final litR = (magR * segs).round();
        for (int s = 0; s < segs; s++) {
          final isLit = s < litR;
          final y = size.height - (s + 1) * segH + 2;
          final rect = Rect.fromLTWH(i * colW + colW * 0.55, y,
              colW * 0.25, segH - 4);
          final c = !isLit
              ? Colors.white10
              : (s > segs * 0.8 ? Colors.pinkAccent : color);
          canvas.drawRect(rect, Paint()..color = c);
        }
      }
    }
  }

  void _paintFrequency(Canvas canvas, Size size) {
    // Spectre fréquentiel (courbe lissée) avec graduation Hz simulée.
    final gridPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    // Lignes horizontales (dB)
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Graduations Hz approximatives (log)
    final freqs = ['60', '250', '1k', '4k', '12k'];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < freqs.length; i++) {
      final x = size.width * (i + 0.5) / freqs.length;
      canvas.drawLine(
          Offset(x, size.height - 8), Offset(x, size.height), gridPaint);
      tp.text = TextSpan(
          text: freqs[i],
          style: const TextStyle(color: Colors.white54, fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height));
    }
    _drawCurve(canvas, size, left, color);
    if (stereo) {
      _drawCurve(canvas, size, right, Colors.pinkAccent);
    }
  }

  void _drawCurve(
      Canvas canvas, Size size, List<double> mags, Color stroke) {
    final n = mags.length;
    if (n == 0) return;
    final fill = Path();
    final line = Path();
    final usableH = size.height - 12;
    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = usableH * (1 - (isPlaying ? mags[i] : 0.05));
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, usableH);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, usableH);
    fill.close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [stroke.withValues(alpha: 0.5), stroke.withValues(alpha: 0)],
          ).createShader(Offset.zero & Size(size.width, usableH)));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = stroke);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) => true;
}
