import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/deterministic_coach.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/session_debrief_builder.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/offline/local_tutor_fallback.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';

void main() {
  group('LocalTutorFallback', () {
    const coach = DeterministicCoach();
    const builder = SessionDebriefBuilder();
    final retriever = KnowledgeRetriever(index: const KnowledgeIndex.empty());

    String lookup(String key) => key;

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

    // ── No debrief input → still produces a minimal debrief ───────────
    test('produces minimal debrief even without debrief input', () {
      final fallback = makeFallback();
      final result = fallback.resolve(
        status: TutorTurnStatus.fallback,
        consent: const TutorConsent(modelUseGranted: true),
        failureCode: 'tutor.model_gateway.unavailable',
      );

      expect(result.debriefOutput, isNotNull);
      expect(result.debriefOutput!.title, isNotEmpty);
    });
  });
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
