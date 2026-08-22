import 'package:meta/meta.dart';

import '../../gamification/public.dart';

/// The three states of the caller-fed migration switch that decides whether
/// the practice adapter writes through the new outbox path at all, and
/// whether the legacy statistics sink is invoked in parallel.
///
/// * [GamificationDualWriteMode.off] — the historical behavior; the adapter
///   is a no-op. No new event is enqueued, no XP is awarded, no legacy sink
///   is called. This is the default value for the migration period.
/// * [GamificationDualWriteMode.dual] — the brief §5.4 "rajta" state: the
///   adapter runs the eligibility → policy → ledger chain AND invokes the
///   legacy sink in parallel. The legacy sink is contractually a
///   statistics-only write; XP is awarded exactly once through the new
///   system.
/// * [GamificationDualWriteMode.newOnly] — the Kör-30 target state ("fölött"
///   in §6.1); the legacy sink is no longer called. The adapter never
///   activates this value in production today — it is implemented so the
///   three-state surface is testable.
enum GamificationDualWriteMode { off, dual, newOnly }

/// Inputs the practice adapter needs about one finished session. Pure values
/// only — no Riverpod snapshots, no clocks, no repositories — so the adapter
/// stays deterministic and easy to drive from tests.
///
/// All fields describe the session exactly as it was at save time; the
/// adapter is forbidden from re-deriving them from a clock or from looking
/// at any other provider state.
@immutable
final class PracticeGamificationSignal {
  const PracticeGamificationSignal({
    required this.sessionId,
    required this.lessonId,
    required this.outcome,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
  }) : assert(
         outcome != ActivityOutcome.completed ||
             (validDuration >= Duration.zero),
         'validDuration must be non-negative for completed sessions',
       );

  /// The persisted, save-time identifier of the practice session. The
  /// adapter derives [eventId] deterministically from it (ADR 0390 §4) so the
  /// result-screen reopening produces the same eventId.
  final String sessionId;

  /// The lesson / play-along the session was on. Used by the policy engine
  /// as the [RewardPolicyRequest.practiceKey] for diminishing returns.
  final String lessonId;

  /// The terminal outcome the caller has already classified. The adapter
  /// forwards it to the R05 eligibility layer as-is.
  final ActivityOutcome outcome;

  /// Validated, non-negative duration the caller counted toward the session.
  final Duration validDuration;

  /// Optional quality observation in [0, 1]. `null` is a permitted signal —
  /// the eligibility layer treats a missing quality as
  /// `fatalSignalQuality`.
  final double? quality;

  /// The evidence-trust grade the caller attached to this session.
  final EvidenceTrust evidenceTrust;

  /// The canonical score field of the [PracticeActivityEvent] in [0, 1].
  /// Distinct from [quality]: it is the published event field, not the
  /// eligibility input.
  final double score;

  /// The epoch day the session belongs to.
  final int epochDay;

  /// The wall-clock instant the session ended. Stamped on the
  /// [RewardLedgerEntry.createdAt].
  final DateTime occurredAt;
}

/// Snapshot the policy engine needs from the surrounding ledger state. Built
/// by the caller from the [RewardLedgerRepository] read page; the adapter
/// never reads the ledger itself.
@immutable
final class PracticeRewardHistorySnapshot {
  const PracticeRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.practiceOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;
  final int practiceOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

/// Output of one adapter invocation. Tells the caller which path was taken
/// without leaking any ledger-internal state.
@immutable
final class PracticeGamificationOutcome {
  const PracticeGamificationOutcome._({
    required this.eventId,
    required this.accepted,
    required this.dualWriteInvoked,
  });

  /// The adapter was a no-op — the switch is [GamificationDualWriteMode.off]
  /// or the R05 eligibility gate denied the activity. No event was enqueued,
  /// no ledger entry was written, no legacy sink was called.
  const PracticeGamificationOutcome.noOp()
    : eventId = null,
      accepted = false,
      dualWriteInvoked = false;

  /// The adapter ran the full chain and produced an event. The caller can
  /// safely invoke [recordSavedActivity]-equivalent work asynchronously
  /// knowing the identifier is stable across reopens.
  const PracticeGamificationOutcome.rewarded({
    required String eventId,
    required bool dualWriteInvoked,
  }) : eventId = eventId,
       accepted = true,
       dualWriteInvoked = dualWriteInvoked;

  /// The canonical event id, derived from the session id (ADR 0390 §4).
  /// `null` for [PracticeGamificationOutcome.noOp] results.
  final String? eventId;

  /// True when the adapter enqueued an event for the new outbox path.
  final bool accepted;

  /// True when the legacy sink was invoked (only meaningful in
  /// [GamificationDualWriteMode.dual]).
  final bool dualWriteInvoked;
}

/// Signature for the legacy statistics sink invoked in dual-write mode.
///
/// The adapter passes the [PracticeGamificationSignal] verbatim — the
/// ledger entry is NOT exposed, so a legacy sink that wants to write XP
/// cannot fabricate an entry from this surface. That is the A7 defense:
/// the dual-write path passes only session-level data, never the ledger
/// entry, so the legacy sink cannot double-write XP.
typedef PracticeLegacySink =
    Future<void> Function(PracticeGamificationSignal signal);

/// Snapshot builder the adapter calls to read today's ledger-derived policy
/// inputs. Keeps the adapter decoupled from any concrete repository.
typedef PracticeHistoryBuilder =
    PracticeRewardHistorySnapshot Function(int epochDay, String lessonId);

/// Pure adapter: maps one finished practice session into the canonical
/// gamification chain
/// `event → eligibility → policy → ledger entry → outbox`.
///
/// Lives at the `practice/application` layer (ADR 0390 1. döntés: no new
/// domain type; the existing [PracticeActivityEvent] is used). Imports the
/// gamification feature ONLY through its [public.dart] barrel, per the
/// public-only boundary (A4).
class GamificationPracticeAdapter {
  const GamificationPracticeAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required PracticeHistoryBuilder historyBuilder,
    required GamificationDualWriteMode dualWriteMode,
    required PracticeLegacySink legacySink,
  }) : _ingestor = ingestor,
       _eligibility = eligibility,
       _rewardPolicy = rewardPolicy,
       _historyBuilder = historyBuilder,
       _dualWriteMode = dualWriteMode,
       _legacySink = legacySink;

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final PracticeHistoryBuilder _historyBuilder;
  final GamificationDualWriteMode _dualWriteMode;
  final PracticeLegacySink _legacySink;

  /// Adapter version stamped on the produced [RewardLedgerEntry]. Bumped only
  /// when the wiring logic itself changes.
  static const int adapterPolicyVersion = 1;

  /// Schema-version constant carried by every emitted event.
  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Stable event id derived from the session id (ADR 0390 §4). The format
  /// is opaque and versioned; the suffix (`/v1`) lets a future migration
  /// introduce a v2 without colliding with v1 ids.
  static String stableEventId(String sessionId) =>
      'practice-session/$sessionId/v1';

  /// Apply [signal] to the chain. Returns the resulting outcome; the caller
  /// observes the [PracticeGamificationOutcome.accepted] flag to know whether
  /// the outbox saw an event.
  Future<PracticeGamificationOutcome> recordSession(
    PracticeGamificationSignal signal,
  ) async {
    if (_dualWriteMode == GamificationDualWriteMode.off) {
      // Migration is OFF: behavior must be byte-identical to the pre-integration
      // state (brief §6.1 "alatt" cell).
      return const PracticeGamificationOutcome.noOp();
    }

    final decision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.practice,
        outcome: signal.outcome,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!decision.baseXp.isGranted) {
      // Cancelled / failed / too-short: the existing R05 gate denies. No
      // event, no XP, no ledger entry, no legacy sink.
      return const PracticeGamificationOutcome.noOp();
    }

    final eventId = stableEventId(signal.sessionId);
    final event = PracticeActivityEvent(
      eventId: eventId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.practice,
      trust: signal.evidenceTrust,
      schemaVersion: _schemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );

    final history = _historyBuilder(signal.epochDay, signal.lessonId);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: signal.lessonId,
      parentEventId: null,
      epochDay: signal.epochDay,
      source: ActivitySource.practice,
      eligibility: decision,
      validDuration: signal.validDuration,
      qualityScore: signal.quality ?? 0.0,
      improvementDelta: 0,
      uniqueSourcesToday: history.uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: signal.epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.practiceOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final decision2 = _rewardPolicy.decide(policyRequest, policyHistory);
    final points = decision2.points;

    final entry = _buildLedgerEntry(
      sessionId: signal.sessionId,
      eventId: eventId,
      occurredAt: signal.occurredAt,
      points: points,
      policyVersion: decision2.policyVersion,
    );

    await _ingestor.recordSavedActivity(event: event, entry: entry);

    final invokedLegacy = _dualWriteMode == GamificationDualWriteMode.dual;
    if (invokedLegacy) {
      // Legacy sink receives session-level data only — it cannot fabricate
      // a RewardLedgerEntry from this surface, so it cannot double-write XP
      // through the ledger (A7 defense).
      await _legacySink(signal);
    }

    return PracticeGamificationOutcome.rewarded(
      eventId: eventId,
      dualWriteInvoked: invokedLegacy,
    );
  }

  RewardLedgerEntry _buildLedgerEntry({
    required String sessionId,
    required String eventId,
    required DateTime occurredAt,
    required ExperiencePoints points,
    required int policyVersion,
  }) {
    final baseXp = points.baseXp;
    final bonusXp =
        points.durationXp +
        points.qualityXp +
        points.improvementXp +
        points.diversityXp;
    final totalXp = points.totalXp;
    return RewardLedgerEntry(
      ledgerId: 'practice-$sessionId-${points.totalXp}',
      sourceEventId: eventId,
      createdAt: occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasonCodes: <RewardReason>[
        if (totalXp > 0) RewardReason.baseExperience,
        ...points.reductionReasons,
      ],
    );
  }
}
