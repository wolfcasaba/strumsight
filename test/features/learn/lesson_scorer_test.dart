import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/lesson_scorer.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';

const _d = StrumDirection.down;
const _u = StrumDirection.up;

// A tidy 60 BPM lesson (1 s/beat) with two strokes: down@beat0, up@beat0.5.
// With a 4-beat count-in their absolute times are 4.0 s and 4.5 s.
Lesson _lesson() => Lesson(
      id: 't',
      name: 'T',
      bpm: 60,
      chords: const ['C'],
      pattern: const [_d, _u, null, null, null, null, null, null],
    );

void main() {
  test('correct direction within the window is a hit and builds combo', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0);
    s.registerStrum(_u, 4.5);
    expect(s.hits, 2);
    expect(s.maxCombo, 2);
    expect(s.accuracy, 1.0);
    expect(s.passed, isTrue);
    expect(s.lastResult, HitResult.hit);
  });

  test('a small timing error still lands inside the window', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0 + 0.2); // within ±0.28
    expect(s.hits, 1);
  });

  test('wrong direction consumes the event and breaks the combo', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0); // hit, combo 1
    s.registerStrum(_d, 4.5); // event is an up-stroke → wrong
    expect(s.hits, 1);
    expect(s.wrong, 1);
    expect(s.combo, 0);
    expect(s.lastResult, HitResult.wrongDirection);
  });

  test('advancing past an unmatched event marks it missed', () {
    final s = LessonScorer(_lesson());
    s.advance(4.4); // event0 window ends at 4.28 < 4.4 → miss
    expect(s.missed, 1);
    expect(s.lastResult, HitResult.missed);
    expect(s.combo, 0);
  });

  test('an extra strum with no event nearby is ignored', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 10.0);
    expect(s.resolved, 0);
    expect(s.hits, 0);
  });

  test('registerStrum returns how it resolved (null when it matched nothing)',
      () {
    final s = LessonScorer(_lesson());
    expect(s.registerStrum(_d, 10.0), isNull); // no event nearby
    expect(s.registerStrum(_d, 4.0), HitResult.hit);
    expect(s.registerStrum(_d, 4.5), HitResult.wrongDirection); // event is up
  });

  test('finalize turns the remaining open events into misses', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0); // 1 hit
    s.finalize();
    expect(s.hits, 1);
    expect(s.missed, 1);
    expect(s.finished, isTrue);
    expect(s.resolved, s.total);
  });

  test('passed requires clearing the threshold', () {
    final s = LessonScorer(_lesson());
    s.registerStrum(_d, 4.0); // 1/2 = 50% < 70%
    s.finalize();
    expect(s.passed, isFalse);
  });

  // A 60 BPM lesson with a chord change: down@beat0 on C, down@beat4 on G.
  // Count-in 4 → chord slots at 4.0 s (C) and 8.0 s (G).
  Lesson chordLesson() => Lesson(
        id: 'c',
        name: 'c',
        bpm: 60,
        chords: const ['C', 'G'],
        pattern: const [_d, null, null, null, null, null, null, null],
      );

  group('chord grading (secondary, lenient)', () {
    test('counts chord slots and grades correct chords as hits', () {
      final s = LessonScorer(chordLesson());
      expect(s.chordTotal, 2);
      s.observeChord('C', 3.9); // C sounding at the first stroke
      s.observeChord('G', 7.9); // G by the second
      s.finalize();
      expect(s.chordHits, 2);
      expect(s.chordMiss, 0);
      expect(s.snapshot().chordAccuracy, 1.0);
    });

    test('tolerates chord-detection lag (chord arrives just after the stroke)',
        () {
      final s = LessonScorer(chordLesson());
      s.observeChord('C', 4.3); // ~0.3 s late — still within the lag window
      s.observeChord('G', 8.3);
      s.finalize();
      expect(s.chordHits, 2);
    });

    test('wrong chords are missed and never touch the strum score', () {
      final s = LessonScorer(chordLesson());
      s.registerStrum(_d, 4.0); // a correct strum hit…
      s.observeChord('D', 3.9); // …but the wrong chord throughout
      s.observeChord('A', 7.9);
      s.finalize();
      expect(s.hits, 1); // strum hit stands
      expect(s.chordHits, 0);
      expect(s.snapshot().chordAccuracy, 0.0);
    });

    test('a strum-only lesson reports no chords', () {
      final s = LessonScorer(Lesson(
        id: 'so',
        name: 'so',
        bpm: 60,
        chords: const [''],
        pattern: const [_d, _u, null, null, null, null, null, null],
      ));
      expect(s.chordTotal, 0);
      expect(s.snapshot().hasChords, isFalse);
    });
  });

  // Game-feel (round 61): timing tiers + points + combo multiplier (chunk 016b).
  // A full down-strum bar (8 slots) over two chords → 16 events at 60 BPM,
  // 0.5 s apart, first at 4.0 s (after the 4-beat count-in).
  Lesson downLesson() => Lesson(
        id: 'dn',
        name: 'dn',
        bpm: 60,
        chords: const ['C', 'G'],
        pattern: const [_d, _d, _d, _d, _d, _d, _d, _d],
      );

  group('game-feel: timing, points, multiplier', () {
    test('a dead-on hit is PERFECT and scores the base 100', () {
      final s = LessonScorer(downLesson());
      s.registerStrum(_d, 4.0);
      expect(s.lastTiming, Timing.perfect);
      expect(s.perfectHits, 1);
      expect(s.score, 100);
      expect(s.snapshot().lastTiming, Timing.perfect);
    });

    test('a hit inside the good window is GOOD (70)', () {
      final s = LessonScorer(downLesson());
      s.registerStrum(_d, 4.0 + 0.09); // >0.05, ≤0.12
      expect(s.lastTiming, Timing.good);
      expect(s.score, 70);
    });

    test('an in-window off-beat hit is EARLY or LATE by sign', () {
      final early = LessonScorer(downLesson())..registerStrum(_d, 4.0 - 0.2);
      expect(early.lastTiming, Timing.early);
      expect(early.score, 40);
      final late = LessonScorer(downLesson())..registerStrum(_d, 4.0 + 0.2);
      expect(late.lastTiming, Timing.late);
    });

    test('combo builds a multiplier that scales points', () {
      final s = LessonScorer(downLesson());
      for (var i = 0; i < 5; i++) {
        s.registerStrum(_d, 4.0 + i * 0.5); // 5 perfect hits in a row
      }
      expect(s.combo, 5);
      expect(s.multiplier, 2);
      // 4 hits at ×1 (100 each) + the 5th at ×2 (200) = 600.
      expect(s.score, 600);
    });

    test('a miss resets the multiplier and clears the timing', () {
      final s = LessonScorer(downLesson());
      for (var i = 0; i < 5; i++) {
        s.registerStrum(_d, 4.0 + i * 0.5);
      }
      expect(s.multiplier, 2);
      s.advance(6.5 + 0.28 + 0.01); // let the 6th event (6.5 s) pass unhit
      expect(s.combo, 0);
      expect(s.multiplier, 1);
      expect(s.lastTiming, isNull);
      expect(s.lastResult, HitResult.missed);
    });

    test('wrong direction clears the timing and breaks the multiplier', () {
      final s = LessonScorer(downLesson());
      for (var i = 0; i < 5; i++) {
        s.registerStrum(_d, 4.0 + i * 0.5);
      }
      s.registerStrum(_u, 6.5); // the event is a down-stroke → wrong
      expect(s.lastResult, HitResult.wrongDirection);
      expect(s.lastTiming, isNull);
      expect(s.combo, 0);
    });
  });

  test('a slower practice tempo scales the event times', () {
    // _lesson() is 60 BPM; override to 30 BPM → 2 s/beat, so down@beat0 lands at
    // (4 + 0)·2 = 8.0 s instead of 4.0 s.
    final s = LessonScorer(_lesson(), bpm: 30);
    s.registerStrum(_d, 4.0); // the original-tempo time → now just an extra
    expect(s.hits, 0);
    s.registerStrum(_d, 8.0); // the slowed-down time → hit
    expect(s.hits, 1);
  });

  test('the nearest open event is chosen when two are in range', () {
    // Two downs a hair apart; a strum between them should take the closer one.
    final lesson = Lesson(
      id: 't2',
      name: 'T2',
      bpm: 60,
      chords: const ['C'],
      pattern: const [_d, _d, null, null, null, null, null, null],
    );
    final s = LessonScorer(lesson); // events at 4.0 and 4.5
    s.registerStrum(_d, 4.45); // closer to 4.5
    s.registerStrum(_d, 4.0);
    expect(s.hits, 2); // both matched, none double-counted
  });
}
