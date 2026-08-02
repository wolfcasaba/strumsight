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
import 'file_song_repository.dart';

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
  FileSongAssetRepository._({required this.root, required this.clock});

  /// Root of the song-tree on disk (same root the [FileSongRepository]
  /// uses — `assets/` and `originals/` live alongside `documents/`).
  final Directory root;

  /// Wall-clock for `createdAt` denormalisation. Injected for tests.
  final DateTime Function() clock;

  /// Open an asset store against the SAME [root] the song repository
  /// uses. The store creates `assets/` and `originals/` if missing.
  static Future<FileSongAssetRepository> openAtDirectory({
    required Directory root,
    DateTime Function()? clock,
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
    return FileSongAssetRepository._(root: root, clock: clock ?? DateTime.now);
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
      final actualHash = crypto.sha256.convert(bytes).toString();
      if (actualHash != request.expectedSha256) {
        return songAssetRepositoryFailure<SongAssetStoreReceipt>(
          SongAssetRepositoryErrorCode.hashMismatch,
        );
      }
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
      // Fresh asset — write the bytes, the per-asset refs file, then
      // return the canonical receipt.
      final targetBytes = Uint8List.fromList(bytes);
      final assetDir = Directory(
        '${root.path}/${request.isOriginal ? SongAssetStoreLayout.originalsDirectory : SongAssetStoreLayout.assetsDirectory}',
      );
      if (!await assetDir.exists()) {
        await assetDir.create(recursive: true);
      }
      final target = File('${assetDir.path}/$actualHash.${request.extension}');
      await _writeAtomic(target, targetBytes);
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
    }
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
    final bytes = await summaryFile.readAsBytes();
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map<String, dynamic>) return null;
    return _summaryFromMap(raw);
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
    await _writeAtomic(summaryFile, Uint8List.fromList(encoded));
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
    final raw = jsonDecode(utf8.decode(await refsFile.readAsBytes()));
    if (raw is! List) return <SongAssetHolder>[];
    final out = <SongAssetHolder>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final sha = entry['sha256'] is! String ? null : entry['sha256'] as String;
      final id = entry['holderId'] is! String
          ? null
          : entry['holderId'] as String;
      if (sha == null || id == null) continue;
      try {
        out.add(
          SongAssetHolder.forDocument(sha256: sha, holderId: SongAssetId(id)),
        );
      } on Object {
        // Skip malformed ref entries; the recovery scanner surfaces
        // them with a stable code.
      }
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
    await _writeAtomic(refsFile, Uint8List.fromList(utf8.encode(payload)));
  }

  Future<void> _writeAtomic(File target, Uint8List bytes) async {
    await target.parent.create(recursive: true);
    final existing = await _tryStat(target);
    if (existing) {
      target.deleteSync(recursive: false);
    }
    target.writeAsBytesSync(bytes, flush: true);
  }

  Future<bool> _tryStat(File file) async => file.existsSync();

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
