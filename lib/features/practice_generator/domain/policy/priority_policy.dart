/// Versioned, deterministic configuration for skill prioritisation.
library;

/// Controls the normalized factors used by [SkillPriorityEngine].
///
/// The policy is immutable and versioned so a generated plan can retain the
/// exact ranking provenance after the values are tuned.
final class PriorityPolicy {
  PriorityPolicy({
    String version = 'priority-policy-v1',
    this.skillGapWeight = 0.45,
    this.assessmentWeight = 0.50,
    this.assessmentValue = 0.50,
    this.primaryGoalWeight = 0.15,
    this.prerequisiteWeight = 0.10,
    this.uncertaintyPenalty = 0.10,
    this.coverageDebtWeight = 0.10,
    this.fatiguePenalty = 0.15,
    this.noveltyPenalty = 0.05,
    this.coverageDebtHorizon = const Duration(days: 30),
  }) : version = _requireText(version, 'version') {
    _requireUnitInterval(skillGapWeight, 'skillGapWeight');
    _requireUnitInterval(assessmentWeight, 'assessmentWeight');
    _requireUnitInterval(assessmentValue, 'assessmentValue');
    _requireUnitInterval(primaryGoalWeight, 'primaryGoalWeight');
    _requireUnitInterval(prerequisiteWeight, 'prerequisiteWeight');
    _requireUnitInterval(uncertaintyPenalty, 'uncertaintyPenalty');
    _requireUnitInterval(coverageDebtWeight, 'coverageDebtWeight');
    _requireUnitInterval(fatiguePenalty, 'fatiguePenalty');
    _requireUnitInterval(noveltyPenalty, 'noveltyPenalty');
    if (coverageDebtHorizon <= Duration.zero) {
      throw ArgumentError.value(
        coverageDebtHorizon,
        'coverageDebtHorizon',
        'must be positive',
      );
    }
  }

  const PriorityPolicy._default()
    : version = 'priority-policy-v1',
      skillGapWeight = 0.45,
      assessmentWeight = 0.50,
      assessmentValue = 0.50,
      primaryGoalWeight = 0.15,
      prerequisiteWeight = 0.10,
      uncertaintyPenalty = 0.10,
      coverageDebtWeight = 0.10,
      fatiguePenalty = 0.15,
      noveltyPenalty = 0.05,
      coverageDebtHorizon = const Duration(days: 30);

  /// Default policy for this initial ranking contract.
  static const PriorityPolicy defaultPolicy = PriorityPolicy._default();

  /// Stable identifier retained by [SkillPriority] as ranking provenance.
  final String version;

  final double skillGapWeight;
  final double assessmentWeight;
  final double assessmentValue;
  final double primaryGoalWeight;
  final double prerequisiteWeight;
  final double uncertaintyPenalty;
  final double coverageDebtWeight;
  final double fatiguePenalty;
  final double noveltyPenalty;
  final Duration coverageDebtHorizon;

  /// Returns the elapsed-practice debt as an inclusive value in `[0, 1]`.
  ///
  /// A caller that has no last-practiced timestamp has a full coverage debt;
  /// future timestamps never become negative debt. The caller supplies [asOf]
  /// so this policy never reads a clock.
  double coverageDebt({required DateTime asOf, DateTime? lastPracticedAt}) {
    if (lastPracticedAt == null) return 1;
    final elapsed = asOf.toUtc().difference(lastPracticedAt.toUtc());
    if (elapsed <= Duration.zero) return 0;
    return (elapsed.inMicroseconds / coverageDebtHorizon.inMicroseconds)
        .clamp(0, 1)
        .toDouble();
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

void _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
}
