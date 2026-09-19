// One instrument for driving the REAL live pipeline over a corpus of real audio.
//
// Extracted in E18-R45 from `test/tooling/guitarset_threshold_sweep_test.dart`, which had
// been the only consumer, because a SECOND corpus now needs the identical machinery: the
// Klangio phone-mic takes turned out to be on the machine all along (ADR 0576), so the
// deployment condition can finally be swept in situ. Copying this file's logic instead of
// sharing it is how two corpora quietly stop being comparable — the same failure
// `modelled_guitar.dart`'s header records for synthesis and `docs/LESSONS.md` L269 records
// for matching helpers, and the exact shape of L682 ("two numbers from two models is not a
// gap"). The whole value of a cross-corpus delta is that ONE instrument produced both sides.
//
// Every comment below is a measured finding, not description. They travelled with the code
// because deleting them would delete the reasons.
//
// ## What this is NOT
//
// It proposes no production behaviour. [RecordingClassifier] deliberately never suppresses
// and reports no probabilities, so that ONE streaming pass can stand in for every candidate
// gate: the real probabilities are recorded and each gate is applied offline afterwards.
// Nothing here is a model of what the app should do.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/domain/recognition/strum_prediction.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

/// Both corpora are 44.1 kHz: GuitarSet's `audio_mono-mic` and Klangio's
/// `recording_<id>_phone.wav`. Asserted at the call site rather than assumed.
const int kSweepSampleRate = 44100;

/// One candidate gate: the no-strum suppression threshold, and whether the pipeline's
/// margin confirmation gate is applied. `suppress: 1.01` never suppresses.
typedef Gate = ({double suppress, bool margin});

/// The canonical gate ladder, shared so the two corpora's tables have the same rows.
///
/// A gate list that drifted between corpora would make every cross-corpus delta read a
/// different row against a different row, which is the L682 error with extra steps. The
/// first entry is what production does today.
const List<Gate> kSweepGates = [
  (suppress: LiveCrnnStrumClassifier.noStrumThreshold, margin: true),
  (suppress: LiveCrnnStrumClassifier.noStrumThreshold, margin: false),
  (suppress: 0.65, margin: true),
  (suppress: 0.65, margin: false),
  // The value ADR 0549 replaced, kept for provenance — NOT a literal 0.85, which is what
  // [LiveCrnnStrumClassifier.noStrumThreshold] already is. When the shipped constant moved
  // here it collided with the literal, and because these records are value-equal the
  // scores map collapsed two entries onto ONE tally: the shipped row's `kept`/`phantoms`
  // printed DOUBLE from then until E18-R43. Ratios survived it, counts did not. Every
  // consumer must assert `scores.length == kSweepGates.length` for that reason.
  (suppress: LiveCrnnStrumClassifier.fittedNoStrumThreshold, margin: true),
  (suppress: LiveCrnnStrumClassifier.fittedNoStrumThreshold, margin: false),
  (suppress: 1.01, margin: true),
  (suppress: 1.01, margin: false),
];

/// F1 under the sweep's scoring CONVENTION, which is the part that has to match across
/// corpora: a strum the gate suppressed is NO CALL — it counts as a false negative for the
/// class that was actually played, never as a false positive for the other one. Excluding
/// suppressed strums instead would grade the model on the subset it happened to like
/// (ADR 0549); the callers arrange that, and this is the arithmetic they share.
double f1(int tp, int fp, int fn) {
  if (tp == 0) return 0;
  final p = tp / (tp + fp);
  final r = tp / (tp + fn);
  return 2 * p * r / (p + r);
}

/// One onset as the pipeline saw it: the FAST (70 ms) probabilities the streaming path
/// produced, plus the SETTLED (untruncated) ones for the same onset frame, from
/// [settledProbs]. The `s*` fields are null when the settled window could not be built.
typedef Heard = ({
  double atSec,
  double? pDown,
  double? pUp,
  double? pNoStrum,
  double? sDown,
  double? sUp,
  double? sNoStrum,
});

/// Delegates to the REAL classifier, records what it said, and never suppresses.
///
/// Never suppressing is not a proposed behaviour — it is how one pass can stand in for
/// every pass: the recorded `pNoStrum` lets each gate be applied afterwards.
final class RecordingClassifier implements StrumDirectionClassifier {
  RecordingClassifier(this._inner);

  /// No settled tier, and that is load-bearing here rather than boilerplate:
  /// delegating it would make the analyzer issue a SECOND classify call per strum,
  /// which this recorder would append to [calls] — silently adding one verdict per
  /// strum, at a different truncation, to the pass every boundary in the measurement
  /// is rescored from (ADR 0556 D3).
  @override
  int? get settleAfterFrames => null;

  final LiveCrnnStrumClassifier _inner;
  final List<StrumClassification> calls = [];

  /// The analyzer frame each call in [calls] was made for, same order. Needed because
  /// the SETTLED window is addressed by onset frame, not by published time: the
  /// published time carries the r144 attack correction and the window does too, so
  /// re-deriving one from the other would double-apply it.
  final List<int> onsetFrames = [];

  @override
  void observe(Float64List frame, StrumFrameFeatures features) =>
      _inner.observe(frame, features);

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    final result = _inner.classifyAt(
      onsetFrame: onsetFrame,
      currentFrame: currentFrame,
    );
    calls.add(result);
    onsetFrames.add(onsetFrame);
    // BOTH gates are lifted here, and the second by OMISSION rather than a flag:
    // `live_pipeline._isDirectionConfirmed` returns true unconditionally for an
    // event carrying no probabilities, so reporting a direction WITHOUT pDown/pUp
    // makes the pipeline publish every onset. The real probabilities are not lost —
    // they are in [calls], which is where each candidate gate is applied offline.
    final up = (result.pUp ?? 0) > (result.pDown ?? 0);
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: 1,
    );
  }
}

/// Would the pipeline's margin gate confirm this onset?
///
/// Built from the SAME `StrumPrediction.decision` the pipeline defers to, so a sweep
/// cannot drift from the shipped rule by restating it.
bool marginConfirms(Heard h) {
  final pDown = h.pDown;
  final pUp = h.pUp;
  if (pDown == null || pUp == null) return true;
  return StrumPrediction(
        onsetTimeSec: h.atSec,
        verdictTimeSec: h.atSec,
        pDown: pDown,
        pUp: pUp,
        pNoStrum: h.pNoStrum ?? 0,
        calibratedConfidence: null,
        modelId: 'sweep',
      ).decision ==
      RecognitionDecision.confirmed;
}

/// The SETTLED probabilities for one onset frame, from the untruncated window.
///
/// Uses `LiveCrnnFrontend.referenceWindow`, which the repo already pins against the
/// streamed `windowAt` — so this is the documented parity anchor, not a second
/// implementation. Two details make it correct rather than approximately right:
///
/// 1. **A SLICE, not the recording.** The frontend's ring is one second long
///    (`Float64List(sampleRate)`), so appending a 30-second take would leave only its
///    last second addressable and every earlier onset would read zeros. The slice runs
///    from 0.1 s before the onset frame to 0.6 s after — comfortably past the window's
///    own span, comfortably inside the ring.
/// 2. **Frame-start semantics.** `referenceWindow` adds the r144 attack offset itself,
///    so what it wants is the onset FRAME's start time, here expressed relative to the
///    slice.
///
/// Null when the slice cannot cover the window (an onset at the very end of a take).
({double pDown, double pUp, double pNoStrum})? settledProbs(
  List<double> pcm,
  CrnnStrumNet net,
  int onsetFrame, {
  int sampleRate = kSweepSampleRate,
  int hop = 256,
}) {
  final frameStart = onsetFrame * hop;
  final lo = math.max(0, frameStart - (sampleRate * 0.1).round());
  final hi = math.min(pcm.length, frameStart + (sampleRate * 0.6).round());
  if (hi - frameStart < (sampleRate * 0.35).round()) return null;
  final slice = Float64List.fromList(pcm.sublist(lo, hi));
  final window = LiveCrnnFrontend.referenceWindow(
    slice,
    sampleRate,
    (frameStart - lo) / sampleRate,
  );
  final call = LiveCrnnStrumClassifier.classifyProbs(net.forward(window));
  final pDown = call.pDown;
  final pUp = call.pUp;
  final pNoStrum = call.pNoStrum;
  if (pDown == null || pUp == null || pNoStrum == null) return null;
  return (pDown: pDown, pUp: pUp, pNoStrum: pNoStrum);
}

/// Run the real [LivePipeline] over [pcm] and return every published onset with both
/// tiers' probabilities, plus the number of strums lost to frame coalescing.
///
/// The coalesced count is RETURNED rather than accumulated in a top-level variable,
/// which is what it was before this file existed: shared mutable state across two
/// corpora's tests would silently pool one corpus's exclusions into the other's report.
({List<Heard> heard, int coalesced}) heardWithProbs(
  List<double> pcm,
  LiveCrnnStrumClassifier crnn,
  CrnnStrumNet net, {
  int sampleRate = kSweepSampleRate,
  int chunk = 1024,
}) {
  final recorder = RecordingClassifier(crnn);
  final pipeline = LivePipeline.debugWithClassifier(
    recorder,
    sampleRate: sampleRate,
  );
  // `LiveFrame` carries direction and confidence but NOT the raw probabilities, so the
  // times come from the frames and the probabilities from the recorder, zipped by order.
  // That zip is an assumption — one classification, one published strum — and it is
  // CHECKED rather than trusted: a pipeline-side guard that dropped an event would
  // silently shift every probability onto the wrong onset, which is exactly the class of
  // error this corpus has already caught twice.
  //
  // A SILENT TAIL, and it is load-bearing rather than tidy. Without it the run reported
  // 172 published strums for 173 classifications: the analyzer classifies an onset only
  // after `_classifyAfterFrames` of post-onset evidence, so the final onset's verdict
  // arrives after the audio has run out and never reaches a published frame. One second
  // of zeros lets it through, which turns the zip below from an assumption into an
  // identity — and the strict check stays, so if the discrepancy ever becomes something
  // OTHER than an end effect the measurement stops instead of silently pairing
  // probabilities with the wrong onsets.
  final padded = [...pcm, ...List<double>.filled(sampleRate, 0)];
  // FRAME COALESCING, measured the hard way. `LiveFrame` is emitted on a sample clock at
  // about 15 Hz and carries only the LATEST strum, while `strumSeq` counts them all. Two
  // strums inside one ~66 ms emission window therefore advance the sequence by two and
  // surface ONE time — the earlier one is unobservable from the frame stream. This showed
  // up as 173 classifications against 172 published strums, and it survived both lifting
  // the suppression gate and padding with silence, which is what ruled out every other
  // explanation.
  //
  // So a jump of k is handled honestly rather than papered over: the frame's time belongs
  // to the LAST of the k, and the preceding k-1 have no recoverable time and are excluded
  // from scoring. The count is returned, because an exclusion nobody sees is just a
  // quieter error. (`test/support/modelled_guitar.dart`'s `strumOnsets` has the same loop
  // and the same blind spot — harmless where its strums are hundreds of ms apart, but it
  // is the same shape.)
  final times = <double?>[];
  var lastSeq = 0;
  for (var i = 0; i < padded.length; i += chunk) {
    final end = math.min(i + chunk, padded.length);
    for (final frame in pipeline.addChunk(padded.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        final jumped = frame.strumSeq - lastSeq;
        lastSeq = frame.strumSeq;
        for (var k = 1; k < jumped; k++) {
          times.add(null); // coalesced away: no recoverable time
        }
        times.add(frame.latestStrumTime);
      }
    }
  }
  expect(
    times.length,
    recorder.calls.length,
    reason:
        'the pipeline accounted for ${times.length} strums against '
        '${recorder.calls.length} classifications. With coalescing handled, these '
        'must agree — a remaining gap means something ELSE drops events and the '
        'probabilities can no longer be zipped onto the onsets by order',
  );
  return (
    heard: [
      for (var i = 0; i < times.length; i++)
        if (times[i] != null)
          () {
            final settled = settledProbs(
              pcm,
              net,
              recorder.onsetFrames[i],
              sampleRate: sampleRate,
            );
            return (
              atSec: times[i]!,
              pDown: recorder.calls[i].pDown,
              pUp: recorder.calls[i].pUp,
              pNoStrum: recorder.calls[i].pNoStrum,
              sDown: settled?.pDown,
              sUp: settled?.pUp,
              sNoStrum: settled?.pNoStrum,
            );
          }(),
    ],
    coalesced: times.where((t) => t == null).length,
  );
}

/// Greedy nearest-match within a tolerance, one detection per expectation.
///
/// Shared so both corpora's onset recall/precision come from the same matcher — the
/// L269 failure mode this file exists to prevent.
List<({int expected, int detected})> matchOnsets(
  List<double> expected,
  List<double> detected, {
  required double toleranceMs,
}) {
  final pairs = <({int expected, int detected})>[];
  final taken = <int>{};
  for (var e = 0; e < expected.length; e++) {
    var best = -1;
    var bestGap = double.infinity;
    for (var d = 0; d < detected.length; d++) {
      if (taken.contains(d)) continue;
      final gap = (detected[d] - expected[e]).abs() * 1000;
      if (gap <= toleranceMs && gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    if (best >= 0) {
      taken.add(best);
      pairs.add((expected: e, detected: best));
    }
  }
  return pairs;
}
