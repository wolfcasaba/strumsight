// The learner-loop XP round: a saved Practice V2 session is fed to the SHARED
// reward pipeline (adapter → outbox → ledger); the result screen ledger
// seam reads the very same ledger — so "+N XP" on the result screen is a
// real ledger entry, never an estimate, and a reward failure never fails
// the session.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/application/practice_reward_providers.dart';
import 'package:strumsight/features/practice/application/practice_reward_recorder.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_session_recorder.dart';
import 'package:strumsight/features/practice/presentation/providers/practice_result_providers.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../support/preference_store.dart';

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

PracticeSessionResult _result(
  String id, {
  Duration activeDuration = const Duration(minutes: 2, seconds: 30),
  PracticeFinishReason finishReason = PracticeFinishReason.completedAllTargets,
  bool scored = true,
}) => PracticeSessionResult(
  id: id,
  activeDuration: activeDuration,
  pausedDuration: Duration.zero,
  attempts: scored
      ? <PracticeAttemptResult>[
          PracticeAttemptResult(
            index: 0,
            tempo: const Tempo(90),
            metrics: _metrics,
            verdicts: const <PracticeVerdict>[],
            outcome: PracticeAttemptOutcome.passed,
          ),
        ]
      : const <PracticeAttemptResult>[],
  finishReason: finishReason,
  highestStableTempo: const Tempo(90),
  coachingSummary: const <String>[],
);

final class _FailingRecorder implements PracticeSessionRecorder {
  const _FailingRecorder();
  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async =>
      const Failure<void>(StorageFailure());
}

final _now = DateTime.utc(2026, 9, 15, 10, 30);

({ProviderContainer container, RewardingPracticeSessionRecorder recorder})
_harness({
  PracticeSessionRecorder inner = const NoopPracticeSessionRecorder(),
}) {
  final container = ProviderContainer(overrides: preferenceOverrides());
  addTearDown(container.dispose);
  final recorder = RewardingPracticeSessionRecorder(
    inner: inner,
    adapter: container.read(practiceGamificationAdapterProvider),
    ingestor: container.read(activityEventIngestorProvider),
    definitionId: 'builtin.quarterDownstrokes.v1',
    now: () => _now,
    logger: const NoopAppLogger(),
  );
  return (container: container, recorder: recorder);
}

void main() {
  group('the saved session reaches the shared ledger', () {
    test('a scored, long-enough session writes exactly one ledger entry that '
        'the result screen seam reads back', () async {
      final h = _harness();
      final saved = await h.recorder.record(_result('session-xp-1'));
      expect(saved, isA<Success<void>>());

      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      final entries = ledger.readPage(limit: 10).entries;
      expect(entries, hasLength(1));
      expect(entries.single.totalXp, greaterThan(0));
      expect(entries.single.sourceEventId, 'practice-session/session-xp-1/v1');

      // The SAME ledger, through the result screen's seam.
      final reward = h.container.read(
        practiceRewardForSessionProvider('session-xp-1'),
      );
      expect(reward, isNotNull);
      expect(reward!.totalXp, entries.single.totalXp);
    });

    test('recording the same session twice keeps one entry', () async {
      final h = _harness();
      await h.recorder.record(_result('session-xp-2'));
      await h.recorder.record(_result('session-xp-2'));
      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      expect(ledger.readPage(limit: 10).entries, hasLength(1));
    });

    test('two different sessions on the same day both earn, and the second '
        'sees the first in its history', () async {
      final h = _harness();
      await h.recorder.record(_result('session-a'));
      await h.recorder.record(_result('session-b'));
      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      expect(ledger.readPage(limit: 10).entries, hasLength(2));
      final snapshot = practiceRewardHistorySnapshotFromLedger(
        ledger,
        epochDay: StreakLogic.epochDayOf(_now),
      );
      expect(snapshot.practiceOccurrenceCount, 2);
      expect(snapshot.rewardedEventIds, hasLength(2));
      expect(snapshot.earnedTodayXp, greaterThan(0));
    });
  });

  group('honest gates — no XP without a real, eligible session', () {
    test('a 30-second session is saved but earns nothing', () async {
      final h = _harness();
      final saved = await h.recorder.record(
        _result('short', activeDuration: const Duration(seconds: 30)),
      );
      expect(saved, isA<Success<void>>());
      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      expect(ledger.readPage(limit: 10).entries, isEmpty);
      expect(
        h.container.read(practiceRewardForSessionProvider('short')),
        isNull,
      );
    });

    test('a cancelled session earns nothing', () async {
      final h = _harness();
      await h.recorder.record(
        _result('cancelled', finishReason: PracticeFinishReason.cancelled),
      );
      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      expect(ledger.readPage(limit: 10).entries, isEmpty);
    });

    test('a failed history save returns the failure, awards nothing', () async {
      final h = _harness(inner: const _FailingRecorder());
      final saved = await h.recorder.record(_result('unsaved'));
      expect(saved, isA<Failure<void>>());
      final ledger = h.container.read(
        gamificationRewardLedgerRepositoryProvider,
      );
      expect(ledger.readPage(limit: 10).entries, isEmpty);
    });
  });

  group('signal mapping is a pure function of the result', () {
    test('finish reasons map to outcomes; a scored session is trusted as '
        'scored with its best overall as quality', () {
      final signal = practiceGamificationSignalFor(
        _result('s'),
        definitionId: 'd',
        now: _now,
      );
      expect(signal.outcome, ActivityOutcome.completed);
      expect(signal.quality, 0.9);
      expect(signal.score, 0.9);
      expect(signal.evidenceTrust, EvidenceTrust.scored);
      expect(signal.lessonId, 'd');
      expect(signal.validDuration, const Duration(minutes: 2, seconds: 30));
      expect(signal.occurredAt, _now);

      expect(
        practiceGamificationSignalFor(
          _result('s', finishReason: PracticeFinishReason.interrupted),
          definitionId: 'd',
          now: _now,
        ).outcome,
        ActivityOutcome.cancelled,
      );
      expect(
        practiceGamificationSignalFor(
          _result('s', finishReason: PracticeFinishReason.failed),
          definitionId: 'd',
          now: _now,
        ).outcome,
        ActivityOutcome.failed,
      );
    });

    test('an unscored session carries no quality and only device-observed '
        'trust', () {
      final signal = practiceGamificationSignalFor(
        _result('s', scored: false),
        definitionId: 'd',
        now: _now,
      );
      expect(signal.quality, isNull);
      expect(signal.score, 0.0);
      expect(signal.evidenceTrust, EvidenceTrust.deviceObserved);
    });
  });
}
