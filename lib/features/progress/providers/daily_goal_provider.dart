import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// The user's daily practice goal in **minutes**, persisted locally (a retention
/// mechanic — a concrete daily target, like Yousician/Simply). Defaults to
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
