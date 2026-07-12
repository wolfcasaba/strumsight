import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_repository.dart';
import '../model/analyzed_session.dart';

/// Loads and mutates the saved-session library (newest first, bounded to 100).
class LibraryController extends AsyncNotifier<List<AnalyzedSession>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  static const _maxSessions = 100;

  @override
  Future<List<AnalyzedSession>> build() => _repo.load();

  /// The loaded list, WAITING for the initial load if it is still in flight
  /// (r150, the r149 race class): `state.value ?? []` during AsyncLoading let
  /// an add-from-Analyze save a single-element list over the whole on-disk
  /// library. On a load error an empty list is accepted (nothing to lose).
  Future<List<AnalyzedSession>> _current() async {
    try {
      return await future;
    } catch (_) {
      return state.value ?? const [];
    }
  }

  Future<void> add(AnalyzedSession session) async {
    final current = await _current();
    var next = [session, ...current];
    if (next.length > _maxSessions) next = next.sublist(0, _maxSessions);
    state = AsyncData(next);
    await _repo.save(next);
  }

  Future<void> delete(String id) async {
    final current = await _current();
    final next = current.where((s) => s.id != id).toList();
    state = AsyncData(next);
    await _repo.save(next);
  }

  /// Rename a saved session (round 106). Blank names are ignored — a title
  /// must never become empty.
  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final current = await _current();
    final next = [
      for (final s in current) s.id == id ? s.withTitle(trimmed) : s,
    ];
    state = AsyncData(next);
    await _repo.save(next);
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryController, List<AnalyzedSession>>(
  LibraryController.new,
);
