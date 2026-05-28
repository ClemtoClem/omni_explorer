/// @file particle_visualizer.dart
/// @brief Visualiseurs à particules : artistique (rendu doux, peinture) et
/// VJing (rendu nerveux, palette saturée, traînées).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';

class ParticleVisualizer extends StatefulWidget {
  /// Niveau global 0..1 (moyenne du spectre).
  final double level;
  final bool isPlaying;
  final ParticleMode mode;

  const ParticleVisualizer({
    super.key,
    required this.level,
    required this.isPlaying,
    required this.mode,
  });

  @override
  State<ParticleVisualizer> createState() => _ParticleVisualizerState();
}

class _ParticleVisualizerState extends State<ParticleVisualizer> {
  final _particles = <_Particle>[];
  final _rng = math.Random();
  DateTime _last = DateTime.now();

  void _spawn(Size size) {
    final n = widget.mode == ParticleMode.vj ? 4 : 2;
    for (int i = 0; i < n; i++) {
      _particles.add(_Particle(
        pos: Offset(size.width / 2 + (_rng.nextDouble() - 0.5) * 20,
            size.height / 2 + (_rng.nextDouble() - 0.5) * 20),
        vel: Offset((_rng.nextDouble() - 0.5) * 4,
            (_rng.nextDouble() - 0.5) * 4),
        life: 1.0,
        hue: _rng.nextDouble() * 360,
        size: 2 + _rng.nextDouble() * 4,
      ));
    }
  }

  void _step(Size size) {
    final now = DateTime.now();
    final dt = now.difference(_last).inMilliseconds / 16.66; // ~frames
    _last = now;
    final boost = (widget.isPlaying ? widget.level : 0.05) *
        (widget.mode == ParticleMode.vj ? 8 : 4);
    for (final p in _particles) {
      p.pos += p.vel * dt * (1 + boost);
      p.life -= 0.012 * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
    if (widget.isPlaying) _spawn(size);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 160,
      child: LayoutBuilder(
        builder: (ctx, c) {
          _step(c.biggest);
          return CustomPaint(
            painter: _ParticlePainter(
              particles: List.of(_particles),
              mode: widget.mode,
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  Offset pos;
  final Offset vel;
  double life;
  final double hue;
  final double size;
  _Particle({
    required this.pos,
    required this.vel,
    required this.life,
    required this.hue,
    required this.size,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final ParticleMode mode;
  _ParticlePainter({required this.particles, required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == ParticleMode.vj) {
      // Fond noir, palette saturée, traînée par addition.
      canvas.drawRect(Offset.zero & size,
          Paint()..color = Colors.black);
    }
    for (final p in particles) {
      final color = HSLColor.fromAHSL(
        p.life.clamp(0.0, 1.0),
        p.hue,
        mode == ParticleMode.vj ? 0.95 : 0.55,
        mode == ParticleMode.vj ? 0.6 : 0.7,
      ).toColor();
      final paint = Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          mode == ParticleMode.vj ? 1 : 3,
        );
      canvas.drawCircle(p.pos, p.size, paint);
      if (mode == ParticleMode.vj) {
        // Petite traînée
        canvas.drawLine(
          p.pos,
          p.pos - p.vel * 3,
          Paint()
            ..color = color.withValues(alpha: p.life * 0.4)
            ..strokeWidth = p.size * 0.8,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}
