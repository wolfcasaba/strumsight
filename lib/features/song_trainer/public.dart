/// Public presentation boundary for flag-gated Song Trainer V2 routes.
library;

export 'presentation/screens/song_import_screen.dart';
export 'presentation/screens/song_library_screen.dart';
// E17-R03 (ADR 0585 D1) — the V2 setlist list is constructor-injected
// (`controller`, `clock`); the router builds it via a `Consumer` bound to
// the two providers below, exactly like the existing Song Trainer routes.
export 'presentation/screens/setlist_list_screen_v2.dart';
export 'domain/repositories/song_repository.dart'
    show SongQuery, SongRepository;
export 'domain/repositories/setlist_repository.dart' show SetlistRepository;
export 'application/song_trainer_providers.dart'
    show
        setlistRepositoryProvider,
        songRepositoryProvider,
        setlistControllerProvider,
        songTrainerClockProvider;
