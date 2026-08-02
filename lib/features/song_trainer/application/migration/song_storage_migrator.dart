// ignore_for_file: prefer_initializing_formals
/// One-shot, restart-safe migration use case for legacy song / setlist
/// content into the V2 file repository (E03-R08, ADR 0117, SDD §18.6).
///
/// The migrator is the boundary between the legacy `JsonDocumentStore`
/// (under `StorageKeys.songs` / `StorageKeys.setlists`, owned by the
/// `songs` / `setlists` features) and the V2 [SongRepository]. It reads
/// the legacy envelopes through the same `JsonDocumentStore` primitive
/// the legacy features already use (ADR 0117 §Döntés 1 — cross-feature
/// import is impossible because the boundary is a core storage type,
/// not a feature type), runs each record through the R06
/// [LegacySongReader] / [LegacySongAdapter] / [LegacySetlistAdapter]
/// pure data classes, and persists the resulting [SongDocument]s through
/// the R07 atomic [SongRepository.create] path with a per-record
/// read-back parity check.
///
/// Restart-safety is provided by the file-based
/// [SongMigrationVersionStore]: every successful song write appends the
/// legacy id to `completedLegacySongIds`; every corrupt-but-skipped
/// record appends to `redactedLegacySongIds`; the global `completed`
/// flag is flipped only AFTER every song is checkpointed AND the setlist
/// mapping has run (ADR 0117 §Döntés 2, §Döntés 3). A crash at any
/// step leaves the next run to resume from the checkpoint — no
/// duplication, no lost work.
///
/// Legacy ID → V2 `SongId` identity (R06) is the idempotency key:
/// restart re-tries `create` for the same id, the repository returns
/// `alreadyExists`, the migrator treats that as "already done, advance".
library;

import 'dart:async';
import 'dart:io';

import '../../../../core/foundation/app_result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/json_document_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../data/migration/legacy_migration_report.dart';
import '../../data/migration/legacy_setlist_adapter.dart';
import '../../data/migration/legacy_song_adapter.dart';
import '../../data/migration/legacy_song_reader.dart';
import '../../data/migration/song_migration_version_store.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/repositories/song_repository.dart';
import 'song_migration_state.dart';

/// Result of parsing one legacy JSON envelope.
sealed class LegacySongRead {
  const LegacySongRead();
}

class LegacySongRecords extends LegacySongRead {
  const LegacySongRecords(this.records);
  final List<Map<String, dynamic>> records;
}

class LegacySongEnvelopeEmpty extends LegacySongRead {
  const LegacySongEnvelopeEmpty();
}

class LegacySongEnvelopeMissing extends LegacySongRead {
  const LegacySongEnvelopeMissing();
}

/// Setlist envelope read result (sealed sibling of [LegacySongRead]).
sealed class LegacySetlistRead {
  const LegacySetlistRead();
}

class LegacySetlistRecords extends LegacySetlistRead {
  const LegacySetlistRecords(this.records);
  final List<Map<String, dynamic>> records;
}

class LegacySetlistEnvelopeEmpty extends LegacySetlistRead {
  const LegacySetlistEnvelopeEmpty();
}

class LegacySetlistEnvelopeMissing extends LegacySetlistRead {
  const LegacySetlistEnvelopeMissing();
}

/// One-shot, restart-safe migration use case (E03-R08).
///
/// Construct via [SongStorageMigrator.create]; the factory wires the
/// legacy `JsonDocumentStore` for `songs` and `setlists` against the
/// supplied [KeyValueStore]. The repository, songs root, and clock are
/// supplied by the caller — production wires the production
/// [SongRepository] via `song_trainer_providers.dart`.
final class SongStorageMigrator {
  SongStorageMigrator({
    required SongMigrationVersionStore versionStore,
    required LegacySongReader reader,
    required LegacySongAdapter songAdapter,
    required LegacySetlistAdapter setlistAdapter,
    required SongRepository songRepository,
    required AppLogger logger,
    required DateTime Function() clock,
    required JsonDocumentStore songsDocument,
    required JsonDocumentStore setlistsDocument,
    Future<SongRepository> Function()? readBackRepositoryFactory,
  }) : _versionStore = versionStore,
       _reader = reader,
       _songAdapter = songAdapter,
       _setlistAdapter = setlistAdapter,
       _songRepository = songRepository,
       _logger = logger,
       _clock = clock,
       _songsDocument = songsDocument,
       _setlistsDocument = setlistsDocument,
       _readBackRepositoryFactory = readBackRepositoryFactory;

  final SongMigrationVersionStore _versionStore;
  final LegacySongReader _reader;
  final LegacySongAdapter _songAdapter;
  final LegacySetlistAdapter _setlistAdapter;
  final SongRepository _songRepository;
  final AppLogger _logger;
  final DateTime Function() _clock;
  final JsonDocumentStore _songsDocument;
  final JsonDocumentStore _setlistsDocument;
  final Future<SongRepository> Function()? _readBackRepositoryFactory;

  /// Factory — opens a migrator against [songsRoot] and wires the
  /// legacy JSON envelopes through a fresh `JsonDocumentStore`
  /// (ADR 0117 §Döntés 1 — the same sanctioned primitive the `songs` /
  /// `setlists` features use; the migrator opens its OWN, read-only
  /// instance, never shares the one those features own).
  factory SongStorageMigrator.create({
    required KeyValueStore legacyStore,
    required SongRepository songRepository,
    required Directory songsRoot,
    DateTime Function()? clock,
    AppLogger? logger,
    Future<SongRepository> Function()? readBackRepositoryFactory,
  }) {
    final effectiveClock = clock ?? DateTime.now;
    final effectiveLogger = logger ?? const NoopAppLogger();
    final songsDocument = JsonDocumentStore(
      store: legacyStore,
      logger: effectiveLogger,
      key: StorageKeys.songs,
      legacyKey: LegacyStorageKeys.songs,
      name: 'migration.legacy.songs',
    );
    final setlistsDocument = JsonDocumentStore(
      store: legacyStore,
      logger: effectiveLogger,
      key: StorageKeys.setlists,
      legacyKey: LegacyStorageKeys.setlists,
      name: 'migration.legacy.setlists',
    );
    return SongStorageMigrator(
      versionStore: SongMigrationVersionStore.open(songsRoot: songsRoot),
      reader: const LegacySongReader(),
      songAdapter: const LegacySongAdapter(),
      setlistAdapter: const LegacySetlistAdapter(),
      songRepository: songRepository,
      logger: effectiveLogger,
      clock: effectiveClock,
      songsDocument: songsDocument,
      setlistsDocument: setlistsDocument,
      readBackRepositoryFactory: readBackRepositoryFactory,
    );
  }

  /// Run the migrator to completion OR until the first unrecoverable
  /// failure. Restart-safe — a subsequent call against the same
  /// `songsRoot` resumes from the persisted checkpoint, never duplicates
  /// a successful id, never loses a redacted id.
  Future<SongMigrationOutcome> run() async {
    // 1. Load the checkpoint; treat missing AND corrupt identically —
    //    both mean "start from an empty working set". A corrupt marker
    //    is logged so diagnostics surface the upgrade / downgrade event.
    final loaded = _versionStore.load();
    var checkpoint = switch (loaded) {
      SongMigrationCheckpointLoaded(:final checkpoint) => checkpoint,
      SongMigrationCheckpointMissing() => SongMigrationCheckpoint.empty(),
      SongMigrationCheckpointCorrupt() => () {
        _logger.warning(
          'songMigration.checkpoint.corrupt',
          fields: const <String, Object?>{'stateFile': 'migration/state.json'},
        );
        return SongMigrationCheckpoint.empty();
      }(),
    };

    // 2. Read the legacy envelopes. Both reads are independent — a
    //    missing / corrupt setlists envelope is fine (no setlists on
    //    this install) and must not block the song step.
    final songRead = _readLegacySongs();
    final setlistRead = _readLegacySetlists();

    // 3. Migrate every legacy song, in stable order, with read-back
    //    parity and checkpoint on success. Bail on the first unrecoverable
    //    failure — a re-run resumes from the checkpoint.
    var migratedCount = 0;
    final failures = <SongMigrationFailure>[];
    final totalRecords = switch (songRead) {
      LegacySongRecords(:final records) => records.length,
      LegacySongEnvelopeEmpty() => 0,
      LegacySongEnvelopeMissing() => 0,
    };

    if (songRead is LegacySongRecords) {
      for (final json in songRead.records) {
        final id = json['id'];
        if (id is! String || id.isEmpty) {
          // An envelope with an entry missing an id is structurally
          // corrupt — we redacted it the same way the reader rejects
          // bad shapes, and never try again.
          failures.add(
            const SongMigrationFailure(
              id: '<unknown>',
              reason: SongMigrationFailureReason.redactedCorrupt,
            ),
          );
          continue;
        }
        // Already redacted in a prior run — surface the failure on the
        // outcome so the UI / diagnostics keep reporting it, but do not
        // re-attempt the decode.
        if (checkpoint.redactedLegacySongIds.contains(id)) {
          failures.add(
            SongMigrationFailure(
              id: id,
              reason: SongMigrationFailureReason.redactedCorrupt,
            ),
          );
          continue;
        }

        // Already checkpointed in a prior run — verify the V2 side
        // still has the document. A missing read-back means the file
        // got deleted out from under the checkpoint; we re-attempt.
        var alreadyMigrated = false;
        if (checkpoint.completedLegacySongIds.contains(id)) {
          final stillThere = await _verifyReadBack(id);
          if (stillThere) {
            alreadyMigrated = true;
          }
        }

        if (!alreadyMigrated) {
          final outcome = await _migrateOneSong(json: json, id: id);
          switch (outcome) {
            case _Migrated():
              migratedCount++;
              checkpoint = _withCompleted(checkpoint, id);
              await _versionStore.save(checkpoint);
            case _Redacted(:final reason):
              failures.add(SongMigrationFailure(id: id, reason: reason));
              checkpoint = _withRedacted(checkpoint, id);
              await _versionStore.save(checkpoint);
            case _RetryableFailure(:final reason):
              // Transient — stop the run, leave the failure visible on the
              // outcome. The next run re-tries from the checkpoint.
              failures.add(SongMigrationFailure(id: id, reason: reason));
              return SongMigrationOutcome(
                status: SongMigrationStatus.needsResume,
                totalSongs: totalRecords,
                migratedSongs: migratedCount,
                failedSongs: List<SongMigrationFailure>.unmodifiable(failures),
                setlistAdaptation: null,
                completedAt: null,
              );
          }
        }
      }
    }

    // 4. Setlist mapping runs only after every song has a
    //    deterministic outcome (succeeded or redacted). Any transient
    //    failure (write refused, read-back miss) means the run returns
    //    needsResume and the next run re-attempts from the checkpoint.
    //    A redacted record is permanent: it shows up on the outcome
    //    every subsequent run, and the completion flag stays false
    //    (a partially-redacted storage is not "done").
    if (failures.isNotEmpty) {
      return SongMigrationOutcome(
        status: SongMigrationStatus.needsResume,
        totalSongs: totalRecords,
        migratedSongs: migratedCount,
        failedSongs: List<SongMigrationFailure>.unmodifiable(failures),
        setlistAdaptation: null,
        completedAt: null,
      );
    }

    final LegacySetlistAdaptation setlistAdaptation;
    if (setlistRead is LegacySetlistRecords) {
      setlistAdaptation = await _migrateSetlists(setlistRead.records);
    } else {
      // No setlists — empty adaptation so the UI has a uniform shape.
      setlistAdaptation = const LegacySetlistAdaptation(
        documents: <SongDocument>[],
        report: LegacyMigrationReport.empty,
        unresolvedIds: <String>[],
      );
    }

    // 5. Flip the global completion flag as the LAST step. A crash
    //    between (4) and (5) leaves the checkpoint uncompleted; the
    //    next run re-runs setlists (idempotent — the adapter reads only
    //    checkpointed songs) and then re-flips the flag.
    final completedAt = _clock().toUtc();
    final finalCheckpoint = SongMigrationCheckpoint(
      completedLegacySongIds: checkpoint.completedLegacySongIds,
      redactedLegacySongIds: checkpoint.redactedLegacySongIds,
      completed: true,
      completedAt: completedAt,
    );
    await _versionStore.save(finalCheckpoint);

    return SongMigrationOutcome(
      status: SongMigrationStatus.completed,
      totalSongs: totalRecords,
      migratedSongs: migratedCount,
      failedSongs: const <SongMigrationFailure>[],
      setlistAdaptation: setlistAdaptation,
      completedAt: completedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  LegacySongRead _readLegacySongs() {
    final body = _songsDocument.readBody();
    if (body == null) return const LegacySongEnvelopeMissing();
    if (body is! List) {
      _logger.warning(
        'songMigration.legacy.songs.bodyNotList',
        fields: const <String, Object?>{'document': 'migration.legacy.songs'},
      );
      return const LegacySongEnvelopeMissing();
    }
    if (body.isEmpty) return const LegacySongEnvelopeEmpty();
    final records = <Map<String, dynamic>>[];
    for (final entry in body) {
      if (entry is Map<String, dynamic>) {
        records.add(entry);
      }
    }
    if (records.isEmpty) return const LegacySongEnvelopeEmpty();
    return LegacySongRecords(records);
  }

  LegacySetlistRead _readLegacySetlists() {
    final body = _setlistsDocument.readBody();
    if (body == null) return const LegacySetlistEnvelopeMissing();
    if (body is! List) {
      return const LegacySetlistEnvelopeMissing();
    }
    final records = <Map<String, dynamic>>[];
    for (final entry in body) {
      if (entry is Map<String, dynamic>) {
        records.add(entry);
      }
    }
    if (records.isEmpty) return const LegacySetlistEnvelopeEmpty();
    return LegacySetlistRecords(records);
  }

  Future<bool> _verifyReadBack(String legacyId) async {
    final result = await _songRepository.get(SongId(legacyId));
    return switch (result) {
      Success(:final value) => value != null,
      Failure() => false,
    };
  }

  Future<_SongMigrationStep> _migrateOneSong({
    required Map<String, dynamic> json,
    required String id,
  }) async {
    final LegacySongRecord record;
    try {
      record = _reader.readSong(json);
    } on LegacySongReaderException catch (e) {
      // Bad shape → permanent redactedCorrupt. The legacy entry is
      // preserved untouched; the V2 repository never sees it.
      _logger.warning(
        'songMigration.song.redactedCorrupt',
        fields: <String, Object?>{
          'id': id,
          'code': e.code,
          if (e.field != null) 'field': e.field!,
        },
      );
      return const _Redacted(
        reason: SongMigrationFailureReason.redactedCorrupt,
      );
    }

    final adaptation = _songAdapter.adapt(record, importedAt: _clock().toUtc());
    final document = adaptation.document;

    final createResult = await _songRepository.create(document);
    if (createResult.isFailure) {
      final failure = createResult.failureOrNull!;
      // Idempotency: the V2 repository refused the create because a
      // document with this id already exists. Verify it matches what we
      // just adapted; if yes, treat as already-migrated, advance.
      if (failure.code == SongRepositoryErrorCode.alreadyExists) {
        final existing = await _readBackDocument(document.id);
        if (existing != null && _hasStableParity(existing, document)) {
          return const _Migrated();
        }
      }
      _logger.warning(
        'songMigration.song.repositoryRejected',
        fields: <String, Object?>{'id': id, 'code': failure.code},
      );
      return const _RetryableFailure(
        reason: SongMigrationFailureReason.repositoryRejected,
      );
    }

    // Read-back parity: the success result is necessary but not
    // sufficient. A platform that reports "write OK" but never persists
    // would silently lose data — re-read through a fresh repository
    // call so a cache cannot defeat this check.
    final readBack = await _readBackDocument(document.id);
    if (readBack == null || !_hasStableParity(readBack, document)) {
      _logger.error(
        'songMigration.song.readBackMiss',
        error: 'readBackMiss',
        stackTrace: StackTrace.empty,
        fields: <String, Object?>{'id': id},
      );
      return const _RetryableFailure(
        reason: SongMigrationFailureReason.readBackMiss,
      );
    }
    return const _Migrated();
  }

  Future<SongDocument?> _readBackDocument(SongId id) async {
    final factory = _readBackRepositoryFactory;
    final repository = factory == null ? _songRepository : await factory();
    final result = await repository.get(id);
    return switch (result) {
      Success(:final value) => value,
      Failure() => null,
    };
  }

  bool _hasStableParity(SongDocument actual, SongDocument expected) =>
      actual == expected;

  Future<LegacySetlistAdaptation> _migrateSetlists(
    List<Map<String, dynamic>> records,
  ) async {
    final issues = <LegacyMigrationIssue>[];
    final unresolved = <String>[];
    final out = <SongDocument>[];

    for (final json in records) {
      try {
        final setlist = _reader.readSetlist(json);
        // Build the songbook for THIS setlist by re-reading each V2
        // document from the repository. The checkpoint guarantees every
        // song id is either present or redacted — `get` returns
        // `Success(null)` for the redacted ids, which the adapter
        // records as `unresolvedIds`.
        final songbook = <String, SongDocument>{};
        for (final songId in setlist.songIds) {
          final result = await _songRepository.get(SongId(songId));
          final doc = switch (result) {
            Success(:final value) => value,
            Failure() => null,
          };
          if (doc != null) songbook[songId] = doc;
        }
        final adaptation = _setlistAdapter.adapt(setlist, songbook);
        issues.addAll(adaptation.report.issues);
        unresolved.addAll(adaptation.unresolvedIds);
        out.addAll(adaptation.documents);
      } on LegacySongReaderException catch (e) {
        issues.add(
          LegacyMigrationIssue(
            code: SongMigrationFailureReason.redactedCorrupt,
            message:
                'Setlist ${json['id']} could not be decoded (${e.code}); '
                'setlist step recorded the corruption and skipped the '
                'record.',
          ),
        );
      }
    }
    return LegacySetlistAdaptation(
      documents: List<SongDocument>.unmodifiable(out),
      report: LegacyMigrationReport.from(issues),
      unresolvedIds: List<String>.unmodifiable(unresolved),
    );
  }

  SongMigrationCheckpoint _withCompleted(
    SongMigrationCheckpoint previous,
    String id,
  ) {
    final next = Set<String>.from(previous.completedLegacySongIds)..add(id);
    return SongMigrationCheckpoint(
      completedLegacySongIds: Set<String>.unmodifiable(next),
      redactedLegacySongIds: previous.redactedLegacySongIds,
      completed: false,
      completedAt: previous.completedAt,
    );
  }

  SongMigrationCheckpoint _withRedacted(
    SongMigrationCheckpoint previous,
    String id,
  ) {
    final next = Set<String>.from(previous.redactedLegacySongIds)..add(id);
    return SongMigrationCheckpoint(
      completedLegacySongIds: previous.completedLegacySongIds,
      redactedLegacySongIds: Set<String>.unmodifiable(next),
      completed: false,
      completedAt: previous.completedAt,
    );
  }
}

/// Tagged union of the per-song migration outcomes the loop in [run]
/// branches on.
sealed class _SongMigrationStep {
  const _SongMigrationStep();
}

class _Migrated extends _SongMigrationStep {
  const _Migrated();
}

class _Redacted extends _SongMigrationStep {
  const _Redacted({required this.reason});
  final String reason;
}

class _RetryableFailure extends _SongMigrationStep {
  const _RetryableFailure({required this.reason});
  final String reason;
}
