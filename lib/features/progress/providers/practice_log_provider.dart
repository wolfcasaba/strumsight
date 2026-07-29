import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/practice_log_repository.dart';
import '../model/practice_entry.dart';

/// The raw practice-history log, persisted locally (like the streak — per-device
/// habit state, not synced). Append a [PracticeEntry] from any real practice
/// moment (Live/Analyze/Learn) via [record]; the Progress dashboard reads the
/// list and rolls it up through `PracticeStats`.
///
/// The list is kept newest-last and capped at [PracticeLogRepository.maxEntries]
/// entries so a heavy user's document stays bounded; the dashboard only ever
/// needs recent history + totals, and the oldest entries are the least
/// interesting.
///
/// The r149 data-loss bug (an entry recorded before the async load finished
/// overwrote the on-disk history with just itself) is structurally gone in
/// E01-R07: the log is read synchronously in [build], so there is no window
/// between "empty default" and "loaded history" to write into.
class PracticeLogController extends Notifier<List<PracticeEntry>> {
  PracticeLogRepository get _repo => ref.read(practiceLogRepositoryProvider);

  static const _cap = PracticeLogRepository.maxEntries;

  @override
  List<PracticeEntry> build() => _repo.load();

  /// Append one practice moment and persist. Best-effort: an entry is never lost
  /// from this session's in-memory state even if the disk write fails.
  Future<void> record(PracticeEntry entry) async {
    final next = [...state, entry];
    // Bound the document — drop the oldest once over the cap.
    state = next.length > _cap ? next.sublist(next.length - _cap) : next;
    await _repo.save(state);
  }
}

final practiceLogProvider =
    NotifierProvider<PracticeLogController, List<PracticeEntry>>(
      PracticeLogController.new,
    );
