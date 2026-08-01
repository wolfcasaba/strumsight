import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';
import '../../practice/public.dart';

/// The user's daily practice goal in **minutes**, persisted locally (a retention
/// mechanic — a concrete daily target, like Yousician / Simply). Defaults to
/// [defaultMinutes]; clamped to a sensible range.
class DailyGoalController extends Notifier<int> with PersistedPreference<int> {
  static const int defaultMinutes = 10;
  static const int minMinutes = 5;
  static const int maxMinutes = 120;

  /// The presets the picker offers.
  static const List<int> presets = [5, 10, 15, 20, 30, 45, 60];

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.dailyGoalMinutes);
    return v == null ? defaultMinutes : v.clamp(minMinutes, maxMinutes);
  }

  Future<void> setGoal(int minutes) async {
    state = minutes.clamp(minMinutes, maxMinutes);
    await persist(
      StorageKeys.dailyGoalMinutes,
      (store) => store.writeInt(StorageKeys.dailyGoalMinutes, state),
    );
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalController, int>(
  DailyGoalController.new,
);

/// Seconds of practice on [today] (an epoch day) that count toward the
/// daily-goal ring — **active time only** (ADR 0085 Döntés 5, SDD §20.4 /
/// §12.2).
///
/// - On the V2 path it sums each aggregated entry's `seconds` (which already
///   comes from `PracticeHistoryEntry.activeDuration.inSeconds`).
/// - On the V1 path it reads the recorded `seconds` field unchanged (the V1
///   log is bájtra érintetlen, A10).
/// - Count-in, pause, setup and result never bleed in (A5).
///
/// Exposed as a family so the calling widget passes its OWN `today` (the
/// screen's `now` parameter) — keeps the dashboard's day-rollups consistent
/// in widget tests with an injected clock.
final dailyGoalActiveSecondsProvider = Provider.family<int, int>((ref, today) {
  final aggregator = ref.watch(practiceProgressAggregatorProvider);
  final entries = ref.watch(aggregatedPracticeFeedProvider);
  return aggregator.secondsForDay(entries, today);
});
