// ignore_for_file: prefer_initializing_formals
/// Filesystem-backed [SongRepository] implementing ADR 0090 §Döntés 1
/// + §3, SDD §18.2 / §18.3 / §18.6 / §18.7.
///
/// Layout under the configured `songs` root (the constructor parameter):
///
/// ```text
/// <root>/
///   index.json
///   documents/<song-id>.json
///   trash/<song-id>.json
///   temp/<song-id>.tmp-*
///   assets/         (reserved for the asset store, populated by
///     `file_song_asset_repository.dart`)
///   originals/      (reserved for the asset store)
/// ```
///
/// Save order (SDD §18.3 / §18.4, ADR 0090 §Döntés 3):
///
///   1. validate the document via the live validator (any fatal issue
///      ⇒ `AppResult.failure(notPersistable)`);
///   2. compute the canonical SHA-256 of the encoded bytes;
///   3. stage the document to `temp/<id>.tmp-<pid>-<n>` via
///      [AtomicFileWriter]; on failure the previous good document
///      survives;
///   4. stage the index to `index.tmp-<pid>-<n>`;
///   5. the index is renamed over `index.json` via the same atomic
///      writer;
///   6. only then does the call return `Success`.
///
/// On a crashed write — process killed between (3) and (4), between (4)
/// and (5) — the recovery scan (separate file) reads the previous good
/// document directly off disk and rebuilds the index from the surviving
/// `documents/` directory. Crash residue inside `temp/` is deleted on
/// the next startup scan (ADR 0090 §Döntés 7).
///
/// The repository is **framework-independent**: no Flutter, Riverpod,
/// SharedPreferences, path-provider or storage plugin import. The
/// production provider (in `application/song_trainer_providers.dart`) is
/// responsible for resolving the platform directory and passing it via
/// the `directory:` argument.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_source.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_validator.dart';
import 'atomic_file_writer.dart';
import 'song_document_codec.dart';
import 'song_index_codec.dart';

/// Filesystem layout constants for the song repository. Exposed so the
/// asset store, the recovery scanner and the application providers can
/// share a single source of truth for subdirectory names.
abstract final class SongRepositoryLayout {
  /// `index.json` — the summary sidecar (ADR 0090 §Döntés 4).
  static const String indexFileName = 'index.json';

  /// Subdirectory holding live documents. Filename matches the
  /// filesystem-safe [SongId] projection.
  static const String documentsDirectory = 'documents';

  /// Subdirectory holding trashed documents.
  static const String trashDirectory = 'trash';

  /// Subdirectory holding staged atomic-write temp files. Crash residue
  /// is deleted on the next recovery scan.
  static const String tempDirectory = 'temp';

  /// Subdirectory reserved for the asset store (managed by a sibling
  /// module; the song repository never touches it).
  static const String assetsDirectory = 'assets';

  /// Subdirectory reserved for the asset store's preserved originals.
  static const String originalsDirectory = 'originals';
}

/// Filesystem-backed implementation of [SongRepository].
final class FileSongRepository implements SongRepository {
  /// Internal constructor; use [openAtDirectory] which prepares the
  /// subtree and injects the production codecs.
  FileSongRepository._({
    required this.directory,
    required DateTime Function() clock,
    required this.documentCodec,
    required this.indexCodec,
    required this.writer,
    required this.validator,
    required this.capabilityResolver,
  }) : _clock = clock;

  /// Root of the song-tree on disk.
  final Directory directory;

  /// Codec for the document files; shared with the rest of the feature.
  final SongDocumentCodec documentCodec;

  /// Codec for the summary sidecar `index.json`.
  final SongIndexCodec indexCodec;

  /// Atomic writer for the staged temp + rename sequence.
  final AtomicFileWriter writer;

  /// Validator used by [create] / [update] / [moveToTrash] to refuse
  /// fatal-severity documents before they touch disk (ADR 0090 §3
  /// step 1, ADR 0114 §Döntés 2).
  final SongValidator validator;

  /// Capability resolver used to populate the [SongCapabilitySummary]
  /// in the index entry on every successful write.
  final SongCapabilityResolver capabilityResolver;

  /// Lazily-built staging directory inside the songs root's `temp/`
  /// subdirectory. The atomic writer places its staged temp files here
  /// so the recovery scanner's `temp/` walk sees real crash residue
  /// (ADR 0090 §Döntés 1).
  Directory? _stagingDirectoryCache;

  final DateTime Function() _clock;

  Directory _stagingDirectory() {
    final cached = _stagingDirectoryCache;
    if (cached != null) return cached;
    final built = Directory(
      '${directory.path}/${SongRepositoryLayout.tempDirectory}',
    );
    _stagingDirectoryCache = built;
    return built;
  }

  /// Open a repository against an existing [directory] (which may be
  /// fresh or pre-existing — the constructor creates only the per-feature
  /// subdirectories it owns). The default [clock] is `DateTime.now`;
  /// tests must inject a fixed clock for determinism.
  static Future<FileSongRepository> openAtDirectory({
    required Directory directory,
    DateTime Function()? clock,
  }) async {
    await _ensureSubtree(directory);
    return FileSongRepository._(
      directory: directory,
      clock: clock ?? DateTime.now,
      documentCodec: const SongDocumentCodec(),
      indexCodec: const SongIndexCodec(),
      writer: const AtomicFileWriter(),
      validator: const SongValidator(),
      capabilityResolver: const SongCapabilityResolver(),
    );
  }

  // ---------------------------------------------------------------------------
  // SongRepository
  // ---------------------------------------------------------------------------

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async {
    try {
      final summaries = await _readIndex();
      final filtered =
          summaries.where((entry) {
            if (!query.includeTrashed && entry.trashed) return false;
            if (!query.includeArchived && entry.archived) return false;
            if (query.sourceTypeFilter != null &&
                entry.sourceType != query.sourceTypeFilter) {
              return false;
            }
            if (query.titleContains != null &&
                query.titleContains!.isNotEmpty &&
                !entry.title.toLowerCase().contains(
                  query.titleContains!.toLowerCase(),
                )) {
              return false;
            }
            if (query.tagFilter != null && query.tagFilter!.isNotEmpty) {
              final wanted = query.tagFilter!.toSet();
              if (!entry.tags.any(wanted.contains)) return false;
            }
            return true;
          }).toList()..sort(
            (a, b) => b.updatedAt.toUtc().compareTo(a.updatedAt.toUtc()),
          );
      return AppResult<List<SongSummary>>.success(
        List<SongSummary>.unmodifiable(filtered),
      );
    } on SongIndexCodecException {
      return songRepositoryFailure<List<SongSummary>>(
        SongRepositoryErrorCode.corruptIndex,
      );
    } on FileSystemException catch (e) {
      return songRepositoryFailure<List<SongSummary>>(
        SongRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final trashed = _DocumentLocation.trash(directory, id);
      final bytes = await _tryReadBytes(live) ?? await _tryReadBytes(trashed);
      if (bytes == null) {
        return AppResult<SongDocument?>.success(null);
      }
      try {
        final doc = documentCodec.decode(bytes);
        return AppResult<SongDocument?>.success(doc);
      } on SongDocumentCodecException catch (e) {
        return songRepositoryFailure<SongDocument?>(
          SongRepositoryErrorCode.corruptDocument,
          cause: e,
        );
      }
    } on FileSystemException catch (e) {
      return songRepositoryFailure<SongDocument?>(
        SongRepositoryErrorCode.io,
        cause: e,
      );
    }
  }

  @override
  Future<AppResult<void>> create(SongDocument document) async {
    // Step 1 (ADR 0090 §3 / ADR 0114 §Döntés 2): refuse any fatal
    // validation issue BEFORE touching the filesystem.
    final capability = _resolveCapability(document);
    if (!capability.canPersist) {
      return songRepositoryFailure<void>(
        SongRepositoryErrorCode.notPersistable,
      );
    }
    try {
      final live = _DocumentLocation.live(directory, document.id);
      if (live.file.existsSync()) {
        return songRepositoryFailure<void>(
          SongRepositoryErrorCode.alreadyExists,
        );
      }
      final encoded = Uint8List.fromList(documentCodec.encode(document));
      await _writeAtomic(live, encoded);
      await _commitIndex(
        _buildSummary(document, trashed: false, capability: capability),
        op: _IndexOp.replace,
      );
      return AppResult<void>.success(null);
    } on SongDocumentCodecException catch (e) {
      return songRepositoryFailure<void>(
        SongRepositoryErrorCode.corruptDocument,
        cause: e,
      );
    } on FileSystemException catch (e) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) async {
    try {
      final live = _DocumentLocation.live(directory, document.id);
      final existingBytes = await _tryReadBytes(live);
      if (existingBytes == null) {
        return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
      }
      final existingDoc = documentCodec.decode(existingBytes);
      if (existingDoc.revision != expectedRevision) {
        return songRepositoryFailure<void>(
          SongRepositoryErrorCode.staleRevision,
        );
      }
      final bumped = _bumpRevision(existingDoc, document);
      // Step 1 (ADR 0090 §3 / ADR 0114 §Döntés 2): refuse any fatal
      // validation issue BEFORE bumping the persisted revision.
      final capability = _resolveCapability(bumped);
      if (!capability.canPersist) {
        return songRepositoryFailure<void>(
          SongRepositoryErrorCode.notPersistable,
        );
      }
      final encoded = Uint8List.fromList(documentCodec.encode(bumped));
      await _writeAtomic(live, encoded);
      await _commitIndex(
        _buildSummary(bumped, trashed: false, capability: capability),
        op: _IndexOp.replace,
      );
      return AppResult<void>.success(null);
    } on SongDocumentCodecException catch (e) {
      return songRepositoryFailure<void>(
        SongRepositoryErrorCode.corruptDocument,
        cause: e,
      );
    } on FileSystemException catch (e) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> moveToTrash(SongId id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final trashed = _DocumentLocation.trash(directory, id);
      if (!live.file.existsSync()) {
        if (trashed.file.existsSync()) {
          // Already trashed — just ensure the index reflects the
          // trashed location.
          final summary = await _summaryFromDisk(trashed, trashed: true);
          await _commitIndex(summary, op: _IndexOp.replace);
          return AppResult<void>.success(null);
        }
        return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
      }
      // Re-validate before the trashed copy lands so a corrupt or
      // schema-broken document is not silently preserved under a new
      // path (the recovery scanner reports the original location; the
      // trash copy would otherwise leak validation failures).
      final bytes = live.file.readAsBytesSync();
      try {
        await _writeAtomic(trashed, bytes);
      } on SongDocumentCodecException catch (e) {
        return songRepositoryFailure<void>(
          SongRepositoryErrorCode.corruptDocument,
          cause: e,
        );
      }
      await _tryDelete(live);
      await _commitIndex(
        await _summaryFromDisk(trashed, trashed: true),
        op: _IndexOp.replace,
      );
      return AppResult<void>.success(null);
    } on FileSystemException catch (e) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> restore(SongId id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final trashed = _DocumentLocation.trash(directory, id);
      if (trashed.file.existsSync()) {
        final bytes = trashed.file.readAsBytesSync();
        try {
          await _writeAtomic(live, bytes);
        } on SongDocumentCodecException catch (e) {
          return songRepositoryFailure<void>(
            SongRepositoryErrorCode.corruptDocument,
            cause: e,
          );
        }
        await _tryDelete(trashed);
        await _commitIndex(
          await _summaryFromDisk(live, trashed: false),
          op: _IndexOp.replace,
        );
        return AppResult<void>.success(null);
      }
      if (live.file.existsSync()) {
        return AppResult<void>.success(null);
      }
      return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
    } on FileSystemException catch (e) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io, cause: e);
    }
  }

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) async {
    try {
      final live = _DocumentLocation.live(directory, id);
      final trashed = _DocumentLocation.trash(directory, id);
      final liveExists = live.file.existsSync();
      final trashedExists = trashed.file.existsSync();
      if (!liveExists && !trashedExists) {
        return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
      }
      if (liveExists) await _tryDelete(live);
      if (trashedExists) await _tryDelete(trashed);
      await _commitIndex(_placeholderSummary(id), op: _IndexOp.drop);
      return AppResult<void>.success(null);
    } on FileSystemException catch (e) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io, cause: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Index helpers
  // ---------------------------------------------------------------------------

  Future<List<SongSummary>> _readIndex() async {
    final indexFile = File(
      '${directory.path}/${SongRepositoryLayout.indexFileName}',
    );
    if (!indexFile.existsSync()) {
      return const <SongSummary>[];
    }
    return indexCodec.decode(indexFile.readAsBytesSync());
  }

  Future<void> _commitIndex(
    SongSummary summary, {
    _IndexOp op = _IndexOp.replace,
  }) async {
    final existing = await _readIndex();
    final next = <SongSummary>[
      for (final entry in existing)
        if (entry.documentId != summary.documentId) entry,
      if (op == _IndexOp.replace) summary,
    ]..sort((a, b) => b.updatedAt.toUtc().compareTo(a.updatedAt.toUtc()));
    final encoded = Uint8List.fromList(indexCodec.encode(next));
    final indexLoc = _DocumentLocation.index(directory);
    await _writeAtomic(indexLoc, encoded);
  }

  Future<void> _writeAtomic(_DocumentLocation loc, Uint8List bytes) async {
    final file = File(loc.path);
    await file.parent.create(recursive: true);
    final outcome = writer.write(
      target: file,
      bytes: bytes,
      stagingDirectory: _stagingDirectory(),
      verifier: (back) {
        // Round-trip the bytes through the appropriate decoder so a
        // future regression to a partial write is caught before the
        // rename lands.
        switch (loc.kind) {
          case _LocationKind.liveDocument:
          case _LocationKind.trashDocument:
            documentCodec.decode(back);
            break;
          case _LocationKind.indexFile:
            indexCodec.decode(back);
            break;
        }
        return true;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException('AtomicFileWriter refused to commit.');
    }
  }

  Future<Uint8List?> _tryReadBytes(_DocumentLocation loc) async {
    final file = File(loc.path);
    if (!file.existsSync()) return null;
    return Uint8List.fromList(file.readAsBytesSync());
  }

  Future<void> _tryDelete(_DocumentLocation loc) async {
    final file = File(loc.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  SongSummary _buildSummary(
    SongDocument document, {
    required bool trashed,
    SongCapabilityReport? capability,
  }) {
    final documentUpdatedAt = document.updatedAt.toUtc();
    final metadata = document.metadata;
    // `lastPracticedAt` is denormalised from the document's own
    // updatedAt; the Practice Engine updates this once a real session
    // runs (out of scope for R07 — the field stays `updatedAt` for
    // now and migrates in a follow-up round).
    final summary = capability == null
        ? null
        : SongCapabilitySummary(
            canPersist: capability.canPersist,
            canTrain: capability.canTrain,
            canExport: capability.canExport,
            chordScoring: capability.chord.scoring,
            pitchScoring: capability.pitch.scoring,
            lastValidatedAt: _clock().toUtc(),
          );
    return SongSummary(
      documentId: document.id,
      title: metadata.title,
      artist: metadata.artist,
      tags: List<String>.unmodifiable(metadata.tags),
      updatedAt: documentUpdatedAt,
      lastPracticedAt: documentUpdatedAt,
      capability: summary,
      sourceType: document.source.type,
      favorite: false,
      archived: false,
      trashed: trashed,
      revision: document.revision,
      documentHash: _documentHash(documentCodec.encode(document)),
    );
  }

  SongCapabilityReport _resolveCapability(SongDocument document) {
    final report = validator.validate(document);
    return capabilityResolver.resolve(
      report: report,
      profile: SongCapabilityProfile.persist,
    );
  }

  Future<SongSummary> _summaryFromDisk(
    _DocumentLocation loc, {
    required bool trashed,
  }) async {
    final file = File(loc.path);
    final document = documentCodec.decode(file.readAsBytesSync());
    return _buildSummary(document, trashed: trashed);
  }

  /// Returns a summary whose `documentId` IS the target id but whose
  /// other fields are arbitrary — the index-drop path only uses
  /// `documentId` to identify the row to remove. Used by
  /// [permanentlyDelete].
  SongSummary _placeholderSummary(SongId id) {
    final updatedAtUtc = _clock().toUtc();
    return SongSummary(
      documentId: id,
      title: '',
      artist: null,
      tags: const <String>[],
      updatedAt: updatedAtUtc,
      lastPracticedAt: updatedAtUtc,
      capability: null,
      sourceType: SongSourceType.createdInApp,
      favorite: false,
      archived: false,
      trashed: false,
      revision: 0,
      documentHash: '0' * 64,
    );
  }

  String _documentHash(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  static SongDocument _bumpRevision(
    SongDocument existing,
    SongDocument incoming,
  ) {
    final expectedRevision = existing.revision;
    return SongDocument(
      schemaVersion: incoming.schemaVersion,
      id: incoming.id,
      revision: expectedRevision + 1,
      metadata: incoming.metadata,
      source: incoming.source,
      createdAt: incoming.createdAt,
      updatedAt: incoming.updatedAt,
      assets: incoming.assets,
      markers: incoming.markers,
      tracks: incoming.tracks,
      sections: incoming.sections,
      measures: incoming.measures,
      tempoMap: incoming.tempoMap,
      meterMap: incoming.meterMap,
      keyMap: incoming.keyMap,
    );
  }

  static Future<void> _ensureSubtree(Directory root) async {
    for (final sub in <String>[
      '',
      SongRepositoryLayout.documentsDirectory,
      SongRepositoryLayout.trashDirectory,
      SongRepositoryLayout.tempDirectory,
      SongRepositoryLayout.assetsDirectory,
      SongRepositoryLayout.originalsDirectory,
    ]) {
      final directory = sub.isEmpty ? root : Directory('${root.path}/$sub');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }
  }
}

enum _LocationKind { liveDocument, trashDocument, indexFile }

enum _IndexOp { replace, drop }

/// Internal location class so the public repository surface stays small.
class _DocumentLocation {
  _DocumentLocation._(this.path, this.kind);

  factory _DocumentLocation.live(Directory root, SongId id) =>
      _DocumentLocation._(
        '${root.path}/${SongRepositoryLayout.documentsDirectory}/'
        '${id.safeFilename()}.json',
        _LocationKind.liveDocument,
      );

  factory _DocumentLocation.trash(Directory root, SongId id) =>
      _DocumentLocation._(
        '${root.path}/${SongRepositoryLayout.trashDirectory}/'
        '${id.safeFilename()}.json',
        _LocationKind.trashDocument,
      );

  factory _DocumentLocation.index(Directory root) => _DocumentLocation._(
    '${root.path}/${SongRepositoryLayout.indexFileName}',
    _LocationKind.indexFile,
  );

  final String path;
  final _LocationKind kind;

  File get file => File(path);
}
