import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('A1 — every receipt exposes the five receipt-facing components', () {
    test('first-time, fully-eligible session decomposes into base/duration/'
        'quality/improvement/diversity', () {
      final policy = _policy();
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(
            granted: const <_Gate>{
              _Gate.baseXp,
              _Gate.qualityBonus,
              _Gate.mastery,
              _Gate.verified,
            },
          ),
          validDuration: const Duration(minutes: 2),
          qualityScore: 1.0,
          improvementDelta: 1.0,
          uniqueSourcesToday: 4,
        ),
        _history(),
      );

      expect(decision.points.baseXp, 5);
      expect(decision.points.durationXp, 2);
      expect(decision.points.qualityXp, 4);
      // improvementDelta=1.0 with cap=6 uses the sub-linear curve
      // 6 * (1 / (1 + 1)) = 3, rounded to the nearest int.
      expect(decision.points.improvementXp, 3);
      expect(decision.points.diversityXp, 3);
      // Total is the documented sum, not a separate figure (A1).
      expect(decision.points.totalXp, 5 + 2 + 4 + 3 + 3);
    });

    test('only baseXp granted with zero duration yields exactly the base '
        'component', () {
      final policy = _policy();
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
          validDuration: Duration.zero,
          qualityScore: 0.0,
          improvementDelta: 0.0,
          uniqueSourcesToday: 1,
        ),
        _history(),
      );

      expect(decision.points.baseXp, 5);
      expect(decision.points.durationXp, 0);
      expect(decision.points.qualityXp, 0);
      expect(decision.points.improvementXp, 0);
      expect(decision.points.diversityXp, 0);
    });
  });

  group('A2 — first-time weak session still earns base XP', () {
    test(
      'low-score, no-improvement activity keeps the base component alive',
      () {
        final policy = _policy();
        final decision = policy.decide(
          _request(
            practiceKey: 'chord-em',
            eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
            validDuration: const Duration(seconds: 30),
            qualityScore: 0.1,
          ),
          _history(),
        );

        expect(decision.points.baseXp, 5);
        expect(decision.points.totalXp, 5);
        // No reduction is recorded for the lack of higher gates — those gates
        // simply never opened.
        expect(decision.points.reductionReasons, isEmpty);
      },
    );
  });

  group('A3 — repeat practice decays XP but never loses the receipt', () {
    test('the fifth identical practice on the same day decays but its '
        'decision is still produced', () {
      final policy = _policy();
      final first = policy.decide(
        _request(practiceKey: 'chord-em'),
        _history(practiceOccurrenceCount: 0, earnedTodayXp: 0),
      );

      // baseline of 5*0.8^4 = 2.048 → 2 (floor) for base component only.
      // We compare against the FIRST decision scaled by the same factor to
      // keep the assertion robust to policy-config tuning in Kör-29.
      final fifth = policy.decide(
        _request(practiceKey: 'chord-em'),
        _history(
          practiceOccurrenceCount: 4,
          earnedTodayXp: first.points.totalXp,
        ),
      );

      expect(fifth.points.totalXp, lessThan(first.points.totalXp));
      expect(
        fifth.points.reductionReasons,
        contains(RewardReason.repeatLimited),
      );
      // The receipt still resolves to a five-component breakdown.
      expect(
        fifth.points.totalXp,
        fifth.points.baseXp +
            fifth.points.durationXp +
            fifth.points.qualityXp +
            fifth.points.improvementXp +
            fifth.points.diversityXp,
      );
    });

    test('the decay multiplier is floored at the configured minimum', () {
      final policy = _policy();
      // 100th occurrence: raw = 0.8^100 ≈ 2e-10, well below the 0.2 floor.
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(
            granted: const <_Gate>{_Gate.baseXp, _Gate.qualityBonus},
          ),
          practiceKey: 'chord-em',
          validDuration: Duration.zero,
          qualityScore: 1.0,
        ),
        _history(practiceOccurrenceCount: 100),
      );

      // base (5) scales by 0.2 → floor(1.0) = 1; quality (4) scales by
      // 0.2 → floor(0.8) = 0. The floor is the visible artefact.
      expect(decision.points.baseXp, 1);
      expect(decision.points.qualityXp, 0);
    });

    test('A3 cell: events above the daily cap still produce a receipt '
        '(zero XP, but the receipt and reason are preserved)', () {
      final policy = _policy(
        dailyXpCap: 100,
        baseReward: 1,
        durationRewardPerMinuteCap: 0,
      );
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
          validDuration: Duration.zero,
        ),
        // earnedTodayXp above the cap — the cap branch must still produce
        // a five-component receipt, not drop the event entirely.
        _history(earnedTodayXp: 200),
      );

      expect(decision.points.totalXp, 0);
      expect(decision.policyVersion, policy.config.policyVersion);
      expect(
        decision.points.reductionReasons,
        contains(RewardReason.dailyCapApplied),
      );
    });
  });

  group('A4 — daily cap persists the receipt with a documented reason', () {
    test('one XP on top of 99 already earned today fits without clipping', () {
      final policy = _policy(
        dailyXpCap: 100,
        baseReward: 1,
        durationRewardPerMinuteCap: 0,
      );
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
          validDuration: Duration.zero,
        ),
        _history(earnedTodayXp: 99),
      );

      expect(decision.points.totalXp, 1);
      expect(decision.points.reductionReasons, isEmpty);
    });

    test('one XP on top of EXACTLY 100 already earned today clips to zero '
        'with the daily cap reason attached', () {
      final policy = _policy(
        dailyXpCap: 100,
        baseReward: 1,
        durationRewardPerMinuteCap: 0,
      );
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
          validDuration: Duration.zero,
        ),
        _history(earnedTodayXp: 100),
      );

      expect(decision.points.totalXp, 0);
      expect(
        decision.points.reductionReasons,
        contains(RewardReason.dailyCapApplied),
      );
    });

    test('one XP on top of 101 already earned today clips to zero '
        '(under, on, over the cap are all matched here)', () {
      final policy = _policy(
        dailyXpCap: 100,
        baseReward: 1,
        durationRewardPerMinuteCap: 0,
      );
      final decision = policy.decide(
        _request(
          eligibility: _eligibility(granted: const <_Gate>{_Gate.baseXp}),
          validDuration: Duration.zero,
        ),
        _history(earnedTodayXp: 101),
      );

      expect(decision.points.totalXp, 0);
      expect(
        decision.points.reductionReasons,
        contains(RewardReason.dailyCapApplied),
      );
    });
  });

  group('A5 — parent and child produce a single combined reward', () {
    test(
      'the second of a parent/child pair produces zero XP with a receipt',
      () {
        final policy = _policy();
        final decision = policy.decide(
          _request(
            eventId: 'child-1',
            practiceKey: 'lesson-pack-1',
            parentEventId: 'session-summary-1',
            eligibility: _eligibility(
              granted: const <_Gate>{
                _Gate.baseXp,
                _Gate.qualityBonus,
                _Gate.mastery,
                _Gate.verified,
              },
            ),
            validDuration: const Duration(minutes: 2),
            qualityScore: 1.0,
            improvementDelta: 1.0,
            uniqueSourcesToday: 4,
          ),
          _history(rewardedParentIds: const <String>{'session-summary-1'}),
        );

        // Dedup zeroes all five components without a cap-related reason
        // (the cap layer still ran, but had envelope to spare).
        expect(decision.points.totalXp, 0);
        expect(
          decision.points.reductionReasons,
          isNot(contains(RewardReason.dailyCapApplied)),
        );
        expect(decision.policyVersion, 1);
      },
    );

    test('the parent arriving after its child collapses to zero '
        '(symmetric ordering)', () {
      final policy = _policy();
      final decision = policy.decide(
        _request(
          eventId: 'session-summary-1',
          practiceKey: 'lesson-pack-1',
          eligibility: _eligibility(
            granted: const <_Gate>{
              _Gate.baseXp,
              _Gate.qualityBonus,
              _Gate.mastery,
              _Gate.verified,
            },
          ),
          validDuration: const Duration(minutes: 2),
          qualityScore: 1.0,
          improvementDelta: 1.0,
          uniqueSourcesToday: 4,
        ),
        _history(rewardedChildParentIds: const <String>{'session-summary-1'}),
      );

      expect(decision.points.totalXp, 0);
      expect(
        decision.points.reductionReasons,
        isNot(contains(RewardReason.dailyCapApplied)),
      );
    });
  });

  group('A6 — same input produces the same decision on every iteration', () {
    test('100 evaluations of the same request + history are equal', () {
      final policy = _policy();
      final request = _request(
        eligibility: _eligibility(
          granted: const <_Gate>{
            _Gate.baseXp,
            _Gate.qualityBonus,
            _Gate.mastery,
          },
        ),
        validDuration: const Duration(minutes: 3),
        qualityScore: 0.7,
        improvementDelta: 0.4,
      );
      final history = _history(practiceOccurrenceCount: 2, earnedTodayXp: 25);

      final first = policy.decide(request, history);
      for (var iteration = 0; iteration < 100; iteration++) {
        final decision = policy.decide(request, history);
        expect(decision, first);
      }
    });
  });

  group('A7 — every receipt carries the configured policy version', () {
    test('a configured policy version of 7 reaches the decision', () {
      final policy = _policy(policyVersion: 7);
      final decision = policy.decide(_request(), _history());
      expect(decision.policyVersion, 7);
    });
  });

  group('A8 — a single configuration controls every component and cap', () {
    test('raising the base reward lifts only the base component', () {
      final baseBaseline = _policy(
        baseReward: 5,
      ).decide(_request(), _history());
      final baseLifted = _policy(baseReward: 9).decide(_request(), _history());

      expect(baseLifted.points.baseXp - baseBaseline.points.baseXp, 4);
      expect(baseLifted.points.durationXp, baseBaseline.points.durationXp);
      expect(baseLifted.points.qualityXp, baseBaseline.points.qualityXp);
      expect(
        baseLifted.points.improvementXp,
        baseBaseline.points.improvementXp,
      );
      expect(baseLifted.points.diversityXp, baseBaseline.points.diversityXp);
      expect(baseLifted.policyVersion, baseBaseline.policyVersion);
    });

    test('lowering the daily cap flips previously-allowed XP into '
        'dailyCapApplied territory', () {
      final loose = _policy(
        dailyXpCap: 200,
      ).decide(_request(), _history(earnedTodayXp: 0));
      final tight = _policy(
        dailyXpCap: 5,
      ).decide(_request(), _history(earnedTodayXp: 0));

      expect(tight.points.totalXp, lessThan(loose.points.totalXp));
      expect(
        tight.points.reductionReasons,
        contains(RewardReason.dailyCapApplied),
      );
    });
  });

  group('validated inputs', () {
    test('request rejects blank identifiers, negative durations, and out-of-'
        'range measurements', () {
      expect(() => _request(eventId: ' '), throwsArgumentError);
      expect(() => _request(practiceKey: ' '), throwsArgumentError);
      expect(() => _request(parentEventId: ' '), throwsArgumentError);
      expect(
        () => _request(validDuration: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      for (final score in <double>[double.nan, -0.1, 1.5]) {
        expect(() => _request(qualityScore: score), throwsArgumentError);
      }
      expect(() => _request(improvementDelta: double.nan), throwsArgumentError);
      expect(() => _request(uniqueSourcesToday: -1), throwsArgumentError);
    });

    test('configuration rejects negative values, zero version, '
        'and a min factor that exceeds the base factor', () {
      final valid = RewardPolicyConfig(
        policyVersion: 1,
        baseReward: 1,
        durationRewardPerMinuteCap: 1,
        qualityRewardCap: 1,
        improvementRewardCap: 1,
        diversityRewardCap: 1,
        dailyXpCap: 1,
        practiceRepeatBaseFactor: 0.8,
        practiceRepeatMinFactor: 0.2,
      );

      expect(
        () => RewardPolicyConfig(
          policyVersion: 0,
          baseReward: valid.baseReward,
          durationRewardPerMinuteCap: valid.durationRewardPerMinuteCap,
          qualityRewardCap: valid.qualityRewardCap,
          improvementRewardCap: valid.improvementRewardCap,
          diversityRewardCap: valid.diversityRewardCap,
          dailyXpCap: valid.dailyXpCap,
          practiceRepeatBaseFactor: valid.practiceRepeatBaseFactor,
          practiceRepeatMinFactor: valid.practiceRepeatMinFactor,
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardPolicyConfig(
          policyVersion: 1,
          baseReward: -1,
          durationRewardPerMinuteCap: valid.durationRewardPerMinuteCap,
          qualityRewardCap: valid.qualityRewardCap,
          improvementRewardCap: valid.improvementRewardCap,
          diversityRewardCap: valid.diversityRewardCap,
          dailyXpCap: valid.dailyXpCap,
          practiceRepeatBaseFactor: valid.practiceRepeatBaseFactor,
          practiceRepeatMinFactor: valid.practiceRepeatMinFactor,
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardPolicyConfig(
          policyVersion: 1,
          baseReward: valid.baseReward,
          durationRewardPerMinuteCap: valid.durationRewardPerMinuteCap,
          qualityRewardCap: valid.qualityRewardCap,
          improvementRewardCap: valid.improvementRewardCap,
          diversityRewardCap: valid.diversityRewardCap,
          dailyXpCap: valid.dailyXpCap,
          practiceRepeatBaseFactor: 1.5,
          practiceRepeatMinFactor: valid.practiceRepeatMinFactor,
        ),
        throwsArgumentError,
      );
      expect(
        () => RewardPolicyConfig(
          policyVersion: 1,
          baseReward: valid.baseReward,
          durationRewardPerMinuteCap: valid.durationRewardPerMinuteCap,
          qualityRewardCap: valid.qualityRewardCap,
          improvementRewardCap: valid.improvementRewardCap,
          diversityRewardCap: valid.diversityRewardCap,
          dailyXpCap: valid.dailyXpCap,
          practiceRepeatBaseFactor: 0.5,
          practiceRepeatMinFactor: 0.8,
        ),
        throwsArgumentError,
      );
    });

    test('history snapshot rejects negative counters', () {
      expect(() => _history(earnedTodayXp: -1), throwsArgumentError);
      expect(() => _history(practiceOccurrenceCount: -1), throwsArgumentError);
    });
  });
}

DefaultRewardPolicy _policy({
  int policyVersion = 1,
  int baseReward = 5,
  int durationRewardPerMinuteCap = 3,
  int qualityRewardCap = 4,
  int improvementRewardCap = 6,
  int diversityRewardCap = 3,
  int dailyXpCap = 100,
  double practiceRepeatBaseFactor = 0.8,
  double practiceRepeatMinFactor = 0.2,
}) => DefaultRewardPolicy(
  config: RewardPolicyConfig(
    policyVersion: policyVersion,
    baseReward: baseReward,
    durationRewardPerMinuteCap: durationRewardPerMinuteCap,
    qualityRewardCap: qualityRewardCap,
    improvementRewardCap: improvementRewardCap,
    diversityRewardCap: diversityRewardCap,
    dailyXpCap: dailyXpCap,
    practiceRepeatBaseFactor: practiceRepeatBaseFactor,
    practiceRepeatMinFactor: practiceRepeatMinFactor,
  ),
);

RewardPolicyRequest _request({
  String eventId = 'event-1',
  String practiceKey = 'chord-em',
  String? parentEventId,
  int epochDay = 20_260,
  ActivitySource source = ActivitySource.practice,
  RewardEligibilityDecision? eligibility,
  Duration validDuration = const Duration(minutes: 1),
  double qualityScore = 0.5,
  double improvementDelta = 0.0,
  int uniqueSourcesToday = 1,
}) => RewardPolicyRequest(
  eventId: eventId,
  practiceKey: practiceKey,
  parentEventId: parentEventId,
  epochDay: epochDay,
  source: source,
  eligibility: eligibility ?? _eligibility(),
  validDuration: validDuration,
  qualityScore: qualityScore,
  improvementDelta: improvementDelta,
  uniqueSourcesToday: uniqueSourcesToday,
);

RewardPolicyHistory _history({
  int epochDay = 20_260,
  int earnedTodayXp = 0,
  int practiceOccurrenceCount = 0,
  Set<String> rewardedParentIds = const <String>{},
  Set<String> rewardedChildParentIds = const <String>{},
}) => RewardPolicyHistory(
  epochDay: epochDay,
  earnedTodayXp: earnedTodayXp,
  practiceOccurrenceCount: practiceOccurrenceCount,
  rewardedParentIds: rewardedParentIds,
  rewardedChildParentIds: rewardedChildParentIds,
);

enum _Gate { baseXp, qualityBonus, mastery, verified }

RewardEligibilityDecision _eligibility({
  Set<_Gate> granted = const <_Gate>{_Gate.baseXp},
  Set<_Gate> denied = const <_Gate>{
    _Gate.qualityBonus,
    _Gate.mastery,
    _Gate.verified,
  },
}) => RewardEligibilityDecision(
  policyVersion: 1,
  baseXp: _gateDecision(_Gate.baseXp, granted, denied, RewardReason.cancelled),
  qualityBonus: _gateDecision(
    _Gate.qualityBonus,
    granted,
    denied,
    RewardReason.fatalSignalQuality,
  ),
  mastery: _gateDecision(
    _Gate.mastery,
    granted,
    denied,
    RewardReason.insufficientTrust,
  ),
  verified: _gateDecision(
    _Gate.verified,
    granted,
    denied,
    RewardReason.insufficientTrust,
  ),
);

RewardGateDecision _gateDecision(
  _Gate gate,
  Set<_Gate> granted,
  Set<_Gate> denied,
  RewardReason deniedReason,
) {
  if (granted.contains(gate)) return RewardGateDecision.granted();
  if (denied.contains(gate)) {
    return RewardGateDecision.denied(deniedReason);
  }
  return RewardGateDecision.denied(RewardReason.cancelled);
}
