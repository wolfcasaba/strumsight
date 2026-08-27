import '../../song_trainer/domain/repositories/setlist_repository.dart';
import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// Wraps the existing [SetlistRepository] (read-only in this round; §0.0/B3).
final class SetlistItemSource implements LibraryItemSource {
  const SetlistItemSource(this._repository);

  final SetlistRepository _repository;

  @override
  LibraryItemType get type => LibraryItemType.setlist;

  @override
  Future<LibrarySourceLoad> load() async {
    final result = await _repository.list();
    return result.fold(
      onSuccess: (setlists) => LibrarySourceLoad.success([
        for (final setlist in setlists)
          SetlistLibraryItem(
            id: setlist.id,
            title: setlist.name,
            songCount: setlist.items.length,
            updatedAt: setlist.updatedAt,
            syncStatus: LibrarySyncStatus.synced,
          ),
      ]),
      onFailure: (error) => LibrarySourceLoad.unavailable(error.code),
    );
  }
}
