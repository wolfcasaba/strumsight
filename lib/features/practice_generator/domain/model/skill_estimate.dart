/// A deterministic, confidence-aware snapshot of one practice skill.
library;

/// The amount and quality of evidence supporting an estimate.
enum SkillEstimateState {
  unknown,
  initial,
  emerging,
  stable,
  strong,
  stale,
  conflicted,
}

/// The bounded direction inferred from time-ordered performance evidence.
enum SkillTrend { unknown, declining, flat, improving }

/// Human-readable, privacy-safe evidence accounting for one reduction.
///
/// Counts intentionally retain stale and discomfort-only observations without
/// allowing either to masquerade as current performance evidence.
final class EvidenceSummary {
  const EvidenceSummary({
    required this.validPerformanceCount,
    required this.stalePerformanceCount,
    required this.discomfortOnlyCount,
    this.discomfortEvidenceCount = 0,
  });

  final int validPerformanceCount;
  final int stalePerformanceCount;
  final int discomfortOnlyCount;
  final int discomfortEvidenceCount;

  String get description =>
      '$validPerformanceCount current performance, '
      '$stalePerformanceCount stale performance, '
      '$discomfortOnlyCount discomfort-only evidence';

  @override
  bool operator ==(Object other) =>
      other is EvidenceSummary &&
      validPerformanceCount == other.validPerformanceCount &&
      stalePerformanceCount == other.stalePerformanceCount &&
      discomfortOnlyCount == other.discomfortOnlyCount &&
      discomfortEvidenceCount == other.discomfortEvidenceCount;

  @override
  int get hashCode => Object.hash(
    validPerformanceCount,
    stalePerformanceCount,
    discomfortOnlyCount,
    discomfortEvidenceCount,
  );
}

/// Immutable skill estimate. [level] is absent for [SkillEstimateState.unknown]
/// so missing evidence can never be mistaken for low performance.
final class SkillEstimate {
  SkillEstimate({
    required String skillId,
    required double level,
    required double uncertainty,
    required this.state,
    required this.trend,
    required double trendDelta,
    required DateTime lastObservedAt,
    required Iterable<String> evidenceIds,
    required this.evidenceSummary,
  }) : skillId = _requireText(skillId),
       level = _unitInterval(level, 'level'),
       uncertainty = _unitInterval(uncertainty, 'uncertainty'),
       trendDelta = _boundedTrend(trendDelta),
       lastObservedAt = lastObservedAt.toUtc(),
       evidenceIds = List<String>.unmodifiable(evidenceIds) {
    if (state == SkillEstimateState.unknown) {
      throw ArgumentError.value(
        state,
        'state',
        'unknown estimates use unknown()',
      );
    }
  }

  SkillEstimate._unknown({
    required String skillId,
    required this.evidenceSummary,
  }) : skillId = _requireText(skillId),
       level = null,
       uncertainty = 1,
       state = SkillEstimateState.unknown,
       trend = SkillTrend.unknown,
       trendDelta = 0,
       lastObservedAt = null,
       evidenceIds = const <String>[];

  factory SkillEstimate.unknown({
    required String skillId,
    EvidenceSummary evidenceSummary = const EvidenceSummary(
      validPerformanceCount: 0,
      stalePerformanceCount: 0,
      discomfortOnlyCount: 0,
    ),
  }) => SkillEstimate._unknown(
    skillId: skillId,
    evidenceSummary: evidenceSummary,
  );

  final String skillId;
  final double? level;
  final double uncertainty;
  final SkillEstimateState state;
  final SkillTrend trend;
  final double trendDelta;
  final DateTime? lastObservedAt;
  final List<String> evidenceIds;
  final EvidenceSummary evidenceSummary;

  bool get isUnknown => state == SkillEstimateState.unknown;

  @override
  bool operator ==(Object other) =>
      other is SkillEstimate &&
      skillId == other.skillId &&
      level == other.level &&
      uncertainty == other.uncertainty &&
      state == other.state &&
      trend == other.trend &&
      trendDelta == other.trendDelta &&
      lastObservedAt == other.lastObservedAt &&
      _sameList(evidenceIds, other.evidenceIds) &&
      evidenceSummary == other.evidenceSummary;

  @override
  int get hashCode => Object.hash(
    skillId,
    level,
    uncertainty,
    state,
    trend,
    trendDelta,
    lastObservedAt,
    Object.hashAll(evidenceIds),
    evidenceSummary,
  );
}

String _requireText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'skillId', 'must not be empty or blank');
  }
  return trimmed;
}

double _unitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}

double _boundedTrend(double value) {
  if (!value.isFinite || value < -1 || value > 1) {
    throw ArgumentError.value(
      value,
      'trendDelta',
      'must be finite and within [-1, 1]',
    );
  }
  return value;
}

bool _sameList<T>(List<T> first, List<T> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
