import 'skill_node.dart';

/// Whether a skill has enough comparable evidence for a trend estimate.
enum SkillEstimateStatus { insufficient, trend }

/// Direction derived from the chronologically first and last comparable groups.
enum SkillTrend { improving, stable, declining }

/// Immutable output of [SkillEvidenceReducer].
final class SkillEstimate {
  SkillEstimate({
    required this.skillId,
    required this.status,
    required this.scoreBasisPoints,
    required this.confidenceBasisPoints,
    required this.evidenceCount,
    required this.comparableGroupCount,
    required List<String> contributingEvidenceIds,
    required DateTime? updatedAt,
    this.comparisonKey,
    this.trend,
  }) : contributingEvidenceIds = List<String>.unmodifiable(
         contributingEvidenceIds,
       ),
       updatedAt = updatedAt?.toUtc() {
    _validate();
  }

  final SkillId skillId;
  final SkillEstimateStatus status;

  /// Null until at least two comparable groups support a trend estimate.
  final int? scoreBasisPoints;

  /// Separate evidence confidence in the normalized integer scale.
  final int confidenceBasisPoints;
  final int evidenceCount;
  final int comparableGroupCount;
  final String? comparisonKey;
  final SkillTrend? trend;
  final List<String> contributingEvidenceIds;
  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillEstimate &&
          other.skillId == skillId &&
          other.status == status &&
          other.scoreBasisPoints == scoreBasisPoints &&
          other.confidenceBasisPoints == confidenceBasisPoints &&
          other.evidenceCount == evidenceCount &&
          other.comparableGroupCount == comparableGroupCount &&
          other.comparisonKey == comparisonKey &&
          other.trend == trend &&
          _stringListsEqual(
            other.contributingEvidenceIds,
            contributingEvidenceIds,
          ) &&
          other.updatedAt?.microsecondsSinceEpoch ==
              updatedAt?.microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    skillId,
    status,
    scoreBasisPoints,
    confidenceBasisPoints,
    evidenceCount,
    comparableGroupCount,
    comparisonKey,
    trend,
    Object.hashAll(contributingEvidenceIds),
    updatedAt?.microsecondsSinceEpoch,
  );

  void _validate() {
    final score = scoreBasisPoints;
    if (confidenceBasisPoints < 0 ||
        confidenceBasisPoints > skillBasisPointScale ||
        evidenceCount < 0 ||
        comparableGroupCount < 0) {
      throw ArgumentError.value(
        this,
        'SkillEstimate',
        'Invalid estimate range',
      );
    }
    if (evidenceCount != contributingEvidenceIds.length ||
        comparableGroupCount > evidenceCount) {
      throw ArgumentError.value(
        this,
        'SkillEstimate',
        'Invalid evidence count',
      );
    }
    if (score != null && (score < 0 || score > skillBasisPointScale)) {
      throw ArgumentError.value(
        this,
        'scoreBasisPoints',
        'Invalid score range',
      );
    }
    switch (status) {
      case SkillEstimateStatus.insufficient:
        if (comparableGroupCount > 1 || score != null || trend != null) {
          throw ArgumentError.value(
            this,
            'status',
            'Invalid insufficient estimate',
          );
        }
      case SkillEstimateStatus.trend:
        if (comparableGroupCount < 2 || score == null || trend == null) {
          throw ArgumentError.value(this, 'status', 'Invalid trend estimate');
        }
    }
  }
}

bool _stringListsEqual(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
