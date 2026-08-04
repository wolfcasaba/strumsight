import 'package:meta/meta.dart';

import 'song_id.dart';

const int songPracticeRecordSchemaVersion = 1;

/// Stable measure/event coordinates used as the revision-aware progress key.
@immutable
final class SongProgressSource {
  const SongProgressSource({
    required this.measureId,
    required this.eventId,
    required this.measureIndex,
    this.sectionId,
  }) : assert(measureId != ''),
       assert(eventId != ''),
       assert(measureIndex >= 0);

  final String measureId;
  final String eventId;
  final int measureIndex;
  final String? sectionId;

  @override
  bool operator ==(Object other) =>
      other is SongProgressSource &&
      other.measureId == measureId &&
      other.eventId == eventId &&
      other.measureIndex == measureIndex &&
      other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(measureId, eventId, measureIndex, sectionId);
}

/// One versioned, source-addressable Song Trainer practice record.
@immutable
final class SongPracticeRecord {
  SongPracticeRecord({
    required this.id,
    required this.songId,
    required this.songRevision,
    required this.source,
    required this.activeDuration,
    required this.completed,
    required this.score,
    required this.recordedAt,
    this.playbackOnly = false,
    this.isArchived = false,
    this.schemaVersion = songPracticeRecordSchemaVersion,
  }) {
    if (id.trim().isEmpty || songRevision < 0 || activeDuration.isNegative) {
      throw ArgumentError(
        'Song practice record has an invalid identity or duration.',
      );
    }
    if (!score.isFinite || score < 0 || score > 1) {
      throw ArgumentError.value(score, 'score', 'Score must be in [0, 1].');
    }
    if (schemaVersion != songPracticeRecordSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported record schema.',
      );
    }
  }

  final int schemaVersion;
  final String id;
  final SongId songId;
  final int songRevision;
  final SongProgressSource source;
  final Duration activeDuration;
  final bool completed;
  final double score;
  final DateTime recordedAt;
  final bool playbackOnly;
  final bool isArchived;

  SongPracticeRecord copyWith({
    int? songRevision,
    SongProgressSource? source,
    bool? isArchived,
  }) => SongPracticeRecord(
    id: id,
    songId: songId,
    songRevision: songRevision ?? this.songRevision,
    source: source ?? this.source,
    activeDuration: activeDuration,
    completed: completed,
    score: score,
    recordedAt: recordedAt,
    playbackOnly: playbackOnly,
    isArchived: isArchived ?? this.isArchived,
    schemaVersion: schemaVersion,
  );

  @override
  bool operator ==(Object other) =>
      other is SongPracticeRecord &&
      other.schemaVersion == schemaVersion &&
      other.id == id &&
      other.songId == songId &&
      other.songRevision == songRevision &&
      other.source == source &&
      other.activeDuration == activeDuration &&
      other.completed == completed &&
      other.score == score &&
      other.recordedAt.toUtc() == recordedAt.toUtc() &&
      other.playbackOnly == playbackOnly &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    songId,
    songRevision,
    source,
    activeDuration,
    completed,
    score,
    recordedAt.toUtc(),
    playbackOnly,
    isArchived,
  );
}
