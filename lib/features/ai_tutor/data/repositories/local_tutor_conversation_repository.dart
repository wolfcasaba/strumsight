import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../domain/models/tutor_conversation.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/repositories/tutor_conversation_repository.dart';
import '../local/tutor_conversation_codec.dart';

/// Versioned local tutor conversation storage with a rebuildable index.
///
/// Documents are written before their lightweight index. A refused index write
/// therefore reports failure without losing the conversation: the next list
/// rebuilds the index from the document envelope.
final class LocalTutorConversationRepository
    implements TutorConversationRepository {
  LocalTutorConversationRepository({required KeyValueStore keyValueStore})
    : this._(keyValueStore);

  LocalTutorConversationRepository._(this._keyValueStore);

  static const int _schemaVersion = 1;

  final KeyValueStore _keyValueStore;
  final TutorConversationCodec _codec = const TutorConversationCodec();

  @override
  Future<AppResult<void>> save(TutorConversation conversation) async {
    try {
      final documents = await _readDocuments();
      final next = <TutorConversation>[
        conversation,
        for (final document in documents)
          if (document.id != conversation.id) document,
      ];
      await _writeDocuments(next);
      await _writeIndex(_ordered(next));
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _writeFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _writeFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<TutorConversation?>> get(TutorConversationId id) async {
    try {
      final documents = await _readDocuments();
      for (final document in documents) {
        if (document.id == id) return Success<TutorConversation?>(document);
      }
      return const Success<TutorConversation?>(null);
    } on StorageException catch (error, stackTrace) {
      return _readFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _readFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<TutorConversationPage>> list({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0 || limit <= 0) {
      return const Failure<TutorConversationPage>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    try {
      final ordered = _ordered(await _readDocuments());
      await _recoverIndexIfNeeded(ordered);
      final end = (offset + limit).clamp(0, ordered.length);
      final page = offset >= ordered.length
          ? const <TutorConversation>[]
          : ordered.sublist(offset, end);
      return Success<TutorConversationPage>(
        TutorConversationPage(
          items: page,
          offset: offset,
          total: ordered.length,
        ),
      );
    } on StorageException catch (error, stackTrace) {
      return _readFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _readFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<TutorConversationSummary?>> summary(
    TutorConversationId id,
  ) async {
    final result = await get(id);
    switch (result) {
      case Failure<TutorConversation?>(:final error):
        return Failure<TutorConversationSummary?>(error);
      case Success<TutorConversation?>(value: null):
        return const Success<TutorConversationSummary?>(null);
      case Success<TutorConversation?>(value: final value?):
        return Success<TutorConversationSummary?>(
          TutorConversationSummary(
            conversationId: value.id,
            messageCount: value.messages.length,
            messageProvenance: [
              for (final message in value.messages)
                TutorMessageProvenance(
                  messageId: message.id,
                  role: message.role,
                  sequence: message.sequence,
                ),
            ],
          ),
        );
    }
  }

  @override
  Future<AppResult<void>> delete(TutorConversationId id) async {
    try {
      final documents = await _readDocuments();
      final next = <TutorConversation>[
        for (final document in documents)
          if (document.id != id) document,
      ];
      await _writeDocuments(next);
      await _writeIndex(_ordered(next));
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _writeFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _writeFailure(error, stackTrace);
    }
  }

  Future<List<TutorConversation>> _readDocuments() async {
    final raw = _keyValueStore.readString(
      StorageKeys.tutorConversationDocuments,
    );
    if (raw == null) return const <TutorConversation>[];
    final List<Object?> encodedItems;
    try {
      final envelope = _objectMap(jsonDecode(raw));
      if (envelope['schemaVersion'] != _schemaVersion) {
        throw const FormatException();
      }
      final items = envelope['items'];
      if (items is! List) {
        throw const FormatException();
      }
      encodedItems = List<Object?>.from(items);
    } catch (_) {
      await _quarantineDocument(raw);
      return const <TutorConversation>[];
    }
    final documents = <TutorConversation>[];
    final corruptRecords = <Object?>[];
    for (final rawRecord in encodedItems) {
      try {
        final record = _objectMap(rawRecord);
        final conversationJson = _objectMap(record['conversation']);
        final conversation = _codec.decode(
          utf8.encode(jsonEncode(conversationJson)),
        );
        if (record['id'] != conversation.id.value) {
          throw const FormatException();
        }
        documents.add(conversation);
      } catch (_) {
        corruptRecords.add(rawRecord);
      }
    }
    if (corruptRecords.isNotEmpty) {
      await _keyValueStore.writeString(
        StorageKeys.quarantineOf(StorageKeys.tutorConversationDocuments),
        jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'items': corruptRecords,
        }),
      );
      await _writeDocuments(documents);
    }
    return documents;
  }

  Future<void> _quarantineDocument(String raw) async {
    await _keyValueStore.writeString(
      StorageKeys.quarantineOf(StorageKeys.tutorConversationDocuments),
      raw,
    );
    await _writeDocuments(const <TutorConversation>[]);
  }

  Future<void> _recoverIndexIfNeeded(List<TutorConversation> documents) async {
    final expected = documents.map((document) => document.id.value).toList();
    final raw = _keyValueStore.readString(StorageKeys.tutorConversationIndex);
    try {
      final envelope = raw == null ? null : _objectMap(jsonDecode(raw));
      final items = envelope?['items'];
      if (envelope?['schemaVersion'] == _schemaVersion &&
          items is List &&
          _sameStrings(items, expected)) {
        return;
      }
    } catch (_) {
      // The document envelope is authoritative; rebuilding below recovers it.
    }
    await _writeIndex(documents);
  }

  Future<void> _writeDocuments(List<TutorConversation> documents) =>
      _keyValueStore.writeString(
        StorageKeys.tutorConversationDocuments,
        jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'items': <Object?>[
            for (final document in documents)
              <String, Object?>{
                'id': document.id.value,
                'conversation': jsonDecode(
                  utf8.decode(_codec.encode(document)),
                ),
              },
          ],
        }),
      );

  Future<void> _writeIndex(List<TutorConversation> documents) =>
      _keyValueStore.writeString(
        StorageKeys.tutorConversationIndex,
        jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'items': [for (final document in documents) document.id.value],
        }),
      );

  List<TutorConversation> _ordered(List<TutorConversation> documents) {
    final result = List<TutorConversation>.of(documents)
      ..sort((left, right) {
        final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
        return byUpdatedAt != 0
            ? byUpdatedAt
            : left.id.value.compareTo(right.id.value);
      });
    return result;
  }
}

Failure<T> _readFailure<T>(Object error, StackTrace stackTrace) => Failure<T>(
  StorageFailure(
    code: FailureCode.storageRead,
    cause: error,
    stackTrace: stackTrace,
  ),
);

Failure<T> _writeFailure<T>(Object error, StackTrace stackTrace) => Failure<T>(
  StorageFailure(
    code: FailureCode.storageWrite,
    cause: error,
    stackTrace: stackTrace,
  ),
);

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException();
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

bool _sameStrings(List<Object?> actual, List<String> expected) =>
    actual.length == expected.length &&
    actual.indexed.every(
      (entry) => entry.$2 is String && entry.$2 == expected[entry.$1],
    );
