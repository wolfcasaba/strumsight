import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('Compiled practice target value models', () {
    test(
      'scalar models compare structurally and hash equal values equally',
      () {
        final event = _eventValue();
        final sameEvent = _eventValue();

        const segment = ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(seconds: 2),
        );
        const sameSegment = ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(seconds: 2),
        );
        const differentSegment = ExpectedChordSegment(
          chord: 'G',
          start: Duration.zero,
          end: Duration(seconds: 2),
        );

        const loop = PracticeLoopRange(startBar: 1, endBarExclusive: 3);
        const sameLoop = PracticeLoopRange(startBar: 1, endBarExclusive: 3);
        const differentLoop = PracticeLoopRange(
          startBar: 0,
          endBarExclusive: 3,
        );

        expect(event, sameEvent);
        expect(event.hashCode, sameEvent.hashCode);
        for (final differentEvent in [
          _eventValue(sourceEventId: 'different'),
          _eventValue(loopIndex: 2),
          _eventValue(position: const BeatPosition(960)),
          _eventValue(time: const Duration(seconds: 2)),
          _eventValue(barIndex: 1),
          _eventValue(chord: 'G'),
          _eventValue(direction: StrumDirection.up),
          _eventValue(accent: false),
          _eventValue(optional: true),
        ]) {
          expect(event, isNot(differentEvent));
        }
        expect(segment, sameSegment);
        expect(segment.hashCode, sameSegment.hashCode);
        expect(segment, isNot(differentSegment));
        expect(
          segment,
          isNot(
            const ExpectedChordSegment(
              chord: 'C',
              start: Duration(microseconds: 1),
              end: Duration(seconds: 2),
            ),
          ),
        );
        expect(
          segment,
          isNot(
            const ExpectedChordSegment(
              chord: 'C',
              start: Duration.zero,
              end: Duration(seconds: 3),
            ),
          ),
        );
        expect(loop, sameLoop);
        expect(loop.hashCode, sameLoop.hashCode);
        expect(loop, isNot(differentLoop));
        expect(
          loop,
          isNot(const PracticeLoopRange(startBar: 1, endBarExclusive: 4)),
        );
      },
    );

    test('aggregate compares every list and scalar structurally', () {
      final first = _target();
      final second = _target();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect({first, second}, hasLength(1));
      for (final differentTarget in [
        _target(definitionId: 'different'),
        _target(definitionSnapshotVersion: 2),
        _target(tempo: const Tempo(90)),
        _target(meter: const Meter(beatsPerBar: 3)),
        _target(countInBars: 0),
        _target(countInDuration: const Duration(seconds: 1)),
        _target(events: const []),
        _target(musicalDuration: const Duration(seconds: 3)),
        _target(ringOutDuration: const Duration(seconds: 3)),
        _target(totalDuration: const Duration(seconds: 7)),
        _target(barBoundaries: const [Duration.zero]),
        _target(loopCount: 2),
        _target(loopRange: null),
        _target(expectedChordSegments: const []),
        _target(scoringApplicable: false),
      ]) {
        expect(first, isNot(differentTarget));
      }
    });

    test('aggregate stores unmodifiable snapshots of every list', () {
      final sourceEvents = <CompiledTargetEvent>[_event];
      final sourceBoundaries = <Duration>[
        Duration.zero,
        const Duration(seconds: 2),
      ];
      final sourceSegments = <ExpectedChordSegment>[_segment];
      final target = _target(
        events: sourceEvents,
        barBoundaries: sourceBoundaries,
        expectedChordSegments: sourceSegments,
      );

      sourceEvents.clear();
      sourceBoundaries.clear();
      sourceSegments.clear();

      expect(target.events, [_event]);
      expect(target.barBoundaries, [Duration.zero, const Duration(seconds: 2)]);
      expect(target.expectedChordSegments, [_segment]);
      expect(() => target.events.add(_event), throwsUnsupportedError);
      expect(
        () => target.barBoundaries.add(Duration.zero),
        throwsUnsupportedError,
      );
      expect(
        () => target.expectedChordSegments.add(_segment),
        throwsUnsupportedError,
      );
    });
  });
}

const _event = CompiledTargetEvent(
  sourceEventId: 'event.0',
  loopIndex: 0,
  position: BeatPosition(0),
  time: Duration(seconds: 2),
  barIndex: 0,
  chord: 'C',
  direction: StrumDirection.down,
  accent: false,
  optional: false,
);

const _segment = ExpectedChordSegment(
  chord: 'C',
  start: Duration.zero,
  end: Duration(seconds: 5),
);

CompiledTargetEvent _eventValue({
  String sourceEventId = 'event.0',
  int loopIndex = 1,
  BeatPosition position = const BeatPosition(480),
  Duration time = const Duration(milliseconds: 1500),
  int barIndex = 0,
  String? chord = 'C',
  StrumDirection? direction = StrumDirection.down,
  bool accent = true,
  bool optional = false,
}) => CompiledTargetEvent(
  sourceEventId: sourceEventId,
  loopIndex: loopIndex,
  position: position,
  time: time,
  barIndex: barIndex,
  chord: chord,
  direction: direction,
  accent: accent,
  optional: optional,
);

CompiledPracticeTarget _target({
  String definitionId = 'definition',
  int definitionSnapshotVersion = 1,
  Tempo tempo = const Tempo(120),
  Meter meter = const Meter(beatsPerBar: 4),
  int countInBars = 1,
  Duration countInDuration = const Duration(seconds: 2),
  List<CompiledTargetEvent>? events,
  Duration musicalDuration = const Duration(seconds: 2),
  Duration ringOutDuration = const Duration(seconds: 2),
  Duration totalDuration = const Duration(seconds: 6),
  List<Duration>? barBoundaries,
  int loopCount = 1,
  PracticeLoopRange? loopRange = const PracticeLoopRange(
    startBar: 0,
    endBarExclusive: 1,
  ),
  List<ExpectedChordSegment>? expectedChordSegments,
  bool scoringApplicable = true,
}) => CompiledPracticeTarget(
  definitionId: definitionId,
  definitionSnapshotVersion: definitionSnapshotVersion,
  tempo: tempo,
  meter: meter,
  countInBars: countInBars,
  countInDuration: countInDuration,
  events: events ?? const [_event],
  musicalDuration: musicalDuration,
  ringOutDuration: ringOutDuration,
  totalDuration: totalDuration,
  barBoundaries: barBoundaries ?? const [Duration.zero, Duration(seconds: 2)],
  loopCount: loopCount,
  loopRange: loopRange,
  expectedChordSegments: expectedChordSegments ?? const [_segment],
  scoringApplicable: scoringApplicable,
);
