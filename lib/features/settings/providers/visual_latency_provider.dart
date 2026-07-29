import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Calibrated tap-vs-FLASH latency in MILLISECONDS (chunk 016b P3, the
/// visual half): input + display lag, from the Settings tap-test's Visual
/// mode. Combined with [inputLatencyProvider] (tap-vs-CLICK = input + audio
/// lag) their DIFFERENCE is the audio↔display skew the Learn highway shifts
/// its drawn playhead by, so the arrow crosses the strike line exactly when
/// the beat is HEARD. Persisted; local-only (per-device). 0 = uncalibrated.
class VisualLatencyNotifier extends Notifier<int>
    with PersistedPreference<int> {
  static const defaultValue = 0;
  static const minMs = -300;
  static const maxMs = 300;

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.visualLatencyMs);
    return v == null ? defaultValue : v.clamp(minMs, maxMs);
  }

  Future<void> set(int ms) async {
    state = ms.clamp(minMs, maxMs);
    await persist(
      StorageKeys.visualLatencyMs,
      (store) => store.writeInt(StorageKeys.visualLatencyMs, state),
    );
  }
}

final visualLatencyProvider = NotifierProvider<VisualLatencyNotifier, int>(
  VisualLatencyNotifier.new,
);
