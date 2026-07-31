import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/lesson_scorer.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/data/adapters/lesson_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';

const _latencies = <Duration>[
  Duration.zero,
  Duration(milliseconds: 40),
  Duration(milliseconds: 300),
];
const _matchWindowMicroseconds = 280000;

const _lessonIds = <String>[
  'first-strums',
  'two-chord-change',
  'eighth-drive',
  'fifties-doo-wop',
  'two-finger-frame',
  'first-waltz',
  'down-up-groove',
  'folk-pattern',
  'barre-groove',
  'anthem-drive',
  'rising-minor',
  'waltz-time',
  'reggae-skank',
  'funk-chop',
  'blues-shuffle',
  'push-and-pull',
  'first-win',
];

void main() {
  group('PracticeEventMatcher legacy LessonScorer parity', () {
    final lessons = <Lesson>[...Lessons.all, Lessons.firstWin];

    test('pins the complete 16 lesson catalog plus first-win', () {
      expect(lessons, hasLength(17));
      expect(lessons.map((lesson) => lesson.id), _lessonIds);
    });

    test('keeps every compiled event within 0.5 us of legacy time', () {
      var eventCount = 0;
      var maximumDifferenceMicroseconds = 0.0;
      var maximumDifferenceCell = '';

      for (final lesson in lessons) {
        final target = _compiledTargetFor(lesson);
        final legacy = LessonScorer(lesson, countInBeats: lesson.beatsPerBar);
        expect(target.events, hasLength(lesson.events.length));

        for (var index = 0; index < lesson.events.length; index++) {
          final legacyMicroseconds =
              legacy.timeOf(lesson.events[index]) *
              Duration.microsecondsPerSecond;
          final differenceMicroseconds =
              (legacyMicroseconds - target.events[index].time.inMicroseconds)
                  .abs();
          if (differenceMicroseconds > maximumDifferenceMicroseconds) {
            maximumDifferenceMicroseconds = differenceMicroseconds;
            maximumDifferenceCell = '${lesson.id}[$index]';
          }
          expect(
            differenceMicroseconds,
            lessThanOrEqualTo(0.5),
            reason:
                '${lesson.id} event $index is not round-to-nearest only: '
                'legacyUs=$legacyMicroseconds '
                'compiledUs=${target.events[index].time.inMicroseconds}',
          );
          eventCount++;
        }
      }

      // ignore: avoid_print
      print(
        'A1b measuredEvents=$eventCount '
        'maximumTimebaseDifferenceUs='
        '${maximumDifferenceMicroseconds.toStringAsFixed(12)} '
        'cell=$maximumDifferenceCell',
      );
      expect(maximumDifferenceMicroseconds, lessThanOrEqualTo(0.5));
    });

    test('pins the first-strums compiled eligibility divergence', () {
      final lesson = Lessons.firstStrums;
      final target = _compiledTargetFor(lesson);
      final legacy = LessonScorer(lesson, countInBeats: lesson.beatsPerBar);
      const playedMicroseconds = 3148571;
      final playedSeconds = playedMicroseconds / Duration.microsecondsPerSecond;
      final legacyDeltaMicroseconds =
          (legacy.timeOf(lesson.events.first) - playedSeconds).abs() *
          Duration.microsecondsPerSecond;

      expect(lesson.events.first.beat, 0);
      expect(legacy.timeOf(lesson.events.first), 3.4285714285714284);
      expect(target.events.first.time.inMicroseconds, 3428571);
      expect(legacyDeltaMicroseconds, 280000.42857142835);
      expect(legacyDeltaMicroseconds, greaterThan(_matchWindowMicroseconds));
      expect(
        legacy.registerStrum(lesson.events.first.direction, playedSeconds),
        isNull,
      );

      final match =
          PracticeEventMatcher(
            target: target,
            scoringProfile: ScoringProfile.legacyLearnParity,
            inputLatency: Duration.zero,
          ).registerStrum(
            StrumObservation(
              at: const Duration(microseconds: playedMicroseconds),
              sequence: 0,
              direction: lesson.events.first.direction,
              confidence: 1,
            ),
          );

      expect(match?.targetIndex, 0);
      expect(match?.timingOffset?.inMicroseconds, -_matchWindowMicroseconds);
    });

    test('pins the anthem-drive [5, 6] compiled midpoint divergence', () {
      final lesson = Lessons.anthemDrive;
      final target = _compiledTargetFor(lesson);
      final legacy = LessonScorer(lesson, countInBeats: lesson.beatsPerBar);
      const earlierIndex = 5;
      const laterIndex = 6;
      const midpointMicroseconds = 4744898;
      final midpointSeconds =
          midpointMicroseconds / Duration.microsecondsPerSecond;
      final earlierLegacyDeltaMicroseconds =
          (legacy.timeOf(lesson.events[earlierIndex]) - midpointSeconds).abs() *
          Duration.microsecondsPerSecond;
      final laterLegacyDeltaMicroseconds =
          (legacy.timeOf(lesson.events[laterIndex]) - midpointSeconds).abs() *
          Duration.microsecondsPerSecond;
      final legacyResults = List<_LegacyTargetResult?>.filled(
        lesson.events.length,
        null,
      );

      expect(lesson.events[earlierIndex].beat, 3.5);
      expect(lesson.events[laterIndex].beat, 4.0);
      expect(target.events[earlierIndex].time.inMicroseconds, 4591837);
      expect(target.events[laterIndex].time.inMicroseconds, 4897959);
      expect(
        (target.events[earlierIndex].time.inMicroseconds +
                target.events[laterIndex].time.inMicroseconds) ~/
            2,
        midpointMicroseconds,
      );
      expect(earlierLegacyDeltaMicroseconds, 153061.26530612208);
      expect(laterLegacyDeltaMicroseconds, 153061.18367346944);
      expect(
        laterLegacyDeltaMicroseconds,
        lessThan(earlierLegacyDeltaMicroseconds),
      );
      expect(
        _legacyMatchedTargetIndex(
          lesson: lesson,
          scorer: legacy,
          elapsedSec: midpointSeconds,
          inputLatency: Duration.zero,
          results: legacyResults,
        ),
        laterIndex,
      );
      expect(
        legacy.registerStrum(
          lesson.events[laterIndex].direction,
          midpointSeconds,
        ),
        HitResult.hit,
      );

      final matcher = PracticeEventMatcher(
        target: target,
        scoringProfile: ScoringProfile.legacyLearnParity,
        inputLatency: Duration.zero,
      );
      final match = matcher.registerStrum(
        StrumObservation(
          at: const Duration(microseconds: midpointMicroseconds),
          sequence: 0,
          direction: lesson.events[laterIndex].direction,
          confidence: 1,
        ),
      );

      expect(match?.targetIndex, earlierIndex);
      expect(matcher.results[earlierIndex].isMatched, isTrue);
      expect(
        matcher.results[laterIndex].resolution,
        PracticeTargetResolution.open,
      );
    });

    test('matches every target exactly across all 51 latency scenarios', () {
      var scenarioCount = 0;
      var maximumMicrosecondDifference = 0;
      var excludedObservationCount = 0;

      for (final lesson in lessons) {
        for (final latency in _latencies) {
          final measurement = _runParityScenario(lesson, latency);
          if (measurement.maximumDifferenceMicroseconds >
              maximumMicrosecondDifference) {
            maximumMicrosecondDifference =
                measurement.maximumDifferenceMicroseconds;
          }
          excludedObservationCount += measurement.excludedObservationCount;
          scenarioCount++;
        }
      }

      // ignore: avoid_print
      print(
        'A1 parity scenarios=$scenarioCount '
        'maximumDifferenceUs=$maximumMicrosecondDifference '
        'excludedObservations=$excludedObservationCount',
      );
      expect(scenarioCount, 17 * 3);
      expect(maximumMicrosecondDifference, 0);
      expect(excludedObservationCount, 0);
    });
  });
}

({int maximumDifferenceMicroseconds, int excludedObservationCount})
_runParityScenario(Lesson lesson, Duration latency) {
  final definition = _definition(practiceDefinitionFromLesson(lesson));
  final target = _target(
    compilePracticeTarget(definition: definition, config: _config(definition)),
  );
  final legacy = LessonScorer(
    lesson,
    countInBeats: lesson.beatsPerBar,
    inputLatencySec: latency.inMicroseconds / Duration.microsecondsPerSecond,
  );
  final matcher = PracticeEventMatcher(
    target: target,
    scoringProfile: ScoringProfile.legacyLearnParity,
    inputLatency: latency,
  );
  final legacyResults = List<_LegacyTargetResult?>.filled(
    lesson.events.length,
    null,
  );
  final observations = _observationsFor(target, latency);
  var excludedObservationCount = 0;

  for (final observation in observations) {
    final guardBand = _measureGuardBand(
      matcher: matcher,
      playedAt: observation.at - latency,
    );
    if (!guardBand.outside) {
      excludedObservationCount++;
      continue;
    }
    final context =
        '${lesson.id}@${latency.inMilliseconds}ms observation '
        '${observation.sequence}';
    expect(guardBand.outside, isTrue, reason: '$context parity guard band');
    final eligibilityDistance =
        guardBand.minimumEligibilityBoundaryDistanceMicroseconds;
    if (eligibilityDistance != null) {
      expect(
        eligibilityDistance,
        greaterThanOrEqualTo(1),
        reason: '$context eligibility guard',
      );
    }
    final closingDistance =
        guardBand.minimumClosingBoundaryDistanceMicroseconds;
    if (closingDistance != null) {
      expect(
        closingDistance,
        greaterThanOrEqualTo(1),
        reason: '$context closing guard',
      );
    }
    final nearestCandidateGap = guardBand.nearestCandidateGapMicroseconds;
    if (nearestCandidateGap != null) {
      expect(
        nearestCandidateGap,
        greaterThanOrEqualTo(2),
        reason: '$context argmin guard',
      );
    }

    final elapsedSec =
        observation.at.inMicroseconds / Duration.microsecondsPerSecond;
    legacy.advance(elapsedSec);
    _captureLegacyMisses(
      lesson: lesson,
      scorer: legacy,
      elapsedSec: elapsedSec,
      inputLatency: latency,
      results: legacyResults,
    );
    matcher.advance(observation.at);

    final matchedIndex = _legacyMatchedTargetIndex(
      lesson: lesson,
      scorer: legacy,
      elapsedSec: elapsedSec,
      inputLatency: latency,
      results: legacyResults,
    );
    final legacyResult = legacy.registerStrum(
      observation.direction,
      elapsedSec,
    );
    final match = matcher.registerStrum(observation);

    if (matchedIndex == null) {
      expect(
        legacyResult,
        isNull,
        reason: '${lesson.id}@${latency.inMilliseconds}ms legacy extra',
      );
      expect(
        match,
        isNull,
        reason: '${lesson.id}@${latency.inMilliseconds}ms matcher extra',
      );
      continue;
    }

    final event = lesson.events[matchedIndex];
    expect(
      legacyResult,
      observation.direction == event.direction
          ? HitResult.hit
          : HitResult.wrongDirection,
      reason:
          '${lesson.id}@${latency.inMilliseconds}ms observation '
          '${observation.sequence} legacy direction result',
    );
    expect(
      match?.targetIndex,
      matchedIndex,
      reason:
          '${lesson.id}@${latency.inMilliseconds}ms observation '
          '${observation.sequence} target index',
    );

    final playedMicroseconds =
        ((elapsedSec - legacy.inputLatencySec) * Duration.microsecondsPerSecond)
            .round();
    final targetMicroseconds =
        (legacy.timeOf(event) * Duration.microsecondsPerSecond).round();
    legacyResults[matchedIndex] = _LegacyTargetResult.matched(
      sequence: observation.sequence,
      playedAtMicroseconds: playedMicroseconds,
      timingOffsetMicroseconds: playedMicroseconds - targetMicroseconds,
    );
  }

  final legacyMissesBeforeFinalize = legacy.missed;
  legacy.finalize();
  matcher.finalize();
  expect(
    legacy.missed,
    legacyMissesBeforeFinalize,
    reason: '${lesson.id} ring-out must close every legacy target',
  );
  expect(
    legacyResults,
    everyElement(isNotNull),
    reason: '${lesson.id} legacy oracle must resolve every target',
  );
  expect(
    matcher.results,
    hasLength(legacyResults.length),
    reason: '${lesson.id} matcher result count',
  );

  var maximumDifference = 0;
  for (var index = 0; index < legacyResults.length; index++) {
    final expected = legacyResults[index]!;
    final actual = matcher.results[index];
    final reason = '${lesson.id}@${latency.inMilliseconds}ms target $index';

    expect(actual.targetIndex, index, reason: '$reason index');
    expect(actual.isMatched, expected.matched, reason: '$reason matched');
    expect(
      actual.matchedObservationSequence,
      expected.sequence,
      reason: '$reason sequence',
    );
    expect(
      actual.observedAt?.inMicroseconds,
      expected.playedAtMicroseconds,
      reason: '$reason corrected observation time',
    );
    expect(
      actual.timingOffset?.inMicroseconds,
      expected.timingOffsetMicroseconds,
      reason: '$reason signed timing offset',
    );

    if (expected.matched) {
      final observedDifference =
          (actual.observedAt!.inMicroseconds - expected.playedAtMicroseconds!)
              .abs();
      final offsetDifference =
          (actual.timingOffset!.inMicroseconds -
                  expected.timingOffsetMicroseconds!)
              .abs();
      if (observedDifference > maximumDifference) {
        maximumDifference = observedDifference;
      }
      if (offsetDifference > maximumDifference) {
        maximumDifference = offsetDifference;
      }
    }
  }

  expect(
    matcher.resolvedTargetCount,
    lesson.events.length,
    reason: '${lesson.id} resolved count',
  );
  return (
    maximumDifferenceMicroseconds: maximumDifference,
    excludedObservationCount: excludedObservationCount,
  );
}

({
  bool outside,
  int? minimumEligibilityBoundaryDistanceMicroseconds,
  int? minimumClosingBoundaryDistanceMicroseconds,
  int? nearestCandidateGapMicroseconds,
})
_measureGuardBand({
  required PracticeEventMatcher matcher,
  required Duration playedAt,
}) {
  final eligibleDeltas = <int>[];
  int? minimumEligibilityBoundaryDistanceMicroseconds;
  int? minimumClosingBoundaryDistanceMicroseconds;

  for (final result in matcher.results) {
    if (result.isResolved) continue;
    final deltaMicroseconds = (result.target.time - playedAt).inMicroseconds
        .abs();
    final eligibilityBoundaryDistanceMicroseconds =
        (deltaMicroseconds - _matchWindowMicroseconds).abs();
    final closingBoundaryDistanceMicroseconds =
        (playedAt.inMicroseconds -
                (result.target.time.inMicroseconds + _matchWindowMicroseconds))
            .abs();
    if (minimumEligibilityBoundaryDistanceMicroseconds == null ||
        eligibilityBoundaryDistanceMicroseconds <
            minimumEligibilityBoundaryDistanceMicroseconds) {
      minimumEligibilityBoundaryDistanceMicroseconds =
          eligibilityBoundaryDistanceMicroseconds;
    }
    if (minimumClosingBoundaryDistanceMicroseconds == null ||
        closingBoundaryDistanceMicroseconds <
            minimumClosingBoundaryDistanceMicroseconds) {
      minimumClosingBoundaryDistanceMicroseconds =
          closingBoundaryDistanceMicroseconds;
    }
    if (deltaMicroseconds <= _matchWindowMicroseconds) {
      eligibleDeltas.add(deltaMicroseconds);
    }
  }

  eligibleDeltas.sort();
  final nearestCandidateGapMicroseconds = eligibleDeltas.length < 2
      ? null
      : eligibleDeltas[1] - eligibleDeltas[0];
  final outside =
      (minimumEligibilityBoundaryDistanceMicroseconds == null ||
          minimumEligibilityBoundaryDistanceMicroseconds >= 1) &&
      (minimumClosingBoundaryDistanceMicroseconds == null ||
          minimumClosingBoundaryDistanceMicroseconds >= 1) &&
      (nearestCandidateGapMicroseconds == null ||
          nearestCandidateGapMicroseconds >= 2);
  return (
    outside: outside,
    minimumEligibilityBoundaryDistanceMicroseconds:
        minimumEligibilityBoundaryDistanceMicroseconds,
    minimumClosingBoundaryDistanceMicroseconds:
        minimumClosingBoundaryDistanceMicroseconds,
    nearestCandidateGapMicroseconds: nearestCandidateGapMicroseconds,
  );
}

List<StrumObservation> _observationsFor(
  CompiledPracticeTarget target,
  Duration latency,
) {
  const offsets = <Duration>[
    Duration(milliseconds: -40),
    Duration.zero,
    Duration(milliseconds: 40),
  ];
  final planned = <({Duration at, StrumDirection direction})>[
    (
      at:
          target.events.first.time -
          const Duration(milliseconds: 380) +
          latency,
      direction: StrumDirection.down,
    ),
  ];

  for (var index = 0; index < target.events.length; index++) {
    if (index % 7 == 6) continue;
    final event = target.events[index];
    final expectedDirection = event.direction!;
    planned.add((
      at: event.time + offsets[index % offsets.length] + latency,
      direction: index % 5 == 4
          ? _opposite(expectedDirection)
          : expectedDirection,
    ));
  }
  planned.add((
    at: target.events.last.time + const Duration(milliseconds: 600) + latency,
    direction: StrumDirection.up,
  ));
  planned.sort((left, right) => left.at.compareTo(right.at));

  for (var index = 1; index < planned.length; index++) {
    expect(planned[index].at, greaterThanOrEqualTo(planned[index - 1].at));
  }
  return [
    for (var index = 0; index < planned.length; index++)
      StrumObservation(
        at: planned[index].at,
        sequence: index,
        direction: planned[index].direction,
        confidence: 1,
      ),
  ];
}

void _captureLegacyMisses({
  required Lesson lesson,
  required LessonScorer scorer,
  required double elapsedSec,
  required Duration inputLatency,
  required List<_LegacyTargetResult?> results,
}) {
  final latencySec =
      inputLatency.inMicroseconds / Duration.microsecondsPerSecond;
  final playedSec = elapsedSec - latencySec;
  for (var index = 0; index < lesson.events.length; index++) {
    if (results[index] != null) continue;
    if (scorer.timeOf(lesson.events[index]) + scorer.windowSec < playedSec) {
      results[index] = const _LegacyTargetResult.missed();
    }
  }
  expect(
    scorer.missed,
    results.where((result) => result != null && !result.matched).length,
  );
}

int? _legacyMatchedTargetIndex({
  required Lesson lesson,
  required LessonScorer scorer,
  required double elapsedSec,
  required Duration inputLatency,
  required List<_LegacyTargetResult?> results,
}) {
  final latencySec =
      inputLatency.inMicroseconds / Duration.microsecondsPerSecond;
  final playedSec = elapsedSec - latencySec;
  int? bestIndex;
  var bestDelta = double.infinity;

  for (var index = 0; index < lesson.events.length; index++) {
    if (results[index] != null) continue;
    final delta = (scorer.timeOf(lesson.events[index]) - playedSec).abs();
    if (delta <= scorer.windowSec && delta < bestDelta) {
      bestIndex = index;
      bestDelta = delta;
    }
  }
  return bestIndex;
}

StrumDirection _opposite(StrumDirection direction) =>
    direction == StrumDirection.down ? StrumDirection.up : StrumDirection.down;

PracticeDefinition _definition(AppResult<PracticeDefinition> result) =>
    (result as Success<PracticeDefinition>).value;

CompiledPracticeTarget _target(AppResult<CompiledPracticeTarget> result) =>
    (result as Success<CompiledPracticeTarget>).value;

CompiledPracticeTarget _compiledTargetFor(Lesson lesson) {
  final definition = _definition(practiceDefinitionFromLesson(lesson));
  return _target(
    compilePracticeTarget(definition: definition, config: _config(definition)),
  );
}

PracticeSessionConfig _config(PracticeDefinition definition) =>
    PracticeSessionConfig(
      definitionId: definition.id,
      definitionSnapshotVersion: definition.schemaVersion,
      effectiveTempo: Tempo(definition.defaultTempo.bpm),
      countInBars: 1,
      loopCount: 1,
      metronomeEnabled: true,
      accentEnabled: true,
      backingEnabled: false,
      scoringProfileId: ScoringProfile.legacyLearnParity.id,
      inputLatency: Duration.zero,
      visualLatency: Duration.zero,
      expectedChordHintEnabled: true,
      sessionTimeout: const Duration(minutes: 10),
      reducedMotion: false,
    );

final class _LegacyTargetResult {
  const _LegacyTargetResult.matched({
    required this.sequence,
    required this.playedAtMicroseconds,
    required this.timingOffsetMicroseconds,
  }) : matched = true;

  const _LegacyTargetResult.missed()
    : matched = false,
      sequence = null,
      playedAtMicroseconds = null,
      timingOffsetMicroseconds = null;

  final bool matched;
  final int? sequence;
  final int? playedAtMicroseconds;
  final int? timingOffsetMicroseconds;
}
