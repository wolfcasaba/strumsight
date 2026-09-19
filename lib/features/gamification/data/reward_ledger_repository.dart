import '../domain/rewards/reward_ledger_entry.dart';

/// Append-only store for idempotent reward decisions.
abstract interface class RewardLedgerRepository {
  /// Adds [entry] when its source event has not yet been processed.
  ///
  /// Returns `true` only for the call that accepted the event. The local store
  /// is best-effort persistent; a platform write failure is logged by its
  /// [JsonDocumentStore] and does not make this method promise durability.
  Future<bool> appendIfAbsent(RewardLedgerEntry entry);

  /// Looks up a processed event through the repository's source-ID index.
  Future<bool> containsSourceEventId(String sourceEventId);

  /// Reads one stable, ascending page for projection rebuilding.
  Future<RewardLedgerPage> readPage({required int limit, String? cursor});
}

/// One page from an append-only reward ledger.
final class RewardLedgerPage {
  RewardLedgerPage({required List<RewardLedgerEntry> entries, this.nextCursor})
    : entries = List<RewardLedgerEntry>.unmodifiable(entries);

  final List<RewardLedgerEntry> entries;

  /// Opaque continuation cursor, or `null` at the final page.
  final String? nextCursor;
}
