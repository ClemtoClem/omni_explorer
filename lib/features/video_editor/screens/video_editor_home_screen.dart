/// @file video_editor_home_screen.dart
/// @brief Accueil de l'« Éditeur multimédia » : éditer vidéo / audio / image,
/// filmer, enregistrer un son, assembler des clips.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import 'audio_editor_screen.dart';
import 'audio_record_screen.dart';
import 'camera_capture_screen.dart';
import 'image_editor_screen.dart';
import 'video_concat_screen.dart';
import 'video_editor_screen.dart';

class VideoEditorHomeScreen extends StatelessWidget {
  const VideoEditorHomeScreen({super.key});

  Future<void> _pickAndOpen(
    BuildContext ctx,
    FileType type,
    Widget Function(File) builder,
  ) async {
    final res = await FilePicker.platform.pickFiles(type: type);
    if (res == null || res.files.single.path == null) return;
    if (!ctx.mounted) return;
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => builder(File(res.files.single.path!))),
    );
  }

  void _open(BuildContext ctx, Widget screen) {
    Navigator.push(ctx, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Éditeur multimédia')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _group(context, 'CRÉER'),
          _tile(context,
              icon: Icons.videocam_rounded,
              color: AppColors.colorVideo,
              title: 'Filmer une vidéo',
              subtitle: 'Caméra avant/arrière, audio inclus',
              onTap: () => _open(context, const CameraCaptureScreen())),
          _tile(context,
              icon: Icons.mic_rounded,
              color: AppColors.colorAudio,
              title: 'Enregistrer un audio',
              subtitle: 'Micro → fichier .m4a éditable',
              onTap: () => _open(context, const AudioRecordScreen())),

          _group(context, 'ÉDITER'),
          _tile(context,
              icon: Icons.movie_creation_rounded,
              color: AppColors.colorVideo,
              title: 'Éditer une vidéo',
              subtitle: 'Trim, recadrage, rotation, cover, reverse, export',
              onTap: () => _pickAndOpen(context, FileType.video,
                  (f) => VideoEditorScreen(file: f))),
          _tile(context,
              icon: Icons.audiotrack_rounded,
              color: AppColors.colorAudio,
              title: 'Éditer un audio',
              subtitle: 'Découpage, volume, filtres (passe-bas/haut/bande)',
              onTap: () => _pickAndOpen(context, FileType.audio,
                  (f) => AudioEditorScreen(file: f))),
          _tile(context,
              icon: Icons.image_rounded,
              color: AppColors.colorImage,
              title: 'Éditer une image',
              subtitle: 'Rotation, miroir, luminosité, contraste, saturation',
              onTap: () => _pickAndOpen(context, FileType.image,
                  (f) => ImageEditorScreen(file: f))),

          _group(context, 'ASSEMBLER'),
          _tile(context,
              icon: Icons.playlist_play_rounded,
              color: theme.colorScheme.secondary,
              title: 'Assembler plusieurs clips',
              subtitle: 'Ordonner et concaténer des vidéos',
              onTap: () => _open(context, const VideoConcatScreen())),

          const SizedBox(height: 20),
          Text(
            'Les exports sont écrits dans le dossier temporaire de '
            'l\'application et notifiés à la fin. L\'export tourne en arrière-'
            'plan (service de premier plan) et reste modéré (threads limités, '
            'accélération matérielle).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
