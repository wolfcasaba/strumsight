import 'dart:async';
import 'dart:convert';

import '../../../core/foundation/json_validation.dart';
import '../../../core/storage/json_document_store.dart';
import '../domain/rewards/reward_ledger_entry.dart';
import 'reward_ledger_repository.dart';

/// Local, append-only reward ledger backed by one versioned JSON document.
///
/// Writes are serialised per repository instance. The document's whole-body
/// replacement provides the crash-recovery boundary: a restart sees either the
/// previous complete body or the complete body written by this append, never a
/// repository-level partial entry.
final class LocalRewardLedgerRepository implements RewardLedgerRepository {
  LocalRewardLedgerRepository({required this.document});

  final JsonDocumentStore document;
  Future<void> _appendTail = Future<void>.value();

  @override
  Future<bool> appendIfAbsent(RewardLedgerEntry entry) {
    final scheduled = _appendTail.then((_) => _append(entry));
    _appendTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  @override
  Future<bool> containsSourceEventId(String sourceEventId) {
    _validateSourceEventId(sourceEventId);
    return Future<bool>.value(
      _readState().sourceEventIds.contains(sourceEventId),
    );
  }

  @override
  Future<RewardLedgerPage> readPage({required int limit, String? cursor}) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final entries = _readState().entries..sort(_compareEntries);
    final position = cursor == null ? null : _LedgerCursor.decode(cursor);
    final start = position == null
        ? 0
        : entries.indexWhere(
            (entry) => _compareEntryToCursor(entry, position) > 0,
          );
    final safeStart = start < 0 ? entries.length : start;
    final end = (safeStart + limit).clamp(0, entries.length);
    final pageEntries = entries.sublist(safeStart, end);
    return Future<RewardLedgerPage>.value(
      RewardLedgerPage(
        entries: pageEntries,
        nextCursor: end == entries.length || pageEntries.isEmpty
            ? null
            : _LedgerCursor.fromEntry(pageEntries.last).encode(),
      ),
    );
  }

  Future<bool> _append(RewardLedgerEntry entry) async {
    final state = _readState();
    if (state.sourceEventIds.contains(entry.sourceEventId)) return false;

    await document.write(<Object?>[...state.rawItems, entry.toJson()]);
    return true;
  }

  _LedgerState _readState() {
    final body = document.readBody();
    if (body == null) return const _LedgerState.empty();
    if (body is! List) {
      document.logger.warning(
        'storage.document.body_not_a_list',
        fields: <String, Object?>{'document': document.name},
      );
      throw StateError('Reward ledger document body is not a list');
    }

    final rawItems = List<Object?>.from(body, growable: false);
    final entries = <RewardLedgerEntry>[];
    final sourceEventIds = <String>{};
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (!_isCurrentSchema(raw)) continue;
      try {
        final entry = RewardLedgerEntry.fromJson(raw);
        entries.add(entry);
        sourceEventIds.add(entry.sourceEventId);
      } on JsonRecordException catch (error) {
        _recordSkippedEntry(index, error);
      } on ArgumentError catch (error) {
        _recordSkippedEntry(index, error);
      }
    }
    return _LedgerState(
      rawItems: rawItems,
      entries: entries,
      sourceEventIds: sourceEventIds,
    );
  }

  bool _isCurrentSchema(Object? raw) {
    if (raw is! Map<String, dynamic>) return false;
    return raw['schemaVersion'] == rewardLedgerEntrySchemaVersion;
  }

  void _recordSkippedEntry(int index, Object error) {
    document.logger.warning(
      'storage.document.record_skipped',
      error: error,
      fields: <String, Object?>{
        'document': document.name,
        'index': index,
        'reason': 'invalid',
      },
    );
  }
}

final class _LedgerState {
  const _LedgerState({
    required this.rawItems,
    required this.entries,
    required this.sourceEventIds,
  });

  const _LedgerState.empty()
    : rawItems = const <Object?>[],
      entries = const <RewardLedgerEntry>[],
      sourceEventIds = const <String>{};

  final List<Object?> rawItems;
  final List<RewardLedgerEntry> entries;
  final Set<String> sourceEventIds;
}

final class _LedgerCursor {
  const _LedgerCursor({
    required this.createdAtMicroseconds,
    required this.ledgerId,
    required this.sourceEventId,
  });

  final int createdAtMicroseconds;
  final String ledgerId;
  final String sourceEventId;

  factory _LedgerCursor.fromEntry(RewardLedgerEntry entry) => _LedgerCursor(
    createdAtMicroseconds: entry.createdAt.toUtc().microsecondsSinceEpoch,
    ledgerId: entry.ledgerId,
    sourceEventId: entry.sourceEventId,
  );

  factory _LedgerCursor.decode(String cursor) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (decoded is! List || decoded.length != 3) {
        throw const FormatException();
      }
      final createdAt = decoded[0];
      final ledgerId = decoded[1];
      final sourceEventId = decoded[2];
      if (createdAt is! int ||
          ledgerId is! String ||
          ledgerId.isEmpty ||
          sourceEventId is! String ||
          sourceEventId.isEmpty) {
        throw const FormatException();
      }
      return _LedgerCursor(
        createdAtMicroseconds: createdAt,
        ledgerId: ledgerId,
        sourceEventId: sourceEventId,
      );
    } on FormatException {
      throw ArgumentError.value(cursor, 'cursor', 'is not a ledger cursor');
    }
  }

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode(<Object>[createdAtMicroseconds, ledgerId, sourceEventId]),
    ),
  );
}

int _compareEntries(RewardLedgerEntry left, RewardLedgerEntry right) =>
    _compareEntryFields(
      left.createdAt.toUtc().microsecondsSinceEpoch,
      left.ledgerId,
      left.sourceEventId,
      right.createdAt.toUtc().microsecondsSinceEpoch,
      right.ledgerId,
      right.sourceEventId,
    );

int _compareEntryToCursor(RewardLedgerEntry entry, _LedgerCursor cursor) =>
    _compareEntryFields(
      entry.createdAt.toUtc().microsecondsSinceEpoch,
      entry.ledgerId,
      entry.sourceEventId,
      cursor.createdAtMicroseconds,
      cursor.ledgerId,
      cursor.sourceEventId,
    );

int _compareEntryFields(
  int leftCreatedAt,
  String leftLedgerId,
  String leftSourceEventId,
  int rightCreatedAt,
  String rightLedgerId,
  String rightSourceEventId,
) {
  final timeOrder = leftCreatedAt.compareTo(rightCreatedAt);
  if (timeOrder != 0) return timeOrder;
  final ledgerOrder = leftLedgerId.compareTo(rightLedgerId);
  return ledgerOrder == 0
      ? leftSourceEventId.compareTo(rightSourceEventId)
      : ledgerOrder;
}

void _validateSourceEventId(String sourceEventId) {
  if (sourceEventId.trim().isEmpty) {
    throw ArgumentError.value(
      sourceEventId,
      'sourceEventId',
      'must not be blank',
    );
  }
}
