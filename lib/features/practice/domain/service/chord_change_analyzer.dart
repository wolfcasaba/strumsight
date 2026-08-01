import '../model/chord_pair_stats.dart';
import '../model/compiled_practice_target.dart';
import '../model/practice_event.dart';
import '../model/practice_observation.dart';
import '../model/practice_verdict.dart';

const Duration _defaultStabilityThreshold = Duration(milliseconds: 180);
const Duration _defaultWindowBefore = Duration(milliseconds: 120);
const Duration _defaultWindowAfter = Duration(milliseconds: 420);
const double _defaultMinimumConfidence = 0.60;

/// Purely analyses expected chord-segment boundaries and sampled observations.
final class ChordChangeAnalyzer {
  const ChordChangeAnalyzer({
    this.stabilityThreshold = _defaultStabilityThreshold,
    this.windowBefore = _defaultWindowBefore,
    this.windowAfter = _defaultWindowAfter,
    this.minimumConfidence = _defaultMinimumConfidence,
  });

  final Duration stabilityThreshold;
  final Duration windowBefore;
  final Duration windowAfter;
  final double minimumConfidence;

  ChordChangeAnalysis analyze({
    required CompiledPracticeTarget target,
    required List<PracticeVerdict> verdicts,
    List<ChordObservation>? observations,
    List<ChordObservation>? chordObservations,
  }) {
    _validateConfiguration();
    final orderedSegments = target.expectedChordSegments.toList()
      ..sort(_compareSegments);
    final orderedObservations =
        (chordObservations ?? observations ?? const []).toList()
          ..sort(_compareObservations);
    final orderedVerdicts = verdicts.toList()..sort(_compareVerdicts);

    final changes = <ChordChangeMeasurement>[];
    for (var index = 1; index < orderedSegments.length; index++) {
      final previous = orderedSegments[index - 1];
      final current = orderedSegments[index];
      if (previous.chord == current.chord) continue;
      final pair = ChordPair(from: previous.chord, to: current.chord);
      changes.add(
        _measureChange(
          pair: pair,
          targetAt: current.start,
          verdicts: orderedVerdicts,
          observations: orderedObservations,
        ),
      );
    }

    final statsByPair = <ChordPair, _MutablePairStats>{};
    for (final change in changes) {
      final stats = statsByPair.putIfAbsent(
        change.pair,
        () => _MutablePairStats(change.pair),
      );
      stats.add(change);
    }
    final stats = statsByPair.values.map((value) => value.freeze()).toList()
      ..sort((left, right) => compareChordPairs(left.pair, right.pair));
    return ChordChangeAnalysis(changes: changes, pairStats: stats);
  }

  ChordChangeMeasurement _measureChange({
    required ChordPair pair,
    required Duration targetAt,
    required List<PracticeVerdict> verdicts,
    required List<ChordObservation> observations,
  }) {
    final windowStart = targetAt - windowBefore;
    // The final stability sample may arrive one stability interval after the
    // configured recognition window. Keep that sample so a change beginning at
    // the end of the window can still be measured.
    final windowEnd = targetAt + windowAfter + stabilityThreshold;
    final hasStrum = verdicts.any(
      (verdict) =>
          verdict.matchedObservationSequence != null &&
          verdict.targetAt >= windowStart &&
          verdict.targetAt <= windowEnd,
    );
    final inWindow = observations
        .where(
          (observation) =>
              observation.at >= windowStart && observation.at <= windowEnd,
        )
        .toList(growable: false);

    if (!hasStrum || inWindow.isEmpty) {
      return ChordChangeMeasurement(
        pair: pair,
        targetAt: targetAt,
        outcome: ChordChangeOutcome.insufficientSignal,
        labelMappingIsLossy: _pairMappingIsLossy(pair),
      );
    }

    final confident = inWindow
        .where((observation) => _hasUsableConfidence(observation))
        .toList(growable: false);
    if (confident.isEmpty) {
      return ChordChangeMeasurement(
        pair: pair,
        targetAt: targetAt,
        outcome: ChordChangeOutcome.insufficientSignal,
        labelMappingIsLossy: _pairMappingIsLossy(pair),
      );
    }

    final segments = _segments(confident);
    final stableTarget = _firstStable(segments, label: pair.to);
    final stableWrong = _firstStable(segments, label: null, exclude: pair.to);
    final hasNonNullLabel = confident.any(
      (observation) => observation.label != null,
    );
    final hasNullLabel = confident.any(
      (observation) => observation.label == null,
    );

    if (stableTarget != null) {
      return ChordChangeMeasurement(
        pair: pair,
        targetAt: targetAt,
        outcome: ChordChangeOutcome.correct,
        recognizedChangeDelay: stableTarget.start - targetAt,
        observedChord: pair.to,
        stableDuration: stableTarget.duration,
        labelMappingIsLossy:
            _pairMappingIsLossy(pair) ||
            !isCanonicalPracticeChordLabel(pair.to),
      );
    }
    if (stableWrong != null) {
      return ChordChangeMeasurement(
        pair: pair,
        targetAt: targetAt,
        outcome: ChordChangeOutcome.wrongChord,
        observedChord: stableWrong.label,
        stableDuration: stableWrong.duration,
        labelMappingIsLossy:
            _pairMappingIsLossy(pair) ||
            !isCanonicalPracticeChordLabel(stableWrong.label),
      );
    }
    if (!hasNonNullLabel && hasNullLabel) {
      return ChordChangeMeasurement(
        pair: pair,
        targetAt: targetAt,
        outcome: ChordChangeOutcome.noDetection,
        labelMappingIsLossy: _pairMappingIsLossy(pair),
      );
    }
    return ChordChangeMeasurement(
      pair: pair,
      targetAt: targetAt,
      outcome: ChordChangeOutcome.unstable,
      observedChord: _firstNonNullLabel(confident),
      stableDuration: _longestSegment(segments)?.duration,
      labelMappingIsLossy: _pairMappingIsLossy(pair),
    );
  }

  bool _hasUsableConfidence(ChordObservation observation) =>
      observation.confidence.isFinite &&
      observation.confidence >= minimumConfidence;

  void _validateConfiguration() {
    if (stabilityThreshold <= Duration.zero) {
      throw ArgumentError.value(
        stabilityThreshold,
        'stabilityThreshold',
        'must be strictly positive',
      );
    }
    if (windowBefore < Duration.zero || windowAfter < Duration.zero) {
      throw ArgumentError('Chord-change windows cannot be negative.');
    }
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      throw ArgumentError.value(
        minimumConfidence,
        'minimumConfidence',
        'must be between zero and one',
      );
    }
  }

  List<_ObservedChordSegment> _segments(List<ChordObservation> observations) {
    final segments = <_ObservedChordSegment>[];
    var index = 0;
    while (index < observations.length) {
      final label = observations[index].label;
      var last = index;
      while (last + 1 < observations.length &&
          observations[last + 1].label == label) {
        last++;
      }
      final end = last + 1 < observations.length
          ? observations[last + 1].at
          : observations[last].at;
      segments.add(
        _ObservedChordSegment(
          label: label,
          start: observations[index].at,
          duration: end - observations[index].at,
        ),
      );
      index = last + 1;
    }
    return segments;
  }

  _ObservedChordSegment? _firstStable(
    List<_ObservedChordSegment> segments, {
    required String? label,
    String? exclude,
  }) {
    for (final segment in segments) {
      final matches = exclude != null
          ? segment.label != null && segment.label != exclude
          : segment.label == label;
      if (matches && segment.duration >= stabilityThreshold) return segment;
    }
    return null;
  }

  _ObservedChordSegment? _longestSegment(List<_ObservedChordSegment> segments) {
    _ObservedChordSegment? longest;
    for (final segment in segments) {
      if (longest == null || segment.duration > longest.duration) {
        longest = segment;
      }
    }
    return longest;
  }

  String? _firstNonNullLabel(List<ChordObservation> observations) {
    for (final observation in observations) {
      if (observation.label != null) return observation.label;
    }
    return null;
  }
}

ChordChangeAnalysis analyzeChordChanges({
  required CompiledPracticeTarget target,
  required List<PracticeVerdict> verdicts,
  required List<ChordObservation> observations,
  Duration stabilityThreshold = _defaultStabilityThreshold,
  Duration windowBefore = _defaultWindowBefore,
  Duration windowAfter = _defaultWindowAfter,
  double minimumConfidence = _defaultMinimumConfidence,
}) => ChordChangeAnalyzer(
  stabilityThreshold: stabilityThreshold,
  windowBefore: windowBefore,
  windowAfter: windowAfter,
  minimumConfidence: minimumConfidence,
).analyze(target: target, verdicts: verdicts, observations: observations);

final class _ObservedChordSegment {
  const _ObservedChordSegment({
    required this.label,
    required this.start,
    required this.duration,
  });

  final String? label;
  final Duration start;
  final Duration duration;
}

final class _MutablePairStats {
  _MutablePairStats(this.pair);

  final ChordPair pair;
  int attempts = 0;
  int correctChanges = 0;
  int wrongChordCount = 0;
  int noDetectionCount = 0;
  int unstableCount = 0;
  int insufficientSignalCount = 0;
  bool labelMappingIsLossy = false;
  final delays = <Duration>[];

  void add(ChordChangeMeasurement measurement) {
    attempts++;
    labelMappingIsLossy =
        labelMappingIsLossy || measurement.labelMappingIsLossy;
    switch (measurement.outcome) {
      case ChordChangeOutcome.correct:
        correctChanges++;
        final delay = measurement.recognizedChangeDelay;
        if (delay != null) delays.add(delay);
      case ChordChangeOutcome.wrongChord:
        wrongChordCount++;
      case ChordChangeOutcome.noDetection:
        noDetectionCount++;
      case ChordChangeOutcome.unstable:
        unstableCount++;
      case ChordChangeOutcome.insufficientSignal:
        insufficientSignalCount++;
    }
  }

  ChordPairStats freeze() => ChordPairStats(
    pair: pair,
    attempts: attempts,
    correctChanges: correctChanges,
    wrongChordCount: wrongChordCount,
    noDetectionCount: noDetectionCount,
    unstableCount: unstableCount,
    insufficientSignalCount: insufficientSignalCount,
    recognizedChangeDelays: delays,
    labelMappingIsLossy: labelMappingIsLossy,
  );
}

int _compareSegments(ExpectedChordSegment left, ExpectedChordSegment right) {
  final start = left.start.compareTo(right.start);
  return start == 0 ? left.chord.compareTo(right.chord) : start;
}

int _compareObservations(ChordObservation left, ChordObservation right) {
  final time = left.at.compareTo(right.at);
  if (time != 0) return time;
  if (left.label == right.label) {
    return right.confidence.compareTo(left.confidence);
  }
  if (left.label == null) return -1;
  if (right.label == null) return 1;
  return left.label!.compareTo(right.label!);
}

int _compareVerdicts(PracticeVerdict left, PracticeVerdict right) {
  final time = left.targetAt.compareTo(right.targetAt);
  if (time != 0) return time;
  final leftId = left.targetEventId.compareTo(right.targetEventId);
  if (leftId != 0) return leftId;
  return (left.matchedObservationSequence ?? -1).compareTo(
    right.matchedObservationSequence ?? -1,
  );
}

bool _pairMappingIsLossy(ChordPair pair) =>
    !isCanonicalPracticeChordLabel(pair.from) ||
    !isCanonicalPracticeChordLabel(pair.to);
