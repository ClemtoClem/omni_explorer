/// @file playback_chips.dart
/// @brief Puces d'état (vitesse, minuteur de sommeil) façon VLC.
///
/// Affichées uniquement quand un réglage non-standard est actif. Un appui
/// sur la puce réinitialise/annule le réglage correspondant.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';

/// Rangée de puces indiquant la vitesse de lecture et le minuteur actifs.
class PlaybackChips extends StatefulWidget {
  final double speed;
  final DateTime? sleepTimerEnd;
  final VoidCallback onResetSpeed;
  final VoidCallback onCancelSleep;

  const PlaybackChips({
    super.key,
    required this.speed,
    required this.sleepTimerEnd,
    required this.onResetSpeed,
    required this.onCancelSleep,
  });

  @override
  State<PlaybackChips> createState() => _PlaybackChipsState();
}

class _PlaybackChipsState extends State<PlaybackChips> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(PlaybackChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// Rafraîchit le compte à rebours du minuteur chaque seconde.
  void _syncTicker() {
    final active = widget.sleepTimerEnd != null;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatRemaining(DateTime end) {
    final remaining = end.difference(DateTime.now());
    if (remaining.isNegative) return '0:00';
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSpeed = widget.speed != 1.0;
    final hasSleep = widget.sleepTimerEnd != null;
    if (!hasSpeed && !hasSleep) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        children: [
          if (hasSpeed)
            _Chip(
              icon: Icons.speed_rounded,
              label: '${widget.speed}x',
              onTap: widget.onResetSpeed,
            ),
          if (hasSleep)
            _Chip(
              icon: Icons.bedtime_rounded,
              label: _formatRemaining(widget.sleepTimerEnd!),
              onTap: widget.onCancelSleep,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Chip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.accent),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(width: 3),
              Icon(Icons.close_rounded, size: 13, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
