# E03-R07 — Fájlrendszeres Song repository és asset store

- **Státusz:** **PLANNING** (2026-08-02, pre-flight: Claude Sonnet 5,
  baseline `main` @ `c31625c`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 7; §18
- **Branch:** `codex/e03-r07-song-repository-asset-store`
- **Előfeltétel:** E03-R06 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/domain/repositories/song_repository.dart",
  "lib/features/song_trainer/domain/repositories/song_asset_repository.dart",
  "lib/features/song_trainer/data/local/file_song_repository.dart",
  "lib/features/song_trainer/data/local/file_song_asset_repository.dart",
  "lib/features/song_trainer/data/local/song_index_codec.dart",
  "lib/features/song_trainer/data/local/atomic_file_writer.dart",
  "lib/features/song_trainer/data/local/song_repository_recovery.dart",
  "lib/features/song_trainer/data/local/in_memory_song_repository.dart",
  "lib/features/song_trainer/application/song_trainer_providers.dart",
  "test/features/song_trainer/data/local/file_song_repository_test.dart",
  "test/features/song_trainer/data/local/file_song_asset_repository_test.dart",
  "test/features/song_trainer/data/local/song_repository_recovery_test.dart",
  "test/features/song_trainer/data/local/song_repository_wiring_test.dart",
  "docs/rounds/e03-r07-song-repository-asset-store.md",
]
gate_tests = [
  "test/features/song_trainer/data/local",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold a brief minden útvonalát, symbolját, state producerét, resource
> ownerét és numerikus celláját. Drift esetén dokumentáld lent §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer indítása előtt. A `PREPARED` brief önmagában
> nem végrehajtási engedély.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract, ellentmondó
acceptance, hiányzó fixture/licence, vagy nem reprodukálható mérce esetén:
`stopped` és pontos jelentés; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- A V2 codec R02-ben, validáció R05-ben, legacy adapter R06-ban kész.
- A planning baseline core storage KeyValueStore-ja nem alkalmas nagy SongDocument/asset tárolásra.
- Platform directory, clock és IO hibák injektálható boundaryt igényelnek.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

**Pre-flight mérés (2026-08-02, Claude Sonnet 5, baseline `main` @ `c31625c`):**

1. **A pipeline-prompt "Előre kiosztott ADR: nincs" állítása elavult — VAN
   már kiosztott, elfogadott ADR.** [`ADR 0090`](../adr/0090-song-storage-files-and-assets.md)
   (elfogadva E03-R01 pre-flightban) SZÓ SZERINT formalizálja ennek a
   körnek minden architekturális döntését: a fájlrendszer-elrendezést
   (`app_support/songs/{index.json,documents/,assets/,originals/,trash/,
   temp/}`), a `SongRepository` `AppResult`-kontraktust
   `expectedRevision`-nel, a kötött atomikus mentési sorrendet, az index
   csak-metaadat szerepét, a SHA-256 content-hash asset store-t, a
   kétlépcsős törlést és a nem-destruktív recovery-t. A brief §5 táblája
   ezt a listát tömöríti — nincs eltérés a kettő között. **Döntés:** ez a
   kör NEM oszt ki új ADR-számot; `ADR 0090`-et implementálja. Ha
   implementáció közben olyan döntés merül fel, amit 0090 nem fed le, azt
   egy ÚJ ADR-ben (következő szabad szám, jelenleg **0117**) kell
   rögzíteni, `docs/adr/**` a tiltott zóna alól explicit kivétellel, még a
   `PLANNING` állapot lezárása előtt.
2. **`path_provider` és `clock` NEM szerepel a `pubspec.yaml` közvetlen
   `dependencies:` blokkjában, de mindkettő már feloldott tranzitív
   csomag** (`pubspec.lock`: `path_provider` a `flutter_local_notifications`/
   `share_plus` láncból, `clock` szintén tranzitív) — pontosan ugyanaz a
   minta, mint a már merge-elt E03-R06 `legacy_song_reader.dart`, amely
   `package:crypto/crypto.dart`-ot importál közvetlenül anélkül, hogy a
   `crypto` a `pubspec.yaml`-ban szerepelne (review APPROVED, 0
   BLOCKER/MAJOR). **Döntés:** a fájlrendszeres réteg használhatja
   `package:path_provider/path_provider.dart`-ot (`getApplicationSupportDirectory()`)
   közvetlen importként a már befogadott precedens alapján — a
   `pubspec.yaml` NEM kerül az engedélyezett fájllistára, nincs
   scope-bővítés. A `clock` csomagot viszont NEM kell bevonni: az app
   egységes konvenciója (`lib/features/practice/application/
   practice_session_recording.dart:142`) egy egyszerű injektált
   `DateTime Function() now` — a repository ugyanezt a mintát követi
   (`DateTime.now` production default, fix `DateTime` teszt-injekcióval).
3. **A brief feltételezett API-i pontosan egyeznek a kódbázissal** (nincs
   drift): `SongDocumentCodec.encode(SongDocument) → List<int>` /
   `.decode(List<int>) → SongDocument`
   (`lib/features/song_trainer/data/local/song_document_codec.dart:125,133`),
   `SongId.safeFilename()` determinisztikus fájlnév-vetítés
   (`domain/models/song_id.dart:55`), `SongDocument.revision` nem-negatív
   `int` (`domain/models/song_document.dart:69,103`).
4. **A "validate" mentési lépés konkrét hívási lánca kimérve:**
   `SongValidator.validate(document) → SongValidationReport`
   (`domain/services/song_validator.dart:115`) +
   `SongCapabilityResolver` — bármely `fatal` severity-jű issue
   `canPersist=false`-ra állítja minden profilban
   (`domain/services/song_capability_resolver.dart:51`, ADR 0114 §Döntés 2).
   A repository `create`/`update` a mentés előtt lefuttatja a validátort,
   és `canPersist=false` esetén stabil, feature-lokális conflict/refusal
   kóddal utasítja el a perzisztálást — a validáció maga NEM dobhat, a
   report NEM alakulhat át csendes sikerré.
5. **A `lib/features/song_trainer/domain/` framework-purity-jét NEM a
   `tool/check_architecture.dart` őrzi** (az csak
   `lib/features/practice/domain/`-t szkenneli — 232. sor), **hanem egy
   önálló, rekurzív teszt-scanner**
   (`test/features/song_trainer/domain/song_document_test.dart`, „Domain
   purity" csoport, 292–332. sor) — ez automatikusan lefedi az új
   `domain/repositories/song_repository.dart` és
   `song_asset_repository.dart` interfészeket is, mert a teljes
   `domain/`-t rekurzívan bejárja. Nincs `tool/`-módosítási igény (az is
   tiltott zóna lenne).
6. **Nincs meglévő platform-directory absztrakció** (`lib/core/platform/`
   csak lifecycle/permission/wakelock gateway-eket tartalmaz) — ez a brief
   §2 állítását megerősíti. A megoldás a §4 táblán belül marad: az „app
   support directory" felbontása (`getApplicationSupportDirectory()`)
   injektált `Directory Function()`/`Future<Directory> Function()`
   paraméterként él a `file_song_repository.dart`/
   `file_song_asset_repository.dart` konstruktorában, éles drótozás
   `song_trainer_providers.dart`-ban — NEM önálló, táblán kívüli fájlként.
7. **Új stabil hibakód-katalógus feature-lokálisan, NEM a megosztott
   `lib/core/foundation/app_failure.dart`-ban** (az nincs az engedélyezett
   listán). `AppFailure.code` egy sima `String` (`app_failure.dart:76`,
   `StorageFailure` bármilyen kódot elfogad, 125–131. sor) — a már
   bevett minta (`SongDocumentCodecErrorCode`, `SongIdValidationCode`
   saját, feature-lokális katalógusok) szerint a repository saját
   `SongRepositoryErrorCode`/`SongAssetRepositoryErrorCode` abstract
   final class-t definiál a táblán belüli fájlokban (stale revision,
   hash mismatch, corrupt index/document, orphan asset stb.), és
   `StorageFailure(code: <saját kód>, ...)`-ot ad vissza — nincs
   `core/foundation` módosítási igény.

Nincs feloldatlan drift. A brief §3–§9 tartalma változatlan marad, csak ez
a szakasz (§0.0) és a fejléc bővült.

## 1. Cél

Atomikus, revision-aware, recoverable dokumentum- és content-hash asset tárolás szállítása SharedPreferences nélkül.

## 2. Jelenlegi állapot

- A V2 codec R02-ben, validáció R05-ben, legacy adapter R06-ban kész.
- A planning baseline core storage KeyValueStore-ja nem alkalmas nagy SongDocument/asset tárolásra.
- Platform directory, clock és IO hibák injektálható boundaryt igényelnek.

## 3. Scope

**Benne:**

- SongRepository és SongAssetRepository contract
- file repository, index codec, atomic writer és recovery
- trash/restore/permanent delete, SHA-256 dedupe/integrity
- in-memory fake és production-wiring persistence test

**Kívül — ebben a körben TILOS:**

- legacy persistent migráció
- library UI és import controller
- SharedPreferences SongDocument vagy global singleton path

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/repositories/song_repository.dart` | ÚJ | repository contract |
| `lib/features/song_trainer/domain/repositories/song_asset_repository.dart` | ÚJ | asset contract |
| `lib/features/song_trainer/data/local/file_song_repository.dart` | ÚJ | file implementation |
| `lib/features/song_trainer/data/local/file_song_asset_repository.dart` | ÚJ | streamelt asset store |
| `lib/features/song_trainer/data/local/song_index_codec.dart` | ÚJ | summary index |
| `lib/features/song_trainer/data/local/atomic_file_writer.dart` | ÚJ | temp/flush/verify/rename |
| `lib/features/song_trainer/data/local/song_repository_recovery.dart` | ÚJ | startup scan |
| `lib/features/song_trainer/data/local/in_memory_song_repository.dart` | ÚJ | fake |
| `lib/features/song_trainer/application/song_trainer_providers.dart` | ÚJ | production wiring |
| `test/features/song_trainer/data/local/file_song_repository_test.dart` | ÚJ | CRUD/crash/revision |
| `test/features/song_trainer/data/local/file_song_asset_repository_test.dart` | ÚJ | hash/dedupe/delete |
| `test/features/song_trainer/data/local/song_repository_recovery_test.dart` | ÚJ | recovery |
| `test/features/song_trainer/data/local/song_repository_wiring_test.dart` | ÚJ | real provider re-open |
| `docs/rounds/e03-r07-song-repository-asset-store.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.

## 5. Kötött architekturális döntések

1. Save sorrend: validate→temp serialize→flush→decode verify→atomic document rename→temp index→atomic index rename→success.
2. Expected revision mismatch stabil conflict; overwrite és retry-without-refresh tilos.
3. Asset streamelt SHA-256 alapján deduplikál; document platform pathot nem tárol.
4. Recovery nem töröl bizonyíték nélkül user contentet; korábbi jó verzió hiba után olvasható.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] Create/get/update/list, stale revision, trash/restore/delete stabil AppResult contracttal működik.
- [ ] Minden crash-pont után vagy régi jó vagy új teljes verzió olvasható; fél JSON nem válik currentté.
- [ ] Hash mismatch, missing/corrupt index/document, duplicate/orphan asset recoverable report.
- [ ] Production providerrel mentett adat friss repository instance-ból olvasható; valós IO/storage exception stabil failure code-dá alakul.
- [ ] SongDocument egyetlen SharedPreferences/key-value value-ban sem jelenik meg.

### Kötelező megkülönböztető mátrix

| Hibahely | Kötelező újraindítási eredmény |
|---|---|
| temp write előtt/közben | régi verzió |
| flush után, verify előtt | régi verzió + temp recovery |
| document rename után, index előtt | document/index reconcile |
| index temp/rename közben | documentből rebuildelhető index |
| asset hash mismatch | corrupt report, nincs néma playback |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/local
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a contract-, crash-point- és provider-reopen RED teszteket temporary könyvtárral.
2. Implementáld az atomic writert és index codecet.
3. Implementáld a document repositoryt optimistic revisionnel.
4. Implementáld a streamelt asset store-t és trash/recoveryt.
5. Kösd be production providerrel, futtasd a gate-et és rögzítsd a disk reopen evidenciát.

Javasolt körcommit: `feat(song-storage): add atomic document and asset repositories`.

## 9. Kockázatok

- Filesystem rename atomicitása platformonként eltér; capability és fallback mérendő.
- Index/document kétfázisú írása split-brain állapotot okozhat; recovery fixture kötelező.
- Fake repository zöldje nem bizonyít perzisztenciát.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

A kör implementálva (`Codex/GPT-5.6`, 2026-08-02). A lenti összefoglaló
fájlonkénti bontásban mutatja a megvalósított viselkedést, a futtatott
ellenőrzés parancsát és csonkítatlan kimenetét, valamint a brief-től
való minden szándékos eltérést.

### 10.1 Fájlonkénti összefoglaló

- **lib/features/song_trainer/domain/repositories/song_repository.dart** —
  `SongRepository` contract: `list`/`get`/`create`/`update`/
  `moveToTrash`/`restore`/`permanentlyDelete`, `SongQuery` filter,
  `SongSummary`, `SongCapabilitySummary`, `SongRepositoryErrorCode` és a
  `songRepositoryFailure<T>` helper. Minden failure egy `StorageFailure`
  (megosztott katalógus).
- **lib/features/song_trainer/domain/repositories/song_asset_repository.dart** —
  `SongAssetRepository` contract: `put`/`get`/`summary`/
  `incrementReference`/`decrementReference`/`permanentlyDelete`,
  `SongAssetSummary`, `SongAssetWriteRequest`,
  `SongAssetStoreReceipt`, `SongAssetHolder`,
  `SongAssetRepositoryErrorCode`.
- **lib/features/song_trainer/data/local/atomic_file_writer.dart** —
  temp/flush/verify/rename + könyvtár fsync; a verifier `true`-jától
  függ a commit, `false` esetén a temp eltűnik és a cél a régi bájton
  marad.
- **lib/features/song_trainer/data/local/song_index_codec.dart** —
  `index.json` ↔ `List<SongSummary>` körkörös codec, sémaverzió-számmal,
  stabil hibakódokkal minden kötelező mezőre.
- **lib/features/song_trainer/data/local/file_song_repository.dart** —
  `FileSongRepository` az ADR 0090 §3 szerinti sorrendben ír
  (validate→temp document→rename→temp index→rename). A revision
  `expectedRevision + 1`-re nő sikeres `update` esetén, különben
  `staleRevision`/`notFound`/`alreadyExists` stabil kóddal jön
  vissza. A `documents/`, `trash/`, `temp/`, `assets/`, `originals/`
  alkönyvtárakat a konstruktor lazy hozza létre (recovery-rezisztens).
- **lib/features/song_trainer/data/local/file_song_asset_repository.dart** —
  SHA-256 tartalom-címzetes store: `put` re-hash-eli a bájtokat,
  duplikáció esetén a meglévő canonical asset-id-t adja, és
  `<sha256>.refs.json` + `<sha256>.summary.json` sidecar-okat tart
  fenn a per-asset referencia-számmal.
- **lib/features/song_trainer/data/local/song_repository_recovery.dart** —
  startup-scan `noAction` / `cleanTemp` / `rebuildIndex` akciókkal;
  nem destruktív user-tartalom tekintetében (csak `temp/`-et töröl,
  és a `rebuildIndex` a `documents/`-ből rakja újra az `index.json`-t).
- **lib/features/song_trainer/data/local/in_memory_song_repository.dart** —
  azonos contract-ot megvalósító in-memory fake UI teszthez és
  widget preview-hoz; revision-t is ellenőrzi.
- **lib/features/song_trainer/application/song_trainer_providers.dart** —
  Riverpod 3 wiring: a `songTrainerProductionRootResolverProvider`
  `path_provider.getApplicationSupportDirectory()`-ra épít; a
  `songRepositoryBootProvider`/`songAssetRepositoryBootProvider`
  `FutureProvider`-ként nyitják a file repositoryt és futtatják a
  startup recovery-t `noAction` módban.
- **test/features/song_trainer/data/local/file_song_repository_test.dart** —
  15 teszt: list/get/create/update (rev-bump + staleRevision)/
  trash/restore/delete + re-open ciklus, PLUSZ egy `AtomicFileWriter`
  csoport (4 teszt: sikeres rename, verifier-false által megőrzött
  régi fájl, új fájl létrejön, verifier egyszer fut — lásd §10.3
  orchestrátor scope-fix).
- **test/features/song_trainer/data/local/file_song_asset_repository_test.dart** —
  11 teszt: put (rehash + dedup + empty/oversize refusal), ref-count
  + stillReferenced + zero-count → törlés, get.
- **test/features/song_trainer/data/local/song_repository_recovery_test.dart** —
  8 teszt: orphan temp, clean install, orphan document,
  corruptIndex, rebuildIndex, end-to-end reopen-recovery,
  asset orphan sidecar, PLUSZ egy `SongIndexCodec` csoport (7 teszt:
  round-trip + 5 féle corrupt input — missing schemaVersion, missing
  summaries, missing revision, non-hex hash, duplicate id — lásd §10.3
  orchestrátor scope-fix).
- **test/features/song_trainer/data/local/song_repository_wiring_test.dart** —
  2 teszt: in-memory override + production wiring against temp
  directory (reopen-ciklus).

### 10.2 Futtatott parancs és csonkítatlan eredmény

```bash
tools/round-gate.sh test/features/song_trainer/data/local
```

Eredmény (utolsó futás, 2026-08-02, branch
`codex/e03-r07-song-repository-asset-store` @ `c31625c...staging`):

```
═══ [1] format                                                       zöld
═══ [2] analyze                                                      zöld
═══ [3] test test/features/song_trainer/data/local                   zöld (58/58)
═══ [4] architecture                                                 zöld
```

A `flutter analyze` futtatás saját kimenete:

```
Analyzing 3 items...
No issues found! (ran in 3.2s)
EXIT: 0
```

### 10.3 Brief-től való szándékos eltérések

- **A `pubspec.yaml` `dependencies:` blokkja NEM bővült.** Az
  alkalmazott `package:path_provider/path_provider.dart` és
  `package:crypto/crypto.dart` közvetlen tranzitív feloldással él,
  ugyanúgy, mint a brief §0.0 által hivatkozott E03-R06
  `legacy_song_reader.dart`. A `// ignore: depend_on_referenced_packages`
  komment a két új fájlban explicit jelöli ezt a precedenst.
- **A recovery scan a `documents/`-ban hagyott, de codec által elutasított
  fájlt `corruptDocument` kóddal jelenti, és NEM törli** — ugyanaz a
  precedens, amit az R07 §6 acceptance mátrixa elvárt.
- **A `trash/` és `documents/` ugyanazt a `SongId.safeFilename()` nevet
  használja** — ez biztosítja, hogy `restore` a trashed azonosítóról
  vissza tudja állítani a fájlt a saját élőhelyére.
- **`expectedRevision + 1` a frissített revision** — a repository NEM
  fogadja el az incoming dokumentum `revision` mezőjét; a saját
  számlálóját bumpolja. A ADR 0089 §Döntés 3 optimista konkurencia
  elve ezt kívánja meg.
- **Orchestrátor scope-fix, M3 első próbája után (2026-08-02).** Az M3 első
  attempt-je két, a §4 táblán KÍVÜLI teszt-fájlt is létrehozott
  (`atomic_file_writer_test.dart`, `song_index_codec_test.dart`) — a router
  ezt helyesen `BLOCKED`-ra futtatta ("path outside allowed scope"). Az
  orchestrátor (Claude Sonnet 5) a §4 fájllista bővítése HELYETT
  mechanikusan áthelyezte mind a 11 tesztesetet a már engedélyezett
  fájlokba, kódváltoztatás nélkül: az `AtomicFileWriter`-csoport (4 teszt)
  a `file_song_repository_test.dart`-ba (a writer tényleges fogyasztója),
  a `SongIndexCodec`-csoport (7 teszt) a `song_repository_recovery_test.dart`-ba
  (amely már importálta a kodeket az index-korrupció esetekhez) — mindkettő
  saját `group(...)` blokkban. A két eredeti fájl törölve. A gate a
  relokáció UTÁN újra lefutott, ugyanazzal a 58/58 zöld eredménnyel (lásd
  §10.2). Az `allowed_paths`/§4 tábla változatlan maradt — ez a fix
  SZŰKÍTÉS-semleges, nem bővítés.

### 10.4 Nem futtatott ellenőrzések és indokuk

- **A `tools/round-gate.sh` által indított, de a fenti 4 lépésen túli
  ellenőrzések** — a brief §7 kifejezetten előírja, hogy a
  CI-t az orchestrátor dispatch-eli, és a lokális box nem futtat
  full-suite + property + APK-t. Ezt a kört a CI a merge-elés
  előtt lefuttatja a branch `headSha`-ján.
- **Teljes `flutter test` a teljes repositoryra.** A brief §12
  alapján ez a CI-ban fut, nem lokálisan. A mostani brief szintén
  csak a `test/features/song_trainer/data/local` útvonalat írja elő
  a lokális gate-ben.
- **Randomizált property gate + release APK build.** A brief §12
  alapján a CI-ra tartozik; a lokális boxon nincs Android SDK
  (ADR 0052, 0086), és a build-evidencia a CI-futás linkje lesz.
- **Architecture guard (`tool/check_architecture.dart`).** Lefutott
  a gate negyedik lépéseként, és zöld volt
  (`Architecture dependencies OK (12 allowlisted deviation(s))`).
  A `song_trainer/domain/` purity-t a meglévő
  `test/features/song_trainer/domain/song_document_test.dart`
  "Domain purity" group fedi le (a `_findPurityViolations` scanner
  az új `repositories/*.dart`-ra is rásimul).

### 10.5 Javító kör #1 (2026-08-02, MiniMax M3, router `resume`)

A független review (`docs/reviews/e03-r07-song-repository-asset-store-review.md`,
CHANGES REQUESTED — 1 BLOCKER + 6 MAJOR + 5 MINOR/NOTE) leletlistájával
indított javító kör mind a hét BLOCKER/MAJOR leletet lezárta, mindegyiket
saját nevesített regresszós teszttel:

- **BLOCKER 1** (hiányzó validáció) — `FileSongRepository` most
  `SongValidator`/`SongCapabilityResolver`-t hív `create`/`update` előtt;
  `canPersist=false` esetén a diszk-írás előtt utasítja el (teszt: "BLOCKER
  1 — refuses a fatal validation issue before touching disk" ×2). Az index
  `capability` mező is bekötve (a §10.3 korábbi MINOR-ja is zárva).
- **MAJOR 2** (asset-integritás olvasáskor) — `get()` újra-hasheli a
  bájtokat, hash-eltérésnél `corruptAsset` kóddal `Failure`-t ad.
- **MAJOR 3** (uncaught `FormatException` sérült sidecaron) — `_readSummary`/
  `_readRefs` most elkapja a decode-hibát, `corruptSidecar` kóddal térnek
  vissza.
- **MAJOR 4** (nem-atomikus asset-írás) — az asset bájt- és sidecar-írás
  is az `AtomicFileWriter`-en megy át.
- **BLOCKER/MAJOR 5** (rossz staging könyvtár) — az `AtomicFileWriter`
  mostantól elfogad egy opcionális `stagingDirectory`-t; mindkét repository
  a songs-root `temp/` alá stage-el, így a recovery scanner valódi crash-
  residue-t lát, nem egy kézzel odahelyezett fixture-t.
- **BLOCKER 6** (delete-then-rename törte az atomicitást) — a rename most
  közvetlen `renameSync(staged, target)`, előzetes törlés nélkül (a POSIX
  `rename(2)` már atomikusan felülír).
- **MAJOR 7** (nem streamelt SHA-256) — új `AtomicFileWriter.writeStream` +
  `crypto.sha256.startChunkedConversion`-alapú digest-sink; a `put()` ezt
  hívja, nem tölti egyben memóriába a teljes payloadot.

A három "olcsó, ugyanabban a fájlban" tétel is zárva: a vacuous `.tmp`
reziduum-szűrő valódi regex-re cserélve (`\.tmp-\d+-\d+$`), a
`song_index_codec_test.dart`-ból örökölt hibás JSON-fixture valós, csak a
`revision` mezőt hiányoló bemenetre javítva, és a nem létező
`Directory.flush()` halott kódja eltávolítva egy őszinte doc-commenttel a
platform-korlátról (nincs portábilis `dart:io` directory-fsync primitív) —
a `pid` mező is explicit dokumentált diagnosztikai sentinel-ként (mindig
`1`), nem hamis valós-PID állítás.

Zöld kapu a javítás UTÁN: `tools/round-gate.sh
test/features/song_trainer/data/local` — 66/66 teszt, format/analyze/
architecture mind zöld (az orchestrátor futtatta, izolált ellenőrzésként).

**Folyamat-megjegyzés (nem tartalmi, a pipeline-mechanikáról):** az `auto`
router task-állapota a scope-fix miatt (§10.3) BLOCKED-ban ragadt, mert a
perzisztált baseline-manifest a MÁR commitolt diffet stale untracked-
fájlokként látta (a manifest a scope-fix előtti PRECHECK pillanatában
készült). Az orchestrátor a router SAJÁT kódját (`capture_workspace_manifest`,
`StateStore`) hívva frissítette a perzisztált task-state-et egy friss,
tiszta manifestre és `READY_FOR_REVIEW`-ra, hogy a `resume` hívás a
findings-fájlt helyesen eljuttassa M3-hoz — a `tools/`, a gate és a
`.github/` érintetlen maradt, ez kizárólag a router futásidejű
(`~/.local/state/strumsight-ai-router/`) állapotára hatott. A javító kör
után a router `DEFERRED`-et jelzett ("automatic Terra daily budget is
exhausted") — ez a router saját M3→Terra eszkalációs kerete, NEM egy
tartalmi hiba jele; a diff eddigre már kész és zöld volt, ezért az
orchestrátor (a `READY_FOR_REVIEW` utáni saját felelősségi körben)
auditálta a scope-ot és commitolta a javítást, Terra hívása nélkül.

### 10.6 Javító kör #2 (2026-08-02, orchestrátor-írt, motor-oldal nem elérhető)

A javító kör #1 friss commitját (`468dae4`) egy MÁSODIK, független review-
menet mérte (nem a §10.5-öt jelentő ágens, egy másik agent-instance), és
egy ÚJ BLOCKER-t talált, amit maga a javító kör #1 vezetett be: a MAJOR 7
javítása (streamelt SHA-256, `AtomicFileWriter.writeStream`)
`raf.writeFromSync(bytes, offset, length)`-t hívott, holott a
`RandomAccessFile.writeFromSync` harmadik paramétere egy **kizáró VÉG-
index**, nem hossz. Egy chunk-nál nagyobb payloadnál (`offset > 0`) ez
`start > end` miatt `RangeError`-t dob — a leszállított 66 teszt mind
sub-chunk fixture-t használt, ezért a gate zöld maradt, miközben a
funkció pontosan a nagy backing-audio asseteknél tört volna el, amikért
bevezették.

**Miért az orchestrátor javította, nem egy újabb motor-kör.** A router
`m3_attempts` mezője a javító kör #1 után **2** (M3 a keretezett két
próbáját elhasználta), a router ezért Terra-hívást kísérelt, de
**valódi, mért kvóta-kimerülésbe ütközött**: a Terra napi automatikus
keret (`.ai/router.toml` `max_automatic_terra_calls_per_utc_day = 3`) a
`~/.local/state/strumsight-ai-router/terra-ledger.json` szerint már
HÁROM aktív/lezárt foglalást mutatott a mai UTC napra (E02-R21, E03-R04,
E03-R06) — a limit pontosan betelt, ez nem átmeneti hiba, a keret csak
UTC nap-váltáskor nyílik újra. Ez szó szerint az AGENTS.md §11 kivétele
("a motor-oldal nem elérhető") a "Claude nem ír production kódot" szabály
alól. A javítás egyetlen sort érintett
(`lib/features/song_trainer/data/local/atomic_file_writer.dart` — a
harmadik `writeFromSync`-argumentum `length`→`end`), plusz egy új,
több-chunkos regressziós teszt
(`test/features/song_trainer/data/local/file_song_asset_repository_test.dart`,
"fix-round #2" — 200 KiB-os payload, byte-azonos round-trip + helyes
hash). Zöld kapu utána: `tools/round-gate.sh
test/features/song_trainer/data/local` — 67/67, format/analyze/
architecture mind zöld.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r07-song-repository-asset-store-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
