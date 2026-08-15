import 'package:strumsight/core/foundation/app_failure.dart';

import '../../domain/analysis_progress.dart';
import '../analysis_stage.dart';
import '../analysis_work_state.dart';
import 'document_stages.dart';
import 'evaluation_stages.dart';
import 'ingest_stages.dart';

/// The stage IDs the seven-stage ingest chain contributes to the full
/// analysis chain (ADR 0252 §5.3), used to dispatch
/// [classifyAnalysisStageFailure] to the right composition-owned classifier.
const Set<String> _ingestStageIds = <String>{
  IngestStageIds.preprocessing,
  IngestStageIds.signalQuality,
  IngestStageIds.legacyEvidence,
  IngestStageIds.pitch,
  IngestStageIds.harmony,
  IngestStageIds.rhythm,
  IngestStageIds.events,
};

/// Stage-id → user-facing progress phase for the full 20-stage analysis
/// chain (ADR 0252). The phase is a composition property, not a stage
/// position: several stages intentionally share one phase, and the mapping
/// is data-driven off the stage-id constants — never string literals — so a
/// later round adding a stage without updating this map fails loudly
/// ([AnalysisPipeline]'s constructor validation, A5).
const Map<String, AnalysisProgressPhase> analysisStagePhases =
    <String, AnalysisProgressPhase>{
      IngestStageIds.preprocessing: AnalysisProgressPhase.preprocessing,
      IngestStageIds.signalQuality: AnalysisProgressPhase.preprocessing,
      IngestStageIds.legacyEvidence: AnalysisProgressPhase.extractingEvents,
      IngestStageIds.pitch: AnalysisProgressPhase.extractingEvents,
      IngestStageIds.harmony: AnalysisProgressPhase.estimatingHarmony,
      IngestStageIds.rhythm: AnalysisProgressPhase.estimatingBeatGrid,
      IngestStageIds.events: AnalysisProgressPhase.estimatingBeatGrid,
      EvaluationStageIds.alignment: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.timing: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.timingHotspots: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.rhythm: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.pitch: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.dynamics: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.accent: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.subdivision: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.transitions: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.technique: AnalysisProgressPhase.computingMetrics,
      EvaluationStageIds.capability: AnalysisProgressPhase.buildingInsights,
      DocumentStageIds.assembly: AnalysisProgressPhase.buildingInsights,
      DocumentStageIds.insights: AnalysisProgressPhase.finalizing,
    };

/// The full 20-stage chain in fixed order: seven ingest stages (ADR 0250),
/// eleven evaluation stages (ADR 0251), then document assembly and insights
/// (ADR 0253). Pairs with [analysisStagePhases] and
/// [classifyAnalysisStageFailure] when composed into a live
/// `AnalysisPipeline`. Not wired into any provider in this round.
List<AnalysisStage<AnalysisWorkState, AnalysisWorkState>>
buildFullAnalysisStages() =>
    <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
      ...buildIngestStages(),
      ...buildEvaluationStages(),
      DocumentAssemblyStage(),
      InsightsStage(),
    ];

/// Dispatches to the ingest or evaluation composition-owned classifier by
/// stage id, so the full chain keeps each stage's original degradation
/// policy unchanged.
StageFailure classifyAnalysisStageFailure(String stageId, AppFailure failure) =>
    _ingestStageIds.contains(stageId)
    ? classifyIngestStageFailure(stageId, failure)
    : classifyEvaluationStageFailure(stageId, failure);
