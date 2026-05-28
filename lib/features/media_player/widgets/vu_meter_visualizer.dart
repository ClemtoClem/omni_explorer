/// @file vu_meter_visualizer.dart
/// @brief VU-mètres : analogique (aiguille), digital (LED rangées), peak-hold.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';

class VuMeterVisualizer extends StatefulWidget {
  final List<double> magnitudesL;
  final List<double> magnitudesR;
  final bool isPlaying;
  final VuMode mode;
  final bool stereo;

  const VuMeterVisualizer({
    super.key,
    required this.magnitudesL,
    required this.magnitudesR,
    required this.isPlaying,
    required this.mode,
    required this.stereo,
  });

  @override
  State<VuMeterVisualizer> createState() => _VuMeterVisualizerState();
}

class _VuMeterVisualizerState extends State<VuMeterVisualizer> {
  double _peakL = 0;
  double _peakR = 0;
  DateTime _peakLAt = DateTime.now();
  DateTime _peakRAt = DateTime.now();

  double _level(List<double> m) {
    if (m.isEmpty) return 0;
    double s = 0;
    for (final v in m) {
      s += v * v;
    }
    return math.sqrt(s / m.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final lvlL = widget.isPlaying ? _level(widget.magnitudesL) : 0.05;
    final lvlR = widget.isPlaying ? _level(widget.magnitudesR) : 0.05;

    // Peak hold (descente lente).
    final now = DateTime.now();
    if (lvlL > _peakL) {
      _peakL = lvlL;
      _peakLAt = now;
    } else if (now.difference(_peakLAt).inMilliseconds > 500) {
      _peakL = (_peakL - 0.01).clamp(0.0, 1.0);
    }
    if (lvlR > _peakR) {
      _peakR = lvlR;
      _peakRAt = now;
    } else if (now.difference(_peakRAt).inMilliseconds > 500) {
      _peakR = (_peakR - 0.01).clamp(0.0, 1.0);
    }

    return SizedBox(
      height: widget.mode == VuMode.analog ? 130 : 100,
      child: CustomPaint(
        painter: _VuPainter(
          levelL: lvlL,
          levelR: lvlR,
          peakL: _peakL,
          peakR: _peakR,
          mode: widget.mode,
          stereo: widget.stereo,
        ),
      ),
    );
  }
}

class _VuPainter extends CustomPainter {
  final double levelL;
  final double levelR;
  final double peakL;
  final double peakR;
  final VuMode mode;
  final bool stereo;

  _VuPainter({
    required this.levelL,
    required this.levelR,
    required this.peakL,
    required this.peakR,
    required this.mode,
    required this.stereo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case VuMode.analog:
        _paintAnalog(canvas, size);
        break;
      case VuMode.digital:
        _paintDigital(canvas, size);
        break;
      case VuMode.peakHold:
        _paintPeakHold(canvas, size);
        break;
    }
  }

  // ── Analogique : aiguille sur cadran. ────────────────────────────────────

  void _paintAnalog(Canvas canvas, Size size) {
    if (stereo) {
      _drawNeedle(canvas, size, levelL, 'L', xCenterFrac: 0.27);
      _drawNeedle(canvas, size, levelR, 'R', xCenterFrac: 0.73);
    } else {
      _drawNeedle(canvas, size, levelL, '', xCenterFrac: 0.5);
    }
  }

  void _drawNeedle(Canvas canvas, Size size, double level, String label,
      {required double xCenterFrac}) {
    final cx = size.width * xCenterFrac;
    final cy = size.height * 0.95;
    final r = math.min(size.width * 0.22, size.height * 0.9);

    // Cadran (arc)
    final dial = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white24;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(rect, math.pi, math.pi, false, dial);

    // Graduations
    const ticks = 11;
    final tickP = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (int i = 0; i < ticks; i++) {
      final ang = math.pi + math.pi * i / (ticks - 1);
      final p1 = Offset(cx + math.cos(ang) * r, cy + math.sin(ang) * r);
      final p2 =
          Offset(cx + math.cos(ang) * r * 0.9, cy + math.sin(ang) * r * 0.9);
      canvas.drawLine(p1, p2, tickP);
    }

    // Zone rouge (haut)
    final redArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.redAccent;
    canvas.drawArc(rect, math.pi * 1.75, math.pi * 0.25, false, redArc);

    // Aiguille
    final ang = math.pi + math.pi * level;
    final tip = Offset(cx + math.cos(ang) * r * 0.92,
        cy + math.sin(ang) * r * 0.92);
    canvas.drawLine(
        Offset(cx, cy),
        tip,
        Paint()
          ..color = Colors.amber
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = Colors.amber);

    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy + 6));
    }
  }

  // ── Digital : barre LED horizontale par canal. ───────────────────────────

  void _paintDigital(Canvas canvas, Size size) {
    if (stereo) {
      _drawDigitalBar(canvas, size, levelL, yFrac: 0.3, label: 'L');
      _drawDigitalBar(canvas, size, levelR, yFrac: 0.7, label: 'R');
    } else {
      _drawDigitalBar(canvas, size, levelL, yFrac: 0.5, label: '');
    }
  }

  void _drawDigitalBar(Canvas canvas, Size size, double level,
      {required double yFrac, required String label}) {
    const segs = 30;
    final y = size.height * yFrac - 12;
    final segW = (size.width - 28) / segs;
    final lit = (level * segs).round();
    if (label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y + 6));
    }
    for (int s = 0; s < segs; s++) {
      final isLit = s < lit;
      final c = !isLit
          ? Colors.white12
          : (s > segs * 0.85
              ? Colors.redAccent
              : (s > segs * 0.6 ? Colors.amber : const Color(0xFFA6E3A1)));
      final rect = Rect.fromLTWH(
          24 + s * segW, y, segW - 1.5, 18);
      canvas.drawRect(rect, Paint()..color = c);
    }
  }

  // ── Peak-hold : barre LED + repère du pic. ───────────────────────────────

  void _paintPeakHold(Canvas canvas, Size size) {
    if (stereo) {
      _drawPeakHold(canvas, size, levelL, peakL, yFrac: 0.3, label: 'L');
      _drawPeakHold(canvas, size, levelR, peakR, yFrac: 0.7, label: 'R');
    } else {
      _drawPeakHold(canvas, size, levelL, peakL, yFrac: 0.5, label: '');
    }
  }

  void _drawPeakHold(Canvas canvas, Size size, double level, double peak,
      {required double yFrac, required String label}) {
    _drawDigitalBar(canvas, size, level, yFrac: yFrac, label: label);
    // Repère de pic
    const segs = 30;
    final y = size.height * yFrac - 12;
    final segW = (size.width - 28) / segs;
    final peakSeg = (peak * segs).round().clamp(0, segs - 1);
    canvas.drawRect(
      Rect.fromLTWH(24 + peakSeg * segW, y, segW - 1.5, 18),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _VuPainter old) => true;
}
