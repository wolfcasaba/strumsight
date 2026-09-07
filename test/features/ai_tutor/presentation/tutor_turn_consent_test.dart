// R9 — the consent gate on the tutor REQUEST path.
//
// Before this round the only production `TutorTurnRequest` builder hardcoded
// `consent: const TutorConsent(modelUseGranted: true)`, so a revocation the
// privacy screen wrote into `tutorConsentControllerProvider` was a value
// nothing in `lib/**` ever read back into a turn (data-inventory MAJOR-3).
// These cells measure the PRODUCTION provider wiring — the real
// `tutorChatControllerProvider` over a real `TutorOrchestrator` — not a
// screen render, and count how often the gateway factory is invoked, which
// is the last observable point before anything could leave the device.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_command.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';

import '../../../support/preference_store.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('buildTutorTurnRequest — the production request producer', () {
    test('granted consent produces a request carrying that consent', () {
      final result = buildTutorTurnRequest(
        message: 'How do I clean up my chord changes?',
        consent: const TutorConsent(modelUseGranted: true),
      );

      expect(result, isA<Success<TutorTurnRequest>>());
      final request = result.valueOrNull!;
      expect(request.message, 'How do I clean up my chord changes?');
      expect(request.consent.modelUseGranted, isTrue);
    });

    test('absent consent refuses with a typed failure and no request', () {
      final result = buildTutorTurnRequest(
        message: 'How do I clean up my chord changes?',
        consent: const TutorConsent(),
      );

      expect(result, isA<Failure<TutorTurnRequest>>());
      expect(result.failureOrNull?.code, tutorModelUseConsentMissingCode);
      expect(result.valueOrNull, isNull);
    });

    test('revoking only model use still refuses, other axes untouched', () {
      const consent = TutorConsent(
        persistentStorageGranted: true,
        evaluationWithRedactionGranted: true,
      );

      final result = buildTutorTurnRequest(message: 'x', consent: consent);

      expect(result.failureOrNull?.code, tutorModelUseConsentMissingCode);
    });
  });

  group('tutorChatControllerProvider — consent is read on the send path', () {
    test('a send without model-use consent creates NO gateway and surfaces '
        'the typed refusal', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      final controller = harness.controller;
      controller.setDraft('Should I use a metronome?');
      controller.send();
      await _settle();

      expect(
        harness.gatewayCalls,
        0,
        reason:
            'a refused request must never reach the orchestrator, so the '
            'gateway factory is not invoked even once',
      );
      expect(controller.status, TutorTurnStatus.consentRevoked);
      expect(controller.banners, contains(TutorBannerKind.consent));
      expect(harness.lastState?.failureCode, tutorModelUseConsentMissingCode);
      expect(
        controller.draft,
        'Should I use a metronome?',
        reason: 'the refused text is kept so the student can resend it',
      );
      expect(controller.messages, isEmpty);
    });

    test('granting consent lets the same controller send, and revoking '
        'mid-session refuses the NEXT turn with no rebuild', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      harness.container
          .read(tutorConsentControllerProvider.notifier)
          .grantModelUse();

      final controller = harness.controller;
      controller.setDraft('Turn one');
      controller.send();
      await _settle();

      expect(harness.gatewayCalls, 1);
      expect(controller.messages, hasLength(1));

      // The student revokes model use in the privacy screen — same
      // container, same controller instance, no restart.
      harness.container
          .read(tutorConsentControllerProvider.notifier)
          .revokeModelUse();

      controller.setDraft('Turn two');
      controller.send();
      await _settle();

      expect(
        harness.gatewayCalls,
        1,
        reason:
            'the post-revocation turn must not create a second gateway — '
            'the producer re-reads the live consent on every send',
      );
      expect(controller.status, TutorTurnStatus.consentRevoked);
      expect(harness.lastState?.failureCode, tutorModelUseConsentMissingCode);
      expect(
        controller.messages,
        hasLength(1),
        reason: 'the refused second message is never appended as sent',
      );
    });
  });
}

/// The real production provider graph with only the two boot seams
/// overridden — the controller under test is the one the app builds.
final class _Harness {
  _Harness() {
    orchestrator = _orchestrator();
    container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        tutorOrchestratorProvider.overrideWithValue(orchestrator),
        tutorConversationRepositoryProvider.overrideWithValue(
          LocalTutorConversationRepository(
            keyValueStore: InMemoryKeyValueStore(),
          ),
        ),
      ],
    );
    controller = container.read(tutorChatControllerProvider);
    _subscription = controller.states.listen((state) => lastState = state);
  }

  late final TutorOrchestrator orchestrator;
  late final ProviderContainer container;
  late final TutorChatController controller;
  late final StreamSubscription<TutorChatState> _subscription;

  int gatewayCalls = 0;
  TutorChatState? lastState;

  TutorOrchestrator _orchestrator() => TutorOrchestrator(
    contextAssembler: const TutorContextAssembler(),
    knowledgeRetriever: KnowledgeRetriever(index: const KnowledgeIndex.empty()),
    promptBuilder: TutorPromptBuilder(templateLoader: _TemplateLoader()),
    gatewayForAttempt: _gateway,
  );

  TutorModelGateway _gateway(int attempt) {
    gatewayCalls++;
    return FakeTutorModelGateway(
      script: <FakeGatewayStep>[
        FakeGatewayDelta(_validOutput(), sequence: 1),
        const FakeGatewayDone(sequence: 2),
      ],
    );
  }

  void dispose() {
    unawaited(_subscription.cancel());
    container.dispose();
    unawaited(orchestrator.dispose());
  }
}

String _validOutput() => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[],
  'claims': <Object?>[],
  'actions': <Object?>[],
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});

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
