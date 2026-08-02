/// Filesystem-backed [SongAssetRepository] implementing ADR 0090
/// §Döntés 5 + §6, SDD §18.5 + §18.6.
///
/// Layout (under the SAME root the song repository uses):
///
/// ```text
/// <root>/assets/<sha256>.<ext>
/// <root>/originals/<sha256>.<ext>
/// <root>/assets/<sha256>.<ext>.refs.json   (per-asset reference list)
/// ```
///
/// The asset store is keyed on SHA-256 (ADR 0090 §Döntés 5). Duplicate
/// bytes do NOT generate a second file — the existing asset is shared,
/// the reference counter is bumped, and the canonical asset-id is
/// returned in [SongAssetStoreReceipt].
///
/// The reference list is persisted per-asset as a small JSON file rather
/// than a single global index. Per-asset resolution lets the recovery
/// scanner walk O(N) files for orphan detection without parsing a single
/// globally-locked document.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_id.dart';
import '../../domain/repositories/song_asset_repository.dart';
import 'atomic_file_writer.dart';
import 'file_song_repository.dart';

/// Internal sentinel thrown by [_readSummary] / [_readRefs] when the
/// sidecar JSON cannot be decoded or fails type validation. The public
/// repository methods catch this and surface
/// [SongAssetRepositoryErrorCode.corruptSidecar] instead of letting
/// the raw `FormatException` / `TypeError` propagate.
class _CorruptSidecarException implements Exception {
  const _CorruptSidecarException(this.path);
  final String path;
}

/// One-shot digest capture sink for streamed SHA-256. The `crypto`
/// package ships an internal `DigestSink` but does not export it, so
/// the asset store carries its own one-shot sink.
class _CaptureDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value {
    final v = _value;
    if (v == null) {
      throw StateError(
        'CaptureDigestSink.value must not be read before the sink '
        'received a digest.',
      );
    }
    return v;
  }

  @override
  void add(crypto.Digest data) {
    if (_value != null) {
      throw StateError('CaptureDigestSink.add may only be called once.');
    }
    _value = data;
  }

  @override
  void close() {}
}

/// Filesystem subdirectory layout constants for the asset store.
abstract final class SongAssetStoreLayout {
  /// Subdirectory holding live assets (ADR 0090 §Döntés 1).
  static const String assetsDirectory = 'assets';

  /// Subdirectory holding preserved originals (out of scope for R07 —
  /// the layout is wired in but no caller is required to populate it).
  static const String originalsDirectory = 'originals';

  /// Per-asset reference index suffix.
  static const String refsExtension = '.refs.json';
}

/// Filesystem-backed implementation of [SongAssetRepository].
final class FileSongAssetRepository implements SongAssetRepository {
  FileSongAssetRepository._({
    required this.root,
    required this.clock,
    required this.writer,
  });

  /// Root of the song-tree on disk (same root the [FileSongRepository]
  /// uses — `assets/` and `originals/` live alongside `documents/`).
  final Directory root;

  /// Wall-clock for `createdAt` denormalisation. Injected for tests.
  final DateTime Function() clock;

  /// Atomic writer used for every bytes-and-sidecar write. The store
  /// delegates staged temp + flush + verify + rename to this single
  /// boundary so the recovery scanner only has to walk one place
  /// (`<root>/temp/`) for crash residue.
  final AtomicFileWriter writer;

  /// Lazily-built staging directory inside the songs root's `temp/`
  /// subdirectory. The atomic writer places its staged temp files
  /// here so the recovery scanner's `temp/` walk sees real crash
  /// residue (ADR 0090 §Döntés 1).
  Directory? _stagingDirectoryCache;

  Directory _stagingDirectory() {
    final cached = _stagingDirectoryCache;
    if (cached != null) return cached;
    final built = Directory(
      '${root.path}/${SongRepositoryLayout.tempDirectory}',
    );
    _stagingDirectoryCache = built;
    return built;
  }

  /// Open an asset store against the SAME [root] the song repository
  /// uses. The store creates `assets/` and `originals/` if missing.
  static Future<FileSongAssetRepository> openAtDirectory({
    required Directory root,
    DateTime Function()? clock,
    AtomicFileWriter? writer,
  }) async {
    for (final sub in const <String>[
      '',
      SongAssetStoreLayout.assetsDirectory,
      SongAssetStoreLayout.originalsDirectory,
    ]) {
      final directory = sub.isEmpty ? root : Directory('${root.path}/$sub');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }
    return FileSongAssetRepository._(
      root: root,
      clock: clock ?? DateTime.now,
      writer: writer ?? const AtomicFileWriter(),
    );
  }

  // ---------------------------------------------------------------------------
  // SongAssetRepository
  // ---------------------------------------------------------------------------

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async {
    try {
      final bytes = request.bytes;
      if (bytes.isEmpty) {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.assetEmpty,
        );
      }
      if (bytes.length > maxSongAssetByteLength) {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.assetTooLarge,
        );
      }
      // Streamed SHA-256 — chunks the bytes through a chunked-conversion
      // sink so no intermediate full-buffer digest is materialised.
      final actualHash = _streamedSha256(bytes);
      if (actualHash != request.expectedSha256) {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.hashMismatch,
        );
      }
      try {
        final existing = await _readSummary(actualHash);
        if (existing != null) {
          // Duplicate — bump the reference count and return the canonical
          // asset-id. We do NOT write the bytes a second time.
          return _incrementAndReturn(
            actualHash: actualHash,
            existing: existing,
            request: request,
          );
        }
      } on _CorruptSidecarException {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.corruptSidecar,
        );
      }
      // Fresh asset — write the bytes via the streaming atomic writer
      // (chunked write + chunked hash), then the per-asset sidecars
      // via the small-payload atomic writer. Every temp file lands
      // under `<root>/temp/` so the recovery scanner can classify it.
      final assetDir = Directory(
        '${root.path}/${request.isOriginal ? SongAssetStoreLayout.originalsDirectory : SongAssetStoreLayout.assetsDirectory}',
      );
      if (!await assetDir.exists()) {
        await assetDir.create(recursive: true);
      }
      final target = File('${assetDir.path}/$actualHash.${request.extension}');
      final outcome = writer.writeStream(
        target: target,
        bytes: bytes,
        stagingDirectory: _stagingDirectory(),
        verifier: (onDiskDigest) => onDiskDigest == actualHash,
      );
      if (!outcome.committed) {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.hashMismatch,
        );
      }
      final summary = SongAssetSummary(
        assetId: request.assetId,
        sha256: actualHash,
        extension: request.extension,
        byteLength: bytes.length,
        mimeType: request.mimeType,
        durationMs: request.durationMs,
        createdAt: clock().toUtc(),
        referenceCount: 0,
        isOriginal: request.isOriginal,
      );
      await _writeRefsFile(actualHash, <SongAssetHolder>[]);
      await _writeSummaryFile(actualHash, summary);
      return AppResult<SongAssetStoreReceipt>.success(
        SongAssetStoreReceipt(
          assetId: request.assetId,
          sha256: actualHash,
          byteLength: bytes.length,
          duplicate: false,
        ),
      );
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<SongAssetStoreReceipt>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    } on _CorruptSidecarException {
      return songAssetRepositoryFailure<SongAssetStoreReceipt>(
        SongAssetRepositoryErrorCode.corruptSidecar,
      );
    }
  }

  /// Streamed SHA-256 — chunks [bytes] through the
  /// `crypto.sha256.startChunkedConversion` sink so the digest is
  /// computed incrementally. No intermediate full-buffer digest is
  /// materialised.
  String _streamedSha256(Uint8List bytes) {
    final digestSink = _CaptureDigestSink();
    final sink = crypto.sha256.startChunkedConversion(digestSink);
    const chunkSize = AtomicFileWriter.defaultChunkSize;
    var offset = 0;
    while (offset < bytes.length) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      sink.add(bytes.sublist(offset, end));
      offset = end;
    }
    sink.close();
    return digestSink.value.toString();
  }

  @override
  Future<AppResult<Uint8List?>> get(String sha256) async {
    try {
      final assetsDir = Directory(
        '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
      );
      final originalsDir = Directory(
        '${root.path}/${SongAssetStoreLayout.originalsDirectory}',
      );
      final result =
          await _tryReadAsset(assetsDir, sha256) ??
          await _tryReadAsset(originalsDir, sha256);
      if (result == null) {
        return AppResult<Uint8List?>.success(null);
      }
      // Re-hash the on-disk bytes against the asset's own SHA-256
      // filename. A bit-rotted or truncated asset file MUST NOT be
      // served as a normal Success (ADR 0090 §Döntés 5, brief §6
      // mandatory matrix row "asset hash mismatch -> corrupt report,
      // nincs néma playback").
      final recomputed = _streamedSha256(result);
      if (recomputed != sha256) {
        return songAssetRepositoryFailure<Uint8List?>(
          SongAssetRepositoryErrorCode.corruptAsset,
        );
      }
      return AppResult<Uint8List?>.success(result);
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<Uint8List?>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async {
    try {
      final summary = await _readSummary(sha256);
      return AppResult<SongAssetSummary?>.success(summary);
    } on _CorruptSidecarException {
      return songAssetRepositoryFailure<SongAssetSummary?>(
        SongAssetRepositoryErrorCode.corruptSidecar,
      );
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<SongAssetSummary?>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async {
    try {
      final refs = await _readRefs(holder.sha256);
      if (refs.any((existing) => existing.holderId == holder.holderId)) {
        return AppResult<void>.success(null);
      }
      refs.add(holder);
      await _writeRefsFile(holder.sha256, refs);
      await _rewriteSummaryWithCount(holder.sha256, refs.length);
      return AppResult<void>.success(null);
    } on _CorruptSidecarException {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.corruptSidecar,
      );
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async {
    try {
      final refs = await _readRefs(holder.sha256);
      refs.removeWhere((existing) => existing.holderId == holder.holderId);
      await _writeRefsFile(holder.sha256, refs);
      await _rewriteSummaryWithCount(holder.sha256, refs.length);
      return AppResult<void>.success(null);
    } on _CorruptSidecarException {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.corruptSidecar,
      );
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async {
    try {
      final refs = await _readRefs(sha256);
      if (refs.isNotEmpty) {
        return songAssetRepositoryFailure<void>(
          SongAssetRepositoryErrorCode.stillReferenced,
        );
      }
      final assetsDir = Directory(
        '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
      );
      final originalsDir = Directory(
        '${root.path}/${SongAssetStoreLayout.originalsDirectory}',
      );
      for (final assetDir in [assetsDir, originalsDir]) {
        if (!await assetDir.exists()) continue;
        final candidates = assetDir.listSync().whereType<File>().where(
          (f) => f.path.contains(sha256),
        );
        for (final file in candidates) {
          await file.delete();
        }
      }
      // Best-effort: drop the refs and summary sidecars so the
      // recovery scanner does not see a dangling summary. We tolerate
      // missing files (a duplicate-delete is no-op).
      final refsFile = File(
        '${assetsDir.path}/$sha256${SongAssetStoreLayout.refsExtension}',
      );
      if (await refsFile.exists()) {
        await refsFile.delete();
      }
      // The summary file is a sidecar carrying the original asset-id —
      // it follows the convention `<sha256>.summary.json` and lives next
      // to the refs file so the recovery scanner can rebuild either.
      final summarySidecar = File('${assetsDir.path}/$sha256.summary.json');
      if (await summarySidecar.exists()) {
        await summarySidecar.delete();
      }
      return AppResult<void>.success(null);
    } on _CorruptSidecarException {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.corruptSidecar,
      );
    } on FileSystemException catch (e) {
      return songAssetRepositoryFailure<void>(
        SongAssetRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<AppResult<SongAssetStoreReceipt>> _incrementAndReturn({
    required String actualHash,
    required SongAssetSummary existing,
    required SongAssetWriteRequest request,
  }) async {
    final refs = await _readRefs(actualHash);
    if (!refs.any((r) => r.holderId == request.assetId)) {
      // The supply-side asset-id is honoured as a new reference; the
      // canonical receipt uses the EXISTING canonical asset-id, not the
      // supplied one (the store is content-addressed).
      refs.add(
        SongAssetHolder.forDocument(
          sha256: actualHash,
          holderId: request.assetId,
        ),
      );
      await _writeRefsFile(actualHash, refs);
      await _rewriteSummaryWithCount(actualHash, refs.length);
    }
    return AppResult<SongAssetStoreReceipt>.success(
      SongAssetStoreReceipt(
        assetId: existing.assetId,
        sha256: actualHash,
        byteLength: existing.byteLength,
        duplicate: true,
      ),
    );
  }

  Future<Uint8List?> _tryReadAsset(Directory base, String sha256) async {
    if (!await base.exists()) return null;
    final entries = base.listSync().whereType<File>();
    for (final file in entries) {
      final name = file.uri.pathSegments.last;
      if (name.startsWith('$sha256.') &&
          !name.endsWith(SongAssetStoreLayout.refsExtension) &&
          !name.endsWith('.summary.json')) {
        return Uint8List.fromList(await file.readAsBytes());
      }
    }
    return null;
  }

  Future<SongAssetSummary?> _readSummary(String sha256) async {
    final assetsDir = Directory(
      '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
    );
    final summaryFile = File('${assetsDir.path}/$sha256.summary.json');
    if (!await summaryFile.exists()) return null;
    final Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(utf8.decode(await summaryFile.readAsBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw _CorruptSidecarException(summaryFile.path);
      }
      raw = decoded;
    } on FormatException catch (_) {
      throw _CorruptSidecarException(summaryFile.path);
    }
    try {
      return _summaryFromMap(raw);
    } on TypeError catch (_) {
      throw _CorruptSidecarException(summaryFile.path);
    }
  }

  Future<void> _writeSummaryFile(
    String sha256,
    SongAssetSummary summary,
  ) async {
    final assetsDir = Directory(
      '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
    );
    final summaryFile = File('${assetsDir.path}/$sha256.summary.json');
    final encoded = utf8.encode(jsonEncode(_summaryToMap(summary)));
    final outcome = writer.write(
      target: summaryFile,
      bytes: Uint8List.fromList(encoded),
      stagingDirectory: _stagingDirectory(),
      verifier: (back) {
        // Round-trip the sidecar through the codec so a partial write
        // is caught before the rename lands.
        final decoded = jsonDecode(utf8.decode(back));
        if (decoded is! Map<String, dynamic>) return false;
        return true;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException(
        'AtomicFileWriter refused to commit the asset summary sidecar.',
      );
    }
  }

  Future<void> _rewriteSummaryWithCount(String sha256, int newCount) async {
    final existing = await _readSummary(sha256);
    if (existing == null) return;
    await _writeSummaryFile(
      sha256,
      SongAssetSummary(
        assetId: existing.assetId,
        sha256: existing.sha256,
        extension: existing.extension,
        byteLength: existing.byteLength,
        mimeType: existing.mimeType,
        durationMs: existing.durationMs,
        createdAt: existing.createdAt,
        referenceCount: newCount,
        isOriginal: existing.isOriginal,
      ),
    );
  }

  Future<List<SongAssetHolder>> _readRefs(String sha256) async {
    final assetsDir = Directory(
      '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
    );
    final refsFile = File(
      '${assetsDir.path}/$sha256${SongAssetStoreLayout.refsExtension}',
    );
    if (!await refsFile.exists()) {
      return <SongAssetHolder>[];
    }
    final List<dynamic> raw;
    try {
      final decoded = jsonDecode(utf8.decode(await refsFile.readAsBytes()));
      if (decoded is! List) {
        throw _CorruptSidecarException(refsFile.path);
      }
      raw = decoded;
    } on FormatException catch (_) {
      throw _CorruptSidecarException(refsFile.path);
    }
    final out = <SongAssetHolder>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, dynamic>) {
        throw _CorruptSidecarException(refsFile.path);
      }
      final sha = entry['sha256'] is! String ? null : entry['sha256'] as String;
      final id = entry['holderId'] is! String
          ? null
          : entry['holderId'] as String;
      if (sha == null || id == null) {
        throw _CorruptSidecarException(refsFile.path);
      }
      out.add(
        SongAssetHolder.forDocument(sha256: sha, holderId: SongAssetId(id)),
      );
    }
    return out;
  }

  Future<void> _writeRefsFile(String sha256, List<SongAssetHolder> refs) async {
    final assetsDir = Directory(
      '${root.path}/${SongAssetStoreLayout.assetsDirectory}',
    );
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }
    final refsFile = File(
      '${assetsDir.path}/$sha256${SongAssetStoreLayout.refsExtension}',
    );
    final payload = jsonEncode([
      for (final holder in refs)
        <String, dynamic>{
          'sha256': holder.sha256,
          'holderId': holder.holderId.value,
        },
    ]);
    final outcome = writer.write(
      target: refsFile,
      bytes: Uint8List.fromList(utf8.encode(payload)),
      stagingDirectory: _stagingDirectory(),
      verifier: (back) {
        final decoded = jsonDecode(utf8.decode(back));
        if (decoded is! List) return false;
        return true;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException(
        'AtomicFileWriter refused to commit the asset refs sidecar.',
      );
    }
  }

  static Map<String, dynamic> _summaryToMap(SongAssetSummary summary) {
    return <String, dynamic>{
      'assetId': summary.assetId.value,
      'sha256': summary.sha256,
      'extension': summary.extension,
      'byteLength': summary.byteLength,
      'mimeType': summary.mimeType,
      'durationMs': summary.durationMs,
      'createdAt': summary.createdAt.toUtc().toIso8601String(),
      'referenceCount': summary.referenceCount,
      'isOriginal': summary.isOriginal,
    };
  }

  static SongAssetSummary _summaryFromMap(Map<String, dynamic> json) {
    return SongAssetSummary(
      assetId: SongAssetId(json['assetId'] as String),
      sha256: json['sha256'] as String,
      extension: json['extension'] as String,
      byteLength: (json['byteLength'] as num).toInt(),
      mimeType: json['mimeType'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      referenceCount: (json['referenceCount'] as num).toInt(),
      isOriginal: json['isOriginal'] as bool,
    );
  }
}
