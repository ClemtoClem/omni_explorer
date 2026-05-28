/// @file theme_picker_screen.dart
/// @brief Écran de sélection et personnalisation du thème de couleur.
///
/// Offre :
/// - 3 modes de luminosité : Sombre / Système / Clair
/// - 10 thèmes prédéfinis affichés en grille
/// - Un éditeur de thème personnalisé avec roue HSV et curseur de luminosité

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/theme/app_theme_presets.dart';
import '../../../core/services/settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// @class ThemePickerScreen
/// @brief Écran principal de sélection du thème.
class ThemePickerScreen extends StatefulWidget {
  const ThemePickerScreen({super.key});

  @override
  State<ThemePickerScreen> createState() => _ThemePickerScreenState();
}

class _ThemePickerScreenState extends State<ThemePickerScreen> {
  // État de la roue de couleur personnalisée
  double _hue        = 210.0; // Bleu par défaut
  double _saturation = 0.80;
  double _brightness = 0.95;
  bool   _showCustom = false;

  @override
  void initState() {
    super.initState();
    // Synchronise la roue avec le preset actuel si c'est un custom
    final preset = context.read<SettingsService>().themePreset;
    if (preset.id == 'custom') {
      final hsv = HSVColor.fromColor(preset.accent);
      _hue        = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
    } else {
      final hsv = HSVColor.fromColor(preset.accent);
      _hue        = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
    }
  }

  Color get _currentCustomColor =>
      HSVColor.fromAHSV(1, _hue, _saturation, _brightness).toColor();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme    = Theme.of(context);
    final accent   = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apparence'),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Mode de luminosité ───────────────────────────────────────────
          const _SectionTitle('LUMINOSITÉ'),
          const SizedBox(height: 10),
          _BrightnessSelector(
            current: settings.themeMode,
            onChanged: settings.setThemeMode,
          ),

          const SizedBox(height: 28),

          // ── Thèmes prédéfinis ────────────────────────────────────────────
          const _SectionTitle('THÈMES PRÉDÉFINIS'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   2,
              childAspectRatio: 1.7,
              crossAxisSpacing: 10,
              mainAxisSpacing:  10,
            ),
            itemCount: AppThemePresets.all.length,
            itemBuilder: (_, i) {
              final preset = AppThemePresets.all[i];
              final isSelected = settings.themePreset.id == preset.id;
              return _PresetCard(
                preset:     preset,
                isSelected: isSelected,
                onTap: () {
                  settings.setThemePreset(preset);
                  setState(() => _showCustom = false);
                },
              );
            },
          ),

          const SizedBox(height: 28),

          // ── Thème personnalisé ───────────────────────────────────────────
          Row(
            children: [
              const _SectionTitle('THÈME PERSONNALISÉ'),
              const Spacer(),
              IconButton(
                icon: AnimatedRotation(
                  turns: _showCustom ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.expand_more_rounded),
                ),
                onPressed: () => setState(() => _showCustom = !_showCustom),
                tooltip: _showCustom ? 'Réduire' : 'Développer',
              ),
            ],
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _showCustom
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildCustomEditor(settings, accent),
            secondChild: _CustomPreview(
              color:      _currentCustomColor,
              isSelected: settings.themePreset.id == 'custom',
              onTap: () => setState(() => _showCustom = true),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Éditeur personnalisé ───────────────────────────────────────────────────

  Widget _buildCustomEditor(SettingsService settings, Color accent) {
    final isCustomActive = settings.themePreset.id == 'custom';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCustomActive
              ? _currentCustomColor
              : Theme.of(context).dividerColor,
          width: isCustomActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Roue de couleur ────────────────────────────────────────────
          Center(
            child: _ColorWheel(
              hue:        _hue,
              saturation: _saturation,
              brightness: _brightness,
              size:       220,
              onChanged: (h, s) => setState(() {
                _hue        = h;
                _saturation = s;
              }),
            ),
          ),
          const SizedBox(height: 20),

          // ── Curseur de luminosité ─────────────────────────────────────
          Text('Luminosité',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          _BrightnessSlider(
            value: _brightness,
            color: HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
            onChanged: (v) => setState(() => _brightness = v),
          ),
          const SizedBox(height: 16),

          // ── Curseur de saturation ─────────────────────────────────────
          Text('Saturation',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          _SaturationSlider(
            value: _saturation,
            hue: _hue,
            brightness: _brightness,
            onChanged: (v) => setState(() => _saturation = v),
          ),
          const SizedBox(height: 20),

          // ── Aperçu + code hex ─────────────────────────────────────────
          Row(
            children: [
              // Swatch couleur sélectionnée
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _currentCustomColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _currentCustomColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Couleur d\'accent',
                        style: Theme.of(context).textTheme.labelMedium),
                    Text(
                      '#${_currentCustomColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                      // ignore: deprecated_member_use
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Bouton Appliquer ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Appliquer ce thème'),
              style: FilledButton.styleFrom(
                backgroundColor: _currentCustomColor,
                foregroundColor: _contrastColor(_currentCustomColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                settings.setCustomAccent(_currentCustomColor);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Retourne blanc ou noir selon le contraste avec [bg].
  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.35 ? Colors.black87 : Colors.white;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets internes
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

// ── Sélecteur de luminosité ────────────────────────────────────────────────

class _BrightnessSelector extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;
  const _BrightnessSelector(
      {required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.dark,
          icon:  Icon(Icons.dark_mode_rounded),
          label: Text('Sombre'),
        ),
        ButtonSegment(
          value: ThemeMode.system,
          icon:  Icon(Icons.brightness_auto_rounded),
          label: Text('Système'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon:  Icon(Icons.light_mode_rounded),
          label: Text('Clair'),
        ),
      ],
      selected:    {current},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── Carte de preset ────────────────────────────────────────────────────────

class _PresetCard extends StatelessWidget {
  final ThemePreset  preset;
  final bool         isSelected;
  final VoidCallback onTap;
  const _PresetCard(
      {required this.preset, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? preset.accent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: preset.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Gradient de prévisualisation
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12)),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            preset.darkBg,
                            preset.darkSurface,
                            preset.accent,
                            preset.lightSurface2,
                            preset.lightBg,
                          ],
                          begin: Alignment.topLeft,
                          end:   Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          preset.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                  ),
                ),
                // Nom du thème
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        preset.name,
                        style: Theme.of(context).textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Badge sélectionné
            if (isSelected)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: preset.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Aperçu compact du thème custom ────────────────────────────────────────

class _CustomPreview extends StatelessWidget {
  final Color        color;
  final bool         isSelected;
  final VoidCallback onTap;
  const _CustomPreview(
      {required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎨 Personnalisé',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                    // ignore: deprecated_member_use
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined,
                size: 18,
                color: Theme.of(context).iconTheme.color),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Roue HSV
// ─────────────────────────────────────────────────────────────────────────────

/// @class _ColorWheel
/// @brief Roue de couleur interactive en espace HSV.
///
/// Utilise deux dégradés superposés (SweepGradient + RadialGradient) pour
/// représenter la teinte et la saturation. La luminosité est contrôlée
/// séparément par [_BrightnessSlider].
class _ColorWheel extends StatefulWidget {
  final double hue;
  final double saturation;
  final double brightness;
  final double size;
  final void Function(double hue, double saturation) onChanged;

  const _ColorWheel({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.size,
    required this.onChanged,
  });

  @override
  State<_ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<_ColorWheel> {
  void _handlePan(Offset local) {
    final radius = widget.size / 2;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Calcul de la teinte : atan2 → angle en degrés depuis le nord
    final rawAngle = math.atan2(dy, dx) * 180 / math.pi;
    final hue = (rawAngle + 90 + 360) % 360;

    // Saturation : distance / rayon, clampée à [0 ; 1]
    final sat = (dist / radius).clamp(0.0, 1.0);

    widget.onChanged(hue, sat);
  }

  /// Convertit [hue] et [saturation] en position (x, y) dans le widget.
  Offset _indicatorPos() {
    final radius = widget.size / 2;
    final angle  = (widget.hue - 90) * math.pi / 180;
    final dist   = widget.saturation * radius;
    return Offset(
      radius + dist * math.cos(angle),
      radius + dist * math.sin(angle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return GestureDetector(
      onPanStart:  (d) => _handlePan(d.localPosition),
      onPanUpdate: (d) => _handlePan(d.localPosition),
      onTapDown:   (d) => _handlePan(d.localPosition),
      child: SizedBox(
        width:  size,
        height: size,
        child: CustomPaint(
          painter: _WheelPainter(widget.brightness),
          child: CustomPaint(
            painter: _IndicatorPainter(
              position:   _indicatorPos(),
              color: HSVColor.fromAHSV(
                1, widget.hue, widget.saturation, widget.brightness,
              ).toColor(),
            ),
          ),
        ),
      ),
    );
  }
}

/// @class _WheelPainter
/// @brief Dessine la roue HSV avec SweepGradient + RadialGradient.
class _WheelPainter extends CustomPainter {
  final double brightness;
  _WheelPainter(this.brightness);

  @override
  void paint(Canvas canvas, Size size) {
    final c    = size.center(Offset.zero);
    final r    = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // ── Couche 1 : dégradé de teinte (SweepGradient) ─────────────────────
    // 13 couleurs couvrant 0→360° pour une interpolation lisse.
    final hueColors = List<Color>.generate(
      13,
      (i) => HSVColor.fromAHSV(1, i * 30.0, 1, brightness).toColor(),
    );
    canvas.drawCircle(
      c, r,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2, // rouge au sommet
          endAngle:    math.pi * 3 / 2,
          colors: hueColors,
        ).createShader(rect),
    );

    // ── Couche 2 : saturation (blanc au centre → transparent) ─────────────
    canvas.drawCircle(
      c, r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // ── Couche 3 : assombrissement si brightness < 1 ───────────────────────
    if (brightness < 1.0) {
      canvas.drawCircle(
        c, r,
        Paint()..color = Colors.black.withValues(alpha: 1 - brightness),
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.brightness != brightness;
}

/// @class _IndicatorPainter
/// @brief Dessine l'indicateur de position sur la roue.
class _IndicatorPainter extends CustomPainter {
  final Offset position;
  final Color  color;
  _IndicatorPainter({required this.position, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 12.0;
    // Ombre portée
    canvas.drawCircle(
      position,
      r + 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Fond blanc
    canvas.drawCircle(position, r + 2, Paint()..color = Colors.white);
    // Couleur sélectionnée
    canvas.drawCircle(position, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.position != position || old.color != color;
}

// ── Curseur de luminosité ──────────────────────────────────────────────────

class _BrightnessSlider extends StatelessWidget {
  final double value;
  final Color  color;
  final ValueChanged<double> onChanged;
  const _BrightnessSlider(
      {required this.value, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [Colors.black, color],
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 0,
          thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 14),
          overlayShape:
              const RoundSliderOverlayShape(overlayRadius: 20),
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          thumbColor: HSVColor.fromAHSV(1, 0, 0, value).toColor(),
        ),
        child: Slider(
          value:    value,
          min:      0.1,
          max:      1.0,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Curseur de saturation ──────────────────────────────────────────────────

class _SaturationSlider extends StatelessWidget {
  final double value;
  final double hue;
  final double brightness;
  final ValueChanged<double> onChanged;
  const _SaturationSlider({
    required this.value,
    required this.hue,
    required this.brightness,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fullColor =
        HSVColor.fromAHSV(1, hue, 1, brightness).toColor();
    final grayColor =
        HSVColor.fromAHSV(1, hue, 0, brightness).toColor();

    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [grayColor, fullColor],
        ),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 0,
          thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 14),
          overlayShape:
              const RoundSliderOverlayShape(overlayRadius: 20),
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          thumbColor:
              HSVColor.fromAHSV(1, hue, value, brightness).toColor(),
        ),
        child: Slider(
          value:    value,
          min:      0.0,
          max:      1.0,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
