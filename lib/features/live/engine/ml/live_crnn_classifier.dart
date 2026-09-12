import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/log_mel_extractor.dart';
import '../dsp/strum_direction_classifier.dart';
import '../../../../core/music/strum.dart';
import 'crnn_frontend.dart';
import 'crnn_strum_net.dart';

/// Streaming front-end for the TRUE-70 ms live model (r168): keeps a raw
/// audio ring fed per fast hop and, at the classify instant, rebuilds the
/// EXACT training window of `ml/experiment_deadline.window_truncated` — a
/// 15-row log-mel around the onset over audio that simply ENDS at the
/// verdict deadline (the truncation is the availability; rows past it see
/// zeros, exactly as trained).
class LiveCrnnFrontend {
  LiveCrnnFrontend({
    required this.sampleRate,
    this.window = 1024,
    this.hop = 256,
  }) : _ring = Float64List(sampleRate), // 1 s — window needs ~300 ms
       _logMel = LogMelExtractor(sampleRate: CrnnFrontend.modelSampleRate);

  final int sampleRate;
  final int window;
  final int hop;

  final Float64List _ring;
  final LogMelExtractor _logMel;
  int _end = 0; // absolute sample index one past the newest sample
  bool _first = true;

  /// Feed one analyzer frame ([window] samples advanced by [hop]).
  void observe(Float64List frame) {
    assert(frame.length == window);
    if (_first) {
      _append(frame, 0);
      _first = false;
    } else {
      _append(frame, window - hop); // only the new hop tail
    }
  }

  void _append(Float64List frame, int from) {
    for (var i = from; i < frame.length; i++) {
      _ring[_end % _ring.length] = frame[i];
      _end++;
    }
  }

  /// The (15, 128) truncated log-mel window for a strum whose onset FRAME is
  /// [onsetFrame], evaluated with the audio available at [currentFrame] —
  /// the analyzer's own frame indices.
  List<List<double>> windowAt(int onsetFrame, int currentFrame) {
    // Reported-time semantics (r144): the attack sits ~2.5 hops after the
    // onset frame's start — the same instant the batch path classifies at.
    final onsetSec = (onsetFrame + 2.5) * hop / sampleRate;
    final availableEnd = currentFrame * hop + window;
    return _buildWindow(onsetSec, availableEnd);
  }

  /// Analyzer frames after an onset frame at which this window has FULLY
  /// arrived — the SETTLED tier's instant (ADR 0556 D3).
  ///
  /// DERIVED from the model geometry, never written down, so it cannot drift from
  /// [CrnnFrontend]'s constants or from the extractor's FFT size. For the shipped
  /// framing (44.1 kHz, hop 256, window 1024) it comes out at 41 frames = 238 ms
  /// past the onset frame — the same 238 ms the settled tier is measured at.
  ///
  /// The `+ 1` is the centre rounding: [_buildWindow] rounds the onset to the
  /// nearest MODEL frame, which can push the segment's end up to half a model hop
  /// (5 ms, ~0.9 analyzer frames) later than the exact arithmetic below. Paying
  /// one analyzer frame (5.8 ms) is the cheap side of that trade — arriving early
  /// would zero-pad the tail, which is precisely the truncation the settled tier
  /// exists to avoid.
  int get framesUntilComplete {
    const modelRate = CrnnFrontend.modelSampleRate;
    const modelHop = CrnnFrontend.modelHop;
    final rows = CrnnFrontend.preFrames + CrnnFrontend.postFrames;
    final segLen = (rows - 1) * modelHop + _logMel.nFft;
    // Segment samples lying AFTER the onset's centre frame.
    final afterCentre = segLen - CrnnFrontend.preFrames * modelHop;
    // [windowAt] puts the attack at (onsetFrame + 2.5) hops, and the audio
    // available at currentFrame ends at currentFrame * hop + window.
    final needed =
        (2.5 * hop + afterCentre * sampleRate / modelRate - window) / hop;
    return needed.ceil() + 1;
  }

  /// The same window computed from a WHOLE signal (no ring) — the test
  /// reference and the parity anchor for the streamed path.
  static List<List<double>> referenceWindow(
    Float64List available,
    int sampleRate,
    double onsetFrameStartSec,
  ) {
    final fe = LiveCrnnFrontend(sampleRate: sampleRate);
    fe._append(available, 0);
    final onsetSec = onsetFrameStartSec + 2.5 * fe.hop / sampleRate;
    return fe._buildWindow(onsetSec, available.length);
  }

  List<List<double>> _buildWindow(double onsetSec, int availableEnd) {
    const mSr = CrnnFrontend.modelSampleRate; // 16 k
    const mHop = CrnnFrontend.modelHop; // 160
    final center = (onsetSec * mSr / mHop).round();
    final lo16 = (center - CrnnFrontend.preFrames) * mHop;
    final rows = CrnnFrontend.preFrames + CrnnFrontend.postFrames;
    final segLen = (rows - 1) * mHop + _logMel.nFft;
    final seg = Float64List(segLen);

    // The 16 k grid maps to source samples at ratio sr/16k; fill what exists.
    final lo44 = (lo16 * sampleRate / mSr).floor();
    final hi44 = math.min(
      availableEnd,
      ((lo16 + segLen) * sampleRate / mSr).ceil(),
    );
    final oldest = math.max(0, _end - _ring.length);
    final a = math.max(lo44, oldest);
    if (hi44 > a) {
      final slice = Float64List(hi44 - a);
      for (var i = 0; i < slice.length; i++) {
        slice[i] = _ring[(a + i) % _ring.length];
      }
      final res = CrnnFrontend.resampleLinear(slice, sampleRate, mSr);
      final off = ((a * mSr / sampleRate).round()) - lo16;
      for (var i = 0; i < res.length; i++) {
        final j = off + i;
        if (j >= 0 && j < segLen) seg[j] = res[i];
      }
    }

    return [
      for (var r = 0; r < rows; r++)
        _logMel
            .processFrame(
              Float64List.sublistView(seg, r * mHop, r * mHop + _logMel.nFft),
            )
            .toList(),
    ];
  }
}

/// The live ↓/↑ classifier behind the r139 seam: the 70 ms-deadline CRNN
/// (real-fold eval 0.799 vs the heuristic's 0.389, r167) with the analyzer's
/// unchanged verdict timing. Absent/unparseable weights → callers construct
/// the heuristic instead ([tryLoad] returns null).
class LiveCrnnStrumClassifier implements StrumDirectionClassifier {
  LiveCrnnStrumClassifier(this._net, {required int sampleRate})
    : _frontend = LiveCrnnFrontend(sampleRate: sampleRate);

  final CrnnStrumNet _net;
  final LiveCrnnFrontend _frontend;

  static LiveCrnnStrumClassifier? tryLoad(
    String path, {
    required int sampleRate,
  }) {
    try {
      final bytes = File(path).readAsBytesSync();
      return LiveCrnnStrumClassifier(
        CrnnStrumNet.parse(ByteData.sublistView(bytes)),
        sampleRate: sampleRate,
      );
    } catch (_) {
      return null;
    }
  }

  /// The gate as FITTED for this model, kept for provenance — the shipped gate is
  /// [noStrumThreshold], which is deliberately higher (ADR 0549).
  ///
  /// r175 — the learned no-strum reject gate. P(no-strum) above this SUPPRESSES
  /// the arrow. Fit on the shipped 3-class live model's HELD-OUT eval fold as
  /// the P(no-strum) quantile that keeps ≥95 % of TRUE strums (chunk 018 r175 —
  /// the same rule as `honest_eval._gate`, retention target 0.95); the measured
  /// value + the retention/rejection it buys are recorded in
  /// `ml/live_3c_threshold.json`. MEASURED for the shipped model: 0.43877 keeps
  /// 95.0 % of true strums (eval fold, n=2013) while rejecting 93.0 % of false
  /// onsets (n=1707; no-strum recall 0.929, direction acc on true strums
  /// 0.807). The capability is LOGO-confirmed (r174): at 95 % true-strum
  /// retention the reject head suppresses ~87 % of false onsets on UNSEEN
  /// players vs ~3 % for the r170 confidence gate — the noise the r170 finding
  /// proved confidence cannot touch. Only consulted for a 3-class model; a
  /// 2-class asset never suppresses (r139 fallback preserved).
  static const fittedNoStrumThreshold = 0.4387717843055725;

  /// What SHIPS, and deliberately not [fittedNoStrumThreshold].
  ///
  /// MEASURED on GuitarSet (`docs/eval/guitarset-strum-baseline.md`, ADR 0549): the
  /// fitted value was the P(no-strum) quantile keeping 95% of true strums **on this
  /// model's own eval fold**, and on 72 files of real Rock/Funk strumming it keeps
  /// **59.6%**. The gate generalises badly, and the cost is not only missed arrows: a
  /// suppressed strum is a stroke the rhythm grader never sees, so a learner who played
  /// it is marked down for the engine's silence.
  ///
  /// The sweep over the same corpus, one row per candidate gate:
  ///
  /// ```
  ///   gate    onset P   onset F1   true-strum recall   direction macro-F1
  ///   0.439     0.913     0.5828               0.596              0.4192
  ///   0.650     0.906     0.6013               0.620              0.4235
  ///   0.850     0.899     0.6223               0.649              0.4311
  ///   none      0.701     0.7847               0.955              0.4506
  /// ```
  ///
  /// 0.85 is better than the fitted value on EVERY column — detection, retention and
  /// direction — for 1.4 points of precision. Lifting the gate entirely is better still
  /// on recall and direction, and is NOT taken: at 0.701 precision roughly three in ten
  /// reported strums match no annotated event, and a phantom stroke credits a slot the
  /// learner never played. That is a lie with the opposite sign to the one being fixed,
  /// and the rhythm pillar cannot afford either.
  ///
  /// [fittedNoStrumThreshold] is kept rather than overwritten because it is a real
  /// measurement with its own provenance (`ml/live_3c_threshold.json`, written by
  /// `ml/train_live_3c.py`). Replacing the number in place would have deleted the
  /// evidence for the number, and left the JSON disagreeing with the code with nothing
  /// saying which was right.
  static const noStrumThreshold = 0.85;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) =>
      _frontend.observe(frame);

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) =>
      classifyProbs(_net.forward(_frontend.windowAt(onsetFrame, currentFrame)));

  /// The instant this model's whole window has arrived, so the verdict runs on
  /// audio the 70 ms deadline could only zero-pad. Derived, not tuned — see
  /// [LiveCrnnFrontend.framesUntilComplete].
  @override
  int? get settleAfterFrames => _frontend.framesUntilComplete;

  /// The r175 decision rule for a raw softmax [probs]. A 3-class vector
  /// `[P(down), P(up), P(no-strum)]` SUPPRESSES the arrow when P(no-strum)
  /// exceeds [noStrumThreshold]; otherwise it emits the winning direction with
  /// the r170 calibrated confidence over the RENORMALISED down/up mass (so the
  /// confidence keeps meaning "P(the arrow is right | it is a strum)"). A
  /// 2-class vector takes today's path and NEVER suppresses — the r139 seam is
  /// preserved byte-for-byte for a 2-class asset. Pure/static so the gate is
  /// unit-testable without an asset.
  static StrumClassification classifyProbs(List<double> probs) {
    if (probs.length >= 3) {
      final sum = probs[0] + probs[1];
      final pDown = sum > 0 ? probs[0] / sum : 0.5;
      final pUp = sum > 0 ? probs[1] / sum : 0.5;
      if (probs[2] > noStrumThreshold) {
        return StrumClassification(
          direction: null,
          confidence: 0,
          suppressed: true,
          // The probabilities are exported on the SUPPRESSED branch too, and this
          // changes nothing production does: `strum_analyzer.dart` returns before
          // building a `StrumEvent` when `suppressed` is set, so no consumer can
          // read them. What it buys is that [noStrumThreshold] becomes MEASURABLE
          // — a sweep can ask what a different gate would have kept without
          // re-running the model per threshold. That matters because the shipped
          // value was fitted for 95% true-strum retention on this model's own
          // held-out fold, and on GuitarSet it retains 59.5%
          // (`docs/eval/guitarset-strum-baseline.md`). A gate whose retention is
          // corpus-dependent has to be re-measurable, not re-derived by hand.
          // Additive export in the sense of ADR 0512 D1.
          pDown: pDown,
          pUp: pUp,
          pNoStrum: probs[2],
        );
      }
      final up = pUp > pDown;
      return StrumClassification(
        direction: up ? StrumDirection.up : StrumDirection.down,
        confidence: calibrate(up ? pUp : pDown),
        // Additive export (ADR 0512 D1): the caller pipeline builds its
        // decision from these — direction/confidence above are unchanged.
        pDown: pDown,
        pUp: pUp,
        pNoStrum: probs[2],
      );
    }
    final up = probs[1] > probs[0];
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: calibrate(up ? probs[1] : probs[0]),
      // The 2-class softmax already sums to 1 — no renormalisation needed.
      pDown: probs[0],
      pUp: probs[1],
    );
  }

  /// Raw softmax → empirical P(correct) (r170). The net is OVERCONFIDENT on
  /// real audio — measured on the eval fold (2 018 matched strums):
  /// p<0.7 → 58 %, 0.7–0.9 → 63 %, 0.9–0.97 → 74 %, ≥0.97 → 86 % — so the
  /// emitted confidence is remapped piecewise-linearly through those knots.
  /// Keeps the UI tiers and the user's confidence threshold meaning what
  /// they always meant (≈ probability the arrow is right). Note: false-alarm
  /// onsets score the SAME raw confidence as real strums (median 0.94 vs
  /// 0.97), so confidence can NOT gate noise — that stays the onset
  /// detector's job (chunk 018 r170).
  static double calibrate(double p) {
    const knots = [
      (0.50, 0.55), (0.60, 0.58), (0.80, 0.63), //
      (0.935, 0.74), (0.9825, 0.86), (1.00, 0.87),
    ];
    if (p <= knots.first.$1) return knots.first.$2;
    for (var i = 1; i < knots.length; i++) {
      if (p <= knots[i].$1) {
        final (x0, y0) = knots[i - 1];
        final (x1, y1) = knots[i];
        return y0 + (y1 - y0) * (p - x0) / (x1 - x0);
      }
    }
    return knots.last.$2;
  }
}
