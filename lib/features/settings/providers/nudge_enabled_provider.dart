import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/nudge_service.dart';

/// Whether the OPT-IN daily practice reminder (19:00 local, chunk 013's
/// retention TODO) is on. Persisted; local-only (notification permission is
/// per-device). The toggle reflects REALITY: if the platform refuses
/// (permission denied), the state reverts to off instead of lying.
class NudgeEnabledNotifier extends Notifier<bool> {
  static const _key = 'nudge_enabled';

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

  /// Startup reconcile (round 82): if the persisted state says ON, verify the
  /// notification can really fire (permission may have been revoked in system
  /// settings; a force-stop clears the alarm) and re-arm it idempotently.
  /// Flips the toggle OFF — honestly — when the platform says no. No-op when
  /// the reminder is off. Never ASKS for permission (no startup ambush).
  Future<void> reconcile(
      {required String title, required String body}) async {
    _prefs ??= await SharedPreferences.getInstance();
    final persisted = _prefs!.getBool(_key) ?? false;
    if (!persisted) return;
    final live = await NudgeService.instance
        .verifyAndRearm(title: title, body: body);
    if (!live && !_userSet) {
      state = false;
      await _prefs!.setBool(_key, false);
    }
  }

  /// Turn the reminder on/off. [title]/[body] are the localised notification
  /// texts (resolved by the caller, which has a BuildContext). Returns the
  /// EFFECTIVE state.
  Future<bool> setEnabled(bool on,
      {required String title, required String body}) async {
    _userSet = true;
    var effective = on;
    if (on) {
      effective = await NudgeService.instance.enable(title: title, body: body);
    } else {
      await NudgeService.instance.disable();
    }
    state = effective;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_key, effective);
    return effective;
  }
}

final nudgeEnabledProvider =
    NotifierProvider<NudgeEnabledNotifier, bool>(NudgeEnabledNotifier.new);
