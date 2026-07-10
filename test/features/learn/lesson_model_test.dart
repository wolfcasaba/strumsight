import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/streak/daily_challenge.dart';

void main() {
  group('simplified (beginner dynamic-difficulty cut)', () {
    test('keeps only on-beat down-strokes', () {
      // downUpGroove = D _ D U _ U D U → downs at slots 0,2,6 (beats 0,1,3),
      // ups at off-beats. Simplified should keep the 3 on-beat downs per bar.
      final s = Lessons.downUpGroove.simplified;
      expect(s.events.every((e) => e.direction == StrumDirection.down), isTrue);
      expect(s.events.every((e) => e.beat % 1.0 == 0), isTrue);
      expect(s.events.length, lessThan(Lessons.downUpGroove.events.length));
      // Same tempo/length/identity so it still scores + records the same lesson.
      expect(s.bpm, Lessons.downUpGroove.bpm);
      expect(s.totalBeats, Lessons.downUpGroove.totalBeats);
      expect(s.id, Lessons.downUpGroove.id);
    });

    test('an all-on-beat-downs lesson is returned unchanged', () {
      // firstStrums is already downs on beats 0..3 → nothing to simplify.
      final l = Lessons.firstStrums;
      expect(identical(l.simplified, l), isTrue);
    });

    test('a purely off-beat pattern falls back to the full lesson (never empty)',
        () {
      // reggaeSkank = all up-strokes on off-beats → no on-beat downs.
      final l = Lessons.reggaeSkank;
      expect(identical(l.simplified, l), isTrue);
      expect(l.simplified.events, isNotEmpty);
    });
  });

  test('a lesson expands its pattern into beat-timed, chord-tagged events', () {
    final lesson = Lessons.firstStrums; // Em Em G G, downs on beats 0,1,2,3
    // 4 downstrokes per bar? pattern = D _ D _ D _ D _ → slots 0,2,4,6 → beats
    // 0,1,2,3 each bar.
    expect(lesson.events.first.beat, 0);
    expect(lesson.events.first.chord, 'Em');
    expect(lesson.events.first.direction, StrumDirection.down);
    // 4 bars × 4 strokes = 16 events.
    expect(lesson.events.length, 16);
    // Bar 3 (beats 8..) uses G.
    expect(lesson.events.firstWhere((e) => e.beat >= 8).chord, 'G');
    expect(lesson.totalBeats, 16);
  });

  test('eighth-note offbeats land on x.5 beats', () {
    final lesson = Lessons.downUpGroove; // has up-strokes on offbeats
    final up = lesson.events.firstWhere((e) => e.direction == StrumDirection.up);
    expect(up.beat % 1, 0.5);
  });

  test('chordSequence lists the distinct chords in order', () {
    expect(Lessons.downUpGroove.chordSequence, ['C', 'G', 'Am', 'F']);
    expect(Lessons.firstStrums.chordSequence, ['Em', 'G']);
  });

  test('fromDailyChallenge yields a playable strum-only one-bar lesson', () {
    final c = DailyChallenge.forDay(20000);
    final lesson = Lessons.fromDailyChallenge(c);
    expect(lesson.events.length, c.pattern.length);
    expect(lesson.events.every((e) => e.chord.isEmpty), isTrue);
    expect(lesson.name, c.name);
  });

  test('built-in lessons are non-empty and well-formed', () {
    for (final lesson in Lessons.all) {
      expect(lesson.events, isNotEmpty);
      expect(lesson.bpm, greaterThan(0));
      expect(lesson.events, everyElement(
          predicate<LessonEvent>((e) => e.beat >= 0 && e.beat < lesson.totalBeats)));
    }
  });
}
