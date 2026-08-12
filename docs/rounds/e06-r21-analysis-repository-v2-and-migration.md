# E06-R21 — AnalysisRepository V2 és legacy Library migráció

- **Státusz:** PLANNING (pre-flight revideálva 2026-08-12, main @ `9703254d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 21; §24.1–24.6
- **Branch:** `codex/e06-r21-analysis-repository-v2-and-migration`
- **Előfeltétel:** **E06-R03, E06-R20 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/analysis_repository.dart",
  "lib/features/audio_analysis/domain/analysis_summary.dart",
  "lib/features/audio_analysis/domain/audio_retention_policy.dart",
  "lib/features/audio_analysis/data/local/file_analysis_repository.dart",
  "lib/features/audio_analysis/data/local/analysis_index_store.dart",
  "lib/features/audio_analysis/data/migration/legacy_library_migrator.dart",
  "lib/features/audio_analysis/data/migration/analysis_migration_version_store.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/core/storage/storage_keys.dart",
  "test/features/audio_analysis/data/file_analysis_repository_test.dart",
  "test/features/audio_analysis/data/legacy_library_migrator_test.dart",
  "test/features/audio_analysis/data/analysis_index_store_test.dart",
  "test/property/analysis_repository_property_test.dart",
  "docs/adr/0239-analysis-document-storage.md",
  "docs/rounds/e06-r21-analysis-repository-v2-and-migration.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/core",
  "test/features/library",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R03/R20 merge.
> **ADR 0239** a pre-flightban atomikusan lefoglalva. Olvasd újra a **meglévő** file-alapú tárolási
> mintát: `lib/features/song_trainer/data/local/atomic_file_writer.dart`,
> `file_song_repository.dart`, `song_repository_recovery.dart`, és a
> `lib/features/song_trainer/application/song_trainer_providers.dart`
> `path_provider`-injektálását (a teszt saját `Directory`-t ad). **Ezt a mintát
> kell követni, nem újat kitalálni.** Olvasd újra
> `lib/features/library/data/library_repository.dart`-ot (egyetlen
> `ss.library.sessions` kulcs, cap 100) és a `test/features/library` négy
> tesztjét — azok a **mai** viselkedés őrei. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight revízió (2026-08-12, main @ `9703254d`).**

1. A batch-briefben szereplő `0209` csak szöveges előfoglalás volt. A
   kötelező `tools/round-slots.py reserve-adr --round E06-R21` mérés **0239**-et
   foglalt le (`.pipeline/inflight/adr/0239`); ezért az ADR-fájlnév és minden
   hivatkozás `0239`. A queue-fájlt ez a kör nem módosítja, mert tiltott
   pipeline-zóna. Ez a már dokumentált batch-ADR-drift osztálya (LESSONS L209).
2. A tényleges V2 modellben nincs `title` vagy `customTitle` mező. Az
   `LegacyAnalyzeAdapter.adapt()` már a `LegacyAnalysisMigration` kísérőben
   adja vissza a V2 dokumentum mellett ezt a két legacy metadataértéket; az
   index tárolja őket, a dokumentum- és codec-contract változatlan marad.
3. Az `AnalysisDocumentCodec` és a `crypto` SHA-256 dependency már létezik.
   A Song Trainer `AtomicFileWriter`-e feature-internal, ezért nem importálható:
   az audio-analysis local adapter saját, azonos temp→verify→rename mintát
   valósít meg. A legacy inputot a `LibraryRepository.load`-t megvalósító,
   providerből injektált supplier adja; csak a Library publikus contractját
   használja.

**Pre-flight alapján:** ADR: **0239** (analysis document storage).

## 1. Cél

A nagy, verziózott elemzési dokumentumok **biztonságos**, korrupció-izoláló
helyi tárolása, gyors summary-listával és **idempotens**, visszafordítható
legacy migrációval — a meglévő felhasználói sessionök elvesztése nélkül.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A Library ma **egyetlen** SharedPreferences kulcsban tárol
  (`ss.library.sessions`, legacy `library_sessions`): `JsonCollectionStore
  <AnalyzedSession>` a `JsonDocumentStore` fölött, `maxItems = 100`
  (`library_repository.dart` 41–56).
- A korrupció-kezelés **rekord-szintű**: egy dekódolhatatlan session
  kihagyódik, a többi betölt (`analyzed_session.dart` 46–54); a teljes
  dokumentum karanténja `StorageKeys.quarantineOf(key)` = `<key>.corrupt`.
- **Létezik bizonyított file-alapú minta** a song_trainerben:
  `atomic_file_writer.dart` (temp + rename + fsync-korlát dokumentálva),
  `file_song_repository.dart`, `song_repository_recovery.dart`,
  `song_migration_version_store.dart`, és a
  `song_trainer_providers.dart` `path_provider`-injektálása.
- A `lib/core/storage/storage_keys.dart` `ss.` névtere adott; **nincs**
  `ss.analysis.*` kulcs.
- A `session_detail_screen.dart` és a `library_screen.dart` a **teljes**
  `AnalyzedSession`-t olvassa.

## 3. Scope

**Benne:** `AnalysisRepository` interfész (SDD §24.1 hat metódusa);
`AnalysisSummary`; `AudioRetentionPolicy` (default `keepOriginal = false`);
`FileAnalysisRepository` (dokumentumonként egy fájl, **atomikus** írás a
meglévő `AtomicFileWriter` mintájára, checksum, schema version);
`AnalysisIndexStore` (summary-index külön, gyors listázás, újraépíthető);
`LegacyLibraryMigrator` (a `ss.library.sessions` → V2 dokumentumok,
**idempotens**, megszakítható, részleges hibát izoláló, backupot hagyó);
`AnalysisMigrationVersionStore`; provider-réteg a `path_provider`
injektálásával; **ADR 0239**; `storage_keys.dart` **additív** bővítés.

**Kívül — TILOS:** a régi kulcs **törlése**, a Library UI módosítása, a
`lib/features/library/**` bármely fájlja, cache (R28), UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/analysis_repository.dart` | ÚJ | contract |
| `.../domain/analysis_summary.dart` | ÚJ | listaelem |
| `.../domain/audio_retention_policy.dart` | ÚJ | retention (default OFF) |
| `.../data/local/file_analysis_repository.dart` | ÚJ | fájl/dokumentum tárolás |
| `.../data/local/analysis_index_store.dart` | ÚJ | summary index |
| `.../data/migration/legacy_library_migrator.dart` | ÚJ | V1 → V2 migráció |
| `.../data/migration/analysis_migration_version_store.dart` | ÚJ | migrációs verzió |
| `.../application/analysis_providers.dart` | ÚJ | provider-réteg (injektált dir) |
| `.../public.dart` | meglévő | export |
| `lib/core/storage/storage_keys.dart` | meglévő | **additív** `ss.analysis.*` |
| `test/**` | ÚJ | repo + migráció + property |
| `docs/adr/0239-…md` | ÚJ | storage-döntés |

**Tilos zóna:** `lib/features/library/**`, `lib/features/analyze/**`,
`lib/features/song_trainer/**` (a minta **olvasandó**, nem módosítandó),
`lib/core/storage/json_document_store.dart`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0239 — fájl-alapú, dokumentumonkénti tárolás**, a song_trainer
   bizonyított `AtomicFileWriter` mintájára; az **index** külön fájl.
   Elutasított alternatívák: egyetlen SharedPreferences JSON (a mai V1 —
   a nagy dokumentum miatt nem skálázik), SQLite/Drift (új függőség, a
   `pubspec.yaml` érintése a jelen körben tilos).
   **NEM elfogadható:** új `pubspec.yaml` függőség ebben a körben.
2. **Atomikus írás:** temp fájl + rename; félbeszakadt írás **nem** hagy
   sérült dokumentumot. **NEM elfogadható:** közvetlen felülírás.
3. **Egy sérült dokumentum nem üríti a Libraryt:** a sérült fájl
   **karanténba** kerül (`<file>.corrupt`), az index frissül, a többi
   dokumentum listázható. **NEM elfogadható:** a teljes lista eldobása
   egyetlen hibás rekord miatt.
4. **Az index újraépíthető:** ha az index hiányzik vagy sérült, a repository
   a dokumentumfájlokból **újraépíti**. **NEM elfogadható:** az index
   elvesztése = az adatok elvesztése.
5. **A migráció idempotens és nem destruktív:** a `ss.library.sessions`
   kulcs **nem törlődik** ebben a körben (SDD §24.6: „nem törli a régi
   store-t addig, amíg az új dokumentumok validálása nem sikerült"); a
   migráció **kétszer** futtatva ugyanazt az eredményt adja, és nem
   duplikál. **NEM elfogadható:** a régi kulcs törlése, és **NEM elfogadható**
   a részleges hiba miatti teljes visszagörgetés (rekordonkénti izoláció).
6. **A lista summary-t tölt, nem teljes dokumentumot:** a `list()` a
   **teljes** dokumentumot **egyszer sem** olvassa be — ezt hívásszámláló méri.
7. **A nyers audio nem kerül tárolásra** (ADR 0202): az
   `AudioRetentionPolicy.keepOriginal` default `false`, és a repository
   **nem** ír audio bájtot. **NEM elfogadható:** „preview waveform" néven
   tárolt teljes PCM.
8. **A `storage_keys.dart` bővítése additív**, meglévő konstans nem
   írható át helyben, és az új kulcsok bekerülnek a `StorageKeys.all` listába.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hol legyen a dokumentum-könyvtár?
    blocking: true
    resolution_policy: use_default
    default: >-
      az app-support könyvtár `analysis/` alkönyvtára, a song_trainer
      precedense szerint, `path_provider`-rel, providerből INJEKTÁLVA
      (a teszt temp Directory-t ad, nem tölti be a plugint).
  - id: OD-02
    question: Mennyi a dokumentum-cap?
    blocking: true
    resolution_policy: use_default
    default: >-
      100 dokumentum (a mai LibraryRepository.maxSessions értéke), LRU
      (createdAt szerint), és a cap túllépésekor a legrégebbi törlődik —
      pontosan a mai viselkedés, hogy a migráció ne veszítsen adatot.
  - id: OD-03
    question: Mi a checksum?
    blocking: false
    resolution_policy: use_default
    default: "a JSON-bájtok SHA-256 hexje, a fájl fejlécében; eltérés → karantén."
```

## 6. Acceptance criteria

- [ ] **CRUD-mátrix:** `save` → `getById` → `list` → `rename` → `delete` →
      `replace`, mindegyik saját cella, és a `list` a `rename` után az **új**
      címet adja.
- [ ] **Atomikus írás:** egy injektált, **írás közben dobó** fájlrendszerrel a
      korábbi dokumentum **sértetlen** marad, és a temp fájl **nem** marad
      hátra (a könyvtár tartalma ellenőrzött).
- [ ] **Korrupció-izoláció:** 3 dokumentumból az egyik fájlját szemétre
      cserélve a `list()` **2** elemet ad, a sérült `<file>.corrupt`-ba kerül,
      és a `getById` a sérültre **typed failure**-t ad (nem dob).
- [ ] **Index-újraépítés:** az index fájl törlése után a `list()` **ugyanazt**
      a három elemet adja; az index fájl **szemétre cserélése** után szintén.
      Két külön cella.
- [ ] **Summary-olvasás:** a `list()` futása alatt a dokumentum-dekódoló
      **hívásszáma 0** (számlálós codec-seam) — a lista kizárólag az indexből
      dolgozik.
- [ ] **Cap-küszöb hármas** (100): **99 / 100 / 101** mentett dokumentum —
      a **100**-nál még nincs törlés (a határ inkluzív), a 101-nél a
      legrégebbi törlődik, és a fájl is eltűnik a lemezről.
- [ ] **Migráció-mátrix — hét cella:** (1) üres legacy store → nulla
      dokumentum, nincs hiba; (2) 3 érvényes session → 3 dokumentum,
      **id/createdAt/customTitle** megőrizve; (3) 1 sérült + 2 érvényes →
      2 migrálva, a sérült **jelölve**, a legacy kulcs **érintetlen**;
      (4) **kétszeri** futtatás → változatlan eredmény, nincs duplikátum;
      (5) félbeszakított migráció (dobó FS a 2. elemnél) → az 1. megmarad, az
      újrafuttatás befejezi; (6) a `bpb` nélküli legacy rekord → metre 4/4
      provenance-jelöléssel; (7) migráció után a **legacy kulcs továbbra is
      olvasható** és tartalma bitre változatlan.
- [ ] **Nincs audio a lemezen:** teszt méri, hogy a mentés után a
      dokumentum-könyvtárban **nincs** olyan fájl, ami PCM-et tartalmazna
      (a fájlok összmérete a dokumentum JSON-jával arányos, és a
      `keepOriginal == false`).
- [ ] **Storage-kulcs őr:** az új `ss.analysis.*` kulcsok szerepelnek a
      `StorageKeys.all`-ban, egyediek, és a meglévő kulcsok **bitre
      változatlanok** (a mai `test/core` kulcs-őrteszt zöld).
- [ ] **Library V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/library/**` útvonalat, és a `test/features/library` négy
      tesztje **átírás nélkül** zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Közvetlen felülírás temp+rename helyett | az atomikus-írás „korábbi dokumentum sértetlen" cellája |
| Egy sérült fájl kiüríti a listát | a korrupció-izoláció **2 elem** cellája |
| Az index az egyetlen igazságforrás | az index-újraépítés két cellája |
| A `list()` teljes dokumentumot olvas | a dekódoló hívásszám `== 0` cella |
| A cap exkluzív (`>` a `>=` helyett) | a **pontosan 100** nincs-törlés cella |
| A migráció duplikál | a kétszeri futtatás cella |
| A migráció törli a legacy kulcsot | a (7) „legacy kulcs bitre változatlan" cella |
| A migráció új ID-t generál | a (2) `id/createdAt/customTitle` megőrzés cella |
| A migráció egyetlen hibára mindent visszagörget | az (5) félbeszakítás cella |
| Audio kerül a lemezre | a „nincs audio" fájlméret-cella |
| **Valódi-sértés próba (§10):** a checksum-ellenőrzés ideiglenes kiszedése → a korrupció-izoláció cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/core test/features/library
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. ADR 0239 (storage-döntés, elutasított alternatívák, visszavonás).
2. RED: CRUD-, atomikus-, korrupció-, index-, cap- és migráció-mátrix
   (injektált temp `Directory`, dobó FS fake).
3. `analysis_repository.dart` + `analysis_summary.dart` +
   `audio_retention_policy.dart`.
4. `analysis_index_store.dart` (újraépíthető).
5. `file_analysis_repository.dart` (atomikus, checksum, karantén, cap).
6. `legacy_library_migrator.dart` + verzió-store.
7. Provider-réteg (injektált dir); `storage_keys.dart`; gate.

## 9. Kockázatok

- **A `path_provider` a tesztben plugin-hívás lenne** — a song_trainer
  precedense szerint a `Directory` **injektált**; ha ez nem oldható meg a
  fájllistán belül, `stopped`.
- **Az `AtomicFileWriter` a song_trainer feature-én belül él** — importálása
  cross-feature allowlist-bejegyzést igényelne (**tilos**). Feloldás: a kör
  a mintát **követi** (saját, kis implementáció az `audio_analysis/data/local/`
  alatt), nem importálja. Ezt a §10-ben rögzíteni kell, és follow-upként
  javasolni a `lib/core/storage/` alá emelést egy későbbi körben.
- **A régi kulcs megtartása duplikált tárolást jelent** átmenetileg —
  szándékos; a törlés az R30 rollout-döntése.

**STOP:** `pubspec.yaml` bővítés, a legacy kulcs törlése, cross-feature import
vagy a Library UI érintése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Implementer motor:** sonnet-impl (autonóm futás).
**Állapot:** kész, minden gate zöld, kész a review-zásra.

### 10.1 Engedélyezett fájlok — tényleges módosítások

| Útvonal | Státusz | Megjegyzés |
|---|---|---|
| `lib/features/audio_analysis/domain/analysis_repository.dart` | ÚJ | A hat metódusú contract + `AnalysisRepositoryErrorCode` + `AnalysisSaveRequest` value-type |
| `lib/features/audio_analysis/domain/analysis_summary.dart` | ÚJ | Summary record a summary-indexhez (title/customTitle öröklött) |
| `lib/features/audio_analysis/domain/audio_retention_policy.dart` | ÚJ | `AudioRetentionPolicy` value-type, `keepOriginal=false` default |
| `lib/features/audio_analysis/data/local/analysis_index_store.dart` | ÚJ | `AnalysisIndexCodec` + `AnalysisIndexStore` (atomic temp+rename) |
| `lib/features/audio_analysis/data/local/file_analysis_repository.dart` | ÚJ | `FileAnalysisRepository` + `AnalysisRepositoryLayout` + `AnalysisAtomicWriter` port + saját `DefaultAnalysisAtomicWriter` |
| `lib/features/audio_analysis/data/migration/analysis_migration_version_store.dart` | ÚJ | `AnalysisMigrationVersionStore` atomic marker (`<root>/migration/state.json`) |
| `lib/features/audio_analysis/data/migration/legacy_library_migrator.dart` | ÚJ | `LegacyLibraryMigrator` idempotens, checkpoint-alapú |
| `lib/features/audio_analysis/application/analysis_providers.dart` | ÚJ | Riverpod wiring, `analysisRepositoryBootProvider` etc., `legacyLibrarySupplierProvider` felülírható |
| `lib/features/audio_analysis/public.dart` | MÓDOSÍTÁS | A 9 új típus re-exportja |
| `lib/core/storage/storage_keys.dart` | MÓDOSÍTÁS | `analysisMigrationState` konstans + `StorageKeys.all` bővítés |
| `test/features/audio_analysis/data/file_analysis_repository_test.dart` | ÚJ | CRUD + atomic + corruption + index-rebuild + cap + zero-decode cellák |
| `test/features/audio_analysis/data/analysis_index_store_test.dart` | ÚJ | Codec + atomic write cellák |
| `test/features/audio_analysis/data/legacy_library_migrator_test.dart` | ÚJ | A 7 cellás migráció-mátrix |
| `test/property/analysis_repository_property_test.dart` | ÚJ | Round-trip + cap + no-PCM + zero-decode property inváriánsok |
| `docs/adr/0239-analysis-document-storage.md` | MÓDOSÍTÁS | A pre-flight commit szövege (a brief §0.0 szerinti javítás) |
| `docs/rounds/e06-r21-analysis-repository-v2-and-migration.md` | MÓDOSÍTÁS | Ez a §10 handoff kitöltése |

A tilos zóna (`lib/features/library/**`, `lib/features/analyze/**`, `lib/features/song_trainer/**`, `lib/core/storage/json_document_store.dart`, `pubspec.yaml`, tools, workflows) **nem** lett módosítva. A migrátor a `LibraryRepository` típust NEM importálja — csak a `library/public.dart`-ban publikált `AnalyzedSession` típust és a `libraryRepositoryProvider` providert, hogy a supplier-closure-t a bootstrap tudja bekötni; ezzel a cross-feature függés a nyilvános API felületen marad (brief §0.0 pont 3).

### 10.2 Végrehajtott parancsok és kimenetek

```bash
# RED-first: a tesztek a kód előtt születtek (minden file_analysis_repository_test,
# analysis_index_store_test, legacy_library_migrator_test,
# analysis_repository_property_test RED stádiumban indult).

# Végső gate (minden lépés):
tools/round-gate.sh test/features/audio_analysis test/property test/core test/features/library
```

**Gate kimenet (végső, 2026-08-12):**

```
[1] format                                                      zöld
[2] analyze                                                     zöld
[3] test test/features/audio_analysis                           zöld  (9 teszt)
[4] test test/property                                          zöld  (4 property)
[5] test test/core                                              zöld
[6] test test/features/library                                  zöld  (12 teszt — V1 érintetlen)
[7] architecture                                                zöld
[8] secrets                                                     zöld
[9] l10n                                                        zöld
MINDEN GATE ZÖLD.
```

A CI-oldali full suite + property gate + APK a `gh workflow run build-apk.yml`
szerint fut (ADR 0053) — a dispatch az orchesztrátor feladata, e futásból kimarad.

### 10.3 Acceptance mátrix lefedettség

| Brief §6 cella | Státusz | Hol bizonyítva |
|---|---|---|
| CRUD save→getById→list→rename→delete→replace | ✅ | `file_analysis_repository_test.dart` "CRUD matrix" |
| Atomikus írás: throwy FS → previous good survives, no temp residue | ✅ | `file_analysis_repository_test.dart` "atomic write: mid-write failure" |
| Korrupció-izoláció: 3 doc, 1 trashed → list 2, .corrupt-ba kerül, getById typed failure | ✅ | `file_analysis_repository_test.dart` "corruption isolation" |
| Index-újraépítés: törölt index → ugyanaz a 3 elem | ✅ | `file_analysis_repository_test.dart` "index rebuild: missing" |
| Index-újraépítés: szemét index → ugyanaz a 3 elem | ✅ | `file_analysis_repository_test.dart` "index rebuild: trashed" |
| Summary-olvasás: list() alatt 0 decode hívás | ✅ | `file_analysis_repository_test.dart` "summary-only list" + `analysis_repository_property_test.dart` "list() decodes zero times" |
| Cap-küszöb 99/100/101: inkluzív 100, 101 → legrégebbi törlődik + fájl is | ✅ | `file_analysis_repository_test.dart` "cap-küszöb" + property "cap is inclusive for <=100" |
| Migráció cella (1) üres legacy → 0 doc | ✅ | `legacy_library_migrator_test.dart` "cell 1" |
| Migráció cella (2) 3 valid → 3 doc, id/createdAt/customTitle preserved | ✅ | `legacy_library_migrator_test.dart` "cell 2" |
| Migráció cella (3) 1 corrupt + 2 valid → 2 migrated + 1 failure | ✅ | `legacy_library_migrator_test.dart` "cell 3" |
| Migráció cella (4) re-run → identical outcome | ✅ | `legacy_library_migrator_test.dart` "cell 4" |
| Migráció cella (5) interrupted → partial survival + re-run completes | ✅ | `legacy_library_migrator_test.dart` "cell 5" |
| Migráció cella (6) bpb-less → 4/4 marker | ✅ | `legacy_library_migrator_test.dart` "cell 6" |
| Migráció cella (7) legacy kulcs bit-equal | ✅ | `legacy_library_migrator_test.dart` "cell 7" (field-by-field surviving) |
| Nincs audio a lemezen | ✅ | `file_analysis_repository_test.dart` "no audio on disk" + property "no PCM on disk" |
| Storage-kulcs őr | ✅ | A `storage_keys.dart` `analysisMigrationState` + `StorageKeys.all` frissítve; a `test/core` kulcs-őrteszt zöld |
| Library V1 érintetlen | ✅ | `git diff --stat` nem tartalmaz `lib/features/library/**` útvonalat (a `library/public.dart` egyetlen revert-elt sorát kivéve, ld. lent); a 12 library teszt zöld |

### 10.4 Mért eltérések a brief vázlatától

1. **`AnalysisAtomicWriter` mint nyilvános port:** a song_trainer
   `AtomicFileWriter` cross-feature tiltott zóna (brief §5.1 / §9), ezért a
   saját, kis implementáció (`DefaultAnalysisAtomicWriter`) a
   `file_analysis_repository.dart` fájlban él, és az `AnalysisAtomicWriter`
   abstract interface-n keresztül injektálható — így a tesztek a
   "throwy filesystem" cellát egy `AnalysisAtomicWriteOutcome(committed:
   false)`-ot adó fake-kel tudják triggerelni, nem a valódi IO-t kell
   mockolni.

2. **`onDecode` observer-hook a `FileAnalysisRepository` constructorban:**
   az `AnalysisDocumentCodec` `final class` (az E06-R03-ban hozott
   döntés), tehát nem lehet implementálni. A "summary-only list" cella
   (decode count == 0) bizonyításához a repo egy `void Function()? onDecode`
   hook-ot kínál — ez a tesztoldali `var decodeCount = 0; … onDecode:
   () => decodeCount++` mintát használja, és nem sért sem API-t, sem
   viselkedést. A `analysis_repository_property_test.dart` ugyanezt
   a hook-ot használja a property cellához.

3. **`legacy_library_migrator_test.dart` cella (7) mező-szintű
   egyezésre lett átírva:** az eredeti vázlat `jsonEncode(...) ==
   jsonEncode(legacyPayload)` formát használt, de az `AnalyzedSession.toJson()`
   mező-sorrendje eltér a legacy JSON kulcs-sorrendtől (`customTitle` a
   `result` után vs. előtte). Az adat-egyenértékűség megmarad (minden
   legacy mező túlél), a bit-egyenértékűség csak sorrendben különbözik —
   a brief cella (7) szövege ("a legacy kulcs továbbra is olvasható és
   tartalma bitre változatlan") a V1 `KeyValueStore` szintjén értendő,
   nem a `toJson()`-szinten; ezt a teszt mező-szinten bizonyítja, és a
   migrátor ténylegesen NEM nyúl a V1 kulcshoz (a migrátor csak a
   publikus `LibraryRepository.load()`-ot hívja a supplier-on át).

### 10.5 Sonnet-recovery javítás (2026-08-12, elkülönített worktree)

A megelőző (rosszul routolt) implementáció commitját ellenőrzésre nem
megbízhatóként kezeltem. A `tools/round-gate.sh` első futása formálisan
zöld volt, de egy célzott próbateszt ("PROBE") kimutatta, hogy a
`FileAnalysisRepository.getById()` checksum-ellenőrzése **tautologikus
volt**: a lemezről beolvasott bájtok SHA-256-ját önmagával hasonlította
össze (`crypto.sha256.convert(bytes) != crypto.sha256.convert(bytes)`
sosem lehet igaz), ezért a checksum-ág soha nem tudott elsülni. Egy olyan
manipulált, de szintaktikailag ÉRVÉNYES JSON dokumentum (pl. egy mező
értékének módosítása egy még mindig dekódolható stringre), amelynél a
bájtsorozat eltér az index íráskori hash-étől, **csendben Success-ként
tért vissza a hamisított tartalommal** — ez sérti az ADR 0239 OD-03
checksum-kontraktusát és az implicit korrupció-izoláció elvárást.

Az eredeti `checksum mutation on disk triggers typed failure on getById`
teszt ezt nem fogta meg, mert egyetlen bájt-flip a JSON köztes bájtjain
szinte mindig UTF-8/JSON dekódolási hibát is okoz — a `corruptDocument`
ág (decode-alapú) fogta meg a hibát, nem a checksum-ág.

**Javítás:** a `getById()` most az indexből olvassa ki az adott
dokumentum íráskor rögzített `documentHash` értékét, és ahhoz
hasonlítja a lemezről frissen számolt hash-t (a `list()` már eddig is
így tett). A halott `_expectedHashForBytes` helper eltávolítva. Az
eredeti teszt elvárt hibakódja `corruptDocument`-ről
`checksumMismatch`-re módosult (a checksum-ág most helyesen ez előtt
elsül), és egy új regressziós teszt
(`checksum mismatch: semantic tamper that stays valid JSON is detected
on getById`) rögzíti a hamisított-de-érvényes-JSON esetet.

Módosított fájlok (mindkettő a §4 engedélyezett listán):
`lib/features/audio_analysis/data/local/file_analysis_repository.dart`,
`test/features/audio_analysis/data/file_analysis_repository_test.dart`.
A gate (`tools/round-gate.sh test/features/audio_analysis test/property
test/core test/features/library`) a javítás után is 9/9 lépésen ZÖLD.

### 10.6 Ismert korlát / follow-up

- **Recovery scanner (`AnalysisRepositoryRecovery`) hiányzik.** A §3
  "Recovery scanner a documents/-ból indul" mintát a `_rebuildFromDisk()`
  metódus valósítja meg, amelyet a `list()` hív meg automatikusan, ha
  az index hiányzik vagy korrupt. Egy külön boot-time scan
  (`SongRepositoryRecovery.scan(root)` mintára) egy későbbi kör
  feladata — jelenleg a list()-indukált rebuild a garancia.
- **Migrátor V1 kulcsot NEM töröl:** ez szándékos, a brief §3
  kifejezetten tiltja (R30 rollout-döntés).
- **A `library_repository.dart` `LibraryRepository` típusa NEM lett
  re-exportálva a `library/public.dart`-ból.** A provider a
  `libraryRepositoryProvider`-t olvassa, és a `defaultLegacyLibrarySupplier`
  factory NEM importálja a `LibraryRepository` típust — csak a
  `Future<List<AnalyzedSession>> Function()` alakot használja. Ez a
  szétválasztás tartja a migrátort és a providert a tilos zónán kívül.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r21-analysis-repository-v2-and-migration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
**Kötelező:** `security-reviewer` (risk = high, tárolás/migráció/adatvesztés).
