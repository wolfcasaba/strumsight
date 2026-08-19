import '../../../core/logging/app_logger.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import 'reward_ledger_repository.dart';

/// Local append-only reward ledger with serialized append-if-absent calls.
final class LocalRewardLedgerRepository implements RewardLedgerRepository {
  LocalRewardLedgerRepository({
    required KeyValueStore store,
    required AppLogger logger,
  }) : _document = JsonDocumentStore(
         store: store,
         logger: logger,
         key: storageKey,
         legacyKey: _legacyStorageKey,
         name: _documentName,
         bodyKey: _bodyKey,
       );

  static const String storageKey = 'ss.gamification.reward_ledger';
  static const String _legacyStorageKey = 'gamification.reward_ledger_v1';
  static const String _documentName = 'reward_ledger';
  static const String _bodyKey = 'data';
  static const String _entriesKey = 'entries';
  static const String _processedEventIdsKey = 'processedEventIds';

  final JsonDocumentStore _document;
  final List<RewardLedgerEntry> _entries = <RewardLedgerEntry>[];
  final List<Object?> _rawEntries = <Object?>[];
  final Set<String> _processedEventIds = <String>{};
  Future<void> _appendTail = Future<void>.value();
  bool _loaded = false;

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) {
    final scheduled = _appendTail.then((_) => _append(entry));
    _appendTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  bool hasProcessedEvent(String sourceEventId) {
    _ensureLoaded();
    return _processedEventIds.contains(sourceEventId);
  }

  @override
  RewardLedgerPage readPage({required int limit, String? cursor}) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least one');
    }
    _ensureLoaded();

    var start = 0;
    if (cursor != null) {
      final cursorIndex = _entries.indexWhere(
        (entry) => entry.sourceEventId == cursor,
      );
      if (cursorIndex < 0) {
        throw ArgumentError.value(cursor, 'cursor', 'is not in this ledger');
      }
      start = cursorIndex + 1;
    }

    final tentativeEnd = start + limit;
    final end = tentativeEnd < _entries.length ? tentativeEnd : _entries.length;
    final entries = _entries.sublist(start, end);
    return RewardLedgerPage(
      entries: entries,
      nextCursor: end < _entries.length ? entries.last.sourceEventId : null,
    );
  }

  Future<bool> _append(RewardLedgerEntry entry) async {
    _ensureLoaded();
    if (_processedEventIds.contains(entry.sourceEventId)) return false;

    _entries.add(entry);
    _rawEntries.add(entry.toJson());
    _processedEventIds.add(entry.sourceEventId);
    await _document.write(_snapshot());
    return true;
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;

    final body = _document.readBody();
    if (body is! Map<String, Object?>) return;
    final storedEntries = body[_entriesKey];
    if (storedEntries is! List<Object?>) return;

    for (var index = 0; index < storedEntries.length; index++) {
      final rawEntry = storedEntries[index];
      _rawEntries.add(rawEntry);
      final sourceEventId = _sourceEventId(rawEntry);
      if (sourceEventId != null) _processedEventIds.add(sourceEventId);

      try {
        _entries.add(RewardLedgerEntry.fromJson(rawEntry));
      } on ArgumentError catch (error, stackTrace) {
        _document.logger.warning(
          'gamification.reward_ledger.entry_isolated',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{'index': index},
        );
      }
    }
  }

  Map<String, Object?> _snapshot() => <String, Object?>{
    _entriesKey: List<Object?>.from(_rawEntries),
    _processedEventIdsKey: _processedEventIds.toList()..sort(),
  };
}

String? _sourceEventId(Object? rawEntry) {
  if (rawEntry is! Map<String, Object?>) return null;
  final sourceEventId = rawEntry['sourceEventId'];
  return sourceEventId is String && sourceEventId.trim().isNotEmpty
      ? sourceEventId
      : null;
}
