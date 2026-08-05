import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_memory_fact.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('LocalTutorMemoryRepository', () {
    test(
      'deduplicates equivalent candidates and lets the user edit and delete the fact',
      () async {
        final repository = LocalTutorMemoryRepository(
          keyValueStore: InMemoryKeyValueStore(),
        );
        final candidate = _candidate('one', 'Prefers slow practice.');

        final first = await repository.saveCandidate(candidate);
        final second = await repository.saveCandidate(
          _candidate('two', '  prefers   slow practice. '),
        );
        final fact = (first as Success<TutorMemoryFact>).value;

        expect((second as Success<TutorMemoryFact>).value.id, fact.id);
        final edited = fact.copyWith(content: 'Prefers slow warm-ups.');
        expect(await repository.update(edited), isA<Success<void>>());
        expect(
          (await repository.list() as Success<List<TutorMemoryFact>>)
              .value
              .single
              .content,
          'Prefers slow warm-ups.',
        );
        expect(await repository.delete(fact.id), isA<Success<void>>());
        expect(
          (await repository.list() as Success<List<TutorMemoryFact>>).value,
          isEmpty,
        );
      },
    );

    test('rejects a sensitive candidate without persisting it', () async {
      final repository = LocalTutorMemoryRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );

      final result = await repository.saveCandidate(
        _candidate('sensitive', 'My password is forest-123.'),
      );

      expect(result, isA<Failure<TutorMemoryFact>>());
      expect(
        (result as Failure<TutorMemoryFact>).error,
        isA<ValidationFailure>(),
      );
      expect(
        (await repository.list() as Success<List<TutorMemoryFact>>).value,
        isEmpty,
      );
    });

    test('purges facts whose documented retention has elapsed', () async {
      final repository = LocalTutorMemoryRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      await repository.saveCandidate(
        _candidate(
          'expired',
          'Old preference',
          expiresAt: DateTime.utc(2026, 8, 5, 12),
        ),
      );
      await repository.saveCandidate(
        _candidate('current', 'Current preference'),
      );

      await repository.purgeExpired(DateTime.utc(2026, 8, 5, 12, 1));

      expect(
        (await repository.list() as Success<List<TutorMemoryFact>>).value.map(
          (fact) => fact.id,
        ),
        ['current'],
      );
    });

    test('exports inspectable fact metadata with content redacted', () async {
      final repository = LocalTutorMemoryRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      await repository.saveCandidate(
        _candidate('export', 'Personal preference'),
      );

      final result = await repository.exportRedacted();

      final export =
          jsonDecode((result as Success<String>).value) as Map<String, dynamic>;
      expect(export['schemaVersion'], 1);
      expect(
        (export['facts'] as List<dynamic>).single['content'],
        '[redacted]',
      );
      expect((result).value, isNot(contains('Personal preference')));
    });

    test(
      'delete all removes every declared tutor key and its quarantine key',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = LocalTutorMemoryRepository(keyValueStore: store);
        for (final key in StorageKeys.tutorAiData) {
          store.values[key] = 'data';
          store.values[StorageKeys.quarantineOf(key)] = 'corrupt';
        }

        expect(await repository.deleteAllAiData(), isA<Success<void>>());

        for (final key in StorageKeys.tutorAiData) {
          expect(store.contains(key), isFalse, reason: key);
          expect(
            store.contains(StorageKeys.quarantineOf(key)),
            isFalse,
            reason: '$key corrupt',
          );
        }
      },
    );

    test(
      'does not report success when a delete all removal is refused',
      () async {
        final store = InMemoryKeyValueStore()
          ..failingKeys.add(StorageKeys.tutorMemoryFacts);
        final repository = LocalTutorMemoryRepository(keyValueStore: store);

        final result = await repository.deleteAllAiData();

        expect(result, isA<Failure<void>>());
        expect((result as Failure<void>).error.code, FailureCode.storageWrite);
      },
    );
  });
}

TutorMemoryCandidate _candidate(
  String id,
  String content, {
  DateTime? expiresAt,
}) => TutorMemoryCandidate(
  id: id,
  content: content,
  conversationId: TutorConversationId('conversation-$id'),
  messageId: TutorMessageId('message-$id'),
  createdAt: DateTime.utc(2026, 8, 5, 11),
  expiresAt: expiresAt,
);
