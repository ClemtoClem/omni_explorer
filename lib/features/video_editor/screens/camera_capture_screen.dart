/// @file camera_capture_screen.dart
/// @brief Filmer une vidéo (caméra) → fichier, puis ouverture dans l'éditeur.

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import 'video_editor_screen.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _recording = false;
  bool _initializing = true;
  String? _error;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initController(_cameraIndex);
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'Aucune caméra disponible';
        });
        return;
      }
      await _initController(0);
    } catch (e) {
      setState(() {
        _initializing = false;
        _error = 'Erreur caméra : $e';
      });
    }
  }

  Future<void> _initController(int index) async {
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Init caméra : $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    await _controller?.dispose();
    setState(() => _controller = null);
    await _initController((_cameraIndex + 1) % _cameras.length);
  }

  Future<void> _toggleRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_recording) {
      _timer?.cancel();
      final file = await c.stopVideoRecording();
      setState(() => _recording = false);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VideoEditorScreen(file: File(file.path)),
          ),
        );
      }
    } else {
      await c.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(seconds: 1),
          (_) => setState(() => _elapsed += const Duration(seconds: 1)));
    }
  }

  String _fmt(Duration d) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  )
                : Stack(
                    children: [
                      if (_controller != null &&
                          _controller!.value.isInitialized)
                        Center(child: CameraPreview(_controller!)),
                      // Barre supérieure
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            if (_recording)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.circle,
                                        color: AppColors.error, size: 12),
                                    const SizedBox(width: 6),
                                    Text(_fmt(_elapsed),
                                        style: const TextStyle(
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Contrôles bas
                      Positioned(
                        bottom: 24,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const SizedBox(width: 48),
                            GestureDetector(
                              onTap: _toggleRecording,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 4),
                                ),
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: _recording ? 28 : 56,
                                    height: _recording ? 28 : 56,
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(
                                          _recording ? 6 : 28),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              iconSize: 32,
                              color: Colors.white,
                              icon: const Icon(Icons.cameraswitch_rounded),
                              onPressed:
                                  _cameras.length < 2 || _recording ? null : _switchCamera,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
