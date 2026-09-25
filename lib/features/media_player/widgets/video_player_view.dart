import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:uuid/uuid.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../models/video_marker.dart';
import '../providers/media_player_provider.dart';
import '../services/subtitle_parser.dart';
import 'marker_editor_dialog.dart';
import 'subtitle_search_dialog.dart';
import 'subtitle_settings_sheet.dart';
import 'vertical_value_slider.dart';
import 'video_indicator_overlay.dart';
import 'video_seek_bar.dart';
import 'video_subtitle_overlay.dart';

class VideoPlayerView extends StatefulWidget {
  final VoidCallback? onTogglePlaylist;
  const VideoPlayerView({super.key, this.onTogglePlaylist});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  late MediaPlayerProvider _provider;

  VideoPlayerController? _controller;
  final _uuid = const Uuid();

  // ── État de lecture ───────────────────────────────────────────────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _completed = false;
  bool _completionHandled = false;
  double _currentSpeed = 1.0;

  // ── Sous-titres ───────────────────────────────────────────────────────────
  List<SubtitleEntry> _subEntries = const [];
  List<String> _subtitleLines = const [];

  // ── État UI ───────────────────────────────────────────────────────────────
  bool _controlsVisible = true;
  bool _scrubbing = false;
  Duration? _scrubPreview;
  Timer? _hideTimer;
  Timer? _savePositionTimer;

  int _lastIndex = -1;

  // ── Indicateurs HUD éphémères ─────────────────────────────────────────────
  _Hud? _hud;
  Timer? _hudTimer;
  _VSlider? _vSlider;
  Timer? _vSliderTimer;

  // ── Zoom / pan ────────────────────────────────────────────────────────────
  final TransformationController _zoom = TransformationController();

  // ── Gestes ────────────────────────────────────────────────────────────────
  double _dragStartBrightness = 0.5;
  double _dragStartVolume = 0.5;
  Duration _dragStartPosition = Duration.zero;
  Offset _vDragOrigin = Offset.zero;
  bool _vDragOnLeft = true;
  double _normalRate = 1.0;
  bool _holdSpeedActive = false;

  // ── Casque ─────────────────────────────────────────────────────────────────
  StreamSubscription? _becomingNoisySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _provider = context.read<MediaPlayerProvider>();
    _provider.addListener(_onProviderChanged);
    WakelockPlus.enable();
    VolumeController.instance.showSystemUI = false;
    _setupHeadphoneWatcher();
    _openCurrent();
    _savePositionTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _persistResume());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_onProviderChanged);
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _vSliderTimer?.cancel();
    _savePositionTimer?.cancel();
    _becomingNoisySub?.cancel();
    _persistResume();
    WakelockPlus.disable();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _zoom.dispose();
    super.dispose();
  }

  // ── Provider listener ─────────────────────────────────────────────────────

  void _onProviderChanged() {
    if (!mounted) return;
    if (_provider.currentIndex != _lastIndex) {
      _openCurrent();
    } else {
      if (!_holdSpeedActive) {
        final speed = _provider.playbackSpeed;
        if (speed != _currentSpeed) {
          _currentSpeed = speed;
          _controller?.setPlaybackSpeed(speed);
        }
      }
      setState(() {});
    }
  }

  // ── Listener VideoPlayerController ────────────────────────────────────────

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final v = _controller!.value;

    final pos = v.position;
    final dur = v.duration;
    final playing = v.isPlaying;
    final buffering = v.isBuffering;
    final lines = _currentSubtitleLines(pos);

    bool fireCompleted = false;
    if (!_completionHandled &&
        dur > Duration.zero &&
        pos >= dur &&
        !playing) {
      _completionHandled = true;
      fireCompleted = true;
    }

    setState(() {
      if (!_scrubbing) _position = pos;
      _duration = dur;
      _playing = playing;
      _buffering = buffering;
      _subtitleLines = lines;
      if (fireCompleted) _completed = true;
    });

    if (fireCompleted) _onCompleted();

    if (playing) {
      _scheduleHideControls();
    } else if (!_scrubbing) {
      _hideTimer?.cancel();
      if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    }
  }

  List<String> _currentSubtitleLines(Duration pos) {
    for (final e in _subEntries) {
      if (pos >= e.start && pos <= e.end) return [e.text];
    }
    return const [];
  }

  // ── Casque déconnecté → pause auto ────────────────────────────────────────

  Future<void> _setupHeadphoneWatcher() async {
    try {
      final session = await AudioSession.instance;
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (_playing) _controller?.pause();
      });
    } catch (_) {}
  }

  // ── Ouverture / changement de média ───────────────────────────────────────

  Future<void> _openCurrent() async {
    final path = _provider.currentPath;
    if (path == null) return;
    _lastIndex = _provider.currentIndex;

    // Libère l'ancien contrôleur
    _controller?.removeListener(_onControllerUpdate);
    final old = _controller;
    _controller = null;

    if (mounted) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _playing = false;
        _buffering = true;
        _completed = false;
        _completionHandled = false;
        _subtitleLines = const [];
        _subEntries = const [];
      });
    }

    await old?.dispose();

    // Charge les sous-titres externes (.srt / .vtt)
    final subPath = SubtitleParser.findExternalSubtitleFor(path);
    if (subPath != null) {
      try {
        final entries = await SubtitleParser.parseFile(subPath);
        if (mounted) setState(() => _subEntries = entries);
      } catch (_) {}
    }

    final resume = await _provider.resumePositionFor(path);

    final ctrl = VideoPlayerController.file(File(path));
    if (!mounted) { ctrl.dispose(); return; }
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } catch (e) {
      debugPrint('[VideoPlayer] init: $e');
      if (mounted) setState(() => _buffering = false);
      return;
    }

    if (!mounted) { ctrl.dispose(); return; }

    ctrl.addListener(_onControllerUpdate);
    await ctrl.setPlaybackSpeed(_currentSpeed);

    final dur = ctrl.value.duration;
    if (resume != null && resume > Duration.zero &&
        resume < dur - const Duration(seconds: 5)) {
      await ctrl.seekTo(resume);
    }

    await ctrl.play();
  }

  // ── Reprise persistante ───────────────────────────────────────────────────

  Future<void> _persistResume() async {
    if (_duration.inMilliseconds == 0) return;
    await _provider.saveVideoPosition(_position, _duration);
  }

  // ── Fin de lecture ────────────────────────────────────────────────────────

  void _onCompleted() {
    if (_provider.isRepeat) {
      _controller?.seekTo(Duration.zero);
      _controller?.play();
      setState(() { _completed = false; _completionHandled = false; });
      return;
    }
    if (_provider.autoplay &&
        _provider.currentIndex < _provider.playlist.length - 1) {
      _provider.skipNext();
    }
  }

  // ── HUD ───────────────────────────────────────────────────────────────────

  void _showHud(_Hud hud) {
    setState(() => _hud = hud);
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  // ── Visibilité des contrôles ──────────────────────────────────────────────

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_scrubbing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  // ── Seek helpers ──────────────────────────────────────────────────────────

  void _seekRelative(Duration delta) {
    if (_controller == null) return;
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _controller!.seekTo(clamped);
    _showHud(_Hud(
      icon: delta.isNegative
          ? Icons.fast_rewind_rounded
          : Icons.fast_forward_rounded,
      label: '${delta.isNegative ? "-" : "+"}${delta.inSeconds.abs()}s',
    ));
  }

  Future<void> _onDoubleTapAt(Offset pos, Size size) async {
    if (pos.dx < size.width * 0.33) {
      _seekRelative(const Duration(seconds: -10));
    } else if (pos.dx > size.width * 0.66) {
      _seekRelative(const Duration(seconds: 10));
    } else {
      if (_playing) {
        await _controller?.pause();
      } else {
        await _controller?.play();
      }
    }
  }

  // ── Long-press ×2 ─────────────────────────────────────────────────────────

  Future<void> _startHoldSpeed() async {
    if (_holdSpeedActive || _controller == null) return;
    _holdSpeedActive = true;
    _normalRate = _currentSpeed;
    await _controller!.setPlaybackSpeed(2.0);
    HapticFeedback.lightImpact();
    _showHud(const _Hud(icon: Icons.speed_rounded, label: '×2'));
  }

  Future<void> _endHoldSpeed() async {
    if (!_holdSpeedActive || _controller == null) return;
    _holdSpeedActive = false;
    await _controller!.setPlaybackSpeed(_normalRate);
  }

  // ── Drag verticaux : luminosité / volume ──────────────────────────────────

  Future<void> _onVerticalDragStart(DragStartDetails d, Size size) async {
    _vDragOrigin = d.globalPosition;
    _vDragOnLeft = d.localPosition.dx < size.width / 2;
    if (_vDragOnLeft) {
      try { _dragStartBrightness = await ScreenBrightness.instance.system; }
      catch (_) {}
    } else {
      try { _dragStartVolume = await VolumeController.instance.getVolume(); }
      catch (_) {}
    }
  }

  Future<void> _onVerticalDragUpdate(DragUpdateDetails d, Size size) async {
    final delta = (_vDragOrigin.dy - d.globalPosition.dy) / size.height;
    if (_vDragOnLeft) {
      final v = (_dragStartBrightness + delta).clamp(0.0, 1.0);
      try { await ScreenBrightness.instance.setSystemScreenBrightness(v); }
      catch (_) {}
      _showVSlider(_VSlider(kind: _VSliderKind.brightness, value: v));
    } else {
      final v = (_dragStartVolume + delta).clamp(0.0, 1.0);
      try { await VolumeController.instance.setVolume(v); }
      catch (_) {}
      _showVSlider(_VSlider(kind: _VSliderKind.volume, value: v));
    }
  }

  void _showVSlider(_VSlider s) {
    setState(() => _vSlider = s);
    _vSliderTimer?.cancel();
    _vSliderTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _vSlider = null);
    });
  }

  // ── Drag horizontal : seek avec preview ───────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartPosition = _position;
    setState(() => _scrubbing = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, Size size) {
    final deltaSec =
        (d.primaryDelta ?? 0) / size.width * _duration.inSeconds * 0.8;
    final target =
        _dragStartPosition + Duration(seconds: deltaSec.round());
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _dragStartPosition = clamped;
    setState(() => _scrubPreview = clamped);
    _showHud(_Hud(icon: Icons.swap_horiz_rounded, label: _fmt(clamped)));
  }

  Future<void> _onHorizontalDragEnd(DragEndDetails _) async {
    if (_scrubPreview != null) await _controller?.seekTo(_scrubPreview!);
    setState(() { _scrubbing = false; _scrubPreview = null; });
  }

  // ── Navigation par marqueur ───────────────────────────────────────────────

  void _onPrevButtonTap() {
    final markers = _provider.currentMarkers;
    if (markers.isEmpty) { _provider.skipPrevious(); return; }
    final prev = markers
        .where((m) => m.position < _position - const Duration(seconds: 2))
        .toList();
    if (prev.isEmpty) {
      _controller?.seekTo(Duration.zero);
    } else {
      _controller?.seekTo(prev.last.position);
    }
  }

  void _onNextButtonTap() {
    final markers = _provider.currentMarkers;
    if (markers.isEmpty) { _provider.skipNext(); return; }
    final next = markers.where((m) => m.position > _position).toList();
    if (next.isEmpty) {
      _provider.skipNext();
    } else {
      _controller?.seekTo(next.first.position);
    }
  }

  // ── Marqueurs ─────────────────────────────────────────────────────────────

  Future<void> _addMarkerHere() async {
    final result =
        await showMarkerEditorDialog(context, position: _position);
    if (result == null || result.delete) return;
    final label =
        result.label.isEmpty ? _fmt(_position) : result.label;
    await _provider.addMarker(VideoMarker(
      id: _uuid.v4(),
      position: _position,
      label: label,
    ));
  }

  // ── Sous-titres ───────────────────────────────────────────────────────────

  void _openSubtitleSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SubtitleSettingsSheet(
        settings: _provider.subtitleSettings,
        onChanged: _provider.updateSubtitleSettings,
      ),
    );
  }

  Future<void> _openSubtitleSearch() async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => SubtitleSearchDialog(
        entries: _subEntries,
        onSeek: (pos) => _controller?.seekTo(pos),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final size = c.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          // 1. Vidéo
          ColoredBox(
            color: Colors.black,
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: false,
              child: _controller != null &&
                      _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const SizedBox.expand(),
            ),
          ),
          // 2. Sous-titres
          if (_subtitleLines.isNotEmpty)
            VideoSubtitleOverlay(
              lines: _subtitleLines,
              settings: _provider.subtitleSettings,
              onSettingsChanged: _provider.updateSubtitleSettings,
            ),
          // 3. Couche de gestes
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTapDown: (d) =>
                  _onDoubleTapAt(d.localPosition, size),
              onLongPressStart: (_) => _startHoldSpeed(),
              onLongPressEnd: (_) => _endHoldSpeed(),
              onVerticalDragStart: (d) =>
                  _onVerticalDragStart(d, size),
              onVerticalDragUpdate: (d) =>
                  _onVerticalDragUpdate(d, size),
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: (d) =>
                  _onHorizontalDragUpdate(d, size),
              onHorizontalDragEnd: _onHorizontalDragEnd,
            ),
          ),
          // 4. Spinner si bufferisation
          if (_buffering && !_completed)
            const Center(
              child:
                  CircularProgressIndicator(color: Colors.white),
            ),
          // 5. Replay si terminé
          if (_completed) _buildReplayOverlay(),
          // 6. HUD éphémère
          if (_hud != null)
            VideoHudIndicator(icon: _hud!.icon, label: _hud!.label),
          // 6b. Slider vertical éphémère
          if (_vSlider != null)
            VerticalValueSlider(
              topIcon: _vSlider!.kind == _VSliderKind.brightness
                  ? Icons.wb_sunny_rounded
                  : Icons.volume_up_rounded,
              bottomIcon: _vSlider!.kind == _VSliderKind.brightness
                  ? Icons.nightlight_round
                  : Icons.volume_off_rounded,
              value: _vSlider!.value,
              alignment: _vSlider!.kind == _VSliderKind.brightness
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              fillColor: _vSlider!.kind == _VSliderKind.brightness
                  ? Colors.amberAccent
                  : Colors.lightBlueAccent,
            ),
          // 7. Contrôles
          if (_controlsVisible) ...[
            _buildTopBar(),
            _buildBottomBar(),
          ],
        ],
      );
    });
  }

  Widget _buildReplayOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 64,
              icon: const Icon(Icons.replay_rounded, color: Colors.white),
              onPressed: () {
                _controller?.seekTo(Duration.zero);
                _controller?.play();
                setState(() {
                  _completed = false;
                  _completionHandled = false;
                });
              },
            ),
            const Text('Rejouer',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            if (_provider.currentIndex < _provider.playlist.length - 1)
              FilledButton.icon(
                onPressed: () => _provider.skipNext(),
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Vidéo suivante'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4, right: 4, bottom: 4),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                _provider.currentPath
                        ?.split(Platform.pathSeparator)
                        .last ??
                    '',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_subEntries.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.search_rounded,
                    color: Colors.white),
                tooltip: 'Rechercher dans les sous-titres',
                onPressed: _openSubtitleSearch,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white),
              color: Colors.black87,
              onSelected: (v) {
                switch (v) {
                  case 'subSettings':
                    _openSubtitleSettings();
                    break;
                  case 'addMarker':
                    _addMarkerHere();
                    break;
                  case 'autoplay':
                    _provider.setAutoplay(!_provider.autoplay);
                    break;
                  case 'shuffle':
                    _provider.setShuffle(!_provider.isShuffle);
                    break;
                  case 'loop':
                    _provider.setRepeat(!_provider.isRepeat);
                    break;
                  case 'playlist':
                    widget.onTogglePlaylist?.call();
                    break;
                  case 'resetZoom':
                    _zoom.value = Matrix4.identity();
                    break;
                }
              },
              itemBuilder: (_) => [
                _menuItem('addMarker', Icons.bookmark_add_rounded,
                    'Ajouter un marqueur'),
                _menuItem('subSettings', Icons.tune_rounded,
                    'Réglages sous-titres'),
                _menuItem(
                    'resetZoom',
                    Icons.center_focus_strong_rounded,
                    'Réinitialiser le zoom'),
                _menuItem(
                    'autoplay',
                    _provider.autoplay
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_outlined,
                    'Lecture auto : ${_provider.autoplay ? "ON" : "OFF"}'),
                _menuItem(
                    'shuffle',
                    _provider.isShuffle
                        ? Icons.shuffle_on_rounded
                        : Icons.shuffle_rounded,
                    'Aléatoire : ${_provider.isShuffle ? "ON" : "OFF"}'),
                _menuItem(
                    'loop',
                    _provider.isRepeat
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    'Boucle : ${_provider.isRepeat ? "ON" : "OFF"}'),
                if (widget.onTogglePlaylist != null)
                  _menuItem('playlist', Icons.queue_music_rounded,
                      'Playlist'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VideoSeekBar(
              position: _scrubPreview ?? _position,
              duration: _duration,
              markers: _provider.currentMarkers,
              onSeek: (pos) => _controller?.seekTo(pos),
              onScrubbing: (pos) =>
                  setState(() => _scrubPreview = pos),
              onScrubbingChange: (active) =>
                  setState(() => _scrubbing = active),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    _fmt(_scrubPreview ?? _position),
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(_duration),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _onPrevButtonTap,
                  onDoubleTap: () => _provider.skipPrevious(),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.skip_previous_rounded,
                        color: Colors.white, size: 30),
                  ),
                ),
                IconButton(
                  iconSize: 44,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_rounded
                        : Icons.play_circle_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => _playing
                      ? _controller?.pause()
                      : _controller?.play(),
                ),
                GestureDetector(
                  onTap: _onNextButtonTap,
                  onDoubleTap: () => _provider.skipNext(),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.skip_next_rounded,
                        color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(
                      Icons.bookmark_add_outlined,
                      color: Colors.white),
                  tooltip: 'Marqueur',
                  onPressed: _addMarkerHere,
                ),
                IconButton(
                  icon: Icon(
                    _provider.isRepeat
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: _provider.isRepeat
                        ? AppColors.accent
                        : Colors.white,
                  ),
                  onPressed: () =>
                      _provider.setRepeat(!_provider.isRepeat),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Hud {
  final IconData icon;
  final String label;
  const _Hud({required this.icon, required this.label});
}

enum _VSliderKind { brightness, volume }

class _VSlider {
  final _VSliderKind kind;
  final double value;
  const _VSlider({required this.kind, required this.value});
}
