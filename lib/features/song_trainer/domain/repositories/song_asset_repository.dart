/// Persistence contract for the content-hash asset store
/// (E03-R07, ADR 0090 §Döntés 5, SDD §18.5 + §18.6).
///
/// The asset store is the **only** boundary the rest of the app talks to
/// when uploading, reading or deleting a binary payload attached to a
/// `SongDocument`. The document itself only carries the typed
/// `SongAssetReference` (sha256, byteLength, extension, mime, duration);
/// the bytes live here, deduplicated by SHA-256 and addressed by that
/// same hash (ADR 0090 §Döntés 5).
///
/// Asset operations are independent of the [SongRepository] contract: the
/// same hash may be referenced by multiple documents, and an asset only
/// becomes eligible for permanent deletion once every referencing document
/// is gone (the reference-count lives in this repository's index, not on
/// the documents). The two contracts are intentionally separate.
library;

import 'dart:typed_data';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../models/song_id.dart';

/// Stable machine-readable codes emitted by [SongAssetRepository].
abstract final class SongAssetRepositoryErrorCode {
  /// Bytes supplied to [SongAssetRepository.put] did not match the
  /// declared SHA-256. The write is rejected — integrity-first, always
  /// (ADR 0090 §Döntés 5 / §5 kötött döntés 3).
  static const String hashMismatch = 'songAssetRepository.hashMismatch';

  /// The asset bytes are larger than the documented
  /// [maxSongAssetByteLength] ceiling. The put is rejected before any
  /// disk I/O; the asset is not partially written.
  static const String assetTooLarge = 'songAssetRepository.assetTooLarge';

  /// The asset stream was empty (zero bytes). Rejected — a content-hash
  /// store treats empty bytes as a malformed input.
  static const String assetEmpty = 'songAssetRepository.assetEmpty';

  /// A permanent delete was requested but the asset still has at least
  /// one outstanding reference; the caller must wait or remove the
  /// referencing document first (ADR 0090 §Döntés 6).
  static const String stillReferenced = 'songAssetRepository.stillReferenced';

  /// The asset is missing on disk but at least one document references
  /// it. Triggers a recoverable report (corrupt / orphan reference).
  static const String missingAsset = 'songAssetRepository.missingAsset';

  /// Generic I/O failure surfaced cleanly. Cause lives inside
  /// `failure.cause` for the logger.
  static const String io = 'songAssetRepository.io';
}

/// Lightweight, summary-only view of a stored asset. Reflects the
/// information that lives inside the document's `SongAssetReference`
/// plus the reference count the store maintains independently (ADR 0090
/// §Döntés 5 — "repository-szintű reverse lookup").
final class SongAssetSummary {
  const SongAssetSummary({
    required this.assetId,
    required this.sha256,
    required this.extension,
    required this.byteLength,
    required this.mimeType,
    required this.durationMs,
    required this.createdAt,
    required this.referenceCount,
    required this.isOriginal,
  });

  /// Stable identifier of the asset record (the same value the document
  /// stores on its `SongAssetReference.id`).
  final SongAssetId assetId;

  /// Lower-case hex SHA-256 of the bytes.
  final String sha256;

  /// File extension without the leading dot.
  final String extension;

  /// Documented size in bytes (mirrors `SongAssetReference.byteLength`).
  final int byteLength;

  /// Optional MIME type — `null` when the importer could not determine
  /// one.
  final String? mimeType;

  /// Optional playback duration in milliseconds for time-bounded assets.
  /// `null` for static assets (images, fonts, JSON).
  final int? durationMs;

  /// UTC timestamp of the first successful [put].
  final DateTime createdAt;

  /// Live reference count — one per document / setlist / draft currently
  /// holding the asset. Stored only on disk, never on the document.
  final int referenceCount;

  /// True iff this asset was stored as the preserved original of an
  /// import (the `originals/` subdirectory in ADR 0090 §Döntés 1). The
  /// original asset store never interferes with normal asset deletion;
  /// this flag exists for diagnostics.
  final bool isOriginal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongAssetSummary &&
          other.assetId == assetId &&
          other.sha256 == sha256 &&
          other.extension == extension &&
          other.byteLength == byteLength &&
          other.mimeType == mimeType &&
          other.durationMs == durationMs &&
          other.createdAt.toUtc().microsecondsSinceEpoch ==
              createdAt.toUtc().microsecondsSinceEpoch &&
          other.referenceCount == referenceCount &&
          other.isOriginal == isOriginal;

  @override
  int get hashCode => Object.hash(
    assetId,
    sha256,
    extension,
    byteLength,
    mimeType,
    durationMs,
    createdAt.toUtc().microsecondsSinceEpoch,
    referenceCount,
    isOriginal,
  );
}

/// Result of an asset write — the [sha256] of the bytes (which becomes the
/// canonical address of the stored asset) and the typed `SongAssetId` the
/// caller should embed in the `SongAssetReference` it persists on the
/// document. The same bytes written twice produce the same pair.
final class SongAssetStoreReceipt {
  const SongAssetStoreReceipt({
    required this.assetId,
    required this.sha256,
    required this.byteLength,
    required this.duplicate,
  });

  /// Stable asset identifier — a fresh id when [duplicate] is `false`;
  /// the original id when [duplicate] is `true`.
  final SongAssetId assetId;

  /// Lower-case hex SHA-256 of the stored bytes.
  final String sha256;

  /// Documented byte size (the [Uint8List]'s length, post-validation).
  final int byteLength;

  /// True when the SHA-256 already had a stored asset; the bytes are NOT
  /// written a second time, and the reference count is bumped instead.
  final bool duplicate;
}

/// Metadata supplied alongside [SongAssetRepository.put]. The store
/// persists every field except [expectedSha256] (a contract assertion —
/// the store re-hashes the bytes to verify).
final class SongAssetWriteRequest {
  const SongAssetWriteRequest({
    required this.bytes,
    required this.assetId,
    required this.extension,
    required this.expectedSha256,
    this.mimeType,
    this.durationMs,
    this.isOriginal = false,
  });

  /// Asset bytes — `Uint8List` rather than `List<int>` so the store can
  /// pass them straight into `crypto.sha256.convert` without a copy.
  final Uint8List bytes;

  /// Stable identifier of the asset. On a duplicated SHA-256 the store
  /// honours the existing canonical id, not this one (the contract is
  /// content-addressed); on a fresh put the supplied id is canonicalised.
  final SongAssetId assetId;

  /// File extension WITHOUT the leading dot (e.g. `'mp3'`, `'png'`).
  final String extension;

  /// Expected SHA-256 of [bytes], lower-case hex, 64 chars. The store
  /// rejects the put with [SongAssetRepositoryErrorCode.hashMismatch]
  /// when the actual hash differs.
  final String expectedSha256;

  /// Optional MIME type — `null` when unknown.
  final String? mimeType;

  /// Optional duration in milliseconds for time-bounded assets.
  final int? durationMs;

  /// True when the asset is being stored in the `originals/` subdirectory
  /// rather than the regular `assets/` directory (ADR 0090 §Döntés 1 —
  /// the originals bucket is the preserved import source).
  final bool isOriginal;
}

/// A target for an asset-reference count event. The store increments the
/// reference count on `incrementReference` and decrements it on
/// `decrementReference`; the counter is a non-negative integer stored on
/// disk keyed by the `(sha256, holderId)` pair. The stringly-typed
/// `holderId` is documented as the canonical typed identifier of the
/// referencing entity — the store enforces no constraint on its
/// taxonomy (it accepts documents, setlists, drafts) but treats it as
/// opaque: the asset store never interprets it.
final class SongAssetHolder {
  const SongAssetHolder._({required this.sha256, required this.holderId});

  /// Lower-case hex SHA-256 of the referenced asset.
  final String sha256;

  /// The canonical typed identifier of the document (or setlist / draft)
  /// holding the reference — opaque to the asset store.
  final SongAssetId holderId;

  /// Construct a [SongAssetHolder] for the asset addressed by [sha256]
  /// from the document (or setlist / draft) identified by [holderId].
  factory SongAssetHolder.forDocument({
    required String sha256,
    required SongAssetId holderId,
  }) => SongAssetHolder._(sha256: sha256, holderId: holderId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongAssetHolder &&
          other.sha256 == sha256 &&
          other.holderId == holderId;

  @override
  int get hashCode => Object.hash(sha256, holderId);
}

/// Persistence contract for the content-hash asset store (ADR 0090
/// §Döntés 5, SDD §18.5 + §18.6).
///
/// The contract never throws an expected failure — every recovery-grade
/// outcome (hash mismatch, still referenced, missing asset, IO error)
/// returns an `AppResult.failure` with a stable code.
abstract interface class SongAssetRepository {
  /// Stream the bytes from [request] into the store. The store re-hashes
  /// the bytes with SHA-256 and refuses writes that do not match
  /// `request.expectedSha256`. On duplicate content the store does NOT
  /// write the bytes a second time — the caller's [SongAssetId] request
  /// is canonicalised against the existing entry.
  Future<AppResult<SongAssetStoreReceipt>> put(SongAssetWriteRequest request);

  /// Read the bytes addressed by [sha256]. Returns `Success(null)` when
  /// the asset is missing on disk.
  Future<AppResult<Uint8List?>> get(String sha256);

  /// Look up a stored asset by SHA-256. Returns `Success(null)` when the
  /// asset is missing on disk.
  Future<AppResult<SongAssetSummary?>> summary(String sha256);

  /// Increment the reference count for [holder]. Idempotent per
  /// `(sha256, holderId)` pair — re-registering the same holder is a
  /// no-op (the count is bumped exactly once).
  Future<AppResult<void>> incrementReference(SongAssetHolder holder);

  /// Decrement the reference count for [holder]. The store refuses
  /// to drop the count below zero. The asset itself is left on disk
  /// when the count is still positive; only [permanentlyDelete]
  /// removes bytes.
  Future<AppResult<void>> decrementReference(SongAssetHolder holder);

  /// Permanently delete the asset if and only if the live reference
  /// count is zero. Returns
  /// [SongAssetRepositoryErrorCode.stillReferenced] otherwise — the
  /// store NEVER drops bytes a document is still using (ADR 0090
  /// §Döntés 6, AGENTS.md §5 product rule).
  Future<AppResult<void>> permanentlyDelete(String sha256);
}

/// Quality-of-life factory used by callers that want to surface a typed
/// asset-store failure as an `AppResult`.
AppResult<T> songAssetRepositoryFailure<T>(
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
