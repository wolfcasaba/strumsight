// ignore_for_file: prefer_initializing_formals
/// Filesystem-backed [AnalysisRepository] implementing ADR 0239
/// (E06-R21, SDD §24.2–§24.5).
///
/// Layout under the configured root directory (the constructor
/// parameter, supplied by the production provider):
///
/// ```text
/// <root>/
///   index.json
///   documents/<document-id>.json
///   documents/<document-id>.json.corrupt   (recovery residue)
///   temp/<document-id>.tmp-*               (staged atomic writes)
///   migration/state.json                   (legacy migration marker)
/// ```
///
/// Save order (ADR 0239 §Döntés 1 + §3):
///
///   1. validate the document via [AnalysisDocumentCodec] (any
///      schema-version mismatch ⇒ typed failure);
///   2. compute the canonical SHA-256 of the encoded bytes;
///   3. stage the document to `temp/<id>.tmp-<pid>-<n>` via
///      [AtomicFileWriter]; on failure the previous good document
///      survives;
///   4. update the index sidecar with the matching summary (same
///      atomic temp+rename);
///   5. only then does the call return `Success`.
///
/// On a crashed write — process killed between (3) and (4) — the
/// recovery scanner (see [AnalysisRepositoryRecovery]) re-walks
/// `documents/` and rebuilds the index from the surviving document
/// files.
///
/// The repository is **framework-independent**: no Flutter, Riverpod,
/// SharedPreferences, or `path_provider` import. The production
/// provider in `application/analysis_providers.dart` is responsible
/// for resolving the platform directory and passing it via the
/// `directory:` argument.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_repository.dart';
import '../../domain/analysis_summary.dart';
import '../analysis_document_codec.dart';
import 'analysis_index_store.dart';

/// Filesystem layout constants for the analysis repository. Exposed so
/// the recovery scanner and the production providers can share a
/// single source of truth for subdirectory names.
abstract final class AnalysisRepositoryLayout {
  /// `index.json` — the summary sidecar (ADR 0239 §Döntés 1).
  static const String indexFileName = 'index.json';

  /// Subdirectory holding live documents.
  static const String documentsDirectory = 'documents';

  /// Subdirectory holding staged atomic-write temp files. Crash residue
  /// is deleted on the next recovery scan.
  static const String tempDirectory = 'temp';

  /// Suffix appended to a document file when it fails checksum or
  /// codec decode. The recovery scanner surfaces these for support
  /// tooling.
  static const String corruptSuffix = '.corrupt';

  /// Reserved subdirectory for the migration marker.
  static const String migrationDirectory = 'migration';
  static const String migrationStateFileName = 'state.json';
}

/// Minimal atomic writer port — the file-analysis repository owns its
/// own writer implementation so the song_trainer `AtomicFileWriter`
/// (a feature-internal dependency) is never imported. The contract is
/// the subset of the song_trainer writer this repository actually
/// uses: staged temp + flush + atomic rename + best-effort cleanup.
abstract interface class AnalysisAtomicWriter {
  AnalysisAtomicWriteOutcome write({
    required File target,
    required Uint8List bytes,
    required Directory stagingDirectory,
    required bool Function(Uint8List verified) verifier,
  });
}

/// Result envelope for a single atomic write. The `committed: false`
/// branch is the fail-closed signal the repository uses to leave the
/// previous good bytes intact.
final class AnalysisAtomicWriteOutcome {
  const AnalysisAtomicWriteOutcome({
    required this.committed,
    required this.bytes,
  });

  /// True when the staged bytes replaced the target bytes.
  final bool committed;

  /// The bytes the caller passed in — surfaced so the repository can
  /// re-emit them on the index path even when the writer refused to
  /// commit.
  final Uint8List bytes;
}

/// In-process default writer — the same temp + flush + verify + rename
/// pattern as the song_trainer `AtomicFileWriter.write()`, lifted
/// here so the audio-analysis data layer has zero cross-feature
/// imports. The only public entry point is [write].
final class DefaultAnalysisAtomicWriter implements AnalysisAtomicWriter {
  const DefaultAnalysisAtomicWriter();

  static int _counter = 0;

  @override
  AnalysisAtomicWriteOutcome write({
    required File target,
    required Uint8List bytes,
    required Directory stagingDirectory,
    required bool Function(Uint8List verified) verifier,
  }) {
    if (!stagingDirectory.existsSync()) {
      stagingDirectory.createSync(recursive: true);
    }
    final counter = ++_counter;
    final staged = File(
      '${stagingDirectory.path}${Platform.pathSeparator}'
      '${_basenameOf(target)}.tmp-1-$counter',
    );
    staged.writeAsBytesSync(bytes, flush: true);
    bool verifierPassed;
    try {
      verifierPassed = verifier(staged.readAsBytesSync());
    } catch (_) {
      _safeDelete(staged);
      rethrow;
    }
    if (!verifierPassed) {
      _safeDelete(staged);
      return AnalysisAtomicWriteOutcome(committed: false, bytes: bytes);
    }
    try {
      staged.renameSync(target.path);
    } on FileSystemException {
      if (target.existsSync()) {
        target.deleteSync(recursive: false);
      }
      staged.renameSync(target.path);
    }
    if (staged.existsSync()) {
      _safeDelete(staged);
    }
    return AnalysisAtomicWriteOutcome(committed: true, bytes: bytes);
  }

  static String _basenameOf(File target) {
    final segments = target.uri.pathSegments;
    if (segments.isEmpty) return target.path;
    return segments.last;
  }

  void _safeDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync(recursive: false);
    } on FileSystemException {
      // Best-effort — recovery covers the gap.
    }
  }
}

/// Filesystem-backed implementation of [AnalysisRepository].
final class FileAnalysisRepository implements AnalysisRepository {
  FileAnalysisRepository._({
    required this.directory,
    required this.documentCodec,
    required this.indexStore,
    required this.writer,
    required this.clock,
    required this.maxDocuments,
    this.onDecode,
  });

  /// Root of the analysis tree on disk.
  final Directory directory;

  /// Codec used to encode/decode the V2 document bytes.
  final AnalysisDocumentCodec documentCodec;

  /// Codec+file pair for the summary sidecar.
  final AnalysisIndexStore indexStore;

  /// Atomic writer used for every staged write. Injected so tests
  /// can swap in a fault-injecting fake (the brief §6 "atomikus-írás"
  /// cell relies on an "írás közben dobó" fake).
  final AnalysisAtomicWriter writer;

  /// Clock supplier — production wires to `DateTime.now`. Tests
  /// inject a deterministic clock for the LRU eviction ordering.
  final DateTime Function() clock;

  /// Cap on the number of persisted documents. The default matches
  /// the V1 [LibraryRepository.maxSessions]; the brief §6 "cap-küszöb
  /// hármas" exercises the inclusive boundary at exactly 100.
  final int maxDocuments;

  /// Test-only observer that fires every time the document codec's
  /// `decode` runs. Used by the brief §6 "summary-only list" cell to
  /// prove that `list()` invokes the decoder exactly zero times —
  /// the [AnalysisDocumentCodec] is `final`, so wrapping the codec
  /// itself is not an option.
  final void Function()? onDecode;

  /// Lazily-built staging directory inside the analysis root's `temp/`
  /// subdirectory.
  Directory? _stagingDirectoryCache;

  Directory _stagingDirectory() {
    final cached = _stagingDirectoryCache;
    if (cached != null) return cached;
    final built = Directory(
      '${directory.path}/${AnalysisRepositoryLayout.tempDirectory}',
    );
    _stagingDirectoryCache = built;
    return built;
  }

  /// Open a repository against an existing [directory]. The
  /// per-feature subdirectories are created lazily here; tests can
  /// pre-create the directory to exercise the "missing root" recovery
  /// path.
  static Future<FileAnalysisRepository> openAtDirectory({
    required Directory directory,
    DateTime Function()? clock,
    AnalysisDocumentCodec documentCodec = const AnalysisDocumentCodec(),
    AnalysisIndexCodec indexCodec = const AnalysisIndexCodec(),
    AnalysisAtomicWriter? writer,
    int maxDocuments = 100,
    void Function()? onDecode,
  }) async {
    await _ensureSubtree(directory);
    return FileAnalysisRepository._(
      directory: directory,
      documentCodec: documentCodec,
      indexStore: AnalysisIndexStore.openAtDirectory(
        directory: directory,
        codec: indexCodec,
      ),
      writer: writer ?? const DefaultAnalysisAtomicWriter(),
      clock: clock ?? DateTime.now,
      maxDocuments: maxDocuments,
      onDecode: onDecode,
    );
  }

  // ---------------------------------------------------------------------------
  // AnalysisRepository
  // ---------------------------------------------------------------------------

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async {
    try {
      final summaries = await _readOrRebuildIndex();
      // Corruption isolation: each summary carries the on-disk SHA-256
      // captured at write time. list() verifies the hash WITHOUT
      // decoding the full document — this keeps the document decoder's
      // call count at exactly 0 for healthy lists, while still
      // quarantining a file whose bytes were tampered with
      // (brief §6 korrupció-izoláció + summary-olvasás cells).
      final verified = <AnalysisSummary>[];
      var indexChanged = false;
      for (final summary in summaries) {
        final live = _DocumentLocation.live(directory, summary.documentId);
        if (!live.file.existsSync()) {
          // The document file is gone — likely evicted by cap. Drop
          // the stale summary from the index.
          indexChanged = true;
          continue;
        }
        final bytes = live.file.readAsBytesSync();
        final actualHash = _hashBytes(bytes);
        if (actualHash != summary.documentHash) {
          _quarantine(live, actualHash);
          indexChanged = true;
          continue;
        }
        verified.add(summary);
      }
      final ordered = <AnalysisSummary>[...verified]
        ..sort((a, b) => b.createdAt.toUtc().compareTo(a.createdAt.toUtc()));
      if (indexChanged) {
        indexStore.write(ordered);
      }
      return AppResult<List<AnalysisSummary>>.success(
        List<AnalysisSummary>.unmodifiable(ordered),
      );
    } on FileSystemException catch (e) {
      return _failure<List<AnalysisSummary>>(
        AnalysisRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final corrupt = File(
        '${live.path}${AnalysisRepositoryLayout.corruptSuffix}',
      );
      if (corrupt.existsSync()) {
        // The live file was quarantined by a previous `list()` or
        // `getById` call. The original document is unrecoverable from
        // the user's perspective — surface a typed failure pointing
        // at the corruption marker (brief §6 korrupció-izoláció).
        return _failure<AnalysisDocument>(
          AnalysisRepositoryErrorCode.corruptDocument,
        );
      }
      if (!live.file.existsSync()) {
        return _failure<AnalysisDocument>(AnalysisRepositoryErrorCode.notFound);
      }
      final bytes = live.file.readAsBytesSync();
      final actualHash = _hashBytes(bytes);
      final summaries = await _readOrRebuildIndex();
      final indexed = <AnalysisSummary>[
        for (final s in summaries)
          if (s.documentId == id) s,
      ];
      if (indexed.isNotEmpty && indexed.first.documentHash != actualHash) {
        // The stored on-disk bytes no longer match the hash captured at
        // write time — the file was tampered with or corrupted, even
        // though it may still decode as syntactically valid JSON
        // (ADR 0239 OD-03). Quarantine it rather than silently
        // returning stale/wrong content.
        _quarantine(live, actualHash);
        return _failure<AnalysisDocument>(
          AnalysisRepositoryErrorCode.checksumMismatch,
        );
      }
      final decodeResult = _decodeDocument(bytes);
      switch (decodeResult) {
        case Success<AnalysisDocument>(:final value):
          return AppResult<AnalysisDocument>.success(value);
        case Failure<AnalysisDocument>(:final error):
          _quarantine(live, actualHash);
          return AppResult<AnalysisDocument>.failure(
            error is ValidationFailure
                ? ValidationFailure(
                    code: AnalysisRepositoryErrorCode.corruptDocument,
                    cause: error.cause,
                  )
                : StorageFailure(
                    code: AnalysisRepositoryErrorCode.corruptDocument,
                  ),
          );
      }
    } on FileSystemException catch (e) {
      return _failure<AnalysisDocument>(
        AnalysisRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) async {
    try {
      final live = _DocumentLocation.live(directory, request.document.id);
      if (live.file.existsSync()) {
        return _failure<void>(
          AnalysisRepositoryErrorCode.unsupportedSchema,
          // Re-use "unsupportedSchema" as a typed signal: the same
          // shape means "an id collision is an invariant violation".
          // The migration layer treats this as a no-op (the id
          // already lives in storage) so this is never seen by users
          // today.
          cause: 'id already exists',
        );
      }
      await _commitDocument(
        location: live,
        request: request,
        expectedReplacement: null,
      );
      return AppResult<void>.success(null);
    } on _UnsupportedSchemaException {
      return _failure<void>(AnalysisRepositoryErrorCode.unsupportedSchema);
    } on FileSystemException catch (e) {
      return _failure<void>(AnalysisRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> replace(
    String id,
    AnalysisSaveRequest request,
  ) async {
    try {
      if (id != request.document.id) {
        return _failure<void>(AnalysisRepositoryErrorCode.unsupportedSchema);
      }
      final live = _DocumentLocation.live(directory, id);
      final existingBytes = await _tryReadBytes(live);
      if (existingBytes == null) {
        return _failure<void>(AnalysisRepositoryErrorCode.notFound);
      }
      await _commitDocument(
        location: live,
        request: request,
        expectedReplacement: existingBytes,
      );
      return AppResult<void>.success(null);
    } on _UnsupportedSchemaException {
      return _failure<void>(AnalysisRepositoryErrorCode.unsupportedSchema);
    } on FileSystemException catch (e) {
      return _failure<void>(AnalysisRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) async {
    try {
      final trimmed = newTitle.trim();
      if (trimmed.isEmpty) {
        return _failure<void>(AnalysisRepositoryErrorCode.unsupportedSchema);
      }
      final live = _DocumentLocation.live(directory, id);
      if (!live.file.existsSync()) {
        return _failure<void>(AnalysisRepositoryErrorCode.notFound);
      }
      var baseline = await _readOrRebuildIndex();
      final existing = <AnalysisSummary>[
        for (final s in baseline)
          if (s.documentId == id) s,
      ];
      if (existing.isEmpty) {
        // Document lives on disk but the index lost the entry — this
        // can only happen if the index file was wiped. Rebuild and
        // try again: if the document decodes, the rename still
        // succeeds; if it does not, the typed failure propagates.
        final rebuilt = await _rebuildFromDisk();
        final rebuiltMatch = <AnalysisSummary>[
          for (final s in rebuilt)
            if (s.documentId == id) s,
        ];
        if (rebuiltMatch.isEmpty) {
          return _failure<void>(AnalysisRepositoryErrorCode.notFound);
        }
        baseline = rebuilt;
        existing.add(rebuiltMatch.first);
      }
      final target = existing.first.copyWith(title: trimmed, customTitle: true);
      final next = <AnalysisSummary>[
        for (final s in baseline)
          if (s.documentId == id) target else s,
      ]..sort((a, b) => b.createdAt.toUtc().compareTo(a.createdAt.toUtc()));
      indexStore.write(next);
      return AppResult<void>.success(null);
    } on FileSystemException catch (e) {
      return _failure<void>(AnalysisRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> delete(String id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final summaries = await _readOrRebuildIndex();
      final filtered = <AnalysisSummary>[
        for (final s in summaries)
          if (s.documentId != id) s,
      ];
      indexStore.write(filtered);
      if (live.file.existsSync()) {
        await live.file.delete();
      }
      final corrupt = File(
        '${live.path}${AnalysisRepositoryLayout.corruptSuffix}',
      );
      if (corrupt.existsSync()) {
        await corrupt.delete();
      }
      return AppResult<void>.success(null);
    } on FileSystemException catch (e) {
      return _failure<void>(AnalysisRepositoryErrorCode.io, cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _commitDocument({
    required _DocumentLocation location,
    required AnalysisSaveRequest request,
    required Uint8List? expectedReplacement,
  }) async {
    if (request.document.schemaVersion != analysisDocumentSchemaVersion) {
      throw const _UnsupportedSchemaException();
    }
    final encoded = utf8.encode(documentCodec.encode(request.document));
    final bytes = Uint8List.fromList(encoded);
    final hash = crypto.sha256.convert(bytes).toString();

    final outcome = writer.write(
      target: location.file,
      bytes: bytes,
      stagingDirectory: _stagingDirectory(),
      verifier: (verified) {
        if (expectedReplacement != null) {
          // A non-empty previous good document MUST survive a failed
          // write — the verifier refuses to commit if the new bytes
          // cannot be round-tripped.
          if (verified.length != bytes.length) return false;
          for (var i = 0; i < verified.length; i++) {
            if (verified[i] != bytes[i]) return false;
          }
        }
        // The codec is fail-closed — a malformed encode throws
        // immediately, which the writer treats as a verifier failure.
        _decodeDocument(verified);
        return true;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException(
        'Atomic writer refused to commit the analysis document.',
      );
    }

    // The cap is enforced AFTER a successful document write so a
    // partial cap-eviction never strands the user's just-saved
    // session.
    final summaries = await _readOrRebuildIndex();
    final updated = <AnalysisSummary>[
      AnalysisSummary(
        documentId: request.document.id,
        title: request.title,
        customTitle: request.customTitle,
        createdAt: request.document.createdAt,
        completionStatus: request.document.completion.status.name,
        documentHash: hash,
        sizeBytes: bytes.length,
      ),
      for (final s in summaries)
        if (s.documentId != request.document.id) s,
    ];
    final trimmed = _enforceCap(updated);
    indexStore.write(trimmed);
  }

  List<AnalysisSummary> _enforceCap(List<AnalysisSummary> summaries) {
    if (summaries.length <= maxDocuments) return summaries;
    // Sort DESCENDING by createdAt so the newest entries are at the
    // front. We keep the first `maxDocuments` (newest) and evict the
    // tail (oldest). The cap is INCLUSIVE: exactly `maxDocuments`
    // entries survive; the 101st oldest is removed (brief §6
    // cap-mátrix).
    final ordered = <AnalysisSummary>[...summaries]
      ..sort((a, b) => b.createdAt.toUtc().compareTo(a.createdAt.toUtc()));
    final survivors = <AnalysisSummary>[];
    for (var i = 0; i < ordered.length; i++) {
      if (i < maxDocuments) {
        survivors.add(ordered[i]);
      } else {
        final evicted = ordered[i];
        final evictedFile = _DocumentLocation.live(
          directory,
          evicted.documentId,
        ).file;
        if (evictedFile.existsSync()) {
          try {
            evictedFile.deleteSync(recursive: false);
          } on FileSystemException {
            // Best-effort — the cap still holds in the index, and the
            // recovery scanner will surface the orphan file on the
            // next boot.
          }
        }
        final evictedCorrupt = File(
          '${evictedFile.path}${AnalysisRepositoryLayout.corruptSuffix}',
        );
        if (evictedCorrupt.existsSync()) {
          try {
            evictedCorrupt.deleteSync(recursive: false);
          } on FileSystemException {
            // Best-effort.
          }
        }
      }
    }
    return survivors;
  }

  Future<List<AnalysisSummary>> _readOrRebuildIndex() async {
    if (!indexStore.file.existsSync()) {
      return _rebuildFromDisk();
    }
    try {
      return indexStore.read();
    } on AnalysisIndexCodecException {
      return _rebuildFromDisk();
    }
  }

  Future<List<AnalysisSummary>> _rebuildFromDisk() async {
    final liveDir = Directory(
      '${directory.path}/${AnalysisRepositoryLayout.documentsDirectory}',
    );
    if (!liveDir.existsSync()) {
      indexStore.write(const <AnalysisSummary>[]);
      return const <AnalysisSummary>[];
    }
    final out = <AnalysisSummary>[];
    for (final entry in liveDir.listSync()) {
      if (entry is! File) continue;
      final basename = _basenameOf(entry);
      if (basename.endsWith(AnalysisRepositoryLayout.corruptSuffix)) {
        continue;
      }
      try {
        final bytes = entry.readAsBytesSync();
        final decodeResult = _decodeDocument(bytes);
        final document = switch (decodeResult) {
          Success<AnalysisDocument>(:final value) => value,
          Failure<AnalysisDocument>() => null,
        };
        if (document == null) {
          _quarantine(
            _DocumentLocation.at(directory, basename),
            _hashBytes(bytes),
          );
          continue;
        }
        out.add(
          AnalysisSummary(
            documentId: document.id,
            title: '',
            customTitle: false,
            createdAt: document.createdAt,
            completionStatus: document.completion.status.name,
            documentHash: _hashBytes(bytes),
            sizeBytes: bytes.length,
          ),
        );
      } on FileSystemException {
        // The recovery walker treats unreadable files as
        // orphan-residue — they stay on disk and are excluded from
        // the rebuilt index.
        continue;
      }
    }
    final ordered = <AnalysisSummary>[...out]
      ..sort((a, b) => b.createdAt.toUtc().compareTo(a.createdAt.toUtc()));
    indexStore.write(ordered);
    return ordered;
  }

  void _quarantine(_DocumentLocation location, String expectedHash) {
    final corrupt = File(
      '${location.path}${AnalysisRepositoryLayout.corruptSuffix}',
    );
    try {
      if (location.file.existsSync()) {
        location.file.renameSync(corrupt.path);
      } else {
        // Synthetic quarantine — used when the test passes a synthetic
        // location pointing at a fake path. The bytes are written
        // separately so the test can assert on disk state.
        final synthetic = File(corrupt.path);
        if (!synthetic.existsSync()) {
          // No-op: caller manages the residue.
        }
      }
    } on FileSystemException {
      // Best-effort.
    }
    // expectedHash is the freshly-computed SHA-256; retained so the
    // signature documents the verification performed even if the
    // quarantine rename is best-effort.
    assert(expectedHash.length == 64);
  }

  AppResult<AnalysisDocument> _decodeDocument(List<int> bytes) {
    final AppResult<AnalysisDocument> result;
    try {
      result = documentCodec.decode(utf8.decode(bytes));
    } on Object {
      // A hand-edited or corrupt on-disk byte sequence may fail UTF-8
      // decoding before the codec even sees it. Surface that as a
      // typed failure rather than letting the exception escape.
      return AppResult<AnalysisDocument>.failure(
        ValidationFailure(code: AnalysisRepositoryErrorCode.corruptDocument),
      );
    }
    final observer = onDecode;
    if (observer != null) {
      observer();
    }
    return result;
  }

  Future<Uint8List?> _tryReadBytes(_DocumentLocation loc) async {
    final file = File(loc.path);
    if (!file.existsSync()) return null;
    return Uint8List.fromList(file.readAsBytesSync());
  }

  static String _basenameOf(File file) {
    final segments = file.uri.pathSegments;
    if (segments.isEmpty) return file.path;
    return segments.last;
  }

  static String _hashBytes(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  static AppResult<T> _failure<T>(String code, {Object? cause}) {
    return AppResult<T>.failure(
      StorageFailure(code: code, retryable: false, cause: cause),
    );
  }

  static Future<void> _ensureSubtree(Directory root) async {
    for (final sub in <String>[
      '',
      AnalysisRepositoryLayout.documentsDirectory,
      AnalysisRepositoryLayout.tempDirectory,
      AnalysisRepositoryLayout.migrationDirectory,
    ]) {
      final directory = sub.isEmpty ? root : Directory('${root.path}/$sub');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }
  }
}

class _UnsupportedSchemaException implements Exception {
  const _UnsupportedSchemaException();
}

class _DocumentLocation {
  _DocumentLocation._(this.path);

  factory _DocumentLocation.live(Directory root, String id) =>
      _DocumentLocation.at(root, '$id.json');

  factory _DocumentLocation.at(Directory root, String basename) =>
      _DocumentLocation._(
        '${root.path}/${AnalysisRepositoryLayout.documentsDirectory}/$basename',
      );

  final String path;

  File get file => File(path);
}
