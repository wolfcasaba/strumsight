import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_chord_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_direction_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';
import 'package:strumsight/features/practice/domain/service/practice_score_aggregator.dart';
import 'package:strumsight/features/practice/domain/service/practice_timing_scorer.dart';

const _gateProfile = ScoringProfile(
  id: 'aggregator-gate-test',
  matchWindow: Duration(milliseconds: 280),
  perfectWindow: Duration(milliseconds: 50),
  goodWindow: Duration(milliseconds: 120),
  extraStrumPolicy: ExtraStrumPolicy.ignore,
  weights: {PracticeScoreDimension.rhythm: 100},
  completionThresholdPercent: 85,
  overallThresholdPercent: 70,
);

void main() {
  group('PracticeScoreAggregator A4 available-dimension weighting', () {
    test('does not fill an unavailable chord dimension with zero', () {
      final fixture = _fixture(
        eventCount: 1,
        directions: const [StrumDirection.down],
        matchedOffsetsMicroseconds: const {0: 0},
        observedDirections: const {0: StrumDirection.down},
      );

      final aggregation = _aggregate(
        fixture,
        ScoringProfile.chordProgressionDefault,
      );

      expect(aggregation.metrics.rhythm, const MetricAvailable(1));
      expect(aggregation.metrics.direction, const MetricAvailable(1));
      expect(aggregation.metrics.chord, const MetricNotApplicable());
      expect(aggregation.overallPerMille, 1000);
      expect(aggregation.metrics.overall, const MetricAvailable(1));
    });

    test('pins every integer overall table cell', () {
      final legacy = _fixture(
        eventCount: 2,
        directions: const [StrumDirection.down, StrumDirection.down],
        matchedOffsetsMicroseconds: const {0: 0, 1: 226667},
        observedDirections: const {
          0: StrumDirection.down,
          1: StrumDirection.up,
        },
      );
      final progression = _fixture(
        eventCount: 9,
        directions: const [
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
          StrumDirection.down,
        ],
        matchedOffsetsMicroseconds: const {
          0: 280000,
          1: 280000,
          2: 280000,
          3: 280000,
          4: 280000,
          5: 191112,
          6: 174400,
        },
        observedDirections: const {
          0: StrumDirection.down,
          1: StrumDirection.down,
          2: StrumDirection.down,
          3: StrumDirection.down,
          4: StrumDirection.down,
          5: StrumDirection.down,
          6: StrumDirection.down,
        },
      );
      final chordChange = _fixture(
        eventCount: 10,
        directions: const [
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
        ],
        chords: const ['G', 'G', 'G', 'G', 'G', 'G', 'G', 'G', 'G', 'G'],
        matchedOffsetsMicroseconds: const {
          0: 191112,
          1: 191112,
          2: 191112,
          3: 191112,
          4: 191112,
          5: 191112,
          6: 191112,
          7: 191112,
          8: 191112,
          9: 191112,
        },
        chordLabels: const ['G', 'G', 'G', 'G', 'G', 'G', 'G', 'G', 'G', 'C'],
      );
      final rhythmOnly = _fixture(
        eventCount: 1,
        directions: const [null],
        matchedOffsetsMicroseconds: const {0: 176178},
      );

      final legacyAggregation = _aggregate(
        legacy,
        ScoringProfile.legacyLearnParity,
      );
      final progressionAggregation = _aggregate(
        progression,
        ScoringProfile.chordProgressionDefault,
      );
      final chordChangeAggregation = _aggregate(
        chordChange,
        ScoringProfile.chordChangeDefault,
      );
      final rhythmOnlyAggregation = _aggregate(
        rhythmOnly,
        ScoringProfile.rhythmOnlyDefault,
      );

      expect(legacyAggregation.metrics.rhythm, const MetricAvailable(0.75));
      expect(legacyAggregation.metrics.direction, const MetricAvailable(0.5));
      expect(legacyAggregation.overallPerMille, 637);
      expect(
        progressionAggregation.metrics.rhythm,
        const MetricAvailable(0.333),
      );
      expect(
        progressionAggregation.metrics.direction,
        const MetricAvailable(0.777),
      );
      expect(progressionAggregation.overallPerMille, 503);
      expect(chordChangeAggregation.metrics.rhythm, const MetricAvailable(0.6));
      expect(chordChangeAggregation.metrics.chord, const MetricAvailable(0.9));
      expect(chordChangeAggregation.overallPerMille, 780);
      expect(
        rhythmOnlyAggregation.metrics.rhythm,
        const MetricAvailable(0.642),
      );
      expect(rhythmOnlyAggregation.overallPerMille, 642);
    });

    test('free practice has no overall score', () {
      final fixture = _fixture(
        eventCount: 1,
        directions: const [StrumDirection.down],
        matchedOffsetsMicroseconds: const {0: 0},
        observedDirections: const {0: StrumDirection.down},
      );

      final aggregation = _aggregate(fixture, ScoringProfile.freePracticeOpen);

      expect(aggregation.overallPerMille, isNull);
      expect(aggregation.metrics.overall, const MetricNotApplicable());
      expect(aggregation.outcome, PracticeAttemptOutcome.notScored);
    });
  });

  group('PracticeScoreAggregator A5 completion and pass gate', () {
    for (final resolved in const [16, 17, 18]) {
      for (final overallPerMille in const [699, 700]) {
        test('$resolved of 20 resolved and $overallPerMille overall', () {
          final aggregation = _gateAggregation(
            resolved: resolved,
            requestedOverallPerMille: overallPerMille,
          );
          final expectedCompletion = resolved * 1000 ~/ 20;
          final expectedOutcome =
              expectedCompletion >= 850 && overallPerMille >= 700
              ? PracticeAttemptOutcome.passed
              : PracticeAttemptOutcome.failed;

          expect(aggregation.metrics.totalTargets, 20);
          expect(aggregation.metrics.resolvedTargets, resolved);
          expect(
            aggregation.metrics.completion,
            MetricAvailable(expectedCompletion / 1000),
          );
          expect(aggregation.overallPerMille, overallPerMille);
          expect(aggregation.outcome, expectedOutcome);
        });
      }
    }

    test('zero resolved targets is incomplete rather than failed', () {
      final fixture = _fixture(
        eventCount: 20,
        directions: List<StrumDirection?>.filled(20, null),
        finalize: false,
      );

      final aggregation = _aggregate(fixture, _gateProfile);

      expect(aggregation.metrics.resolvedTargets, 0);
      expect(aggregation.metrics.completion, const MetricAvailable(0));
      expect(aggregation.metrics.overall, const MetricNotApplicable());
      expect(aggregation.outcome, PracticeAttemptOutcome.incomplete);
    });

    for (final optionalMatched in [false, true]) {
      test('${optionalMatched ? 'matched' : 'unmatched'} optional target is '
          'excluded from completion counters', () {
        final fixture = _fixture(
          eventCount: 3,
          directions: const [null, null, null],
          optionalIndices: const {2},
          matchedOffsetsMicroseconds: optionalMatched
              ? const {0: 0, 1: 0, 2: 0}
              : const {0: 0, 1: 0},
        );

        final aggregation = _aggregate(fixture, _gateProfile);

        expect(aggregation.metrics.totalTargets, 2);
        expect(aggregation.metrics.resolvedTargets, 2);
        expect(aggregation.metrics.completion, const MetricAvailable(1));
      });
    }
  });

  test('A6 increments combo before the fifth-hit multiplier', () {
    final fixture = _fixture(
      eventCount: 8,
      directions: const [
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
      ],
      optionalIndices: const {4},
      matchedOffsetsMicroseconds: const {0: 0, 1: 0, 2: 0, 3: 0, 5: 0, 6: 0},
      observedDirections: const {
        0: StrumDirection.down,
        1: StrumDirection.down,
        2: StrumDirection.down,
        3: StrumDirection.down,
        5: StrumDirection.down,
        6: StrumDirection.up,
      },
    );

    final aggregation = _aggregate(fixture, ScoringProfile.legacyLearnParity);

    expect(
      fixture.matcher.results[4].resolution,
      PracticeTargetResolution.optionalUnmatched,
    );
    expect(fixture.matcher.results[6].isMatched, isTrue);
    expect(fixture.matcher.results[7].isMissed, isTrue);
    expect(aggregation.metrics.scorePoints, 600);
    expect(aggregation.metrics.maxCombo, 5);
    expect(aggregation.verdicts[6].directionOutcome, DirectionOutcome.wrong);
    expect(aggregation.verdicts[6].timingGrade, TimingGrade.notApplicable);
    expect(aggregation.verdicts[6].eventScore, 0);
  });

  group('A6 combo resets and optional isolation', () {
    test('a wrong direction resets before the next clean hit', () {
      final fixture = _fixture(
        eventCount: 6,
        directions: List<StrumDirection?>.filled(6, StrumDirection.down),
        matchedOffsetsMicroseconds: const {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        observedDirections: const {4: StrumDirection.up},
      );

      final aggregation = _aggregate(fixture, ScoringProfile.legacyLearnParity);

      expect(aggregation.verdicts[4].directionOutcome, DirectionOutcome.wrong);
      expect(aggregation.metrics.scorePoints, 500);
      expect(aggregation.metrics.maxCombo, 4);
    });

    test('a miss resets before the next clean hit', () {
      final fixture = _fixture(
        eventCount: 6,
        directions: List<StrumDirection?>.filled(6, StrumDirection.down),
        matchedOffsetsMicroseconds: const {0: 0, 1: 0, 2: 0, 3: 0, 5: 0},
      );

      final aggregation = _aggregate(fixture, ScoringProfile.legacyLearnParity);

      expect(fixture.matcher.results[4].isMissed, isTrue);
      expect(aggregation.metrics.scorePoints, 500);
      expect(aggregation.metrics.maxCombo, 4);
    });

    for (final optionalDirection in const [
      StrumDirection.down,
      StrumDirection.up,
    ]) {
      test('matched ${optionalDirection.name} optional target neither '
          'increments nor resets combo', () {
        final fixture = _fixture(
          eventCount: 6,
          directions: List<StrumDirection?>.filled(6, StrumDirection.down),
          optionalIndices: const {4},
          matchedOffsetsMicroseconds: const {
            0: 0,
            1: 0,
            2: 0,
            3: 0,
            4: 0,
            5: 0,
          },
          observedDirections: {4: optionalDirection},
        );

        final aggregation = _aggregate(
          fixture,
          ScoringProfile.legacyLearnParity,
        );

        expect(fixture.matcher.results[4].isMatched, isTrue);
        expect(aggregation.metrics.scorePoints, 600);
        expect(aggregation.metrics.maxCombo, 5);
      });
    }
  });

  test('A8 every verdict and the complete attempt result are valid', () {
    final fixture = _fixture(
      eventCount: 3,
      directions: const [
        StrumDirection.down,
        StrumDirection.down,
        StrumDirection.down,
      ],
      matchedOffsetsMicroseconds: const {0: -200000, 1: 0},
      observedDirections: const {0: StrumDirection.down, 1: StrumDirection.up},
      sourceEventIds: const ['repeat', 'repeat', 'repeat'],
      loopIndexes: const [0, 1, 2],
    );
    final aggregation = _aggregate(fixture, ScoringProfile.legacyLearnParity);
    final attempt = PracticeAttemptResult(
      index: 0,
      tempo: const Tempo(120),
      metrics: aggregation.metrics,
      verdicts: aggregation.verdicts,
      outcome: aggregation.outcome,
    );

    for (final verdict in aggregation.verdicts) {
      expect(verdict.validate(), isEmpty, reason: verdict.targetEventId);
    }
    expect(aggregation.verdicts.map((verdict) => verdict.targetEventId), const [
      'repeat@0',
      'repeat@1',
      'repeat@2',
    ]);
    expect(attempt.validate(), isEmpty);
    expect(
      () => aggregation.verdicts.add(aggregation.verdicts.first),
      throwsUnsupportedError,
    );
  });
}

PracticeScoreAggregation _gateAggregation({
  required int resolved,
  required int requestedOverallPerMille,
}) {
  final offsets = <int, int>{
    for (var index = 0; index < 12; index++) index: 0,
    for (var index = 12; index < 15; index++) index: 226667,
    15: requestedOverallPerMille == 700 ? 226667 : 233778,
  };
  final fixture = _fixture(
    eventCount: 20,
    directions: List<StrumDirection?>.filled(20, null),
    matchedOffsetsMicroseconds: offsets,
    finalize: false,
  );
  if (resolved > 16) {
    fixture.matcher.advance(
      _eventTime(resolved - 1) +
          _gateProfile.matchWindow +
          const Duration(microseconds: 1),
    );
  }
  return _aggregate(fixture, _gateProfile);
}

PracticeScoreAggregation _aggregate(
  _ScoringFixture fixture,
  ScoringProfile profile,
) {
  final timing = const PracticeTimingScorer().score(
    matches: fixture.matcher.results,
    scoringProfile: profile,
  );
  final direction = const PracticeDirectionScorer().score(
    matches: fixture.matcher.results,
    observationsByTargetIndex: fixture.observationsByTargetIndex,
  );
  final chord = const PracticeChordScorer().score(
    matches: fixture.matcher.results,
    observations: fixture.chordObservations,
  );
  return const PracticeScoreAggregator().aggregate(
    matches: fixture.matcher.results,
    scoringProfile: profile,
    timing: timing,
    direction: direction,
    chord: chord,
  );
}

_ScoringFixture _fixture({
  required int eventCount,
  required List<StrumDirection?> directions,
  List<String?>? chords,
  Set<int> optionalIndices = const {},
  Map<int, int> matchedOffsetsMicroseconds = const {},
  Map<int, StrumDirection> observedDirections = const {},
  List<String?>? chordLabels,
  List<String>? sourceEventIds,
  List<int>? loopIndexes,
  bool finalize = true,
}) {
  final target = _target(
    eventCount: eventCount,
    directions: directions,
    chords: chords ?? List<String?>.filled(eventCount, null),
    optionalIndices: optionalIndices,
    sourceEventIds:
        sourceEventIds ??
        [for (var index = 0; index < eventCount; index++) 'event-$index'],
    loopIndexes: loopIndexes ?? List<int>.filled(eventCount, 0),
  );
  final matcher = PracticeEventMatcher(
    target: target,
    scoringProfile: ScoringProfile.legacyLearnParity,
    inputLatency: Duration.zero,
  );
  final observationsByTargetIndex = <int, StrumObservation>{};
  var sequence = 0;
  for (final entry in matchedOffsetsMicroseconds.entries) {
    final observation = StrumObservation(
      at: _eventTime(entry.key) + Duration(microseconds: entry.value),
      sequence: sequence,
      direction: observedDirections[entry.key] ?? StrumDirection.down,
      confidence: 1,
    );
    final match = matcher.registerStrum(observation);
    if (match != null) {
      observationsByTargetIndex[match.targetIndex] = observation;
    }
    sequence++;
  }
  if (finalize) matcher.finalize();

  final chordObservations = <ChordObservation>[];
  if (chordLabels != null) {
    for (var index = 0; index < chordLabels.length; index++) {
      final label = chordLabels[index];
      chordObservations
        ..add(
          ChordObservation(at: _eventTime(index), label: label, confidence: 1),
        )
        ..add(
          ChordObservation(
            at: _eventTime(index) + const Duration(milliseconds: 180),
            label: label,
            confidence: 1,
          ),
        );
    }
  }
  return _ScoringFixture(
    matcher: matcher,
    observationsByTargetIndex: observationsByTargetIndex,
    chordObservations: chordObservations,
  );
}

Duration _eventTime(int index) => Duration(seconds: 1 + index * 2);

CompiledPracticeTarget _target({
  required int eventCount,
  required List<StrumDirection?> directions,
  required List<String?> chords,
  required Set<int> optionalIndices,
  required List<String> sourceEventIds,
  required List<int> loopIndexes,
}) => CompiledPracticeTarget(
  definitionId: 'aggregator-test',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: [
    for (var index = 0; index < eventCount; index++)
      CompiledTargetEvent(
        sourceEventId: sourceEventIds[index],
        loopIndex: loopIndexes[index],
        position: BeatPosition.fromTicks(index),
        time: _eventTime(index),
        barIndex: 0,
        chord: chords[index],
        direction: directions[index],
        accent: false,
        optional: optionalIndices.contains(index),
      ),
  ],
  musicalDuration: eventCount == 0
      ? Duration.zero
      : _eventTime(eventCount - 1) + const Duration(seconds: 1),
  ringOutDuration: Duration.zero,
  totalDuration: eventCount == 0
      ? Duration.zero
      : _eventTime(eventCount - 1) + const Duration(seconds: 1),
  barBoundaries: const [],
  loopCount: loopIndexes.fold<int>(
    1,
    (count, index) => index >= count ? index + 1 : count,
  ),
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: eventCount > 0,
);

final class _ScoringFixture {
  const _ScoringFixture({
    required this.matcher,
    required this.observationsByTargetIndex,
    required this.chordObservations,
  });

  final PracticeEventMatcher matcher;
  final Map<int, StrumObservation> observationsByTargetIndex;
  final List<ChordObservation> chordObservations;
}
