import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/setlist.dart';

/// The user's saved setlists, persisted locally (newest-first). Stores song ids
/// only; songs are resolved from the songbook at play time.
class SetlistsController extends Notifier<List<Setlist>> {
  static const _key = 'user_setlists_v1';

  SharedPreferences? _prefs;
  // Mutations WAIT for the initial load (r150, the r149 race class): a
  // mutation racing the load used to persist the near-empty default over the
  // unread on-disk collection, wiping it.
  final Completer<void> _loaded = Completer<void>();
  int _seq = 0;

  @override
  List<Setlist> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        state = (jsonDecode(raw) as List)
            .map((e) => Setlist.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Prefs unavailable → keep the empty default.
    } finally {
      // Riverpod keeps the notifier instance across ref.invalidate — build()
      // and _load() re-run on the SAME object, so the Completer may already
      // be done (r158 probe: 'Bad state: Future already completed').
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<String> add(String name) async {
    final s = Setlist(id: _newId(), name: name, songIds: const []);
    await _loaded.future;
    state = [s, ...state];
    await _persist();
    return s.id;
  }

  Future<void> rename(String id, String name) =>
      _mutate(id, (s) => s.copyWith(name: name));

  Future<void> remove(String id) async {
    await _loaded.future;
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  /// Append a song id (allowing duplicates — a set can repeat a song).
  Future<void> addSong(String setlistId, String songId) =>
      _mutate(setlistId, (s) => s.copyWith(songIds: [...s.songIds, songId]));

  Future<void> removeAt(String setlistId, int index) => _mutate(setlistId, (s) {
        if (index < 0 || index >= s.songIds.length) return s;
        final ids = [...s.songIds]..removeAt(index);
        return s.copyWith(songIds: ids);
      });

  /// Reorder within a setlist (ReorderableListView semantics: [oldIndex] item
  /// moves to [newIndex]).
  Future<void> reorder(String setlistId, int oldIndex, int newIndex) =>
      _mutate(setlistId, (s) {
        final ids = [...s.songIds];
        if (oldIndex < 0 || oldIndex >= ids.length) return s;
        var to = newIndex;
        if (to > oldIndex) to -= 1; // account for the removed slot
        final moved = ids.removeAt(oldIndex);
        ids.insert(to.clamp(0, ids.length), moved);
        return s.copyWith(songIds: ids);
      });

  Future<void> _mutate(String id, Setlist Function(Setlist) f) async {
    await _loaded.future; // the existence check must see the LOADED list
    if (!state.any((s) => s.id == id)) return;
    state = [for (final s in state) if (s.id == id) f(s) else s];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _key,
        jsonEncode(state.map((s) => s.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort; state stays correct in memory for this session.
    }
  }
}

final setlistsProvider =
    NotifierProvider<SetlistsController, List<Setlist>>(SetlistsController.new);
