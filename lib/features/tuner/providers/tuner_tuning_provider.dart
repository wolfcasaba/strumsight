import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/tuning.dart';

/// The tuner's selected tuning. Persisted by id; LOCAL-only (a device/session
/// preference like the A4 reference — never synced).
class TunerTuningNotifier extends Notifier<Tuning> {
  static const _key = 'tuner_tuning';

  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  Tuning build() {
    _load();
    return Tunings.standard;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final id = _prefs!.getString(_key);
      // Don't clobber a value the user changed before prefs finished loading.
      if (id != null && !_userSet) state = Tunings.byId(id);
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> set(Tuning tuning) async {
    _userSet = true;
    state = tuning;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, tuning.id);
  }
}

final tunerTuningProvider =
    NotifierProvider<TunerTuningNotifier, Tuning>(TunerTuningNotifier.new);
