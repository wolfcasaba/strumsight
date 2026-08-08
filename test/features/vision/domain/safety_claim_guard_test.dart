// E05-R20 — Safety claim guard tests (ADR 0188, brief §6 acceptance #1).
//
// The guard is the ONLY machine-side defence against a "helpful" claim
// silently morphing into a medical/diagnostic statement (brief §9 — primary
// risk of this round). The tests must hold in BOTH directions of the
// fail-closed allowlist:
//
//   - Positive: every catalog code is declared in an ALLOWED class.
//   - Negative: every code that maps to a FORBIDDEN class is rejected.
//   - Negative: every code that is NOT in the catalog is rejected (fail-closed).
//
// The "valódi-sértés próba" (brief §6 acceptance #2) is encoded by the
// `_forbiddenClassCases` group: the test fixture exercises the stack of
// forbidden classes directly against the guard, then the production code is
// separately verified by the §10 valódi-sértés próba that the orchestrator
// ran during the round (citation in handoff).

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/safety/safety_claim_guard.dart';
import 'package:strumsight/features/vision/domain/safety/vision_safety_policy.dart';

void main() {
  group('SafetyClaimGuard — fail-closed allowlist', () {
    const guard = SafetyClaimGuard();

    test('every catalog code is allowed', () {
      for (final code in VisionSafetyPolicy.catalog.keys) {
        final result = guard.evaluate(code);
        expect(
          result.isAllowed,
          isTrue,
          reason: 'catalog code "$code" must classify as allowed',
        );
      }
    });

    test('every allowed class is reachable from the catalog', () {
      // Belt-and-braces: the catalog must COVER every ALLOWED class
      // (not the forbidden ones — the brief §5 /1 explicitly forbids
      // them, so they MUST NOT appear in the catalog).
      final usedClasses = VisionSafetyPolicy.catalog.values.toSet();
      for (final cls in VisionSafetyClaimClass.values) {
        if (cls.isForbidden) continue;
        expect(
          usedClasses.contains(cls),
          isTrue,
          reason:
              'allowlist class "${cls.name}" must be reachable from the catalog',
        );
      }
    });

    test('an unknown code is rejected (fail-closed)', () {
      final result = guard.evaluate('postureSomethingThatDoesNotExist');
      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('not in catalog'));
    });

    test('a declared class still requires catalog membership', () {
      final result = guard.evaluate(
        'postureCodeThatIsNotCatalogued',
        declaredClass: VisionSafetyClaimClass.baselineRelative,
      );
      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('not in catalog'));
    });

    test('medical code is rejected despite an allowed declared class', () {
      const medicalCode = 'postureShoulderAsymmetryMayCauseLongTermPain';
      final result = guard.evaluate(
        medicalCode,
        declaredClass: VisionSafetyClaimClass.baselineRelative,
        catalog: <String, VisionSafetyClaimClass>{
          medicalCode: VisionSafetyClaimClass.baselineRelative,
        },
      );
      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('pain'));
    });
  });

  // ---------------------------------------------------------------------------
  // Forbidden-class exercises (mirrors the §10 valódi-sértés próba).
  //
  // For each forbidden class we exercise the guard with a synthetic code
  // declared in that class. The guard must reject them. These cases
  // duplicate the "temporarily add a forbidden code to the catalog" probe
  // from the brief so the prod code is independently verified to refuse
  // anything that lands in a forbidden class.
  // ---------------------------------------------------------------------------
  group('SafetyClaimGuard — forbidden classes (§10 valódi-sértés próba)', () {
    const guard = SafetyClaimGuard();

    final forbiddenClassCases = <String, VisionSafetyClaimClass>{
      'postureShoulderAsymmetryCausesChronicPain':
          VisionSafetyClaimClass.diagnosis,
      'postureTorsoLeanWillCauseInjury':
          VisionSafetyClaimClass.injuryPrediction,
      'postureElbowDriftExplainsDiscomfort':
          VisionSafetyClaimClass.painExplanation,
      'postureNeckStrainRequiresRecovery':
          VisionSafetyClaimClass.recoveryAdvice,
      'postureShoulderAsymmetryIsHarmful':
          VisionSafetyClaimClass.harmfulJudgment,
    };

    for (final entry in forbiddenClassCases.entries) {
      test('a "${entry.value.name}" claim is rejected: "${entry.key}"', () {
        final result = guard.evaluate(entry.key, declaredClass: entry.value);
        expect(result.isAllowed, isFalse);
        expect(result.reason, contains(entry.value.name));
      });
    }
  });

  // ---------------------------------------------------------------------------
  // The neutral/allowed classes are reachable for the R23/R27 text layer.
  // ---------------------------------------------------------------------------
  group('SafetyClaimGuard — allowed classes are reachable', () {
    const guard = SafetyClaimGuard();

    final allowedClassCases = <String, VisionSafetyClaimClass>{
      'postureShoulderAsymmetryIncreasedVsBaseline':
          VisionSafetyClaimClass.baselineRelative,
      'postureTorsoLeanShiftedVsBaseline':
          VisionSafetyClaimClass.baselineRelative,
      'postureElbowDriftObserved': VisionSafetyClaimClass.neutralObservation,
      'postureNeckProxyUnavailable': VisionSafetyClaimClass.unobservable,
    };

    for (final entry in allowedClassCases.entries) {
      test('a "${entry.value.name}" claim is allowed: "${entry.key}"', () {
        final result = guard.evaluate(entry.key, declaredClass: entry.value);
        expect(result.isAllowed, isTrue);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // The catalog itself is a valid VisionSafetyPolicy (every entry has a
  // declared class, every class is in the closed set).
  // ---------------------------------------------------------------------------
  group('VisionSafetyPolicy — catalog integrity', () {
    test('the catalog is not empty', () {
      expect(VisionSafetyPolicy.catalog, isNotEmpty);
    });

    test('no catalog code is declared in a forbidden class', () {
      for (final entry in VisionSafetyPolicy.catalog.entries) {
        expect(
          VisionSafetyPolicy.forbidden.contains(entry.value),
          isFalse,
          reason:
              'catalog code "${entry.key}" declares forbidden class '
              '"${entry.value.name}"',
        );
      }
    });

    test(
      'all classes in the catalog are valid VisionSafetyClaimClass values',
      () {
        for (final cls in VisionSafetyPolicy.catalog.values) {
          expect(VisionSafetyClaimClass.values, contains(cls));
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Pain-report handoff (§5 /4, ADR 0177 `painResponse` sibling).
  // The guard does NOT validate the pain category — that is the tutor's
  // job. The guard only checks that any posture-side claim code is in the
  // catalog and in an allowed class. The acknowledged handoff is a
  // standalone flag, not a posture claim.
  // ---------------------------------------------------------------------------
  group('SafetyClaimGuard — pain handoff', () {
    const guard = SafetyClaimGuard();

    test('the pain handoff flag is independent of the guard', () {
      // The pain handoff is a sibling channel, not a claim code — it
      // cannot be a "stored" code with a forbidden class. The guard does
      // not own the handoff; this test pins the contract.
      final result = guard.evaluate('painHandoffRequired');
      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('not in catalog'));
    });
  });
}
