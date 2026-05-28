/// @file video_crop_screen.dart
/// @brief Écran de recadrage (rotation, ratio préréglé, validation). Adapté du
/// pattern officiel du paquet `video_editor`.

import 'package:flutter/material.dart';
import 'package:fraction/fraction.dart';
import 'package:omni_explorer/features/video_editor/controller.dart';
import 'package:omni_explorer/features/video_editor/models/crop_style.dart';
import 'package:omni_explorer/features/video_editor/widgets/crop_grid.dart';

class VideoCropScreen extends StatelessWidget {
  final VideoEditorController controller;
  const VideoCropScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: IconButton(
                  onPressed: () =>
                      controller.rotate90Degrees(RotateDirection.left),
                  icon: const Icon(Icons.rotate_left, color: Colors.white),
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: () =>
                      controller.rotate90Degrees(RotateDirection.right),
                  icon: const Icon(Icons.rotate_right, color: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 15),
            Expanded(
              child: CropGridViewer.edit(
                controller: controller,
                rotateCropArea: false,
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
            const SizedBox(height: 15),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                flex: 4,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          color: Colors.white,
                          onPressed: () =>
                              controller.preferredCropAspectRatio = controller
                                  .preferredCropAspectRatio
                                  ?.toFraction()
                                  .inverse()
                                  .toDouble(),
                          icon: controller.preferredCropAspectRatio != null &&
                                  controller.preferredCropAspectRatio! < 1
                              ? const Icon(
                                  Icons.panorama_vertical_select_rounded)
                              : const Icon(Icons.panorama_vertical_rounded),
                        ),
                        IconButton(
                          color: Colors.white,
                          onPressed: () =>
                              controller.preferredCropAspectRatio = controller
                                  .preferredCropAspectRatio
                                  ?.toFraction()
                                  .inverse()
                                  .toDouble(),
                          icon: controller.preferredCropAspectRatio != null &&
                                  controller.preferredCropAspectRatio! > 1
                              ? const Icon(
                                  Icons.panorama_horizontal_select_rounded)
                              : const Icon(Icons.panorama_horizontal_rounded),
                        ),
                      ],
                    ),
                    Row(children: [
                      _buildCropButton(context, null),
                      _buildCropButton(context, 1.toFraction()),
                      _buildCropButton(context, Fraction.fromString('9/16')),
                      _buildCropButton(context, Fraction.fromString('3/4')),
                    ]),
                  ]),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: () {
                    controller.applyCacheCrop();
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Valider',
                    style: TextStyle(
                      color: const CropGridStyle().selectedBoundariesColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildCropButton(BuildContext context, Fraction? f) {
    if (controller.preferredCropAspectRatio != null &&
        controller.preferredCropAspectRatio! > 1) {
      f = f?.inverse();
    }
    return Flexible(
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: controller.preferredCropAspectRatio == f?.toDouble()
              ? Colors.grey.shade800
              : null,
          foregroundColor: Colors.white,
          textStyle: Theme.of(context).textTheme.bodySmall,
        ),
        onPressed: () => controller.preferredCropAspectRatio = f?.toDouble(),
        child: Text(f == null ? 'libre' : '${f.numerator}:${f.denominator}'),
      ),
    );
  }
}
