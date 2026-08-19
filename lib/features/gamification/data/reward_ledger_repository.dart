import '../domain/rewards/reward_ledger_entry.dart';

/// Append-only local source of truth for rewarded learning activity.
abstract interface class RewardLedgerRepository {
  /// Adds [entry] when its source event has not been processed in this ledger.
  ///
  /// A true result means the entry joined the repository's in-memory session
  /// state. Its local disk write follows the existing best-effort storage
  /// contract.
  Future<bool> appendIfAbsent(RewardLedgerEntry entry);

  /// Whether the source event is already represented in this ledger.
  bool hasProcessedEvent(String sourceEventId);

  /// Returns one stable slice after an opaque [cursor].
  RewardLedgerPage readPage({required int limit, String? cursor});
}

/// A stable ledger slice for rebuilding projections without a full read.
final class RewardLedgerPage {
  RewardLedgerPage({
    required List<RewardLedgerEntry> entries,
    required this.nextCursor,
  }) : entries = List<RewardLedgerEntry>.unmodifiable(entries);

  final List<RewardLedgerEntry> entries;
  final String? nextCursor;
}
