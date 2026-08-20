import 'dart:math' as math;

import '../application/reward_policy_engine.dart';
import '../domain/rewards/experience_points.dart';
import '../domain/rewards/reward_reason.dart';

/// Versioned, single-source configuration for the [DefaultRewardPolicy].
///
/// Every tunable — component weights, decay curve, daily cap — lives here.
/// Method-level constants are forbidden (ADR 0341 §4): the Kör-29 simulator
/// varies these values, so anything baked into a method body cannot be
/// measured.
final class RewardPolicyConfig {
  factory RewardPolicyConfig({
    required int policyVersion,
    required int baseReward,
    required int durationRewardPerMinuteCap,
    required int qualityRewardCap,
    required int improvementRewardCap,
    required int diversityRewardCap,
    required int dailyXpCap,
    required double practiceRepeatBaseFactor,
    required double practiceRepeatMinFactor,
  }) {
    if (policyVersion < 1) {
      throw ArgumentError.value(policyVersion, 'policyVersion', 'must be >= 1');
    }
    for (final entry in <String, int>{
      'baseReward': baseReward,
      'durationRewardPerMinuteCap': durationRewardPerMinuteCap,
      'qualityRewardCap': qualityRewardCap,
      'improvementRewardCap': improvementRewardCap,
      'diversityRewardCap': diversityRewardCap,
      'dailyXpCap': dailyXpCap,
    }.entries) {
      if (entry.value < 0) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'must not be negative',
        );
      }
    }
    if (!practiceRepeatBaseFactor.isFinite ||
        practiceRepeatBaseFactor <= 0 ||
        practiceRepeatBaseFactor > 1) {
      throw ArgumentError.value(
        practiceRepeatBaseFactor,
        'practiceRepeatBaseFactor',
        'must be finite and in (0, 1]',
      );
    }
    if (!practiceRepeatMinFactor.isFinite ||
        practiceRepeatMinFactor < 0 ||
        practiceRepeatMinFactor > 1) {
      throw ArgumentError.value(
        practiceRepeatMinFactor,
        'practiceRepeatMinFactor',
        'must be finite and in [0, 1]',
      );
    }
    if (practiceRepeatMinFactor > practiceRepeatBaseFactor) {
      throw ArgumentError.value(
        practiceRepeatMinFactor,
        'practiceRepeatMinFactor',
        'must be <= practiceRepeatBaseFactor',
      );
    }
    return RewardPolicyConfig._(
      policyVersion: policyVersion,
      baseReward: baseReward,
      durationRewardPerMinuteCap: durationRewardPerMinuteCap,
      qualityRewardCap: qualityRewardCap,
      improvementRewardCap: improvementRewardCap,
      diversityRewardCap: diversityRewardCap,
      dailyXpCap: dailyXpCap,
      practiceRepeatBaseFactor: practiceRepeatBaseFactor,
      practiceRepeatMinFactor: practiceRepeatMinFactor,
    );
  }

  /// Reasonable starting balance. Kör-29 will tune these.
  factory RewardPolicyConfig.standard() => RewardPolicyConfig(
    policyVersion: 1,
    baseReward: 5,
    durationRewardPerMinuteCap: 3,
    qualityRewardCap: 4,
    improvementRewardCap: 6,
    diversityRewardCap: 3,
    dailyXpCap: 100,
    practiceRepeatBaseFactor: 0.8,
    practiceRepeatMinFactor: 0.2,
  );

  const RewardPolicyConfig._({
    required this.policyVersion,
    required this.baseReward,
    required this.durationRewardPerMinuteCap,
    required this.qualityRewardCap,
    required this.improvementRewardCap,
    required this.diversityRewardCap,
    required this.dailyXpCap,
    required this.practiceRepeatBaseFactor,
    required this.practiceRepeatMinFactor,
  });

  /// The policy version stamped on every produced [RewardPolicyDecision]
  /// — must travel to the ledger so historical balances stay interpretable
  /// (ADR 0341 §5).
  final int policyVersion;

  /// XP granted unconditionally when the `baseXp` eligibility gate is open.
  final int baseReward;

  /// Upper bound on the duration component. The duration component scales
  /// with the elapsed practice time clamped at this cap.
  final int durationRewardPerMinuteCap;

  /// Upper bound on the quality component. The component scales with the
  /// measured [RewardPolicyRequest.qualityScore] capped at this value.
  final int qualityRewardCap;

  /// Upper bound on the improvement component. Scales with a non-negative
  /// improvement delta capped at this value.
  final int improvementRewardCap;

  /// Upper bound on the diversity component. Scales with the count of
  /// distinct activity sources seen today.
  final int diversityRewardCap;

  /// Total XP a single user may earn in one epoch day from any source.
  final int dailyXpCap;

  /// Base multiplier applied to each subsequent occurrence of the same
  /// practiceKey. The Nth (1-indexed) occurrence multiplies earned XP by
  /// `practiceRepeatBaseFactor ^ (N - 1)`, never lower than the floor.
  final double practiceRepeatBaseFactor;

  /// Floor on the diminishing-returns multiplier — the XP a very
  /// repeated practice still leaves on the table. Independent of
  /// [practiceRepeatBaseFactor]; must be <= it.
  final double practiceRepeatMinFactor;
}

/// Default policy implementation: component rules → diminishing returns →
/// parent/child dedup → daily cap, with each layer's reason preserved on
/// the receipt (ADR 0341 §3).
final class DefaultRewardPolicy implements RewardPolicy {
  DefaultRewardPolicy({required this.config});

  final RewardPolicyConfig config;

  @override
  RewardPolicyDecision decide(
    RewardPolicyRequest request,
    RewardPolicyHistory history,
  ) {
    if (history.epochDay != request.epochDay) {
      throw ArgumentError(
        'history.epochDay (${history.epochDay}) must match '
        'request.epochDay (${request.epochDay})',
      );
    }

    final points = _dedup(
      _applyRepeatDecay(_applyComponentRules(request), history),
      request,
      history,
    );

    return RewardPolicyDecision(
      policyVersion: config.policyVersion,
      points: _applyDailyCap(points, history),
    );
  }

  // --- layer 1: component rules ------------------------------------------

  ExperiencePoints _applyComponentRules(RewardPolicyRequest request) {
    final baseXp = request.eligibility.baseXp.isGranted ? config.baseReward : 0;
    final durationXp = request.eligibility.baseXp.isGranted
        ? _durationComponent(request.validDuration)
        : 0;
    final qualityXp = request.eligibility.qualityBonus.isGranted
        ? _qualityComponent(request.qualityScore)
        : 0;
    final improvementXp = request.eligibility.mastery.isGranted
        ? _improvementComponent(request.improvementDelta)
        : 0;
    final diversityXp = request.eligibility.verified.isGranted
        ? _diversityComponent(request.uniqueSourcesToday)
        : 0;

    return ExperiencePoints(
      baseXp: baseXp,
      durationXp: durationXp,
      qualityXp: qualityXp,
      improvementXp: improvementXp,
      diversityXp: diversityXp,
    );
  }

  int _durationComponent(Duration validDuration) {
    if (validDuration <= Duration.zero) return 0;
    final minutes =
        validDuration.inMicroseconds / Duration.microsecondsPerMinute;
    // Cap the eligible minutes at durationRewardPerMinuteCap/XP-per-minute.
    final capped = math
        .min<double>(minutes, config.durationRewardPerMinuteCap.toDouble())
        .floor();
    return capped;
  }

  int _qualityComponent(double qualityScore) {
    if (qualityScore <= 0) return 0;
    final raw = config.qualityRewardCap * qualityScore;
    return raw.round().clamp(0, config.qualityRewardCap);
  }

  int _improvementComponent(double improvementDelta) {
    if (improvementDelta <= 0) return 0;
    final raw =
        config.improvementRewardCap *
        (improvementDelta / (improvementDelta + 1));
    return raw.round().clamp(0, config.improvementRewardCap);
  }

  int _diversityComponent(int uniqueSourcesToday) {
    if (uniqueSourcesToday <= 0) return 0;
    final step = math.min<int>(
      uniqueSourcesToday - 1,
      config.diversityRewardCap,
    );
    return step;
  }

  // --- layer 2: diminishing returns on the same practice ----------------

  ExperiencePoints _applyRepeatDecay(
    ExperiencePoints preDecay,
    RewardPolicyHistory history,
  ) {
    final occurrence = history.practiceOccurrenceCount;
    if (occurrence <= 0) return preDecay;

    final double rawFactor = math
        .pow(config.practiceRepeatBaseFactor, occurrence)
        .toDouble();
    final factor = rawFactor < config.practiceRepeatMinFactor
        ? config.practiceRepeatMinFactor
        : rawFactor;

    return ExperiencePoints(
      baseXp: _scaled(preDecay.baseXp, factor),
      durationXp: _scaled(preDecay.durationXp, factor),
      qualityXp: _scaled(preDecay.qualityXp, factor),
      improvementXp: _scaled(preDecay.improvementXp, factor),
      diversityXp: _scaled(preDecay.diversityXp, factor),
      reductionReasons: <RewardReason>[
        ...preDecay.reductionReasons,
        RewardReason.repeatLimited,
      ],
    );
  }

  int _scaled(int amount, double factor) {
    if (amount <= 0) return 0;
    final raw = amount * factor;
    return raw.floor().clamp(0, amount);
  }

  // --- layer 3: parent/child dedup ---------------------------------------

  ExperiencePoints _dedup(
    ExperiencePoints preDedup,
    RewardPolicyRequest request,
    RewardPolicyHistory history,
  ) {
    // A re-submission of an event id that has already been rewarded in any
    // role is structurally suppressed. The reward has already left the
    // building on a previous pass — re-running the policy can't unpay it.
    final alreadyRewarded = history.rewardedEventIds.contains(request.eventId);
    if (alreadyRewarded) {
      return ExperiencePoints(reductionReasons: preDedup.reductionReasons);
    }

    if (request.parentEventId != null) {
      // This event is a CHILD. The parent already claimed the XP earlier
      // today: the child claim collapses to zero without that day's cap
      // being affected.
      final parentClaimed = history.rewardedParentIds.contains(
        request.parentEventId!,
      );
      if (parentClaimed) {
        return ExperiencePoints(reductionReasons: preDedup.reductionReasons);
      }
      return preDedup;
    }

    // This event has no parent link — a parent or standalone event. If a
    // child already arrived for this id today the parent collapses
    // symmetrically, matching the child branch.
    if (history.rewardedChildParentIds.contains(request.eventId)) {
      return ExperiencePoints(reductionReasons: preDedup.reductionReasons);
    }
    return preDedup;
  }

  // --- layer 4: daily cap with reason -----------------------------------

  ExperiencePoints _applyDailyCap(
    ExperiencePoints points,
    RewardPolicyHistory history,
  ) {
    final preCap = points.totalXp;
    final remaining = config.dailyXpCap - history.earnedTodayXp;
    if (remaining <= 0) {
      // Already at or over the cap before this event applies. A receipt is
      // still produced with zero credit and the cap reason.
      return ExperiencePoints(
        reductionReasons: <RewardReason>[
          ...points.reductionReasons,
          RewardReason.dailyCapApplied,
        ],
      );
    }
    if (remaining >= preCap) {
      // Full XP fits in the remaining envelope — no cap reason.
      return points;
    }
    // Some of the pre-cap XP fits, the rest is clipped. Preserve the
    // pre-cap breakdown so the interface can show "you would have earned N
    // but the cap left you with M". The per-component earned values are
    // scaled uniformly so the ratio matches.
    final fraction = remaining / preCap;
    final clipped = ExperiencePoints(
      baseXp: _scaled(points.baseXp, fraction),
      durationXp: _scaled(points.durationXp, fraction),
      qualityXp: _scaled(points.qualityXp, fraction),
      improvementXp: _scaled(points.improvementXp, fraction),
      diversityXp: _scaled(points.diversityXp, fraction),
      reductionReasons: <RewardReason>[
        ...points.reductionReasons,
        RewardReason.dailyCapApplied,
      ],
    );
    return clipped;
  }
}
