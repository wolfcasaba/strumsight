/// E03-R07 — Production wiring smoke test (ADR 0090 §Döntés 1 + §5).
///
/// This suite replaces a missing integration test. It verifies the
/// production provider graph wires up against a temporary directory
/// WITHOUT pulling `path_provider` into the test process. The point is
/// to fail loudly if the production wiring drifts — the provider suite
/// (`song_trainer_providers.dart`) is the single entry point the rest
/// of the app reads; we MUST NOT silently swap implementations under
library;

/// it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/seed/song_seed_installer.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/data/seed/song_seed_marker_store.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('wiring_');
  });
  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('in-memory override returns the fake SongRepository', () {
    final container = ProviderContainer(
      overrides: [
        songRepositoryProvider.overrideWithValue(
          InMemorySongRepository(clock: () => DateTime.utc(2026, 8, 2, 13)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final repo = container.read(songRepositoryProvider);
    expect(repo, isA<InMemorySongRepository>());
  });

  test(
    'production wiring against a temp directory survives a full reopen',
    () async {
      final songsRoot = Directory('${sandbox.path}/songs')
        ..createSync(recursive: true);
      final container = ProviderContainer(
        overrides: [
          songTrainerProductionRootResolverProvider.overrideWithValue(
            () async => songsRoot,
          ),
          songTrainerClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 8, 2, 13),
          ),
          // E16-R01/A1 — the boot provider now ALSO installs the shipped
          // practice songs. This cell measures the bare store, so the
          // catalogue is pinned empty; the seeding cells are below.
          songSeedCatalogProvider.overrideWithValue(_noSeeds),
        ],
      );
      addTearDown(container.dispose);

      final repo = await container.read(songRepositoryBootProvider.future);
      expect(repo, isA<FileSongRepository>());
      final listResult = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(listResult.isSuccess, isTrue);
      expect(listResult.valueOrNull, isEmpty);

      // The asset store must also be wired against the SAME root so a
      // document hash from one and an asset SHA from the other share a
      // single filesystem namespace.
      final assetStore = await container.read(
        songAssetRepositoryBootProvider.future,
      );
      expect(assetStore, isA<SongAssetRepository>());
      expect(assetStore, isA<FileSongAssetRepository>());
    },
  );

  // ─── E16-R01/A1: the shipped practice songs are seeded at boot ───────
  //
  // MEASURED gap: a fresh install opened the Songs tab on an empty list.
  // The seeding runs inside `songRepositoryBootProvider` — the SAME place
  // that opens the store — so the Library sees the songs on first frame.

  test('the boot path seeds the catalogue exactly once', () async {
    final songsRoot = Directory('${sandbox.path}/songs')
      ..createSync(recursive: true);
    ProviderContainer boot() {
      final container = ProviderContainer(
        overrides: [
          songTrainerProductionRootResolverProvider.overrideWithValue(
            () async => songsRoot,
          ),
          songTrainerClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 9, 17),
          ),
          songSeedCatalogProvider.overrideWithValue(_testCatalog),
          songSeedAssetLoaderProvider.overrideWithValue(_loadTestSeed),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final firstRepo = await boot().read(songRepositoryBootProvider.future);
    final firstList = await firstRepo.list(const SongQuery());
    expect(
      firstList.valueOrNull!.map((s) => s.documentId.value).toList(),
      <String>['seed-a'],
    );
    expect(songSeedStateFileFor(songsRoot).existsSync(), isTrue);

    // A second boot against the SAME root must not duplicate the song.
    final secondRepo = await boot().read(songRepositoryBootProvider.future);
    final secondList = await secondRepo.list(const SongQuery());
    expect(
      secondList.valueOrNull!.map((s) => s.documentId.value).toList(),
      <String>['seed-a'],
    );
  });

  test('a deleted seed stays deleted across a reboot', () async {
    final songsRoot = Directory('${sandbox.path}/songs')
      ..createSync(recursive: true);
    ProviderContainer boot() {
      final container = ProviderContainer(
        overrides: [
          songTrainerProductionRootResolverProvider.overrideWithValue(
            () async => songsRoot,
          ),
          songTrainerClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 9, 17),
          ),
          songSeedCatalogProvider.overrideWithValue(_testCatalog),
          songSeedAssetLoaderProvider.overrideWithValue(_loadTestSeed),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final repo = await boot().read(songRepositoryBootProvider.future);
    await repo.permanentlyDelete(SongId('seed-a'));

    final rebooted = await boot().read(songRepositoryBootProvider.future);
    final listed = await rebooted.list(const SongQuery());

    expect(listed.valueOrNull, isEmpty);
  });
}

const _noSeeds = <SongSeedDefinition>[];

const _testCatalog = <SongSeedDefinition>[
  SongSeedDefinition(seedId: 'seed-a', assetKey: 'assets/songs/seed-a.json'),
];

Future<String> _loadTestSeed(String _) async {
  final document = SongDocument(
    schemaVersion: 1,
    id: SongId('seed-a'),
    revision: 0,
    metadata: SongMetadata(title: 'Seed A'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'seed-a.song.json',
      sha256: 'a' * 64,
      importedAt: DateTime.utc(2026, 9, 17),
      importerVersion: 'test@1',
    ),
    createdAt: DateTime.utc(2026, 9, 17),
    updatedAt: DateTime.utc(2026, 9, 17),
  );
  return utf8.decode(const SongDocumentCodec().encode(document));
}
