import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether to render chord diagrams **left-handed** (high-E string on the left).
/// Persisted locally; a per-player physical preference (like the capo), not
/// synced. Default: right-handed.
class LeftHandedController extends Notifier<bool> {
  static const _key = 'left_handed_v1';

  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final v = _prefs!.getBool(_key);
      if (v != null && !_userSet) state = v;
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(bool value) async {
    _userSet = true;
    state = value;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_key, state);
    } catch (_) {
      // Best-effort.
    }
  }
}

final leftHandedProvider =
    NotifierProvider<LeftHandedController, bool>(LeftHandedController.new);
