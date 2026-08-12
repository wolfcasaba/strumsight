import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/target/alignment_result.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';
import 'package:strumsight/features/audio_analysis/domain/target/expected_event.dart';
import 'package:strumsight/features/audio_analysis/engine/alignment/event_aligner.dart';

void main() {
  const aligner = EventAligner();
  const beat = Duration(milliseconds: 500);

  AlignmentResult align({
    required List<AnalysisEvent> observed,
    required List<ExpectedEvent> expected,
  }) =>
      aligner.align(observed: observed, expected: expected, beatDuration: beat);

  group('EventAligner matrix', () {
    test('perfect observations match with zero total cost', () {
      final result = align(
        observed: <AnalysisEvent>[_onset('o0', 0), _onset('o1', 500)],
        expected: <ExpectedEvent>[_expected('e0', 0), _expected('e1', 500)],
      );

      expect(result.matches, hasLength(2));
      expect(result.missedExpected, isEmpty);
      expect(result.extraObserved, isEmpty);
      expect(result.totalCost, 0);
      expect(result.confidence, 1);
    });

    test('one missing expected event has one missed penalty', () {
      final result = align(
        observed: <AnalysisEvent>[_onset('o0', 0)],
        expected: <ExpectedEvent>[_expected('e0', 0), _expected('e1', 500)],
      );

      expect(result.matches, hasLength(1));
      expect(result.missedExpected.map((event) => event.id), <String>['e1']);
      expect(result.extraObserved, isEmpty);
      expect(result.totalCost, 1);
    });

    test('one extra observed event has one extra penalty', () {
      final result = align(
        observed: <AnalysisEvent>[_onset('o0', 0), _onset('o1', 500)],
        expected: <ExpectedEvent>[_expected('e0', 0)],
      );

      expect(result.matches, hasLength(1));
      expect(result.missedExpected, isEmpty);
      expect(result.extraObserved.map((event) => event.id), <String>['o1']);
      expect(result.totalCost, 1);
    });

    test(
      'early cluster remains monotonic and records negative timing errors',
      () {
        final result = align(
          observed: <AnalysisEvent>[
            for (var index = 0; index < 5; index++)
              _onset('o$index', 900 + index * 500),
          ],
          expected: <ExpectedEvent>[
            for (var index = 0; index < 5; index++)
              _expected('e$index', 1000 + index * 500),
          ],
        );

        expect(result.matches, hasLength(5));
        expect(
          result.matches.every((match) => match.timingError.isNegative),
          isTrue,
        );
        _expectStrictlyMonotonic(result);
      },
    );

    test(
      'late cluster remains monotonic and records positive timing errors',
      () {
        final result = align(
          observed: <AnalysisEvent>[
            for (var index = 0; index < 5; index++)
              _onset('o$index', 1100 + index * 500),
          ],
          expected: <ExpectedEvent>[
            for (var index = 0; index < 5; index++)
              _expected('e$index', 1000 + index * 500),
          ],
        );

        expect(result.matches, hasLength(5));
        expect(
          result.matches.every((match) => !match.timingError.isNegative),
          isTrue,
        );
        _expectStrictlyMonotonic(result);
      },
    );

    test(
      'equal-distance candidates always choose the earlier expected index',
      () {
        final observed = <AnalysisEvent>[_onset('o', 500)];
        final expected = <ExpectedEvent>[
          _expected('early', 400),
          _expected('late', 600),
        ];

        for (var run = 0; run < 100; run++) {
          final result = align(observed: observed, expected: expected);
          expect(result.matches.single.expectedIndex, 0, reason: 'run=$run');
          expect(
            result.matches.single.expected.id,
            'early',
            reason: 'run=$run',
          );
        }
      },
    );

    test('direction mismatch adds the named direction penalty', () {
      final result = align(
        observed: <AnalysisEvent>[
          StrumEvent(
            id: 'o',
            time: Duration.zero,
            confidence: 1,
            direction: StrumDirection.down,
          ),
        ],
        expected: <ExpectedEvent>[
          _expected(
            'e',
            0,
            type: ExpectedEventType.strum,
            direction: StrumDirection.up,
          ),
        ],
      );

      expect(result.matches, hasLength(1));
      expect(result.totalCost, EventAligner.directionMismatchPenalty);
    });

    test('event type mismatch adds the named type penalty', () {
      final result = align(
        observed: <AnalysisEvent>[_onset('o', 0)],
        expected: <ExpectedEvent>[
          _expected('e', 0, type: ExpectedEventType.strum),
        ],
      );

      expect(result.matches, hasLength(1));
      expect(result.totalCost, EventAligner.typeMismatchPenalty);
    });

    test('empty inputs return an empty zero-cost result', () {
      final result = align(
        observed: const <AnalysisEvent>[],
        expected: const <ExpectedEvent>[],
      );

      expect(result.matches, isEmpty);
      expect(result.missedExpected, isEmpty);
      expect(result.extraObserved, isEmpty);
      expect(result.totalCost, 0);
      expect(result.confidence, 0);
    });

    test(
      'higher observed confidence wins when it competes for one expected event',
      () {
        final result = align(
          observed: <AnalysisEvent>[
            _onset('low', 100, confidence: .1),
            _onset('high', 100, confidence: .9),
          ],
          expected: <ExpectedEvent>[_expected('e', 0)],
        );

        expect(result.matches.single.observed.id, 'high');
        expect(result.extraObserved.single.id, 'low');
      },
    );
  });

  group('EventAligner contracts', () {
    test('does not mutate observed or expected input snapshots', () {
      final observed = <AnalysisEvent>[_onset('o1', 500), _onset('o0', 0)];
      final expected = <ExpectedEvent>[
        _expected('e1', 500),
        _expected('e0', 0),
      ];
      final observedBefore = List<AnalysisEvent>.of(observed);
      final expectedBefore = List<ExpectedEvent>.of(expected);

      expect(
        () => align(observed: observed, expected: expected),
        throwsArgumentError,
      );
      expect(observed, observedBefore);
      expect(expected, expectedBefore);
    });

    test('target is a versioned immutable snapshot', () {
      final events = <ExpectedEvent>[_expected('e', 0)];
      final target = AnalysisTarget(
        id: 'target',
        targetVersion: 1,
        kind: AnalysisTargetKind.practice,
        timebase: AnalysisTargetTimebase.session,
        expectedEvents: events,
      );
      events.add(_expected('later', 500));

      expect(target.expectedEvents, hasLength(1));
      expect(
        () => target.expectedEvents.add(_expected('nope', 1000)),
        throwsUnsupportedError,
      );
    });

    test('large sparse alignment stays within the time-derived band', () {
      final observed = <AnalysisEvent>[
        for (var index = 0; index < 2000; index++)
          _onset('o$index', index * 100),
      ];
      final expected = <ExpectedEvent>[
        for (var index = 0; index < 2000; index++)
          _expected('e$index', index * 100),
      ];
      final stopwatch = Stopwatch()..start();
      final result = align(observed: observed, expected: expected);
      stopwatch.stop();
      // ignore: avoid_print
      print('alignment_2000x2000_elapsed_ms=${stopwatch.elapsedMilliseconds}');

      expect(result.matches, hasLength(2000));
      expect(
        result.diagnostics.maximumCandidateBandWidth,
        lessThanOrEqualTo(3),
      );
      expect(result.diagnostics.scoreStateCount, 2000);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('score state uses the shorter input axis', () {
      final result = align(
        observed: <AnalysisEvent>[_onset('o', 0)],
        expected: <ExpectedEvent>[
          for (var index = 0; index < 2000; index++)
            _expected('e$index', index * 500),
        ],
      );

      expect(result.diagnostics.scoreStateCount, 1);
      expect(result.matches.single.expectedIndex, 0);
    });
  });
}

OnsetEvent _onset(String id, int milliseconds, {double confidence = 1}) =>
    OnsetEvent(
      id: id,
      time: Duration(milliseconds: milliseconds),
      confidence: confidence,
    );

ExpectedEvent _expected(
  String id,
  int milliseconds, {
  ExpectedEventType type = ExpectedEventType.onset,
  StrumDirection? direction,
}) => ExpectedEvent(
  id: id,
  time: Duration(milliseconds: milliseconds),
  type: type,
  direction: direction,
);

void _expectStrictlyMonotonic(AlignmentResult result) {
  var previousObserved = -1;
  var previousExpected = -1;
  for (final match in result.matches) {
    expect(match.observedIndex, greaterThan(previousObserved));
    expect(match.expectedIndex, greaterThan(previousExpected));
    previousObserved = match.observedIndex;
    previousExpected = match.expectedIndex;
  }
}
