/// Explicit migration state and outcome types (E03-R08, ADR 0117
/// §Döntés 1 / §Döntés 2, SDD §18.6).
///
/// The migrator reports its progress as a single value-object tree so the
/// caller (a controller, a UI, a test) can branch on a sealed type without
/// reaching into a repository or a side-effect channel. The shape mirrors
/// the §6 acceptance matrix:
///
///   - [SongMigrationStatus.completed] — every legacy song is checkpointed,
///     every corrupt record is redacted, and the setlist mapping has run.
///     [SongMigrationOutcome.completedAt] is non-null.
///   - [SongMigrationStatus.needsResume] — at least one song failed or is
///     still pending, and the global completion flag is therefore NOT set.
///     The caller must run the migrator again on the same directory.
///
/// Two structural pieces:
///
///   - [SongMigrationOutcome] is the per-run return value (status, counts,
///     failed entries, setlist report).
///   - [SongMigrationCheckpoint] is the **persisted** state the migrator
///     reads at boot to know which legacy song ids have already landed in
///     the V2 repository. It lives under `<songsRoot>/migration/state.json`
///     (ADR 0117 §Döntés 2).
///
/// The two pieces are deliberately separated: a checkpoint is durable and
/// survives a process crash; an outcome is the per-run report a caller
/// reads at the end of [SongStorageMigrator.run].
library;

import 'package:meta/meta.dart';

import '../../data/migration/legacy_setlist_adapter.dart';

/// Status of a single [SongStorageMigrator.run] invocation (E03-R08).
///
/// The migrator is a one-shot use case: a run ends in exactly one of these
/// states. The next run starts by reading the persisted checkpoint, so a
/// [needsResume] run is always re-entrant from the same migrator instance
/// constructed against the same `songsRoot`.
enum SongMigrationStatus {
  /// Every legacy song is checkpointed, every corrupt record is redacted,
  /// the setlist mapping has run, and the global completion flag is set.
  /// Re-running against the same state is a no-op.
  completed,

  /// At least one song is missing, failed, or read-back parity was lost
  /// during this run. The completion flag is NOT set. The caller MUST run
  /// the migrator again — a subsequent run will resume from the persisted
  /// checkpoint, never duplicate a successful id, and continue from the
  /// first failing id onward.
  needsResume,
}

/// One redacted / failed song entry reported by a single run.
///
/// The [reason] is a stable, machine-readable code the UI can map to a
/// localised message — it carries no user content and no diagnostic
/// payload the user should not see. The codes are intentionally a
/// closed set so the reviewer can assert on them deterministically.
@immutable
final class SongMigrationFailure {
  /// Stable constructor.
  const SongMigrationFailure({required this.id, required this.reason});

  /// Legacy song id the migration could not complete. The V2 document was
  /// either not written or written-but-not-confirmed-by-read-back; the
  /// migrator records this id so a subsequent run re-attempts the same id
  /// (except for [reason] `redactedCorrupt`, which is permanent).
  final String id;

  /// One of [SongMigrationFailureReason]'s constants.
  final String reason;
}

/// Closed enumeration of the migration-failure reasons the UI must be
/// able to display.
///
/// The list is short on purpose: every value has a documented, distinct
/// recovery story. The migrator MUST NOT emit a code outside this list —
/// the §6 acceptance matrix reads it as a sealed switch.
abstract final class SongMigrationFailureReason {
  /// The legacy JSON record could not be decoded by [LegacySongReader]
  /// (missing required key, wrong type, value out of range). The record
  /// is **permanently** redacted from this run and from all subsequent
  /// runs — a restart does NOT re-attempt it.
  static const String redactedCorrupt = 'songMigration.failure.redactedCorrupt';

  /// The V2 repository refused the write (validation, IO). The record is
  /// **transient** — a subsequent run retries it.
  static const String repositoryRejected =
      'songMigration.failure.repositoryRejected';

  /// The V2 write returned `Success` but a fresh `get()` against the
  /// repository returned `null` — the migration lost the document after
  /// the write. The record is **transient** — a subsequent run retries it
  /// but will likely fail again until the underlying cause is fixed.
  static const String readBackMiss = 'songMigration.failure.readBackMiss';
}

/// The full report a single [SongStorageMigrator.run] returns.
///
/// The outcome is intentionally immutable and not a stream — the §6
/// acceptance matrix is a per-run assertion surface, and a UI that wants
/// a per-record progress feed reads the checkpoint directly.
@immutable
final class SongMigrationOutcome {
  /// Stable constructor.
  const SongMigrationOutcome({
    required this.status,
    required this.totalSongs,
    required this.migratedSongs,
    required this.failedSongs,
    required this.setlistAdaptation,
    required this.completedAt,
  });

  /// Run-level status.
  final SongMigrationStatus status;

  /// Number of legacy song records the migrator saw on this run. Stays
  /// stable across runs of the same legacy snapshot.
  final int totalSongs;

  /// Number of legacy song ids the migrator successfully wrote to the V2
  /// repository on this run (checkpoint already-OK ids are not counted
  /// again, so `migratedSongs` resets to 0 on a re-run that has nothing
  /// new to do).
  final int migratedSongs;

  /// Per-song failure entries. Empty when [status] is `completed`.
  /// Stable order — the migrator emits failures in legacy-id order.
  final List<SongMigrationFailure> failedSongs;

  /// Setlist mapping output, or `null` when the song step has at least
  /// one failure (the migrator runs the setlist step ONLY after every
  /// song is checkpointed).
  final LegacySetlistAdaptation? setlistAdaptation;

  /// UTC timestamp of the moment the run hit `completed`. `null` when
  /// [status] is `needsResume` — the global completion flag is not set.
  final DateTime? completedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongMigrationOutcome) return false;
    if (other.status != status) return false;
    if (other.totalSongs != totalSongs) return false;
    if (other.migratedSongs != migratedSongs) return false;
    if (other.completedAt != completedAt) return false;
    if (other.setlistAdaptation != setlistAdaptation) return false;
    if (other.failedSongs.length != failedSongs.length) return false;
    for (var i = 0; i < failedSongs.length; i++) {
      if (other.failedSongs[i] != failedSongs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    status,
    totalSongs,
    migratedSongs,
    Object.hashAll(failedSongs),
    setlistAdaptation,
    completedAt,
  );
}

/// Persisted checkpoint the migrator reads at boot (ADR 0117 §Döntés 2).
///
/// The checkpoint lives at `<songsRoot>/migration/state.json` (see
/// [SongMigrationVersionStore]). It is the durable handoff between two
/// runs of the migrator, and is the only piece of state the run matrix
/// (§6) inspects across process restarts.
@immutable
final class SongMigrationCheckpoint {
  /// Stable constructor.
  const SongMigrationCheckpoint({
    required this.completedLegacySongIds,
    required this.redactedLegacySongIds,
    required this.completed,
    required this.completedAt,
  });

  /// Stable constructor for an empty / fresh-install checkpoint.
  factory SongMigrationCheckpoint.empty() => const SongMigrationCheckpoint(
    completedLegacySongIds: <String>{},
    redactedLegacySongIds: <String>{},
    completed: false,
    completedAt: null,
  );

  /// Legacy song ids the migrator has successfully written to the V2
  /// repository in some prior run. The migrator treats these ids as
  /// already-done — `create` for them will surface `alreadyExists`, the
  /// migrator interprets that as "skip, verify read-back, advance".
  final Set<String> completedLegacySongIds;

  /// Legacy song ids the migrator has PERMANENTLY redacted (legacy JSON
  /// could not be decoded). These are NEVER retried — they show up in
  /// every subsequent run's [SongMigrationOutcome.failedSongs] as a
  /// `redactedCorrupt` entry so the UI / diagnostics surface keeps
  /// reporting them, but the migrator does not re-run the adapter.
  final Set<String> redactedLegacySongIds;

  /// `true` only when every legacy song id is either in
  /// [completedLegacySongIds] or in [redactedLegacySongIds] AND the
  /// setlist mapping has run. Flipping this flag is the LAST step of a
  /// successful run.
  final bool completed;

  /// UTC timestamp of the moment the checkpoint flipped to `completed`.
  /// `null` until then.
  final DateTime? completedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongMigrationCheckpoint) return false;
    if (other.completed != completed) return false;
    if (other.completedAt != completedAt) return false;
    if (other.completedLegacySongIds.length != completedLegacySongIds.length) {
      return false;
    }
    if (!other.completedLegacySongIds.containsAll(completedLegacySongIds)) {
      return false;
    }
    if (other.redactedLegacySongIds.length != redactedLegacySongIds.length) {
      return false;
    }
    if (!other.redactedLegacySongIds.containsAll(redactedLegacySongIds)) {
      return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(completedLegacySongIds),
    Object.hashAll(redactedLegacySongIds),
    completed,
    completedAt,
  );
}
