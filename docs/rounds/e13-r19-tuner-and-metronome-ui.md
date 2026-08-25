# E13-R19 — Tuner és Metronome UI migráció

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ e9a2c8b2`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 19
- **Kör-azonosító:** `E13-R19`
- **Branch:** `<motor>/e13-r19-tuner-and-metronome-ui`
- **Előfeltétel:** `E13-R18` merge-elve (Live Stage)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — az ADR 0274 (audio óra) és 0280 érvényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES hangmagasság-
> becslő kimenetét (a YIN-alapú réteg típusa és mezői), mert a §6 A1 cellája
> erre a kimenetre képez UI-állapotot. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/tuner/",
  "lib/features/metronome/",
  "lib/core/design_system/components/music/ss_tuner_gauge.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/features/tuner_en.arb",
  "lib/l10n/features/tuner_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/metronome/metronome_screen_test.dart",
  "test/features/tuner/cents_gauge_semantics_test.dart",
  "test/features/tuner/manual_string_pin_test.dart",
  "test/features/tuner/reference_tone_test.dart",
  "test/features/tuner/string_chips_test.dart",
  "test/features/tuner/tuner_screen_error_test.dart",
  "test/features/tuner/tuning_selector_test.dart",
  "test/features/tuner/tuner_ui_mapping_test.dart",
  "test/features/tuner/tuner_route_cleanup_test.dart",
  "test/features/metronome/metronome_beat_sync_test.dart",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "docs/rounds/e13-r19-tuner-and-metronome-ui.md",
]
gate_tests = [
  "test/features/tuner/tuner_ui_mapping_test.dart",
  "test/features/tuner/tuner_route_cleanup_test.dart",
  "test/features/metronome/metronome_beat_sync_test.dart",
  "test/ui/goldens/e13_r19_screens_golden_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/shell_lifecycle_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/tooling/dio_factory_guard_test.dart",
  "test/tooling/preferences_plugin_import_guard_test.dart",
  "test/tooling/route_literal_guard_test.dart",
  "test/features/today/hub_navigation_test.dart",
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

**Kockázat = high, indoklás:** a hangoló a mikrofon-erőforrást (authorization) tartja nyitva; a hangmagasság- és cent-kijelzés igazmondása mérce.

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör fája ma **19** l10n-kulcsot használ, és mind feloldható: `tuner` = 14 kulcs, `app` = 5 kulcs.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `metronome` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek
- `tuner` → a MÁR LÉTEZŐ `features/tuner_*.arb` fragmentum

Az aggregátum a listán MARAD, de **kizárólag generált kimenetként**
(`dart run tool/gen_l10n_segments.dart --write`); a merge-elt precedens
egységesen a forrást ÉS a regenerált aggregátumot is commitolja (E09-R26
`df0ad3dd`, E13-R12 `376b8a1d`, E13-R10 `b11ab2ed`). **Új fragmentum NEM
készül**, ezért a `test/l10n/arb_parity_test.dart` beégetett szegmens-listáját
sem kell bővíteni — a felvett források mind szerepelnek benne.

### R2 — a kör SAJÁT feature-fáján élő, ma zöld widget-tesztek (FELVÉVE)

Ezek közvetlenül a migrálandó képernyőkre állítanak, tehát a migráció után
pirosra váltanának, ami a §0 szerint `blocked` lenne:

  - `test/features/metronome/metronome_screen_test.dart`
  - `test/features/tuner/cents_gauge_semantics_test.dart`
  - `test/features/tuner/manual_string_pin_test.dart`
  - `test/features/tuner/reference_tone_test.dart`
  - `test/features/tuner/string_chips_test.dart`
  - `test/features/tuner/tuner_screen_error_test.dart`
  - `test/features/tuner/tuning_selector_test.dart`

**A jogosultság szűk:** a teszteket az ÚJ widgetekre kell ráállítani. A lefedett
viselkedést gyengíteni, cellát törölni vagy `skip`-elni **TILOS** — az a mérce
meggyengítése, amit a gate-guard emberhez eszkalál.

### R3 — keresztmetszeti tesztek (NEM kerültek listára — figyelmeztetés)

A kör fájára hivatkozó további widget-tesztek közös infrastruktúrán élnek
(`test/app/**`, `test/core/**`, más feature-ek fái) — 7 ilyen fájl van. Ezeket a kör
**NEM** szerkesztheti: ha egy elbukik, az `blocked` jelzés és célzott
brief-revízió, nem csendes átírás. A körbe húzásuk a scope-fegyelem feladása
lenne.

### R4 — a képernyő-leltár őre (H3 önjavító kör, ADR 0112, 2026-08-25)

A `test/ui/ui_inventory_test.dart` **repó-szintű** őr: a `tool/ui_inventory.dart`
a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z) `lib/features/metronome/`, `lib/features/tuner/` könyvtár-előtag
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

### S11 — az örökség-képernyőt PINNELŐ, listán kívüli tesztek (2026-08-25)

A kör lecserél legalább egy MEGLÉVŐ képernyőt, amelynek a TÍPUSÁT a brief
listáján kívül élő teszt pinneli. Mérve a `tools/brief-lint.py` `S11`
szabályával (import ÉS típusnév együtt), a `main @ b28bb1bf` fán:

- `test/app/navigation/adaptive_scaffold_test.dart`
- `test/app/navigation/legacy_route_redirect_test.dart`
- `test/app/offline_network_guard_test.dart`
- `test/app/routing/shell_lifecycle_test.dart`
- `test/core/screen_size_guard_test.dart`
- `test/ui/ui_baseline_screenshot_test.dart`

Ez pontosan az a halt-osztály, amelyik az **E13-R16/F9**-et (full-gate
32867296946, `hasLength(79)` vs 81) és az **E13-R17/H3**-at (`flutter test
test/app/navigation/` +33 → +30 -3) megállította: az őr a listán kívül él, a
felvétele az orchestrátornak TÁGÍTÁS ([L478](../LESSONS.md)), tehát a kör H3-ban
áll meg, mielőtt egyetlen sor kód megszületne. A fenti fájlok ezért mostantól
az `allowed_paths`-on ÉS a `gate_tests`-en is szerepelnek.

**A jogosultság PONTOSAN a lecserélt képernyő típusának átírása.** Cella
törlése, `skip`-je, küszöb-lazítása vagy az állítás gyengítése TILOS — az a
mérce meghamisítása. Ha a kör bizonyíthatóan nem cseréli le a képernyőt, a kör
pre-flightja mondja ki ezt a mérést, és hagyja a cellákat érintetlenül.

**Kiegészítés (az E13-R17 merge UTÁN újramérve):** a `4235f636` körrel új őr került a fába, ami szintén pinneli a kör képernyőit — `test/features/today/hub_navigation_test.dart` —, ezért az is felkerült mindkét listára és a §7 parancsba.

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
- `test/l10n/hardcoded_string_guard_test.dart`
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

### R5 — a kör-indító pre-flight ÚJRAMÉRÉSE (2026-08-25, `main @ b266f5cc`)

A fenti revíziók a `main @ 41fbd40` / `b28bb1bf` fán készültek. Ez a szakasz a
kör tényleges indulási fáján mér újra, és elvégzi a fejlécben KÖTELEZŐVÉ tett
hangmagasság-becslő-mérést. **Visszakeresett előzmény:**
[L488](../LESSONS.md) (a szomszéd kör merge-e új őrt hozhat → újramérés, és a
feloldás a típus HELYBEN tartása), [L486](../LESSONS.md) (a golden a
RASZTERIZÁLÁST rögzíti — seed-származtatott szín nagy felületen box↔CI diffet
ad), [L465](../LESSONS.md)/[L420](../LESSONS.md)/[L397](../LESSONS.md) (a
képernyő-leltár egzakt száma), [L489](../LESSONS.md) (a dispatch adja át a
motor-nyilvántartás őr-küszöbeit; korai `progress` + inkrementális commit),
[ADR 0274](../adr/0274-motion-driven-by-the-audio-clock.md) (a ritmus-animációt
az audio óra hajtja), [L444](../LESSONS.md) (a PULL-alapú órán a ticker
leállítása néma no-op).

#### R5.1 A hangmagasság-becslő TÉNYLEGES kimenete (a fejléc kötelező mérése)

`lib/features/tuner/model/tuner_reading.dart` — az A1 cellája ERRE képez
UI-állapotot:

| Mező / getter | Típus | Mért jelentés |
|---|---|---|
| `note` | `String` | a legközelebbi hang neve; **üres**, ha nincs jel |
| `cents` | `double` | −50..+50, **negatív = mély** |
| `frequencyHz` | `double` | mért frekvencia |
| `hasSignal` | `bool` | `note.isNotEmpty` |
| `inTune` | `bool` | `hasSignal && cents.abs() <= inTuneCents` |
| `TunerReading.inTuneCents` | `static const double` | **5** |
| `TunerReading.silent` | `static const` | a nincs-jel konstans |

A §6 „hangolt" cellahármasa ezzel **egyezik**: a `<=` miatt a ±5 cent
határ INKLUZÍV, tehát a „rajta" cella elvárása (hangolt) a kód mért
viselkedése, nem feltételezés. **Brief-revízió nem szükséges** — a §6
változatlan.

A képernyő-szintű állapotforrások (mind a mai `tuner_screen.dart`-ból mérve):
`tunerReadingProvider` → `AsyncValue<TunerReading>` (a hiba-ág
`readingAsync.hasError`, ma `MicErrorBanner` + `ref.invalidate`),
`micPermissionProvider` (ma `MicPermissionBanner`), `pinnedStringProvider`
(kézi cél), `tunerTuningProvider`, `tuningReferenceProvider` (A4 Hz),
`InTuneLock` (`holdReadings = 6`, egyszer tüzelő „bezárult" esemény).

**Az „instabil" állapotnak NINCS mezője a becslő kimenetén.** A §3-ban felsorolt
hat állapot közül ötnek van közvetlen forrása (idle/hallgató = `!hasSignal`,
nincs hangmagasság = `AsyncLoading`/`silent`, hangolt = `inTune`, referenciahang
= a `pinned != null` ág). Az „instabil" ezért **kizárólag a UI-rétegben
származtatható** (pl. az `InTuneLock` újra-élesedése vagy egy UI-oldali
stabilitás-heurisztika a `cents` sorozatán), és a származtatás a kör
`allowed_paths`-án belül marad. **A becslőt (`engine/dsp/**`) módosítani TILOS**
(§3, AGENTS.md §9) — ez a §3 tiltásának megerősítése, nem tágítása.

#### R5.2 A metronóm MA sem `Timer.periodic` — a mérce a PORT, nem az átírás

Mért tények (`lib/features/metronome/`):

- `metronome_screen.dart` ma `Ticker` (`createTicker`) + a **fázistartó**
  `BeatClock`-ot (`beat_clock.dart`, `beatsAt/setBpm/reset`) használja; a
  kattintás és a vizuális `_BeatDot` UGYANABBÓL a `_onTick`-ből jön.
- A design system a portot MÁR tartalmazza: `SsBeatClock`
  (`abstract interface class`, egyetlen tagja `Duration? get position`) és
  `SsBeatPulse` (`lib/core/design_system/motion/ss_beat_pulse.dart`), mindkettő
  exportálva a `public.dart`-on. `SsBeatPulse.syncTolerance = 100 ms`,
  `SsBeatPulse.isWithinSyncTolerance(...)` tiszta függvény, `SsBeatPulse.dotKey`
  a rögzített kulcs. Futó fogyasztói precedens:
  `lib/features/live/widgets/beat_counter.dart`.

**Amit ez a körre nézve JELENT (szűkítés):** az A4 teljesítése nem a
metronóm időzítésének átírása (azt a §3 tiltja), hanem egy `SsBeatClock`
**adapter** a meglévő `BeatClock`/`Ticker` fölé a `lib/features/metronome/`
fán, és a vizuális ütem ezen keresztüli hajtása. A `metronome_beat_sync_test.dart`
fake órája ezt az adaptert/`SsBeatClock` implementációt táplálja — nem a
kattintás-ütemezést. **A hangzó klikk időzítése bitre változatlan marad.**

⚠ [L444](../LESSONS.md): az `SsBeatClock` **pull-alapú** — a fogyasztó minden
frame-en lekérdezi a `position`-t. Egy „ne pörögjön feleslegesen" ticker-stop
ezen a porton néma no-op (a leállított ticker soha nem indul újra). Ne
optimalizáld.

#### R5.3 Típus-HELYBEN-tartás — SZŰKÍTÉS, három őr egyszerre semlegesítve

Az `S11`-mérés a mai fán (`grep -rln` a `test/` fán) **változatlanul** a brief
listáján lévő fájlokat adja — a szomszéd sáv NEM hozott új őrt:

```
TunerScreen      → 12 fájl   (mind az allowed_paths-on)
MetronomeScreen  →  5 fájl   (mind az allowed_paths-on)
CentsGauge       →  2 teszt  (mind az allowed_paths-on)
```

A kör ezért — [L488](../LESSONS.md) mintájára — **kötötten helyben migrál**:

| Kötés | Mért következmény |
|---|---|
| `lib/features/tuner/screens/tuner_screen.dart` útvonala és a publikus `TunerScreen` típusnév VÁLTOZATLAN | a 12 `find.byType(TunerScreen)` pin zöld marad |
| `lib/features/metronome/screens/metronome_screen.dart` + `MetronomeScreen` VÁLTOZATLAN | az 5 pin zöld marad |
| a kör **NEM hoz új** `lib/features/**/*_screen.dart` fájlt | `test/ui/ui_inventory_test.dart` `hasLength(84)` (mért: `find lib/features -name '*_screen.dart' \| wc -l` → **84**) NEM mozdul |

Ez **szűkítés**, tehát az orchestrátor saját hatásköre (ADR 0087 §2). Az
`allowed_paths` listán a fenti őrfájlok MARADNAK (a lista szűkítése nem
kötelező), de a várt kimenet az, hogy a kör **egyiküket sem szerkeszti**: a
`git diff --name-only` a kör végén a `test/app/**`, `test/core/**`,
`test/ui/ui_inventory_test.dart` és `test/features/today/**` útvonalakon
**üres**. Ha a kör mégis szerkeszteni akarná valamelyiket, az azt jelenti, hogy
a fenti kötést megsértette → `stopped` jelzés, nem csendes átírás.

#### R5.4 Golden-szabály a mért box↔CI eltérés ellen ([L486](../LESSONS.md))

Az A8 két goldenje (412×915 compact portrait + `textScaleFactor: 2.0`) a
`test/ui/goldens/e13_r18_screens_golden_test.dart` mintáját kövesse
(`AppTheme.dark()`, `MaterialApp` a felvétel gyökere,
`matchesGoldenFile('goldens/<név>.png')`). **Kötelező szabály:** a felvett
képernyők nagy, EGYBEFÜGGŐ kitöltései **konstans színforrásból** jöjjenek
(`AppColors`, `context.palette`), NE `Theme.of(context).colorScheme.*`
seed-származtatott tónusból (`ColorScheme.fromSeed` → HCT lebegőpont) — ez
mérve 5–12%-os box↔CI diffet ad, ami csak az exact-SHA Full Gate-en bukik ki,
javító kör árán. A tipográfia (`fontFamily`, szintetikus súly) és a
`withValues(alpha:)` mérve hordozható.

#### R5.5 l10n — a 19 kulcs feloldása a mai fán

Mérve: a két képernyő + a `cents_gauge.dart` összesen **19** kulcsot hív; a
`metronome*` **5** kulcs a `lib/l10n/base/app_{en,hu}.arb` szegmensben, a
`tuner*` **14** kulcs a `lib/l10n/features/tuner_{en,hu}.arb` fragmentumban él
— pontosan úgy, ahogy az R1 leírja. Új szöveg ugyanide megy, majd
`dart run tool/gen_l10n_segments.dart --write` regenerálja az aggregátumot.

#### R5.6 Nincs új ADR

Az `ADR 0274` (audio óra) és `ADR 0280` (felolvasható cents) érvényes és
merge-elt; a kör ezek ALKALMAZÁSA, nem új döntés. A sor-fájl `adr` oszlopa
`nincs`, foglalás nem történt.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A hangoló és a metronóm (UI-09–UI-10) átállítása a közös Stage-komponensekre,
**pontos audio-óra** és hozzáférhető viselkedés mellett (SDD Ch13 Kör 19).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0274 kimondta: a ritmus-animáció az audio órából jön, nem külön
  `Timer`-ből — a metronóm ennek a legkritikusabb alkalmazása.
- Az ADR 0280 kimondta: a tuner cents-eltérése **felolvasható** kell legyen.
- A tap tempo kiugró-érték kezelése meglévő, tesztelt viselkedés.

## 3. Scope

**Benne van:** `SsTunerGauge` és hangolás/húr-választó · a hangoló idle,
hallgató, nincs hangmagasság, instabil, hangolt és referenciahang állapotai ·
a metronóm fő BPM/ütem/transport elrendezése (a haladó beállítások **lapra**
kerülnek) · az ütem-vizualizáció az **audio óra állapotához** kötve · landscape
és expanded elrendezés · a route elhagyásakor audio-fókusz és erőforrás
felszabadítása.

**NINCS benne (tilos):** a hangmagasság-becslő vagy a metronóm időzítésének
módosítása (AGENTS.md §9) · a tap tempo kiugró-kezelés viselkedésének
megváltoztatása · más képernyők migrációja · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/tuner/` | a hangoló UI-migrációja |
| `lib/features/metronome/` | a metronóm UI-migrációja |
| `components/music/ss_tuner_gauge.dart` | **ÚJ** — a mutató |
| `public.dart` | az export bővítése |
| `lib/l10n/features/tuner_{en,hu}.arb` | **FORRÁS** — a hangoló/metronóm szövegek (`tuner` MÁR migrált feature) |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — kizárólag a **metronóm** szövegei (a `metronome` még nem migrált feature; a hangolóé a `tuner` fragmentumba megy) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/…` (7 meglévő teszt) | ma zöld, a migrált képernyőkre állítandó — lásd §0.0 R2 |
| `test/features/**` (3) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r19-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` a két érintett KIVÉTELÉVEL · a DSP- és
időzítés-paraméterek bárhol · `lib/core/theme/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A cents-eltérés IRÁNYA szöveges

„12 centtel mély" — nem csak egy elmozduló mutató. Az ADR 0280 §3
kikényszerítése.

**NEM elfogadható gyengítés:** csak a grafikus mutató, mert „az intuitívabb".
Felolvasóval használhatatlan, és nagy betűméret mellett is nehezen olvasható.

### 5.2 A „hangolt" visszajelzés TÖBBCSATORNÁS

Szín + ikon/szöveg (és ahol elérhető, haptika). Nem csak a mutató zöldre
váltása.

### 5.3 Az ütem-vizualizáció NEM külön `Timer`

Az ADR 0274 kötelező alkalmazása: a vizuális ütem az audio óra állapotát követi
— fake órával determinisztikusan tesztelve.

**NEM elfogadható gyengítés:** `Timer.periodic` a BPM-ből. Ez mérve elcsúszó
metronómot ad, ami a funkció lényegét semmisíti meg.

### 5.4 A referenciahang a route elhagyásakor LEÁLL

Nem szólhat tovább háttérben. Az audio-fókusz is felszabadul.

### 5.5 A tap tempo kiugró-kezelése VÁLTOZATLAN

Meglévő, tesztelt viselkedés — a UI-migráció nem érinti.

### 5.6 A haladó beállítások LAPRA kerülnek

A fő felület a BPM, az ütem és a transport. Az R13 overlay-rendszere adja a
lapot.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A hangmagasság-kimenet UI-állapotra képzése helyes minden ágon | `tuner_ui_mapping_test.dart` |
| A2 | A cents-eltérés iránya szövegesen is megjelenik | ugyanott |
| A3 | A „hangolt" visszajelzés több csatornán érkezik | ugyanott |
| A4 | Az ütem-vizualizáció az audio órához kötött (fake órával mérve) | `metronome_beat_sync_test.dart` |
| A5 | A referenciahang és az audio-fókusz a route elhagyásakor felszabadul | `tuner_route_cleanup_test.dart` |
| A6 | A tap tempo kiugró-kezelése változatlan | a meglévő tesztek zöldek |
| A7 | 2.0 text scale és landscape mellett nincs túlcsordulás | `tuner_ui_mapping_test.dart` |
| A8 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r19_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak grafikus mutató, szöveg nélkül | **A2** |
| A „hangolt" csak zöld szín | **A3** |
| `Timer.periodic` az ütemre | **A4** |
| A referenciahang tovább szól kilépés után | **A5** |
| A kiugró tap tempo átírása | A6 |
| Fix magasságú hangoló-fejléc | A7 |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A8** |

**A „hangolt" tartomány három kötelező cellája** (a küszöb: **±5 cent**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | ±3 cent | **hangolt** |
| rajta (a küszöbön) | pontosan **±5 cent** | **hangolt** (a határ inkluzív) |
| a küszöb fölött | ±9 cent | **nem hangolt** — irány szövegesen |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az
ütem-vizualizáció forrását `Timer.periodic`-ra → az **A4** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/tuner/tuner_ui_mapping_test.dart test/features/tuner/tuner_route_cleanup_test.dart test/features/metronome/metronome_beat_sync_test.dart test/ui/goldens/e13_r19_screens_golden_test.dart test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/app/routing/shell_lifecycle_test.dart test/core/screen_size_guard_test.dart test/ui/ui_baseline_screenshot_test.dart test/core/architecture_dependency_test.dart test/l10n/hardcoded_string_guard_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart test/features/today/hub_navigation_test.dart
```

**A golden-felvétel (A8) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

```bash
~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r19_screens_golden_test.dart
```

A keletkezett PNG-ket **commitolni kell** — enélkül az A8 nem teljesült. A
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

1. A hangmagasság-kimenet → UI-állapot leképezés + a ±5 cent cellák.
2. `ss_tuner_gauge.dart` + a szöveges irány és a többcsatornás visszajelzés.
3. A hangoló hat állapota, húr- és hangolás-választóval.
4. A metronóm elrendezése; a haladó beállítások lapra.
5. Az ütem-vizualizáció audio órához kötve, fake órás cellával.
6. Route-elhagyás: referenciahang + audio-fókusz felszabadítása.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `Timer`-es metronóm.** A legkézenfekvőbb implementáció, és mérve
  elcsúszik — pont a funkció lényegén (A4).
- **A tovább szóló referenciahang.** Kilépés után is hallható, és a
  felhasználó nem találja, mi szól (A5).
- **A csak grafikus hangoló.** Intuitívnak tűnik, és felolvasóval semmit nem
  mond (A2).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`), effort=medium.

### 10.1 Mit implementáltam

**Tuner (`lib/features/tuner/`)** — `tuner_screen.dart` helyben migrálva
`SsStageScaffold`-ra (útvonal és `TunerScreen` típusnév változatlan, §0.0/R5.3):

- `statusHeader`: vissza-gomb (`Navigator.canPop` mögött) + cím + a hangolás-
  választó popup + mic-engedély/hiba bannerek (változatlan logika).
- `hero`: idle állapotban `l10n.tunerListening`; egyébként a nagy hangnév
  (`FittedBox`-ba csomagolva az A7 miatt) + Hz + `CentsGauge`.
- `feedback`: **ÚJ** `_TunerFeedback` — a látható, többcsatornás visszajelzés
  (ikon + szín + szöveg) a négy `TunerUiState` ágra (`idle` itt nem renderel).
- `timeline`: a húr-chipek sora (`_StringChips`, tartalmilag változatlan).
- `bottomAction`: referenciahang gomb (pin esetén) + A4 felirat.
- **ÚJ** `lib/core/design_system/components/music/ss_tuner_gauge.dart`
  (`SsTunerGauge`) — a mutató design-system komponense, palette-driven
  (színeket a hívó adja), a `cents_gauge.dart` most erre épül (a `CentsGauge`
  publikus API-ja és szemantika-szövegei változatlanok, ezért a
  `cents_gauge_semantics_test.dart` módosítás nélkül zöld maradt).
- **ÚJ** `lib/features/tuner/model/tuner_ui_state.dart` (`TunerUiState` enum +
  `tunerUiStateOf` tiszta függvény) és `tuner_stability.dart`
  (`TunerStability` — az „instabil" állapot UI-rétegbeli származtatása,
  same-note cents-ugrás küszöbbel; a becslő kimenetét NEM módosítja).
- **ÚJ** `lib/features/tuner/providers/reference_tone_provider.dart`
  (`ReferenceTonePlayer`/`RealReferenceTonePlayer` +
  `referenceTonePlayerProvider`, `Provider.autoDispose`, `ref.watch`-olva a
  buildban) — a tuner most SAJÁT hangot játszik (nem a `learn/`-beli megosztott
  `Backing`-et), mert A5 megköveteli a leállítást route-elhagyáskor, a
  `Backing` viszont app-szintű singleton (`lib/features/learn/**` tiltott
  zóna, nem módosítható). Az `AudioPlayer` **lazy** (csak `.play()`-kor jön
  létre) — enélkül minden Tuner-mountoló teszt (ami nem override-olja a
  providert) platform-channel `MissingPluginException`-t dobott volna a
  golden tesztben (mérve, ld. 10.3).

**Metronome (`lib/features/metronome/`)** — `metronome_screen.dart` helyben
migrálva (útvonal és `MetronomeScreen` típusnév változatlan):

- `statusHeader`: vissza-gomb + cím + „Advanced settings" (`Icons.tune`) ikon.
- `hero`: BPM felirat + `−`/csúszka/`+` (a §5.6 „fő BPM").
- `feedback`: **ÚJ** `BeatPulseDot` — az audio-órához kötött vizuális pulzus
  (a §5.6 „ütem"-viualizáció, A4).
- `timeline`: a meglévő per-bar `_BeatDot` sor (a `_currentBeat`-ből, ami MA
  is a `BeatClock`/`Ticker`-ből jön — időzítés bitre változatlan).
- `bottomAction`: tap tempo + start/stop (változatlan, §5.5).
- Az ütemmutató (2/4…6/4) a haladó-beállítások lapra került
  (`showModalBottomSheet`, ld. 10.2) — az `SsChoice<int>` (segmented) adja a
  választót; a főfelület csak BPM+ütem-vizualizáció+transport (§5.6).
- **ÚJ** `lib/features/metronome/beat_pulse_dot.dart`:
  `MetronomeBeatClockAdapter implements SsBeatClock` — a `position` getter a
  MEGLÉVŐ `BeatClock`/`Ticker` ugyanazon elapsed-secs értékét adja vissza,
  amit a kattintás-ütemezés is használ (`_lastSecs`), tehát a vizuális pulzus
  SOSEM csúszhat el a hangzó klikktől. `BeatPulseDot` a design rendszer
  `SsBeatPulse`-jának pull-every-frame logikáját tükrözi, DE explicit
  `playing: bool` paraméterrel kapcsolja a saját tickerét (ld. 10.2 — miért
  szükséges ez az eltérés).

### 10.2 Két mért, a brief-ben nem jelzett csapda — és a feloldásuk

1. **`SsBeatPulse` és `SsOverlayHost.showSheetSurface` az `AppTheme` alatt
   ÖSSZEOMLIK.** Mindkettő a design-system `SsColorScheme`/`SsThemeBehavior`
   téma-extension-jeit olvassa (`Theme.of(context).extension<X>()!`), amiket
   KIZÁRÓLAG az `SsDarkTheme`/`SsLightTheme` regisztrál — az app tényleges
   futásidejű témája, az `AppTheme` (`lib/core/theme/app_theme.dart`), csak az
   `AppPalette`-et regisztrálja (ugyanaz a tény, amit az E13-R18 handoff már
   leírt az `SsChordHero`/`SsTempoDisplay` kapcsán, csak ott a KOMPONENS
   tervezése kerülte el a függést — az `SsBeatPulse`/`SsOverlayHost` viszont
   MÁR nem, és ennek a körnek volt az első tényleges fogyasztója egyiknek is).
   Mérve: `_SsBottomSheetSurface` `SsElevation.resolve`-ban null-check hibával
   bukik; az `SsBeatPulse` widget maga csak `test/core/design_system/motion/
   ss_beat_pulse_test.dart`-ban fut, ami `SsDarkTheme`-mel csomagol — sosem
   `AppTheme`-mel. Mindkét design-system fájl (`motion/ss_beat_pulse.dart`,
   `components/overlays/ss_overlay_host.dart`) a kör tiltott zónájában van,
   nem javítható itt. **Feloldás:** a metronóm SAJÁT `BeatPulseDot`-ot kapott
   (palette-driven, nincs `SsColorScheme` függés) és a haladó-beállítások
   `showModalBottomSheet`-tel nyílik (`SsOverlayHost` helyett) — mindkettő a
   kör saját fáján belül marad, a design-system fájlokhoz nem nyúltam.
2. **`BeatPulseDot`-nak NEM szabad örökké pörögnie.** Az `SsBeatPulse`
   mintája (L444) szerint a fogyasztó tickere sosem áll le, mert nincs
   pozitív "resume" jelzése. A metronóm esetében viszont VAN — a `_playing`
   mező pontosan tudja, mikor fut a lejátszás —, és enélkül a
   `MetronomeScreen`-t útvonalba állító BÁRMELY teszt (pl.
   `test/app/navigation/adaptive_scaffold_test.dart`, amit nem
   szerkeszthetek) `pumpAndSettle()`-je végtelenségig futna (mérve: a saját
   `metronome_screen_test.dart`-om sheet-tesztje `pumpAndSettle timed out`
   hibával bukott, amíg ezt nem javítottam). Ezért a `BeatPulseDot` explicit
   `playing` paramétert kapott, ami `didUpdateWidget`-ben indítja/állítja a
   sajét tickerét — ez NEM ugyanaz a hiba, amit L444 tilt (ott nincs pozitív
   jelzés, itt van).

### 10.3 Egy mért riverpod-race a tuner tesztjeiben

A `tuner_screen_error_test.dart` „Retry restarts the engine" tesztje a
migráció UTÁN `engine.startCalls == 2`-t mért `pumpAndSettle()` után, ahol a
mérce 1-et várt Retry ELŐTT. Ok: a `flutter_riverpod` 3.3.2
`ProviderContainer.defaultRetry`-ja MINDEN nem-`Error` kivételre (tehát sima
`Exception`-re is) automatikus, 200 ms-tól induló visszapörgetést ütemez — ez
MÁR a meglévő `tunerReadingProvider`-ben is benne volt, csak a migrált
(mélyebb) widget-fa `pumpAndSettle()`-je most már 200 ms-nál TOVÁBB fut a
letelepedésig, így a saját automatikus retry begyújtott a teszt manuális Retry
gombja ELŐTT. Feloldás a tesztben: `pumpAndSettle()` helyett kötött,
nulla-időtartamú `pump()` hívások (nem haladtatják a szimulált órát), amíg a
fa letelepszik — ez a riverpod saját (a kör szempontjából irreleváns)
retry-jét sosem éri el, de a UI állapotváltásait igen. Ugyanez a minta jelent
meg két helyen az `overrideWithValue` kontra `overrideWith` különbségeként is:
`referenceTonePlayerProvider.overrideWithValue(fake)` megkerüli a provider
SAJÁT `create` törzsét — pont azt, ahol a `ref.onDispose(player.dispose)`
history regisztrálva van —, ezért `tone.disposed` sosem vált `true`-ra a teszt
route-elhagyás után. A javítás: `overrideWith((ref) { ref.onDispose(tone.
dispose); return tone; })` — a fake befecskendezve, de a valódi leiratkozási
út is lefut (`reference_tone_test.dart`, `tuner_route_cleanup_test.dart`).

### 10.4 Valódi-sértés próba (§6, kötelező)

`lib/features/metronome/beat_pulse_dot.dart` `_onTick`-jét ideiglenesen
átírtam, hogy a fed `SsBeatClock.position`-t figyelmen kívül hagyva a saját
Ticker `elapsed`-jéből (`Timer.periodic`-ekvivalens, a valódi órától
független) számolja a fázist. Eredmény:
`test/features/metronome/metronome_beat_sync_test.dart` 3 tesztje azonnal
PIROSRA váltott (`within tolerance: 0ms lag`, `at the boundary: 100ms lag`,
`the rendered size exactly matches the phase formula` — mind a fed
pozíciótól való eltérést mérték). Ezután a módosítást visszaállítottam
(`git diff` a fájlon üres a visszaállítás után), és a teszt újra 9/9 zöld.

### 10.5 §7 gate — csonkítatlan eredmény

`tools/round-gate.sh` mind a 22 lépése **ZÖLD**: `format`, `analyze`, a 17
megadott teszt-útvonal külön-külön, `architecture`, `secrets`, `l10n`. Ezen
felül a kör saját feature-fáinak teljes tesztkészlete külön hívásban:
`test/features/tuner/` **61/61 zöld**, `test/features/metronome/` **23/23
zöld**. `git diff --name-only origin/main...HEAD -- test/app/ test/core/
test/ui/ui_inventory_test.dart test/features/today/` **üres** (§0.0/R5.3
kötés betartva). `find lib/features -name '*_screen.dart' | wc -l` → **84**
(változatlan, nincs új képernyő-fájl).

### 10.6 Acceptance-mátrix (A1–A8)

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | `tunerUiStateOf` tiszta leképezés minden mért ágra (idle/unstable/inTune/outOfTune) + a három ±5 cent cella | ZÖLD |
| A2 | Látható (nem csak szemantikus) irány-szöveg (`_TunerFeedback`) | ZÖLD |
| A3 | Ikon + szín + szöveg együtt (`_TunerFeedback`), haptika a lockon | ZÖLD |
| A4 | `BeatPulseDot` az `SsBeatClock` adapteren keresztül, sosem `Timer.periodic` (valódi-sértés próbával bizonyítva) | ZÖLD |
| A5 | Mic-engine stop (autodispose) + `ReferenceTonePlayer` dispose route-elhagyáskor | ZÖLD |
| A6 | Tap tempo (`TapTempo`) érintetlen | ZÖLD (meglévő tesztek) |
| A7 | 2.0 text scale + landscape, nincs overflow (`tester.takeException()` null) | ZÖLD |
| A8 | 4 golden PNG (tuner + metronome × compact/scale2) felvéve és commitolva | ZÖLD |

## 11. Review — a Claude tölti ki
