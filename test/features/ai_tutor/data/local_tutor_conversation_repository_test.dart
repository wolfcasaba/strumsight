import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_conversation.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_conversation_repository.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('LocalTutorConversationRepository', () {
    test(
      'preserves the document when its index write fails and recovers later',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = LocalTutorConversationRepository(
          keyValueStore: store,
        );
        final conversation = _conversation('one', updatedMinute: 1);

        store.failingKeys.add(StorageKeys.tutorConversationIndex);
        expect(await repository.save(conversation), isA<Failure<void>>());
        store.failingKeys.remove(StorageKeys.tutorConversationIndex);

        final page = await repository.list(limit: 10);

        expect(page, isA<Success<TutorConversationPage>>());
        expect((page as Success<TutorConversationPage>).value.items, [
          conversation,
        ]);
        expect(store.readString(StorageKeys.tutorConversationIndex), isNotNull);
      },
    );

    test('paginates newest conversations without dropping the total', () async {
      final repository = LocalTutorConversationRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      await repository.save(_conversation('old', updatedMinute: 1));
      await repository.save(_conversation('middle', updatedMinute: 2));
      await repository.save(_conversation('new', updatedMinute: 3));

      final page = await repository.list(offset: 1, limit: 1);

      final result = page as Success<TutorConversationPage>;
      expect(result.value.items.single.id, TutorConversationId('middle'));
      expect(result.value.offset, 1);
      expect(result.value.total, 3);
      expect(result.value.hasMore, isTrue);
    });

    test('builds a structured summary with every message provenance', () async {
      final repository = LocalTutorConversationRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      final conversation = _conversation('summary', messageCount: 2);
      await repository.save(conversation);

      final summary = await repository.summary(conversation.id);

      final result = summary as Success<TutorConversationSummary?>;
      expect(result.value!.conversationId, conversation.id);
      expect(result.value!.messageCount, 2);
      expect(
        result.value!.messageProvenance.map((item) => item.messageId.value),
        ['summary-message-0', 'summary-message-1'],
      );
      expect(result.value!.messageProvenance.map((item) => item.role), [
        TutorMessageRole.user,
        TutorMessageRole.tutor,
      ]);
    });

    test(
      'quarantines one corrupt record while keeping other conversations readable',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = LocalTutorConversationRepository(
          keyValueStore: store,
        );
        final good = _conversation('good', updatedMinute: 1);
        await repository.save(good);
        final document =
            jsonDecode(
                  store.readString(StorageKeys.tutorConversationDocuments)!,
                )
                as Map<String, Object?>;
        final items = (document['items']! as List<Object?>).toList()
          ..add(<String, Object?>{
            'id': 'bad',
            'conversation': 'not-an-object',
          });
        document['items'] = items;
        store.values[StorageKeys.tutorConversationDocuments] = jsonEncode(
          document,
        );

        final page = await repository.list(limit: 10);

        expect((page as Success<TutorConversationPage>).value.items, [good]);
        expect(
          store.readString(
            StorageKeys.quarantineOf(StorageKeys.tutorConversationDocuments),
          ),
          contains('bad'),
        );
      },
    );

    test(
      'returns a storage failure instead of silently accepting a refused save',
      () async {
        final store = InMemoryKeyValueStore()
          ..failingKeys.add(StorageKeys.tutorConversationDocuments);
        final repository = LocalTutorConversationRepository(
          keyValueStore: store,
        );

        final result = await repository.save(_conversation('refused'));

        expect(result, isA<Failure<void>>());
        expect((result as Failure<void>).error, isA<StorageFailure>());
        expect(result.error.code, FailureCode.storageWrite);
      },
    );

    test('loads saved conversations after a repository restart', () async {
      final store = InMemoryKeyValueStore();
      final firstRepository = LocalTutorConversationRepository(
        keyValueStore: store,
      );
      final conversation = _conversation('restart', updatedMinute: 4);
      await firstRepository.save(conversation);

      final secondRepository = LocalTutorConversationRepository(
        keyValueStore: store,
      );
      final result = await secondRepository.get(conversation.id);

      expect((result as Success<TutorConversation?>).value, conversation);
    });
  });
}

TutorConversation _conversation(
  String id, {
  int updatedMinute = 1,
  int messageCount = 1,
}) {
  final createdAt = DateTime.utc(2026, 8, 5, 12);
  return TutorConversation(
    schemaVersion: 1,
    id: TutorConversationId(id),
    createdAt: createdAt,
    updatedAt: createdAt.add(Duration(minutes: updatedMinute)),
    locale: 'hu',
    status: TutorConversationStatus.active,
    messages: <TutorMessage>[
      for (var index = 0; index < messageCount; index++)
        TutorMessage(
          id: TutorMessageId('$id-message-$index'),
          role: index.isEven ? TutorMessageRole.user : TutorMessageRole.tutor,
          createdAt: createdAt.add(Duration(seconds: index)),
          sequence: index,
          deliveryState: TutorMessageDeliveryState.complete,
          blocks: <TutorContentBlock>[TutorTextBlock(text: 'message $index')],
        ),
    ],
  );
}
