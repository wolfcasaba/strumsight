import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/data/adapters/analyze_practice_adapter.dart';
import 'package:strumsight/features/practice/data/adapters/daily_challenge_practice_adapter.dart';
import 'package:strumsight/features/practice/data/adapters/lesson_practice_adapter.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/beat_time_converter.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../../support/practice_baseline_scenarios.dart';

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

const _builtinIds = <String>[
  'builtin.quarterDownstrokes.v1',
  'builtin.alternatingEighths.v1',
  'builtin.folkPattern.v1',
  'builtin.gToDChanges.v1',
  'builtin.emToCChanges.v1',
  'builtin.cGAmFProgression.v1',
  'builtin.firstWaltz.v1',
  'builtin.syncopatedUps.v1',
  'builtin.rhythmOnlyQuarters.v1',
  'builtin.freePracticeTemplate.v1',
];

void main() {
  group('Practice target legacy baseline parity', () {
    test('ten frozen scenarios match finish and every event within 1 us', () {
      expect(legacyPracticeBaselineScenarios, hasLength(10));
      var maximumFinishDifference = 0;
      var maximumEventDifference = 0;

      for (final scenario in legacyPracticeBaselineScenarios) {
        final definition = _definition(
          practiceDefinitionFromLesson(scenario.lesson),
        );
        final target = _target(
          compilePracticeTarget(
            definition: definition,
            config: _config(definition, Tempo(scenario.bpm)),
          ),
        );
        final legacyFinishMicroseconds =
            (scenario.finishAtSec * Duration.microsecondsPerSecond).round();
        final finishDifference =
            (target.totalDuration.inMicroseconds - legacyFinishMicroseconds)
                .abs();
        if (finishDifference > maximumFinishDifference) {
          maximumFinishDifference = finishDifference;
        }
        expect(
          finishDifference,
          lessThanOrEqualTo(1),
          reason:
              '${scenario.id} finish differs by $finishDifference us: '
              'compiled=${target.totalDuration.inMicroseconds}, '
              'legacy=$legacyFinishMicroseconds',
        );

        expect(target.events, hasLength(scenario.lesson.events.length));
        for (var index = 0; index < scenario.lesson.events.length; index++) {
          final sourceEvent = scenario.lesson.events[index];
          final legacyEventMicroseconds =
              ((scenario.countInBeats + sourceEvent.beat) *
                      60 /
                      scenario.bpm *
                      Duration.microsecondsPerSecond)
                  .round();
          final eventDifference =
              (target.events[index].time.inMicroseconds -
                      legacyEventMicroseconds)
                  .abs();
          if (eventDifference > maximumEventDifference) {
            maximumEventDifference = eventDifference;
          }
          expect(
            eventDifference,
            lessThanOrEqualTo(1),
            reason:
                '${scenario.id} event $index differs by $eventDifference us: '
                'compiled=${target.events[index].time.inMicroseconds}, '
                'legacy=$legacyEventMicroseconds',
          );
        }
      }

      expect(maximumFinishDifference, 0);
      expect(maximumEventDifference, 0);
    });
  });

  group('Practice target shipped-lesson parity', () {
    final lessons = <Lesson>[...Lessons.all, Lessons.firstWin];

    test('pins all 17 lesson IDs in the measured order', () {
      expect(lessons.map((lesson) => lesson.id), _lessonIds);
    });

    test('all valid 50, 75 and 100 percent tempos match within 1 us', () {
      const speeds = <double>[0.5, 0.75, 1.0];
      final skipped = <String>[];
      var maximumEventDifference = 0;

      for (final lesson in lessons) {
        final definition = _definition(practiceDefinitionFromLesson(lesson));
        for (final speed in speeds) {
          final effectiveTempo = Tempo(lesson.bpm * speed);
          if (effectiveTempo.validate().isNotEmpty) {
            skipped.add(
              '${lesson.id}@${speed}x: '
              '${effectiveTempo.bpm} BPM is outside 30..300',
            );
            continue;
          }
          final target = _target(
            compilePracticeTarget(
              definition: definition,
              config: _config(definition, effectiveTempo),
            ),
          );

          expect(target.events, hasLength(lesson.events.length));
          for (var index = 0; index < lesson.events.length; index++) {
            final legacyEventMicroseconds =
                ((lesson.beatsPerBar + lesson.events[index].beat) *
                        60 /
                        effectiveTempo.bpm *
                        Duration.microsecondsPerSecond)
                    .round();
            final difference =
                (target.events[index].time.inMicroseconds -
                        legacyEventMicroseconds)
                    .abs();
            if (difference > maximumEventDifference) {
              maximumEventDifference = difference;
            }
            expect(
              difference,
              lessThanOrEqualTo(1),
              reason:
                  '${lesson.id}@${speed}x event $index differs by '
                  '$difference us',
            );
          }
        }
      }

      expect(skipped, isEmpty);
      expect(maximumEventDifference, 0);
    });

    test('first-waltz explicitly measures the three-beat count-in edge', () {
      final lesson = lessons.singleWhere(
        (candidate) => candidate.id == 'first-waltz',
      );
      final definition = _definition(practiceDefinitionFromLesson(lesson));
      final target = _target(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, Tempo(lesson.bpm)),
        ),
      );

      expect(lesson.beatsPerBar, 3);
      expect(
        target.countInDuration.inMicroseconds,
        (3 * 60 / lesson.bpm * Duration.microsecondsPerSecond).round(),
      );
    });

    test('eighth-drive explicitly measures its closest-to-end event', () {
      final lesson = lessons.singleWhere(
        (candidate) => candidate.id == 'eighth-drive',
      );
      final definition = _definition(practiceDefinitionFromLesson(lesson));
      final target = _target(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, Tempo(lesson.bpm)),
        ),
      );

      expect(
        definition.totalBeats.ticks - definition.events.last.position.ticks,
        240,
      );
      expect(target.events.last.sourceEventId, definition.events.last.id);
    });
  });

  group('Practice target corpus invariants', () {
    test('whole-bar rounding is a no-op for every pinned shipped ID', () {
      final definitions = <PracticeDefinition>[
        for (final lesson in <Lesson>[...Lessons.all, Lessons.firstWin])
          _definition(practiceDefinitionFromLesson(lesson)),
        ...const BuiltinPracticeCatalog().all(),
        _definition(
          practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
        ),
      ];
      final examinedIds = <String>[
        ..._lessonIds.map((id) => 'lesson.$id.v1'),
        ..._builtinIds,
        'dailyChallenge.20000.v1',
      ];

      expect(definitions.map((definition) => definition.id), examinedIds);
      for (final definition in definitions) {
        expect(
          definition.totalBeats.ticks % definition.meter.ticksPerBar,
          0,
          reason: '${definition.id} must already end on a bar boundary',
        );
        final target = _target(
          compilePracticeTarget(
            definition: definition,
            config: _config(definition, definition.defaultTempo),
          ),
        );
        for (var index = 1; index < target.events.length; index++) {
          expect(
            target.events[index].time,
            greaterThanOrEqualTo(target.events[index - 1].time),
            reason: '${definition.id} event timeline must be nondecreasing',
          );
        }
        expect(
          target.totalDuration,
          target.countInDuration +
              target.musicalDuration +
              target.ringOutDuration,
          reason: '${definition.id} total duration composition',
        );
      }
    });

    test('eventless Analyze import keeps one positive 4/4 bar', () {
      final definition = _definition(
        practiceDefinitionFromAnalyze(
          const AnalyzeResult(durationSec: 0, bpm: 90, chords: [], strums: []),
          sourceId: 'empty-clip',
          title: 'Empty clip',
        ),
      );
      final target = _target(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, definition.defaultTempo),
        ),
      );

      expect(definition.events, isEmpty);
      expect(definition.totalBeats.ticks, greaterThan(0));
      expect(target.events, isEmpty);
      final converter = BeatTimeConverter(
        tempo: definition.defaultTempo,
        meter: definition.meter,
      );
      final countInTicks = target.countInBars * definition.meter.ticksPerBar;
      expect(
        target.musicalDuration,
        converter.timeOfTicks(countInTicks + definition.meter.ticksPerBar) -
            converter.timeOfTicks(countInTicks),
      );
      expect(target.scoringApplicable, isFalse);
    });
  });
}

PracticeDefinition _definition(AppResult<PracticeDefinition> result) =>
    (result as Success<PracticeDefinition>).value;

CompiledPracticeTarget _target(AppResult<CompiledPracticeTarget> result) =>
    (result as Success<CompiledPracticeTarget>).value;

PracticeSessionConfig _config(PracticeDefinition definition, Tempo tempo) =>
    PracticeSessionConfig(
      definitionId: definition.id,
      definitionSnapshotVersion: definition.schemaVersion,
      effectiveTempo: tempo,
      countInBars: 1,
      loopCount: 1,
      metronomeEnabled: true,
      accentEnabled: true,
      backingEnabled: false,
      scoringProfileId: definition.scoringProfile.id,
      inputLatency: Duration.zero,
      visualLatency: Duration.zero,
      expectedChordHintEnabled: true,
      sessionTimeout: const Duration(minutes: 10),
      reducedMotion: false,
    );
