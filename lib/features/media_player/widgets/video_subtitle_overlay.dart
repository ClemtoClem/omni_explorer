/// @file video_subtitle_overlay.dart
/// @brief Sous-titres déplaçables (drag) et redimensionnables (pinch).
///
/// Affiche les lignes de sous-titres courantes au-dessus de la vidéo. Le
/// glissement vertical déplace la position et le pinch ajuste la taille de
/// police. Les modifications remontent via [onSettingsChanged].

import 'package:flutter/material.dart';
import '../models/subtitle_settings.dart';

class VideoSubtitleOverlay extends StatefulWidget {
  final List<String> lines;
  final SubtitleSettings settings;
  final ValueChanged<SubtitleSettings> onSettingsChanged;
  final bool enableManipulation;

  const VideoSubtitleOverlay({
    super.key,
    required this.lines,
    required this.settings,
    required this.onSettingsChanged,
    this.enableManipulation = true,
  });

  @override
  State<VideoSubtitleOverlay> createState() => _VideoSubtitleOverlayState();
}

class _VideoSubtitleOverlayState extends State<VideoSubtitleOverlay> {
  double _scaleStart = 1.0;
  double _hOffsetStart = 0;
  double _vAlignStart = 0;

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStart = widget.settings.fontSize;
    _hOffsetStart = widget.settings.horizontalOffsetPx;
    _vAlignStart = widget.settings.verticalAlignment;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    SubtitleSettings s = widget.settings;
    if (d.scale != 1.0) {
      final newSize = (_scaleStart * d.scale).clamp(10.0, 48.0);
      s = s.copyWith(fontSize: newSize);
    }
    if (d.pointerCount == 1) {
      final dx = d.focalPointDelta.dx;
      final dy = d.focalPointDelta.dy;
      final newH = _hOffsetStart + dx;
      final newV =
          (_vAlignStart + dy / size.height).clamp(0.05, 0.95);
      // L'offset horizontal s'accumule pendant le drag.
      _hOffsetStart = newH;
      _vAlignStart = newV;
      s = s.copyWith(horizontalOffsetPx: newH, verticalAlignment: newV);
    }
    widget.onSettingsChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) return const SizedBox.shrink();
    final s = widget.settings;
    return LayoutBuilder(builder: (ctx, c) {
      final top = c.maxHeight * s.verticalAlignment - 40;
      final textWidget = Container(
        constraints: BoxConstraints(maxWidth: c.maxWidth * 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: s.highlightColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.lines.map((line) => _SubtitleLine(line, s)).toList(),
        ),
      );
      return Positioned.fill(
        child: IgnorePointer(
          ignoring: !widget.enableManipulation,
          child: Stack(
            children: [
              Positioned(
                top: top,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(s.horizontalOffsetPx, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onScaleStart: widget.enableManipulation ? _onScaleStart : null,
                      onScaleUpdate: widget.enableManipulation
                          ? (d) => _onScaleUpdate(d, c.biggest)
                          : null,
                      child: textWidget,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SubtitleLine extends StatelessWidget {
  final String text;
  final SubtitleSettings s;
  const _SubtitleLine(this.text, this.s);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      // Police universelle (system fallback couvre Latin, CJK, Indic via
      // platform fonts: Noto / SF / Segoe UI). En l'absence d'asset packagé,
      // s'appuyer sur fontFamily null laisse le moteur Skia choisir.
      fontSize: s.fontSize,
      color: s.textColor,
      fontWeight: FontWeight.w600,
      height: 1.25,
      shadows: s.textOutline
          ? const [
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, -1)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 0)),
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(-1, 0)),
            ]
          : null,
    );
    return Text(text, textAlign: TextAlign.center, style: base);
  }
}
