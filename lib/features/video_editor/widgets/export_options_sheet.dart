/// @file export_options_sheet.dart
/// @brief Feuille de réglages d'export : qualité, régulation thermique et
/// filtres vidéo/audio. Retourne un [ExportSettings] via Navigator.pop.

import 'package:flutter/material.dart';
import '../models/export_settings.dart';

Future<ExportSettings?> showExportOptionsSheet(
  BuildContext context, {
  ExportSettings initial = const ExportSettings(),
}) {
  return showModalBottomSheet<ExportSettings>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ExportOptionsSheet(initial: initial),
  );
}

class _ExportOptionsSheet extends StatefulWidget {
  final ExportSettings initial;
  const _ExportOptionsSheet({required this.initial});

  @override
  State<_ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<_ExportOptionsSheet> {
  late ExportSettings _s = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Options d\'export', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),

          // ── Qualité ───────────────────────────────────────────────────────
          _section('Qualité'),
          _dropdown<ExportResolution>(
            label: 'Résolution',
            value: _s.resolution,
            items: ExportResolution.values,
            itemLabel: (r) => r.label,
            onChanged: (v) => setState(() => _s = _s.copyWith(resolution: v)),
          ),
          _dropdown<int>(
            label: 'Images / s',
            value: _s.fps,
            items: const [24, 30, 60],
            itemLabel: (f) => '$f fps',
            onChanged: (v) => setState(() => _s = _s.copyWith(fps: v)),
          ),
          _slider(
            label: 'Qualité (CRF ${_s.crf})',
            sub: 'Plus bas = meilleure qualité, fichier plus gros',
            value: _s.crf.toDouble(),
            min: 16,
            max: 30,
            divisions: 14,
            onChanged: (v) => setState(() => _s = _s.copyWith(crf: v.round())),
          ),

          // ── Régulation thermique ───────────────────────────────────────────
          _section('Performances / chaleur'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accélération matérielle'),
            subtitle: const Text(
                'Encodeur natif (mediacodec) — moins de chauffe, plus rapide'),
            value: _s.hardwareAcceleration,
            onChanged: (v) =>
                setState(() => _s = _s.copyWith(hardwareAcceleration: v)),
          ),
          _slider(
            label: 'Threads CPU (${_s.threads})',
            sub: 'Moins de threads = moins de surchauffe',
            value: _s.threads.toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            onChanged: (v) => setState(() => _s = _s.copyWith(threads: v.round())),
          ),

          // ── Filtres vidéo ──────────────────────────────────────────────────
          _section('Filtres vidéo'),
          _slider(
            label: 'Luminosité (${_s.brightness.toStringAsFixed(2)})',
            value: _s.brightness,
            min: -1.0,
            max: 1.0,
            divisions: 40,
            onChanged: (v) => setState(() => _s = _s.copyWith(brightness: v)),
          ),
          _slider(
            label: 'Contraste (${_s.contrast.toStringAsFixed(2)})',
            value: _s.contrast,
            min: 0.0,
            max: 2.0,
            divisions: 40,
            onChanged: (v) => setState(() => _s = _s.copyWith(contrast: v)),
          ),
          _slider(
            label: 'Saturation (${_s.saturation.toStringAsFixed(2)})',
            value: _s.saturation,
            min: 0.0,
            max: 3.0,
            divisions: 60,
            onChanged: (v) => setState(() => _s = _s.copyWith(saturation: v)),
          ),

          // ── Filtres audio ──────────────────────────────────────────────────
          _section('Filtres audio'),
          _slider(
            label: 'Volume (${(_s.volume * 100).round()} %)',
            value: _s.volume,
            min: 0.0,
            max: 3.0,
            divisions: 60,
            onChanged: (v) => setState(() => _s = _s.copyWith(volume: v)),
          ),
          _dropdown<AudioFilterType>(
            label: 'Filtre',
            value: _s.audioFilter,
            items: AudioFilterType.values,
            itemLabel: (f) => f.label,
            onChanged: (v) => setState(() => _s = _s.copyWith(audioFilter: v)),
          ),
          if (_s.audioFilter != AudioFilterType.none)
            _slider(
              label: 'Fréquence (${_s.audioFilterFrequency} Hz)',
              value: _s.audioFilterFrequency.toDouble(),
              min: 50,
              max: 18000,
              divisions: 100,
              onChanged: (v) => setState(
                  () => _s = _s.copyWith(audioFilterFrequency: v.round())),
            ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _s),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Exporter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: value,
            items: items
                .map((i) => DropdownMenuItem(value: i, child: Text(itemLabel(i))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    String? sub,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        if (sub != null)
          Text(sub, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
