import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/lesson_scorer.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';

const _d = StrumDirection.down;
const _u = StrumDirection.up;

Lesson _lesson() => Lesson(
      id: 't',
      name: 'T',
      bpm: 60,
      chords: const ['C'],
      pattern: const [_d, _u, null, null, null, null, null, null],
    );

/// Chunk 016b P3 — latency calibration. The mic→DSP→score path detects a
/// strum ~100–200 ms after it was PLAYED (device-specific). Without
/// compensation a perfectly-on-beat player is graded LATE (or misses the
/// window entirely); with the calibrated [inputLatencySec] the scorer
/// evaluates strums at their PLAYED time.
void main() {
  test('a calibrated scorer grades an on-beat player PERFECT despite '
      'detection latency', () {
    final s = LessonScorer(_lesson(), inputLatencySec: 0.15);
    // Played exactly on the beats (4.0, 4.5); DETECTED 150 ms later.
    s.registerStrum(_d, 4.0 + 0.15);
    s.registerStrum(_u, 4.5 + 0.15);
    expect(s.hits, 2);
    expect(s.perfectHits, 2, reason: 'latency must not eat the PERFECT tier');
  });

  test('without calibration the same run is NOT perfect (the problem)', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0 + 0.15);
    s.registerStrum(_u, 4.5 + 0.15);
    expect(s.perfectHits, 0);
  });

  test('large latency would push strums out of the window — calibration '
      'keeps them matchable', () {
    final s = LessonScorer(_lesson(), inputLatencySec: 0.30);
    s.registerStrum(_d, 4.0 + 0.30); // raw offset > windowSec (0.28)
    expect(s.hits, 1);
  });

  test('misses are judged on corrected time (events stay open for the '
      'latency tail)', () {
    final s = LessonScorer(_lesson(), inputLatencySec: 0.30);
    // At raw 4.30 the event played at 4.0 is only NOW arriving via the mic;
    // advance must not close it as missed yet.
    s.advance(4.30);
    expect(s.missed, 0);
    s.registerStrum(_d, 4.31);
    expect(s.hits, 1);
  });

  test('a wrong-direction hit exposes the EXPECTED direction (016b P6 '
      'coaching vocabulary)', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_u, 4.0); // the beat-0 event wants a DOWN stroke
    expect(s.lastResult, HitResult.wrongDirection);
    expect(s.lastExpectedDirection, _d,
        reason: 'the UI badge must say which way the stroke SHOULD have gone');
    // A correct hit clears it (no stale coaching on the next verdict).
    s.registerStrum(_u, 4.5);
    expect(s.lastResult, HitResult.hit);
    expect(s.lastExpectedDirection, isNull);
  });

  test('the snapshot carries the expected direction to the UI', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_u, 4.0);
    expect(s.snapshot().expectedDirection, _d);
    s.registerStrum(_u, 4.5);
    expect(s.snapshot().expectedDirection, isNull);
  });
}
