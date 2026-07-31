import 'package:meta/meta.dart';

import '../model/practice_attempt_result.dart';
import '../model/practice_metrics.dart';
import '../model/practice_verdict.dart';
import '../model/scoring_profile.dart';
import 'practice_chord_scorer.dart';
import 'practice_direction_scorer.dart';
import 'practice_event_matcher.dart';
import 'practice_timing_scorer.dart';

const int _maximumScorePerMille = 1000;

/// Immutable verdict and metric output of one practice scoring pass.
@immutable
final class PracticeScoreAggregation {
  PracticeScoreAggregation._({
    required this.metrics,
    required List<PracticeVerdict> verdicts,
    required this.outcome,
    required this.overallPerMille,
  }) : verdicts = List<PracticeVerdict>.unmodifiable(verdicts);

  final PracticeMetrics metrics;
  final List<PracticeVerdict> verdicts;
  final PracticeAttemptOutcome outcome;

  /// Null when [metrics.overall] is not available.
  final int? overallPerMille;
}

/// Combines independently scored dimensions without re-matching observations.
final class PracticeScoreAggregator {
  const PracticeScoreAggregator();

  PracticeScoreAggregation aggregate({
    required List<PracticeEventMatchResult> matches,
    required ScoringProfile scoringProfile,
    required PracticeTimingScore timing,
    required PracticeDirectionScore direction,
    required PracticeChordScore chord,
  }) {
    _requireAlignedScores(
      matches: matches,
      timing: timing,
      direction: direction,
      chord: chord,
    );

    final requiredMatches = matches.where((match) => !match.target.optional);
    final totalTargets = requiredMatches.length;
    final resolvedTargets = requiredMatches
        .where((match) => match.isResolved)
        .length;
    final int? completionPerMille = totalTargets == 0
        ? null
        : resolvedTargets * _maximumScorePerMille ~/ totalTargets;
    final completion = completionPerMille == null
        ? const MetricNotApplicable()
        : MetricAvailable(completionPerMille / _maximumScorePerMille);

    var weightedScoreTotal = 0;
    var availableWeightTotal = 0;
    for (final entry in scoringProfile.weights.entries) {
      if (entry.value <= 0) continue;
      final dimensionScore = switch (entry.key) {
        PracticeScoreDimension.rhythm => timing.rhythmPerMille,
        PracticeScoreDimension.direction => direction.directionPerMille,
        PracticeScoreDimension.chord => chord.chordPerMille,
        _ => null,
      };
      if (dimensionScore == null) continue;
      weightedScoreTotal += entry.value * dimensionScore;
      availableWeightTotal += entry.value;
    }
    final int? overallPerMille = availableWeightTotal == 0
        ? null
        : weightedScoreTotal ~/ availableWeightTotal;
    final overall = overallPerMille == null
        ? const MetricNotApplicable()
        : MetricAvailable(overallPerMille / _maximumScorePerMille);

    final comboScore = _scoreComboAndPoints(
      matches: matches,
      scoringProfile: scoringProfile,
      timing: timing,
      direction: direction,
      chord: chord,
    );
    final metrics = PracticeMetrics(
      completion: completion,
      rhythm: timing.rhythm,
      direction: direction.direction,
      chord: chord.chord,
      overall: overall,
      totalTargets: totalTargets,
      resolvedTargets: resolvedTargets,
      maxCombo: comboScore.maxCombo,
      scorePoints: comboScore.points,
      meanAbsoluteOffset: timing.meanAbsoluteOffset,
      timingBias: timing.timingBias,
    );
    final verdicts = <PracticeVerdict>[
      for (var index = 0; index < matches.length; index++)
        _verdict(
          match: matches[index],
          timing: timing.events[index],
          direction: direction.events[index],
          chord: chord.events[index],
          scoringProfile: scoringProfile,
        ),
    ];
    final outcome = _outcome(
      totalTargets: totalTargets,
      resolvedTargets: resolvedTargets,
      completionPerMille: completionPerMille,
      overallPerMille: overallPerMille,
      scoringProfile: scoringProfile,
    );

    return PracticeScoreAggregation._(
      metrics: metrics,
      verdicts: verdicts,
      outcome: outcome,
      overallPerMille: overallPerMille,
    );
  }
}

({int points, int maxCombo}) _scoreComboAndPoints({
  required List<PracticeEventMatchResult> matches,
  required ScoringProfile scoringProfile,
  required PracticeTimingScore timing,
  required PracticeDirectionScore direction,
  required PracticeChordScore chord,
}) {
  var combo = 0;
  var maxCombo = 0;
  var points = 0;

  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    if (match.target.optional) continue;
    if (!match.isMatched) {
      combo = 0;
      continue;
    }

    var hasAvailableWeightedDimension = false;
    var isWrong = false;
    if (_hasWeight(scoringProfile, PracticeScoreDimension.rhythm)) {
      hasAvailableWeightedDimension = true;
    }
    if (_hasWeight(scoringProfile, PracticeScoreDimension.direction)) {
      final directionPerMille = direction.events[index].scorePerMille;
      if (directionPerMille != null) {
        hasAvailableWeightedDimension = true;
        if (directionPerMille == 0) isWrong = true;
      }
    }
    if (_hasWeight(scoringProfile, PracticeScoreDimension.chord)) {
      final chordPerMille = chord.events[index].scorePerMille;
      if (chordPerMille != null) {
        hasAvailableWeightedDimension = true;
        if (chordPerMille == 0) isWrong = true;
      }
    }
    if (isWrong) {
      combo = 0;
      continue;
    }
    if (!hasAvailableWeightedDimension) continue;

    combo++;
    if (combo > maxCombo) maxCombo = combo;
    final basePoints = switch (timing.events[index].grade) {
      TimingGrade.perfect => 100,
      TimingGrade.good => 70,
      TimingGrade.early || TimingGrade.late => 40,
      TimingGrade.missed || TimingGrade.notApplicable => throw StateError(
        'A matched required target must have an applicable timing grade.',
      ),
    };
    points += basePoints * _comboMultiplier(combo);
  }
  return (points: points, maxCombo: maxCombo);
}

PracticeVerdict _verdict({
  required PracticeEventMatchResult match,
  required PracticeTimingEventScore timing,
  required PracticeDirectionEventScore direction,
  required PracticeChordEventScore chord,
  required ScoringProfile scoringProfile,
}) {
  final optionalUnmatched = match.target.optional && !match.isMatched;
  final missReasonCode = !match.isMatched && !optionalUnmatched
      ? PracticeMetricReasonCode.noSignal
      : null;
  final String? coachingCode;
  if (optionalUnmatched) {
    coachingCode = null;
  } else if (!match.isMatched) {
    coachingCode = PracticeCoachingCode.noSignal;
  } else if (direction.outcome == DirectionOutcome.wrong) {
    coachingCode = PracticeCoachingCode.wrongDirection;
  } else if (chord.outcome == ChordOutcome.noDetection) {
    coachingCode = PracticeCoachingCode.noSignal;
  } else if (chord.outcome == ChordOutcome.insufficientData) {
    coachingCode =
        chord.insufficientReasonCode == PracticeMetricReasonCode.noSignal
        ? PracticeCoachingCode.noSignal
        : PracticeCoachingCode.chordNotStable;
  } else {
    coachingCode = switch (timing.grade) {
      TimingGrade.early => PracticeCoachingCode.early,
      TimingGrade.late => PracticeCoachingCode.late,
      _ => null,
    };
  }

  final weightedWrongDirection =
      _hasWeight(scoringProfile, PracticeScoreDimension.direction) &&
      direction.outcome == DirectionOutcome.wrong;
  final weightedWrongChord =
      _hasWeight(scoringProfile, PracticeScoreDimension.chord) &&
      (chord.outcome == ChordOutcome.wrong ||
          chord.outcome == ChordOutcome.noDetection);
  final suppressTimingVerdict =
      match.isMatched && (weightedWrongDirection || weightedWrongChord);

  return PracticeVerdict(
    targetEventId: '${match.target.sourceEventId}@${match.target.loopIndex}',
    matchedObservationSequence: match.matchedObservationSequence,
    targetAt: match.target.time,
    observedAt: match.observedAt,
    timingOffset: match.timingOffset,
    timingGrade: suppressTimingVerdict
        ? TimingGrade.notApplicable
        : timing.grade,
    expectedDirection: match.target.direction,
    observedDirection: direction.observedDirection,
    directionOutcome: direction.outcome,
    expectedChord: match.target.chord,
    observedChord: chord.observedChord,
    chordOutcome: chord.outcome,
    eventScore: suppressTimingVerdict ? 0 : timing.score,
    missReasonCode: missReasonCode,
    coachingCode: coachingCode,
  );
}

PracticeAttemptOutcome _outcome({
  required int totalTargets,
  required int resolvedTargets,
  required int? completionPerMille,
  required int? overallPerMille,
  required ScoringProfile scoringProfile,
}) {
  if (totalTargets == 0 || scoringProfile.weights.isEmpty) {
    return PracticeAttemptOutcome.notScored;
  }
  if (resolvedTargets == 0) return PracticeAttemptOutcome.incomplete;
  if (completionPerMille == null || overallPerMille == null) {
    return PracticeAttemptOutcome.notScored;
  }
  final passed =
      completionPerMille >= scoringProfile.completionThresholdPercent * 10 &&
      overallPerMille >= scoringProfile.overallThresholdPercent * 10;
  return passed ? PracticeAttemptOutcome.passed : PracticeAttemptOutcome.failed;
}

void _requireAlignedScores({
  required List<PracticeEventMatchResult> matches,
  required PracticeTimingScore timing,
  required PracticeDirectionScore direction,
  required PracticeChordScore chord,
}) {
  if (timing.events.length != matches.length ||
      direction.events.length != matches.length ||
      chord.events.length != matches.length) {
    throw StateError('Dimension event scores must align with matcher results.');
  }
  for (var index = 0; index < matches.length; index++) {
    if (matches[index].targetIndex != index ||
        timing.events[index].targetIndex != index ||
        direction.events[index].targetIndex != index ||
        chord.events[index].targetIndex != index) {
      throw StateError('Dimension event scores are not in target order.');
    }
  }
}

bool _hasWeight(
  ScoringProfile scoringProfile,
  PracticeScoreDimension dimension,
) => (scoringProfile.weights[dimension] ?? 0) > 0;

int _comboMultiplier(int combo) => combo >= 20
    ? 4
    : combo >= 10
    ? 3
    : combo >= 5
    ? 2
    : 1;
