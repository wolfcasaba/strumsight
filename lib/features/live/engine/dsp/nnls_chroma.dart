import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
// `package:meta`, not `package:flutter/foundation` — which only re-exports this
// annotation anyway. With it, the whole chord chain (this file, `dsp_config`,
// `chord_dictionary`, `chord_matcher`, `viterbi_chord_decoder`) is Flutter-free,
// as SDD Ch2 §10.1 asks of DSP. The practical payoff: it can be compiled AOT by
// `dart compile exe` and benchmarked the way it actually ships, instead of only
// under the test runner's JIT.
import 'package:meta/meta.dart' show visibleForTesting;

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
    this.whiteningExponent = defaultWhiteningExponent,
    this.whiteningHalfSemitones = 3.0,
    this.whiteningMeanCoefficient = defaultWhiteningMeanCoefficient,
    this.whiteningSpectralFloor = defaultWhiteningSpectralFloor,
    this.whiteningHammingKernel = defaultWhiteningHammingKernel,
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
    // The Hamming kernel over the WHOLE neighbourhood (2H+1 taps), from the
    // textbook definition `0.54 - 0.46*cos(2*pi*i/(N-1))` — derived here, never
    // copied from a table. The running prefix of the weights is what makes the
    // edge re-normalisation O(1): the in-bounds weight sum for any bin is one
    // subtraction of two prefix entries.
    final taps = 2 * _whiteningHalfWindow + 1;
    _hammingKernel = Float64List(taps);
    _hammingKernelPrefix = Float64List(taps + 1);
    for (var i = 0; i < taps; i++) {
      _hammingKernel[i] = taps == 1
          ? 1.0
          : 0.54 - 0.46 * math.cos(2 * math.pi * i / (taps - 1));
      _hammingKernelPrefix[i + 1] = _hammingKernelPrefix[i] + _hammingKernel[i];
    }
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
    _whitenPrefix = Float64List(_nBins + 1);
    _whitenMean = Float64List(_nBins);
    _whitenWork = Float64List(_nBins);
    _whitenVariance = Float64List(_nBins);
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

  /// The shipped whitening exponent, named so a caller that only wants to
  /// OVERRIDE it sometimes (the sweep harness) has one place to fall back to
  /// rather than a second copy of the literal that could silently desync.
  static const double defaultWhiteningExponent = 0.7;

  /// The SHIPPED normalisation kernel for whitening: Hamming-weighted.
  ///
  /// Named rather than inlined so there is exactly one place that says what ships
  /// — the constructor default and any test that asserts "the shipped kernel is
  /// X" read the SAME constant, instead of a literal in each that can disagree
  /// silently. MEASURED in `docs/research/hamming-whitening-kernel-2026-09.md`.
  static const bool defaultWhiteningHammingKernel = true;

  /// The SHIPPED amount of local mean the whitener subtracts, and the SHIPPED
  /// rectifier floor. Named for the same reason as the kernel above: a probe or
  /// sweep that wants "the shipped value unless overridden" must be able to say
  /// so, instead of writing `?? 0.0` and silently pinning the dial to a value
  /// that used to be the default. That exact bug was found in
  /// `real_audio_hearing_probe_test.dart`, whose comment promised the shipped
  /// value while its code pinned zero.
  static const double defaultWhiteningMeanCoefficient = 0.20;
  static const double defaultWhiteningSpectralFloor = 0.0;

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
  /// The kernel is chosen separately by [whiteningHammingKernel], because
  /// changing two things at once makes a measurement unreadable.
  final double whiteningMeanCoefficient;

  /// The SPECTRAL FLOOR of the rectifier, as a fraction of the bin's own
  /// magnitude: 0 = today's hard zero, β > 0 keeps `β · s[j]` where the hard
  /// zero kept nothing.
  ///
  /// Why a floor at all. With [whiteningMeanCoefficient] > 0 the whitener
  /// subtracts a local estimate and then half-wave rectifies — and
  /// "subtract an estimate, clamp the negatives to zero" is the textbook
  /// spectral-subtraction rule, whose textbook failure mode is exactly what the
  /// E18-R10 sweep measured. Berouti, Schwartz & Makhoul (ICASSP 1979,
  /// *Enhancement of speech corrupted by acoustic noise*) identified the hard
  /// zero as the cause of "musical noise" and fixed it with a SPECTRAL FLOOR:
  /// hold the output at a small β instead of dropping it to nothing, with
  /// 0 < β ≪ 1. Forty-odd years of suppressors carry the same idea in the
  /// gain domain as a minimum gain `G_min` ("maximum reduction per bin",
  /// typically −26 dB … −6 dB, i.e. β ≈ 0.05 … 0.5).
  ///
  /// The floor here is proportional to the BIN'S OWN magnitude, which is the
  /// gain-domain form `out = max(d, β · s[j])`, not Berouti's flat
  /// `β · estimate`. That choice is deliberate and it is the whole point: a
  /// flat floor gives every sub-mean bin in a neighbourhood the SAME value, so a
  /// quiet-but-real major third and an empty bin come out identical — fine when
  /// the consumer is an ear being masked, useless when the consumer is an NNLS
  /// fit that has to tell the two apart. Scaling by `s[j]` preserves the
  /// ordering among weak bins, is scale-free (β is a pure ratio, no dependence
  /// on the frame's peak), is continuous in `s[j]` (a max of two continuous
  /// functions), is monotone, and can never go negative — which matters because
  /// the NNLS stage below assumes a non-negative spectrum: a negative `_s[j]`
  /// would make `Dᵀs` negative and the multiplicative update would flip the
  /// activation's sign on every iteration.
  ///
  /// At β = 0 the arithmetic is bit-for-bit today's: `max(d, 0)` is the hard
  /// zero. MEASURED: see `docs/research/soft-floor-rectifier-2026-09.md`.
  final double whiteningSpectralFloor;

  /// Diagnostic (E18-R11): the fraction of log-frequency bins that the last
  /// frame's [whiteningSpectralFloor] RESCUED — bins the hard zero would have
  /// discarded and the floor kept. 0 on the shipped path.
  ///
  /// It exists so a marginal measurement can be told apart from a no-op: "the
  /// floor barely does anything" and "the floor changes a third of the spectrum
  /// and the decoder does not care" are different findings with different
  /// follow-ups, and without this counter they look the same from outside.
  double lastWhiteningRescuedFraction = 0;

  /// Diagnostic (E18-R11): the fraction of bins the last frame's rectifier left
  /// at exactly zero, AFTER any floor. 0 on the shipped path.
  double lastWhiteningZeroedFraction = 0;

  /// Weight the normalisation neighbourhood with a **Hamming window** instead of
  /// the flat box, for BOTH whitening paths (the plain running-RMS divide and
  /// the mean-subtracting local-contrast form).
  ///
  /// The reference (`Chordino.cpp`, via its `SpecialConvolution` helper) takes
  /// its running mean and running standard deviation through a normalised
  /// Hamming-weighted kernel, not a box. The hypothesis that made this worth a
  /// round (E18-R10, from the E18-R09 write-up): a box treats the bin 3
  /// semitones away exactly like the bin next door, so at the EDGE of a loud
  /// peak the local mean is dragged up by energy that is musically elsewhere —
  /// and that is precisely where a quiet chord third lives. A weighted mean
  /// discounts the distant neighbour, so the mean near a peak's skirt is lower
  /// and a quiet third should survive a subtraction that a box would kill.
  ///
  /// Default false: the shipped behaviour is the flat box, and this flag exists
  /// so the claim could be MEASURED rather than assumed. See
  /// `docs/research/hamming-whitening-kernel-2026-09.md` for what the
  /// measurement said.
  final bool whiteningHammingKernel;

  /// The Hamming weights over the `2*whiteningHalfWindow + 1` tap neighbourhood,
  /// and their running prefix (for the O(1) in-bounds weight sum at the edges).
  late final Float64List _hammingKernel;
  late final Float64List _hammingKernelPrefix;

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

  /// The WHITENED log-frequency bin nearest [hz], as a fraction of the frame's
  /// largest whitened bin — 0 when the rectifier zeroed it (E18-R11 seam).
  ///
  /// Test seam for one specific question the decoded label cannot answer: when a
  /// quiet third still reads as a minor chord, is its bin GONE or merely
  /// under-weighted? The spectral floor changes which of those is true without
  /// changing the label, so the two have to be distinguishable from outside.
  @visibleForTesting
  double debugWhitenedRelativeAt(double hz) {
    var best = 0;
    var bestDistance = double.infinity;
    var peak = 0.0;
    for (var j = 0; j < _nBins; j++) {
      final distance = (_binFreq[j] - hz).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = j;
      }
      if (_s[j] > peak) peak = _s[j];
    }
    return peak <= 0 ? 0 : _s[best] / peak;
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

  // Whitening scratch, allocated once: [_whiten] runs on every frame of the
  // live audio path, and a per-frame `Float64List` there is pure garbage.
  late final Float64List _whitenPrefix;
  late final Float64List _whitenMean;
  late final Float64List _whitenWork;

  /// The local mean of the squared deviations, i.e. the local VARIANCE.
  late final Float64List _whitenVariance;
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
  ///
  /// Two kernels, selected by [whiteningHammingKernel]: a flat box (the shipped
  /// default, computed by prefix sum in O(1) per bin) or a normalised Hamming
  /// weighting (direct convolution — a weighted kernel has no prefix-sum
  /// shortcut).
  void _whiten(double maxS) {
    if (whiteningMeanCoefficient > 0) {
      _whitenByLocalContrast(maxS);
      return;
    }
    // No rectifier on this path, so there is nothing for the spectral floor to
    // hold up and the diagnostics read zero rather than going stale.
    lastWhiteningRescuedFraction = 0;
    lastWhiteningZeroedFraction = 0;
    final floor = 1e-4 * maxS;
    if (whiteningHammingKernel) {
      // The squared spectrum is copied aside first because the whitened result
      // is written back over [_s] while later bins still need their original values.
      for (var j = 0; j < _nBins; j++) {
        _whitenWork[j] = _s[j] * _s[j];
      }
      for (var j = 0; j < _nBins; j++) {
        var rms = math.sqrt(_weightedLocalMean(_whitenWork, j));
        if (rms < floor) rms = floor;
        _s[j] = _s[j] / math.pow(rms, whiteningExponent);
      }
      return;
    }
    final prefix = _whitenPrefix;
    for (var j = 0; j < _nBins; j++) {
      prefix[j + 1] = prefix[j] + _s[j] * _s[j];
    }
    for (var j = 0; j < _nBins; j++) {
      final lo = math.max(0, j - whiteningHalfWindow);
      final hi = math.min(_nBins - 1, j + whiteningHalfWindow);
      var rms = math.sqrt((prefix[hi + 1] - prefix[lo]) / (hi - lo + 1));
      if (rms < floor) rms = floor;
      _s[j] = _s[j] / math.pow(rms, whiteningExponent);
    }
  }

  /// The Hamming-weighted mean of [src] over bin [j]'s neighbourhood,
  /// re-normalised by the weight that actually falls INSIDE the array.
  ///
  /// WHY re-normalise instead of zero-padding. Zero padding would let the taps
  /// hanging off the end of the axis count as measured silence, so the first and
  /// last [whiteningHalfWindow] bins would report a local level pulled toward
  /// zero and come out of whitening several times too loud — a fabricated peak
  /// at each end of the log-frequency axis, which is exactly where the lowest
  /// guitar fundamental (E2, bin 0) sits. Dividing by the in-bounds weight sum
  /// instead says "there is less evidence here", which is the truth, and leaves
  /// an all-flat spectrum whitened flat everywhere including its edges. It is
  /// also the reference's convention for the same operator.
  ///
  /// O(taps) per bin by direct convolution; the in-bounds weight sum is O(1)
  /// from [_hammingKernelPrefix].
  double _weightedLocalMean(Float64List src, int j) {
    final half = whiteningHalfWindow;
    final lo = math.max(0, j - half);
    final hi = math.min(_nBins - 1, j + half);
    var sum = 0.0;
    for (var b = lo; b <= hi; b++) {
      sum += _hammingKernel[b - j + half] * src[b];
    }
    final weight =
        _hammingKernelPrefix[hi - j + half + 1] -
        _hammingKernelPrefix[lo - j + half];
    return weight > 0 ? sum / weight : 0.0;
  }

  /// The reference arithmetic: subtract the running mean, divide by the running
  /// standard deviation raised to [whiteningExponent], and rectify.
  ///
  /// Two passes over the neighbourhood, both through whichever kernel
  /// [whiteningHammingKernel] selects: the first gives each bin's local mean,
  /// the second the local mean of the squared deviations — each bin's deviation
  /// measured from ITS OWN local mean, as the reference does it.
  ///
  /// The rectification happens in exactly ONE place, for both kernels. That is
  /// deliberate: [whiteningSpectralFloor] and its two diagnostics have to apply
  /// identically whichever kernel is in use, and a per-kernel copy of the
  /// rectifier would be a per-kernel chance for them to drift apart.
  ///
  /// The standard-deviation FLOOR is ours, not the reference's: without it a
  /// silent neighbourhood divides by ~0 and turns numerical dust into structure.
  /// The reference has no such guard because it never runs on a live microphone
  /// that can be handed pure silence.
  void _whitenByLocalContrast(double maxS) {
    final mean = _whitenMean;
    final deviation = _whitenWork;
    _localMeanInto(_s, mean);
    for (var j = 0; j < _nBins; j++) {
      final d = _s[j] - whiteningMeanCoefficient * mean[j];
      deviation[j] = d * d;
    }
    final variance = _whitenVariance;
    _localMeanInto(deviation, variance);

    final floor = 1e-4 * maxS;
    var rescued = 0;
    var zeroed = 0;
    for (var j = 0; j < _nBins; j++) {
      final d = _s[j] - whiteningMeanCoefficient * mean[j];
      // Half-wave rectification with a SPECTRAL FLOOR (Berouti et al. 1979, in
      // the gain domain): at or below the local estimate keep β of the bin's own
      // magnitude rather than nothing. `max` of two continuous, non-negative
      // functions — so continuous at the threshold and never negative, which the
      // NNLS stage requires. At β = 0 this is exactly the hard zero.
      final rectified = whiteningSpectralFloor * _s[j];
      final effective = d > rectified ? d : rectified;
      if (d <= 0 && effective > 0) rescued++;
      if (effective <= 0) {
        zeroed++;
        _s[j] = 0;
        continue;
      }
      var std = math.sqrt(variance[j]);
      if (std < floor) std = floor;
      _s[j] = effective / math.pow(std, whiteningExponent);
    }
    lastWhiteningRescuedFraction = rescued / _nBins;
    lastWhiteningZeroedFraction = zeroed / _nBins;
  }

  /// The local mean of [src] over each bin's neighbourhood, into [out].
  ///
  /// The flat box goes by prefix sum (O(1) per bin); the Hamming kernel by
  /// direct convolution, because a weighted kernel has no prefix-sum shortcut.
  /// Both divide by what actually falls inside the axis — see
  /// [_weightedLocalMean] for why that is re-normalisation and not zero-padding.
  void _localMeanInto(Float64List src, Float64List out) {
    if (whiteningHammingKernel) {
      for (var j = 0; j < _nBins; j++) {
        out[j] = _weightedLocalMean(src, j);
      }
      return;
    }
    final prefix = _whitenPrefix;
    for (var j = 0; j < _nBins; j++) {
      prefix[j + 1] = prefix[j] + src[j];
    }
    for (var j = 0; j < _nBins; j++) {
      final lo = math.max(0, j - whiteningHalfWindow);
      final hi = math.min(_nBins - 1, j + whiteningHalfWindow);
      out[j] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1);
    }
  }

  /// Test/benchmark seam: load [spectrum] into the log-frequency buffer, run ONE
  /// whitening pass over it with this instance's settings, and return a copy of
  /// the result.
  ///
  /// Exists for two reasons that both need the whitener ISOLATED from the rest
  /// of [process]. First, the kernels have different complexity — the box is
  /// O(1) per bin by prefix sum, the Hamming O(taps) by direct convolution — and
  /// this runs on the live on-device audio path, so the difference has to be
  /// measured rather than assumed. Second, the kernel's own properties (a flat
  /// spectrum whitens flat, including at the edges) are only checkable here;
  /// through a decoded chord label they are invisible.
  @visibleForTesting
  Float64List debugWhitenSpectrum(Float64List spectrum) {
    assert(spectrum.length == _nBins);
    var maxS = 0.0;
    for (var j = 0; j < _nBins; j++) {
      _s[j] = spectrum[j];
      if (spectrum[j] > maxS) maxS = spectrum[j];
    }
    _whiten(maxS);
    return Float64List.fromList(_s);
  }

  /// The number of log-frequency bins — the length [debugWhitenSpectrum] wants.
  @visibleForTesting
  int get debugBinCount => _nBins;

  /// Test seam for the kernel: the normalised weight bin `j` gives to the
  /// neighbour [offset] bins away, or 0 outside the neighbourhood. A property
  /// test needs to read the weights to assert they are a Hamming and that the
  /// in-bounds normalisation sums to 1 — it must not re-derive them.
  @visibleForTesting
  double debugWhiteningWeight(int j, int offset) {
    final half = whiteningHalfWindow;
    if (offset.abs() > half) return 0;
    final neighbour = j + offset;
    if (neighbour < 0 || neighbour >= _nBins) return 0;
    final lo = math.max(0, j - half);
    final hi = math.min(_nBins - 1, j + half);
    if (!whiteningHammingKernel) return 1.0 / (hi - lo + 1);
    final weight =
        _hammingKernelPrefix[hi - j + half + 1] -
        _hammingKernelPrefix[lo - j + half];
    return _hammingKernel[offset + half] / weight;
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
