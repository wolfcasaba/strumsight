import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

const _targetTime = Duration(microseconds: 2000000);
const _matchWindow = Duration(microseconds: 280000);

void main() {
  group('PracticeEventMatcher eligibility and close boundaries', () {
    test('pins all six cells around the 280 ms boundary', () {
      for (final cell in <({int delta, bool matched})>[
        (delta: 279999, matched: true),
        (delta: 280000, matched: true),
        (delta: 280001, matched: false),
      ]) {
        final matcher = _matcher([_targetTime]);
        final match = matcher.registerStrum(
          _observation(at: _targetTime + Duration(microseconds: cell.delta)),
        );
        expect(match != null, cell.matched, reason: 'match +${cell.delta} us');
      }

      for (final cell in <({int delta, PracticeTargetResolution resolution})>[
        (delta: 279999, resolution: PracticeTargetResolution.open),
        (delta: 280000, resolution: PracticeTargetResolution.open),
        (delta: 280001, resolution: PracticeTargetResolution.missed),
      ]) {
        final matcher = _matcher([_targetTime]);
        matcher.advance(_targetTime + Duration(microseconds: cell.delta));
        expect(
          matcher.results.single.resolution,
          cell.resolution,
          reason: 'close +${cell.delta} us',
        );
      }
    });

    test('exact boundary stays open and eligible after advance', () {
      final matcher = _matcher([_targetTime]);
      final boundary = _targetTime + _matchWindow;

      matcher.advance(boundary);
      expect(matcher.results.single.resolution, PracticeTargetResolution.open);

      final match = matcher.registerStrum(_observation(at: boundary));
      expect(match?.targetIndex, 0);
      expect(match?.timingOffset, _matchWindow);
      expect(
        matcher.results.single.resolution,
        PracticeTargetResolution.matched,
      );
    });
  });

  group('PracticeEventMatcher latency correction', () {
    test('pins matching and closing for 0, 40 and 300 ms latency', () {
      const latencies = <Duration>[
        Duration.zero,
        Duration(milliseconds: 40),
        Duration(milliseconds: 300),
      ];
      expect(latencies.last, greaterThan(_matchWindow));

      for (final latency in latencies) {
        final onBeat = _matcher([_targetTime], inputLatency: latency);
        final match = onBeat.registerStrum(
          _observation(at: _targetTime + latency),
        );
        expect(match?.observedAt, _targetTime, reason: '$latency observedAt');
        expect(match?.timingOffset, Duration.zero, reason: '$latency offset');

        final exactClose = _matcher([_targetTime], inputLatency: latency);
        exactClose.advance(_targetTime + _matchWindow + latency);
        expect(
          exactClose.results.single.resolution,
          PracticeTargetResolution.open,
          reason: '$latency exact close boundary',
        );

        final aboveClose = _matcher([_targetTime], inputLatency: latency);
        aboveClose.advance(
          _targetTime +
              _matchWindow +
              const Duration(microseconds: 1) +
              latency,
        );
        expect(
          aboveClose.results.single.resolution,
          PracticeTargetResolution.missed,
          reason: '$latency above close boundary',
        );
      }
    });
  });

  group('PracticeEventMatcher tie breaking', () {
    test('midpoint and neighboring microseconds choose the pinned target', () {
      const earlier = Duration(microseconds: 2000000);
      const later = Duration(microseconds: 2500000);
      const cells = <({int playedAt, int targetIndex, int offset})>[
        (playedAt: 2249999, targetIndex: 0, offset: 249999),
        (playedAt: 2250000, targetIndex: 0, offset: 250000),
        (playedAt: 2250001, targetIndex: 1, offset: -249999),
      ];

      for (final cell in cells) {
        final matcher = _matcher([earlier, later]);
        final match = matcher.registerStrum(
          _observation(at: Duration(microseconds: cell.playedAt)),
        );
        expect(match?.targetIndex, cell.targetIndex);
        expect(match?.timingOffset?.inMicroseconds, cell.offset);
      }
    });

    test('equal-time targets choose the smaller list index', () {
      final matcher = _matcher([_targetTime, _targetTime]);

      final match = matcher.registerStrum(_observation(at: _targetTime));

      expect(match?.targetIndex, 0);
      expect(matcher.results[0].isMatched, isTrue);
      expect(matcher.results[1].resolution, PracticeTargetResolution.open);
    });
  });

  group('PracticeEventMatcher one-to-one resolution', () {
    test('a wrong direction consumes the target before a correct retry', () {
      final matcher = _matcher([_targetTime]);
      final wrong = matcher.registerStrum(
        _observation(
          at: _targetTime,
          sequence: 10,
          direction: StrumDirection.up,
        ),
      );
      final retry = matcher.registerStrum(
        _observation(
          at: _targetTime,
          sequence: 11,
          direction: StrumDirection.down,
        ),
      );
      matcher.finalize();

      expect(wrong?.targetIndex, 0);
      expect(retry, isNull);
      expect(
        matcher.results.single.resolution,
        PracticeTargetResolution.matched,
      );
      expect(matcher.results.single.matchedObservationSequence, 10);
      expect(matcher.results.single.isMissed, isFalse);
    });

    test('an out-of-window extra leaves every target resolution unchanged', () {
      final matcher = _matcher([_targetTime]);
      final before = matcher.results.toList();
      final resolvedBefore = matcher.resolvedTargetCount;

      final match = matcher.registerStrum(
        _observation(at: const Duration(microseconds: 2280001)),
      );

      expect(match, isNull);
      expect(matcher.results, before);
      expect(matcher.resolvedTargetCount, resolvedBefore);
      expect(matcher.extraStrumCount, 1);
    });

    test('one observation resolves at most one of two eligible targets', () {
      final matcher = _matcher([
        const Duration(microseconds: 1900000),
        const Duration(microseconds: 2100000),
      ]);

      final match = matcher.registerStrum(_observation(at: _targetTime));

      expect(match?.targetIndex, 0);
      expect(matcher.resolvedTargetCount, 1);
      expect(matcher.results.where((result) => result.isMatched), hasLength(1));
    });

    test('a restarted gateway sequence can match a later target', () {
      final matcher = _matcher([
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);

      final first = matcher.registerStrum(
        _observation(at: const Duration(seconds: 1), sequence: 0),
      );
      final afterRestart = matcher.registerStrum(
        _observation(at: const Duration(seconds: 2), sequence: 0),
      );

      expect(first?.targetIndex, 0);
      expect(afterRestart?.targetIndex, 1);
      expect(matcher.resolvedTargetCount, 2);
    });

    test('resolved count is monotonic and terminal results never reopen', () {
      final matcher = _matcher([
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      ]);
      final counts = <int>[matcher.resolvedTargetCount];

      matcher.registerStrum(
        _observation(at: const Duration(seconds: 2), sequence: 20),
      );
      counts.add(matcher.resolvedTargetCount);
      matcher.advance(const Duration(microseconds: 1280001));
      counts.add(matcher.resolvedTargetCount);
      final terminal = matcher.results.take(2).toList();
      matcher.advance(const Duration(milliseconds: 500));
      counts.add(matcher.resolvedTargetCount);
      matcher.finalize();
      counts.add(matcher.resolvedTargetCount);

      for (var index = 1; index < counts.length; index++) {
        expect(counts[index], greaterThanOrEqualTo(counts[index - 1]));
      }
      expect(matcher.results.take(2), terminal);
      expect(matcher.results.every((result) => result.isResolved), isTrue);
    });

    test(
      'finalize separates required misses from unmatched optional targets',
      () {
        final matcher = _matcher(
          [const Duration(seconds: 1), const Duration(seconds: 2)],
          optionalIndices: {1},
        );

        matcher.finalize();

        expect(matcher.results[0].resolution, PracticeTargetResolution.missed);
        expect(
          matcher.results[1].resolution,
          PracticeTargetResolution.optionalUnmatched,
        );
        expect(matcher.results.every((result) => result.isResolved), isTrue);
        expect(matcher.resolvedTargetCount, 2);
      },
    );

    test('an optional target remains matchable before its window closes', () {
      final matcher = _matcher([_targetTime], optionalIndices: {0});

      final match = matcher.registerStrum(
        _observation(at: _targetTime, sequence: 30),
      );

      expect(match?.targetIndex, 0);
      expect(match?.resolution, PracticeTargetResolution.matched);
      expect(
        matcher.results.single.resolution,
        PracticeTargetResolution.matched,
      );
      expect(matcher.results.single.matchedObservationSequence, 30);
    });

    test('finalize is idempotent', () {
      final matcher = _matcher([_targetTime]);
      matcher.finalize();
      final first = matcher.results.toList();
      final resolved = matcher.resolvedTargetCount;

      matcher.finalize();

      expect(matcher.results, first);
      expect(matcher.resolvedTargetCount, resolved);
    });

    test('signed offsets keep early negative and late positive', () {
      final early = _matcher([
        _targetTime,
      ]).registerStrum(_observation(at: const Duration(microseconds: 1900000)));
      final late = _matcher([
        _targetTime,
      ]).registerStrum(_observation(at: const Duration(microseconds: 2100000)));

      expect(early?.timingOffset, const Duration(milliseconds: -100));
      expect(late?.timingOffset, const Duration(milliseconds: 100));
    });

    test('an empty target is safe to match, advance, and finalize', () {
      final matcher = _matcher(const []);

      expect(matcher.registerStrum(_observation(at: Duration.zero)), isNull);
      matcher.advance(Duration.zero);
      matcher.finalize();

      expect(matcher.results, isEmpty);
      expect(matcher.resolvedTargetCount, 0);
      expect(matcher.extraStrumCount, 1);
    });
  });

  group('PracticeEventMatchResult value semantics', () {
    test('separate matchers produce equal results and hash codes', () {
      final target = _compiledTarget(const [
        Duration(seconds: 1),
        Duration(seconds: 2),
      ]);
      final first = _matcherForTarget(target);
      final second = _matcherForTarget(target);
      const observations = <StrumObservation>[
        StrumObservation(
          at: Duration(seconds: 1),
          sequence: 10,
          direction: StrumDirection.down,
          confidence: 1,
        ),
        StrumObservation(
          at: Duration(seconds: 2),
          sequence: 11,
          direction: StrumDirection.down,
          confidence: 1,
        ),
      ];

      for (final observation in observations) {
        first.registerStrum(observation);
        second.registerStrum(observation);
      }

      for (var index = 0; index < target.events.length; index++) {
        _expectMatchResultDifferences(
          first.results[index],
          second.results[index],
        );
        expect(first.results[index].hashCode, second.results[index].hashCode);
      }
    });

    test('targetIndex alone contributes to equality', () {
      final event = _compiledTarget([_targetTime]).events.single;
      final matcher = _matcherForTarget(
        _compiledTargetFromEvents([event, event]),
      );

      _expectMatchResultDifferences(
        matcher.results[0],
        matcher.results[1],
        targetIndexDiffers: true,
      );
    });

    test('target alone contributes to equality', () {
      final required = _matcher([_targetTime]).results.single;
      final optional = _matcher(
        [_targetTime],
        optionalIndices: {0},
      ).results.single;

      _expectMatchResultDifferences(required, optional, targetDiffers: true);
    });

    test('resolution alone contributes to equality', () {
      final matcher = _matcher([_targetTime]);
      final open = matcher.results.single;

      matcher.finalize();
      final missed = matcher.results.single;

      _expectMatchResultDifferences(open, missed, resolutionDiffers: true);
    });

    test('matched observation sequence alone contributes to equality', () {
      final target = _compiledTarget([_targetTime]);
      final first = _matcherForTarget(
        target,
      ).registerStrum(_observation(at: _targetTime, sequence: 20))!;
      final second = _matcherForTarget(
        target,
      ).registerStrum(_observation(at: _targetTime, sequence: 21))!;

      _expectMatchResultDifferences(
        first,
        second,
        matchedObservationSequenceDiffers: true,
      );
    });

    test('observedAt and timingOffset together contribute to equality', () {
      final target = _compiledTarget([_targetTime]);
      final early = _matcherForTarget(target).registerStrum(
        _observation(
          at: _targetTime - const Duration(microseconds: 1),
          sequence: 30,
        ),
      )!;
      final late = _matcherForTarget(target).registerStrum(
        _observation(
          at: _targetTime + const Duration(microseconds: 1),
          sequence: 30,
        ),
      )!;

      _expectMatchResultDifferences(
        early,
        late,
        observedAtDiffers: true,
        timingOffsetDiffers: true,
      );
    });

    test('results rejects mutation', () {
      final matcher = _matcher([_targetTime]);

      expect(
        () => matcher.results.add(matcher.results.single),
        throwsUnsupportedError,
      );
    });
  });

  group('PracticeEventMatcher measured scaling', () {
    test('20k targets and 1k strums stay below the cursor threshold', () {
      const targetCount = 20000;
      const strumCount = 1000;
      const spacingMicroseconds = 50000;
      const maximumExamined = 64 * (targetCount + strumCount);
      final times = List<Duration>.generate(
        targetCount,
        (index) => Duration(microseconds: index * spacingMicroseconds),
        growable: false,
      );
      final matcher = _matcher(times);

      for (var index = 0; index < strumCount; index++) {
        final match = matcher.registerStrum(
          _observation(at: times[index], sequence: index),
        );
        expect(match?.targetIndex, index);
      }
      matcher.finalize();

      // ignore: avoid_print
      print(
        'A6 cursor examined=${matcher.examinedTargetRecordCount} '
        'threshold=$maximumExamined',
      );
      expect(
        matcher.examinedTargetRecordCount,
        lessThanOrEqualTo(maximumExamined),
      );
      expect(matcher.resolvedTargetCount, targetCount);
      expect(matcher.retainedTargetRecordCount, targetCount);
    });

    test('100k extras do not grow retained records beyond four targets', () {
      final matcher = _matcher(const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 4),
      ]);
      final before = matcher.results.toList();

      for (var index = 0; index < 100000; index++) {
        matcher.registerStrum(
          _observation(
            at: Duration(seconds: 100) + Duration(microseconds: index),
            sequence: index,
          ),
        );
      }

      // ignore: avoid_print
      print(
        'A6 memory retained=${matcher.retainedTargetRecordCount} threshold=4',
      );
      expect(matcher.results, before);
      expect(matcher.resolvedTargetCount, 0);
      expect(matcher.extraStrumCount, 100000);
      expect(matcher.retainedTargetRecordCount, 4);
    });
  });
}

PracticeEventMatcher _matcher(
  List<Duration> times, {
  Duration inputLatency = Duration.zero,
  Set<int> optionalIndices = const {},
}) => _matcherForTarget(
  _compiledTarget(times, optionalIndices: optionalIndices),
  inputLatency: inputLatency,
);

PracticeEventMatcher _matcherForTarget(
  CompiledPracticeTarget target, {
  Duration inputLatency = Duration.zero,
}) => PracticeEventMatcher(
  target: target,
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: inputLatency,
);

CompiledPracticeTarget _compiledTarget(
  List<Duration> times, {
  Set<int> optionalIndices = const {},
}) => _compiledTargetFromEvents([
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
      optional: optionalIndices.contains(index),
    ),
]);

CompiledPracticeTarget _compiledTargetFromEvents(
  List<CompiledTargetEvent> events,
) {
  final totalDuration = events.isEmpty
      ? Duration.zero
      : events.last.time + const Duration(seconds: 1);
  return CompiledPracticeTarget(
    definitionId: 'matcher-test',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: totalDuration,
    ringOutDuration: Duration.zero,
    totalDuration: totalDuration,
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: events.isNotEmpty,
  );
}

void _expectMatchResultDifferences(
  PracticeEventMatchResult first,
  PracticeEventMatchResult second, {
  bool targetIndexDiffers = false,
  bool targetDiffers = false,
  bool resolutionDiffers = false,
  bool matchedObservationSequenceDiffers = false,
  bool observedAtDiffers = false,
  bool timingOffsetDiffers = false,
}) {
  expect(
    first.targetIndex == second.targetIndex,
    !targetIndexDiffers,
    reason: 'targetIndex isolation',
  );
  expect(
    first.target == second.target,
    !targetDiffers,
    reason: 'target isolation',
  );
  expect(
    first.resolution == second.resolution,
    !resolutionDiffers,
    reason: 'resolution isolation',
  );
  expect(
    first.matchedObservationSequence == second.matchedObservationSequence,
    !matchedObservationSequenceDiffers,
    reason: 'matchedObservationSequence isolation',
  );
  expect(
    first.observedAt == second.observedAt,
    !observedAtDiffers,
    reason: 'observedAt isolation',
  );
  expect(
    first.timingOffset == second.timingOffset,
    !timingOffsetDiffers,
    reason: 'timingOffset isolation',
  );

  final shouldDiffer =
      targetIndexDiffers ||
      targetDiffers ||
      resolutionDiffers ||
      matchedObservationSequenceDiffers ||
      observedAtDiffers ||
      timingOffsetDiffers;
  expect(first == second, !shouldDiffer, reason: 'overall equality');
}

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
