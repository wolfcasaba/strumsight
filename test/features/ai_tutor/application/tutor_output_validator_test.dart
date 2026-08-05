import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_output_validator.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_action.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_source_ref.dart';

void main() {
  const validator = TutorOutputValidator();
  final now = DateTime.utc(2026, 8, 5);
  const source = TutorSourceRef(
    sourceId: 'rhythm-basics',
    title: 'Rhythm basics',
    locale: 'en',
    topic: 'rhythm',
    knowledgeVersion: 1,
    chunkIndex: 0,
    chunkHash: 'hash',
  );

  TutorOutputValidationRequest request({
    String? output,
    Iterable<TutorActionProposal> actions = const <TutorActionProposal>[],
  }) => TutorOutputValidationRequest(
    output:
        output ?? _output(claims: <Object?>[_groundedClaim(source.chunkId)]),
    trustedSources: const <TutorSourceRef>[source],
    actions: actions,
    actionContext: TutorActionValidationContext(
      now: now,
      availableCapabilities: TutorActionCapability.values,
      activeSessionIds: const <String>[],
      songRevisions: const <String, TutorActionRevisionToken>{},
    ),
  );

  test('accepts v1 schema with a grounded knowledge claim', () {
    expect(validator.validate(request()).isValid, isTrue);
  });

  test('blocks a knowledge claim without an approved source reference', () {
    final result = validator.validate(
      request(output: _output(claims: <Object?>[_groundedClaim('invented#1')])),
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues,
      contains(TutorOutputValidationIssue.unsupportedClaimEvidence),
    );
  });

  test('blocks malformed action schema and expired action proposal', () {
    final action = TutorProfileUpdateAction(
      metadata: TutorActionMetadata(
        source: TutorActionSource.modelSuggestion,
        expiresAt: now.subtract(const Duration(seconds: 1)),
        requiredCapability: TutorActionCapability.updateProfile,
        clientActionId: 'expired-profile',
      ),
      changes: const <String, Object?>{'preferredTempo': 100},
    );
    final result = validator.validate(
      request(
        output: _output(
          actions: <Object?>[
            <String, Object?>{'type': 'deleteEverything'},
          ],
        ),
        actions: <TutorActionProposal>[action],
      ),
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues,
      contains(TutorOutputValidationIssue.invalidActionSchema),
    );
    expect(result.issues, contains(TutorOutputValidationIssue.invalidAction));
  });
}

Map<String, Object?> _groundedClaim(String reference) => <String, Object?>{
  'type': 'knowledgeFact',
  'evidenceRefs': <String>[reference],
};

String _output({
  List<Object?> claims = const <Object?>[],
  List<Object?> actions = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[],
  'claims': claims,
  'actions': actions,
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});
