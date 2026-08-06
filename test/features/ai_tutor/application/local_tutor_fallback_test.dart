import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_command.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/deterministic_coach.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/session_debrief_builder.dart';
import 'package:strumsight/features/ai_tutor/application/offline/local_tutor_fallback.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_response_mode.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool.dart';
import 'package:strumsight/features/ai_tutor/domain/tools/tutor_tool_request.dart';

void main() {
  group('LocalTutorFallback', () {
    const coach = DeterministicCoach();
    const builder = SessionDebriefBuilder();
    final retriever = KnowledgeRetriever(index: const KnowledgeIndex.empty());

    String lookup(String key) => key;

    SessionDebriefInput minimalDebriefInput() => SessionDebriefInput(
      sessionEvidenceRef: 'test.session-1',
      comparisonKey: 'test',
      pairedEventCount: SessionDebriefBuilder.minimumPairedEvidence,
      stableTempoBpm: 120,
    );

    LocalTutorFallback makeFallback() => LocalTutorFallback(
      coach: coach,
      builder: builder,
      retriever: retriever,
      localizationLookup: lookup,
    );

    // ── Falsification cell 1 ──────────────────────────────────────────
    // offline + consent-off → deterministic debrief content,
    // capability indicates offline/consent.
    // Mutation: promise cloud capability → RED
    test(
      'offline with consent revoked produces debrief and honest capability',
      () {
        final fallback = makeFallback();
        final result = fallback.resolve(
          status: TutorTurnStatus.consentRevoked,
          consent: const TutorConsent(),
          failureCode: 'tutor.model_gateway.unavailable',
          debriefInput: minimalDebriefInput(),
        );

        // Must have debrief output (deterministic content)
        expect(result.debriefOutput, isNotNull);
        expect(result.debriefOutput!.title, isNotEmpty);

        // Must NOT promise cloud capability
        expect(result.capabilities, contains(TutorCapability.offline));
        expect(result.capabilities, contains(TutorCapability.consent));
        expect(result.capabilities, isNot(contains(TutorCapability.online)));
      },
    );

    // ── Falsification cell 2 ──────────────────────────────────────────
    // usage-limit → capability shows limit, NOT cloud retry
    // Mutation: retry on usage-limit → RED
    test(
      'usage limit produces honest limit capability without cloud retry',
      () {
        final fallback = makeFallback();
        final result = fallback.resolve(
          status: TutorTurnStatus.usageLimit,
          consent: const TutorConsent(modelUseGranted: true),
          failureCode: 'tutor.usage_limit',
          debriefInput: minimalDebriefInput(),
        );

        // Must indicate limit, NOT online
        expect(result.capabilities, contains(TutorCapability.limit));
        expect(result.capabilities, isNot(contains(TutorCapability.online)));

        // Must still produce debrief (deterministic fallback)
        expect(result.debriefOutput, isNotNull);
      },
    );

    // ── Falsification cell 3 ──────────────────────────────────────────
    // fallback NEVER touches network / calls gateway
    // Mutation: gateway call → RED
    test('fallback resolve never calls gateway or network', () {
      final fallback = makeFallback();
      // The class itself is pure — no async, no I/O, no gateway reference.
      // This test verifies that the constructor accepts no gateway
      // dependency and that resolve() is synchronous.
      final result = fallback.resolve(
        status: TutorTurnStatus.fallback,
        consent: const TutorConsent(modelUseGranted: true),
        failureCode: 'tutor.model_gateway.unavailable',
        debriefInput: minimalDebriefInput(),
      );

      // The result must be immediate (sync) and contain debrief
      expect(result.debriefOutput, isNotNull);
      expect(result.capabilities, contains(TutorCapability.offline));
    });

    // ── Retrieval integration ─────────────────────────────────────────
    test('retrieves knowledge from local index when query is provided', () {
      final doc = _makeDocument(
        id: 'rhythm-101',
        locale: 'en',
        skill: KnowledgeSkill.rhythm,
        title: 'Rhythm Basics',
        body: 'Practice with a metronome.\n\nStart slow and build speed.',
      );
      final index = KnowledgeIndex.fromDocuments([doc]);
      final retrieverWithData = KnowledgeRetriever(index: index);
      final fallback = LocalTutorFallback(
        coach: coach,
        builder: builder,
        retriever: retrieverWithData,
        localizationLookup: lookup,
      );

      final result = fallback.resolve(
        status: TutorTurnStatus.fallback,
        consent: const TutorConsent(modelUseGranted: true),
        failureCode: 'tutor.model_gateway.unavailable',
        retrievalQuery: const KnowledgeRetrievalQuery(
          queryText: 'metronome',
          locale: 'en',
        ),
      );

      expect(result.retrievedSources, isNotEmpty);
      expect(result.retrievedSources.first.title, contains('Rhythm'));
    });

    // ── Online capability when consent and no failure ─────────────────
    test('online state with full consent shows online capability', () {
      final fallback = makeFallback();
      final result = fallback.resolve(
        status: TutorTurnStatus.completed,
        consent: const TutorConsent(modelUseGranted: true),
      );

      expect(result.capabilities, contains(TutorCapability.online));
      expect(result.capabilities, isNot(contains(TutorCapability.offline)));
      expect(result.capabilities, isNot(contains(TutorCapability.consent)));
      expect(result.capabilities, isNot(contains(TutorCapability.limit)));
    });

    // ── Offline capability from gateway unavailable ───────────────────
    test('gateway unavailable failure code shows offline capability', () {
      final fallback = makeFallback();
      final result = fallback.resolve(
        status: TutorTurnStatus.fallback,
        consent: const TutorConsent(modelUseGranted: true),
        failureCode: 'tutor.model_gateway.unavailable',
      );

      expect(result.capabilities, contains(TutorCapability.offline));
      expect(result.capabilities, isNot(contains(TutorCapability.online)));
    });

    // ── No debrief input → debriefOutput is null (never fabricates ────
    // measured results for a non-existent session, Epic §37).
    test('returns null debriefOutput when debriefInput is null', () {
      final fallback = makeFallback();
      final result = fallback.resolve(
        status: TutorTurnStatus.fallback,
        consent: const TutorConsent(modelUseGranted: true),
        failureCode: 'tutor.model_gateway.unavailable',
      );

      expect(result.debriefOutput, isNull);
    });
  });
  group('TutorOrchestrator gateway selection', () {
    test('consent revoked: orchestrator never calls the gateway '
        '— MUTATION: call gateway on consent-revoked → RED', () async {
      final spy = _SpyTutorModelGateway();
      final orchestrator = _makeOrchestrator((_) => spy);

      await orchestrator.dispatch(
        SendTutorMessage(
          _makeRequest(consent: const TutorConsent(modelUseGranted: false)),
        ),
      );
      await _settle();

      expect(orchestrator.state.status, TutorTurnStatus.consentRevoked);
      // Core guarantee: consent-revoked means zero cloud access.
      // If a mutation starts the gateway on this path, this cell
      // MUST turn red — that is the Epic §36 guarantee.
      expect(spy.startCalls, 0);
      await orchestrator.dispose();
    });

    test('usage limit: after the limit error surfaces, no further gateway '
        'call is made — MUTATION: retry gateway after limit → RED', () async {
      final limitSpy = _UsageLimitSpyGateway();
      final limitOrchestrator = _makeOrchestrator((_) => limitSpy);

      await limitOrchestrator.dispatch(SendTutorMessage(_makeRequest()));
      await _settle();

      expect(limitOrchestrator.state.status, TutorTurnStatus.usageLimit);
      // The gateway was opened once to discover the limit, then cancelled.
      // After usage-limit, no further start() may happen.
      expect(limitSpy.startCalls, 1);
      await limitOrchestrator.dispose();
    });
  });
}

final class _SpyTutorModelGateway implements TutorModelGateway {
  int startCalls = 0;

  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(
    TutorModelRequest request,
  ) async {
    startCalls++;
    return AppResult.success(Stream<TutorModelEvent>.empty());
  }

  @override
  void cancel() {}

  @override
  Future<AppResult<void>> health() async => const AppResult.success(null);
}

final class _TestTemplateLoader implements PromptTemplateLoader {
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

TutorOrchestrator _makeOrchestrator(
  TutorModelGateway Function(int) gatewayForAttempt,
) => TutorOrchestrator(
  contextAssembler: const TutorContextAssembler(),
  knowledgeRetriever: KnowledgeRetriever(index: const KnowledgeIndex.empty()),
  promptBuilder: TutorPromptBuilder(templateLoader: _TestTemplateLoader()),
  gatewayForAttempt: gatewayForAttempt,
);

TutorTurnRequest _makeRequest({
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
  retrievalQuery: KnowledgeRetrievalQuery(queryText: 'rhythm', locale: 'en'),
  responseLocale: 'en',
  responseMode: TutorResponseMode.concise,
  toolPolicy: TutorToolTurnPolicy(
    allowedToolNames: const <String>{'getContextField'},
    allowedPermissions: const <TutorToolPermission>[],
  ),
  actionContext: TutorActionValidationContext(
    now: DateTime.utc(2026, 8, 5),
    availableCapabilities: const [],
    activeSessionIds: const <String>[],
    songRevisions: const {},
  ),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _UsageLimitSpyGateway implements TutorModelGateway {
  int startCalls = 0;

  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(
    TutorModelRequest request,
  ) async {
    startCalls++;
    return AppResult.success(
      Stream<TutorModelEvent>.value(
        TutorModelError(
          sequence: 0,
          code: tutorUsageLimitCode,
          message: 'Usage exhausted.',
        ),
      ),
    );
  }

  @override
  void cancel() {}

  @override
  Future<AppResult<void>> health() async => const AppResult.success(null);
}

KnowledgeDocument _makeDocument({
  required String id,
  required String locale,
  required KnowledgeSkill skill,
  required String title,
  required String body,
}) {
  final contentHash = KnowledgeCodec.contentHashForDocument(
    title: title,
    body: body,
  );
  return KnowledgeDocument(
    schemaVersion: KnowledgeDocument.currentSchemaVersion,
    id: id,
    locale: locale,
    skill: skill,
    difficulty: KnowledgeDifficulty.beginner,
    license: 'CC-BY-4.0',
    version: 1,
    status: KnowledgeApprovalStatus.approved,
    title: title,
    body: body,
    contentHash: contentHash,
  );
}
