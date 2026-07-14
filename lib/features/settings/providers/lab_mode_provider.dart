import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lab mode (ship-path step 4, r197): an OPT-IN diagnostics switch. When ON,
/// the Analyze batch path ALSO runs the ML chord model alongside the DSP one
/// and attaches both timelines + their agreement to the result (for the
/// upcoming ML-vs-DSP diagnostics). Default FALSE — when off, the analyze path
/// does ZERO extra work and the result shape is unchanged.
///
/// Persisted, local-only (a per-device developer/diagnostic toggle). Mirrors
/// the [NudgeEnabledNotifier] persistence pattern.
class LabModeNotifier extends Notifier<bool> {
  static const _key = 'lab_mode';

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
      // Prefs unavailable → keep the default (off).
    }
  }

  /// Turn Lab mode on/off and persist it.
  Future<void> setEnabled(bool on) async {
    _userSet = true;
    state = on;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_key, on);
  }
}

final labModeProvider =
    NotifierProvider<LabModeNotifier, bool>(LabModeNotifier.new);
