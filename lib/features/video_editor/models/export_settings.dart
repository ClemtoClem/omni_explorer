/// @file export_settings.dart
/// @brief Réglages d'export vidéo : qualité (résolution / fps / débit),
/// régulation thermique (threads, accélération matérielle) et filtres
/// vidéo/audio appliqués au clip.

/// Résolution maximale de sortie (la hauteur est plafonnée, l'aspect conservé).
enum ExportResolution {
  original(0, 'Originale'),
  p480(480, '480p'),
  p720(720, '720p (HD)'),
  p1080(1080, '1080p (Full HD)');

  const ExportResolution(this.maxHeight, this.label);
  final int maxHeight;
  final String label;
}

/// Type de filtre audio (façon Shotcut).
enum AudioFilterType {
  none('Aucun'),
  lowpass('Passe-bas'),
  highpass('Passe-haut'),
  bandpass('Passe-bande'),
  bandreject('Coupe-bande');

  const AudioFilterType(this.label);
  final String label;
}

class ExportSettings {
  // ── Qualité ────────────────────────────────────────────────────────────────
  final ExportResolution resolution;
  final int fps;          // 24 / 30 / 60
  /// CRF (Constant Rate Factor) — qualité VBR ; plus bas = meilleure qualité.
  /// 18 ≈ visuellement sans perte, 23 = défaut, 28 = compressé.
  final int crf;

  // ── Régulation thermique ────────────────────────────────────────────────────
  /// Nombre de threads FFmpeg (limité pour éviter la surchauffe).
  final int threads;
  /// Utiliser l'encodeur matériel (h264_mediacodec sur Android) si possible.
  final bool hardwareAcceleration;

  // ── Filtres vidéo (FFmpeg `eq`) ──────────────────────────────────────────────
  /// Luminosité -1.0 .. 1.0 (0 = neutre).
  final double brightness;
  /// Contraste 0.0 .. 2.0 (1 = neutre).
  final double contrast;
  /// Saturation 0.0 .. 3.0 (1 = neutre).
  final double saturation;

  // ── Filtres audio ────────────────────────────────────────────────────────────
  /// Volume multiplicateur (1.0 = neutre).
  final double volume;
  final AudioFilterType audioFilter;
  /// Fréquence de coupure / centrale du filtre audio (Hz).
  final int audioFilterFrequency;

  const ExportSettings({
    this.resolution = ExportResolution.p1080,
    this.fps = 30,
    this.crf = 23,
    this.threads = 2,
    this.hardwareAcceleration = true,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.volume = 1.0,
    this.audioFilter = AudioFilterType.none,
    this.audioFilterFrequency = 1000,
  });

  ExportSettings copyWith({
    ExportResolution? resolution,
    int? fps,
    int? crf,
    int? threads,
    bool? hardwareAcceleration,
    double? brightness,
    double? contrast,
    double? saturation,
    double? volume,
    AudioFilterType? audioFilter,
    int? audioFilterFrequency,
  }) =>
      ExportSettings(
        resolution: resolution ?? this.resolution,
        fps: fps ?? this.fps,
        crf: crf ?? this.crf,
        threads: threads ?? this.threads,
        hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        volume: volume ?? this.volume,
        audioFilter: audioFilter ?? this.audioFilter,
        audioFilterFrequency: audioFilterFrequency ?? this.audioFilterFrequency,
      );

  bool get hasVideoFilter =>
      brightness != 0.0 || contrast != 1.0 || saturation != 1.0;

  bool get hasAudioFilter =>
      volume != 1.0 || audioFilter != AudioFilterType.none;

  // ── Construction des chaînes de filtres FFmpeg ───────────────────────────────

  /// Chaîne du filtre vidéo combinant échelle, fps, eq (luminosité/contraste/
  /// saturation). Retourne `null` si rien à appliquer.
  String? buildVideoFilter() {
    final parts = <String>[];
    if (resolution != ExportResolution.original) {
      // -2 garde un nombre pair (requis par h264) et conserve le ratio.
      parts.add('scale=-2:${resolution.maxHeight}');
    }
    parts.add('fps=$fps');
    if (hasVideoFilter) {
      parts.add('eq=brightness=$brightness:contrast=$contrast:'
          'saturation=$saturation');
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  /// Chaîne du filtre audio (volume + passe-bande, etc.). `null` si rien.
  String? buildAudioFilter() {
    final parts = <String>[];
    if (volume != 1.0) parts.add('volume=$volume');
    switch (audioFilter) {
      case AudioFilterType.lowpass:
        parts.add('lowpass=f=$audioFilterFrequency');
        break;
      case AudioFilterType.highpass:
        parts.add('highpass=f=$audioFilterFrequency');
        break;
      case AudioFilterType.bandpass:
        parts.add('bandpass=f=$audioFilterFrequency');
        break;
      case AudioFilterType.bandreject:
        parts.add('bandreject=f=$audioFilterFrequency');
        break;
      case AudioFilterType.none:
        break;
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  /// Encodeur vidéo : matériel (mediacodec) si demandé, sinon x264 logiciel.
  /// Note : avec mediacodec, le CRF n'est pas supporté → on passe par un débit.
  String videoCodecArgs() {
    if (hardwareAcceleration) {
      // h264_mediacodec utilise un bitrate cible plutôt que CRF.
      final bitrate = _bitrateForResolution();
      return '-c:v h264_mediacodec -b:v $bitrate';
    }
    return '-c:v libx264 -preset veryfast -crf $crf';
  }

  String _bitrateForResolution() {
    switch (resolution) {
      case ExportResolution.p480:
        return '1500k';
      case ExportResolution.p720:
        return '3000k';
      case ExportResolution.p1080:
        return '6000k';
      case ExportResolution.original:
        return '8000k';
    }
  }

  /// Assemble la commande FFmpeg complète (trim + filtres + encodage régulé).
  ///
  /// [editorVideoFilters] contient les filtres déjà calculés par l'éditeur
  /// (recadrage, rotation) qu'on combine avec les filtres de réglage.
  String buildFFmpegCommand({
    required String videoPath,
    required String outputPath,
    required double startSeconds,
    required double durationSeconds,
    List<String> editorVideoFilters = const [],
  }) {
    final vfParts = <String>[
      ...editorVideoFilters,
      if (resolution != ExportResolution.original)
        'scale=-2:${resolution.maxHeight}',
      'fps=$fps',
      if (hasVideoFilter)
        'eq=brightness=$brightness:contrast=$contrast:saturation=$saturation',
    ];
    final vf = vfParts.isEmpty ? '' : "-vf \"${vfParts.join(',')}\"";
    final af = buildAudioFilter();
    final afArg = af == null ? '' : "-af \"$af\"";

    return [
      '-ss', startSeconds.toStringAsFixed(3),
      '-i', "'$videoPath'",
      '-t', durationSeconds.toStringAsFixed(3),
      // Régulation thermique : limite le nombre de threads CPU.
      '-threads', '$threads',
      vf,
      videoCodecArgs(),
      afArg,
      '-c:a', 'aac', '-b:a', '128k',
      '-movflags', '+faststart',
      '-y', "'$outputPath'",
    ].where((s) => s.isNotEmpty).join(' ');
  }
}
