/// @file video_player_view.dart
/// @brief Lecteur vidéo personnalisé bâti sur media_kit, avec tous les gestes
/// (double-tap zones, swipe luminosité/volume, pinch zoom, long press ×2,
/// scrub timeline + preview), les contrôles, les sous-titres déplaçables,
/// les marqueurs utilisateur, le changement de piste, la reprise persistante,
/// la pause automatique au débranchement du casque, etc.

import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:uuid/uuid.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../models/subtitle_settings.dart';
import '../models/video_marker.dart';
import '../providers/media_player_provider.dart';
import '../services/subtitle_parser.dart';
import '../services/track_preferences_service.dart';
import 'marker_editor_dialog.dart';
import 'subtitle_search_dialog.dart';
import 'subtitle_settings_sheet.dart';
import 'track_picker_sheet.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late MediaPlayerProvider _provider;

  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  final _uuid = const Uuid();

  // ── État de lecture ───────────────────────────────────────────────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _completed = false;
  Tracks _tracks = const Tracks();
  AudioTrack _audioTrack = AudioTrack.auto();
  SubtitleTrack _subtitleTrack = SubtitleTrack.auto();
  List<String> _subtitleLines = const [];

  // ── État UI ───────────────────────────────────────────────────────────────
  bool _controlsVisible = true;
  bool _scrubbing = false;
  Duration? _scrubPreview;
  Timer? _hideTimer;
  Timer? _savePositionTimer;

  // ── Index courant suivi pour détecter un changement de média ──────────────
  int _lastIndex = -1;
  String? _signature;

  // ── Subtitle entries pour la recherche (chargées à la demande) ────────────
  List<SubtitleEntry> _subEntries = const [];
  bool _subsLoaded = false;

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
  /// Position globale au début du glissement vertical (référence pour le delta).
  Offset _vDragOrigin = Offset.zero;
  /// Côté où le drag vertical a commencé (gauche = luminosité, droite = volume).
  bool _vDragOnLeft = true;
  // Vitesse précédente pour restaurer après long-press ×2.
  double _normalRate = 1.0;
  bool _holdSpeedActive = false;

  // ── Casque ─────────────────────────────────────────────────────────────────
  StreamSubscription? _becomingNoisySub;

  // ── Abonnements aux streams du player ─────────────────────────────────────
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _provider = context.read<MediaPlayerProvider>();
    _provider.addListener(_onProviderChanged);
    WakelockPlus.enable();
    VolumeController.instance.showSystemUI = false;
    _setupHeadphoneWatcher();
    _wireStreams();
    _openCurrent();
    _savePositionTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _persistResume());
  }

  /// L'app passe en arrière-plan : on persiste immédiatement la position
  /// (sinon on perd jusqu'à 5 s de progression si le système tue le process).
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
    for (final s in _subs) {
      s.cancel();
    }
    _persistResume();
    WakelockPlus.disable();
    // Pas de reset : on utilise la luminosité SYSTÈME (modifiée durablement
    // côté OS comme avec les touches matérielles).
    _player.dispose();
    super.dispose();
  }

  // ── Provider listener (changement d'index, paramètres sous-titres) ────────

  void _onProviderChanged() {
    if (!mounted) return;
    if (_provider.currentIndex != _lastIndex) {
      _openCurrent();
    } else {
      setState(() {});
    }
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  void _wireStreams() {
    final s = _player.stream;
    _subs.add(s.position.listen((p) {
      if (!_scrubbing && mounted) setState(() => _position = p);
    }));
    _subs.add(s.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(s.playing.listen((p) {
      if (mounted) {
        setState(() => _playing = p);
        if (p) {
          _scheduleHideControls();
        } else {
          _hideTimer?.cancel();
          setState(() => _controlsVisible = true);
        }
      }
    }));
    _subs.add(s.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    }));
    _subs.add(s.completed.listen((c) {
      if (mounted) {
        setState(() => _completed = c);
        if (c) _onCompleted();
      }
    }));
    _subs.add(s.tracks.listen((t) {
      if (mounted) {
        setState(() => _tracks = t);
        _applyTrackPreferences();
      }
    }));
    _subs.add(s.subtitle.listen((lines) {
      if (mounted) setState(() => _subtitleLines = lines.where((l) => l.isNotEmpty).toList());
    }));
    _subs.add(s.track.listen((t) {
      if (mounted) {
        setState(() {
          _audioTrack = t.audio;
          _subtitleTrack = t.subtitle;
        });
        _saveTrackPreferences();
      }
    }));
    _subs.add(s.rate.listen((r) {
      if (mounted && !_holdSpeedActive) _normalRate = r;
    }));
  }

  // ── Casque déconnecté → pause auto ────────────────────────────────────────

  Future<void> _setupHeadphoneWatcher() async {
    try {
      final session = await AudioSession.instance;
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (_playing) _player.pause();
      });
    } catch (_) {}
  }

  // ── Ouverture / changement de média ───────────────────────────────────────

  Future<void> _openCurrent() async {
    final path = _provider.currentPath;
    if (path == null) return;
    _lastIndex = _provider.currentIndex;
    _subsLoaded = false;
    _subEntries = const [];

    final resume = await _provider.resumePositionFor(path);
    await _player.open(Media('file://$path'), play: false);
    if (resume != null && resume > Duration.zero) {
      await _player.seek(resume);
    }
    await _player.setRate(_provider.playbackSpeed);
    await _player.play();
  }

  // ── Préférences de pistes ─────────────────────────────────────────────────

  String _trackSignature(Tracks tracks) {
    String key(AudioTrack t) => '${t.language ?? ""}|${t.title ?? ""}';
    String keyS(SubtitleTrack t) => '${t.language ?? ""}|${t.title ?? ""}';
    return TrackPreferencesService.buildSignature(
      audioKeys: tracks.audio.map(key),
      subtitleKeys: tracks.subtitle.map(keyS),
    );
  }

  Future<void> _applyTrackPreferences() async {
    if (_tracks.audio.length <= 2 && _tracks.subtitle.length <= 2) {
      // Les deux entrées par défaut (auto + no) ne sont pas significatives.
      return;
    }
    final sig = _trackSignature(_tracks);
    if (sig == _signature) return;
    _signature = sig;
    final pref = await _provider.getTrackPreference(sig);
    if (pref == null) {
      _provider.updateSubtitleSettings(const SubtitleSettings());
      return;
    }
    final audio = _tracks.audio.firstWhere(
      (t) => t.id == pref.audioTrackId ||
          (t.language != null && t.language == pref.audioTrackLanguage),
      orElse: () => _audioTrack,
    );
    final sub = _tracks.subtitle.firstWhere(
      (t) => t.id == pref.subtitleTrackId ||
          (t.language != null && t.language == pref.subtitleTrackLanguage),
      orElse: () => _subtitleTrack,
    );
    await _player.setAudioTrack(audio);
    await _player.setSubtitleTrack(sub);
    _provider.updateSubtitleSettings(pref.subtitleSettings);
  }

  Future<void> _saveTrackPreferences() async {
    final sig = _signature;
    if (sig == null) return;
    await _provider.saveTrackPreference(
      sig,
      TrackPreference(
        audioTrackId: _audioTrack.id,
        audioTrackLanguage: _audioTrack.language,
        subtitleTrackId: _subtitleTrack.id,
        subtitleTrackLanguage: _subtitleTrack.language,
        subtitleSettings: _provider.subtitleSettings,
      ),
    );
  }

  // ── Reprise persistante ───────────────────────────────────────────────────

  Future<void> _persistResume() async {
    if (_duration.inMilliseconds == 0) return;
    await _provider.saveVideoPosition(_position, _duration);
  }

  // ── Fin de lecture ────────────────────────────────────────────────────────

  void _onCompleted() {
    if (_provider.isRepeat) {
      _player.seek(Duration.zero);
      _player.play();
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

  // ── Tap & seek helpers ────────────────────────────────────────────────────

  void _seekRelative(Duration delta) {
    final target = _position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player.seek(clamped);
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
        await _player.pause();
      } else {
        await _player.play();
      }
    }
  }

  // ── Long-press ×2 ─────────────────────────────────────────────────────────

  Future<void> _startHoldSpeed() async {
    if (_holdSpeedActive) return;
    _holdSpeedActive = true;
    _normalRate = _provider.playbackSpeed;
    await _player.setRate(2.0);
    HapticFeedback.lightImpact();
    _showHud(const _Hud(icon: Icons.speed_rounded, label: '×2'));
  }

  Future<void> _endHoldSpeed() async {
    if (!_holdSpeedActive) return;
    _holdSpeedActive = false;
    await _player.setRate(_normalRate);
  }

  // ── Drag verticaux : luminosité (gauche) / volume (droite) ────────────────

  Future<void> _onVerticalDragStart(DragStartDetails d, Size size) async {
    _vDragOrigin = d.globalPosition;
    _vDragOnLeft = d.localPosition.dx < size.width / 2;
    if (_vDragOnLeft) {
      try {
        _dragStartBrightness = await ScreenBrightness.instance.system;
      } catch (_) {}
    } else {
      try {
        _dragStartVolume = await VolumeController.instance.getVolume();
      } catch (_) {}
    }
  }

  Future<void> _onVerticalDragUpdate(
      DragUpdateDetails d, Size size) async {
    // Delta cumulé depuis le DÉBUT du drag, en fraction de la hauteur visible
    // (donc indépendant de l'orientation : haut → +, bas → −).
    final delta = (_vDragOrigin.dy - d.globalPosition.dy) / size.height;
    if (_vDragOnLeft) {
      final v = (_dragStartBrightness + delta).clamp(0.0, 1.0);
      try {
        // Écrit dans Settings.System.SCREEN_BRIGHTNESS (luminosité système) :
        // s'aligne sur le curseur des paramètres et reste après fermeture.
        await ScreenBrightness.instance.setSystemScreenBrightness(v);
      } catch (_) {}
      _showVSlider(_VSlider(kind: _VSliderKind.brightness, value: v));
    } else {
      final v = (_dragStartVolume + delta).clamp(0.0, 1.0);
      try {
        // VolumeController contrôle AudioManager.STREAM_MUSIC (volume média
        // système : touches matérielles et statut système restent en phase).
        await VolumeController.instance.setVolume(v);
      } catch (_) {}
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
    final ratio = (d.globalPosition.dx - d.localPosition.dx + d.localPosition.dx) /
        size.width; // (positionneur)
    final deltaSec =
        (d.primaryDelta ?? 0) / size.width * _duration.inSeconds * 0.8;
    final target = _dragStartPosition + Duration(seconds: deltaSec.round());
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _dragStartPosition = clamped;
    setState(() => _scrubPreview = clamped);
    _showHud(_Hud(
      icon: Icons.swap_horiz_rounded,
      label: _fmt(clamped),
    ));
    // (ratio est calculé mais non utilisé : la preview suit _dragStartPosition)
    ratio.toString();
  }

  Future<void> _onHorizontalDragEnd(DragEndDetails _) async {
    if (_scrubPreview != null) {
      await _player.seek(_scrubPreview!);
    }
    setState(() {
      _scrubbing = false;
      _scrubPreview = null;
    });
  }

  // ── Navigation par chapitre/marqueur (boutons next/prev) ─────────────────

  void _onPrevButtonTap() {
    final markers = _provider.currentMarkers;
    if (markers.isEmpty) {
      _provider.skipPrevious();
      return;
    }
    final prev = markers
        .where((m) => m.position < _position - const Duration(seconds: 2))
        .toList();
    if (prev.isEmpty) {
      _player.seek(Duration.zero);
    } else {
      _player.seek(prev.last.position);
    }
  }

  void _onNextButtonTap() {
    final markers = _provider.currentMarkers;
    if (markers.isEmpty) {
      _provider.skipNext();
      return;
    }
    final next = markers.where((m) => m.position > _position).toList();
    if (next.isEmpty) {
      _provider.skipNext();
    } else {
      _player.seek(next.first.position);
    }
  }

  // ── Marqueurs ─────────────────────────────────────────────────────────────

  Future<void> _addMarkerHere() async {
    final result = await showMarkerEditorDialog(context, position: _position);
    if (result == null || result.delete) return;
    final label = result.label.isEmpty
        ? _fmt(_position)
        : result.label;
    await _provider.addMarker(VideoMarker(
      id: _uuid.v4(),
      position: _position,
      label: label,
    ));
  }

  // ── Sous-titres : ouverture du sélecteur ──────────────────────────────────

  void _openTrackPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => TrackPickerSheet(
        tracks: _tracks,
        currentAudio: _audioTrack,
        currentSubtitle: _subtitleTrack,
        onAudioSelected: (t) async {
          await _player.setAudioTrack(t);
        },
        onSubtitleSelected: (t) async {
          await _player.setSubtitleTrack(t);
        },
      ),
    );
  }

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
    final path = _provider.currentPath;
    if (path == null) return;
    if (!_subsLoaded) {
      final ext = SubtitleParser.findExternalSubtitleFor(path);
      if (ext != null) {
        try {
          _subEntries = await SubtitleParser.parseFile(ext);
        } catch (_) {}
      }
      _subsLoaded = true;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => SubtitleSearchDialog(
        entries: _subEntries,
        onSeek: _player.seek,
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

  Widget _buildExternalSubtitleButton() {
    final path = _provider.currentPath;
    if (path == null) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: Future.value(SubtitleParser.findExternalSubtitleFor(path)),
      builder: (_, snap) {
        final hasExt = snap.data != null;
        if (!hasExt) return const SizedBox.shrink();
        return IconButton(
          icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
          tooltip: 'Charger sous-titres',
          onPressed: () async {
            await _player.setSubtitleTrack(SubtitleTrack.uri(snap.data!));
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final size = c.biggest;
      return Stack(
        fit: StackFit.expand,
        children: [
          // 1. Vidéo (avec zoom InteractiveViewer)
          ColoredBox(
            color: Colors.black,
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled: false,
              child: Video(controller: _videoController, controls: NoVideoControls),
            ),
          ),
          // 2. Sous-titres (manipulables)
          if (_subtitleLines.isNotEmpty)
            VideoSubtitleOverlay(
              lines: _subtitleLines,
              settings: _provider.subtitleSettings,
              onSettingsChanged: _provider.updateSubtitleSettings,
            ),
          // 3. Couche de gestes (toujours active)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTapDown: (d) => _onDoubleTapAt(d.localPosition, size),
              onLongPressStart: (_) => _startHoldSpeed(),
              onLongPressEnd: (_) => _endHoldSpeed(),
              onVerticalDragStart: (d) => _onVerticalDragStart(d, size),
              onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, size),
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, size),
              onHorizontalDragEnd: _onHorizontalDragEnd,
            ),
          ),
          // 4. Spinner si bufferisation
          if (_buffering && !_completed)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          // 5. Replay si terminé
          if (_completed) _buildReplayOverlay(),
          // 6. HUD éphémère (seek delta, vitesse ×2…)
          if (_hud != null)
            VideoHudIndicator(icon: _hud!.icon, label: _hud!.label),
          // 6b. Slider vertical éphémère (luminosité / volume)
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
          // 7. Contrôles (top + bottom)
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
                _player.seek(Duration.zero);
                _player.play();
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
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                _provider.currentPath?.split(Platform.pathSeparator).last ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildExternalSubtitleButton(),
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              tooltip: 'Rechercher dans les sous-titres',
              onPressed: _openSubtitleSearch,
            ),
            IconButton(
              icon: const Icon(Icons.subtitles_rounded, color: Colors.white),
              tooltip: 'Pistes & sous-titres',
              onPressed: _openTrackPicker,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
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
                _menuItem('resetZoom', Icons.center_focus_strong_rounded,
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
                  _menuItem('playlist', Icons.queue_music_rounded, 'Playlist'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(
            left: 12, right: 12,
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
              onSeek: (pos) => _player.seek(pos),
              onScrubbing: (pos) {
                setState(() => _scrubPreview = pos);
              },
              onScrubbingChange: (active) =>
                  setState(() => _scrubbing = active),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(_fmt(_scrubPreview ?? _position),
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
                  const Spacer(),
                  Text(_fmt(_duration),
                      style: const TextStyle(
                          color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
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
                  onPressed: () =>
                      _playing ? _player.pause() : _player.play(),
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
                  icon: const Icon(Icons.bookmark_add_outlined,
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
                  onPressed: () => _provider.setRepeat(!_provider.isRepeat),
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
