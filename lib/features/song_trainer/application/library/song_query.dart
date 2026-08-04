import '../../domain/models/song_source.dart';
import '../../domain/repositories/song_repository.dart' as repository;

/// Presentation-only filters applied to already loaded index summaries.
///
/// Keeping this separate from [repository.SongQuery] ensures a search or sort
/// change never causes a document decode or a second repository scan.
final class SongLibraryQuery {
  const SongLibraryQuery({
    this.searchText = '',
    this.sourceType,
    this.favoritesOnly = false,
    this.sort = SongLibrarySort.recent,
  });

  final String searchText;
  final SongSourceType? sourceType;
  final bool favoritesOnly;
  final SongLibrarySort sort;
}

enum SongLibrarySort { recent, title }
