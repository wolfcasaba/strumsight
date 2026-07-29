import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/setlists_repository.dart';
import '../model/setlist.dart';

/// The user's saved setlists, persisted locally (newest-first). Stores song ids
/// only; songs are resolved from the songbook at play time.
///
/// Like the songbook, the sets are read synchronously in [build] (E01-R07), so
/// the r149/r150 load-race guard is gone with the async load that needed it.
class SetlistsController extends Notifier<List<Setlist>> {
  SetlistsRepository get _repo => ref.read(setlistsRepositoryProvider);

  int _seq = 0;

  @override
  List<Setlist> build() => _repo.load();

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<String> add(String name) async {
    final s = Setlist(id: _newId(), name: name, songIds: const []);
    var next = [s, ...state];
    // Documented cap (§7.5) — the oldest set is evicted, never the new one.
    if (next.length > SetlistsRepository.maxSetlists) {
      next = next.sublist(0, SetlistsRepository.maxSetlists);
    }
    state = next;
    await _repo.save(state);
    return s.id;
  }

  Future<void> rename(String id, String name) =>
      _mutate(id, (s) => s.copyWith(name: name));

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _repo.save(state);
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
    if (!state.any((s) => s.id == id)) return;
    state = [
      for (final s in state)
        if (s.id == id) f(s) else s,
    ];
    await _repo.save(state);
  }
}

final setlistsProvider = NotifierProvider<SetlistsController, List<Setlist>>(
  SetlistsController.new,
);
