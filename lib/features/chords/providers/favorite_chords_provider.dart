import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's pinned chord labels (round 108). Local-only, like all
/// practice-habit state.
class FavoriteChordsNotifier extends Notifier<Set<String>> {
  static const _key = 'favorite_chords';

  SharedPreferences? _prefs;
  // Mutations WAIT for the initial load (r150, the r149 race class): a
  // mutation racing the load used to persist the near-empty default over the
  // unread on-disk collection, wiping it.
  final Completer<void> _loaded = Completer<void>();

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final list = _prefs!.getStringList(_key);
      if (list != null) state = list.toSet();
    } catch (_) {
      // Prefs unavailable → keep the default.
    } finally {
      _loaded.complete();
    }
  }

  Future<void> toggle(String label) async {
    await _loaded.future; // merge onto the LOADED set, never the default
    state = state.contains(label)
        ? ({...state}..remove(label))
        : {...state, label};
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_key, state.toList()..sort());
  }
}

final favoriteChordsProvider =
    NotifierProvider<FavoriteChordsNotifier, Set<String>>(
        FavoriteChordsNotifier.new);
