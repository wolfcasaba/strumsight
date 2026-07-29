import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/nudge_service.dart';
import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Whether the OPT-IN daily practice reminder (19:00 local, chunk 013's
/// retention TODO) is on. Persisted; local-only (notification permission is
/// per-device). The toggle reflects REALITY: if the platform refuses
/// (permission denied), the state reverts to off instead of lying.
class NudgeEnabledNotifier extends Notifier<bool>
    with PersistedPreference<bool> {
  /// Bumped by every [setEnabled]; lets [reconcile] tell "nothing happened
  /// while I was awaiting the platform" from "the user just decided".
  int _userEdits = 0;

  @override
  bool build() => preferences.readBool(StorageKeys.nudgeEnabled) ?? false;

  /// Startup reconcile (round 82): if the reminder is on, verify the
  /// notification can really fire (permission may have been revoked in system
  /// settings; a force-stop clears the alarm) and re-arm it idempotently.
  /// Flips the toggle OFF — honestly — when the platform says no. No-op when
  /// the reminder is off. Never ASKS for permission (no startup ambush).
  Future<void> reconcile({required NudgeCopyFor copyFor}) async {
    if (!state) return;
    final edits = _userEdits;
    final live = await NudgeService.instance.verifyAndRearm(copyFor: copyFor);
    // The user may have toggled the switch while the platform was answering —
    // that intent is newer than this check, so it must not be overwritten.
    if (!live && _userEdits == edits) {
      state = false;
      await persist(
        StorageKeys.nudgeEnabled,
        (store) => store.writeBool(StorageKeys.nudgeEnabled, false),
      );
    }
  }

  /// Turn the reminder on/off. [copyFor] resolves the localised per-day
  /// texts (the caller has a BuildContext). Returns the EFFECTIVE state.
  Future<bool> setEnabled(bool on, {required NudgeCopyFor copyFor}) async {
    _userEdits++;
    var effective = on;
    if (on) {
      effective = await NudgeService.instance.enable(copyFor: copyFor);
    } else {
      await NudgeService.instance.disable();
    }
    state = effective;
    await persist(
      StorageKeys.nudgeEnabled,
      (store) => store.writeBool(StorageKeys.nudgeEnabled, effective),
    );
    return effective;
  }
}

final nudgeEnabledProvider = NotifierProvider<NudgeEnabledNotifier, bool>(
  NudgeEnabledNotifier.new,
);
