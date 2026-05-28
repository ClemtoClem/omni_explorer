import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/settings_service.dart';

// ── Catalogues de polices ──────────────────────────────────────────────────

class _FontCatalog {
  static const List<String> ui = [
    'Inter', 'Jost', 'Roboto', 'Lato', 'Open Sans', 'Nunito', 'Poppins',
  ];
  static const List<String> mono = [
    'JetBrains Mono', 'Roboto Mono', 'Source Code Pro', 'Fira Code', 'Inconsolata',
  ];
  static const List<String> text = [
    'Inter', 'Roboto', 'Open Sans', 'Lato', 'Nunito', 'Merriweather',
  ];

  static TextStyle style(String family, {double size = 13, Color? color}) {
    try {
      return GoogleFonts.getFont(family, fontSize: size, color: color);
    } catch (_) {
      return TextStyle(fontSize: size, color: color);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// @class FontSettingsScreen
/// @brief Réglage de la police et de la taille pour l'UI et chaque type d'éditeur.
class FontSettingsScreen extends StatelessWidget {
  const FontSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Polices'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Interface globale ────────────────────────────────────────────
          _FontSection(
            icon: Icons.text_fields_rounded,
            color: AppColors.accent,
            title: 'Interface',
            subtitle: 'Texte de l\'application (menus, titres, labels)',
            families: _FontCatalog.ui,
            currentFamily: settings.uiFontFamily,
            onFamilyChanged: settings.setUiFontFamily,
            // Scale factor instead of absolute size for UI
            isScale: true,
            scaleValue: settings.uiFontScale,
            onScaleChanged: settings.setUiFontScale,
            previewText: 'Explorateur de fichiers',
          ),
          const Divider(height: 1),

          // ── Éditeur de code ──────────────────────────────────────────────
          _FontSection(
            icon: Icons.code_rounded,
            color: AppColors.colorCode,
            title: 'Éditeur de code',
            subtitle: 'Code source, coloration syntaxique',
            families: _FontCatalog.mono,
            currentFamily: settings.codeFontFamily,
            onFamilyChanged: settings.setCodeFontFamily,
            currentSize: settings.codeFontSize,
            onSizeChanged: settings.setCodeFontSize,
            minSize: 8,
            maxSize: 24,
            previewText: 'void main() => runApp(MyApp());',
          ),
          const Divider(height: 1),

          // ── Markdown ─────────────────────────────────────────────────────
          _FontSection(
            icon: Icons.article_outlined,
            color: AppColors.colorDoc,
            title: 'Markdown',
            subtitle: 'Corps du texte dans le visionneur markdown',
            families: _FontCatalog.text,
            currentFamily: settings.markdownFontFamily,
            onFamilyChanged: settings.setMarkdownFontFamily,
            currentSize: settings.markdownFontSize,
            onSizeChanged: settings.setMarkdownFontSize,
            minSize: 10,
            maxSize: 24,
            previewText: 'Il était une fois un explorateur de fichiers.',
          ),
          const Divider(height: 1),

          // ── Texte brut ────────────────────────────────────────────────────
          _FontSection(
            icon: Icons.text_snippet_outlined,
            color: AppColors.colorText,
            title: 'Texte brut',
            subtitle: 'Fichiers .txt, .log, .csv',
            families: _FontCatalog.mono,
            currentFamily: settings.textFontFamily,
            onFamilyChanged: settings.setTextFontFamily,
            currentSize: settings.textFontSize,
            onSizeChanged: settings.setTextFontSize,
            minSize: 8,
            maxSize: 24,
            previewText: '2024-01-01 12:00:00  INFO  Application started',
          ),
          const Divider(height: 1),

          // ── Texte enrichi ─────────────────────────────────────────────────
          _FontSection(
            icon: Icons.format_color_text_rounded,
            color: const Color(0xFF2B579A),
            title: 'Texte enrichi',
            subtitle: 'Éditeur avec gras, italique, couleurs',
            families: _FontCatalog.text,
            currentFamily: settings.richFontFamily,
            onFamilyChanged: settings.setRichFontFamily,
            currentSize: settings.richFontSize,
            onSizeChanged: settings.setRichFontSize,
            minSize: 10,
            maxSize: 28,
            previewText: 'Texte en gras, italique et souligné.',
          ),
          const Divider(height: 1),

          // ── Hexadécimal ───────────────────────────────────────────────────
          _FontSection(
            icon: Icons.memory_rounded,
            color: AppColors.colorUnknown,
            title: 'Hexadécimal',
            subtitle: 'Éditeur de données binaires',
            families: _FontCatalog.mono,
            currentFamily: settings.hexFontFamily,
            onFamilyChanged: settings.setHexFontFamily,
            currentSize: settings.hexFontSize,
            onSizeChanged: settings.setHexFontSize,
            minSize: 8,
            maxSize: 18,
            previewText: '00000000  48 65 6C 6C 6F 20 57 6F  Hello Wo',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Section polices pour un type d'éditeur.
class _FontSection extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;
  final List<String>  families;
  final String         currentFamily;
  final void Function(String) onFamilyChanged;
  // Taille absolue (éditeurs)
  final int?           currentSize;
  final void Function(int)? onSizeChanged;
  final int            minSize;
  final int            maxSize;
  // Échelle (UI)
  final bool           isScale;
  final double?        scaleValue;
  final void Function(double)? onScaleChanged;
  final String         previewText;

  const _FontSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.families,
    required this.currentFamily,
    required this.onFamilyChanged,
    this.currentSize,
    this.onSizeChanged,
    this.minSize = 8,
    this.maxSize = 24,
    this.isScale = false,
    this.scaleValue,
    this.onScaleChanged,
    required this.previewText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Sélecteur de police ───────────────────────────────────────────
          Text('Police', style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: families.map((f) {
              final selected = f == currentFamily;
              return _FontChip(
                label: f,
                fontFamily: f,
                selected: selected,
                accentColor: color,
                onTap: () => onFamilyChanged(f),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // ── Taille ────────────────────────────────────────────────────────
          if (!isScale && currentSize != null && onSizeChanged != null)
            _SizeControl(
              label: 'Taille',
              value: currentSize!,
              min: minSize,
              max: maxSize,
              onChanged: onSizeChanged!,
              color: color,
            ),
          if (isScale && scaleValue != null && onScaleChanged != null)
            _ScaleControl(
              scale: scaleValue!,
              onChanged: onScaleChanged!,
              color: color,
            ),
          const SizedBox(height: 12),

          // ── Aperçu ────────────────────────────────────────────────────────
          _Preview(
            text: previewText,
            fontFamily: currentFamily,
            fontSize: isScale
                ? 13 * (scaleValue ?? 1.0)
                : (currentSize ?? 13).toDouble(),
            bgColor: color.withValues(alpha: 0.06),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FontChip extends StatelessWidget {
  final String   label;
  final String   fontFamily;
  final bool     selected;
  final Color    accentColor;
  final VoidCallback onTap;

  const _FontChip({
    required this.label,
    required this.fontFamily,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor : theme.dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: _FontCatalog.style(
            fontFamily,
            size: 12,
            color: selected ? accentColor : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SizeControl extends StatelessWidget {
  final String   label;
  final int      value;
  final int      min;
  final int      max;
  final void Function(int) onChanged;
  final Color    color;

  const _SizeControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 12),
        _StepBtn(
          icon: Icons.remove_rounded,
          onTap: value > min ? () => onChanged(value - 1) : null,
          color: color,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 6),
        _StepBtn(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
          color: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        Text('$max', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ScaleControl extends StatelessWidget {
  final double   scale;
  final void Function(double) onChanged;
  final Color    color;

  const _ScaleControl({
    required this.scale,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = '${(scale * 100).round()}%';
    return Row(
      children: [
        Text('Taille', style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 12),
        _StepBtn(
          icon: Icons.remove_rounded,
          onTap: scale > 0.75
              ? () => onChanged(double.parse((scale - 0.05).toStringAsFixed(2)))
              : null,
          color: color,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text(pct,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(width: 6),
        _StepBtn(
          icon: Icons.add_rounded,
          onTap: scale < 1.5
              ? () => onChanged(double.parse((scale + 0.05).toStringAsFixed(2)))
              : null,
          color: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: scale,
              min: 0.75,
              max: 1.50,
              divisions: 15,
              onChanged: (v) =>
                  onChanged(double.parse(v.toStringAsFixed(2))),
            ),
          ),
        ),
        const Text('150%', style: TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StepBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback? onTap;
  final Color        color;

  const _StepBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: onTap != null ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap != null ? color : Theme.of(context).disabledColor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Preview extends StatelessWidget {
  final String text;
  final String fontFamily;
  final double fontSize;
  final Color  bgColor;

  const _Preview({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(
        text,
        style: _FontCatalog.style(
          fontFamily,
          size: fontSize.clamp(8, 28),
          color: theme.textTheme.bodyLarge?.color,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
