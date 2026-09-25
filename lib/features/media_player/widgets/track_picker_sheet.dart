/// @file track_picker_sheet.dart
/// @brief Sélecteur de fichiers de sous-titres externes.

import 'package:flutter/material.dart';

class TrackPickerSheet extends StatelessWidget {
  final List<String> subtitleFiles;
  final String? currentSubtitle;
  final ValueChanged<String?> onSubtitleSelected;

  const TrackPickerSheet({
    super.key,
    required this.subtitleFiles,
    required this.currentSubtitle,
    required this.onSubtitleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.subtitles_rounded),
                  const SizedBox(width: 12),
                  const Text('Sous-titres',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                currentSubtitle == null
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: currentSubtitle == null ? Colors.lightBlueAccent : null,
              ),
              title: const Text('Aucun'),
              onTap: () {
                Navigator.pop(context);
                onSubtitleSelected(null);
              },
            ),
            ...subtitleFiles.map((path) {
              final name = path.split('/').last;
              final selected = path == currentSubtitle;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected ? Colors.lightBlueAccent : null,
                ),
                title: Text(name),
                onTap: () {
                  Navigator.pop(context);
                  onSubtitleSelected(path);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
