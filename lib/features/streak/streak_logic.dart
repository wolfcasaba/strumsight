import 'dart:math' as math;

import 'model/streak_data.dart';

/// Pure practice-streak maths (RAG chunk 013 — retention). Kept free of clocks
/// and IO so it is exhaustively unit-testable; the controller supplies "today".
class StreakLogic {
  StreakLogic._();

  /// Grant one streak-freeze every N practice days…
  static const int freezeEveryNDays = 7;

  /// …up to this many banked.
  static const int maxFreezes = 3;

  /// The local-midnight epoch day for [d] (days since 1970-01-01, local time).
  /// Using local midnight keeps consecutive calendar days exactly 1 apart.
  static int epochDayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Apply a practice event on [today] to [prev], returning the new state.
  ///
  /// Rules (loss-aversion model, à la Duolingo):
  /// - already practiced today (or a clock that went backwards) → no change;
  /// - practiced yesterday → streak + 1;
  /// - missed exactly one day but a freeze is banked → streak + 1, spend a
  ///   freeze (the freeze "covers" the gap);
  /// - any larger gap (or no freeze) → streak resets to 1.
  /// A freeze is then awarded every [freezeEveryNDays] total practice days,
  /// capped at [maxFreezes].
  static StreakData applyPractice(StreakData prev, int today) {
    if (today <= prev.lastPracticeDay) return prev; // done today / clock skew

    int current;
    var freezes = prev.freezes;
    if (prev.lastPracticeDay < 0) {
      current = 1; // first practice ever
    } else {
      final gap = today - prev.lastPracticeDay;
      if (gap == 1) {
        current = prev.current + 1;
      } else if (gap == 2 && freezes > 0) {
        current = prev.current + 1;
        freezes -= 1;
      } else {
        current = 1;
      }
    }

    final totalDays = prev.totalDays + 1;
    if (totalDays % freezeEveryNDays == 0 && freezes < maxFreezes) {
      freezes += 1;
    }

    return StreakData(
      current: current,
      longest: math.max(prev.longest, current),
      lastPracticeDay: today,
      freezes: freezes,
      totalDays: totalDays,
    );
  }

  /// Whether the user has already practiced on [today].
  static bool practicedToday(StreakData d, int today) =>
      d.lastPracticeDay == today;

  /// The streak is "at risk" when there is a live streak, today isn't done yet,
  /// and the last practice was exactly yesterday — practise today or lose it
  /// (unless a freeze saves it). Drives the "don't break your streak" nudge.
  static bool atRisk(StreakData d, int today) =>
      d.hasStreak &&
      !practicedToday(d, today) &&
      (today - d.lastPracticeDay) == 1;

  /// Whether the streak is already broken as of [today] (gap > 1 and today not
  /// yet practised) — a freeze can still rescue it on the next practice.
  static bool isBroken(StreakData d, int today) =>
      d.hasStreak &&
      !practicedToday(d, today) &&
      (today - d.lastPracticeDay) > 1;
}
