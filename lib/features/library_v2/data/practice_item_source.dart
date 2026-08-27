import '../../practice/domain/repository/practice_history_repository.dart';
import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// Wraps the existing [PracticeHistoryRepository] (read-only in this round —
/// no per-entry delete exists on that contract yet, §0.0/B3).
final class PracticeItemSource implements LibraryItemSource {
  const PracticeItemSource(this._repository);

  final PracticeHistoryRepository _repository;

  @override
  LibraryItemType get type => LibraryItemType.practice;

  @override
  Future<LibrarySourceLoad> load() async {
    final result = await _repository.load();
    return result.fold(
      onSuccess: (entries) => LibrarySourceLoad.success([
        for (final entry in entries)
          PracticeLibraryItem(
            id: entry.id,
            title: entry.displayTitle,
            createdAt: entry.createdAt,
            syncStatus: LibrarySyncStatus.synced,
          ),
      ]),
      onFailure: (error) => LibrarySourceLoad.unavailable(error.code),
    );
  }
}
