/// @file visualizer_picker_sheet.dart
/// @brief Feuille de sélection du style de visualiseur audio.

import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../models/visualizer_style.dart';

class VisualizerPickerSheet extends StatelessWidget {
  final VisualizerStyle current;
  final ValueChanged<VisualizerStyle> onSelected;

  const VisualizerPickerSheet({
    super.key,
    required this.current,
    required this.onSelected,
  });

  static const _groups = <VisualizerFamily, String>{
    VisualizerFamily.spectrum: 'Spectre',
    VisualizerFamily.vu: 'VU-mètres',
    VisualizerFamily.circular: 'Circulaire',
    VisualizerFamily.particle: 'Particules',
    VisualizerFamily.oscilloscope: 'Oscilloscope',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Style de visualiseur',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: _groups.entries.expand((g) {
                  final styles = VisualizerStyle.values
                      .where((s) => s.family == g.key)
                      .toList();
                  return [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        g.value.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: AppColors.accent,
                            ),
                      ),
                    ),
                    ...styles.map((s) => ListTile(
                          dense: true,
                          leading: Icon(
                            s == current
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: s == current
                                ? AppColors.accent
                                : null,
                            size: 18,
                          ),
                          title: Text(s.label),
                          onTap: () {
                            Navigator.pop(context);
                            onSelected(s);
                          },
                        )),
                  ];
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
