import '../domain/analysis_progress.dart';
import '../engine/analysis_cancellation.dart';
import '../engine/analysis_pipeline.dart';
import '../engine/analysis_work_state.dart';
import '../engine/stages/analysis_stage_phases.dart';
import 'analysis_isolate_runner.dart';

/// The real V2 boundary implementation (ADR 0254): translates one
/// [AnalysisRunRequest] into an [AnalysisWorkState] seed and runs it through
/// the full, existing 20-stage chain (never a bespoke stage list — ADR 0254
/// §3). A single [AnalysisPipeline] instance is reused across runs so its
/// own active-run tracking keeps rejecting late progress from a superseded
/// run, matching [AnalysisPipeline]'s single-active-run contract.
final class V2AnalysisRunner implements AnalysisRunner {
  V2AnalysisRunner()
    : _pipeline = AnalysisPipeline<AnalysisWorkState>(
        stages: buildFullAnalysisStages(),
        failureClassifier: classifyAnalysisStageFailure,
        stagePhases: analysisStagePhases,
      );

  final AnalysisPipeline<AnalysisWorkState> _pipeline;

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) {
    final cancellationSource = AnalysisCancellationSource();
    final seed = AnalysisWorkState.seed(
      input: input.audio,
      mode: input.seed.mode,
      target: input.target,
    );
    final run = _pipeline.start(seed, cancellationToken: cancellationSource);
    return _V2AnalysisRun(run: run, cancellationSource: cancellationSource);
  }
}

final class _V2AnalysisRun implements AnalysisRunHandle {
  _V2AnalysisRun({required this.run, required this.cancellationSource});

  final AnalysisPipelineRun<AnalysisWorkState> run;
  final AnalysisCancellationSource cancellationSource;

  @override
  String get runId => run.runId;

  @override
  Stream<AnalysisProgressEvent> get progress => run.progress;

  @override
  Future<AnalysisRunResult> get result => run.result.then(
    (pipelineResult) => AnalysisRunResult(
      completion: pipelineResult.completion,
      document: pipelineResult.value?.document,
      failure: pipelineResult.failure,
    ),
  );

  @override
  Future<void> cancel() async {
    cancellationSource.cancel();
    await result;
  }
}
