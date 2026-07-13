import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/model/strum.dart';

/// r168 — the STREAMING front-end of the live 70 ms model. The risky logic is
/// the ring/frame bookkeeping (absolute sample indexing across hops), so the
/// contract test compares the streamed window against one built from the
/// WHOLE signal in one go — same helpers, different data path.
void main() {
  const sr = 44100;
  const window = 1024;
  const hop = 256;

  Float64List synthSignal(int n, int seed) {
    final rng = math.Random(seed);
    final x = Float64List(n);
    for (var i = 0; i < n; i++) {
      // A few sines + noise so every log-mel band has structure.
      x[i] = 0.3 * math.sin(2 * math.pi * 110 * i / sr) +
          0.2 * math.sin(2 * math.pi * 523 * i / sr) +
          0.1 * (rng.nextDouble() * 2 - 1);
    }
    return x;
  }

  test('streamed truncated window == whole-signal reference', () {
    final signal = synthSignal(sr, 7); // 1 s
    final fe = LiveCrnnFrontend(sampleRate: sr, window: window, hop: hop);

    // Stream like StrumAnalyzer does: frames of `window`, advanced by `hop`.
    final nFrames = 1 + (signal.length - window) ~/ hop;
    for (var f = 0; f < nFrames; f++) {
      fe.observe(Float64List.sublistView(signal, f * hop, f * hop + window));
    }
    const onsetFrame = 80; // well inside
    const currentFrame = 92; // onset + 12 hops (the classify instant)
    final streamed = fe.windowAt(onsetFrame, currentFrame);

    // Reference: the same window from the whole signal, no ring involved.
    final availableEnd = currentFrame * hop + window;
    final reference = LiveCrnnFrontend.referenceWindow(
      Float64List.sublistView(signal, 0, availableEnd),
      sr,
      onsetFrame * hop / sr,
    );

    expect(streamed, hasLength(reference.length));
    for (var i = 0; i < reference.length; i++) {
      for (var j = 0; j < reference[i].length; j++) {
        expect(streamed[i][j], closeTo(reference[i][j], 1e-9),
            reason: 'row $i mel $j');
      }
    }
  });

  test('rows past the available audio are the zero-audio log-mel floor', () {
    final signal = synthSignal(sr ~/ 2, 3);
    final fe = LiveCrnnFrontend(sampleRate: sr, window: window, hop: hop);
    final nFrames = 1 + (signal.length - window) ~/ hop;
    for (var f = 0; f < nFrames; f++) {
      fe.observe(Float64List.sublistView(signal, f * hop, f * hop + window));
    }
    // Classify right at the last observed frame: most of the 15-row window's
    // tail is future audio -> those rows must equal log(1e-6) (zero audio),
    // exactly like training's zeroed tail.
    final w = fe.windowAt(nFrames - 13, nFrames - 1);
    final floor = math.log(1e-6);
    expect(w.last.every((v) => (v - floor).abs() < 1e-9), isTrue,
        reason: 'the final row is fully past the deadline');
  });

  test('LiveCrnnStrumClassifier implements the seam and returns a verdict',
      () {
    // Degenerate weights are fine — the seam contract is direction+confidence
    // shapes, exercised without the real asset (which the parity tests own).
    final classifier = LiveCrnnStrumClassifier.tryLoad(
      'assets/ml/strum_crnn_live.bin',
      sampleRate: sr,
    );
    expect(classifier, isNotNull,
        reason: 'the live weights asset ships with the repo');
    final signal = synthSignal(sr, 11);
    final nFrames = 1 + (signal.length - window) ~/ hop;
    StrumClassification? c;
    for (var f = 0; f < nFrames; f++) {
      classifier!.observe(
        Float64List.sublistView(signal, f * hop, f * hop + window),
        const StrumFrameFeatures(lowEnergy: 0, highEnergy: 0, centroid: 0),
      );
      if (f == 92) {
        c = classifier.classifyAt(onsetFrame: 80, currentFrame: 92);
      }
    }
    expect(c, isNotNull);
    expect(c!.direction, isIn([StrumDirection.down, StrumDirection.up]));
    expect(c.confidence, inInclusiveRange(0.5, 1.0));
  });

  test('tryLoad returns null when the asset is missing (heuristic fallback)',
      () {
    expect(
        LiveCrnnStrumClassifier.tryLoad('assets/ml/nope.bin', sampleRate: sr),
        isNull);
  });
}
