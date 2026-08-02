/// Stable re-export of [BackingAudioTrack] for callers that import the
/// track subtype directly from its dedicated file.
///
/// The class itself lives in `song_track.dart` so the sealed
/// [SongTrack] hierarchy stays in a single library (Dart 3 sealed
/// invariant). This file exists to satisfy the public barrel's
/// per-subtype export shape and to keep imports from the codec layer
/// unchanged.
library;

export 'song_track.dart' show BackingAudioTrack;
