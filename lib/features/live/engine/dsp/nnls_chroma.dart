import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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
    this.bassMaxMidi = 52, // E3 — bass/root register upper edge
    this.trebleMinMidi = 40, // E2 — treble spans the FULL range (see below)
    this.tuningEstimation = true,
    this.tuningSmoothing = 0.2,
    this.spectralWhitening = true,
    this.whiteningExponent = 0.7,
    this.whiteningHalfSemitones = 3.0,
    this.whiteningMeanCoefficient = 0.0,
    this.referenceRegisterWindows = true,
  }) : _fft = FFT(window),
       _hann = Float64List(window),
       _windowed = Float64List(window),
       nNotes = maxMidi - minMidi + 1 {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
    _nBins = nNotes * binsPerSemitone;
    _whiteningHalfWindow = (whiteningHalfSemitones * binsPerSemitone).round();
    _bassWeight = Float64List(nNotes);
    _trebleWeight = Float64List(nNotes);
    for (var n = 0; n < nNotes; n++) {
      final midi = minMidi + n;
      if (referenceRegisterWindows) {
        // Hann windows indexed in semitones from A0 (MIDI 21), exactly as
        // the reference tables are: `0.5 - 0.5*cos(2*pi*(i + 0.5)/len)`
        // reproduces `basswindow`/`treblewindow` to all six printed digits.
        final i = midi - 21;
        _bassWeight[n] = (i < 0 || i > 36)
            ? 0.0
            : 0.5 - 0.5 * math.cos(2 * math.pi * (i + 0.5) / 37);
        _trebleWeight[n] = (i < 0 || i > 83)
            ? 0.0
            : 0.5 - 0.5 * math.cos(2 * math.pi * (i + 0.5) / 84);
      } else {
        _bassWeight[n] = midi <= bassMaxMidi ? 1.0 : 0.0;
        _trebleWeight[n] = midi >= trebleMinMidi ? 1.0 : 0.0;
      }
    }
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

  /// Per-frame tuning estimation (chunk 012, Chordino stage): real guitars sit
  /// 10–40 cents off concert pitch, which — measured, round 69 — mis-names a
  /// 35-cent-flat C major as B. When enabled, each frame's sub-semitone offset
  /// is estimated from the log-freq spectrum (circular mean of the 3-bin
  /// phase), EMA-smoothed by [tuningSmoothing], and the spectrum is resampled
  /// at the shifted frequencies so note centres line up again.
  final bool tuningEstimation;
  final double tuningSmoothing;

  /// Spectral whitening (chunk 012, Chordino stage): divide each log-freq bin
  /// by the RMS of its ±[whiteningHalfSemitones] neighbourhood raised to
  /// [whiteningExponent], flattening the spectral envelope BEFORE NNLS.
  /// Measured round-70 failure it fixes: a phone mic's low-shelf roll-off
  /// (fundamentals ×0.15 below 300 Hz) read a C major as Em — the notes were
  /// outvoted by their own harmonics' register.
  final bool spectralWhitening;
  final double whiteningExponent;

  /// Half-width of the normalisation neighbourhood, in SEMITONES.
  ///
  /// ±3 semitones (a minor third). The span matters as much as the whitening
  /// itself, because it sets what "loud" is measured against: at a WIDE span a
  /// bin is normalised against most of an octave, so a quiet tone stays quiet
  /// relative to its loud neighbours, while at a NARROW span each local peak is
  /// normalised by its own neighbourhood and the peaks are pulled toward a
  /// common level.
  ///
  /// For guitar that distinction decides the chord, because a guitar voicing is
  /// not level-flat: the fifth is doubled across two or three strings while the
  /// third is fretted exactly once, so the tone that determines the QUALITY is
  /// routinely the quietest thing in the signal. MEASURED on the E18-R01
  /// reference recordings: in the open E the third G#3 sat at 0.12 of the peak
  /// against the fifth B2 at 0.97, and the decoder returned `Bsus4` — a profile
  /// built wholly on the loud root and fifth, with the chord's own third
  /// invisible. The open G read `Bm` / `Dsus4` the same way.
  ///
  /// The span is bounded from BOTH sides, and the two bounds are the same
  /// mechanism seen in two registers (ADR 0540):
  /// - too WIDE and a quiet third never becomes evidence — the seven labelled
  ///   recordings score 5/7 correct at ±6 and ±5, 6/7 at ±4, and 7/7 from ±3.5
  ///   down;
  /// - too NARROW and the peak levelling also erodes the ROOT's natural
  ///   dominance, which is the only thing naming the root in the bass chroma —
  ///   at 7 bins (±2.4 and below) `test/property/dsp_property_test.dart` loses
  ///   low-voiced dominant 7ths to a diminished triad on their own third
  ///   (`B7` → `D#dim`, i.e. B7 with its root gone) on 4 of the 5 documented
  ///   seeds.
  ///
  /// ±3.0 is 9 bins at [binsPerSemitone] 3: two bins above that property cliff
  /// (8 bins also passes everything) and inside the real-audio plateau.
  /// Verified at this value — the seven recordings 7/7 correct with all seven
  /// `confirmed` through the full `LivePipeline` (was 4/7 correct, with D never
  /// confirming), and `dsp_property_test.dart` green on seeds 42, 7, 123, 2026
  /// and 31337.
  ///
  /// The round-70 envelope guards this whitening exists for (phone-mic low
  /// shelf, body resonance) hold across the ENTIRE sweep — the span was never
  /// the knob that fixed the thin mic, [whiteningExponent] was — so the span is
  /// free to be chosen on the criteria above.
  ///
  /// Expressed in semitones on purpose: the bin count it converts to depends on
  /// [binsPerSemitone], and while this was stored as a raw BIN COUNT the two
  /// could silently desync — a change to [binsPerSemitone] moved the musical
  /// span without anyone editing the constant. That is not hypothetical; it
  /// produced a wrong diagnosis once (see the E18-R06 section of
  /// `docs/rag/chunks/012-chord-dictionary-viterbi.md`). The musical quantity
  /// is what matters, so the musical quantity is what is stored.
  ///
  /// The span is quantised to the bin grid, so several nearby values collapse
  /// onto the same neighbourhood: at [binsPerSemitone] 3 the effective
  /// half-window is `round(whiteningHalfSemitones * 3)` bins.
  final double whiteningHalfSemitones;

  /// How much of the local mean whitening SUBTRACTS before dividing, from 0
  /// (today's behaviour: divide only) to 1 (the reference's arithmetic).
  ///
  /// The reference (`Chordino.cpp:333-345`) computes `d = spec - runningmean`
  /// and then `d > 0 ? d / runningstd^w : 0`. Subtracting makes the whitener a
  /// true local-CONTRAST operator — a bin must exceed its neighbourhood to
  /// survive — and the half-wave rectification zeroes everything at or below the
  /// local mean, which suppresses noise floors and the skirts of strong peaks far
  /// harder than dividing by an RMS does.
  ///
  /// MEASURED, and the reason this is a dial rather than a switch. At the full
  /// reference value the engine hears a great deal MORE on real recordings — a
  /// file that named nothing at all across 12.7 s went to 112 confirmed frames,
  /// 90% of them in the labelled key — but it also lost a QUIET MAJOR THIRD, so
  /// an open E whose third sits at 0.08 read as `Em`. Confusing major with minor
  /// is the worst error this app can make: those are the chords the beginner
  /// course teaches, and a learner playing E correctly would be told they played
  /// Em. The coefficient exists so that trade can be measured instead of taken.
  ///
  /// The kernel stays a flat box regardless: the reference's Hamming weighting is
  /// a SEPARATE difference, and changing two things at once makes a measurement
  /// unreadable.
  final double whiteningMeanCoefficient;

  /// [whiteningHalfSemitones] on the log-frequency bin grid — derived once in
  /// the constructor, never per bin: [_whiten] reads it inside a per-bin loop.
  int get whiteningHalfWindow => _whiteningHalfWindow;
  late final int _whiteningHalfWindow;

  /// Register split for the bass+treble chroma (RAG chunk 012). The **treble**
  /// chroma folds the whole harmony (activations at/above [trebleMinMidi],
  /// defaulting to the full note range) — the chord tones that decide quality.
  /// The **bass** chroma folds only the low sub-register (at/below
  /// [bassMaxMidi]) to surface the root/bass note, which disambiguates
  /// inversions, slash chords and quality. Guitar chords voice low (roots
  /// E2–D3), so a high treble floor would drop the root and third out of the
  /// harmony — hence treble spans everything and bass is the isolating cut.
  final int bassMaxMidi;
  final int trebleMinMidi;

  /// EXPERIMENT (E18-R07): fold the registers with the reference
  /// implementation's smooth raised-cosine weights instead of the hard
  /// [bassMaxMidi] / [trebleMinMidi] cuts. See `chromamethods.h` in
  /// c4dm/nnls-chroma: `basswindow` is a Hann of length 37 semitones from
  /// A0 (MIDI 21), `treblewindow` a Hann of length 84 from the same base.
  final bool referenceRegisterWindows;

  late final Float64List _bassWeight;
  late final Float64List _trebleWeight;

  /// The bass-register weight applied to [midi] when folding to 12 bins, or 0
  /// for a note outside the analysed range. Test seam: the depth ORDERING is
  /// the property that names a root, so a test must be able to read it without
  /// inferring it from a decoded label.
  @visibleForTesting
  double debugBassWeightForMidi(int midi) {
    final n = midi - minMidi;
    return (n < 0 || n >= nNotes) ? 0 : _bassWeight[n];
  }

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

  /// Smoothed tuning offset of the input in semitones (−0.5..0.5); 0 when
  /// in tune or when [tuningEstimation] is off. Positive = instrument sharp.
  double lastTuningSemitones = 0;
  bool _tuningInit = false;

  /// Bass-register chroma (12, L2-normalised) of the last processed frame —
  /// the root/bass note. Zeros on a silent frame. See [bassMaxMidi] (chunk 012).
  final Float64List lastBassChroma = Float64List(12);

  /// Treble-register chroma (12, L2-normalised) of the last processed frame —
  /// the harmony. Zeros on a silent frame. See [trebleMinMidi] (chunk 012).
  final Float64List lastTrebleChroma = Float64List(12);

  void _buildDictionary() {
    _dict = List.generate(nNotes, (_) => Float64List(_nBins));
    for (var n = 0; n < nNotes; n++) {
      final col = _dict[n];
      // Note centre bin. On the [_binFreq] grid `midi = minMidi + j/bps`, so
      // note n's exact frequency sits at bin n·bps — NOT n·bps + bps~/2, which
      // silently biased the whole dictionary +1/3 semitone SHARP (measured in
      // round 69: a 35-cent-flat C major decoded as B while +35 cents passed).
      final base = n * binsPerSemitone;
      for (var h = 1; h <= harmonics; h++) {
        // Harmonic h sits log2(h) octaves above → +12·log2(h) semitones.
        final offsetBins = (binsPerSemitone * 12 * (math.log(h) / math.ln2))
            .round();
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
    var maxS = _sampleLogFreq(spec, nFft, 1.0);
    if (maxS <= 0) return null;

    // 1b) Tuning estimation (chunk 012): the sub-semitone offset of the input
    //     is the circular mean of energy over the 3 within-semitone bin
    //     phases. EMA-smooth it across frames, then RESAMPLE the spectrum at
    //     the shifted frequencies so a detuned instrument's partials land on
    //     the note-centre bins again. Skipped for near-zero offsets — the
    //     nominal grid is already right.
    if (tuningEstimation) {
      var re = 0.0, im = 0.0;
      for (var j = 0; j < _nBins; j++) {
        final theta = 2 * math.pi * (j % binsPerSemitone) / binsPerSemitone;
        final w = _s[j] * _s[j]; // energy-weight the peaks
        re += w * math.cos(theta);
        im += w * math.sin(theta);
      }
      if (re != 0 || im != 0) {
        // atan2 already lands in (−0.5, 0.5] semitone — no wrap needed.
        final frac = math.atan2(im, re) / (2 * math.pi);
        _tuningInit
            ? lastTuningSemitones =
                  lastTuningSemitones +
                  tuningSmoothing * (frac - lastTuningSemitones)
            : lastTuningSemitones = frac;
        _tuningInit = true;
      }
      if (lastTuningSemitones.abs() > 0.02) {
        final factor = math.pow(2, lastTuningSemitones / 12).toDouble();
        maxS = _sampleLogFreq(spec, nFft, factor);
        if (maxS <= 0) return null;
      }
    }

    // 1c) Spectral whitening (chunk 012): flatten the envelope so timbre/EQ
    //     (phone-mic bass roll-off, body resonances) can't outvote the notes.
    if (spectralWhitening) _whiten(maxS);

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

    // 3) Fold note activations to 12 pitch classes; L2-normalise. Fold the
    //    bass and treble registers SEPARATELY too (chunk 012): the bass chroma
    //    carries the root, the treble chroma the harmony.
    final chroma = List<double>.filled(12, 0);
    for (var i = 0; i < 12; i++) {
      lastBassChroma[i] = 0;
      lastTrebleChroma[i] = 0;
    }
    for (var n = 0; n < nNotes; n++) {
      final midi = minMidi + n;
      final pc = midi % 12;
      final a = _activation[n];
      chroma[pc] += a;
      lastBassChroma[pc] += a * _bassWeight[n];
      lastTrebleChroma[pc] += a * _trebleWeight[n];
    }
    _l2Normalise(lastBassChroma);
    _l2Normalise(lastTrebleChroma);

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

  /// Whiten [_s] in place: each bin ÷ RMS(±[whiteningHalfWindow] neighbours)
  /// ^[whiteningExponent]. The RMS floor (relative to [maxS]) keeps true
  /// silence from being amplified into structure.
  void _whiten(double maxS) {
    if (whiteningMeanCoefficient > 0) {
      _whitenByLocalContrast(maxS);
      return;
    }
    final prefix = Float64List(_nBins + 1);
    for (var j = 0; j < _nBins; j++) {
      prefix[j + 1] = prefix[j] + _s[j] * _s[j];
    }
    final floor = 1e-4 * maxS;
    for (var j = 0; j < _nBins; j++) {
      final lo = math.max(0, j - whiteningHalfWindow);
      final hi = math.min(_nBins - 1, j + whiteningHalfWindow);
      var rms = math.sqrt((prefix[hi + 1] - prefix[lo]) / (hi - lo + 1));
      if (rms < floor) rms = floor;
      _s[j] = _s[j] / math.pow(rms, whiteningExponent);
    }
  }

  /// The reference arithmetic: subtract the running mean, divide by the running
  /// standard deviation raised to [whiteningExponent], and half-wave rectify.
  ///
  /// Two box passes, both by prefix sum: the first gives each bin's local mean,
  /// the second the local mean of the squared deviations — each bin's deviation
  /// measured from ITS OWN local mean, as the reference does it.
  ///
  /// The standard-deviation FLOOR is ours, not the reference's: without it a
  /// silent neighbourhood divides by ~0 and turns numerical dust into structure.
  /// The reference has no such guard because it never runs on a live microphone
  /// that can be handed pure silence.
  void _whitenByLocalContrast(double maxS) {
    final prefix = Float64List(_nBins + 1);
    for (var j = 0; j < _nBins; j++) {
      prefix[j + 1] = prefix[j] + _s[j];
    }
    final mean = Float64List(_nBins);
    final deviation = Float64List(_nBins);
    for (var j = 0; j < _nBins; j++) {
      final lo = math.max(0, j - whiteningHalfWindow);
      final hi = math.min(_nBins - 1, j + whiteningHalfWindow);
      mean[j] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
      final d = _s[j] - whiteningMeanCoefficient * mean[j];
      deviation[j] = d * d;
    }
    final devPrefix = Float64List(_nBins + 1);
    for (var j = 0; j < _nBins; j++) {
      devPrefix[j + 1] = devPrefix[j] + deviation[j];
    }
    final floor = 1e-4 * maxS;
    for (var j = 0; j < _nBins; j++) {
      final lo = math.max(0, j - whiteningHalfWindow);
      final hi = math.min(_nBins - 1, j + whiteningHalfWindow);
      final d = _s[j] - whiteningMeanCoefficient * mean[j];
      if (d <= 0) {
        // Half-wave rectification: at or below the local mean is nothing.
        _s[j] = 0;
        continue;
      }
      var std = math.sqrt((devPrefix[hi + 1] - devPrefix[lo]) / (hi - lo + 1));
      if (std < floor) std = floor;
      _s[j] = d / math.pow(std, whiteningExponent);
    }
  }

  /// Sample the STFT magnitude at each log-freq bin centre × [tuningFactor]
  /// (linear interp between FFT bins) into [_s]; returns the max magnitude.
  double _sampleLogFreq(List<dynamic> spec, int nFft, double tuningFactor) {
    var maxS = 0.0;
    for (var j = 0; j < _nBins; j++) {
      final kc =
          _binFreq[j] * tuningFactor * window / sampleRate; // fractional bin
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
    return maxS;
  }

  static void _l2Normalise(Float64List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) return;
    for (var i = 0; i < v.length; i++) {
      v[i] /= norm;
    }
  }

  static double _mag(List<dynamic> spec, int k) {
    final c = spec[k];
    return math.sqrt(c.x * c.x + c.y * c.y);
  }
}
