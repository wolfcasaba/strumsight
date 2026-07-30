import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/lesson_scorer.dart';
import 'package:strumsight/features/learn/model/lesson.dart';

import '../../support/practice_baseline_scenarios.dart';

const _goldenPath = 'test/fixtures/practice/legacy_scorer_baseline.json';

/// ADR 0067 §1/§3: this golden records legacy behavior; it does not prescribe it.
/// Regenerate only in a reviewable commit with a stated reason.
const _generatorEnvironmentKey = 'UPDATE_LEGACY_SCORER_BASELINE';
const _legacyMatchWindowSec = 0.28;
const _legacyPerfectWindowSec = 0.05;
const _legacyGoodWindowSec = 0.12;

final _generatorMode = Platform.environment[_generatorEnvironmentKey] == '1';

void main() {
  test('scenario catalog contains every required deterministic baseline', () {
    const requiredIds = {
      'p44_basic_all_perfect',
      'p44_all_late',
      'p44_timing_tiers',
      'p44_wrong_direction',
      'p44_extra_strums',
      'p44_chord_lag',
      'p44_input_latency',
      'p44_dejittered',
      'p44_eighths_contended',
      'p34_waltz',
    };
    final ids = legacyPracticeBaselineScenarios
        .map((scenario) => scenario.id)
        .toList();

    expect(ids.toSet(), requiredIds);
    expect(ids, hasLength(requiredIds.length), reason: 'IDs must be unique');
    for (final scenario in legacyPracticeBaselineScenarios) {
      expect(
        scenario.countInBeats,
        scenario.lesson.beatsPerBar,
        reason: '${scenario.id} must use the real one-bar count-in path',
      );
    }

    final deJittered = legacyPracticeBaselineScenarios.singleWhere(
      (scenario) => scenario.id == 'p44_dejittered',
    );
    for (final strum in deJittered.strums) {
      expect(strum.frameArrivalSec, isNotNull);
      final lag = strum.frameArrivalSec! - strum.elapsedSec;
      expect(lag, greaterThan(0));
      expect(lag, lessThan(0.5));
    }
  });

  test('contended eighths exercise overlapping legacy match windows', () {
    final scenario = legacyPracticeBaselineScenarios.singleWhere(
      (scenario) => scenario.id == 'p44_eighths_contended',
    );
    final targetTimes = [
      for (var i = 0; i < scenario.lesson.events.length; i++)
        _legacyEventTimeSec(scenario, i),
    ];

    expect(scenario.bpm, 96);
    for (var i = 1; i < targetTimes.length; i++) {
      final spacing = targetTimes[i] - targetTimes[i - 1];
      expect(spacing, 0.3125);
      expect(spacing, lessThan(2 * _legacyMatchWindowSec));
    }

    final tie = scenario.strums[1];
    expect(tie.targetEventIndex, 1);
    expect(
      (tie.elapsedSec - targetTimes[1]).abs(),
      (tie.elapsedSec - targetTimes[2]).abs(),
    );

    final consumedExtra = scenario.strums.singleWhere(
      (strum) => strum.legacyMatchedEventIndex != null,
    );
    expect(consumedExtra.targetEventIndex, isNull);
    expect(consumedExtra.legacyMatchedEventIndex, 2);
    final consumedDelta = (consumedExtra.elapsedSec - targetTimes[2]).abs();
    final competingDelta = (consumedExtra.elapsedSec - targetTimes[3]).abs();
    expect(consumedDelta, lessThanOrEqualTo(_legacyMatchWindowSec));
    expect(competingDelta, lessThanOrEqualTo(_legacyMatchWindowSec));
    expect(consumedDelta, lessThan(competingDelta));
    expect(consumedExtra.direction, isNot(scenario.lesson.events[2].direction));

    final reopenAttempt = scenario.strums.singleWhere(
      (strum) => strum.frameArrivalSec != null,
    );
    final reopenTargetTime = targetTimes[reopenAttempt.targetEventIndex!];
    expect(
      (reopenAttempt.elapsedSec - reopenTargetTime).abs(),
      lessThanOrEqualTo(_legacyMatchWindowSec),
    );
    expect(
      reopenAttempt.frameArrivalSec,
      greaterThan(reopenTargetTime + _legacyMatchWindowSec),
    );
  });

  test('replay rejects a target annotation that is not the matched event', () {
    const lesson = Lesson.fromEvents(
      id: 'test-only-overlapping-events',
      name: 'Test-only overlapping events',
      bpm: 60,
      totalBeats: 0.5,
      events: [
        LessonEvent(beat: 0, chord: '', direction: StrumDirection.down),
        LessonEvent(beat: 0.25, chord: '', direction: StrumDirection.down),
      ],
    );
    final misannotated = PracticeBaselineScenario(
      id: 'test-only-misannotated-target',
      lesson: lesson,
      bpm: 60,
      countInBeats: 4,
      strums: const [
        PracticeBaselineStrum(
          elapsedSec: 4,
          direction: StrumDirection.down,
          targetEventIndex: 1,
        ),
        PracticeBaselineStrum(
          elapsedSec: 4.25,
          direction: StrumDirection.down,
          targetEventIndex: 0,
        ),
      ],
      chordObservations: const [],
    );

    expect(() => _runScenario(misannotated), throwsA(isA<TestFailure>()));
  });

  test('replay advances at frame arrival before a de-jittered strum', () {
    final source = legacyPracticeBaselineScenarios.first;
    final delayedFrame = PracticeBaselineScenario(
      id: 'test-only-delayed-frame',
      lesson: source.lesson,
      bpm: source.bpm,
      countInBeats: source.countInBeats,
      strums: [
        PracticeBaselineStrum(
          elapsedSec: 4,
          frameArrivalSec: 4.3,
          direction: source.strums.first.direction,
          targetEventIndex: 0,
        ),
      ],
      chordObservations: const [],
    );

    final finalState =
        _runScenario(delayedFrame)['final']! as Map<String, Object?>;
    expect(finalState['hits'], 0);
    expect(finalState['missed'], source.lesson.events.length);
  });

  test(
    'legacy LessonScorer replay matches the frozen JSON byte for byte',
    () {
      final expected = File(_goldenPath).readAsStringSync();
      expect(_encodeCurrentBaseline(), expected);
    },
    skip: _generatorMode
        ? 'Generator mode writes the reviewed baseline fixture.'
        : false,
  );

  test(
    'GENERATE legacy LessonScorer baseline JSON',
    () {
      final golden = File(_goldenPath);
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(_encodeCurrentBaseline(), flush: true);
    },
    skip: _generatorMode
        ? false
        : 'Set $_generatorEnvironmentKey=1 and run this test by name.',
  );
}

String _encodeCurrentBaseline() {
  final document = <String, Object?>{
    'schemaVersion': 1,
    'engine': 'legacyLessonScorer',
    'scenarios': [
      for (final scenario in legacyPracticeBaselineScenarios)
        _runScenario(scenario),
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

Map<String, Object?> _runScenario(PracticeBaselineScenario scenario) {
  final scorer = LessonScorer(
    scenario.lesson,
    countInBeats: scenario.countInBeats,
    bpm: scenario.bpm,
    inputLatencySec: scenario.inputLatencySec,
  );
  final verdicts = List<Map<String, Object?>?>.filled(
    scenario.lesson.events.length,
    null,
  );
  final actions = <_ReplayAction>[
    for (var i = 0; i < scenario.strums.length; i++)
      _StrumAction(i, scenario.strums[i]),
    for (var i = 0; i < scenario.chordObservations.length; i++)
      _ChordAction(i, scenario.chordObservations[i]),
  ]..sort(_compareActions);

  for (final action in actions) {
    scorer.advance(action.dispatchSec);
    _captureMisses(
      scenario: scenario,
      scorer: scorer,
      elapsedSec: action.dispatchSec,
      verdicts: verdicts,
    );

    switch (action) {
      case _StrumAction(:final index, :final strum):
        final matchedEventIndex = _legacyMatchedEventIndex(
          scenario: scenario,
          strum: strum,
          verdicts: verdicts,
        );
        final result = scorer.registerStrum(strum.direction, strum.elapsedSec);
        final annotatedTarget = strum.targetEventIndex;

        if (matchedEventIndex == null) {
          expect(
            strum.legacyMatchedEventIndex,
            isNull,
            reason:
                '${scenario.id} expected a legacy-consumed extra but the '
                'observation matched no event',
          );
          expect(
            result,
            isNull,
            reason: '${scenario.id} strum $index unexpectedly matched an event',
          );
          if (annotatedTarget != null) {
            expect(
              verdicts[annotatedTarget]?['result'],
              HitResult.missed.name,
              reason:
                  '${scenario.id} intended target $annotatedTarget did not '
                  'match and was not already closed as missed',
            );
          }
        } else {
          final expectedMatchedEventIndex =
              annotatedTarget ?? strum.legacyMatchedEventIndex;
          expect(
            expectedMatchedEventIndex,
            matchedEventIndex,
            reason:
                '${scenario.id} strum $index annotation must identify the '
                'nearest still-open legacy event',
          );
          expect(
            verdicts[matchedEventIndex],
            isNull,
            reason: '${scenario.id} target $matchedEventIndex resolved twice',
          );

          final event = scenario.lesson.events[matchedEventIndex];
          final expectedResult = strum.direction == event.direction
              ? HitResult.hit
              : HitResult.wrongDirection;
          final playedSec = strum.elapsedSec - scenario.inputLatencySec;
          final offsetSec =
              playedSec - _legacyEventTimeSec(scenario, matchedEventIndex);
          final expectedTiming = expectedResult == HitResult.hit
              ? _legacyTimingFor(offsetSec)
              : null;
          final expectedDirection = expectedResult == HitResult.wrongDirection
              ? event.direction
              : null;

          expect(
            result,
            expectedResult,
            reason:
                '${scenario.id} scorer result must agree with the independently '
                'matched event $matchedEventIndex',
          );
          expect(
            scorer.lastTiming,
            expectedTiming,
            reason:
                '${scenario.id} scorer timing must agree with legacy windows',
          );
          expect(
            scorer.lastExpectedDirection,
            expectedDirection,
            reason:
                '${scenario.id} expected direction must come from the matched '
                'event',
          );
          verdicts[matchedEventIndex] = _eventVerdict(
            eventIndex: matchedEventIndex,
            result: expectedResult.name,
            timing: expectedTiming?.name,
            expectedDirection: expectedDirection?.name,
          );
        }
      case _ChordAction(:final observation):
        scorer.observeChord(observation.label, observation.elapsedSec);
    }
  }

  scorer.advance(scenario.finishAtSec);
  _captureMisses(
    scenario: scenario,
    scorer: scorer,
    elapsedSec: scenario.finishAtSec,
    verdicts: verdicts,
  );
  expect(
    verdicts,
    everyElement(isNotNull),
    reason: '${scenario.id} ring-out must resolve every target before finalize',
  );
  final missedBeforeFinalize = scorer.missed;
  scorer.finalize();
  expect(
    scorer.missed,
    missedBeforeFinalize,
    reason: '${scenario.id} real screen path closes misses during ring-out',
  );

  return {
    'id': scenario.id,
    'final': {
      'hits': scorer.hits,
      'wrong': scorer.wrong,
      'missed': scorer.missed,
      'combo': scorer.combo,
      'maxCombo': scorer.maxCombo,
      'total': scorer.total,
      'perfect': scorer.perfectHits,
      'score': scorer.score,
      'multiplier': scorer.multiplier,
      'chordHits': scorer.chordHits,
      'chordTotal': scorer.chordTotal,
      'accuracy': scorer.accuracy,
      'passed': scorer.passed,
      'failStreak': scorer.failStreak,
    },
    'verdicts': verdicts.cast<Map<String, Object?>>(),
  };
}

void _captureMisses({
  required PracticeBaselineScenario scenario,
  required LessonScorer scorer,
  required double elapsedSec,
  required List<Map<String, Object?>?> verdicts,
}) {
  final playedSec = elapsedSec - scenario.inputLatencySec;
  for (var i = 0; i < scenario.lesson.events.length; i++) {
    if (verdicts[i] != null) continue;
    final targetTime = _legacyEventTimeSec(scenario, i);
    if (targetTime + _legacyMatchWindowSec < playedSec) {
      verdicts[i] = _eventVerdict(
        eventIndex: i,
        result: HitResult.missed.name,
        timing: null,
        expectedDirection: null,
      );
    }
  }

  final capturedMisses = verdicts
      .where((verdict) => verdict?['result'] == HitResult.missed.name)
      .length;
  expect(
    scorer.missed,
    capturedMisses,
    reason: '${scenario.id} replay must map every legacy miss to an event',
  );
}

int? _legacyMatchedEventIndex({
  required PracticeBaselineScenario scenario,
  required PracticeBaselineStrum strum,
  required List<Map<String, Object?>?> verdicts,
}) {
  final playedSec = strum.elapsedSec - scenario.inputLatencySec;
  int? bestIndex;
  var bestDelta = double.infinity;

  for (var i = 0; i < scenario.lesson.events.length; i++) {
    if (verdicts[i] != null) continue;
    final delta = (_legacyEventTimeSec(scenario, i) - playedSec).abs();
    if (delta <= _legacyMatchWindowSec && delta < bestDelta) {
      bestIndex = i;
      bestDelta = delta;
    }
  }

  return bestIndex;
}

double _legacyEventTimeSec(PracticeBaselineScenario scenario, int eventIndex) =>
    (scenario.countInBeats + scenario.lesson.events[eventIndex].beat) *
    60 /
    scenario.bpm;

Timing _legacyTimingFor(double offsetSec) {
  final magnitude = offsetSec.abs();
  if (magnitude <= _legacyPerfectWindowSec) return Timing.perfect;
  if (magnitude <= _legacyGoodWindowSec) return Timing.good;
  return offsetSec < 0 ? Timing.early : Timing.late;
}

Map<String, Object?> _eventVerdict({
  required int eventIndex,
  required String result,
  required String? timing,
  required String? expectedDirection,
}) => {
  'eventIndex': eventIndex,
  'result': result,
  'timing': timing,
  'expectedDirection': expectedDirection,
};

int _compareActions(_ReplayAction a, _ReplayAction b) {
  final byTime = a.dispatchSec.compareTo(b.dispatchSec);
  if (byTime != 0) return byTime;
  final byKind = a.kindOrder.compareTo(b.kindOrder);
  if (byKind != 0) return byKind;
  return a.index.compareTo(b.index);
}

sealed class _ReplayAction {
  const _ReplayAction(this.index);

  final int index;
  double get dispatchSec;

  /// The screen registers a strum before observing the chord from that frame.
  int get kindOrder;
}

final class _StrumAction extends _ReplayAction {
  const _StrumAction(super.index, this.strum);

  final PracticeBaselineStrum strum;

  @override
  double get dispatchSec => strum.frameArrivalSec ?? strum.elapsedSec;

  @override
  int get kindOrder => 0;
}

final class _ChordAction extends _ReplayAction {
  const _ChordAction(super.index, this.observation);

  final PracticeBaselineChordObservation observation;

  @override
  double get dispatchSec => observation.elapsedSec;

  @override
  int get kindOrder => 1;
}
