import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/streak_repository.dart';
import '../model/streak_data.dart';
import '../streak_logic.dart';

/// Practice-streak state, persisted locally (RAG chunk 013 — retention). Call
/// [StreakController.recordPracticeToday] from any real practice moment (a Live
/// session that detects playing, or a completed Analyze). Local-only, like the
/// capo: a streak is per-device habit state, not a synced profile field.
///
/// The stored streak is read synchronously in [build] (E01-R07), so the r150
/// guard is unnecessary: a cold-start practice moment can no longer apply onto
/// the empty default and persist a streak of 1 over a multi-day streak.
class StreakController extends Notifier<StreakData> {
  StreakRepository get _repo => ref.read(streakRepositoryProvider);

  @override
  StreakData build() => _repo.load() ?? const StreakData();

  /// Record that the user practised now. Idempotent within a calendar day.
  /// Returns true if this call advanced the streak (i.e. first practice today).
  Future<bool> recordPracticeToday([DateTime? now]) async {
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final next = StreakLogic.applyPractice(state, today);
    if (next == state) return false; // already practised today / no change
    state = next;
    await _repo.save(state);
    return true;
  }
}

final streakProvider = NotifierProvider<StreakController, StreakData>(
  StreakController.new,
);
