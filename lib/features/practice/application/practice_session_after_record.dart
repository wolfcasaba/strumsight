// After-record hooks of the Practice Engine V2 session (javító sáv
// 2026-09-06, `docs/ui/apk-functionality-audit-2026-09-06.md` §1.3;
// E16-R05 leletek L4/L5; E16-R01 backlog §6.6).
//
// A durably recorded V2 session used to be invisible to the rest of the app
// until a full restart:
//
//   * `practiceHistoryV2ListProvider` is a plain `FutureProvider` that nothing
//     in `lib/` invalidated (E16-R05 L5) — Progress / Today / Library kept
//     the FIRST read for the whole container lifetime;
//   * the streak was credited only by the V1 Learn path
//     (`PracticeSessionRecording`), never by a V2 session;
//   * `GamificationPracticeAdapter` had ZERO callers in `lib/` (E16-R01
//     backlog §6.6) — no XP was ever awarded, the hub stayed at 0 forever.
//
// The hooks run AFTER `PracticeSessionRecorder.record` returned `Success` —
// the session is already saved, so a hook failure is logged and NEVER turns a
// saved session into a failure (the same contract the outbox drain gives the
// ledger). Every provider a hook needs is resolved lazily, inside the hook,
// so a container without the composition root (a widget test) still records
// the session and only logs the missing side effect.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../gamification/public.dart';
import '../../streak/public.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_metrics.dart';
import '../domain/model/practice_session_result.dart';
import '../domain/repository/practice_session_recorder.dart';
import '../domain/service/practice_session_eligibility.dart';
import 'gamification_practice_adapter.dart';
import 'practice_progress_providers.dart';
import 'practice_result_target.dart';
import 'practice_session_recording.dart';

/// One side effect to run after a V2 session was durably recorded.
typedef PracticeSessionRecordedHook =
    Future<void> Function(
      PracticeSessionResult result,
      PracticeDefinition definition,
    );

/// Decorates a [PracticeSessionRecorder]: forwards `record`, and on
/// [Success] runs every hook in order. A hook exception is logged under
/// `practice_session_after_record_hook_failed` and does not propagate — the
/// session is already saved, and the refresh / streak / reward work must not
/// turn that into a user-visible failure. On [Failure] no hook runs.
final class PracticeSessionRecorderWithHooks
    implements PracticeSessionRecorder {
  const PracticeSessionRecorderWithHooks({
    required PracticeSessionRecorder inner,
    required PracticeDefinition definition,
    required List<PracticeSessionRecordedHook> hooks,
    required AppLogger logger,
    void Function(PracticeSessionResult result)? onRecordFailed,
  }) : _inner = inner, // ignore: prefer_initializing_formals
       _definition = definition, // ignore: prefer_initializing_formals
       _hooks = hooks, // ignore: prefer_initializing_formals
       _logger = logger, // ignore: prefer_initializing_formals
       _onRecordFailed = onRecordFailed; // ignore: prefer_initializing_formals

  final PracticeSessionRecorder _inner;
  final PracticeDefinition _definition;
  final List<PracticeSessionRecordedHook> _hooks;
  final AppLogger _logger;

  /// Told when the durable write itself failed (no hook runs then) — the
  /// result route stops waiting for an entry that will never arrive.
  final void Function(PracticeSessionResult result)? _onRecordFailed;

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async {
    final outcome = await _inner.record(result);
    if (outcome case Failure()) {
      _onRecordFailed?.call(result);
      return outcome;
    }
    for (var index = 0; index < _hooks.length; index++) {
      try {
        await _hooks[index](result, _definition);
      } catch (error, stackTrace) {
        _logger.warning(
          'practice_session_after_record_hook_failed',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{'hook': index, 'sessionId': result.id},
        );
      }
    }
    return outcome;
  }
}

/// The production hook list, in execution order:
///
/// 1. award XP through the merged gamification chain (backlog §6.6),
/// 2. credit the streak when the session qualifies (L4 — the V1 log is NOT
///    written: `aggregatedPracticeFeedProvider` already unions V1 + V2, so a
///    V1 copy would double-count the daily goal),
/// 3. refresh the V2 history views LAST (L5).
///
/// The order is load-bearing, not cosmetic: the hooks run sequentially with
/// `await`, and hook 3 is what RELEASES the result screen — it names the
/// entry on `practiceResultTargetProvider` and invalidates
/// `practiceHistoryV2ListProvider`, so `PracticeResultRoute` builds
/// `PracticeResultScreen` as soon as the reloaded list carries the entry.
/// `_RewardSection` then reads `practiceRewardForSessionProvider`, which is
/// a one-shot ledger lookup cached for the container's lifetime. Refreshing
/// first would let that lookup run BEFORE `_awardGamification` appended the
/// ledger entry, and the session would show "no reward" forever. Awarding
/// first means the ledger entry — and the invalidated profile / achievement
/// / inbox projections — are already in place when the screen appears.
final practiceSessionRecordedHooksProvider =
    Provider<List<PracticeSessionRecordedHook>>((ref) {
      return <PracticeSessionRecordedHook>[
        (result, definition) async =>
            _awardGamification(ref, result, definition),
        (result, definition) async => _creditStreak(ref, result),
        (result, definition) async => _refreshHistoryViews(ref, result),
      ];
    });

/// The gamification chain for one finished V2 practice session, composed
/// from the merged gamification infrastructure (ADR 0390 / E16-R01):
/// eligibility → policy → ledger entry → outbox. `newOnly` — the V1
/// statistics sink is not called (see the hook-list note above), so the
/// legacy sink is a no-op by construction.
final practiceGamificationAdapterProvider =
    Provider<GamificationPracticeAdapter>((ref) {
      final ledger = ref.watch(gamificationRewardLedgerRepositoryProvider);
      return GamificationPracticeAdapter(
        ingestor: ref.watch(activityEventIngestorProvider),
        eligibility: DefaultRewardEligibilityPolicy(
          config: RewardEligibilityPolicyConfig.standard(),
        ),
        rewardPolicy: DefaultRewardPolicy(
          config: RewardPolicyConfig.standard(),
        ),
        historyBuilder: (epochDay, lessonId) =>
            practiceRewardHistorySnapshot(ledger: ledger, epochDay: epochDay),
        dualWriteMode: GamificationDualWriteMode.newOnly,
        legacySink: (_) async {},
      );
    });

/// The prefix of [GamificationPracticeAdapter.stableEventId]
/// (`practice-session/<id>/v1`) before its first `/`.
const String _practiceSessionEventPrefix = 'practice-session';

/// Today's policy inputs, read from the ledger (the adapter never reads the
/// ledger itself). The ledger entry carries no lesson id, so
/// `practiceOccurrenceCount` counts EVERY practice-session entry of the day
/// — a stricter repeat decay than a per-lesson count, never a looser one.
/// Parent/child ids are not produced by the practice path, so both sets are
/// empty.
@visibleForTesting
PracticeRewardHistorySnapshot practiceRewardHistorySnapshot({
  required RewardLedgerRepository ledger,
  required int epochDay,
  int pageSize = 100,
  int maxPages = 50,
}) {
  var earnedTodayXp = 0;
  var practiceOccurrenceCount = 0;
  final sourcesToday = <String>{};
  final rewardedEventIds = <String>{};
  String? cursor;
  for (var page = 0; page < maxPages; page++) {
    final result = ledger.readPage(limit: pageSize, cursor: cursor);
    for (final entry in result.entries) {
      if (StreakLogic.epochDayOf(entry.createdAt) != epochDay) continue;
      earnedTodayXp += entry.totalXp;
      rewardedEventIds.add(entry.sourceEventId);
      final source = entry.sourceEventId.split('/').first;
      sourcesToday.add(source);
      if (source == _practiceSessionEventPrefix) practiceOccurrenceCount += 1;
    }
    final next = result.nextCursor;
    if (next == null || next == cursor) break;
    cursor = next;
  }
  return PracticeRewardHistorySnapshot(
    earnedTodayXp: earnedTodayXp,
    practiceOccurrenceCount: practiceOccurrenceCount,
    uniqueSourcesToday: sourcesToday.length,
    rewardedEventIds: rewardedEventIds,
    rewardedParentIds: const <String>{},
    rewardedChildParentIds: const <String>{},
  );
}

/// Whether the terminal reason describes practice that happened (as opposed
/// to a session the user abandoned or one that failed to run).
@visibleForTesting
bool practiceSessionCountsAsPractice(PracticeFinishReason reason) =>
    switch (reason) {
      PracticeFinishReason.completedAllTargets ||
      PracticeFinishReason.userFinished ||
      PracticeFinishReason.timedOut => true,
      PracticeFinishReason.cancelled ||
      PracticeFinishReason.interrupted ||
      PracticeFinishReason.failed => false,
    };

Future<void> _refreshHistoryViews(Ref ref, PracticeSessionResult result) async {
  if (!ref.mounted) return;
  // The result route may already be waiting for THIS entry (the navigation
  // sink fires before the record completes) — name it before the list
  // re-loads, so the route never settles on "unavailable" in between.
  ref.read(practiceResultTargetProvider.notifier).recorded(result.id);
  // A later read re-loads the repository the recorder just wrote to; every
  // dependent (Progress dashboard, Today ring, Library sources) rebuilds.
  ref.invalidate(practiceHistoryV2ListProvider);
}

Future<void> _creditStreak(Ref ref, PracticeSessionResult result) async {
  if (!practiceSessionCountsAsPractice(result.finishReason)) return;
  // The V2 result does not carry the V1 "resolved targets" / "free strums"
  // counters, so only the active-duration threshold of the canonical
  // predicate can qualify a session here — the conservative direction.
  final input = PracticeSessionEligibilityInput(
    activeDuration: result.activeDuration,
    resolvedRequiredTargets: 0,
    freePracticeStrums: 0,
  );
  final eligibility = ref.read(practiceSessionEligibilityProvider);
  if (!eligibility.isEligible(input)) return;
  await ref.read(streakProvider.notifier).recordPracticeToday();
}

Future<void> _awardGamification(
  Ref ref,
  PracticeSessionResult result,
  PracticeDefinition definition,
) async {
  final adapter = ref.read(practiceGamificationAdapterProvider);
  final now = DateTime.now();
  final overall = result.bestAttempt?.metrics.overall;
  final quality = overall is MetricAvailable ? overall.value : null;
  final outcome = await adapter.recordSession(
    PracticeGamificationSignal(
      sessionId: result.id,
      lessonId: definition.id,
      outcome: _activityOutcomeOf(result.finishReason),
      validDuration: result.activeDuration,
      quality: quality,
      // A scored attempt is device-scored evidence; a session that produced
      // no scored attempt is only device-observed.
      evidenceTrust: quality == null
          ? EvidenceTrust.deviceObserved
          : EvidenceTrust.scored,
      score: quality ?? 0.0,
      epochDay: StreakLogic.epochDayOf(now),
      occurredAt: now,
    ),
  );
  if (!outcome.accepted) return;
  // The ingestor only ENQUEUES; the ledger sees the entry on drain. Drain
  // now so the result screen (which reads the ledger, never estimates) can
  // show the reward of the session that just ended.
  await ref.read(activityEventIngestorProvider).drain();
  final projector = ref.read(gamificationProfileProjectorProvider);
  final projection = await projector.rebuild();
  final repository = ref.read(gamificationRepositoryProvider);
  await repository.replaceProfileSnapshot(
    GamificationProfileSnapshot(totalXp: projection.profile.totalXp),
  );
  if (!ref.mounted) return;
  ref.invalidate(gamificationProfileProvider);
  ref.invalidate(achievementProgressProvider);
  ref.invalidate(rewardInboxItemsProvider);
}

ActivityOutcome _activityOutcomeOf(PracticeFinishReason reason) =>
    switch (reason) {
      PracticeFinishReason.completedAllTargets ||
      PracticeFinishReason.userFinished ||
      PracticeFinishReason.timedOut => ActivityOutcome.completed,
      PracticeFinishReason.cancelled ||
      PracticeFinishReason.interrupted => ActivityOutcome.cancelled,
      PracticeFinishReason.failed => ActivityOutcome.failed,
    };
