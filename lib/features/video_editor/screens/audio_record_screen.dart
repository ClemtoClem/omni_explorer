/// @file audio_record_screen.dart
/// @brief Enregistrement audio (micro) → fichier .m4a, puis ouverture
/// optionnelle dans l'éditeur audio.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../app/theme/app_theme.dart';
import 'audio_editor_screen.dart';

class AudioRecordScreen extends StatefulWidget {
  const AudioRecordScreen({super.key});

  @override
  State<AudioRecordScreen> createState() => _AudioRecordScreenState();
}

class _AudioRecordScreenState extends State<AudioRecordScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _paused = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _path;
  double _amplitude = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permission micro refusée')));
      }
      return;
    }
    final dir = (await getTemporaryDirectory()).path;
    final path =
        p.join(dir, 'rec-${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
    _path = path;
    setState(() {
      _recording = true;
      _paused = false;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_paused) setState(() => _elapsed += const Duration(milliseconds: 200));
      try {
        final amp = await _recorder.getAmplitude();
        if (mounted) {
          setState(() => _amplitude =
              ((amp.current + 45) / 45).clamp(0.0, 1.0)); // ~-45dB..0dB
        }
      } catch (_) {}
    });
  }

  Future<void> _togglePause() async {
    if (_paused) {
      await _recorder.resume();
    } else {
      await _recorder.pause();
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _stop({required bool keep}) async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (!keep) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return;
    }
    final finalPath = path ?? _path;
    if (finalPath != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AudioEditorScreen(file: File(finalPath)),
        ),
      );
    }
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = ((d.inMilliseconds % 1000) ~/ 100).toString();
    return '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Enregistrement audio'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Indicateur d'amplitude
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 140 + _amplitude * 120,
              height: 140 + _amplitude * 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_recording && !_paused
                        ? AppColors.error
                        : AppColors.accent)
                    .withValues(alpha: 0.15),
              ),
              child: Icon(
                _recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 64,
                color: _recording && !_paused ? AppColors.error : AppColors.accent,
              ),
            ),
            const SizedBox(height: 32),
            Text(_fmt(_elapsed),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontFeatures: [],
                    fontFamily: 'monospace')),
            const SizedBox(height: 40),
            if (!_recording)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: _start,
                icon: const Icon(Icons.fiber_manual_record_rounded),
                label: const Text('Démarrer'),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    color: Colors.white,
                    icon: Icon(_paused
                        ? Icons.play_circle_rounded
                        : Icons.pause_circle_rounded),
                    onPressed: _togglePause,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 48,
                    color: AppColors.error,
                    icon: const Icon(Icons.stop_circle_rounded),
                    tooltip: 'Arrêter et éditer',
                    onPressed: () => _stop(keep: true),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    iconSize: 40,
                    color: Colors.white54,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Annuler',
                    onPressed: () => _stop(keep: false),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
