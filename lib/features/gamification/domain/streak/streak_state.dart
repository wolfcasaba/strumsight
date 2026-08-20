/// The currently supported version of the Streak V2 domain contract.
const int streakPolicyVersion = 1;

/// A recovery status reserved for the qualified-day policy in the next round.
enum StreakGraceState { none }

/// Immutable, versioned state for one user's qualified-practice streak.
final class StreakState {
  StreakState({
    required this.current,
    required this.longest,
    required this.lastQualifiedDay,
    required this.totalQualifiedDays,
    required this.freezes,
    this.graceState = StreakGraceState.none,
    Set<int> plannedRestDays = const <int>{},
    this.policyVersion = streakPolicyVersion,
  }) : plannedRestDays = Set<int>.unmodifiable(plannedRestDays) {
    if (current < 0 || longest < 0 || totalQualifiedDays < 0 || freezes < 0) {
      throw ArgumentError('Streak counters must not be negative.');
    }
    if (lastQualifiedDay < -1) {
      throw ArgumentError.value(
        lastQualifiedDay,
        'lastQualifiedDay',
        'must be -1 or a non-negative epoch day',
      );
    }
    if (policyVersion != streakPolicyVersion) {
      throw ArgumentError.value(
        policyVersion,
        'policyVersion',
        'is unsupported',
      );
    }
  }

  final int current;
  final int longest;
  final int lastQualifiedDay;
  final int totalQualifiedDays;
  final int freezes;
  final StreakGraceState graceState;
  final Set<int> plannedRestDays;
  final int policyVersion;

  StreakState copyWith({
    int? current,
    int? longest,
    int? lastQualifiedDay,
    int? totalQualifiedDays,
    int? freezes,
    StreakGraceState? graceState,
    Set<int>? plannedRestDays,
    int? policyVersion,
  }) => StreakState(
    current: current ?? this.current,
    longest: longest ?? this.longest,
    lastQualifiedDay: lastQualifiedDay ?? this.lastQualifiedDay,
    totalQualifiedDays: totalQualifiedDays ?? this.totalQualifiedDays,
    freezes: freezes ?? this.freezes,
    graceState: graceState ?? this.graceState,
    plannedRestDays: plannedRestDays ?? this.plannedRestDays,
    policyVersion: policyVersion ?? this.policyVersion,
  );

  LegacyStreakProjection toLegacyProjection() => LegacyStreakProjection(
    current: current,
    longest: longest,
    lastPracticeDay: lastQualifiedDay,
    freezes: freezes,
    totalDays: totalQualifiedDays,
  );

  @override
  bool operator ==(Object other) =>
      other is StreakState &&
      current == other.current &&
      longest == other.longest &&
      lastQualifiedDay == other.lastQualifiedDay &&
      totalQualifiedDays == other.totalQualifiedDays &&
      freezes == other.freezes &&
      graceState == other.graceState &&
      policyVersion == other.policyVersion &&
      _sameDays(plannedRestDays, other.plannedRestDays);

  @override
  int get hashCode => Object.hash(
    current,
    longest,
    lastQualifiedDay,
    totalQualifiedDays,
    freezes,
    graceState,
    policyVersion,
    Object.hashAllUnordered(plannedRestDays),
  );
}

/// Feature-neutral representation required by legacy streak consumers.
final class LegacyStreakProjection {
  const LegacyStreakProjection({
    required this.current,
    required this.longest,
    required this.lastPracticeDay,
    required this.freezes,
    required this.totalDays,
  });

  final int current;
  final int longest;
  final int lastPracticeDay;
  final int freezes;
  final int totalDays;

  @override
  bool operator ==(Object other) =>
      other is LegacyStreakProjection &&
      current == other.current &&
      longest == other.longest &&
      lastPracticeDay == other.lastPracticeDay &&
      freezes == other.freezes &&
      totalDays == other.totalDays;

  @override
  int get hashCode =>
      Object.hash(current, longest, lastPracticeDay, freezes, totalDays);
}

bool _sameDays(Set<int> left, Set<int> right) =>
    left.length == right.length && left.containsAll(right);
