import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/lesson_scorer.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/data/adapters/lesson_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_chord_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_direction_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';
import 'package:strumsight/features/practice/domain/service/practice_score_aggregator.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';
import 'package:strumsight/features/practice/domain/service/practice_timing_scorer.dart';

const _latencies = <Duration>[
  Duration.zero,
  Duration(milliseconds: 40),
  Duration(milliseconds: 300),
];

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

const _timingThresholds =
    <
      ({
        int microseconds,
        Timing expectedLegacyTiming,
        TimingGrade expectedCompiledEarly,
        TimingGrade expectedCompiledLate,
      })
    >[
      (
        microseconds: 50000,
        expectedLegacyTiming: Timing.good,
        expectedCompiledEarly: TimingGrade.perfect,
        expectedCompiledLate: TimingGrade.perfect,
      ),
      (
        microseconds: 120000,
        expectedLegacyTiming: Timing.early,
        expectedCompiledEarly: TimingGrade.good,
        expectedCompiledLate: TimingGrade.good,
      ),
      (
        microseconds: 280000,
        expectedLegacyTiming: Timing.early,
        expectedCompiledEarly: TimingGrade.early,
        expectedCompiledLate: TimingGrade.late,
      ),
    ];

void main() {
  group('Practice scorer legacy LessonScorer parity', () {
    final lessons = <Lesson>[...Lessons.all, Lessons.firstWin];

    test('pins the complete 16 lesson catalog plus first-win', () {
      expect(lessons, hasLength(17));
      expect(lessons.map((lesson) => lesson.id), _lessonIds);
    });

    test('measures the compiled timebase guard at at most 0.5 us', () {
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
        'A7b measuredEvents=$eventCount '
        'maximumTimebaseDifferenceUs='
        '${maximumDifferenceMicroseconds.toStringAsFixed(12)} '
        'cell=$maximumDifferenceCell',
      );
      expect(eventCount, 348);
      expect(maximumDifferenceCell, 'anthem-drive[23]');
      expect(maximumDifferenceMicroseconds, lessThanOrEqualTo(0.5));
    });

    test(
      'matches score, combo, counters and direction across 51 scenarios',
      () {
        var scenarioCount = 0;
        var excludedGuardBandEventCount = 0;

        for (final lesson in lessons) {
          for (final latency in _latencies) {
            final measurement = _runParityScenario(lesson, latency);
            excludedGuardBandEventCount +=
                measurement.excludedGuardBandEventCount;
            scenarioCount++;
          }
        }

        // ignore: avoid_print
        print(
          'A7 parity scenarios=$scenarioCount '
          'excludedGuardBandEvents=$excludedGuardBandEventCount',
        );
        expect(scenarioCount, 17 * 3);
        expect(excludedGuardBandEventCount, 0);
      },
    );

    test('pins 18 representative extrema divergence cells', () {
      final cells = <_DivergenceCell>[
        const _DivergenceCell(
          lessonId: 'first-strums',
          eventIndex: 0,
          legacyTargetMicroseconds: 3428571.4285714284,
          compiledTargetMicroseconds: 3428571,
          sign: -1,
        ),
        const _DivergenceCell(
          lessonId: 'anthem-drive',
          eventIndex: 23,
          legacyTargetMicroseconds: 11938775.51020408,
          compiledTargetMicroseconds: 11938776,
          sign: 1,
        ),
      ];
      var pinnedCellCount = 0;

      for (final cell in cells) {
        final lesson = lessons.singleWhere(
          (candidate) => candidate.id == cell.lessonId,
        );
        final target = _compiledTargetFor(lesson);
        expect(
          target.events[cell.eventIndex].time.inMicroseconds,
          cell.compiledTargetMicroseconds,
        );
        final reference = LessonScorer(
          lesson,
          countInBeats: lesson.beatsPerBar,
        );
        expect(
          reference.timeOf(lesson.events[cell.eventIndex]) *
              Duration.microsecondsPerSecond,
          cell.legacyTargetMicroseconds,
        );

        for (final threshold in _timingThresholds) {
          for (final latency in _latencies) {
            _expectPinnedDivergence(
              lesson: lesson,
              target: target,
              latency: latency,
              cell: cell,
              threshold: threshold,
            );
            pinnedCellCount++;
          }
        }
      }

      // ignore: avoid_print
      print('A7c representativeDivergenceCells=$pinnedCellCount');
      expect(pinnedCellCount, 2 * 3 * 3);
    });

    test('discovers and pins every actual boundary divergence cell', () {
      var divergenceCellCount = 0;
      var fingerprint = 0;

      for (final lesson in lessons) {
        final target = _compiledTargetFor(lesson);
        final reference = LessonScorer(
          lesson,
          countInBeats: lesson.beatsPerBar,
        );
        for (
          var eventIndex = 0;
          eventIndex < lesson.events.length;
          eventIndex++
        ) {
          final legacyTargetMicroseconds =
              reference.timeOf(lesson.events[eventIndex]) *
              Duration.microsecondsPerSecond;
          final compiledTargetMicroseconds =
              target.events[eventIndex].time.inMicroseconds;

          for (final threshold in _timingThresholds) {
            for (final latency in _latencies) {
              for (final sign in const [-1, 1]) {
                final measurement = _measureBoundaryCell(
                  lesson: lesson,
                  target: target,
                  latency: latency,
                  cell: _DivergenceCell(
                    lessonId: lesson.id,
                    eventIndex: eventIndex,
                    legacyTargetMicroseconds: legacyTargetMicroseconds,
                    compiledTargetMicroseconds: compiledTargetMicroseconds,
                    sign: sign,
                  ),
                  threshold: threshold,
                );
                final legacyGrade = switch (measurement.legacyTiming) {
                  Timing.perfect => TimingGrade.perfect,
                  Timing.good => TimingGrade.good,
                  Timing.early => TimingGrade.early,
                  Timing.late => TimingGrade.late,
                  null => null,
                };
                if (legacyGrade == measurement.compiledGrade) continue;

                divergenceCellCount++;
                final descriptor =
                    '${lesson.id}:$eventIndex:'
                    '${legacyTargetMicroseconds.toStringAsFixed(12)}:'
                    '$compiledTargetMicroseconds:${threshold.microseconds}:'
                    '${latency.inMicroseconds}:$sign:'
                    '${measurement.legacyTiming?.name ?? 'noMatch'}:'
                    '${measurement.compiledGrade.name};';
                fingerprint = _fingerprint(fingerprint, descriptor);
                expect(
                  (legacyTargetMicroseconds - compiledTargetMicroseconds).abs(),
                  lessThanOrEqualTo(0.5),
                  reason: descriptor,
                );
              }
            }
          }
        }
      }

      // ignore: avoid_print
      print(
        'A7c exhaustiveDivergenceCells=$divergenceCellCount '
        'fingerprint=$fingerprint',
      );
      expect(divergenceCellCount, 3213);
      expect(fingerprint, 375672841);
    });
  });
}

({int excludedGuardBandEventCount}) _runParityScenario(
  Lesson lesson,
  Duration latency,
) {
  final target = _compiledTargetFor(lesson);
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
  final observations = _parityObservationsFor(lesson, target, latency);
  final observationsByTargetIndex = <int, StrumObservation>{};
  var excludedGuardBandEventCount = 0;

  for (final observation in observations) {
    matcher.advance(observation.at);
    legacy.advance(
      observation.at.inMicroseconds / Duration.microsecondsPerSecond,
    );
    final matched = matcher.registerStrum(observation);
    if (matched != null) {
      observationsByTargetIndex[matched.targetIndex] = observation;
    }
    legacy.registerStrum(
      observation.direction,
      observation.at.inMicroseconds / Duration.microsecondsPerSecond,
    );
  }
  matcher.finalize();
  legacy.finalize();

  for (final result in matcher.results.where((result) => result.isMatched)) {
    final magnitude = result.timingOffset!.inMicroseconds.abs();
    final inGuardBand = <int>[
      ScoringProfile.legacyLearnParity.perfectWindow.inMicroseconds,
      ScoringProfile.legacyLearnParity.goodWindow.inMicroseconds,
      ScoringProfile.legacyLearnParity.matchWindow.inMicroseconds,
    ].any((threshold) => (magnitude - threshold).abs() < 1);
    if (inGuardBand) excludedGuardBandEventCount++;
  }
  expect(
    excludedGuardBandEventCount,
    0,
    reason: '${lesson.id}@${latency.inMilliseconds}ms guard-band construction',
  );

  final timing = const PracticeTimingScorer().score(
    matches: matcher.results,
    scoringProfile: ScoringProfile.legacyLearnParity,
  );
  final direction = const PracticeDirectionScorer().score(
    matches: matcher.results,
    observationsByTargetIndex: observationsByTargetIndex,
  );
  final chord = const PracticeChordScorer().score(
    matches: matcher.results,
    observations: const [],
  );
  final aggregation = const PracticeScoreAggregator().aggregate(
    matches: matcher.results,
    scoringProfile: ScoringProfile.legacyLearnParity,
    timing: timing,
    direction: direction,
    chord: chord,
  );
  final verdicts = aggregation.verdicts;
  final correct = verdicts
      .where((verdict) => verdict.directionOutcome == DirectionOutcome.correct)
      .length;
  final wrongMatched = verdicts
      .where(
        (verdict) =>
            verdict.matchedObservationSequence != null &&
            verdict.directionOutcome == DirectionOutcome.wrong,
      )
      .length;
  final missed = verdicts
      .where((verdict) => verdict.matchedObservationSequence == null)
      .length;
  final perfect = verdicts
      .where((verdict) => verdict.timingGrade == TimingGrade.perfect)
      .length;
  final directionMetric = aggregation.metrics.direction as MetricAvailable;

  expect(
    aggregation.metrics.scorePoints,
    legacy.score,
    reason: '${lesson.id}@${latency.inMilliseconds}ms score',
  );
  expect(
    aggregation.metrics.maxCombo,
    legacy.maxCombo,
    reason: '${lesson.id}@${latency.inMilliseconds}ms max combo',
  );
  expect(correct, legacy.hits);
  expect(wrongMatched, legacy.wrong);
  expect(missed, legacy.missed);
  expect(directionMetric.value, legacy.accuracy);
  expect(
    perfect,
    legacy.perfectHits,
    reason: '${lesson.id}@${latency.inMilliseconds}ms perfect hits',
  );
  expect(aggregation.metrics.validate(), isEmpty);
  for (final verdict in verdicts) {
    expect(verdict.validate(), isEmpty, reason: verdict.targetEventId);
  }

  return (excludedGuardBandEventCount: excludedGuardBandEventCount);
}

List<StrumObservation> _parityObservationsFor(
  Lesson lesson,
  CompiledPracticeTarget target,
  Duration latency,
) {
  final planned = <({Duration at, StrumDirection direction})>[];
  final hitCount = target.events.length ~/ 2;

  for (var index = 0; index < target.events.length; index++) {
    final event = target.events[index];
    if (index < hitCount) {
      final offset = switch (index) {
        0 => const Duration(milliseconds: 80),
        1 => const Duration(milliseconds: -200),
        _ => Duration.zero,
      };
      planned.add((
        at: event.time + offset + latency,
        direction: event.direction!,
      ));
    } else if ((index - hitCount).isEven) {
      planned.add((
        at: event.time + latency,
        direction: _opposite(event.direction!),
      ));
    }
  }
  planned.sort((left, right) => left.at.compareTo(right.at));

  for (var index = 1; index < planned.length; index++) {
    expect(
      planned[index].at,
      greaterThanOrEqualTo(planned[index - 1].at),
      reason: '${lesson.id} observation order',
    );
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

void _expectPinnedDivergence({
  required Lesson lesson,
  required CompiledPracticeTarget target,
  required Duration latency,
  required _DivergenceCell cell,
  required ({
    int microseconds,
    Timing expectedLegacyTiming,
    TimingGrade expectedCompiledEarly,
    TimingGrade expectedCompiledLate,
  })
  threshold,
}) {
  final measurement = _measureBoundaryCell(
    lesson: lesson,
    target: target,
    latency: latency,
    cell: cell,
    threshold: threshold,
  );
  final context =
      '${cell.lessonId}[${cell.eventIndex}] '
      '${latency.inMilliseconds}ms ${cell.sign < 0 ? 'early' : 'late'} '
      '${threshold.microseconds}us';

  expect(
    measurement.compiledTargetIndex,
    cell.eventIndex,
    reason: '$context compiled match',
  );
  expect(
    measurement.compiledGrade,
    cell.sign < 0
        ? threshold.expectedCompiledEarly
        : threshold.expectedCompiledLate,
    reason: '$context compiled grade',
  );
  if (threshold.microseconds ==
      ScoringProfile.legacyLearnParity.matchWindow.inMicroseconds) {
    expect(
      measurement.legacyResult,
      isNull,
      reason: '$context legacy eligibility',
    );
    expect(measurement.legacyTiming, isNull, reason: '$context legacy grade');
  } else {
    expect(
      measurement.legacyResult,
      HitResult.hit,
      reason: '$context legacy match',
    );
    expect(
      measurement.legacyTiming,
      cell.sign < 0
          ? threshold.expectedLegacyTiming
          : threshold.expectedLegacyTiming == Timing.early
          ? Timing.late
          : threshold.expectedLegacyTiming,
      reason: '$context legacy grade',
    );
  }
}

({
  HitResult? legacyResult,
  Timing? legacyTiming,
  int? compiledTargetIndex,
  TimingGrade compiledGrade,
})
_measureBoundaryCell({
  required Lesson lesson,
  required CompiledPracticeTarget target,
  required Duration latency,
  required _DivergenceCell cell,
  required ({
    int microseconds,
    Timing expectedLegacyTiming,
    TimingGrade expectedCompiledEarly,
    TimingGrade expectedCompiledLate,
  })
  threshold,
}) {
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
  var sequence = 0;
  for (var index = 0; index < lesson.events.length; index++) {
    if (index == cell.eventIndex) continue;
    final at = target.events[index].time + latency;
    matcher.registerStrum(
      StrumObservation(
        at: at,
        sequence: sequence,
        direction: lesson.events[index].direction,
        confidence: 1,
      ),
    );
    legacy.registerStrum(
      lesson.events[index].direction,
      at.inMicroseconds / Duration.microsecondsPerSecond,
    );
    sequence++;
  }

  final event = lesson.events[cell.eventIndex];
  final rawObservationAt = Duration(
    microseconds:
        cell.compiledTargetMicroseconds +
        cell.sign * threshold.microseconds +
        latency.inMicroseconds,
  );
  final legacyResult = legacy.registerStrum(
    event.direction,
    rawObservationAt.inMicroseconds / Duration.microsecondsPerSecond,
  );
  final match = matcher.registerStrum(
    StrumObservation(
      at: rawObservationAt,
      sequence: sequence,
      direction: event.direction,
      confidence: 1,
    ),
  );
  final timing = const PracticeTimingScorer().score(
    matches: matcher.results,
    scoringProfile: ScoringProfile.legacyLearnParity,
  );
  return (
    legacyResult: legacyResult,
    legacyTiming: legacyResult == null ? null : legacy.lastTiming,
    compiledTargetIndex: match?.targetIndex,
    compiledGrade: timing.events[cell.eventIndex].grade,
  );
}

int _fingerprint(int current, String value) {
  var result = current;
  for (final codeUnit in value.codeUnits) {
    result = (result * 31 + codeUnit) % 1000000007;
  }
  return result;
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

final class _DivergenceCell {
  const _DivergenceCell({
    required this.lessonId,
    required this.eventIndex,
    required this.legacyTargetMicroseconds,
    required this.compiledTargetMicroseconds,
    required this.sign,
  });

  final String lessonId;
  final int eventIndex;
  final double legacyTargetMicroseconds;
  final int compiledTargetMicroseconds;
  final int sign;
}
