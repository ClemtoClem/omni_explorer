/// @file subtitle_settings_sheet.dart
/// @brief Feuille de réglages d'apparence pour les sous-titres.

import 'package:flutter/material.dart';
import '../models/subtitle_settings.dart';

class SubtitleSettingsSheet extends StatefulWidget {
  final SubtitleSettings settings;
  final ValueChanged<SubtitleSettings> onChanged;

  const SubtitleSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<SubtitleSettingsSheet> createState() => _SubtitleSettingsSheetState();
}

class _SubtitleSettingsSheetState extends State<SubtitleSettingsSheet> {
  late SubtitleSettings _s = widget.settings;

  static const _textColors = <Color>[
    Colors.white,
    Colors.yellow,
    Colors.cyan,
    Color(0xFF89B4FA),
    Color(0xFFF38BA8),
    Colors.greenAccent,
  ];

  static const _highlights = <Color>[
    Colors.transparent,
    Color(0x80000000),
    Color(0xB3000000),
    Color(0x66FFFFFF),
  ];

  void _update(SubtitleSettings next) {
    setState(() => _s = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Réglages des sous-titres',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Taille (${_s.fontSize.toStringAsFixed(0)})',
                style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _s.fontSize,
              min: 10,
              max: 48,
              onChanged: (v) => _update(_s.copyWith(fontSize: v)),
            ),
            const SizedBox(height: 8),
            Text('Position verticale',
                style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _s.verticalAlignment,
              min: 0.05,
              max: 0.95,
              onChanged: (v) => _update(_s.copyWith(verticalAlignment: v)),
            ),
            const SizedBox(height: 8),
            Text('Couleur du texte',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _textColors
                  .map((c) => _ColorDot(
                        color: c,
                        selected: _s.textColor == c,
                        onTap: () => _update(_s.copyWith(textColor: c)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text('Surbrillance',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _highlights
                  .map((c) => _ColorDot(
                        color: c,
                        selected: _s.highlightColor == c,
                        onTap: () => _update(_s.copyWith(highlightColor: c)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              dense: true,
              title: const Text('Contour pour lisibilité'),
              value: _s.textOutline,
              onChanged: (v) => _update(_s.copyWith(textOutline: v)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color == Colors.transparent ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: color == Colors.transparent
            ? const Icon(Icons.block_rounded, color: Colors.white54, size: 18)
            : null,
      ),
    );
  }
}
