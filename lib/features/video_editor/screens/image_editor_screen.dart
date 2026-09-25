/// @file image_editor_screen.dart
/// @brief Éditeur d'image : rotation, miroir, réglages (luminosité, contraste,
/// saturation) avec aperçu live, export FFmpeg.

import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/app_theme.dart';

class ImageEditorScreen extends StatefulWidget {
  final File file;
  const ImageEditorScreen({super.key, required this.file});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  int _rotation = 0; // 0/90/180/270
  bool _flipH = false;
  double _brightness = 0.0; // -1..1
  double _contrast = 1.0; // 0..2
  double _saturation = 1.0; // 0..3
  bool _exporting = false;

  void _rotate() => setState(() => _rotation = (_rotation + 90) % 360);
  void _flip() => setState(() => _flipH = !_flipH);

  /// Filtre live approximatif via ColorFiltered + Transform (luminosité/
  /// contraste/saturation ne sont pas tous exprimables en ColorFilter simple,
  /// on applique au moins la rotation/miroir et un ajustement de luminosité).
  Widget _preview() {
    Widget img = Image.file(widget.file, fit: BoxFit.contain);
    // Matrice de saturation + luminosité approximative pour l'aperçu.
    final s = _saturation;
    const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;
    final b = _brightness * 255;
    final c = _contrast;
    final t = (1 - c) * 128 + b;
    final matrix = <double>[
      (sr + s) * c, sg * c, sb * c, 0, t,
      sr * c, (sg + s) * c, sb * c, 0, t,
      sr * c, sg * c, (sb + s) * c, 0, t,
      0, 0, 0, 1, 0,
    ];
    img = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: img);
    return Transform.flip(
      flipX: _flipH,
      child: Transform.rotate(
        angle: _rotation * 3.14159265 / 180,
        child: img,
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final dir = (await getTemporaryDirectory()).path;
    final out = p.join(dir,
        '${p.basenameWithoutExtension(widget.file.path)}_edit-${DateTime.now().millisecondsSinceEpoch}.jpg');

    final vf = <String>[];
    // Rotation (transpose) — répétée.
    for (int i = 0; i < _rotation ~/ 90; i++) {
      vf.add('transpose=1'); // 90° horaire
    }
    if (_flipH) vf.add('hflip');
    if (_brightness != 0.0 || _contrast != 1.0 || _saturation != 1.0) {
      vf.add('eq=brightness=$_brightness:contrast=$_contrast:saturation=$_saturation');
    }
    final vfArg = vf.isEmpty ? '' : "-vf \"${vf.join(',')}\"";
    final cmd = "-i '${widget.file.path}' $vfArg -q:v 2 -y '$out'";

    final session = await FFmpegKit.execute(cmd);
    final code = await session.getReturnCode();
    if (!mounted) return;
    setState(() => _exporting = false);
    if (ReturnCode.isSuccess(code)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Image exportée : ${p.basename(out)}'),
        action: SnackBarAction(
            label: 'OK', onPressed: () => Navigator.pop(context, out)),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Échec de l\'export'),
          backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(p.basename(widget.file.path),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded),
            tooltip: 'Pivoter',
            onPressed: _rotate,
          ),
          IconButton(
            icon: const Icon(Icons.flip_rounded),
            tooltip: 'Miroir',
            onPressed: _flip,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Exporter',
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _preview())),
          if (_exporting) const LinearProgressIndicator(),
          Container(
            color: AppColors.darkSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _adjust('Luminosité', _brightness, -1, 1,
                    (v) => setState(() => _brightness = v)),
                _adjust('Contraste', _contrast, 0, 2,
                    (v) => setState(() => _contrast = v)),
                _adjust('Saturation', _saturation, 0, 3,
                    (v) => setState(() => _saturation = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adjust(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
