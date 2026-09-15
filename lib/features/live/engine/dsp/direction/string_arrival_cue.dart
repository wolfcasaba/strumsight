import 'dart:math' as math;
import 'dart:typed_data';

import '../../../../../core/music/strum.dart';

/// One narrow-band partial that belongs to exactly one string of a voicing.
class StringPartial {
  const StringPartial({required this.string, required this.hz});

  /// String index, 0 = low E (6th) … 5 = high E (1st).
  final int string;

  /// Frequency of the partial in Hz.
  final double hz;
}

/// The arrival-order verdict for one strum.
class StringArrivalResult {
  const StringArrivalResult({
    required this.direction,
    required this.confidence,
    required this.slopeMsPerString,
    required this.tau,
    required this.stringsUsed,
    required this.arrivalMs,
  });

  /// `null` = honestly ambiguous (too few strings, or no ordered stagger).
  final StrumDirection? direction;

  /// 0..1 — a calibrated-by-construction ladder, not a probability.
  final double confidence;

  /// Least-squares slope of arrival time vs string index (positive = low
  /// strings first = down-stroke).
  final double slopeMsPerString;

  /// Kendall rank correlation between string index and arrival time over the
  /// strings that could be measured (+1 = perfect down order, −1 = up).
  final double tau;

  /// How many strings yielded an arrival time.
  final int stringsUsed;

  /// Per-string arrival in ms relative to the analysis origin (null = the
  /// string's partials were not measurable).
  final List<double?> arrivalMs;

  static const ambiguous = StringArrivalResult(
    direction: null,
    confidence: 0.3,
    slopeMsPerString: 0,
    tau: 0,
    stringsUsed: 0,
    arrivalMs: [null, null, null, null, null, null],
  );
}

/// Chord-informed string-arrival direction cue.
///
/// A strumming hand excites the strings ONE AFTER ANOTHER: a down-stroke
/// reaches the low E first and the high E last (typically 4–15 ms per string),
/// an up-stroke the reverse. The shipped cues (two broad bands, or a 10 ms
/// log-mel) cannot resolve that stagger. This cue can, because the app knows
/// WHICH chord is being played and therefore which frequencies live on which
/// string: for every string it picks the partials (fundamental + harmonics)
/// that no other string of the voicing shares, tracks each with a centred
/// Goertzel envelope at ~1.5 ms hop, measures the instant that partial's NEW
/// energy crosses half of its post-onset peak (pre-onset baseline subtracted,
/// so a ringing previous strum does not count), and reads the direction from
/// the ORDER in which the strings arrive.
///
/// Pure and allocation-light per call; no state between strums.
class StringArrivalCue {
  StringArrivalCue({
    required this.sampleRate,
    this.hop = 64,
    this.preSec = 0.040,
    this.postSec = 0.100,
    this.minPartialHz = 150,
    this.maxPartialHz = 4000,
    this.harmonicCount = 6,
    this.windowSamples = 2048,
    double? uniqueSeparationHz,
    this.minSnr = 3.0,
    this.minSpanMs = 2.0,
    this.riseFraction = 0.5,
  }) : uniqueSeparationHz =
           uniqueSeparationHz ?? 2.1 * sampleRate / windowSamples;

  final int sampleRate;

  /// Envelope hop in samples (64 @ 44.1 kHz ≈ 1.45 ms).
  final int hop;

  /// Analysis span before / after the onset estimate.
  final double preSec;
  final double postSec;

  /// Partials outside this band are ignored (phone mics roll off below
  /// ~150 Hz; above ~4 kHz the pick noise is broadband, not per string).
  final double minPartialHz;
  final double maxPartialHz;

  /// Harmonics considered per string (1 = fundamental only).
  final int harmonicCount;

  /// Goertzel window length in samples (2048 @ 44.1 kHz ≈ 46 ms). Sets the
  /// frequency selectivity: a Hann main lobe reaches ±2·sr/n Hz, so a
  /// neighbouring partial closer than that leaks in and drags the arrival
  /// estimate (MEASURED on synth: 4-cycle windows compressed a 60 ms stagger
  /// to 14 ms). Time resolution is NOT set by this — a centred window puts an
  /// energy step's 50 % crossing at the true instant whatever [windowSamples]
  /// is; only interference and the decay shape blur it.
  final int windowSamples;

  /// A partial is attributable to a string only if no other string's partial
  /// lies within this distance — derived from [windowSamples] (the Hann main
  /// lobe) unless given.
  final double uniqueSeparationHz;

  /// Post-onset peak must exceed the pre-onset baseline by this factor.
  final double minSnr;

  /// Total arrival spread below this is called ambiguous.
  final double minSpanMs;

  /// The arrival instant is where a partial's NEW energy first reaches this
  /// fraction of its post-onset peak.
  final double riseFraction;

  /// Below this confidence the cue reports no direction (see the ladder in
  /// [analyze]). The high rung starts at [highConfidence].
  static const double speakThreshold = 0.65;
  static const double highConfidence = 0.80;

  /// Standard-tuning open-string MIDI numbers, low → high.
  static const List<int> standardMidi = [40, 45, 50, 55, 59, 64];

  /// Per-string fundamental frequency of a fretted voicing (`frets` per
  /// string low → high, `-1` = muted → null).
  static List<double?> voicingHz(List<int> frets, {double a4 = 440}) => [
    for (var s = 0; s < 6; s++)
      frets[s] < 0
          ? null
          : a4 * math.pow(2, (standardMidi[s] + frets[s] - 69) / 12).toDouble(),
  ];

  /// The partials of [stringHz] that belong to exactly one string.
  List<StringPartial> attributablePartials(List<double?> stringHz) {
    final all = <StringPartial>[];
    for (var s = 0; s < stringHz.length; s++) {
      final f0 = stringHz[s];
      if (f0 == null) continue;
      for (var h = 1; h <= harmonicCount; h++) {
        final f = f0 * h;
        if (f < minPartialHz || f > maxPartialHz) continue;
        all.add(StringPartial(string: s, hz: f));
      }
    }
    return [
      for (final p in all)
        if (!all.any(
          (q) =>
              q.string != p.string && (q.hz - p.hz).abs() < uniqueSeparationHz,
        ))
          p,
    ];
  }

  /// Analyse the strum whose estimated attack is at [onsetSample] in [pcm].
  StringArrivalResult analyze(
    Float64List pcm,
    int onsetSample,
    List<double?> stringHz,
  ) {
    final partials = attributablePartials(stringHz);
    if (partials.length < 2) return StringArrivalResult.ambiguous;

    final pre = (preSec * sampleRate).round();
    final post = (postSec * sampleRate).round();
    final origin = onsetSample - pre;
    final frames = (pre + post) ~/ hop;
    if (frames < 8) return StringArrivalResult.ambiguous;

    // Per-string summed NORMALISED envelopes (each partial scaled to its own
    // peak, weighted by SNR) — summing BEFORE the threshold crossing averages
    // the partials' noise instead of picking one noisy crossing per partial.
    final stringEnv = List<Float64List?>.filled(6, null);
    final stringWeight = Float64List(6);
    final env = Float64List(frames);
    for (final p in partials) {
      _goertzelEnvelope(pcm, origin, frames, windowSamples, p.hz, env);

      // Baseline: the earliest quarter of the pre-onset region.
      final baseFrames = math.max(2, (pre ~/ hop) ~/ 4);
      var base = 0.0;
      for (var k = 0; k < baseFrames; k++) {
        base += env[k];
      }
      base /= baseFrames;

      var peak = 0.0;
      for (var k = 0; k < frames; k++) {
        env[k] = math.max(0.0, env[k] - base);
        peak = math.max(peak, env[k]);
      }
      if (peak <= 0 || (base > 0 && peak < (minSnr - 1) * base)) continue;

      final snr = math.min(base > 0 ? peak / base : minSnr * 10, 100.0);
      final acc = stringEnv[p.string] ??= Float64List(frames);
      for (var k = 0; k < frames; k++) {
        acc[k] += snr * env[k] / peak;
      }
      stringWeight[p.string] += snr;
    }

    // One arrival per string: the crossing of the summed normalised envelope.
    final arrivalMs = List<double?>.filled(6, null);
    final xs = <double>[], ys = <double>[], ws = <double>[];
    for (var s = 0; s < 6; s++) {
      final acc = stringEnv[s];
      if (acc == null) continue;
      var peak = 0.0;
      for (var k = 0; k < frames; k++) {
        peak = math.max(peak, acc[k]);
      }
      final half = riseFraction * peak;
      for (var k = 1; k < frames; k++) {
        if (acc[k] >= half) {
          final frac = (half - acc[k - 1]) / (acc[k] - acc[k - 1]);
          arrivalMs[s] =
              (k - 1 + frac.clamp(0.0, 1.0)) * hop / sampleRate * 1000;
          break;
        }
      }
      if (arrivalMs[s] == null) continue;
      xs.add(s.toDouble());
      ys.add(arrivalMs[s]!);
      ws.add(stringWeight[s]);
    }
    final used = xs.length;
    if (used < 2) return StringArrivalResult.ambiguous;

    // Weighted least-squares slope (ms per string) and Kendall tau.
    var sw = 0.0, sx = 0.0, sy = 0.0;
    for (var i = 0; i < used; i++) {
      sw += ws[i];
      sx += ws[i] * xs[i];
      sy += ws[i] * ys[i];
    }
    final mx = sx / sw, my = sy / sw;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < used; i++) {
      sxx += ws[i] * (xs[i] - mx) * (xs[i] - mx);
      sxy += ws[i] * (xs[i] - mx) * (ys[i] - my);
    }
    final slope = sxx > 0 ? sxy / sxx : 0.0;

    var concordant = 0, discordant = 0;
    for (var i = 0; i < used; i++) {
      for (var j = i + 1; j < used; j++) {
        final d = ys[j] - ys[i]; // xs is ascending
        if (d > 0.5) {
          concordant++;
        } else if (d < -0.5) {
          discordant++;
        }
      }
    }
    final pairs = concordant + discordant;
    final tau = pairs == 0 ? 0.0 : (concordant - discordant) / pairs;

    var lo = double.infinity, hi = -double.infinity;
    for (final y in ys) {
      lo = math.min(lo, y);
      hi = math.max(hi, y);
    }
    final span = hi - lo;

    // Confidence ladder, MEASURED on GuitarSet's 3035 clean comping sweeps
    // with exact voicings (test/tools/string_arrival_guitarset_probe_test.dart):
    // ≥ 0.80 → 97.7 % (n=218), 0.65–0.80 → 85.6 % (n=871), below 0.65 →
    // 60.8 % (n=426). The bottom rung is barely better than a coin, so the
    // cue stays silent there ([speakThreshold]) — it is a precision
    // instrument that covers ~36 % of strokes at ~88 %, not a guesser.
    StrumDirection? direction;
    double confidence;
    if (span < minSpanMs || tau.abs() < 0.34) {
      direction = null;
      confidence = 0.3;
    } else {
      final spanTerm = math.min(1.0, span / 8.0);
      final stringsTerm = math.min(1.0, (used - 1) / 4.0);
      confidence = (0.5 + 0.45 * tau.abs() * spanTerm * stringsTerm).clamp(
        0.0,
        0.95,
      );
      direction = confidence >= speakThreshold
          ? (tau > 0 ? StrumDirection.down : StrumDirection.up)
          : null;
    }
    return StringArrivalResult(
      direction: direction,
      confidence: confidence,
      slopeMsPerString: slope,
      tau: tau,
      stringsUsed: used,
      arrivalMs: arrivalMs,
    );
  }

  /// Hann-windowed Goertzel magnitude of [hz] over [frames] windows of [n]
  /// samples CENTRED at `origin + k·hop` (centred → an energy step shows its
  /// 50 % crossing at the true step instant, whatever [n] is).
  void _goertzelEnvelope(
    Float64List pcm,
    int origin,
    int frames,
    int n,
    double hz,
    Float64List out,
  ) {
    final w = 2 * math.pi * hz / sampleRate;
    final coeff = 2 * math.cos(w);
    final half = n ~/ 2;
    for (var k = 0; k < frames; k++) {
      final start = origin + k * hop - half;
      var s0 = 0.0, s1 = 0.0, s2 = 0.0;
      for (var i = 0; i < n; i++) {
        final idx = start + i;
        final x = idx < 0 || idx >= pcm.length ? 0.0 : pcm[idx];
        final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
        s0 = x * hann + coeff * s1 - s2;
        s2 = s1;
        s1 = s0;
      }
      final power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
      out[k] = math.sqrt(math.max(0.0, power)) / n;
    }
  }
}
