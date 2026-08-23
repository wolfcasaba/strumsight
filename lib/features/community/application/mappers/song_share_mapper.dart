/// Song → Community share-artifact mapper (E09-R10, ADR 0404 §D1).
///
/// One mapper file, three factory methods — the brief's allowed
/// `song_share_mapper.dart` is the SEAM that translates the user-
/// authored [Song] into the three distinct artifact subtypes the
/// Community surface exposes:
///
/// * [songResultFromSong] → [SongResultArtifact]
/// * [originalProgressionFromSong] → [OriginalProgressionArtifact]
/// * [planTemplateFromSong] → [PlanTemplateArtifact]
///
/// All three share the same wire field set (progression, strum
/// pattern, tempo, time signature) — the only difference is the
/// `type` discriminator. Three methods in one file avoid the
/// H3 scope-tripwire of three separate mapper files (which would
/// fall outside the brief's `allowed_paths`).
///
/// The mapper imports only the Song feature's `public.dart`
/// barrel — the internal `Song.toJson`/`fromJson` codec is NOT
/// reused here. The Community domain never touches a Song-shaped
/// JSON; it builds the artifact's wire fields explicitly.
library;

import 'package:strumsight/features/songs/public.dart';

import '../../domain/entities/share_artifact.dart';

/// Wire encoding for one slot of the strum pattern. The Song
/// feature's internal model uses `null` for rests; on the wire
/// a dash is friendlier for both server and human readers, and
/// `d`/`u` mirror the existing `Song.toJson()` slot encoding so
/// the round-trip stays faithful.
const String _slotDown = 'd';
const String _slotUp = 'u';
const String _slotRest = '-';

String _encodePattern(List<StrumDirection?> pattern) {
  final buffer = StringBuffer();
  for (final slot in pattern) {
    buffer.write(switch (slot) {
      StrumDirection.down => _slotDown,
      StrumDirection.up => _slotUp,
      null => _slotRest,
    });
  }
  return buffer.toString();
}

/// Builds a [SongResultArtifact] from a [Song]. This is the
/// "I practiced my song" Community share.
SongResultArtifact songResultFromSong(
  Song song, {
  required DateTime createdAt,
  String sourceId = '',
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  return SongResultArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId.isEmpty ? song.id : sourceId,
    createdAt: createdAt,
    songName: song.name,
    chords: song.chords,
    strumPattern: _encodePattern(song.pattern),
    bpm: song.bpm,
    beatsPerBar: song.beatsPerBar,
  );
}

/// Builds an [OriginalProgressionArtifact] from a [Song]. Same
/// wire fields as [songResultFromSong] but a distinct
/// discriminator so a future server renderer can frame the post
/// as "the user's own composition".
OriginalProgressionArtifact originalProgressionFromSong(
  Song song, {
  required DateTime createdAt,
  String sourceId = '',
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  return OriginalProgressionArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId.isEmpty ? song.id : sourceId,
    createdAt: createdAt,
    songName: song.name,
    chords: song.chords,
    strumPattern: _encodePattern(song.pattern),
    bpm: song.bpm,
    beatsPerBar: song.beatsPerBar,
  );
}

/// Builds a [PlanTemplateArtifact] from a [Song]. Same wire
/// fields, distinct discriminator — "try this routine" framing.
PlanTemplateArtifact planTemplateFromSong(
  Song song, {
  required DateTime createdAt,
  String sourceId = '',
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  return PlanTemplateArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId.isEmpty ? song.id : sourceId,
    createdAt: createdAt,
    songName: song.name,
    chords: song.chords,
    strumPattern: _encodePattern(song.pattern),
    bpm: song.bpm,
    beatsPerBar: song.beatsPerBar,
  );
}
