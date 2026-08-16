/// Findings produced while validating an [AdaptivePracticePlan] against a
/// `PlanValidationContext` (ADR 0263, SDD Ch8 §17.2).
///
/// [ValidationSeverity] (info/warning/error/fatal) is defined in
/// `plan_enums.dart` and reused here — the plan-validation boundary shares
/// the same severity family as request validation.
library;

import '../id/planner_ids.dart';
import 'plan_enums.dart';

/// Stable, machine-readable codes for a [PlanValidationIssue].
abstract final class PlanValidationCode {
  static const String candidateIdentityMissing =
      'plan.block.candidateIdentity.missing';
  static const String contentRevisionMismatch =
      'plan.block.contentRevision.mismatch';
  static const String assetNotConfirmed = 'plan.block.asset.notConfirmed';
  static const String deviceCapabilityNotConfirmed =
      'plan.block.deviceCapability.notConfirmed';
  static const String offlineNotConfirmed = 'plan.block.offline.notConfirmed';
  static const String tuningNotConfirmed = 'plan.block.tuning.notConfirmed';
  static const String hardAvoidViolated = 'plan.block.hardAvoid.violated';
  static const String hardMaximumExceeded = 'plan.day.hardMaximum.exceeded';
  static const String loadSequencingWarning =
      'plan.day.loadSequencing.warning';
  static const String completedHistoryModified =
      'plan.completedHistory.modified';
}

/// One deterministic, presentable plan-validation finding.
///
/// A finding never carries free-text learner-constraint interpretation
/// (§0.0.1): every code above corresponds to a typed, identity-based
/// executability signal supplied by the caller's context.
final class PlanValidationIssue {
  PlanValidationIssue({
    required this.severity,
    required String code,
    required String message,
    this.dayId,
    this.blockId,
  }) : code = _requireText(code, 'code'),
       message = _requireText(message, 'message');

  final ValidationSeverity severity;
  final String code;
  final String message;
  final DayId? dayId;
  final BlockId? blockId;

  /// `error` and `fatal` gate activation (ADR 0263 §1); `info`/`warning`
  /// never do.
  bool get blocksActivation =>
      severity == ValidationSeverity.error ||
      severity == ValidationSeverity.fatal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanValidationIssue &&
          other.severity == severity &&
          other.code == code &&
          other.message == message &&
          other.dayId == dayId &&
          other.blockId == blockId;

  @override
  int get hashCode => Object.hash(severity, code, message, dayId, blockId);

  @override
  String toString() =>
      'PlanValidationIssue(${severity.code}, $code, $message)';
}

/// Immutable, deterministically ordered output of `PlanValidator.validate`.
final class PlanValidationResult {
  PlanValidationResult(Iterable<PlanValidationIssue> issues)
    : issues = List<PlanValidationIssue>.unmodifiable(
        List<PlanValidationIssue>.of(issues)..sort(_compareIssues),
      );

  final List<PlanValidationIssue> issues;

  bool get hasFatal =>
      issues.any((issue) => issue.severity == ValidationSeverity.fatal);

  bool get hasError =>
      issues.any((issue) => issue.severity == ValidationSeverity.error);

  /// A1: `error`/`fatal` mellett a terv nem aktiválható.
  bool get isActivatable => !issues.any((issue) => issue.blocksActivation);
}

int _compareIssues(PlanValidationIssue a, PlanValidationIssue b) {
  final severity = b.severity.index.compareTo(a.severity.index);
  if (severity != 0) return severity;
  final code = a.code.compareTo(b.code);
  if (code != 0) return code;
  final dayComparison = (a.dayId?.value ?? '').compareTo(b.dayId?.value ?? '');
  if (dayComparison != 0) return dayComparison;
  return (a.blockId?.value ?? '').compareTo(b.blockId?.value ?? '');
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
