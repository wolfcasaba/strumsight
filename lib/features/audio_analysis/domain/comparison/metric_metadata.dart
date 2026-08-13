import '../analysis_metric_catalog.dart';

/// How a metric's numeric movement should be framed (ADR 0246 §2).
///
/// [descriptive] metrics (e.g. signed bias, BPM-like facts) carry no
/// preferred direction: they can be `unchanged` or `inconclusive`, but
/// NEVER `improved`/`regressed` — framing an arbitrary descriptive change as
/// "better" would be a fabricated diagnosis.
enum MetricDirection { lowerIsBetter, higherIsBetter, targetRange, descriptive }

/// Comparison metadata for one published metric ID (ADR 0246 §2).
///
/// [minimumMeaningfulDelta] is expressed in the same numeric unit the
/// comparison engine reads the metric's value in (see
/// `numericMetricValue` in `compatibility_evaluator.dart`): milliseconds for
/// `DurationMetricValue`, the raw 0..1 ratio for `PercentageMetricValue`, and
/// the raw scalar otherwise. A delta strictly below this threshold is noise
/// and reports as `unchanged`, never a diagnosis.
final class MetricMetadata {
  MetricMetadata({
    required this.metricId,
    required this.direction,
    required this.minimumMeaningfulDelta,
    this.targetRangeMin,
    this.targetRangeMax,
  }) {
    if (minimumMeaningfulDelta < 0) {
      throw ArgumentError.value(
        minimumMeaningfulDelta,
        'minimumMeaningfulDelta',
        'must not be negative',
      );
    }
    if (direction == MetricDirection.targetRange) {
      if (targetRangeMin == null || targetRangeMax == null) {
        throw ArgumentError(
          'targetRange metrics require targetRangeMin and targetRangeMax.',
        );
      }
      if (targetRangeMin! > targetRangeMax!) {
        throw ArgumentError('targetRangeMin must not exceed targetRangeMax.');
      }
    }
  }

  final String metricId;
  final MetricDirection direction;
  final double minimumMeaningfulDelta;

  /// Inclusive lower bound of the ideal range. Only set for [MetricDirection.targetRange].
  final double? targetRangeMin;

  /// Inclusive upper bound of the ideal range. Only set for [MetricDirection.targetRange].
  final double? targetRangeMax;
}

/// The comparison metadata table. Every ID in [AnalysisMetricId.known] must
/// have an entry here — [isComplete] is the machine gate a completeness
/// test asserts (ADR 0246 §2, brief §6 "Metaadat-teljesség").
abstract final class MetricMetadataCatalog {
  static MetricMetadata? forId(String metricId) => _table[metricId];

  static bool get isComplete =>
      AnalysisMetricId.known.every(_table.containsKey);

  /// IDs published by the catalog that have no comparison metadata yet —
  /// empty when [isComplete] is true. Exposed so a failing completeness
  /// test can report exactly which IDs are missing, not just a boolean.
  static Set<String> get missingIds => <String>{
    for (final id in AnalysisMetricId.known)
      if (!_table.containsKey(id)) id,
  };

  static final Map<String, MetricMetadata> _table = <String, MetricMetadata>{
    AnalysisMetricId.timingMeanAbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingMeanAbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 5,
    ),
    AnalysisMetricId.rhythmRushDragBias: MetricMetadata(
      metricId: AnalysisMetricId.rhythmRushDragBias,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.dynamicsStrumConsistency: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsStrumConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.harmonyChordCoverage: MetricMetadata(
      metricId: AnalysisMetricId.harmonyChordCoverage,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),

    // Target-alignment timing (ADR 0232). minimumMeaningfulDelta matches the
    // brief's §6 illustrative 5 ms threshold on the mean-absolute-error ID.
    AnalysisMetricId.timingTargetMeanAbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 5,
    ),
    AnalysisMetricId.timingTargetMedianAbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetMedianAbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 4,
    ),
    AnalysisMetricId.timingTargetP90AbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetP90AbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 8,
    ),
    AnalysisMetricId.timingTargetSignedBias: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetSignedBias,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 3,
    ),
    AnalysisMetricId.timingTargetOnTimeRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetOnTimeRatio,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingTargetEarlyRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetEarlyRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingTargetLateRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetLateRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingTargetMissedRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetMissedRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.timingTargetExtraRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetExtraRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.timingTargetLongestStableStreak: MetricMetadata(
      metricId: AnalysisMetricId.timingTargetLongestStableStreak,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 2,
    ),

    // Free-play timing — estimated beat-grid based, slightly wider noise
    // bands than the reference-bound target suite above (ADR 0232 §5.5).
    AnalysisMetricId.timingFreeplayMeanAbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayMeanAbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 6,
    ),
    AnalysisMetricId.timingFreeplayMedianAbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayMedianAbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 5,
    ),
    AnalysisMetricId.timingFreeplayP90AbsoluteError: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayP90AbsoluteError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 10,
    ),
    AnalysisMetricId.timingFreeplaySignedBias: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplaySignedBias,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 3,
    ),
    AnalysisMetricId.timingFreeplayOnTimeRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayOnTimeRatio,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingFreeplayEarlyRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayEarlyRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingFreeplayLateRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayLateRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.timingFreeplayMissedRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayMissedRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.timingFreeplayExtraRatio: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayExtraRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.timingFreeplayLongestStableStreak: MetricMetadata(
      metricId: AnalysisMetricId.timingFreeplayLongestStableStreak,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 2,
    ),

    // Rhythm consistency (ADR 0233) — target-grid bound.
    AnalysisMetricId.rhythmTargetIoiConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetIoiConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmTargetSubdivisionConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetSubdivisionConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmTargetBeatPhaseConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetBeatPhaseConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmTargetLongestStableIoiStreak: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetLongestStableIoiStreak,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 2,
    ),
    AnalysisMetricId.rhythmTargetAccentPositionConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetAccentPositionConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmTargetSwingRatio: MetricMetadata(
      metricId: AnalysisMetricId.rhythmTargetSwingRatio,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.03,
    ),

    // Rhythm consistency — inferred grid (no measured swing ratio).
    AnalysisMetricId.rhythmInferredIoiConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmInferredIoiConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmInferredSubdivisionConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmInferredSubdivisionConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmInferredBeatPhaseConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmInferredBeatPhaseConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.rhythmInferredLongestStableIoiStreak: MetricMetadata(
      metricId: AnalysisMetricId.rhythmInferredLongestStableIoiStreak,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 2,
    ),
    AnalysisMetricId.rhythmInferredAccentPositionConsistency: MetricMetadata(
      metricId: AnalysisMetricId.rhythmInferredAccentPositionConsistency,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),

    // Dynamics and stroke balance (ADR 0234). Per the catalog's own source
    // comment, only accentAccuracy is evaluative — the rest are descriptive
    // and must never be framed as "lower is better".
    AnalysisMetricId.dynamicsStrokeStrengthCv: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsStrokeStrengthCv,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.dynamicsDownUpMedianRatio: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsDownUpMedianRatio,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.dynamicsDrift: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsDrift,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.dynamicsOutlierRatio: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsOutlierRatio,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.dynamicsAccentAccuracy: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsAccentAccuracy,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.dynamicsQuietRegionRatio: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsQuietRegionRatio,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),
    AnalysisMetricId.dynamicsClippedEventRatio: MetricMetadata(
      metricId: AnalysisMetricId.dynamicsClippedEventRatio,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 0.02,
    ),

    // Target-bound monophonic pitch (ADR 0235). The signed cents error is
    // descriptive per the catalog's own source comment; p90 (absolute) and
    // stability are evaluative.
    AnalysisMetricId.pitchNoteHitRatio: MetricMetadata(
      metricId: AnalysisMetricId.pitchNoteHitRatio,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 0.03,
    ),
    AnalysisMetricId.pitchMedianCentsError: MetricMetadata(
      metricId: AnalysisMetricId.pitchMedianCentsError,
      direction: MetricDirection.descriptive,
      minimumMeaningfulDelta: 3,
    ),
    AnalysisMetricId.pitchP90CentsError: MetricMetadata(
      metricId: AnalysisMetricId.pitchP90CentsError,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 5,
    ),
    AnalysisMetricId.pitchStabilityCents: MetricMetadata(
      metricId: AnalysisMetricId.pitchStabilityCents,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 3,
    ),
    AnalysisMetricId.pitchNoteTransitionTiming: MetricMetadata(
      metricId: AnalysisMetricId.pitchNoteTransitionTiming,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 5,
    ),
    AnalysisMetricId.pitchSustainedNoteDuration: MetricMetadata(
      metricId: AnalysisMetricId.pitchSustainedNoteDuration,
      direction: MetricDirection.higherIsBetter,
      minimumMeaningfulDelta: 50,
    ),
    AnalysisMetricId.pitchUnwantedDropoutRatio: MetricMetadata(
      metricId: AnalysisMetricId.pitchUnwantedDropoutRatio,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),

    // Experimental Lab-only technique proxies (ADR 0236) — never published
    // to AnalysisDocument.metrics in this round, but the completeness gate
    // still requires metadata for every catalog ID.
    AnalysisMetricId.techniqueChordChangeGap: MetricMetadata(
      metricId: AnalysisMetricId.techniqueChordChangeGap,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 20,
    ),
    AnalysisMetricId.techniqueConfidenceCollapseDuration: MetricMetadata(
      metricId: AnalysisMetricId.techniqueConfidenceCollapseDuration,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 50,
    ),
    AnalysisMetricId.techniqueUnexpectedExtraOnsets: MetricMetadata(
      metricId: AnalysisMetricId.techniqueUnexpectedExtraOnsets,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 1,
    ),
    AnalysisMetricId.techniqueSustainedNoteDropout: MetricMetadata(
      metricId: AnalysisMetricId.techniqueSustainedNoteDropout,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 1,
    ),
    AnalysisMetricId.techniqueAttackInstability: MetricMetadata(
      metricId: AnalysisMetricId.techniqueAttackInstability,
      direction: MetricDirection.lowerIsBetter,
      minimumMeaningfulDelta: 0.02,
    ),
  };
}
