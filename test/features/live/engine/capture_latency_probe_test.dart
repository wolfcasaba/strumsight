// Synthetic capture-latency probe (D4).
//
// WHAT IT MEASURES. A strum is synthesized with its attack at a KNOWN sample,
// the signal is fed to [LivePipeline] in fixed-size chunks exactly the way the
// mic callback does, and we record how far past that attack the feed cursor
// has advanced when the LiveFrame carrying the onset — and later the direction
// verdict — comes out. Feed position IS wall time for a real capture: the mic
// hands the app a chunk only once its last sample exists, so "samples fed when
// the frame was emitted, minus the attack sample" is the honest in-app latency,
// excluding only the platform's own (unobservable from Dart) input latency.
//
// WHERE THE BOUND COMES FROM. Nothing here is a hand-picked number; every term
// is a framing constant:
//
//   onset  ≤ (onsetWindow + (superFluxConfirmHops + peakJitterHops) * onsetHop
//             + chunk) / sampleRate
//   strum  ≤ (onsetWindow + (classifyAfterFrames + peakJitterHops) * onsetHop
//             + chunk) / sampleRate
//
// * `onsetWindow` (1024) — a frame is only complete once its LAST sample has
//   been fed, so the analysis always trails the attack by up to one window.
// * `onsetHop` (256) — the frame grid's step.
// * `superFluxConfirmHops` (2) — `SuperFluxOnsetDetector._postFrames`: the
//   peak is confirmed as a local maximum two frames after it happened.
// * `classifyAfterFrames` (12) — `StrumAnalyzer._classifyAfterFrames`: the
//   ~70 ms post-onset evidence window the direction verdict waits out.
// * `peakJitterHops` (2) — the only slack term: a strum is STAGGERED across
//   six strings (8 ms ≈ 1.4 hops here), so the flux peak can land a frame or
//   two after the first string speaks. Deliberately small; the measured values
//   printed by this probe sit well inside it.
// * `chunk` — the capture buffer. The frame is emitted at the END of the
//   addChunk call that completed it, so a bigger mic chunk costs its full
//   length. THIS is the dominant term on a real device: audio_streamer 4.3.0
//   delivers 6400 samples on Android (~145 ms) and requests a 22050-sample tap
//   on iOS — see `AudioStreamerCapture` and RAG chunk 010.
//
// The probe also pins the invariant the chunking must not break: the ESTIMATED
// attack instant is identical at every chunk size. Chunk size may only change
// WHEN a verdict is delivered, never WHAT it says — that is the contract
// `SlidingFramer`'s cross-chunk continuity exists to keep.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

import '../../../support/synth.dart';

void main() {
  const sr = DspConfig.defaultSampleRate;
  const attackSec = 0.3;
  const signalSec = 1.2;

  // Mirrored from the private constants named in the header comment; they are
  // implementation details of files this round must not edit, so the probe
  // restates them and would fail loudly (over the bound) if either changed.
  const superFluxConfirmHops = 2;
  const classifyAfterFrames = 12;
  const peakJitterHops = 2;

  double boundSec(int chunk, int decisionHops) =>
      (DspConfig.onsetWindow +
          (decisionHops + peakJitterHops) * DspConfig.onsetHop +
          chunk) /
      sr;

  /// Feeds one strum in [chunk]-sample pieces and reports, in seconds past the
  /// true attack, when each verdict's frame left the pipeline.
  ({double onsetLatency, double strumLatency, double estimatedAttack}) probe(
    int chunk,
  ) {
    final signal = strumSignal(
      lowFirst: true,
      seconds: signalSec - attackSec,
      leadSilenceSeconds: attackSec,
    );
    final pipeline = LivePipeline(sampleRate: sr);
    double? onsetAt;
    double? strumAt;
    var estimatedAttack = -1.0;
    for (var i = 0; i < signal.length; i += chunk) {
      final end = i + chunk < signal.length ? i + chunk : signal.length;
      for (final frame in pipeline.addChunk(signal.sublist(i, end))) {
        if (onsetAt == null && frame.onsetSeq >= 1) {
          onsetAt = end / sr;
          estimatedAttack = frame.latestOnsetTime;
        }
        if (strumAt == null && frame.strumSeq >= 1) strumAt = end / sr;
      }
    }
    expect(onsetAt, isNotNull, reason: 'no onset detected at chunk $chunk');
    expect(strumAt, isNotNull, reason: 'no direction verdict at chunk $chunk');
    return (
      onsetLatency: onsetAt! - attackSec,
      strumLatency: strumAt! - attackSec,
      estimatedAttack: estimatedAttack,
    );
  }

  // 512/1024: the capture buffer this round targeted. 4096: the largest size
  // RAG chunk 001 used to claim. 6400: what audio_streamer 4.3.0 ACTUALLY
  // delivers on Android. 22050: the iOS tap request.
  const chunks = [512, 1024, 4096, 6400, 22050];

  test('onset and direction land inside the framing-derived bound', () {
    for (final chunk in chunks) {
      final m = probe(chunk);
      debugPrint(
        'chunk $chunk (${(chunk / sr * 1000).toStringAsFixed(1)} ms): '
        'onset ${(m.onsetLatency * 1000).toStringAsFixed(1)} ms '
        '(bound ${(boundSec(chunk, superFluxConfirmHops) * 1000).toStringAsFixed(1)}), '
        'strum ${(m.strumLatency * 1000).toStringAsFixed(1)} ms '
        '(bound ${(boundSec(chunk, classifyAfterFrames) * 1000).toStringAsFixed(1)})',
      );
      expect(
        m.onsetLatency,
        lessThanOrEqualTo(boundSec(chunk, superFluxConfirmHops)),
        reason: 'onset-first latency regressed at chunk $chunk',
      );
      expect(
        m.strumLatency,
        lessThanOrEqualTo(boundSec(chunk, classifyAfterFrames)),
        reason: 'direction-verdict latency regressed at chunk $chunk',
      );
      // The verdict can never precede the onset that triggered it.
      expect(m.strumLatency, greaterThanOrEqualTo(m.onsetLatency));
    }
  });

  test('the capture buffer is the term that dominates the budget', () {
    // Android's real 6400-sample chunk against the 512 this round targeted:
    // the rest of the path is chunk-independent, so the whole difference is
    // the mic buffer — bounded by one buffer length, and strictly positive.
    // This is the term the latency budget in chunk 010 attributes to the mic.
    final small = probe(512);
    final large = probe(6400);
    const oneBufferSec = 6400 / sr;
    expect(large.onsetLatency - small.onsetLatency, lessThan(oneBufferSec));
    expect(large.strumLatency - small.strumLatency, lessThan(oneBufferSec));
    expect(large.onsetLatency, greaterThan(small.onsetLatency));
  });

  test('chunk size changes WHEN a verdict lands, never WHAT it says', () {
    final reference = probe(chunks.first).estimatedAttack;
    expect(reference, closeTo(attackSec, 0.03));
    for (final chunk in chunks.skip(1)) {
      expect(
        probe(chunk).estimatedAttack,
        closeTo(reference, 1e-12),
        reason: 'the frame grid restarted at chunk $chunk',
      );
    }
  });
}
