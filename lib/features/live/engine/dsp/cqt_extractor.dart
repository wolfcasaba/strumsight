import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Constant-Q transform (CQT) feature front-end for the ML CHORD track.
///
/// This is a PARITY-CONTRACTED port of `ml/chords/cqt.py::cqt` (StrumSight
/// round 194 — see docs/plans/ml-chord-track.md P0.3). The chord model consumes
/// a CQT (constant-Q spacing puts every octave the same number of bins apart so
/// a chord looks the same shape at any root); it is NOT the log-mel the strum
/// model uses. Any change here MUST keep the golden-fixture test green
/// (test/features/live/dsp/cqt_parity_test.dart) and stay in sync with cqt.py.
///
/// Constants mirror `ml/chords/cqt.py` EXACTLY (do not "round" them):
///   SR = 22050, BINS_PER_OCTAVE = 24, N_OCTAVES = 6, N_BINS = 144,
///   HOP = 2048, FMIN = 32.70319566257483 (C1), GAMMA = 1.0,
///   SPARSITY_THRESH = 0.01.
///
/// Algorithm = the precomputed sparse spectral kernel method (Brown & Puckette
/// 1992), identical to cqt.py:
///   1. Per bin k, a Hann-windowed complex exponential temporal kernel of
///      length N_k = ceil(Q*SR/f_k), centred in an FFT frame of length FFT_LEN
///      (next pow2 >= the longest / lowest-bin kernel). Q = 1/(2^(1/BPO)-1).
///   2. FFT each temporal kernel ONCE -> a spectral kernel row; conjugate,
///      divide by FFT_LEN (Parseval), round to float32, and zero entries below
///      SPARSITY_THRESH of the global peak magnitude -> sparse (N_BINS, FFT_LEN).
///   3. Per audio hop: FFT the (centre-padded) frame and matrix-multiply by the
///      kernel; |result| is the CQT magnitude.
/// Post: log-amplitude = log(1 + GAMMA*|CQT|) (`log1p`), per-bin normalization
/// intentionally left to the caller (train-only mean/std, like the log-mel path).
///
/// Note on FFT sign convention: fftea's forward FFT may use the opposite
/// exponent sign to numpy's `np.fft.fft`, but the CQT here is a Parseval inner
/// product `<frame, temporal_k>` evaluated in the frequency domain. Because the
/// SAME FFT builds the kernel AND transforms every frame, the result is
/// identical for either sign convention (the sparsification zeroes the same
/// physical entries, just mirror-indexed), so the Dart output equals numpy's.
class CqtExtractor {
  // --- constants mirrored from ml/chords/cqt.py -----------------------------
  static const int sr = 22050;
  static const int binsPerOctave = 24;
  static const int nOctaves = 6;
  static const int nBins = binsPerOctave * nOctaves; // 144
  static const int hop = 2048; // ~93 ms @ 22.05 kHz
  static const double fMin = 32.70319566257483; // C1 (A4 = 440 Hz reference)
  static const double gamma = 1.0; // out = log(1 + gamma*|CQT|)
  static const double sparsityThresh = 0.01; // fraction of global peak |kernel|

  /// Constant-Q quality factor Q = 1 / (2^(1/binsPerOctave) - 1).
  static double get _q => 1.0 / (math.pow(2.0, 1.0 / binsPerOctave) - 1.0);

  static int _nextPow2(int x) {
    var p = 1;
    while (p < x) {
      p <<= 1;
    }
    return p;
  }

  // Lazily-built, cached sparse spectral kernel (shared across instances — it
  // depends only on the module constants). Per bin: the non-zero frequency
  // indices and the conjugated/scaled/float32-rounded kernel value at each.
  static List<Int32List>? _kernelIdx;
  static List<Float64List>? _kernelRe;
  static List<Float64List>? _kernelIm;
  static int _fftLen = 0;
  static FFT? _fft;

  /// np.hanning(m): symmetric Hann, denominator M-1 (M==1 -> [1.0]).
  static Float64List _hanning(int m) {
    final w = Float64List(m);
    if (m == 1) {
      w[0] = 1.0;
      return w;
    }
    for (var n = 0; n < m; n++) {
      w[n] = 0.5 - 0.5 * math.cos(2 * math.pi * n / (m - 1));
    }
    return w;
  }

  // Round a double to float32 precision (matches numpy's .astype(float32)).
  static final Float32List _f32 = Float32List(1);
  static double _toF32(double x) {
    _f32[0] = x;
    return _f32[0];
  }

  static void _buildKernel() {
    if (_kernelIdx != null) return;
    final q = _q;
    final nLo = (q * sr / fMin).ceil(); // longest kernel = lowest bin
    final fftLen = _nextPow2(nLo);
    final fft = FFT(fftLen);

    // Full dense kernel rows (complex) so we can find the global peak magnitude
    // before sparsifying, exactly like cqt.py.
    final rowsRe = <Float64List>[];
    final rowsIm = <Float64List>[];
    var globalMax = 0.0;
    for (var k = 0; k < nBins; k++) {
      final fk = fMin * math.pow(2.0, k / binsPerOctave);
      final nk = (q * sr / fk).ceil();
      final win = _hanning(nk);
      final start = (fftLen - nk) ~/ 2; // centre the kernel in the frame
      // temporal[n] = (win/nk) * exp(2j*pi*q*n/nk)
      final tk = ComplexArray.fromRealArray(Float64List(fftLen));
      for (var n = 0; n < nk; n++) {
        final phase = 2 * math.pi * q * n / nk;
        final amp = win[n] / nk;
        tk[start + n] = Float64x2(amp * math.cos(phase), amp * math.sin(phase));
      }
      fft.inPlaceFft(tk);
      final re = Float64List(fftLen);
      final im = Float64List(fftLen);
      for (var f = 0; f < fftLen; f++) {
        final v = tk[f];
        re[f] = v.x;
        im[f] = v.y;
        final mag = math.sqrt(v.x * v.x + v.y * v.y);
        if (mag > globalMax) globalMax = mag;
      }
      rowsRe.add(re);
      rowsIm.add(im);
    }

    // Sparsify (drop |kernel| < thresh*peak), conjugate, Parseval 1/N, float32.
    final cutoff = sparsityThresh * globalMax;
    final idx = <Int32List>[];
    final outRe = <Float64List>[];
    final outIm = <Float64List>[];
    for (var k = 0; k < nBins; k++) {
      final re = rowsRe[k];
      final im = rowsIm[k];
      final ii = <int>[];
      final rr = <double>[];
      final jj = <double>[];
      for (var f = 0; f < fftLen; f++) {
        final mag = math.sqrt(re[f] * re[f] + im[f] * im[f]);
        if (mag < cutoff) continue;
        // conj(kernel)/fftLen, rounded to float32 (numpy astype(complex64)).
        ii.add(f);
        rr.add(_toF32(re[f] / fftLen));
        jj.add(_toF32(-im[f] / fftLen));
      }
      idx.add(Int32List.fromList(ii));
      outRe.add(Float64List.fromList(rr));
      outIm.add(Float64List.fromList(jj));
    }

    _kernelIdx = idx;
    _kernelRe = outRe;
    _kernelIm = outIm;
    _fftLen = fftLen;
    _fft = fft;
  }

  /// FFT frame length (next pow2 >= longest kernel). Exposed for tests.
  static int get fftLen {
    _buildKernel();
    return _fftLen;
  }

  /// Number of CQT frames for [nSamples] input samples (centred hops), matching
  /// cqt.py::n_frames: any non-empty signal yields >= 1 frame.
  static int nFrames(int nSamples) {
    if (nSamples <= 0) return 0;
    return 1 + (nSamples - 1) ~/ hop;
  }

  /// Linear resample to [sr] (matches cqt.py::_resample / np.interp).
  static Float32List _resample(Float32List pcm, int inputSr) {
    if (inputSr == sr || pcm.isEmpty) return pcm;
    final n = (pcm.length * sr / inputSr).round();
    if (n <= 0) return Float32List(0);
    final out = Float32List(n);
    final last = pcm.length - 1;
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? 0.0 : last * i / (n - 1); // np.linspace(0, len-1, n)
      final x0 = x.floor();
      if (x0 >= last) {
        out[i] = pcm[last];
      } else {
        final frac = x - x0;
        out[i] = _toF32(pcm[x0] + (pcm[x0 + 1] - pcm[x0]) * frac);
      }
    }
    return out;
  }

  /// Log-amplitude CQT of a mono [-1, 1] signal -> `nFrames` rows of [nBins]
  /// float32 values. Frames are centre-padded (fftLen/2 each side). Empty input
  /// returns an empty list. Resamples internally if [inputSr] != [sr].
  ///
  /// Mirrors `ml/chords/cqt.py::cqt(pcm, sr)`; orientation is (nFrames, nBins).
  List<Float32List> extract(Float32List pcm, int inputSr) {
    _buildKernel();
    final idx = _kernelIdx!, kre = _kernelRe!, kim = _kernelIm!;
    final fft = _fft!;
    final fftLen = _fftLen;

    final resampled = _resample(pcm, inputSr);
    final ns = resampled.length;
    if (ns == 0) return <Float32List>[];

    final nf = nFrames(ns);
    final pad = fftLen ~/ 2;
    // Centre-padded signal (float32, matching numpy's float32 padded/frames).
    final padded = Float64List(ns + 2 * pad);
    for (var i = 0; i < ns; i++) {
      padded[pad + i] = resampled[i]; // resampled already float32-valued
    }

    final out = <Float32List>[];
    for (var i = 0; i < nf; i++) {
      final s = i * hop;
      final frame = Float64List(fftLen);
      for (var j = 0; j < fftLen; j++) {
        frame[j] = padded[s + j];
      }
      final spec = fft.realFft(frame); // full complex spectrum, length fftLen
      final row = Float32List(nBins);
      for (var k = 0; k < nBins; k++) {
        final ii = idx[k], rr = kre[k], jj = kim[k];
        var accRe = 0.0, accIm = 0.0;
        for (var t = 0; t < ii.length; t++) {
          final sv = spec[ii[t]];
          final a = sv.x, b = sv.y; // frame spectrum
          final c = rr[t], d = jj[t]; // conj-scaled kernel
          // (a+bi)(c+di)
          accRe += a * c - b * d;
          accIm += a * d + b * c;
        }
        final mag = math.sqrt(accRe * accRe + accIm * accIm);
        row[k] = _toF32(math.log(1.0 + gamma * mag));
      }
      out.add(row);
    }
    return out;
  }
}
