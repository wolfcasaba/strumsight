import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/service/practice_progress_aggregator.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';

/// Builds a MetricSnapshot where every dimension is `NotApplicable` (the V2
/// "no metric" shape).
PracticeMetricSnapshot _naSnapshot() => PracticeMetricSnapshot(
  completion: PracticeMetricDimension.notApplicable(),
  rhythm: PracticeMetricDimension.notApplicable(),
  direction: PracticeMetricDimension.notApplicable(),
  chord: PracticeMetricDimension.notApplicable(),
  overall: PracticeMetricDimension.notApplicable(),
);

/// A V2 history entry whose every metric dimension carries [directionValue]
/// only; the rest stay [NotApplicable].
PracticeHistoryEntry _v2WithDirection({
  required String id,
  required int dayOffset,
  required double directionValue,
  int seconds = 90,
  int attempts = 16,
}) {
  final created = DateTime.utc(2026, 1, 1).add(Duration(days: dayOffset));
  return PracticeHistoryEntry(
    id: id,
    modeCode: 'practice.mode.unknown',
    sourceCode: 'live',
    createdAt: created,
    definitionId: 'practice.definition.unknown',
    displayTitle: '',
    finishReasonCode: PracticeFinishReason.completedAllTargets.code,
    activeDuration: Duration(seconds: seconds),
    pausedDuration: Duration.zero,
    attemptsCount: attempts,
    finalMetricSnapshot: PracticeMetricSnapshot(
      completion: const PracticeMetricDimensionNotApplicable(),
      rhythm: const PracticeMetricDimensionNotApplicable(),
      direction: PracticeMetricDimension.available(directionValue),
      chord: const PracticeMetricDimensionNotApplicable(),
      overall: const PracticeMetricDimensionNotApplicable(),
    ),
    totalTargets: 0,
    resolvedTargets: 0,
    scorePoints: 0,
    maxCombo: 0,
    meanAbsoluteOffset: Duration.zero,
    timingBias: Duration.zero,
    coachingSummary: const <String>[],
    skillTags: const <String>[],
  );
}

void main() {
  const aggregator = PracticeProgressAggregator();

  group('A1 — V1+V2 aggregation: no fabricated data', () {
    test('V1 record with non-null directionAccuracy exposes that value', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 10,
          source: PracticeSource.learn,
          seconds: 60,
          strokes: 12,
          chords: 2,
          directionAccuracy: 0.82,
        ),
      ];
      final result = aggregator.aggregate(v1: v1, v2: const []);
      expect(result.single.id, 'v1-1');
      expect(
        result.single.direction,
        isA<MetricAvailable>().having((m) => m.value, 'value', 0.82),
      );
      // No dimension other than direction carries a value for V1.
      expect(result.single.completion, isA<MetricNotApplicable>());
      expect(result.single.rhythm, isA<MetricNotApplicable>());
      expect(result.single.chord, isA<MetricNotApplicable>());
      expect(result.single.overall, isA<MetricNotApplicable>());
    });

    test('V1 record with null directionAccuracy → MetricNotApplicable', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 11,
          source: PracticeSource.live,
          seconds: 30,
          strokes: 4,
          chords: 1,
        ),
      ];
      final result = aggregator.aggregate(v1: v1, v2: const []);
      expect(result.single.direction, isA<MetricNotApplicable>());
    });

    test('V2 record carries its full V2 metrics through', () {
      final v2 = <PracticeHistoryEntry>[
        _v2WithDirection(
          id: 'v2-1',
          dayOffset: 0,
          directionValue: 0.95,
          seconds: 100,
          attempts: 20,
        ),
      ];
      final result = aggregator.aggregate(v1: const [], v2: v2);
      expect(result.single.id, 'v2-1');
      expect(
        result.single.direction,
        isA<MetricAvailable>().having((m) => m.value, 'value', 0.95),
      );
      expect(result.single.strokes, 20);
      expect(result.single.seconds, 100);
    });

    test(
      'a V2 free-practice record with NotApplicable direction stays that way',
      () {
        final created = DateTime.utc(2026, 1, 1);
        final v2 = <PracticeHistoryEntry>[
          PracticeHistoryEntry(
            id: 'v2-fp',
            modeCode: 'practice.mode.unknown',
            sourceCode: 'live',
            createdAt: created,
            definitionId: 'practice.definition.unknown',
            displayTitle: '',
            finishReasonCode: PracticeFinishReason.completedAllTargets.code,
            activeDuration: const Duration(seconds: 25),
            pausedDuration: Duration.zero,
            attemptsCount: 12,
            finalMetricSnapshot: _naSnapshot(),
            totalTargets: 0,
            resolvedTargets: 0,
            scorePoints: 0,
            maxCombo: 0,
            meanAbsoluteOffset: Duration.zero,
            timingBias: Duration.zero,
            coachingSummary: const <String>[],
            skillTags: const <String>[],
          ),
        ];
        final result = aggregator.aggregate(v1: const [], v2: v2);
        expect(result.single.direction, isA<MetricNotApplicable>());
        expect(result.single.completion, isA<MetricNotApplicable>());
      },
    );
  });

  group('A2 — totals matrix', () {
    test('3 V1 + 3 V2 → totalSessions == 6, correct seconds sum', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 1,
          source: PracticeSource.learn,
          seconds: 60,
          strokes: 8,
        ),
        PracticeEntry(
          day: 2,
          source: PracticeSource.live,
          seconds: 45,
          strokes: 5,
        ),
        PracticeEntry(
          day: 3,
          source: PracticeSource.analyze,
          seconds: 30,
          strokes: 4,
        ),
      ];
      final v2 = <PracticeHistoryEntry>[
        _v2WithDirection(
          id: 'a',
          dayOffset: 4,
          directionValue: 0.7,
          seconds: 90,
          attempts: 16,
        ),
        _v2WithDirection(
          id: 'b',
          dayOffset: 5,
          directionValue: 0.8,
          seconds: 120,
          attempts: 22,
        ),
        _v2WithDirection(
          id: 'c',
          dayOffset: 6,
          directionValue: 0.9,
          seconds: 150,
          attempts: 28,
        ),
      ];
      final entries = aggregator.aggregate(v1: v1, v2: v2);
      expect(entries.length, 6);
      expect(entries.length, 6); // totalSessions via .length
      // totalSeconds = (60+45+30) + (90+120+150) = 495
      expect(entries.fold<int>(0, (s, e) => s + e.seconds), 495);
      expect(aggregator.daysPracticed(entries), 6);
    });

    test('per-day rollup sums V1 and V2 entries on the same epoch day', () {
      // A V1 entry for "day X" and a V2 entry whose createdAt lands on the
      // same local epoch day as day X — both must fold into the rollup sum.
      final day = DateTime.utc(2026, 4, 10); // arbitrary fixed local date
      final epochDay =
          DateTime(day.year, day.month, day.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: epochDay,
          source: PracticeSource.learn,
          seconds: 60,
          strokes: 4,
        ),
      ];
      final created = DateTime(2026, 4, 10, 12, 30); // same local date, noon
      final v2 = <PracticeHistoryEntry>[
        PracticeHistoryEntry(
          id: 'd-1',
          modeCode: 'practice.mode.unknown',
          sourceCode: 'live',
          createdAt: created,
          definitionId: 'practice.definition.unknown',
          displayTitle: '',
          finishReasonCode: PracticeFinishReason.completedAllTargets.code,
          activeDuration: const Duration(seconds: 90),
          pausedDuration: Duration.zero,
          attemptsCount: 10,
          finalMetricSnapshot: _naSnapshot(),
          totalTargets: 0,
          resolvedTargets: 0,
          scorePoints: 0,
          maxCombo: 0,
          meanAbsoluteOffset: Duration.zero,
          timingBias: Duration.zero,
          coachingSummary: const <String>[],
          skillTags: const <String>[],
        ),
      ];
      final entries = aggregator.aggregate(v1: v1, v2: v2);
      expect(aggregator.secondsForDay(entries, epochDay), 150);
    });

    test('source breakdown keeps V1 PracticeSource names', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 1,
          source: PracticeSource.live,
          seconds: 10,
          strokes: 1,
        ),
        PracticeEntry(
          day: 1,
          source: PracticeSource.analyze,
          seconds: 10,
          strokes: 1,
        ),
        PracticeEntry(
          day: 1,
          source: PracticeSource.learn,
          seconds: 10,
          strokes: 1,
        ),
      ];
      final entries = aggregator.aggregate(v1: v1, v2: const []);
      expect(aggregator.sessionsFrom(entries, PracticeSource.live), 1);
      expect(aggregator.sessionsFrom(entries, PracticeSource.analyze), 1);
      expect(aggregator.sessionsFrom(entries, PracticeSource.learn), 1);
    });
  });

  group('A3 — same V2 session id is never counted twice', () {
    test('two V2 entries sharing an id collapse to one aggregated record', () {
      // Simulate a race where the V2 store somehow hands back two entries with
      // the same id (e.g. a slow reader after a fast writer). The aggregator
      // must NEVER let that double the totals.
      final v2 = <PracticeHistoryEntry>[
        _v2WithDirection(
          id: 'dupe',
          dayOffset: 0,
          directionValue: 0.7,
          seconds: 60,
          attempts: 10,
        ),
        _v2WithDirection(
          id: 'dupe',
          dayOffset: 0,
          directionValue: 0.7,
          seconds: 60,
          attempts: 10,
        ),
      ];
      final entries = aggregator.aggregate(v1: const [], v2: v2);
      expect(entries.length, 1, reason: 'V2 id dedup (A3)');
      expect(entries.single.seconds, 60);
      expect(entries.single.strokes, 10);
    });

    test(
      'V1+V2 mix never doubles a V2 entry even when V1 also logs the same session',
      () {
        // The V1 model has no session-id field today, so duplication requires V2
        // entries to share an id (the case already covered). Confirm the mix is
        // stable regardless of V1 size.
        final v1 = <PracticeEntry>[
          for (var i = 0; i < 5; i++)
            PracticeEntry(
              day: i,
              source: PracticeSource.learn,
              seconds: 30,
              strokes: 4,
            ),
        ];
        final v2 = <PracticeHistoryEntry>[
          _v2WithDirection(
            id: 's',
            dayOffset: 0,
            directionValue: 0.8,
            seconds: 120,
            attempts: 25,
          ),
          _v2WithDirection(
            id: 's',
            dayOffset: 0,
            directionValue: 0.8,
            seconds: 120,
            attempts: 25,
          ),
        ];
        final entries = aggregator.aggregate(v1: v1, v2: v2);
        // 5 V1 + 1 deduped V2 = 6
        expect(entries.length, 6);
        expect(entries.where((e) => e.id == 's').length, 1);
      },
    );
  });

  group(
    'source code mapping (Döntés 3 — V2 PracticeSource → V1 dashboard enum)',
    () {
      test('live → live', () {
        final v2 = <PracticeHistoryEntry>[
          _v2WithDirection(id: 'x', dayOffset: 0, directionValue: 0.5),
        ];
        final entries = aggregator.aggregate(v1: const [], v2: v2);
        expect(entries.single.source, PracticeSource.live);
      });

      test('learn → learn', () {
        final v2 = <PracticeHistoryEntry>[
          PracticeHistoryEntry(
            id: 'l',
            modeCode: 'practice.mode.unknown',
            sourceCode: 'learn',
            createdAt: DateTime.utc(2026, 1, 1),
            definitionId: 'practice.definition.unknown',
            displayTitle: '',
            finishReasonCode: PracticeFinishReason.completedAllTargets.code,
            activeDuration: const Duration(seconds: 30),
            pausedDuration: Duration.zero,
            attemptsCount: 5,
            finalMetricSnapshot: _naSnapshot(),
            totalTargets: 0,
            resolvedTargets: 0,
            scorePoints: 0,
            maxCombo: 0,
            meanAbsoluteOffset: Duration.zero,
            timingBias: Duration.zero,
            coachingSummary: const <String>[],
            skillTags: const <String>[],
          ),
        ];
        final entries = aggregator.aggregate(v1: const [], v2: v2);
        expect(entries.single.source, PracticeSource.learn);
      });

      test('analyze → analyze', () {
        final v2 = <PracticeHistoryEntry>[
          PracticeHistoryEntry(
            id: 'a',
            modeCode: 'practice.mode.unknown',
            sourceCode: 'analyze',
            createdAt: DateTime.utc(2026, 1, 1),
            definitionId: 'practice.definition.unknown',
            displayTitle: '',
            finishReasonCode: PracticeFinishReason.completedAllTargets.code,
            activeDuration: const Duration(seconds: 30),
            pausedDuration: Duration.zero,
            attemptsCount: 5,
            finalMetricSnapshot: _naSnapshot(),
            totalTargets: 0,
            resolvedTargets: 0,
            scorePoints: 0,
            maxCombo: 0,
            meanAbsoluteOffset: Duration.zero,
            timingBias: Duration.zero,
            coachingSummary: const <String>[],
            skillTags: const <String>[],
          ),
        ];
        final entries = aggregator.aggregate(v1: const [], v2: v2);
        expect(entries.single.source, PracticeSource.analyze);
      });
    },
  );

  group('direction aggregate rollups', () {
    test('averageDirectionAccuracy ignores NotApplicable entries', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 1,
          source: PracticeSource.live,
          seconds: 10,
          strokes: 1,
        ),
        PracticeEntry(
          day: 2,
          source: PracticeSource.learn,
          seconds: 10,
          strokes: 1,
          directionAccuracy: 1.0,
        ),
        PracticeEntry(
          day: 3,
          source: PracticeSource.learn,
          seconds: 10,
          strokes: 1,
          directionAccuracy: 0.5,
        ),
      ];
      final entries = aggregator.aggregate(v1: v1, v2: const []);
      expect(aggregator.averageDirectionAccuracy(entries), closeTo(0.75, 1e-9));
      expect(aggregator.bestDirectionAccuracy(entries), 1.0);
    });

    test('averageDirectionAccuracy returns null when none scored', () {
      final v1 = <PracticeEntry>[
        PracticeEntry(
          day: 1,
          source: PracticeSource.live,
          seconds: 10,
          strokes: 1,
        ),
      ];
      final entries = aggregator.aggregate(v1: v1, v2: const []);
      expect(aggregator.averageDirectionAccuracy(entries), isNull);
      expect(aggregator.bestDirectionAccuracy(entries), isNull);
    });
  });
}
