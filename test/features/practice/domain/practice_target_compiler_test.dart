import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/beat_time_converter.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';

void main() {
  group('PracticeTargetCompiler timeline structure', () {
    test('rounds a partial 4/4 definition up to a complete final bar', () {
      final definition = _definition(
        totalBeats: const BeatPosition(1921),
        events: const [
          PracticeEvent(
            id: 'event.0',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'event.1',
            position: BeatPosition(1920),
            direction: StrumDirection.up,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(120)),
        ),
      );

      expect(target.countInDuration, const Duration(seconds: 2));
      expect(target.musicalDuration, const Duration(seconds: 4));
      expect(target.ringOutDuration, const Duration(seconds: 2));
      expect(target.totalDuration, const Duration(seconds: 8));
      expect(target.barBoundaries, const [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 6),
      ]);
      expect(target.barBoundaries.length, target.countInBars + 2 + 1);
      expect(target.barBoundaries[target.countInBars], target.countInDuration);
      expect(
        target.barBoundaries.last,
        target.countInDuration + target.musicalDuration,
      );
    });

    test('uses three quarter beats per 3/4 count-in and bar step', () {
      final definition = _definition(
        meter: const Meter(beatsPerBar: 3),
        totalBeats: BeatPosition.quarters(6),
        events: const [
          PracticeEvent(
            id: 'event.0',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(120)),
        ),
      );

      expect(target.countInDuration, const Duration(milliseconds: 1500));
      expect(target.ringOutDuration, const Duration(milliseconds: 1500));
      expect(target.barBoundaries, const [
        Duration.zero,
        Duration(milliseconds: 1500),
        Duration(seconds: 3),
        Duration(milliseconds: 4500),
      ]);
    });

    test('pins two count-in bars and repeated-pass bar boundaries', () {
      final definition = _definition(totalBeats: BeatPosition.quarters(4));
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(
            definition,
            tempo: const Tempo(120),
            countInBars: 2,
            loopCount: 3,
          ),
        ),
      );

      expect(target.countInDuration, const Duration(seconds: 4));
      expect(target.musicalDuration, const Duration(seconds: 6));
      expect(target.barBoundaries, const [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 6),
        Duration(seconds: 8),
        Duration(seconds: 10),
      ]);
      expect(target.barBoundaries.length, target.countInBars + 3 + 1);
    });

    test(
      'gives a downbeat event and its bar boundary the same time at 90 BPM',
      () {
        final definition = _definition(
          totalBeats: BeatPosition.quarters(8),
          events: const [
            PracticeEvent(
              id: 'first.downbeat',
              position: BeatPosition(0),
              direction: StrumDirection.down,
            ),
            PracticeEvent(
              id: 'second.downbeat',
              position: BeatPosition(1920),
              direction: StrumDirection.down,
            ),
          ],
        );
        final target = _success(
          compilePracticeTarget(
            definition: definition,
            config: _config(definition, tempo: const Tempo(90)),
          ),
        );
        final secondDownbeat = target.events.singleWhere(
          (event) => event.sourceEventId == 'second.downbeat',
        );

        expect(secondDownbeat.time, target.barBoundaries[2]);
      },
    );

    test('computes total duration from all absolute ticks at 90 BPM', () {
      final definition = _definition(totalBeats: BeatPosition.quarters(4));
      const converter = BeatTimeConverter(
        tempo: Tempo(90),
        meter: Meter(beatsPerBar: 4),
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(90)),
        ),
      );
      final ticksPerBar = definition.meter.ticksPerBar;
      final countInTicks = target.countInBars * ticksPerBar;
      final musicalTicks = ticksPerBar;
      final countInEnd = converter.timeOfTicks(countInTicks);
      final musicalEnd = converter.timeOfTicks(countInTicks + musicalTicks);
      final sessionEnd = converter.timeOfTicks(
        countInTicks + musicalTicks + ticksPerBar,
      );

      expect(target.countInDuration, countInEnd);
      expect(target.musicalDuration, musicalEnd - countInEnd);
      expect(target.ringOutDuration, sessionEnd - musicalEnd);
      expect(
        target.totalDuration,
        target.countInDuration +
            target.musicalDuration +
            target.ringOutDuration,
      );
      expect(target.totalDuration, sessionEnd);
    });

    test('compiles the final in-range tick instead of dropping it', () {
      final definition = _definition(
        totalBeats: const BeatPosition(1920),
        events: const [
          PracticeEvent(
            id: 'last',
            position: BeatPosition(1919),
            direction: StrumDirection.down,
          ),
        ],
      );
      const converter = BeatTimeConverter(
        tempo: Tempo(90),
        meter: Meter(beatsPerBar: 4),
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(90)),
        ),
      );

      expect(target.events, hasLength(1));
      expect(target.events.single.sourceEventId, 'last');
      expect(target.events.single.time, converter.timeOfTicks(1920 + 1919));
    });

    test('uses effective tempo at 50 and 75 percent without accumulation', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(4),
        events: const [
          PracticeEvent(
            id: 'event.0',
            position: BeatPosition(480),
            direction: StrumDirection.down,
          ),
        ],
      );

      for (final tempo in const [Tempo(60), Tempo(90)]) {
        final converter = BeatTimeConverter(
          tempo: tempo,
          meter: definition.meter,
        );
        final target = _success(
          compilePracticeTarget(
            definition: definition,
            config: _config(definition, tempo: tempo),
          ),
        );
        expect(
          target.events.single.time,
          converter.timeOfTicks(definition.meter.ticksPerBar + 480),
        );
      }
    });

    test('excludes markers while preserving a one-event target', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(4),
        events: const [
          PracticeEvent(
            id: 'target',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'marker',
            position: BeatPosition(240),
            marker: true,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(120)),
        ),
      );

      expect(target.events, hasLength(1));
      expect(target.events.single.sourceEventId, 'target');
      expect(target.events.single.time, target.countInDuration);
      expect(target.scoringApplicable, isTrue);
    });

    test('projects target metadata and every scored event field', () {
      final definition = _definition(
        id: 'definition.projected',
        schemaVersion: 7,
        totalBeats: BeatPosition.quarters(8),
        events: const [
          PracticeEvent(
            id: 'projected',
            position: BeatPosition(2400),
            duration: BeatPosition(240),
            chord: 'G',
            direction: StrumDirection.up,
            accent: true,
            optional: true,
          ),
        ],
      );
      final config = _config(
        definition,
        tempo: const Tempo(90),
        countInBars: 2,
      );
      final target = _success(
        compilePracticeTarget(definition: definition, config: config),
      );
      final converter = BeatTimeConverter(
        tempo: config.effectiveTempo,
        meter: definition.meter,
      );

      expect(target.definitionId, definition.id);
      expect(target.definitionSnapshotVersion, definition.schemaVersion);
      expect(target.tempo, config.effectiveTempo);
      expect(target.meter, definition.meter);
      expect(target.countInBars, config.countInBars);
      expect(target.loopCount, config.loopCount);
      expect(target.loopRange, isNull);
      expect(target.events, [
        CompiledTargetEvent(
          sourceEventId: 'projected',
          loopIndex: 0,
          position: const BeatPosition(2400),
          time: converter.timeOfTicks(2 * 1920 + 2400),
          barIndex: 1,
          chord: 'G',
          direction: StrumDirection.up,
          accent: true,
          optional: true,
        ),
      ]);
      expect(target.scoringApplicable, isTrue);
    });

    test('a marker-only scored definition compiles without scored events', () {
      final definition = _definition(
        events: const [
          PracticeEvent(id: 'marker', position: BeatPosition(0), marker: true),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition),
        ),
      );

      expect(target.events, isEmpty);
      expect(target.expectedChordSegments, isEmpty);
      expect(target.scoringApplicable, isFalse);
    });
  });

  group('PracticeTargetCompiler loops', () {
    test(
      'repeats every source event with absolute positions and loop indexes',
      () {
        final definition = _definition(
          totalBeats: BeatPosition.quarters(4),
          events: const [
            PracticeEvent(
              id: 'event.0',
              position: BeatPosition(0),
              direction: StrumDirection.down,
            ),
            PracticeEvent(
              id: 'event.1',
              position: BeatPosition(480),
              direction: StrumDirection.up,
            ),
          ],
        );
        final config = _config(
          definition,
          tempo: const Tempo(120),
          countInBars: 0,
          loopCount: 3,
        );
        final target = _success(
          compilePracticeTarget(definition: definition, config: config),
        );
        final converter = BeatTimeConverter(
          tempo: config.effectiveTempo,
          meter: definition.meter,
        );
        final passTicks = definition.meter.ticksPerBar;

        expect(target.events, hasLength(6));
        expect(target.events.map((event) => event.loopIndex), [
          0,
          0,
          1,
          1,
          2,
          2,
        ]);
        for (var loopIndex = 0; loopIndex < 3; loopIndex++) {
          for (var sourceIndex = 0; sourceIndex < 2; sourceIndex++) {
            final compiled = target.events[loopIndex * 2 + sourceIndex];
            final expectedTicks =
                loopIndex * passTicks +
                definition.events[sourceIndex].position.ticks;
            expect(compiled.position.ticks, expectedTicks);
            expect(compiled.time, converter.timeOfTicks(expectedTicks));
            expect(compiled.barIndex, expectedTicks ~/ passTicks);
          }
        }
      },
    );

    test('selects one source bar and rebases it before repeating', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(16),
        events: const [
          PracticeEvent(
            id: 'bar.0',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'bar.1',
            position: BeatPosition(1920),
            direction: StrumDirection.up,
          ),
          PracticeEvent(
            id: 'bar.2',
            position: BeatPosition(3840),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'bar.3',
            position: BeatPosition(5760),
            direction: StrumDirection.up,
          ),
        ],
      );
      const range = PracticeLoopRange(startBar: 1, endBarExclusive: 2);
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, countInBars: 0, loopCount: 2),
          loopRange: range,
        ),
      );

      expect(target.loopRange, range);
      expect(target.events.map((event) => event.sourceEventId), [
        'bar.1',
        'bar.1',
      ]);
      expect(target.events.map((event) => event.position.ticks), [0, 1920]);
      expect(
        target.events.every(
          (event) => event.position.ticks < 2 * definition.meter.ticksPerBar,
        ),
        isTrue,
      );
    });

    test('accepts the rounded final partial bar as a whole-bar loop', () {
      final definition = _definition(
        totalBeats: const BeatPosition(1921),
        events: const [
          PracticeEvent(
            id: 'partial.final-bar',
            position: BeatPosition(1920),
            direction: StrumDirection.down,
          ),
        ],
      );
      const range = PracticeLoopRange(startBar: 1, endBarExclusive: 2);
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, countInBars: 0),
          loopRange: range,
        ),
      );

      expect(target.loopRange, range);
      expect(target.events, hasLength(1));
      expect(target.events.single.sourceEventId, 'partial.final-bar');
      expect(target.events.single.position, const BeatPosition(0));
      expect(target.events.single.time, Duration.zero);
      expect(target.musicalDuration, const Duration(seconds: 2));
    });

    test('computes barIndex from ticksPerBar for multi-bar passes', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(8),
        events: const [
          PracticeEvent(
            id: 'bar.0',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'bar.1.beat.1',
            position: BeatPosition(2400),
            direction: StrumDirection.up,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, countInBars: 0, loopCount: 2),
        ),
      );

      expect(target.events.map((event) => event.position.ticks), [
        0,
        2400,
        3840,
        6240,
      ]);
      expect(target.events.map((event) => event.barIndex), [0, 1, 2, 3]);
    });

    for (final invalidRange in const [
      PracticeLoopRange(startBar: -1, endBarExclusive: 1),
      PracticeLoopRange(startBar: 1, endBarExclusive: 1),
      PracticeLoopRange(startBar: 0, endBarExclusive: 5),
    ]) {
      test('rejects invalid loop range $invalidRange without clamping', () {
        final definition = _definition(totalBeats: BeatPosition.quarters(16));
        final result = compilePracticeTarget(
          definition: definition,
          config: _config(definition),
          loopRange: invalidRange,
        );

        _expectCompilationFailure(
          result,
          PracticeValidationCode.targetLoopRangeInvalid,
        );
      });
    }
  });

  group('PracticeTargetCompiler expected-chord segments', () {
    test('matches the pinned legacy pre-roll and merges repeated labels', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(12),
        events: const [
          PracticeEvent(
            id: 'c.first',
            position: BeatPosition(0),
            chord: 'C',
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'direction.only',
            position: BeatPosition(480),
            direction: StrumDirection.up,
          ),
          PracticeEvent(
            id: 'c.repeated',
            position: BeatPosition(1920),
            chord: 'C',
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'g.change',
            position: BeatPosition(3840),
            chord: 'G',
            direction: StrumDirection.down,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(120)),
        ),
      );

      expect(target.expectedChordSegments, const [
        ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(microseconds: 5875000),
        ),
        ExpectedChordSegment(
          chord: 'G',
          start: Duration(microseconds: 5875000),
          end: Duration(seconds: 10),
        ),
      ]);
      expect(target.expectedChordSegments.first.start, Duration.zero);
      expect(target.expectedChordSegments.last.end, target.totalDuration);
      for (
        var index = 1;
        index < target.expectedChordSegments.length;
        index++
      ) {
        expect(
          target.expectedChordSegments[index - 1].end,
          target.expectedChordSegments[index].start,
        );
        expect(
          target.expectedChordSegments[index - 1].chord,
          isNot(target.expectedChordSegments[index].chord),
        );
      }
    });

    test('uses the named 120-tick lookahead for a one-beat chord change', () {
      final definition = _definition(
        totalBeats: BeatPosition.quarters(4),
        events: const [
          PracticeEvent(
            id: 'c',
            position: BeatPosition(0),
            chord: 'C',
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'g',
            position: BeatPosition(480),
            chord: 'G',
            direction: StrumDirection.down,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, tempo: const Tempo(120)),
        ),
      );
      const converter = BeatTimeConverter(
        tempo: Tempo(120),
        meter: Meter(beatsPerBar: 4),
      );
      final expectedStart =
          target.countInDuration +
          converter.timeOf(const BeatPosition(480 - 120));

      expect(
        PracticeTargetCompiler.expectedChordLookahead,
        const BeatPosition(120),
      );
      expect(target.expectedChordSegments.map((segment) => segment.start), [
        Duration.zero,
        expectedStart,
      ]);
      expect(expectedStart, const Duration(milliseconds: 2375));
    });

    test('returns no segments when no compiled event carries a chord', () {
      final definition = _definition(
        events: const [
          PracticeEvent(
            id: 'direction.only',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition),
        ),
      );

      expect(target.expectedChordSegments, isEmpty);
    });

    test('extends one chord across the complete session timeline', () {
      final definition = _definition(
        events: const [
          PracticeEvent(
            id: 'only.c',
            position: BeatPosition(0),
            chord: 'C',
            direction: StrumDirection.down,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition),
        ),
      );

      expect(target.expectedChordSegments, [
        ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: target.totalDuration,
        ),
      ]);
    });

    test('carries chord changes across a repeated loop boundary', () {
      final definition = _definition(
        events: const [
          PracticeEvent(
            id: 'c',
            position: BeatPosition(0),
            chord: 'C',
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'g',
            position: BeatPosition(480),
            chord: 'G',
            direction: StrumDirection.up,
          ),
        ],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, loopCount: 2),
        ),
      );

      expect(target.expectedChordSegments, const [
        ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(milliseconds: 2375),
        ),
        ExpectedChordSegment(
          chord: 'G',
          start: Duration(milliseconds: 2375),
          end: Duration(milliseconds: 3875),
        ),
        ExpectedChordSegment(
          chord: 'C',
          start: Duration(milliseconds: 3875),
          end: Duration(milliseconds: 4375),
        ),
        ExpectedChordSegment(
          chord: 'G',
          start: Duration(milliseconds: 4375),
          end: Duration(seconds: 8),
        ),
      ]);
    });
  });

  group('PracticeTargetCompiler validation order', () {
    test('definition validation wins and rejects zero totalBeats', () {
      final definition = _definition(
        id: '',
        mode: PracticeMode.freePractice,
        totalBeats: const BeatPosition(0),
        events: const [],
      );
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(definition, definitionId: 'different', countInBars: 5),
      );

      _expectCompilationFailure(
        result,
        PracticeValidationCode.targetDefinitionInvalid,
      );
    });

    test('config validation wins before definition ID mismatch', () {
      final definition = _definition();
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(definition, definitionId: 'different', countInBars: 5),
      );

      _expectCompilationFailure(
        result,
        PracticeValidationCode.targetConfigInvalid,
      );
    });

    test('definition ID mismatch wins before variation mismatch', () {
      final definition = _definition();
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(
          definition,
          definitionId: 'different',
          easyVariationId: 'also-different',
        ),
      );

      _expectCompilationFailure(
        result,
        PracticeValidationCode.targetDefinitionMismatch,
      );
    });

    test('rejects a non-matching Easy variation explicitly', () {
      final definition = _definition();
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(definition, easyVariationId: 'different'),
      );

      _expectCompilationFailure(
        result,
        PracticeValidationCode.targetVariationMismatch,
      );
    });

    test('variation mismatch wins before an invalid loop range', () {
      final definition = _definition();
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(definition, easyVariationId: 'different'),
        loopRange: const PracticeLoopRange(startBar: 1, endBarExclusive: 1),
      );

      _expectCompilationFailure(
        result,
        PracticeValidationCode.targetVariationMismatch,
      );
    });

    test('accepts a matching non-null Easy variation ID', () {
      final definition = _definition(id: 'definition.easy.v1');
      final result = compilePracticeTarget(
        definition: definition,
        config: _config(definition, easyVariationId: 'definition.easy.v1'),
      );

      expect(result, isA<Success<CompiledPracticeTarget>>());
    });
  });

  group('PracticeTargetCompiler empty and deterministic outputs', () {
    test('compiles positive-length Free Practice without target events', () {
      final definition = _definition(
        mode: PracticeMode.freePractice,
        totalBeats: BeatPosition.quarters(16),
        events: const [],
      );
      final target = _success(
        compilePracticeTarget(
          definition: definition,
          config: _config(definition, loopCount: 2),
        ),
      );

      expect(target.events, isEmpty);
      expect(target.scoringApplicable, isFalse);
      expect(target.expectedChordSegments, isEmpty);
      expect(target.countInDuration, const Duration(seconds: 2));
      expect(target.musicalDuration, const Duration(seconds: 16));
      expect(target.ringOutDuration, const Duration(seconds: 2));
      expect(target.totalDuration, const Duration(seconds: 20));
      expect(target.barBoundaries, const [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 6),
        Duration(seconds: 8),
        Duration(seconds: 10),
        Duration(seconds: 12),
        Duration(seconds: 14),
        Duration(seconds: 16),
        Duration(seconds: 18),
      ]);
      expect(
        target.totalDuration,
        target.countInDuration +
            target.musicalDuration +
            target.ringOutDuration,
      );
    });

    test(
      'returns equal, hash-equal targets with nondecreasing event times',
      () {
        final definition = _definition(
          totalBeats: BeatPosition.quarters(4),
          events: const [
            PracticeEvent(
              id: 'event.0',
              position: BeatPosition(0),
              direction: StrumDirection.down,
            ),
            PracticeEvent(
              id: 'event.1',
              position: BeatPosition(480),
              direction: StrumDirection.up,
            ),
          ],
        );
        final config = _config(definition, loopCount: 2);
        final first = _success(
          compilePracticeTarget(definition: definition, config: config),
        );
        final second = _success(
          compilePracticeTarget(definition: definition, config: config),
        );

        expect(first, second);
        expect(first.hashCode, second.hashCode);
        for (var index = 1; index < first.events.length; index++) {
          expect(
            first.events[index].time,
            greaterThanOrEqualTo(first.events[index - 1].time),
          );
        }
      },
    );
  });
}

CompiledPracticeTarget _success(AppResult<CompiledPracticeTarget> result) =>
    (result as Success<CompiledPracticeTarget>).value;

void _expectCompilationFailure(
  AppResult<CompiledPracticeTarget> result,
  String validationCode,
) {
  expect(result, isA<Failure<CompiledPracticeTarget>>());
  final failure = (result as Failure<CompiledPracticeTarget>).error;
  expect(failure.code, FailureCode.practiceTargetUncompilable);
  expect(failure.cause, isA<PracticeValidationFailure>());
  final cause = failure.cause! as PracticeValidationFailure;
  expect(cause.code, validationCode);
  expect(cause.message, contains(validationCode));
}

PracticeDefinition _definition({
  String id = 'definition',
  int schemaVersion = 1,
  Meter meter = const Meter(beatsPerBar: 4),
  PracticeMode mode = PracticeMode.strumPattern,
  BeatPosition? totalBeats,
  List<PracticeEvent>? events,
}) => PracticeDefinition(
  id: id,
  schemaVersion: schemaVersion,
  titleKey: 'practiceTitle',
  descriptionKey: 'practiceDescription',
  mode: mode,
  source: PracticeSource.builtin,
  meter: meter,
  defaultTempo: const Tempo(120),
  totalBeats: totalBeats ?? BeatPosition.quarters(4),
  events:
      events ??
      const [
        PracticeEvent(
          id: 'event.0',
          position: BeatPosition(0),
          direction: StrumDirection.down,
        ),
      ],
  scoringProfile: mode == PracticeMode.freePractice
      ? ScoringProfile.freePracticeOpen
      : ScoringProfile.legacyLearnParity,
  skillTags: const [],
);

PracticeSessionConfig _config(
  PracticeDefinition definition, {
  String? definitionId,
  Tempo tempo = const Tempo(120),
  int countInBars = 1,
  int loopCount = 1,
  String? easyVariationId,
}) => PracticeSessionConfig(
  definitionId: definitionId ?? definition.id,
  definitionSnapshotVersion: definition.schemaVersion,
  effectiveTempo: tempo,
  countInBars: countInBars,
  loopCount: loopCount,
  metronomeEnabled: true,
  accentEnabled: true,
  backingEnabled: false,
  scoringProfileId: definition.scoringProfile.id,
  easyVariationId: easyVariationId,
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: true,
  sessionTimeout: const Duration(minutes: 5),
  reducedMotion: false,
);
