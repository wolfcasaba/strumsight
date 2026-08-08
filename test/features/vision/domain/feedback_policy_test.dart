import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/feedback/cue_budget.dart';
import 'package:strumsight/features/vision/domain/feedback/feedback_policy.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/safety/safety_claim_guard.dart';
import 'package:strumsight/features/vision/domain/safety/vision_safety_policy.dart';

void main() {
  test('the setup insight code is admitted by the vision safety catalog', () {
    final result = SafetyClaimGuard().evaluate(
      'visionInsightSetupNotObservable',
    );

    expect(result.isAllowed, isTrue, reason: result.reason);
  });

  test(
    'every insight code has a complete policy, safety entry, and ARB key',
    () {
      final english =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, Object?>;
      final hungarian =
          jsonDecode(File('lib/l10n/app_hu.arb').readAsStringSync())
              as Map<String, Object?>;
      const guard = SafetyClaimGuard();

      for (final code in InsightCode.values) {
        final policy = FeedbackPolicies.catalog[code];
        expect(policy, isNotNull, reason: '${code.name} needs a policy');
        expect(policy!.code, code);
        expect(guard.evaluate(code.safetyCode).isAllowed, isTrue);
        expect(english[code.safetyCode], isA<String>());
        expect(english['@${code.safetyCode}'], isA<Map<String, Object?>>());
        final metadata = english['@${code.safetyCode}'] as Map<String, Object?>;
        expect(metadata['description'], isA<String>());
        expect(hungarian[code.safetyCode], isA<String>());
      }
    },
  );

  test(
    'negative confidence thresholds are stricter than positive thresholds',
    () {
      for (final policy in FeedbackPolicies.catalog.values) {
        expect(
          policy.negativeConfidenceThreshold,
          greaterThan(policy.positiveConfidenceThreshold),
        );
      }
    },
  );

  test('cooldown suppresses a code below and at its boundary', () {
    var now = DateTime.utc(2026, 8, 8, 12);
    final budget = CueBudget(now: () => now);
    final insight = _insight(InsightCode.frettingStable);

    expect(budget.selectRealtime(<VisionInsight>[insight]), insight);
    now = now.add(const Duration(seconds: 4, milliseconds: 999));
    expect(budget.selectRealtime(<VisionInsight>[insight]), isNull);
    now = now.add(const Duration(milliseconds: 1));
    expect(budget.selectRealtime(<VisionInsight>[insight]), isNull);
    now = now.add(const Duration(milliseconds: 1));
    expect(budget.selectRealtime(<VisionInsight>[insight]), insight);
  });

  test('VisionInsight derives priority and direction from its policy code', () {
    final insight = _insight(InsightCode.frettingFocus);
    final policy = FeedbackPolicies.catalog[insight.code]!;

    expect(insight.priority, policy.priority);
    expect(insight.direction, policy.direction);
  });

  test('focus insight codes are neutral observations', () {
    for (final code in <InsightCode>[
      InsightCode.frettingFocus,
      InsightCode.pickingFocus,
      InsightCode.postureFocus,
    ]) {
      expect(
        VisionSafetyPolicy.catalog[code.safetyCode],
        VisionSafetyClaimClass.neutralObservation,
      );
    }
  });

  test(
    'session summary is limited to two deterministic technical insights',
    () {
      final budget = CueBudget(now: () => DateTime.utc(2026, 8, 8, 12));
      final insights = <VisionInsight>[
        _insight(InsightCode.postureFocus),
        _insight(InsightCode.pickingFocus),
        _insight(InsightCode.frettingFocus),
        _insight(InsightCode.postureStable),
        _insight(InsightCode.pickingStable),
      ];

      final first = budget.sessionSummary(insights);
      final second = budget.sessionSummary(insights.reversed);

      expect(first, hasLength(2));
      expect(second, first);
      expect(first.map((insight) => insight.code), <InsightCode>[
        InsightCode.pickingStable,
        InsightCode.postureStable,
      ]);
    },
  );
}

VisionInsight _insight(InsightCode code) {
  return VisionInsight(
    code: code,
    policyVersion: FeedbackPolicies.policyVersion,
    evidenceIds: <String>['evidence-${code.name}'],
    confidence: 0.9,
  );
}
