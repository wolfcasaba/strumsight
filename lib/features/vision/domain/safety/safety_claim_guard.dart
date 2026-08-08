// E05-R20 — Safety claim guard (ADR 0188, brief §5 /6).
//
// The guard is the SINGLE machine-side defence against a posture
// code silently morphing into a medical/diagnostic statement (brief
// §9 — primary risk of this round). Two fail-closed checks per
// code:
//
//   1. The code must be in [VisionSafetyPolicy.catalog].
//   2. Its declared class must not be in the forbidden subset.
//
// Both checks must pass for the code to be allowed. The guard
// never tries to interpret the code's surface form — it is a
// pure map lookup against the closed catalog. Text-side patterns
// are the tutor's job (ADR 0177, `TutorSafetyPolicy` regex).
//
// The guard is a const-constructible, pure function. The vision
// layer calls it at code-emission time (every posture metric
// passes through the guard before it can be returned to a
// caller). The brief §6 /1 acceptance test holds the invariant.

library;

import 'package:meta/meta.dart';

import 'vision_safety_policy.dart';

/// The deterministic output of [SafetyClaimGuard.evaluate].
@immutable
final class SafetyClaimGuardResult {
  const SafetyClaimGuardResult._({
    required this.isAllowed,
    required this.reason,
  });

  /// Allowed evaluation: the code is in the catalog and its class is
  /// not forbidden.
  const SafetyClaimGuardResult.allowed() : isAllowed = true, reason = 'allowed';

  /// Rejected evaluation: the reason is the failure description.
  const SafetyClaimGuardResult.rejected(String this.reason) : isAllowed = false;

  final bool isAllowed;
  final String reason;
}

/// The fail-closed safety claim guard.
///
/// The guard accepts a code (and an optional declared class) and
/// returns a [SafetyClaimGuardResult]. The pattern is intentionally
/// simple: a map lookup + a forbidden-set check. The guard is
/// deterministic and pure — no I/O, no side effects.
@immutable
final class SafetyClaimGuard {
  const SafetyClaimGuard();

  /// Evaluate [code] against the [VisionSafetyPolicy] catalog.
  ///
  /// - If [declaredClass] is provided, the guard checks that the
  ///   declared class is not in the forbidden subset. This lets a
  ///   caller with its own classification (e.g. the §10 valódi-sértés
  ///   próba) exercise the forbidden-class path directly.
  /// - If [declaredClass] is omitted, the guard looks up the class
  ///   from the catalog. This is the production path.
  SafetyClaimGuardResult evaluate(
    String code, {
    VisionSafetyClaimClass? declaredClass,
  }) {
    if (code.trim().isEmpty) {
      return const SafetyClaimGuardResult.rejected('code is empty');
    }
    // (1) Closed-set membership — every allowed code lives in the
    // catalog.
    final declared = declaredClass ?? VisionSafetyPolicy.catalog[code];
    if (declared == null) {
      return SafetyClaimGuardResult.rejected('code "$code" is not in catalog');
    }
    // (2) Forbidden-class check — the guard is fail-closed against
    // ANY declared class on the forbidden list.
    if (declared.isForbidden) {
      return SafetyClaimGuardResult.rejected(
        'code "$code" declares forbidden class "${declared.name}"',
      );
    }
    return const SafetyClaimGuardResult.allowed();
  }

  /// Validate the [VisionSafetyPolicy.catalog] itself. The guard's
  /// own self-test — every entry passes `evaluate`. Returns the
  /// first rejection reason, or `null` when the catalog is healthy.
  ///
  /// This is invoked by the catalog-integrity test in
  /// `safety_claim_guard_test.dart` and by the `tools/round-gate.sh`
  /// architecture check.
  static String? validateCatalog() {
    for (final entry in VisionSafetyPolicy.catalog.entries) {
      final result = SafetyClaimGuard().evaluate(
        entry.key,
        declaredClass: entry.value,
      );
      if (!result.isAllowed) {
        return 'catalog entry "${entry.key}" fails guard: ${result.reason}';
      }
    }
    return null;
  }
}
