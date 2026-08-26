# E13-R25 — Song Trainer, Result és Setlist Run UI

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 74f8a8ec`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 25
- **Kör-azonosító:** `E13-R25`
- **Branch:** `<motor>/e13-r25-song-trainer-and-setlist-run`
- **Előfeltétel:** `E13-R24` merge-elve (import és szerkesztő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274 (audio óra) és 0283 érvényes.

> ✅ **A pre-flight MEGTÖRTÉNT (2026-08-26, `main @ 4185418d`) — a leletei a
> [§0.0/B](#00b-brief-revízió--2026-08-26-a-kör-saját-pre-flightja-main--4185418d)-ben.**
> A kötelező kérdésre („létezik-e »csak lejátszás« mód") a válasz **IGEN**
> (§0.0/B/B2), a §5.1 tehát mért alapon áll. **A §0.0 három útvonala viszont
> NEM létezik** — az érvényes fájllista az `ai-router` blokkban van (§0.0/B/B1).
> Olvasd el a §0.0/B-t a §0.0 ELŐTT; eltérésnél a §0.0/B nyer.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B/B1 — az eredeti HÁROM könyvtár-előtag (`lib/features/songs/trainer/`,
  # `lib/features/songs/results/`, `lib/features/setlists/run/`) a verziókövetett
  # fán NEM létezik, tehát NULLA fájlt fedett (L497 hibaosztály, harmadszor:
  # E13-R22, E13-R23, most). A négy megnevezett felület MÁR LÉTEZIK a
  # `song_trainer` presentation rétegében. A csere a merge-elt E13-R23
  # user-jóváhagyott listájának valódi RÉSZHALMAZA: nevesített screen +
  # nevesített widget — `presentation/widgets/` KÖNYVTÁR, `public.dart` és
  # `lib/app/routing/` NÉLKÜL.
  "lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_trainer_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_result_screen.dart",
  "lib/features/song_trainer/presentation/screens/setlist_session_screen.dart",
  "lib/features/song_trainer/presentation/widgets/song_track_picker.dart",
  "lib/features/song_trainer/presentation/widgets/trainer_range_picker.dart",
  "lib/features/song_trainer/presentation/widgets/tuning_capo_reminder.dart",
  "lib/features/song_trainer/presentation/widgets/chord_lane.dart",
  "lib/features/song_trainer/presentation/widgets/loop_controls.dart",
  "lib/features/song_trainer/presentation/widgets/measure_heatmap.dart",
  "lib/features/song_trainer/presentation/widgets/song_loop_feedback.dart",
  "lib/features/song_trainer/presentation/widgets/strum_lane.dart",
  "lib/features/song_trainer/presentation/widgets/tablature_lane.dart",
  "lib/features/song_trainer/presentation/widgets/transport_controls.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/fixtures/songs/trainer/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r25-song-trainer-and-setlist-run.md",
]
gate_tests = [
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  # §0.0/B/B4 — a négy célképernyőre MA is mérő, listán KÍVÜLI pinek:
  # futtatni KELL, szerkeszteni TILOS (a migráció nem törheti el őket).
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/app/routing/app_router_test.dart",
  # §0.0/B/B5 (ADR 0426 §3) — a golden-útvonal NEM kerül a lokális ARM-gate-re;
  # a lokális mérés egyetlen érvényes alakja:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r25_screens_golden_test.dart`
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
]
native_gate = false
```

## 0.0 BRIEF-REVÍZIÓ — 2026-08-25, batch pre-flight (E13-R17…R35)

A brief 2026-08-15-én készült; ez a pre-flight `main @ 41fbd40` ellen mért.
**Visszakeresett előzmény:** [L478](../LESSONS.md) (a pre-flight csak szűkíthet;
a tágítás H3), [ADR 0307 §4](../adr/0307-parallel-round-execution.md) (a
`lib/l10n/app_*.arb` GENERÁLT aggregátum, a forrás a `base/` és a
`features/` szegmens), [L481](../LESSONS.md) (a lánc remote konténerből nem
indítható). A hibaosztályt a **teljes Ch13 sávon** mérte ki egy batch-vizsgálat:
az R17–R35 MIND a generált aggregátumot sorolta fel forrásként (`agg=2, frag=0`).

**Kockázat = high, indoklás:** a tréner és a setlist-futtatás a mikrofon-erőforrást (authorization) birtokolja, és eredményt ír.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fájából `lib/features/songs/trainer/`, `lib/features/songs/results/`, `lib/features/setlists/run/` **még nem létezik** — a képernyőket ez a kör hozza létre, tehát MINDEN szövege új.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `setlists` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `songs` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - nincs ilyen.

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — nincs ilyen. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/setlists/run/`, `lib/features/songs/results/`, `lib/features/songs/trainer/` könyvtár-előtag
alá képernyőt hoz vagy hozhat, tehát a szám **elmozdul**, és az exact-SHA Full
Gate pirosra vált.

A `test/ui/goldens/` előtag ezt **nem** fedi (az a `test/ui/` fának csak az egyik
ága), a leltárteszt utólagos felvétele pedig tágítás, azaz **H3** — az
orchestrátor a pre-flightban nem oldhatja fel ([L478](../LESSONS.md)). Ezért
kerül a listára MOST, az önjavító körben.

**MÉRVE (E13-R16, 2026-08-25):** pontosan ez a hiány állította meg a sáv első
migrációs körét — [full-gate 32867296946](https://github.com/wolfcasaba/strumsight/actions/runs/32867296946)
6366 passed / 2 failed, `hasLength(79)` a tényleges 81 ellen. A `9acd14e5`
sáv-szintű batch pre-flight azért nem találta meg, mert a `tools/brief-lint.py`
`S9` szabálya csak LITERÁLIS `*_screen.dart` útvonalat nézett, KÖNYVTÁR-előtagot
nem — a predikátumot ugyanez az önjavító kör javította, regressziós teszttel
([L483](../LESSONS.md)).

**A jogosultság PONTOSAN a szám emelése** a kör tényleges képernyőszámára; a
leltárteszt minden más állítása érintetlen marad. Kerülőút (képernyő-átnevezés
vagy a `tool/ui_inventory.dart` szabályának lazítása) **TILOS** — az a mérce
meghamisítása.

### S12 — a fa-szintű őrök a kör LOKÁLIS kapujába (2026-08-25)

A kör lokális kapuja eddig KIZÁRÓLAG a saját céltesztjeit futtatta, ezért a
teljes `lib/` fát pásztázó őrök leletei szerkezetileg csak a ~17 perces
exact-SHA Full Gate-en jelentek meg — javító kör árán. MÉRT eset: **E13-R16/F8**
(`docs/reviews/e13-r16-review.md`), ahol mind a három új képernyő közvetlenül
importálta a `design_system/foundations/**`-ot a `public.dart` helyett — **11
sértés** —, és a review szó szerint rögzíti, miért nem fogta a célzott gate:
a `tools/round-gate.sh` `architecture` lépése a `tool/check_architecture.dart`-ot
futtatja, ami egy MÁSIK, tágabb szabálykészlet; a design-system-határ mércéje
egy külön `test/core/` teszt, amit csak a teljes suite futtat.

Ezért ez a kör mostantól a `gate_tests`-ben futtatja ezeket az őröket:

- `test/core/architecture_dependency_test.dart`
- `test/tooling/dio_factory_guard_test.dart`
- `test/tooling/preferences_plugin_import_guard_test.dart`
- `test/tooling/route_literal_guard_test.dart`

A kiválasztás MÉRT, nem vaktában: a globális őrök a `Directory('lib')` teljes
fát pásztázzák (bármelyik kör diffje elmozdíthatja őket), a szűkített őrök pedig
csak akkor kerülnek fel, ha a kör `allowed_paths`-a metszi a pásztázott
gyökeret.

**Ezek az őrök NEM kerülnek az `allowed_paths`-ra** — és ez szándékos: a kör
futtatja, de NEM szerkesztheti őket, tehát a lelet javítása kizárólag a kör
SAJÁT kódjában történhet. Cella törlése, `skip`-je vagy küszöb-lazítása így
gépileg kizárt, a mérce pedig tiszta erősítést kap.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, a kör SAJÁT pre-flightja (`main @ 4185418d`)

A 2026-08-25-i sáv-szintű batch pre-flight (§0.0) az ARB-csapdát megtalálta, de
a kör fájára vonatkozó állítását NEM ellenőrizte. A kör indítása előtti mérés
hat leletet adott. **Visszakeresett előzmény** (§4.9, szűkítve ELŐSZÖR):
[L497](../LESSONS.md#l497) (nem létező `allowed_paths`, kétszer mérve),
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET; a tágítás H3),
[L397](../LESSONS.md#l397)/[L377](../LESSONS.md#l377)/[L401](../LESSONS.md#l401)
(a `ui_inventory` bázisvonal CI-only lelete),
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
(golden-raszterizáció), [ADR 0129](../adr/0129-song-trainer-ui-loop-speed-and-result-boundary.md)
(a trainer/result UI és loop merge-elt határa).

### B1 — a három könyvtár-előtag NEM LÉTEZIK; a felületek MÁR LÉTEZNEK

Mérve (`find lib/features/songs lib/features/setlists -type d`):

```
lib/features/songs → application  data  model  providers  screens  theory  widgets
lib/features/setlists → bfs: error: No such file or directory
```

A brief §0.0/R1 abból indult ki, hogy „a képernyőket ez a kör hozza létre,
tehát MINDEN szövege új". **Ez hamis.** A négy megnevezett felület mind él a
`song_trainer` presentation rétegében, és a router három route-on pinneli
(`lib/app/routing/app_router.dart:361,365,373`):

| §3 felület | A fán MÉRT fájl | Sor |
|---|---|---|
| tréner beállítása | `presentation/screens/trainer_setup_screen.dart` | 264 |
| tréner Stage | `presentation/screens/song_trainer_screen.dart` | 355 |
| dal-eredmény | `presentation/screens/song_result_screen.dart` | 150 |
| setlist futása | `presentation/screens/setlist_session_screen.dart` | 200 |

**A feloldás útvonal-csere**, az `ai-router` blokkban. A csere szigorúan
KEVESEBB, mint az egy körrel korábbi, merge-elt és user-jóváhagyott E13-R23
lista ugyanerre a feature-re — a tágítás H3 lenne ([L478](../LESSONS.md#l478)):

| E13-R23 (merge-elt) | E13-R25 (a csere) |
|---|---|
| 3 nevesített screen + `presentation/widgets/` (TELJES könyvtár) + `public.dart` + `lib/app/routing/` | 4 nevesített screen + **10 nevesített** widget |

A 10 widget nem vaktában választott: pontosan azok, amelyeket a négy képernyő
MA importál (`grep -hn "^import '\.\./widgets" …`). A `domain/`, `data/` és
`application/` így OLVASHATÓ, de nem írható marad — a §3 „a pontozás vagy a
lejátszás logikájának módosítása tilos" kikötése ezzel **gépi** lett
(`scope-audit.py`), nem csak szöveges. A `public.dart` és a `lib/app/routing/`
kimarad: a migráció HELYBEN történik, típusnév/route/konstruktor-szignatúra
változatlan (az E13-R24 merge-elt precedense).

### B2 — a §5.1 alatti „csak lejátszás" mód LÉTEZIK (a brief ⚠ pre-flight kérdése)

A brief fejléce kötelezővé tette ennek mérését. Az eredmény: **létezik**, és a
domain a pontozás hiányát MA is hordozza — a §5.1/A1 tehát mért alapon áll, nem
kell revízió:

- `application/trainer/song_practice_compiler.dart:24` —
  `const SongPracticeCompilation.playbackOnly()`; `:33` — `bool get isPlaybackOnly => definition == null;`
- `application/trainer/song_trainer_controller.dart:117,156,317` —
  `isPlaybackOnly`, `_startPlaybackOnly()`
- `domain/models/song_practice_record.dart:48,78` — `playbackOnly` mező
- `application/progress/song_progress_aggregator.dart:225` — `if (record.playbackOnly)`
  ága, és `song_trainer_providers.dart:462`: *„`playbackOnly`, which the credit
  recorder intentionally leaves uncredited."*

**Amit ez a körre jelent:** az A1 NEM új domain-mód bevezetése (az §3 szerint
tilos is lenne), hanem a MÁR MÉRT `isPlaybackOnly == true` ág **kimondása a
felületen**, pontszám nélkül. A `SetlistSessionScreen` már ma is ezen az elven
áll: `_unavailablePracticeRunner` → `StateError('Playback-only sessions cannot
run scoring.')` (`setlist_session_screen.dart:63-65`).

### B3 — a `ui_inventory` száma NEM mozdul (a §0.0/R4 feltevése avult)

A §0.0/R4 azért vette listára a `test/ui/ui_inventory_test.dart`-ot, mert „a kör
képernyőt hoz vagy hozhat, tehát a szám elmozdul". A B1 mérése után ez **nem
áll**: mind a négy képernyő létezik, a migráció HELYBEN történik, tehát új
`lib/features/**/*_screen.dart` fájl nem keletkezik.

Mérve: `test/ui/ui_inventory_test.dart:14` → `expect(first.screenPaths, hasLength(86))`.
A merge-elt E13-R24 precedense ugyanez: *„az `ui_inventory` diffje ÜRES, 86 → 86"*.

**A listaelem MARAD** (a szám elmozdulása nem zárható ki teljesen, és a
felvétele utólag H3 lenne — [L478](../LESSONS.md#l478)), de a **VÁRT diff ÜRES**.
A szám emelése ÚJ képernyő-fájl NÉLKÜL a mérce meghamisítása, nem a kör joga;
képernyő-átnevezés vagy a `tool/ui_inventory.dart` lazítása szintén TILOS.

### B4 — a négy célképernyőre MA is mérő pinek: futtatni KELL, szerkeszteni TILOS

A §0.0/R2 azt írta: „nincs ilyen". **Ez hamis** — öt ma zöld cella pinneli
közvetlenül a kör célfájljait:

```
test/features/song_trainer/presentation/trainer_setup_screen_test.dart
test/features/song_trainer/presentation/song_trainer_screen_test.dart
test/features/song_trainer/presentation/song_result_screen_test.dart
test/features/song_trainer/presentation/song_trainer_accessibility_test.dart
test/features/song_trainer/application/setlists/setlist_session_controller_test.dart
```

Ezek a `gate_tests`-be kerülnek, az `allowed_paths`-ra **NEM** — a kör futtatja,
de nem szerkesztheti őket, tehát a lelet javítása kizárólag a kör SAJÁT
kódjában történhet (a §0.0/S12 mintája). Ugyanígy fut a `test/app/routing/app_router_test.dart`
a három route-pin miatt. Ha ezek bármelyike elbukik, az `blocked` jelzés és
célzott brief-revízió, NEM csendes átírás.

**A `brief-lint` S11 lelete erre a mérésre oldódik fel.** Az S11 azt a
hibaosztályt védi, amikor egy migrációs kör **LECSERÉLI** a képernyő típusát
(új `…_screen_v2.dart`, új osztálynév), és a briefen kívüli pinek emiatt
pirosra váltanak — az ő felvételük utólag H3 lenne. A lint maga adja a második
kifutót: *„Ha a kör a képernyőt bizonyíthatóan nem cseréli le, a §0.0 mondja ki
ezt a mérést."* **Ez a kör nem cseréli le**, és ezt a §3 hatóköre ki is zárja:

- a négy képernyő **HELYBEN** módosul — típusnév, fájlútvonal, route-regisztráció
  és konstruktor-szignatúra **változatlan**;
- ezért a `ui_inventory` diffje ÜRES (86 → 86, §0.0/B/B3), és a három
  `app_router.dart` route-pin (`:361,365,373`) érintetlen;
- a merge-elt precedens ugyanez: az E13-R24 három képernyőt migrált HELYBEN,
  `ui_inventory` 86 → 86, a pinek zölden maradtak, felvételük nélkül.

**Ebből következő KÖTELEZETTSÉG az implementerre:** a fenti öt pin + a
route-teszt a kör végén ugyanúgy ZÖLD, ahogy ma az. Ha a választott megoldás
csak a pin átírásával lenne zöld, az a képernyő lecserélése — tehát **`stopped`
jelzés** és célzott brief-revízió, nem a cella hozzáigazítása.

**A lint MARADÉK S11 lelete VÁRT, és nem hallgattatható el szűkítéssel.** Az
`outside_screen_pins` predikátuma szerkezeti: kizárólag az `allowed_paths`-ba
vétel törli (`if covered_by(relative, allowed_paths): continue` —
`tools/brief-lint.py`). A pinek felvétele viszont **tágítás**, ami az
orchestrátornak H3 ([L478](../LESSONS.md#l478)) — és éppen az ellenkezőjét érné
el annak, amit a B4 véd: szerkeszthetővé tenné a cellákat, amiknek zölden kell
maradniuk. A szabály SAJÁT kommentje ezt vállalt maradékként nevezi meg:
*„A vállalt maradék hamis riasztás … egy csak MÓDOSÍTÓ (nem lecserélő) kör
feleslegesen kapja a teendőt."* A `brief-lint` kilépési kódja `0`; a lelet
tehát tudomásul véve és MÉRVE feloldva, nem figyelmen kívül hagyva.

### B5 — a golden felvétele és ellenőrzése a MERGE-KAPU architektúráján (ADR 0426)

A §7 `~/flutter/bin/flutter test --update-goldens` sora **elavult és tiltott**
ezen az **aarch64** boxon: ez adta az E13-R17 két vak javító körét és az
E13-R20 **H5 haltját** ([L493](../LESSONS.md#l493), [L486](../LESSONS.md#l486)).
Az [ADR 0426 §3](../adr/0426-golden-rasterization-on-the-gate-architecture.md)
kimondja: *„Golden-teszt-útvonal nem kerül a lokális `tools/round-gate.sh`
`gate_tests` listájára"* — az ARM-futás ezekre a cellákra a rossz gépet méri.
Ezért a `gate_tests`-ből kikerül, és helyette:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r25_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r25_screens_golden_test.dart
```

**Ez nem lazítás:** a komparátor (nulla tolerancia) és a golden-bank
változatlan, a verifikáció pedig a CI teljes suite-ja marad. A PNG-k a
`test/ui/goldens/goldens/` alá kerülnek (a `test/ui/goldens/` listaelem fedi),
és **commitolni kell** őket. Minta és futó precedens:
`test/ui/goldens/e13_r24_screens_golden_test.dart` (`AppTheme`, 412×915,
`devicePixelRatio: 1.0`, `textScaler` 1.0 és 2.0).

### B6 — a kör ADR-t NEM ír (a nyolcadik ADR nélküli kör a sávon)

A §5 mind az öt kötött döntése MÁR merge-elt ADR-ekben él:
[0274](../adr/0274-motion-driven-by-the-audio-clock.md) (audio óra, §5.2),
[0283](../adr/0283-results-never-overstate-certainty.md) (§5.1),
[0276](../adr/0276-stage-scaffold-owns-no-resources.md) (§5.6),
[0277](../adr/0277-failure-presentation-model.md) (hiba-állapotok),
[0129](../adr/0129-song-trainer-ui-loop-speed-and-result-boundary.md) (trainer/result
UI, loop és result boundary). Ezek újraírása **H1** lenne (ADR 0087 §2), és a
sávon ez a hibaosztály E13-R17…R24 között hétszer merült fel. Ezért a
pre-flight **nem foglal** ADR-számot; ha az implementer ÚJ normatív döntést
találna, az `stopped` jelzés, nem önkezű ADR.

### B7 — az erőforrás-tulajdonlás MÉRT láncon (a §1/2. szabály)

A §0.0 „a tréner és a setlist-futtatás a mikrofon-erőforrást (authorization)
birtokolja" állítását a tényleges hívási lánc **cáfolja**:
`grep -rn "\.acquire(" lib/` → az egyetlen audio-lease-szerző a
`lib/core/audio/mic_capture.dart:82` (`_coordinator.acquire(...)`), az
`AudioSessionCoordinator`-t pedig a `practice` réteg köti be
(`practice_session_providers.dart`, `practice_session_controller.dart`,
`core/audio/audio_providers.dart`). A `song_trainer` presentation rétegében
**nincs** `acquire` hívás; a `song_transport_state.dart:30` csak az
`audioFocusLost` állapotot HORDOZZA.

**Amit ez a §5.6/A7-re jelent:** a kör NEM szerezhet és nem is szabadíthat fel
saját erőforrást — az [ADR 0276](../adr/0276-stage-scaffold-owns-no-resources.md)
szerint a Stage layout nem birtokol erőforrást. Az A7 mércéje ezért a
**tulajdonos értesítése** (a controller `dispose`/kilépési útjának meghívása
MINDEN kilépési úton), nem egy presentation-rétegbe húzott `acquire`/`release`
pár. Utóbbi ADR 0276-sértés lenne, és `stopped`-ot érdemel.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-29–UI-31 és UI-33 teljes Stage/analitika folyamata szinkron-, loop- és
csak-lejátszás állapotokkal (SDD Ch13 Kör 25).

## 2. Jelenlegi állapot — mért tények

- Az R09 StageScaffoldja és az ADR 0274 óra-szabálya adott: a lejátszófej és a
  loop az **audio órából** vezetett.
- Az R22 ADR 0283 kimondta: az eredmény nem állíthat többet, mint amit mért.
- Nagy dalnál a kotta-nézet teljesítménye külön kockázat (a Ch13 maga jelzi).

## 3. Scope

**Benne van:** a tréner beállítása (szakasz, sebesség, loop, kísérőhang-keverés,
pontozási készenlét) · a tréner portrait / landscape / expanded kotta +
lejátszófej Stage-elrendezése · a dal-eredmény szakasz-bontása, nehéz szakaszok,
korrekciós akciók · a setlist részletnézete és **folyamatos futása**
hangolás-váltással · csak-lejátszás, gyenge jel, hiányzó eszköz, audio-hiba és
folytatás állapotok · **fake lejátszási órával** mért lejátszófej/loop szinkron.

**NINCS benne (tilos):** a pontozás vagy a lejátszás logikájának módosítása ·
DSP (AGENTS.md §9) · az import/szerkesztő (Kör 24) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

> ⚠ **A §0.0/B/B1 felülírja az alábbi három első sort.** A `songs/trainer/`,
> `songs/results/` és `setlists/run/` előtag a fán NEM létezik; az érvényes
> lista az `ai-router` blokkban van.

| Útvonal | Indok |
|---|---|
| `song_trainer/presentation/screens/trainer_setup_screen.dart` | a tréner beállítása (§0.0/B/B1) |
| `song_trainer/presentation/screens/song_trainer_screen.dart` | a tréner Stage-elrendezése (§0.0/B/B1) |
| `song_trainer/presentation/screens/song_result_screen.dart` | a dal-eredmény (§0.0/B/B1) |
| `song_trainer/presentation/screens/setlist_session_screen.dart` | a folyamatos futás (§0.0/B/B1) |
| `song_trainer/presentation/widgets/` — **10 nevesített** fájl | pontosan azok, amiket a négy képernyő MA importál (§0.0/B/B1) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a tréner-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/songs/trainer/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a listaelem MARAD, de a **VÁRT diff ÜRES** (86 → 86): a migráció HELYBEN történik, új képernyő-fájl nem keletkezik (§0.0/B/B3) |
| `docs/rounds/e13-r25-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/song_trainer/` a fenti 14 nevesített fájlon kívül
(kiemelten `domain/**`, `data/**`, `application/**`, `public.dart`) ·
`lib/app/routing/**` · `lib/features/practice/**` ·
`lib/core/design_system/**` · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A csak-lejátszás NEM kap pontszámot

Ha nem volt bemeneti jel (mikrofon kikapcsolva, csak hallgatás), az eredmény
ezt kimondja — nem ad kitalált százalékot. Az ADR 0283 §1 folytatása.

**NEM elfogadható gyengítés:** nulla vagy „N/A" helyett becsült pontszám „hogy
legyen mit mutatni". Ez a projekt legveszélyesebb hibaosztálya: magabiztos
hazugság.

### 5.2 A lejátszófej és a loop az AUDIO ÓRÁBÓL vezetett

Az ADR 0274 kötelező alkalmazása. A vizuális loop-határ és a hallható
loop-határ ugyanaz — fake órával determinisztikusan mérve.

**NEM elfogadható gyengítés:** külön `Timer` a lejátszófejnek. Hosszú dalon
látványosan elcsúszik.

### 5.3 A szünet PONTOS helyről folytat

Nem a szakasz elejéről és nem néhány másodperccel arrébb. A folytatás pozíciója
a lejátszási óráé.

### 5.4 A setlist hangolás-váltása ELŐRE jelzett

Ha a következő dal más hangolást igényel, a felhasználó **azelőtt** tudja meg,
hogy belekezdene — fellépés közben ez a legfontosabb átmenet.

### 5.5 Az orientációváltás MEGŐRZI az állapotot

Portrait ↔ landscape váltás nem indítja újra a lejátszást és nem veszíti el a
loop-beállítást.

### 5.6 A Stage route-ok takarítása zöld

Minden kilépési úton felszabadul a lejátszás és az audio-fókusz (az ADR 0276
folytatása).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A csak-lejátszás nem kap pontszámot, és ezt kimondja | `playback_only_result_test.dart` |
| A2 | A lejátszófej az audio órából vezetett (fake órával mérve) | `playhead_loop_sync_test.dart` |
| A3 | A vizuális és a hallható loop-határ egyezik | ugyanott |
| A4 | A szünet pontos helyről folytat | ugyanott |
| A5 | A setlist hangolás-váltása előre jelzett | `setlist_run_test.dart` |
| A6 | Az orientációváltás megőrzi a lejátszási és loop-állapotot | `trainer_setup_test.dart` |
| A7 | A Stage route elhagyásakor a lejátszás és az audio-fókusz felszabadul | `setlist_run_test.dart` |
| A8 | A beállítás validációja hibás szakasz/sebesség párost nem enged | `trainer_setup_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r25_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Becsült pontszám csak-lejátszásnál | **A1** |
| Külön `Timer` a lejátszófejnek | **A2** |
| A vizuális loop-határ a kerekített ütemhez igazítva | **A3** |
| A folytatás a szakasz elejéről | **A4** |
| A hangolás-váltás csak a dal indulásakor derül ki | **A5** |
| Az orientációváltás újraindítja a lejátszást | A6 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A lejátszófej-szinkron három kötelező cellája** (a küszöb: **100 ms**, az
ADR 0274 §3 szerint):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 40 ms eltérés | **elfogadva** |
| rajta (a küszöbön) | pontosan **100 ms** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 180 ms | **elutasítva** — a cella PIROS |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj becsült pontszámot
csak-lejátszás módban → az **A1** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/songs/trainer/trainer_setup_test.dart test/features/songs/trainer/playhead_loop_sync_test.dart test/features/songs/trainer/playback_only_result_test.dart test/features/songs/trainer/setlist_run_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart test/features/song_trainer/presentation/song_trainer_screen_test.dart test/features/song_trainer/presentation/song_result_screen_test.dart test/features/song_trainer/presentation/song_trainer_accessibility_test.dart test/features/song_trainer/application/setlists/setlist_session_controller_test.dart test/app/routing/app_router_test.dart test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-sáv KÜLÖN, az x86 konténerben fut (§0.0/B/B5, ADR 0426 §3)** — a
golden-útvonal szándékosan NINCS a fenti sorban:

```bash
tools/golden-x86.sh check test/ui/goldens/e13_r25_screens_golden_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

> ⚠ **A §0.0/B/B5 felülírja az alábbi parancsot.** Az `--update-goldens` ezen az
> **aarch64** boxon TILOS (ADR 0426, [L493](../LESSONS.md#l493)): a felvétel a
> merge-kapu **x86_64** architektúráján történik.

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r25_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A9 nem teljesült. A
márkabetűtípusok a teszt-hostban nem töltődnek be (fallback face); ez a
meglévő golden-teszt mért viselkedése, az elrendezést, méretezést és színeket
nem érinti. MIÉRT ez a kör dolga és nem az E13-R36-é: a záró vizuális
regressziós kör csak azt tudja megmondani, hogy valami MEGVÁLTOZOTT — azt,
hogy a képernyő eleve csúnya-e, a saját körében kell látni.

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. A tréner beállítása + validáció.
2. A Stage-elrendezés (kotta + lejátszófej) három orientációban.
3. A lejátszófej/loop szinkron fake órával + a három cella.
4. A csak-lejátszás eredmény-ága — pontszám NÉLKÜL.
5. A dal-eredmény szakasz-bontása és korrekciós akciói.
6. A setlist folyamatos futása, előre jelzett hangolás-váltással.
7. Golden felvétele: `tools/golden-x86.sh record …` (§7, §0.0/B/B5), a PNG-ket
   commitolni.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint, majd `tools/golden-x86.sh check …`.

## 9. Kockázatok

- **A kitalált pontszám.** Csak-lejátszásnál „üresnek" tűnik az eredmény, és a
  kitöltése hazugság lenne (A1).
- **A `Timer`-es lejátszófej.** Rövid teszt-dalon nem látszik, hosszún
  látványosan elcsúszik (A2).
- **A kotta-nézet teljesítménye.** Nagy dalnál külön profilozandó — ha akadozik,
  a §10-ben rögzítendő, nem elhallgatandó.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
