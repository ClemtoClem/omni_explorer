/// @file audio_editor_screen.dart
/// @brief Éditeur audio : aperçu (play/pause), découpage (trim), volume,
/// filtres (passe-bas/haut/bande), export FFmpeg en arrière-plan.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/app_theme.dart';
import '../models/export_settings.dart';
import '../services/video_export_service.dart';

class AudioEditorScreen extends StatefulWidget {
  final File file;
  const AudioEditorScreen({super.key, required this.file});

  @override
  State<AudioEditorScreen> createState() => _AudioEditorScreenState();
}

class _AudioEditorScreenState extends State<AudioEditorScreen> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  RangeValues _trim = const RangeValues(0, 1); // fractions 0..1
  bool _playing = false;

  // Filtres
  double _volume = 1.0;
  AudioFilterType _filter = AudioFilterType.none;
  int _filterFreq = 1000;

  bool _exporting = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final d = await _player.setFilePath(widget.file.path);
      if (mounted && d != null) {
        setState(() {
          _duration = d;
          _trim = const RangeValues(0, 1);
        });
      }
    } catch (_) {}
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Duration get _trimStart => _duration * _trim.start;
  Duration get _trimEnd => _duration * _trim.end;

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      // Lecture dans la zone de trim.
      await _player.seek(_trimStart);
      await _player.play();
    }
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _progress = 0;
    });
    final dir = (await getTemporaryDirectory()).path;
    final out = p.join(dir,
        '${p.basenameWithoutExtension(widget.file.path)}_edit-${DateTime.now().millisecondsSinceEpoch}.m4a');

    final afParts = <String>[];
    if (_volume != 1.0) afParts.add('volume=$_volume');
    switch (_filter) {
      case AudioFilterType.lowpass:
        afParts.add('lowpass=f=$_filterFreq');
        break;
      case AudioFilterType.highpass:
        afParts.add('highpass=f=$_filterFreq');
        break;
      case AudioFilterType.bandpass:
        afParts.add('bandpass=f=$_filterFreq');
        break;
      case AudioFilterType.bandreject:
        afParts.add('bandreject=f=$_filterFreq');
        break;
      case AudioFilterType.none:
        break;
    }
    final af = afParts.isEmpty ? '' : "-af \"${afParts.join(',')}\"";
    final start = _trimStart.inMilliseconds / 1000.0;
    final dur = (_trimEnd - _trimStart).inMilliseconds / 1000.0;
    final cmd =
        "-ss ${start.toStringAsFixed(3)} -i '${widget.file.path}' "
        "-t ${dur.toStringAsFixed(3)} $af -c:a aac -b:a 192k -y '$out'";

    await VideoExportService.export(
      command: cmd,
      outputPath: out,
      totalDurationMs: (_trimEnd - _trimStart).inMilliseconds,
      onProgress: (pr) {
        if (mounted) setState(() => _progress = pr);
      },
      onCompleted: (file) {
        if (!mounted) return;
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Audio exporté : ${p.basename(file.path)}'),
          action: SnackBarAction(
              label: 'OK',
              onPressed: () => Navigator.pop(context, file.path)),
        ));
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: AppColors.error));
      },
    );
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.file.path),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Exporter',
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Aperçu + position
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.graphic_eq_rounded,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position)),
                      Text(_fmt(_duration)),
                    ],
                  ),
                  IconButton(
                    iconSize: 48,
                    icon: Icon(_playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded),
                    onPressed: _togglePlay,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Trim
          _label('Découpage : ${_fmt(_trimStart)} → ${_fmt(_trimEnd)}'),
          RangeSlider(
            values: _trim,
            onChanged: _duration == Duration.zero
                ? null
                : (v) => setState(() => _trim = v),
          ),

          // Volume
          _label('Volume : ${(_volume * 100).round()} %'),
          Slider(
            value: _volume,
            min: 0,
            max: 3,
            divisions: 60,
            onChanged: (v) => setState(() => _volume = v),
          ),

          // Filtre
          Row(
            children: [
              const Text('Filtre audio'),
              const Spacer(),
              DropdownButton<AudioFilterType>(
                value: _filter,
                items: AudioFilterType.values
                    .map((f) =>
                        DropdownMenuItem(value: f, child: Text(f.label)))
                    .toList(),
                onChanged: (v) => setState(() => _filter = v ?? _filter),
              ),
            ],
          ),
          if (_filter != AudioFilterType.none) ...[
            _label('Fréquence : $_filterFreq Hz'),
            Slider(
              value: _filterFreq.toDouble(),
              min: 50,
              max: 18000,
              divisions: 100,
              onChanged: (v) => setState(() => _filterFreq = v.round()),
            ),
          ],

          if (_exporting) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 4),
            Text('Export ${(_progress * 100).round()} %',
                style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}
