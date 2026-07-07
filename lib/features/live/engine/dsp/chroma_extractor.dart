import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'dsp_config.dart';

/// Extracts a 12-dim chromagram from PCM frames (RAG chunks 002–003).
///
/// Pure and reusable: feed [process] a frame of [window] samples, get back the
/// EMA-smoothed, L2-normalised chroma (or null while below the silence gate).
/// Scratch buffers are reused — no per-frame allocation in the hot path.
class ChromaExtractor {
  ChromaExtractor({
    required this.sampleRate,
    this.window = DspConfig.chromaWindow,
  })  : _fft = FFT(window),
        _hann = Float64List(window),
        _windowed = Float64List(window),
        _mags = Float64List(window ~/ 2),
        _smoothed = List<double>.filled(12, 0),
        _raw = List<double>.filled(12, 0) {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
  }

  final int sampleRate;
  final int window;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final Float64List _mags;
  final List<double> _smoothed;
  final List<double> _raw;
  bool _hasSmoothed = false;

  /// Frame RMS of the last processed frame (drives the level meter + gate).
  double lastRms = 0;

  /// Tonalness of the last chroma, 0.25 (diffuse — speech/noise) … 1.0 (a clean
  /// triad): energy concentration in the top-3 pitch classes of the unit chroma.
  /// The chord path gates on this so diffuse frames don't fake a chord.
  double lastTonalness = 0;

  /// Process one frame of exactly [window] samples (-1..1). Returns the
  /// smoothed unit-norm chroma, or null when the frame is below the silence
  /// gate (never normalise noise — chunk 003).
  List<double>? process(Float64List frame) {
    assert(frame.length == window);

    var sumSq = 0.0;
    for (var i = 0; i < window; i++) {
      final s = frame[i];
      sumSq += s * s;
      _windowed[i] = s * _hann[i];
    }
    lastRms = math.sqrt(sumSq / window);
    if (lastRms < DspConfig.silenceRms) {
      _hasSmoothed = false; // silence resets the EMA — a new strum starts clean
      return null;
    }

    final spectrum = _fft.realFft(_windowed);

    // Spectral-PEAK accumulation (chunk 003). Naive per-bin mapping fails
    // below ~250 Hz where a semitone (< 8 Hz) is narrower than a bin
    // (~10.8 Hz) and leakage lands in neighbouring pitch classes. Instead:
    // local maxima + parabolic interpolation → sub-bin frequency, then snap.
    final nBins = window ~/ 2;
    var maxMag = 0.0;
    for (var k = 1; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      _mags[k] = math.sqrt(re * re + im * im);
      if (_mags[k] > maxMag) maxMag = _mags[k];
    }
    if (maxMag <= 0) return null;
    final peakFloor = maxMag * 0.002;
    _raw.fillRange(0, 12, 0);

    for (var k = 2; k < nBins - 1; k++) {
      final m = _mags[k];
      if (m < peakFloor || m <= _mags[k - 1] || m < _mags[k + 1]) continue;

      // Parabolic interpolation for the true (fractional-bin) frequency.
      final a = _mags[k - 1], c = _mags[k + 1];
      final denom = a - 2 * m + c;
      final p = denom == 0 ? 0.0 : (0.5 * (a - c) / denom).clamp(-0.5, 0.5);
      final f = (k + p) * sampleRate / window;
      if (f < DspConfig.chromaMinHz || f > DspConfig.chromaMaxHz) continue;

      final midi = 69 + 12 * (math.log(f / 440) / math.ln2);
      final nearest = midi.round();
      if ((midi - nearest).abs() > DspConfig.semitoneTolerance) continue;

      // For guitar triads the 3rd/5th harmonics land ON the fifth/third (chord
      // tones), so harmonics REINFORCE the template — hence a light octave
      // weighting to tame the highest partials, NOT full NNLS suppression
      // (which fights the triad templates; proper NNLS needs chord profiles).
      var energy = m * m;
      if (nearest >= 60) {
        energy /= 1 << ((nearest - 60) ~/ 12 + 1);
      }
      _raw[nearest % 12] += energy;
    }

    var norm = 0.0;
    for (final v in _raw) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) return null;

    // EMA smoothing (chunk 003), then re-normalise.
    final a = DspConfig.chromaEmaAlpha;
    var sNorm = 0.0;
    for (var i = 0; i < 12; i++) {
      final cur = _raw[i] / norm;
      _smoothed[i] = _hasSmoothed ? a * cur + (1 - a) * _smoothed[i] : cur;
      sNorm += _smoothed[i] * _smoothed[i];
    }
    _hasSmoothed = true;
    sNorm = math.sqrt(sNorm);
    final result = [for (final v in _smoothed) v / sNorm];

    // Tonalness = summed energy of the 3 strongest pitch classes (the unit
    // vector's squared entries sum to 1). A clean triad concentrates ~0.85+;
    // diffuse speech/noise spreads to ~0.3–0.45.
    final sq = [for (final v in result) v * v]..sort();
    lastTonalness = sq[11] + sq[10] + sq[9];

    return result;
  }
}
