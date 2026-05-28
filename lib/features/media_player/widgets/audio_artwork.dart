/// @file audio_artwork.dart
/// @brief Pochette d'album animée pour la lecture audio (style VLC).

import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';

/// Pochette placeholder avec une légère rotation lente quand la lecture est active.
class AudioArtwork extends StatefulWidget {
  final String trackName;
  final bool isDark;
  final bool isPlaying;

  const AudioArtwork({
    super.key,
    required this.trackName,
    required this.isDark,
    this.isPlaying = false,
  });

  @override
  State<AudioArtwork> createState() => _AudioArtworkState();
}

class _AudioArtworkState extends State<AudioArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    if (widget.isPlaying) _rotation.repeat();
  }

  @override
  void didUpdateWidget(AudioArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!widget.isPlaying && _rotation.isAnimating) {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isDark
              ? [AppColors.darkSurface2, AppColors.accentVariant]
              : [AppColors.accent.withAlpha(30), AppColors.accent.withAlpha(80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withAlpha(50),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: RotationTransition(
        turns: _rotation,
        child: Icon(Icons.music_note_rounded, size: 80, color: AppColors.accent),
      ),
    );
  }
}
