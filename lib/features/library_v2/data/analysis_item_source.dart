import '../../audio_analysis/domain/analysis_repository.dart';
import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// Wraps the existing [AnalysisRepository] — the ONLY entry point this
/// source reads from (§0.0/B3). Never decodes a full [AnalysisDocument];
/// `list()` already returns index-only summaries.
final class AnalysisItemSource implements LibraryItemSource {
  const AnalysisItemSource(this._repository);

  final AnalysisRepository _repository;

  @override
  LibraryItemType get type => LibraryItemType.analysis;

  @override
  Future<LibrarySourceLoad> load() async {
    final result = await _repository.list();
    return result.fold(
      onSuccess: (summaries) => LibrarySourceLoad.success([
        for (final summary in summaries)
          AnalysisLibraryItem(
            id: summary.documentId,
            title: summary.title,
            createdAt: summary.createdAt,
            syncStatus: LibrarySyncStatus.synced,
            // Production never retains raw audio today
            // (AudioRetentionPolicy.defaultPolicy) — honest until a future
            // round wires retention (§5.5 doc comment on the field).
            hasRawAudio: false,
            hasResult: true,
          ),
      ]),
      onFailure: (error) => LibrarySourceLoad.unavailable(error.code),
    );
  }
}
