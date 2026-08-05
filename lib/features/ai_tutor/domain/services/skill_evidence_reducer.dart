import '../models/skill_estimate.dart';
import '../models/skill_evidence.dart';
import '../models/skill_node.dart';

/// Stable exception emitted when a reduction input is ambiguous or invalid.
class SkillEvidenceReducerException implements Exception {
  SkillEvidenceReducerException._(this.code);

  /// One of [SkillEvidenceReducerCode]'s constants.
  final String code;

  @override
  String toString() => 'SkillEvidenceReducerException($code)';
}

/// Stable machine-readable codes emitted by the skill evidence reducer.
abstract final class SkillEvidenceReducerCode {
  static const String unexpectedSkill = 'skillEvidenceReducer.skill.unexpected';
  static const String duplicateEvidenceIdConflict =
      'skillEvidenceReducer.evidenceId.conflict';
}

/// Pure, integer-arithmetic reducer for one skill's evidence collection.
final class SkillEvidenceReducer {
  const SkillEvidenceReducer();

  /// At least this many groups are required before exposing a trend estimate.
  static const int minimumComparableGroupsForTrend = 2;

  /// Confidence added by each comparable group, capped at the normalized scale.
  static const int confidencePerComparableGroup = 2000;

  /// Stable sorting rule used when two groups have the same UTC timestamp.
  static const String stableGroupTieBreak =
      'observedAtUtcAscending, comparableGroupIdLexicalAscending';

  /// Reduces evidence without clocks, randomness, floating point, or I/O.
  SkillEstimate reduce({
    required SkillId skillId,
    required Iterable<SkillEvidence> evidence,
  }) {
    final distinctEvidence = _deduplicate(skillId, evidence);
    if (distinctEvidence.isEmpty) {
      return SkillEstimate(
        skillId: skillId,
        status: SkillEstimateStatus.insufficient,
        scoreBasisPoints: null,
        confidenceBasisPoints: 0,
        evidenceCount: 0,
        comparableGroupCount: 0,
        contributingEvidenceIds: const <String>[],
        updatedAt: null,
      );
    }

    final selected = _selectMostComparablePartition(distinctEvidence);
    final evidenceIds = <String>[
      for (final group in selected.groups)
        for (final item in group.evidence) item.id,
    ];
    final updatedAt = _latestObservedAt(selected.groups);
    final groupCount = selected.groups.length;
    final confidenceBasisPoints = _confidenceFor(groupCount);

    if (groupCount < minimumComparableGroupsForTrend) {
      return SkillEstimate(
        skillId: skillId,
        status: SkillEstimateStatus.insufficient,
        scoreBasisPoints: null,
        confidenceBasisPoints: confidenceBasisPoints,
        evidenceCount: evidenceIds.length,
        comparableGroupCount: groupCount,
        comparisonKey: selected.comparisonKey,
        contributingEvidenceIds: evidenceIds,
        updatedAt: updatedAt,
      );
    }

    final scoreBasisPoints =
        selected.groups.fold<int>(
          0,
          (total, group) => total + group.scoreBasisPoints,
        ) ~/
        groupCount;
    final firstScore = selected.groups.first.scoreBasisPoints;
    final lastScore = selected.groups.last.scoreBasisPoints;
    final trend = lastScore > firstScore
        ? SkillTrend.improving
        : lastScore < firstScore
        ? SkillTrend.declining
        : SkillTrend.stable;

    return SkillEstimate(
      skillId: skillId,
      status: SkillEstimateStatus.trend,
      scoreBasisPoints: scoreBasisPoints,
      confidenceBasisPoints: confidenceBasisPoints,
      evidenceCount: evidenceIds.length,
      comparableGroupCount: groupCount,
      comparisonKey: selected.comparisonKey,
      trend: trend,
      contributingEvidenceIds: evidenceIds,
      updatedAt: updatedAt,
    );
  }

  List<SkillEvidence> _deduplicate(
    SkillId skillId,
    Iterable<SkillEvidence> evidence,
  ) {
    final evidenceById = <String, SkillEvidence>{};
    for (final item in evidence) {
      if (item.skillId != skillId) {
        throw SkillEvidenceReducerException._(
          SkillEvidenceReducerCode.unexpectedSkill,
        );
      }
      final existing = evidenceById[item.id];
      if (existing == null) {
        evidenceById[item.id] = item;
      } else if (existing != item) {
        throw SkillEvidenceReducerException._(
          SkillEvidenceReducerCode.duplicateEvidenceIdConflict,
        );
      }
    }
    return evidenceById.values.toList()..sort(_compareEvidence);
  }

  _ComparablePartition _selectMostComparablePartition(
    List<SkillEvidence> evidence,
  ) {
    final groupMapsByComparisonKey =
        <String, Map<String, List<SkillEvidence>>>{};
    for (final item in evidence) {
      final groups = groupMapsByComparisonKey.putIfAbsent(
        item.comparisonKey,
        () => <String, List<SkillEvidence>>{},
      );
      groups
          .putIfAbsent(item.comparableGroupId, () => <SkillEvidence>[])
          .add(item);
    }

    final partitions = <_ComparablePartition>[];
    for (final entry in groupMapsByComparisonKey.entries) {
      final groups = <_ComparableGroup>[];
      for (final groupEntry in entry.value.entries) {
        final groupedEvidence = List<SkillEvidence>.of(groupEntry.value)
          ..sort(_compareEvidence);
        groups.add(
          _ComparableGroup(
            id: groupEntry.key,
            evidence: groupedEvidence,
            observedAt: groupedEvidence.first.observedAt,
            scoreBasisPoints: _weightedScore(groupedEvidence),
          ),
        );
      }
      groups.sort(_compareGroups);
      partitions.add(
        _ComparablePartition(comparisonKey: entry.key, groups: groups),
      );
    }
    partitions.sort(_comparePartitions);
    return partitions.first;
  }

  int _weightedScore(List<SkillEvidence> evidence) {
    var weightedScoreTotal = 0;
    var weightTotal = 0;
    for (final item in evidence) {
      final weight = item.source.weightBasisPoints;
      weightedScoreTotal += item.scoreBasisPoints * weight;
      weightTotal += weight;
    }
    return weightedScoreTotal ~/ weightTotal;
  }

  int _confidenceFor(int comparableGroupCount) {
    final uncapped = comparableGroupCount * confidencePerComparableGroup;
    return uncapped > skillBasisPointScale ? skillBasisPointScale : uncapped;
  }

  DateTime _latestObservedAt(List<_ComparableGroup> groups) {
    var latest = groups.first.observedAt;
    for (final group in groups.skip(1)) {
      if (group.observedAt.isAfter(latest)) latest = group.observedAt;
    }
    return latest;
  }
}

int _compareEvidence(SkillEvidence left, SkillEvidence right) {
  final timeOrder = left.observedAt.compareTo(right.observedAt);
  return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
}

int _compareGroups(_ComparableGroup left, _ComparableGroup right) {
  final timeOrder = left.observedAt.compareTo(right.observedAt);
  return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
}

int _comparePartitions(_ComparablePartition left, _ComparablePartition right) {
  final groupCountOrder = right.groups.length.compareTo(left.groups.length);
  return groupCountOrder != 0
      ? groupCountOrder
      : left.comparisonKey.compareTo(right.comparisonKey);
}

final class _ComparablePartition {
  _ComparablePartition({
    required this.comparisonKey,
    required List<_ComparableGroup> groups,
  }) : groups = List<_ComparableGroup>.unmodifiable(groups);

  final String comparisonKey;
  final List<_ComparableGroup> groups;
}

final class _ComparableGroup {
  _ComparableGroup({
    required this.id,
    required List<SkillEvidence> evidence,
    required this.observedAt,
    required this.scoreBasisPoints,
  }) : evidence = List<SkillEvidence>.unmodifiable(evidence);

  final String id;
  final List<SkillEvidence> evidence;
  final DateTime observedAt;
  final int scoreBasisPoints;
}
