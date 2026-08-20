import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('A1/A2 — four independent reward gates', () {
    test('low-trust evidence grants effort and quality, but not mastery', () {
      final decision = _policy().evaluate(
        _request(trust: EvidenceTrust.deviceObserved),
      );

      _expectGranted(decision.baseXp);
      _expectGranted(decision.qualityBonus);
      _expectDenied(decision.mastery, RewardReason.insufficientTrust);
      _expectDenied(decision.verified, RewardReason.insufficientTrust);
    });

    test('verified evidence independently grants every gate', () {
      final decision = _policy().evaluate(
        _request(trust: EvidenceTrust.verified),
      );

      _expectGranted(decision.baseXp);
      _expectGranted(decision.qualityBonus);
      _expectGranted(decision.mastery);
      _expectGranted(decision.verified);
    });
  });

  group(
    'A3/A5 — completed outcome is required and every denial is explained',
    () {
      for (final outcome in <ActivityOutcome>[
        ActivityOutcome.cancelled,
        ActivityOutcome.failed,
      ]) {
        test('$outcome denies every gate with its stable reason code', () {
          final decision = _policy().evaluate(
            _request(outcome: outcome, trust: EvidenceTrust.verified),
          );
          final expectedReason = outcome == ActivityOutcome.cancelled
              ? RewardReason.cancelled
              : RewardReason.failed;

          _expectDenied(decision.baseXp, expectedReason);
          _expectDenied(decision.qualityBonus, expectedReason);
          _expectDenied(decision.mastery, expectedReason);
          _expectDenied(decision.verified, expectedReason);
        });
      }
    },
  );

  group('A4/A5 — fatal signal quality denies quality-derived gates', () {
    test('quality exactly on the fatal threshold is denied inclusively', () {
      final decision = _policy().evaluate(_request(quality: 0.2));

      _expectGranted(decision.baseXp);
      _expectDenied(decision.qualityBonus, RewardReason.fatalSignalQuality);
      _expectDenied(decision.mastery, RewardReason.fatalSignalQuality);
      _expectDenied(decision.verified, RewardReason.fatalSignalQuality);
    });

    test(
      'a missing quality measurement is not converted to a numeric score',
      () {
        final decision = _policy().evaluate(_request(quality: null));

        _expectGranted(decision.baseXp);
        _expectDenied(decision.qualityBonus, RewardReason.fatalSignalQuality);
        _expectDenied(decision.mastery, RewardReason.fatalSignalQuality);
        _expectDenied(decision.verified, RewardReason.fatalSignalQuality);
      },
    );
  });

  group('A5 — duration boundary and denial cascades', () {
    test('below the per-source duration threshold is too short', () {
      final decision = _policy().evaluate(
        _request(validDuration: const Duration(minutes: 4, seconds: 59)),
      );

      _expectDenied(decision.baseXp, RewardReason.tooShort);
      _expectDenied(decision.qualityBonus, RewardReason.tooShort);
      _expectDenied(decision.mastery, RewardReason.tooShort);
      _expectDenied(decision.verified, RewardReason.tooShort);
    });

    test('exactly on the per-source duration threshold grants base XP', () {
      final decision = _policy().evaluate(
        _request(validDuration: const Duration(minutes: 5)),
      );

      _expectGranted(decision.baseXp);
    });

    test('above the per-source duration threshold grants base XP', () {
      final decision = _policy().evaluate(
        _request(validDuration: const Duration(minutes: 5, seconds: 1)),
      );

      _expectGranted(decision.baseXp);
    });
  });

  test('A6: repeated evaluations of the same request are deterministic', () {
    final policy = _policy();
    final request = _request(trust: EvidenceTrust.verified);
    final expected = policy.evaluate(request);

    for (var iteration = 0; iteration < 100; iteration++) {
      expect(policy.evaluate(request), expected);
    }
  });

  test('A7: every decision carries the configured policy version', () {
    final decision = _policy(policyVersion: 7).evaluate(_request());

    expect(decision.policyVersion, 7);
  });

  group('A8 — one policy configuration controls behavior', () {
    test('a changed duration threshold changes base-XP eligibility', () {
      final request = _request(
        validDuration: const Duration(minutes: 5),
        trust: EvidenceTrust.verified,
      );
      final accepted = _policy(
        minimumDuration: const Duration(minutes: 5),
      ).evaluate(request);
      final denied = _policy(
        minimumDuration: const Duration(minutes: 6),
      ).evaluate(request);

      _expectGranted(accepted.baseXp);
      _expectDenied(denied.baseXp, RewardReason.tooShort);
    });

    test('a changed trust threshold changes mastery eligibility', () {
      final request = _request(trust: EvidenceTrust.deviceObserved);
      final accepted = _policy(
        masteryThreshold: EvidenceTrust.deviceObserved,
      ).evaluate(request);
      final denied = _policy(
        masteryThreshold: EvidenceTrust.scored,
      ).evaluate(request);

      _expectGranted(accepted.mastery);
      _expectDenied(denied.mastery, RewardReason.insufficientTrust);
    });
  });

  group('validated policy inputs', () {
    test('request rejects invalid duration and quality values', () {
      expect(
        () => _request(validDuration: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      for (final quality in <double>[double.nan, -0.001, 1.001]) {
        expect(() => _request(quality: quality), throwsArgumentError);
      }
    });

    test('configuration rejects incomplete maps and invalid values', () {
      expect(
        () => RewardEligibilityPolicyConfig(
          policyVersion: 0,
          minValidDurationBySource: _durationThresholds(),
          masteryTrustThresholdBySource: _trustThresholds(),
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardEligibilityPolicyConfig(
          policyVersion: 1,
          minValidDurationBySource: _durationThresholds()
            ..remove(ActivitySource.practice),
          masteryTrustThresholdBySource: _trustThresholds(),
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardEligibilityPolicyConfig(
          policyVersion: 1,
          minValidDurationBySource: _durationThresholds(),
          masteryTrustThresholdBySource: _trustThresholds(),
          fatalSignalQualityThreshold: double.infinity,
        ),
        throwsArgumentError,
      );
    });
  });
}

DefaultRewardEligibilityPolicy _policy({
  int policyVersion = 3,
  Duration minimumDuration = const Duration(minutes: 5),
  EvidenceTrust masteryThreshold = EvidenceTrust.scored,
}) => DefaultRewardEligibilityPolicy(
  config: RewardEligibilityPolicyConfig(
    policyVersion: policyVersion,
    minValidDurationBySource: _durationThresholds(minimumDuration),
    masteryTrustThresholdBySource: _trustThresholds(masteryThreshold),
    fatalSignalQualityThreshold: 0.2,
  ),
);

RewardEligibilityRequest _request({
  ActivityOutcome outcome = ActivityOutcome.completed,
  EvidenceTrust trust = EvidenceTrust.scored,
  Duration validDuration = const Duration(minutes: 5),
  double? quality = 0.8,
}) => RewardEligibilityRequest(
  source: ActivitySource.practice,
  outcome: outcome,
  trust: trust,
  validDuration: validDuration,
  quality: quality,
);

Map<ActivitySource, Duration> _durationThresholds([
  Duration minimumDuration = const Duration(minutes: 5),
]) => <ActivitySource, Duration>{
  for (final source in ActivitySource.values) source: minimumDuration,
};

Map<ActivitySource, EvidenceTrust> _trustThresholds([
  EvidenceTrust masteryThreshold = EvidenceTrust.scored,
]) => <ActivitySource, EvidenceTrust>{
  for (final source in ActivitySource.values) source: masteryThreshold,
};

void _expectGranted(RewardGateDecision decision) {
  expect(decision.isGranted, isTrue);
  expect(decision.reason, isNull);
}

void _expectDenied(RewardGateDecision decision, RewardReason reason) {
  expect(decision.isGranted, isFalse);
  expect(decision.reason, reason);
}
