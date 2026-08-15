import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_request_serializer.dart';
import 'package:strumsight/features/practice_generator/domain/model/learner_constraints.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_generation_request.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

/// The storage key an active-plan repository would use. Deliberately not
/// [GenerationDraftRepository.draftStorageKey] — the isolation test (A7)
/// writes here directly and asserts the draft repository never touches it.
const String _activePlanKey = 'ss.practice_generator.active_plan';

PracticeGenerationRequest buildDraft({String id = 'draft-1'}) =>
    PracticeGenerationRequest(
      id: GenerationRequestId(id),
      createdAt: DateTime.utc(2026, 8, 15),
      locale: 'en',
      generationMode: GenerationMode.starter,
      planHorizonDays: 7,
      availability: WeeklyAvailability(const []),
      constraints: LearnerConstraints(const []),
    );

void main() {
  group('GenerationDraftRepository', () {
    test('loadDraft returns Success(null) when nothing is saved', () async {
      final repository = GenerationDraftRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );

      final result = await repository.loadDraft();

      expect(result, const Success<PracticeGenerationRequest?>(null));
    });

    test('a saved draft round-trips through loadDraft', () async {
      final store = InMemoryKeyValueStore();
      final repository = GenerationDraftRepository(keyValueStore: store);
      final draft = buildDraft();

      final saveResult = await repository.saveDraft(draft);
      final loadResult = await repository.loadDraft();

      expect(saveResult.isSuccess, isTrue);
      expect(loadResult.isSuccess, isTrue);
      expect(loadResult.valueOrNull, draft);
    });

    test('a corrupt draft is a controlled failure, not a crash (A6)', () async {
      final store = InMemoryKeyValueStore({
        GenerationDraftRepository.draftStorageKey: 'not-json-at-all{{{',
      });
      final repository = GenerationDraftRepository(keyValueStore: store);

      final result = await repository.loadDraft();

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test(
      'a draft at a future schema version is a controlled failure (A6, A5)',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = GenerationDraftRepository(keyValueStore: store);
        final futureJson = <String, dynamic>{
          ...const GenerationRequestSerializer().toJson(buildDraft()),
          'schemaVersion': GenerationRequestSerializer.currentSchemaVersion + 1,
        };
        await store.writeString(
          GenerationDraftRepository.draftStorageKey,
          jsonEncode(futureJson),
        );

        final result = await repository.loadDraft();

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<StorageFailure>());
      },
    );

    test(
      'saving or clearing a draft never touches the active-plan key (A7)',
      () async {
        final store = InMemoryKeyValueStore({_activePlanKey: 'untouched'});
        final repository = GenerationDraftRepository(keyValueStore: store);

        await repository.saveDraft(buildDraft());
        expect(store.values[_activePlanKey], 'untouched');

        await repository.clearDraft();
        expect(store.values[_activePlanKey], 'untouched');
        expect(
          store.writeLog.every((entry) => !entry.contains(_activePlanKey)),
          isTrue,
        );
      },
    );

    test('the draft key is distinct from the active-plan key (A7)', () {
      expect(GenerationDraftRepository.draftStorageKey, isNot(_activePlanKey));
    });

    test(
      'clearDraft is idempotent — clearing twice both succeed (A8)',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = GenerationDraftRepository(keyValueStore: store);
        await repository.saveDraft(buildDraft());

        final first = await repository.clearDraft();
        final second = await repository.clearDraft();

        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);
        expect(repository.hasDraft, isFalse);
        expect((await repository.loadDraft()).valueOrNull, isNull);
      },
    );

    test('clearDraft on an already-empty store still succeeds (A8)', () async {
      final repository = GenerationDraftRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );

      final result = await repository.clearDraft();

      expect(result.isSuccess, isTrue);
    });
  });
}
