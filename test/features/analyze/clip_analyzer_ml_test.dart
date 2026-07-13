import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_analyzer.dart';
import 'package:music_theory/features/analyze/providers/analyze_providers.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../support/synth.dart';

/// r165 — the Analyze path's CRNN refine seam (deployment decided by the
/// r164 real-recording A/B: heuristic 38.9 % vs CRNN 86.7 % on real takes).
/// The refiner re-labels each detected strum's DIRECTION at its attack time;
/// detection, times and the rest of the timeline stay the DSP's.
void main() {
  final clip = strumPattern(
    lowFirstPerStrum: [true, false, true, false],
    gapSeconds: 0.5,
  );

  test('an injected refiner re-labels strum directions, keeping the times',
      () {
    final seen = <double>[];
    final analyzer = ClipAnalyzer(
      strumRefiner: (pcm, sr, onsets) {
        seen.addAll(onsets);
        return [
          for (var i = 0; i < onsets.length; i++)
            const StrumClassification(
                direction: StrumDirection.up, confidence: 0.93),
        ];
      },
    );
    final result = analyzer.analyze(clip, 44100);
    final baseline = const ClipAnalyzer().analyze(clip, 44100);

    expect(result.strums, isNotEmpty);
    expect(seen, hasLength(result.strums.length),
        reason: 'the refiner sees every detected strum');
    for (var i = 0; i < result.strums.length; i++) {
      expect(result.strums[i].direction, StrumDirection.up);
      expect(result.strums[i].confidence, 0.93);
      expect(result.strums[i].timeSec, baseline.strums[i].timeSec,
          reason: 'refine changes the label, never the attack time');
    }
    expect(result.bpm, baseline.bpm,
        reason: 'tempo comes from the times, so it must not move');
  });

  test('a throwing refiner falls back to the heuristic labels (never crash)',
      () {
    final analyzer = ClipAnalyzer(
      strumRefiner: (pcm, sr, onsets) => throw StateError('model exploded'),
    );
    final result = analyzer.analyze(clip, 44100);
    final baseline = const ClipAnalyzer().analyze(clip, 44100);

    expect(result.strums, hasLength(baseline.strums.length));
    for (var i = 0; i < result.strums.length; i++) {
      expect(result.strums[i].direction, baseline.strums[i].direction);
    }
  });

  test('runClipAnalysis wires real weights bytes end-to-end (smoke)', () {
    final bytes = Uint8List.fromList(
        File('assets/ml/strum_crnn.bin').readAsBytesSync());
    final refined = runClipAnalysis((clip.toList(), 44100, bytes));
    final baseline = runClipAnalysis((clip.toList(), 44100, null));

    expect(refined.strums, hasLength(baseline.strums.length),
        reason: "the CRNN refines labels; detection stays the DSP's");
    for (var i = 0; i < refined.strums.length; i++) {
      expect(refined.strums[i].timeSec, baseline.strums[i].timeSec);
      expect(refined.strums[i].confidence, inInclusiveRange(0.5, 1.0),
          reason: 'softmax max-prob is always >= 0.5 for 2 classes');
    }
  });

  test('batch confidences are CALIBRATED P(correct), not raw softmax (r171)',
      () {
    // Fold-measured knots: <0.7→62%, 0.7–0.9→64%, 0.9–0.97→73%,
    // 0.97–0.995→83%, ≥0.995→96%.
    expect(StrumCrnn.calibrate(0.60), closeTo(0.62, 0.03));
    expect(StrumCrnn.calibrate(0.935), closeTo(0.73, 0.03));
    expect(StrumCrnn.calibrate(0.999), closeTo(0.96, 0.02));
    var prev = 0.0;
    for (var p = 0.5; p <= 1.0001; p += 0.01) {
      final c = StrumCrnn.calibrate(p);
      expect(c, greaterThanOrEqualTo(prev));
      expect(c, inInclusiveRange(0.5, 0.97));
      prev = c;
    }
    // And the clip path emits the calibrated value (share cards / timeline).
    final bytes = Uint8List.fromList(
        File('assets/ml/strum_crnn.bin').readAsBytesSync());
    final refined = runClipAnalysis((clip.toList(), 44100, bytes));
    for (final s in refined.strums) {
      expect(s.confidence, lessThanOrEqualTo(0.97),
          reason: 'raw softmax 0.99+ must not surface on the timeline');
    }
  });

  test('runClipAnalysis with garbage weights bytes falls back cleanly', () {
    final result =
        runClipAnalysis((clip.toList(), 44100, Uint8List(16)));
    final baseline = runClipAnalysis((clip.toList(), 44100, null));
    expect(result.strums, hasLength(baseline.strums.length));
  });
}
