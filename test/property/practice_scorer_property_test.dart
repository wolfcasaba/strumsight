// Randomized property gate for the E02-R10 practice scoring chain.
//
// Seed: PROPERTY_SEED from CI; locally absent -> 42 for reproducibility.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_chord_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_direction_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';
import 'package:strumsight/features/practice/domain/service/practice_score_aggregator.dart';
import 'package:strumsight/features/practice/domain/service/practice_timing_scorer.dart';

const _profiles = <ScoringProfile>[
  ScoringProfile.legacyLearnParity,
  ScoringProfile.chordChangeDefault,
  ScoringProfile.chordProgressionDefault,
  ScoringProfile.rhythmOnlyDefault,
  ScoringProfile.freePracticeOpen,
];

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  group('Practice scorer randomized invariants', () {
    test('available metrics are normalized and overall stays in range', () {
      var availableMetricCount = 0;
      var availableOverallCount = 0;
      for (var trial = 0; trial < 160; trial++) {
        final rng = math.Random(seed + trial * 1009);
        final profile = _profiles[rng.nextInt(_profiles.length)];
        final run = _randomRun(rng: rng, profile: profile);
        final metrics = run.metrics;

        for (final metric in <MetricValue>[
          metrics.completion,
          metrics.rhythm,
          metrics.direction,
          metrics.chord,
          metrics.overall,
        ]) {
          if (metric case MetricAvailable(:final value)) {
            availableMetricCount++;
            expect(
              value,
              inInclusiveRange(0, 1),
              reason: 'seed=$seed trial=$trial metric=$metric',
            );
          }
        }

        final availableWeightedDimensions = <double>[
          for (final entry in profile.weights.entries)
            if (entry.value > 0)
              if (_metricFor(metrics, entry.key) case MetricAvailable(
                :final value,
              ))
                value,
        ];
        if (metrics.overall case MetricAvailable(:final value)) {
          availableOverallCount++;
          expect(availableWeightedDimensions, isNotEmpty);
          expect(
            value,
            greaterThanOrEqualTo(availableWeightedDimensions.reduce(math.min)),
            reason: 'seed=$seed trial=$trial overall below minimum',
          );
          expect(
            value,
            lessThanOrEqualTo(availableWeightedDimensions.reduce(math.max)),
            reason: 'seed=$seed trial=$trial overall above maximum',
          );
        } else {
          expect(
            availableWeightedDimensions,
            isEmpty,
            reason: 'seed=$seed trial=$trial discarded available dimensions',
          );
        }

        expect(
          metrics.resolvedTargets,
          lessThanOrEqualTo(metrics.totalTargets),
          reason: 'seed=$seed trial=$trial completion counters',
        );
        expect(metrics.validate(), isEmpty, reason: 'seed=$seed trial=$trial');
        for (final verdict in run.verdicts) {
          expect(
            verdict.validate(),
            isEmpty,
            reason: 'seed=$seed trial=$trial ${verdict.targetEventId}',
          );
        }
      }
      expect(availableMetricCount, greaterThan(0));
      expect(availableOverallCount, greaterThan(0));
    });

    test('changing one wrong direction to correct never lowers points', () {
      var strictIncreaseCount = 0;
      for (var trial = 0; trial < 120; trial++) {
        final rng = math.Random(seed + 200000 + trial * 1013);
        final eventCount = 1 + rng.nextInt(28);
        final wrongIndex = rng.nextInt(eventCount);
        final target = _target(
          eventCount: eventCount,
          directions: List<StrumDirection?>.filled(
            eventCount,
            StrumDirection.down,
          ),
          chords: List<String?>.filled(eventCount, null),
          optionalIndices: const {},
        );
        final matcher = PracticeEventMatcher(
          target: target,
          scoringProfile: ScoringProfile.legacyLearnParity,
          inputLatency: Duration.zero,
        );
        final wrongObservations = <int, StrumObservation>{};
        for (var index = 0; index < eventCount; index++) {
          final observation = StrumObservation(
            at:
                _eventTime(index) +
                Duration(microseconds: rng.nextInt(560001) - 280000),
            sequence: index,
            direction: index == wrongIndex
                ? StrumDirection.up
                : StrumDirection.down,
            confidence: rng.nextDouble(),
          );
          matcher.registerStrum(observation);
          wrongObservations[index] = observation;
        }
        matcher.finalize();
        final correctedObservations = Map<int, StrumObservation>.of(
          wrongObservations,
        );
        final wrong = wrongObservations[wrongIndex]!;
        correctedObservations[wrongIndex] = StrumObservation(
          at: wrong.at,
          sequence: wrong.sequence,
          direction: StrumDirection.down,
          confidence: wrong.confidence,
        );

        final before = _score(
          matcher: matcher,
          profile: ScoringProfile.legacyLearnParity,
          observationsByTargetIndex: wrongObservations,
          chordObservations: const [],
        );
        final after = _score(
          matcher: matcher,
          profile: ScoringProfile.legacyLearnParity,
          observationsByTargetIndex: correctedObservations,
          chordObservations: const [],
        );

        expect(
          after.metrics.scorePoints,
          greaterThanOrEqualTo(before.metrics.scorePoints),
          reason: 'seed=$seed trial=$trial wrongIndex=$wrongIndex',
        );
        if (after.metrics.scorePoints > before.metrics.scorePoints) {
          strictIncreaseCount++;
        }
      }
      expect(strictIncreaseCount, 120);
    });

    test('zero observations never become a zero-valued scoring dimension', () {
      for (var trial = 0; trial < 120; trial++) {
        final rng = math.Random(seed + 400000 + trial * 1019);
        final eventCount = 1 + rng.nextInt(30);
        final profile = _profiles[rng.nextInt(_profiles.length)];
        final matcher = PracticeEventMatcher(
          target: _target(
            eventCount: eventCount,
            directions: [
              for (var index = 0; index < eventCount; index++)
                rng.nextBool() ? StrumDirection.down : null,
            ],
            chords: [
              for (var index = 0; index < eventCount; index++)
                rng.nextBool() ? 'G' : null,
            ],
            optionalIndices: {
              for (var index = 0; index < eventCount; index++)
                if (rng.nextInt(5) == 0) index,
            },
          ),
          scoringProfile: profile,
          inputLatency: Duration.zero,
        )..finalize();

        final run = _score(
          matcher: matcher,
          profile: profile,
          observationsByTargetIndex: const {},
          chordObservations: const [],
        );

        for (final entry in <String, MetricValue>{
          'rhythm': run.metrics.rhythm,
          'direction': run.metrics.direction,
          'chord': run.metrics.chord,
          'overall': run.metrics.overall,
        }.entries) {
          expect(
            entry.value is MetricAvailable &&
                (entry.value as MetricAvailable).value == 0,
            isFalse,
            reason: 'seed=$seed trial=$trial dimension=${entry.key}',
          );
        }
      }
    });
  });
}

PracticeScoreAggregation _randomRun({
  required math.Random rng,
  required ScoringProfile profile,
}) {
  final eventCount = 1 + rng.nextInt(30);
  final directions = <StrumDirection?>[
    for (var index = 0; index < eventCount; index++)
      rng.nextInt(4) == 0
          ? null
          : rng.nextBool()
          ? StrumDirection.down
          : StrumDirection.up,
  ];
  final chords = <String?>[
    for (var index = 0; index < eventCount; index++)
      rng.nextInt(5) < 2
          ? null
          : rng.nextBool()
          ? 'G'
          : 'C',
  ];
  final optionalIndices = <int>{
    for (var index = 0; index < eventCount; index++)
      if (rng.nextInt(7) == 0) index,
  };
  final matcher = PracticeEventMatcher(
    target: _target(
      eventCount: eventCount,
      directions: directions,
      chords: chords,
      optionalIndices: optionalIndices,
    ),
    scoringProfile: profile,
    inputLatency: Duration.zero,
  );
  final observationsByTargetIndex = <int, StrumObservation>{};
  var sequence = 0;
  for (var index = 0; index < eventCount; index++) {
    if (rng.nextInt(10) < 3) continue;
    final observation = StrumObservation(
      at:
          _eventTime(index) +
          Duration(microseconds: rng.nextInt(560001) - 280000),
      sequence: sequence,
      direction: rng.nextBool() ? StrumDirection.down : StrumDirection.up,
      confidence: rng.nextDouble(),
    );
    final match = matcher.registerStrum(observation);
    if (match != null) {
      observationsByTargetIndex[match.targetIndex] = observation;
    }
    sequence++;
  }
  matcher.finalize();

  final chordObservations = <ChordObservation>[];
  for (var index = 0; index < eventCount; index++) {
    if (chords[index] == null) continue;
    final mode = rng.nextInt(4);
    if (mode == 0) continue;
    if (mode == 3) {
      chordObservations.add(
        ChordObservation(
          at: _eventTime(index),
          label: null,
          confidence: rng.nextDouble(),
        ),
      );
      continue;
    }
    final label = mode == 1
        ? chords[index]
        : chords[index] == 'G'
        ? 'C'
        : 'G';
    chordObservations
      ..add(
        ChordObservation(
          at: _eventTime(index),
          label: label,
          confidence: rng.nextDouble(),
        ),
      )
      ..add(
        ChordObservation(
          at: _eventTime(index) + const Duration(milliseconds: 180),
          label: label,
          confidence: rng.nextDouble(),
        ),
      );
  }
  return _score(
    matcher: matcher,
    profile: profile,
    observationsByTargetIndex: observationsByTargetIndex,
    chordObservations: chordObservations,
  );
}

PracticeScoreAggregation _score({
  required PracticeEventMatcher matcher,
  required ScoringProfile profile,
  required Map<int, StrumObservation> observationsByTargetIndex,
  required List<ChordObservation> chordObservations,
}) {
  final timing = const PracticeTimingScorer().score(
    matches: matcher.results,
    scoringProfile: profile,
  );
  final direction = const PracticeDirectionScorer().score(
    matches: matcher.results,
    observationsByTargetIndex: observationsByTargetIndex,
  );
  final chord = const PracticeChordScorer().score(
    matches: matcher.results,
    observations: chordObservations,
  );
  return const PracticeScoreAggregator().aggregate(
    matches: matcher.results,
    scoringProfile: profile,
    timing: timing,
    direction: direction,
    chord: chord,
  );
}

MetricValue _metricFor(
  PracticeMetrics metrics,
  PracticeScoreDimension dimension,
) => switch (dimension) {
  PracticeScoreDimension.rhythm => metrics.rhythm,
  PracticeScoreDimension.direction => metrics.direction,
  PracticeScoreDimension.chord => metrics.chord,
  _ => const MetricNotApplicable(),
};

Duration _eventTime(int index) => Duration(seconds: 1 + index);

CompiledPracticeTarget _target({
  required int eventCount,
  required List<StrumDirection?> directions,
  required List<String?> chords,
  required Set<int> optionalIndices,
}) => CompiledPracticeTarget(
  definitionId: 'scorer-property',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: [
    for (var index = 0; index < eventCount; index++)
      CompiledTargetEvent(
        sourceEventId: 'event-$index',
        loopIndex: 0,
        position: BeatPosition.fromTicks(index * 480),
        time: _eventTime(index),
        barIndex: index ~/ 4,
        chord: chords[index],
        direction: directions[index],
        accent: false,
        optional: optionalIndices.contains(index),
      ),
  ],
  musicalDuration: _eventTime(eventCount - 1) + const Duration(seconds: 1),
  ringOutDuration: Duration.zero,
  totalDuration: _eventTime(eventCount - 1) + const Duration(seconds: 1),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: true,
);
