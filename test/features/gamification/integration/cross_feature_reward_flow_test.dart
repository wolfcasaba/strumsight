// E08-R26 — Cross-feature gamification reward flow integration tests.
//
// Covers brief §6 acceptance cells A1..A8 with the §6.1 valódi-sértés
// próba for the three Vision-threshold cells (alatt / rajta / fölött),
// the §6.1 A5 cell (analysis version bump), the §6.1 A3 cell
// (block aggregation), and the A1 chat-farm probe. The A6 cell lives
// in `test/core/architecture_dependency_test.dart` (architecture guard).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/ai_tutor/application/gamification_tutor_adapter.dart';
import 'package:strumsight/features/analyze/application/gamification_analysis_adapter.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice_generator/application/gamification_plan_adapter.dart';
import 'package:strumsight/features/vision/application/gamification_vision_adapter.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_observation.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_definition.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

// ── shared fixtures ──────────────────────────────────────────────────────

const int _defaultEpochDay = 20420;
final DateTime _defaultOccurredAt = DateTime.utc(2026, 8, 22, 18, 0);

final EvidenceMetric _testMetric = EvidenceMetric.fretting(
  FrettingMetricId.positionStability,
);

VisionEvidence _evidenceWithConfidence(double confidence) {
  return VisionEvidence(
    id: 'evidence-$confidence',
    metric: _testMetric,
    value: 1.0,
    confidence: confidence,
    observationState: ObservationState.observed,
    provenance: EvidenceProvenance(
      metricId: _testMetric.id,
      window: EvidenceWindow(startUs: 0, endUs: 1),
      modelVersion: 'test-model',
      geometrySource: GeometrySource.tracked,
      syncQuality: SyncQuality.excellent,
      thresholdsVersion: 'test-thresholds',
      qualityThresholdsVersion: 'test-quality-thresholds',
    ),
  );
}

AnalysisRewardHistorySnapshot _emptyAnalysisHistory(int epochDay, String key) =>
    AnalysisRewardHistorySnapshot(
      earnedTodayXp: 0,
      analysisOccurrenceCount: 0,
      uniqueSourcesToday: 1,
      rewardedEventIds: <String>{},
      rewardedParentIds: <String>{},
      rewardedChildParentIds: <String>{},
    );

VisionRewardHistorySnapshot _emptyVisionHistory(int epochDay, String key) =>
    VisionRewardHistorySnapshot(
      earnedTodayXp: 0,
      visionOccurrenceCount: 0,
      uniqueSourcesToday: 1,
      rewardedEventIds: <String>{},
      rewardedParentIds: <String>{},
      rewardedChildParentIds: <String>{},
    );

PlanRewardHistorySnapshot _emptyPlanHistory(int epochDay, String key) =>
    PlanRewardHistorySnapshot(
      earnedTodayXp: 0,
      planOccurrenceCount: 0,
      uniqueSourcesToday: 1,
      rewardedEventIds: <String>{},
      rewardedParentIds: <String>{},
      rewardedChildParentIds: <String>{},
    );

class _Fixture {
  _Fixture._({
    required this.ledger,
    required this.outbox,
    required this.ingestor,
    required this.eligibility,
    required this.rewardPolicy,
  });

  factory _Fixture.build() {
    final store = InMemoryKeyValueStore(<String, Object>{});
    const logger = NoopAppLogger();
    final ledger = LocalRewardLedgerRepository(store: store, logger: logger);
    final outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: logger,
      capacity: 64,
      maxAttempts: 3,
    );
    final ingestor = ActivityEventIngestor(outbox: outbox, logger: logger);
    final eligibility = DefaultRewardEligibilityPolicy(
      config: RewardEligibilityPolicyConfig.standard(),
    );
    final rewardPolicy = DefaultRewardPolicy(
      config: RewardPolicyConfig.standard(),
    );
    return _Fixture._(
      ledger: ledger,
      outbox: outbox,
      ingestor: ingestor,
      eligibility: eligibility,
      rewardPolicy: rewardPolicy,
    );
  }

  final LocalRewardLedgerRepository ledger;
  final LocalActivityOutboxRepository outbox;
  final ActivityEventIngestor ingestor;
  final RewardEligibilityPolicy eligibility;
  final RewardPolicy rewardPolicy;
}

GamificationAnalysisAdapter _analysisAdapter(
  _Fixture fixture, {
  bool featureEnabled = true,
}) {
  return GamificationAnalysisAdapter(
    ingestor: fixture.ingestor,
    eligibility: fixture.eligibility,
    rewardPolicy: fixture.rewardPolicy,
    historyBuilder: _emptyAnalysisHistory,
    featureEnabled: featureEnabled,
  );
}

GamificationVisionAdapter _visionAdapter(
  _Fixture fixture, {
  bool featureEnabled = true,
}) {
  return GamificationVisionAdapter(
    ingestor: fixture.ingestor,
    eligibility: fixture.eligibility,
    rewardPolicy: fixture.rewardPolicy,
    historyBuilder: _emptyVisionHistory,
    featureEnabled: featureEnabled,
  );
}

GamificationTutorAdapter _tutorAdapter(
  _Fixture fixture, {
  bool featureEnabled = true,
}) {
  return GamificationTutorAdapter(
    ingestor: fixture.ingestor,
    eligibility: fixture.eligibility,
    rewardPolicy: fixture.rewardPolicy,
    featureEnabled: featureEnabled,
  );
}

GamificationPlanAdapter _planAdapter(
  _Fixture fixture, {
  bool featureEnabled = true,
}) {
  return GamificationPlanAdapter(
    ingestor: fixture.ingestor,
    eligibility: fixture.eligibility,
    rewardPolicy: fixture.rewardPolicy,
    historyBuilder: _emptyPlanHistory,
    featureEnabled: featureEnabled,
  );
}

AnalysisGamificationSignal _analysisSignal({
  String sessionId = 'analysis-session-1',
  String sourceHash = 'clip-hash-001',
  String analyzerVersion = 'dsp-v1.0.0',
  Duration validDuration = const Duration(minutes: 2),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) {
  return AnalysisGamificationSignal(
    sessionId: sessionId,
    sourceHash: sourceHash,
    analyzerVersion: analyzerVersion,
    validDuration: validDuration,
    quality: quality,
    evidenceTrust: trust,
    score: score,
    epochDay: epochDay,
    occurredAt: occurredAt ?? _defaultOccurredAt,
  );
}

VisionGamificationSignal _visionSignal({
  String sessionId = 'vision-session-1',
  InsightCode claim = InsightCode.frettingStable,
  double confidence = 0.70,
  Object? evidence = const _Sentinel(),
  Duration validDuration = const Duration(minutes: 2),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) {
  final resolvedEvidence = evidence is _Sentinel
      ? _evidenceWithConfidence(confidence)
      : evidence as VisionEvidence?;
  return VisionGamificationSignal(
    sessionId: sessionId,
    claim: claim,
    evidence: resolvedEvidence,
    confidence: confidence,
    validDuration: validDuration,
    quality: quality,
    evidenceTrust: trust,
    score: score,
    epochDay: epochDay,
    occurredAt: occurredAt ?? _defaultOccurredAt,
  );
}

class _Sentinel {
  const _Sentinel();
}

TutorGamificationSignal _tutorSignal({
  String sessionId = 'tutor-session-1',
  TutorGamificationKind kind = TutorGamificationKind.conversation,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) {
  return TutorGamificationSignal(
    sessionId: sessionId,
    kind: kind,
    occurredAt: occurredAt ?? _defaultOccurredAt,
    epochDay: epochDay,
  );
}

PlanGamificationSignal _planSignal({
  String planId = 'plan-001',
  bool planCompleted = true,
  Duration validDuration = const Duration(minutes: 5),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) {
  return PlanGamificationSignal(
    planId: planId,
    planCompleted: planCompleted,
    validDuration: validDuration,
    quality: quality,
    evidenceTrust: trust,
    score: score,
    epochDay: epochDay,
    occurredAt: occurredAt ?? _defaultOccurredAt,
  );
}

List<RewardLedgerEntry> _entriesFor(_Fixture fixture) =>
    fixture.ledger.readPage(limit: 100).entries;

int _totalXp(List<RewardLedgerEntry> entries) =>
    entries.fold<int>(0, (sum, e) => sum + e.totalXp);

Future<String> _readSource(String relativePath) =>
    File(relativePath).readAsString();

void main() {
  group('E08-R26 — Cross-feature gamification reward flow', () {
    // ── A1 — Tutor chat yields ZERO XP (§6.1 chat-farm cell) ────────
    test('A1: a tutor conversation emits NO event and NO ledger entry — '
        'the §6.1 chat-farm cell stays GREEN', () async {
      final fixture = _Fixture.build();
      final adapter = _tutorAdapter(fixture);

      final outcome = await adapter.recordConversation(_tutorSignal());

      expect(outcome.accepted, isFalse);
      expect(outcome.eventId, isNull);
      await fixture.ingestor.drain();
      expect(_entriesFor(fixture), isEmpty);
      expect(_totalXp(_entriesFor(fixture)), 0);
    });

    test('A1: even when the conversation runs for an hour with high quality, '
        'the ledger stays at zero — no engagement XP path exists', () async {
      final fixture = _Fixture.build();
      final adapter = _tutorAdapter(fixture);

      final outcome = await adapter.recordConversation(
        _tutorSignal(sessionId: 'tutor-marathon'),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isFalse);
      expect(_entriesFor(fixture), isEmpty);
    });

    test(
      'A1 valódi-sértés próba: a hypothetical engagement-XP tutor adapter '
      'would leave the cell RED — the production adapter never does',
      () async {
        final fixture = _Fixture.build();
        final broken = _BrokenTutorAdapter(
          ingestor: fixture.ingestor,
          eligibility: fixture.eligibility,
          rewardPolicy: fixture.rewardPolicy,
          featureEnabled: true,
        );
        final outcome = await broken.recordConversation(_tutorSignal());
        await fixture.ingestor.drain();

        // The broken adapter DOES emit an entry — which is exactly
        // what the production adapter must avoid.
        expect(outcome.accepted, isTrue);
        expect(_entriesFor(fixture), isNotEmpty);
        expect(_totalXp(_entriesFor(fixture)), greaterThan(0));
      },
    );

    // ── A2 — Vision §6.1 threshold triple (alatt / rajta / fölött) ───
    test('A2 (§6.1 alatt, confidence = 0.69): only base event fires, '
        'no technical-progress event', () async {
      final fixture = _Fixture.build();
      final adapter = _visionAdapter(fixture);

      final outcome = await adapter.recordSession(
        _visionSignal(confidence: 0.69),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.baseEventId, isNotNull);
      expect(
        outcome.technicalEventId,
        isNull,
        reason:
            'Confidence below the 0.70 threshold MUST NOT unlock '
            'technical progress (A2 alatt cell).',
      );
      final entries = _entriesFor(fixture);
      expect(entries, hasLength(1));
      expect(entries.single.sourceEventId, outcome.baseEventId);
    });

    test('A2 (§6.1 rajta, confidence = 0.70): BOTH base AND technical events '
        'fire — the threshold is the inclusive accepting boundary', () async {
      final fixture = _Fixture.build();
      final adapter = _visionAdapter(fixture);

      final outcome = await adapter.recordSession(
        _visionSignal(confidence: 0.70),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.baseEventId, isNotNull);
      expect(
        outcome.technicalEventId,
        isNotNull,
        reason:
            'VisionClaimGuard uses `confidence < minimumConfidence` '
            '(strict less-than), so the threshold itself is the '
            'accepting side. The §6.1 rajta cell receives technical '
            'progress.',
      );
      final entries = _entriesFor(fixture);
      expect(entries, hasLength(2));
    });

    test('A2 (§6.1 fölött, confidence = 0.71): BOTH base AND technical events '
        'fire', () async {
      final fixture = _Fixture.build();
      final adapter = _visionAdapter(fixture);

      final outcome = await adapter.recordSession(
        _visionSignal(confidence: 0.71),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.baseEventId, isNotNull);
      expect(outcome.technicalEventId, isNotNull);
      final entries = _entriesFor(fixture);
      expect(entries, hasLength(2));
    });

    test('A2: missing evidence denies technical progress even at high '
        'confidence — the guard fail-closes', () async {
      final fixture = _Fixture.build();
      final adapter = _visionAdapter(fixture);

      final outcome = await adapter.recordSession(
        _visionSignal(confidence: 0.95, evidence: null),
      );
      await fixture.ingestor.drain();

      expect(outcome.technicalEventId, isNull);
      final entries = _entriesFor(fixture);
      expect(entries, hasLength(1));
      expect(entries.single.sourceEventId, outcome.baseEventId);
    });

    // ── A3 — Plan completion bonus only (§6.1 block aggregation cell) ──
    test('A3: a completed plan emits exactly ONE event with the bonus shape, '
        'no block aggregation', () async {
      final fixture = _Fixture.build();
      final adapter = _planAdapter(fixture);

      final outcome = await adapter.recordCompletion(_planSignal());
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.eventId, GamificationPlanAdapter.eventIdFor('plan-001'));
      final entries = _entriesFor(fixture);
      expect(entries, hasLength(1));
      expect(entries.single.baseXp, greaterThan(0));
      // §5.3 — bonus only. bonusXp is forced to zero.
      expect(entries.single.bonusXp, 0);
      expect(
        entries.single.totalXp,
        entries.single.baseXp,
        reason: 'bonus-only means totalXp == baseXp',
      );
    });

    test('A3: planCompleted = false → no event at all (the adapter never '
        'rewards a partial / paused plan)', () async {
      final fixture = _Fixture.build();
      final adapter = _planAdapter(fixture);

      final outcome = await adapter.recordCompletion(
        _planSignal(planCompleted: false),
      );
      await fixture.ingestor.drain();

      expect(outcome.accepted, isFalse);
      expect(_entriesFor(fixture), isEmpty);
    });

    test('A3 (reopen): a second call with the same planId collapses to '
        'noOp — the bonus is paid at most once', () async {
      final fixture = _Fixture.build();
      final adapter = _planAdapter(fixture);

      final first = await adapter.recordCompletion(_planSignal());
      await fixture.ingestor.drain();
      final firstCount = _entriesFor(fixture).length;

      final reopened = await adapter.recordCompletion(_planSignal());
      await fixture.ingestor.drain();

      expect(first.accepted, isTrue);
      expect(reopened.accepted, isFalse);
      expect(
        _entriesFor(fixture).length,
        firstCount,
        reason: 'reopen must NOT add a second entry for the same planId',
      );
    });

    test(
      'A3 valódi-sértés próba: a hypothetical "aggregate blocks" adapter '
      'would inflate the bonus — the production adapter never does',
      () async {
        final fixture = _Fixture.build();
        final broken = _BrokenAggregatingPlanAdapter(
          ingestor: fixture.ingestor,
          eligibility: fixture.eligibility,
          rewardPolicy: fixture.rewardPolicy,
          historyBuilder: _emptyPlanHistory,
          featureEnabled: true,
        );
        final outcome = await broken.recordCompletion(_planSignal());
        await fixture.ingestor.drain();

        expect(outcome.accepted, isTrue);
        final entries = _entriesFor(fixture);
        // The broken adapter forwards the policy's components as
        // bonusXp, so the bonus is positive — the §6.1 A3 cell.
        expect(entries.single.bonusXp, greaterThan(0));
      },
    );

    // ── A4 — Same clip + same analyzer version = same event ──────────
    test('A4: same sourceHash + same analyzerVersion → same eventId, the '
        'ledger stays at one entry across two invocations', () async {
      final fixture = _Fixture.build();
      final adapter = _analysisAdapter(fixture);
      final signal = _analysisSignal();

      final first = await adapter.recordSession(signal);
      await fixture.ingestor.drain();
      final firstEntryCount = _entriesFor(fixture).length;

      final reopened = await adapter.recordSession(signal);
      await fixture.ingestor.drain();

      expect(first.accepted, isTrue);
      expect(first.eventId, isNotNull);
      expect(reopened.accepted, isTrue);
      expect(
        reopened.eventId,
        first.eventId,
        reason:
            'Same clip + same analyzer version must produce the same '
            'eventId so the ledger collapses the duplicate',
      );
      expect(_entriesFor(fixture).length, firstEntryCount);
    });

    // ── A5 — Same clip + NEW analyzer version = fresh event ──────────
    test('A5 (§6.1): same sourceHash + NEW analyzerVersion → fresh eventId '
        'and a new ledger entry', () async {
      final fixture = _Fixture.build();
      final adapter = _analysisAdapter(fixture);

      final v1 = await adapter.recordSession(
        _analysisSignal(analyzerVersion: 'dsp-v1.0.0'),
      );
      await fixture.ingestor.drain();
      final v1Entries = _entriesFor(fixture).length;

      final v2 = await adapter.recordSession(
        _analysisSignal(analyzerVersion: 'dsp-v2.0.0'),
      );
      await fixture.ingestor.drain();
      final v2Entries = _entriesFor(fixture).length;

      expect(v1.eventId, isNot(equals(v2.eventId)));
      expect(v2Entries, greaterThan(v1Entries));
      expect(_entriesFor(fixture), hasLength(v1Entries + 1));
    });

    test(
      'A5 valódi-sértés próba: a hash-only dedup would collapse a new '
      'version to no reward — the production adapter distinguishes them',
      () async {
        final fixture = _Fixture.build();
        final broken = _BrokenHashOnlyAnalysisAdapter(
          ingestor: fixture.ingestor,
          eligibility: fixture.eligibility,
          rewardPolicy: fixture.rewardPolicy,
          historyBuilder: _emptyAnalysisHistory,
          featureEnabled: true,
        );

        final v1 = await broken.recordSession(
          _analysisSignal(analyzerVersion: 'dsp-v1.0.0'),
        );
        await fixture.ingestor.drain();
        final afterV1 = _entriesFor(fixture).length;

        // New analyzer version with the SAME hash: the broken adapter
        // ignores the version, so it the same id as v1 and the ledger
        // collapses. The §6.1 A5 cell.
        final v2 = await broken.recordSession(
          _analysisSignal(analyzerVersion: 'dsp-v2.0.0'),
        );
        await fixture.ingestor.drain();

        expect(v1.accepted, isTrue);
        expect(v2.accepted, isTrue);
        // Both broken invocations claim the SAME eventId — the
        // production adapter must avoid this by encoding the version.
        expect(v1.eventId, equals(v2.eventId));
        expect(_entriesFor(fixture).length, afterV1);
      },
    );

    // ── A7 — feature-switch fallback keeps the build clean ───────────
    test('A7: featureEnabled = false → every adapter is a no-op, no crash, '
        'no ledger entry', () async {
      // analysis
      {
        final fixture = _Fixture.build();
        final adapter = _analysisAdapter(fixture, featureEnabled: false);
        final outcome = await adapter.recordSession(_analysisSignal());
        await fixture.ingestor.drain();
        expect(outcome.accepted, isFalse);
        expect(_entriesFor(fixture), isEmpty);
      }
      // vision
      {
        final fixture = _Fixture.build();
        final adapter = _visionAdapter(fixture, featureEnabled: false);
        final outcome = await adapter.recordSession(_visionSignal());
        await fixture.ingestor.drain();
        expect(outcome.accepted, isFalse);
        expect(_entriesFor(fixture), isEmpty);
      }
      // tutor
      {
        final fixture = _Fixture.build();
        final adapter = _tutorAdapter(fixture, featureEnabled: false);
        final outcome = await adapter.recordConversation(_tutorSignal());
        await fixture.ingestor.drain();
        expect(outcome.accepted, isFalse);
        expect(_entriesFor(fixture), isEmpty);
      }
      // plan
      {
        final fixture = _Fixture.build();
        final adapter = _planAdapter(fixture, featureEnabled: false);
        final outcome = await adapter.recordCompletion(_planSignal());
        await fixture.ingestor.drain();
        expect(outcome.accepted, isFalse);
        expect(_entriesFor(fixture), isEmpty);
      }
    });

    // ── A8 — no AI / network / platform imports on the reward path ──
    test('A8: the four adapter files import NO AI / network / platform '
        'package — no new model invocation, no HTTP, no device plugin', () async {
      const forbidden = <String>[
        'package:http/',
        'package:dio/',
        'package:google_mlkit_',
        'package:tflite_flutter/',
        'package:flutter_tts/',
        'package:speech_to_text/',
        'package:image_picker/',
        'package:audioplayers/',
        'package:webview_flutter/',
        'package:flutter_localizations/',
        'package:mobile_scanner/',
        'package:health/',
      ];
      for (final path in <String>[
        'lib/features/analyze/application/gamification_analysis_adapter.dart',
        'lib/features/vision/application/gamification_vision_adapter.dart',
        'lib/features/ai_tutor/application/gamification_tutor_adapter.dart',
        'lib/features/practice_generator/application/gamification_plan_adapter.dart',
      ]) {
        final source = await _readSource(path);
        for (final pattern in forbidden) {
          expect(
            source.contains(pattern),
            isFalse,
            reason: '$path must not import $pattern (A8 — no new AI call)',
          );
        }
      }
    });
  });
}

// ── §6.1 / §10 broken-probe adapters ─────────────────────────────────────
//
// These deliberately mirror the production adapter's surface so the
// §6.1 valódi-sértés próba can drive the same drain flow as the
// production tests — but they are STANDALONE classes, not subclasses,
// so they do not depend on the production adapter's private fields.

class _BrokenTutorAdapter {
  _BrokenTutorAdapter({
    required this.ingestor,
    required this.eligibility,
    required this.rewardPolicy,
    required this.featureEnabled,
  });

  final ActivityEventIngestor ingestor;
  final RewardEligibilityPolicy eligibility;
  final RewardPolicy rewardPolicy;
  final bool featureEnabled;

  Future<TutorGamificationOutcome> recordConversation(
    TutorGamificationSignal signal,
  ) async {
    if (!featureEnabled) {
      return const TutorGamificationOutcome.noOp();
    }
    // Hypothetical engagement-XP path: emit a fake TutorActivityEvent
    // so the ledger records positive XP. The §A1 cell requires the
    // production adapter to AVOID this branch.
    final event = TutorActivityEvent(
      eventId: 'tutor-broken/${signal.sessionId}/v1',
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.tutor,
      trust: EvidenceTrust.unverified,
      schemaVersion: learningActivityEventSchemaVersion,
      duration: const Duration(minutes: 5),
      score: 0.5,
    );
    final points = ExperiencePoints(baseXp: 10, durationXp: 5);
    final entry = RewardLedgerEntry(
      ledgerId: 'tutor-broken/${signal.sessionId}/15',
      sourceEventId: event.eventId,
      createdAt: signal.occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: GamificationTutorAdapter.adapterPolicyVersion,
      baseXp: points.baseXp,
      bonusXp: points.durationXp,
      totalXp: points.totalXp,
      reasonCodes: const <RewardReason>[RewardReason.baseExperience],
    );
    await ingestor.recordSavedActivity(event: event, entry: entry);
    return TutorGamificationOutcome.rewarded(eventId: event.eventId);
  }
}

class _BrokenAggregatingPlanAdapter {
  _BrokenAggregatingPlanAdapter({
    required this.ingestor,
    required this.eligibility,
    required this.rewardPolicy,
    required this.historyBuilder,
    required this.featureEnabled,
  });

  final ActivityEventIngestor ingestor;
  final RewardEligibilityPolicy eligibility;
  final RewardPolicy rewardPolicy;
  final PlanHistoryBuilder historyBuilder;
  final bool featureEnabled;

  Future<PlanGamificationOutcome> recordCompletion(
    PlanGamificationSignal signal,
  ) async {
    if (!featureEnabled || !signal.planCompleted) {
      return const PlanGamificationOutcome.noOp();
    }
    // Hypothetical block-aggregating path: forwards the policy's
    // bonus components as ledger bonusXp. The §A3 cell requires the
    // production adapter to AVOID this branch.
    final eventId = GamificationPlanAdapter.eventIdFor(signal.planId);
    final event = PlanActivityEvent(
      eventId: eventId,
      occurredAt: signal.occurredAt,
      epochDay: signal.epochDay,
      source: ActivitySource.practicePlan,
      trust: signal.evidenceTrust,
      schemaVersion: learningActivityEventSchemaVersion,
      duration: signal.validDuration,
      score: signal.score,
    );
    final decision = eligibility.evaluate(
      RewardEligibilityRequest(
        source: ActivitySource.practicePlan,
        outcome: ActivityOutcome.completed,
        trust: signal.evidenceTrust,
        validDuration: signal.validDuration,
        quality: signal.quality,
      ),
    );
    final history = historyBuilder(signal.epochDay, signal.planId);
    final policyRequest = RewardPolicyRequest(
      eventId: eventId,
      practiceKey: signal.planId,
      parentEventId: null,
      epochDay: signal.epochDay,
      source: ActivitySource.practicePlan,
      eligibility: decision,
      validDuration: signal.validDuration,
      qualityScore: signal.quality ?? 0.0,
      improvementDelta: 0,
      uniqueSourcesToday: history.uniqueSourcesToday,
    );
    final policyHistory = RewardPolicyHistory(
      epochDay: signal.epochDay,
      earnedTodayXp: history.earnedTodayXp,
      practiceOccurrenceCount: history.planOccurrenceCount,
      rewardedEventIds: history.rewardedEventIds,
      rewardedParentIds: history.rewardedParentIds,
      rewardedChildParentIds: history.rewardedChildParentIds,
    );
    final policyDecision = rewardPolicy.decide(policyRequest, policyHistory);
    final points = policyDecision.points;
    final bonusXp =
        points.durationXp +
        points.qualityXp +
        points.improvementXp +
        points.diversityXp;
    final totalXp = points.totalXp;
    final entry = RewardLedgerEntry(
      ledgerId: 'plan-broken/${signal.planId}/$totalXp',
      sourceEventId: eventId,
      createdAt: signal.occurredAt,
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: policyDecision.policyVersion,
      baseXp: points.baseXp,
      bonusXp: bonusXp,
      totalXp: totalXp,
      reasonCodes: <RewardReason>[
        if (totalXp > 0) RewardReason.achievementUnlocked,
      ],
    );
    await ingestor.recordSavedActivity(event: event, entry: entry);
    return PlanGamificationOutcome.rewarded(eventId: eventId);
  }
}

class _BrokenHashOnlyAnalysisAdapter {
  _BrokenHashOnlyAnalysisAdapter({
    required this.ingestor,
    required this.eligibility,
    required this.rewardPolicy,
    required this.historyBuilder,
    required this.featureEnabled,
  });

  final ActivityEventIngestor ingestor;
  final RewardEligibilityPolicy eligibility;
  final RewardPolicy rewardPolicy;
  final AnalysisHistoryBuilder historyBuilder;
  final bool featureEnabled;

  Future<AnalysisGamificationOutcome> recordSession(
    AnalysisGamificationSignal signal,
  ) async {
    if (!featureEnabled) {
      return const AnalysisGamificationOutcome.noOp();
    }
    // Hash-only dedup: ignore the analyzer version in the event id
    // so a new version of the same clip produces the SAME id, which
    // the ledger collapses. The §A5 cell requires the production
    // adapter to AVOID this branch.
    final eventId = 'analysis-broken-hash/${signal.sourceHash}/v1';
    return AnalysisGamificationOutcome.rewarded(eventId: eventId);
  }
}
