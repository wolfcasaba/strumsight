import 'dart:math' as math;

import 'streak_state.dart';
import 'streak_transition.dart';

/// Pure policy for applying one caller-confirmed qualified epoch day.
final class StreakPolicy {
  const StreakPolicy();

  static const int freezeEveryQualifiedDays = 7;
  static const int maxFreezes = 3;

  StreakTransition applyQualifiedDay(StreakState previous, int qualifiedDay) {
    if (qualifiedDay == previous.lastQualifiedDay) {
      return StreakTransition(
        state: previous,
        reason: StreakTransitionReason.alreadyQualifiedToday,
      );
    }
    if (qualifiedDay < previous.lastQualifiedDay) {
      return StreakTransition(
        state: previous,
        reason: StreakTransitionReason.clockMovedBackwards,
      );
    }

    final isFirstQualifiedDay = previous.lastQualifiedDay < 0;
    final gap = isFirstQualifiedDay
        ? null
        : qualifiedDay - previous.lastQualifiedDay;
    var freezes = previous.freezes;
    late final int current;
    late final StreakTransitionReason reason;
    if (isFirstQualifiedDay) {
      current = 1;
      reason = StreakTransitionReason.firstQualifiedDay;
    } else if (gap == 1) {
      current = previous.current + 1;
      reason = StreakTransitionReason.consecutiveQualifiedDay;
    } else if (gap == 2 && freezes > 0) {
      current = previous.current + 1;
      freezes -= 1;
      reason = StreakTransitionReason.freezeCoveredMissedDay;
    } else {
      current = 1;
      reason = StreakTransitionReason.resetAfterMissedDays;
    }

    final totalQualifiedDays = previous.totalQualifiedDays + 1;
    if (totalQualifiedDays % freezeEveryQualifiedDays == 0 &&
        freezes < maxFreezes) {
      freezes += 1;
    }
    return StreakTransition(
      state: previous.copyWith(
        current: current,
        longest: math.max(previous.longest, current),
        lastQualifiedDay: qualifiedDay,
        totalQualifiedDays: totalQualifiedDays,
        freezes: freezes,
      ),
      reason: reason,
    );
  }
}
