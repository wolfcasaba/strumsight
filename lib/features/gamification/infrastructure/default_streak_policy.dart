import 'package:strumsight/features/practice_generator/public.dart';

import '../domain/activity/learning_activity_event.dart';

/// Immutable, validated inputs for the qualified-day application policy.
final class DefaultStreakPolicyConfig {
  DefaultStreakPolicyConfig({
    required this.minQualifiedDuration,
    required this.minRecoveryDuration,
    this.graceDays = 1,
  }) {
    if (minQualifiedDuration.isNegative || minRecoveryDuration.isNegative) {
      throw ArgumentError('Qualified-day durations must not be negative.');
    }
    if (minRecoveryDuration > minQualifiedDuration) {
      throw ArgumentError.value(
        minRecoveryDuration,
        'minRecoveryDuration',
        'must not exceed minQualifiedDuration',
      );
    }
    if (graceDays < 0) {
      throw ArgumentError.value(graceDays, 'graceDays', 'must not be negative');
    }
  }

  /// The standard product policy: 120 seconds normally, 60 in recovery.
  factory DefaultStreakPolicyConfig.standard() => DefaultStreakPolicyConfig(
    minQualifiedDuration: const Duration(seconds: 120),
    minRecoveryDuration: const Duration(seconds: 60),
  );

  /// Minimum valid activity required outside an explicit recovery session.
  final Duration minQualifiedDuration;

  /// Minimum valid activity required when recovery was explicitly allowed.
  final Duration minRecoveryDuration;

  /// Number of unqualified calendar days projected as a compassionate grace.
  final int graceDays;
}

/// Deterministic threshold and planned-rest policy used by [StreakService].
///
/// The class has no clock or persistence dependency. Planned rest is read only
/// from the Practice Generator's public typed decision contract.
final class DefaultStreakPolicy {
  DefaultStreakPolicy({DefaultStreakPolicyConfig? config})
    : config = config ?? DefaultStreakPolicyConfig.standard();

  final DefaultStreakPolicyConfig config;

  /// Returns whether [activity] reaches the applicable inclusive threshold.
  bool qualifies(
    LearningActivityEvent? activity, {
    required bool recoveryEligible,
  }) {
    if (activity == null) return false;
    final minimum = recoveryEligible
        ? config.minRecoveryDuration
        : config.minQualifiedDuration;
    return activity.duration >= minimum;
  }

  /// Converts typed, local planned-rest decisions into timezone-neutral epoch
  /// days without reading the device clock or parsing a reason-code string.
  Set<int> plannedRestEpochDays(WeeklyScheduleDecision? schedule) {
    if (schedule == null) return const <int>{};
    return Set<int>.unmodifiable({
      for (final decision in schedule.dayDecisions)
        if (decision.reasonCodes.contains(ScheduleDecisionReason.restDay.code))
          _epochDayFor(decision.date),
    });
  }

  static int _epochDayFor(LocalDate date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
