// Resume checkpoint repository for one Song Trainer session.
//
// E03-R21 brief §5.4 / §6 acceptance "resume biztonságos időközönként +
// pause/stopkor; scoring state nem áll vissza fél attemptként; revision-mismatch
// -> explicit invalidáció".
//
// The contract is intentionally thin: a Song Trainer checkpoint is a single
// immutable record keyed by the song id + revision + selected range. The
// repository persists the latest snapshot, returns it on re-entry, and never
// silently rewinds a half-attempt or applies a checkpoint that targets a
// different song revision.

import 'package:meta/meta.dart';

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/trainer_range.dart';

abstract final class SongResumeFailureCode {
  static const String noCheckpoint = 'songResume.noCheckpoint';
  static const String revisionMismatch = 'songResume.revisionMismatch';
}

/// Immutable checkpoint a Song Trainer route leaves behind when the user
/// pauses or backgrounds the session.
///
/// A checkpoint carries the attempt counter and the resume position — and
/// nothing else. Scoring state, live audio, and the Practice session result
/// are owned by the commit boundary and the Practice controller, not by
/// the resume repository.
@immutable
final class SongResumeCheckpoint {
  const SongResumeCheckpoint({
    required this.songId,
    required this.songRevision,
    required this.range,
    required this.attemptCounter,
    required this.resumedFrom,
    required this.recordedAt,
  });

  final SongId songId;
  final int songRevision;
  final MeasureRange range;
  final int attemptCounter;
  final Duration resumedFrom;
  final DateTime recordedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongResumeCheckpoint &&
          other.songId == songId &&
          other.songRevision == songRevision &&
          other.range == range &&
          other.attemptCounter == attemptCounter &&
          other.resumedFrom == resumedFrom &&
          other.recordedAt == recordedAt;

  @override
  int get hashCode => Object.hash(
    songId,
    songRevision,
    range,
    attemptCounter,
    resumedFrom,
    recordedAt,
  );
}

abstract interface class SongResumeRepository {
  Future<AppResult<SongResumeCheckpoint>> load({
    required SongId songId,
    required int revision,
  });

  Future<AppResult<void>> save(SongResumeCheckpoint checkpoint);

  Future<AppResult<void>> discard({
    required SongId songId,
    required int revision,
  });
}
