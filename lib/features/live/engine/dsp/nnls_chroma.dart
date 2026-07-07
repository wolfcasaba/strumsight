import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Chordino-class chroma (RAG chunk 011): STFT → log-frequency spectrum →
/// **NNLS approximate note transcription** against a harmonic dictionary →
/// 12-bin chroma. The transcription explains each note's overtones with the
/// dictionary, so a bass fundamental's partials don't leak into other pitch
/// classes — the classic reliability win over raw peak/template chroma.
///
/// Pure & deterministic. A large window (≈0.37 s) is required so a semitone is
/// resolvable down at low E (≈4.8 Hz apart) — fine for the slow chord path.
class NnlsChroma {
  NnlsChroma({
    required this.sampleRate,
    this.window = 16384,
    this.minMidi = 40, // E2 ≈ 82 Hz
    this.maxMidi = 88, // E6 ≈ 1319 Hz
    this.binsPerSemitone = 3,
    this.harmonics = 12,
    this.spectralShape = 0.7,
    this.nnlsIterations = 20,
    this.silenceRms = 0.008,
  })  : _fft = FFT(window),
        _hann = Float64List(window),
        _windowed = Float64List(window),
        nNotes = maxMidi - minMidi + 1 {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
    _nBins = nNotes * binsPerSemitone;
    _binFreq = Float64List(_nBins);
    for (var j = 0; j < _nBins; j++) {
      final midi = minMidi + j / binsPerSemitone;
      _binFreq[j] = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    }
    _buildDictionary();
    _activation = Float64List(nNotes);
    _s = Float64List(_nBins);
    _dtS = Float64List(nNotes);
    _dtDx = Float64List(nNotes);
  }

  final int sampleRate;
  final int window;
  final int minMidi;
  final int maxMidi;
  final int binsPerSemitone;
  final int harmonics;
  final double spectralShape;
  final int nnlsIterations;
  final double silenceRms;

  final int nNotes;
  late final int _nBins;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  late final Float64List _binFreq;

  // Harmonic dictionary: _dict[note] is a sparse-ish column over the _nBins
  // log-frequency axis (unit L2). _dtd is DᵀD (nNotes × nNotes), precomputed.
  late final List<Float64List> _dict;
  late final List<Float64List> _dtd;

  late final Float64List _activation;
  late final Float64List _s;
  late final Float64List _dtS;
  late final Float64List _dtDx;

  double lastRms = 0;

  /// Tonalness of the last chroma (top-3 pitch-class energy of the unit
  /// vector): ~1.0 for a clean chord, low for a diffuse/noisy frame.
  double lastTonalness = 0;

  void _buildDictionary() {
    _dict = List.generate(nNotes, (_) => Float64List(_nBins));
    for (var n = 0; n < nNotes; n++) {
      final col = _dict[n];
      final base = n * binsPerSemitone + binsPerSemitone ~/ 2; // note centre bin
      for (var h = 1; h <= harmonics; h++) {
        // Harmonic h sits log2(h) octaves above → +12·log2(h) semitones.
        final offsetBins =
            (binsPerSemitone * 12 * (math.log(h) / math.ln2)).round();
        final j = base + offsetBins;
        if (j >= 0 && j < _nBins) {
          col[j] += math.pow(spectralShape, h - 1).toDouble();
        }
      }
      // Unit-normalise the column so activations are comparable across notes.
      var norm = 0.0;
      for (final v in col) {
        norm += v * v;
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (var j = 0; j < _nBins; j++) {
          col[j] /= norm;
        }
      }
    }

    // Precompute DᵀD.
    _dtd = List.generate(nNotes, (_) => Float64List(nNotes));
    for (var a = 0; a < nNotes; a++) {
      for (var b = a; b < nNotes; b++) {
        var dot = 0.0;
        final ca = _dict[a], cb = _dict[b];
        for (var j = 0; j < _nBins; j++) {
          dot += ca[j] * cb[j];
        }
        _dtd[a][b] = dot;
        _dtd[b][a] = dot;
      }
    }
  }

  /// Process one [window]-sample frame → 12-bin unit chroma (or null if silent).
  List<double>? process(Float64List frame) {
    assert(frame.length == window);

    var sumSq = 0.0;
    for (var i = 0; i < window; i++) {
      final x = frame[i];
      sumSq += x * x;
      _windowed[i] = x * _hann[i];
    }
    lastRms = math.sqrt(sumSq / window);
    if (lastRms < silenceRms) return null;

    // 1) STFT magnitude → log-frequency spectrum (linear interp at bin centres).
    final spec = _fft.realFft(_windowed);
    final nFft = window ~/ 2;
    var maxS = 0.0;
    for (var j = 0; j < _nBins; j++) {
      final kc = _binFreq[j] * window / sampleRate; // fractional FFT bin
      final k0 = kc.floor();
      double mag;
      if (k0 < 1 || k0 + 1 >= nFft) {
        mag = 0;
      } else {
        final m0 = _mag(spec, k0), m1 = _mag(spec, k0 + 1);
        final t = kc - k0;
        mag = m0 * (1 - t) + m1 * t;
      }
      _s[j] = mag;
      if (mag > maxS) maxS = mag;
    }
    if (maxS <= 0) return null;

    // 2) NNLS: min ‖D·x − s‖², x ≥ 0, via non-negative multiplicative updates
    //    x ← x · (Dᵀs) / (DᵀD·x + ε). Warm, cheap, converges to the NNLS fit.
    for (var n = 0; n < nNotes; n++) {
      var dot = 0.0;
      final col = _dict[n];
      for (var j = 0; j < _nBins; j++) {
        dot += col[j] * _s[j];
      }
      _dtS[n] = dot;
      _activation[n] = dot > 0 ? dot : 0; // non-negative warm start
    }
    const eps = 1e-9;
    for (var it = 0; it < nnlsIterations; it++) {
      for (var a = 0; a < nNotes; a++) {
        var v = 0.0;
        final row = _dtd[a];
        for (var b = 0; b < nNotes; b++) {
          v += row[b] * _activation[b];
        }
        _dtDx[a] = v;
      }
      for (var n = 0; n < nNotes; n++) {
        _activation[n] *= _dtS[n] / (_dtDx[n] + eps);
      }
    }

    // 3) Fold note activations to 12 pitch classes; L2-normalise.
    final chroma = List<double>.filled(12, 0);
    for (var n = 0; n < nNotes; n++) {
      chroma[(minMidi + n) % 12] += _activation[n];
    }
    var norm = 0.0;
    for (final v in chroma) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) return null;
    for (var i = 0; i < 12; i++) {
      chroma[i] /= norm;
    }

    final sq = [for (final v in chroma) v * v]..sort();
    lastTonalness = sq[11] + sq[10] + sq[9];

    return chroma;
  }

  static double _mag(List<dynamic> spec, int k) {
    final c = spec[k];
    return math.sqrt(c.x * c.x + c.y * c.y);
  }
}
