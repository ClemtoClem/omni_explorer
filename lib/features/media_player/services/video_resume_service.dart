/// @file video_resume_service.dart
/// @brief Persistance des positions de reprise par fichier vidéo.
///
/// Mémorise la dernière position lue pour chaque chemin afin de reprendre la
/// lecture à l'endroit exact lors d'une réouverture (même après un redémarrage).
/// Les entrées sont purgées au-delà de [maxEntries] (LRU implicite via timestamp).

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class VideoResumeService {
  static const _key = 'media_player.resume_positions';
  static const int maxEntries = 200;
  // Au-delà de cette position relative, on considère la vidéo « terminée ».
  static const double finishedThreshold = 0.97;

  Map<String, _Entry> _entries = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _entries = map.map((k, v) => MapEntry(k, _Entry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {}
  }

  /// Retourne la position sauvegardée pour [path], ou null si aucune.
  Duration? positionFor(String path) {
    final e = _entries[path];
    if (e == null) return null;
    // Si la vidéo a été quasi-terminée, on reprend du début.
    if (e.duration.inMilliseconds > 0 &&
        e.position.inMilliseconds / e.duration.inMilliseconds >= finishedThreshold) {
      return null;
    }
    return e.position;
  }

  Future<void> save(String path, Duration position, Duration duration) async {
    // N'enregistre pas les positions triviales (< 5s).
    if (position.inSeconds < 5) {
      _entries.remove(path);
    } else {
      _entries[path] = _Entry(
        position: position,
        duration: duration,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    _enforceLimit();
    await _persist();
  }

  void _enforceLimit() {
    if (_entries.length <= maxEntries) return;
    final sorted = _entries.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    _entries = Map.fromEntries(sorted.take(maxEntries));
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    await _prefs!
        .setString(_key, jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))));
  }
}

class _Entry {
  final Duration position;
  final Duration duration;
  final int updatedAt;
  const _Entry({required this.position, required this.duration, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'p': position.inMilliseconds,
        'd': duration.inMilliseconds,
        't': updatedAt,
      };

  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
        position: Duration(milliseconds: j['p'] as int),
        duration: Duration(milliseconds: j['d'] as int),
        updatedAt: j['t'] as int,
      );
}
