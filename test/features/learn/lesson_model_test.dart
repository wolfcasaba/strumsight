import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/streak/daily_challenge.dart';

void main() {
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
