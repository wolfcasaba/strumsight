import '../model/learner_constraints.dart';
import '../model/plan_enums.dart';
import '../model/practice_goal.dart';
import '../model/weekly_availability.dart';

/// A reported mismatch between a candidate plan and a learner constraint.
///
/// The validator reports it but does not repair or reinterpret it.
final class ConstraintViolation {
  ConstraintViolation({required this.constraint, required String reason})
    : reason = _requireText(reason, 'reason');

  final LearnerConstraint constraint;
  final String reason;
}

/// Stable validation codes for the goal and constraint input boundary.
abstract final class RequestValidationCode {
  static const String customGoalNotExecutable = 'goal.custom.notExecutable';
  static const String tooManyPrimaryGoals = 'goal.primary.tooMany';
  static const String hardConstraintViolated = 'constraint.hard.violated';
  static const String softConstraintViolated = 'constraint.soft.violated';
  static const String unavailableDayScheduled =
      'availability.unavailable.scheduled';
  static const String hardMaximumExceeded = 'availability.hardMaximum.exceeded';
  static const String softMaximumExceeded = 'availability.softMaximum.exceeded';
}

/// One deterministic, presentable validation finding.
final class RequestValidationFinding {
  const RequestValidationFinding({
    required this.severity,
    required this.code,
    required this.message,
    this.softViolationCost = 0,
  });

  final ValidationSeverity severity;
  final String code;
  final String message;

  /// Non-zero only for a soft violation. Hard failures never enter the cost.
  final int softViolationCost;

  bool get isError =>
      severity == ValidationSeverity.error ||
      severity == ValidationSeverity.fatal;
}

/// Immutable output of [RequestValidator].
final class RequestValidationResult {
  RequestValidationResult(Iterable<RequestValidationFinding> findings)
    : findings = List<RequestValidationFinding>.unmodifiable(findings);

  final List<RequestValidationFinding> findings;

  bool get hasErrors => findings.any((finding) => finding.isError);

  bool get isValid => !hasErrors;

  int get totalSoftViolationCost =>
      findings.fold(0, (total, finding) => total + finding.softViolationCost);
}

/// Pure conflict detector for goal, availability, and constraint inputs.
///
/// It does not create schedules, relax constraints, or suggest repairs. Those
/// are later planning responsibilities; this boundary only makes conflicts
/// visible and preserves the hard/soft distinction from ADR 0258.
final class RequestValidator {
  const RequestValidator({this.maximumPrimaryGoals = 1});

  /// SDD Ch8 §11.3 recommends one primary goal; more is a warning, not an
  /// invalid request. Kept injectable so policy changes do not alter the
  /// validator algorithm.
  final int maximumPrimaryGoals;

  RequestValidationResult validate({
    required Iterable<PracticeGoal> goals,
    required WeeklyAvailability availability,
    required Map<LocalDate, int> scheduledMinutes,
    Iterable<ConstraintViolation> constraintViolations =
        const <ConstraintViolation>[],
  }) {
    if (maximumPrimaryGoals < 1) {
      throw StateError('maximumPrimaryGoals must be at least one');
    }

    final findings = <RequestValidationFinding>[
      ..._validateGoals(goals),
      ..._validateSchedule(availability, scheduledMinutes),
      ..._validateConstraintViolations(constraintViolations),
    ];
    findings.sort((a, b) {
      final severity = a.severity.index.compareTo(b.severity.index);
      if (severity != 0) return severity;
      final code = a.code.compareTo(b.code);
      if (code != 0) return code;
      return a.message.compareTo(b.message);
    });
    return RequestValidationResult(findings);
  }

  List<RequestValidationFinding> _validateGoals(Iterable<PracticeGoal> goals) {
    final goalList = goals.toList(growable: false);
    final findings = <RequestValidationFinding>[];
    for (final goal in goalList) {
      if (!goal.isExecutable) {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.error,
            code: RequestValidationCode.customGoalNotExecutable,
            message: 'Custom goal ${goal.id.value} has no normalized target.',
          ),
        );
      }
    }
    final primaryCount = goalList
        .where((goal) => goal.priority == GoalPriority.primary)
        .length;
    if (primaryCount > maximumPrimaryGoals) {
      findings.add(
        RequestValidationFinding(
          severity: ValidationSeverity.warning,
          code: RequestValidationCode.tooManyPrimaryGoals,
          message:
              '$primaryCount primary goals exceed the recommended maximum of '
              '$maximumPrimaryGoals.',
        ),
      );
    }
    return findings;
  }

  List<RequestValidationFinding> _validateSchedule(
    WeeklyAvailability availability,
    Map<LocalDate, int> scheduledMinutes,
  ) {
    final findings = <RequestValidationFinding>[];
    for (final entry in scheduledMinutes.entries) {
      final minutes = entry.value;
      if (minutes < 0) {
        throw ArgumentError.value(
          minutes,
          'scheduledMinutes',
          'must not contain negative values',
        );
      }
      if (minutes == 0) continue;
      final day = availability.forDate(entry.key);
      if (day == null || !day.isAvailable) {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.error,
            code: RequestValidationCode.unavailableDayScheduled,
            message: 'No practice is available on ${entry.key}.',
          ),
        );
        continue;
      }
      if (minutes <= day.maximumMinutes) continue;
      final excessMinutes = minutes - day.maximumMinutes;
      if (day.maximumStrength == ConstraintStrength.hard) {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.error,
            code: RequestValidationCode.hardMaximumExceeded,
            message:
                '$minutes minutes exceeds the hard maximum of '
                '${day.maximumMinutes} on ${entry.key}.',
          ),
        );
      } else {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.warning,
            code: RequestValidationCode.softMaximumExceeded,
            message:
                '$minutes minutes exceeds the soft maximum of '
                '${day.maximumMinutes} on ${entry.key}.',
            softViolationCost: excessMinutes * day.softExcessMinuteCost,
          ),
        );
      }
    }
    return findings;
  }

  List<RequestValidationFinding> _validateConstraintViolations(
    Iterable<ConstraintViolation> violations,
  ) {
    final findings = <RequestValidationFinding>[];
    for (final violation in violations) {
      final constraint = violation.constraint;
      if (constraint.isHard) {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.error,
            code: RequestValidationCode.hardConstraintViolated,
            message: violation.reason,
          ),
        );
      } else {
        findings.add(
          RequestValidationFinding(
            severity: ValidationSeverity.warning,
            code: RequestValidationCode.softConstraintViolated,
            message: violation.reason,
            softViolationCost: constraint.softViolationCost,
          ),
        );
      }
    }
    return findings;
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
