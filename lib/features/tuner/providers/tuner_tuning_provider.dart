import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';
import '../model/tuning.dart';

/// The tuner's selected tuning. Persisted by id; LOCAL-only (a device/session
/// preference like the A4 reference — never synced).
class TunerTuningNotifier extends Notifier<Tuning>
    with PersistedPreference<Tuning> {
  @override
  Tuning build() {
    final id = preferences.readString(StorageKeys.tunerTuning);
    // `byId` already falls back to standard for an id this build doesn't know.
    return id == null ? Tunings.standard : Tunings.byId(id);
  }

  Future<void> set(Tuning tuning) async {
    state = tuning;
    await persist(
      StorageKeys.tunerTuning,
      (store) => store.writeString(StorageKeys.tunerTuning, tuning.id),
    );
  }
}

final tunerTuningProvider = NotifierProvider<TunerTuningNotifier, Tuning>(
  TunerTuningNotifier.new,
);
