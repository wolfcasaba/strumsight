import 'package:meta/meta.dart';

import '../../domain/models/tutor_source_ref.dart';

/// Why a claim is blocked by the domain-level claim validator.
enum TutorClaimValidationIssue {
  /// The claim type is not in the R16 grounding taxonomy.
  unsupportedClaim,

  /// A measuredFact, computedTrend, or knowledgeFact claim has no trusted
  /// evidenceRef — this is an invented metric and is a HARD block.
  unsupportedClaimEvidence,
}

/// A single claim to validate, with its type and evidence references.
@immutable
final class TutorClaim {
  const TutorClaim({
    required this.type,
    this.evidenceRefs = const <String>{},
  });

  final String type;
  final Set<String> evidenceRefs;

  @override
  bool operator ==(Object other) =>
      other is TutorClaim &&
      type == other.type &&
      evidenceRefs.length == other.evidenceRefs.length &&
      evidenceRefs.containsAll(other.evidenceRefs);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(evidenceRefs));

  @override
  String toString() =>
      'TutorClaim(type: $type, evidenceRefs: ${evidenceRefs.length} refs)';
}

/// Result of claim validation — deterministic and immutable.
@immutable
final class TutorClaimValidationResult {
  const TutorClaimValidationResult({this.issues = const <TutorClaimValidationIssue>[]});

  final List<TutorClaimValidationIssue> issues;

  bool get isValid => issues.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TutorClaimValidationResult &&
      issues.length == other.issues.length &&
      issues.toSet().containsAll(other.issues.toSet());

  @override
  int get hashCode => Object.hashAll(issues);

  @override
  String toString() =>
      'TutorClaimValidationResult(isValid: $isValid, issues: ${issues.length})';
}

/// Pure domain-level claim-provenance validator.
///
/// Reuses the R16 grounding taxonomy from [TutorOutputValidator]:
/// `{measuredFact, computedTrend, knowledgeFact, userProvidedFact, inference,
/// recommendation, safetyNotice}`. Does NOT fork the taxonomy — this is the
/// single source of truth for claim type grounding.
///
/// Invented-metric: a `measuredFact` or `computedTrend` claim with no trusted
/// `evidenceRefs` → HARD block (`unsupportedClaimEvidence`), never a warning.
@immutable
final class TutorClaimValidator {
  const TutorClaimValidator();

  /// The R16 grounding claim type taxonomy — must NOT diverge from
  /// `TutorOutputValidator._groundedClaimTypes`.
  static const Set<String> groundedClaimTypes = <String>{
    'measuredFact',
    'computedTrend',
    'knowledgeFact',
    'userProvidedFact',
    'inference',
    'recommendation',
    'safetyNotice',
  };

  /// Claim types that require trusted evidence references.
  static const Set<String> _evidenceRequiredTypes = <String>{
    'measuredFact',
    'computedTrend',
    'knowledgeFact',
  };

  /// Validate claims against the grounding taxonomy and trusted sources.
  ///
  /// Returns [TutorClaimValidationResult] with issues for any claim that:
  /// - has an unknown type (unsupportedClaim)
  /// - is evidence-required but has no matching trusted source ref
  ///   (unsupportedClaimEvidence — invented metric block).
  TutorClaimValidationResult validate({
    required Iterable<TutorClaim> claims,
    required Iterable<TutorSourceRef> trustedSourceRefs,
  }) {
    final trustedIds = trustedSourceRefs
        .map((ref) => ref.chunkId)
        .toSet();
    final issues = <TutorClaimValidationIssue>[];

    for (final claim in claims) {
      final type = claim.type.trim();
      if (type.isEmpty || !groundedClaimTypes.contains(type)) {
        issues.add(TutorClaimValidationIssue.unsupportedClaim);
        continue;
      }

      if (_evidenceRequiredTypes.contains(type)) {
        final refs = claim.evidenceRefs;
        if (refs.isEmpty || refs.every((ref) => !trustedIds.contains(ref))) {
          issues.add(TutorClaimValidationIssue.unsupportedClaimEvidence);
        }
      }
    }

    return TutorClaimValidationResult(issues: issues);
  }
}
