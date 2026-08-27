import '../../song_trainer/domain/repositories/song_repository.dart';
import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// Wraps the existing [SongRepository] (read-only in this round; §0.0/B3
/// names only `libraryProvider.notifier.delete` / `AnalysisRepository` as
/// sanctioned delete owners).
final class SongItemSource implements LibraryItemSource {
  const SongItemSource(this._repository);

  final SongRepository _repository;

  @override
  LibraryItemType get type => LibraryItemType.song;

  @override
  Future<LibrarySourceLoad> load() async {
    final result = await _repository.list(const SongQuery());
    return result.fold(
      onSuccess: (summaries) => LibrarySourceLoad.success([
        for (final summary in summaries)
          SongLibraryItem(
            id: summary.documentId.value,
            title: summary.title,
            artist: summary.artist,
            updatedAt: summary.updatedAt,
            syncStatus: LibrarySyncStatus.synced,
          ),
      ]),
      onFailure: (error) => LibrarySourceLoad.unavailable(error.code),
    );
  }
}
