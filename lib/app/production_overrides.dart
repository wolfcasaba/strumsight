// A kompozíciós gyökér tároló-oldali felülírásai (WP-A, 2026-09-06).
//
// A `main.dart` eddig NYOLC providert kötött be, de az analysis V2 és a
// song_trainer oldalon további HÉT éles provider `StateError`-t dob override
// nélkül — a `*BootProvider` párjaikat semmi nem hívta. Emiatt a szállított
// Library fül (`UnifiedLibraryScreen` → `libraryV2SourcesProvider`) a
// forráslista helyett kivételt kapott.
//
// A lista azért él külön fájlban, mert a `main.dart` maga nem tesztelhető: a
// `test/app/production_composition_test.dart` ugyanezt a két függvényt hívja
// temp könyvtárra állított gyökér-feloldókkal, és providerenként állítja, hogy
// felold.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/storage/key_value_store.dart';
import '../core/storage/storage_providers.dart';
import '../features/audio_analysis/application/analysis_providers.dart';
import '../features/audio_analysis/data/cache/analysis_cache.dart';
import '../features/audio_analysis/data/migration/analysis_migration_version_store.dart';
import '../features/audio_analysis/data/migration/legacy_library_migrator.dart';
import '../features/audio_analysis/domain/analysis_repository.dart';
import '../features/library/data/library_repository.dart';
import '../features/song_trainer/application/song_trainer_providers.dart';
import '../features/song_trainer/domain/repositories/setlist_repository.dart';
import '../features/song_trainer/domain/repositories/song_progress_repository.dart';

/// A felülírások, amikre már a BOOTSTRAP konténernek szüksége van, mielőtt a
/// boot-providerek felépítik az éles példányokat.
///
/// A `legacyLibrarySupplierProvider` alapértéke üres lista — a migrátor
/// dokumentált szándéka szerint (`analysis_providers.dart`) az éles bekötés
/// egy olyan closure-re cseréli, ami a legacy Library feature
/// `libraryRepositoryProvider.load` hívását végzi. Ez a csere ITT is kell, nem
/// csak az app-scope-ban: a `legacyLibraryMigratorBootProvider` a bootstrap
/// konténerben olvassa ki a suppliert, tehát ott is az élesnek kell lennie,
/// különben a migrátor egy örökre üres V1-forrással épülne fel.
List<Override> storageBootstrapContainerOverrides({
  required KeyValueStore keyValueStore,
}) => <Override>[
  keyValueStoreProvider.overrideWithValue(keyValueStore),
  legacyLibrarySupplierProvider.overrideWith(_productionLegacyLibrarySupplier),
];

/// A `libraryRepositoryProvider`-re kötött éles V1-forrás. `ref.read`, mert a
/// supplier hívásonként olvas — nem tart állapotot.
LegacyLibrarySupplier _productionLegacyLibrarySupplier(Ref ref) =>
    () => ref.read(libraryRepositoryProvider).load();

/// Megnyitja az analysis V2 és a song_trainer éles tárolóit a
/// [bootstrapContainer] boot-providerein keresztül, és visszaadja a hozzájuk
/// tartozó `ProviderScope` felülírásokat.
///
/// A [bootstrapContainer]-t a [storageBootstrapContainerOverrides] listájával
/// kell felépíteni.
///
/// MEGJEGYZÉS a migrátorról: a [legacyLibraryMigratorProvider] itt bekötésre
/// kerül, de a boot NEM futtatja le a migrációt — a fában ma sincs egyetlen
/// `LegacyLibraryMigrator.run` hívás sem az éles útvonalon. A providert
/// feloldhatóvá tesszük (eddig `StateError`-t dobott), a futtatás bekötése
/// külön döntés (ADR 0239).
Future<List<Override>> buildStorageProductionOverrides(
  ProviderContainer bootstrapContainer,
) async {
  final AnalysisRepository analysisRepository = await bootstrapContainer.read(
    analysisRepositoryBootProvider.future,
  );
  final AnalysisCache analysisCache = await bootstrapContainer.read(
    analysisCacheBootProvider.future,
  );
  final AnalysisMigrationVersionStore migrationVersionStore =
      await bootstrapContainer.read(
        analysisMigrationVersionStoreBootProvider.future,
      );
  final LegacyLibraryMigrator legacyMigrator = await bootstrapContainer.read(
    legacyLibraryMigratorBootProvider.future,
  );
  final SetlistRepository setlistRepository = await bootstrapContainer.read(
    setlistRepositoryBootProvider.future,
  );
  final SongProgressRepository songProgressRepository = await bootstrapContainer
      .read(songProgressRepositoryBootProvider.future);

  return <Override>[
    analysisRepositoryProvider.overrideWithValue(analysisRepository),
    analysisCacheProvider.overrideWithValue(analysisCache),
    analysisMigrationVersionStoreProvider.overrideWithValue(
      migrationVersionStore,
    ),
    legacyLibraryMigratorProvider.overrideWithValue(legacyMigrator),
    legacyLibrarySupplierProvider.overrideWith(
      _productionLegacyLibrarySupplier,
    ),
    setlistRepositoryProvider.overrideWithValue(setlistRepository),
    songProgressRepositoryProvider.overrideWithValue(songProgressRepository),
  ];
}
