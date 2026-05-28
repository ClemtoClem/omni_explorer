/// @file video_editor_home_screen.dart
/// @brief Page d'accueil de l'éditeur vidéo : choix entre édition d'un clip
/// unique (trim / crop / rotate / cover / reverse) et assemblage multi-clips.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'video_concat_screen.dart';
import 'video_editor_screen.dart';

class VideoEditorHomeScreen extends StatelessWidget {
  const VideoEditorHomeScreen({super.key});

  Future<void> _pickAndEdit(BuildContext ctx) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    if (!ctx.mounted) return;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(file: File(res.files.single.path!)),
      ),
    );
  }

  void _openConcat(BuildContext ctx) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const VideoConcatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Éditeur vidéo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ActionTile(
            icon: Icons.content_cut,
            color: theme.colorScheme.primary,
            title: 'Éditer une vidéo',
            subtitle:
                'Trim, recadrage, rotation, miniature (cover), inversion, export',
            onTap: () => _pickAndEdit(context),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.playlist_play_rounded,
            color: theme.colorScheme.secondary,
            title: 'Assembler plusieurs clips',
            subtitle: 'Sélectionner et ordonner des vidéos puis les concaténer',
            onTap: () => _openConcat(context),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Les exports sont écrits dans le dossier temporaire de '
              'l\'application. Utilisez le bouton « Voir » du snackbar de fin '
              "d'export pour récupérer le chemin.",
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
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
    );
  }
}
