import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/streak/model/streak_data.dart';
import 'package:music_theory/features/streak/streak_logic.dart';

void main() {
  const start = StreakData();

  test('first practice ever starts a 1-day streak', () {
    final s = StreakLogic.applyPractice(start, 1000);
    expect(s.current, 1);
    expect(s.longest, 1);
    expect(s.lastPracticeDay, 1000);
    expect(s.totalDays, 1);
  });

  test('practising on consecutive days grows the streak', () {
    var s = start;
    for (var day = 1000; day < 1006; day++) {
      s = StreakLogic.applyPractice(s, day);
    }
    expect(s.current, 6);
    expect(s.longest, 6);
  });

  test('a second practice the same day is a no-op', () {
    final s1 = StreakLogic.applyPractice(start, 1000);
    final s2 = StreakLogic.applyPractice(s1, 1000);
    expect(identical(s1, s2), isTrue);
    expect(s2.current, 1);
  });

  test('a clock that goes backwards does not corrupt the streak', () {
    final s1 = StreakLogic.applyPractice(start, 1000);
    final s2 = StreakLogic.applyPractice(s1, 995);
    expect(s2, s1);
  });

  test('missing a day with NO freeze resets the streak to 1', () {
    var s = StreakLogic.applyPractice(start, 1000);
    s = StreakLogic.applyPractice(s, 1001); // current 2, no freeze yet
    expect(s.freezes, 0);
    s = StreakLogic.applyPractice(s, 1003); // gap of 2 days, no freeze
    expect(s.current, 1);
    expect(s.longest, 2); // best is remembered
  });

  test('a banked freeze covers exactly one missed day', () {
    // Reach 7 total days → earns a freeze; then skip a day.
    var s = start;
    for (var day = 1000; day < 1007; day++) {
      s = StreakLogic.applyPractice(s, day);
    }
    expect(s.current, 7);
    expect(s.freezes, 1); // awarded at 7 total days
    // Skip day 1007, practise 1008 (gap of 2) → freeze saves it.
    s = StreakLogic.applyPractice(s, 1008);
    expect(s.current, 8);
    expect(s.freezes, 0);
  });

  test('a two-day gap (gap of 3) is too big for a single freeze → reset', () {
    var s = start;
    for (var day = 1000; day < 1007; day++) {
      s = StreakLogic.applyPractice(s, day);
    }
    expect(s.freezes, 1);
    s = StreakLogic.applyPractice(s, 1010); // gap of 3
    expect(s.current, 1);
    expect(s.freezes, 1); // not spent on an uncoverable gap
  });

  test('freezes are capped at maxFreezes', () {
    var s = start;
    // 21 consecutive days → 3 freeze awards (at 7,14,21), capped at 3.
    for (var day = 1000; day < 1000 + 30; day++) {
      s = StreakLogic.applyPractice(s, day);
    }
    expect(s.freezes, StreakLogic.maxFreezes);
  });

  test('atRisk / isBroken / practicedToday reflect the calendar', () {
    final s = StreakData(current: 5, longest: 5, lastPracticeDay: 1000);
    expect(StreakLogic.practicedToday(s, 1000), isTrue);
    expect(StreakLogic.atRisk(s, 1000), isFalse); // already done today
    expect(StreakLogic.atRisk(s, 1001), isTrue); // yesterday → play today
    expect(StreakLogic.isBroken(s, 1001), isFalse);
    expect(StreakLogic.isBroken(s, 1003), isTrue); // gap > 1
  });

  test('epochDayOf is 1 apart for consecutive calendar days', () {
    final a = StreakLogic.epochDayOf(DateTime(2026, 7, 9, 23, 59));
    final b = StreakLogic.epochDayOf(DateTime(2026, 7, 10, 0, 1));
    expect(b - a, 1);
    // Same day, different times → same epoch day.
    expect(StreakLogic.epochDayOf(DateTime(2026, 7, 9, 6)),
        StreakLogic.epochDayOf(DateTime(2026, 7, 9, 20)));
  });
}
