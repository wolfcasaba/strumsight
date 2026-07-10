import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Calibrated mic→detection latency in MILLISECONDS (chunk 016b P3), from the
/// Settings tap-test. Persisted; **local-only** — latency is a property of
/// THIS device's audio path (mic, DSP, route), so unlike theme/A4 it is
/// deliberately NOT synced to the cloud profile. 0 = uncalibrated.
class InputLatencyNotifier extends Notifier<int> {
  static const _key = 'input_latency_ms';
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

final inputLatencyProvider =
    NotifierProvider<InputLatencyNotifier, int>(InputLatencyNotifier.new);
