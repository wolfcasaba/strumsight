// E05-R20 — Safety claim guard (ADR 0188, brief §5 /6).
//
// The guard is the SINGLE machine-side defence against a posture
// code silently morphing into a medical/diagnostic statement (brief
// §9 — primary risk of this round). Three fail-closed checks per code:
//
//   1. The code must be in [VisionSafetyPolicy.catalog].
//   2. Its declared class must not be in the forbidden subset.
//   3. Its surface form must not contain a forbidden medical lexeme.
//
// The lexical check is a closed, documented deny-list independent of the
// declared class, so a misclassified medical code cannot pass merely by
// being labelled as an allowed observation.

library;

import 'package:meta/meta.dart';

import 'vision_safety_policy.dart';

/// The deterministic output of [SafetyClaimGuard.evaluate].
@immutable
final class SafetyClaimGuardResult {
  /// Allowed evaluation: the code is catalogued, non-forbidden, and neutral.
  const SafetyClaimGuardResult.allowed() : isAllowed = true, reason = 'allowed';

  /// Rejected evaluation: the reason is the failure description.
  const SafetyClaimGuardResult.rejected(this.reason) : isAllowed = false;

  final bool isAllowed;
  final String reason;
}

/// The fail-closed safety claim guard.
@immutable
final class SafetyClaimGuard {
  const SafetyClaimGuard();

  /// Closed lexical deny-list for medical/diagnostic claim concepts.
  ///
  /// Claim codes are stable English identifiers. These conservative stems
  /// are intentionally closed; additions require a safety-policy review.
  static const List<String> _forbiddenLexemes = <String>[
    'pain',
    'diagnos',
    'injur',
    'harm',
    'recover',
    'treat',
    'symptom',
    'disease',
    'disorder',
    'syndrome',
  ];

  /// Evaluate [code] against the [VisionSafetyPolicy] catalog.
  ///
  /// [declaredClass] is a classification override used by catalog
  /// validation and focused regression tests. Membership and lexical
  /// checks still apply when it is provided.
  SafetyClaimGuardResult evaluate(
    String code, {
      VisionSafetyClaimClass? declaredClass,
      @visibleForTesting Map<String, VisionSafetyClaimClass>? catalog,
    }) {
    if (code.trim().isEmpty) {
      return const SafetyClaimGuardResult.rejected('code is empty');
    }
    // (1) Closed-set membership applies to every call path.
    final policyCatalog = catalog ?? VisionSafetyPolicy.catalog;
    final catalogClass = policyCatalog[code];
    if (catalogClass == null) {
      return SafetyClaimGuardResult.rejected('code "$code" is not in catalog');
    }
    // (2) Check the explicit class when supplied, otherwise the catalog.
    final declared = declaredClass ?? catalogClass;
    if (declared.isForbidden) {
      return SafetyClaimGuardResult.rejected(
        'code "$code" declares forbidden class "${declared.name}"',
      );
    }
    // (3) Independent surface-form defence against misclassification.
    final normalizedCode = code.toLowerCase();
    for (final lexeme in _forbiddenLexemes) {
      if (normalizedCode.contains(lexeme)) {
        return SafetyClaimGuardResult.rejected(
          'code "$code" contains forbidden safety lexeme "$lexeme"',
        );
      }
    }
    return const SafetyClaimGuardResult.allowed();
  }

  /// Validate the [VisionSafetyPolicy.catalog] itself.
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
