/// Persistence contract for the immutable [SongDocument] V2 record
/// (E03-R07, ADR 0090 §Döntés 1 + §Döntés 2, SDD §18.2).
///
/// The repository is the **only** boundary the application layer is allowed
/// to depend on (`package:strumsight/features/song_trainer/domain/
/// repositories/song_repository.dart`). The implementation lives in
/// `data/local/file_song_repository.dart`; the in-memory fake used by UI
/// tests lives in `data/local/in_memory_song_repository.dart`. Neither
/// touches Flutter, SharedPreferences, path-provider or riverpod — they are
/// framework-independent by construction.
///
/// The contract is `AppResult`-based: implementations never throw an
/// exception for an expected failure (a stale revision, a corrupt index,
/// a hash mismatch). Unexpected I/O failures are also returned as
/// `AppResult.failure(StorageFailure)` so the UI cannot be handed an
/// unrelated platform exception (AGENTS.md §6).
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../models/song_document.dart';
import '../models/song_id.dart';
import '../models/song_source.dart';

/// Stable machine-readable codes emitted by [SongRepository] implementations.
///
/// The codes are feature-local (the shared `FailureCode` core catalogue
/// carries generic transports only — a stale revision is a song-storage
/// concern, not a generic storage concern). The UI maps each code to a
/// localised message; tests assert on the constant.
abstract final class SongRepositoryErrorCode {
  /// The repository received a write but the on-disk `revision` no longer
  /// matches [SongRepository.update]'s `expectedRevision` argument. Caller
  /// MUST re-read and re-merge before retrying — silent overwrite is not
  /// supported (ADR 0090 §Döntés 1 / §5 kötött döntés 2 in the brief).
  static const String staleRevision = 'songRepository.staleRevision';

  /// Attempted to persist a document the validator refuses (any fatal
  /// validation issue ⇒ `canPersist=false`, ADR 0114 §Döntés 2).
  static const String notPersistable = 'songRepository.notPersistable';

  /// A document with this [SongId] already exists. The repository does not
  /// silently overwrite on `create` (SDD §18.2).
  static const String alreadyExists = 'songRepository.alreadyExists';

  /// The on-disk index file is structurally invalid (missing required
  /// fields, wrong type, corrupt JSON, duplicate entries). Recoverable by
  /// [SongRepositoryRecovery.scan]; the original user content is preserved
  /// in the `documents/` directory and may be rebuilt.
  static const String corruptIndex = 'songRepository.corruptIndex';

  /// The on-disk document file is structurally invalid or its codec detected
  /// a wire-incompatibility. The file is preserved for forensic recovery;
  /// the user sees a stable code instead of a platform exception.
  static const String corruptDocument = 'songRepository.corruptDocument';

  /// The requested [SongId] does not exist on disk.
  static const String notFound = 'songRepository.notFound';

  /// The on-disk document referenced an asset that the asset store cannot
  /// locate (orphan reference). Surfaces as a recoverable report and a
  /// [Success] with a degraded document index entry (the orphan asset is
  /// inspected via [SongRepositoryRecovery]).
  static const String orphanAssetReference =
      'songRepository.orphanAssetReference';

  /// Generic I/O failure the platform refused to surface cleanly. The cause
  /// stays inside `failure.cause` for the logger.
  static const String io = 'songRepository.io';
}

/// Compact, persistable summary of a document's capability — small enough
/// to live inside the index file but rich enough for the Library listview
/// to render scoring badges without re-running the validator (ADR 0090
/// §Döntés 4, SDD §18.4). The full per-track answers live in the document
/// itself; this is a roll-up.
final class SongCapabilitySummary {
  const SongCapabilitySummary({
    required this.canPersist,
    required this.canTrain,
    required this.canExport,
    required this.chordScoring,
    required this.pitchScoring,
    required this.lastValidatedAt,
  });

  /// Mirrors `SongCapabilityReport.canPersist`.
  final bool canPersist;

  /// Mirrors `SongCapabilityReport.canTrain`.
  final bool canTrain;

  /// Mirrors `SongCapabilityReport.canExport`.
  final bool canExport;

  /// Mirrors `SongChordCapability.scoring`.
  final bool chordScoring;

  /// Mirrors `SongPitchCapability.scoring`.
  final bool pitchScoring;

  /// UTC timestamp of the last successful validation. The repository
  /// recomputes the summary on every successful write; the Live / Trainer
  /// layers treat this as a hint, never as ground truth.
  final DateTime lastValidatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongCapabilitySummary &&
          other.canPersist == canPersist &&
          other.canTrain == canTrain &&
          other.canExport == canExport &&
          other.chordScoring == chordScoring &&
          other.pitchScoring == pitchScoring &&
          other.lastValidatedAt.toUtc().microsecondsSinceEpoch ==
              lastValidatedAt.toUtc().microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    canPersist,
    canTrain,
    canExport,
    chordScoring,
    pitchScoring,
    lastValidatedAt.toUtc().microsecondsSinceEpoch,
  );
}

/// Lightweight, summary-only view of a stored [SongDocument].
///
/// The repository keeps these summaries in `index.json` so [list] can
/// serve the §27.1 Library listview without deserialising every document
/// (ADR 0090 §Döntés 4, SDD §18.4). The full document is loaded on demand
/// via [get].
final class SongSummary {
  const SongSummary({
    required this.documentId,
    required this.title,
    required this.artist,
    required this.tags,
    required this.updatedAt,
    required this.lastPracticedAt,
    required this.capability,
    required this.sourceType,
    required this.favorite,
    required this.archived,
    required this.revision,
    required this.documentHash,
    required this.trashed,
  });

  /// Stable document identifier — mirrors [SongDocument.id].
  final SongId documentId;

  /// Display title (denormalised from metadata).
  final String title;

  /// Display artist (denormalised from metadata); `null` when the metadata
  /// has no artist field.
  final String? artist;

  /// Case-normalised tag list (denormalised from metadata).
  final List<String> tags;

  /// UTC `updatedAt` from the last successful write.
  final DateTime updatedAt;

  /// UTC `lastPracticedAt`. Defaults to `updatedAt` until the Practice
  /// Engine stores a real value (out of scope for R07 — this round never
  /// writes it; the value comes from the document's own metadata contract).
  final DateTime lastPracticedAt;

  /// Cached capability summary so the Library listview can render scoring
  /// badges without re-running the validator. Null when no summary is
  /// cached yet (the first start of a fresh install has no capability
  /// computed). Treat as a hint, never as ground truth — the Live layer
  /// always defers to the live validator.
  final SongCapabilitySummary? capability;

  /// Source provenance type, persisted as its stable [SongSourceType.code].
  final SongSourceType sourceType;

  /// User-controlled favourite flag. Stored only inside the index — the
  /// document itself does not carry it (no `SongDocument.favorite` field,
  /// per ADR 0089 §Döntés 1). The repository exposes reads/writes via a
  /// follow-up round's UX surface; this round keeps the flag persisted
  /// but read-only through the summaries.
  final bool favorite;

  /// User-controlled archived flag. See [favorite] — same note applies.
  final bool archived;

  /// Whether the summary has been moved to the trash. `true` exactly when
  /// the underlying file currently sits in the `trash/` directory; the
  /// default [SongQuery] filters trash out.
  final bool trashed;

  /// Latest persisted `revision` (mirrors [SongDocument.revision]).
  final int revision;

  /// Lower-case SHA-256 of the canonical JSON bytes of the document. Used
  /// to detect index / document drift without re-reading the document.
  final String documentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongSummary &&
          other.documentId == documentId &&
          other.title == title &&
          other.artist == artist &&
          _listEquals(other.tags, tags) &&
          other.updatedAt.toUtc().microsecondsSinceEpoch ==
              updatedAt.toUtc().microsecondsSinceEpoch &&
          other.lastPracticedAt.toUtc().microsecondsSinceEpoch ==
              lastPracticedAt.toUtc().microsecondsSinceEpoch &&
          other.capability == capability &&
          other.sourceType == sourceType &&
          other.favorite == favorite &&
          other.archived == archived &&
          other.trashed == trashed &&
          other.revision == revision &&
          other.documentHash == documentHash;

  @override
  int get hashCode => Object.hash(
    documentId,
    title,
    artist,
    Object.hashAll(tags),
    updatedAt.toUtc().microsecondsSinceEpoch,
    lastPracticedAt.toUtc().microsecondsSinceEpoch,
    capability,
    sourceType,
    favorite,
    archived,
    trashed,
    revision,
    documentHash,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Optional query filter for [SongRepository.list].
///
/// Missing fields mean "no filter on this axis" — the repository returns
/// every stored summary that matches every present field. Implementation
/// behaviour is up to the concrete repository; the file repository
/// performs an exact, in-memory scan (Library never grew large enough to
/// need a different index for this round, per ADR 0090 §Alternatives).
final class SongQuery {
  const SongQuery({
    this.includeTrashed = false,
    this.includeArchived = true,
    this.sourceTypeFilter,
    this.titleContains,
    this.tagFilter,
  });

  /// Whether soft-deleted (trash) songs are included. Default `false` —
  /// the Library listview never shows trashed rows.
  final bool includeTrashed;

  /// Whether archived songs are included. Default `true` — the user may
  /// archive a song to hide it from the default list, but the "show
  /// archived" toggle makes them visible again.
  final bool includeArchived;

  /// Optional source-type filter — e.g. "show only `createdInApp` rows".
  final SongSourceType? sourceTypeFilter;

  /// Case-insensitive substring match on the title.
  final String? titleContains;

  /// Optional tag intersection filter — a summary matches when it carries
  /// at least one of these tags (OR semantics; AND semantics is a follow-up).
  final List<String>? tagFilter;
}

/// Persistence contract for the immutable V2 song record.
///
/// The contract is intentionally narrow. Asset operations live on
/// [SongAssetRepository]; the recovery scan lives on
/// [SongRepositoryRecovery]. This keeps the file round-trip clean and
/// keeps the wire-incompatible changes isolated.
abstract interface class SongRepository {
  /// Load every stored [SongSummary], newest-first, respecting [query].
  ///
  /// Returns `Success([])` on a fresh install — never null. A corrupt
  /// index yields [SongRepositoryErrorCode.corruptIndex] and the caller
  /// should invoke the recovery scanner to rebuild.
  Future<AppResult<List<SongSummary>>> list(SongQuery query);

  /// Load the full [SongDocument] for [id]. Returns `Success(null)` when
  /// the document does not exist; a corrupt document yields
  /// [SongRepositoryErrorCode.corruptDocument].
  Future<AppResult<SongDocument?>> get(SongId id);

  /// Persist a brand-new [document]. The repository refuses to overwrite
  /// an existing record with the same [SongDocument.id] — callers must
  /// use [update] for that flow.
  ///
  /// The implementation re-runs the validator before writing; any fatal
  /// issue short-circuits to [SongRepositoryErrorCode.notPersistable].
  /// The persisted `revision` is the document's own `revision` — the
  /// repository does NOT auto-bump it on create (no prior baseline existed).
  Future<AppResult<void>> create(SongDocument document);

  /// Persist [document] when the on-disk `revision` equals
  /// [expectedRevision]. The optimistic-concurrency contract (ADR 0089
  /// §Döntés 3, ADR 0090 §5 kötött döntés 2) means the caller MUST
  /// re-read with [get] on a [SongRepositoryErrorCode.staleRevision]
  /// result — silent overwrite is forbidden.
  ///
  /// On success the persisted `revision` is `expectedRevision + 1`; the
  /// repository never persists the same revision twice even if the
  /// caller requests it.
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  });

  /// Move [id] into the trash directory. The actual file persists on disk
  /// until [restore] or [permanentlyDelete] resolves it (ADR 0090
  /// §Döntés 6).
  Future<AppResult<void>> moveToTrash(SongId id);

  /// Restore a previously trashed [id]. No-op (`Success`) when the song is
  /// not currently in trash — the operation is idempotent.
  Future<AppResult<void>> restore(SongId id);

  /// Permanently delete [id] and every orphan asset it owned (no other
  /// document references the asset's SHA-256). Destructive — the caller
  /// is expected to have confirmed the user intent.
  Future<AppResult<void>> permanentlyDelete(SongId id);
}

/// Quality-of-life factory used by callers that want to surface a typed
/// failure as an `AppResult`. Internally the repositories construct these
/// directly — the helper exists so application-layer code (import
/// controllers, diagnostics) that catches an exception can translate
/// without depending on a concrete repository implementation.
AppResult<T> songRepositoryFailure<T>(
  String code, {
  bool retryable = false,
  Object? cause,
  StackTrace? stackTrace,
}) {
  return AppResult<T>.failure(
    StorageFailure(
      code: code,
      retryable: retryable,
      cause: cause,
      stackTrace: stackTrace,
    ),
  );
}
