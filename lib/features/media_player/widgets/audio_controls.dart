/// @file audio_controls.dart
/// @brief Barre de contrôle de lecture audio (progression + boutons).

import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';

/// Barre inférieure : seek, temps (avec bascule temps restant) et transport.
class AudioControls extends StatelessWidget {
  final bool isDark;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isShuffle;
  final bool isRepeat;
  final bool showRemainingTime;
  final ValueChanged<double> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback onToggleRemainingTime;

  const AudioControls({
    super.key,
    required this.isDark,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isShuffle,
    required this.isRepeat,
    required this.showRemainingTime,
    required this.onSeek,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    required this.onToggleRemainingTime,
  });

  String _fmt(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final subColor = isDark ? AppColors.darkSubtext : AppColors.lightSubtext;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    double progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    if (progress.isNaN || progress.isInfinite) progress = 0.0;

    final remaining = duration - position;
    final rightLabel = showRemainingTime
        ? '-${_fmt(remaining.inSeconds.clamp(0, duration.inSeconds))}'
        : _fmt(duration.inSeconds);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface2 : AppColors.lightSurface2,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progress,
              onChanged: onSeek,
              activeColor: AppColors.accent,
              inactiveColor: borderColor,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position.inSeconds),
                    style: Theme.of(context).textTheme.bodySmall),
                GestureDetector(
                  onTap: onToggleRemainingTime,
                  child: Text(rightLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle_rounded,
                    color: isShuffle ? AppColors.accent : subColor),
                onPressed: onToggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 32),
                onPressed: onPrevious,
              ),
              Container(
                width: 56,
                height: 56,
                decoration:
                    BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(isPlaying),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  onPressed: onPlayPause,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 32),
                onPressed: onNext,
              ),
              IconButton(
                icon: Icon(
                  isRepeat ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: isRepeat ? AppColors.accent : subColor,
                ),
                onPressed: onToggleRepeat,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
