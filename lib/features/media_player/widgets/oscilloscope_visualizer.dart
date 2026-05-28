/// @file oscilloscope_visualizer.dart
/// @brief Oscilloscope : 4 modes (mono / stéréo / XY / Lissajous) × 3 styles
/// visuels (synthé glow, électronique sec, scientifique avec graduation).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';

class OscilloscopeVisualizer extends StatelessWidget {
  /// Échantillons (-1..1) du canal gauche.
  final List<double> waveformL;
  /// Échantillons (-1..1) du canal droit (ignoré en mono).
  final List<double> waveformR;
  final bool isPlaying;
  final OscilloscopeMode mode;
  final OscilloscopeStyle style;

  const OscilloscopeVisualizer({
    super.key,
    required this.waveformL,
    required this.waveformR,
    required this.isPlaying,
    required this.mode,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: mode == OscilloscopeMode.xy || mode == OscilloscopeMode.lissajous
          ? 220
          : 320,
      height: mode == OscilloscopeMode.xy || mode == OscilloscopeMode.lissajous
          ? 220
          : 140,
      child: CustomPaint(
        painter: _OscilloscopePainter(
          left: waveformL,
          right: waveformR,
          isPlaying: isPlaying,
          mode: mode,
          style: style,
        ),
      ),
    );
  }
}

class _OscilloscopePainter extends CustomPainter {
  final List<double> left;
  final List<double> right;
  final bool isPlaying;
  final OscilloscopeMode mode;
  final OscilloscopeStyle style;

  _OscilloscopePainter({
    required this.left,
    required this.right,
    required this.isPlaying,
    required this.mode,
    required this.style,
  });

  // ── Couleurs / fond / grille par style. ──────────────────────────────────

  Color get _bg => switch (style) {
        OscilloscopeStyle.synth => const Color(0xFF0B0B22),
        OscilloscopeStyle.electronic => Colors.black,
        OscilloscopeStyle.scientific => const Color(0xFF002B23),
      };

  Color get _strokeColor => switch (style) {
        OscilloscopeStyle.synth => const Color(0xFFCBA6F7),
        OscilloscopeStyle.electronic => const Color(0xFFA6E3A1),
        OscilloscopeStyle.scientific => const Color(0xFF7FFF7F),
      };

  bool get _withGrid => style == OscilloscopeStyle.scientific;
  bool get _withGlow => style == OscilloscopeStyle.synth;

  @override
  void paint(Canvas canvas, Size size) {
    // Fond
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = _bg);
    if (_withGrid) _drawGrid(canvas, size);

    switch (mode) {
      case OscilloscopeMode.mono:
        _drawWaveform(canvas, size, _activeLeft(), 0.5);
        break;
      case OscilloscopeMode.stereo:
        _drawWaveform(canvas, size, _activeLeft(), 0.27);
        _drawWaveform(canvas, size, _activeRight(), 0.73,
            color: _strokeColor.withValues(alpha: 0.7));
        break;
      case OscilloscopeMode.xy:
        _drawXY(canvas, size, _activeLeft(), _activeRight());
        break;
      case OscilloscopeMode.lissajous:
        _drawLissajous(canvas, size);
        break;
    }

    // Bordure
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white24);
  }

  List<double> _activeLeft() => isPlaying ? left : List.filled(left.length, 0);
  List<double> _activeRight() =>
      isPlaying ? right : List.filled(right.length, 0);

  void _drawGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.6;
    // 8 divisions horizontales × 6 verticales (calque oscilloscope).
    for (int i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (int i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // Marques médianes (échelle).
    final pStrong = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(size.width / 2, 0), Offset(size.width / 2, size.height), pStrong);
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), pStrong);
  }

  void _drawWaveform(Canvas canvas, Size size, List<double> samples,
      double yCenterFrac,
      {Color? color}) {
    if (samples.isEmpty) return;
    final n = samples.length;
    final amp = size.height * 0.4;
    final yCenter = size.height * yCenterFrac;
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final y = yCenter - samples[i] * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final stroke = color ?? _strokeColor;
    if (_withGlow) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = stroke.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = stroke);
  }

  // ── XY : trace (L, R) → (x, y). ──────────────────────────────────────────
  void _drawXY(Canvas canvas, Size size, List<double> l, List<double> r) {
    if (l.isEmpty || r.isEmpty) return;
    final n = math.min(l.length, r.length);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final amp = math.min(cx, cy) * 0.85;
    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = cx + l[i] * amp;
      final y = cy - r[i] * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (_withGlow) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = _strokeColor.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _strokeColor);
  }

  // ── Lissajous : (L, R + déphasage) — produit des figures bouclées. ───────
  void _drawLissajous(Canvas canvas, Size size) {
    if (left.isEmpty) return;
    final n = left.length;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final amp = math.min(cx, cy) * 0.8;
    final path = Path();
    // Couple ratio 3:2 par défaut pour produire une figure stable.
    for (int i = 0; i < n; i++) {
      final tx = left[i];
      final tyIdx = (i + n ~/ 4) % n;
      final ty = right.isEmpty ? left[tyIdx] * 0.9 : right[tyIdx];
      final x = cx + tx * amp;
      final y = cy - ty * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (_withGlow) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = _strokeColor.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _strokeColor);
  }

  @override
  bool shouldRepaint(covariant _OscilloscopePainter old) => true;
}
