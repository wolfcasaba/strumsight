// Javító sáv 2026-09-06 — after-record hooks of the V2 practice session
// (`docs/ui/apk-functionality-audit-2026-09-06.md` §1.3, E16-R05 L4/L5,
// E16-R01 backlog §6.6).
//
// A1 — the decorator runs the hooks ONLY after a successful durable write,
//      in order, and a throwing hook is logged without failing the session.
// A2 — the ledger-derived policy snapshot counts today's entries only.
// A3 — the terminal-reason mapping: abandoned / failed sessions are not
//      practice.
// A4 — the result screen reads the SAME ledger instance the gamification
//      composition owns (no more always-empty default).
// A5 — end to end in a real container: a 90 s completed session advances
//      the streak, lands a ledger entry under the adapter's stable event id,
//      and moves the profile's total XP off zero.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/application/gamification_practice_adapter.dart';
import 'package:strumsight/features/practice/application/practice_session_after_record.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_session_recorder.dart';
import 'package:strumsight/features/practice/presentation/providers/practice_result_providers.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../../support/preference_store.dart';

void main() {
  group('A1 — PracticeSessionRecorderWithHooks', () {
    test('runs every hook in order after a successful write', () async {
      final calls = <String>[];
      final recorder = PracticeSessionRecorderWithHooks(
        inner: const _SucceedingRecorder(),
        definition: _definition(),
        hooks: <PracticeSessionRecordedHook>[
          (result, definition) async => calls.add('first:${result.id}'),
          (result, definition) async => calls.add('second:${definition.id}'),
        ],
        logger: const NoopAppLogger(),
      );

      final outcome = await recorder.record(_result('s-1'));

      expect(outcome, isA<Success<void>>());
      expect(calls, <String>['first:s-1', 'second:fixture.session']);
    });

    test('runs NO hook when the durable write failed', () async {
      var hookRuns = 0;
      final recorder = PracticeSessionRecorderWithHooks(
        inner: const _FailingRecorder(),
        definition: _definition(),
        hooks: <PracticeSessionRecordedHook>[
          (result, definition) async => hookRuns += 1,
        ],
        logger: const NoopAppLogger(),
      );

      final outcome = await recorder.record(_result('s-2'));

      expect(outcome, isA<Failure<void>>());
      expect(hookRuns, 0);
    });

    test('a throwing hook is logged, the next hook still runs, and the '
        'saved session stays a Success', () async {
      final logger = _RecordingLogger();
      var secondRan = false;
      final recorder = PracticeSessionRecorderWithHooks(
        inner: const _SucceedingRecorder(),
        definition: _definition(),
        hooks: <PracticeSessionRecordedHook>[
          (result, definition) async => throw StateError('boom'),
          (result, definition) async => secondRan = true,
        ],
        logger: logger,
      );

      final outcome = await recorder.record(_result('s-3'));

      expect(outcome, isA<Success<void>>());
      expect(secondRan, isTrue);
      expect(logger.warnings, <String>[
        'practice_session_after_record_hook_failed',
      ]);
    });
  });

  group('A2 — practiceRewardHistorySnapshot', () {
    test('sums, counts and collects ONLY the entries of the given '
        'day', () async {
      final ledger = LocalRewardLedgerRepository(
        store: InMemoryKeyValueStore(),
        logger: const NoopAppLogger(),
      );
      final today = DateTime(2026, 9, 6, 14);
      final yesterday = DateTime(2026, 9, 5, 14);
      await ledger.appendIfAbsent(
        _entry('practice-session/a/v1', createdAt: today, totalXp: 7),
      );
      await ledger.appendIfAbsent(
        _entry('song-session/b/v1', createdAt: today, totalXp: 5),
      );
      await ledger.appendIfAbsent(
        _entry('practice-session/c/v1', createdAt: yesterday, totalXp: 9),
      );

      final snapshot = practiceRewardHistorySnapshot(
        ledger: ledger,
        epochDay: StreakLogic.epochDayOf(today),
      );

      expect(snapshot.earnedTodayXp, 12);
      expect(snapshot.practiceOccurrenceCount, 1);
      expect(snapshot.uniqueSourcesToday, 2);
      expect(snapshot.rewardedEventIds, <String>{
        'practice-session/a/v1',
        'song-session/b/v1',
      });
      expect(snapshot.rewardedParentIds, isEmpty);
      expect(snapshot.rewardedChildParentIds, isEmpty);
    });

    test('an empty ledger yields the zero snapshot', () {
      final ledger = LocalRewardLedgerRepository(
        store: InMemoryKeyValueStore(),
        logger: const NoopAppLogger(),
      );

      final snapshot = practiceRewardHistorySnapshot(
        ledger: ledger,
        epochDay: 20_000,
      );

      expect(snapshot.earnedTodayXp, 0);
      expect(snapshot.practiceOccurrenceCount, 0);
      expect(snapshot.uniqueSourcesToday, 0);
      expect(snapshot.rewardedEventIds, isEmpty);
    });
  });

  group('A3 — practiceSessionCountsAsPractice', () {
    test('finished sessions count, abandoned or failed ones do not', () {
      expect(
        practiceSessionCountsAsPractice(
          PracticeFinishReason.completedAllTargets,
        ),
        isTrue,
      );
      expect(
        practiceSessionCountsAsPractice(PracticeFinishReason.userFinished),
        isTrue,
      );
      expect(
        practiceSessionCountsAsPractice(PracticeFinishReason.timedOut),
        isTrue,
      );
      expect(
        practiceSessionCountsAsPractice(PracticeFinishReason.cancelled),
        isFalse,
      );
      expect(
        practiceSessionCountsAsPractice(PracticeFinishReason.interrupted),
        isFalse,
      );
      expect(
        practiceSessionCountsAsPractice(PracticeFinishReason.failed),
        isFalse,
      );
    });
  });

  group('A4 — the result screen reads the gamification ledger', () {
    test('rewardLedgerRepositoryProvider is the gamification instance', () {
      final container = ProviderContainer(overrides: preferenceOverrides());
      addTearDown(container.dispose);

      expect(
        container.read(rewardLedgerRepositoryProvider),
        same(container.read(gamificationRewardLedgerRepositoryProvider)),
      );
    });
  });

  group('A5 — the production hook list in a real container', () {
    test('a 90 s completed session advances the streak, lands a ledger '
        'entry and moves the profile XP off zero', () async {
      final container = ProviderContainer(overrides: preferenceOverrides());
      addTearDown(container.dispose);
      final hooks = container.read(practiceSessionRecordedHooksProvider);
      expect(hooks, hasLength(3));
      expect(container.read(streakProvider).current, 0);
      expect(container.read(gamificationProfileProvider).totalXp, 0);

      final result = _result(
        's-e2e',
        activeDuration: const Duration(seconds: 90),
      );
      for (final hook in hooks) {
        await hook(result, _definition());
      }

      expect(container.read(streakProvider).current, 1);
      final eventId = GamificationPracticeAdapter.stableEventId('s-e2e');
      final ledger = container.read(gamificationRewardLedgerRepositoryProvider);
      expect(ledger.hasProcessedEvent(eventId), isTrue);
      expect(
        container.read(gamificationProfileProvider).totalXp,
        greaterThan(0),
      );
    });

    test('a cancelled session credits nothing', () async {
      final container = ProviderContainer(overrides: preferenceOverrides());
      addTearDown(container.dispose);
      final hooks = container.read(practiceSessionRecordedHooksProvider);

      final result = _result(
        's-cancelled',
        activeDuration: const Duration(seconds: 90),
        finishReason: PracticeFinishReason.cancelled,
      );
      for (final hook in hooks) {
        await hook(result, _definition());
      }

      expect(container.read(streakProvider).current, 0);
      final eventId = GamificationPracticeAdapter.stableEventId('s-cancelled');
      final ledger = container.read(gamificationRewardLedgerRepositoryProvider);
      expect(ledger.hasProcessedEvent(eventId), isFalse);
      expect(container.read(gamificationProfileProvider).totalXp, 0);
    });
  });
}

final class _SucceedingRecorder implements PracticeSessionRecorder {
  const _SucceedingRecorder();

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async =>
      const Success<void>(null);
}

final class _FailingRecorder implements PracticeSessionRecorder {
  const _FailingRecorder();

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async =>
      const Failure<void>(StorageFailure());
}

final class _RecordingLogger implements AppLogger {
  final List<String> warnings = <String>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    warnings.add(event);
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

PracticeDefinition _definition() => PracticeDefinition(
  id: 'fixture.session',
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSetupTitle',
  descriptionKey: 'practiceCatalogTestSetupDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: const <PracticeEvent>[],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['test'],
  displayTitle: 'Session fixture',
);

PracticeSessionResult _result(
  String id, {
  Duration activeDuration = const Duration(seconds: 30),
  PracticeFinishReason finishReason = PracticeFinishReason.userFinished,
}) {
  return PracticeSessionResult(
    id: id,
    activeDuration: activeDuration,
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[
      PracticeAttemptResult(
        index: 0,
        tempo: const Tempo(90),
        metrics: _metrics,
        verdicts: const <PracticeVerdict>[],
        outcome: PracticeAttemptOutcome.passed,
      ),
    ],
    finishReason: finishReason,
    highestStableTempo: const Tempo(90),
    coachingSummary: const <String>[],
  );
}

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(0.9),
  rhythm: MetricAvailable(0.85),
  direction: MetricAvailable(0.95),
  chord: MetricNotApplicable(),
  overall: MetricAvailable(0.9),
  totalTargets: 16,
  resolvedTargets: 14,
  maxCombo: 8,
  scorePoints: 800,
  meanAbsoluteOffset: Duration(milliseconds: 18),
  timingBias: Duration.zero,
);

RewardLedgerEntry _entry(
  String sourceEventId, {
  required DateTime createdAt,
  required int totalXp,
}) => RewardLedgerEntry(
  ledgerId: 'ledger-$sourceEventId',
  sourceEventId: sourceEventId,
  createdAt: createdAt,
  schemaVersion: rewardLedgerEntrySchemaVersion,
  policyVersion: 1,
  baseXp: totalXp,
  bonusXp: 0,
  totalXp: totalXp,
  reasonCodes: const <RewardReason>[RewardReason.baseExperience],
);
