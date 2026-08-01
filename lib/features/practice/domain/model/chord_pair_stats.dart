import 'package:meta/meta.dart';

/// The result assigned to one expected chord transition.
enum ChordChangeOutcome {
  correct('correct'),
  wrongChord('wrongChord'),
  noDetection('noDetection'),
  unstable('unstable'),
  insufficientSignal('insufficientSignal');

  const ChordChangeOutcome(this.code);

  final String code;
}

/// The ordered source and destination labels of a chord transition.
@immutable
final class ChordPair {
  const ChordPair({required this.from, required this.to});

  final String from;
  final String to;

  String get key => '$from->$to';

  List<ChordPairValidationFailure> validate() {
    final failures = <ChordPairValidationFailure>[];
    if (from.isEmpty || to.isEmpty) {
      failures.add(
        const ChordPairValidationFailure(
          code: 'chordPair.label.empty',
          message: 'Chord-pair labels cannot be empty.',
        ),
      );
    }
    if (from == to) {
      failures.add(
        const ChordPairValidationFailure(
          code: 'chordPair.sameLabel',
          message: 'A chord-change pair must contain two different labels.',
        ),
      );
    }
    return List<ChordPairValidationFailure>.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => key;
}

/// One measured expected transition.
@immutable
final class ChordChangeMeasurement {
  const ChordChangeMeasurement({
    required this.pair,
    required this.targetAt,
    required this.outcome,
    this.recognizedChangeDelay,
    this.observedChord,
    this.stableDuration,
    this.labelMappingIsLossy = false,
  });

  final ChordPair pair;
  final Duration targetAt;
  final ChordChangeOutcome outcome;
  final Duration? recognizedChangeDelay;
  final String? observedChord;
  final Duration? stableDuration;
  final bool labelMappingIsLossy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordChangeMeasurement &&
          other.pair == pair &&
          other.targetAt == targetAt &&
          other.outcome == outcome &&
          other.recognizedChangeDelay == recognizedChangeDelay &&
          other.observedChord == observedChord &&
          other.stableDuration == stableDuration &&
          other.labelMappingIsLossy == labelMappingIsLossy;

  @override
  int get hashCode => Object.hash(
    pair,
    targetAt,
    outcome,
    recognizedChangeDelay,
    observedChord,
    stableDuration,
    labelMappingIsLossy,
  );
}

/// A delay metric that keeps insufficient evidence distinct from a duration.
@immutable
sealed class ChordChangeDelayMetric {
  const ChordChangeDelayMetric();
}

@immutable
final class ChordChangeDelayAvailable extends ChordChangeDelayMetric {
  const ChordChangeDelayAvailable(this.value);

  final Duration value;

  @override
  bool operator ==(Object other) =>
      other is ChordChangeDelayAvailable && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

@immutable
final class ChordChangeDelayInsufficientData extends ChordChangeDelayMetric {
  const ChordChangeDelayInsufficientData();

  @override
  bool operator ==(Object other) => other is ChordChangeDelayInsufficientData;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Counts and delay evidence for one directed chord pair.
@immutable
final class ChordPairStats {
  ChordPairStats({
    required this.pair,
    required this.attempts,
    required this.correctChanges,
    required this.wrongChordCount,
    required this.noDetectionCount,
    required this.unstableCount,
    required this.insufficientSignalCount,
    required List<Duration> recognizedChangeDelays,
    this.labelMappingIsLossy = false,
  }) : recognizedChangeDelays = List<Duration>.unmodifiable(
         recognizedChangeDelays,
       );

  final ChordPair pair;
  final int attempts;
  final int correctChanges;
  final int wrongChordCount;
  final int noDetectionCount;
  final int unstableCount;
  final int insufficientSignalCount;
  final List<Duration> recognizedChangeDelays;
  final bool labelMappingIsLossy;

  int get measuredChanges => recognizedChangeDelays.length;

  int get outcomeCount =>
      correctChanges +
      wrongChordCount +
      noDetectionCount +
      unstableCount +
      insufficientSignalCount;

  bool get hasSufficientDelayData => measuredChanges >= 3;

  Duration? get medianRecognizedChangeDelay {
    if (!hasSufficientDelayData) return null;
    final sorted = recognizedChangeDelays.toList()
      ..sort((left, right) => left.compareTo(right));
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    final sum =
        sorted[middle - 1].inMicroseconds + sorted[middle].inMicroseconds;
    return Duration(microseconds: sum ~/ 2);
  }

  ChordChangeDelayMetric get recognizedChangeDelayMetric {
    final median = medianRecognizedChangeDelay;
    return median == null
        ? const ChordChangeDelayInsufficientData()
        : ChordChangeDelayAvailable(median);
  }

  List<ChordPairStatsValidationFailure> validate() {
    final failures = <ChordPairStatsValidationFailure>[
      ...pair.validate().map(
        (failure) => ChordPairStatsValidationFailure(
          code: failure.code,
          message: failure.message,
        ),
      ),
    ];
    if (attempts < 0) {
      failures.add(
        const ChordPairStatsValidationFailure(
          code: 'chordPairStats.attempts.negative',
          message: 'Attempt count cannot be negative.',
        ),
      );
    }
    if (correctChanges < 0 ||
        wrongChordCount < 0 ||
        noDetectionCount < 0 ||
        unstableCount < 0 ||
        insufficientSignalCount < 0) {
      failures.add(
        const ChordPairStatsValidationFailure(
          code: 'chordPairStats.outcomeCount.negative',
          message: 'Outcome counts cannot be negative.',
        ),
      );
    }
    if (outcomeCount != attempts) {
      failures.add(
        const ChordPairStatsValidationFailure(
          code: 'chordPairStats.outcomeCount.mismatch',
          message: 'Outcome counts must add up to attempts.',
        ),
      );
    }
    if (recognizedChangeDelays.any((delay) => delay < Duration.zero)) {
      failures.add(
        const ChordPairStatsValidationFailure(
          code: 'chordPairStats.delay.negative',
          message: 'Recognized-change delays cannot be negative.',
        ),
      );
    }
    if (recognizedChangeDelays.length > correctChanges) {
      failures.add(
        const ChordPairStatsValidationFailure(
          code: 'chordPairStats.delay.countMismatch',
          message: 'Only correct changes may carry a delay.',
        ),
      );
    }
    return List<ChordPairStatsValidationFailure>.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordPairStats &&
          other.pair == pair &&
          other.attempts == attempts &&
          other.correctChanges == correctChanges &&
          other.wrongChordCount == wrongChordCount &&
          other.noDetectionCount == noDetectionCount &&
          other.unstableCount == unstableCount &&
          other.insufficientSignalCount == insufficientSignalCount &&
          _listEquals(other.recognizedChangeDelays, recognizedChangeDelays) &&
          other.labelMappingIsLossy == labelMappingIsLossy;

  @override
  int get hashCode => Object.hash(
    pair,
    attempts,
    correctChanges,
    wrongChordCount,
    noDetectionCount,
    unstableCount,
    insufficientSignalCount,
    Object.hashAll(recognizedChangeDelays),
    labelMappingIsLossy,
  );
}

/// The immutable result of one pure chord-change analysis pass.
@immutable
final class ChordChangeAnalysis {
  ChordChangeAnalysis({
    required List<ChordChangeMeasurement> changes,
    required List<ChordPairStats> pairStats,
  }) : changes = List<ChordChangeMeasurement>.unmodifiable(changes),
       pairStats = List<ChordPairStats>.unmodifiable(pairStats);

  final List<ChordChangeMeasurement> changes;
  final List<ChordPairStats> pairStats;

  ChordPairStats? get slowestPair {
    final measured = pairStats
        .where((stats) => stats.medianRecognizedChangeDelay != null)
        .toList();
    if (measured.isEmpty) return null;
    measured.sort((left, right) {
      final delay = right.medianRecognizedChangeDelay!.compareTo(
        left.medianRecognizedChangeDelay!,
      );
      if (delay != 0) return delay;
      return _comparePairs(left.pair, right.pair);
    });
    return measured.first;
  }

  ChordPairStats? get slowestPairStats => slowestPair;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordChangeAnalysis &&
          _listEquals(other.changes, changes) &&
          _listEquals(other.pairStats, pairStats);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(changes), Object.hashAll(pairStats));
}

@immutable
final class ChordPairValidationFailure {
  const ChordPairValidationFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ChordPairValidationFailure &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

typedef ChordPairStatsValidationFailure = ChordPairValidationFailure;

int compareChordPairs(ChordPair left, ChordPair right) =>
    _comparePairs(left, right);

int _comparePairs(ChordPair left, ChordPair right) {
  final from = left.from.compareTo(right.from);
  return from == 0 ? left.to.compareTo(right.to) : from;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
