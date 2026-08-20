import 'streak_state.dart';

/// Why a qualified-day application produced its resulting state.
enum StreakTransitionReason {
  firstQualifiedDay,
  alreadyQualifiedToday,
  clockMovedBackwards,
  consecutiveQualifiedDay,
  freezeCoveredMissedDay,
  resetAfterMissedDays,
}

/// A streak policy result with an auditable transition reason.
final class StreakTransition {
  const StreakTransition({required this.state, required this.reason});

  final StreakState state;
  final StreakTransitionReason reason;
}
