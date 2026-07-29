import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Capo fret (0 = no capo). Persisted; **local-only** — a capo is a physical,
/// per-guitar, transient state, so unlike theme/A4 it is deliberately NOT
/// synced to the cloud profile. Display-side only: it transposes the shown
/// chord SHAPE (detected − capo); detection always runs at concert pitch.
class CapoNotifier extends Notifier<int> with PersistedPreference<int> {
  static const defaultValue = 0;
  static const minFret = 0;
  static const maxFret = 11; // 12 = octave = same pitch classes

  @override
  int build() {
    final v = preferences.readInt(StorageKeys.capoFret);
    return v == null ? defaultValue : v.clamp(minFret, maxFret);
  }

  Future<void> set(int value) async {
    state = value.clamp(minFret, maxFret);
    await persist(
      StorageKeys.capoFret,
      (store) => store.writeInt(StorageKeys.capoFret, state),
    );
  }
}

final capoProvider = NotifierProvider<CapoNotifier, int>(CapoNotifier.new);
