import 'dart:math' as math;

import '../../model/chord.dart';
import 'dsp_config.dart';

/// Result of matching one chroma frame.
class ChordMatch {
  const ChordMatch(this.chord, this.confidence);

  final Chord chord;

  /// 0..1 — strength × decisiveness (RAG chunk 004).
  final double confidence;
}

/// 24-template (maj/min) chord matcher with anti-flicker hysteresis
/// (RAG chunk 004). Pure: chroma in → stable chord out.
class ChordMatcher {
  ChordMatcher() {
    _buildTemplates();
  }

  static const _pitchClasses = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];
  static const _qualities = <String, List<int>>{
    '': [0, 4, 7], // major
    'm': [0, 3, 7], // minor
  };

  late final List<String> _labels;
  late final List<List<double>> _templates;

  String? _reported; // currently reported (hysteresis-stable) chord
  String? _candidate;
  int _candidateStreak = 0;
  double _reportedConfidence = 0;

  void _buildTemplates() {
    _labels = [];
    _templates = [];
    final norm = 1 / math.sqrt(3);
    for (final entry in _qualities.entries) {
      for (var root = 0; root < 12; root++) {
        final vec = List<double>.filled(12, 0);
        for (final o in entry.value) {
          vec[(root + o) % 12] = norm;
        }
        _labels.add(_pitchClasses[root] + entry.key);
        _templates.add(vec);
      }
    }
  }

  /// Match one smoothed unit-norm chroma frame; null chroma (silence) decays
  /// the reported chord. Returns the stable (hysteresis-filtered) result, or
  /// null when nothing is sounding.
  ChordMatch? process(List<double>? chroma) {
    if (chroma == null) {
      // Silence: decay, and drop the chord entirely once confidence dies.
      _reportedConfidence *= 0.8;
      _candidate = null;
      _candidateStreak = 0;
      if (_reportedConfidence < 0.1) _reported = null;
      return _reported == null
          ? null
          : ChordMatch(Chord(_reported!), _reportedConfidence);
    }

    var best = -1.0, second = -1.0;
    var bestIdx = 0;
    for (var c = 0; c < _templates.length; c++) {
      var dot = 0.0;
      final t = _templates[c];
      for (var i = 0; i < 12; i++) {
        dot += t[i] * chroma[i];
      }
      if (dot > best) {
        second = best;
        best = dot;
        bestIdx = c;
      } else if (dot > second) {
        second = dot;
      }
    }

    final label = _labels[bestIdx];
    final margin = best <= 0 ? 0.0 : (best - second) / best;
    final confidence = (best * (0.5 + 2 * margin)).clamp(0.0, 1.0);

    // Hysteresis (chunk 004): switch on 3 consecutive wins, or instantly on a
    // decisive one.
    if (label == _reported) {
      _candidate = null;
      _candidateStreak = 0;
      _reportedConfidence = confidence;
    } else if (confidence >= DspConfig.chordInstantSwitchConfidence) {
      _reported = label;
      _reportedConfidence = confidence;
      _candidate = null;
      _candidateStreak = 0;
    } else {
      if (label == _candidate) {
        _candidateStreak++;
      } else {
        _candidate = label;
        _candidateStreak = 1;
      }
      if (_candidateStreak >= DspConfig.chordHysteresisFrames) {
        _reported = label;
        _reportedConfidence = confidence;
        _candidate = null;
        _candidateStreak = 0;
      } else if (_reported != null) {
        // Keep the old chord, slightly decayed, while the challenger proves out.
        _reportedConfidence *= 0.95;
      }
    }

    _reported ??= label;
    if (_reportedConfidence == 0) _reportedConfidence = confidence;
    return ChordMatch(Chord(_reported!), _reportedConfidence);
  }

  /// Reset all hysteresis state (new session).
  void reset() {
    _reported = null;
    _candidate = null;
    _candidateStreak = 0;
    _reportedConfidence = 0;
  }
}
