import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_command.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_response_mode.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';

void main() {
  group('TutorOrchestrator transition matrix', () {
    test('happy path completes and treats empty retrieval as valid', () async {
      final clock = FakeClock();
      final orchestrator = _orchestrator(
        (attempt) => FakeTutorModelGateway(
          clock: clock,
          script: <FakeGatewayStep>[
            FakeGatewayDelta(_validOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ),
      );

      await orchestrator.dispatch(SendTutorMessage(_request()));
      clock.advance(Duration.zero);
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.completed);
      expect(orchestrator.state.sources, isEmpty);
      await orchestrator.dispose();
    });

    test('executes a scripted read-only tool call before completing', () async {
      final clock = FakeClock();
      final orchestrator = _orchestrator(
        (attempt) => FakeTutorModelGateway(
          clock: clock,
          script: <FakeGatewayStep>[
            const FakeGatewayToolCall(
              'tool-1',
              'getContextField',
              '{"field":"studentProfile"}',
              sequence: 1,
            ),
            const FakeGatewayDelay(Duration(seconds: 1)),
            FakeGatewayDelta(_validOutput(), sequence: 2),
            const FakeGatewayDone(sequence: 3),
          ],
        ),
      );

      await orchestrator.dispatch(SendTutorMessage(_request()));
      clock.advance(Duration.zero);
      await _settle();
      clock.advance(const Duration(seconds: 1));
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.completed);
      await orchestrator.dispose();
    });

    test(
      'repairs one invalid output and completes with the repair response',
      () async {
        final clocks = <FakeClock>[FakeClock(), FakeClock()];
        final orchestrator = _orchestrator(
          (attempt) => FakeTutorModelGateway(
            clock: clocks[attempt],
            script: <FakeGatewayStep>[
              FakeGatewayDelta(attempt == 0 ? 'not-json' : _validOutput()),
              const FakeGatewayDone(),
            ],
          ),
        );

        await orchestrator.dispatch(SendTutorMessage(_request()));
        clocks[0].advance(Duration.zero);
        await _settle();
        clocks[1].advance(Duration.zero);
        await _settle();

        expect(orchestrator.state.status, TutorTurnStatus.completed);
        expect(orchestrator.state.repairCount, 1);
        await orchestrator.dispose();
      },
    );

    test('falls back after the bounded repair also fails', () async {
      final clocks = <FakeClock>[FakeClock(), FakeClock()];
      var starts = 0;
      final orchestrator = _orchestrator((attempt) {
        starts++;
        return FakeTutorModelGateway(
          clock: clocks[attempt],
          script: const <FakeGatewayStep>[
            FakeGatewayDelta('not-json'),
            FakeGatewayDone(),
          ],
        );
      });

      await orchestrator.dispatch(SendTutorMessage(_request()));
      clocks[0].advance(Duration.zero);
      await _settle();
      clocks[1].advance(Duration.zero);
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.fallback);
      expect(orchestrator.state.repairCount, 1);
      expect(
        starts,
        2,
        reason: 'The state-owned repair cap forbids a third start.',
      );
      await orchestrator.dispose();
    });

    test('cancel and late delta leave the cancelled state unchanged', () async {
      final clock = FakeClock();
      final request = _request();
      final orchestrator = _orchestrator(
        (attempt) => FakeTutorModelGateway(
          clock: clock,
          script: const <FakeGatewayStep>[
            FakeGatewayDelay(Duration(seconds: 1)),
            FakeGatewayDelta('late'),
            FakeGatewayDone(),
          ],
        ),
      );

      await orchestrator.dispatch(SendTutorMessage(request));
      await orchestrator.dispatch(CancelTutorTurn(request.requestId));
      await orchestrator.dispatch(
        TutorModelEventReceived(
          request.requestId,
          const TutorModelDelta(sequence: 99, delta: 'late'),
        ),
      );
      clock.advance(const Duration(seconds: 1));
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.cancelled);
      expect(orchestrator.state.responseText, isEmpty);
      await orchestrator.dispose();
    });

    test('rejects a concurrent send while one turn is active', () async {
      final clock = FakeClock();
      final orchestrator = _orchestrator(
        (attempt) => FakeTutorModelGateway(
          clock: clock,
          script: const <FakeGatewayStep>[
            FakeGatewayDelay(Duration(seconds: 1)),
          ],
        ),
      );
      await orchestrator.dispatch(SendTutorMessage(_request()));

      final transition = await orchestrator.dispatch(
        SendTutorMessage(_request(requestId: 'request-2')),
      );

      expect(transition.isRejected, isTrue);
      expect(orchestrator.state.requestId, TutorRequestId('request-1'));
      await orchestrator.dispose();
    });

    test('short-circuits revoked consent before creating a gateway', () async {
      var gatewayCalls = 0;
      final orchestrator = _orchestrator((attempt) {
        gatewayCalls++;
        return FakeTutorModelGateway(script: const <FakeGatewayStep>[]);
      });

      await orchestrator.dispatch(
        SendTutorMessage(_request(consent: const TutorConsent())),
      );

      expect(orchestrator.state.status, TutorTurnStatus.consentRevoked);
      expect(gatewayCalls, 0);
      await orchestrator.dispose();
    });

    test(
      'maps the owned usage-limit gateway code to a terminal limit state',
      () async {
        final clock = FakeClock();
        final orchestrator = _orchestrator(
          (attempt) => FakeTutorModelGateway(
            clock: clock,
            script: const <FakeGatewayStep>[
              FakeGatewayError(tutorUsageLimitCode, 'quota exhausted'),
            ],
          ),
        );

        await orchestrator.dispatch(SendTutorMessage(_request()));
        clock.advance(Duration.zero);
        await _settle();

        expect(orchestrator.state.status, TutorTurnStatus.usageLimit);
        await orchestrator.dispose();
      },
    );
  });
}

TutorOrchestrator _orchestrator(
  TutorModelGateway Function(int) gatewayForAttempt,
) => TutorOrchestrator(
  contextAssembler: const TutorContextAssembler(),
  knowledgeRetriever: KnowledgeRetriever(index: const KnowledgeIndex.empty()),
  promptBuilder: TutorPromptBuilder(templateLoader: _TemplateLoader()),
  gatewayForAttempt: gatewayForAttempt,
);

TutorTurnRequest _request({
  String requestId = 'request-1',
  TutorConsent consent = const TutorConsent(modelUseGranted: true),
}) => TutorTurnRequest(
  requestId: TutorRequestId(requestId),
  conversationId: TutorConversationId('conversation-1'),
  message: 'How can I improve my rhythm?',
  createdAt: DateTime.utc(2026, 8, 5),
  consent: consent,
  purpose: ContextPurpose.generalQuestion,
  contextFields: <TutorContextField>[
    TutorContextField.available(
      key: TutorContextFieldKey.studentProfile,
      values: const <String, Object?>{'level': 'beginner'},
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.aiTutor,
        schemaVersion: 'v1',
      ),
    ),
  ],
  retrievalQuery: const KnowledgeRetrievalQuery(
    queryText: 'rhythm',
    locale: 'en',
  ),
  responseLocale: 'en',
  responseMode: TutorResponseMode.concise,
  toolPolicy: TutorToolTurnPolicy(
    allowedToolNames: const <String>{'getContextField', 'summarizeContext'},
    allowedPermissions: TutorToolPermission.values,
  ),
  actionContext: TutorActionValidationContext(
    now: DateTime.utc(2026, 8, 5),
    availableCapabilities: const [],
    activeSessionIds: const <String>[],
    songRevisions: const {},
  ),
);

String _validOutput() => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[],
  'claims': <Object?>[],
  'actions': <Object?>[],
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _TemplateLoader implements PromptTemplateLoader {
  @override
  Future<PromptTemplate> load(ContextPurpose purpose) async => PromptTemplate(
    id: 'test.${purpose.name}',
    version: PromptVersion.v1,
    locale: 'en',
    intent: purpose,
    template: 'Return structured tutor output.',
    outputSchemaVersion: PromptVersion.v1,
  );
}
