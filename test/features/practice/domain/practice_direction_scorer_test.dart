import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_direction_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

void main() {
  test('PracticeMetricReasonCode pins the complete stable code set', () {
    const expected = <String>{
      'practice.metric.no_signal',
      'practice.metric.no_applicable_targets',
      'practice.metric.chord_unstable',
      'practice.metric.insufficient_samples',
    };

    expect({
      PracticeMetricReasonCode.noSignal,
      PracticeMetricReasonCode.noApplicableTargets,
      PracticeMetricReasonCode.chordUnstable,
      PracticeMetricReasonCode.insufficientSamples,
    }, expected);
    expect(PracticeMetricReasonCode.values, expected);
  });

  group('PracticeDirectionScorer A2 matrix', () {
    test('matched equal direction is correct and worth 1000 per mille', () {
      final fixture = _matchedFixture(
        expected: StrumDirection.down,
        observed: StrumDirection.down,
      );

      final score = const PracticeDirectionScorer().score(
        matches: fixture.matcher.results,
        observationsByTargetIndex: {0: fixture.observation},
      );

      expect(score.events.single.outcome, DirectionOutcome.correct);
      expect(score.events.single.observedDirection, StrumDirection.down);
      expect(score.events.single.scorePerMille, 1000);
      expect(score.directionPerMille, 1000);
      expect(score.direction, const MetricAvailable(1));
    });

    test('matched different direction is wrong and worth zero', () {
      final fixture = _matchedFixture(
        expected: StrumDirection.down,
        observed: StrumDirection.up,
      );

      final score = const PracticeDirectionScorer().score(
        matches: fixture.matcher.results,
        observationsByTargetIndex: {0: fixture.observation},
      );

      expect(score.events.single.outcome, DirectionOutcome.wrong);
      expect(score.events.single.observedDirection, StrumDirection.up);
      expect(score.events.single.scorePerMille, 0);
      expect(score.directionPerMille, 0);
      expect(score.direction, const MetricAvailable(0));
    });

    test('unmatched directional target is wrong when signal existed', () {
      final matcher = _matcher(expectedDirections: const [StrumDirection.down])
        ..finalize();
      final unrelated = _observation(
        at: const Duration(seconds: 10),
        sequence: 9,
        direction: StrumDirection.down,
      );

      final score = const PracticeDirectionScorer().score(
        matches: matcher.results,
        observationsByTargetIndex: {9: unrelated},
      );

      expect(score.events.single.outcome, DirectionOutcome.wrong);
      expect(score.events.single.observedDirection, isNull);
      expect(score.directionPerMille, 0);
      expect(score.direction, const MetricAvailable(0));
    });

    for (final matched in [true, false]) {
      test('target without direction is not applicable when '
          '${matched ? 'matched' : 'unmatched'}', () {
        final matcher = _matcher(expectedDirections: const [null]);
        final observation = _observation(
          at: const Duration(seconds: 1),
          direction: StrumDirection.up,
        );
        if (matched) {
          matcher.registerStrum(observation);
        } else {
          matcher.finalize();
        }

        final score = const PracticeDirectionScorer().score(
          matches: matcher.results,
          observationsByTargetIndex: matched ? {0: observation} : const {},
        );

        expect(score.events.single.outcome, DirectionOutcome.notApplicable);
        expect(score.events.single.scorePerMille, isNull);
        expect(score.directionPerMille, isNull);
        expect(score.direction, const MetricNotApplicable());
      });
    }

    test(
      'directional targets with zero strum signal are insufficient data',
      () {
        final matcher = _matcher(
          expectedDirections: const [StrumDirection.down],
        )..finalize();

        final score = const PracticeDirectionScorer().score(
          matches: matcher.results,
          observationsByTargetIndex: const {},
        );

        expect(score.events.single.outcome, DirectionOutcome.wrong);
        expect(score.directionPerMille, isNull);
        expect(
          score.direction,
          const MetricInsufficientData(PracticeMetricReasonCode.noSignal),
        );
      },
    );
  });

  group('PracticeDirectionScorer input and aggregation', () {
    test('fails fast when a matched sequence has no observation mapping', () {
      final fixture = _matchedFixture(
        expected: StrumDirection.down,
        observed: StrumDirection.down,
      );

      expect(
        () => const PracticeDirectionScorer().score(
          matches: fixture.matcher.results,
          observationsByTargetIndex: const {},
        ),
        throwsStateError,
      );
    });

    test('uses integer accumulation and one truncating division', () {
      final matcher = _matcher(
        expectedDirections: const [
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
        ],
      );
      final observations = <int, StrumObservation>{};
      for (var index = 0; index < 3; index++) {
        final observation = _observation(
          at: Duration(seconds: index + 1),
          sequence: index,
          direction: index < 2 ? StrumDirection.down : StrumDirection.up,
        );
        observations[index] = observation;
        matcher.registerStrum(observation);
      }

      final score = const PracticeDirectionScorer().score(
        matches: matcher.results,
        observationsByTargetIndex: observations,
      );

      expect(score.directionPerMille, 666);
      expect(score.direction, const MetricAvailable(0.666));
    });

    for (final finalized in [false, true]) {
      test('${finalized ? 'finalized' : 'open'} unmatched optional direction '
          'target does not dilute the metric', () {
        final matcher = _matcher(
          expectedDirections: const [StrumDirection.down, StrumDirection.down],
          optionalIndices: const {1},
        );
        final observation = _observation(at: const Duration(seconds: 1));
        matcher.registerStrum(observation);
        if (finalized) matcher.finalize();

        final score = const PracticeDirectionScorer().score(
          matches: matcher.results,
          observationsByTargetIndex: {0: observation},
        );

        expect(score.events[1].outcome, DirectionOutcome.notApplicable);
        expect(score.directionPerMille, 1000);
      });
    }

    test('target-index pairing supports restarted observation sequences', () {
      final matcher = _matcher(
        expectedDirections: const [StrumDirection.down, StrumDirection.down],
      );
      final first = _observation(at: const Duration(seconds: 1));
      final afterRestart = _observation(
        at: const Duration(seconds: 2),
        direction: StrumDirection.up,
      );
      matcher.registerStrum(first);
      matcher.registerStrum(afterRestart);

      final score = const PracticeDirectionScorer().score(
        matches: matcher.results,
        observationsByTargetIndex: {0: first, 1: afterRestart},
      );

      expect(first.sequence, 0);
      expect(afterRestart.sequence, 0);
      expect(score.events[0].outcome, DirectionOutcome.correct);
      expect(score.events[1].outcome, DirectionOutcome.wrong);
      expect(score.directionPerMille, 500);
    });

    test('fails fast when a target mapping carries the wrong sequence', () {
      final fixture = _matchedFixture(
        expected: StrumDirection.down,
        observed: StrumDirection.down,
      );
      final wrongSequence = _observation(
        at: fixture.observation.at,
        sequence: 99,
      );

      expect(
        () => const PracticeDirectionScorer().score(
          matches: fixture.matcher.results,
          observationsByTargetIndex: {0: wrongSequence},
        ),
        throwsStateError,
      );
    });

    test('the event-score view rejects mutation', () {
      final matcher = _matcher(expectedDirections: const [null])..finalize();
      final score = const PracticeDirectionScorer().score(
        matches: matcher.results,
        observationsByTargetIndex: const {},
      );

      expect(
        () => score.events.add(score.events.single),
        throwsUnsupportedError,
      );
    });
  });
}

({PracticeEventMatcher matcher, StrumObservation observation}) _matchedFixture({
  required StrumDirection expected,
  required StrumDirection observed,
}) {
  final matcher = _matcher(expectedDirections: [expected]);
  final observation = _observation(
    at: const Duration(seconds: 1),
    direction: observed,
  );
  matcher.registerStrum(observation);
  return (matcher: matcher, observation: observation);
}

PracticeEventMatcher _matcher({
  required List<StrumDirection?> expectedDirections,
  Set<int> optionalIndices = const {},
}) => PracticeEventMatcher(
  target: _target(expectedDirections, optionalIndices),
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: Duration.zero,
);

StrumObservation _observation({
  required Duration at,
  int sequence = 0,
  StrumDirection direction = StrumDirection.down,
}) => StrumObservation(
  at: at,
  sequence: sequence,
  direction: direction,
  confidence: 1,
);

CompiledPracticeTarget _target(
  List<StrumDirection?> expectedDirections,
  Set<int> optionalIndices,
) => CompiledPracticeTarget(
  definitionId: 'direction-test',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: [
    for (var index = 0; index < expectedDirections.length; index++)
      CompiledTargetEvent(
        sourceEventId: 'event-$index',
        loopIndex: 0,
        position: BeatPosition.fromTicks(index),
        time: Duration(seconds: index + 1),
        barIndex: 0,
        chord: null,
        direction: expectedDirections[index],
        accent: false,
        optional: optionalIndices.contains(index),
      ),
  ],
  musicalDuration: Duration(seconds: expectedDirections.length + 1),
  ringOutDuration: Duration.zero,
  totalDuration: Duration(seconds: expectedDirections.length + 1),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: expectedDirections.isNotEmpty,
);
