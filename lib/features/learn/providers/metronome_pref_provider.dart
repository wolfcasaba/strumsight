import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the play-along metronome is muted. Persisted locally so the choice
/// sticks across lessons/sessions (RAG chunk 014). Default: not muted (hear it).
class MetronomeMutedController extends Notifier<bool> {
  static const _key = 'metronome_muted_v1';

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

  Future<void> toggle() async {
    _userSet = true;
    state = !state;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_key, state);
    } catch (_) {
      // Best-effort.
    }
  }
}

final metronomeMutedProvider =
    NotifierProvider<MetronomeMutedController, bool>(
        MetronomeMutedController.new);
