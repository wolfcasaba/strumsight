import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Concert-pitch reference A4 in Hz. Persisted; defaults to 440 (standard).
/// Clamped to a sane range that matches the backend contract (400..480).
class TuningReferenceNotifier extends Notifier<int> {
  static const _key = 'tuning_a4';
  static const defaultValue = 440;
  static const minHz = 400;
  static const maxHz = 480;

  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  int build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final v = _prefs!.getInt(_key);
      // Don't clobber a value the user changed before prefs finished loading.
      if (v != null && !_userSet) state = v.clamp(minHz, maxHz);
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(int value) async {
    _userSet = true;
    state = value.clamp(minHz, maxHz);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_key, state);
  }
}

final tuningReferenceProvider =
    NotifierProvider<TuningReferenceNotifier, int>(TuningReferenceNotifier.new);
