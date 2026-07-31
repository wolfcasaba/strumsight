import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';
import 'package:strumsight/features/practice/domain/service/practice_timing_scorer.dart';

const _targetAt = Duration(seconds: 1);

void main() {
  group('PracticeTimingScorer A1 boundary matrix', () {
    const cells = <({int offsetMicroseconds, int perMille, TimingGrade grade})>[
      (offsetMicroseconds: 0, perMille: 1000, grade: TimingGrade.perfect),
      (offsetMicroseconds: 49999, perMille: 1000, grade: TimingGrade.perfect),
      (offsetMicroseconds: 50000, perMille: 1000, grade: TimingGrade.perfect),
      (offsetMicroseconds: 50001, perMille: 800, grade: TimingGrade.good),
      (offsetMicroseconds: 119999, perMille: 800, grade: TimingGrade.good),
      (offsetMicroseconds: 120000, perMille: 800, grade: TimingGrade.good),
      (offsetMicroseconds: 120001, perMille: 800, grade: TimingGrade.early),
      (offsetMicroseconds: 200000, perMille: 575, grade: TimingGrade.early),
      (offsetMicroseconds: 279999, perMille: 351, grade: TimingGrade.early),
      (offsetMicroseconds: 280000, perMille: 350, grade: TimingGrade.early),
    ];

    for (final cell in cells) {
      for (final sign in const [-1, 1]) {
        test('${sign < 0 ? 'early' : 'late'} ${cell.offsetMicroseconds} us '
            'is exactly ${cell.perMille} per mille', () {
          final matcher = _matcher();
          matcher.registerStrum(
            _observation(
              _targetAt +
                  Duration(microseconds: sign * cell.offsetMicroseconds),
            ),
          );
          final score = const PracticeTimingScorer().score(
            matches: matcher.results,
            scoringProfile: ScoringProfile.legacyLearnParity,
          );
          final event = score.events.single;
          final expectedGrade = switch (cell.grade) {
            TimingGrade.early when sign > 0 => TimingGrade.late,
            _ => cell.grade,
          };

          expect(event.grade, expectedGrade);
          expect(event.scorePerMille, cell.perMille);
          expect(event.score, cell.perMille / 1000);
          expect(score.rhythmPerMille, cell.perMille);
          expect(score.rhythm, MetricAvailable(cell.perMille / 1000));
        });
      }
    }

    test('an unmatched required target is a zero-score miss', () {
      final matcher = _matcher()..finalize();

      final score = const PracticeTimingScorer().score(
        matches: matcher.results,
        scoringProfile: ScoringProfile.legacyLearnParity,
      );

      expect(score.events.single.grade, TimingGrade.missed);
      expect(score.events.single.scorePerMille, 0);
      expect(score.rhythmPerMille, isNull);
      expect(
        score.rhythm,
        const MetricInsufficientData(PracticeMetricReasonCode.noSignal),
      );
    });
  });

  group('PracticeTimingScorer aggregation', () {
    test('uses integer accumulation and one truncating mean division', () {
      final matcher = _matcher(
        times: const [Duration(seconds: 1), Duration(seconds: 2)],
      );
      matcher.registerStrum(
        _observation(const Duration(seconds: 1), sequence: 0),
      );
      matcher.registerStrum(
        _observation(const Duration(milliseconds: 2200), sequence: 1),
      );

      final score = const PracticeTimingScorer().score(
        matches: matcher.results,
        scoringProfile: ScoringProfile.legacyLearnParity,
      );

      expect(score.events.map((event) => event.scorePerMille), [1000, 575]);
      expect(score.rhythmPerMille, 787);
      expect(score.rhythm, const MetricAvailable(0.787));
      expect(score.meanAbsoluteOffset, const Duration(milliseconds: 100));
      expect(score.timingBias, const Duration(milliseconds: 100));
    });

    test(
      'signed timing bias truncates toward zero in integer microseconds',
      () {
        final matcher = _matcher(
          times: const [Duration(seconds: 1), Duration(seconds: 2)],
        );
        matcher.registerStrum(
          _observation(const Duration(microseconds: 999998), sequence: 0),
        );
        matcher.registerStrum(
          _observation(const Duration(microseconds: 2000001), sequence: 1),
        );

        final score = const PracticeTimingScorer().score(
          matches: matcher.results,
          scoringProfile: ScoringProfile.legacyLearnParity,
        );

        expect(score.meanAbsoluteOffset, const Duration(microseconds: 1));
        expect(score.timingBias, Duration.zero);
      },
    );

    for (final finalized in [false, true]) {
      test('${finalized ? 'finalized' : 'open'} unmatched optional target does '
          'not dilute the rhythm dimension', () {
        final matcher = _matcher(
          times: const [Duration(seconds: 1), Duration(seconds: 2)],
          optionalIndices: const {1},
        );
        matcher.registerStrum(_observation(const Duration(seconds: 1)));
        if (finalized) matcher.finalize();

        final score = const PracticeTimingScorer().score(
          matches: matcher.results,
          scoringProfile: ScoringProfile.legacyLearnParity,
        );

        expect(score.events[1].grade, TimingGrade.notApplicable);
        expect(score.rhythmPerMille, 1000);
        expect(score.rhythm, const MetricAvailable(1));
      });
    }

    test('an empty target has no applicable rhythm metric', () {
      final score = const PracticeTimingScorer().score(
        matches: const [],
        scoringProfile: ScoringProfile.legacyLearnParity,
      );

      expect(score.events, isEmpty);
      expect(score.rhythmPerMille, isNull);
      expect(score.rhythm, const MetricNotApplicable());
      expect(score.meanAbsoluteOffset, Duration.zero);
      expect(score.timingBias, Duration.zero);
    });

    test('the event-score view rejects mutation', () {
      final score = const PracticeTimingScorer().score(
        matches: (_matcher()..finalize()).results,
        scoringProfile: ScoringProfile.legacyLearnParity,
      );

      expect(
        () => score.events.add(score.events.single),
        throwsUnsupportedError,
      );
    });
  });
}

PracticeEventMatcher _matcher({
  List<Duration> times = const [_targetAt],
  Set<int> optionalIndices = const {},
}) => PracticeEventMatcher(
  target: _target(times, optionalIndices),
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: Duration.zero,
);

StrumObservation _observation(Duration at, {int sequence = 0}) =>
    StrumObservation(
      at: at,
      sequence: sequence,
      direction: StrumDirection.down,
      confidence: 1,
    );

CompiledPracticeTarget _target(
  List<Duration> times,
  Set<int> optionalIndices,
) => CompiledPracticeTarget(
  definitionId: 'timing-test',
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
        optional: optionalIndices.contains(index),
      ),
  ],
  musicalDuration: times.isEmpty
      ? Duration.zero
      : times.last + const Duration(seconds: 1),
  ringOutDuration: Duration.zero,
  totalDuration: times.isEmpty
      ? Duration.zero
      : times.last + const Duration(seconds: 1),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: times.isNotEmpty,
);
