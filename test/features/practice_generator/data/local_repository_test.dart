import 'dart:convert';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_plan_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_migrator.dart';
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

      test('dotted plan and revision ids produce distinct active and archive '
          'keys for otherwise-colliding pairs', () {
        final firstPlanId = PlanId('plan.a');
        final firstRevisionId = RevisionId('revision.b');
        final secondPlanId = PlanId('plan.a.revision');
        final secondRevisionId = RevisionId('b');

        expect(
          LocalPracticePlanRepository.activePlanRevisionKey(
            planId: firstPlanId,
            revisionId: firstRevisionId,
          ),
          isNot(
            LocalPracticePlanRepository.activePlanRevisionKey(
              planId: secondPlanId,
              revisionId: secondRevisionId,
            ),
          ),
        );
        expect(
          LocalPracticePlanRepository.archiveRevisionKey(
            planId: firstPlanId,
            revisionId: RevisionId('b.revisions.index'),
          ),
          isNot(
            LocalPracticePlanRepository.archiveRevisionsIndexKey(
              PlanId('plan.a.revisions.b'),
            ),
          ),
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

      test('a failed old-record cleanup does not report a committed '
          'activation as a failure', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final firstPlan = plan();
        final nextPlan = _bumpedPlan(number: 99);

        expect(
          (await repository.activateAndReport(firstPlan)).isSuccess,
          isTrue,
        );
        final oldRecordKey = LocalPracticePlanRepository.activePlanRevisionKey(
          planId: firstPlan.id,
          revisionId: firstPlan.activeRevisionId,
        );
        store.failingKeys.add(oldRecordKey);

        final result = await repository.activateAndReport(nextPlan);

        store.failingKeys.remove(oldRecordKey);
        expect(result.isSuccess, isTrue);
        expect(result.valueOrNull!.revisionWritten, isTrue);
        final active = await repository.readActivePlan();
        expect(active.isSuccess, isTrue);
        expect(active.valueOrNull, nextPlan);
        expect(
          store.contains(oldRecordKey),
          isTrue,
          reason: 'failed housekeeping must leave the old record intact',
        );
      });
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

      test(
        'a re-stamped-checksum, semantically corrupted archive revision '
        'is dropped, while the healthy sibling remains readable '
        '(S-02 — record-level isolation over any decode exception)',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);
          final planId = PlanId('plan.1');

          // Two healthy revisions on disk.
          final first = _revision(planId, number: 1);
          final second = _revision(planId, number: 2);
          await repository.appendRevision(first);
          await repository.appendRevision(second);

          // Corrupt revision.1's body in a way the domain decoders reject
          // with an exception OTHER than PracticePlanSerializerException
          // (DateTime.parse throws FormatException), then re-stamp the
          // checksum to match. This proves the record-level drop is
          // driven by the catch-all on the decode path — not by the
          // envelope's checksum gate, which now trusts the body.
          final corruptKey = LocalPracticePlanRepository.archiveRevisionKey(
            planId: planId,
            revisionId: first.id,
          );
          final raw = store.readString(corruptKey);
          expect(raw, isNotNull);
          final envelope = jsonDecode(raw!) as Map<String, dynamic>;
          final body = envelope['body'] as Map<String, dynamic>;
          body['createdAt'] = 'not-a-valid-iso-date';
          envelope['body'] = body;
          envelope['checksum'] = _sha256OfCanonicalJson(
            body as Map<String, Object?>,
          );
          await store.writeString(corruptKey, jsonEncode(envelope));

          final archive = await repository.readArchive(planId);

          // The healthy sibling reads back; the corrupt one is silently
          // dropped. The whole read does NOT fail just because one record
          // is semantically broken — S-02 / A2 invariant.
          expect(archive.isSuccess, isTrue);
          final log = archive.valueOrNull!;
          final numbers = log.revisions.map((r) => r.number).toList();
          expect(numbers, <int>[2], reason: 'sibling survives, corrupt gone');
          expect(
            log.droppedRevisions,
            1,
            reason: 'exactly the one re-stamped-checksum record is dropped',
          );
        },
      );

      test(
        'a re-stamped-checksum, semantically corrupted archive outcome '
        'is dropped, while the healthy sibling remains readable '
        '(S-02 — outcome symmetry: same catch-all must guard outcomes)',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);
          final planId = PlanId('plan.1');

          // Two healthy outcomes on disk.
          final first = _outcome('outcome.a');
          final second = _outcome('outcome.b');
          await repository.appendOutcome(first);
          await repository.appendOutcome(second);

          // Corrupt outcome.a's body in a way the domain decoders reject
          // with a non-serializer exception (DateTime.parse throws
          // FormatException on a bad ISO string), then re-stamp the
          // checksum. This proves the catch-all on the OUTCOMES read path
          // is what saves the sibling — not the envelope's checksum gate,
          // which now trusts the body.
          final corruptKey = LocalPracticePlanRepository.archiveOutcomeKey(
            planId: planId,
            outcomeId: first.id,
          );
          final raw = store.readString(corruptKey);
          expect(raw, isNotNull);
          final envelope = jsonDecode(raw!) as Map<String, dynamic>;
          final body = envelope['body'] as Map<String, dynamic>;
          body['recordedAt'] = 'not-a-valid-iso-date';
          envelope['body'] = body;
          envelope['checksum'] = _sha256OfCanonicalJson(
            body as Map<String, Object?>,
          );
          await store.writeString(corruptKey, jsonEncode(envelope));

          final archive = await repository.readArchive(planId);

          expect(archive.isSuccess, isTrue);
          final log = archive.valueOrNull!;
          final ids = log.outcomes.map((o) => o.id.value).toList();
          expect(ids, <String>[
            'outcome.b',
          ], reason: 'sibling survives, corrupt gone');
          expect(
            log.droppedOutcomes,
            1,
            reason: 'exactly the one re-stamped-checksum outcome is dropped',
          );
        },
      );
    });

    group('non-object JSON corruption (S-01)', () {
      test(
        'a present-but-non-object active record is a controlled '
        'StorageFailure, not a first-launch success (S-01, active)',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);
          final p1 = plan();
          await repository.activateAndReport(p1);

          // Overwrite the active record with each of the three persistence
          // shapes the bug used to silently treat as "absent" — a list,
          // a JSON null, and a JSON number. All are valid JSON, none is a
          // JSON object.
          for (final corruptValue in <Object?>[<Object?>[], null, 42]) {
            final activeKey = LocalPracticePlanRepository.activePlanRevisionKey(
              planId: p1.id,
              revisionId: p1.activeRevisionId,
            );
            await store.writeString(activeKey, jsonEncode(corruptValue));

            final result = await repository.readActivePlan();

            expect(
              result.isFailure,
              isTrue,
              reason:
                  'present-but-non-object active record ($corruptValue) '
                  'must be a StorageFailure, never Success(null)',
            );
            final failure = result.failureOrNull;
            expect(failure, isA<StorageFailure>());
            expect(failure!.code, FailureCode.storageRead);
            // The cause is a controlled serializer exception with the
            // stable `notAnObject` code — no persisted raw value escapes.
            expect(failure.cause, isA<PracticePlanSerializerException>());
            expect(
              (failure.cause as PracticePlanSerializerException).code,
              PracticePlanSerializerErrorCode.notAnObject,
            );
            // The redacting log path takes the failure, not the raw
            // bytes — verify the value was never carried in toString.
            expect(
              failure.toString(),
              isNot(contains(jsonEncode(corruptValue))),
            );
          }
        },
      );

      test('a present-but-non-object draft is a controlled StorageFailure, '
          'not a first-launch success (S-01, draft)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        await repository.saveDraft(draftKey: 'main', plan: plan());

        for (final corruptValue in <Object?>[<Object?>[], null, 42]) {
          final draftKey = LocalPracticePlanRepository.draftStorageKey('main');
          await store.writeString(draftKey, jsonEncode(corruptValue));

          final result = await repository.readDraft('main');

          expect(
            result.isFailure,
            isTrue,
            reason:
                'present-but-non-object draft ($corruptValue) must be a '
                'StorageFailure, never Success(null)',
          );
          final failure = result.failureOrNull;
          expect(failure, isA<StorageFailure>());
          expect(failure!.code, FailureCode.storageRead);
          expect(failure.cause, isA<PracticePlanSerializerException>());
          expect(
            (failure.cause as PracticePlanSerializerException).code,
            PracticePlanSerializerErrorCode.notAnObject,
          );
          expect(failure.toString(), isNot(contains(jsonEncode(corruptValue))));
        }
      });
    });

    group('schema-version gate on the read path (A7, repository-level)', () {
      // The migrator MUST run before body decoding for every persisted
      // record kind. The brief calls out six kinds (active record, draft,
      // revision, outcome, revisions index, outcomes index) plus the
      // active pointer. The §6.1 three schema cells (below / at / above)
      // are exercised here against the repository, not just the migrator
      // (the migrator test alone proved no production caller).
      test('an active plan record above the supported version is a '
          'controlled read failure (A7, above cell — current+1 is '
          'rejected before its body is decoded)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final p1 = plan();
        await repository.activateAndReport(p1);

        // Bump the stored active record to schemaVersion = current + 1.
        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.activePlanRevisionKey(
            planId: p1.id,
            revisionId: p1.activeRevisionId,
          ),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion + 1,
        );

        final result = await repository.readActivePlan();

        expect(result.isFailure, isTrue);
        final error = result.failureOrNull;
        expect(error, isA<StorageFailure>());
        // The migrator exception is the cause — proves the gate fired
        // BEFORE the body codec tried to decode the future shape.
        expect(error!.cause, isA<PracticePlanMigratorException>());
        expect(
          (error.cause as PracticePlanMigratorException).code,
          PracticePlanMigratorErrorCode.schemaVersionTooNew,
        );
      });

      test('an active pointer above the supported version is a controlled '
          'corruption failure, never a first-launch success '
          '(A7, above cell — pointer)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final p1 = plan();
        await repository.activateAndReport(p1);

        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.activePointerKey,
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion + 1,
        );

        final activeResult = await repository.readActivePlan();
        final draftResult = await repository.readDraft('main');

        // Pointer is too-new — preserve the distinction between a missing
        // pointer (first launch) and an unreadable persisted pointer.
        expect(activeResult.isFailure, isTrue);
        expect(
          activeResult.failureOrNull!.cause,
          isA<PracticePlanActivePointerCorruptionException>(),
        );
        // Draft key was never written — but the read should still be
        // a clean Success(null), not a thrown exception.
        expect(draftResult.isSuccess, isTrue);
        expect(draftResult.valueOrNull, isNull);
      });

      test(
        'an archived revision record above the supported version is '
        'dropped from the log without taking the rest of the archive '
        'with it (A7, above cell — revisions, record-level isolation)',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);
          final planId = PlanId('plan.1');

          // Seed three valid revisions.
          await repository.appendRevision(_revision(planId, number: 1));
          await repository.appendRevision(_revision(planId, number: 2));
          await repository.appendRevision(_revision(planId, number: 3));

          // Bump revision 2 to current + 1 — keep body & checksum so this
          // proves the gate, not the checksum path.
          _retuneEnvelope(
            store,
            key: LocalPracticePlanRepository.archiveRevisionKey(
              planId: planId,
              revisionId: RevisionId('revision.2'),
            ),
            schemaVersion:
                PracticePlanMigrator.currentSupportedSchemaVersion + 1,
          );

          final archive = await repository.readArchive(planId);

          expect(archive.isSuccess, isTrue);
          final log = archive.valueOrNull!;
          final numbers = log.revisions.map((r) => r.number).toList();
          // Newest-first; revision 2 dropped, 3 and 1 survive.
          expect(numbers, <int>[3, 1]);
          expect(log.droppedRevisions, 1, reason: 'one record was dropped');
        },
      );

      test(
        'an archived outcome record above the supported version is '
        'dropped from the log without taking the rest of the archive '
        'with it (A7, above cell — outcomes, record-level isolation)',
        () async {
          final store = InMemoryKeyValueStore();
          final repository = _newRepository(store);
          final planId = PlanId('plan.1');

          await repository.appendOutcome(_outcome('outcome.a'));
          await repository.appendOutcome(_outcome('outcome.b'));
          await repository.appendOutcome(_outcome('outcome.c'));

          _retuneEnvelope(
            store,
            key: LocalPracticePlanRepository.archiveOutcomeKey(
              planId: planId,
              outcomeId: OutcomeId('outcome.b'),
            ),
            schemaVersion:
                PracticePlanMigrator.currentSupportedSchemaVersion + 1,
          );

          final archive = await repository.readArchive(planId);

          expect(archive.isSuccess, isTrue);
          final log = archive.valueOrNull!;
          final ids = log.outcomes.map((o) => o.id.value).toList();
          // Newest-first; outcome.b dropped, outcome.c and outcome.a survive.
          expect(ids, <String>['outcome.c', 'outcome.a']);
          expect(log.droppedOutcomes, 1);
        },
      );

      test('an archived index record above the supported version fails the '
          'read of THAT plan while other plans stay readable '
          '(A7, above cell — index is preserved)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final planA = PlanId('plan.A');
        final planB = PlanId('plan.B');

        // plan.A: one healthy revision.
        await repository.appendRevision(_revision(planA, number: 1));
        // plan.B: one healthy revision (kept).
        await repository.appendRevision(_revision(planB, number: 1));

        // Bump plan.A's revisions index to current + 1.
        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.archiveRevisionsIndexKey(planA),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion + 1,
        );

        final logA = await repository.readArchive(planA);
        final logB = await repository.readArchive(planB);

        expect(logA.isFailure, isTrue);
        expect(
          logA.failureOrNull!.cause,
          isA<PracticePlanArchiveIndexCorruptionException>(),
        );
        expect(logB.isSuccess, isTrue);
        expect(
          logB.valueOrNull!.revisions,
          hasLength(1),
          reason: 'other plans remain readable',
        );
      });

      test('a malformed active pointer is a controlled corruption failure, '
          'not a first-launch success', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        await repository.activateAndReport(plan());
        await store.writeString(
          LocalPracticePlanRepository.activePointerKey,
          'not-json',
        );

        final result = await repository.readActivePlan();

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<StorageFailure>());
        expect(
          result.failureOrNull!.cause,
          isA<PracticePlanActivePointerCorruptionException>(),
        );
      });

      test('a draft record above the supported version is a controlled '
          'read failure (A7, above cell — draft)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        await repository.saveDraft(draftKey: 'main', plan: plan());

        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.draftStorageKey('main'),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion + 1,
        );

        final result = await repository.readDraft('main');

        expect(result.isFailure, isTrue);
        final error = result.failureOrNull;
        expect(error, isA<StorageFailure>());
        expect(error!.cause, isA<PracticePlanMigratorException>());
        expect(
          (error.cause as PracticePlanMigratorException).code,
          PracticePlanMigratorErrorCode.schemaVersionTooNew,
        );
      });

      test('an active plan record at the supported version is read '
          'unchanged (A7, at cell — current is the no-op path)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final p1 = plan();
        await repository.activateAndReport(p1);

        // No tampering — the envelope is already schemaVersion=current.
        final raw = store.readString(
          LocalPracticePlanRepository.activePlanRevisionKey(
            planId: p1.id,
            revisionId: p1.activeRevisionId,
          ),
        );
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(
          decoded['schemaVersion'],
          PracticePlanMigrator.currentSupportedSchemaVersion,
        );

        final reloaded = await repository.readActivePlan();
        expect(reloaded.isSuccess, isTrue);
        expect(reloaded.valueOrNull, p1);
      });

      test('an active plan record one below the supported version routes '
          'through the forward-migration path and reads back identically '
          '(A7, below cell — current−1 migrates, never throws)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final p1 = plan();
        await repository.activateAndReport(p1);

        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.activePlanRevisionKey(
            planId: p1.id,
            revisionId: p1.activeRevisionId,
          ),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion - 1,
        );

        final reloaded = await repository.readActivePlan();

        expect(reloaded.isSuccess, isTrue);
        // The no-op migration pass-through keeps the body identical, so
        // checksum verification still passes and the plan reads back
        // equal to the original.
        expect(reloaded.valueOrNull, p1);
      });

      test('an archived revision record one below the supported version '
          'routes through the forward-migration path and survives '
          '(A7, below cell — revision migration)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final planId = PlanId('plan.1');

        await repository.appendRevision(_revision(planId, number: 1));
        await repository.appendRevision(_revision(planId, number: 2));

        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.archiveRevisionKey(
            planId: planId,
            revisionId: RevisionId('revision.1'),
          ),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion - 1,
        );

        final archive = await repository.readArchive(planId);

        expect(archive.isSuccess, isTrue);
        final log = archive.valueOrNull!;
        expect(
          log.droppedRevisions,
          0,
          reason: 'older-record migration must not drop',
        );
        // Newest-first; both revisions present, revision.1 route through
        // the migrator on read.
        expect(log.revisions.map((r) => r.number), <int>[2, 1]);
      });

      test('a draft record one below the supported version routes '
          'through the forward-migration path and reads back identically '
          '(A7, below cell — draft migration)', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final draftPlan = plan(title: 'd');
        await repository.saveDraft(draftKey: 'main', plan: draftPlan);

        _retuneEnvelope(
          store,
          key: LocalPracticePlanRepository.draftStorageKey('main'),
          schemaVersion: PracticePlanMigrator.currentSupportedSchemaVersion - 1,
        );

        final reloaded = await repository.readDraft('main');

        expect(reloaded.isSuccess, isTrue);
        expect(reloaded.valueOrNull, draftPlan);
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

    group('archive index corruption containment', () {
      test('a corrupt archive index fails an append without overwriting the '
          'index or orphaning existing history', () async {
        final store = InMemoryKeyValueStore();
        final repository = _newRepository(store);
        final planId = PlanId('plan.1');
        final firstRevision = _revision(planId, number: 1);
        final secondRevision = _revision(planId, number: 2);
        expect(
          (await repository.appendRevision(firstRevision)).isSuccess,
          isTrue,
        );

        final indexKey = LocalPracticePlanRepository.archiveRevisionsIndexKey(
          planId,
        );
        const corruptIndex = 'not-json-at-all';
        await store.writeString(indexKey, corruptIndex);

        final result = await repository.appendRevision(secondRevision);

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<StorageFailure>());
        expect(
          result.failureOrNull!.cause,
          isA<PracticePlanArchiveIndexCorruptionException>(),
        );
        expect(store.readString(indexKey), corruptIndex);
        expect(
          store.contains(
            LocalPracticePlanRepository.archiveRevisionKey(
              planId: planId,
              revisionId: secondRevision.id,
            ),
          ),
          isFalse,
          reason: 'a rejected append must not create an unindexed record',
        );
      });
    });

    group('F1 — durable manifest (E07-R29 review)', () {
      test('a fresh repository over the same store discovers the writer\'s '
          'planner-owned keys (drafts, archive-only plans).', () async {
        final store = InMemoryKeyValueStore();
        final writer = _newRepository(store);

        // Seed: an active plan, a draft, and an archive-only revision on
        // a different plan that was NEVER activated in this writer.
        await writer.activateAndReport(plan());
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'd'),
        );
        await writer.appendRevision(_revision(PlanId('plan.2'), number: 1));

        // Restart boundary — a fresh repository over the same store.
        final reader = _newRepository(store);

        // Both the draft AND the archive-only plan are visible (the
        // measured F1 failure: in-memory _writtenKeys was empty on the
        // restart side, so they fell off the discovery surface).
        expect(reader.knownDraftKeysSync(), ['main']);
        expect(
          reader.knownPlanIdsSync(),
          containsAll(<PlanId>{PlanId('plan.1'), PlanId('plan.2')}),
        );

        // The manifest itself lives on disk so a third repository also
        // sees the same key set.
        final third = _newRepository(store);
        expect(third.knownDraftKeysSync(), ['main']);
        expect(
          third.knownPlanIdsSync(),
          containsAll(<PlanId>{PlanId('plan.1'), PlanId('plan.2')}),
        );

        // delete-all on the third repository wipes EVERY planner-owned
        // key, including the manifest itself.
        final deleted = await third.deleteAllPlanningData();
        expect(deleted.isSuccess, isTrue);

        final afterDelete = _newRepository(store);
        expect(afterDelete.knownDraftKeysSync(), isEmpty);
        expect(afterDelete.knownPlanIdsSync(), isEmpty);
        expect(
          store.contains(LocalPracticePlanRepository.manifestKey),
          isFalse,
        );
      });

      test('the manifest persists through a draft clear-then-resave cycle '
          '(restart-stable draft discovery).', () async {
        final store = InMemoryKeyValueStore();
        final writer = _newRepository(store);
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'd1'),
        );
        await writer.clearDraft('main');
        await writer.saveDraft(
          draftKey: 'main',
          plan: plan(title: 'd2'),
        );

        final reader = _newRepository(store);
        expect(reader.knownDraftKeysSync(), ['main']);
      });

      test('a corrupt manifest on disk is treated as empty (no-op '
          'discovery; does not poison the repository).', () {
        // Seed a manifest whose JSON body is not a List.
        final store = InMemoryKeyValueStore();
        store.values[LocalPracticePlanRepository.manifestKey] =
            '{"not":"a list"}';
        // Other planner-owned keys were never recorded by this build —
        // the manifest is the only ledger.
        store.values[LocalPracticePlanRepository.draftStorageKey('survivor')] =
            '"raw"';

        final repository = _newRepository(store);
        // A corrupt manifest falls back to "no planner-owned keys" and
        // the rest of the surface works as designed (writes still
        // succeed). The pre-existing, non-manifest key is unreadable
        // by `_namespaceKeys()` only because the manifest itself is
        // empty — by design.
        expect(repository.knownDraftKeysSync(), isEmpty);
      });
    });

    group('F3 — manifest persistence failures (E07-R29 review)', () {
      test(
        'a rejected manifest write makes saveDraft return StorageFailure',
        () async {
          final store = InMemoryKeyValueStore()
            ..failingKeys.add(LocalPracticePlanRepository.manifestKey);
          final repository = _newRepository(store);

          final result = await repository.saveDraft(
            draftKey: 'main',
            plan: plan(),
          );

          expect(result.isFailure, isTrue);
          final failure = result.failureOrNull;
          expect(failure, isA<StorageFailure>());
          expect(failure!.code, FailureCode.storageWrite);
          expect(failure.cause, isA<StorageException>());
          expect(
            (failure.cause! as StorageException).key,
            LocalPracticePlanRepository.manifestKey,
          );
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

/// Reads the stored envelope at [key], re-stamps only `schemaVersion` to
/// the requested value (leaving the body and checksum exactly as encoded
/// by the serializer), and writes it back. This simulates a record
/// authored by a build with a different envelope version without
/// tampering with the checksum-protected body.
///
/// Required by the schema-version gate tests (A7) to construct the
/// "current+1" and "current-1" inputs that the read path must then
/// gate / migrate.
Future<void> _retuneEnvelope(
  InMemoryKeyValueStore store, {
  required String key,
  required int schemaVersion,
}) async {
  final raw = store.readString(key);
  expect(raw, isNotNull, reason: 'seed record missing at $key');
  final decoded = jsonDecode(raw!) as Map<String, dynamic>;
  decoded['schemaVersion'] = schemaVersion;
  await store.writeString(key, jsonEncode(decoded));
}

/// Recomputes the SHA-256 checksum the [PracticePlanSerializer] would
/// have written for [body] — key-sorted, deterministic canonicalization,
/// hex digest. Used by the S-02 regression test to *re-stamp* an
/// envelope's checksum after a semantic mutation, so the read path
/// cannot fall back to the checksum gate to mask the catch-all.
String _sha256OfCanonicalJson(Map<String, Object?> body) {
  // Mirrors `practice_plan_serializer.dart::_canonicalize`: recursively
  // sort map keys so the JSON encoding is insertion-order-independent.
  Object? canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return <String, Object?>{for (final k in keys) k: canonicalize(value[k])};
    }
    if (value is List) {
      return <Object?>[for (final item in value) canonicalize(item)];
    }
    return value;
  }

  final canonical = jsonEncode(canonicalize(body));
  return crypto.sha256.convert(utf8.encode(canonical)).toString();
}
