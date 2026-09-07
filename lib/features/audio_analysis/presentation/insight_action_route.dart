import '../../../app/routing/app_route.dart';
import '../domain/analysis_insight.dart';

/// R22 (audit MI3) — the destination one persisted
/// [AnalysisRecommendedAction] resolves to.
///
/// `document_stages.dart` drops the engine's rich `RecommendedAnalysisAction`
/// payload (the hotspot or metric id the rule named) when it writes the
/// insight into the document, so no per-hotspot deep link can be honest
/// here. What IS honest is the tool each coarse action asks for, and every
/// one of those already has a registered route:
///
///  * `repeatSection` / `continuePractice` → the practice hub, the same
///    destination `QuestStartPracticeAction` pushes in `app_router.dart`;
///  * `slowDown` → the metronome, the app's only tempo control;
///  * `adjustInput` → the analysis capture screen, where a new recording
///    with a corrected input starts. NOT `/calibrate`: that route is the
///    timing-latency wizard, while both rules that emit this action
///    (`quality.low_signal` and the insufficient-data rule) are about the
///    captured signal itself.
String insightActionRoute(AnalysisRecommendedAction action) {
  return switch (action) {
    AnalysisRecommendedAction.repeatSection => AppRoutes.practiceHub,
    AnalysisRecommendedAction.slowDown => AppRoutes.metronome,
    AnalysisRecommendedAction.adjustInput => AppRoutes.analysisCapture,
    AnalysisRecommendedAction.continuePractice => AppRoutes.practiceHub,
  };
}
