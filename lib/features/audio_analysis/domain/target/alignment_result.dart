import '../analysis_event.dart';
import 'expected_event.dart';

/// One monotonic observed-to-expected pairing.
final class AlignmentMatch {
  AlignmentMatch({
    required this.observedIndex,
    required this.expectedIndex,
    required this.observed,
    required this.expected,
    required this.timingError,
    required this.cost,
  }) {
    if (observedIndex < 0 || expectedIndex < 0) {
      throw ArgumentError('Alignment indices must be non-negative.');
    }
    if (!cost.isFinite || cost < 0) {
      throw ArgumentError.value(cost, 'cost');
    }
  }

  final int observedIndex;
  final int expectedIndex;
  final AnalysisEvent observed;
  final ExpectedEvent expected;

  /// `observed.time - expected.time`; negative is early, positive is late.
  final Duration timingError;
  final double cost;
}

/// Bounded-work diagnostics for one [AlignmentResult].
final class AlignmentDiagnostics {
  const AlignmentDiagnostics({
    required this.algorithmVersion,
    required this.observedCount,
    required this.expectedCount,
    required this.candidatePairCount,
    required this.maximumCandidateBandWidth,
    required this.scoreStateCount,
  });

  final String algorithmVersion;
  final int observedCount;
  final int expectedCount;
  final int candidatePairCount;
  final int maximumCandidateBandWidth;

  /// Number of linear-space DP score entries allocated for this run.
  final int scoreStateCount;
}

/// Immutable output of an [EventAligner] run.
final class AlignmentResult {
  AlignmentResult({
    required List<AlignmentMatch> matches,
    required List<ExpectedEvent> missedExpected,
    required List<AnalysisEvent> extraObserved,
    required this.totalCost,
    required this.confidence,
    required this.diagnostics,
  }) : matches = List<AlignmentMatch>.unmodifiable(matches),
       missedExpected = List<ExpectedEvent>.unmodifiable(missedExpected),
       extraObserved = List<AnalysisEvent>.unmodifiable(extraObserved) {
    if (!totalCost.isFinite || totalCost < 0) {
      throw ArgumentError.value(totalCost, 'totalCost');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
  }

  final List<AlignmentMatch> matches;
  final List<ExpectedEvent> missedExpected;
  final List<AnalysisEvent> extraObserved;
  final double totalCost;
  final double confidence;
  final AlignmentDiagnostics diagnostics;
}
