// E08-R26 — Vision → gamification reward adapter.
//
// Maps a caller-supplied vision session onto the canonical gamification
// chain `event → eligibility → policy → ledger entry → outbox`, mirroring
// the practice / lesson / song adapter shape so every cross-feature
// bridge stays uniform.
//
// Two design choices are dictated by brief §0.0/3 and §5.2 (ADR 0392):
//
// 1. The technical-progress reward is gated by the *existing*
//    `VisionClaimGuard` (`lib/features/vision/domain/integration/
//    vision_claim_guard.dart`, `_minimumConfidence = 0.70`). The
//    adapter imports `vision/domain/integration/public.dart` — the
//    narrower, cross-feature consumer barrel — for the guard, and
//    `vision/public.dart` (top-level) for `InsightCode` and
//    `VisionEvidence` since the §0.0/6 architecture guard accepts
//    BOTH barrels as vision boundaries (the inner barrel does not
//    re-export the claim/evidence types, so the top-level barrel is
//    needed for the inputs the guard requires).
//
// 2. The session produces TWO events, distinct ids:
//    * `vision-base` — emitted whenever the R05 eligibility gate
//      grants the base XP. This is the effort reward (§5.2: "az
//      alap-XP az erőfeszítésért továbbra is jár") and is independent
//      of the VisionClaimGuard verdict.
//    * `vision-technical` — emitted ONLY when `VisionClaimGuard` says
//      the underlying claim is observable (`isAllowed == true`).
//      This is the §5.2 technical-progress reward; the §6.1 threshold
//      triple (alatt / rajta / fölött) maps onto the guard's
//      `confidence < minimumConfidence` (strict-less-than) predicate:
//      the threshold itself is the inclusive accepting boundary.
//
// The §6.1 `rajta` cell (confidence exactly `0.70`) IS allowed by the
// guard — the adapter asserts that as the "rajta" cell of the
// threshold triple.
//
// All other fields follow the same contract as the song / practice /
// lesson adapters: imports the gamification feature ONLY through its
// `public.dart` barrel, never inspects the vision feature's internals
// beyond the two public barrels, and never introduces a new network
// or platform call (A8).

import 'package:meta/meta.dart';

import '../../gamification/public.dart';
import '../domain/integration/public.dart';
import '../public.dart';

/// Inputs the vision adapter needs about one finished vision session.
/// Pure values only — no Riverpod snapshots, no clocks, no
/// repositories.
///
/// The adapter derives the two public event ids deterministically
/// from [sessionId] (ADR 0390 §4) so a result-screen reopen produces
/// the same ids and the ledger's append-if-absent absorbs the
/// duplicate write.
@immutable
final class VisionGamificationSignal {
  const VisionGamificationSignal({
    required this.sessionId,
    required this.claim,
    required this.evidence,
    required this.confidence,
    required this.validDuration,
    required this.quality,
    required this.evidenceTrust,
    required this.score,
    required this.epochDay,
    required this.occurredAt,
  });

  /// Persisted, save-time identifier of the vision session.
  final String sessionId;

  /// The insight claim the caller (a vision consumer) wants to land.
  /// The guard inspects it against its internal catalog and chooses
  /// between `_minimumConfidence` and `_minimumNegativeConfidence`
  /// accordingly — a concern the adapter does not need to duplicate.
  final InsightCode claim;

  /// The vision evidence the caller attaches to the claim. `null`
  /// triggers the `notObservable` rejection branch — the §6.1
  /// "missing evidence" failure mode the adapter MUST treat as a
  /// guard denial (A2 / A7).
  final VisionEvidence? evidence;

  /// Confidence the caller assigns to the claim, in `[0, 1]`. The
  /// guard checks this against its per-claim threshold.
  final double confidence;

  /// Validated, non-negative duration the caller counted toward the
  /// vision session.
  final Duration validDuration;

  /// Optional quality observation in `[0, 1]`. `null` is permitted; the
  /// eligibility layer treats a missing quality as
  /// `fatalSignalQuality`.
  final double? quality;

  /// The evidence-trust grade the caller attached to the session.
  final EvidenceTrust evidenceTrust;

  /// Canonical score field of the [VisionActivityEvent] in `[0, 1]`.
  final double score;

  /// Epoch day the session belongs to.
  final int epochDay;

  /// Wall-clock instant the session ended; stamped on the
  /// [RewardLedgerEntry.createdAt].
  final DateTime occurredAt;
}

/// Snapshot the policy engine needs from the surrounding ledger state.
@immutable
final class VisionRewardHistorySnapshot {
  const VisionRewardHistorySnapshot({
    required this.earnedTodayXp,
    required this.visionOccurrenceCount,
    required this.uniqueSourcesToday,
    required this.rewardedEventIds,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  });

  final int earnedTodayXp;
  final int visionOccurrenceCount;
  final int uniqueSourcesToday;
  final Set<String> rewardedEventIds;
  final Set<String> rewardedParentIds;
  final Set<String> rewardedChildParentIds;
}

typedef VisionHistoryBuilder =
    VisionRewardHistorySnapshot Function(int epochDay, String practiceKey);

/// Outcome of one adapter invocation. The two-event design is
/// observable: the adapter reports which events fired so the caller
/// can tell a base-only session from a session that also unlocked
/// technical progress.
@immutable
final class VisionGamificationOutcome {
  const VisionGamificationOutcome.noOp()
    : baseEventId = null,
      technicalEventId = null,
      accepted = false;

  /// The adapter ran the chain and produced one or both events. Both
  /// ids are listed in emission order.
  const VisionGamificationOutcome.rewarded({
    required this.baseEventId,
    this.technicalEventId,
  }) : accepted = true;

  /// The base-effort event id (always present when [accepted] is
  /// true). `null` only when [accepted] is `false`.
  final String? baseEventId;

  /// The technical-progress event id. `null` when the
  /// [VisionClaimGuard] denied the claim (the §6.1 "alatt" cell) or
  /// when the caller did not provide evidence.
  final String? technicalEventId;

  /// True when the adapter enqueued at least the base event.
  final bool accepted;
}

/// Pure adapter. Maps one finished vision session into the canonical
/// gamification chain.
class GamificationVisionAdapter {
  const GamificationVisionAdapter({
    required ActivityEventIngestor ingestor,
    required RewardEligibilityPolicy eligibility,
    required RewardPolicy rewardPolicy,
    required VisionHistoryBuilder historyBuilder,
    required bool featureEnabled,
  }) : _ingestor = ingestor, // ignore: prefer_initializing_formals
       _eligibility = eligibility, // ignore: prefer_initializing_formals
       _rewardPolicy = rewardPolicy, // ignore: prefer_initializing_formals
       _historyBuilder = historyBuilder, // ignore: prefer_initializing_formals
       _featureEnabled = featureEnabled; // ignore: prefer_initializing_formals

  final ActivityEventIngestor _ingestor;
  final RewardEligibilityPolicy _eligibility;
  final RewardPolicy _rewardPolicy;
  final VisionHistoryBuilder _historyBuilder;
  final bool _featureEnabled;

  /// Adapter version stamped on the produced [RewardLedgerEntry].
  static const int adapterPolicyVersion = 1;

  /// Schema-version constant carried by every emitted event.
  static const int _schemaVersion = learningActivityEventSchemaVersion;

  /// Stable event id for the base-effort event. Format is opaque and
  /// versioned; the suffix (`/v1`) lets a future migration introduce
  /// a v2 without colliding with v1 ids.
  static String baseEventId(String sessionId) => 'vision-base/$sessionId/v1';

  /// Stable event id for the technical-progress event. Distinct from
  /// [baseEventId] so a guard-denial session never collides with a
  /// guard-allowing one (A2 — the §6.1 "alatt" cell must NOT receive
  /// the technical-progress reward).
  static String technicalEventId(String sessionId) =>
      'vision-technical/$sessionId/v1';

  /// Apply [signal] to the chain. The adapter first asks the R05
  /// eligibility gate for base XP (always), then asks
  /// [VisionClaimGuard] whether the technical-progress event should
  /// also fire.
  Future<VisionGamificationOutcome> recordSession(
    VisionGamificationSignal signal,
  ) async {
    // A7 — feature-switch fallback.
    if (!_featureEnabled) {
      return const VisionGamificationOutcome.noOp();
    }

    final decision = _eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.vision,
        outcome: ActivityOutcome.completed,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );

    if (!decision.baseXp.isGranted) {
      // R05 denied — too short / cancelled / failed. Neither event
      // fires.
      return const VisionGamificationOutcome.noOp();
    }

    final practiceKey = signal.sessionId;

    final baseId = baseEventId(signal.sessionId);
    final baseEvent = VisionActivityEvent(
      eventId: baseId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.vision,
      trust: signal.evidenceTrust,
      schemaVersion: _schemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );
    final baseEntry = _buildEntry(
      sessionId: signal.sessionId,
      eventId: baseId,
      practiceKey: practiceKey,
      occurredAt: signal.occurredAt,
      decision: decision,
      qualityScore: signal.quality ?? 0.0,
      validDuration: signal.validDuration,
      epochDay: signal.epochDay,
      source: ActivitySource.vision,
      uniqueSourcesToday: _historyBuilder(
        signal.epochDay,
        practiceKey,
      ).uniqueSourcesToday,
      includeTechnicalBonus: false,
    );
    await _ingestor.recordSavedActivity(event: baseEvent, entry: baseEntry);

    // VisionClaimGuard — the §6.1 threshold triple.
    final guard = const VisionClaimGuard();
    final guardResult = guard.evaluate(
      claim: signal.claim,
      evidence: signal.evidence,
      confidence: signal.confidence,
    );

    String? technicalId;
    if (guardResult.isAllowed) {
      // §5.2 — technical progress fires AFTER the quality gate.
      // §6.1 "rajta" cell: when `confidence == _minimumConfidence`
      // the guard's strict-less-than predicate accepts, so this
      // branch IS the inclusive-accept boundary.
      technicalId = technicalEventId(signal.sessionId);
      final techEvent = VisionActivityEvent(
        eventId: technicalId,
        occurredAt: signal.occurredAt,
        epochDay: signal.epochDay,
        source: ActivitySource.vision,
        trust: signal.evidenceTrust,
        schemaVersion: _schemaVersion,
        duration: signal.validDuration,
        score: signal.score,
      );
      final techEntry = _buildEntry(
        sessionId: signal.sessionId,
        eventId: technicalId,
        practiceKey: practiceKey,
        occurredAt: signal.occurredAt,
        decision: decision,
        qualityScore: signal.quality ?? 0.0,
        validDuration: signal.validDuration,
        epochDay: signal.epochDay,
        source: ActivitySource.vision,
        uniqueSourcesToday: _historyBuilder(
          signal.epochDay,
          practiceKey,
        ).uniqueSourcesToday,
        includeTechnicalBonus: true,
      );
      await _ingestor.recordSavedActivity(event: techEvent, entry: techEntry);
    }

    return VisionGamificationOutcome.rewarded(
      baseEventId: baseId,
      technicalEventId: technicalId,
    );
  }

  RewardLedgerEntry _buildEntry({
    required String sessionId,
    required String eventId,
    required String practiceKey,
    required DateTime occurredAt,
    required RewardEligibilityDecision decision,
    required double qualityScore,
    required Duration validDuration,
    required int epochDay,
    required ActivitySource source,
    required int uniqueSourcesToday,
    required bool includeTechnicalBonus,
  }) {
    final history = _historyBuilder(epochDay, practiceKey);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: practiceKey,
      parentEventId: null,
      epochDay: epochDay,
      source: source,
      eligibility: decision,
      validDuration: validDuration,
      qualityScore: qualityScore,
      improvementDelta: includeTechnicalBonus ? 1 : 0,
      uniqueSourcesToday: uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.visionOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final policyDecision = _rewardPolicy.decide(policyRequest, policyHistory);
    final points = policyDecision.points;
    final baseXp = points.baseXp;
    final bonusXp =
        points.durationXp +
        points.qualityXp +
        points.improvementXp +
        points.diversityXp;
    final totalXp = points.totalXp;
    return RewardLedgerEntry(
      ledgerId: 'vision/$practiceKey/$eventId/$totalXp',
      sourceEventId: eventId,
      createdAt: occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: policyDecision.policyVersion,
      baseXp: baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasonCodes: <RewardReason>[
        if (totalXp > 0) RewardReason.baseExperience,
        if (includeTechnicalBonus && totalXp > 0) RewardReason.qualityBonus,
        ...points.reductionReasons,
      ],
    );
  }
}
