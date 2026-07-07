import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/tuner_reading.dart';
import 'yin_pitch_detector.dart';

/// PCM buffer → [TunerReading]. Robust against voice/noise the way real tuners
/// are (McLeod/YIN literature): a note is only shown when the signal is (1) loud
/// enough, (2) strongly periodic (YIN clarity), (3) in the guitar range, AND
/// (4) STABLE across several frames — the median of that stable window is what
/// gets displayed. Speech glides and its consonants are noisy, so it fails the
/// clarity+stability gates. Pure and streaming.
class TunerAnalyzer {
  TunerAnalyzer({
    required this.sampleRate,
    this.a4 = 440,
    this.silenceRms = 0.014,
    this.minClarity = 0.85,
    this.minHz = 70,
    this.maxHz = 1320,
    this.stabilityCents = 30,
    this.stableFrames = 4,
  }) : _yin = YinPitchDetector(sampleRate: sampleRate);

  final int sampleRate;

  /// Concert-pitch reference A4 in Hz — shifts the note/cents mapping.
  final int a4;

  /// Level gate: below this RMS the frame is treated as silence.
  final double silenceRms;

  /// Minimum YIN clarity (tone-likeness, 0..1) — the voiced/unvoiced gate.
  final double minClarity;

  /// Accepted pitch range (Hz). Guitar spans ~E2 (82) to ~E6 (1318).
  final double minHz;
  final double maxHz;

  /// A note only locks once the recent estimates agree within this many cents…
  final double stabilityCents;

  /// …across this many consecutive frames (rejects speech's constant glide).
  final int stableFrames;

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
    if (rms < silenceRms) return _unstable();

    final f0 = _yin.detect(buffer);
    // Gate on periodicity (clarity), validity and instrument range.
    if (f0 == null ||
        _yin.clarity < minClarity ||
        f0 < minHz ||
        f0 > maxHz) {
      return _unstable();
    }

    _recent.add(f0);
    if (_recent.length > stableFrames) _recent.removeAt(0);

    // Need a full window of agreement before showing anything.
    if (_recent.length < stableFrames) return TunerReading.silent;

    final sorted = [..._recent]..sort();
    final median = sorted[sorted.length ~/ 2];
    for (final f in _recent) {
      final cents = 1200 * math.log(f / median) / math.ln2;
      if (cents.abs() > stabilityCents) {
        // The pitch is moving (speech/vibrato/transition) — don't lock yet.
        return TunerReading.silent;
      }
    }

    // Stable, clear, in-range note: report the median (jitter-free).
    final mapped = noteForFrequency(median, a4: a4.toDouble());
    return TunerReading(
      note: mapped.note,
      cents: mapped.cents,
      frequencyHz: median,
    );
  }

  /// Reset the stability window and report silence.
  TunerReading _unstable() {
    _recent.clear();
    return TunerReading.silent;
  }
}
