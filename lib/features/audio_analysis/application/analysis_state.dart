import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';

/// User-visible state of one V2 analysis attempt (SDD Ch7 §21.1).
sealed class AnalysisState {
  const AnalysisState();
}

final class AnalysisIdle extends AnalysisState {
  const AnalysisIdle();
}

final class AnalysisAcquiringInput extends AnalysisState {
  const AnalysisAcquiringInput();
}

final class AnalysisRecording extends AnalysisState {
  const AnalysisRecording();
}

final class AnalysisValidating extends AnalysisState {
  const AnalysisValidating();
}

final class AnalysisAnalyzing extends AnalysisState {
  const AnalysisAnalyzing({
    required this.runId,
    this.phase,
    this.completedUnits,
    this.totalUnits,
    this.emittedProgressEvents = 0,
  });

  final String runId;
  final AnalysisProgressPhase? phase;
  final int? completedUnits;
  final int? totalUnits;
  final int emittedProgressEvents;
}

final class AnalysisCompleted extends AnalysisState {
  const AnalysisCompleted({required this.runId, required this.document});

  final String runId;
  final AnalysisDocument document;
}

final class AnalysisDegradedCompleted extends AnalysisState {
  const AnalysisDegradedCompleted({
    required this.runId,
    required this.document,
  });

  final String runId;
  final AnalysisDocument document;
}

final class AnalysisCancelled extends AnalysisState {
  const AnalysisCancelled({required this.runId});

  final String runId;
}

final class AnalysisPermissionDenied extends AnalysisState {
  const AnalysisPermissionDenied();
}

final class AnalysisInputError extends AnalysisState {
  const AnalysisInputError(this.failure);

  final AppFailure failure;
}

final class AnalysisError extends AnalysisState {
  const AnalysisError({required this.runId, required this.failure});

  final String runId;
  final AppFailure failure;
}
