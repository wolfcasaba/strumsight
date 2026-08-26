# E13-R27 — Analysis Overview, Timeline, Metric és Compare UI

- **Státusz:** FUT (pre-flight 2026-08-26, kód MÉRVE: `main @ 37c8f1a9`; eredetileg
  előre megírva 2026-08-15 `main @ c732ec75` ellen — a §0.0/B revízió hat mért
  eltérést old fel)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 27
- **Kör-azonosító:** `E13-R27`
- **Branch:** `<motor>/e13-r27-analysis-results-ui`
- **Előfeltétel:** `E13-R26` merge-elve (felvétel és feldolgozás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0286`](../adr/0286-charts-need-a-text-alternative.md)
  — **MÁR MERGE-ELT** (`6e7877de`, 2026-08-15), státusza *elfogadva*. A kör
  ADR-t **NEM ír**, csak hivatkozza: egy merge-elt ADR újraírása H1 (§0.0/B/B0).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el az elemzési eredmény
> TÉNYLEGES szerkezetét (verzió, mérőszámok, hiányzó/nem támogatott jelölés),
> mert a §5.1 „hiányzó metrika nem 0" cella a mért mezőkre épül. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  # §0.0/B/B1 — az eredeti `lib/features/analyze/results/` KÖNYVTÁR-előtag a
  # verziókövetett fán NEM létezik (S13 lint, L497 hibaosztály), ÉS rossz fát
  # céloz: a `lib/features/analyze/` a LEGACY V1 fa (egyetlen
  # `analyze_screen.dart` + `timeline_view.dart`, NULLA mérőszám-kártya, NULLA
  # összehasonlítás). A brief §3 által leírt eredmény-felületek MÉRHETŐEN a V2
  # `lib/features/audio_analysis/presentation/` fában élnek — ugyanaz a fa,
  # amit a MERGE-ELT E13-R26 brief a saját tilos zónájában szó szerint
  # „a Kör 27 öt eredmény-képernyője és widgetjeik" néven tartott fenn ENNEK a
  # körnek. A csere szigorúan KEVESEBB, mint a szomszéd, user-jóváhagyott
  # E13-R22 lista (ott `presentation/widgets/` ÉS `presentation/providers/` ÉS
  # a feature `public.dart`-ja is szerepelt): itt NINCS provider-réteg és NINCS
  # feature-`public.dart`, az export-képernyő pedig kimarad (§3-ban nem
  # szerepel → a szűkítés a §0.0 hatáskörében van).
  "lib/features/audio_analysis/presentation/analysis_overview_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_timeline_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_compare_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart",
  "lib/features/audio_analysis/presentation/widgets/",
  "lib/features/audio_analysis/presentation/controllers/",
  # §0.0/B/B2 — a lint S13 ESCAPE-ágán marad bent: ezt a három előtagot EZ a
  # kör hozza létre (diagram-komponensek, cél-tesztek, nagy idővonal-fixture).
  "lib/core/design_system/components/analytics/",
  "lib/core/design_system/public.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/analyze/results/metric_missing_test.dart",
  "test/features/analyze/results/timeline_virtualization_test.dart",
  "test/features/analyze/results/chart_semantics_test.dart",
  "test/features/analyze/results/compare_compatibility_test.dart",
  "test/fixtures/analyze/results/",
  "test/ui/goldens/",
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r27-analysis-results-ui.md",
]
gate_tests = [
  "test/features/analyze/results/metric_missing_test.dart",
  "test/features/analyze/results/timeline_virtualization_test.dart",
  "test/features/analyze/results/chart_semantics_test.dart",
  "test/features/analyze/results/compare_compatibility_test.dart",
  # §0.0/B/B3 — a MEGLÉVŐ, listán KÍVÜLI pinek: futtatni KELL, szerkeszteni
  # TILOS. Ebben a könyvtárban él mind a nyolc teszt, amely ma az öt
  # eredmény-képernyőre, a `metric_card`-ra, a `hotspot_navigator`-ra, az
  # `overview_view_model`-re és a `timeline_viewport`-ra állít. A kör
  # migrációja ezért ADDITÍV: a mai szerződéseket nem írja át.
  "test/features/audio_analysis/presentation/",
  # §0.0/B/B5 (ADR 0426 §3) — a golden-útvonal NEM kerül a lokális ARM-gate-re;
  # a lokális mérés egyetlen érvényes alakja:
  # `tools/golden-x86.sh check test/ui/goldens/e13_r27_screens_golden_test.dart`
  "test/ui/ui_inventory_test.dart",
  "test/core/architecture_dependency_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
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

**Kockázat = high, indoklás:** az elemzési eredmények a felhasználó felvételéből származó adatot jelenítik meg és exportálhatóvá teszik.

## 0.0/B BRIEF-REVÍZIÓ — 2026-08-26, E13-R27 pre-flight (`main @ 37c8f1a9`)

**Visszakeresett előzmény (ADR 0312 §4.9):** [L497](../LESSONS.md#l497) (nem
létező könyvtár-előtag az `allowed_paths`-on — most ÖTÖDSZÖR),
[L478](../LESSONS.md#l478) (a pre-flight csak SZŰKÍTHET, a tágítás H3),
[L486](../LESSONS.md#l486) + [L493](../LESSONS.md#l493) (a golden a
RASZTERIZÁLÁST rögzíti; ARM↔x86 diff → öt vak CI-kör),
[ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md) (a
goldent a merge-kapu architektúráján mérjük), [L443](../LESSONS.md#l443) (a
tiszta predikátumot hívó „küszöb-cella" a tiltott implementáción is zöld
marad), [L403](../LESSONS.md#l403) (a widget-TÍPUS szintjén mérő valódi-sértés
próba átengedi a tartalmi sértést), [L397](../LESSONS.md#l397) +
[L401](../LESSONS.md#l401) (a `ui_inventory` bázisvonal CI-only lelet),
[ADR 0283](../adr/0283-results-never-overstate-certainty.md),
[ADR 0282](../adr/0282-diagram-text-alternative-and-handedness.md),
[ADR 0286](../adr/0286-charts-need-a-text-alternative.md).

### B0 — a kiosztott ADR `0286` MÁR MERGE-ELT → a kör ADR-t NEM ír

A pipeline-prompt szerint az ADR-t a pre-flight írná meg, de a mérés mást ad:
`docs/adr/0286-charts-need-a-text-alternative.md` a fán van, **merge-elve**
(`6e7877de`, „docs(ch13): E13-R26..R29 briefek + ADR 0285-0287", 2026-08-15),
státusza *elfogadva*, és a §5 mind a hat kötött döntése szó szerint benne áll.
Egy merge-elt ADR újraírása **H1** (ADR 0087 §2). A kör tehát **ADR-t nem ír**,
és **új sorszámot sem foglal** — ez a sávon a tizedik ADR nélküli kör egymás
után (E13-R17…R27), azonos indokkal.

### B1 — a `lib/features/analyze/results/` előtag NEM LÉTEZIK, és rossz fát céloz

Mérve:

```
$ find lib/features/analyze -type d
lib/features/analyze/{application,engine,model,providers,screens,widgets}
```

`results/` **nincs** — a lista nulla fájlt fedett (S13 lint). A javítás azonban
NEM a `lib/features/analyze/results/` létrehozása, mert **két** analyze-fa van,
és a brief a MÁSIKAT írja le:

| | `lib/features/analyze/` (V1, legacy) | `lib/features/audio_analysis/presentation/` (V2, SDD Ch7) |
|---|---|---|
| eredmény-képernyők | `analyze_screen.dart` (EGY) | `analysis_{overview,timeline,compare,metric_detail,export}_screen.dart` (ÖT) |
| mérőszám-kártya | nincs | `widgets/metric_card.dart` + `OverviewMetricCard` **öt** állapottal |
| confidence | nincs | `widgets/confidence_badge.dart`, `ConfidenceBadgeLevel` |
| összehasonlítás | nincs | `engine/comparison/compatibility_evaluator.dart` + `ComparisonInconclusiveReason` |
| idővonal | `widgets/timeline_view.dart` (statikus) | `controllers/timeline_viewport.dart` (zoom/pan/reveal) + `widgets/timeline_{lane,lanes,ruler}.dart` |

Ugyanezt mondja ki a **merge-elt** E13-R26 brief tilos zónája szó szerint: „a
Kör 27 öt eredmény-képernyője és widgetjeik
(`audio_analysis/presentation/analysis_{overview,timeline,compare,metric_detail,export}_screen.dart`,
`presentation/widgets/`, `presentation/controllers/`)". A csere tehát nem
tágítás, hanem **ennek a körnek előre, írásban fenntartott** fája.

**Amit a csere elhagy (szűkítés):** az `analysis_export_screen.dart` és a
`presentation/capture/` (Kör 26) — az export a §3 scope-ban nem szerepel.

### B2 — a három ÚJ előtag a lint ESCAPE-ágán marad

`lib/core/design_system/components/analytics/`, `test/features/analyze/results/`
és `test/fixtures/analyze/results/` egyike sem létezik a fán — mindhármat **EZ
a kör hozza létre** (a lint S13 kimondottan megengedi, ha a §0.0 ezt kijelenti).
A `components/` mai gyerekei: `actions`, `ai`, `cards`, `feedback`, `inputs`,
`music`, `overlays`, `surfaces` — az `analytics/` a kilencedik.

### B3 — a nyolc MEGLÉVŐ pin-teszt: futtatni KELL, szerkeszteni TILOS

```
$ ls test/features/audio_analysis/presentation/
analysis_compare_screen_test.dart   analysis_overview_screen_test.dart
analysis_export_screen_test.dart    analysis_progress_view_test.dart
analysis_timeline_screen_test.dart  hotspot_navigator_test.dart
metric_card_test.dart               overview_view_model_test.dart
timeline_viewport_test.dart
```

Mind a kilenc a kör célfájára állít. A listára **NEM** kerülnek (az tágítás,
L478), hanem a `gate_tests` **pinjei** — pontosan az E13-R22 merge-elt alakja
(`test/features/practice/presentation/` mint listán kívüli pin-könyvtár).

**Következmény, amit be KELL tartani:** a kör migrációja **additív**. A mai
szerződések (`OverviewMetricCardState` öt állapota, a `MetricCard` reason/tip
ága, a `ConfidenceBadge`, a `TimelineViewport` zoom-invariánsai, a
`CompatibilityEvaluator` kilenc cellája) érintetlenek maradnak. Ha egy pin
elbukik, az `blocked` jelzés és célzott brief-revízió, **nem** a teszt átírása.

### B4 — `ui_inventory` bázisvonal: 89, és a kör NEM mozdítja

Mérve: `test/ui/ui_inventory_test.dart:14` → `hasLength(89)`, és
`find lib/features -name '*_screen.dart' | wc -l` → **89** (egyezik). Az öt
eredmény-képernyő **MA IS LÉTEZIK**, tehát a kör — az R26-tal ellentétben —
alapesetben **nem hoz új `*_screen.dart`-ot**, és a szám nem mozdul. A fájl a
listán MARAD (nem tágítás: eleve rajta volt), de a jogosultság változatlanul
**PONTOSAN a szám emelése** a ténylegesen mért értékre, ha a kör mégis új
képernyőt hoz. Minden más állítás érintetlen.

### B5 — a golden NEM fut a lokális ARM-kapun (ADR 0426, L486/L493)

Az eredeti `gate_tests` felsorolta a
`test/ui/goldens/e13_r27_screens_golden_test.dart`-ot; ez ezen a boxon (aarch64)
raszterizáció-eltérés miatt a CI-ban pirosra váltana, miközben lokálisan zöld —
E13-R17 és E13-R20 együtt **öt vak CI-kört** fizetett ki ezért. A merge-elt
E13-R22/R25/R26 precedens szerint a golden kikerül a lokális gate-sorból, és a
mérése:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r27_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r27_screens_golden_test.dart
```

A PNG-ket commitolni kell (A9), és a CI-oldali Full Gate futtatja a goldent
élesben. A `flutter test --update-goldens` a §7-ben leírt alakja ezen a boxon
**érvénytelen** — a fenti két parancs lép a helyére.

### B6 — az acceptance-cellák a MÉRT fához horgonyozva: mi VAN már, és mi ÚJ

A §6 kilenc cellája közül **öt** olyan viselkedést ír elő, ami a domain/
presentation rétegben MÁR HELYESEN él; ezeket a kör **megőrzi és bizonyítja**,
nem újra feltalálja. **Négy** cella valódi új munka:

| Cella | Mért mai állapot | A kör dolga |
|---|---|---|
| **A1** hiányzó ≠ nulla | `OverviewMetricCardState.unavailable` + `card.reasonText`/`tipText` — a `MetricCard` ma sem ír `?? 0`-t | **MEGŐRZÉS**, és a DS-migráció után is bizonyítva (`metric_missing_test.dart`) |
| **A2** nem támogatott külön állapot | `OverviewMetricCardState.notApplicable` + 13 `analysisCapabilityUnavailable*` kulcs | **MEGŐRZÉS** + indoklás a felületen |
| **A3** confidence minden mérőszám mellett | `ConfidenceBadge(level:…)` a `MetricCard` minden ágán | **MEGŐRZÉS** a részletnézetben is |
| **A4** virtualizált idővonal | **NINCS MEG.** `analysis_timeline_screen.dart:84` sima `ListView(children: <Widget>[…])` — minden gyermek mohón épül; a `TimelineViewport` ablakol, de a lane-tartalom nem lusta | **ÚJ MUNKA** — a fő tétel |
| **A5** diagram-szöveg + esemény-lista | RÉSZBEN: `TimelineLane.summary` semantics létezik, de **bejárható esemény-lista alternatíva nincs**, és a trend/hullámforma néma | **ÚJ MUNKA** |
| **A6/A7** kompatibilitás + indoklás | `CompatibilityEvaluator.evaluateCompatibility` + `ComparisonInconclusiveReason` + 8 `analysisCompareReason*` kulcs | **MEGŐRZÉS** — a UI a domain verdiktjét mondja ki, saját szabályt NEM hoz |
| **A8** kijelölésből indított gyakorlás | **NINCS MEG.** `grep -rn "[Pp]ractice" lib/features/audio_analysis/presentation/*.dart` → **NULLA** találat | **ÚJ MUNKA** |
| **A9** golden | nincs `e13_r27_*` golden | **ÚJ MUNKA** (B5 szerint) |

**A DS-migráció maga is új munka:** `grep -rn "design_system" lib/features/audio_analysis/presentation/` → **NULLA** találat, tehát az öt képernyő ma egyetlen design-system komponenst sem használ.

**A8 horgonya:** a kör `lib/features/practice/**`-hoz **nem** nyúlhat (nincs a
listán → H3), és GoRouter route-literált sem vezethet be (a
`route_literal_guard_test.dart` a `gate_tests`-ben fut, L97). Az A8 érvényes
alakja ezért egy **callback-szerződés** a kijelölés-felületen
(`void Function(Duration start, Duration end)` vagy azzal egyenértékű, a
kijelölt tartományt HELYESEN továbbadó paraméter), amit a cella a ténylegesen
átadott értékeken mér — nem a gyakorlás-motor indítása.

### B7 — a cellák a WIDGETET építsék, ne egy tiszta predikátumot (L443, L403)

A négy cél-teszt minden cellája **pumpálja a valódi widgetet**, és a
**megjelenített SZÖVEG tartalmát** ellenőrizze (`find.text` / `find.textContaining`
/ `Semantics` label), ne csak egy widget-típus vagy kulcs jelenlétét, és ne egy
ugyanabban a fájlban lakó tiszta segédfüggvényt. Mérve: az E13-R06 három cellája
így maradt zöld a tiltott implementáción (L443), az E08-R23 valódi-sértés próbája
pedig típus-szinten mérve átengedte a tartalmi sértést (L403).

### B8 — S11 feloldás: a migráció ADDITÍV, a pinnelt szerkezet NEM cserélődik

A `tools/brief-lint.py` **S11** lelete a §0.0/B/B1 csere után jelent meg, és
VALÓDI, mért kockázatot ír le: a kör olyan MEGLÉVŐ képernyőket írhat át,
amelyeknek a szerkezetét a briefen KÍVÜL élő tesztek pinnelik. A lint két
feloldást enged; a listát tágító ág az orchestrátornak **H3** ([L478](../LESSONS.md#l478)),
ezért a **második** ágat választjuk: a §0.0 kimondja a mérést, amiből
következik, hogy a kör a pinnelt szerkezetet nem cseréli le.

**A pontos pinek, kimérve:**

| Pin | Hol | Mit rögzít |
|---|---|---|
| `find.byType(AnalysisCompareScreen)` | `test/app/routing/app_router_test.dart:235,270` | az OSZTÁLYNÉV és a route-célpont |
| `find.byType(Card), findsWidgets` | `analysis_overview_screen_test.dart:249` | az áttekintőn Material `Card` VAN a fában |
| `w.runtimeType.toString() == 'InsightCard'`, darabszám **4**, majd **5** | `analysis_overview_screen_test.dart:514-526` | az `InsightCard` TÍPUSNÉV és a max-policy slot-szám |
| `find.text('Analysis overview')` / `'Main metrics'` / `'Elemzés áttekintése'` / `'Fő metrikák'` | `analysis_overview_screen_test.dart:196-281` | a MEGLÉVŐ l10n kulcsok mindkét nyelven |
| tartalmi feliratok (`'Measurement unavailable'`, `'Uncertain measurement'`, `'Not applicable'`, …) | `metric_card_test.dart:56-159` | az öt mérőszám-állapot SZÖVEGE |

**A veszély gépileg mérve:** `lib/core/design_system/components/surfaces/ss_card.dart`
az `SsSurface`-re épül, Material `Card`-ot **nem** tartalmaz — egy „cseréljük
`Card` → `SsCard`" reflex tehát az `analysis_overview_screen_test.dart:249`-et
azonnal pirosra váltaná, az `InsightCard` → `SsInsightCard` csere pedig a
514–526 két darabszám-celláját.

**A kör szerződése ezért:**

1. A négy képernyő **osztályneve és konstruktora változatlan**
   (`AnalysisOverviewScreen`, `AnalysisTimelineScreen`, `AnalysisCompareScreen`,
   `AnalysisMetricDetailScreen`).
2. A MEGLÉVŐ widget-típusok (`MetricCard`, `InsightCard`, `ConfidenceBadge`,
   `TimelineLane`, `TimelineRuler`, `HotspotNavigator`) **megmaradnak a nevükön**,
   és a Material `Card` sem tűnik el az áttekintőről. Belül finomíthatók, de
   típus-cserét (`SsCard`, `SsInsightCard`, `SsMetricCard`) a kör **NEM** végez.
3. A MEGLÉVŐ l10n kulcsok és feliratok **nem íródnak át**; a kör **új** kulcsokat
   vesz fel.
4. Az `lib/core/design_system/components/analytics/` ÚJ komponensei az **ÚJ**
   felületeket szolgálják ki (pontszám-gyűrű, trend, diagram-szöveg-összegzés,
   esemény-lista, virtualizált idővonal) — nem a meglévők leváltását.

**Ez szűkítés, nem tágítás,** tehát az orchestrátor hatáskörében van (ADR 0087
§2). A kilenc pin-teszt a `gate_tests`-ben fut (§0.0/B/B3): ha bármelyik
pirosra vált, az **`blocked` jelzés és célzott brief-revízió** — nem a teszt
átírása, és nem a mérce gyengítése.

**Megmaradó, TUDATOSAN vállalt strict-lint leletek** (a CI-kapu `--level base`
szinten mér, ami zöld): az **S13** a két ÚJ előtagra
(`design_system/components/analytics/`, `test/fixtures/analyze/results/`) — a
lint saját ESCAPE-ága szerint feloldva a §0.0/B/B2-ben; az **S11** — feloldva
ITT, a lint második ágán. Ugyanez az alak merge-elt precedens: E13-R26 §0.0/B1
szó szerint „a szűkebb, gépileg tiszta scope-ot választjuk a strict-szintű
lint-lelet árán".

### R1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum → a FORRÁS a szegmens

A kör öt eredmény-képernyője a V2 `presentation/` fában él; az `audio_analysis`
feature-nek **nincs** saját l10n fragmentuma (`ls lib/l10n/features/` →
community, design_system, gamification, onboarding, tuner), és a MEGLÉVŐ
`analysis*` kulcsok (**264 db**, köztük a 13 `analysisCapabilityUnavailable*` és
a 8 `analysisCompareReason*`) a `lib/l10n/base/app_{en,hu}.arb` szegmensben
élnek — a kör új kulcsai tehát ugyanoda mennek.

A kör ezért **nem tudott volna egyetlen szöveget sem írni** a saját listáján
belül. Feloldás — H3 lista-tágítás, **user-engedéllyel (2026-08-25)**, a
lehető legszűkebb alakban:

- `analyze` → nincs saját fragmentuma, a kulcsai a `base/app_*.arb` szegmensben élnek

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
EGZAKT `hasLength(...)`-et állít rájuk. Ez a kör a(z)
`lib/features/audio_analysis/presentation/` fában dolgozik (§0.0/B/B1), ahol az
öt eredmény-képernyő MA IS LÉTEZIK, tehát a szám **alapesetben nem mozdul**
(mérve: 89 = 89, §0.0/B/B4) — ha a kör mégis új képernyőt hoz, az exact-SHA Full
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

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az UI-37–UI-39 Studio Analytics rendszere **confidence-tudatos**, virtualizált
és hozzáférhető adatvizualizációval (SDD Ch13 Kör 27).

## 2. Jelenlegi állapot — mért tények

- Az R12 mérőszám-kártyái és badge-ei, az R26 feldolgozási felülete készen áll.
- Az ADR 0283 kimondta: az eredmény nem állít többet, mint amit mértünk — ez a
  kör ennek vizualizációs oldala.
- A felvételek hosszúak lehetnek: az idővonalnak **virtualizáltnak** kell lennie.
- **MÉRVE (§0.0/B/B1):** az öt eredmény-képernyő a V2
  `lib/features/audio_analysis/presentation/` fában **MÁR LÉTEZIK** (168 / 226 /
  110 / 68 / 69 sor), és a domain a mérőszám-állapotokat, a confidence-t és a
  kompatibilitást **helyesen** modellezi. A kör tehát **migrál és kiegészít**,
  nem nulláról épít.
- **MÉRVE (§0.0/B/B6):** a fa NULLA `design_system` importot tartalmaz ebben a
  rétegben; az idővonal `ListView(children: […])`-vel mohón renderel; a
  kijelölésből induló gyakorlásnak NINCS nyoma. Ez a három a kör érdemi munkája.

## 3. Scope

**Benne van:** pontszám-gyűrű, mérőszám-kártya, trend, confidence-jelmagyarázat
és insight komponensek · az áttekintő összegzés-központú elrendezése részleges
és nem támogatott mérőszám-állapotokkal · **virtualizált** idővonal, hullámforma,
átfedés, kijelölés és esemény-vizsgáló · a mérőszám részletnézete és a
session-összehasonlítás **kompatibilitási szabályai** · diagram-szöveg-összegzés
és esemény-lista alternatíva · nagy fixture-ös teljesítmény- és görgetés-teszt.

**NINCS benne (tilos):** az elemzési logika vagy a mérőszám-számítás módosítása ·
DSP (AGENTS.md §9) · a felvétel/feldolgozás (Kör 26) · `docs/adr/**`,
`tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `audio_analysis/presentation/analysis_{overview,timeline,compare,metric_detail}_screen.dart` | a NÉGY eredmény-felület (§0.0/B/B1 — az export-képernyő a §3-ban nem szerepel, kimarad) |
| `audio_analysis/presentation/widgets/` | a mérőszám-kártya, confidence-badge, idővonal-lane/ruler, insight-kártya |
| `audio_analysis/presentation/controllers/` | `overview_view_model`, `timeline_view_state`, `timeline_viewport` |
| `design_system/components/analytics/` | **ÚJ könyvtár, ezt a kör hozza létre** (§0.0/B/B2) — diagram-komponensek |
| `public.dart` | az export bővítése |
| `lib/l10n/base/app_{en,hu}.arb` | **FORRÁS** — a mérőszám-szövegek (a kör feature-ei még nem migráltak, a kulcsaik itt élnek) |
| `lib/l10n/app_{en,hu}.arb` | **CSAK GENERÁLT KIMENET** — kizárólag `dart run tool/gen_l10n_segments.dart --write`, kézzel írni TILOS |
| `test/features/analyze/results/*_test.dart` (4) | a §6 cellái |
| `test/ui/ui_inventory_test.dart` | **repó-szintű képernyő-leltár őr** — a kör új `lib/features/**/*_screen.dart`-ot hozhat, ezért az egzakt `hasLength(...)` elmozdul; a jogosultság PONTOSAN a szám emelése, más állítás nem érinthető (§0.0/R4) |
| `docs/rounds/e13-r27-…md` | a §10 handoff |

**Tilos zóna:** a V2 `domain/`, `application/`, `data/`, `engine/` rétege (az
elemzési logika és a mérőszám-számítás NEM módosul — a UI a domain verdiktjét
mondja ki) · `audio_analysis/presentation/capture/` és
`analysis_progress_view.dart` (Kör 26) · `audio_analysis/presentation/analysis_export_screen.dart`
(§0.0/B/B1) · `audio_analysis/public.dart` · a legacy `lib/features/analyze/**` ·
`lib/features/practice/**` (§0.0/B/B6 — az A8 callback-szerződés, nem
motor-indítás) · `lib/features/**` a listán kívül · `lib/app/routing/**` (a kör
route-ot NEM vezet be) · `test/features/audio_analysis/presentation/**` (a nyolc
pin — futtatni kell, szerkeszteni tilos, §0.0/B/B3) · `lib/core/theme/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `pubspec.*` és a
natív réteg.

## 5. Kötött architekturális döntések (ADR 0286)

### 5.1 A hiányzó mérőszám NEM nulla

A „nincs adat" és a „nulla" két különböző dolog. Nullaként megjelenítve a
felhasználó rossz teljesítménynek olvassa azt, amit meg sem mértünk.

**NEM elfogadható gyengítés:** `?? 0` a mérőszám megjelenítésénél. Ez a
projekt legveszélyesebb hibaosztálya: magabiztos, hamis állítás.

### 5.2 Minden diagramnak van SZÖVEGES összegzése

Grafikon önmagában felolvasóval néma (az ADR 0282 elve az adatvizualizációra).
A szöveges összegzés a trendet és a szélsőértékeket mondja ki, az esemény-lista
pedig bejárható alternatíva.

### 5.3 A confidence LÁTHATÓ a mérőszám mellett

Nem elég a számot mutatni: mellette látszik, mennyire megbízható.

### 5.4 Az idővonal VIRTUALIZÁLT

Hosszú felvételnél is használható marad. Ez acceptance-cella (A4), nem
optimalizációs törekvés.

### 5.5 Az összehasonlítás CSAK kompatibilis adat között

Eltérő eredmény-verziók vagy nem összemérhető mérőszámok között a felület nem
kínál összehasonlítást — és megmondja, miért nem.

**NEM elfogadható gyengítés:** „a közös mezőket úgyis össze lehet hasonlítani".
Eltérő számítási alap mellett az összevetés félrevezet.

### 5.6 A kijelölésből INDÍTHATÓ gyakorlás

A nehéz szakasz kijelölése után a gyakorlás helyesen paraméterezve indul.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A hiányzó mérőszám NEM nullaként jelenik meg | `metric_missing_test.dart` |
| A2 | A nem támogatott mérőszám külön állapot, indoklással | ugyanott |
| A3 | A confidence minden mérőszám mellett látható | ugyanott |
| A4 | Az idővonal nagy fixture mellett is virtualizált és használható | `timeline_virtualization_test.dart` |
| A5 | Minden diagramnak van szöveges összegzése és esemény-lista alternatívája | `chart_semantics_test.dart` |
| A6 | Az összehasonlítás csak kompatibilis adat között indul | `compare_compatibility_test.dart` |
| A7 | Az inkompatibilitás oka megjelenik | ugyanott |
| A8 | A kijelölésből indított gyakorlás helyesen paraméterez | `timeline_virtualization_test.dart` |
| A9 | A kör §3-ban megnevezett MINDEN képernyőről golden-felvétel készül és be van commitolva — 412×915 compact portrait ÉS `textScaleFactor: 2.0` | `e13_r27_screens_golden_test.dart` + a `test/ui/goldens/*.png` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `?? 0` a hiányzó mérőszámra | **A1** |
| A nem támogatott mérőszám elrejtve | A2 |
| A confidence csak az áttekintőben | A3 |
| Az egész idővonal egyszerre renderelve | **A4** |
| Diagram szöveges összegzés nélkül | **A5** |
| Eltérő verziójú eredmények összevetése | **A6** |
| A képernyő elcsúszik, túlcsordul vagy nagy szövegméretnél olvashatatlan | **A9** |

**A mérőszám-megjelenítés három kötelező cellája** (a küszöb: van-e mért érték):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nincs mérés (hiányzó/nem támogatott) | **„nincs adat"** — soha nem 0 |
| rajta (a küszöbön) | mért érték, alacsony megbízhatósággal | az érték **confidence-jelöléssel** |
| a küszöb fölött | mért érték, magas megbízhatósággal | az érték normál jelöléssel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írj `?? 0`-t a
hiányzó mérőszám megjelenítésébe → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/analyze/results/metric_missing_test.dart test/features/analyze/results/timeline_virtualization_test.dart test/features/analyze/results/chart_semantics_test.dart test/features/analyze/results/compare_compatibility_test.dart test/features/audio_analysis/presentation/ test/ui/ui_inventory_test.dart test/core/architecture_dependency_test.dart test/l10n/hardcoded_string_guard_test.dart test/tooling/dio_factory_guard_test.dart test/tooling/preferences_plugin_import_guard_test.dart test/tooling/route_literal_guard_test.dart
```

**A golden-felvétel (A9) rögzítése — a mérce ÚJ, nem alku tárgya:** a képernyő
minden állapotát NEM kell felvenni, a §3 szerinti alap-nézet elég, de a két
keret (412×915 compact portrait és ugyanaz `textScaleFactor: 2.0` mellett)
KÖTELEZŐ. Minta és futó precedens: `test/features/live/chord_timeline_golden_test.dart`
(valódi kapu, nem `skip`-elt rögzítő). Előállítás:

**MÉRVE (§0.0/B/B5, ADR 0426, L486/L493): az alábbi parancs ezen a boxon
ÉRVÉNYTELEN** — a goldent aarch64-en felvenni és x86-os CI-vel mérni öt vak
CI-kört fizetett ki. Az EGYETLEN érvényes alak:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r27_screens_golden_test.dart
tools/golden-x86.sh check  test/ui/goldens/e13_r27_screens_golden_test.dart
```

~~`~/flutter/bin/flutter test --update-goldens test/ui/goldens/e13_r27_screens_golden_test.dart`~~
(a §0.0/B/B5 revízió hatályon kívül helyezte)

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

A sorrend a §0.0/B/B6 mérését követi: előbb a MEGŐRZÉS bizonyítása, aztán az
ÚJ munka.

1. `lib/core/design_system/components/analytics/` — az analitika-komponensek
   (pontszám-gyűrű, trend, confidence-jelmagyarázat), export a `public.dart`-ba.
2. A mérőszám-megjelenítés három cellája (`metric_missing_test.dart`) a MAI,
   helyes `OverviewMetricCardState` szerződésre — hiányzó ≠ nulla, nem
   támogatott külön állapot, confidence mindenhol. **Ez megőrző cella:** a
   viselkedés már él, a cella innentől gépileg tartja (A1–A3).
3. Az áttekintő és a részletnézet DS-migrációja a 2. lépés cellái mellett.
4. **A virtualizált idővonal** — a `ListView(children: […])` lecserélése lusta
   (builder-alapú) renderelésre + nagy fixture-ös cella (A4). Ez a kör fő tétele.
5. Diagram-szöveg-összegzés és **bejárható esemény-lista alternatíva** (A5).
6. A kijelölés-callback helyes paraméterezése (A8, §0.0/B/B6 horgony).
7. Az összehasonlítás: a UI a `CompatibilityEvaluator` verdiktjét és a
   `ComparisonInconclusiveReason` indoklását mondja ki — saját szabály NÉLKÜL
   (A6–A7).
8. Golden-felvétel a §7/B5 szerint (`tools/golden-x86.sh record`), PNG-k
   commitolva (A9).
9. A valódi-sértés próba, §10-be dokumentálva.
10. `tools/round-gate.sh` a §7 szerint — a nyolc pin-teszttel EGYÜTT.

## 9. Kockázatok

- **A `?? 0` reflex.** Egyetlen karakternyi kényelem, és a felhasználó rossz
  eredménynek olvassa a hiányzó mérést (A1).
- **A nem virtualizált idővonal.** Rövid teszt-fixture-rel nem látszik, hosszú
  felvételen használhatatlan (A4).
- **A „közös mezők" összevetése.** Logikusnak tűnik, és eltérő számítási alap
  mellett félrevezet (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
