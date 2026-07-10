import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's daily practice goal in **minutes**, persisted locally (a retention
/// mechanic — a concrete daily target, like Yousician/Simply). Defaults to
/// [defaultMinutes]; clamped to a sensible range.
class DailyGoalController extends Notifier<int> {
  static const _key = 'daily_goal_min_v1';
  static const int defaultMinutes = 10;
  static const int minMinutes = 5;
  static const int maxMinutes = 120;

  /// The presets the picker offers.
  static const List<int> presets = [5, 10, 15, 20, 30, 45, 60];

  SharedPreferences? _prefs;
  bool _dirty = false;

  @override
  int build() {
    _load();
    return defaultMinutes;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final v = _prefs!.getInt(_key);
      if (v != null && !_dirty) state = v.clamp(minMinutes, maxMinutes);
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> setGoal(int minutes) async {
    _dirty = true;
    state = minutes.clamp(minMinutes, maxMinutes);
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt(_key, state);
    } catch (_) {
      // Best-effort; state stays correct in memory for this session.
    }
  }
}

final dailyGoalProvider =
    NotifierProvider<DailyGoalController, int>(DailyGoalController.new);
