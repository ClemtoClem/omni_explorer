/// @file password_generator_sheet.dart
/// @brief Feuille de génération de mot de passe (longueur, types de
/// caractères, entropie). Renvoie le mot de passe choisi.

import 'package:flutter/material.dart';

import '../services/password_generator.dart';

Future<String?> showPasswordGeneratorSheet(BuildContext context,
    {PasswordGenerator? generator}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GeneratorSheet(generator ?? PasswordGenerator()),
  );
}

class _GeneratorSheet extends StatefulWidget {
  final PasswordGenerator generator;
  const _GeneratorSheet(this.generator);

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  var _options = const PasswordGeneratorOptions();
  late String _password = widget.generator.generate(_options);

  void _update(PasswordGeneratorOptions options) {
    // Au moins un type de caractères doit rester coché.
    if (PasswordGenerator.charsets(options).isEmpty) return;
    setState(() {
      _options = options;
      _password = widget.generator.generate(options);
    });
  }

  String get _strength {
    final bits = PasswordGenerator.entropyBits(_options);
    final label = bits >= 100
        ? 'excellente'
        : bits >= 75
            ? 'forte'
            : bits >= 50
                ? 'moyenne'
                : 'faible';
    return 'Robustesse $label (≈ ${bits.round()} bits)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Générer un mot de passe', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(_password,
                      key: const Key('generated-password'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 16)),
                ),
                IconButton(
                  tooltip: 'Régénérer',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _update(_options),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(_strength, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('Longueur : ${_options.length}'),
          Slider(
            value: _options.length.toDouble(),
            min: PasswordGeneratorOptions.minLength.toDouble(),
            max: 64,
            divisions: 64 - PasswordGeneratorOptions.minLength,
            label: '${_options.length}',
            onChanged: (v) => _update(_options.copyWith(length: v.round())),
          ),
          _toggle('Minuscules (a-z)', _options.lowercase,
              (v) => _options.copyWith(lowercase: v)),
          _toggle('Majuscules (A-Z)', _options.uppercase,
              (v) => _options.copyWith(uppercase: v)),
          _toggle('Chiffres (0-9)', _options.digits,
              (v) => _options.copyWith(digits: v)),
          _toggle('Symboles (!#\$%…)', _options.symbols,
              (v) => _options.copyWith(symbols: v)),
          _toggle(
              'Éviter les caractères ambigus (O/0, l/1…)',
              _options.avoidAmbiguous,
              (v) => _options.copyWith(avoidAmbiguous: v)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, _password),
            child: const Text('Utiliser ce mot de passe'),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value,
      PasswordGeneratorOptions Function(bool) change) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: (v) => _update(change(v)),
    );
  }
}
