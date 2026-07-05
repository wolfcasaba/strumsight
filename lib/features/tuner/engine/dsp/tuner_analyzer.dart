import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/tuner_reading.dart';
import 'yin_pitch_detector.dart';

/// PCM buffer → [TunerReading]: silence gate + YIN + note/cents mapping +
/// median-of-3 stabilisation (RAG chunk 008). Pure and streaming.
class TunerAnalyzer {
  TunerAnalyzer({required this.sampleRate, this.silenceRms = 0.008})
      : _yin = YinPitchDetector(sampleRate: sampleRate);

  final int sampleRate;
  final double silenceRms;
  final YinPitchDetector _yin;

  final List<double> _recent = [];

  int get bufferSize => _yin.bufferSize;

  /// Analyse one buffer of at least [bufferSize] samples.
  TunerReading process(Float64List buffer) {
    var sumSq = 0.0;
    for (final s in buffer) {
      sumSq += s * s;
    }
    final rms = math.sqrt(sumSq / buffer.length);
    if (rms < silenceRms) {
      _recent.clear();
      return TunerReading.silent;
    }

    final f0 = _yin.detect(buffer);
    if (f0 == null) {
      _recent.clear();
      return TunerReading.silent;
    }

    // Median of the last 3 estimates — one glitchy frame must not jerk the
    // gauge.
    _recent.add(f0);
    if (_recent.length > 3) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final stable = sorted[sorted.length ~/ 2];

    final mapped = noteForFrequency(stable);
    return TunerReading(
      note: mapped.note,
      cents: mapped.cents,
      frequencyHz: stable,
    );
  }
}
