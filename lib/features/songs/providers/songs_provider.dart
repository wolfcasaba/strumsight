import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../live/model/strum.dart';
import '../model/song.dart';

/// The user's saved songs, persisted locally (like the library — offline,
/// per-device, not synced). Newest-first for display.
class SongsController extends Notifier<List<Song>> {
  static const _key = 'user_songs_v1';

  SharedPreferences? _prefs;
  // Mutations WAIT for the initial load (r150, the r149 race class): a
  // mutation racing the load used to persist the near-empty default over the
  // unread on-disk collection, wiping it.
  final Completer<void> _loaded = Completer<void>();
  int _seq = 0; // disambiguates ids created within the same microsecond

  @override
  List<Song> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        state = (jsonDecode(raw) as List)
            .map((e) => Song.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Prefs unavailable → keep the empty default.
    } finally {
      _loaded.complete();
    }
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

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
    await _loaded.future;
    state = [song, ...state];
    await _persist();
    return song.id;
  }

  /// Replace an existing song by id (no-op if the id is gone).
  Future<void> update(Song song) async {
    if (!state.any((s) => s.id == song.id)) return;
    await _loaded.future;
    state = [for (final s in state) if (s.id == song.id) song else s];
    await _persist();
  }

  Future<void> remove(String id) async {
    await _loaded.future;
    state = state.where((s) => s.id != id).toList();
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

final songsProvider =
    NotifierProvider<SongsController, List<Song>>(SongsController.new);
