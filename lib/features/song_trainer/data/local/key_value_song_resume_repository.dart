// Persisted resume-checkpoint store for the Song Trainer.
//
// Javító sáv 2026-09-06, audit §5.2 "Song resume persistálás": the R21
// wiring shipped an in-memory repository, so the checkpoint the trainer
// writes on pause / background was gone on the next app start — exactly the
// case the resume feature exists for.
//
// The store sits on the app's only non-secret persistence boundary
// ([KeyValueStore]), the way `GenerationDraftRepository` does for the
// practice-plan wizard: a feature-owned key, a versioned envelope, and no
// direct plugin dependency.
//
// Corruption is tolerated but never silently repaired: an unreadable
// document surfaces as `Failure(storage.read)` so the caller can say "your
// resume point could not be restored", and the next `save` replaces it. A
// checkpoint is derived state (attempt counter + position), never user
// content, so replacing it costs the user nothing they authored.

import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../application/trainer/song_resume_repository.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/trainer_range.dart';

/// [SongResumeRepository] backed by the app-wide [KeyValueStore].
final class KeyValueSongResumeRepository implements SongResumeRepository {
  const KeyValueSongResumeRepository({required this.keyValueStore});

  /// Dedicated to the resume checkpoints — deliberately never the key the
  /// songs or setlists documents live under, so a corrupt checkpoint can
  /// never cost the user a song.
  static const String storageKey = 'ss.song_trainer.resume';

  /// Envelope version of the stored document.
  static const int schemaVersion = 1;

  /// Documented storage bound (SDD Ch2 §7.5). The newest checkpoints are
  /// kept: the resume point a user is coming back to is the last one they
  /// left behind.
  static const int maxCheckpoints = 20;

  final KeyValueStore keyValueStore;

  @override
  Future<AppResult<SongResumeCheckpoint>> load({
    required SongId songId,
    required int revision,
  }) async {
    final Map<String, SongResumeCheckpoint> stored;
    try {
      stored = _readAll();
    } on FormatException catch (e, stackTrace) {
      return Failure<SongResumeCheckpoint>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
    final exact = stored[_keyOf(songId, revision)];
    if (exact != null) return Success<SongResumeCheckpoint>(exact);
    // A checkpoint for the same song at a different revision is an explicit
    // invalidation, not a "never existed" — the caller distinguishes stale
    // from absent (R21 §5.4).
    final stale = stored.values.any((entry) => entry.songId == songId);
    return Failure<SongResumeCheckpoint>(
      StorageFailure(
        code: stale
            ? SongResumeFailureCode.revisionMismatch
            : SongResumeFailureCode.noCheckpoint,
      ),
    );
  }

  @override
  Future<AppResult<void>> save(SongResumeCheckpoint checkpoint) async {
    final next = <String, SongResumeCheckpoint>{};
    try {
      next.addAll(_readAll());
    } on FormatException {
      // A document this build cannot read must not block a NEW checkpoint.
      // The unreadable bytes are replaced by the write below.
    }
    next[_keyOf(checkpoint.songId, checkpoint.songRevision)] = checkpoint;
    return _write(next);
  }

  @override
  Future<AppResult<void>> discard({
    required SongId songId,
    required int revision,
  }) async {
    final Map<String, SongResumeCheckpoint> stored;
    try {
      stored = _readAll();
    } on FormatException {
      // Nothing readable to discard — drop the corrupt document instead, so
      // the next load starts from a clean slate.
      return _write(const <String, SongResumeCheckpoint>{});
    }
    final key = _keyOf(songId, revision);
    if (!stored.containsKey(key)) return const Success<void>(null);
    final next = Map<String, SongResumeCheckpoint>.of(stored)..remove(key);
    return _write(next);
  }

  Future<AppResult<void>> _write(
    Map<String, SongResumeCheckpoint> checkpoints,
  ) async {
    final entries = checkpoints.values.toList()
      ..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'checkpoints': <Map<String, Object?>>[
        for (final checkpoint in entries.take(maxCheckpoints))
          _encode(checkpoint),
      ],
    };
    try {
      await keyValueStore.writeString(storageKey, jsonEncode(payload));
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Every stored checkpoint keyed by `<songId>@<revision>`.
  ///
  /// Throws [FormatException] — and nothing else — when the document cannot
  /// be read, so every caller has exactly one failure shape to handle.
  Map<String, SongResumeCheckpoint> _readAll() {
    final raw = keyValueStore.readString(storageKey);
    if (raw == null || raw.isEmpty) return <String, SongResumeCheckpoint>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resume document is not a JSON object.');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Resume document has an unknown version.');
    }
    final body = decoded['checkpoints'];
    if (body is! List) {
      throw const FormatException('Resume document has no checkpoint list.');
    }
    final result = <String, SongResumeCheckpoint>{};
    for (final entry in body) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Resume entry is not a JSON object.');
      }
      final checkpoint = _decode(entry);
      result[_keyOf(checkpoint.songId, checkpoint.songRevision)] = checkpoint;
    }
    return result;
  }

  static Map<String, Object?> _encode(SongResumeCheckpoint checkpoint) {
    return <String, Object?>{
      'songId': checkpoint.songId.value,
      'songRevision': checkpoint.songRevision,
      'rangeStart': checkpoint.range.start,
      'rangeEndExclusive': checkpoint.range.endExclusive,
      'attemptCounter': checkpoint.attemptCounter,
      'resumedFromMs': checkpoint.resumedFrom.inMilliseconds,
      'recordedAt': checkpoint.recordedAt.toUtc().toIso8601String(),
    };
  }

  static SongResumeCheckpoint _decode(Map<String, dynamic> json) {
    final songId = json['songId'];
    final revision = json['songRevision'];
    final rangeStart = json['rangeStart'];
    final rangeEnd = json['rangeEndExclusive'];
    final attempt = json['attemptCounter'];
    final resumedFromMs = json['resumedFromMs'];
    final recordedAt = json['recordedAt'];
    if (songId is! String ||
        revision is! int ||
        rangeStart is! int ||
        rangeEnd is! int ||
        attempt is! int ||
        resumedFromMs is! int ||
        recordedAt is! String) {
      throw const FormatException('Resume entry has a mistyped field.');
    }
    final parsedAt = DateTime.tryParse(recordedAt);
    if (parsedAt == null) {
      throw const FormatException('Resume entry has an invalid timestamp.');
    }
    if (songId.isEmpty ||
        revision < 0 ||
        rangeStart < 0 ||
        rangeEnd <= rangeStart ||
        attempt < 0 ||
        resumedFromMs < 0) {
      throw const FormatException('Resume entry is out of range.');
    }
    final SongId parsedId;
    try {
      parsedId = SongId(songId);
    } on SongIdValidationException {
      throw const FormatException('Resume entry has an invalid song id.');
    }
    return SongResumeCheckpoint(
      songId: parsedId,
      songRevision: revision,
      range: MeasureRange(start: rangeStart, endExclusive: rangeEnd),
      attemptCounter: attempt,
      resumedFrom: Duration(milliseconds: resumedFromMs),
      recordedAt: parsedAt.toUtc(),
    );
  }

  static String _keyOf(SongId songId, int revision) =>
      '${songId.value}@$revision';
}
