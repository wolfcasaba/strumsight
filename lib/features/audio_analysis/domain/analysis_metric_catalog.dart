/// Stable identifiers for every metric this V2 contract can publish.
///
/// IDs include their own metric version and are intentionally the only values
/// accepted by [AnalysisMetricResult].
abstract final class AnalysisMetricId {
  static const String timingMeanAbsoluteError = 'timing.mean_absolute_error.v1';
  static const String rhythmRushDragBias = 'rhythm.rush_drag_bias.v1';
  static const String dynamicsStrumConsistency =
      'dynamics.strum_consistency.v1';
  static const String harmonyChordCoverage = 'harmony.chord_coverage.v1';

  // Target-alignment timing (E06-R14, ADR 0232). Reference-bound: only ever
  // published from an AlignmentResult. Disjoint from the timingFreeplay*
  // namespace below — never mix the two in a comparison (ADR 0232 §1).
  static const String timingTargetMeanAbsoluteError =
      'timing.target_mean_absolute_error.v1';
  static const String timingTargetMedianAbsoluteError =
      'timing.target_median_absolute_error.v1';
  static const String timingTargetP90AbsoluteError =
      'timing.target_p90_absolute_error.v1';
  static const String timingTargetSignedBias = 'timing.target_signed_bias.v1';
  static const String timingTargetOnTimeRatio =
      'timing.target_on_time_ratio.v1';
  static const String timingTargetEarlyRatio = 'timing.target_early_ratio.v1';
  static const String timingTargetLateRatio = 'timing.target_late_ratio.v1';
  static const String timingTargetMissedRatio = 'timing.target_missed_ratio.v1';
  static const String timingTargetExtraRatio = 'timing.target_extra_ratio.v1';
  static const String timingTargetLongestStableStreak =
      'timing.target_longest_stable_streak.v1';

  // Free-play timing (E06-R14, ADR 0232 §1, §5.5): estimated beat-grid based,
  // never reference-bound, always a lower confidence ceiling than the grid.
  static const String timingFreeplayMeanAbsoluteError =
      'timing.freeplay_mean_absolute_error.v1';
  static const String timingFreeplayMedianAbsoluteError =
      'timing.freeplay_median_absolute_error.v1';
  static const String timingFreeplayP90AbsoluteError =
      'timing.freeplay_p90_absolute_error.v1';
  static const String timingFreeplaySignedBias =
      'timing.freeplay_signed_bias.v1';
  static const String timingFreeplayOnTimeRatio =
      'timing.freeplay_on_time_ratio.v1';
  static const String timingFreeplayEarlyRatio =
      'timing.freeplay_early_ratio.v1';
  static const String timingFreeplayLateRatio = 'timing.freeplay_late_ratio.v1';
  static const String timingFreeplayMissedRatio =
      'timing.freeplay_missed_ratio.v1';
  static const String timingFreeplayExtraRatio =
      'timing.freeplay_extra_ratio.v1';
  static const String timingFreeplayLongestStableStreak =
      'timing.freeplay_longest_stable_streak.v1';

  // Rhythm consistency and measured groove proxies (E06-R15, ADR 0233).
  // Target and inferred grids deliberately use distinct namespaces: they
  // describe different reference evidence and are never interchangeable.
  static const String rhythmTargetIoiConsistency =
      'rhythm.target_ioi_consistency.v1';
  static const String rhythmTargetSubdivisionConsistency =
      'rhythm.target_subdivision_consistency.v1';
  static const String rhythmTargetBeatPhaseConsistency =
      'rhythm.target_beat_phase_consistency.v1';
  static const String rhythmTargetLongestStableIoiStreak =
      'rhythm.target_longest_stable_ioi_streak.v1';
  static const String rhythmTargetAccentPositionConsistency =
      'rhythm.target_accent_position_consistency.v1';
  static const String rhythmTargetSwingRatio = 'rhythm.target_swing_ratio.v1';

  static const String rhythmInferredIoiConsistency =
      'rhythm.inferred_ioi_consistency.v1';
  static const String rhythmInferredSubdivisionConsistency =
      'rhythm.inferred_subdivision_consistency.v1';
  static const String rhythmInferredBeatPhaseConsistency =
      'rhythm.inferred_beat_phase_consistency.v1';
  static const String rhythmInferredLongestStableIoiStreak =
      'rhythm.inferred_longest_stable_ioi_streak.v1';
  static const String rhythmInferredAccentPositionConsistency =
      'rhythm.inferred_accent_position_consistency.v1';

  // Dynamics and stroke balance (E06-R16, ADR 0234). Descriptive metrics
  // (strength CV, down/up ratio, drift, outlier ratio, quiet/clipped ratios)
  // carry no preferred direction and are never framed as "lower is better".
  // Only `dynamicsAccentAccuracy` is evaluative, and only with an explicit
  // target — without one it publishes `notApplicable`, never a fabricated
  // number.
  static const String dynamicsStrokeStrengthCv =
      'dynamics.stroke_strength_cv.v1';
  static const String dynamicsDownUpMedianRatio =
      'dynamics.down_up_median_ratio.v1';
  static const String dynamicsDrift = 'dynamics.drift.v1';
  static const String dynamicsOutlierRatio = 'dynamics.outlier_ratio.v1';
  static const String dynamicsAccentAccuracy = 'dynamics.accent_accuracy.v1';
  static const String dynamicsQuietRegionRatio =
      'dynamics.quiet_region_ratio.v1';
  static const String dynamicsClippedEventRatio =
      'dynamics.clipped_event_ratio.v1';

  // Target-bound monophonic pitch (E06-R17, ADR 0235). The signed median
  // cents error is descriptive intonation evidence, never a diagnosis.
  static const String pitchNoteHitRatio = 'pitch.note_hit_ratio.v1';
  static const String pitchMedianCentsError = 'pitch.median_cents_error.v1';
  static const String pitchP90CentsError = 'pitch.p90_cents_error.v1';
  static const String pitchStabilityCents = 'pitch.stability_cents.v1';
  static const String pitchNoteTransitionTiming =
      'pitch.note_transition_timing.v1';
  static const String pitchSustainedNoteDuration =
      'pitch.sustained_note_duration.v1';
  static const String pitchUnwantedDropoutRatio =
      'pitch.unwanted_dropout_ratio.v1';

  // Experimental Lab-only technique proxies (E06-R18, ADR 0236). Each name
  // states only what is measured — never a technique/skill/cleanliness
  // score, and never a hand, finger or ergonomics claim. These IDs are
  // additive: no pipeline or `AnalysisDocument` wiring publishes them in
  // this round, and they may only be computed behind the
  // `analysisTechniqueProxiesEnabled` flag AND explicit Lab-mode input
  // (`TechniqueProxyReport`, `technique_proxies.dart`).
  static const String techniqueChordChangeGap = 'technique.chord_change_gap.v1';
  static const String techniqueConfidenceCollapseDuration =
      'technique.confidence_collapse_duration.v1';
  static const String techniqueUnexpectedExtraOnsets =
      'technique.unexpected_extra_onsets.v1';
  static const String techniqueSustainedNoteDropout =
      'technique.sustained_note_dropout.v1';
  static const String techniqueAttackInstability =
      'technique.attack_instability.v1';

  static const Set<String> known = <String>{
    timingMeanAbsoluteError,
    rhythmRushDragBias,
    dynamicsStrumConsistency,
    harmonyChordCoverage,
    timingTargetMeanAbsoluteError,
    timingTargetMedianAbsoluteError,
    timingTargetP90AbsoluteError,
    timingTargetSignedBias,
    timingTargetOnTimeRatio,
    timingTargetEarlyRatio,
    timingTargetLateRatio,
    timingTargetMissedRatio,
    timingTargetExtraRatio,
    timingTargetLongestStableStreak,
    timingFreeplayMeanAbsoluteError,
    timingFreeplayMedianAbsoluteError,
    timingFreeplayP90AbsoluteError,
    timingFreeplaySignedBias,
    timingFreeplayOnTimeRatio,
    timingFreeplayEarlyRatio,
    timingFreeplayLateRatio,
    timingFreeplayMissedRatio,
    timingFreeplayExtraRatio,
    timingFreeplayLongestStableStreak,
    rhythmTargetIoiConsistency,
    rhythmTargetSubdivisionConsistency,
    rhythmTargetBeatPhaseConsistency,
    rhythmTargetLongestStableIoiStreak,
    rhythmTargetAccentPositionConsistency,
    rhythmTargetSwingRatio,
    rhythmInferredIoiConsistency,
    rhythmInferredSubdivisionConsistency,
    rhythmInferredBeatPhaseConsistency,
    rhythmInferredLongestStableIoiStreak,
    rhythmInferredAccentPositionConsistency,
    dynamicsStrokeStrengthCv,
    dynamicsDownUpMedianRatio,
    dynamicsDrift,
    dynamicsOutlierRatio,
    dynamicsAccentAccuracy,
    dynamicsQuietRegionRatio,
    dynamicsClippedEventRatio,
    pitchNoteHitRatio,
    pitchMedianCentsError,
    pitchP90CentsError,
    pitchStabilityCents,
    pitchNoteTransitionTiming,
    pitchSustainedNoteDuration,
    pitchUnwantedDropoutRatio,
    techniqueChordChangeGap,
    techniqueConfidenceCollapseDuration,
    techniqueUnexpectedExtraOnsets,
    techniqueSustainedNoteDropout,
    techniqueAttackInstability,
  };

  static bool contains(String id) => known.contains(id);
}

/// The five experimental, Lab-only technique-proxy metric IDs (E06-R18,
/// ADR 0236). Never published to `AnalysisDocument.metrics` in this round;
/// only returned inside a standalone `TechniqueProxyReport`.
abstract final class TechniqueProxyMetricIds {
  static const String chordChangeGap = AnalysisMetricId.techniqueChordChangeGap;
  static const String confidenceCollapseDuration =
      AnalysisMetricId.techniqueConfidenceCollapseDuration;
  static const String unexpectedExtraOnsets =
      AnalysisMetricId.techniqueUnexpectedExtraOnsets;
  static const String sustainedNoteDropout =
      AnalysisMetricId.techniqueSustainedNoteDropout;
  static const String attackInstability =
      AnalysisMetricId.techniqueAttackInstability;

  static const Set<String> all = <String>{
    chordChangeGap,
    confidenceCollapseDuration,
    unexpectedExtraOnsets,
    sustainedNoteDropout,
    attackInstability,
  };
}

/// The seven mandatory dynamics and stroke-balance metric IDs (E06-R16,
/// ADR 0234). A single suite — no target/inferred split, since every value
/// is derived from `PreprocessedAudio.originalSamples` regardless of whether
/// a target exists; only [accentAccuracy] itself is target-gated.
abstract final class DynamicsMetricIds {
  static const String strokeStrengthCv =
      AnalysisMetricId.dynamicsStrokeStrengthCv;
  static const String downUpMedianRatio =
      AnalysisMetricId.dynamicsDownUpMedianRatio;
  static const String drift = AnalysisMetricId.dynamicsDrift;
  static const String outlierRatio = AnalysisMetricId.dynamicsOutlierRatio;
  static const String accentAccuracy = AnalysisMetricId.dynamicsAccentAccuracy;
  static const String quietRegionRatio =
      AnalysisMetricId.dynamicsQuietRegionRatio;
  static const String clippedEventRatio =
      AnalysisMetricId.dynamicsClippedEventRatio;

  static const Set<String> all = <String>{
    strokeStrengthCv,
    downUpMedianRatio,
    drift,
    outlierRatio,
    accentAccuracy,
    quietRegionRatio,
    clippedEventRatio,
  };
}

/// One mode's rhythm consistency metrics (ADR 0233). The target suite carries
/// the measured long/short swing ratio; inferred mode intentionally does not.
final class RhythmMetricSuiteIds {
  const RhythmMetricSuiteIds({
    required this.ioiConsistency,
    required this.subdivisionConsistency,
    required this.beatPhaseConsistency,
    required this.longestStableIoiStreak,
    required this.accentPositionConsistency,
    this.swingRatio,
  });

  static const RhythmMetricSuiteIds target = RhythmMetricSuiteIds(
    ioiConsistency: AnalysisMetricId.rhythmTargetIoiConsistency,
    subdivisionConsistency: AnalysisMetricId.rhythmTargetSubdivisionConsistency,
    beatPhaseConsistency: AnalysisMetricId.rhythmTargetBeatPhaseConsistency,
    longestStableIoiStreak: AnalysisMetricId.rhythmTargetLongestStableIoiStreak,
    accentPositionConsistency:
        AnalysisMetricId.rhythmTargetAccentPositionConsistency,
    swingRatio: AnalysisMetricId.rhythmTargetSwingRatio,
  );

  static const RhythmMetricSuiteIds inferred = RhythmMetricSuiteIds(
    ioiConsistency: AnalysisMetricId.rhythmInferredIoiConsistency,
    subdivisionConsistency:
        AnalysisMetricId.rhythmInferredSubdivisionConsistency,
    beatPhaseConsistency: AnalysisMetricId.rhythmInferredBeatPhaseConsistency,
    longestStableIoiStreak:
        AnalysisMetricId.rhythmInferredLongestStableIoiStreak,
    accentPositionConsistency:
        AnalysisMetricId.rhythmInferredAccentPositionConsistency,
  );

  final String ioiConsistency;
  final String subdivisionConsistency;
  final String beatPhaseConsistency;
  final String longestStableIoiStreak;
  final String accentPositionConsistency;
  final String? swingRatio;

  Set<String> get all => <String>{
    ioiConsistency,
    subdivisionConsistency,
    beatPhaseConsistency,
    longestStableIoiStreak,
    accentPositionConsistency,
    ?swingRatio,
  };
}

/// Groups one mode's ten timing metric IDs (ADR 0232 §1). [target] is
/// reference-bound (from an `AlignmentResult`); [freeplay] is estimated
/// beat-grid based. The two sets are always disjoint.
final class TimingMetricSuiteIds {
  const TimingMetricSuiteIds({
    required this.meanAbsoluteError,
    required this.medianAbsoluteError,
    required this.p90AbsoluteError,
    required this.signedBias,
    required this.onTimeRatio,
    required this.earlyRatio,
    required this.lateRatio,
    required this.missedRatio,
    required this.extraRatio,
    required this.longestStableStreak,
  });

  static const TimingMetricSuiteIds target = TimingMetricSuiteIds(
    meanAbsoluteError: AnalysisMetricId.timingTargetMeanAbsoluteError,
    medianAbsoluteError: AnalysisMetricId.timingTargetMedianAbsoluteError,
    p90AbsoluteError: AnalysisMetricId.timingTargetP90AbsoluteError,
    signedBias: AnalysisMetricId.timingTargetSignedBias,
    onTimeRatio: AnalysisMetricId.timingTargetOnTimeRatio,
    earlyRatio: AnalysisMetricId.timingTargetEarlyRatio,
    lateRatio: AnalysisMetricId.timingTargetLateRatio,
    missedRatio: AnalysisMetricId.timingTargetMissedRatio,
    extraRatio: AnalysisMetricId.timingTargetExtraRatio,
    longestStableStreak: AnalysisMetricId.timingTargetLongestStableStreak,
  );

  static const TimingMetricSuiteIds freeplay = TimingMetricSuiteIds(
    meanAbsoluteError: AnalysisMetricId.timingFreeplayMeanAbsoluteError,
    medianAbsoluteError: AnalysisMetricId.timingFreeplayMedianAbsoluteError,
    p90AbsoluteError: AnalysisMetricId.timingFreeplayP90AbsoluteError,
    signedBias: AnalysisMetricId.timingFreeplaySignedBias,
    onTimeRatio: AnalysisMetricId.timingFreeplayOnTimeRatio,
    earlyRatio: AnalysisMetricId.timingFreeplayEarlyRatio,
    lateRatio: AnalysisMetricId.timingFreeplayLateRatio,
    missedRatio: AnalysisMetricId.timingFreeplayMissedRatio,
    extraRatio: AnalysisMetricId.timingFreeplayExtraRatio,
    longestStableStreak: AnalysisMetricId.timingFreeplayLongestStableStreak,
  );

  final String meanAbsoluteError;
  final String medianAbsoluteError;
  final String p90AbsoluteError;
  final String signedBias;
  final String onTimeRatio;
  final String earlyRatio;
  final String lateRatio;
  final String missedRatio;
  final String extraRatio;
  final String longestStableStreak;

  /// All ten IDs in this mode's suite, for disjointness/coverage assertions.
  Set<String> get all => <String>{
    meanAbsoluteError,
    medianAbsoluteError,
    p90AbsoluteError,
    signedBias,
    onTimeRatio,
    earlyRatio,
    lateRatio,
    missedRatio,
    extraRatio,
    longestStableStreak,
  };
}
