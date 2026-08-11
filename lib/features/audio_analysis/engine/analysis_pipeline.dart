import 'dart:async';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';

import 'analysis_cancellation.dart';
import 'analysis_context.dart';
import 'analysis_stage.dart';

/// The observable handle for one pipeline execution.
final class AnalysisPipelineRun<T> {
  const AnalysisPipelineRun({
    required this.runId,
    required this.progress,
    required this.result,
  });

  final String runId;
  final Stream<AnalysisProgressEvent> progress;
  final Future<AnalysisPipelineResult<T>> result;
}

/// Terminal state of a pipeline execution. A cancelled run intentionally has
/// no [value], so callers cannot publish a partial document by accident.
final class AnalysisPipelineResult<T> {
  AnalysisPipelineResult({
    required this.runId,
    required this.completion,
    required this.value,
    required Map<String, T> stageOutputs,
    required List<AnalysisWarning> warnings,
    required Set<AnalysisCapability> unavailableCapabilities,
    required this.provenance,
    this.failure,
  }) : stageOutputs = Map<String, T>.unmodifiable(stageOutputs),
       warnings = List<AnalysisWarning>.unmodifiable(warnings),
       unavailableCapabilities = Set<AnalysisCapability>.unmodifiable(
         unavailableCapabilities,
       );

  final String runId;
  final AnalysisCompletionStatus completion;
  final T? value;
  final Map<String, T> stageOutputs;
  final List<AnalysisWarning> warnings;
  final Set<AnalysisCapability> unavailableCapabilities;
  final AnalysisPipelineProvenance provenance;
  final AppFailure? failure;
}

/// Composes same-state stages in order. Future real DSP stages can use their
/// own work-state type while keeping the SDD's generic stage contract.
final class AnalysisPipeline<T> {
  AnalysisPipeline({
    required List<AnalysisStage<T, T>> stages,
    AnalysisStageFailureClassifier? failureClassifier,
    Stopwatch Function()? stopwatchFactory,
  }) : _stages = List<AnalysisStage<T, T>>.unmodifiable(stages),
       _failureClassifier = failureClassifier ?? _fatalFailure,
       _stopwatchFactory = stopwatchFactory ?? Stopwatch.new {
    if (_stages.isEmpty) {
      throw ArgumentError.value(stages, 'stages', 'must not be empty');
    }
    if (_stages.length > AnalysisProgressPhase.values.length) {
      throw ArgumentError.value(
        stages,
        'stages',
        'cannot exceed the nine ordered progress phases',
      );
    }
    final ids = _stages.map((stage) => stage.id).toList(growable: false);
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length) {
      throw ArgumentError.value(stages, 'stages', 'stage IDs must be unique');
    }
  }

  final List<AnalysisStage<T, T>> _stages;
  final AnalysisStageFailureClassifier _failureClassifier;
  final Stopwatch Function() _stopwatchFactory;

  int _nextRunNumber = 0;
  String? _activeRunId;
  int _droppedLateEvents = 0;

  /// Diagnostic evidence for SDD Ch7 §21.2 late-event filtering.
  int get droppedLateEvents => _droppedLateEvents;

  AnalysisPipelineRun<T> start(
    T input, {
    required AnalysisCancellationToken cancellationToken,
  }) {
    final runId = 'analysis-run-${++_nextRunNumber}';
    final progressController = StreamController<AnalysisProgressEvent>();
    _activeRunId = runId;

    final result = Future<AnalysisPipelineResult<T>>.microtask(
      () => _execute(
        runId: runId,
        input: input,
        cancellationToken: cancellationToken,
        progressController: progressController,
      ),
    );
    return AnalysisPipelineRun<T>(
      runId: runId,
      progress: progressController.stream,
      result: result,
    );
  }

  Future<AnalysisPipelineResult<T>> _execute({
    required String runId,
    required T input,
    required AnalysisCancellationToken cancellationToken,
    required StreamController<AnalysisProgressEvent> progressController,
  }) async {
    final outputs = <String, T>{};
    final warnings = <AnalysisWarning>[];
    final unavailableCapabilities = <AnalysisCapability>{};
    final provenance = AnalysisPipelineProvenanceCollector();
    var currentValue = input;
    AnalysisProgressPhase? latestPhase;

    void publish(AnalysisProgressEvent event) {
      if (_activeRunId != event.runId) {
        _droppedLateEvents++;
        return;
      }
      if (event is AnalysisPhaseProgressEvent) {
        if (latestPhase != null && event.phase.index <= latestPhase!.index) {
          throw StateError(
            'Analysis progress phases must be strictly monotonic.',
          );
        }
        latestPhase = event.phase;
      }
      progressController.add(event);
    }

    Future<AnalysisPipelineResult<T>> finish({
      required AnalysisCompletionStatus completion,
      required T? value,
      AppFailure? failure,
    }) async {
      if (completion != AnalysisCompletionStatus.cancelled) {
        publish(AnalysisRunResultEvent(runId: runId, completion: completion));
      }
      // A single-subscription stream's close future waits for its listener.
      // Completion must not depend on whether a caller chose to observe
      // progress, so close the stream without making the run future wait.
      unawaited(progressController.close());
      if (_activeRunId == runId) _activeRunId = null;
      return AnalysisPipelineResult<T>(
        runId: runId,
        completion: completion,
        value: value,
        stageOutputs: outputs,
        warnings: warnings,
        unavailableCapabilities: unavailableCapabilities,
        provenance: provenance.snapshot(),
        failure: failure,
      );
    }

    try {
      cancellationToken.throwIfCancelled();
      for (var index = 0; index < _stages.length; index++) {
        cancellationToken.throwIfCancelled();
        final stage = _stages[index];
        final context = AnalysisStageContext(
          runId: runId,
          phase: AnalysisProgressPhase.values[index],
          cancellationToken: cancellationToken,
          eventSink: publish,
        );
        final stopwatch = _stopwatchFactory()..start();
        AppResult<T> stageResult;
        try {
          stageResult = await stage.run(currentValue, context);
        } finally {
          stopwatch.stop();
          provenance.recordStage(
            id: stage.id,
            version: stage.version,
            elapsed: stopwatch.elapsed,
          );
        }
        cancellationToken.throwIfCancelled();
        if (!context.hasReportedProgress) context.reportProgress();

        switch (stageResult) {
          case Success<T>(:final value):
            currentValue = value;
            outputs[stage.id] = value;
          case Failure<T>(:final error):
            final classifiedFailure = _failureClassifier(stage.id, error);
            if (!classifiedFailure.isDegradable) {
              return finish(
                completion: AnalysisCompletionStatus.failed,
                value: null,
                failure: classifiedFailure.failure,
              );
            }
            warnings.add(
              AnalysisWarning(
                kind: AnalysisWarningKind.processing,
                severity: AnalysisWarningSeverity.warning,
                messageKey: 'analysis.stage_unavailable',
                messageArgs: <String, String>{
                  'stageId': stage.id,
                  'failureCode': classifiedFailure.failure.code,
                },
              ),
            );
            unavailableCapabilities.addAll(
              classifiedFailure.unavailableCapabilities,
            );
        }
      }
      cancellationToken.throwIfCancelled();
      return finish(
        completion: warnings.isEmpty
            ? AnalysisCompletionStatus.complete
            : AnalysisCompletionStatus.degraded,
        value: currentValue,
      );
    } on AnalysisCancelledException {
      return finish(
        completion: AnalysisCompletionStatus.cancelled,
        value: null,
      );
    } catch (error, stackTrace) {
      return finish(
        completion: AnalysisCompletionStatus.failed,
        value: null,
        failure: UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  static StageFailure _fatalFailure(String _, AppFailure failure) =>
      StageFailure.fatal(failure);
}
