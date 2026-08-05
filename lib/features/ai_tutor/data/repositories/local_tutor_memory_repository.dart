import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_memory_fact.dart';
import '../../domain/repositories/tutor_memory_repository.dart';

/// Local, versioned memory with explicit retention and user-controlled erase.
final class LocalTutorMemoryRepository implements TutorMemoryRepository {
  LocalTutorMemoryRepository({required KeyValueStore keyValueStore})
    : this._(keyValueStore);

  LocalTutorMemoryRepository._(this._keyValueStore);

  static const int _schemaVersion = 1;

  final KeyValueStore _keyValueStore;

  @override
  Future<AppResult<List<TutorMemoryFact>>> list() async {
    try {
      return Success<List<TutorMemoryFact>>(_ordered(await _readFacts()));
    } on StorageException catch (error, stackTrace) {
      return _memoryReadFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryReadFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<TutorMemoryFact>> saveCandidate(
    TutorMemoryCandidate candidate,
  ) async {
    if (_isSensitive(candidate.content)) {
      return const Failure<TutorMemoryFact>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    try {
      final facts = await _readFacts();
      final fingerprint = _fingerprint(candidate.content);
      for (final fact in facts) {
        if (_fingerprint(fact.content) == fingerprint) {
          return Success<TutorMemoryFact>(fact);
        }
      }
      final fact = TutorMemoryFact(
        id: candidate.id,
        content: candidate.content,
        conversationId: candidate.conversationId,
        messageId: candidate.messageId,
        createdAt: candidate.createdAt,
        updatedAt: candidate.createdAt,
        expiresAt: candidate.expiresAt,
      );
      await _writeFacts(<TutorMemoryFact>[fact, ...facts]);
      return Success<TutorMemoryFact>(fact);
    } on StorageException catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<void>> update(TutorMemoryFact fact) async {
    if (_isSensitive(fact.content)) {
      return const Failure<void>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    try {
      final facts = await _readFacts();
      if (!facts.any((item) => item.id == fact.id)) {
        return const Failure<void>(
          ValidationFailure(code: FailureCode.validationInvalidInput),
        );
      }
      await _writeFacts(<TutorMemoryFact>[
        fact,
        for (final item in facts)
          if (item.id != fact.id) item,
      ]);
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<void>> delete(String factId) async {
    try {
      final facts = await _readFacts();
      await _writeFacts(<TutorMemoryFact>[
        for (final fact in facts)
          if (fact.id != factId) fact,
      ]);
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<void>> purgeExpired(DateTime now) async {
    try {
      final facts = await _readFacts();
      await _writeFacts(<TutorMemoryFact>[
        for (final fact in facts)
          if (!fact.isExpiredAt(now)) fact,
      ]);
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<String>> exportRedacted() async {
    try {
      final facts = await _readFacts();
      return Success<String>(
        jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'facts': <Object?>[
            for (final fact in _ordered(facts))
              <String, Object?>{
                'id': fact.id,
                'content': '[redacted]',
                'conversationId': fact.conversationId.value,
                'messageId': fact.messageId.value,
                'createdAt': fact.createdAt.toIso8601String(),
                'updatedAt': fact.updatedAt.toIso8601String(),
                'expiresAt': fact.expiresAt?.toIso8601String(),
              },
          ],
        }),
      );
    } on StorageException catch (error, stackTrace) {
      return _memoryReadFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryReadFailure(error, stackTrace);
    }
  }

  @override
  Future<AppResult<void>> deleteAllAiData() async {
    try {
      for (final key in StorageKeys.tutorAiData) {
        await _keyValueStore.remove(key);
        await _keyValueStore.remove(StorageKeys.quarantineOf(key));
      }
      return const Success<void>(null);
    } on StorageException catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    } catch (error, stackTrace) {
      return _memoryWriteFailure(error, stackTrace);
    }
  }

  Future<List<TutorMemoryFact>> _readFacts() async {
    final raw = _keyValueStore.readString(StorageKeys.tutorMemoryFacts);
    if (raw == null) return const <TutorMemoryFact>[];
    try {
      final envelope = _objectMap(raw == '' ? null : jsonDecode(raw));
      if (envelope['schemaVersion'] != _schemaVersion ||
          envelope['items'] is! List) {
        throw const FormatException();
      }
      return <TutorMemoryFact>[
        for (final item in envelope['items']! as List<Object?>)
          _factFromJson(item),
      ];
    } catch (_) {
      await _keyValueStore.writeString(
        StorageKeys.quarantineOf(StorageKeys.tutorMemoryFacts),
        raw,
      );
      await _writeFacts(const <TutorMemoryFact>[]);
      return const <TutorMemoryFact>[];
    }
  }

  Future<void> _writeFacts(List<TutorMemoryFact> facts) =>
      _keyValueStore.writeString(
        StorageKeys.tutorMemoryFacts,
        jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'items': <Object?>[
            for (final fact in _ordered(facts)) _factToJson(fact),
          ],
        }),
      );
}

Failure<T> _memoryReadFailure<T>(Object error, StackTrace stackTrace) =>
    Failure<T>(
      StorageFailure(
        code: FailureCode.storageRead,
        cause: error,
        stackTrace: stackTrace,
      ),
    );

Failure<T> _memoryWriteFailure<T>(Object error, StackTrace stackTrace) =>
    Failure<T>(
      StorageFailure(
        code: FailureCode.storageWrite,
        cause: error,
        stackTrace: stackTrace,
      ),
    );

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException();
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw const FormatException();
    result[entry.key as String] = entry.value;
  }
  return result;
}

TutorMemoryFact _factFromJson(Object? value) {
  final json = _objectMap(value);
  return TutorMemoryFact(
    id: _requiredString(json, 'id'),
    content: _requiredString(json, 'content'),
    conversationId: TutorConversationId(
      _requiredString(json, 'conversationId'),
    ),
    messageId: TutorMessageId(_requiredString(json, 'messageId')),
    createdAt: _utcTimestamp(json, 'createdAt'),
    updatedAt: _utcTimestamp(json, 'updatedAt'),
    expiresAt: json['expiresAt'] == null
        ? null
        : _utcTimestamp(json, 'expiresAt'),
  );
}

Map<String, Object?> _factToJson(TutorMemoryFact fact) => <String, Object?>{
  'id': fact.id,
  'content': fact.content,
  'conversationId': fact.conversationId.value,
  'messageId': fact.messageId.value,
  'createdAt': fact.createdAt.toIso8601String(),
  'updatedAt': fact.updatedAt.toIso8601String(),
  'expiresAt': fact.expiresAt?.toIso8601String(),
};

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw const FormatException();
  return value;
}

DateTime _utcTimestamp(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.endsWith('Z')) throw const FormatException();
  return parsed.toUtc();
}

List<TutorMemoryFact> _ordered(List<TutorMemoryFact> facts) {
  final result = List<TutorMemoryFact>.of(facts)
    ..sort((left, right) {
      final byUpdate = right.updatedAt.compareTo(left.updatedAt);
      return byUpdate != 0 ? byUpdate : left.id.compareTo(right.id);
    });
  return result;
}

String _fingerprint(String content) =>
    content.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _isSensitive(String content) => RegExp(
  r'\b(password|passcode|jelsz[oó]|api[ _-]?key|secret|token)\b|'
  r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b|\b\+?\d[\d ()-]{6,}\d\b',
  caseSensitive: false,
).hasMatch(content);
