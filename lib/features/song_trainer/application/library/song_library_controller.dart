import 'dart:async';

import '../../../../core/foundation/app_result.dart';
import '../../data/importers/native_json_exporter.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/repositories/song_repository.dart';
import 'song_library_state.dart';
import 'song_query.dart';

/// Index-only controller for Song Library V2.
///
/// A full document is deliberately never requested here: cards render only
/// [SongSummary] data maintained by the repository index.
final class SongLibraryController {
  SongLibraryController(this._repository);

  final SongRepository _repository;
  final StreamController<SongLibraryState> _states =
      StreamController<SongLibraryState>.broadcast(sync: true);
  SongLibraryState _state = const SongLibraryState.loading();
  List<SongSummary> _allSummaries = const <SongSummary>[];
  final Set<SongId> _favoriteIds = <SongId>{};
  var _disposed = false;

  SongLibraryState get state => _state;
  Stream<SongLibraryState> get states => _states.stream;

  Future<void> load() async {
    if (_disposed) return;
    _set(const SongLibraryState.loading());
    final result = await _repository.list(const SongQuery());
    if (_disposed) return;
    if (result case Failure<List<SongSummary>>(:final error)) {
      _set(
        SongLibraryState(
          status: SongLibraryStatus.failure,
          summaries: const <SongSummary>[],
          query: _state.query,
          failureCode: error.code,
        ),
      );
      return;
    }
    _allSummaries = (result as Success<List<SongSummary>>).value;
    _publish(query: _state.query);
  }

  void setQuery(SongLibraryQuery query) {
    if (_disposed) return;
    _publish(query: query);
  }

  Future<void> moveToTrash(SongId id) async {
    if (_disposed) return;
    final result = await _repository.moveToTrash(id);
    if (_disposed) return;
    if (result case Failure<void>(:final error)) {
      _set(
        _state.copyWith(
          status: SongLibraryStatus.failure,
          failureCode: error.code,
        ),
      );
      return;
    }
    _allSummaries = _allSummaries
        .where((item) => item.documentId != id)
        .toList(growable: false);
    _publish(query: _state.query, undoSongId: id);
  }

  /// Changes the library-local favorite view without decoding a document.
  void toggleFavorite(SongId id) {
    if (_disposed) return;
    if (!_favoriteIds.add(id)) _favoriteIds.remove(id);
    _publish(query: _state.query, undoSongId: _state.undoSongId);
  }

  /// Builds the R09 privacy-scrubbed native artifact only after an explicit
  /// export action. The list itself remains summary-only.
  Future<NativeJsonExport?> export(SongId id) async {
    if (_disposed) return null;
    final result = await _repository.get(id);
    if (_disposed) return null;
    if (result case Failure(:final error)) {
      _set(
        _state.copyWith(
          status: SongLibraryStatus.failure,
          failureCode: error.code,
        ),
      );
      return null;
    }
    final document = (result as Success<SongDocument?>).value;
    if (document == null) {
      _set(
        _state.copyWith(
          status: SongLibraryStatus.failure,
          failureCode: SongRepositoryErrorCode.notFound,
        ),
      );
      return null;
    }
    return const NativeJsonExporter().export(document);
  }

  Future<void> undoTrash() async {
    final id = _state.undoSongId;
    if (_disposed || id == null) return;
    final result = await _repository.restore(id);
    if (_disposed) return;
    if (result case Failure<void>(:final error)) {
      _set(
        _state.copyWith(
          status: SongLibraryStatus.failure,
          failureCode: error.code,
        ),
      );
      return;
    }
    await load();
  }

  void _publish({required SongLibraryQuery query, SongId? undoSongId}) {
    var visible = _allSummaries
        .where((summary) {
          final normalizedSearch = query.searchText.trim().toLowerCase();
          final titleMatches =
              normalizedSearch.isEmpty ||
              summary.title.toLowerCase().contains(normalizedSearch) ||
              (summary.artist?.toLowerCase().contains(normalizedSearch) ??
                  false);
          return titleMatches &&
              (query.sourceType == null ||
                  summary.sourceType == query.sourceType) &&
              (!query.favoritesOnly ||
                  summary.favorite ||
                  _favoriteIds.contains(summary.documentId));
        })
        .toList(growable: false);
    visible = switch (query.sort) {
      SongLibrarySort.recent =>
        visible..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      SongLibrarySort.title =>
        visible..sort((a, b) => a.title.compareTo(b.title)),
    };
    _set(
      SongLibraryState(
        status: SongLibraryStatus.ready,
        summaries: List<SongSummary>.unmodifiable(visible),
        query: query,
        undoSongId: undoSongId,
        favoriteIds: _favoriteIds,
      ),
    );
  }

  void _set(SongLibraryState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _states.close();
  }
}
