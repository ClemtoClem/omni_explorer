/// @file video_editor_screen.dart
/// @brief Écran principal de l'éditeur vidéo : prévisualisation, trim, cover,
/// recadrage (page dédiée), rotation, inversion (reverse), export.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../controller.dart';
import '../utils/ffmpeg_config.dart';
import '../widgets/cover_selection.dart';
import '../widgets/cover_viewer.dart';
import '../widgets/crop_grid.dart';
import '../widgets/trim_slider.dart';
import '../widgets/trim_timeline.dart';

import '../../../app/theme/app_theme.dart';
import '../services/export_service.dart';
import 'video_crop_screen.dart';

class VideoEditorScreen extends StatefulWidget {
  /// Fichier vidéo source.
  final File file;
  const VideoEditorScreen({super.key, required this.file});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    with SingleTickerProviderStateMixin {
  late final VideoEditorController _controller = VideoEditorController.file(
    widget.file,
    minDuration: const Duration(seconds: 1),
    maxDuration: const Duration(minutes: 30),
  );
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _exporting = false;
  double _exportProgress = 0;
  String? _exportError;

  @override
  void initState() {
    super.initState();
    _controller
        .initialize(aspectRatio: 9 / 16)
        .then((_) => setState(() {}))
        .catchError((e) {
      if (mounted) setState(() => _exportError = 'Erreur init : $e');
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    ExportService.disposeAll();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _outputPath(String suffix, String ext) async {
    final dir = (await getTemporaryDirectory()).path;
    final base = p.basenameWithoutExtension(widget.file.path);
    return p.join(
        dir, '${base}_$suffix-${DateTime.now().millisecondsSinceEpoch}.$ext');
  }

  void _onExportProgress(Statistics stats) {
    if (!mounted) return;
    setState(() {
      _exportProgress = _controller.video.value.duration.inMilliseconds == 0
          ? 0
          : (stats.getTime() /
                  _controller.video.value.duration.inMilliseconds)
              .clamp(0.0, 1.0);
    });
  }

  void _onExportDone(File output) {
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportProgress = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Exporté : ${p.basename(output.path)}'),
      action: SnackBarAction(
        label: 'Voir',
        onPressed: () => Navigator.pop(context, output.path),
      ),
    ));
  }

  void _onExportError(Object e, StackTrace st) {
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportProgress = 0;
      _exportError = e.toString();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export échoué : $e'),
        backgroundColor: AppColors.error));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _openCropScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCropScreen(controller: _controller),
      ),
    );
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportError = null;
    });
    final config = VideoFFmpegVideoEditorConfig(_controller);
    final execute = await config.getExecuteConfig();
    await ExportService.runFFmpegCommand(
      execute,
      onCompleted: _onExportDone,
      onProgress: _onExportProgress,
      onError: _onExportError,
    );
  }

  Future<void> _reverse() async {
    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportError = null;
    });
    final output = await _outputPath('reverse', 'mp4');
    final command = ExportService.reverseCommand(widget.file.path, output);
    await ExportService.runRawCommand(
      command,
      outputPath: output,
      onCompleted: _onExportDone,
      onProgress: _onExportProgress,
      onError: _onExportError,
    );
  }

  Future<void> _saveCover() async {
    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportError = null;
    });
    final config = CoverFFmpegVideoEditorConfig(_controller);
    final execute = await config.getExecuteConfig();
    if (execute == null) {
      setState(() => _exporting = false);
      return;
    }
    await ExportService.runFFmpegCommand(
      execute,
      onCompleted: _onExportDone,
      onError: _onExportError,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(p.basename(widget.file.path),
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.crop_rounded),
            tooltip: 'Recadrer',
            onPressed: _controller.initialized ? _openCropScreen : null,
          ),
          IconButton(
            icon: const Icon(Icons.fast_rewind_rounded),
            tooltip: 'Inverser (reverse)',
            onPressed: _exporting ? null : _reverse,
          ),
          IconButton(
            icon: const Icon(Icons.image_rounded),
            tooltip: 'Exporter la miniature',
            onPressed: _exporting ? null : _saveCover,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Exporter',
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
      body: _controller.initialized
          ? Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TabBarView(
                        controller: _tabs,
                        children: [
                          // Onglet 1 : prévisualisation + crop visualisation.
                          CropGridViewer.preview(controller: _controller),
                          // Onglet 2 : sélection de la cover.
                          CoverViewer(controller: _controller),
                        ],
                      ),
                      AnimatedBuilder(
                        animation: _controller.video,
                        builder: (_, __) => AnimatedOpacity(
                          opacity: _controller.isPlaying ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTap: _controller.video.play,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 36),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 200,
                  margin: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabs,
                        tabs: const [
                          Tab(icon: Icon(Icons.content_cut), text: 'Trim'),
                          Tab(icon: Icon(Icons.video_label), text: 'Cover'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildTrimPanel(),
                            CoverSelection(
                              controller: _controller,
                              size: 60,
                              quantity: 8,
                              selectedCoverBuilder: (cover, size) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    cover,
                                    const Icon(Icons.check_circle,
                                        color: Colors.white),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_exporting) _buildProgress(),
                if (_exportError != null && !_exporting)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_exportError!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  Widget _buildTrimPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _controller.video]),
      builder: (_, __) {
        final pos = _controller.video.value.position;
        final start = _controller.startTrim;
        final end = _controller.endTrim;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(color: Colors.white70)),
                  Text(
                      '${_fmt(start)} → ${_fmt(end)} '
                      '(${_fmt(end - start)})',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TrimSlider(
                  controller: _controller,
                  height: 60,
                  horizontalMargin: 8,
                  child: TrimTimeline(
                    controller: _controller,
                    padding: const EdgeInsets.only(top: 8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _exportProgress == 0 ? null : _exportProgress,
          ),
          const SizedBox(height: 4),
          Text(
            'Export ${(_exportProgress * 100).round()}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
