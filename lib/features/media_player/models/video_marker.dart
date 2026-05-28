/// @file video_marker.dart
/// @brief Marqueur utilisateur sur la timeline d'une vidéo.

class VideoMarker {
  final String id;
  final Duration position;
  final String label;

  const VideoMarker({
    required this.id,
    required this.position,
    required this.label,
  });

  VideoMarker copyWith({Duration? position, String? label}) => VideoMarker(
        id: id,
        position: position ?? this.position,
        label: label ?? this.label,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'positionMs': position.inMilliseconds,
        'label': label,
      };

  factory VideoMarker.fromJson(Map<String, dynamic> json) => VideoMarker(
        id: json['id'] as String,
        position: Duration(milliseconds: json['positionMs'] as int),
        label: json['label'] as String,
      );
}
