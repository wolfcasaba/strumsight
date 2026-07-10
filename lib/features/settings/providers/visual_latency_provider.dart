import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Calibrated tap-vs-FLASH latency in MILLISECONDS (chunk 016b P3, the
/// visual half): input + display lag, from the Settings tap-test's Visual
/// mode. Combined with [inputLatencyProvider] (tap-vs-CLICK = input + audio
/// lag) their DIFFERENCE is the audio↔display skew the Learn highway shifts
/// its drawn playhead by, so the arrow crosses the strike line exactly when
/// the beat is HEARD. Persisted; local-only (per-device). 0 = uncalibrated.
class VisualLatencyNotifier extends Notifier<int> {
  static const _key = 'visual_latency_ms';
  static const defaultValue = 0;
  static const minMs = -300;
  static const maxMs = 300;

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
      if (v != null && !_userSet) state = v.clamp(minMs, maxMs);
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(int ms) async {
    _userSet = true;
    state = ms.clamp(minMs, maxMs);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_key, state);
  }
}

final visualLatencyProvider =
    NotifierProvider<VisualLatencyNotifier, int>(VisualLatencyNotifier.new);
