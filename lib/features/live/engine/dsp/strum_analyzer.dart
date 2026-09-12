import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../../../core/music/strum.dart';
import 'dsp_config.dart';
import 'strum_direction_classifier.dart';
import 'superflux_onset_detector.dart';

/// A detected strum: when, which direction (null = truly ambiguous), and how
/// confident the direction call is.
class StrumEvent {
  const StrumEvent({
    required this.onsetFrame,
    required this.timeSec,
    required this.direction,
    required this.confidence,
    this.pDown,
    this.pUp,
    this.pNoStrum,
  });

  /// The analyzer's own frame index for this strum's detected onset — its
  /// IDENTITY, and what a later [StrumRevision] matches on.
  ///
  /// An integer on purpose. Matching on [timeSec] would need an epsilon, and at
  /// 200 bpm sixteenths consecutive strokes are ~13 frames (75 ms) apart while a
  /// settled verdict takes ~41 frames, so up to three strokes are in flight at
  /// once. An epsilon wide enough to absorb float rounding could reach the
  /// NEIGHBOURING stroke, which is exactly the hazard ADR 0556 names.
  final int onsetFrame;

  final double timeSec;
  final StrumDirection? direction;
  final double confidence;

  /// Carried verbatim from [StrumClassification.pDown] — `null` unless the
  /// CRNN produced it (ADR 0512 D1). The pipeline is the only reader.
  final double? pDown;

  /// See [pDown]; carried from [StrumClassification.pUp].
  final double? pUp;

  /// See [pDown]; carried from [StrumClassification.pNoStrum].
  final double? pNoStrum;
}

/// A SETTLED direction verdict for a strum [StrumAnalyzer.process] already
/// reported (ADR 0556 D3).
///
/// It revises DIRECTION and nothing else. It cannot create a strum, cannot
/// retract one, and says nothing about whether a stroke happened — those were
/// decided at the fast deadline and are not reopened. A consumer must match it to
/// the strum whose [StrumEvent.onsetFrame] equals [onsetFrame], never to "the
/// latest strum": by the time a revision lands, later strokes may already have
/// arrived.
///
/// Per ADR 0556 D1 the revision must NOT redraw an arrow the learner has seen.
/// Its purpose is the direction used for SCORING and for the post-bar review —
/// where there is no latency requirement and where a wrong answer actually costs
/// the learner marks.
class StrumRevision {
  const StrumRevision({
    required this.onsetFrame,
    required this.timeSec,
    required this.direction,
    required this.confidence,
    this.pDown,
    this.pUp,
    this.pNoStrum,
  });

  /// Identity of the strum being revised — matches [StrumEvent.onsetFrame].
  final int onsetFrame;

  /// Same reported attack instant the original [StrumEvent] carried, recomputed
  /// from [onsetFrame] rather than stored, so the two can never disagree.
  final double timeSec;

  /// The settled direction (`null` = the model is still ambiguous, which is a
  /// verdict, not a failure).
  final StrumDirection? direction;

  final double confidence;
  final double? pDown;
  final double? pUp;
  final double? pNoStrum;
}

/// Onset detection (SuperFlux, chunk 015 rec #3 — round 136) + strum-direction
/// classification behind the [StrumDirectionClassifier] seam (round 139) +
/// level. Pure & streaming: push fixed frames via [process]; confirmed,
/// classified strums come back a few frames later (~70–90 ms).
///
/// Round 136 replaced the whitened-flux onset trigger with the r135
/// [SuperFluxOnsetDetector] — A/B MEASURED: vibrato false onsets 23 → 1 on a
/// 3 s constant-amplitude bend, 180/200 BPM 16ths 10–11/12 → 12/12, parity on
/// the mixed randomized suite. Round 139 moved the chunk-006 heuristic (with
/// its r59 onset-relative baseline) verbatim into [HeuristicStrumClassifier];
/// the future TFLite CRNN drops in behind the same seam (ml-track P1).
/// Cost note: this runs a second 1024-pt FFT per hop (the detector owns its
/// own log-mel) — ~tens of µs, dwarfed by the NNLS path.
class StrumAnalyzer {
  StrumAnalyzer({
    required this.sampleRate,
    this.window = DspConfig.onsetWindow,
    this.hop = DspConfig.onsetHop,
    StrumDirectionClassifier? classifier,
    this.settledTier = false,
  }) : _fft = FFT(window),
       _hann = Float64List(window),
       _windowed = Float64List(window),
       _onsets = SuperFluxOnsetDetector(sampleRate: sampleRate),
       _classifier = classifier ?? HeuristicStrumClassifier() {
    assert(
      window == _onsets.window && hop == _onsets.hop,
      'StrumAnalyzer framing must match the SuperFlux detector',
    );
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
  }

  final int sampleRate;
  final int window;
  final int hop;

  /// Whether to produce [settledRevision] at all (ADR 0556 D3). **Off by
  /// default, deliberately.**
  ///
  /// Enabling it makes the classifier run a SECOND time per strum — with the live
  /// CRNN behind the seam that is a second model forward, doubling the direction
  /// model's per-strum cost, and at 200 bpm sixteenths there are ~13 strums a
  /// second. Until a consumer actually reads [settledRevision], that cost would
  /// buy a learner's phone nothing, so the tier stays dark.
  ///
  /// It is switched on by the round that wires the settled direction into SCORING
  /// (ADR 0558 D1: the tie-break fusion rule, measured to never lose at any
  /// learner compliance) — the same round that can justify the cost with the
  /// +0.0723 macro-F1 it buys. The flag is not a feature toggle for users; it is
  /// the seam that keeps an unconsumed computation from shipping.
  final bool settledTier;

  // Tunables (RAG chunks 005–006; update the chunk when retuned).
  static const _lowBandMaxHz = 200.0;
  static const _highBandMinHz = 1000.0;
  static const _classifyAfterFrames = 12; // ~70 ms of post-onset evidence

  // Reported-time correction (r144, MEASURED): the SuperFlux peak frame
  // STARTS a constant ~2.5 hops (14.2 ms) before the true attack instant —
  // invariant across stagger 4–12 ms and level 1.0/0.3. StrumEvent.timeSec
  // reports the estimated ATTACK so the LessonScorer's ±50 ms PERFECT window
  // keeps its full late-side margin for uncalibrated users. The correction is
  // applied ONLY to the reported time — classification and the Viterbi onset
  // boost keep the peak-frame reference (shifting them would slide the r59
  // baseline window into the attack).
  static const double _attackOffsetFrames = 2.5;

  /// A fast verdict at or above this direction margin (`|pDown - pUp|`) is taken as
  /// final: no settled verdict is requested, so no second model forward is spent.
  ///
  /// MEASURED (`ml/probe_settled_tier_value.py`, held-out GuitarSet, unseen player AND
  /// tune, 530 strokes). The margin really does predict whether the fast call is right,
  /// which is what makes routing on it legitimate:
  ///
  /// ```
  ///   fast margin   n     fast accuracy
  ///    0.0-0.2      70       0.4000
  ///    0.2-0.4      72       0.4167
  ///    0.4-0.6      66       0.5455
  ///    0.6-0.8     102       0.5588
  ///    0.8-1.0     220       0.8500
  /// ```
  ///
  /// And the hybrid curve, against fast-only macro-F1 0.5262:
  ///
  /// ```
  ///   margin t   macro    settled verdicts requested
  ///     0.10     0.5389        6.4 %
  ///     0.30     0.5813       19.8 %     <- this constant
  ///     0.70     0.6044       49.1 %
  ///     1.01     0.5917      100.0 %     (= settled-only)
  /// ```
  ///
  /// 0.30 buys 84 % of the settled-only gain for a fifth of its cost. The higher rows
  /// are NOT chosen: above ~0.3 the curve is within a handful of strokes of itself on
  /// this sample (the t = 0.70 row even exceeds settled-only, which a 530-stroke
  /// up-F1 cannot support), and each step costs both CPU and direction-neutral arrows.
  static const double _settleBelowMargin = 0.30;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final SuperFluxOnsetDetector _onsets;
  final StrumDirectionClassifier _classifier;

  /// The classifier behind the seam (wiring proof surface, r169).
  StrumDirectionClassifier get debugClassifier => _classifier;

  // Onsets awaiting their post-onset evidence window. A queue (not a single
  // slot): at 200 BPM 16ths the next onset (~75 ms) can land while the
  // previous one is still inside its ~70 ms classify window.
  final ListQueue<int> _pendingOnsets = ListQueue();

  // Strums that have ALREADY been reported and are waiting for their settled
  // verdict. Separate from [_pendingOnsets] because the two tiers drain at
  // different delays, and because an onset the fast tier SUPPRESSED must never
  // enter this queue — a suppressed onset that came back later would be the
  // analyzer inventing a stroke (ADR 0556, hazard 3).
  final ListQueue<int> _pendingSettled = ListQueue();
  int _frameIndex = -1;

  /// RMS of the most recent frame (level meter).
  double lastRms = 0;

  /// True when THIS frame confirmed a new onset (before classification — the
  /// pipeline uses it to trigger the decoder's onset-aligned switch boost,
  /// round 138). Reset every [process] call.
  bool onsetJustFired = false;

  /// The settled verdict that came due on THIS frame, or `null`. Reset every
  /// [process] call, the same idiom as [onsetJustFired] and [lastRms].
  ///
  /// A separate field rather than a second return value because one frame can
  /// legitimately carry both: a settled verdict for an earlier strum and a fast
  /// verdict for a later one. Returning a record would make every existing caller
  /// unpack something it does not use.
  StrumRevision? settledRevision;

  double get _frameSec => hop / sampleRate;

  /// Whether this fast verdict is uncertain enough to be worth a settled one.
  ///
  /// A null direction is always worth settling: the fast call named nothing, so there
  /// is no arrow claim for a later verdict to contradict, and the grader would
  /// otherwise have nothing at all (ADR 0556 D3's direction-neutral case).
  static bool _needsSettling(StrumClassification c) {
    if (c.direction == null) return true;
    final down = c.pDown, up = c.pUp;
    if (down == null || up == null) return false;
    return (down - up).abs() < _settleBelowMargin;
  }

  /// Push the next [window]-sample frame (advanced by [hop]); returns a
  /// confirmed+classified strum when one completes its evidence window.
  StrumEvent? process(Float64List frame) {
    assert(frame.length == window);
    _frameIndex++;
    settledRevision = null;

    var sumSq = 0.0;
    for (var i = 0; i < window; i++) {
      final s = frame[i];
      sumSq += s * s;
      _windowed[i] = s * _hann[i];
    }
    lastRms = math.sqrt(sumSq / window);

    final spectrum = _fft.realFft(_windowed);
    final nBins = window ~/ 2;
    var low = 0.0, high = 0.0, magSum = 0.0, weighted = 0.0;
    for (var k = 1; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      final m = math.sqrt(re * re + im * im);
      final freq = k * sampleRate / window;
      if (freq <= _lowBandMaxHz) low += m;
      if (freq >= _highBandMinHz) high += m;
      magSum += m;
      weighted += m * freq;
    }
    _classifier.observe(
      frame,
      StrumFrameFeatures(
        lowEnergy: low,
        highEnergy: high,
        centroid: magSum > 0 ? weighted / magSum : 0,
      ),
    );

    // SuperFlux onset trigger (silence gate, release hysteresis and the
    // attack-relative peak gate all live inside the detector).
    final onsetSec = _onsets.processFrame(frame);
    onsetJustFired = onsetSec != null;
    if (onsetSec != null) {
      _pendingOnsets.addLast((onsetSec * sampleRate / hop).round());
    }

    // The SETTLED tier (ADR 0556 D3), drained BEFORE the fast tier because that
    // branch returns: in one frame a settled verdict for an EARLIER strum and a
    // fast verdict for a LATER one can both come due, and the early return would
    // otherwise swallow the settled one. At most one settled verdict per frame,
    // mirroring the fast tier — the queue is FIFO, so a dense burst delays a
    // verdict by a frame but can never skip one.
    final settleAfter = settledTier ? _classifier.settleAfterFrames : null;
    if (settleAfter != null &&
        _pendingSettled.isNotEmpty &&
        _frameIndex - _pendingSettled.first >= settleAfter) {
      final onsetFrame = _pendingSettled.removeFirst();
      final settled = _classifier.classifyAt(
        onsetFrame: onsetFrame,
        currentFrame: _frameIndex,
      );
      // A settled SUPPRESSION is deliberately ignored. Existence was decided at
      // the fast deadline and an event has already reached every consumer;
      // retracting it would delete a stroke the learner saw, which is the visible
      // self-correction ADR 0556 D1 forbids. The settled tier revises DIRECTION,
      // never existence — so the fast verdict simply stands.
      if (!settled.suppressed) {
        settledRevision = StrumRevision(
          onsetFrame: onsetFrame,
          timeSec: (onsetFrame + _attackOffsetFrames) * _frameSec,
          direction: settled.direction,
          confidence: settled.confidence,
          pDown: settled.pDown,
          pUp: settled.pUp,
          pNoStrum: settled.pNoStrum,
        );
      }
    }

    // Classify once enough post-onset evidence has accumulated (chunk 006).
    if (_pendingOnsets.isNotEmpty &&
        _frameIndex - _pendingOnsets.first >= _classifyAfterFrames) {
      final onsetFrame = _pendingOnsets.removeFirst();
      final c = _classifier.classifyAt(
        onsetFrame: onsetFrame,
        currentFrame: _frameIndex,
      );
      // r175: the learned no-strum reject fired — this detected onset is not a
      // strum, so emit NO event. Every downstream consumer (Live arrow, Learn
      // scoring, streak) sees nothing, exactly as if the onset never happened.
      // A 2-class model / the heuristic never set this, so their behaviour is
      // unchanged (a null direction still yields a StrumEvent — ambiguous
      // strum, not no-strum).
      if (c.suppressed) return null;
      // Only a strum that was actually REPORTED waits for a settled verdict, so
      // the suppressed onset above can never come back (ADR 0556, hazard 3) — and
      // only one whose fast margin was SHORT, because that is the only subset the
      // settled verdict measurably improves. A classification with no
      // probabilities (the heuristic) has no margin to judge, and also no settled
      // tier, so it never reaches here.
      if (settleAfter != null && _needsSettling(c)) {
        _pendingSettled.addLast(onsetFrame);
      }
      return StrumEvent(
        onsetFrame: onsetFrame,
        timeSec: (onsetFrame + _attackOffsetFrames) * _frameSec,
        direction: c.direction,
        confidence: c.confidence,
        pDown: c.pDown,
        pUp: c.pUp,
        pNoStrum: c.pNoStrum,
      );
    }
    return null;
  }
}
