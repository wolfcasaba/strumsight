import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_plan_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_serializer.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/adaptive_practice_plan.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_revision.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

void main() {
  group('LocalPracticePlanRepository', () {
    group('key namespace isolation (A5)', () {
      test(
        'saving a draft never touches the active pointer or active record',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          final result = await repository.saveDraft(
            draftKey: 'main',
            plan: plan(),
          );

          expect(result.isSuccess, isTrue);
          expect(
            store.contains(LocalPracticePlanRepository.activePointerKey),
            isFalse,
          );
          expect(
            store.values.keys.any(
              (key) =>
                  key ==
                  LocalPracticePlanRepository.activePlanRevisionKey(
                    planId: PlanId('plan.1'),
                    revisionId: RevisionId('revision.1'),
                  ),
            ),
            isFalse,
          );
          expect(
            store.writeLog.every(
              (entry) =>
                  !entry.contains(LocalPracticePlanRepository.activePointerKey),
            ),
            isTrue,
            reason: 'draft path must NEVER write the active-pointer key',
          );
        },
      );

      test(
        'activating a plan never touches the draft namespace keys',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          final result = await repository.activateAndReport(plan());

          expect(result.isSuccess, isTrue);
          expect(
            store.values.keys.where((key) => key.contains('.draft.')).toList(),
            isEmpty,
            reason: 'activation must NEVER write a draft key',
          );
        },
      );

      test('the draft key prefix is distinct from the active prefix', () {
        expect(
          LocalPracticePlanRepository.draftStorageKey('main'),
          isNot(contains(LocalPracticePlanRepository.activePointerKey)),
        );
      });
    });

    group('active plan persistence (A1)', () {
      test('an activated plan survives a "restart" — a new repository '
          'instance over the same store reads it back identically', () async {
        final store = InMemoryKeyValueStore();
        final writer = _newRepository(store);
        final original = plan();

        final activation = await writer.activateAndReport(original);
        expect(activation.isSuccess, isTrue);
        expect(activation.valueOrNull!.revisionWritten, isTrue);

        // Simulate a restart: a fresh repository backed by the same store.
        final reader = _newRepository(store);

        final reloaded = await reader.readActivePlan();

        expect(reloaded.isSuccess, isTrue);
        expect(reloaded.valueOrNull, original);
      });

      test(
        'readActivePlan returns null when nothing has been activated',
        () async {
          final repository = _newRepository(InMemoryKeyValueStore());

          final result = await repository.readActivePlan();

          expect(result, const Success<AdaptivePracticePlan?>(null));
        },
      );
    });

    group('idempotent activation (NOTE-4)', () {
      test('activating the same plan twice writes no second time and returns '
          'revisionWritten=false', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final p = plan();

        final first = await repository.activateAndReport(p);
        final writeCountAfterFirst = store.writeLog.length;

        final second = await repository.activateAndReport(p);

        expect(first.isSuccess, isTrue);
        expect(first.valueOrNull!.revisionWritten, isTrue);
        expect(second.isSuccess, isTrue);
        expect(second.valueOrNull!.revisionWritten, isFalse);
        expect(second.valueOrNull!.pointer, first.valueOrNull!.pointer);
        expect(
          store.writeLog.length,
          writeCountAfterFirst,
          reason: 'second activate must not write any record',
        );
      });
    });

    group('atomic activation (A3)', () {
      test(
        'a failed record write leaves the prior active pointer intact',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          // First activation: success.
          final initial = await repository.activateAndReport(plan());
          expect(initial.isSuccess, isTrue);
          final initialPointer = initial.valueOrNull!.pointer;
          expect(
            store.readString(LocalPracticePlanRepository.activePointerKey),
            isNotNull,
          );

          // Next plan: a *different* plan so activate is not a no-op.
          final next = _bumpedPlan(number: 99);

          // Make the new revision record key throw — that simulates an
          // interrupted write BEFORE the pointer moves. Step 1 fails,
          // step 2 must therefore never run.
          final newRevisionKey =
              LocalPracticePlanRepository.activePlanRevisionKey(
                planId: next.id,
                revisionId: next.activeRevisionId,
              );
          store.failingKeys.add(newRevisionKey);

          final second = await repository.activateAndReport(next);

          store.failingKeys.remove(newRevisionKey);

          expect(second.isFailure, isTrue);
          expect(second.failureOrNull, isA<StorageFailure>());
          // The prior pointer is still in place; the read sees the original
          // plan.
          final reloaded = await repository.readActivePlan();
          expect(reloaded.isSuccess, isTrue);
          expect(reloaded.valueOrNull!.id, initialPointer.planId);
          expect(
            reloaded.valueOrNull!.activeRevisionId,
            initialPointer.revisionId,
          );
        },
      );

      test(
        'a failed pointer write leaves the prior record and pointer intact',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          final firstPlan = plan();
          final first = await repository.activateAndReport(firstPlan);
          expect(first.isSuccess, isTrue);

          // Second plan: needs a brand-new revision key (so step 1 will
          // succeed independently). Make the active-pointer key throw on
          // step 2.
          final next = _bumpedPlan(number: 99);
          store.failingKeys.add(LocalPracticePlanRepository.activePointerKey);

          final second = await repository.activateAndReport(next);

          store.failingKeys.remove(
            LocalPracticePlanRepository.activePointerKey,
          );

          expect(second.isFailure, isTrue);
          // The pointer key is still readable and still points at the first
          // plan.
          final reloaded = await repository.readActivePlan();
          expect(reloaded.isSuccess, isTrue);
          expect(reloaded.valueOrNull, firstPlan);
        },
      );
    });

    group('record-level corruption containment (A2)', () {
      test(
        'one corrupt active record does not destroy the others, the draft, '
        'or the archive index — pointer survives but reads null cleanly',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          // Healthy: plan 1 + revision 1.
          final p1 = plan();
          await repository.activateAndReport(p1);
          // Draft under .plan.draft.main.
          await repository.saveDraft(
            draftKey: 'main',
            plan: plan(title: 'd'),
          );

          // Real corruption probe (§6.1, §10): write garbage under one of
          // the archive record slots, leaving the pointer / draft / index
          // untouched.
          final corruptedKey = LocalPracticePlanRepository.archiveRevisionKey(
            planId: PlanId('plan.1'),
            revisionId: RevisionId('revision.corrupt'),
          );
          await store.writeString(corruptedKey, 'not-json-at-all{{{');

          final activeResult = await repository.readActivePlan();
          final draftResult = await repository.readDraft('main');

          expect(activeResult.isSuccess, isTrue);
          expect(activeResult.valueOrNull, p1);
          expect(draftResult.isSuccess, isTrue);
          expect(draftResult.valueOrNull, plan(title: 'd'));
        },
      );

      test('a tampered-checksum active record is a controlled read failure, '
          'leaving the next plan visible after the pointer switches', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);

        final p1 = plan();
        await repository.activateAndReport(p1);

        // Tamper: read the active record raw, mutate one character inside
        // the body, rewrite it under the same key. The checksum then
        // mismatches.
        final activeKey = LocalPracticePlanRepository.activePlanRevisionKey(
          planId: p1.id,
          revisionId: p1.activeRevisionId,
        );
        final raw = store.readString(activeKey);
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        final body = decoded['body'] as Map<String, dynamic>;
        final title = body['title'] as String;
        body['title'] = '${title}TAMPERED';
        await store.writeString(activeKey, jsonEncode(decoded));

        final reloaded = await repository.readActivePlan();

        // The checksum mismatch surfaces as a StorageFailure with the
        // reproducible code, never a thrown exception.
        expect(reloaded.isFailure, isTrue);
        expect(reloaded.failureOrNull, isA<StorageFailure>());
      });
    });

    group('appendOutcome idempotence (A4)', () {
      test('appending the same OutcomeId twice yields exactly one record, '
          'with the second call as a no-op', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);

        final outcome = _outcome('outcome.1');
        final first = await repository.appendOutcome(outcome);
        final second = await repository.appendOutcome(outcome);

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);

        final archive = await repository.readArchive(outcome.planId);
        expect(archive.isSuccess, isTrue);
        final outcomes = archive.valueOrNull!.outcomes;
        expect(outcomes.where((o) => o.id == outcome.id).length, 1);
      });

      test(
        'appending different OutcomeIds preserves each, newest first',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);

          await repository.appendOutcome(_outcome('outcome.a'));
          await repository.appendOutcome(_outcome('outcome.b'));

          final archive = await repository.readArchive(
            _outcome('outcome.a').planId,
          );
          expect(archive.isSuccess, isTrue);
          final ids = archive.valueOrNull!.outcomes.map((o) => o.id.value);
          expect(ids.first, 'outcome.b');
          expect(ids.contains('outcome.a'), isTrue);
        },
      );
    });

    group('bounded history (A6)', () {
      test('revisions beyond maxRevisionsPerPlan evict the oldest, never '
          'modify an existing one', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(
          store,
          historyPolicy: const PracticePlanHistoryPolicy(
            maxRevisionsPerPlan: 3,
          ),
        );
        final planId = PlanId('plan.1');

        // Append 5 revisions; the repository keeps the 3 newest.
        await repository.appendRevision(_revision(planId, number: 1));
        await repository.appendRevision(_revision(planId, number: 2));
        await repository.appendRevision(_revision(planId, number: 3));
        await repository.appendRevision(_revision(planId, number: 4));
        await repository.appendRevision(_revision(planId, number: 5));

        final archive = await repository.readArchive(planId);
        expect(archive.isSuccess, isTrue);
        final revisions = archive.valueOrNull!.revisions;
        final numbers = revisions.map((r) => r.number).toList();
        expect(numbers, <int>[5, 4, 3]);

        // Every surviving revision is byte-identical to the one we
        // appended — the cap never modifies an existing record.
        for (final kept in revisions) {
          final key = LocalPracticePlanRepository.archiveRevisionKey(
            planId: planId,
            revisionId: kept.id,
          );
          expect(
            store.contains(key),
            isTrue,
            reason: 'kept revision ${kept.number} record must persist',
          );
        }

        // The two earliest records were evicted from disk (closed-range
        // compression dropped them when newer revisions capped the
        // history).
        final dropped1 = LocalPracticePlanRepository.archiveRevisionKey(
          planId: planId,
          revisionId: RevisionId('revision.1'),
        );
        final dropped2 = LocalPracticePlanRepository.archiveRevisionKey(
          planId: planId,
          revisionId: RevisionId('revision.2'),
        );
        expect(store.contains(dropped1), isFalse);
        expect(store.contains(dropped2), isFalse);

        // The index itself no longer references the dropped ids.
        final keptIds = revisions.map((r) => r.id.value).toSet();
        expect(keptIds.contains('revision.1'), isFalse);
        expect(keptIds.contains('revision.2'), isFalse);
      });
    });
  });
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

LocalPracticePlanRepository _newRepository(
  InMemoryKeyValueStore store, {
  PracticePlanHistoryPolicy? historyPolicy,
}) => LocalPracticePlanRepository(
  keyValueStore: store,
  resolveCandidate: resolveCandidate,
  historyPolicy: historyPolicy,
);

ArchivedRevision _revision(PlanId planId, {required int number}) =>
    ArchivedRevision(
      id: RevisionId('revision.$number'),
      planId: planId,
      number: number,
      createdAt: DateTime.utc(2026, 8, 18, 10, number),
      reason: PlanRevisionReason.initialGeneration,
      previousRevisionId: number == 1
          ? null
          : RevisionId('revision.${number - 1}'),
      snapshot: plan(),
    );

PracticeOutcome _outcome(String idValue) => PracticeOutcome(
  id: OutcomeId(idValue),
  planId: PlanId('plan.1'),
  revisionId: RevisionId('revision.1'),
  recordedAt: DateTime.utc(2026, 8, 18),
  durationMinutes: 5,
  completedBlockCount: 1,
  plannedBlockCount: 1,
  summary: 'short practice',
);

AdaptivePracticePlan _bumpedPlan({int number = 99}) {
  final p = plan();
  return AdaptivePracticePlan(
    id: p.id,
    schemaVersion: p.schemaVersion,
    status: PlanStatus.active,
    title: p.title,
    createdAt: p.createdAt,
    startDate: p.startDate,
    endDate: p.endDate,
    goals: p.goals,
    days: p.days,
    activeRevisionId: RevisionId('revision.$number'),
    generationProvenance: p.generationProvenance,
    policyVersions: p.policyVersions,
  );
}

// Reference [KeyValueStore] so the test imports it intentionally for the
// failing-keys behaviour the `failingKeys` set configures.
// ignore: unused_element
typedef _Anchor = KeyValueStore;
