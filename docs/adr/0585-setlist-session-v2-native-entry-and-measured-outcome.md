# ADR 0585 — A Setlist-session V2-natív belépési pontja és a MÉRT tétel-kimenet

**Státusz:** elfogadva (2026-09-19, E17-R03 — Chapter 17 „Teljes bekötés", Kör 3)

**Kör:** `E17-R03` · **Brief:** [`docs/rounds/e17-r03-setlist-session-wiring.md`](../rounds/e17-r03-setlist-session-wiring.md)

Kapcsolódik: [ADR 0130](0130-setlist-v2-song-progress-and-epic-3-closure-boundary.md)
(Setlist V2 modell + a `SetlistSessionController` határa),
[ADR 0116](0116-legacy-song-setlist-migration-boundary.md) (a legacy→V2 adapter nem-perzisztens
dokumentum-mappingje), [ADR 0129](0129-song-trainer-ui-loop-speed-and-result-boundary.md)
(a trainer-session és a result-route szerződése),
[ADR 0125](0125-song-trainer-setup-configuration-boundary.md) §„Elutasított
alternatívák" (route-literál helyett katalógus-konstans),
[ADR 0471](0471-screen-reachability-is-measured-not-assumed.md) / a
[`docs/ui/retirement-plan.md`](../ui/retirement-plan.md) §3.2–§6 (mikor tartozik
egy képernyő a design-migrációba), [ADR 0426](0426-golden-rasterization-on-the-gate-architecture.md)
(golden-felvétel x86-on), [ADR 0087](0087-round-brief-scope-authority.md) §2
(a kör-brief scope-hatásköre), [ADR 0112](0112-self-healing-pipeline.md)
(a kör 2026-09-19-i H3 önjavító köre, `ba8233af`).

## Kontextus

A `SetlistSessionScreen` és a `SetlistListScreenV2` a mérés szerint ma is a 97
képernyőből 3 elérhetetlen közül kettő. A kör pre-flightja ezt `main @ ba8233af`-on
mérte újra, és a brief §2 minden állítását változatlanul igazolta:

```
$ dart run tool/check_screen_reachability.dart --format json
measuredScreenCount=97  unreachableCount=3
SetlistSessionScreen   reachable=false declarative=[] imperative=[]
SetlistListScreenV2    reachable=false declarative=[] imperative=[]
SetlistDetailScreen    reachable=true  imperative=[setlist_list_screen.dart:24]   # legacy világ
PracticePlanPreviewScreen reachable=false                                          # E17-R04 tárgya

$ grep -c design_system .../setlist_list_screen_v2.dart   → 0     (nem migrált)
$ grep -c design_system .../setlist_session_screen.dart   → 1     (migrált)
$ grep -rn "UnimplementedError" lib/features/song_trainer/ | wc -l → 0
$ grep -n "songTrainerV2Enabled" lib/app/config/feature_flags.dart:247 → nonProd
```

A kör 2026-09-19-én egyszer már megállt a dispatch ELŐTT (`H3`), mert az eredeti
brief premisszája — „a `SetlistDetailScreen` a session természetes belépési
pontja" — MÉRVE hamis: két diszjunkt setlist-világ van (legacy
`Setlist{songIds}` a `songs` feature-ben, V2 `SongSetlist{items:[SongId…]}` a
`song_trainer`-ben), és a session a MÁSIKHOZ tartozik. Az önjavító kör
(`ba8233af`) a briefet V2-natívvá írta, és gépi őrt adott hozzá
(`tools/tests/test_e17_r03_setlist_session_scope.py`, 9 cella, a revízió előtti
briefen 7 piros). Ez az ADR a brief §5 döntéseit rögzíti, és feloldja azt a KÉT
kérdést, amit csak a pre-flight kódmérése tudott eldönteni (D3, D4).

## Döntések

### D1 — A belépés a V2 setlist-felületről megy, egyetlen új útvonalon

Az útvonal `AppRoutes.songTrainerSetlists = '/song-trainer/setlists'`, a
`songTrainer*` konstanscsalád tagjaként (`app_route.dart:42-49`), és a MEGLÉVŐ
`if (songTrainerEnabled)` blokkban regisztrálódik (`app_router.dart:751`).
Route-literál az `app_router.dart`-ban tilos (`test/tooling/route_literal_guard_test.dart`).
A `SetlistListScreenV2` konstruktor-injektált (`controller`, `clock`), ezért a
builder `Consumer`-en át a `setlistControllerProvider`-ből és a
`songTrainerClockProvider`-ből köti be — nem vezet be új provider-hidat.

**Elutasítva:** a legacy `Setlist` → `SongSetlist` projekció. A két ID-tér
diszjunkt (a legacy id `'${microsecondsSinceEpoch}_$seq'`, a V2 id seed- vagy
dokumentum-id), a legacy részletnek MÁR VAN működő futtatása (`_playAll`), és a
projekció mögötti `LearnScreen` szerződése (`learn_screen.dart:38-41`) semmit nem
ad vissza — minden tétel-eredmény kitalált lenne.

### D2 — A két mód a belépési pont PARAMÉTERE

A `SetlistSessionMode` már ma is a képernyő paramétere
(`setlist_session_screen.dart:24`). Két külön belépési pont két kód-utat teremtene
ugyanarra az állapotgépre, és a divergencia csak futásidőben derülne ki.

### D3 — Az availability KÉT rétegben mér, és egyik réteg sem talál ki semmit

A pre-flight mérése kényszeríti ezt a szétvágást: a
`SetlistAvailabilityResolver` **szinkron** typedef
(`SetlistItemAvailability Function(SongSetlistItem)`,
`setlist_session_controller.dart:4-5`), a `SongRepository` viszont
**kizárólag aszinkron** (`list`/`get` → `Future<AppResult<…>>`,
`song_repository.dart:295-306`). Szinkron rétegből tehát a dokumentum tartalma
elvileg sem érhető el.

1. **Szinkron réteg — indexpróba.** A session indulásakor EGYSZER betöltött
   `repository.list(SongQuery(...))` pillanatképe (`SongSummary.documentId`,
   `revision`, `trashed`) fölött zár a resolver. A setlistben szereplő, de az
   indexben nem (vagy `trashed`-ként) szereplő `SongId` → `missingSong`.
   Konstans `ready` visszaadása tilos; üres pillanatkép mellett minden tétel
   `skipped`/`missingSong`.
2. **Aszinkron réteg — indítási próba.** A mély okokat a runner méri, a MÁR
   LÉTEZŐ `songTrainerSessionLauncherProvider`
   (`song_trainer_session_launcher.dart:88`) hibakódjain keresztül, kötött
   leképezéssel:

   | launcher-hiba | `SetlistItemAvailability` |
   |---|---|
   | `SongRepositoryErrorCode.notFound` | `missingSong` |
   | `SongTrainerLaunchFailureCode.staleRevision` | `requiresMigration` |
   | `SongTrainerLaunchFailureCode.notPlayable` (fordítási hiba) | `invalidConfig` |

   Az ilyen tétel `SetlistItemResult.skipped(availability: …)` — ez a modell
   `repairRequired: true` ága, tehát az összegzés a javítandót javítandónak
   mutatja.

A `SongSetlistItem.initialAvailability` **perzisztált tipp, nem mérés**: a
session indulásakor a fenti két réteg dönt újra. Egy időközben törölt dal
`ready` tippel sem futhat.

### D4 — A `SetlistItemResult` a session MÉRT kimenete; a varrat a session-route-ban van

Ma a `SongTrainerSessionRoute` a scored session végén a result-route-ot nyitja
meg (`NavigateToSongTrainerResult` → `_openResult`), és a HÍVÓJÁNAK semmit nem ad
vissza (`song_trainer_session_route.dart:130-146`). Varrat nélkül tehát a setlist-runner
csak a fal-órából tudna „eredményt" gyártani — pontosan az a hibaosztály, amit a
`partial` doc-commentje (`setlist_result.dart:7-11`) kizár.

A kör MINIMÁLIS varratot épít: a session-route a saját, már meglévő
`SongTrainerResult`-ját visszaadja a navigációs hívójának, és a setlist-runner EZT
képezi le `SetlistItemResult`-ra. Kötött következmények:

- **Az egydalos út viselkedése bit-azonos marad.** A varrat csak akkor termel
  kimenetet, ha a hívó kért ilyet; a setup→session→result út, a „practice again"
  (a result alatt mountolva maradó session `seek(Duration.zero)`-ja) és a
  fail-closed `extra`-redirect változatlan.
- **Szintetizálás tilos.** Eredmény nélkül elhagyott session NEM `completed`.
  A „félbehagyta" ág a modell `partial` faktoryja, és csak akkor, ha a session
  ténylegesen mért `activeDuration`-t adott vissza.
- Ha a varrat a brief §4 fájllistáján belül nem építhető meg, a kör `stopped`,
  és a kimenet brief-revízió — nem tágabb lista, és nem kitalált státusz.

### D5 — A V2 lista bekötése és design-migrációja UGYANAZ a kör

Gépi kényszer, nem ízlés. A `test/tooling/screen_reachability_test.dart` **A3**
cellája minden *elérhető ÉS nem migrált* képernyőtől `migrate`/`retire` verdiktet
és `^E15-R\d+$` gazda-kört követel a `retirement-plan.md` §6 sorában. A
`setlist_list_screen_v2.dart`-ban `grep -c design_system` → **0**, a sora
`unreachable` / gazda `—`, és minden E15-ös kör `done` — gazdát tehát nem lehet
őszintén beírni. A puszta bekötés így a kör SIKERÉVEL tenné pirossá a kaput
(`ownerless: [setlist_list_screen_v2.dart]`). A migráció a
`core/design_system/public.dart` komponenseire és tokenjeire megy, ÚJ
`*ThemeScope` burkoló nélkül (E15-R01 óta az app témája hordozza a tokeneket), és
a `retirement-plan.md` §6 két sora + a §3.4 felsorolás a MÉRT új állapotra
vezetődik át.

### D6 — Ami NEM változik

A `songTrainerV2Enabled` alapértéke (`nonProd`, `feature_flags.dart:247`), a
`SetlistSessionController` szemantikája, a legacy `songs` setlist-út
(`SetlistListScreen` / `SetlistDetailScreen` / `_playAll`), és a
`test/tooling/screen_reachability_test.dart` — az a kör MÉRŐESZKÖZE, nem terméke
(a briefben szándékosan csak `gate_tests`-ben szerepel, `allowed_paths`-ban nem).

## Következmények

- A `SetlistSessionScreen` és a `SetlistListScreenV2` `reachable: true` lesz, és a
  mért elérhetetlen képernyők száma 3-ról 1-re csökken (marad a `PracticePlanPreviewScreen`,
  az E17-R04 tárgya).
- A `SetlistItemResult` innentől ellenőrizhető állítás: az A6 cella pirosra vált,
  ha a runner fix `completed`-et ad vissza (a brief §6.1 kötelező falszifikációs
  próbája).
- A design-migráció pixelt mozdít, ezért az `e13_r23_*` goldenek újrafelvétele
  **x86-on** kötelező (`tools/golden-x86.sh record`); a lokális
  `--update-goldens` aarch64-en tiltott ([L486](../LESSONS.md), [L493](../LESSONS.md)).
- A migrált képernyő túlcsordulás-cellái NEM az alapértelmezett 800×600-as
  viewporton bizonyítanak: az a méret szélesebb ÉS magasabb minden telefonnál, és
  a lusta `ListView` a viewport alá eső gyermeket fel sem építi — a cella akár üres
  fát is mérhet ([L558](../LESSONS.md), E15-R06). Telefon-méretű viewport
  (`tester.view.physicalSize`) kell.
- A `docs/ui/retirement-plan.md` és a mérés keresztellenőrzése az A8 cellában
  marad: a terv és a valóság együtt mozdul, vagy a kapu piros.

## Elutasított alternatívák

- **A legacy részletképernyőből indított session** — D1 (diszjunkt ID-terek,
  a `LearnScreen` semmit nem ad vissza, és egy már működő utat duplikálna).
- **Módonként külön belépési pont** — D2 (két kód-út ugyanarra az állapotgépre).
- **Konstans `ready` availability-resolver** — D3 (a session nem létező tételeket
  próbálna futtatni; a brief A5 cellája ezt méri üres repository-val).
- **Fal-óra alapú `completed`/`partial`** — D4 (a `partial` doc-commentje szerint
  ez pontosan az a hazugság, ami miatt a státusz bekerült).
- **Provider-híd a `songs` feature-höz** — a `tool/check_architecture.dart:382-392`
  cross-feature szabálya csak `public.dart`-ot enged, és a `songs/public.dart`
  kizárólag a `model/song.dart`-ot exportálja: sem a `Setlist`, sem a
  `setlistsProvider` nem látszik.
- **A bekötés design-migráció nélkül** — D5 (a kör sikere tenné pirossá az A3-at).
- **Gazda-kör beírása a `retirement-plan.md`-be `^E15-R\d+$` alakban** — minden
  E15-ös kör `done`; egy lezárt körre mutató gazda hamis állítás lenne
  (a hibaosztály: [L612](../LESSONS.md)).
