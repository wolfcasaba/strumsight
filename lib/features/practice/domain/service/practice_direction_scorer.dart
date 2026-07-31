import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import '../model/practice_metrics.dart';
import '../model/practice_observation.dart';
import '../model/practice_verdict.dart';
import 'practice_event_matcher.dart';

const int _maximumScorePerMille = 1000;

/// The direction evaluation of one compiled target event.
@immutable
final class PracticeDirectionEventScore {
  const PracticeDirectionEventScore._({
    required this.targetIndex,
    required this.outcome,
    required this.observedDirection,
    required this.scorePerMille,
  });

  final int targetIndex;
  final DirectionOutcome outcome;
  final StrumDirection? observedDirection;

  /// Null when direction does not apply to this target.
  final int? scorePerMille;

  double? get score =>
      scorePerMille == null ? null : scorePerMille! / _maximumScorePerMille;
}

/// Event direction evaluations and their attempt-level dimension score.
@immutable
final class PracticeDirectionScore {
  PracticeDirectionScore._({
    required List<PracticeDirectionEventScore> events,
    required this.directionPerMille,
    required this.direction,
  }) : events = List<PracticeDirectionEventScore>.unmodifiable(events);

  final List<PracticeDirectionEventScore> events;

  /// Null when [direction] is not available.
  final int? directionPerMille;

  final MetricValue direction;
}

/// Compares matched strum directions with directional target events.
final class PracticeDirectionScorer {
  const PracticeDirectionScorer();

  PracticeDirectionScore score({
    required List<PracticeEventMatchResult> matches,
    required Map<int, StrumObservation> observationsByTargetIndex,
  }) {
    final events = <PracticeDirectionEventScore>[];
    var applicableCount = 0;
    var correctCount = 0;
    var matchedApplicableCount = 0;

    for (final match in matches) {
      final expected = match.target.direction;
      if (expected == null || (match.target.optional && !match.isMatched)) {
        events.add(
          PracticeDirectionEventScore._(
            targetIndex: match.targetIndex,
            outcome: DirectionOutcome.notApplicable,
            observedDirection: null,
            scorePerMille: null,
          ),
        );
        continue;
      }

      applicableCount++;
      if (!match.isMatched) {
        events.add(
          PracticeDirectionEventScore._(
            targetIndex: match.targetIndex,
            outcome: DirectionOutcome.wrong,
            observedDirection: null,
            scorePerMille: 0,
          ),
        );
        continue;
      }

      matchedApplicableCount++;
      final sequence = match.matchedObservationSequence;
      final observation = observationsByTargetIndex[match.targetIndex];
      if (observation == null) {
        throw StateError(
          'Matched target index ${match.targetIndex} has no strum mapping.',
        );
      }
      if (observation.sequence != sequence) {
        throw StateError(
          'Target index ${match.targetIndex} maps sequence '
          '${observation.sequence}, expected $sequence.',
        );
      }
      final isCorrect = observation.direction == expected;
      if (isCorrect) correctCount++;
      events.add(
        PracticeDirectionEventScore._(
          targetIndex: match.targetIndex,
          outcome: isCorrect
              ? DirectionOutcome.correct
              : DirectionOutcome.wrong,
          observedDirection: observation.direction,
          scorePerMille: isCorrect ? _maximumScorePerMille : 0,
        ),
      );
    }

    final int? directionPerMille;
    final MetricValue direction;
    if (applicableCount == 0) {
      directionPerMille = null;
      direction = const MetricNotApplicable();
    } else if (matchedApplicableCount == 0 &&
        observationsByTargetIndex.isEmpty) {
      directionPerMille = null;
      direction = const MetricInsufficientData(
        PracticeMetricReasonCode.noSignal,
      );
    } else {
      directionPerMille =
          correctCount * _maximumScorePerMille ~/ applicableCount;
      direction = MetricAvailable(directionPerMille / _maximumScorePerMille);
    }

    return PracticeDirectionScore._(
      events: events,
      directionPerMille: directionPerMille,
      direction: direction,
    );
  }
}
