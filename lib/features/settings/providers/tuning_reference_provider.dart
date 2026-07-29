import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Concert-pitch reference A4 in Hz. Persisted; defaults to 440 (standard).
/// Clamped to a sane range that matches the backend contract (400..480).
class TuningReferenceNotifier extends Notifier<int>
    with PersistedPreference<int> {
  static const defaultValue = 440;
  static const minHz = 400;
  static const maxHz = 480;

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.tuningA4);
    return v == null ? defaultValue : v.clamp(minHz, maxHz);
  }

  Future<void> set(int value) async {
    state = value.clamp(minHz, maxHz);
    await persist(
      StorageKeys.tuningA4,
      (store) => store.writeInt(StorageKeys.tuningA4, state),
    );
  }
}

final tuningReferenceProvider = NotifierProvider<TuningReferenceNotifier, int>(
  TuningReferenceNotifier.new,
);
