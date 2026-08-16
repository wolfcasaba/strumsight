/// Versioned, centralized bounds for evidence-based difficulty adaptation.
///
/// The policy contains every tunable boundary used by [AdaptationDecider]:
/// evidence quantity and confidence, estimate uncertainty, the one-step cap,
/// cooldown, performance thresholds, and supported tempo range. Keeping those
/// limits together makes an adaptation decision reproducible and auditable.
library;

/// Immutable configuration for bounded difficulty adaptation (ADR 0265).
final class ProgressionPolicy {
  ProgressionPolicy({
    String version = 'progression-policy-v1',
    int maximumDifficultyStep = 1,
    int minimumSuccessfulEvidence = 3,
    double minimumEvidenceConfidence = 0.8,
    double maximumEstimateUncertainty = 0.4,
    int repeatedStruggleEvidence = 2,
    Duration advanceCooldown = const Duration(days: 7),
    int tempoStepBpm = 10,
    int minimumTempoBpm = 40,
    int maximumTempoBpm = 180,
    int minimumDifficultyLevel = 0,
    int minimumLoopCount = 1,
    int minimumVariationLevel = 0,
    int minimumStrictnessLevel = 0,
    double successfulPerformanceThreshold = 0.8,
    double strugglePerformanceThreshold = 0.4,
  }) : version = _requireText(version, 'version'),
       maximumDifficultyStep = _requireOneStep(maximumDifficultyStep),
       minimumSuccessfulEvidence = _requirePositiveInt(
         minimumSuccessfulEvidence,
         'minimumSuccessfulEvidence',
       ),
       minimumEvidenceConfidence = _requireUnitInterval(
         minimumEvidenceConfidence,
         'minimumEvidenceConfidence',
       ),
       maximumEstimateUncertainty = _requireUnitInterval(
         maximumEstimateUncertainty,
         'maximumEstimateUncertainty',
       ),
       repeatedStruggleEvidence = _requireRepeatedEvidence(
         repeatedStruggleEvidence,
       ),
       advanceCooldown = _requirePositiveDuration(
         advanceCooldown,
         'advanceCooldown',
       ),
       tempoStepBpm = _requirePositiveInt(tempoStepBpm, 'tempoStepBpm'),
       minimumTempoBpm = _requirePositiveInt(
         minimumTempoBpm,
         'minimumTempoBpm',
       ),
       maximumTempoBpm = _requirePositiveInt(
         maximumTempoBpm,
         'maximumTempoBpm',
       ),
       minimumDifficultyLevel = _requireNonNegativeInt(
         minimumDifficultyLevel,
         'minimumDifficultyLevel',
       ),
       minimumLoopCount = _requirePositiveInt(
         minimumLoopCount,
         'minimumLoopCount',
       ),
       minimumVariationLevel = _requireNonNegativeInt(
         minimumVariationLevel,
         'minimumVariationLevel',
       ),
       minimumStrictnessLevel = _requireNonNegativeInt(
         minimumStrictnessLevel,
         'minimumStrictnessLevel',
       ),
       successfulPerformanceThreshold = _requireUnitInterval(
         successfulPerformanceThreshold,
         'successfulPerformanceThreshold',
       ),
       strugglePerformanceThreshold = _requireUnitInterval(
         strugglePerformanceThreshold,
         'strugglePerformanceThreshold',
       ) {
    if (this.minimumTempoBpm > this.maximumTempoBpm) {
      throw ArgumentError.value(
        minimumTempoBpm,
        'minimumTempoBpm',
        'must not exceed maximumTempoBpm ($maximumTempoBpm)',
      );
    }
    if (this.strugglePerformanceThreshold >=
        this.successfulPerformanceThreshold) {
      throw ArgumentError.value(
        strugglePerformanceThreshold,
        'strugglePerformanceThreshold',
        'must be lower than successfulPerformanceThreshold '
            '($successfulPerformanceThreshold)',
      );
    }
  }

  /// Stable decision provenance.
  final String version;

  /// ADR 0265's non-negotiable maximum. It is exactly one, never a tuning
  /// value that can quietly permit a multi-step jump.
  final int maximumDifficultyStep;

  /// Inclusive number of reliable successful sessions needed to advance.
  final int minimumSuccessfulEvidence;

  /// Minimum confidence required for a performance evidence item to count.
  final double minimumEvidenceConfidence;

  /// The estimate must be no more uncertain than this to advance.
  final double maximumEstimateUncertainty;

  /// At least this many reliable weak sessions are required to regress.
  final int repeatedStruggleEvidence;

  /// The inclusive wait between two advances.
  final Duration advanceCooldown;

  /// The bounded tempo adjustment made by one adaptation step.
  final int tempoStepBpm;

  /// Inclusive lower tempo boundary for a tempo-capable exercise.
  final int minimumTempoBpm;

  /// Inclusive upper tempo boundary for a tempo-capable exercise.
  final int maximumTempoBpm;

  /// Inclusive lower difficulty level after a regression.
  final int minimumDifficultyLevel;

  /// Inclusive lower bound for loop count after a regression.
  final int minimumLoopCount;

  /// Inclusive lower variation level after a regression.
  final int minimumVariationLevel;

  /// Inclusive lower strictness level after a regression.
  final int minimumStrictnessLevel;

  /// Inclusive performance value that counts as a success.
  final double successfulPerformanceThreshold;

  /// Inclusive performance value at or below which a session counts as a
  /// struggle.
  final double strugglePerformanceThreshold;

  /// The v1 policy used unless a caller explicitly supplies another version.
  static final ProgressionPolicy defaultPolicy = ProgressionPolicy();

  /// Whether [lastAdvanceAt] is strictly inside the cooldown interval.
  ///
  /// Exactly one full cooldown duration later is eligible to advance again.
  bool isAdvanceInCooldown(DateTime lastAdvanceAt, DateTime asOf) =>
      asOf.toUtc().difference(lastAdvanceAt.toUtc()) < advanceCooldown;

  /// Clamp a tempo to this policy's inclusive supported range.
  int clampTempoBpm(int value) {
    if (value < minimumTempoBpm) return minimumTempoBpm;
    if (value > maximumTempoBpm) return maximumTempoBpm;
    return value;
  }
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}

int _requireOneStep(int value) {
  if (value != 1) {
    throw ArgumentError.value(
      value,
      'maximumDifficultyStep',
      'must be exactly 1; multi-step adaptation is prohibited',
    );
  }
  return value;
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

int _requireNonNegativeInt(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
  return value;
}

int _requireRepeatedEvidence(int value) {
  if (value < 2) {
    throw ArgumentError.value(
      value,
      'repeatedStruggleEvidence',
      'must be at least 2 so one weak session cannot regress',
    );
  }
  return value;
}

double _requireUnitInterval(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and within [0, 1]');
  }
  return value;
}

Duration _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}
