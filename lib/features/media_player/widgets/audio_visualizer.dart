/// @file audio_visualizer.dart
/// @brief Dispatcher de visualiseur audio : reçoit les données synthétiques
/// (magnitudes spectrales L/R + waveform L/R + phase + niveau) et délègue à
/// la famille de visualiseur sélectionnée par [VisualizerStyle].

import 'package:flutter/material.dart';
import '../models/visualizer_style.dart';
import 'circular_spectrum_visualizer.dart';
import 'oscilloscope_visualizer.dart';
import 'particle_visualizer.dart';
import 'spectrum_visualizer.dart';
import 'vu_meter_visualizer.dart';

class AudioVisualizer extends StatelessWidget {
  /// Magnitudes 0..1 du canal gauche (ou unique en mono).
  final List<double> magnitudesL;
  /// Magnitudes 0..1 du canal droit (mêmes mags que L en mono).
  final List<double> magnitudesR;
  /// Échantillons -1..1 du canal gauche (pour oscilloscope).
  final List<double> waveformL;
  /// Échantillons -1..1 du canal droit.
  final List<double> waveformR;
  final bool isPlaying;
  /// Phase d'animation continue, croît en permanence.
  final double phase;
  /// Niveau global 0..1 (RMS du spectre).
  final double level;
  final VisualizerStyle style;

  const AudioVisualizer({
    super.key,
    required this.magnitudesL,
    required this.magnitudesR,
    required this.waveformL,
    required this.waveformR,
    required this.isPlaying,
    required this.phase,
    required this.level,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    switch (style.family) {
      case VisualizerFamily.spectrum:
        return SpectrumVisualizer(
          magnitudesL: magnitudesL,
          magnitudesR: magnitudesR,
          isPlaying: isPlaying,
          mode: _spectrumMode(),
          stereo: style.isStereo,
        );
      case VisualizerFamily.vu:
        return VuMeterVisualizer(
          magnitudesL: magnitudesL,
          magnitudesR: magnitudesR,
          isPlaying: isPlaying,
          mode: _vuMode(),
          stereo: style.isStereo,
        );
      case VisualizerFamily.circular:
        return CircularSpectrumVisualizer(
          magnitudes: magnitudesL,
          isPlaying: isPlaying,
          mode: _circularMode(),
          phase: phase,
        );
      case VisualizerFamily.particle:
        return ParticleVisualizer(
          level: level,
          isPlaying: isPlaying,
          mode: style == VisualizerStyle.particleVj
              ? ParticleMode.vj
              : ParticleMode.artistic,
        );
      case VisualizerFamily.oscilloscope:
        return OscilloscopeVisualizer(
          waveformL: waveformL,
          waveformR: waveformR,
          isPlaying: isPlaying,
          mode: _oscMode(),
          style: _oscStyle(),
        );
    }
  }

  SpectrumMode _spectrumMode() {
    switch (style) {
      case VisualizerStyle.spectrumColumnsMono:
      case VisualizerStyle.spectrumColumnsStereo:
        return SpectrumMode.columns;
      case VisualizerStyle.spectrumFrequencyMono:
      case VisualizerStyle.spectrumFrequencyStereo:
        return SpectrumMode.frequency;
      default:
        return SpectrumMode.bars;
    }
  }

  VuMode _vuMode() {
    switch (style) {
      case VisualizerStyle.vuAnalogMono:
      case VisualizerStyle.vuAnalogStereo:
        return VuMode.analog;
      case VisualizerStyle.vuDigitalMono:
      case VisualizerStyle.vuDigitalStereo:
        return VuMode.digital;
      default:
        return VuMode.peakHold;
    }
  }

  CircularMode _circularMode() {
    switch (style) {
      case VisualizerStyle.circularGlowingRings:
        return CircularMode.glowingRings;
      case VisualizerStyle.circularPulsation:
        return CircularMode.pulsation;
      default:
        return CircularMode.radialBars;
    }
  }

  OscilloscopeMode _oscMode() {
    final n = style.name;
    if (n.endsWith('Stereo')) return OscilloscopeMode.stereo;
    if (n.endsWith('XY')) return OscilloscopeMode.xy;
    if (n.endsWith('Lissajous')) return OscilloscopeMode.lissajous;
    return OscilloscopeMode.mono;
  }

  OscilloscopeStyle _oscStyle() {
    final n = style.name;
    if (n.contains('Electronic')) return OscilloscopeStyle.electronic;
    if (n.contains('Scientific')) return OscilloscopeStyle.scientific;
    return OscilloscopeStyle.synth;
  }
}
