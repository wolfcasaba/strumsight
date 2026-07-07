import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_repository.dart';
import '../model/analyzed_session.dart';

/// Loads and mutates the saved-session library (newest first, bounded to 100).
class LibraryController extends AsyncNotifier<List<AnalyzedSession>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  static const _maxSessions = 100;

  @override
  Future<List<AnalyzedSession>> build() => _repo.load();

  Future<void> add(AnalyzedSession session) async {
    final current = state.value ?? const [];
    var next = [session, ...current];
    if (next.length > _maxSessions) next = next.sublist(0, _maxSessions);
    state = AsyncData(next);
    await _repo.save(next);
  }

  Future<void> delete(String id) async {
    final current = state.value ?? const [];
    final next = current.where((s) => s.id != id).toList();
    state = AsyncData(next);
    await _repo.save(next);
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryController, List<AnalyzedSession>>(
  LibraryController.new,
);
