/// Deterministic weighting policy for normalised skill evidence.
library;

import 'dart:math' as math;

import '../model/skill_evidence.dart';

/// Calculates the bounded influence of one [SkillEvidence] observation.
///
/// The explicit [singleEvidenceInfluenceCap] is a safety boundary: no source,
/// confidence, recency, or sample count can bypass it.
final class EvidenceWeightPolicy {
  EvidenceWeightPolicy({
    this.singleEvidenceInfluenceCap = 0.25,
    this.recencyHalfLife = const Duration(days: 30),
    this.staleWeightMultiplier = 0.1,
    this.conflictThreshold = 0.4,
    this.conflictUncertaintyPenalty = 0.45,
    this.maximumTrendMagnitude = 0.2,
  }) {
    _requireUnitInterval(
      singleEvidenceInfluenceCap,
      'singleEvidenceInfluenceCap',
      nonZero: true,
    );
    if (recencyHalfLife.inMicroseconds <= 0) {
      throw ArgumentError.value(
        recencyHalfLife,
        'recencyHalfLife',
        'must be positive',
      );
    }
    _requireUnitInterval(staleWeightMultiplier, 'staleWeightMultiplier');
    _requireUnitInterval(conflictThreshold, 'conflictThreshold', nonZero: true);
    _requireUnitInterval(
      conflictUncertaintyPenalty,
      'conflictUncertaintyPenalty',
    );
    _requireUnitInterval(
      maximumTrendMagnitude,
      'maximumTrendMagnitude',
      nonZero: true,
    );
  }

  /// Maximum aggregate confidence a single observation may contribute.
  final double singleEvidenceInfluenceCap;

  /// Age at which an otherwise current observation has half its raw weight.
  final Duration recencyHalfLife;

  /// Multiplier applied after an explicit [SkillEvidence.validUntil] expiry.
  final double staleWeightMultiplier;

  /// Minimum performance spread that marks a set as conflicting.
  final double conflictThreshold;

  /// Additional uncertainty assigned to a conflicting evidence set.
  final double conflictUncertaintyPenalty;

  /// Absolute bound applied to the reported directional trend.
  final double maximumTrendMagnitude;

  /// Stable provenance reliability. Adapters may add sources only by changing
  /// this policy deliberately, rather than receiving an accidental default.
  ///
  /// `vision` (E07-R25, ADR 0319, narrow
  /// `lib/features/vision/domain/evidence/public.dart` contract) is rated
  /// below `analyzeV2` (0.9) but above `progress` (0.7): the value is
  /// derived and confidence-calibrated once a vision session is running, but
  /// it depends on a user-controlled capability (camera, pose tracking)
  /// that may be unavailable on a given session, so the policy reflects that
  /// asymmetry deliberately. The `singleEvidenceInfluenceCap` (default 0.25)
  /// still bounds every individual weight — this reliability multiplies into
  /// that bounded value, so even a maximally reliable vision record cannot
  /// drive an aggressive focus on its own (A3).
  ///
  /// NB: the switch has no `default` arm — exhaustive enumeration is the
  /// compile-time trap the E07-R25 self-heal reverted (see §0.0.1). Adding
  /// any [EvidenceSource] value without a matching arm here is a hard
  /// compile error, not a silent fallthrough.
  double sourceReliability(EvidenceSource source) => switch (source) {
    EvidenceSource.learn => 0.8,
    EvidenceSource.progress => 0.7,
    EvidenceSource.analyzeV2 => 0.9,
    EvidenceSource.selfReport => 0.5,
    EvidenceSource.vision => 0.75,
  };

  /// Calculates and caps one evidence record's influence at caller-supplied
  /// [asOf]; no clock is read internally.
  double weightFor(SkillEvidence evidence, {required DateTime asOf}) {
    final performance = evidence.performance;
    if (performance == null) return 0;

    final asOfUtc = asOf.toUtc();
    final age = asOfUtc.difference(evidence.measuredAt).inMicroseconds;
    final nonNegativeAge = math.max(0, age);
    final halfLife = recencyHalfLife.inMicroseconds;
    final recency = math.pow(0.5, nonNegativeAge / halfLife).toDouble();
    final sampleWeight = 1 - 1 / (performance.sampleCount + 1);
    final staleMultiplier = evidence.isValidAt(asOfUtc)
        ? 1.0
        : staleWeightMultiplier;
    final raw =
        sourceReliability(evidence.source) *
        evidence.confidence *
        sampleWeight *
        recency *
        staleMultiplier;
    return math.min(singleEvidenceInfluenceCap, raw);
  }
}

void _requireUnitInterval(double value, String name, {bool nonZero = false}) {
  if (!value.isFinite || value < 0 || value > 1 || (nonZero && value == 0)) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
}
