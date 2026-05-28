/// @file media_player_provider.dart
/// @brief Provider persistant pour le lecteur multimédia (style VLC).
///
/// L'AudioPlayer (just_audio) est un singleton qui survit aux navigations —
/// la musique continue en arrière-plan. Le lecteur vidéo (media_kit) est géré
/// dans VideoPlayerView qui s'occupe aussi de la persistance de la position,
/// des marqueurs et des préférences de piste (via les services injectés ici).

import 'dart:async';
import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/constants/app_constants.dart';
import '../../../core/utils/file_utils.dart';
import '../models/subtitle_settings.dart';
import '../models/video_marker.dart';
import '../models/visualizer_style.dart';
import '../services/track_preferences_service.dart';
import '../services/video_markers_service.dart';
import '../services/video_resume_service.dart';

class MediaPlayerProvider extends ChangeNotifier {
  // ── AudioPlayer singleton (ne jamais dispose sauf fermeture app) ──────────
  final AudioPlayer audioPlayer = AudioPlayer();

  // ── Playlist ──────────────────────────────────────────────────────────────
  List<String> playlist = [];
  int currentIndex = 0;

  // ── État ──────────────────────────────────────────────────────────────────
  bool isAudio = true;
  bool isPlaying = false;
  bool isRepeat = false;
  bool isShuffle = false;
  double playbackSpeed = 1.0;

  // ── Lecture automatique vidéo (enchaînement épisode suivant) ──────────────
  bool autoplay = true;

  // ── Style du visualiseur audio (persistant) ───────────────────────────────
  VisualizerStyle visualizerStyle = VisualizerStyle.spectrumBarsMono;
  static const _visualizerKey = 'media_player.visualizer_style';

  // ── Services persistants (initialisés à la demande) ───────────────────────
  final VideoResumeService _resume = VideoResumeService();
  final VideoMarkersService _markersSvc = VideoMarkersService();
  final TrackPreferencesService _trackPrefs = TrackPreferencesService();
  bool _servicesReady = false;

  // ── État dérivé du fichier courant ────────────────────────────────────────
  List<VideoMarker> currentMarkers = [];
  /// Réglages d'affichage des sous-titres pour la lecture en cours.
  SubtitleSettings subtitleSettings = const SubtitleSettings();

  // ── Sleep timer (style VLC) ───────────────────────────────────────────────
  Timer? _sleepTimer;
  DateTime? sleepTimerEnd;

  // ── Interne ───────────────────────────────────────────────────────────────
  final _random = math.Random();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<ProcessingState>? _processingSub;
  bool _audioSessionReady = false;

  bool get hasMedia => playlist.isNotEmpty;
  String? get currentPath =>
      playlist.isEmpty ? null : playlist[currentIndex];

  MediaPlayerProvider() {
    _setupListeners();
  }

  void _setupListeners() {
    _playerStateSub = audioPlayer.playerStateStream.listen((state) {
      if (isPlaying != state.playing) {
        isPlaying = state.playing;
        notifyListeners();
      }
    });
    _processingSub = audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackComplete();
    });
  }

  // ── API publique ──────────────────────────────────────────────────────────

  /// Ouvre un ou plusieurs médias et démarre la lecture.
  Future<void> openMedia(List<String> paths, {int index = 0}) async {
    if (paths.isEmpty) return;
    playlist = List<String>.from(paths);
    currentIndex = index.clamp(0, paths.length - 1);
    isAudio = _isAudioPath(playlist[currentIndex]);
    playbackSpeed = 1.0;
    await _refreshCurrentMarkers();
    notifyListeners();

    if (isAudio) {
      await _ensureAudioSession();
      await _loadCurrentTrack();
    } else {
      await audioPlayer.stop();
    }
  }

  /// Ajoute des fichiers à la playlist courante.
  Future<void> addToPlaylist(List<String> paths) async {
    if (paths.isEmpty) return;
    if (playlist.isEmpty) {
      await openMedia(paths);
      return;
    }
    final sameType = paths.where((path) => _isAudioPath(path) == isAudio);
    playlist.addAll(sameType);
    notifyListeners();
  }

  /// Ajoute un fichier à la playlist (depuis le menu contextuel).
  Future<void> addPathToPlaylist(String path) async {
    await addToPlaylist([path]);
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await audioPlayer.pause();
    } else {
      await audioPlayer.play();
    }
  }

  Future<void> skipNext() async {
    if (playlist.length <= 1) return;
    int next;
    if (isShuffle) {
      next = _random.nextInt(playlist.length);
    } else {
      next = (currentIndex + 1) % playlist.length;
    }
    currentIndex = next;
    notifyListeners();
    if (isAudio) await _loadCurrentTrack();
  }

  Future<void> skipPrevious() async {
    if (playlist.isEmpty) return;
    if (isAudio && audioPlayer.position.inSeconds > 3) {
      await audioPlayer.seek(Duration.zero);
      return;
    }
    int prev = currentIndex <= 0 ? playlist.length - 1 : currentIndex - 1;
    currentIndex = prev;
    notifyListeners();
    if (isAudio) await _loadCurrentTrack();
  }

  Future<void> seekTo(double fraction, Duration duration) async {
    final pos = Duration(
        milliseconds: (fraction * duration.inMilliseconds).toInt());
    await audioPlayer.seek(pos);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await audioPlayer.setSpeed(speed);
    notifyListeners();
  }

  void setCurrentIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex = index;
    notifyListeners();
    if (isAudio) _loadCurrentTrack();
  }

  void removeFromPlaylist(int index) {
    if (index < 0 || index >= playlist.length) return;
    playlist.removeAt(index);
    if (currentIndex >= playlist.length && currentIndex > 0) {
      currentIndex = playlist.length - 1;
    }
    notifyListeners();
  }

  void reorderPlaylist(int oldIndex, int newIndex) {
    final item = playlist.removeAt(oldIndex);
    playlist.insert(newIndex, item);
    if (currentIndex == oldIndex) {
      currentIndex = newIndex;
    } else if (currentIndex > oldIndex && currentIndex <= newIndex) {
      currentIndex--;
    } else if (currentIndex < oldIndex && currentIndex >= newIndex) {
      currentIndex++;
    }
    notifyListeners();
  }

  void setRepeat(bool value) {
    isRepeat = value;
    notifyListeners();
  }

  void setShuffle(bool value) {
    isShuffle = value;
    notifyListeners();
  }

  // ── Position de reprise vidéo (persistante, par fichier) ──────────────────

  Future<void> saveVideoPosition(Duration position, Duration duration) async {
    final path = currentPath;
    if (path == null) return;
    await _ensureServices();
    await _resume.save(path, position, duration);
  }

  /// Position à laquelle reprendre la lecture pour [path] (null si rien).
  Future<Duration?> resumePositionFor(String path) async {
    await _ensureServices();
    return _resume.positionFor(path);
  }

  void setAutoplay(bool value) {
    autoplay = value;
    notifyListeners();
  }

  // ── Marqueurs utilisateur sur la timeline ─────────────────────────────────

  Future<void> _refreshCurrentMarkers() async {
    final path = currentPath;
    if (path == null) {
      currentMarkers = const [];
      return;
    }
    await _ensureServices();
    currentMarkers = _markersSvc.markersFor(path);
  }

  Future<void> addMarker(VideoMarker marker) async {
    final path = currentPath;
    if (path == null) return;
    await _ensureServices();
    await _markersSvc.addMarker(path, marker);
    await _refreshCurrentMarkers();
    notifyListeners();
  }

  Future<void> removeMarker(String id) async {
    final path = currentPath;
    if (path == null) return;
    await _ensureServices();
    await _markersSvc.removeMarker(path, id);
    await _refreshCurrentMarkers();
    notifyListeners();
  }

  Future<void> renameMarker(String id, String newLabel) async {
    final path = currentPath;
    if (path == null) return;
    await _ensureServices();
    await _markersSvc.renameMarker(path, id, newLabel);
    await _refreshCurrentMarkers();
    notifyListeners();
  }

  // ── Préférences de pistes (par signature de série) ────────────────────────

  Future<TrackPreference?> getTrackPreference(String signature) async {
    await _ensureServices();
    return _trackPrefs.get(signature);
  }

  Future<void> saveTrackPreference(String signature, TrackPreference pref) async {
    await _ensureServices();
    await _trackPrefs.save(signature, pref);
  }

  void updateSubtitleSettings(SubtitleSettings s) {
    subtitleSettings = s;
    notifyListeners();
  }

  Future<void> _ensureServices() async {
    if (_servicesReady) return;
    await _resume.init();
    await _markersSvc.init();
    await _trackPrefs.init();
    await _loadVisualizerStyle();
    _servicesReady = true;
  }

  Future<void> _loadVisualizerStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_visualizerKey);
    if (stored == null) return;
    final match = VisualizerStyle.values
        .where((v) => v.name == stored)
        .firstOrNull;
    if (match != null) {
      visualizerStyle = match;
      notifyListeners();
    }
  }

  Future<void> setVisualizerStyle(VisualizerStyle style) async {
    if (visualizerStyle == style) return;
    visualizerStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_visualizerKey, style.name);
  }

  // ── Sleep timer (style VLC) ───────────────────────────────────────────────

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    sleepTimerEnd = DateTime.now().add(duration);
    notifyListeners();
    _sleepTimer = Timer(duration, () async {
      await audioPlayer.pause();
      sleepTimerEnd = null;
      notifyListeners();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerEnd = null;
    notifyListeners();
  }

  // ── Interne ───────────────────────────────────────────────────────────────

  Future<void> _ensureAudioSession() async {
    if (_audioSessionReady) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioSessionReady = true;
  }

  Future<void> _loadCurrentTrack() async {
    if (playlist.isEmpty) return;
    final path = playlist[currentIndex];
    try {
      // Le tag MediaItem est requis par just_audio_background (Android) pour
      // afficher la notification et poursuivre la lecture en arrière-plan.
      await audioPlayer.setAudioSource(
        AudioSource.file(
          path,
          tag: MediaItem(
            id: path,
            title: p.basenameWithoutExtension(path),
            album: p.basename(p.dirname(path)),
          ),
        ),
      );
      await audioPlayer.setSpeed(playbackSpeed);
      await audioPlayer.play();
    } catch (e) {
      debugPrint('[MediaPlayer] Erreur chargement: $e');
    }
  }

  void _onTrackComplete() {
    if (isRepeat) {
      audioPlayer.seek(Duration.zero);
      audioPlayer.play();
    } else if (currentIndex < playlist.length - 1) {
      skipNext();
    }
  }

  bool _isAudioPath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return FileUtils.detectType(ext) == FileCategory.audio;
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playerStateSub?.cancel();
    _processingSub?.cancel();
    audioPlayer.dispose();
    super.dispose();
  }
}
