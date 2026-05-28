/// @file media_player_screen.dart
/// @brief Lecteur multimédia style VLC.
///
/// - Audio : lecture en arrière-plan via MediaPlayerProvider (AudioPlayer singleton)
/// - Vidéo : wakelock activé, position sauvegardée au retour dans l'explorateur
/// - Playlist persistante avec glisser-déposer pour réordonner
/// - Vitesse de lecture (0.5x → 2x) et minuteur de sommeil
/// - Bascule temps restant / durée totale
/// - Visualiseur spectral animé (audio)

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omni_explorer/core/utils/system_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/settings_service.dart';
import '../providers/media_player_provider.dart';
import '../widgets/audio_artwork.dart';
import '../widgets/audio_controls.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/media_playlist_panel.dart';
import '../widgets/playback_chips.dart';
import '../widgets/visualizer_picker_sheet.dart';
import '../widgets/video_player_view.dart';

/// Écran du lecteur multimédia.
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({super.key});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen>
    with TickerProviderStateMixin {

  late MediaPlayerProvider _provider;

  // ── Position / Durée (flux locaux pour fluidité) ──────────────────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>?  _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  // ── UI ────────────────────────────────────────────────────────────────────
  bool _showPlaylist = false;
  bool _showRemainingTime = false;

  // ── Visualiseur audio ─────────────────────────────────────────────────────
  late AnimationController _visualizerCtrl;
  static const int _barCount = 32;
  static const int _waveCount = 256;
  final _rng = math.Random();
  List<double> _barHeights  = List.filled(_barCount, 0.1);
  final List<double> _barHeightsR = List.filled(_barCount, 0.1);
  final List<double> _waveformL   = List.filled(_waveCount, 0.0);
  final List<double> _waveformR   = List.filled(_waveCount, 0.0);
  double _vizLevel = 0;
  double _vizPhase = 0;

  // ─── InitState ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _provider = context.read<MediaPlayerProvider>();
    _provider.addListener(_onProviderChanged);
    SystemUI.hideBottomBar();

    final path = _provider.currentPath;
    if (path != null) {
      context.read<SettingsService>().addRecentFile(path);
    }

    _initVisualizer();

    if (_provider.isAudio) {
      _initAudioStreams();
    }
    // Vidéo : géré par VideoPlayerView (créé dans build).
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _visualizerCtrl.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();

    super.dispose();
  }

  // ─── Listener provider ────────────────────────────────────────────────────

  void _onProviderChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ─── Initialisation audio ─────────────────────────────────────────────────

  void _initAudioStreams() {
    // Reprend l'état courant : si l'audio joue déjà (ouvert avant le push),
    // le visualiseur doit démarrer immédiatement sans attendre un évènement.
    _position = _provider.audioPlayer.position;
    _duration = _provider.audioPlayer.duration ?? Duration.zero;
    if (_provider.isPlaying) _visualizerCtrl.repeat();

    _posSub = _provider.audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durSub = _provider.audioPlayer.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });
    _stateSub = _provider.audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        if (!_visualizerCtrl.isAnimating) _visualizerCtrl.repeat();
        _updateVisualizerBars();
      } else {
        _visualizerCtrl.stop();
      }
      setState(() {});
    });
  }

  // ─── Visualiseur ──────────────────────────────────────────────────────────

  void _initVisualizer() {
    _visualizerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _barHeights = List.generate(
        _barCount, (i) => 0.05 + math.sin(i * math.pi / _barCount) * 0.3);

    _visualizerCtrl.addListener(() {
      if (_provider.isPlaying && mounted) setState(() => _updateVisualizerBars());
    });
  }

  void _updateVisualizerBars() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = now * 0.001;
    _vizPhase = t;
    double total = 0;
    for (int i = 0; i < _barCount; i++) {
      final freq       = (i + 1) / _barCount;
      final timeOffset = t + i * 0.3;
      final baseWave   = math.sin(timeOffset * 2.5 + i * 0.5) * 0.3;
      final midWave    = math.sin(timeOffset * 4.0 + i * 0.8) * 0.2;
      final noise      = (_rng.nextDouble() - 0.5) * 0.1;
      final spectral   = math.exp(-math.pow((freq - 0.4) * 3, 2));
      final v = (0.05 + (baseWave + midWave + noise) * spectral + spectral * 0.4)
          .clamp(0.03, 1.0);
      _barHeights[i] = v;
      // Décalage de phase pour le canal droit (stéréo simulée).
      final baseR  = math.sin(timeOffset * 2.5 + i * 0.5 + 0.9) * 0.3;
      final midR   = math.sin(timeOffset * 4.0 + i * 0.8 + 0.4) * 0.2;
      _barHeightsR[i] =
          (0.05 + (baseR + midR + noise * 0.6) * spectral + spectral * 0.4)
              .clamp(0.03, 1.0);
      total += v * v;
    }
    _vizLevel = math.sqrt(total / _barCount);

    // Waveform : composite de quelques sinusoïdes modulées par le niveau.
    for (int i = 0; i < _waveCount; i++) {
      final x = i / _waveCount;
      final s1 = math.sin(2 * math.pi * (x * 6 + t * 1.3));
      final s2 = math.sin(2 * math.pi * (x * 14 + t * 0.6)) * 0.5;
      final s3 = math.sin(2 * math.pi * (x * 27 + t * 0.4)) * 0.25;
      final amp = 0.45 + _vizLevel * 0.55;
      _waveformL[i] = ((s1 + s2 + s3) / 1.75) * amp;
      // Canal R : même mélange, déphasé.
      final r1 = math.sin(2 * math.pi * (x * 6 + t * 1.3 + 0.18));
      final r2 = math.sin(2 * math.pi * (x * 14 + t * 0.6 + 0.07)) * 0.5;
      final r3 = math.sin(2 * math.pi * (x * 27 + t * 0.4 + 0.03)) * 0.25;
      _waveformR[i] = ((r1 + r2 + r3) / 1.75) * amp;
    }
  }

  // ─── Contrôles ────────────────────────────────────────────────────────────

  Future<void> _togglePlayPause() async => _provider.togglePlayPause();

  Future<void> _skipNext() async => _provider.skipNext();

  Future<void> _skipPrevious() async => _provider.skipPrevious();

  Future<void> _seekTo(double value) async =>
      _provider.seekTo(value, _duration);

  Future<void> _setSpeed(double speed) async =>
      _provider.setPlaybackSpeed(speed);

  void _onSelectTrack(int idx) {
    if (idx == _provider.currentIndex) return;
    _provider.setCurrentIndex(idx);
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showSleepTimerDialog() {
    showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Arrêt automatique'),
        children: [
          for (final minutes in [5, 10, 15, 30, 45, 60])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, minutes),
              child: Text('$minutes minutes'),
            ),
          if (_provider.sleepTimerEnd != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Annuler le minuteur',
                  style: TextStyle(color: AppColors.error)),
            ),
        ],
      ),
    ).then((minutes) {
      if (minutes == null) return;
      if (minutes == 0) {
        _provider.cancelSleepTimer();
      } else {
        _provider.setSleepTimer(Duration(minutes: minutes));
      }
    });
  }

  void _showSpeedDialog() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showDialog<double>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Vitesse de lecture'),
        children: speeds
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Row(children: [
                    if (_provider.playbackSpeed == s)
                      Icon(Icons.check_rounded, size: 18, color: AppColors.accent)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text('${s}x',
                        style: TextStyle(
                            color: _provider.playbackSpeed == s
                                ? AppColors.accent
                                : null)),
                  ]),
                ))
            .toList(),
      ),
    ).then((speed) {
      if (speed != null) _setSpeed(speed);
    });
  }

  void _showVisualizerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VisualizerPickerSheet(
        current: _provider.visualizerStyle,
        onSelected: _provider.setVisualizerStyle,
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String get _currentTrackName {
    if (_provider.playlist.isEmpty) return 'Média';
    return p.basenameWithoutExtension(_provider.playlist[_provider.currentIndex]);
  }

  String get _currentExt {
    if (_provider.playlist.isEmpty) return '';
    return p.extension(_provider.playlist[_provider.currentIndex])
        .toUpperCase()
        .replaceFirst('.', '');
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final hasSleep = _provider.sleepTimerEnd != null;
    final speedActive = _provider.playbackSpeed != 1.0;

    return Scaffold(
      backgroundColor: _provider.isAudio ? bgColor : Colors.black,
      appBar: _provider.isAudio
          ? AppBar(
              title: Text(_currentTrackName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.graphic_eq_rounded),
                  tooltip: 'Visualiseur',
                  onPressed: _showVisualizerPicker,
                ),
                IconButton(
                  icon: Icon(Icons.bedtime_outlined,
                      color: hasSleep ? AppColors.accent : null),
                  tooltip: 'Arrêt automatique',
                  onPressed: _showSleepTimerDialog,
                ),
                TextButton(
                  onPressed: _showSpeedDialog,
                  child: Text(
                    speedActive ? '${_provider.playbackSpeed}x' : '1×',
                    style: TextStyle(color: speedActive ? AppColors.accent : null),
                  ),
                ),
                if (_provider.playlist.length > 1)
                  IconButton(
                    icon: Icon(_showPlaylist
                        ? Icons.queue_music_rounded
                        : Icons.queue_music_outlined),
                    onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
                    tooltip: 'Playlist',
                  ),
              ],
            )
          : null,
      body: _provider.isAudio ? _buildAudioPlayer(isDark) : _buildVideoPlayer(),
    );
  }

  // ─── Lecteur Audio ────────────────────────────────────────────────────────

  Widget _buildAudioPlayer(bool isDark) {
    return Column(
      children: [
        PlaybackChips(
          speed: _provider.playbackSpeed,
          sleepTimerEnd: _provider.sleepTimerEnd,
          onResetSpeed: () => _setSpeed(1.0),
          onCancelSleep: _provider.cancelSleepTimer,
        ),
        Expanded(
          child: _showPlaylist
              ? MediaPlaylistPanel(
                  paths: _provider.playlist,
                  currentIndex: _provider.currentIndex,
                  onReorder: _provider.reorderPlaylist,
                  onRemove: _provider.removeFromPlaylist,
                  onSelect: _onSelectTrack,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AudioArtwork(
                        trackName: _currentTrackName,
                        isDark: isDark,
                        isPlaying: _provider.isPlaying,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(_currentTrackName,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_currentExt,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.xl),
                      GestureDetector(
                        onLongPress: _showVisualizerPicker,
                        child: AudioVisualizer(
                          magnitudesL: _barHeights,
                          magnitudesR: _barHeightsR,
                          waveformL: _waveformL,
                          waveformR: _waveformR,
                          isPlaying: _provider.isPlaying,
                          phase: _vizPhase,
                          level: _vizLevel,
                          style: _provider.visualizerStyle,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        AudioControls(
          isDark: isDark,
          position: _position,
          duration: _duration,
          isPlaying: _provider.isPlaying,
          isShuffle: _provider.isShuffle,
          isRepeat: _provider.isRepeat,
          showRemainingTime: _showRemainingTime,
          onSeek: _seekTo,
          onPlayPause: _togglePlayPause,
          onNext: _skipNext,
          onPrevious: _skipPrevious,
          onToggleShuffle: () => _provider.setShuffle(!_provider.isShuffle),
          onToggleRepeat: () => _provider.setRepeat(!_provider.isRepeat),
          onToggleRemainingTime: () =>
              setState(() => _showRemainingTime = !_showRemainingTime),
        ),
      ],
    );
  }

  // ─── Lecteur Vidéo ────────────────────────────────────────────────────────

  Widget _buildVideoPlayer() {
    return Column(
      children: [
        Expanded(
          child: VideoPlayerView(
            onTogglePlaylist: () =>
                setState(() => _showPlaylist = !_showPlaylist),
          ),
        ),
        if (_showPlaylist)
          SizedBox(
            height: 240,
            child: MediaPlaylistPanel(
              paths: _provider.playlist,
              currentIndex: _provider.currentIndex,
              onReorder: _provider.reorderPlaylist,
              onRemove: _provider.removeFromPlaylist,
              onSelect: _onSelectTrack,
            ),
          ),
      ],
    );
  }
}
