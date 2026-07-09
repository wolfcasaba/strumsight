import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/progress/model/practice_stats.dart';

void main() {
  PracticeEntry entry({
    required int day,
    PracticeSource source = PracticeSource.live,
    int seconds = 0,
    int strokes = 0,
    int chords = 0,
    double? dir,
  }) =>
      PracticeEntry(
        day: day,
        source: source,
        seconds: seconds,
        strokes: strokes,
        chords: chords,
        directionAccuracy: dir,
      );

  test('totals fold seconds / strokes / distinct days', () {
    final stats = PracticeStats([
      entry(day: 100, seconds: 60, strokes: 4),
      entry(day: 100, seconds: 30, strokes: 2),
      entry(day: 101, seconds: 90, strokes: 6),
    ]);
    expect(stats.totalSessions, 3);
    expect(stats.totalSeconds, 180);
    expect(stats.totalStrokes, 12);
    expect(stats.daysPracticed, 2);
  });

  test('negative durations are clamped, never subtracting from totals', () {
    final stats = PracticeStats([
      entry(day: 1, seconds: -5, strokes: -3),
      entry(day: 1, seconds: 10, strokes: 2),
    ]);
    expect(stats.totalSeconds, 10);
    expect(stats.totalStrokes, 2);
  });

  test('averageDirectionAccuracy folds ONLY scored runs; null when none', () {
    expect(
      PracticeStats([entry(day: 1, seconds: 60)]).averageDirectionAccuracy,
      isNull,
    );
    final stats = PracticeStats([
      entry(day: 1, source: PracticeSource.learn, dir: 0.6),
      entry(day: 2, source: PracticeSource.learn, dir: 0.8),
      entry(day: 2, source: PracticeSource.live, seconds: 30), // unscored
    ]);
    expect(stats.averageDirectionAccuracy, closeTo(0.7, 1e-9));
    expect(stats.bestDirectionAccuracy, 0.8);
  });

  test('sessionsFrom counts per source', () {
    final stats = PracticeStats([
      entry(day: 1, source: PracticeSource.live),
      entry(day: 1, source: PracticeSource.learn),
      entry(day: 2, source: PracticeSource.learn),
    ]);
    expect(stats.sessionsFrom(PracticeSource.live), 1);
    expect(stats.sessionsFrom(PracticeSource.learn), 2);
    expect(stats.sessionsFrom(PracticeSource.analyze), 0);
  });

  test('lastDays is a zero-filled window ending at today, oldest-first', () {
    const today = 1000;
    final stats = PracticeStats([
      entry(day: today, seconds: 120),
      entry(day: today, seconds: 60), // same day → summed
      entry(day: today - 2, seconds: 30),
      entry(day: today - 30, seconds: 999), // outside the 7-day window
    ]);
    final week = stats.lastDays(today);
    expect(week.length, 7);
    expect(week.first.day, today - 6);
    expect(week.last.day, today);
    expect(week.last.seconds, 180); // both of today's entries
    expect(week.last.sessions, 2);
    // The gap day (today-1) is zero-filled.
    expect(week[5].day, today - 1);
    expect(week[5].isEmpty, isTrue);
    // today-2 carries its 30s.
    expect(week[4].day, today - 2);
    expect(week[4].seconds, 30);
    // The 30-days-ago entry never leaks into the window.
    expect(week.every((d) => d.seconds != 999), isTrue);
  });

  test('PracticeEntry survives a JSON round-trip', () {
    final e = entry(
      day: 42,
      source: PracticeSource.learn,
      seconds: 75,
      strokes: 8,
      chords: 3,
      dir: 0.875,
    );
    expect(PracticeEntry.fromJson(e.toJson()), e);
  });

  test('an unknown persisted source degrades to live, never throws', () {
    final e = PracticeEntry.fromJson({'day': 1, 'src': 'someFutureThing'});
    expect(e.source, PracticeSource.live);
  });
}
