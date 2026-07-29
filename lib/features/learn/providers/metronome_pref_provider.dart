import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// Whether the play-along metronome is muted. Persisted locally so the choice
/// sticks across lessons/sessions (RAG chunk 014). Default: not muted (hear it).
class MetronomeMutedController extends Notifier<bool>
    with PersistedPreference<bool> {
  @override
  bool build() => preferences.readBool(StorageKeys.metronomeMuted) ?? false;

  Future<void> toggle() async {
    state = !state;
    await persist(
      StorageKeys.metronomeMuted,
      (store) => store.writeBool(StorageKeys.metronomeMuted, state),
    );
  }
}

final metronomeMutedProvider = NotifierProvider<MetronomeMutedController, bool>(
  MetronomeMutedController.new,
);
