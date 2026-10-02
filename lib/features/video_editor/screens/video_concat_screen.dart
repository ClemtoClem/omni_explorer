/// @file video_concat_screen.dart
/// @brief Écran d'assemblage multi-clips : sélection de plusieurs vidéos,
/// réorganisation, puis export via le démuxer concat de FFmpeg.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/theme/app_theme.dart';
import '../../file_explorer/explorer_picker.dart';
import '../services/export_service.dart';

class VideoConcatScreen extends StatefulWidget {
  const VideoConcatScreen({super.key});

  @override
  State<VideoConcatScreen> createState() => _VideoConcatScreenState();
}

class _VideoConcatScreenState extends State<VideoConcatScreen> {
  final List<File> _clips = [];
  bool _exporting = false;
  double _progress = 0;
  String? _error;

  Future<void> _pickClips() async {
    final paths = await ExplorerPicker.pickFiles(
      context,
      title: 'Clips à assembler',
      categories: {FileCategory.video},
    );
    if (paths.isEmpty || !mounted) return;
    setState(() => _clips.addAll(paths.map(File.new)));
  }

  Future<void> _export() async {
    if (_clips.length < 2) return;
    setState(() {
      _exporting = true;
      _progress = 0;
      _error = null;
    });
    try {
      // Crée le fichier de liste demandé par le démuxer concat.
      final tmp = await getTemporaryDirectory();
      final listFile = File(p.join(tmp.path,
          'concat-${DateTime.now().millisecondsSinceEpoch}.txt'));
      final lines = _clips.map((f) => "file '${f.path}'").join('\n');
      await listFile.writeAsString(lines);
      final output = p.join(tmp.path,
          'concat-${DateTime.now().millisecondsSinceEpoch}.mp4');
      final cmd = ExportService.concatCommand(listFile.path, output);
      await ExportService.runRawCommand(
        cmd,
        outputPath: output,
        onCompleted: (file) {
          if (!mounted) return;
          setState(() => _exporting = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Assemblé : ${p.basename(file.path)}')));
          Navigator.pop(context, file.path);
        },
        onError: (e, _) {
          if (!mounted) return;
          setState(() {
            _exporting = false;
            _error = e.toString();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Assemblage multi-clips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Ajouter des clips',
            onPressed: _pickClips,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Exporter',
            onPressed: _clips.length >= 2 && !_exporting ? _export : null,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_clips.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ajoutez au moins deux clips pour les assembler.\n'
                    '⚠ Les clips doivent partager le même codec / résolution '
                    '(remux sans réencodage).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _clips.length,
                onReorderItem: (oldIdx, newIdx) {
                  setState(() {
                    final item = _clips.removeAt(oldIdx);
                    _clips.insert(newIdx, item);
                  });
                },
                itemBuilder: (_, i) {
                  final c = _clips[i];
                  return ListTile(
                    key: ValueKey('${c.path}#$i'),
                    leading: CircleAvatar(
                      backgroundColor: Colors.white12,
                      child: Text('${i + 1}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(p.basename(c.path),
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(c.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      onPressed: () =>
                          setState(() => _clips.removeAt(i)),
                    ),
                  );
                },
              ),
            ),
          if (_exporting)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress),
                  const SizedBox(height: 4),
                  const Text('Assemblage en cours…',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          if (_error != null && !_exporting)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
