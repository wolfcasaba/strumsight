import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Calibrated mic→detection latency in MILLISECONDS (chunk 016b P3), from the
/// Settings tap-test. Persisted; **local-only** — latency is a property of
/// THIS device's audio path (mic, DSP, route), so unlike theme/A4 it is
/// deliberately NOT synced to the cloud profile. 0 = uncalibrated.
class InputLatencyNotifier extends Notifier<int> with PersistedPreference<int> {
  static const defaultValue = 0;
  static const minMs = -300;
  static const maxMs = 300;

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.inputLatencyMs);
    return v == null ? defaultValue : v.clamp(minMs, maxMs);
  }

  Future<void> set(int ms) async {
    state = ms.clamp(minMs, maxMs);
    await persist(
      StorageKeys.inputLatencyMs,
      (store) => store.writeInt(StorageKeys.inputLatencyMs, state),
    );
  }
}

final inputLatencyProvider = NotifierProvider<InputLatencyNotifier, int>(
  InputLatencyNotifier.new,
);
