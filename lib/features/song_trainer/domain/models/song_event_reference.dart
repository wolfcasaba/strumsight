import 'song_id.dart';

/// Immutable coordinates of one source event in a compiled practice target.
///
/// This model deliberately contains only Song Trainer domain values. The
/// application-level compiler owns the `PracticeEvent.id` association, so the
/// Song Trainer domain remains independent of the Practice feature.
final class SongEventReference {
  const SongEventReference({
    required this.songId,
    required this.songRevision,
    required this.trackId,
    required this.eventId,
    required this.measureIndex,
    required this.sectionId,
  });

  final SongId songId;
  final int songRevision;
  final SongTrackId trackId;
  final SongEventId eventId;
  final int measureIndex;
  final SongSectionId? sectionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongEventReference &&
          other.songId == songId &&
          other.songRevision == songRevision &&
          other.trackId == trackId &&
          other.eventId == eventId &&
          other.measureIndex == measureIndex &&
          other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(
    songId,
    songRevision,
    trackId,
    eventId,
    measureIndex,
    sectionId,
  );
}
