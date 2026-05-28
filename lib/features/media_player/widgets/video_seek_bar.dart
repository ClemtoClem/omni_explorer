/// @file video_seek_bar.dart
/// @brief Barre de progression vidéo avec marqueurs utilisateur, snap haptique
/// au survol d'un marqueur, et callback de prévisualisation pendant le scrub.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/app_theme.dart';
import '../models/video_marker.dart';

class VideoSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<VideoMarker> markers;
  /// Distance en pixels pour considérer qu'on est « sur » un marqueur (snap).
  final double snapPxRadius;
  final ValueChanged<Duration> onSeek;
  /// Appelé en continu pendant un drag horizontal (pour afficher la preview).
  final ValueChanged<Duration>? onScrubbing;
  /// Appelé au début / à la fin du drag pour masquer/afficher la preview.
  final ValueChanged<bool>? onScrubbingChange;

  const VideoSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.markers,
    required this.onSeek,
    this.onScrubbing,
    this.onScrubbingChange,
    this.snapPxRadius = 12,
  });

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  String? _lastSnappedId;
  Duration? _draggedPosition;
  double _lastDx = 0;

  Duration _applySnap(double dx, double width) {
    final dur = widget.duration;
    if (dur.inMilliseconds == 0) return Duration.zero;
    final ratio = (dx / width).clamp(0.0, 1.0);
    final pxPerMs = width / dur.inMilliseconds;
    for (final m in widget.markers) {
      final mDx = m.position.inMilliseconds * pxPerMs;
      if ((mDx - dx).abs() <= widget.snapPxRadius) {
        if (_lastSnappedId != m.id) {
          HapticFeedback.selectionClick();
          _lastSnappedId = m.id;
        }
        return m.position;
      }
    }
    _lastSnappedId = null;
    return Duration(milliseconds: (ratio * dur.inMilliseconds).round());
  }

  void _handleScrub(double dx, double width) {
    _lastDx = dx;
    final pos = _applySnap(dx, width);
    setState(() => _draggedPosition = pos);
    widget.onScrubbing?.call(pos);
  }

  void _commit(double dx, double width) {
    final pos = _applySnap(dx, width);
    widget.onSeek(pos);
    setState(() => _draggedPosition = null);
    widget.onScrubbingChange?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.duration;
    final pos = _draggedPosition ?? widget.position;
    final fraction =
        dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (ctx, c) {
      return SizedBox(
        height: 22,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            widget.onScrubbingChange?.call(true);
            _handleScrub(d.localPosition.dx, c.maxWidth);
          },
          onHorizontalDragUpdate: (d) =>
              _handleScrub(d.localPosition.dx, c.maxWidth),
          onHorizontalDragEnd: (_) => _commit(_lastDx, c.maxWidth),
          onTapUp: (d) => _commit(d.localPosition.dx, c.maxWidth),
          child: CustomPaint(
            painter: _SeekPainter(
              fraction: fraction,
              markers: widget.markers,
              duration: dur,
            ),
            size: Size(c.maxWidth, 22),
          ),
        ),
      );
    });
  }
}

class _SeekPainter extends CustomPainter {
  final double fraction;
  final List<VideoMarker> markers;
  final Duration duration;

  _SeekPainter({
    required this.fraction,
    required this.markers,
    required this.duration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final trackPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), trackPaint);

    final progressPaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(0, midY), Offset(size.width * fraction, midY), progressPaint);

    // Marqueurs
    if (duration.inMilliseconds > 0) {
      final markerPaint = Paint()..color = Colors.amberAccent;
      for (final m in markers) {
        final dx =
            size.width * (m.position.inMilliseconds / duration.inMilliseconds);
        canvas.drawCircle(Offset(dx, midY), 4, markerPaint);
      }
    }

    // Tête de lecture
    final thumbPaint = Paint()..color = AppColors.accent;
    canvas.drawCircle(Offset(size.width * fraction, midY), 7, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _SeekPainter old) =>
      old.fraction != fraction ||
      old.duration != duration ||
      old.markers.length != markers.length;
}
