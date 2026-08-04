import '../../domain/models/song_id.dart';
import '../../domain/repositories/song_repository.dart';
import 'song_query.dart';

enum SongLibraryStatus { loading, ready, failure }

/// Immutable state used by the V2 library screen.
final class SongLibraryState {
  const SongLibraryState({
    required this.status,
    required this.summaries,
    required this.query,
    this.failureCode,
    this.undoSongId,
    this.favoriteIds = const <SongId>{},
  });

  const SongLibraryState.loading()
    : this(
        status: SongLibraryStatus.loading,
        summaries: const <SongSummary>[],
        query: const SongLibraryQuery(),
      );

  final SongLibraryStatus status;
  final List<SongSummary> summaries;
  final SongLibraryQuery query;
  final String? failureCode;
  final SongId? undoSongId;
  final Set<SongId> favoriteIds;

  SongLibraryState copyWith({
    SongLibraryStatus? status,
    List<SongSummary>? summaries,
    SongLibraryQuery? query,
    String? failureCode,
    SongId? undoSongId,
    Set<SongId>? favoriteIds,
    bool clearFailure = false,
    bool clearUndoSong = false,
  }) => SongLibraryState(
    status: status ?? this.status,
    summaries: List<SongSummary>.unmodifiable(summaries ?? this.summaries),
    query: query ?? this.query,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
    undoSongId: clearUndoSong ? null : undoSongId ?? this.undoSongId,
    favoriteIds: Set<SongId>.unmodifiable(favoriteIds ?? this.favoriteIds),
  );
}
