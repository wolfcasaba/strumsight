import 'analysis_document.dart';

/// The ordered, user-observable analysis phases from SDD Ch7 §6.4.
enum AnalysisProgressPhase {
  preparing,
  validatingInput,
  preprocessing,
  extractingEvents,
  estimatingHarmony,
  estimatingBeatGrid,
  computingMetrics,
  buildingInsights,
  finalizing,
}

/// An event published during one analysis run.
sealed class AnalysisProgressEvent {
  const AnalysisProgressEvent({required this.runId});

  final String runId;
}

/// A phase transition, with optional deterministic sub-work accounting.
final class AnalysisPhaseProgressEvent extends AnalysisProgressEvent {
  AnalysisPhaseProgressEvent({
    required super.runId,
    required this.phase,
    this.completedUnits,
    this.totalUnits,
  }) {
    if ((completedUnits == null) != (totalUnits == null)) {
      throw ArgumentError('Progress units must be supplied as a pair.');
    }
    if (completedUnits != null &&
        (completedUnits! < 0 ||
            totalUnits! <= 0 ||
            completedUnits! > totalUnits!)) {
      throw ArgumentError('Progress units must be within 0..totalUnits.');
    }
  }

  final AnalysisProgressPhase phase;
  final int? completedUnits;
  final int? totalUnits;
}

/// The terminal result publication for an analysis run.
final class AnalysisRunResultEvent extends AnalysisProgressEvent {
  const AnalysisRunResultEvent({
    required super.runId,
    required this.completion,
  });

  final AnalysisCompletionStatus completion;
}
