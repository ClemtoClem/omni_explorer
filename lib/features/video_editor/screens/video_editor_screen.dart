/// @file video_editor_screen.dart
/// @brief Écran principal de l'éditeur vidéo : prévisualisation, trim, cover,
/// recadrage (page dédiée), rotation, inversion (reverse), export.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../models/export_settings.dart';
import '../services/export_service.dart';
import '../services/video_export_service.dart';
import '../widgets/export_options_sheet.dart';
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
  ExportSettings _settings = const ExportSettings();
  // Zoom de la timeline de trim (maxViewportRatio) : 1× = vue complète,
  // 8× = timeline 8× plus large (scroll horizontal) pour un découpage précis.
  double _trimZoom = 2.5;

  @override
  void initState() {
    super.initState();
    // Mode paysage pour maximiser l'espace de prévisualisation et de timeline.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller
        .initialize(aspectRatio: 16 / 9)
        .then((_) => setState(() {}))
        .catchError((e) {
      if (mounted) setState(() => _exportError = 'Erreur init : $e');
    });
  }

  @override
  void dispose() {
    // Restaure toutes les orientations en quittant l'éditeur.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
    // 1. Demande les options (qualité, thermique, filtres).
    final settings = await showExportOptionsSheet(context, initial: _settings);
    if (settings == null) return;
    _settings = settings;

    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _exportError = null;
    });

    // 2. Assemble la commande régulée via le commandBuilder du config (qui
    //    fournit le chemin de sortie et les filtres d'éditeur crop/rotation).
    final config = VideoFFmpegVideoEditorConfig(
      _controller,
      commandBuilder: (cfg, videoPath, outputPath) {
        // videoPath / outputPath sont déjà entre quotes simples.
        final c = cfg.controller;
        return settings.buildFFmpegCommand(
          videoPath: videoPath.replaceAll("'", ''),
          outputPath: outputPath.replaceAll("'", ''),
          startSeconds: c.startTrim.inMilliseconds / 1000.0,
          durationSeconds: c.trimmedDuration.inMilliseconds / 1000.0,
          editorVideoFilters: cfg.getExportFilters(),
        );
      },
    );
    final execute = await config.getExecuteConfig();

    // 3. Export en arrière-plan (service de premier plan + notification).
    await VideoExportService.export(
      command: execute.command,
      outputPath: execute.outputPath,
      totalDurationMs: _controller.trimmedDuration.inMilliseconds,
      onProgress: (pr) {
        if (mounted) setState(() => _exportProgress = pr);
      },
      onCompleted: _onExportDone,
      onError: (e) => _onExportError(e, StackTrace.current),
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
              // ── Zoom timeline (précision du découpage) ──────────────────
              Row(
                children: [
                  const Icon(Icons.zoom_out_rounded,
                      color: Colors.white54, size: 18),
                  Expanded(
                    child: Slider(
                      value: _trimZoom,
                      min: 1.0,
                      max: 8.0,
                      label: '${_trimZoom.toStringAsFixed(1)}×',
                      onChanged: (v) => setState(() => _trimZoom = v),
                    ),
                  ),
                  const Icon(Icons.zoom_in_rounded,
                      color: Colors.white54, size: 18),
                ],
              ),
              Expanded(
                child: TrimSlider(
                  // Key sur le zoom : force la recréation du slider avec le
                  // nouveau maxViewportRatio (timeline plus large = plus précis).
                  key: ValueKey('trim-$_trimZoom'),
                  controller: _controller,
                  height: 60,
                  horizontalMargin: 8,
                  maxViewportRatio: _trimZoom,
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
