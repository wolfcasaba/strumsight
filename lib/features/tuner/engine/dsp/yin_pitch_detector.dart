import 'dart:math' as math;
import 'dart:typed_data';

/// YIN fundamental-frequency estimator (RAG chunk 008).
///
/// Time-domain: difference function → cumulative-mean-normalised difference
/// (CMNDF) → absolute threshold → parabolic interpolation. Chosen over plain
/// autocorrelation for far fewer octave errors on low guitar strings.
class YinPitchDetector {
  YinPitchDetector({
    required this.sampleRate,
    this.bufferSize = 4096,
    this.threshold = 0.12,
    double minFrequency = 60,
  }) : _maxLag = (sampleRate / minFrequency).floor() {
    assert(_maxLag < bufferSize ~/ 2,
        'buffer must hold ≥2 periods of the lowest pitch');
    _d = Float64List(_maxLag + 1);
    _cmndf = Float64List(_maxLag + 1);
  }

  final int sampleRate;
  final int bufferSize;

  /// CMNDF dip threshold; 0.10–0.15 is the standard range.
  final double threshold;

  final int _maxLag;
  late final Float64List _d;
  late final Float64List _cmndf;

  /// Clarity (periodicity) of the LAST [detect] call, 0..1 — the McLeod-style
  /// tone-likeness measure `1 − CMNDF[τ]`. A cleanly plucked string is ~0.95+;
  /// voiced speech and noise are lower. 0 when no pitch was found. Callers gate
  /// on this to reject voice/noise (the primary voiced/unvoiced discriminator).
  double clarity = 0;

  /// Estimated f0 in Hz, or null when no confident pitch is present.
  double? detect(Float64List buffer) {
    assert(buffer.length >= bufferSize);
    final w = bufferSize - _maxLag; // correlation window

    // 1) Difference function.
    for (var tau = 1; tau <= _maxLag; tau++) {
      var sum = 0.0;
      for (var j = 0; j < w; j++) {
        final diff = buffer[j] - buffer[j + tau];
        sum += diff * diff;
      }
      _d[tau] = sum;
    }

    // 2) Cumulative mean normalised difference.
    _cmndf[0] = 1;
    var running = 0.0;
    for (var tau = 1; tau <= _maxLag; tau++) {
      running += _d[tau];
      _cmndf[tau] = running == 0 ? 1 : _d[tau] * tau / running;
    }

    // 3) Absolute threshold: first dip below it, then descend to the local
    // minimum.
    var tau = -1;
    for (var t = 2; t <= _maxLag; t++) {
      if (_cmndf[t] < threshold) {
        while (t + 1 <= _maxLag && _cmndf[t + 1] < _cmndf[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      clarity = 0;
      return null;
    }
    // Tone-likeness of the chosen dip (1 = perfectly periodic).
    clarity = (1 - _cmndf[tau]).clamp(0.0, 1.0);

    // 4) Parabolic interpolation around the minimum.
    var tauF = tau.toDouble();
    if (tau > 1 && tau < _maxLag) {
      final a = _cmndf[tau - 1], b = _cmndf[tau], c = _cmndf[tau + 1];
      final denom = a - 2 * b + c;
      if (denom != 0) {
        tauF += (0.5 * (a - c) / denom).clamp(-0.5, 0.5);
      }
    }
    return sampleRate / tauF;
  }
}

/// Maps a frequency to the nearest note + cents offset (chunk 008).
({String note, double cents}) noteForFrequency(double f0, {double a4 = 440}) {
  const names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];
  final midi = 69 + 12 * (math.log(f0 / a4) / math.ln2);
  final nearest = midi.round();
  final cents = ((midi - nearest) * 100).clamp(-50.0, 50.0).toDouble();
  return (note: names[((nearest % 12) + 12) % 12], cents: cents);
}
