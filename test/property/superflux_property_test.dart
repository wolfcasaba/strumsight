// Randomized property gate for the SuperFlux onset detector (HORIZON —
// docs/plans/ml-track.md P0.2). Same seed convention as dsp_property_test:
// PROPERTY_SEED env (CI: run id), absent → 42 (deterministic dev loop).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/superflux_onset_detector.dart';

import '../support/synth.dart';

const _sr = 44100;
const _tolSec = 0.05; // the field-standard ±50 ms eval window (chunk 015)

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('SuperFlux finds ≥85% of randomized 16th-note strums, ≤15% spurious',
      () {
    var totalExpected = 0, totalHits = 0, totalDetected = 0;
    for (var trial = 0; trial < 5; trial++) {
      final bpm = 100 + rng.nextInt(81); // 100–180
      final gap = 60 / bpm / 4;
      final count = 10 + rng.nextInt(5); // 10–14 strums
      final stagger = 6 + rng.nextDouble() * 4; // 6–10 ms
      final signal = overlappingStrums(
        lowFirstPerStrum: List.generate(count, (_) => rng.nextBool()),
        gapSeconds: gap,
        ringSeconds: gap * 2, // previous strum still rings — adversarial
        staggerMs: stagger,
        sampleRate: _sr,
      );
      final expected = [for (var i = 0; i < count; i++) 0.1 + i * gap];

      final d = SuperFluxOnsetDetector(sampleRate: _sr);
      final onsets = <double>[];
      for (final frame in frames(signal, d.window, d.hop)) {
        final t = d.processFrame(frame);
        if (t != null) onsets.add(t);
      }

      final remaining = List<double>.from(expected);
      for (final t in onsets) {
        final i = remaining.indexWhere((e) => (e - t).abs() <= _tolSec);
        if (i >= 0) {
          remaining.removeAt(i);
          totalHits++;
        }
      }
      totalExpected += count;
      totalDetected += onsets.length;
    }
    final recall = totalHits / totalExpected;
    final spurious = (totalDetected - totalHits) / totalExpected;
    // ignore: avoid_print
    print('superflux property: recall=$recall spurious=$spurious');
    expect(recall, greaterThanOrEqualTo(0.85),
        reason: 'recall $totalHits/$totalExpected');
    expect(spurious, lessThanOrEqualTo(0.15),
        reason: 'spurious ${totalDetected - totalHits}/$totalExpected');
  });
}
