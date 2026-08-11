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

  static const Set<String> known = <String>{
    timingMeanAbsoluteError,
    rhythmRushDragBias,
    dynamicsStrumConsistency,
    harmonyChordCoverage,
  };

  static bool contains(String id) => known.contains(id);
}
