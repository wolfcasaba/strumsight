import '../../../../core/foundation/app_result.dart';
import '../model/practice_history_entry.dart';

/// Persists the immutable Practice History V2 — one record per finished
/// session, keyed by `sessionId`, idempotent on re-record (ADR 0084
/// §Döntés 4), versioned and capped (ADR 0084 §Döntés 2–3).
///
/// Implementations must NEVER swallow storage errors with an empty
/// `catch` — the contract is `AppResult.failure(StorageFailure)` so the
/// caller can surface the error to the user (ADR 0084 §Döntés 5).
abstract interface class PracticeHistoryRepository {
  /// Documented storage bound (SDD §20.1, ADR 0084 §Döntés 3): the newest
  /// [maxSessions] saved records are kept, older ones evicted.
  static const int maxSessions = 200;

  /// Number of most-recent attempts whose per-attempt metrics are kept.
  /// Older sessions retain the summary only.
  static const int maxDetailedAttempts = practiceHistoryDetailLimit;

  /// Load the persisted history, newest-first.
  ///
  /// Returns `Success([])` on a fresh install — never null.
  Future<AppResult<List<PracticeHistoryEntry>>> load();

  /// Persist [entry] (or update the existing record with the same
  /// [PracticeHistoryEntry.id]). Never throws; reports via [AppResult].
  Future<AppResult<void>> save(PracticeHistoryEntry entry);

  /// Remove every persisted record. Used by diagnostics / tests.
  Future<AppResult<void>> clear();
}
