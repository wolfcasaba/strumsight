// Javító sáv 2026-09-06 (R6) — the session → result-route hand-off that the
// shipped app never had (`docs/ui/apk-functionality-audit-2026-09-06.md`
// §1.3: the `practiceResult` route always rendered "result unavailable").
//
// T1 — navigate-then-record: `expect(id)` then `recorded(id)` ends on the
//      recorded session.
// T2 — record-then-navigate: `recorded(id)` then `expect(id)` keeps the
//      recorded state (never regresses).
// T3 — `expect(null)` (no result id yet) is pending; `recorded` resolves it.
// T4 — `recordFailed` is terminal for the route.
// V1 — resolver: a named session whose entry is present renders it.
// V2 — resolver: a named session not yet in the list is LOADING while the
//      record is in flight or the list is (re)loading, FALLBACK once settled.
// V3 — resolver: no hand-off shows the NEWEST entry; an empty list is the
//      fallback; a first load is loading.
// V4 — resolver: pending is loading, failed is fallback.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_result_target.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/presentation/practice_result_route.dart';

PracticeHistoryEntry _entry(String id, {required DateTime createdAt}) {
  return PracticeHistoryEntry(
    id: id,
    modeCode: 'chord.sequence',
    sourceCode: 'builtin',
    createdAt: createdAt,
    definitionId: 'd-$id',
    displayTitle: 'fixture-$id',
    finishReasonCode: 'userFinished',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionAvailable(0.92),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 16,
    resolvedTargets: 14,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const <String>[],
    skillTags: const <String>['smoke'],
    highestStableTempoBpm: 100.0,
  );
}

void main() {
  group('PracticeResultTargetController', () {
    late ProviderContainer container;
    late PracticeResultTargetController controller;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      controller = container.read(practiceResultTargetProvider.notifier);
    });

    PracticeResultTarget state() =>
        container.read(practiceResultTargetProvider);

    test('T1 — navigate then record ends on the recorded session', () {
      controller.expect('s1');
      expect(state(), const PracticeResultTargetSession('s1', recorded: false));

      controller.recorded('s1');

      expect(state(), const PracticeResultTargetSession('s1', recorded: true));
    });

    test('T2 — record then navigate keeps the recorded state', () {
      controller.recorded('s1');

      controller.expect('s1');

      expect(state(), const PracticeResultTargetSession('s1', recorded: true));
    });

    test('T3 — no result id yet is pending until the record lands', () {
      controller.expect(null);
      expect(state(), isA<PracticeResultTargetPending>());

      controller.recorded('s2');

      expect(state(), const PracticeResultTargetSession('s2', recorded: true));
    });

    test('T4 — a failed record is terminal', () {
      controller.expect('s3');

      controller.recordFailed();

      expect(state(), isA<PracticeResultTargetFailed>());
    });
  });

  group('resolvePracticeResultView', () {
    final older = _entry('old', createdAt: DateTime.utc(2026, 9, 1));
    final newer = _entry('new', createdAt: DateTime.utc(2026, 9, 6));
    final loaded = AsyncValue<List<PracticeHistoryEntry>>.data([older, newer]);
    const loading = AsyncValue<List<PracticeHistoryEntry>>.loading();

    test('V1 — a named, present session renders its entry', () {
      final view = resolvePracticeResultView(
        target: const PracticeResultTargetSession('old', recorded: true),
        history: loaded,
      );
      expect(view, isA<PracticeResultViewEntry>());
      expect((view as PracticeResultViewEntry).entry.id, 'old');
    });

    test('V2 — a named session not in the list: loading while in flight or '
        'refreshing, fallback once settled', () {
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetSession('s9', recorded: false),
          history: loaded,
        ),
        isA<PracticeResultViewLoading>(),
      );
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetSession('s9', recorded: true),
          history: loading,
        ),
        isA<PracticeResultViewLoading>(),
      );
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetSession('s9', recorded: true),
          history: loaded,
        ),
        isA<PracticeResultViewFallback>(),
      );
    });

    test('V3 — no hand-off shows the newest entry; empty is the fallback; '
        'a first load is loading', () {
      final newest = resolvePracticeResultView(
        target: const PracticeResultTargetNone(),
        history: loaded,
      );
      expect((newest as PracticeResultViewEntry).entry.id, 'new');
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetNone(),
          history: const AsyncValue<List<PracticeHistoryEntry>>.data([]),
        ),
        isA<PracticeResultViewFallback>(),
      );
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetNone(),
          history: loading,
        ),
        isA<PracticeResultViewLoading>(),
      );
    });

    test('V4 — pending is loading, failed is fallback', () {
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetPending(),
          history: loaded,
        ),
        isA<PracticeResultViewLoading>(),
      );
      expect(
        resolvePracticeResultView(
          target: const PracticeResultTargetFailed(),
          history: loaded,
        ),
        isA<PracticeResultViewFallback>(),
      );
    });
  });
}
