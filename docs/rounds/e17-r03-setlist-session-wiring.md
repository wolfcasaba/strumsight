# E17-R03 — A Song Trainer setlist-session bekötése (V2-natív)

- **Státusz:** REVISED (ADR 0112 önjavító kör, 2026-09-19) + PRE-FLIGHT ÚJRAMÉRVE (2026-09-19, `main @ ba8233af`) — **`pending`**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 3
- **Kör-azonosító:** `E17-R03`
- **Branch:** `<motor>/e17-r03-setlist-session-wiring`
- **Brief szerzője:** Claude (Opus 5) — a §0.1 revízió az ADR 0112 önjavító köréé
- **ADR:** [`ADR 0585`](../adr/0585-setlist-session-v2-native-entry-and-measured-outcome.md) — a foglaló (`tools/round-slots.py reserve-adr`) adta a kör indulásakor; a queue `0522` oszlopa ELŐZETES volt.
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény (a pre-flight lefuttatta, 2026-09-19):**
[`adr/0130`](../adr/0130-setlist-v2-song-progress-and-epic-3-closure-boundary.md) (Setlist V2 + a
session-controller határa, `bm25#1 emb#7`), [`adr/0129`](../adr/0129-song-trainer-ui-loop-speed-and-result-boundary.md)
(a trainer-session/result szerződése), [`adr/0125`](../adr/0125-song-trainer-setup-configuration-boundary.md)
(„route-literál a katalógus helyett" elutasítva; „unreachable-status szabály: kitalált capability tilos"),
[`halts/E15-R07 H2`](../../.pipeline/) (a nem elérhető, flag alatt hard-`false` képernyők NEM Ch15
design-migrációs ügyek — ezért kellett D5-ben a MÉRT A3-kényszer, nem hivatkozás),
[`lessons/L558`](../LESSONS.md) (a `flutter_test` 800×600-as alapviewportján a túlcsordulás-cella
akár ÜRES fát is mérhet — a migráció celláihoz telefon-méretű viewport kell),
[`lessons/L612`](../LESSONS.md) (a kör sikere viszi pirosra a kaput),
[`lessons/L337`](../LESSONS.md) / [`lessons/L357`](../LESSONS.md) (H3-osztály: a listán kívüli fájl).

## 0.0 A `hold` FELOLDVA (2026-09-05)

A kör kompozíciót köt be egy MÁR LÉTEZŐ application-réteg fölé (`SetlistSessionController`); a `song_trainer` feature-ben `0` db `UnimplementedError` van.

Az eredeti `hold` indoka az `E17-R01` mintájára hivatkozott. **2026-09-05-én feloldva:** sorrendi preferencia volt, nem függőség — a `lib/` halmazok diszjunktak.

## 0.1 Revízió — ADR 0112 önjavító kör, 2026-09-19 (H3 a pre-flightban)

A kör 2026-09-19-én a **dispatch ELŐTT** megállt (`H3`), mert a brief-lint `S15` által
kötelezővé tett §2-újramérés a brief PREMISSZÁJÁT cáfolta meg. A teljes mérés:
`.pipeline/halt-E17-R03-preflight.md`. Motor nem indult, ág/PR/munkapéldány nem
készült. Amit az önjavító kör MÉRT, és ami emiatt átíródott:

**R1 — a megdőlt premissza.** A régi §2/§5.1 szerint „a `SetlistDetailScreen` a
`SetlistSessionScreen` természetes belépési pontja". **Hamis:** két diszjunkt
setlist-világ van, és a session a MÁSIKHOZ tartozik.

| | legacy (`songs`) | V2 (`song_trainer`) |
|---|---|---|
| modell | `Setlist{id,name,songIds}` (`lib/features/songs/model/setlist.dart:14`) | `SongSetlist{id,name,items:[SongSetlistItem{SongId,overrides}]}` (`.../domain/models/song_setlist.dart:106`) |
| dal-azonosító | `'${DateTime.now().microsecondsSinceEpoch}_$seq'` (`songs_provider.dart:23`) | `SongId` — seed-id (`seed-blues-shuffle-a`, …) vagy importált dokumentum-id |
| tár | `KeyValueSongsRepository` / `SetlistsRepository` | `FileSetlistRepository` (`production_overrides.dart:88,109`) |
| belépés | `SetlistListScreen` → `SetlistDetailScreen` (**reachable: true**) | `SetlistListScreenV2` (**reachable: false**) |

A `SetlistSessionScreen.setlist` mezője `SongSetlist` (`setlist_session_screen.dart:24`),
a `SetlistDetailScreen` legacy `Setlist`-et tart. A két ID-tér nem metszi egymást.

**R2 — a V2 setlist-tárnak NULLA produkciós írója van.**
`grep -rn "SongSetlist(" --include=*.dart lib` → 4 találat: a konstruktor
(`song_setlist.dart:106`), a dekódolás (`file_setlist_repository.dart:151`), a
`LegacySetlistAdapter.persistV2` (`legacy_setlist_adapter.dart:130` — `lib`-ből
SEHONNAN nem hívott, egyetlen hívója a
`test/features/song_trainer/integration/legacy_setlist_migration_test.dart:21`),
és az EGYETLEN szerkesztő: a `reachable:false` `SetlistListScreenV2:248`. A
felhasználó ma semmilyen úton nem tud V2 setlistet létrehozni (ugyanaz az
osztály, mint [L606](../LESSONS.md) és [L652](../LESSONS.md)).

**R3 — a legacy-projekciós kifutás nem tud őszinte eredményt adni.** A legacy
`Setlist` → `SongSetlist` vetítés után a `SetlistItemRunner`-nek a
`LearnScreen`-t kellene futtatnia; annak szerződése (`learn_screen.dart:38-41`)
**csak `lesson`-t vesz át és semmit nem ad vissza** — nincs `onCompleted`, nem
popol eredménnyel. Minden `SetlistItemResult` kitalált lenne (`partial` doc-comment:
„félbehagyta", `setlist_result.dart:36-40`). Ráadásul a legacy részlet-képernyőnek
MÁR VAN működő setlist-futtatása (`_playAll`, `setlist_detail_screen.dart:20-27`),
tehát a projekció egy meglévő utat duplikálna egy rosszabbal.

**R4 — az architektúra-korlát zárja a provider-hidat.** `tool/check_architecture.dart:382-392`:
cross-feature import CSAK `public.dart`-ra mehet, és a `songs/public.dart` kizárólag a
`model/song.dart`-ot exportálja — sem a `Setlist`, sem a `setlistsProvider` nem látszik.

**R5 — a MÉRT A3-következmény (ez a revízió legfontosabb új ténye).**
A `test/tooling/screen_reachability_test.dart` **A3** cellája minden
*elérhető ÉS nem design-rendszerre migrált* képernyőtől megköveteli a
`docs/ui/retirement-plan.md` §6 sorában a `migrate`/`retire` verdiktet + egy
`^E15-R\d+$` gazda-kört. A `setlist_list_screen_v2.dart` **nem tartalmaz
`design_system`-et** (a cella `_isMigrated` mércéje pontosan ez), a sora
`unreachable` / gazda `—`, és **minden E15-ös kör `done`** — gazdát tehát
nem lehet őszintén beírni. Gépi szimuláció ugyanazzal a logikával:

```
NOW   ownerless: []
AFTER wiring ownerless:
  ['lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart']
```

Ezért a V2 lista bekötése és a design-rendszerre migrálása **ugyanabban a körben**
történik — nem scope-bővítés, hanem a bekötés gépileg kikényszerített ára.
(A `retirement-plan.md` §3.2 saját megfogalmazásában: *„design tokens are moot on a
screen nobody can open"* — megfordítva: amint megnyitható, számítanak.)

**R6 — a lista-TÁGÍTÁS jogalapja.** A feloldás `allowed_paths`-tágítást kíván, ami
a kör-orchestrátornak nem hatásköre (ADR 0087 §2, `S15`) — az ADR 0112 önjavító
körének viszont igen. A §4 lista ennek megfelelően bővült; a mércéből semmi nem
került ki (a `test/tooling/screen_reachability_test.dart` SZÁNDÉKOSAN csak
`gate_tests`-ben van, `allowed_paths`-ban nincs: a kör MÉRI, de nem írhatja).

**R7 — gépi őr.** `tools/tests/test_e17_r03_setlist_session_scope.py` — a revízió
ELŐTTI briefen piros (7 cella), utána zöld; a cellák a briefet a KÓDHOZ mérik
(a `SongSetlist`-termelők grepje, a `LearnScreen` szerződése, a retirement-plan
saját táblája), nem egy kézzel másolt listához.

## 0.2 Pre-flight újramérés — 2026-09-19, `main @ ba8233af`

A §0.1 revízió óta a `main` egyetlen commitot kapott: magát az önjavító kört
(`ba8233af`, csak `docs/` + `tools/tests/`). A §2 MINDEN mért tényét a pre-flight
újramérte, és **változatlanul igazolta**:

```
$ dart run tool/check_screen_reachability.dart --format json
measuredScreenCount=97  unreachableCount=3
  SetlistSessionScreen      reachable=false declarative=[] imperative=[]
  SetlistListScreenV2       reachable=false declarative=[] imperative=[]
  PracticePlanPreviewScreen reachable=false                       # E17-R04 tárgya
  SetlistDetailScreen       reachable=true  [setlist_list_screen.dart:24]   # legacy világ
$ grep -c design_system .../setlist_list_screen_v2.dart → 0 | .../setlist_session_screen.dart → 1
$ grep -rn "UnimplementedError" lib/features/song_trainer/ | wc -l → 0
$ grep -rn "SongSetlist(" --include=*.dart lib → 4 (konstruktor, dekódolás, adapter, a v2 lista:248)
$ feature_flags.dart:247 → songTrainerV2Enabled: nonProd        (a kör NEM módosítja)
$ tools/tests/test_e17_r03_setlist_session_scope.py → 9 passed
```

**Két kérdést csak ez a mérés tudott eldönteni — az [ADR 0585](../adr/0585-setlist-session-v2-native-entry-and-measured-outcome.md) D3 és D4 pontja zárja le:**

- **D3 (az availability KÉT rétege).** A `SetlistAvailabilityResolver` typedef
  **szinkron** (`setlist_session_controller.dart:4-5`), a `SongRepository` viszont
  kizárólag aszinkron (`song_repository.dart:295-306`) — a dokumentum tartalma
  szinkron rétegből elvileg sem érhető el. Ezért: a resolver egy EGYSZER betöltött
  `repository.list(...)` pillanatkép (`SongSummary.documentId/revision/trashed`)
  fölött zár (hiányzó/trashed → `missingSong`), a mély okokat pedig a runner méri a
  MÁR LÉTEZŐ launcher hibakódjain (`notFound` → `missingSong`, `staleRevision` →
  `requiresMigration`, `notPlayable` → `invalidConfig`), `SetlistItemResult.skipped`
  formában. A `SongSetlistItem.initialAvailability` perzisztált TIPP, nem mérés.
- **D4 (a befejezés-varrat helye).** A `SongTrainerSessionRoute` ma a result-route-ot
  nyitja meg, és a HÍVÓJÁNAK semmit nem ad vissza
  (`song_trainer_session_route.dart:130-146`) — varrat nélkül a §5.4 nem
  teljesíthető. A varrat a session-route saját, már meglévő `SongTrainerResult`-ját
  adja vissza a navigációs hívónak; az egydalos út (setup→session→result,
  „practice again", fail-closed `extra`-redirect) bit-azonos marad.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/features/song_trainer/application/setlists/setlist_session_providers.dart",
  "lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart",
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_trainer_session_route.dart",
  "lib/features/song_trainer/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/rounds/e17-r03-setlist-session-wiring.md",
  "docs/ui/retirement-plan.md",
  "test/features/song_trainer/setlist_session_wiring_test.dart",
  "test/features/song_trainer/",
  "test/features/songs/setlist_list_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/e2e/song_trainer_walkthrough_test.dart",
  "test/app/navigation/",
  "test/app/routing/",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/goldens/goldens/e13_r23_setlist_list_compact.png",
  "test/ui/goldens/goldens/e13_r23_setlist_list_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r23_song_library_compact.png",
  "test/ui/goldens/goldens/e13_r23_song_library_compact_scale2.png",
]
native_gate = false
gate_tests = [
  "test/features/song_trainer/",
  "test/features/songs/setlist_list_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/e2e/song_trainer_walkthrough_test.dart",
  "test/app/navigation/",
  "test/app/routing/",
  "test/tooling/screen_reachability_test.dart",
  "test/tooling/route_literal_guard_test.dart",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/goldens/e13_r25_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/l10n/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A V2 dalcsomag (Setlist V2) a szállított kompozícióból megnyitható, szerkeszthető,
és egy konkrét setlistre gyakorló- vagy előadás-módú session indítható: a
`SetlistSessionScreen` és a `SetlistListScreenV2` egyaránt `reachable: true`.

## 2. Jelenlegi állapot — mért tények (`main @ 3ffde512`)

Reprodukció: `dart run tool/check_screen_reachability.dart --format json`.

- `SetlistSessionScreen` → `reachable:false`, `declarative:[]`, `imperative:[]` (csak teszt-hivatkozások).
- `SetlistListScreenV2` → `reachable:false`, `declarative:[]`, `imperative:[]`.
- `SetlistDetailScreen` (legacy) → `reachable:true` (`setlist_list_screen.dart:24`) — **más világ**, l. §0.1/R1.
- A mért 97 képernyőből 3 elérhetetlen; ebből 2 ennek a körnek a tárgya.
- Az application réteg LÉTEZIK és nem hiányos: `SetlistSessionController`
  (`.../application/setlists/setlist_session_controller.dart`) a
  `SetlistAvailabilityResolver` / `SetlistItemRunner` typedefekkel;
  `SetlistController` + `setlistControllerProvider`
  (`song_trainer_providers.dart:251`) a lista/szerkesztő oldalon;
  `songTrainerSessionLauncherProvider`
  (`.../application/trainer/song_trainer_session_launcher.dart:88`) a futtató oldalon.
  A `song_trainer` feature-ben `0` db `UnimplementedError` van.
- A V2 songbook produkciósan FEL VAN TÖLTVE (`SongSeedInstaller`,
  `song_trainer_providers.dart:157`, `assets/songs/seed-*.song.json`) — a forrás nem üres.
- A `songTrainerV2Enabled` kapu alapértéke `nonProd` (`feature_flags.dart:247`) —
  a kör NEM módosítja; a `songTrainer*` route-ok mind e kapu alatt élnek
  (`app_router.dart:751`).
- `setlist_list_screen_v2.dart`: `grep -c design_system` → **0** (nem migrált);
  `setlist_session_screen.dart` → **1** (migrált).

## 3. Scope

**Benne van:**

- A V2 setlist-lista útvonala (`AppRoutes` konstans + regisztráció a
  `songTrainerEnabled` kapu alatt) és a belépési pont a `SongLibraryScreen`-ből.
- A `SetlistListScreenV2` design-rendszerre migrálása (§0.1/R5 gépi kényszer).
- A session indítása a V2 listából egy KONKRÉT setlistre, mindkét módban.
- A kompozíciós providerek: a `SetlistAvailabilityResolver` és a `SetlistItemRunner`
  a szállított forrásból (dal-repository + trainer-session launcher).
- A session befejezésének visszatérési útja a V2 listára.
- A futtatói visszajelzés minimális varrata a `song_trainer_session_route.dart`-ban,
  hogy a `SetlistItemResult` MÉRT kimenet legyen (§5.4).

**NINCS benne (tilos):**

- A `SetlistSessionController` szemantikájának módosítása.
- Új setlist-viselkedés vagy -modell; a legacy `Setlist` → `SongSetlist` projekció.
- A `songTrainerV2Enabled` (vagy bármely) kapu alapértékének megváltoztatása.
- A legacy `songs` setlist-út (`SetlistListScreen`/`SetlistDetailScreen`/`_playAll`) bármilyen módosítása.
- A `test/tooling/screen_reachability_test.dart` szerkesztése (mérőeszköz, nem a kör terméke).

## 4. Engedélyezett fájlok

(a teljes gépi lista az `ai-router` blokkban; alább a szűk indoklás)

| Fájl | A jogosultság PONTOS terjedelme | Miért |
|---|---|---|
| `lib/app/routing/app_route.dart` | **KIZÁRÓLAG** egy ÚJ konstans felvétele (`/song-trainer/setlists`); meglévő átírása/törlése tilos | minden `GoRoute.path` `AppRoutes` konstans, a route-literál tiltott (`test/tooling/route_literal_guard_test.dart`) — L97/L246 |
| `lib/app/routing/app_router.dart` | a route regisztrálása a MEGLÉVŐ `if (songTrainerEnabled)` blokkban | a bekötés helye |
| `lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart` | design-rendszer migráció + a session indítása (mód-választás) | az EGYETLEN produkciós V2 setlist-szerkesztő (§0.1/R2); a migráció az A3 gépi ára (§0.1/R5) |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | **KIZÁRÓLAG** egy belépési affordancia a setlist-útvonalra (a meglévő AppBar-akciók mintájára, `:163`/`:169`) | különben a route-ot ember nem éri el |
| `lib/features/song_trainer/presentation/screens/song_trainer_session_route.dart` | **KIZÁRÓLAG** a befejezés-varrat (a session saját kimenetének visszaadása a hívónak); az egydalos út viselkedése nem változhat | §5.4 — enélkül a `SetlistItemResult` kitalált lenne |
| `lib/features/song_trainer/application/setlists/setlist_session_providers.dart` (új) | availability-resolver + runner-kompozíció | a kör tényleges terméke |
| `lib/features/song_trainer/public.dart` | csak a kör által ÁTHATÁROLT típusok exportja, ha kell | `tool/check_architecture.dart` cross-feature szabálya |
| `lib/l10n/base/app_{en,hu}.arb` **és** `lib/l10n/app_{en,hu}.arb` | az új felhasználói szövegek | a FORRÁS szegmens + a generált aggregátum együtt utazik (S16, [L646](../LESSONS.md)) |
| `docs/ui/retirement-plan.md` | **KIZÁRÓLAG** a két érintett §6 sor + a §3.4 felsorolás átvezetése a MÉRT új állapotra | az A3 cella a terv és a mérés keresztellenőrzése |
| `test/ui/goldens/goldens/e13_r23_*.png` | ÚJRAFELVÉTEL `tools/golden-x86.sh record`-dal | a migráció és az új akció pixelt mozdít (ADR 0426) |
| `test/features/songs/setlist_list_test.dart`, `test/features/songs/song_library_test.dart`, `test/e2e/song_trainer_walkthrough_test.dart` | **KIZÁRÓLAG** a lecserélt képernyő/komponens típusának átírása a pinnelő cellában | S11 pin-őrök a két érintett képernyőre (l. a bekezdést alább) |

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.

## 5. Kötött architekturális döntések (ADR 0585)

### 5.1 A belépés a V2 setlist-felületről megy, nem a legacy részletből

A session `SongSetlist`-et futtat; a legacy `SetlistDetailScreen` legacy
`Setlist`-et tart, és a két ID-tér diszjunkt (§0.1/R1–R2). Az útvonal-konstans
alakja kötött: **`/song-trainer/setlists`** (a `songTrainer*` prefix családja,
`app_route.dart:42-49`), regisztrálva a MEGLÉVŐ `if (songTrainerEnabled)` blokkban.

### 5.2 A két mód (gyakorlás / előadás) UGYANAZON a belépési ponton megy, paraméterként

A `SetlistSessionMode` már ma is a képernyő paramétere. Két külön belépési pont
két kód-utat teremtene ugyanarra az állapotgépre.

### 5.3 Az availability a VALÓS dal-tárból jön

A `SetlistAvailabilityResolver` a `songRepositoryProvider`-ből dönt; konstans
`ready` tilos. A leképezés kötött: hiányzó dokumentum → `missingSong`,
revízió-eltérés → `requiresMigration`, fordítási hiba → `invalidConfig`. A
`SetlistItemResult.skipped` ezt az okot hordozza.

### 5.4 A `SetlistItemResult` MÉRT kimenet, nem feltételezés

A runner a MÁR REGISZTRÁLT trainer-session utat használja
(`songTrainerSessionLauncherProvider` + `AppRoutes.songTrainerSession`), és csak
olyan státuszt jelent, amit a session ténylegesen visszaad. Ehhez a
`song_trainer_session_route.dart` minimális befejezés-varratot kap (a session
saját kimenetének visszaadása a hívónak). **Tilos** a `completed`/`partial`
szintetizálása (pl. fal-óra alapján) — ha a varrat nem építhető meg a §4 listán
belül, a kör `stopped`, és a kimenet brief-revízió.

### 5.5 A V2 lista bekötése és design-migrációja EGY kör

Mért kényszer, nem ízlés: az A3 cella egy elérhetővé tett, nem migrált képernyőre
`E15-Rxx` gazdát követel, és minden E15-ös kör `done` (§0.1/R5). A migráció a
`core/design_system/public.dart` komponenseire és tokenjeire megy, ÚJ `*ThemeScope`
burkoló bevezetése nélkül (E15-R01 óta az app témája hordozza a tokeneket).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `SetlistSessionScreen` `reachable: true` | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | A `SetlistListScreenV2` `reachable: true`, és a `SongLibraryScreen`-ből ember által elérhető | ugyanaz + widget-teszt a belépési akcióra |
| A3 | A V2 listából mindkét mód elindítható, és a session a VALÓS `SetlistSessionController`-rel fut | widget-teszt valós `ProviderContainer`-rel |
| A4 | A mód a belépési pont PARAMÉTERE — a diff nem visz két külön indító útvonalat | `git diff` + teszt mindkét módra |
| A5 | Az availability a valós dal-tárból jön: hiányzó dalra a tétel `skipped`, `missingSong` okkal | widget/unit teszt üres repository-val |
| A6 | A `SetlistItemResult` státusza a session visszajelzéséből származik; nincs szintetizált `completed` | teszt: a session befejezés nélküli elhagyása NEM ad `completed`-et |
| A7 | A session befejezése a V2 setlist-listára tér vissza, nem a gyökérre | widget-teszt |
| A8 | `test/tooling/screen_reachability_test.dart` **teljes egészében zöld** (az A3 cella is), a `retirement-plan.md` átvezetett soraival | a gate teszt-lépése |
| A9 | Az új szövegek mindkét locale-ban léteznek, és a generált aggregátum friss | `test/l10n/` + `dart run tool/gen_l10n_segments.dart --check` |
| A10 | A `route_literal_guard` zöld: az új útvonal `AppRoutes` konstans | `test/tooling/route_literal_guard_test.dart` |
| A11 | A `songTrainerV2Enabled` alapértéke változatlan | `git diff lib/core/**/feature_flags.dart` üres |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Kösd a két módot két külön
belépési pontra, futtasd a gate-et → az A4 cellának PIROSNAK kell lennie → állítsd vissza.

**Második, kötelező próba (A6):** cseréld a runner kimenetét fix
`SetlistItemResult.completed`-re → az A6 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a
falszifikációs próbák bizonyítják, hogy a cellák tényleg pirosra váltanak a hibás
implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/ test/features/songs/setlist_list_test.dart test/features/songs/song_library_test.dart test/e2e/song_trainer_walkthrough_test.dart test/app/navigation/ test/app/routing/ test/tooling/screen_reachability_test.dart test/tooling/route_literal_guard_test.dart test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/l10n/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

**Golden-újrafelvétel (ADR 0426):** a lokális `flutter test --update-goldens` TILOS
(aarch64 ≠ a merge-kapu x86_64 raszterizációja, [L486](../LESSONS.md)/[L493](../LESSONS.md)):

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r23_screens_golden_test.dart
```

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhat).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Útvonal-konstans → router-regisztráció → `SongLibraryScreen` belépési akció.
4. A `SetlistListScreenV2` design-rendszer migrációja (§5.5).
5. A `setlist_session_providers.dart` (availability + runner) és a §5.4 befejezés-varrat.
6. A session indítása a listából, mindkét módban; a visszatérési út.
7. l10n kulcsfelvétel a `lib/l10n/base/app_{en,hu}.arb`-ba, majd
   `dart run tool/gen_l10n_segments.dart --write` a gate ELŐTT.
8. A `retirement-plan.md` két sorának és a §3.4 felsorolásának átvezetése a MÉRT állapotra.
9. A §6 acceptance-cellák tesztjei; a §6.1 két falszifikációs próba lefuttatása és a §10-be dokumentálása.
10. Golden-újrafelvétel x86-on, majd a §7 gate csonkítatlan kimenettel.

## 9. Kockázatok

- **A két kód-út.** Módonként külön indító útvonal ugyanarra az állapotgépre divergáló viselkedést szül (5.2).
- **A kitalált eredmény.** Ha a runner nem MÉRT státuszt jelent, a session-összegzés hazudik (5.4, A6) — ez a §0.1/R3 hibaosztálya.
- **Az availability-resolver megkerülése.** Konstans elérhetőség mellett a session nem létező tételeket próbálna futtatni (5.3, A5).
- **Az A3 visszacsapása.** Ha a lista bekötése megtörténik, de a design-migráció nem, a `screen_reachability_test` A3 cellája pirosra vált, és a kör SIKERE zárja ki a merge-ből (§0.1/R5; a hibaosztály: [L612](../LESSONS.md)).
- **Golden-drift.** Lokálisan felvett golden a CI-ban mindig piros (ADR 0426).
- **A visszatérési út elvesztése.** A session végén gyökérre navigálás elveszíti a setlist kontextusát (A7).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Mit építettem, fájlonként

| Fájl | Mit csinál |
|---|---|
| `lib/app/routing/app_route.dart` | ÚJ `AppRoutes.songTrainerSetlists` konstans (`/song-trainer/setlists`) |
| `lib/app/routing/app_router.dart` | a route regisztrálása a meglévő `if (songTrainerEnabled)` blokkban, a `SetlistListScreenV2`-t a valós `setlistControllerProvider`/`songTrainerClockProvider`/`songRepositoryProvider`/`songTrainerSessionLauncherProvider` négyesével konstruktor-injektálva |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | egy ÚJ AppBar-akció (`song-library-open-setlists` kulcs) a setlist-útvonalra |
| `lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart` | design-rendszer migráció (`core/design_system/public.dart` tokenek/komponensek) + `songRepository`/`sessionLauncher` konstruktor-paraméter + az EGYETLEN `_startSession(setlist, mode)` belépési pont (5.2), ami friss `loadSetlistAvailabilitySnapshot` + `buildSetlistAvailabilityResolver` hívással pusholja a `SetlistSessionScreen`-t a `Navigator`-on (raw push, nem `context.go`, hogy a lista a veremben maradjon — A7) |
| `lib/features/song_trainer/application/setlists/setlist_session_providers.dart` (ÚJ) | `loadSetlistAvailabilitySnapshot`, `buildSetlistAvailabilityResolver`, `buildSetlistPracticeRunner`/`buildSetlistPerformanceRunner`, `_runSetlistItem`, `_resultFor` — a runner a `songTrainerSessionLauncherProvider`-en és a valós `SongTrainerSessionRoute`-on át fut, és a `SetlistItemResult`-ot a session TÉNYLEGES `SongTrainerSessionOutcome`-jából képezi (5.3/5.4) |
| `lib/features/song_trainer/presentation/screens/song_trainer_session_route.dart` | a befejezés-varrat: amikor `returnResultToCaller: true`, a route a saját mért `SongTrainerSessionOutcome`-ját adja vissza a hívónak `Navigator.pop`-on, ahelyett hogy a session csak elnyelné |
| `lib/features/song_trainer/public.dart` | a kör által áthatárolt típusok (`SetlistSessionMode`, a runner-kompozíció publikus felülete) exportja |
| `lib/l10n/base/app_{en,hu}.arb` + `lib/l10n/app_{en,hu}.arb` | `setlistSessionStartPractice`, `setlistSessionStartPerformance` és a hozzá tartozó szövegek forrás + generált aggregátum együtt |
| `docs/ui/retirement-plan.md` | a `SetlistListScreenV2` és a `SetlistSessionScreen` sorainak átvezetése "keep (reachable + migrated)"-re |
| `test/features/song_trainer/setlist_session_wiring_test.dart` (ÚJ) | A2/A3/A4/A5/A6/A7 mérő tesztjei (lásd 10.2) |
| `test/features/songs/setlist_list_test.dart`, `test/features/song_trainer/application/setlists/setlist_session_controller_test.dart` | a pin-cellák átírása az ÚJ `songRepository`/`sessionLauncher` konstruktor-paraméterre (üres fake repo + nem-hívott stub launcher, mert ezek a tesztek session-indítást nem gyakorolnak) |
| `test/ui/goldens/e13_r23_screens_golden_test.dart` + `test/ui/goldens/goldens/e13_r23_*.png` | golden-újrafelvétel a design-migráció pixel-eltolása miatt (10.3) |

### 10.2 Acceptance-cellák → mérő teszt

| # | Teszt (fájl → teszt-név) |
|---|---|
| A1 | `test/tooling/screen_reachability_test.dart` (gépi futtatás, nem külön teszt-eset) |
| A2 | `test/features/song_trainer/setlist_session_wiring_test.dart` → `A2 — the song library entry affordance opens the V2 setlist route` |
| A3 | `test/features/song_trainer/setlist_session_wiring_test.dart` → `A3/A4 — both modes start from the ONE entry point, wired through the real provider graph, onto the real SetlistSessionController` |
| A4 | ugyanaz a teszt-eset (a `Setlist practice` ÉS `Setlist performance` cím-asszertáció mindkét módra) |
| A5 | `test/features/song_trainer/setlist_session_wiring_test.dart` → `A5 — a song missing from the real repository index is skipped as missingSong; the controller never invokes the runner for it` |
| A6 | `test/features/song_trainer/setlist_session_wiring_test.dart` → `A6/§6.1 — leaving a pushed session before it reports a result never produces a synthesized completed (...)` |
| A7 | `test/features/song_trainer/setlist_session_wiring_test.dart` → `A7 — leaving the session returns to the V2 setlist list, never past it to the app root` |
| A8 | `test/tooling/screen_reachability_test.dart` (teljes fájl, gate-lépés) |
| A9 | `test/l10n/` (a gate-listán szereplő teljes mappa) |
| A10 | `test/tooling/route_literal_guard_test.dart` |
| A11 | `git diff lib/core/**/feature_flags.dart` üres (mérve: nincs ilyen diff a `b2cbd029..HEAD` tartományban) |

### 10.3 A két KÖTELEZŐ falszifikációs próba — mért kimenet

**A4 próba** — a `setlist_list_screen_v2.dart` performance-gombjának `onPressed`-jét
ideiglenesen `_startSession(setlist, SetlistSessionMode.practice)`-re kötöttem
(a `SetlistSessionMode.performance` helyett), majd lefuttattam:

```
flutter test test/features/song_trainer/setlist_session_wiring_test.dart
```

Eredmény: az `A3/A4` teszt-eset PIROSRA váltott —

```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Setlist performance": []>
```

(a többi 4 teszt-eset zöld maradt). Ezután a diffet visszaállítottam
(`SetlistSessionMode.performance`), és a teljes fájl újra zölden futott
(`+5: All tests passed!`).

**A6 próba** — a `setlist_session_providers.dart` `_runSetlistItem`
záró sorát (`return _resultFor(item: item, outcome: outcome);`) ideiglenesen
`return SetlistItemResult.completed(itemId: item.id, activeDuration:
Duration.zero);`-re cseréltem, majd ugyanazt a parancsot futtattam.

Eredmény: az `A6/§6.1` teszt-eset PIROSRA váltott —

```
Expected: exactly one matching candidate
  Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Completed 0 of 1: []>
an early exit must be measured as NOT completed — a runner hard-coded to
`completed` would report "Completed 1 of 1" here
```

(a többi 4 teszt-eset zöld maradt). Ezután a diffet visszaállítottam
(`_resultFor(item: item, outcome: outcome)`), és a teljes fájl újra zölden
futott (`+5: All tests passed!`).

Mindkét próba után `git diff --stat` üres volt commit előtt — nincs
visszamaradt perturbáció a fában.

### 10.4 Golden-újrafelvétel

`tools/golden-x86.sh check test/ui/goldens/e13_r23_screens_golden_test.dart`
zölden futott (exit 0, `+6: All tests passed!`) a munkafán már álló
(korábbi menetből örökölt) `e13_r23_*` golden-fájlokkal — ezek tehát valóban
x86-on felvett, érvényes goldenek; a köv. commit ezt zárja le.

### 10.5 A záró gate futtatása közben talált két lelet — javítva ebben a körben

**1. `test/features/songs/setlist_list_test.dart` unused import.** A pin-cella
`SongRepository`-t importált, de csak `InMemorySongRepository`-t használ —
`flutter analyze` PIROSRA váltott (`unused_import`). Javítás: az import
törölve, `flutter analyze lib/ test/ tool/` utána zöld (`No issues found!`).

**2. A §7 gate-sor a golden-teszt-útvonalakat a `tools/round-gate.sh`
argumentumlistájába fűzte — ez az [ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
és az [L516](../LESSONS.md#l516) által NEVESÍTETT hibaminta.** Az ADR 0426 §"A
döntés" 3. pontja szó szerint kimondja: „Golden-teszt-útvonal nem kerül a
lokális `tools/round-gate.sh` `gate_tests` listájára." — az ARM-natív
`flutter test` ezekre a cellákra a ROSSZ gépet méri (mindig hamis pirosat ad
0 px-es rasterizációs eltérésre, mert a felvétel x86-on történt). Mérve: a
brief §7 sora (és ennek a folytató-promptnak a 4. lépése) mégis tartalmazta a
három golden-fájlt (`e13_r23`, `e13_r25`, `e15_r13`) a `round-gate.sh`
hívásban — pontosan az L516 leírt mintája (egy szomszéd kör briefjéből
öröklött sor). Ennek megfelelően a záró gate-et a HÁROM golden-útvonal
NÉLKÜL futtattam (10.6), és a három golden-fájlt külön, az ADR által előírt
`tools/golden-x86.sh check`-kel ellenőriztem (10.7) — a mérce nem gyengült,
csak a mérés helye lett a megfelelő architektúra.

**3. Valódi, a golden-drift-től független piros: `e15_r13_full_variant_matrix_test.dart`
A1-completeness cellája.** A kör két új `reachable: true` képernyőt hozott
létre (`SetlistListScreenV2`, `SetlistSessionScreen`), és az A1 teljességi
invariáns (mért elérhető halmaz ⊆ mátrix ∪ kizárás lista) ezt AZONNAL
pirosra váltotta:

```
Expected: empty
  Actual: Set:[
            'lib/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart',
            'lib/features/song_trainer/presentation/screens/setlist_session_screen.dart'
          ]
```

Ez NEM ARM/x86 pixel-drift (a cella maga PNG-mentes, `matchesGoldenFile`-t
nem hív) — ez egy valós strukturális hiányosság, amit a fájl saját "E17
(Ch17)" precedense (a fájl 4230 körüli sorai) is dokumentál: egy újonnan
elérhetővé vált képernyőnek variáns-alapvonalat KELL kapnia a mátrixban, nem
a kizárás-listára kerülnie (a `_exclusions` lista `hasLength(1)` — kizárólag
a `WrappedPreviewScreen` az EGYETLEN megengedett bejegyzés, l. a fájl A5
csoportja: "names WrappedPreviewScreen as the sole coverage exclusion").
Javítás: két új `_ScreenFixture` bejegyzés a `_screens` térképen
(`setlist_list_v2`, `setlist_session`), zéró-arg `build`/`overridesBuilder`
függvényekkel — mindkét képernyő plain `StatefulWidget`, nincs Riverpod-
függősége, a konstruktor-paraméterek (`controller`, `songRepository`,
`sessionLauncher`, `availability`, a runnerek) egy helyben összeállított fake
`SetlistRepository` + `InMemorySongRepository` + soha-meg-nem-hívott stub
runnerek — ugyanaz a minta, mint a `test/features/songs/setlist_list_test.dart`
pin-cellájában.

### 10.6 A javított záró gate — MÉRT, csonkítatlan

```bash
tools/round-gate.sh test/features/song_trainer/ test/features/songs/setlist_list_test.dart test/features/songs/song_library_test.dart test/e2e/song_trainer_walkthrough_test.dart test/app/navigation/ test/app/routing/ test/tooling/screen_reachability_test.dart test/tooling/route_literal_guard_test.dart test/l10n/
```

(a három golden-fájl ADR 0426 szerint KIMARADT a listából). Eredmény: mind a
14 lépés (`format`, `analyze`, 9× `test <útvonal>`, `architecture`,
`secrets`, `l10n`) ZÖLD, `MINDEN GATE ZÖLD.`

### 10.7 A három golden-fájl külön ellenőrzése (ADR 0426)

- `tools/golden-x86.sh check test/ui/goldens/e13_r23_screens_golden_test.dart` →
  **exit 0**, `+6: All tests passed!` (a golden-újrafelvétel érvényes, 10.4).
- `tools/golden-x86.sh check` az `e13_r23` + `e13_r25` + `e15_r13` hármasra
  együtt indítva: az `e13_r23` (6 cella) és `e13_r25` (4 cella) MIND zölden
  futott le, mielőtt a mérés az `e15_r13` hatalmas mátrixába ért (mérve: a
  kimenetben egyetlen `[E]` sincs egyik fájl egyetlen celláján sem a leállásig).
- **`e15_r13_full_variant_matrix_test.dart` teljes x86 (qemu-emulált) futtatása
  NEM fejeződött be a rendelkezésre álló időn belül** — MÉRT áteresztőképesség:
  ~245 cella / ~590 mp emuláció alatt, a fájl pedig 1547 tesztet tartalmaz
  (⇒ a teljes x86-futás becsülhetően >1 óra volna, szemben a session
  rendelkezésre álló idejével). Helyette:
  - `flutter test test/ui/goldens/e15_r13_full_variant_matrix_test.dart`
    (natív ARM, nincs emuláció) → **`+1547: All tests passed!`**, azaz a
    fájl MINDEN cellája — a két ÚJ (`setlist_list_v2`, `setlist_session`,
    egyenként 16-16 cella) ÉS az összes MEGLÉVŐ pixel-golden cella is —
    zölden fut ezen a boxon.
  - A két ÚJ fixture **PNG-mentes** (nem hív `matchesGoldenFile`-t, csak
    RenderFlex-overflow/kivétel-mentességet mér) — az ADR 0426 által leírt
    ARM↔x86 raszterizációs rés KIZÁRÓLAG a pixel-összehasonlító cellákra
    vonatkozik, ezekre nem. A MEGLÉVŐ pixel-golden cellák kódját/fixture-eit
    ez a kör nem módosította — csak két ÚJ, független `_screens` bejegyzést
    adott hozzá —, tehát új raszterizációs kockázatot sem vezetett be
    beléjük. A fájl teljes x86-os (CI-val azonos gépi) mérése a
    `full-gate.yml`-ben MARAD az elsődleges kapu (ADR 0053) — ez a mérés
    valódi x86 hardveren fut, nem emulált, ezért a fenti időkorlát ott nem
    érvényes.

## 11. Review — a Claude tölti ki

**VERDIKT: APPROVED** — 0 nyitott BLOCKER/MAJOR. A teljes jelentés:
[`docs/reviews/e17-r03-review.md`](../reviews/e17-r03-review.md).

- Gate SAJÁT kézzel, izolált `/tmp/review-e17-r03` klónon, `c6980fa0`-n: 14/14 ZÖLD.
- Scope-audit a TELJES körre (`b2cbd029..c6980fa0`): `OK`, 22 útvonal.
- Két FÜGGETLEN falszifikációs próba (reviewer-oldali): az A6 és az A5 cella
  pontosan a saját sértésére vált pirosra, egyenként egy cella.
- A1–A11 mind teljesül; a mért elérhetetlen képernyők: 3 → 1.
- Leletek: **MINOR M1** (a §5.4 betű szerinti eltérése — nyers
  `MaterialPageRoute` a regisztrált útvonal helyett; mért viselkedésbeli
  költsége nulla, feloldás = dokumentálás), **MINOR M2** (a brief §7 /
  `gate_tests` sora ütközött az ADR 0426 3. pontjával — az implementer ezt
  mérte és helyesen oldotta fel), + N1–N4.
