import '../../domain/analysis_event.dart';
import '../../domain/target/alignment_result.dart';
import '../../domain/target/expected_event.dart';
import 'tolerance_policy.dart';

/// Monotonic, deterministic target alignment with a time-derived candidate band.
///
/// The working score table is a prefix maximum over the shorter input, so its
/// size is `O(min(observed.length, expected.length))`. Only candidates inside
/// the tolerance band are evaluated; no `observed × expected` score matrix is
/// allocated.
final class EventAligner {
  const EventAligner({this.tolerancePolicy = const TolerancePolicy()});

  static const String algorithmVersion = 'event-aligner.v1';
  static const double directionMismatchPenalty =
      TolerancePolicy.directionMismatchPenalty;
  static const double typeMismatchPenalty = TolerancePolicy.typeMismatchPenalty;

  final TolerancePolicy tolerancePolicy;

  AlignmentResult align({
    required List<AnalysisEvent> observed,
    required List<ExpectedEvent> expected,
    required Duration beatDuration,
  }) {
    _validateOrderedObserved(observed);
    _validateOrderedExpected(expected);
    final tolerance = tolerancePolicy.forBeatDuration(beatDuration);
    final expectedAreColumns = expected.length <= observed.length;
    final columnCount = expectedAreColumns ? expected.length : observed.length;
    final bestByColumn = List<_Path?>.filled(columnCount, null);
    final prefixBest = _PrefixBest(columnCount);
    var candidatePairCount = 0;
    var maximumCandidateBandWidth = 0;

    final rowCount = expectedAreColumns ? observed.length : expected.length;
    for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
      final rowTime = expectedAreColumns
          ? observed[rowIndex].time
          : expected[rowIndex].time;
      final first = expectedAreColumns
          ? _lowerBoundExpected(expected, rowTime - tolerance)
          : _lowerBoundObserved(observed, rowTime - tolerance);
      final endExclusive = expectedAreColumns
          ? _upperBoundExpected(expected, rowTime + tolerance)
          : _upperBoundObserved(observed, rowTime + tolerance);
      final width = endExclusive - first;
      candidatePairCount += width;
      if (width > maximumCandidateBandWidth) maximumCandidateBandWidth = width;
      final pending = <_PendingPath>[];

      for (var columnIndex = first; columnIndex < endExclusive; columnIndex++) {
        final observedIndex = expectedAreColumns ? rowIndex : columnIndex;
        final expectedIndex = expectedAreColumns ? columnIndex : rowIndex;
        final cost = _matchCost(
          observed[observedIndex],
          expected[expectedIndex],
          tolerance,
        );
        final gain =
            TolerancePolicy.missedPenalty + TolerancePolicy.extraPenalty - cost;
        if (gain <= 0) continue;
        final previous = prefixBest.query(columnIndex - 1);
        final candidate = _Path(
          benefit: (previous?.benefit ?? 0) + gain,
          previous: previous,
          observedIndex: observedIndex,
          expectedIndex: expectedIndex,
          cost: cost,
        );
        if (_isBetter(candidate, bestByColumn[columnIndex])) {
          pending.add(_PendingPath(columnIndex, candidate));
        }
      }

      // Apply only after evaluating the row: an observed event cannot match
      // more than one expected event.
      for (final update in pending) {
        bestByColumn[update.columnIndex] = update.path;
        prefixBest.update(update.columnIndex, update.path);
      }
    }

    final selected = prefixBest.query(columnCount - 1);
    final selectedPaths = <_Path>[];
    for (var current = selected; current != null; current = current.previous) {
      selectedPaths.add(current);
    }
    final paths = selectedPaths.reversed.toList(growable: false);
    final observedMatched = List<bool>.filled(observed.length, false);
    final expectedMatched = List<bool>.filled(expected.length, false);
    final matches = <AlignmentMatch>[];
    for (final path in paths) {
      observedMatched[path.observedIndex] = true;
      expectedMatched[path.expectedIndex] = true;
      final observedEvent = observed[path.observedIndex];
      final expectedEvent = expected[path.expectedIndex];
      matches.add(
        AlignmentMatch(
          observedIndex: path.observedIndex,
          expectedIndex: path.expectedIndex,
          observed: observedEvent,
          expected: expectedEvent,
          timingError: observedEvent.time - expectedEvent.time,
          cost: path.cost,
        ),
      );
    }

    final missed = <ExpectedEvent>[
      for (var index = 0; index < expected.length; index++)
        if (!expectedMatched[index]) expected[index],
    ];
    final extra = <AnalysisEvent>[
      for (var index = 0; index < observed.length; index++)
        if (!observedMatched[index]) observed[index],
    ];
    final confidence = matches.isEmpty
        ? 0.0
        : matches.fold<double>(
                0,
                (sum, match) => sum + match.observed.confidence,
              ) /
              matches.length;

    return AlignmentResult(
      matches: matches,
      missedExpected: missed,
      extraObserved: extra,
      totalCost:
          observed.length * TolerancePolicy.extraPenalty +
          expected.length * TolerancePolicy.missedPenalty -
          (selected?.benefit ?? 0),
      confidence: confidence,
      diagnostics: AlignmentDiagnostics(
        algorithmVersion: algorithmVersion,
        observedCount: observed.length,
        expectedCount: expected.length,
        candidatePairCount: candidatePairCount,
        maximumCandidateBandWidth: maximumCandidateBandWidth,
        scoreStateCount: columnCount,
      ),
    );
  }

  double _matchCost(
    AnalysisEvent observed,
    ExpectedEvent expected,
    Duration tolerance,
  ) {
    final timingDistance = (observed.time - expected.time).inMicroseconds.abs();
    final timingCost = timingDistance / tolerance.inMicroseconds;
    final directionCost =
        observed is StrumEvent &&
            expected.direction != null &&
            observed.direction != expected.direction
        ? TolerancePolicy.directionMismatchPenalty
        : 0.0;
    final typeCost = _eventTypeOf(observed) != expected.type
        ? TolerancePolicy.typeMismatchPenalty
        : 0.0;
    return (timingCost + directionCost + typeCost) *
        (TolerancePolicy.confidenceMultiplierBase - observed.confidence);
  }
}

ExpectedEventType _eventTypeOf(AnalysisEvent event) => switch (event) {
  OnsetEvent() => ExpectedEventType.onset,
  StrumEvent() => ExpectedEventType.strum,
  ChordChangeEvent() => ExpectedEventType.chordChange,
  BeatEvent() => ExpectedEventType.beat,
  NoteOnsetEvent() => ExpectedEventType.noteOnset,
  AnalysisRegionEvent() => ExpectedEventType.onset,
};

void _validateOrderedObserved(List<AnalysisEvent> events) {
  Duration? previous;
  for (final event in events) {
    if (!event.confidence.isFinite) {
      throw ArgumentError.value(event.confidence, 'observed.confidence');
    }
    if (previous != null && event.time < previous) {
      throw ArgumentError.value(events, 'observed', 'must be ordered by time');
    }
    previous = event.time;
  }
}

void _validateOrderedExpected(List<ExpectedEvent> events) {
  Duration? previous;
  for (final event in events) {
    if (previous != null && event.time < previous) {
      throw ArgumentError.value(events, 'expected', 'must be ordered by time');
    }
    previous = event.time;
  }
}

int _lowerBoundExpected(List<ExpectedEvent> events, Duration value) {
  var low = 0;
  var high = events.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (events[middle].time < value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

int _upperBoundExpected(List<ExpectedEvent> events, Duration value) {
  var low = 0;
  var high = events.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (events[middle].time <= value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

int _lowerBoundObserved(List<AnalysisEvent> events, Duration value) {
  var low = 0;
  var high = events.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (events[middle].time < value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

int _upperBoundObserved(List<AnalysisEvent> events, Duration value) {
  var low = 0;
  var high = events.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (events[middle].time <= value) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

bool _isBetter(_Path candidate, _Path? current) {
  if (current == null) return true;
  const epsilon = 1e-12;
  if (candidate.benefit > current.benefit + epsilon) return true;
  if ((candidate.benefit - current.benefit).abs() > epsilon) return false;
  return candidate.expectedIndex < current.expectedIndex;
}

final class _PendingPath {
  const _PendingPath(this.columnIndex, this.path);

  final int columnIndex;
  final _Path path;
}

final class _Path {
  const _Path({
    required this.benefit,
    required this.previous,
    required this.observedIndex,
    required this.expectedIndex,
    required this.cost,
  });

  final double benefit;
  final _Path? previous;
  final int observedIndex;
  final int expectedIndex;
  final double cost;
}

/// Fenwick prefix maximum with deterministic earlier-index tie resolution.
final class _PrefixBest {
  _PrefixBest(int length) : _tree = List<_Path?>.filled(length + 1, null);

  final List<_Path?> _tree;

  _Path? query(int index) {
    _Path? best;
    for (
      var position = index + 1;
      position > 0;
      position -= position & -position
    ) {
      final candidate = _tree[position];
      if (candidate != null && _isBetter(candidate, best)) best = candidate;
    }
    return best;
  }

  void update(int index, _Path path) {
    for (
      var position = index + 1;
      position < _tree.length;
      position += position & -position
    ) {
      if (_isBetter(path, _tree[position])) _tree[position] = path;
    }
  }
}
