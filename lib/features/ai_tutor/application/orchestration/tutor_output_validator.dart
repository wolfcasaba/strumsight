import 'dart:convert';

import '../../application/prompts/tutor_output_schema.dart';
import '../../domain/models/tutor_action.dart';
import '../../domain/models/tutor_source_ref.dart';
import 'tutor_action_validator.dart';

enum TutorOutputValidationIssue {
  malformedJson,
  missingSchemaField,
  schemaFieldNotList,
  unsupportedClaim,
  unsupportedClaimEvidence,
  invalidActionSchema,
  invalidAction,
}

/// Input to the pure schema, grounding, and action validation pass.
final class TutorOutputValidationRequest {
  TutorOutputValidationRequest({
    required this.output,
    required Iterable<TutorSourceRef> trustedSources,
    required Iterable<TutorActionProposal> actions,
    required this.actionContext,
  }) : trustedSources = List<TutorSourceRef>.unmodifiable(trustedSources),
       actions = List<TutorActionProposal>.unmodifiable(actions);

  final String output;
  final List<TutorSourceRef> trustedSources;
  final List<TutorActionProposal> actions;
  final TutorActionValidationContext actionContext;
}

final class TutorOutputValidationResult {
  TutorOutputValidationResult(Iterable<TutorOutputValidationIssue> issues)
    : issues = List<TutorOutputValidationIssue>.unmodifiable(issues);

  final List<TutorOutputValidationIssue> issues;
  bool get isValid => issues.isEmpty;
}

/// Pure validation for the v1 model output contract.
final class TutorOutputValidator {
  const TutorOutputValidator();

  static const Set<String> _schemaFields = <String>{
    'answerBlocks',
    'claims',
    'actions',
    'followUpSuggestions',
    'safetyNotices',
    'memoryCandidates',
  };
  static const Set<String> _groundedClaimTypes = <String>{
    'measuredFact',
    'computedTrend',
    'knowledgeFact',
    'userProvidedFact',
    'inference',
    'recommendation',
    'safetyNotice',
  };
  static const Set<String> _actionTypes = <String>{
    'profileUpdate',
    'planSave',
    'launchPracticeSession',
    'launchSongRange',
  };

  TutorOutputValidationResult validate(TutorOutputValidationRequest request) {
    final issues = <TutorOutputValidationIssue>[];
    Object? decoded;
    try {
      decoded = jsonDecode(request.output);
    } on FormatException {
      return TutorOutputValidationResult(const <TutorOutputValidationIssue>[
        TutorOutputValidationIssue.malformedJson,
      ]);
    }
    if (decoded is! Map<String, dynamic>) {
      return TutorOutputValidationResult(const <TutorOutputValidationIssue>[
        TutorOutputValidationIssue.malformedJson,
      ]);
    }
    final values = Map<String, Object?>.from(decoded);
    final schema = TutorOutputSchema.v1.toJson();
    // This makes the owned validation explicitly tied to the prompt's v1 schema.
    final required = (schema['required'] as List<Object?>).cast<String>();
    for (final field in required) {
      final value = values[field];
      if (!values.containsKey(field)) {
        issues.add(TutorOutputValidationIssue.missingSchemaField);
      } else if (value is! List) {
        issues.add(TutorOutputValidationIssue.schemaFieldNotList);
      }
    }
    if (values.keys.any((key) => !_schemaFields.contains(key))) {
      issues.add(TutorOutputValidationIssue.missingSchemaField);
    }
    final trustedRefs = request.trustedSources
        .map((source) => source.chunkId)
        .toSet();
    final claims = values['claims'];
    if (claims is List) {
      for (final claim in claims) {
        if (claim is! Map) {
          issues.add(TutorOutputValidationIssue.unsupportedClaim);
          continue;
        }
        final type = claim['type'];
        final evidenceRefs = claim['evidenceRefs'];
        if (type is! String || !_groundedClaimTypes.contains(type)) {
          issues.add(TutorOutputValidationIssue.unsupportedClaim);
          continue;
        }
        if (type == 'knowledgeFact' ||
            type == 'measuredFact' ||
            type == 'computedTrend') {
          if (evidenceRefs is! List ||
              evidenceRefs.isEmpty ||
              evidenceRefs.any(
                (ref) => ref is! String || !trustedRefs.contains(ref),
              )) {
            issues.add(TutorOutputValidationIssue.unsupportedClaimEvidence);
          }
        }
      }
    }
    final actionSchemas = values['actions'];
    if (actionSchemas is List) {
      for (final action in actionSchemas) {
        if (action is! Map ||
            action['type'] is! String ||
            !_actionTypes.contains(action['type']) ||
            action['clientActionId'] is! String ||
            (action['clientActionId'] as String).trim().isEmpty) {
          issues.add(TutorOutputValidationIssue.invalidActionSchema);
        }
      }
    }
    const actionValidator = TutorActionValidator();
    for (final proposal in request.actions) {
      if (!actionValidator
          .validate(proposal, context: request.actionContext)
          .isValid) {
        issues.add(TutorOutputValidationIssue.invalidAction);
      }
    }
    return TutorOutputValidationResult(issues);
  }
}
