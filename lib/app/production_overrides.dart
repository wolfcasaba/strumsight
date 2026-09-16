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
import '../features/song_trainer/domain/repositories/song_asset_repository.dart';
import '../features/song_trainer/domain/repositories/song_progress_repository.dart';
import '../features/song_trainer/domain/repositories/song_repository.dart';

/// A felülírások, amikre már a BOOTSTRAP konténernek szüksége van, mielőtt a
/// boot-providerek felépítik az éles példányokat.
///
/// CSAK a kulcs-érték tároló. A `legacyLibrarySupplierProvider` felülírása
/// szándékosan NINCS itt (MÉRT hiba, 2026-09-06 review, BLOCKER-2): a
/// bootstrap konténer `Ref`-jére záródó closure a konténer eldobása után
/// „Cannot use the Ref after it has been disposed" kivétellel dobna — a
/// migrátor és a suppliere ezért az APP-scope-ban épül fel, saját `Ref`-fel
/// (lásd [buildStorageProductionOverrides]).
List<Override> storageBootstrapContainerOverrides({
  required KeyValueStore keyValueStore,
}) => <Override>[keyValueStoreProvider.overrideWithValue(keyValueStore)];

/// A `libraryRepositoryProvider`-re kötött éles V1-forrás. `ref.read`, mert a
/// supplier hívásonként olvas — nem tart állapotot.
///
/// Az itt kapott [ref] az APP-scope providereé, tehát pontosan addig él, amíg
/// a provider maga.
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
///
/// A migrátor és a suppliere NEM a bootstrap konténerben épül fel (MÉRT hiba,
/// 2026-09-06 review, BLOCKER-2): a `legacyLibraryMigratorBootProvider` a
/// bootstrap `Ref`-jén keresztül olvasta ki a suppliert, a `main` viszont a
/// `finally` ágon eldobja azt a konténert — az így publikált migrátor
/// suppliere az ELSŐ hívásnál „Cannot use the Ref after it has been
/// disposed"-zal dobott volna. Mindkettő ezért `overrideWith`-tel, az
/// app-scope saját `Ref`-jéből épül fel, lustán.
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
    legacyLibrarySupplierProvider.overrideWith(
      _productionLegacyLibrarySupplier,
    ),
    legacyLibraryMigratorProvider.overrideWith(
      (ref) => LegacyLibraryMigrator(
        repository: ref.watch(analysisRepositoryProvider),
        versionStore: ref.watch(analysisMigrationVersionStoreProvider),
        supplier: ref.watch(legacyLibrarySupplierProvider),
      ),
    ),
    setlistRepositoryProvider.overrideWithValue(setlistRepository),
    songProgressRepositoryProvider.overrideWithValue(songProgressRepository),
  ];
}

/// A `main` kompozíciós lépésének kimenetele.
///
/// MÉRT hiba (2026-09-06 review, BLOCKER-1): a `main` `try`/`finally`-je NEM
/// fogott kivételt, a boot-providerek viszont lemezt olvasnak. Egy sérült
/// helyi fájl `FormatException`-je így kiszökött a `main`-ből, a `runApp`
/// SOHA nem futott le — a felhasználó örökre fekete képernyőt kapott, minden
/// visszaút nélkül. A hiba ezért ITT válik adattá: a `main` a
/// [ProductionCompositionFailure] ágon a bootstrap hibaképernyőt indítja el,
/// ugyanazzal a `problems` listával, amit az `AppBootstrap` is használ.
sealed class ProductionComposition {
  const ProductionComposition();
}

/// A felülírás-lista felépült; a `main` ezzel indítja az appot.
final class ProductionCompositionSuccess extends ProductionComposition {
  const ProductionCompositionSuccess(this.overrides);

  final List<Override> overrides;
}

/// A kompozíció elhasalt. A [problems] a `BootstrapFailureApp` bemenete.
final class ProductionCompositionFailure extends ProductionComposition {
  const ProductionCompositionFailure(this.problems);

  /// Egy bejegyzés a bukott lépésről — a bootstrap `problems` alakja.
  final List<String> problems;
}

/// Felépíti a `main` MINDEN boot utáni felülírását, kivétel nélkül.
///
/// A [buildTutorOverrides] azért paraméter, mert az éles változata a
/// `rootBundle`-t olvassa (Flutter-binding), a teszt viszont a hibaágat a
/// tároló-oldalról méri.
Future<ProductionComposition> composeProductionOverridesOrFailure({
  required ProviderContainer bootstrapContainer,
  required Future<List<Override>> Function() buildTutorOverrides,
}) async {
  try {
    final SongRepository songRepository = await bootstrapContainer.read(
      songRepositoryBootProvider.future,
    );
    final SongAssetRepository songAssetRepository = await bootstrapContainer
        .read(songAssetRepositoryBootProvider.future);
    final storageOverrides = await buildStorageProductionOverrides(
      bootstrapContainer,
    );
    final tutorOverrides = await buildTutorOverrides();
    return ProductionCompositionSuccess(<Override>[
      songRepositoryProvider.overrideWithValue(songRepository),
      songAssetRepositoryProvider.overrideWithValue(songAssetRepository),
      ...storageOverrides,
      ...tutorOverrides,
    ]);
  } on Object catch (error) {
    return ProductionCompositionFailure(<String>[
      'A helyi tárolók megnyitása nem sikerült, ezért az app nem indult el: '
          '$error',
    ]);
  }
}
