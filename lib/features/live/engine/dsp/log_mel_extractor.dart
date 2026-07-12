import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Log-mel spectrogram front-end for the on-device strum-direction model
/// (docs/plans/ml-track.md P0.1; RAG chunk 018).
///
/// This is a PARITY-CONTRACTED port of `ml/features.py::log_mel`: 16 kHz,
/// 2048-sample Hann window / 160-sample hop (10 ms frames), 128 triangular
/// HTK-mel filters from 30 Hz to Nyquist, `log(melPower + 1e-6)`. The trained
/// model consumes exactly these features, so any change here MUST keep the
/// golden-fixture test green (test/features/live/dsp/log_mel_extractor_test.dart)
/// and stay in sync with the Python side + chunk 018.
class LogMelExtractor {
  LogMelExtractor({
    required this.sampleRate,
    this.nFft = 2048,
    this.hop = 160,
    this.nMels = 128,
    this.fMin = 30.0,
  })  : _fft = FFT(nFft),
        _hann = Float64List(nFft),
        _windowed = Float64List(nFft),
        _power = Float64List(nFft ~/ 2 + 1),
        _filterStart = Int32List(nMels),
        _filterWeights = List.generate(nMels, (_) => Float64List(0)) {
    // np.hanning: symmetric Hann, denominator N-1 (matches ChromaExtractor).
    for (var i = 0; i < nFft; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (nFft - 1));
    }
    _buildFilterbank();
  }

  final int sampleRate;
  final int nFft;
  final int hop;
  final int nMels;
  final double fMin;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final Float64List _power;

  /// Sparse triangular filters: per mel, the first non-zero FFT bin and the
  /// contiguous weights from there (the triangle is the only non-zero run).
  final Int32List _filterStart;
  final List<Float64List> _filterWeights;

  static double _hzToMel(double f) => 2595.0 * (math.log(1.0 + f / 700.0) / math.ln10);
  static double _melToHz(double m) => 700.0 * (math.pow(10.0, m / 2595.0) - 1.0);

  void _buildFilterbank() {
    final nBins = nFft ~/ 2 + 1;
    final fMax = sampleRate / 2;
    final melLo = _hzToMel(fMin);
    final melHi = _hzToMel(fMax);
    final hzPts = List<double>.generate(
      nMels + 2,
      (i) => _melToHz(melLo + (melHi - melLo) * i / (nMels + 1)),
    );
    for (var m = 0; m < nMels; m++) {
      final lo = hzPts[m], ce = hzPts[m + 1], hi = hzPts[m + 2];
      var start = -1;
      final weights = <double>[];
      for (var k = 0; k < nBins; k++) {
        final f = k * sampleRate / 2 / (nBins - 1);
        double w;
        if (f >= lo && f <= ce && ce > lo) {
          w = (f - lo) / (ce - lo);
        } else if (f > ce && f <= hi && hi > ce) {
          w = (hi - f) / (hi - ce);
        } else {
          w = 0.0;
        }
        if (w > 0) {
          if (start < 0) start = k;
          weights.add(w);
        } else if (start >= 0 && f > hi) {
          break; // past the triangle — the non-zero run is contiguous
        }
      }
      _filterStart[m] = start < 0 ? 0 : start;
      _filterWeights[m] = Float64List.fromList(weights);
    }
  }

  /// Log-mel of one [nFft]-sample frame (no hop logic — the streaming
  /// primitive the live path will call per hop).
  Float64List processFrame(Float64List frame, [Float64List? out]) {
    assert(frame.length == nFft);
    for (var i = 0; i < nFft; i++) {
      _windowed[i] = frame[i] * _hann[i];
    }
    final spectrum = _fft.realFft(_windowed);
    final nBins = nFft ~/ 2 + 1;
    for (var k = 0; k < nBins; k++) {
      // realFft returns nFft/2+1 unique bins first; index k is bin k.
      final re = spectrum[k].x, im = spectrum[k].y;
      _power[k] = re * re + im * im;
    }
    final mel = out ?? Float64List(nMels);
    for (var m = 0; m < nMels; m++) {
      final start = _filterStart[m];
      final w = _filterWeights[m];
      var acc = 0.0;
      for (var j = 0; j < w.length; j++) {
        acc += w[j] * _power[start + j];
      }
      mel[m] = math.log(acc + 1e-6);
    }
    return mel;
  }

  /// Batch log-mel of a mono [-1, 1] signal: `1 + (n - nFft) ~/ hop` frames
  /// (empty when the signal is shorter than one window) — mirrors
  /// `ml/features.py::log_mel` exactly.
  List<Float64List> process(Float64List pcm) {
    if (pcm.length < nFft) return const [];
    final n = 1 + (pcm.length - nFft) ~/ hop;
    return List.generate(
      n,
      (i) => processFrame(
        Float64List.sublistView(pcm, i * hop, i * hop + nFft),
      ),
    );
  }
}
