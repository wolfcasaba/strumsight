/// E03-R08 — SongStorageMigrator contract matrix
/// (ADR 0117 §Döntés 1 + §Döntés 2 + §Döntés 3, SDD §18.6).
library;

import 'dart:convert';
import 'dart:io';
import 'package:strumsight/core/foundation/app_result.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/song_trainer/application/migration/song_migration_state.dart';
import 'package:strumsight/features/song_trainer/application/migration/song_storage_migrator.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_migration_report.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  _InMemoryKeyValueStore();

  final Map<String, Object> _values = <String, Object>{};
  int failNextWriteCount = 0;

  @override
  String? readString(String key) =>
      _values[key] is String ? _values[key] as String : null;

  @override
  int? readInt(String key) => _values[key] is int ? _values[key] as int : null;

  @override
  double? readDouble(String key) =>
      _values[key] is double ? _values[key] as double : null;

  @override
  bool? readBool(String key) =>
      _values[key] is bool ? _values[key] as bool : null;

  @override
  List<String>? readStringList(String key) =>
      _values[key] is List<String> ? _values[key] as List<String> : null;

  @override
  Future<void> writeString(String key, String value) async {
    if (failNextWriteCount > 0) {
      failNextWriteCount--;
      throw const StorageException('storage.write');
    }
    _values[key] = value;
  }

  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;

  @override
  Future<void> writeDouble(String key, double value) async =>
      _values[key] = value;

  @override
  Future<void> writeBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> writeStringList(String key, List<String> value) async =>
      _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  bool contains(String key) => _values.containsKey(key);

  /// Bypass [failNextWriteCount] for test seeds — see [_seedLegacySongs].
  void unsafeWriteString(String key, String value) {
    _values[key] = value;
  }
}

const String _songSeed1Id = 'song_alpha';
const String _songSeed2Id = 'song_bravo';
const String _songSeed3Id = 'song_charlie';

Map<String, dynamic> _songJson({
  required String id,
  String name = 'Fixture',
  int bpm = 96,
  String pattern = 'd-du-ud-',
  List<String> chords = const ['C', 'G'],
  int beatsPerBar = 4,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'chords': chords,
    'pat': pattern,
    'bpm': bpm,
    'bpb': beatsPerBar,
  };
}

void _seedLegacySongs(
  _InMemoryKeyValueStore store,
  List<Map<String, dynamic>> songs,
) {
  final encoded = jsonEncode(<String, dynamic>{
    'schemaVersion': 1,
    'items': songs,
  });
  // Bypass [failNextWriteCount] — the seed runs before the migrator's
  // first write, so a failure gate here would silently drop the data.
  store.unsafeWriteString('ss.songs.songs', encoded);
}

void _seedLegacySetlists(
  _InMemoryKeyValueStore store,
  List<Map<String, dynamic>> setlists,
) {
  final encoded = jsonEncode(<String, dynamic>{
    'schemaVersion': 1,
    'items': setlists,
  });
  store.unsafeWriteString('ss.songs.setlists', encoded);
}

Map<String, dynamic> _setlistJson({
  required String id,
  String name = 'Setlist',
  List<String> songIds = const [],
}) {
  return <String, dynamic>{'id': id, 'name': name, 'songs': songIds};
}

Future<SongStorageMigrator> _buildMigrator({
  required _InMemoryKeyValueStore store,
  required Directory songsRoot,
  DateTime Function()? clock,
}) async {
  final repo = await FileSongRepository.openAtDirectory(
    directory: songsRoot,
    clock: clock ?? () => DateTime.utc(2026, 8, 2, 13),
  );
  return SongStorageMigrator.create(
    legacyStore: store,
    songRepository: repo,
    songsRoot: songsRoot,
    clock: clock ?? () => DateTime.utc(2026, 8, 2, 13),
  );
}

void main() {
  group('SongStorageMigrator — empty storage baseline', () {
    late Directory sandbox;
    late _InMemoryKeyValueStore store;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('song_migrator_empty_');
      store = _InMemoryKeyValueStore();
    });
    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('completes with 0 records when the legacy store is empty', () async {
      final migrator = await _buildMigrator(
        store: store,
        songsRoot: Directory('${sandbox.path}/songs')..createSync(),
      );

      final outcome = await migrator.run();
      expect(outcome.status, SongMigrationStatus.completed);
      expect(outcome.totalSongs, 0);
      expect(outcome.migratedSongs, 0);
      expect(outcome.failedSongs, isEmpty);
      expect(outcome.completedAt, isNotNull);
      expect(outcome.setlistAdaptation, isNotNull);
      expect(outcome.setlistAdaptation!.documents, isEmpty);
      expect(outcome.setlistAdaptation!.unresolvedIds, isEmpty);
    });
  });

  group('SongStorageMigrator — single record happy path', () {
    late Directory sandbox;
    late _InMemoryKeyValueStore store;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('song_migrator_one_');
      store = _InMemoryKeyValueStore();
    });
    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test(
      'persists one song, then resumes with no-op and stays completed',
      () async {
        _seedLegacySongs(store, [_songJson(id: _songSeed1Id)]);
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();

        final migrator = await _buildMigrator(
          store: store,
          songsRoot: songsRoot,
        );

        final first = await migrator.run();
        expect(first.status, SongMigrationStatus.completed);
        expect(first.migratedSongs, 1);
        expect(first.totalSongs, 1);
        expect(first.failedSongs, isEmpty);

        final migratorAgain = await _buildMigrator(
          store: store,
          songsRoot: songsRoot,
        );
        final second = await migratorAgain.run();
        expect(second.status, SongMigrationStatus.completed);
        // Second run is a no-op for migration (the song is already
        // checkpointed) — the V2 repository still owns exactly one copy.
        expect(second.migratedSongs, 0);
        expect(second.totalSongs, 1);
        expect(second.failedSongs, isEmpty);

        final repo = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final list = await repo.list(
          const SongQuery(includeTrashed: true, includeArchived: true),
        );
        expect(list.isSuccess, isTrue);
        expect(list.valueOrNull!.map((s) => s.documentId.value), [
          _songSeed1Id,
        ]);
      },
    );
  });

  group('SongStorageMigrator — restart matrix', () {
    late Directory sandbox;
    late _InMemoryKeyValueStore store;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('song_migrator_restart_');
      store = _InMemoryKeyValueStore();
    });
    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test(
      'mid-run write failure leaves checkpoint for #1, restart resumes',
      () async {
        _seedLegacySongs(store, [
          _songJson(id: _songSeed1Id, name: 'Alpha'),
          _songJson(id: _songSeed2Id, name: 'Bravo'),
          _songJson(id: _songSeed3Id, name: 'Charlie'),
        ]);
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();

        // The repository fails its 2nd `create` call with an IO error.
        // Song #1 lands, song #2 surfaces a transient failure, song #3
        // is never reached in the first run.
        final failingRepo = _FailNthCreateSongRepository(
          await FileSongRepository.openAtDirectory(
            directory: songsRoot,
            clock: () => DateTime.utc(2026, 8, 2, 13),
          ),
          failAfterCreates: 1,
        );
        final failingRun = SongStorageMigrator.create(
          legacyStore: store,
          songRepository: failingRepo,
          songsRoot: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );
        final firstOutcome = await failingRun.run();
        expect(firstOutcome.status, SongMigrationStatus.needsResume);
        expect(firstOutcome.migratedSongs, 1);
        expect(firstOutcome.totalSongs, 3);
        expect(firstOutcome.completedAt, isNull);
        expect(firstOutcome.failedSongs, isNotEmpty);

        // Restart against a clean repository — checkpoint for #1 stays,
        // #2 + #3 are processed in this run.
        final cleanRepo = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final restart = SongStorageMigrator.create(
          legacyStore: store,
          songRepository: cleanRepo,
          songsRoot: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final secondOutcome = await restart.run();
        expect(secondOutcome.status, SongMigrationStatus.completed);
        // Restart: alpha is already checkpointed; bravo + charlie are
        // the two NEW migrations this run.
        expect(secondOutcome.migratedSongs, 2);
        expect(secondOutcome.totalSongs, 3);
        expect(secondOutcome.failedSongs, isEmpty);

        final list = await cleanRepo.list(
          const SongQuery(includeTrashed: true, includeArchived: true),
        );
        expect(
          list.valueOrNull!.map((s) => s.documentId.value).toList()..sort(),
          [_songSeed1Id, _songSeed2Id, _songSeed3Id],
        );
      },
    );

    test(
      'read-back parity failure marks the song failed and resumes',
      () async {
        _seedLegacySongs(store, [
          _songJson(id: _songSeed1Id, name: 'Alpha'),
          _songJson(id: _songSeed2Id, name: 'Bravo'),
        ]);
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();

        final failingRepo = _ParityFailSongRepository(
          await FileSongRepository.openAtDirectory(
            directory: songsRoot,
            clock: () => DateTime.utc(2026, 8, 2, 13),
          ),
          failCreateIds: <SongId>{SongId(_songSeed2Id)},
        );

        final migrator = SongStorageMigrator.create(
          legacyStore: store,
          songRepository: failingRepo,
          songsRoot: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );

        final firstOutcome = await migrator.run();
        expect(firstOutcome.status, SongMigrationStatus.needsResume);
        expect(firstOutcome.migratedSongs, 1);
        expect(firstOutcome.failedSongs, isNotEmpty);
        expect(
          firstOutcome.failedSongs.any((f) => f.id == _songSeed2Id),
          isTrue,
        );

        final cleanRepo = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final restart = SongStorageMigrator.create(
          legacyStore: store,
          songRepository: cleanRepo,
          songsRoot: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final secondOutcome = await restart.run();
        expect(secondOutcome.status, SongMigrationStatus.completed);
        // Restart: alpha is already checkpointed (no NEW write); bravo is
        // the only NEW migration this run.
        expect(secondOutcome.migratedSongs, 1);
        expect(secondOutcome.totalSongs, 2);
        expect(secondOutcome.failedSongs, isEmpty);

        final list = await cleanRepo.list(
          const SongQuery(includeTrashed: true, includeArchived: true),
        );
        expect(
          list.valueOrNull!.map((s) => s.documentId.value).toList()..sort(),
          [_songSeed1Id, _songSeed2Id],
        );
      },
    );

    test(
      'read-back parity rejects an altered document with the same id and title',
      () async {
        _seedLegacySongs(store, [_songJson(id: _songSeed1Id, name: 'Alpha')]);
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();
        final delegate = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );
        final migrator = SongStorageMigrator.create(
          legacyStore: store,
          songRepository: _AlteredReadBackSongRepository(delegate),
          songsRoot: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );

        final outcome = await migrator.run();

        expect(outcome.status, SongMigrationStatus.needsResume);
        expect(outcome.failedSongs, hasLength(1));
        expect(
          outcome.failedSongs.single.reason,
          SongMigrationFailureReason.readBackMiss,
        );
        expect(outcome.completedAt, isNull);
      },
    );

    test(
      'corrupt song record redacts recovery and keeps the good checkpoint',
      () async {
        _seedLegacySongs(store, [
          _songJson(id: _songSeed1Id, name: 'Alpha'),
          _songJson(id: 'song_corrupt', name: 'Corrupt', bpm: 0),
          _songJson(id: _songSeed3Id, name: 'Charlie'),
        ]);
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();

        final migrator = await _buildMigrator(
          store: store,
          songsRoot: songsRoot,
        );
        final outcome = await migrator.run();
        expect(outcome.status, SongMigrationStatus.needsResume);
        expect(outcome.migratedSongs, 2);
        expect(outcome.failedSongs, hasLength(1));
        expect(outcome.failedSongs.single.id, 'song_corrupt');
        expect(outcome.failedSongs.single.reason, isNotEmpty);
        expect(outcome.completedAt, isNull);

        final restart = await _buildMigrator(
          store: store,
          songsRoot: songsRoot,
        );
        final second = await restart.run();
        // Restart: alpha + charlie are already checkpointed, so this run
        // does 0 new writes; song_corrupt stays redacted and is reported
        // again as a failure.
        expect(second.status, SongMigrationStatus.needsResume);
        expect(second.migratedSongs, 0);
        expect(second.failedSongs.single.id, 'song_corrupt');
        final repo = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 14),
        );
        final list = await repo.list(
          const SongQuery(includeTrashed: true, includeArchived: true),
        );
        expect(
          list.valueOrNull!.map((s) => s.documentId.value).toList()..sort(),
          [_songSeed1Id, _songSeed3Id],
        );
      },
    );
  });

  group('SongStorageMigrator — setlist mapping', () {
    late Directory sandbox;
    late _InMemoryKeyValueStore store;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('song_migrator_setlist_');
      store = _InMemoryKeyValueStore();
    });
    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('setlist runs only after every song is checkpointed', () async {
      _seedLegacySongs(store, [_songJson(id: _songSeed1Id, name: 'Alpha')]);
      _seedLegacySetlists(store, [
        _setlistJson(id: 'set_main', songIds: [_songSeed1Id]),
      ]);
      final songsRoot = Directory('${sandbox.path}/songs')..createSync();

      final migrator = await _buildMigrator(store: store, songsRoot: songsRoot);
      final outcome = await migrator.run();

      expect(outcome.status, SongMigrationStatus.completed);
      expect(outcome.setlistAdaptation, isNotNull);
      expect(outcome.setlistAdaptation!.documents, hasLength(1));
      expect(outcome.setlistAdaptation!.documents.first.id.value, _songSeed1Id);
      expect(outcome.setlistAdaptation!.unresolvedIds, isEmpty);
    });

    test('missing setlist reference is unresolved, songs survive', () async {
      _seedLegacySongs(store, [_songJson(id: _songSeed1Id, name: 'Alpha')]);
      _seedLegacySetlists(store, [
        _setlistJson(
          id: 'set_partial',
          songIds: [_songSeed1Id, 'song_missing'],
        ),
      ]);
      final songsRoot = Directory('${sandbox.path}/songs')..createSync();

      final migrator = await _buildMigrator(store: store, songsRoot: songsRoot);
      final outcome = await migrator.run();

      expect(outcome.status, SongMigrationStatus.completed);
      expect(outcome.setlistAdaptation, isNotNull);
      expect(outcome.setlistAdaptation!.documents, hasLength(1));
      expect(outcome.setlistAdaptation!.unresolvedIds, ['song_missing']);
      expect(
        outcome.setlistAdaptation!.report.warningSummary,
        contains(LegacyMigrationCode.setlistReferenceUnresolved),
      );

      final repo = await FileSongRepository.openAtDirectory(
        directory: songsRoot,
        clock: () => DateTime.utc(2026, 8, 2, 14),
      );
      final list = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(list.valueOrNull!.map((s) => s.documentId.value), [_songSeed1Id]);
    });

    test('setlist step is skipped while any song is still failed', () async {
      _seedLegacySongs(store, [
        _songJson(id: _songSeed1Id, name: 'Alpha'),
        _songJson(id: 'song_corrupt', name: 'Corrupt', bpm: 0),
      ]);
      _seedLegacySetlists(store, [
        _setlistJson(id: 'set_main', songIds: [_songSeed1Id]),
      ]);
      final songsRoot = Directory('${sandbox.path}/songs')..createSync();

      final migrator = await _buildMigrator(store: store, songsRoot: songsRoot);
      final outcome = await migrator.run();

      expect(outcome.status, SongMigrationStatus.needsResume);
      expect(
        outcome.setlistAdaptation,
        isNull,
        reason: 'Setlist mapping must NOT run while a song is failed',
      );
    });
  });
}

class _FailNthCreateSongRepository implements SongRepository {
  _FailNthCreateSongRepository(
    this._delegate, {
    required this.failAfterCreates,
  });

  final SongRepository _delegate;
  final int failAfterCreates;
  int _successCount = 0;

  @override
  Future<AppResult<void>> create(SongDocument document) async {
    if (_successCount >= failAfterCreates) {
      _successCount++;
      return songRepositoryFailure<void>(SongRepositoryErrorCode.io);
    }
    final result = await _delegate.create(document);
    if (result.isSuccess) {
      _successCount++;
    }
    return result;
  }

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      _delegate.list(query);

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => _delegate.get(id);

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => _delegate.update(document, expectedRevision: expectedRevision);

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => _delegate.moveToTrash(id);

  @override
  Future<AppResult<void>> restore(SongId id) => _delegate.restore(id);

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      _delegate.permanentlyDelete(id);
}

class _ParityFailSongRepository implements SongRepository {
  _ParityFailSongRepository(this._delegate, {required this.failCreateIds});

  final SongRepository _delegate;
  final Set<SongId> failCreateIds;

  @override
  Future<AppResult<void>> create(SongDocument document) async {
    if (failCreateIds.contains(document.id)) {
      return const AppResult<void>.success(null);
    }
    return _delegate.create(document);
  }

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      _delegate.list(query);

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => _delegate.get(id);

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => _delegate.update(document, expectedRevision: expectedRevision);

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => _delegate.moveToTrash(id);

  @override
  Future<AppResult<void>> restore(SongId id) => _delegate.restore(id);

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      _delegate.permanentlyDelete(id);
}

class _AlteredReadBackSongRepository implements SongRepository {
  _AlteredReadBackSongRepository(this._delegate);

  final SongRepository _delegate;
  bool _altered = false;

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      _delegate.create(document);

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      _delegate.list(query);

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async {
    final result = await _delegate.get(id);
    final document = result.valueOrNull;
    if (_altered || document == null) return result;
    _altered = true;
    return AppResult<SongDocument?>.success(
      SongDocument(
        schemaVersion: document.schemaVersion,
        id: document.id,
        revision: document.revision,
        metadata: document.metadata,
        source: document.source,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
        assets: document.assets,
        markers: document.markers,
        tracks: document.tracks,
        sections: const [],
        measures: document.measures,
        tempoMap: document.tempoMap,
        meterMap: document.meterMap,
        keyMap: document.keyMap,
      ),
    );
  }

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => _delegate.update(document, expectedRevision: expectedRevision);

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => _delegate.moveToTrash(id);

  @override
  Future<AppResult<void>> restore(SongId id) => _delegate.restore(id);

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      _delegate.permanentlyDelete(id);
}
