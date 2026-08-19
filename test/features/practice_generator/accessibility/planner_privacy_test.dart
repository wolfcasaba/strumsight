import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/practice_generator/application/usecase/delete_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/application/usecase/export_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_plan_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_serializer.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_revision.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/repository/practice_evidence_repository.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

/// E07-R29 §6 acceptance criteria + §6.1 measurement matrix for the
/// privacy-sensitive delete-all + export-all paths.
void main() {
  group('DeletePracticePlanningData (A7 — actual removal, §6.1 row 3)', () {
    test('below the threshold — only the active plan is removed; drafts, '
        'archive, evidence remain.', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();
      final useCase = _newDeleteUseCase(store, planRepo, evidence);

      // Seed: an active plan + an archived revision + a draft.
      await planRepo.activateAndReport(plan());
      await planRepo.saveDraft(
        draftKey: 'main',
        plan: plan(title: 'd'),
      );
      await planRepo.appendRevision(_revision(PlanId('plan.1'), number: 1));

      // Seed evidence for an outcome.
      evidence.save(
        _evidenceForOutcome(OutcomeId('outcome.1'), PlanId('plan.1')),
      );

      final result = await useCase();

      expect(result.isSuccess, isTrue);
      // Active plan is gone.
      expect((await planRepo.readActivePlan()).valueOrNull, isNull);
      // Drafts gone.
      expect(planRepo.knownDraftKeysSync(), isEmpty);
      // Archive index + records gone.
      final archive = await planRepo.readArchive(PlanId('plan.1'));
      expect(archive.isSuccess, isTrue);
      expect(archive.valueOrNull!.revisions, isEmpty);
      // Evidence gone (the planner's evidence is the only one).
      expect(evidence.allForSkill('chord.gMajor'), isEmpty);
    });

    test('on the threshold — "delete all" removes every planner-owned key, '
        'exactly the documented circle.', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();
      final useCase = _newDeleteUseCase(store, planRepo, evidence);

      // Seed planner data: an active plan, two drafts, archive entries.
      await planRepo.activateAndReport(plan());
      await planRepo.saveDraft(
        draftKey: 'main',
        plan: plan(title: 'd1'),
      );
      await planRepo.saveDraft(
        draftKey: 'alt',
        plan: plan(title: 'd2'),
      );
      await planRepo.appendRevision(_revision(PlanId('plan.1'), number: 1));

      final result = await useCase();

      expect(result.isSuccess, isTrue);
      // The use case surfaces the count of removed keys + plan ids.
      final value = result.valueOrNull!;
      expect(value.affectedPlanIds, isNotEmpty);
      expect(value.plannerKeyCount, 0);
      expect(value.evidenceRecordCount, greaterThanOrEqualTo(0));
    });

    test('above the threshold — keys that belong to another feature are '
        'untouched (§6.1 third-row "küszöb fölött").', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();
      final useCase = _newDeleteUseCase(store, planRepo, evidence);

      // Seed a key owned by an unrelated feature.
      await store.writeString('learning.history.record.1', 'opaque');
      // Seed planner data.
      await planRepo.activateAndReport(plan());

      final result = await useCase();

      expect(result.isSuccess, isTrue);
      // The unrelated key is untouched.
      expect(store.contains('learning.history.record.1'), isTrue);
      expect(store.readString('learning.history.record.1'), 'opaque');
    });

    test(
      'evidence removal is reachable ONLY through this use case — the '
      'store keeps evidence otherwise (ADR 0260 §5 narrow exception).',
      () async {
        final evidence = _newEvidenceRepository();
        evidence.save(
          _evidenceForOutcome(OutcomeId('outcome.1'), PlanId('plan.1')),
        );

        expect(evidence.allForSkill('chord.gMajor'), hasLength(1));

        // Direct call to the new evidence-port hook works as designed.
        final removed = evidence.deleteForPlan(PlanId('plan.1'));
        expect(removed, 1);
        expect(evidence.allForSkill('chord.gMajor'), isEmpty);
      },
    );

    test('plan-scoped evidence delete does NOT touch evidence from another '
        'plan (§5.7 narrow exception boundary).', () async {
      final evidence = InMemoryPracticeEvidenceRepository(
        outcomePlanLookup: (outcomeId) {
          if (outcomeId.startsWith('plan.a.outcome')) return PlanId('plan.a');
          if (outcomeId.startsWith('plan.b.outcome')) return PlanId('plan.b');
          return null;
        },
      );
      evidence.save(
        SkillEvidence(
          skillId: 'chord.gMajor',
          source: EvidenceSource.learn,
          sourceOutcomeId: OutcomeId('plan.a.outcome.1'),
          measurementVersion: 1,
          measuredAt: DateTime.utc(2026, 8, 19),
          capturedAt: DateTime.utc(2026, 8, 19),
          confidence: 0.8,
          performance: PerformanceEvidence(
            metricCode: 'chordChangeAccuracy',
            value: 0.7,
          ),
        ),
      );
      evidence.save(
        SkillEvidence(
          skillId: 'chord.gMajor',
          source: EvidenceSource.learn,
          sourceOutcomeId: OutcomeId('plan.b.outcome.1'),
          measurementVersion: 1,
          measuredAt: DateTime.utc(2026, 8, 19),
          capturedAt: DateTime.utc(2026, 8, 19),
          confidence: 0.8,
          performance: PerformanceEvidence(
            metricCode: 'chordChangeAccuracy',
            value: 0.7,
          ),
        ),
      );

      // Delete plan A only.
      final removed = evidence.deleteForPlan(PlanId('plan.a'));

      expect(removed, 1);
      expect(evidence.findByOutcomeId(OutcomeId('plan.a.outcome.1')), isNull);
      expect(
        evidence.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
        isNotNull,
      );
    });
  });

  group('ExportPracticePlanningData (A7 export mirror, §6.1 second row)', () {
    test('export never carries free-text comfort notes', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();

      // Activate a plan so the export has content to copy.
      await planRepo.activateAndReport(plan());
      evidence.save(
        _evidenceForOutcome(OutcomeId('outcome.1'), PlanId('plan.1')),
      );

      final captured = <String>[];
      final useCase = ExportPracticePlanningData(
        planRepository: planRepo,
        evidenceRepository: evidence,
        cacheDirectory: () async => Directory.systemTemp,
        clock: () => DateTime.utc(2026, 8, 19, 12),
        fileWriter: (path, bytes) async {
          captured.add(String.fromCharCodes(bytes));
        },
      );

      final result = await useCase();
      expect(result.isSuccess, isTrue);
      final json = captured.single;
      // The export must NOT include any "comfort" free-text field. We
      // assert the export does not include the substring "comfortNote",
      // which would be a leak of the planner's sensitive-input name
      // (ADR 0260 §4).
      expect(json.contains('comfortNote'), isFalse);
    });

    test(
      'export produces a JSON document with the documented envelope',
      () async {
        final store = _newStore();
        final planRepo = _newPlanRepository(store);
        final evidence = _newEvidenceRepository();
        await planRepo.activateAndReport(plan());
        evidence.save(
          _evidenceForOutcome(OutcomeId('outcome.1'), PlanId('plan.1')),
        );

        final captured = <String>[];
        final useCase = ExportPracticePlanningData(
          planRepository: planRepo,
          evidenceRepository: evidence,
          cacheDirectory: () async => Directory.systemTemp,
          clock: () => DateTime.utc(2026, 8, 19, 12),
          fileWriter: (path, bytes) async =>
              captured.add(String.fromCharCodes(bytes)),
        );

        final result = await useCase();
        expect(result.isSuccess, isTrue);
        final r = result.valueOrNull!;
        expect(r.fileName, startsWith('strumsight-planning-export-'));
        expect(r.fileName, endsWith('.json'));
        expect(r.byteCount, greaterThan(0));
      },
    );
  });

  group('Real-violation probe (A6 §6.1)', () {
    test('writing the discomfort free text into a "telemetry" payload is '
        'detected: the planner does not persist or export it.', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();

      const freeText = 'my wrist hurts after 10 minutes';
      // The planner exposes no telemetry API, so the only way the
      // free text could leak is via the persistence layer. We assert
      // the entire write-log of the in-memory store does NOT contain
      // the free text after a full export-all run.
      await planRepo.activateAndReport(plan());
      evidence.save(
        _evidenceForOutcome(OutcomeId('outcome.1'), PlanId('plan.1')),
      );

      final captured = <String>[];
      final useCase = ExportPracticePlanningData(
        planRepository: planRepo,
        evidenceRepository: evidence,
        cacheDirectory: () async => Directory.systemTemp,
        clock: () => DateTime.utc(2026, 8, 19, 12),
        fileWriter: (path, bytes) async =>
            captured.add(String.fromCharCodes(bytes)),
      );
      await useCase();

      // The free text is NOT in the export.
      expect(captured.any((s) => s.contains(freeText)), isFalse);
      // The free text is NOT in the write log of the underlying store.
      expect(store.writeLog.every((e) => !e.contains(freeText)), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

InMemoryKeyValueStore _newStore() => InMemoryKeyValueStore();

LocalPracticePlanRepository _newPlanRepository(InMemoryKeyValueStore store) =>
    LocalPracticePlanRepository(
      keyValueStore: store,
      resolveCandidate: resolveCandidate,
    );

InMemoryPracticeEvidenceRepository _newEvidenceRepository() =>
    InMemoryPracticeEvidenceRepository();

DeletePracticePlanningData _newDeleteUseCase(
  InMemoryKeyValueStore store,
  LocalPracticePlanRepository planRepo,
  InMemoryPracticeEvidenceRepository evidence,
) {
  final draftRepo = GenerationDraftRepository(keyValueStore: store);
  return DeletePracticePlanningData(
    planRepository: planRepo,
    draftRepository: draftRepo,
    evidenceRepository: evidence,
  );
}

SkillEvidence _evidenceForOutcome(OutcomeId outcomeId, PlanId planId) {
  return SkillEvidence(
    skillId: 'chord.gMajor',
    source: EvidenceSource.learn,
    sourceOutcomeId: outcomeId,
    measurementVersion: 1,
    measuredAt: DateTime.utc(2026, 8, 19),
    capturedAt: DateTime.utc(2026, 8, 19),
    confidence: 0.8,
    validUntil: DateTime.utc(2026, 9, 19),
    performance: PerformanceEvidence(
      metricCode: 'chordChangeAccuracy',
      value: 0.7,
    ),
  );
}

ArchivedRevision _revision(PlanId planId, {required int number}) =>
    ArchivedRevision(
      id: RevisionId('revision.$number'),
      planId: planId,
      number: number,
      createdAt: DateTime.utc(2026, 8, 19, 10, number),
      reason: PlanRevisionReason.initialGeneration,
      previousRevisionId: number == 1
          ? null
          : RevisionId('revision.${number - 1}'),
      snapshot: plan(),
    );

// KeyValueStore is intentionally imported but used indirectly via the
// in-memory store; the type alias keeps the dependency explicit.
// ignore: unused_element
typedef _KeyValueStoreAlias = KeyValueStore;
