// Randomized property gate for the E02-R09 practice event matcher.
//
// Seed: PROPERTY_SEED from CI; locally absent -> 42 for reproducibility.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

typedef _ResultSnapshot = ({
  PracticeTargetResolution resolution,
  int? sequence,
  Duration? observedAt,
  Duration? timingOffset,
});

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  group('PracticeEventMatcher randomized invariants', () {
    test('no double match, reopen, or resolved-count regression', () {
      var matchedRegistrationCount = 0;
      for (var trial = 0; trial < 160; trial++) {
        final rng = math.Random(seed + trial * 1009);
        final fixture = _randomFixture(rng);
        final matcher = fixture.matcher;
        final terminal = List<_ResultSnapshot?>.filled(
          matcher.results.length,
          null,
        );
        var previousResolved = 0;
        final observationCount = 30 + rng.nextInt(100);

        for (var step = 0; step < observationCount; step++) {
          final observation = _randomObservation(
            rng: rng,
            sequence: step % 11,
            maximumAt: fixture.maximumObservationAt,
          );
          matcher.advance(observation.at);
          final matchedBefore = matcher.results
              .where((result) => result.isMatched)
              .length;
          final matched = matcher.registerStrum(observation);
          final matchedAfter = matcher.results
              .where((result) => result.isMatched)
              .length;

          if (matched != null) {
            matchedRegistrationCount++;
            expect(
              matched.matchedObservationSequence,
              observation.sequence,
              reason: 'seed=$seed trial=$trial step=$step return sequence',
            );
          }
          expect(
            matchedAfter - matchedBefore,
            matched == null ? 0 : 1,
            reason:
                'seed=$seed trial=$trial step=$step one observation call '
                'resolved more than one target',
          );
          _assertInvariants(
            matcher: matcher,
            terminal: terminal,
            previousResolved: previousResolved,
            seed: seed,
            trial: trial,
            step: step,
          );
          previousResolved = matcher.resolvedTargetCount;
        }

        matcher.finalize();
        _assertInvariants(
          matcher: matcher,
          terminal: terminal,
          previousResolved: previousResolved,
          seed: seed,
          trial: trial,
          step: observationCount,
        );
        expect(
          matcher.results.every((result) => result.isResolved),
          isTrue,
          reason: 'seed=$seed trial=$trial finalize left an open target',
        );
        expect(
          matcher.results
              .where((result) => !result.target.optional)
              .every((result) => result.isResolved),
          isTrue,
          reason:
              'seed=$seed trial=$trial finalize left a required target open',
        );
      }
      expect(
        matchedRegistrationCount,
        greaterThan(0),
        reason: 'seed=$seed property never exercised a successful match',
      );
    });

    test(
      'random extra-strum floods leave every target resolution unchanged',
      () {
        for (var trial = 0; trial < 80; trial++) {
          final rng = math.Random(seed + 200000 + trial * 1013);
          final fixture = _randomFixture(rng, minimumFirstTimeMs: 2000);
          final matcher = fixture.matcher;
          final before = matcher.results.map(_snapshot).toList(growable: false);
          final resolvedBefore = matcher.resolvedTargetCount;
          final first = fixture.times.first;
          final last = fixture.times.last;

          for (var step = 0; step < 500; step++) {
            final playedAt = rng.nextBool()
                ? first -
                      ScoringProfile.legacyLearnParity.matchWindow -
                      Duration(microseconds: 1 + rng.nextInt(500000))
                : last +
                      ScoringProfile.legacyLearnParity.matchWindow +
                      Duration(microseconds: 1 + rng.nextInt(500000));
            final observation = StrumObservation(
              at: playedAt + fixture.inputLatency,
              sequence: step,
              direction: rng.nextBool()
                  ? StrumDirection.down
                  : StrumDirection.up,
              confidence: rng.nextDouble(),
            );

            expect(
              matcher.registerStrum(observation),
              isNull,
              reason: 'seed=$seed trial=$trial extra step=$step',
            );
          }

          expect(
            matcher.results.map(_snapshot),
            before,
            reason: 'seed=$seed trial=$trial extras changed target state',
          );
          expect(matcher.resolvedTargetCount, resolvedBefore);
          expect(matcher.extraStrumCount, 500);
        }
      },
    );

    test('the same observation set stays safe when shuffled', () {
      for (var trial = 0; trial < 120; trial++) {
        final rng = math.Random(seed + 400000 + trial * 1019);
        final fixture = _randomFixture(rng);
        final observations = <StrumObservation>[
          for (var index = 0; index < fixture.times.length; index++)
            StrumObservation(
              at:
                  fixture.times[index] +
                  Duration(microseconds: rng.nextInt(400001) - 200000) +
                  fixture.inputLatency,
              sequence: index,
              direction: rng.nextBool()
                  ? StrumDirection.down
                  : StrumDirection.up,
              confidence: rng.nextDouble(),
            ),
        ]..sort((left, right) => left.at.compareTo(right.at));
        final shuffled = List<StrumObservation>.of(observations)..shuffle(rng);

        _runOrder(
          matcher: _matcherForFixture(fixture),
          observations: observations,
          seed: seed,
          trial: trial,
          order: 'sorted',
        );
        _runOrder(
          matcher: _matcherForFixture(fixture),
          observations: shuffled,
          seed: seed,
          trial: trial,
          order: 'shuffled',
        );
      }
    });
  });
}

void _runOrder({
  required PracticeEventMatcher matcher,
  required List<StrumObservation> observations,
  required int seed,
  required int trial,
  required String order,
}) {
  final terminal = List<_ResultSnapshot?>.filled(matcher.results.length, null);
  var previousResolved = 0;
  for (var step = 0; step < observations.length; step++) {
    final observation = observations[step];
    matcher.advance(observation.at);
    final matchedBefore = matcher.results
        .where((result) => result.isMatched)
        .length;
    final matched = matcher.registerStrum(observation);
    final matchedAfter = matcher.results
        .where((result) => result.isMatched)
        .length;
    expect(
      matchedAfter - matchedBefore,
      matched == null ? 0 : 1,
      reason:
          'seed=$seed trial=$trial step=$step order=$order '
          'one observation call resolved more than one target',
    );
    _assertInvariants(
      matcher: matcher,
      terminal: terminal,
      previousResolved: previousResolved,
      seed: seed,
      trial: trial,
      step: step,
      order: order,
    );
    previousResolved = matcher.resolvedTargetCount;
  }
  matcher.finalize();
  _assertInvariants(
    matcher: matcher,
    terminal: terminal,
    previousResolved: previousResolved,
    seed: seed,
    trial: trial,
    step: observations.length,
    order: order,
  );
  expect(
    matcher.results.every((result) => result.isResolved),
    isTrue,
    reason: 'seed=$seed trial=$trial order=$order finalize',
  );
}

void _assertInvariants({
  required PracticeEventMatcher matcher,
  required List<_ResultSnapshot?> terminal,
  required int previousResolved,
  required int seed,
  required int trial,
  required int step,
  String? order,
}) {
  final context =
      'seed=$seed trial=$trial step=$step${order == null ? '' : ' order=$order'}';
  expect(
    matcher.resolvedTargetCount,
    greaterThanOrEqualTo(previousResolved),
    reason: '$context resolved count regressed',
  );
  expect(
    matcher.resolvedTargetCount,
    matcher.results.where((result) => result.isResolved).length,
    reason: '$context resolved count disagrees with results',
  );

  for (var index = 0; index < matcher.results.length; index++) {
    final current = _snapshot(matcher.results[index]);
    final previousTerminal = terminal[index];
    if (previousTerminal != null) {
      expect(
        current,
        previousTerminal,
        reason: '$context target $index reopened or changed terminal result',
      );
    } else if (matcher.results[index].isResolved) {
      terminal[index] = current;
    }
  }
}

StrumObservation _randomObservation({
  required math.Random rng,
  required int sequence,
  required Duration maximumAt,
}) => StrumObservation(
  at: Duration(microseconds: rng.nextInt(maximumAt.inMicroseconds + 1)),
  sequence: sequence,
  direction: rng.nextBool() ? StrumDirection.down : StrumDirection.up,
  confidence: rng.nextDouble(),
);

_ResultSnapshot _snapshot(PracticeEventMatchResult result) => (
  resolution: result.resolution,
  sequence: result.matchedObservationSequence,
  observedAt: result.observedAt,
  timingOffset: result.timingOffset,
);

final class _RandomFixture {
  const _RandomFixture({
    required this.target,
    required this.times,
    required this.inputLatency,
  });

  final CompiledPracticeTarget target;
  final List<Duration> times;
  final Duration inputLatency;

  Duration get maximumObservationAt =>
      target.totalDuration + inputLatency + const Duration(seconds: 1);

  PracticeEventMatcher get matcher => _matcherForFixture(this);
}

_RandomFixture _randomFixture(
  math.Random rng, {
  int minimumFirstTimeMs = 1000,
}) {
  final eventCount = 1 + rng.nextInt(40);
  final times = <Duration>[];
  var currentMicroseconds = minimumFirstTimeMs * 1000;
  final optional = <bool>[];
  for (var index = 0; index < eventCount; index++) {
    if (index > 0) {
      currentMicroseconds += rng.nextInt(10) == 0
          ? 0
          : 50000 + rng.nextInt(450001);
    }
    times.add(Duration(microseconds: currentMicroseconds));
    optional.add(rng.nextInt(5) == 0);
  }
  const latencies = <Duration>[
    Duration.zero,
    Duration(milliseconds: 40),
    Duration(milliseconds: 300),
  ];
  return _RandomFixture(
    target: _target(times, optional),
    times: times,
    inputLatency: latencies[rng.nextInt(latencies.length)],
  );
}

PracticeEventMatcher _matcherForFixture(_RandomFixture fixture) =>
    PracticeEventMatcher(
      target: fixture.target,
      scoringProfile: ScoringProfile.legacyLearnParity,
      inputLatency: fixture.inputLatency,
    );

CompiledPracticeTarget _target(List<Duration> times, List<bool> optional) {
  final totalDuration = times.last + const Duration(seconds: 1);
  return CompiledPracticeTarget(
    definitionId: 'property-target',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: [
      for (var index = 0; index < times.length; index++)
        CompiledTargetEvent(
          sourceEventId: 'event-$index',
          loopIndex: 0,
          position: BeatPosition.fromTicks(index),
          time: times[index],
          barIndex: 0,
          chord: null,
          direction: StrumDirection.down,
          accent: false,
          optional: optional[index],
        ),
    ],
    musicalDuration: totalDuration,
    ringOutDuration: Duration.zero,
    totalDuration: totalDuration,
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}
