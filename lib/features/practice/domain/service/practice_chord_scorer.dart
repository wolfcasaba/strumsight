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
    required this.recognitionCoverage,
  }) : events = List<PracticeChordEventScore>.unmodifiable(events);

  final List<PracticeChordEventScore> events;

  /// Null when [chord] is not available.
  final int? chordPerMille;

  final MetricValue chord;

  /// How much of what the recognizer said it could actually stand behind —
  /// evidence-bearing chord observations ÷ all chord observations, reported
  /// ALONGSIDE the score and never folded into it (E14-R38, ADR 0551 D5).
  ///
  /// This is the honest home for abstention: a session where the app was
  /// unsure half the time gets the SAME score as one where it was sure, and
  /// says so here instead of quietly marking the player wrong. It is
  /// [MetricNotApplicable] when no chord observation was made at all — zero
  /// observations have no coverage, and reporting `0.0` would claim the
  /// recognizer failed when it was simply never asked.
  final MetricValue recognitionCoverage;
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
    // Coverage is measured over EVERY observation, evidence-bearing or not —
    // that ratio is the whole point (ADR 0551 D5). The scoring below then
    // sees only the evidence-bearing ones.
    final measuredCount = orderedObservations
        .where((observation) => observation.evidence.isEvidence)
        .length;
    final recognitionCoverage = orderedObservations.isEmpty
        ? const MetricNotApplicable()
        : MetricAvailable(measuredCount / orderedObservations.length);
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
          // "The app was unsure" outranks "you were unsteady": when both
          // appear, naming the recognizer's own abstention is the honest
          // headline, and it is the one the correction loop can act on.
          : applicable.any(
              (event) =>
                  event.insufficientReasonCode ==
                  PracticeMetricReasonCode.chordUncertain,
            )
          ? PracticeMetricReasonCode.chordUncertain
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
      recognitionCoverage: recognitionCoverage,
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
    // E14-R38 (ADR 0551 D3): only evidence-bearing readings may decide this
    // target. The recognizer having SAID something it does not stand behind
    // is not the player playing the wrong chord — it is the app abstaining,
    // and the outcome says exactly that. Note the consequence, which is
    // deliberate: an abstained frame in the middle of a held chord no longer
    // splits that chord's stable run, because the app never actually
    // observed a change there.
    final evidence = <ChordObservation>[
      for (final observation in inWindow)
        if (observation.evidence.isEvidence) observation,
    ];
    if (evidence.isEmpty) {
      return PracticeChordEventScore._(
        targetIndex: match.targetIndex,
        outcome: ChordOutcome.insufficientData,
        observedChord: null,
        scorePerMille: null,
        insufficientReasonCode: PracticeMetricReasonCode.chordUncertain,
      );
    }
    if (evidence.every((observation) => observation.label == null)) {
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
    while (index < evidence.length) {
      final label = evidence[index].label;
      final start = evidence[index].at;
      var lastSameIndex = index;
      while (lastSameIndex + 1 < evidence.length &&
          evidence[lastSameIndex + 1].label == label) {
        lastSameIndex++;
      }
      if (label != null) {
        final end = lastSameIndex + 1 < evidence.length
            ? evidence[lastSameIndex + 1].at
            : evidence[lastSameIndex].at;
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
