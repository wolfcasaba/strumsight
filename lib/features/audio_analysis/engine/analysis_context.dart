import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';

import 'analysis_cancellation.dart';

typedef AnalysisProgressEventSink = void Function(AnalysisProgressEvent event);

/// Immutable timing evidence for one executed analysis stage.
final class AnalysisStageTiming {
  const AnalysisStageTiming({
    required this.id,
    required this.version,
    required this.elapsed,
  });

  final String id;
  final int version;
  final Duration elapsed;
}

/// Pipeline-owned provenance that can later feed the immutable R02 document
/// provenance without modifying that domain contract.
final class AnalysisPipelineProvenance {
  AnalysisPipelineProvenance({
    required Map<String, String> stageVersions,
    required List<AnalysisStageTiming> stageTimings,
  }) : stageVersions = Map<String, String>.unmodifiable(stageVersions),
       stageTimings = List<AnalysisStageTiming>.unmodifiable(stageTimings);

  final Map<String, String> stageVersions;
  final List<AnalysisStageTiming> stageTimings;
}

final class AnalysisPipelineProvenanceCollector {
  final Map<String, String> _stageVersions = <String, String>{};
  final List<AnalysisStageTiming> _stageTimings = <AnalysisStageTiming>[];

  void recordStage({
    required String id,
    required int version,
    required Duration elapsed,
  }) {
    _stageVersions[id] = '$version';
    _stageTimings.add(
      AnalysisStageTiming(id: id, version: version, elapsed: elapsed),
    );
  }

  AnalysisPipelineProvenance snapshot() => AnalysisPipelineProvenance(
    stageVersions: _stageVersions,
    stageTimings: _stageTimings,
  );
}

/// Per-stage, per-run context. It contains no process-global state.
final class AnalysisStageContext {
  AnalysisStageContext({
    required this.runId,
    required this.phase,
    required this.cancellationToken,
    required this.eventSink,
  });

  final String runId;
  final AnalysisProgressPhase phase;
  final AnalysisCancellationToken cancellationToken;
  final AnalysisProgressEventSink eventSink;
  bool _hasReportedProgress = false;

  bool get hasReportedProgress => _hasReportedProgress;

  /// Publishes the stage's assigned phase. The pipeline rejects an active
  /// run's duplicate or backwards phase before it reaches consumers.
  void reportProgress({int? completedUnits, int? totalUnits}) {
    _hasReportedProgress = true;
    eventSink(
      AnalysisPhaseProgressEvent(
        runId: runId,
        phase: phase,
        completedUnits: completedUnits,
        totalUnits: totalUnits,
      ),
    );
  }

  /// Allows an isolate-backed future stage to return a result event through
  /// the same run-ID filter as progress. Normal in-process stages leave this
  /// to [AnalysisPipeline].
  void publishResult(AnalysisCompletionStatus completion) =>
      eventSink(AnalysisRunResultEvent(runId: runId, completion: completion));
}
