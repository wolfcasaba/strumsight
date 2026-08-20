import '../domain/activity/activity_source.dart';
import '../domain/activity/evidence_trust.dart';
import '../domain/rewards/reward_reason.dart';

/// The terminal state of a learning activity before reward evaluation.
enum ActivityOutcome { completed, cancelled, failed }

/// Immutable inputs needed to determine a learning activity's reward gates.
final class RewardEligibilityRequest {
  factory RewardEligibilityRequest({
    required ActivitySource source,
    required ActivityOutcome outcome,
    required EvidenceTrust trust,
    required Duration validDuration,
    required double? quality,
  }) {
    if (validDuration.isNegative) {
      throw ArgumentError.value(
        validDuration,
        'validDuration',
        'must not be negative',
      );
    }
    if (quality != null && (!quality.isFinite || quality < 0 || quality > 1)) {
      throw ArgumentError.value(
        quality,
        'quality',
        'must be finite and in the range [0, 1]',
      );
    }
    return RewardEligibilityRequest._(
      source: source,
      outcome: outcome,
      trust: trust,
      validDuration: validDuration,
      quality: quality,
    );
  }

  const RewardEligibilityRequest._({
    required this.source,
    required this.outcome,
    required this.trust,
    required this.validDuration,
    required this.quality,
  });

  final ActivitySource source;
  final ActivityOutcome outcome;
  final EvidenceTrust trust;
  final Duration validDuration;
  final double? quality;
}

/// The granted or denied state of one reward gate.
final class RewardGateDecision {
  factory RewardGateDecision.granted() =>
      const RewardGateDecision._(isGranted: true);

  factory RewardGateDecision.denied(RewardReason reason) =>
      RewardGateDecision._(isGranted: false, reason: reason);

  const RewardGateDecision._({required this.isGranted, this.reason})
    : assert(isGranted == (reason == null));

  final bool isGranted;
  final RewardReason? reason;

  @override
  bool operator ==(Object other) =>
      other is RewardGateDecision &&
      isGranted == other.isGranted &&
      reason == other.reason;

  @override
  int get hashCode => Object.hash(isGranted, reason);
}

/// The independent gates decided by a versioned reward-eligibility policy.
final class RewardEligibilityDecision {
  factory RewardEligibilityDecision({
    required int policyVersion,
    required RewardGateDecision baseXp,
    required RewardGateDecision qualityBonus,
    required RewardGateDecision mastery,
    required RewardGateDecision verified,
  }) => RewardEligibilityDecision._(
    policyVersion: policyVersion,
    baseXp: baseXp,
    qualityBonus: qualityBonus,
    mastery: mastery,
    verified: verified,
  );

  const RewardEligibilityDecision._({
    required this.policyVersion,
    required this.baseXp,
    required this.qualityBonus,
    required this.mastery,
    required this.verified,
  });

  final int policyVersion;
  final RewardGateDecision baseXp;
  final RewardGateDecision qualityBonus;
  final RewardGateDecision mastery;
  final RewardGateDecision verified;

  @override
  bool operator ==(Object other) =>
      other is RewardEligibilityDecision &&
      policyVersion == other.policyVersion &&
      baseXp == other.baseXp &&
      qualityBonus == other.qualityBonus &&
      mastery == other.mastery &&
      verified == other.verified;

  @override
  int get hashCode =>
      Object.hash(policyVersion, baseXp, qualityBonus, mastery, verified);
}

/// Deterministically decides which reward components an activity may receive.
abstract interface class RewardEligibilityPolicy {
  RewardEligibilityDecision evaluate(RewardEligibilityRequest request);
}
