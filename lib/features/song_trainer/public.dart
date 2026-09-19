/// Public presentation boundary for flag-gated Song Trainer V2 routes.
library;

export 'presentation/screens/song_import_screen.dart';
export 'presentation/screens/song_library_screen.dart';
export 'domain/repositories/song_repository.dart'
    show SongQuery, SongRepository;
export 'domain/repositories/setlist_repository.dart' show SetlistRepository;
export 'application/song_trainer_providers.dart'
    show
        SongTrainerControllerInputs,
        setlistRepositoryProvider,
        songRepositoryProvider;
// E17-R03 (ADR 0522) — the Setlist session entry surface the Songs feature
// composes from its setlist detail: the screen, its mode/result vocabulary,
// the composer that binds availability + runners, the legacy record the
// composer projects, and the single-song Stage the runners present.
export 'application/setlists/setlist_session_providers.dart';
export 'data/migration/legacy_song_reader.dart' show LegacySetlistRecord;
export 'domain/models/setlist_result.dart'
    show SetlistItemResultStatus, SetlistResult;
export 'domain/models/song_setlist.dart' show SetlistSessionMode, SongSetlist;
export 'presentation/screens/setlist_session_screen.dart';
export 'presentation/screens/song_trainer_screen.dart' show SongTrainerScreen;
