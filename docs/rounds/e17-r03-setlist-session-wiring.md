# E17-R03 — A Song Trainer setlist-session bekötése (V2-natív)

- **Státusz:** **`done`** — a kör TARTALMA a pipeline dispatch-én KÍVÜL landolt (`25b518457`, 2026-09-15), lásd §0.2. A §0.1 REVISED szövege (ADR 0112 önjavító kör, 2026-09-19; mért alap: `main @ 3ffde512`) történeti rekord.
- **Típus:** Chapter 17 (Teljes bekötés), Kör 3
- **Kör-azonosító:** `E17-R03`
- **Branch:** `<motor>/e17-r03-setlist-session-wiring`
- **Brief szerzője:** Claude (Opus 5) — a §0.1 revízió az ADR 0112 önjavító köréé
- **Előre kiosztott ADR:** `ADR 0522` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "a song trainer setlist-session bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie.

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

## 0.2 A kör tartalma a pipeline-on KÍVÜL landolt (2026-09-15) — `done`

**Mérve 2026-09-19 (négy-vonalas main-integráció).** A setlist-session bekötése
nem ezen a briefen keresztül dispatch-elve született meg, hanem a `25b518457`
commitban („feat(song_trainer): the setlist session is reachable from the setlist
detail — one launcher, mode as a parameter"), és az integrációval a `main`-re
került. A körhöz nyitott #604 PR fája BITRE azonos volt a mainnel, ezért merge
nélkül lezárva; a queue-sor `pending` → `done`.

**A szállított megoldás ELTÉR e brief §5.1-étől.** A §0.1 revízió a belépést a
**V2 setlist-felületre** tette volna (`/song-trainer/setlists`); ami valójában
szállt, az a **legacy `SetlistDetailScreen`** belépés, ahol a legacy setlist
belépésenként, MEMÓRIÁBAN vetül `SongSetlist`-re
(`SetlistSessionComposer.compose`, semmi nem perzisztálódik). A §5.2–5.4 döntések
(egy indító paraméteres móddal, valós dal-tárból jövő availability, mért
`SetlistItemResult`) változatlanul érvényesek és szállítva vannak.

**A kötött döntések mostantól az ADR-ben élnek, nem itt:**
[`ADR 0522`](../adr/0522-setlist-session-single-launcher-and-mode-parameter.md)
— a §5 alatti szakaszok ezért történeti rekordnak olvasandók, és a kódban lévő
`ADR 0522 §…` hivatkozások az ADR saját döntés-számozására mutatnak.

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

## 5. Kötött architekturális döntések (ADR 0522)

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

## 11. Review — a Claude tölti ki
