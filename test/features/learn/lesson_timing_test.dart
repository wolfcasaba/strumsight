import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/lesson_timing.dart';
import 'package:music_theory/features/learn/model/lesson.dart';

void main() {
  test('beatForElapsed converts seconds to beats at a tempo', () {
    expect(LessonTiming.beatForElapsed(2, 60), 2); // 60 BPM → 1 beat/s
    expect(LessonTiming.beatForElapsed(1, 120), 2);
  });

  test('playhead is negative through the count-in, then advances', () {
    // 4-beat count-in at 60 BPM: at t=0 → -4, at t=4s → 0, at t=5s → +1.
    expect(LessonTiming.playhead(0, 60, 4), -4);
    expect(LessonTiming.playhead(4, 60, 4), 0);
    expect(LessonTiming.playhead(5, 60, 4), 1);
  });

  test('beatsCrossedLooped handles the loop wrap as a beat-0 downbeat', () {
    // No wrap → same as beatsCrossed.
    expect(LessonTiming.beatsCrossedLooped(0.5, 1.5, 8), [1]);
    expect(LessonTiming.beatsCrossedLooped(2.0, 2.0, 8), isEmpty);
    // Wrap: the loop restart IS beat 0 (the downbeat must sound).
    expect(LessonTiming.beatsCrossedLooped(7.5, 0.5, 8), [0]);
    // Wrap with beats on both sides, in playback order.
    expect(LessonTiming.beatsCrossedLooped(6.5, 1.2, 8), [7, 0, 1]);
  });

  test('countInNumber counts 1..N then null once playing', () {
    expect(LessonTiming.countInNumber(-4.0, 4), 1);
    expect(LessonTiming.countInNumber(-3.5, 4), 1);
    expect(LessonTiming.countInNumber(-1.0, 4), 4);
    expect(LessonTiming.countInNumber(-0.1, 4), 4);
    expect(LessonTiming.countInNumber(0.0, 4), isNull);
    expect(LessonTiming.countInNumber(2.0, 4), isNull);
  });

  test('xForEvent puts an event on the strike line when its beat == playhead',
      () {
    expect(LessonTiming.xForEvent(4, 4, 40, 68), 68); // on the line
    expect(LessonTiming.xForEvent(5, 4, 40, 68), 108); // one beat ahead → right
    expect(LessonTiming.xForEvent(3, 4, 40, 68), 28); // one beat past → left
  });

  test('isFinished only after the lesson plus a bar of ring-out', () {
    // 8 beats total, 4 beats/bar → finished at playhead >= 12.
    expect(LessonTiming.isFinished(8, 8, 4), isFalse);
    expect(LessonTiming.isFinished(11.9, 8, 4), isFalse);
    expect(LessonTiming.isFinished(12, 8, 4), isTrue);
  });

  test('visibleEvents windows around the playhead', () {
    final lesson = Lessons.downUpGroove; // events across 4 bars
    final near = LessonTiming.visibleEvents(lesson.events, 0,
        aheadBeats: 4, behindBeats: 1);
    // Only early events (beat within [-1, 4]) are visible at playhead 0.
    expect(near.every((e) => e.beat >= -1 && e.beat <= 4), isTrue);
    expect(near.length, lessThan(lesson.events.length));
  });
}
