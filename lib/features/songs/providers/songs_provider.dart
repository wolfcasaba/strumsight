import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/music/strum.dart';
import '../data/songs_repository.dart';
import '../model/song.dart';

/// The user's saved songs, persisted locally (like the library — offline,
/// per-device, not synced). Newest-first for display.
///
/// The r149/r150 load-race guard (a `Completer` every mutation had to await, so
/// an add could not persist the empty default over the unread songbook) is gone
/// with the async load itself (E01-R07): the songbook is read synchronously in
/// [build] from the injected repository, so a mutation always starts from the
/// stored list.
class SongsController extends Notifier<List<Song>> {
  SongsRepository get _repo => ref.read(songsRepositoryProvider);

  int _seq = 0; // disambiguates ids created within the same microsecond

  @override
  List<Song> build() => _repo.load();

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Create a new song (newest-first) and persist. Returns its id.
  Future<String> add({
    required String name,
    required List<String> chords,
    required List<StrumDirection?> pattern,
    required int bpm,
    int beatsPerBar = 4,
  }) async {
    final song = Song(
      id: _newId(),
      name: name,
      chords: chords,
      pattern: pattern,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
    );
    var next = [song, ...state];
    // Documented cap (§7.5) — the OLDEST song is evicted, never the new one.
    if (next.length > SongsRepository.maxSongs) {
      next = next.sublist(0, SongsRepository.maxSongs);
    }
    state = next;
    await _repo.save(state);
    return song.id;
  }

  /// Replace an existing song by id (no-op if the id is gone).
  Future<void> update(Song song) async {
    if (!state.any((s) => s.id == song.id)) return;
    state = [
      for (final s in state)
        if (s.id == song.id) song else s,
    ];
    await _repo.save(state);
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _repo.save(state);
  }

  /// Undo of [remove]: re-insert [song] at its original [index] (clamped to the
  /// current bounds) with all fields intact, persisting like a normal save.
  /// No-op if a song with the same id is already present.
  Future<void> restore(int index, Song song) async {
    if (state.any((s) => s.id == song.id)) return;
    final next = [...state];
    next.insert(index.clamp(0, next.length), song);
    state = next;
    await _repo.save(state);
  }
}

final songsProvider = NotifierProvider<SongsController, List<Song>>(
  SongsController.new,
);
