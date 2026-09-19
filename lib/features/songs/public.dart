/// Public song contract for other features (SDD Ch2 §10.4).
///
/// Consumers must import this boundary instead of Songs internals; the
/// authoring/persistence wiring behind it is free to change.
library;

/// The user-authored song model (chord-per-bar progression + strum pattern +
/// tempo) and its `toLesson`/share helpers.
export 'model/song.dart';

/// The user's songbook as live app state (WP-H2, 2026-09-06). The AI Tutor's
/// practice-plan compiler needs the REAL song list to validate a song block —
/// and the architecture rule lets another feature reach it only through this
/// barrel.
export 'providers/songs_provider.dart' show SongsController, songsProvider;
