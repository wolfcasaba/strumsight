import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's pinned chord labels (round 108). Local-only, like all
/// practice-habit state.
class FavoriteChordsNotifier extends Notifier<Set<String>> {
  static const _key = 'favorite_chords';

  SharedPreferences? _prefs;
  bool _userSet = false;

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final list = _prefs!.getStringList(_key);
      // Don't clobber a toggle made before prefs finished loading.
      if (list != null && !_userSet) state = list.toSet();
    } catch (_) {
      // Prefs unavailable → keep the default.
    }
  }

  Future<void> toggle(String label) async {
    _userSet = true;
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
