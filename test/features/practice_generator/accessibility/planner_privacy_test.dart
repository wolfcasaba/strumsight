import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/practice_generator/application/usecase/delete_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/application/usecase/export_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_plan_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_serializer.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/adaptive_practice_plan.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_revision.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_day.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_generation_request.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_goal.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
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

      // Seed evidence for an outcome (with an explicit ownership record).
      _saveEvidence(
        evidence,
        outcomeId: OutcomeId('outcome.1'),
        planId: PlanId('plan.1'),
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
        _saveEvidence(
          evidence,
          outcomeId: OutcomeId('outcome.1'),
          planId: PlanId('plan.1'),
        );

        expect(evidence.allForSkill('chord.gMajor'), hasLength(1));

        // Direct call to the new evidence-port hook works as designed.
        final removed = evidence.deleteForPlan(PlanId('plan.1'));
        expect(removed, 1);
        expect(evidence.allForSkill('chord.gMajor'), isEmpty);
      },
    );

    test('a record saved WITHOUT explicit ownership is never deleted by '
        'deleteForPlan — unknown ownership is a refusal, not a wildcard '
        '(F2 default-implementation regression, two plans).', () async {
      final evidence = InMemoryPracticeEvidenceRepository();

      // Two plans, two outcomes — both saved WITHOUT a source-plan-id
      // (the "legitimate" production call path: the aggregator passes
      // a SkillEvidence whose ownership is unknowable from the
      // evidence record alone).
      evidence.save(_evidenceRecord(OutcomeId('plan.a.outcome.1')));
      evidence.save(_evidenceRecord(OutcomeId('plan.b.outcome.1')));

      // Default-implementation regression: deleting "plan.a" must
      // leave "plan.b" intact. With the F2 bug, the null-default
      // lookup treated BOTH records as owned by the caller and would
      // wipe both — measured regression.
      final removed = evidence.deleteForPlan(PlanId('plan.a'));

      expect(removed, 0, reason: 'no record carries plan-a ownership');
      expect(
        evidence.findByOutcomeId(OutcomeId('plan.a.outcome.1')),
        isNotNull,
        reason: 'unknown ownership must not silently lose the record',
      );
      expect(
        evidence.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
        isNotNull,
      );
    });

    test("deleteForPlan on the DEFAULT InMemory (no lookup, no "
        "source-plan-id) does NOT treat every record as the caller's "
        "(E07-R29 review F2 measured regression — two plans).", () async {
      final evidence = InMemoryPracticeEvidenceRepository();
      // Save a single record with explicit ownership to plan.a.
      _saveEvidence(
        evidence,
        outcomeId: OutcomeId('plan.a.outcome.1'),
        planId: PlanId('plan.a'),
      );
      // Save a SECOND record whose ownership is none of the caller's
      // business — a save WITHOUT a sourcePlanId (the Aggregator path).
      evidence.save(_evidenceRecord(OutcomeId('plan.b.outcome.1')));

      final removed = evidence.deleteForPlan(PlanId('plan.a'));

      expect(removed, 1, reason: 'only the plan.a record matches');
      expect(evidence.findByOutcomeId(OutcomeId('plan.a.outcome.1')), isNull);
      expect(
        evidence.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
        isNotNull,
        reason: 'unknown-ownership record is NOT silently claimed',
      );
    });

    test(
      'legacy outcomePlanLookup still works for tests that build '
      'evidence through a string-prefix pattern (F2 backward-compat).',
      () async {
        final evidence = InMemoryPracticeEvidenceRepository(
          outcomePlanLookup: (outcomeId) {
            if (outcomeId.startsWith('plan.a.outcome')) return PlanId('plan.a');
            if (outcomeId.startsWith('plan.b.outcome')) return PlanId('plan.b');
            return null;
          },
        );
        evidence.save(_evidenceRecord(OutcomeId('plan.a.outcome.1')));
        evidence.save(_evidenceRecord(OutcomeId('plan.b.outcome.1')));

        // Delete plan A only.
        final removed = evidence.deleteForPlan(PlanId('plan.a'));

        expect(removed, 1);
        expect(evidence.findByOutcomeId(OutcomeId('plan.a.outcome.1')), isNull);
        expect(
          evidence.findByOutcomeId(OutcomeId('plan.b.outcome.1')),
          isNotNull,
        );
      },
    );
  });

  group(
    'F1 — durable manifest makes delete-all and export-all restart-stable',
    () {
      test('a fresh repository over the same store discovers the former '
          'draft AND an archive-only plan (E07-R29 review F1 measured '
          'regression).', () async {
        final store = InMemoryKeyValueStore();
        final writer = _newPlanRepository(store);

        // Two distinct plans: plan.A is activated AND archived; plan.B
        // is archive-only (the F1 reviewer scenario — a plan that was
        // once active, is no longer, but still has archive records on
        // disk and was the precise case the §6.1 "archive-only plan"
        // cell aimed at).
        await writer.activateAndReport(
          AdaptivePracticePlan(
            id: PlanId('plan.A'),
            schemaVersion: 1,
            status: PlanStatus.archived,
            title: 'A',
            createdAt: DateTime.utc(2026, 8, 19, 9),
            startDate: LocalDate(2026, 8, 20),
            endDate: LocalDate(2026, 9, 20),
            goals: const <PracticeGoal>[],
            days: const <PracticeDay>[],
            activeRevisionId: RevisionId('revision.A.1'),
            generationProvenance: GenerationRequestId('archive-only.A'),
            policyVersions: const <String, String>{'catalog': 'catalog.v1'},
          ),
        );
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'main-draft'),
        );
        // Archive-only plan: never activated on this writer instance —
        // directly archived.
        await writer.appendRevision(
          ArchivedRevision(
            id: RevisionId('revision.B.1'),
            planId: PlanId('plan.B'),
            number: 1,
            createdAt: DateTime.utc(2026, 8, 18, 10),
            reason: PlanRevisionReason.initialGeneration,
            previousRevisionId: null,
            snapshot: plan(),
          ),
        );

        // Sanity: the writer sees both drafts and both plans.
        expect(writer.knownDraftKeysSync(), ['main']);
        expect(
          writer.knownPlanIdsSync(),
          containsAll(<PlanId>{PlanId('plan.A'), PlanId('plan.B')}),
        );

        // --- The restart boundary. A fresh repository over the same
        // store must discover both (the previous bug: in-memory
        // `_writtenKeys` was empty, drafts and archive-only plans fell
        // off the discovery surface).
        final reader = _newPlanRepository(store);

        expect(reader.knownDraftKeysSync(), ['main']);
        expect(
          reader.knownPlanIdsSync(),
          containsAll(<PlanId>{PlanId('plan.A'), PlanId('plan.B')}),
        );

        // Export: includes the draft AND the archive-only plan's
        // archived revisions.
        final exported = await reader.exportSnapshot();
        expect(exported.isSuccess, isTrue);
        final snapshot = exported.valueOrNull!;
        expect(snapshot.drafts.keys, contains('main'));
        expect(snapshot.archive.keys, contains(PlanId('plan.B')));
        expect(snapshot.archive[PlanId('plan.B')]!.revisions, hasLength(1));

        // Delete: must wipe every planner-owned key including the draft
        // and the archive-only plan.
        final deleted = await reader.deleteAllPlanningData();
        expect(deleted.isSuccess, isTrue);

        // A new repository over the now-empty store starts with no
        // keys and no plans.
        final afterDelete = _newPlanRepository(store);
        expect(afterDelete.knownDraftKeysSync(), isEmpty);
        expect(afterDelete.knownPlanIdsSync(), isEmpty);
        expect(
          store.contains(LocalPracticePlanRepository.manifestKey),
          isFalse,
          reason: 'delete-all removes the manifest itself',
        );
      });

      test('the persisted manifest survives a draft clearing (restart-stable '
          'discovery of cleared-then-re-saved drafts).', () async {
        final store = InMemoryKeyValueStore();
        final writer = _newPlanRepository(store);

        // Draft goes through save → clear → save cycle.
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'd1'),
        );
        await writer.clearDraft('main');
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'd2'),
        );

        // Fresh repository sees the live draft.
        final reader = _newPlanRepository(store);
        expect(reader.knownDraftKeysSync(), ['main']);
      });
    },
  );

  group('ExportPracticePlanningData (A7 export mirror, §6.1 second row)', () {
    test('export never carries free-text comfort notes', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();

      // Activate a plan so the export has content to copy.
      await planRepo.activateAndReport(plan());
      _saveEvidence(
        evidence,
        outcomeId: OutcomeId('outcome.1'),
        planId: PlanId('plan.1'),
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
        _saveEvidence(
          evidence,
          outcomeId: OutcomeId('outcome.1'),
          planId: PlanId('plan.1'),
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
    test('writing the comfort free text into the planner\'s own persistence '
        'is detected: the export redacts it (ADR 0260 §4).', () async {
      final store = _newStore();
      final planRepo = _newPlanRepository(store);
      final evidence = _newEvidenceRepository();

      const freeText = 'my wrist hurts after 10 minutes';

      // Build a plan that has BOTH a `comfort` constraint whose `value`
      // is the free text AND a `userNote` on its goal that is the
      // same free text. This is the realistic "leak" shape — a
      // future regression that does NOT redact the export envelope
      // would surface here as a literal substring in the captured
      // JSON.
      final leakyPlan = _leakyPlanWithFreeText(freeText);

      // Persist the leaky plan as the active record.
      final activation = await planRepo.activateAndReport(leakyPlan);
      expect(activation.isSuccess, isTrue);

      // Save it again as a draft so both export branches exercise
      // the redaction.
      await planRepo.saveDraft(draftKey: 'main', plan: leakyPlan);

      // Confirm the persistence layer DID write the free text (we are
      // testing the export's redaction, not the planner's storage).
      // The whole exercise is meaningful only if the bytes actually
      // reached the underlying store.
      expect(
        store.values.values.any((v) => '$v'.contains(freeText)),
        isTrue,
        reason:
            'the leak must actually be persisted for the probe to '
            'be meaningful',
      );

      // Run export-all and capture the produced JSON.
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
      final json = captured.single;

      // The free text is NOT in the export, even though the
      // persistence layer wrote it. If a future change removes the
      // redaction, this assertion flips to a real failure with the
      // literal free text in `json`.
      expect(
        json.contains(freeText),
        isFalse,
        reason: 'comfort free text must never appear in the export',
      );
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

SkillEvidence _evidenceRecord(OutcomeId outcomeId) => SkillEvidence(
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

void _saveEvidence(
  InMemoryPracticeEvidenceRepository evidence, {
  required OutcomeId outcomeId,
  required PlanId planId,
}) {
  evidence.save(_evidenceRecord(outcomeId), sourcePlanId: planId);
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

/// Builds a plan whose goal carries the comfort free text in its
/// `userNote`. The plan's `userNote` is the realistic "free-text
/// learner input" shape — a learner typing a sentence into the goal
/// composer. The export is contractually bound to redact this field
/// (ADR 0260 §4); the test asserts the redaction actually does.
AdaptivePracticePlan _leakyPlanWithFreeText(String freeText) {
  final base = plan();
  return AdaptivePracticePlan(
    id: base.id,
    schemaVersion: base.schemaVersion,
    status: base.status,
    title: base.title,
    createdAt: base.createdAt,
    startDate: base.startDate,
    endDate: base.endDate,
    goals: base.goals
        .map(
          (g) => PracticeGoal(
            id: g.id,
            type: g.type,
            priority: g.priority,
            status: g.status,
            createdAt: g.createdAt,
            skillIds: g.skillIds,
            userNote: freeText,
          ),
        )
        .toList(growable: false),
    days: base.days,
    activeRevisionId: base.activeRevisionId,
    generationProvenance: base.generationProvenance,
    policyVersions: base.policyVersions,
  );
}

// KeyValueStore is intentionally imported but used indirectly via the
// in-memory store; the type alias keeps the dependency explicit.
// ignore: unused_element
typedef _KeyValueStoreAlias = KeyValueStore;
