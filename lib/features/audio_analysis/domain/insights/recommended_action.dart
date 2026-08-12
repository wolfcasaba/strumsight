/// A serializable description of a follow-up action. Consumers decide how to
/// render or perform it; the analysis domain never carries navigation or
/// callback state.
sealed class RecommendedAnalysisAction {
  const RecommendedAnalysisAction();
}

final class PracticeHotspotAction extends RecommendedAnalysisAction {
  const PracticeHotspotAction({required this.hotspotId});

  final String hotspotId;
}

final class RepeatSlowerAction extends RecommendedAnalysisAction {
  const RepeatSlowerAction({required this.metricId});

  final String metricId;
}

final class CalibrateInputAction extends RecommendedAnalysisAction {
  const CalibrateInputAction();
}

final class CompareWithPreviousAction extends RecommendedAnalysisAction {
  const CompareWithPreviousAction({required this.metricId});

  final String metricId;
}

final class OpenChordTransitionExerciseAction
    extends RecommendedAnalysisAction {
  const OpenChordTransitionExerciseAction({required this.hotspotId});

  final String hotspotId;
}

final class AskTutorAction extends RecommendedAnalysisAction {
  const AskTutorAction({required this.metricId});

  final String metricId;
}
