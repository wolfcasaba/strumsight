/// Presentation-layer seams for the E13-R22 result/history/Speed Builder
/// screens (§0.0/B/R6 — practice `domain`/`data`/`application` stay
/// read-only for this round; every provider here either reads an existing
/// repository or exposes a pure local-only value).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_result.dart';
import '../../../gamification/public.dart';
import '../../application/gamification_practice_adapter.dart';
import '../../data/local_practice_history_repository.dart';
import '../../domain/model/practice_history_entry.dart';
import '../../domain/model/practice_mode.dart';

/// The reward ledger the result screen reads — the gamification feature's
/// own composition (`gamificationRewardLedgerRepositoryProvider`, ADR 0496
/// §1). Until the javító sáv 2026-09-06 this defaulted to an always-empty
/// ledger, so the screen could never show a reward; the V2 session now
/// writes the ledger through `practice_session_after_record.dart`, and the
/// screen reads the SAME instance. Tests override this seam.
final rewardLedgerRepositoryProvider = Provider<RewardLedgerRepository>(
  (ref) => ref.watch(gamificationRewardLedgerRepositoryProvider),
);

/// Ledger pages scanned per lookup. Bounded so a lookup can never loop
/// unboundedly over a corrupt or unexpectedly large ledger.
const int _rewardLookupPageSize = 100;
const int _rewardLookupMaxPages = 20;

/// Reads the reward ledger entry for one finished practice session, or
/// `null` when the ledger has not recorded one (ADR 0283 §Döntés 4 — the
/// screen never estimates a reward, it only reads what the ledger already
/// wrote). This is a pure read: it never calls [RewardLedgerRepository.appendIfAbsent],
/// so reopening the same session's result always returns the same answer —
/// the A5 idempotency guarantee at the UI boundary.
final practiceRewardForSessionProvider =
    Provider.family<RewardLedgerEntry?, String>((ref, sessionId) {
      final ledger = ref.watch(rewardLedgerRepositoryProvider);
      final eventId = GamificationPracticeAdapter.stableEventId(sessionId);
      String? cursor;
      for (var page = 0; page < _rewardLookupMaxPages; page++) {
        final result = ledger.readPage(
          limit: _rewardLookupPageSize,
          cursor: cursor,
        );
        for (final entry in result.entries) {
          if (entry.sourceEventId == eventId) return entry;
        }
        final next = result.nextCursor;
        if (next == null) break;
        cursor = next;
      }
      return null;
    });

/// The persisted practice history. [practiceHistoryRepositoryProvider] is
/// local storage only (ADR 0283 §Döntés 3) — this provider never depends on
/// any network provider, so the History screen is offline-capable by
/// construction.
final practiceHistoryEntriesProvider =
    FutureProvider.autoDispose<AppResult<List<PracticeHistoryEntry>>>((ref) {
      final repository = ref.watch(practiceHistoryRepositoryProvider);
      return repository.load();
    });

/// The active mode filter on the History screen. `null` means "all modes".
class PracticeHistoryModeFilterNotifier extends Notifier<PracticeMode?> {
  @override
  PracticeMode? build() => null;

  void set(PracticeMode? mode) => state = mode;
}

final practiceHistoryModeFilterProvider =
    NotifierProvider<PracticeHistoryModeFilterNotifier, PracticeMode?>(
      PracticeHistoryModeFilterNotifier.new,
    );
