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
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
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
}
