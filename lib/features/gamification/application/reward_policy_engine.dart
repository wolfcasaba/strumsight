import '../domain/activity/activity_source.dart';
import '../domain/rewards/experience_points.dart';
import 'reward_eligibility_policy.dart';

/// Inputs that the policy needs about the activity being rewarded, beyond
/// the already-decided eligibility gates.
///
/// The policy engine NEVER re-decides eligibility: it consumes the
/// [RewardEligibilityDecision] and the measured activity signals to translate
/// "this activity earned this set of gates" into a five-component
/// [ExperiencePoints] receipt. Measured signals ([validDuration],
/// [qualityScore], [improvementDelta], [uniqueSourcesToday]) do not flow
/// through the R05 eligibility contract — the policy request carries them
/// because they are XP calculation inputs, not gating inputs.
final class RewardPolicyRequest {
  RewardPolicyRequest({
    required this.eventId,
    required this.practiceKey,
    required this.parentEventId,
    required this.epochDay,
    required this.source,
    required this.eligibility,
    required this.validDuration,
    required this.qualityScore,
    required this.improvementDelta,
    required this.uniqueSourcesToday,
  }) {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(eventId, 'eventId', 'must not be blank');
    }
    if (practiceKey.trim().isEmpty) {
      throw ArgumentError.value(
        practiceKey,
        'practiceKey',
        'must not be blank',
      );
    }
    if (parentEventId != null && parentEventId!.trim().isEmpty) {
      throw ArgumentError.value(
        parentEventId,
        'parentEventId',
        'must not be blank when provided',
      );
    }
    if (validDuration.isNegative) {
      throw ArgumentError.value(
        validDuration,
        'validDuration',
        'must not be negative',
      );
    }
    if (!qualityScore.isFinite || qualityScore < 0 || qualityScore > 1) {
      throw ArgumentError.value(
        qualityScore,
        'qualityScore',
        'must be finite and in the range [0, 1]',
      );
    }
    if (!improvementDelta.isFinite) {
      throw ArgumentError.value(
        improvementDelta,
        'improvementDelta',
        'must be finite',
      );
    }
    if (uniqueSourcesToday < 0) {
      throw ArgumentError.value(
        uniqueSourcesToday,
        'uniqueSourcesToday',
        'must not be negative',
      );
    }
  }

  /// Stable identifier of the canonical activity event being rewarded.
  final String eventId;

  /// Practice identifier used by the diminishing-returns layer. Distinct
  /// events of the same practice on the same day share this key.
  final String practiceKey;

  /// Optional explicit parent-event link. When non-null, the policy uses it
  /// to enforce the single-reward invariant (ADR 0341 §3) instead of any
  /// time-proximity heuristic.
  final String? parentEventId;

  /// The epoch day the activity belongs to — used by the daily cap layer.
  final int epochDay;

  /// The originating feature boundary — forwarded for the diversity layer.
  final ActivitySource source;

  /// The R05 eligibility result. The policy never re-decides any gate; it
  /// only consumes the decision shape and the measured signals.
  final RewardEligibilityDecision eligibility;

  /// Validated duration the eligibility layer counted toward the
  /// `validDuration` requirement.
  final Duration validDuration;

  /// Quality observation in `[0, 1]`. The eligibility layer treats
  /// measurements at the fatal threshold as missing.
  final double qualityScore;

  /// Improvement delta — signed improvement (positive) vs. previous session.
  final double improvementDelta;

  /// How many distinct activity sources (including the current one when
  /// first seen) have produced a rewarded activity today. Drives the
  /// diversity bonus.
  final int uniqueSourcesToday;
}

/// A snapshot of the state the policy must reason against. The caller
/// (the future R03/R07 ledger bridge) is responsible for keeping this
/// snapshot accurate — the engine never mutates it.
final class RewardPolicyHistory {
  RewardPolicyHistory({
    required this.epochDay,
    required this.earnedTodayXp,
    required this.practiceOccurrenceCount,
    required this.rewardedParentIds,
    required this.rewardedChildParentIds,
  }) {
    if (earnedTodayXp < 0) {
      throw ArgumentError.value(
        earnedTodayXp,
        'earnedTodayXp',
        'must not be negative',
      );
    }
    if (practiceOccurrenceCount < 0) {
      throw ArgumentError.value(
        practiceOccurrenceCount,
        'practiceOccurrenceCount',
        'must not be negative',
      );
    }
  }

  /// The epoch day the snapshot was taken on. The history only applies to
  /// that day; cross-day snapshots are the caller's responsibility.
  final int epochDay;

  /// Sum of XP already awarded on [epochDay]. Used by the daily cap layer
  /// to compute `max(cap - earnedTodayXp, 0)`.
  final int earnedTodayXp;

  /// How many times the requested [RewardPolicyRequest.practiceKey] has
  /// already been rewarded on [epochDay] — BEFORE the current request.
  /// The decay layer treats the current event as
  /// `practiceOccurrenceCount`-th on the day (zero-indexed).
  final int practiceOccurrenceCount;

  /// The parent event ids rewarded in their parent role on [epochDay]. When
  /// the requested event has a [RewardPolicyRequest.parentEventId] that is
  /// present here, the parent has already claimed the credit and the current
  /// child collapses to zero.
  final Set<String> rewardedParentIds;

  /// The parent event ids whose CHILDREN have already been rewarded on
  /// [epochDay]. The decision suppresses a parent whose id appears here —
  /// the credit was already paid out via the child event.
  final Set<String> rewardedChildParentIds;

  /// Distinct set of already-rewarded event ids on [epochDay] — used so a
  /// re-submission of the same event id cannot double-claim.
  Set<String> get rewardedEventIds => <String>{
    ...rewardedParentIds,
    ...rewardedChildParentIds,
  };
}

/// Immutable output of a single policy evaluation. The receipt is total +
/// per-component XP plus the policy version that produced it; a downstream
/// ledger bridge can persist the same values into the R03 schema (future round).
final class RewardPolicyDecision {
  RewardPolicyDecision({required this.policyVersion, required this.points})
    : assert(policyVersion >= 1, 'policyVersion must be >= 1');

  final int policyVersion;
  final ExperiencePoints points;

  @override
  bool operator ==(Object other) =>
      other is RewardPolicyDecision &&
      policyVersion == other.policyVersion &&
      points == other.points;

  @override
  int get hashCode => Object.hash(policyVersion, points);
}

/// Deterministic, side-effect-free mapping of a request + history snapshot
/// into a [RewardPolicyDecision]. Versioned by configuration so balance
/// changes are auditable against the receipt (ADR 0341 §5).
abstract interface class RewardPolicy {
  RewardPolicyDecision decide(
    RewardPolicyRequest request,
    RewardPolicyHistory history,
  );
}
