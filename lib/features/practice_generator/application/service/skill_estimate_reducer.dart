/// Pure, order-independent reduction from evidence to a skill estimate.
library;

import 'dart:math' as math;

import '../../domain/model/skill_estimate.dart';
import '../../domain/model/skill_evidence.dart';
import '../../domain/policy/evidence_weight_policy.dart';

/// Produces a conservative [SkillEstimate] from one skill's evidence.
///
/// Every time input is explicit. The reducer first canonicalises and dedupes
/// evidence, then applies the policy, so a caller's iteration order cannot
/// affect the result.
final class SkillEstimateReducer {
  SkillEstimateReducer({EvidenceWeightPolicy? policy})
    : policy = policy ?? EvidenceWeightPolicy();

  final EvidenceWeightPolicy policy;

  SkillEstimate reduce({
    required String skillId,
    required Iterable<SkillEvidence> evidence,
    required DateTime asOf,
  }) {
    final normalizedSkillId = _requireText(skillId);
    final asOfUtc = asOf.toUtc();
    final canonical = evidence.toList(growable: false)..sort(_compareEvidence);
    if (canonical.any((item) => item.skillId != normalizedSkillId)) {
      throw ArgumentError.value(
        evidence,
        'evidence',
        'every record must belong to $normalizedSkillId',
      );
    }

    final deduplicated = <SkillEvidence>[];
    final seenOutcomeIds = <String>{};
    for (final item in canonical) {
      if (seenOutcomeIds.add(item.sourceOutcomeId.value)) {
        deduplicated.add(item);
      }
    }

    final performance = deduplicated
        .where((item) => item.performance != null)
        .toList(growable: false);
    final summary = EvidenceSummary(
      validPerformanceCount: performance
          .where((item) => item.isValidAt(asOfUtc))
          .length,
      stalePerformanceCount: performance
          .where((item) => !item.isValidAt(asOfUtc))
          .length,
      discomfortOnlyCount: deduplicated
          .where((item) => item.performance == null && item.discomfort != null)
          .length,
      discomfortEvidenceCount: deduplicated
          .where((item) => item.discomfort != null)
          .length,
    );
    if (performance.isEmpty) {
      return SkillEstimate.unknown(
        skillId: normalizedSkillId,
        evidenceSummary: summary,
      );
    }

    final weighted = performance
        .map(
          (item) => _WeightedEvidence(
            evidence: item,
            value: _clamp01(item.performance!.value),
            weight: policy.weightFor(item, asOf: asOfUtc),
          ),
        )
        .toList(growable: false);
    final totalWeight = weighted.fold<double>(
      0,
      (total, item) => total + item.weight,
    );
    final aggregateInfluence = _clamp01(totalWeight);
    final weightedMean = totalWeight == 0
        ? 0.5
        : weighted.fold<double>(
                0,
                (total, item) => total + item.value * item.weight,
              ) /
              totalWeight;
    final level = _clamp01(0.5 + (weightedMean - 0.5) * aggregateInfluence);
    final conflicted = _hasComparableConflict(weighted);
    final uncertainty = _clamp01(
      math.max(0.05, 1 - aggregateInfluence) +
          (conflicted ? policy.conflictUncertaintyPenalty : 0),
    );
    final allStale = summary.validPerformanceCount == 0;

    return SkillEstimate(
      skillId: normalizedSkillId,
      level: level,
      uncertainty: uncertainty,
      state: _stateFor(
        evidenceCount: performance.length,
        level: level,
        uncertainty: uncertainty,
        allStale: allStale,
        conflicted: conflicted,
      ),
      trend: _trendFor(weighted),
      trendDelta: _trendDelta(weighted),
      lastObservedAt: performance
          .map((item) => item.measuredAt)
          .reduce((latest, item) => item.isAfter(latest) ? item : latest),
      evidenceIds: performance
          .map((item) => item.sourceOutcomeId.value)
          .toList(growable: false),
      evidenceSummary: summary,
    );
  }

  SkillEstimateState _stateFor({
    required int evidenceCount,
    required double level,
    required double uncertainty,
    required bool allStale,
    required bool conflicted,
  }) {
    if (allStale) return SkillEstimateState.stale;
    if (conflicted) return SkillEstimateState.conflicted;
    if (evidenceCount == 1) return SkillEstimateState.initial;
    if (uncertainty <= 0.25 && level >= 0.8) {
      return SkillEstimateState.strong;
    }
    if (uncertainty <= 0.35) return SkillEstimateState.stable;
    return SkillEstimateState.emerging;
  }

  SkillTrend _trendFor(List<_WeightedEvidence> evidence) {
    final delta = _trendDelta(evidence);
    if (evidence.length < 2 || delta.abs() < 0.02) return SkillTrend.unknown;
    if (delta > 0) return SkillTrend.improving;
    return SkillTrend.declining;
  }

  double _trendDelta(List<_WeightedEvidence> evidence) {
    final chronological = _timeBuckets(evidence);
    if (chronological.length < 2) return 0;
    final split = chronological.length ~/ 2;
    final early = chronological.take(split);
    final late = chronological.skip(split);
    final delta = _bucketMean(late) - _bucketMean(early);
    return delta
        .clamp(-policy.maximumTrendMagnitude, policy.maximumTrendMagnitude)
        .toDouble();
  }

  bool _hasComparableConflict(List<_WeightedEvidence> evidence) =>
      _timeBuckets(evidence).any(
        (bucket) =>
            bucket.length > 1 &&
            _spread(bucket.map((item) => item.value)) >=
                policy.conflictThreshold,
      );

  List<List<_WeightedEvidence>> _timeBuckets(List<_WeightedEvidence> evidence) {
    final chronological = evidence.toList(growable: false)
      ..sort(
        (first, second) =>
            first.evidence.measuredAt.compareTo(second.evidence.measuredAt),
      );
    final buckets = <List<_WeightedEvidence>>[];
    for (final item in chronological) {
      if (buckets.isEmpty ||
          buckets.last.first.evidence.measuredAt != item.evidence.measuredAt) {
        buckets.add(<_WeightedEvidence>[]);
      }
      buckets.last.add(item);
    }
    return buckets;
  }

  double _bucketMean(Iterable<List<_WeightedEvidence>> buckets) {
    final list = buckets.toList(growable: false);
    if (list.isEmpty) return 0.5;
    return list
            .map(_weightedMean)
            .fold<double>(0, (total, mean) => total + mean) /
        list.length;
  }

  double _weightedMean(Iterable<_WeightedEvidence> evidence) {
    final list = evidence.toList(growable: false);
    final weight = list.fold<double>(0, (total, item) => total + item.weight);
    if (weight == 0) return 0.5;
    return list.fold<double>(
          0,
          (total, item) => total + item.value * item.weight,
        ) /
        weight;
  }
}

final class _WeightedEvidence {
  const _WeightedEvidence({
    required this.evidence,
    required this.value,
    required this.weight,
  });

  final SkillEvidence evidence;
  final double value;
  final double weight;
}

int _compareEvidence(SkillEvidence first, SkillEvidence second) {
  final outcome = first.sourceOutcomeId.value.compareTo(
    second.sourceOutcomeId.value,
  );
  if (outcome != 0) return outcome;
  final source = first.source.code.compareTo(second.source.code);
  if (source != 0) return source;
  final measuredAt = first.measuredAt.compareTo(second.measuredAt);
  if (measuredAt != 0) return measuredAt;
  final version = first.measurementVersion.compareTo(second.measurementVersion);
  if (version != 0) return version;
  final confidence = first.confidence.compareTo(second.confidence);
  if (confidence != 0) return confidence;
  final firstValue = first.performance?.value ?? double.negativeInfinity;
  final secondValue = second.performance?.value ?? double.negativeInfinity;
  return firstValue.compareTo(secondValue);
}

double _spread(Iterable<double> values) {
  final list = values.toList(growable: false);
  final minimum = list.reduce(math.min);
  final maximum = list.reduce(math.max);
  return maximum - minimum;
}

double _clamp01(double value) => value.clamp(0, 1).toDouble();

String _requireText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'skillId', 'must not be empty or blank');
  }
  return trimmed;
}
