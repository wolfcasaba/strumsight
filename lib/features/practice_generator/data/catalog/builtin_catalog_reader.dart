/// A beépített gyakorlatok katalógus-olvasója (2026-09-05).
///
/// Az egyetlen éles `PracticeCatalogReader` implementáció. Eddig CSAK
/// tesztekben létezett ilyen, ezért a `exerciseCandidateResolverProvider`
/// élesben dobott, és a gyakorlástervező négy képernyője elérhetetlen volt.
///
/// **Nem hoz saját szabályt.** A jelöltté alakítást a
/// `PracticeEngineCatalogAdapter` végzi, a tervezői metaadatot a
/// `builtin_catalog_metadata.dart` tartja. Ez a modul a kettő összekötése és
/// a revíziók megnevezése.
///
/// **A kizárt jelölt nem tűnik el némán.** Az adapter figyelmeztetései a
/// `PracticeCatalogSnapshot.warnings`-ba kerülnek, tehát egy profil nélküli
/// gyakorlat KIMUTATHATÓAN marad ki, nem csak hiányzik.
library;

import '../../application/port/practice_catalog_reader.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import '../adapter/practice_engine_catalog_adapter.dart';
import 'builtin_catalog_metadata.dart';

/// A katalógus-revízió. Akkor lép, ha a beépített gyakorlatok HALMAZA vagy a
/// hozzájuk tartozó tervezői profil változik — a kettő együtt határozza meg,
/// mit lát a tervező.
const String builtinCatalogRevision = 'builtin-catalog.2026-09-05';

/// A tartalom-revízió. A gyakorlatok tartalmi sémájának verziója.
const String builtinContentRevision = 'builtin.v1';

final class BuiltinPracticeCatalogReader implements PracticeCatalogReader {
  const BuiltinPracticeCatalogReader({
    this.adapter = const PracticeEngineCatalogAdapter(),
  });

  final PracticeEngineCatalogAdapter adapter;

  @override
  PracticeCatalogSnapshot read() {
    final adaptation = adapter.adapt(builtinCatalogEntries());
    return PracticeCatalogSnapshot(
      catalogRevision: builtinCatalogRevision,
      contentRevision: builtinContentRevision,
      candidates: adaptation.candidates,
      warnings: adaptation.warnings,
    );
  }
}
