import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// The learner's preferred play-along practice speed (tempo multiplier).
/// Persisted locally so it sticks across lessons/sessions (round 132 — a
/// beginner who drills at 75 % shouldn't re-select it on every lesson open,
/// the way the metronome-mute pref already persists, round 39). Yousician /
/// Simply both remember the practice tempo.
class PracticeSpeedController extends Notifier<double>
    with PersistedPreference<double> {
  /// The selectable multipliers (must match the Learn screen's chips).
  static const options = [0.5, 0.75, 1.0];
  static const defaultValue = 1.0;

  @override
  double build() {
    // A stored value no longer offered (an older/newer build's grid) falls back
    // to the default instead of putting the UI in a state its chips can't show.
    final v = preferences.readDouble(StorageKeys.practiceSpeed);
    return v != null && options.contains(v) ? v : defaultValue;
  }

  Future<void> set(double value) async {
    if (!options.contains(value)) return; // never persist an off-grid speed
    state = value;
    await persist(
      StorageKeys.practiceSpeed,
      (store) => store.writeDouble(StorageKeys.practiceSpeed, value),
    );
  }
}

final practiceSpeedProvider = NotifierProvider<PracticeSpeedController, double>(
  PracticeSpeedController.new,
);
