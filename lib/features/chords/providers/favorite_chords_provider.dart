import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_preference.dart';
import '../../../core/storage/storage_keys.dart';

/// The user's pinned chord labels (round 108). Local-only, like all
/// practice-habit state.
///
/// The r149/r150 load-race guard (a `Completer` mutations had to await, so a
/// toggle could not persist the empty default over the unread on-disk set) is
/// gone with the async load itself: the initial set is read synchronously in
/// [build], so a mutation always merges onto the stored collection.
class FavoriteChordsNotifier extends Notifier<Set<String>>
    with PersistedPreference<Set<String>> {
  @override
  Set<String> build() {
    final list = preferences.readStringList(StorageKeys.favoriteChords);
    return list == null ? const {} : Set.unmodifiable(list);
  }

  Future<void> toggle(String label) async {
    state = state.contains(label)
        ? ({...state}..remove(label))
        : {...state, label};
    await persist(
      StorageKeys.favoriteChords,
      (store) => store.writeStringList(
        StorageKeys.favoriteChords,
        state.toList()..sort(),
      ),
    );
  }
}

final favoriteChordsProvider =
    NotifierProvider<FavoriteChordsNotifier, Set<String>>(
      FavoriteChordsNotifier.new,
    );
