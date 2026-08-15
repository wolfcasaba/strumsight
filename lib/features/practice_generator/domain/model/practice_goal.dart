import '../id/planner_ids.dart';
import 'weekly_availability.dart';

/// A stable category for the learner's requested outcome (SDD Ch8 §11.2).
enum PracticeGoalType {
  foundation('foundation'),
  rhythm('rhythm'),
  chordChanges('chordChanges'),
  strummingPattern('strummingPattern'),
  speed('speed'),
  songPerformance('songPerformance'),
  repertoireMaintenance('repertoireMaintenance'),
  musicTheory('musicTheory'),
  technique('technique'),
  confidence('confidence'),
  custom('custom');

  const PracticeGoalType(this.code);

  final String code;

  static PracticeGoalType fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'PracticeGoalType',
  );
}

/// The learner-facing focus level of a goal (SDD Ch8 §11.3).
enum GoalPriority {
  primary('primary'),
  secondary('secondary'),
  maintenance('maintenance'),
  optional('optional');

  const GoalPriority(this.code);

  final String code;

  static GoalPriority fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'GoalPriority',
  );
}

/// Persisted lifecycle of a practice goal (SDD Ch8 §11.5).
enum PracticeGoalStatus {
  proposed('proposed'),
  active('active'),
  paused('paused'),
  achieved('achieved'),
  abandoned('abandoned'),
  superseded('superseded');

  const PracticeGoalStatus(this.code);

  final String code;

  static PracticeGoalStatus fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'PracticeGoalStatus',
  );
}

/// The desired direction for a measurable target.
enum MetricDirection {
  increase('increase'),
  decrease('decrease'),
  atLeast('atLeast'),
  atMost('atMost');

  const MetricDirection(this.code);

  final String code;

  static MetricDirection fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'MetricDirection',
  );
}

/// Evidence requirements for a metric-based goal.
final class MetricTarget {
  MetricTarget({
    required String metricCode,
    required this.direction,
    required this.threshold,
    required String measurementCapability,
    required this.minimumConfidence,
    required this.minimumSampleCount,
    this.targetDate,
  }) : metricCode = _requireText(metricCode, 'metricCode'),
       measurementCapability = _requireText(
         measurementCapability,
         'measurementCapability',
       ) {
    if (!threshold.isFinite) {
      throw ArgumentError.value(threshold, 'threshold', 'must be finite');
    }
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      throw ArgumentError.value(
        minimumConfidence,
        'minimumConfidence',
        'must be a finite value from 0 to 1',
      );
    }
    if (minimumSampleCount <= 0) {
      throw ArgumentError.value(
        minimumSampleCount,
        'minimumSampleCount',
        'must be positive',
      );
    }
  }

  final String metricCode;
  final MetricDirection direction;
  final double threshold;
  final String measurementCapability;
  final double minimumConfidence;
  final int minimumSampleCount;
  final LocalDate? targetDate;

  @override
  bool operator ==(Object other) =>
      other is MetricTarget &&
      metricCode == other.metricCode &&
      direction == other.direction &&
      threshold == other.threshold &&
      measurementCapability == other.measurementCapability &&
      minimumConfidence == other.minimumConfidence &&
      minimumSampleCount == other.minimumSampleCount &&
      targetDate == other.targetDate;

  @override
  int get hashCode => Object.hash(
    metricCode,
    direction,
    threshold,
    measurementCapability,
    minimumConfidence,
    minimumSampleCount,
    targetDate,
  );
}

/// An immutable learner goal. Creation time is supplied by the caller, never
/// read from a clock, so domain behaviour remains deterministic.
final class PracticeGoal {
  PracticeGoal({
    required this.id,
    required this.type,
    required this.priority,
    required this.status,
    required DateTime createdAt,
    this.targetDate,
    Iterable<String> skillIds = const <String>[],
    String? songReference,
    this.metricTarget,
    String? userNote,
    String? normalizedTargetId,
  }) : createdAt = createdAt.toUtc(),
       skillIds = List<String>.unmodifiable(
         skillIds.map((value) => _requireText(value, 'skillIds')),
       ),
       songReference = _normalizeOptionalText(songReference),
       userNote = _normalizeOptionalText(userNote),
       normalizedTargetId = _normalizeOptionalText(normalizedTargetId) {
    if (this.skillIds.toSet().length != this.skillIds.length) {
      throw ArgumentError.value(
        skillIds,
        'skillIds',
        'must not contain duplicates',
      );
    }
  }

  final GoalId id;
  final PracticeGoalType type;
  final GoalPriority priority;
  final PracticeGoalStatus status;
  final DateTime createdAt;
  final LocalDate? targetDate;
  final List<String> skillIds;
  final String? songReference;
  final MetricTarget? metricTarget;
  final String? userNote;

  /// A stable target produced by a later normalizer for a custom goal.
  final String? normalizedTargetId;

  bool get isExecutable =>
      type != PracticeGoalType.custom || normalizedTargetId != null;

  bool canTransitionTo(PracticeGoalStatus next) => switch (status) {
    PracticeGoalStatus.proposed =>
      next == PracticeGoalStatus.active || next == PracticeGoalStatus.abandoned,
    PracticeGoalStatus.active =>
      next == PracticeGoalStatus.paused ||
          next == PracticeGoalStatus.achieved ||
          next == PracticeGoalStatus.abandoned ||
          next == PracticeGoalStatus.superseded,
    PracticeGoalStatus.paused =>
      next == PracticeGoalStatus.active ||
          next == PracticeGoalStatus.abandoned ||
          next == PracticeGoalStatus.superseded,
    PracticeGoalStatus.achieved ||
    PracticeGoalStatus.abandoned ||
    PracticeGoalStatus.superseded => false,
  };

  PracticeGoal transitionTo(PracticeGoalStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Cannot transition goal $id from ${status.code} to ${next.code}',
      );
    }
    return PracticeGoal(
      id: id,
      type: type,
      priority: priority,
      status: next,
      createdAt: createdAt,
      targetDate: targetDate,
      skillIds: skillIds,
      songReference: songReference,
      metricTarget: metricTarget,
      userNote: userNote,
      normalizedTargetId: normalizedTargetId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeGoal &&
      id == other.id &&
      type == other.type &&
      priority == other.priority &&
      status == other.status &&
      createdAt == other.createdAt &&
      targetDate == other.targetDate &&
      _sameList(skillIds, other.skillIds) &&
      songReference == other.songReference &&
      metricTarget == other.metricTarget &&
      userNote == other.userNote &&
      normalizedTargetId == other.normalizedTargetId;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    priority,
    status,
    createdAt,
    targetDate,
    Object.hashAll(skillIds),
    songReference,
    metricTarget,
    userNote,
    normalizedTargetId,
  );
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

String? _normalizeOptionalText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

T _decodeEnumCode<T extends Enum>({
  required String? code,
  required List<T> values,
  required String Function(T value) codeOf,
  required String typeName,
}) {
  if (code == null || code.trim().isEmpty) {
    throw ArgumentError.value(code, 'code', '$typeName code must not be empty');
  }
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  throw ArgumentError.value(code, 'code', 'Unknown $typeName code: $code');
}
