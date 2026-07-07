import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Capo fret (0 = no capo). Persisted; **local-only** — a capo is a physical,
/// per-guitar, transient state, so unlike theme/A4 it is deliberately NOT
/// synced to the cloud profile. Display-side only: it transposes the shown
/// chord SHAPE (detected − capo); detection always runs at concert pitch.
class CapoNotifier extends Notifier<int> {
  static const _key = 'capo_fret';
  static const defaultValue = 0;
  static const minFret = 0;
  static const maxFret = 11; // 12 = octave = same pitch classes

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
      if (v != null && !_userSet) state = v.clamp(minFret, maxFret);
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(int value) async {
    _userSet = true;
    state = value.clamp(minFret, maxFret);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_key, state);
  }
}

final capoProvider =
    NotifierProvider<CapoNotifier, int>(CapoNotifier.new);
