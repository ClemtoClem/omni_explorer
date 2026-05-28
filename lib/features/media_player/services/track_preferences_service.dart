/// @file track_preferences_service.dart
/// @brief Mémorise les choix de piste audio / sous-titres et de réglages
/// d'affichage par "signature" de série, afin de garder la même configuration
/// d'un épisode au suivant.
///
/// La signature est une chaîne dérivée des métadonnées audio/sous-titres
/// (titres et langues), normalisée. Si deux vidéos exposent les mêmes pistes,
/// elles partagent la même signature et donc les mêmes préférences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subtitle_settings.dart';

class TrackPreference {
  final String? audioTrackId;
  final String? audioTrackLanguage;
  final String? subtitleTrackId;
  final String? subtitleTrackLanguage;
  final SubtitleSettings subtitleSettings;

  const TrackPreference({
    this.audioTrackId,
    this.audioTrackLanguage,
    this.subtitleTrackId,
    this.subtitleTrackLanguage,
    this.subtitleSettings = const SubtitleSettings(),
  });

  TrackPreference copyWith({
    String? audioTrackId,
    String? audioTrackLanguage,
    String? subtitleTrackId,
    String? subtitleTrackLanguage,
    SubtitleSettings? subtitleSettings,
  }) =>
      TrackPreference(
        audioTrackId: audioTrackId ?? this.audioTrackId,
        audioTrackLanguage: audioTrackLanguage ?? this.audioTrackLanguage,
        subtitleTrackId: subtitleTrackId ?? this.subtitleTrackId,
        subtitleTrackLanguage: subtitleTrackLanguage ?? this.subtitleTrackLanguage,
        subtitleSettings: subtitleSettings ?? this.subtitleSettings,
      );

  Map<String, dynamic> toJson() => {
        'audioTrackId': audioTrackId,
        'audioTrackLanguage': audioTrackLanguage,
        'subtitleTrackId': subtitleTrackId,
        'subtitleTrackLanguage': subtitleTrackLanguage,
        'subtitleSettings': subtitleSettings.toJson(),
      };

  factory TrackPreference.fromJson(Map<String, dynamic> j) => TrackPreference(
        audioTrackId: j['audioTrackId'] as String?,
        audioTrackLanguage: j['audioTrackLanguage'] as String?,
        subtitleTrackId: j['subtitleTrackId'] as String?,
        subtitleTrackLanguage: j['subtitleTrackLanguage'] as String?,
        subtitleSettings: SubtitleSettings.fromJson(
            j['subtitleSettings'] as Map<String, dynamic>),
      );
}

class TrackPreferencesService {
  static const _key = 'media_player.track_prefs';

  Map<String, TrackPreference> _prefsMap = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _prefsMap = map.map((k, v) =>
          MapEntry(k, TrackPreference.fromJson(v as Map<String, dynamic>)));
    } catch (_) {}
  }

  TrackPreference? get(String signature) => _prefsMap[signature];

  Future<void> save(String signature, TrackPreference pref) async {
    _prefsMap[signature] = pref;
    await _persist();
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    await _prefs!.setString(
      _key,
      jsonEncode(_prefsMap.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Construit une signature à partir des listes de titres+langues des pistes
  /// disponibles. Deux vidéos d'une même série exposeront généralement les
  /// mêmes pistes (mêmes langues), d'où la même signature.
  static String buildSignature({
    required Iterable<String> audioKeys,
    required Iterable<String> subtitleKeys,
  }) {
    final audio = audioKeys.toList()..sort();
    final subs  = subtitleKeys.toList()..sort();
    return 'A:${audio.join("|")}#S:${subs.join("|")}';
  }
}
