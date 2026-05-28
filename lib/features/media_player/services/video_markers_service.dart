/// @file video_markers_service.dart
/// @brief Persistance des marqueurs utilisateur sur la timeline par fichier.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_marker.dart';

class VideoMarkersService {
  static const _key = 'media_player.markers';

  Map<String, List<VideoMarker>> _markers = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _markers = map.map((path, list) => MapEntry(
            path,
            (list as List)
                .map((j) => VideoMarker.fromJson(j as Map<String, dynamic>))
                .toList(),
          ));
    } catch (_) {}
  }

  List<VideoMarker> markersFor(String path) =>
      List.unmodifiable(_markers[path] ?? const []);

  Future<void> addMarker(String path, VideoMarker marker) async {
    final list = List<VideoMarker>.from(_markers[path] ?? const []);
    list.add(marker);
    list.sort((a, b) => a.position.compareTo(b.position));
    _markers[path] = list;
    await _persist();
  }

  Future<void> removeMarker(String path, String id) async {
    final list = _markers[path];
    if (list == null) return;
    final updated = list.where((m) => m.id != id).toList();
    if (updated.isEmpty) {
      _markers.remove(path);
    } else {
      _markers[path] = updated;
    }
    await _persist();
  }

  Future<void> renameMarker(String path, String id, String newLabel) async {
    final list = _markers[path];
    if (list == null) return;
    _markers[path] = list
        .map((m) => m.id == id ? m.copyWith(label: newLabel) : m)
        .toList();
    await _persist();
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    final encoded = _markers.map((path, list) =>
        MapEntry(path, list.map((m) => m.toJson()).toList()));
    await _prefs!.setString(_key, jsonEncode(encoded));
  }
}
