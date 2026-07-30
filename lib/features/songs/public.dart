/// Public song contract for other features (SDD Ch2 §10.4).
///
/// Consumers must import this boundary instead of Songs internals; the
/// authoring/persistence wiring behind it is free to change.
library;

/// The user-authored song model (chord-per-bar progression + strum pattern +
/// tempo) and its `toLesson`/share helpers.
export 'model/song.dart';
