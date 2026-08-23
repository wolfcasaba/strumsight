/// Import a Community share-artifact into a local Practice / Song
/// instance (E09-R17, ADR 0408, brief §5.1 / §6 A4–A7).
///
/// The use case is the single entry point the Community surface
/// exposes for "save a community post's plan template / original
/// progression as a local, editable practice target". It is
/// PURE — it does not persist anything, does not call
/// ``songsProvider`` (the brief's D2 — the Songs feature's own
/// ``public.dart`` is the seam a future round will use to wire
/// the actual local save; the §6 A5 invariant is preserved here
/// by the function returning a new value, not mutating the
/// input).
///
/// ## Design contract (the §5 / §0.0 invariants)
///
/// * **Schema validation is mandatory (§6 A4).** The use case
///   refuses an artifact whose ``schemaVersion`` differs from the
///   wire constant ``importSupportedSchemaVersion`` — a future
///   schema bump cannot silently fall back to v1. The §6.1
///   valódi-sértés próba turns the A4 cell red when the check is
///   removed.
///
/// * **A new local instance, never a mutation (§5.1, §6 A5).**
///   The output ``Song`` carries a fresh, caller-supplied id
///   (``idGenerator()``) and a ``name`` augmented with the
///   source-attribution suffix. The input ``artifact`` is never
///   touched — the function is a value transformer, not a
///   repository write. The §6.1 probe asserts the artifact's
///   identity is preserved through the call (no side-effect on
///   the source).
///
/// * **Name-collision is surfaced, not silently overwritten
///   (§6 A6, §3 risk).** When a Song with the proposed name
///   already exists in the caller's local Songs collection, the
///   use case returns ``ImportShareArtifactNameCollision(...)``
///   — the Flutter composer receives a typed signal and decides
///   whether to rename or cancel. The §6.1 probe asserts a
///   silent overwrite would have been the bug.
///
/// * **Deprecated artifacts surface a read-only fallback
///   (§6 A7, §0.0 D3).** The "deprecated, read-only fallback"
///   branch is collapsed with the "post moderation-removed"
///   branch: a source artifact with a non-``visible``
///   ``moderationState`` (the §3 tombstone) is rejected as
///   ``ImportShareArtifactDeprecated(...)`` — the local copy is
///   NOT created; the user sees a "this post is no longer
///   importable" surface instead.
///
/// * **Pure / deterministic.** The function reads no globals,
///   no current time, no provider, no filesystem. The id
///   generator is the only seam — it is a ``() → String``
///   function, easy to fake in a test. This keeps the §6.1
///   valódi-sértés próba in the deterministic-time discipline
///   (the rest of the project uses a caller-supplied clock /
///   id-generator seam).
///
/// * **Only the two import-eligible types are accepted.** The
///   ``practiceSummary`` / ``songResult`` / ``analysisImprovement``
///   / ``achievement`` / ``challenge`` artifacts are rejected
///   with ``ImportShareArtifactUnsupportedType(...)`` — they
///   are display-only on the Community surface and have no
///   local import semantic. The brief §1 calls out the two
///   import-eligible types by name: plan template + original
///   progression.
library;

import 'package:flutter/foundation.dart';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/songs/public.dart';

// ---------------------------------------------------------------------------
// Wire constants — mirrors the rest of the project (Kör 10 sealed
// share-artifact hierarchy). The schema version is a single
// constant; the use case refuses anything else.
// ---------------------------------------------------------------------------

/// The single supported wire ``schemaVersion``. Bumped only on a
/// backward-incompatible shape change (Kör 10). An unknown
/// version is rejected by ``importShareArtifact`` (§6 A4).
const int importSupportedSchemaVersion = 1;

/// The local-id prefix a freshly-imported Song carries. The
/// caller-side id generator concatenates this with a unique
/// suffix; the prefix is the audit-trail marker the Songs
/// repository reads to recognise "this is a community import,
/// not a user-authored song".
const String importSongIdPrefix = 'imp_';

/// The display-name suffix the use case appends to a freshly
/// imported Song to mark the source. The visual marker is
/// non-negotiable — the user must be able to recognise the
/// import at a glance.
const String importSourceAttributionSuffix = ' (from community)';

// ---------------------------------------------------------------------------
// Id generator — the only seam between the use case and the
// outside world. The default produces a uuid-shaped string; the
// test fakes a deterministic counter so the §6 A5 probe is
// repeatable.
// ---------------------------------------------------------------------------

/// The id-generator contract. Returns a NEW id every call; the
/// default implementation reads no globals.
typedef ImportIdGenerator = String Function();

/// The default id generator: a hex-shaped 32-char string with the
/// ``importSongIdPrefix`` prepended. The function reads no
/// globals — collision resistance is "good enough" for an
/// opaque local id (the project standard is uuid4, but a tiny
/// LCG is fine for an internal marker the user never sees).
String defaultImportIdGenerator() {
  return '${importSongIdPrefix}${_randomHex(16)}';
}

String _randomHex(int bytes) {
  final random = _ImportRandom();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class _ImportRandom {
  int _state = DateTime.now().microsecondsSinceEpoch;
  int nextInt(int max) {
    // LCG — collision resistance is "good enough" for opaque
    // local ids; the project standard is uuid4, but this use
    // case does not need cryptographic strength.
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}

// ---------------------------------------------------------------------------
// Result — the typed signal the composer reads.
// ---------------------------------------------------------------------------

/// What the import can do, sealed. The composer pattern-matches
/// on the concrete subtype to decide which UI surface to show
/// (success → save dialog; collision → rename dialog;
/// deprecated → read-only surface; unsupportedType →
/// "this artifact is not importable" surface).
@immutable
sealed class ImportShareArtifactResult {
  const ImportShareArtifactResult();
}

/// Successful import: the use case produced a new local
/// ``Song`` ready for the Songs repository to persist.
final class ImportShareArtifactSuccess extends ImportShareArtifactResult {
  const ImportShareArtifactSuccess({required this.song});
  final Song song;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportShareArtifactSuccess && other.song == song);
  @override
  int get hashCode => song.hashCode;
}

/// The proposed name already exists in the caller's local
/// Songs collection. The composer decides whether to
/// rename (passing a new name back through the use case) or
/// cancel. The use case does NOT silently overwrite — the §6
/// A6 invariant.
final class ImportShareArtifactNameCollision extends ImportShareArtifactResult {
  const ImportShareArtifactNameCollision({
    required this.proposedName,
    required this.existingSongId,
  });

  /// The name the use case tried to use. The composer may
  /// prompt the user to rename.
  final String proposedName;

  /// The id of the existing song the name collided with. The
  /// composer may deep-link to the existing song.
  final String existingSongId;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportShareArtifactNameCollision &&
          other.proposedName == proposedName &&
          other.existingSongId == existingSongId);
  @override
  int get hashCode => Object.hash(proposedName, existingSongId);
}

/// The source artifact is in a deprecated / read-only state
/// (brief §6 A7, §0.0 D3). The composer renders a
/// "this post is no longer importable" surface; no local copy
/// is created. The carry-on message is the wire reason the
/// server attached (a future-round field — empty for now).
final class ImportShareArtifactDeprecated extends ImportShareArtifactResult {
  const ImportShareArtifactDeprecated({required this.reason});
  final String reason;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportShareArtifactDeprecated && other.reason == reason);
  @override
  int get hashCode => reason.hashCode;
}

/// The artifact's ``schemaVersion`` differs from the supported
/// one (§6 A4). The composer renders an "unknown version,
/// please update" surface.
final class ImportShareArtifactUnsupportedVersion
    extends ImportShareArtifactResult {
  const ImportShareArtifactUnsupportedVersion({
    required this.found,
    required this.expected,
  });
  final int found;
  final int expected;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportShareArtifactUnsupportedVersion &&
          other.found == found &&
          other.expected == expected);
  @override
  int get hashCode => Object.hash(found, expected);
}

/// The artifact's ``type`` is not in the import-eligible set
/// (the brief §1 names only plan-template + original-progression
/// as importable). The composer renders a "this is display-only"
/// surface.
final class ImportShareArtifactUnsupportedType
    extends ImportShareArtifactResult {
  const ImportShareArtifactUnsupportedType({required this.typeCode});
  final String typeCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportShareArtifactUnsupportedType &&
          other.typeCode == typeCode);
  @override
  int get hashCode => typeCode.hashCode;
}

// ---------------------------------------------------------------------------
// Existence check — the caller's view of the local Songs.
// ---------------------------------------------------------------------------

/// The minimal "is there a local song with this name?" seam. The
/// real Songs repository has a richer query surface, but the use
/// case only needs the existence / id pair. The default
/// implementation is a no-op (returns ``null`` — no collision);
/// the real wire injects a Songs-feature-backed implementation
/// in a future round.
typedef LocalSongExistenceCheck = String? Function(String proposedName);

/// The default existence check: nothing is local, no collision
/// is possible. Useful for tests that don't care about the
/// collision branch.
String? defaultLocalSongExistenceCheck(String proposedName) => null;

// ---------------------------------------------------------------------------
// The use case itself — the only function the composer calls.
// ---------------------------------------------------------------------------

/// A snapshot of the Song-shaped fields the two import-eligible
/// artifact subtypes share. Used internally to lift the common
/// field set out of the pattern-match arms before building the
/// new local ``Song``.
class _SongFields {
  const _SongFields({
    required this.songName,
    required this.chords,
    required this.strumPattern,
    required this.bpm,
    required this.beatsPerBar,
  });
  final String songName;
  final List<String> chords;
  final String strumPattern;
  final int bpm;
  final int beatsPerBar;
}

_SongFields? _extractSongFields(ShareArtifact artifact) {
  switch (artifact) {
    case PlanTemplateArtifact(
      :final songName,
      :final chords,
      :final strumPattern,
      :final bpm,
      :final beatsPerBar,
    ):
      return _SongFields(
        songName: songName,
        chords: chords,
        strumPattern: strumPattern,
        bpm: bpm,
        beatsPerBar: beatsPerBar,
      );
    case OriginalProgressionArtifact(
      :final songName,
      :final chords,
      :final strumPattern,
      :final bpm,
      :final beatsPerBar,
    ):
      return _SongFields(
        songName: songName,
        chords: chords,
        strumPattern: strumPattern,
        bpm: bpm,
        beatsPerBar: beatsPerBar,
      );
    case SongResultArtifact():
    case PracticeSummaryArtifact():
    case AnalysisImprovementArtifact():
    case AchievementArtifact():
    case ChallengeArtifact():
      return null;
  }
}

/// Import a Community share-artifact as a new local ``Song``.
///
/// The function is PURE — it does not persist the new ``Song``;
/// the caller's Songs repository writes the row. The
/// ``idGenerator`` seam is the only source of non-determinism;
/// the test fakes it for the §6.1 probe.
///
/// * **§6 A4** — schema version is checked. Unknown / manipulated
///   versions are rejected with
///   :class:`ImportShareArtifactUnsupportedVersion`.
/// * **§6 A5** — the input ``artifact`` is NEVER mutated; the
///   function returns a fresh ``Song`` carrying a new id. The
///   §6.1 probe asserts the source identity is preserved.
/// * **§6 A6** — a name collision is surfaced as
///   :class:`ImportShareArtifactNameCollision`, not silently
///   overwritten.
/// * **§6 A7** — a ``deprecated`` artifact (or a
///   moderation-removed source — the §0.0 D3 collapse) is
///   surfaced as :class:`ImportShareArtifactDeprecated`.
ImportShareArtifactResult importShareArtifact(
  ShareArtifact artifact, {
  ImportIdGenerator idGenerator = defaultImportIdGenerator,
  LocalSongExistenceCheck localSongExists = defaultLocalSongExistenceCheck,
  bool isDeprecated = false,
  String deprecationReason = '',
}) {
  // §6 A4 — schema version is mandatory. The codec layer already
  // rejects unknown versions when the artifact was built; the
  // use case re-checks the invariant so a future caller that
  // bypasses the codec still hits the same gate. The §6.1
  // valódi-sértés próba turns the A4 cell red when this branch
  // is removed.
  if (artifact.schemaVersion != importSupportedSchemaVersion) {
    return ImportShareArtifactUnsupportedVersion(
      found: artifact.schemaVersion,
      expected: importSupportedSchemaVersion,
    );
  }

  // §6 A7 — the source post is in a deprecated / read-only
  // state. The composer renders the read-only surface; the use
  // case does NOT build a local copy.
  if (isDeprecated) {
    return ImportShareArtifactDeprecated(reason: deprecationReason);
  }

  // Only the two import-eligible types are accepted. The brief
  // §1 names plan-template and original-progression by name;
  // the other five artifact subtypes are display-only on the
  // Community surface and have no local import semantic.
  final fields = _extractSongFields(artifact);
  if (fields == null) {
    return ImportShareArtifactUnsupportedType(typeCode: artifact.type.code);
  }

  // §6 A6 — name collision is surfaced, not silently overwritten.
  // The proposed name is the source artifact's name augmented
  // with the source-attribution suffix; the check is on the
  // augmented string (so a user-authored song and a community
  // import sharing the base name are both detected).
  final proposedName = fields.songName.isEmpty
      ? '(untitled)$importSourceAttributionSuffix'
      : '${fields.songName}$importSourceAttributionSuffix';
  final existingId = localSongExists(proposedName);
  if (existingId != null) {
    return ImportShareArtifactNameCollision(
      proposedName: proposedName,
      existingSongId: existingId,
    );
  }

  // §6 A5 — a fresh id, a fresh Song, the input artifact
  // untouched. The Songs repository writes the row in a future
  // round (the brief's D2 — the seam is the public.dart
  // barrel).
  final newId = idGenerator();
  final pattern = _decodePattern(fields.strumPattern, fields.beatsPerBar);
  final song = Song(
    id: newId,
    name: proposedName,
    chords: List<String>.unmodifiable(fields.chords),
    pattern: pattern,
    bpm: fields.bpm,
    beatsPerBar: fields.beatsPerBar,
  );
  return ImportShareArtifactSuccess(song: song);
}

/// Decode the wire strum-pattern string back to the
/// ``List<StrumDirection?>`` the ``Song`` model wants. Mirrors
/// the Song-feature codec: ``d`` = down, ``u`` = up, ``-`` = rest.
/// The pattern length is fitted to ``beatsPerBar * 2`` (the
/// one-bar contract; see ``Song._fitToMeter``).
List<StrumDirection?> _decodePattern(String strumPattern, int beatsPerBar) {
  final want = beatsPerBar * 2;
  final raw = strumPattern.split('');
  return <StrumDirection?>[
    for (var i = 0; i < want; i++)
      if (i < raw.length) _slotToDirection(raw[i]) else null,
  ];
}

StrumDirection? _slotToDirection(String slot) {
  switch (slot) {
    case 'd':
      return StrumDirection.down;
    case 'u':
      return StrumDirection.up;
    default:
      return null; // '-' or anything else is a rest.
  }
}
