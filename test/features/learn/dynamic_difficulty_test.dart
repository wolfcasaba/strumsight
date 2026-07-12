import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/lesson_scorer.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';

/// Round 154 — dynamic difficulty (016b P4): the fail-streak signal that
/// offers the Easy cut. Consecutive misses/wrong-directions accumulate; one
/// clean hit resets — a struggling player gets a hand, a recovering one
/// doesn't get nagged.
Lesson _lesson() => Lesson(
      id: 'dd',
      name: 'DD',
      bpm: 60,
      chords: const ['C', 'C'],
      pattern: const [
        StrumDirection.down, StrumDirection.down,
        StrumDirection.down, StrumDirection.down,
        StrumDirection.down, StrumDirection.down,
        StrumDirection.down, StrumDirection.down,
      ],
    );

void main() {
  test('4 consecutive failures raise the suggestion', () {
    final s = LessonScorer(_lesson());
    expect(s.suggestsEasier, isFalse);
    // Miss the first four events (advance past their windows).
    s.advance(4 + 2.2); // events at 4.0, 4.5, 5.0, 5.5 all closed
    expect(s.failStreak, greaterThanOrEqualTo(4));
    expect(s.suggestsEasier, isTrue);
  });

  test('a clean hit resets the streak — no nagging a recovery', () {
    final s = LessonScorer(_lesson());
    s.advance(4 + 1.2); // miss the first two (4.0, 4.5); 5.0 still open
    expect(s.failStreak, 2);
    s.registerStrum(StrumDirection.down, 5.2); // clean on-time hit
    expect(s.failStreak, 0);
    expect(s.suggestsEasier, isFalse);
  });

  test('wrong-direction strums count toward the streak', () {
    final s = LessonScorer(_lesson());
    for (var i = 0; i < 4; i++) {
      s.registerStrum(StrumDirection.up, 4.0 + i * 0.5); // all wrong-way
    }
    expect(s.failStreak, 4);
    expect(s.suggestsEasier, isTrue);
  });
}
