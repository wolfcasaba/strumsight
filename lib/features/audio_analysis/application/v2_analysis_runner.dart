import 'package:strumsight/core/foundation/app_result.dart';

import '../data/analysis_document_codec.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_input.dart';
import '../domain/analysis_progress.dart';
import '../domain/target/analysis_target.dart';
import '../engine/analysis_cancellation.dart';
import '../engine/analysis_pipeline.dart';
import '../engine/analysis_work_state.dart';
import '../engine/stages/analysis_stage_phases.dart';
import 'analysis_isolate_runner.dart';

/// The real V2 boundary implementation (ADR 0254): runs the full, existing
/// 20-stage chain (never a bespoke stage list — ADR 0254 §3) inside a
/// dedicated isolate, via [AnalysisIsolateRunner]'s audio/target transport,
/// so the DSP work never blocks the UI isolate. [cancel] terminates that
/// isolate outright, which is this run's cancellation mechanism — the
/// pipeline's own cooperative cancellation token is local to the isolate and
/// never observed from the outside.
final class V2AnalysisRunner implements AnalysisRunner {
  V2AnalysisRunner()
    : _delegate = AnalysisIsolateRunner(operation: _runFullChain);

  final AnalysisIsolateRunner _delegate;

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) => _delegate.start(input);
}

/// Runs inside the spawned isolate: builds one [AnalysisPipeline] from the
/// existing stage builders, forwards its progress across the isolate
/// boundary via [reportProgress], and returns the resulting document
/// JSON-encoded once the chain finishes. A pipeline run that fails without
/// producing a document throws, which the isolate boundary turns into a
/// failed completion.
Future<String> _runFullChain(
  String documentJson,
  ValidatedPcmAnalysisInput audio,
  AnalysisTarget? target,
  void Function(AnalysisProgressEvent event) reportProgress,
) async {
  final decodedSeed = const AnalysisDocumentCodec().decode(documentJson);
  final seedMode = switch (decodedSeed) {
    Success<AnalysisDocument>(:final value) => value.mode,
    Failure<AnalysisDocument>() => throw StateError(
      'V2 analysis run seed document failed to decode.',
    ),
  };
  final pipeline = AnalysisPipeline<AnalysisWorkState>(
    stages: buildFullAnalysisStages(),
    failureClassifier: classifyAnalysisStageFailure,
    stagePhases: analysisStagePhases,
  );
  final run = pipeline.start(
    AnalysisWorkState.seed(input: audio, mode: seedMode, target: target),
    cancellationToken: AnalysisCancellationSource(),
  );
  final progressSubscription = run.progress.listen(reportProgress);
  final pipelineResult = await run.result;
  await progressSubscription.cancel();
  final document = pipelineResult.value?.document;
  if (document == null) {
    throw StateError(
      'V2 analysis pipeline failed without producing a document '
      '(completion: ${pipelineResult.completion}).',
    );
  }
  // The document-assembly stage's own `completion` field reflects only the
  // ingest-side capability state at assembly time, not the pipeline's full,
  // end-to-end result (e.g. a target-less run marks the timing capability
  // unavailable there, which is not itself a degraded pipeline run — ADR
  // 0251 §2). The isolate boundary's final message carries only the encoded
  // document, so [pipelineResult.completion] — the authoritative status —
  // is folded into the wire document here, matching the direct, in-process
  // translation this runner used before it moved into an isolate.
  final wireDocument = AnalysisDocument(
    id: document.id,
    schemaVersion: document.schemaVersion,
    createdAt: document.createdAt,
    mode: document.mode,
    input: document.input,
    provenance: document.provenance,
    signalQuality: document.signalQuality,
    capabilities: document.capabilities,
    timeline: document.timeline,
    metrics: document.metrics,
    hotspots: document.hotspots,
    insights: document.insights,
    warnings: document.warnings,
    completion: AnalysisCompletion(status: pipelineResult.completion),
  );
  return const AnalysisDocumentCodec().encode(wireDocument);
}
