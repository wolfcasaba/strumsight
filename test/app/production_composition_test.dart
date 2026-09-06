// Őr a kompozíciós gyökér tároló-oldali felülírásaira (WP-A, 2026-09-06).
//
// Mérés a javítás előtt: a `main.dart` felülírás-listájával felépített
// konténerben a `libraryV2SourcesProvider` NEM oldott fel, hanem
//
//   Bad state: analysisRepositoryProvider must be overridden by the bootstrap
//   layer before the rest of the app reads it.
//
// A Library fül (`UnifiedLibraryScreen`) tehát a forráslista helyett kivételt
// kapott. Ez a teszt providerenként állítja, hogy a
// `buildStorageProductionOverrides` listája MINDEGYIKET feloldja — a lista
// bármelyik elemének elhagyása pontosan azt a cellát viszi pirosra.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/production_overrides.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/library/data/library_repository.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';
import 'package:strumsight/features/library_v2/providers/library_v2_providers.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';

import '../support/preference_store.dart';

void main() {
  late Directory root;
  late InMemoryKeyValueStore store;
  late ProviderContainer bootstrapContainer;
  late List<Override> storageOverrides;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('production_composition');
    store = InMemoryKeyValueStore();
    bootstrapContainer = ProviderContainer(
      overrides: [
        ...storageBootstrapContainerOverrides(keyValueStore: store),
        ..._tempRootResolverOverrides(root),
      ],
    );
    storageOverrides = await buildStorageProductionOverrides(
      bootstrapContainer,
    );
  });

  tearDown(() async {
    bootstrapContainer.dispose();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  /// Az app-scope konténer: a `main.dart` maradék felülírásai (kv-store, song
  /// repo) + a mért lista. Semmi más — így egy hiányzó elem itt dob.
  ProviderContainer appContainer() {
    final container = ProviderContainer(
      overrides: [
        preferenceStoreOverride(store),
        songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
        ..._tempRootResolverOverrides(root),
        ...storageOverrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('production storage overrides', () {
    test('analysisRepositoryProvider resolves', () {
      expect(appContainer().read(analysisRepositoryProvider), isNotNull);
    });

    test('analysisCacheProvider resolves', () {
      expect(appContainer().read(analysisCacheProvider), isNotNull);
    });

    test('analysisMigrationVersionStoreProvider resolves', () {
      expect(
        appContainer().read(analysisMigrationVersionStoreProvider),
        isNotNull,
      );
    });

    test('legacyLibraryMigratorProvider resolves', () {
      expect(appContainer().read(legacyLibraryMigratorProvider), isNotNull);
    });

    test('setlistRepositoryProvider resolves', () {
      expect(appContainer().read(setlistRepositoryProvider), isNotNull);
    });

    test('songProgressRepositoryProvider resolves', () {
      expect(appContainer().read(songProgressRepositoryProvider), isNotNull);
    });

    // A supplier alapértéke ÜRES listát ad — az a migrátornak azt hazudná,
    // hogy nincs migrálandó V1 tartalom. Az éles bekötésnek a legacy Library
    // repositoryt kell olvasnia (`analysis_providers.dart` dokumentált
    // szándéka), ezért itt valós mentett munkamenetet kérünk vissza.
    test('legacyLibrarySupplierProvider reads the legacy library', () async {
      final container = appContainer();
      await container.read(libraryRepositoryProvider).save([_session()]);

      final supplier = container.read(legacyLibrarySupplierProvider);
      final sessions = await supplier();

      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'legacy-1');
    });
  });

  group('the Library tab', () {
    test('libraryV2SourcesProvider resolves with 4 sources', () {
      expect(appContainer().read(libraryV2SourcesProvider), hasLength(4));
    });

    test('libraryV2ItemsProvider loads without throwing', () async {
      final items = await appContainer().read(libraryV2ItemsProvider.future);
      expect(items, isEmpty);
    });
  });
}

/// A három éles gyökér-feloldó temp könyvtárra kötve — a `path_provider`
/// SOHA nem kerül a teszt-folyamatba (a song_trainer minta, ADR 0090).
List<Override> _tempRootResolverOverrides(Directory root) => <Override>[
  analysisRepositoryProductionRootResolverProvider.overrideWithValue(
    () async => Directory('${root.path}/analysis'),
  ),
  analysisCacheProductionRootResolverProvider.overrideWithValue(
    () async => Directory('${root.path}/analysis_cache'),
  ),
  songTrainerProductionRootResolverProvider.overrideWithValue(
    () async => Directory('${root.path}/songs')..createSync(recursive: true),
  ),
];

AnalyzedSession _session() => AnalyzedSession(
  id: 'legacy-1',
  createdAt: DateTime.utc(2026, 9, 6),
  title: 'C',
  result: const AnalyzeResult(
    durationSec: 1,
    bpm: 120,
    chords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
    strums: [],
  ),
);
