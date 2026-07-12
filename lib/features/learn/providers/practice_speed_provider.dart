import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The learner's preferred play-along practice speed (tempo multiplier).
/// Persisted locally so it sticks across lessons/sessions (round 132 — a
/// beginner who drills at 75 % shouldn't re-select it on every lesson open,
/// the way the metronome-mute pref already persists, round 39). Yousician /
/// Simply both remember the practice tempo.
class PracticeSpeedController extends Notifier<double> {
  static const _key = 'practice_speed_v1';

  /// The selectable multipliers (must match the Learn screen's chips).
  static const options = [0.5, 0.75, 1.0];
  static const defaultValue = 1.0;

  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  double build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final v = _prefs!.getDouble(_key);
      // Don't clobber a value the user picked before prefs finished loading,
      // and ignore a stored value no longer in the options (forward-compat).
      if (v != null && !_userSet && options.contains(v)) state = v;
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(double value) async {
    if (!options.contains(value)) return; // never persist an off-grid speed
    _userSet = true;
    state = value;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setDouble(_key, value);
    } catch (_) {
      // Best-effort; state stays correct in memory for this session.
    }
  }
}

final practiceSpeedProvider =
    NotifierProvider<PracticeSpeedController, double>(
        PracticeSpeedController.new);
