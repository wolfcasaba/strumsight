import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Lab mode (ship-path step 4, r197): an OPT-IN diagnostics switch. When ON,
/// the Analyze batch path ALSO runs the ML chord model alongside the DSP one
/// and attaches both timelines + their agreement to the result (for the
/// upcoming ML-vs-DSP diagnostics). Default FALSE — when off, the analyze path
/// does ZERO extra work and the result shape is unchanged.
///
/// Persisted, local-only (a per-device developer/diagnostic toggle). Mirrors
/// the [NudgeEnabledNotifier] persistence pattern.
class LabModeNotifier extends Notifier<bool> with PersistedPreference<bool> {
  @override
  bool build() => preferences.readBool(StorageKeys.labMode) ?? false;

  /// Turn Lab mode on/off and persist it.
  Future<void> setEnabled(bool on) async {
    state = on;
    await persist(
      StorageKeys.labMode,
      (store) => store.writeBool(StorageKeys.labMode, on),
    );
  }
}

final labModeProvider = NotifierProvider<LabModeNotifier, bool>(
  LabModeNotifier.new,
);
