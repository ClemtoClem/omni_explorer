/// @file visualizer_style.dart
/// @brief Catalogue des styles de visualiseur audio.
///
/// Les données alimentant les visualiseurs sont synthétiques (pas de FFT réelle
/// — `just_audio` n'expose pas le spectre côté Flutter). Les styles « stéréo »
/// font apparaître les deux canaux en utilisant des décalages de phase distincts
/// sur le même signal de base.

enum VisualizerFamily {
  spectrum,
  vu,
  circular,
  particle,
  oscilloscope,
}

/// Sous-mode du spectre (orientation des éléments).
enum SpectrumMode { bars, columns, frequency }

/// Sous-mode du VU-mètre.
enum VuMode { analog, digital, peakHold }

/// Sous-mode du visualiseur circulaire.
enum CircularMode { radialBars, glowingRings, pulsation }

/// Sous-mode du visualiseur de particules.
enum ParticleMode { artistic, vj }

/// Sous-mode (forme de l'oscilloscope).
enum OscilloscopeMode { mono, stereo, xy, lissajous }

/// Style visuel de l'oscilloscope (synthé / électronique / scientifique).
enum OscilloscopeStyle { synth, electronic, scientific }

/// Catalogue plat des styles utilisé par le sélecteur et la sérialisation.
enum VisualizerStyle {
  spectrumBarsMono,
  spectrumBarsStereo,
  spectrumColumnsMono,
  spectrumColumnsStereo,
  spectrumFrequencyMono,
  spectrumFrequencyStereo,
  vuAnalogMono,
  vuAnalogStereo,
  vuDigitalMono,
  vuDigitalStereo,
  vuPeakHoldMono,
  vuPeakHoldStereo,
  circularRadialBars,
  circularGlowingRings,
  circularPulsation,
  particleArtistic,
  particleVj,
  oscilloscopeSynthMono,
  oscilloscopeSynthStereo,
  oscilloscopeSynthXY,
  oscilloscopeSynthLissajous,
  oscilloscopeElectronicMono,
  oscilloscopeElectronicStereo,
  oscilloscopeElectronicXY,
  oscilloscopeElectronicLissajous,
  oscilloscopeScientificMono,
  oscilloscopeScientificStereo,
  oscilloscopeScientificXY,
  oscilloscopeScientificLissajous,
}

extension VisualizerStyleX on VisualizerStyle {
  String get label {
    switch (this) {
      case VisualizerStyle.spectrumBarsMono:           return 'Spectre — barres (mono)';
      case VisualizerStyle.spectrumBarsStereo:         return 'Spectre — barres (stéréo)';
      case VisualizerStyle.spectrumColumnsMono:        return 'Spectre — colonnes (mono)';
      case VisualizerStyle.spectrumColumnsStereo:      return 'Spectre — colonnes (stéréo)';
      case VisualizerStyle.spectrumFrequencyMono:      return 'Spectre fréquentiel (mono)';
      case VisualizerStyle.spectrumFrequencyStereo:    return 'Spectre fréquentiel (stéréo)';
      case VisualizerStyle.vuAnalogMono:               return 'VU analogique (mono)';
      case VisualizerStyle.vuAnalogStereo:             return 'VU analogique (stéréo)';
      case VisualizerStyle.vuDigitalMono:              return 'VU digital (mono)';
      case VisualizerStyle.vuDigitalStereo:            return 'VU digital (stéréo)';
      case VisualizerStyle.vuPeakHoldMono:             return 'VU peak-hold (mono)';
      case VisualizerStyle.vuPeakHoldStereo:           return 'VU peak-hold (stéréo)';
      case VisualizerStyle.circularRadialBars:         return 'Circulaire — barres radiales';
      case VisualizerStyle.circularGlowingRings:       return 'Circulaire — anneaux lumineux';
      case VisualizerStyle.circularPulsation:          return 'Circulaire — pulsation';
      case VisualizerStyle.particleArtistic:           return 'Particules — artistique';
      case VisualizerStyle.particleVj:                 return 'Particules — VJing';
      case VisualizerStyle.oscilloscopeSynthMono:      return 'Oscillo synthé (mono)';
      case VisualizerStyle.oscilloscopeSynthStereo:    return 'Oscillo synthé (stéréo)';
      case VisualizerStyle.oscilloscopeSynthXY:        return 'Oscillo synthé (XY)';
      case VisualizerStyle.oscilloscopeSynthLissajous: return 'Oscillo synthé (Lissajous)';
      case VisualizerStyle.oscilloscopeElectronicMono: return 'Oscillo électronique (mono)';
      case VisualizerStyle.oscilloscopeElectronicStereo: return 'Oscillo électronique (stéréo)';
      case VisualizerStyle.oscilloscopeElectronicXY:   return 'Oscillo électronique (XY)';
      case VisualizerStyle.oscilloscopeElectronicLissajous: return 'Oscillo électronique (Lissajous)';
      case VisualizerStyle.oscilloscopeScientificMono: return 'Oscillo scientifique (mono)';
      case VisualizerStyle.oscilloscopeScientificStereo: return 'Oscillo scientifique (stéréo)';
      case VisualizerStyle.oscilloscopeScientificXY:   return 'Oscillo scientifique (XY)';
      case VisualizerStyle.oscilloscopeScientificLissajous: return 'Oscillo scientifique (Lissajous)';
    }
  }

  VisualizerFamily get family {
    switch (this) {
      case VisualizerStyle.spectrumBarsMono:
      case VisualizerStyle.spectrumBarsStereo:
      case VisualizerStyle.spectrumColumnsMono:
      case VisualizerStyle.spectrumColumnsStereo:
      case VisualizerStyle.spectrumFrequencyMono:
      case VisualizerStyle.spectrumFrequencyStereo:
        return VisualizerFamily.spectrum;
      case VisualizerStyle.vuAnalogMono:
      case VisualizerStyle.vuAnalogStereo:
      case VisualizerStyle.vuDigitalMono:
      case VisualizerStyle.vuDigitalStereo:
      case VisualizerStyle.vuPeakHoldMono:
      case VisualizerStyle.vuPeakHoldStereo:
        return VisualizerFamily.vu;
      case VisualizerStyle.circularRadialBars:
      case VisualizerStyle.circularGlowingRings:
      case VisualizerStyle.circularPulsation:
        return VisualizerFamily.circular;
      case VisualizerStyle.particleArtistic:
      case VisualizerStyle.particleVj:
        return VisualizerFamily.particle;
      default:
        return VisualizerFamily.oscilloscope;
    }
  }

  bool get isStereo {
    return name.endsWith('Stereo');
  }
}
