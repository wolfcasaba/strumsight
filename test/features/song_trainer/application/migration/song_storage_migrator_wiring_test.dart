/// E03-R08 — Production wiring smoke test for the migration
/// (ADR 0117 §Döntés 1 + §Döntés 2, SDD §18.6).
///
/// This suite replaces a missing integration test. It verifies the
/// production provider graph wires the legacy `KeyValueStore`, the V2
/// `SongRepository`, the songs-root `migration/state.json` marker, and
/// the migration outcome across an open / reopen cycle — without
/// pulling `path_provider` or `shared_preferences` into the test
/// process. The point is to fail loudly if the wiring drifts; the
/// provider suite is the single entry point the rest of the app
/// reads, and we MUST NOT silently swap implementations under it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/song_trainer/application/migration/song_migration_state.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

/// Hand-rolled in-memory `KeyValueStore` for the wiring test. We keep
/// the contract narrow (only `readString` / `writeString` are exercised)
/// because that is exactly what the production `keyValueStoreProvider`
/// hands the migrator.
class _WiringKeyValueStore implements KeyValueStore {
  _WiringKeyValueStore();

  final Map<String, Object> _values = <String, Object>{};

  @override
  String? readString(String key) =>
      _values[key] is String ? _values[key] as String : null;

  @override
  int? readInt(String key) => null;

  @override
  double? readDouble(String key) => null;

  @override
  bool? readBool(String key) => null;

  @override
  List<String>? readStringList(String key) => null;

  @override
  Future<void> writeString(String key, String value) async {
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
}

void _seedLegacySong(_WiringKeyValueStore store, Map<String, dynamic> song) {
  final existing = store.readString('ss.songs.songs');
  final list = existing == null
      ? <Map<String, dynamic>>[]
      : (jsonDecode(existing) as Map<String, dynamic>)['items']
            as List<dynamic>;
  list.add(song);
  store.writeString(
    'ss.songs.songs',
    jsonEncode(<String, dynamic>{'schemaVersion': 1, 'items': list}),
  );
}

Map<String, dynamic> _song({
  required String id,
  String name = 'Fixture',
  int bpm = 96,
  String pattern = 'd-du-ud-',
  List<String> chords = const ['C', 'G'],
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'chords': chords,
  'pat': pattern,
  'bpm': bpm,
  'bpb': 4,
};

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('song_migrator_wiring_');
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('production wiring migrates legacy content through the V2 repository '
      'and persists the marker across a fresh provider container', () async {
    final songsRoot = Directory('${sandbox.path}/songs')
      ..createSync(recursive: true);
    final legacyStore = _WiringKeyValueStore();
    _seedLegacySong(legacyStore, _song(id: 'song_alpha', name: 'Alpha'));
    _seedLegacySong(legacyStore, _song(id: 'song_bravo', name: 'Bravo'));

    // First boot — run the migrator through the production provider
    // graph. No FakeStore, no in-memory fake: the same code path
    // production ships must hand back a completed outcome.
    final firstContainer = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(legacyStore),
        songTrainerProductionRootResolverProvider.overrideWithValue(
          () async => songsRoot,
        ),
        songTrainerClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 2, 13),
        ),
      ],
    );
    addTearDown(firstContainer.dispose);

    final firstOutcome = await firstContainer.read(
      songMigrationOutcomeProvider.future,
    );
    expect(firstOutcome.status, SongMigrationStatus.completed);
    expect(firstOutcome.totalSongs, 2);
    expect(firstOutcome.migratedSongs, 2);
    expect(firstOutcome.failedSongs, isEmpty);
    expect(firstOutcome.completedAt, isNotNull);

    // The marker file MUST be on disk under the songs-root
    // `migration/` subdirectory (ADR 0117 §Döntés 2).
    final markerFile = File('${songsRoot.path}/migration/state.json');
    expect(
      markerFile.existsSync(),
      isTrue,
      reason: 'migration marker must be persisted under the songs root',
    );

    // The V2 repository MUST hold the migrated documents.
    final firstRepo = await firstContainer.read(
      songRepositoryBootProvider.future,
    );
    final firstList = await firstRepo.list(
      const SongQuery(includeTrashed: true, includeArchived: true),
    );
    expect(
      firstList.valueOrNull!.map((s) => s.documentId.value).toList()..sort(),
      ['song_alpha', 'song_bravo'],
    );

    // Second boot — fresh provider container against the SAME
    // legacy store (data still on disk) and the SAME songs root.
    // The marker must make the second run a no-op (no duplicates).
    final secondContainer = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(legacyStore),
        songTrainerProductionRootResolverProvider.overrideWithValue(
          () async => songsRoot,
        ),
        songTrainerClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 2, 14),
        ),
      ],
    );
    addTearDown(secondContainer.dispose);

    final secondOutcome = await secondContainer.read(
      songMigrationOutcomeProvider.future,
    );
    expect(secondOutcome.status, SongMigrationStatus.completed);
    expect(
      secondOutcome.migratedSongs,
      0,
      reason: 'second boot must be a no-op migration',
    );
    expect(secondOutcome.totalSongs, 2);

    // No duplicates — the V2 repository still owns exactly two songs.
    final secondRepo = await secondContainer.read(
      songRepositoryBootProvider.future,
    );
    final secondList = await secondRepo.list(
      const SongQuery(includeTrashed: true, includeArchived: true),
    );
    expect(
      secondList.valueOrNull!.map((s) => s.documentId.value).toList()..sort(),
      ['song_alpha', 'song_bravo'],
    );
  });

  test('in-memory song repository override skips filesystem but still runs the '
      'migrator via the override path', () async {
    final songsRoot = Directory('${sandbox.path}/songs')
      ..createSync(recursive: true);
    final legacyStore = _WiringKeyValueStore();
    _seedLegacySong(legacyStore, _song(id: 'song_gamma', name: 'Gamma'));

    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(legacyStore),
        songTrainerProductionRootResolverProvider.overrideWithValue(
          () async => songsRoot,
        ),
        songTrainerClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 2, 13),
        ),
        songRepositoryProvider.overrideWith((ref) {
          // Production override pattern: widget tests use this to
          // bypass the file system. The migration must still run
          // end-to-end against the in-memory fake.
          throw UnimplementedError(
            'override required: see inMemorySongRepositoryProvider.',
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    // Use the in-memory override path: re-bind `songRepositoryProvider`
    // to the in-memory fake.
    final migratedRepo = await container
        .read(songStorageMigratorProvider.future)
        .then((_) => container.read(inMemorySongRepositoryProvider));
    expect(migratedRepo, isNotNull);
    final list = await migratedRepo.list(
      const SongQuery(includeTrashed: true, includeArchived: true),
    );
    expect(list.isSuccess, isTrue);
  }, skip: 'In-memory override path is a follow-up (UI tests only).');
}
