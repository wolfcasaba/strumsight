import 'package:meta/meta.dart';

import '../model/practice_metrics.dart';
import '../model/practice_observation.dart';
import '../model/practice_verdict.dart';
import 'practice_event_matcher.dart';

const int _maximumScorePerMille = 1000;
const Duration _windowBeforeTarget = Duration(milliseconds: 120);
const Duration _windowAfterTarget = Duration(milliseconds: 420);
const Duration _defaultChordStableDuration = Duration(milliseconds: 180);

/// The chord evaluation of one compiled target event.
@immutable
final class PracticeChordEventScore {
  const PracticeChordEventScore._({
    required this.targetIndex,
    required this.outcome,
    required this.observedChord,
    required this.scorePerMille,
    required this.insufficientReasonCode,
  });

  final int targetIndex;
  final ChordOutcome outcome;
  final String? observedChord;

  /// Null when chord scoring is unavailable for this target.
  final int? scorePerMille;

  /// Present only for [ChordOutcome.insufficientData].
  final String? insufficientReasonCode;

  double? get score =>
      scorePerMille == null ? null : scorePerMille! / _maximumScorePerMille;
}

/// Event chord evaluations and their attempt-level dimension score.
@immutable
final class PracticeChordScore {
  PracticeChordScore._({
    required List<PracticeChordEventScore> events,
    required this.chordPerMille,
    required this.chord,
  }) : events = List<PracticeChordEventScore>.unmodifiable(events);

  final List<PracticeChordEventScore> events;

  /// Null when [chord] is not available.
  final int? chordPerMille;

  final MetricValue chord;
}

/// Evaluates the longest stable observed chord in each target window.
final class PracticeChordScorer {
  const PracticeChordScorer();

  PracticeChordScore score({
    required List<PracticeEventMatchResult> matches,
    required List<ChordObservation> observations,
    Duration chordStableDuration = _defaultChordStableDuration,
  }) {
    if (chordStableDuration <= Duration.zero) {
      throw ArgumentError.value(
        chordStableDuration,
        'chordStableDuration',
        'must be strictly positive',
      );
    }
    final orderedObservations = observations.toList()
      ..sort((left, right) => left.at.compareTo(right.at));
    final events = <PracticeChordEventScore>[
      for (final match in matches)
        _scoreEvent(
          match: match,
          observations: orderedObservations,
          chordStableDuration: chordStableDuration,
        ),
    ];
    final applicable = events.where(
      (event) => event.outcome != ChordOutcome.notApplicable,
    );
    final measured = applicable.where((event) => event.scorePerMille != null);

    final int? chordPerMille;
    final MetricValue chord;
    if (applicable.isEmpty) {
      chordPerMille = null;
      chord = const MetricNotApplicable();
    } else if (measured.isNotEmpty) {
      final totalPerMille = measured.fold<int>(
        0,
        (sum, event) => sum + event.scorePerMille!,
      );
      chordPerMille = totalPerMille ~/ measured.length;
      chord = MetricAvailable(chordPerMille / _maximumScorePerMille);
    } else {
      chordPerMille = null;
      final reasonCode = observations.isEmpty
          ? PracticeMetricReasonCode.noSignal
          : applicable.any(
              (event) =>
                  event.insufficientReasonCode ==
                  PracticeMetricReasonCode.chordUnstable,
            )
          ? PracticeMetricReasonCode.chordUnstable
          : PracticeMetricReasonCode.insufficientSamples;
      chord = MetricInsufficientData(reasonCode);
    }

    return PracticeChordScore._(
      events: events,
      chordPerMille: chordPerMille,
      chord: chord,
    );
  }

  PracticeChordEventScore _scoreEvent({
    required PracticeEventMatchResult match,
    required List<ChordObservation> observations,
    required Duration chordStableDuration,
  }) {
    final expectedChord = match.target.chord;
    if (expectedChord == null || (match.target.optional && !match.isMatched)) {
      return PracticeChordEventScore._(
        targetIndex: match.targetIndex,
        outcome: ChordOutcome.notApplicable,
        observedChord: null,
        scorePerMille: null,
        insufficientReasonCode: null,
      );
    }

    final windowStart = match.target.time - _windowBeforeTarget;
    final windowEnd = match.target.time + _windowAfterTarget;
    final inWindow = <ChordObservation>[
      for (final observation in observations)
        if (observation.at >= windowStart && observation.at <= windowEnd)
          observation,
    ];
    if (inWindow.isEmpty) {
      return PracticeChordEventScore._(
        targetIndex: match.targetIndex,
        outcome: ChordOutcome.insufficientData,
        observedChord: null,
        scorePerMille: null,
        insufficientReasonCode: PracticeMetricReasonCode.insufficientSamples,
      );
    }
    if (inWindow.every((observation) => observation.label == null)) {
      return PracticeChordEventScore._(
        targetIndex: match.targetIndex,
        outcome: ChordOutcome.noDetection,
        observedChord: null,
        scorePerMille: 0,
        insufficientReasonCode: null,
      );
    }

    _ChordSegment? longest;
    var index = 0;
    while (index < inWindow.length) {
      final label = inWindow[index].label;
      final start = inWindow[index].at;
      var lastSameIndex = index;
      while (lastSameIndex + 1 < inWindow.length &&
          inWindow[lastSameIndex + 1].label == label) {
        lastSameIndex++;
      }
      if (label != null) {
        final end = lastSameIndex + 1 < inWindow.length
            ? inWindow[lastSameIndex + 1].at
            : inWindow[lastSameIndex].at;
        final candidate = _ChordSegment(label: label, duration: end - start);
        if (longest == null || candidate.duration > longest.duration) {
          longest = candidate;
        }
      }
      index = lastSameIndex + 1;
    }

    if (longest == null || longest.duration < chordStableDuration) {
      return PracticeChordEventScore._(
        targetIndex: match.targetIndex,
        outcome: ChordOutcome.insufficientData,
        observedChord: longest?.label,
        scorePerMille: null,
        insufficientReasonCode: PracticeMetricReasonCode.chordUnstable,
      );
    }
    final correct = longest.label == expectedChord;
    return PracticeChordEventScore._(
      targetIndex: match.targetIndex,
      outcome: correct ? ChordOutcome.correct : ChordOutcome.wrong,
      observedChord: longest.label,
      scorePerMille: correct ? _maximumScorePerMille : 0,
      insufficientReasonCode: null,
    );
  }
}

final class _ChordSegment {
  const _ChordSegment({required this.label, required this.duration});

  final String label;
  final Duration duration;
}
