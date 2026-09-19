import '../../../core/storage/json_document_store.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import 'reward_ledger_repository.dart';

/// Local append-only reward ledger over one uncapped JSON document.
///
/// Every append rewrites the complete raw document through [JsonDocumentStore]
/// so the underlying whole-document recovery semantics apply. Entries this
/// build cannot decode stay in the raw list unchanged; a future schema's
/// source-event ID still participates in deduplication.
final class LocalRewardLedgerRepository implements RewardLedgerRepository {
  LocalRewardLedgerRepository({required JsonDocumentStore document})
    : _document = document;

  final JsonDocumentStore _document;
  final Set<String> _processedSourceEventIds = <String>{};
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) async {
    if (_readSnapshot().sourceEventIds.contains(entry.sourceEventId)) {
      return false;
    }
    await Future<void>.delayed(Duration.zero);
    final snapshot = _readSnapshot();
    await _document.write(<Object?>[...snapshot.rawEntries, entry.toJson()]);
    return _readSnapshot().sourceEventIds.contains(entry.sourceEventId);
  }

  @override
  Future<bool> containsSourceEventId(String sourceEventId) {
    _validateSourceEventId(sourceEventId);
    return _enqueue<bool>(() async {
      final snapshot = _readSnapshot();
      _replaceProcessedIndex(snapshot.sourceEventIds);
      return snapshot.sourceEventIds.contains(sourceEventId);
    });
  }

  @override
  Future<RewardLedgerPage> readPage({
    int limit = RewardLedgerRepository.defaultPageLimit,
    String? cursor,
  }) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }
    final offset = _cursorOffset(cursor);
    return _enqueue<RewardLedgerPage>(() async {
      final snapshot = _readSnapshot();
      _replaceProcessedIndex(snapshot.sourceEventIds);
      final entries = _ordered(snapshot.entries);
      final start = offset > entries.length ? entries.length : offset;
      final end = (start + limit) > entries.length
          ? entries.length
          : start + limit;
      return RewardLedgerPage(
        entries: entries.sublist(start, end),
        nextCursor: end < entries.length ? end.toString() : null,
      );
    });
  }

  Future<bool> _appendIfAbsent(RewardLedgerEntry entry) async {
    if (_processedSourceEventIds.contains(entry.sourceEventId)) return false;

    final snapshot = _readSnapshot();
    _replaceProcessedIndex(snapshot.sourceEventIds);
    if (_processedSourceEventIds.contains(entry.sourceEventId)) return false;

    await _document.write(<Object?>[...snapshot.rawEntries, entry.toJson()]);

    final recovered = _readSnapshot();
    _replaceProcessedIndex(recovered.sourceEventIds);
    return recovered.sourceEventIds.contains(entry.sourceEventId);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final scheduled = _operationTail.then<T>((_) => operation());
    _operationTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  _LedgerSnapshot _readSnapshot() {
    final body = _document.readBody();
    if (body == null) return _LedgerSnapshot.empty();
    if (body is! List<Object?>) {
      _document.logger.warning(
        'storage.document.body_not_a_list',
        fields: <String, Object?>{'document': _document.name},
      );
      return _LedgerSnapshot.empty();
    }

    final rawEntries = List<Object?>.from(body);
    final sourceEventIds = <String>{};
    final entries = <RewardLedgerEntry>[];
    for (var index = 0; index < rawEntries.length; index++) {
      final rawEntry = rawEntries[index];
      final sourceEventId = _rawSourceEventId(rawEntry);
      if (sourceEventId != null && !sourceEventIds.add(sourceEventId)) {
        _recordSkippedEntry(index, 'duplicate_source_event_id');
        continue;
      }
      try {
        final entry = RewardLedgerEntry.fromJson(rawEntry);
        sourceEventIds.add(entry.sourceEventId);
        entries.add(entry);
      } on ArgumentError {
        _recordSkippedEntry(index, 'unknown_or_invalid_reward_ledger_entry');
      }
    }
    return _LedgerSnapshot(
      rawEntries: rawEntries,
      sourceEventIds: sourceEventIds,
      entries: entries,
    );
  }

  String? _rawSourceEventId(Object? rawEntry) {
    if (rawEntry is! Map<Object?, Object?>) return null;
    final value = rawEntry['sourceEventId'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  void _replaceProcessedIndex(Set<String> sourceEventIds) {
    _processedSourceEventIds
      ..clear()
      ..addAll(sourceEventIds);
  }

  void _recordSkippedEntry(int index, String reason) {
    _document.logger.warning(
      'storage.document.record_skipped',
      fields: <String, Object?>{
        'document': _document.name,
        'index': index,
        'reason': reason,
      },
    );
  }
}

final class _LedgerSnapshot {
  _LedgerSnapshot({
    required List<Object?> rawEntries,
    required Set<String> sourceEventIds,
    required List<RewardLedgerEntry> entries,
  }) : rawEntries = List<Object?>.unmodifiable(rawEntries),
       sourceEventIds = Set<String>.unmodifiable(sourceEventIds),
       entries = List<RewardLedgerEntry>.unmodifiable(entries);

  factory _LedgerSnapshot.empty() => _LedgerSnapshot(
    rawEntries: const <Object?>[],
    sourceEventIds: const <String>{},
    entries: const <RewardLedgerEntry>[],
  );

  final List<Object?> rawEntries;
  final Set<String> sourceEventIds;
  final List<RewardLedgerEntry> entries;
}

List<RewardLedgerEntry> _ordered(List<RewardLedgerEntry> entries) {
  final ordered = List<RewardLedgerEntry>.from(entries);
  ordered.sort((left, right) {
    final byCreatedAt = left.createdAt.compareTo(right.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    final byLedgerId = left.ledgerId.compareTo(right.ledgerId);
    if (byLedgerId != 0) return byLedgerId;
    return left.sourceEventId.compareTo(right.sourceEventId);
  });
  return ordered;
}

int _cursorOffset(String? cursor) {
  if (cursor == null) return 0;
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(
      cursor,
      'cursor',
      'must be a non-negative offset',
    );
  }
  return offset;
}

void _validateSourceEventId(String sourceEventId) {
  if (sourceEventId.trim().isEmpty) {
    throw ArgumentError.value(
      sourceEventId,
      'sourceEventId',
      'must not be empty or blank',
    );
  }
}
