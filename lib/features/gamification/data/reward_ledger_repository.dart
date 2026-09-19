import '../domain/rewards/reward_ledger_entry.dart';

/// A stable, immutable page from the reward ledger.
final class RewardLedgerPage {
  RewardLedgerPage({
    required List<RewardLedgerEntry> entries,
    required this.nextCursor,
  }) : entries = List<RewardLedgerEntry>.unmodifiable(entries);

  final List<RewardLedgerEntry> entries;

  /// Opaque continuation cursor, or null when this is the final page.
  final String? nextCursor;
}

/// Append-only source of truth for reward decisions.
abstract interface class RewardLedgerRepository {
  /// Default maximum entries returned by [readPage].
  static const int defaultPageLimit = 100;

  /// Appends [entry] only when its source event has not already been recorded.
  ///
  /// Returns true when the entry is present after this call. A false result
  /// means the source event was already present, or the best-effort document
  /// write did not leave the new entry readable.
  Future<bool> appendIfAbsent(RewardLedgerEntry entry);

  /// Whether [sourceEventId] already has a ledger record.
  Future<bool> containsSourceEventId(String sourceEventId);

  /// Reads a deterministic page ordered by caller-provided timestamp and IDs.
  ///
  /// Feed [RewardLedgerPage.nextCursor] back as [cursor] to continue. [limit]
  /// must be positive; zero would make continuation impossible.
  Future<RewardLedgerPage> readPage({
    int limit = defaultPageLimit,
    String? cursor,
  });
}
