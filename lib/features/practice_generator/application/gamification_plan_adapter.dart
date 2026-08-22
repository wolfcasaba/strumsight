// E08-R26 — Practice-Generator plan completion → gamification reward
// adapter.
//
// Maps a caller-supplied plan-completion signal onto the canonical
// gamification chain `event → eligibility → policy → ledger entry →
// outbox`, mirroring the practice / lesson / song adapter shape so
// every cross-feature bridge stays uniform.
//
// Two design choices are dictated by brief §0.0/4 and §5.3 (ADR 0392):
//
// 1. The adapter does NOT observe `PlanStatus`. The plan-wide enum
//    is unreachable from completion in the current code (measured:
//    `grep -rn "PlanStatus\." lib/features/practice_generator/`
//    shows only `draft` / `active` / `paused` transitions — see
//    L20, the "elérhetetlen cél-státusz" halt class). Block-level
//    completion (`PracticeItemStatus.completed`) IS reachable today
//    and IS already rewarded through the practice / song adapters
//    that sit downstream of the plan. The adapter therefore
//    deliberately takes a caller-fed `planCompleted: bool` signal
//    (the §0.0/4 ADJ decision, mirroring `SongGamificationSignal.
//    fullSongCompleted`) and refuses to read any state-machine file
//    inside `practice_generator`.
//
// 2. The plan-completion event is a *bonus only* (brief §5.3). The
//    plan's blocks have already been rewarded on their own source
//    path (practice, song, etc.); aggregating them a second time
//    would inflate the ledger (the §6.1 A3 cell). The adapter
//    produces exactly one event with a flat bonus signal — no
//    per-block aggregation, no parent-child linking, no derivation
//    from the block ledger. The event id format makes the bonus
//    visible in diagnostics so a future audit can confirm it never
//    grew block-level XP.
//
// All other fields follow the same contract as the song / practice /
// lesson adapters: imports the gamification feature ONLY through its
// `public.dart` barrel, never inspects the practice_generator
// feature's internals, and never introduces a new network or
// platform call (A8).

import 'package:meta/meta.dart';

import '../../gamification/public.dart';

/// Inputs the plan adapter needs about one plan completion. Pure
/// values only — no Riverpod snapshots, no clocks, no repositories.
///
/// The adapter derives the public event id deterministically from
/// [planId] (ADR 0390 §4) so a result-screen reopen produces the
/// same event id and the ledger's append-if-absent absorbs the
/// duplicate write.
@immutable
final class PlanGamificationSignal {
  const PlanGamificationSignal({
    required this.planId,
    required this.planCompleted,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
  }) : assert(
         validDuration >= Duration.zero,
         'validDuration must be non-negative',
       );

  /// Persisted, save-time identifier of the plan. The adapter
  /// namespaces the event under this id (brief §6 A2
  /// session-namespacing).
  final String planId;

  /// Whether the plan is being reported as completed. When `false`,
  /// the adapter is a no-op — only plan completion earns a reward
  /// (brief §5.3). The caller is expected to set this from a future
  /// UI signal that lives outside this round's scope.
  final bool planCompleted;

  /// Validated, non-negative duration the caller counted toward the
  /// plan. The adapter uses this only to satisfy the R05 eligibility
  /// gate — the bonus itself is flat (no duration component
  /// aggregation, §5.3).
  final Duration validDuration;

  /// Optional quality observation in `[0, 1]`. `null` is permitted; the
  /// eligibility layer treats a missing quality as
  /// `fatalSignalQuality`.
  final double? quality;

  /// The evidence-trust grade the caller attached to the plan.
  final EvidenceTrust evidenceTrust;

  /// Canonical score field of the [PlanActivityEvent] in `[0, 1]`.
  final double score;

  /// Epoch day the plan completion belongs to.
  final int epochDay;

  /// Wall-clock instant the plan completion was recorded; stamped on
  /// the [RewardLedgerEntry.createdAt].
  final DateTime occurredAt;
}

/// Snapshot the policy engine needs from the surrounding ledger state.
@immutable
final class PlanRewardHistorySnapshot {
  const PlanRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.planOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;
  final int planOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

typedef PlanHistoryBuilder =
    PlanRewardHistorySnapshot Function(int epochDay, String practiceKey);

/// Outcome of one adapter invocation.
@immutable
final class PlanGamificationOutcome {
  const PlanGamificationOutcome.noOp() : eventId = null, accepted = false;

  const PlanGamificationOutcome.rewarded({required this.eventId})
    : accepted = true;

  final String? eventId;
  final bool accepted;
}

/// Pure adapter. Maps one plan-completion signal into the canonical
/// gamification chain.
///
/// The adapter holds a tiny in-memory set of `planId`s it has
/// rewarded in this process lifetime so a double-call from a
/// result-screen reopen path collapses to one event — the same
/// ledger-append-if-absent mechanism would also catch the
/// duplicate, but the in-memory check makes the §A3 reopen
/// behaviour observable in unit tests without going through the
/// drain.
class GamificationPlanAdapter {
  GamificationPlanAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required PlanHistoryBuilder historyBuilder,
    required bool featureEnabled,
  }) : _ingestor = ingestor,
       _eligibility = eligibility,
       _rewardPolicy = rewardPolicy,
       _historyBuilder = historyBuilder,
       _featureEnabled = featureEnabled;

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final PlanHistoryBuilder _historyBuilder;
  final bool _featureEnabled;

  /// Plan ids the adapter has rewarded in this process lifetime.
  /// Capped at [_reopenLedgerCap] entries to bound memory.
  final Set<String> _rewardedPlanIds = <String>{};

  /// Hard cap on the reopen-tracking set. The ledger's
  /// append-if-absent is the durable dedup; this is a fast-path
  /// for unit tests.
  static const int _reopenLedgerCap = 1024;

  /// Adapter version stamped on the produced [RewardLedgerEntry].
  static const int adapterPolicyVersion = 1;

  /// Schema-version constant carried by every emitted event.
  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Stable event id for a plan-completion event. Format is opaque
  /// and versioned; the suffix (`/v1`) lets a future migration
  /// introduce a v2 without colliding with v1 ids.
  static String eventIdFor(String planId) => 'plan-bonus/$planId/v1';

  /// Apply [signal] to the chain. Returns the resulting outcome.
  /// When [PlanGamificationSignal.planCompleted] is `false` — or
  /// the adapter is feature-switched off, or the R05 gate denies,
  /// or the plan id was already rewarded this process — the
  /// adapter returns [PlanGamificationOutcome.noOp].
  Future<PlanGamificationOutcome> recordCompletion(
    PlanGamificationSignal signal,
  ) async {
    // A7 — feature-switch fallback.
    if (!_featureEnabled) {
      return const PlanGamificationOutcome.noOp();
    }

    // §5.3 — completion is the only rewarded transition. A
    // non-completion signal (e.g. an in-progress pause/resume) is a
    // no-op.
    if (!signal.planCompleted) {
      return const PlanGamificationOutcome.noOp();
    }

    // §A3 — a second call for the same planId in this process
    // lifetime collapses to a no-op. The durable guard is the
    // ledger's append-if-absent; this set is a fast-path that lets
    // the test assert the reopen behaviour without going through
    // the drain.
    if (_rewardedPlanIds.contains(signal.planId)) {
      return const PlanGamificationOutcome.noOp();
    }

    final decision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.practicePlan,
        outcome: ActivityOutcome.completed,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!decision.baseXp.isGranted) {
      // R05 denied — too short / cancelled / failed. No event.
      return const PlanGamificationOutcome.noOp();
    }

    final eventId = eventIdFor(signal.planId);
    final practiceKey = signal.planId;

    final event = PlanActivityEvent(
      eventId: eventId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.practicePlan,
      trust: signal.evidenceTrust,
      schemaVersion: _schemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );

    final history = _historyBuilder(signal.epochDay, practiceKey);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: practiceKey,
      parentEventId: null,
      epochDay: signal.epochDay,
      source: ActivitySource.practicePlan,
      eligibility: decision,
      validDuration: signal.validDuration,
      qualityScore: signal.quality ?? 0.0,
      improvementDelta: 0,
      uniqueSourcesToday: history.uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: signal.epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.planOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);

    final entry = _buildLedgerEntry(
      planId: signal.planId,
      eventId: eventId,
      practiceKey: practiceKey,
      occurredAt: signal.occurredAt,
      points: policyDecision.points,
      policyVersion: policyDecision.policyVersion,
    );

    await _ingestor.recordSavedActivity(event: event, entry: entry);

    // Bookkeeping — bounded. The cap is well above any realistic
    // per-user plan count; eviction is just an in-memory hygiene
    // measure, the ledger is the durable source of truth.
    if (_rewardedPlanIds.length >= _reopenLedgerCap) {
      _rewardedPlanIds.clear();
    }
    _rewardedPlanIds.add(signal.planId);

    return PlanGamificationOutcome.rewarded(eventId: eventId);
  }

  RewardLedgerEntry _buildLedgerEntry({
    required String planId,
    required String eventId,
    required String practiceKey,
    required DateTime occurredAt,
    required ExperiencePoints points,
    required int policyVersion,
  }) {
    final baseXp = points.baseXp;
    // §5.3 — the completion bonus is a flat signal. We discard
    // every non-base component the policy engine computes, because
    // the blocks have already been rewarded on their own source
    // path (practice / song). The policy's components are still
    // computed so the test suite can verify the adapter's input
    // signal shape, but the ledger sees only `baseXp`.
    final bonusXp = 0;
    final totalXp = baseXp;
    return RewardLedgerEntry(
      ledgerId: 'plan-bonus/$practiceKey/$eventId/$totalXp',
      sourceEventId: eventId,
      createdAt: occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasonCodes: <RewardReason>[
        if (totalXp > 0) RewardReason.achievementUnlocked,
      ],
    );
  }
}
