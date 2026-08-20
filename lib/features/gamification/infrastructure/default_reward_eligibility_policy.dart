import '../application/reward_eligibility_policy.dart';
import '../domain/activity/activity_source.dart';
import '../domain/activity/evidence_trust.dart';
import '../domain/rewards/reward_reason.dart';

/// Versioned, source-specific inputs for [DefaultRewardEligibilityPolicy].
final class RewardEligibilityPolicyConfig {
  factory RewardEligibilityPolicyConfig({
    required int policyVersion,
    required Map<ActivitySource, Duration> minValidDurationBySource,
    required Map<ActivitySource, EvidenceTrust> masteryTrustThresholdBySource,
    double fatalSignalQualityThreshold = 0.0,
  }) {
    if (policyVersion < 1) {
      throw ArgumentError.value(policyVersion, 'policyVersion', 'must be >= 1');
    }
    _validateCompleteSourceMap(
      minValidDurationBySource,
      'minValidDurationBySource',
    );
    _validateCompleteSourceMap(
      masteryTrustThresholdBySource,
      'masteryTrustThresholdBySource',
    );
    for (final duration in minValidDurationBySource.values) {
      if (duration.isNegative) {
        throw ArgumentError.value(
          duration,
          'minValidDurationBySource',
          'must not contain negative durations',
        );
      }
    }
    if (!fatalSignalQualityThreshold.isFinite ||
        fatalSignalQualityThreshold < 0 ||
        fatalSignalQualityThreshold > 1) {
      throw ArgumentError.value(
        fatalSignalQualityThreshold,
        'fatalSignalQualityThreshold',
        'must be finite and in the range [0, 1]',
      );
    }
    return RewardEligibilityPolicyConfig._(
      policyVersion: policyVersion,
      minValidDurationBySource: Map.unmodifiable(minValidDurationBySource),
      masteryTrustThresholdBySource: Map.unmodifiable(
        masteryTrustThresholdBySource,
      ),
      fatalSignalQualityThreshold: fatalSignalQualityThreshold,
    );
  }

  factory RewardEligibilityPolicyConfig.standard() =>
      RewardEligibilityPolicyConfig(
        policyVersion: 1,
        minValidDurationBySource: <ActivitySource, Duration>{
          for (final source in ActivitySource.values)
            source: const Duration(minutes: 1),
        },
        masteryTrustThresholdBySource: <ActivitySource, EvidenceTrust>{
          for (final source in ActivitySource.values)
            source: EvidenceTrust.scored,
        },
      );

  const RewardEligibilityPolicyConfig._({
    required this.policyVersion,
    required this.minValidDurationBySource,
    required this.masteryTrustThresholdBySource,
    required this.fatalSignalQualityThreshold,
  });

  final int policyVersion;
  final Map<ActivitySource, Duration> minValidDurationBySource;
  final Map<ActivitySource, EvidenceTrust> masteryTrustThresholdBySource;
  final double fatalSignalQualityThreshold;

  static void _validateCompleteSourceMap<T>(
    Map<ActivitySource, T> values,
    String parameterName,
  ) {
    if (ActivitySource.values.any((source) => !values.containsKey(source))) {
      throw ArgumentError.value(
        values,
        parameterName,
        'must contain every ActivitySource',
      );
    }
  }
}

/// The standard deterministic implementation of the four reward gates.
final class DefaultRewardEligibilityPolicy implements RewardEligibilityPolicy {
  DefaultRewardEligibilityPolicy({required this.config});

  final RewardEligibilityPolicyConfig config;

  @override
  RewardEligibilityDecision evaluate(RewardEligibilityRequest request) {
    final baseXp = _evaluateBaseXp(request);
    final qualityBonus = _evaluateQualityBonus(request, baseXp);
    final mastery = _evaluateMastery(request, qualityBonus);
    final verified = _evaluateVerified(request, mastery);

    return RewardEligibilityDecision(
      policyVersion: config.policyVersion,
      baseXp: baseXp,
      qualityBonus: qualityBonus,
      mastery: mastery,
      verified: verified,
    );
  }

  RewardGateDecision _evaluateBaseXp(RewardEligibilityRequest request) {
    switch (request.outcome) {
      case ActivityOutcome.cancelled:
        return RewardGateDecision.denied(RewardReason.cancelled);
      case ActivityOutcome.failed:
        return RewardGateDecision.denied(RewardReason.failed);
      case ActivityOutcome.completed:
        final minimumDuration =
            config.minValidDurationBySource[request.source]!;
        if (request.validDuration < minimumDuration) {
          return RewardGateDecision.denied(RewardReason.tooShort);
        }
        return RewardGateDecision.granted();
    }
  }

  RewardGateDecision _evaluateQualityBonus(
    RewardEligibilityRequest request,
    RewardGateDecision baseXp,
  ) {
    if (!baseXp.isGranted) {
      return _cascade(baseXp);
    }
    if (!_hasUsableQuality(request.quality)) {
      return RewardGateDecision.denied(RewardReason.fatalSignalQuality);
    }
    return RewardGateDecision.granted();
  }

  RewardGateDecision _evaluateMastery(
    RewardEligibilityRequest request,
    RewardGateDecision qualityBonus,
  ) {
    if (!qualityBonus.isGranted) {
      return _cascade(qualityBonus);
    }
    final threshold = config.masteryTrustThresholdBySource[request.source]!;
    if (request.trust.index < threshold.index) {
      return RewardGateDecision.denied(RewardReason.insufficientTrust);
    }
    return RewardGateDecision.granted();
  }

  RewardGateDecision _evaluateVerified(
    RewardEligibilityRequest request,
    RewardGateDecision mastery,
  ) {
    if (!mastery.isGranted) {
      return _cascade(mastery);
    }
    if (request.trust.index < EvidenceTrust.verified.index) {
      return RewardGateDecision.denied(RewardReason.insufficientTrust);
    }
    return RewardGateDecision.granted();
  }

  bool _hasUsableQuality(double? quality) =>
      quality != null && quality > config.fatalSignalQualityThreshold;

  RewardGateDecision _cascade(RewardGateDecision deniedGate) =>
      RewardGateDecision.denied(deniedGate.reason!);
}
