# E15-R10 — Audio Analysis és Analyze képernyők migrálása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 10
- **Kör-azonosító:** `E15-R10`
- **Branch:** `<motor>/e15-r10-analysis-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "analysis recording processing export metric detail UI"` → a `halts/round-status-E13-R26` (Analyze felvétel és feldolgozás UI) és **[ADR 0246](../adr/0246-analysis-session-comparison-and-trend-contract.md)** (összehasonlítás és trend szerződés).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart lib/features/audio_analysis/presentation/analysis_export_screen.dart lib/features/analyze/screens/analyze_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **6** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Az elemzési út a második leggyakrabban használt felület a Live után, és a felvétel–feldolgozás–eredmény hármas ma legacy megjelenésű; az `analyze_screen` ráadásul a régi, párhuzomos belépő.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart",
  "lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart",
  "lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart",
  "lib/features/audio_analysis/presentation/analysis_export_screen.dart",
  "lib/features/analyze/screens/analyze_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  "test/features/analyze/mic_error_parity_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/recording_state_test.dart",
  "test/features/audio_analysis/presentation/analysis_overview_screen_test.dart",
  "test/features/audio_analysis/presentation/analysis_export_screen_test.dart",
  "test/ui/goldens/e13_r26_screens_golden_test.dart",
  "test/ui/goldens/e13_r27_screens_golden_test.dart",
  "test/ui/goldens/goldens/e13_r26_analysis_home_compact.png",
  "test/ui/goldens/goldens/e13_r26_analysis_home_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r26_analysis_recording_compact.png",
  "test/ui/goldens/goldens/e13_r26_analysis_recording_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r26_analysis_processing_compact.png",
  "test/ui/goldens/goldens/e13_r26_analysis_processing_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r27_analysis_overview_compact.png",
  "test/ui/goldens/goldens/e13_r27_analysis_overview_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r27_analysis_timeline_compact.png",
  "test/ui/goldens/goldens/e13_r27_analysis_timeline_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r27_analysis_compare_compact.png",
  "test/ui/goldens/goldens/e13_r27_analysis_compare_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r27_analysis_metric_detail_compact.png",
  "test/ui/goldens/goldens/e13_r27_analysis_metric_detail_compact_scale2.png",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r10-analysis-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/features/analyze/analyze_cleanup_test.dart",
  "test/features/analyze/mic_error_parity_test.dart",
  "test/features/analyze/processing_progress_test.dart",
  "test/features/analyze/recording_state_test.dart",
  "test/features/audio_analysis/presentation/analysis_overview_screen_test.dart",
  "test/features/audio_analysis/presentation/analysis_export_screen_test.dart",
  "test/ui/goldens/e13_r26_screens_golden_test.dart",
  "test/ui/goldens/e13_r27_screens_golden_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0.0.A Pre-flight brief-revízió (Claude / Opus 5 orchestrátor, 2026-09-03, `main @ f51c45dd`)

A brief 2026-08-28-i mért állításait a kör indítása előtt újramértem. Az alábbi
tizenhárom revízió KÖTELEZŐ; ütközés esetén ez a szakasz erősebb a brief korábbi
szövegénél.

**Visszakeresés (ADR 0312).** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr
--top 5 "design-rendszer migráció képernyő SsErrorState SsEmptyState állapot"` →
[ADR 0466](../adr/0466-app-runtime-theme-is-the-design-system-theme.md),
[ADR 0277](../adr/0277-failure-presentation-model.md),
[ADR 0273](../adr/0273-design-system-token-source-of-truth.md),
[L559](../LESSONS.md#l559). `--corpus lessons,halts --top 5 "analysis felvétel
feldolgozás export képernyő migráció kockázat golden teszt"` →
[L493](../LESSONS.md#l493), [L517](../LESSONS.md#l517), [L486](../LESSONS.md#l486),
[L524](../LESSONS.md#l524), [L133](../LESSONS.md#l133). A batch közvetlen
precedense az `E15-R09` (`docs/rounds/e15-r09-ai-tutor-migration.md` §0.0.A/R3, R5,
R7 és §0.0.B/R9, R10, R14) — ez a kör UGYANAZT a hét defektosztályt hordozta, és a
review-ban 1 BLOCKER + 5 MAJOR árat fizetett értük. Itt ezért a pre-flightban
oldom fel őket.

### R1 — A scope teljes egészében áll (mérve)

```
legacy lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart
legacy lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart
legacy lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart
legacy lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart
legacy lib/features/audio_analysis/presentation/analysis_export_screen.dart
legacy lib/features/analyze/screens/analyze_screen.dart
```

Mind a 6 képernyő legacy → a §3 scope-ból semmit nem kell kivenni. A
`retirement-plan.md` ehhez a kör-azonosítóhoz MÁS listát ír (`:174` a
setlist-képernyőket és az exportot/metric-detailt sorolja, `:208` az
`analyze_screen`-t `retire`/`E15-R04`-nek jelöli, `:214-216` a három capture-
képernyőt `unreachable`-nek) — ugyanaz a kör-számsodródás, mint az E15-R08/R09
esetében. **Az irányadó a queue sora és ez a brief**; a `retirement-plan.md`
NINCS az `allowed_paths`-on, tehát változatlan marad. Az `unreachable` besorolás
nem szűkíti a scope-ot: a három capture-képernyőt kipinnelt widget-tesztek ÉS 6
committolt golden PNG méri, tehát migrálhatók és mérhetők.

### R2 — Az érintett feature-öknek NINCS `*ThemeScope` burkolójuk (mérve)

`grep -rn "ThemeScope" lib/features/audio_analysis/ lib/features/analyze/` → **0
találat**; a 9 létező burkoló (`Auth`, `Community`, `Gamification`, `Library`,
`OfflineAi`, `Progress`, `Settings`, `Share`, `Vision`) egyike sem ezekhez tartozik.
Ezért a §3 „a meglévő `*ThemeScope` burkoló eltávolítása" kikötése ezen a batch-en
**tárgytalan** (no-op). A §3 TILTÁSA (`Új *ThemeScope burkoló bevezetése`)
**VÁLTOZATLANUL ÉL** — sem `lib/`-ben, sem teszt-helperben widget formájában.

### R3 — A komponens-nevek javítása (a §3/§5.2/§6.1 három nevet tévesen ír)

Mérve (`lib/core/design_system/`): **NINCS** `SsErrorState`, `SsListTile` és
`SsMetricTile` osztály. A ténylegesen létező, ide illő nevek: `SsCard`,
`SsContentCard`, `SsInsightCard`, `SsMetricCard`, `SsHeroCard`, `SsSection`,
`SsSurface`, `SsButton`, `SsIconButton`, `SsEmptyState`, **`SsFailureState`**
(hibaállapot, `SsFailurePresentation` bemenettel — ADR 0277), `SsSkeleton`
(betöltés), `SsStatusBadge`, `SsScoreRing`, `SsTrendIndicator`, valamint az
`SsSpacing`/`SsTypography`/`SsRadius`/`SsColorScheme` tokenek.

**A brief minden `SsErrorState` említése `SsFailureState`-ként, minden
`SsListTile`/`SsMetricTile` említése a fenti tényleges megfelelőjeként
olvasandó** — beleértve a §5.2-t, a §3-at és a §6.1 valódi-sértés próbáját (ott
tehát `SsFailureState` → nyers `Text` a visszacserélendő él).

### R4 — A token-feloldás mért útja: a HARNESS adja, nem a képernyő

Mérve:

- a design-rendszer komponensei `Theme.of(context).extension<...>()!` alakban
  oldanak fel (bang, nem null-tűrő): `ss_empty_state.dart:29-30`,
  `ss_failure_state.dart:32-33`, `ss_skeleton.dart:27`, és az `SsCard` →
  `ss_surface.dart` → `ss_elevation.dart:14-15` láncon szintén;
- `lib/core/theme/app_theme.dart:47` → `extensions: [palette]`, tehát az
  **`AppTheme` a design-rendszer kiterjesztéseit NEM hordozza**;
- `lib/app/strumsight_app.dart:33-34` → a futásidejű app gyökere
  `SsLightTheme.data()` / `SsDarkTheme.data()`, tehát **PRODUKCIÓBAN a feloldás
  mért módon rendben van** (ADR 0466).

**Miért nem esik szét MA az `AppTheme.dark()`-os golden, ami migrált képernyőt
rajzol:** a `test/ui/goldens/e13_r27_screens_golden_test.dart:216-234` az
`AnalysisOverviewScreen`/`AnalysisTimelineScreen`/`AnalysisCompareScreen`-t
pumpálja, ezek viszont mért módon `SsConfidenceLegend`-et és társait használják,
amelyek **egyetlen `extension<...>` olvasást sem tartalmaznak**. Ebből tehát NEM
következik, hogy az `AppTheme` elég — a null-check összeomlás pontosan akkor
jelenik meg, amikor a migráció `SsCard`/`SsEmptyState`/`SsFailureState`/
`SsSkeleton`-t tesz ezekbe a képernyőkbe. Ez a kör célja, tehát a becsapódás
KONSTRUKCIÓBÓL biztos.

**Kötelező megoldás — teszt-harness téma-drótozása.** Az alábbi harnessek ma
téma NÉLKÜLI `MaterialApp`-ot pumpálnak, és mind az `allowed_paths`-on vannak:
`analyze_cleanup_test.dart:19`, `processing_progress_test.dart:17`,
`recording_state_test.dart:24`, `mic_error_parity_test.dart:51`,
`analysis_overview_screen_test.dart:101/:184`,
`analysis_export_screen_test.dart:92`. Ezek `theme: SsLightTheme.data()`-ot
kapnak — a mért precedens
`test/features/practice_generator/presentation/today_plan_screen_test.dart:141-142`,
és ugyanez az egysornyi javítás zárta az E15-R09 BLOCKER-1-ét. Az
`adaptive_scaffold_test.dart:56/:393/:470` és a `legacy_route_redirect_test.dart:47`
MÁR `SsLightTheme.data()`-ot használ — azokhoz nem kell nyúlni.

**Ez nem cella-gyengítés:** egyetlen cella sem törölhető, `skip`-elhető vagy
lazítható (§0.0), a kipinnelt elvárások (típus-állítások, kulcsok, szövegek) szó
szerint maradnak.

### R5 — A golden-sáv KONSTRUKCIÓBÓL érintett: téma-csere + 14 PNG újrafelvétele

Mérve: mindkét golden-fájl `theme: AppTheme.dark()`-ot pumpál
(`e13_r26_…:41`, `e13_r27_…:48`), és a batch NÉGY képernyőjét rajzolja —
`AnalysisHomeScreen` (`r26:98`), `AnalysisRecordingScreen` (`r26:111`),
`AnalysisProcessingScreen` (`r26:124`), `AnalysisMetricDetailScreen` (`r27:243`).
Az R4 szerint ezek a migráció után `AppTheme` alatt összeomlanak.

Kötött megoldás: **mindkét fájl `_pump` témája `SsDarkTheme.data()` legyen** (ez a
futásidejű app sötét témája, `strumsight_app.dart:34` — a golden így hűbb lesz a
valósághoz, nem lazább), és mind a **14** `e13_r26_*` / `e13_r27_*` PNG
újrafelvételre kerül. A `r27` három már migrált képernyője (overview, timeline,
compare) azért kerül bele, mert a téma-csere az egész fájlra hat — ez a
téma-csere mechanikus következménye, nem scope-tágítás. Az `allowed_paths` ezért
egészült ki a 14 PNG-vel (a brief §7 SAJÁT újrafelvételi előírásának
következménye).

Mindkét fájl `:5-6` fejléc-kommentje azt állítja, hogy a minta „`AppTheme` (the
app's actual runtime theme), not `SsDarkTheme`" — ez a csere után **HAMIS**, tehát
a kommentet is javítani KELL (L486/L493 osztály: a golden a raszterizálást
rögzíti, a hamis indoklás a következő kört viszi félre).

Az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426, L493); az
előfeltétel ezen a boxon MÉRVE megvan (`Docker 29.4.0`,
`strumsight-golden-x86:3.44.2` image jelen):

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart
```

`flutter test --update-goldens` ezen az (aarch64) boxon **TILOS**.

### R6 — `analysis_export_screen_test.dart` a fájllistára ÉS a kapuba

Mérve: `test/features/audio_analysis/presentation/analysis_export_screen_test.dart`
LÉTEZIK, és az `AnalysisExportScreen`-t pinneli (locale-paritás, „soha nem nyers
export JSON" cellákkal), de a brief `allowed_paths`-án és `gate_tests`-ében NEM
szerepelt — miközben az export-képernyő a kör scope-jában van. Ez pontosan az
E15-R09 BLOCKER-1 osztálya (`tutor_home_screen_test.dart`), ott egy teljes javító
kör volt az ára. A fájl felkerült MINDKÉT listára; a harnesse az R4 szerinti
téma-drótozást kapja.

### R7 — ARB: a §3 engedélye és a fájllista ütközött (feloldva)

A §3 kimondottan engedi új kulcs felvételét mindkét locale-ra, de a
`lib/l10n/*.arb` NEM volt az `allowed_paths`-on — ez a brief hibája volt, nem
tilos zóna. A két ARB fájl felkerült a listára, a tiltás VÁLTOZATLAN: kulcs **nem
törölhető**, meglévő kulcs jelentése **nem változhat**, új kulcs csak `en` ÉS `hu`
párban. A célzott gate ezért kiegészült a `test/l10n/arb_parity_test.dart`
cellával.

### R8 — A barrel-szabály a kapuba (E15-R09 BLOCKER-2 osztálya)

A design-rendszer KIZÁRÓLAG a `lib/core/design_system/public.dart` barrelen át
importálható (ADR 0273 §1); belső fájl közvetlen importja architektúra-sértés. Ezt
a szabályt mérten csak a teljes CI `architecture` lépése méri, a kör célzott
gate-je nem — az E15-R09-ben emiatt csúszott át egy BLOCKER a review-ig. A
`gate_tests` ezért kiegészült a `test/core/architecture_dependency_test.dart`
cellával. **Mind a 6 migrált fájl a `public.dart`-ot importálja**, nem a
komponens-fájlt.

### R9 — A `metric_detail` migrációja szükségszerűen SEKÉLY (mért scope-korlát)

Mérve: `analysis_metric_detail_screen.dart` mindössze 68 sor, és a teljes vizuális
törzsét két megosztott widgetnek delegálja — `MetricCard`
(`lib/features/audio_analysis/presentation/widgets/metric_card.dart:17`) és
`InsightCard` (`…/widgets/insight_card.dart:10`). Ez a két fájl **NINCS** az
`allowed_paths`-on, és nem is kerül rá: megosztott widgetek, más képernyők is
használják őket.

Következmény: ezen a képernyőn a kör a SAJÁT rétegét migrálja (scaffold, elrendezés,
`SsSpacing`/`SsTypography` tokenek, üres/hiba állapot, `SsSection`), a két kártya
pedig VÁLTOZATLAN marad. Ez **nem** az A2 lazítása, hanem egy mért tény
átvezetése: az érintett vizuális elem nem a kör fájljában él. A két kártya
design-rendszer-migrációja KÜLÖN kör dolga, és a `docs/ui/migration-status.md`-ben
nevesített follow-upként KELL rögzíteni. (Ugyanaz az osztály, mint az E15-R09
§0.0.B/R9 `TutorBanner`-esete.)

### R10 — A6: a hivatkozott őr nem méri, amit állít (őszinteségi kikötés)

Mérve: `test/l10n/hardcoded_string_guard_test.dart` `_scopeDirs` listája
**EXAKTUL** négy könyvtár a `lib/core/design_system/` alatt (`components`,
`accessibility`, `layouts`, `motion`) — a `lib/features/**`-ra **NEM** néz. Az őr
hatókörének átírása NEM ennek a körnek a dolga (`test/l10n/**` scope-tágítás
lenne). Az A6 bizonyítéka a §10-ben ŐSZINTÉN fogalmazandó: „mért tény, hogy a
hivatkozott guard nem fedi a `lib/features/**`-ot; a kör bizonyítéka a diff kézi
és reviewer-oldali ellenőrzése, amely új beégetett felhasználói szöveget nem
talált". A guard a kapuban marad (regresszió-őr a design-rendszer oldalán).

### R11 — Az A3 bizonyítéka COMMITTOLT cella, nem `/tmp`-beli próba

Az A3 (`textScaler 2.0`, `en` ÉS `hu`, túlcsordulás nélkül) mércéje committolt
cella az engedélyezett teszt-fájlokban, mind a **6** képernyőre,
`expect(tester.takeException(), isNull)` elvárással. A küszöb-hármasból a `2.0`
KÖTELEZŐ, az `1.5`/`2.5` cellák opcionálisak (a `2.5` teljesítése nem
követelmény, és a `2.0`-t nem helyettesíti). Indok: L517 mérése szerint a
`textScaler 2.0` keret két egymást követő körben fogott ki valódi, addig
láthatatlan elrendezési hibát, amit a teljes CI-suite átengedett. L559: ha egy
elrendezési védelmet MINTA-szinten kell feltenni (pl. `SsEmptyState` négy eleme
magasabb a lecserélt kettőnél), akkor MINDEN testvér-példányra fel kell tenni,
nem csak az elsőre.

### R12 — Az A2-nek képernyőnkénti, típus-szintű mércéje legyen

A §6.1 első sora („a hibaállapot nyers `Text` marad") csak akkor tud pirosra
váltani, ha van rá típus-állítás. Minden migrált állapot kap egyet a batch
teszt-fájljaiban — pl. `find.byType(SsFailureState)` a felvétel-képernyő
`_RecordingStage.error` ágára (`analysis_recording_screen.dart:174`) és a
feldolgozás két hiba-ágára (`analysis_processing_screen.dart:100/:106`),
`find.byType(SsEmptyState)` a `analysis_home_screen.dart:66`
(`recentAnalyses.isEmpty`) ágra, betöltésre a design-rendszer betöltés-komponense
(`analysis_processing_screen.dart:139` `LinearProgressIndicator`).

**Az `SsEmptyState` mért API-ja `required actionLabel` + `required onAction`**
(`ss_empty_state.dart:14-18`), tehát VALÓDI következő lépést feltételez (ADR 0277
§5). Ahol az üres állapotnak mérten NINCS valódi akciója, ott az E15-R04/R06/R07/
R08/R09 precedens kivétel-osztálya érvényes: a komponens NEM kényszeríthető ki
hamis akcióval, az állapot marad képernyő-lokális widget, de **KÖTELEZŐEN**
`SsColorScheme`/`SsTypography`/`SsSpacing` tokenekkel stílusozva — és a §10-ben
képernyőnként, mért indoklással dokumentálva.

Az `analyze_screen.dart` `AppColors` hivatkozásai (`:264`, `:274`, `:284`, `:347`,
`:393`) a migráció után `SsColorScheme`-ből jönnek — a §6.1 utolsó sora
(„importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön")
pontosan ezt méri.

### R13 — ADR: nincs, és nem is kell

A kör nem hoz ÚJ architekturális döntést: a token-forrás (ADR 0273), a
hiba-prezentáció (ADR 0277), a futásidejű téma (ADR 0466), a golden-felvétel
architektúrája (ADR 0426), a mikrofon-életciklus (ADR 0056) és az export-redakció
(ADR 0247) mind merge-elt szerződések, amelyeket a migráció HASZNÁL, nem ír át. A
golden téma-cseréje (R5) teszt-hűségi javítás a már merge-elt futásidejű témára,
nem új döntés. `tools/round-slots.py reserve-adr` ezért **nem futott** (ugyanaz a
döntés, mint az E15-R09 §0.0.A/R8-ban). Ha az implementer szerint ÚJ
architekturális döntés kellene, az **STOP-eset** (`stopped` jelzés), nem önkezű
ADR-írás.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 6 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `analysis_home_screen.dart`, `analysis_recording_screen.dart`, `analysis_processing_screen.dart`, `analysis_metric_detail_screen.dart`, `analysis_export_screen.dart`, `analyze_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 6 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a felvétel-képernyő mikrofon-életciklusa (lease, felszabadítás) ÉRINTETLEN — a kör nem nyúl a `core/audio` réteghez (ADR 0056)
- a feldolgozás-képernyő szakasz-jelzései a MÉRT pipeline-állapotokat tükrözik; új állapot nem vezethető be
- az export-képernyő redakciós szabályai (ADR 0247) változatlanok

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/audio_analysis/presentation/analysis_export_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/analyze/screens/analyze_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/navigation/legacy_route_redirect_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/analyze/analyze_cleanup_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/analyze/mic_error_parity_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/analyze/processing_progress_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/analyze/recording_state_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/audio_analysis/presentation/analysis_overview_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r26_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r27_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsErrorState`, betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 6 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával) | a dokumentum |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsErrorState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/features/analyze/analyze_cleanup_test.dart test/features/analyze/mic_error_parity_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/recording_state_test.dart test/features/audio_analysis/presentation/analysis_overview_screen_test.dart test/features/audio_analysis/presentation/analysis_export_screen_test.dart test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart test/core/architecture_dependency_test.dart
```

> A sor a §0.0.A/R6 (export-teszt), R7 (ARB-paritás), R8 (barrel-szabály)
> revízióival bővült. A gate-et TELJES egészében, csővezeték és `tail` nélkül
> futtasd.

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart lib/features/audio_analysis/presentation/analysis_export_screen.dart lib/features/analyze/screens/analyze_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Migrációs mérés (A1, A7)

```
$ for f in lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart lib/features/audio_analysis/presentation/analysis_export_screen.dart lib/features/analyze/screens/analyze_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
MIGRATED lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart
MIGRATED lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart
MIGRATED lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart
MIGRATED lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart
MIGRATED lib/features/audio_analysis/presentation/analysis_export_screen.dart
MIGRATED lib/features/analyze/screens/analyze_screen.dart
```

Mind a 6 képernyő migrált. A teljes 96-os korpuszon: **86/96 (89.583%)**, fel
az E15-R09 utáni 80/96-ról (`docs/ui/migration-status.md` teteje — a mérés
parancsa és a részletes komponens-térkép ott).

### 10.2 Komponens-térkép (5.2, R3, R9, R12)

> **Frissítve a javító körben (1. javító menet, §10.8)** — az idle fázis
> `SsEmptyState`-je és a `SsContentCard` home-képernyős használata a review
> B1/M1/M4 leletei nyomán token-stílusú helyi widgetre cserélődött; a lenti
> lista a JAVÍTOTT állapotot írja le.

- **`SsEmptyState`** — `AnalysisHomeScreen` üres recent-lista (akció:
  `onStartRecording`, valódi), `AnalyzeScreen` micDenied fázis (akció:
  `openAppSettings`, valódi — a lecserélt bespoke Column ezt nem tudta
  modellezni; cím: `analysisRecordingPermissionDeniedTitle`, a §10.8/m1
  javítás után, hogy ne ismételje a képernyő-fejlécet), `AnalysisMetricDetailScreen`
  új üres ága (se metrika, se insight — korábban néma üres `ListView` volt;
  akció: `commonClose` + `Navigator.maybePop`; cím/üzenet a §10.8/m2 javítás
  után `analysisOverviewUnavailable`/`analysisOverviewNotApplicable`).
- **`SsFailureState`** — `AnalysisRecordingScreen._RecordingStage.error`,
  `AnalysisProcessingScreen`'s `AnalysisInputError`/`AnalysisError` —
  mindhárom valódi `AppFailure`-t hordoz, `SsFailurePresentation.from`
  kódalapú címet/üzenetet ad a korábbi nyers `failure.code` helyett. A
  §10.8/B1 és M3 javítás után: ha a mért `retryable == false`
  (`contactSupport`-only prezentáció, amelyre ennek a két képernyőnek nincs
  valódi kezelője), a screen egy explicit, token-stílusú fallback gombot ad
  (`analysis-processing-restart` / `analysis-recording-error-retry`) — az
  `SsFailureState` a maga beépített gombját csak `retryable == true` esetén
  kapja meg, hogy sose legyen két azonos célú CTA egymás alatt.
- **Kivétel-osztály (R12), token-stílusú helyi widget marad** —
  `AnalysisRecordingScreen._PermissionDeniedBody` (a `retryable`-től
  függetlenül MINDIG retry-t mutat; az `SsFailureState` kód-alapú akciója ezt
  némán "open settings"-re cserélné egy tartósan megtagadott engedélynél —
  VISELKEDÉS-változás, nem vizuális), `AnalysisProcessingScreen`'s
  `AnalysisPermissionDenied` ága (nincs `AppFailure` objektum ezen az
  állapoton — kitalálni egyet mért kódot hamisítana), `AnalyzeScreen`'s
  `micError` fázisa (a busy-mic szövegnek szándékosan nincs saját akciója — a
  Retry a különálló nagy vezérlőben él, parity Live r13/Tuner r68-cal),
  `AnalyzeScreen`'s `AnalyzeSkeleton` (`:222`, betöltés — a widget maga
  scope-on kívüli, de a hívási hely token-stílusú) és `analyzeNoChords`
  (`:227-234`, nyers `Text`, de a `bodyMedium`/`textSecondary` tokent
  használja — nincs saját akciója, a "New recording" a lenti vezérlősávban
  él). **A javító kör (§10.8/M4) egy ÚJ taggal bővítette ezt az osztályt:**
  `AnalyzeScreen`'s **idle** fázisa — a lenti vezérlősáv már ad egy valódi
  "Record" CTA-t, ezért az `SsEmptyState` kötelező második akciója csak
  hamisítható vagy duplikálható lett volna (M4); a fázis emiatt VISSZAállt
  token-stílusú helyi widgetre, cím nélkül (hogy ne ismételje a `:108-113`
  fejlécet), üzenettel (`analyzeIntro`).
- **Betöltés** — `AnalysisProcessingScreen`'s `LinearProgressIndicator`
  típusban PINNELT (`processing_progress_test.dart`), ezért típusban
  változatlan marad, csak `color`/`backgroundColor` tokent kap.
- **`AnalysisHomeScreen` — `_UntruncatedContentCard` (§10.8/M1)** — a
  `SsContentCard` (`lib/core/design_system/components/cards/ss_content_card.dart`,
  scope-on KÍVÜL) `maxLines: 2`/`4` + `TextOverflow.ellipsis` némán csonkolja
  a valódi felhasználói tartalmat (a legutóbbi elemzés címét) `textScaler
  2.0`-n. Mivel a komponens maga nem módosítható, a képernyő két kártyája
  (`_InputModeCard`, `_RecentAnalysisTile`) egy képernyő-lokális,
  ugyanazokra a tokenekre (`SsSpacing`/`SsTypography`/`SsColorScheme`) és
  ugyanarra a `SsSurface`/`SsCardActionRegion`/`SsCardAction` primitívre épülő
  megfelelőre vált, `maxLines`/`overflow` NÉLKÜL — a `ListView` amúgy is
  görgethető, tehát a hosszabb szöveg csak több sort foglal, nem csordul túl.
- **`AnalysisMetricDetailScreen` SEKÉLY migráció (R9)** — a vizuális törzs a
  `MetricCard`/`InsightCard` megosztott widgetekben él, azok NINCSENEK az
  `allowed_paths`-on; a kör csak a képernyő saját rétegét migrálta
  (scaffold, `ListView` tokenek, az új üres állapot, a "More insights"
  szekció-cím). A két kártya design-rendszer-migrációja follow-up, rögzítve a
  `migration-status.md`-ben.
- **`AnalyzeScreen`** — `AppColors` → `SsColorScheme`, `_BigButton` törölve
  (minden hívási hely `SizedBox(width: infinity, height: 52, child: SsButton)`
  mintát kap), `done` fázis "Save"/"New recording" párja
  `SsButtonVariant.secondary`/`.primary`. A megosztás/gyakorlás ikon-gombok
  (`IconButton.filledTonal`) VÁLTOZATLANOK maradtak — nem hordoznak
  `AppColors`/legacy-token hivatkozást, és az `SsIconButton` névkatalógusa
  nem tartalmazza az `ios_share`/`school_outlined` ikonneveket.

### 10.3 Teszt-harness téma-drótozás (R4) — egy HETEDIK ponttal

A briefben nevesített 6 harness (`analyze_cleanup_test.dart`,
`processing_progress_test.dart`, `recording_state_test.dart`,
`mic_error_parity_test.dart`, `analysis_overview_screen_test.dart` — `_harness`
ÉS az inline üres-állapot `MaterialApp`, `analysis_export_screen_test.dart`)
mind megkapta a `theme: SsLightTheme.data()`-t. **A gate első teljes futása egy
HETEDIK, a briefben nem nevesített pontot is elkapott:**
`analysis_overview_screen_test.dart`'s `_routedHarness` (egy HARMADIK
`MaterialApp`-építő ugyanabban a fájlban, a már meglévő, kipinnelt
"maximum-policy" tesztet szolgálja ki) szintén téma nélküli volt — ez egy
VALÓDI `AnalysisMetricDetailScreen` null-check összeomlást okozott egy
kipinnelt cellán. Javítva ugyanúgy (`theme: SsLightTheme.data()`), a mért
"literálisan változatlan" kritérium (kulcsok/típusok/szövegek) sértetlen.

### 10.4 ARB-mérés — a brief §3/§7 engedélye vs. a mért forrás (R7 kiegészítés)

A brief `allowed_paths`-a a `lib/l10n/app_en.arb`/`app_hu.arb` fájlokat sorolja
fel új kulcs felvételéhez. Mérve a kör közben: ezek **GENERÁLT aggregátumok**
(ADR 0307 §4, `tool/gen_l10n_segments.dart`), a `lib/l10n/base/app_<locale>.arb`
+ `lib/l10n/features/<feature>_<locale>.arb` fragmentumok determinisztikus
uniója — egy kézi szerkesztést a gate saját `l10n` lépése (amely újragenerálja
az aggregátumot) NÉMÁN felülír. Három új kulcsot (`analyzeIntroTitle`,
`analysisHomeRecentEmptyTitle`, `analysisMetricDetailEmptyTitle`/`Message`)
így elvesztettem az első gate-futás után — a `lib/l10n/base/app_en.arb` NINCS
az `allowed_paths`-on (a scope-audit ezt blokkolta is, STOP-eset lett volna).
Mivel egyik új szöveg sem volt VALÓDI új tartalom (mindegyik egy már létező
képernyő-cím vagy üzenet ismételt felhasználása), a végleges megoldás a
meglévő kulcsok újrahasznosítása lett — **ÚJ ARB-kulcs végül nem került be**:

- `AnalysisHomeScreen` üres állapota: title = `analysisHomeRecentSectionTitle`
  (a különálló szekció-fejléc emiatt csak a NEM üres ágon jelenik meg —
  duplikáció-mentes), message = `analysisHomeRecentEmpty` (változatlan).
- `AnalyzeScreen` idle/micDenied title: `navAnalyze` ("Analyze"/"Elemzés").
- `AnalysisMetricDetailScreen` üres állapota: title =
  `analysisOverviewMetricDetailTitle`, message = `analysisOverviewNoDocument`
  (mindkettő már létező, testvér-képernyőn bevezetett kulcs, jelentésük nem
  változott, csak újrahasznosítva).

Egy jövőbeli körnek, ha VALÓDI új szöveget kell felvennie ide, a
`lib/l10n/base/**`/`lib/l10n/features/**` fragmentumot kell az
`allowed_paths`-ra tennie, nem az aggregátumot — rögzítve a
`migration-status.md`-ben is.

### 10.5 A3 — egy valódi túlcsordulás, megtalálva és javítva

`AnalyzeScreen`'s idle-állapotának `SsEmptyState`-je a saját `textScaler 2.0`
cellámban (`mic_error_parity_test.dart`) VALÓDI `RenderFlex overflow`-t adott
az alapértelmezett teszt-viewporton — az `SsEmptyState` csak középre igazít,
nem tart fenn scroll-helyet. Javítás: `SingleChildScrollView` az idle és a
micDenied ág köré (mindkettő `SsEmptyState`-et használ). Hasonló okból az
`AnalysisMetricDetailScreen` A3 cellája NEM az overview-képernyőn át navigálva
méri magát (az a navigáció egy MÁSIK, a kör hatókörén kívüli, már migrált
komponenst — `SsConfidenceLegend` — is belehúzna, amely 320px+2.0 kombón
önmagában túlcsordul, a batch-től függetlenül); helyette
`AnalysisMetricDetailScreen`-t közvetlenül pumpálja reprezentatív
metrika+insight tartalommal.

### 10.6 Valódi-sértés próba (§6.1, KÖTELEZŐ)

Cél: `analysis_recording_screen.dart`'s `_ErrorBody` — `SsFailureState` →
nyers `Text(presentation.title, key: ...)`. Gate-cella:
`test/features/analyze/analyze_cleanup_test.dart` ÚJ sora
(`expect(find.byType(SsFailureState), findsOneWidget)`).

```
$ flutter test test/features/analyze/analyze_cleanup_test.dart   # SÉRTÉS UTÁN
...
00:01 +1 -1: AnalysisRecordingScreen — A5 no orphan microphone an engine
failure mid-start releases the lease it took [E]
  Expected: exactly one matching candidate
  Actual: <zero widgets with type SsFailureState>
Failing tests:
  .../analyze_cleanup_test.dart: ... an engine failure mid-start releases
  the lease it took
```

Az A2 cella PIROSRA váltott, ahogy a mátrix előírja. Visszaállítva
(`git diff` a kör commitjai között üres erre a fájlra a próba előtt/után),
`flutter test test/features/analyze/analyze_cleanup_test.dart` → 5/5 zöld.

### 10.7 Kötelező ellenőrzés — artefaktum

```
$ tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/features/analyze/analyze_cleanup_test.dart test/features/analyze/mic_error_parity_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/recording_state_test.dart test/features/audio_analysis/presentation/analysis_overview_screen_test.dart test/features/audio_analysis/presentation/analysis_export_screen_test.dart test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart test/core/architecture_dependency_test.dart
...
MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (exit 0).
```

A golden-újrafelvétel (`tools/golden-x86.sh record ...`, exit 0, 14/14 zöld) és
egy második, független `tools/golden-x86.sh check ...` futás (exit 0, 14/14
zöld) is megerősítette, hogy a §10.4 utólagos ARB/kód-javítások (amelyek a
golden-felvétel UTÁN történtek) nem változtatták meg egyik golden képernyő
kimenetét sem — mindkét érintett üres-állapot ág (`AnalysisHomeScreen`,
`AnalysisMetricDetailScreen`) a golden-fixture NEM-üres adatával fut, tehát
az érintett kódágat a golden sosem hívta.

### 10.8 Javító kör (1. javító menet) — leletenkénti javítás és bizonyíték

A `docs/reviews/e15-r10-review.md` CHANGES REQUESTED verdiktje 1 BLOCKER + 4
MAJOR + 6 MINOR + 1 NOTE leletet mért. Az alábbi lista leletenként rögzíti a
javítást és a bizonyítékot; a §7 gate + a golden-újrafelvétel/-ellenőrzés
teljes kimenete a §10.7-et követi (frissítve a javító kör után).

- **B1 (BLOCKER) — javítva.** `analysis_processing_screen.dart`'s
  `_FailureBody`: a nem-újrapróbálható ág (`presentation.retryable == false`
  — `UnknownFailure`/`ValidationFailure`) mostantól MINDIG kap egy explicit
  `SsButton(key: Key('analysis-processing-restart'))` fallback-akciót, az
  `SsFailureState`-nek pedig csak `retryable == true` esetén adjuk át az
  `onRetry`-t (hogy sose legyen két, ugyanarra a célra mutató gomb). Bizonyíték:
  `test/features/analyze/processing_progress_test.dart` `§0.0.A/R12` csoportja
  HÁROM cellára bővült — `AnalysisInputError` (non-retryable),
  `AnalysisError`+`AudioFailure` (retryable) és `AnalysisError`+`UnknownFailure`
  (non-retryable) —, mindhárom a valódi akció jelenlétét is állítja
  (`analysis-processing-restart` kulcs vagy `FilledButton` típus), nem csak a
  `SsFailureState` típusát.
- **M1 (MAJOR) — javítva.** `analysis_home_screen.dart`: a `SsContentCard`
  (scope-on kívüli) `maxLines`+`ellipsis` csonkolása helyett a képernyő két
  kártyája (`_InputModeCard`, `_RecentAnalysisTile`) egy új, screen-lokális
  `_UntruncatedContentCard`-ot használ — ugyanazok a design-rendszer
  primitívek (`SsSurface`, `SsCardActionRegion`, `SsCardAction`), de
  `maxLines`/`overflow` nélkül. Bizonyíték:
  `test/features/analyze/recording_state_test.dart`'s `AnalysisHomeScreen —
  en/hu` A3-cellája a `takeException` mellett most `RenderParagraph
  .didExceedMaxLines`-t is ellenőrzi minden `RichText`-en — ez a mérce
  STRUKTURÁLISAN látja az ellipszist is, nem csak a kivételt.
- **M2 (MAJOR) — mérve dokumentálva, nem visszaállítható.** A
  `analysisProcessingErrorTitle`/`analysisRecordingErrorTitle`/
  `analysisRecordingErrorRetry` (utóbbi visszakötve, ld. M3) képernyő-specifikus
  szövegek forrása az `SsFailurePresentation.from(l10n, failure)` — MÉRVE ez
  egy `factory`, ami egy PRIVÁT konstruktort (`SsFailurePresentation._`) hív;
  a `title`/`message` mezők a `failure.code`-ból származnak
  (`failure_presentation.dart:59-96`), és a hívó oldalról nem
  felülírhatók anélkül, hogy a `lib/core/design_system/**` fájlt módosítanánk
  — ami a kör `allowed_paths`-án KÍVÜL van. A processzálás-képernyőn a régi
  nyers `failure.code` cseréje (§10.2 eredeti indoklása) valóban helytálló; a
  felvétel-képernyőn a cím korábban IS rendes lokalizált szöveg volt (mérve:
  `analysisRecordingErrorTitle` = "Recording couldn't start"), tehát ott a
  §10.2 eredeti indoklása MÉRVE PONTATLAN volt — ez a javító kör helyesbíti.
  A generikus (`dsFailureUnknownTitle`, "Something went wrong") cím
  MEGMARAD mindkét képernyőn, mert az ADR 0277 kód-alapú modellje ezt a
  screen-specifikus felülírást szándékosan nem teszi lehetővé a design-rendszer
  módosítása nélkül; a `analysisProcessingErrorTitle`/`analysisRecordingErrorTitle`
  ARB-kulcsok ezután is árván maradnak (nincs hívási helyük a `lib/`-ben) —
  egy jövőbeli körnek, ha vissza akarja hozni a screen-specifikus címeket,
  vagy az `SsFailurePresentation`-t kell bővítenie egy opcionális
  title-felülbírálással (ADR-döntés, ki a `lib/core/design_system/**`
  scope-ból), vagy a két árva kulcsot törölnie kell.
- **M3 (MAJOR) — javítva, a hiba MA is csak védekező ágon érhető el.**
  `analysis_recording_screen.dart`'s `_ErrorBody`: pontosan a B1 mintája —
  `presentation.retryable == false` esetén az `SsFailureState` helyett/mellett
  egy explicit `SsButton(key: Key('analysis-recording-error-retry'), label:
  l10n.analysisRecordingErrorRetry)` jelenik meg, ugyanazzal az `onRetry`
  (`_start`) callback-kel. Mérve: `mic_capture.dart` MA is kizárólag
  `PermissionFailure`/`CancelledFailure`/`AudioFailure`-t ad vissza
  (mindhárom `retryable = true`), tehát ez az ág élő úton MA is csak a
  `failure ?? const UnknownFailure()` védekező fallback-on át érhető el — a
  fix mégis szükséges, mert a `_ErrorBody` privát osztály, nem tesztelhető
  közvetlenül a védekező ág kikényszerítése nélkül; a kódmintát a B1-gyel
  szimmetrikusan tartja karban, hogy egyetlen jövőbeli, nem-újrapróbálható
  `AppFailure` hozzáadása a `data/` rétegben NE reprodukálja csendben a B1
  osztályát.
- **M4 (MAJOR) — javítva.** `analyze_screen.dart`'s `idle` fázisa többé NEM
  `SsEmptyState`-et használ: a lenti vezérlősáv (`_controls`, `:266-279`) már
  ad egy valódi "Record" CTA-t, így az `SsEmptyState` kötelező második
  akciója csak ennek szó szerinti duplikátuma lehetett (`analyzeRecord`
  felirat mindkét helyen). A fázis egy token-stílusú, cím nélküli helyi
  widgetre váltott (ugyanaz a minta, mint a MEGLÉVŐ `micError` ág — R12
  kivétel-osztály), `l10n.analyzeIntro` üzenettel. Bizonyíték:
  `test/features/analyze/mic_error_parity_test.dart` — nincs olyan cella, ami
  `find.byType(SsEmptyState)`-et állítana az idle fázisra (csak a `micDenied`
  fázisra, ami VÁLTOZATLANUL valódi, egyedi akciót ad), tehát a törlés egyetlen
  kipinnelt cellát sem gyengít; a `find.byKey(Key('analyze-idle-empty'))`
  kulcs megmaradt.
- **m1 (MINOR) — javítva.** A duplikált CTA az M4 javításával megszűnt
  (nincs többé két "Record" gomb az idle fázison). A cím-duplikáció: a
  `micDenied` fázis `title`-je `l10n.navAnalyze` helyett
  `l10n.analysisRecordingPermissionDeniedTitle` ("Microphone access needed" —
  meglévő kulcs, más képernyőn már bevezetve, ÚJ ARB-kulcs nem kellett), az
  idle fázis pedig `title` NÉLKÜL renderel (ld. M4) — egyik ág sem ismétli
  többé a `:108-113` képernyő-fejlécet.
- **m2 (MINOR) — javítva.** `analysis_metric_detail_screen.dart`'s üres ága:
  `title` `analysisOverviewMetricDetailTitle` (AppBar-duplikátum) →
  `analysisOverviewUnavailable` ("Measurement unavailable"); `message`
  `analysisOverviewNoDocument` ("No analysis document is available yet." —
  téves állítás LÉTEZŐ dokumentumnál) → `analysisOverviewNotApplicable`
  ("Not applicable for this recording"). Mindkettő meglévő, más
  `analysisOverview*` képernyőn már bevezetett kulcs — új ARB-kulcs nem
  kellett.
- **m3 (MINOR) — javítva.** A §10.2 kivétel-lista kiegészült az
  `AnalyzeSkeleton` (`:222`) és az `analyzeNoChords` (`:227-234`) ágakkal, és
  a javító kör ÚJ tagjával, az `AnalyzeScreen` idle fázisával (M4).
- **m4 (MINOR) — javítva a kóddal, itt dokumentálva.** A B1/M3 javítás
  VISSZAHOZTA mindkét törölt kulcsot: `Key('analysis-processing-restart')`
  most már MINDHÁROM ágon reachable, ahol korábban élt VAGY hiányzott
  (cancelled, permission-denied — változatlanul —, és most az input-error/
  general-error ág is, ha `retryable == false`); `Key
  ('analysis-recording-error-retry')` szintén visszatért az `_ErrorBody`
  `retryable == false` ágára. Egyik kulcs sem "eltűnt, dokumentálatlanul" —
  mindkettő aktív widget-fa-tag lett újra.
- **m5 (MINOR) — javítva.** Az A6-őszinteségi mondat (§0.0.A/R10 által
  előírt) itt, szó szerint: mért tény, hogy a hivatkozott
  `test/l10n/hardcoded_string_guard_test.dart` (`_scopeDirs`, `:18-23`) NEM
  fedi a `lib/features/**`-ot, tehát az A6 bizonyítéka a diff kézi és
  reviewer-oldali ellenőrzése, amely új beégetett felhasználói szöveget nem
  talált. A guard a kapuban marad mint a design-rendszer oldali
  regresszió-őr, nem mint az A6 bizonyítéka.
- **m6 (MINOR) — javítva.** Új `textScaler 2.0` cellák, `en` ÉS `hu`:
  `AnalyzeScreen` micDenied fázisa (`mic_error_parity_test.dart`, az idle
  fázis melletti testvér-cella) és `AnalysisRecordingScreen` `error`/
  `permissionDenied` törzse (`recording_state_test.dart`, a ready/idle
  cella melletti két testvér-cella, `FakeAudioCapture(failWith:)` illetve
  `FakeMicrophonePermissionGateway(state: denied)` állítja elő az ágat).
  Az `AnalyzeScreen` `done` fázisa (§10 "Nyitott mérési hézag") továbbra is
  méretlen marad — ez a kör-előtti `ProviderException` a review szerint a
  körtől független, javítása külön kör dolga.
- **N3 (NOTE) — dokumentálva, kód-változtatás nem szükséges.**
  `AnalysisExportScreen`-nek MÉRVE nincs saját üres/betöltés/hiba állapota: a
  törzse egészében a scope-on kívüli `ExportPreview`-ra delegál, a képernyő
  saját rétege csak az `AppBar` cím és az `SsButton`
  (`analysis-export-confirm`, `loading: _sharing`). Az A2 mérce-mátrix ezért
  erre a képernyőre nem alkalmazható — nincs mit "nyers `Text`-re
  visszacserélni" a valódi-sértés próbához sem.

### 10.9 Javító kör — záró ellenőrzés (§7 kötelező sor, csővezeték nélkül)

Az M1 javítás (SsContentCard → `_UntruncatedContentCard`) VIZUÁLISAN
megváltoztatta az `AnalysisHomeScreen`-t (a golden fixture hosszabb
tartalommal tölt, ezért a csonkolás megszűnése után a kártyák magassága nő,
`textScaler 2.0`-n a `home_compact_scale2` PNG 44%-ban tért el) — a golden a
§7/ADR 0426 szerint kizárólag a merge-kapu x86 architektúráján lett
újrafelvéve:

```
$ tools/golden-x86.sh record test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart
...
00:55 +14: All tests passed!
```

Egy második, FÜGGETLEN `check` futás (nem csak a felvétel önmaga) is
megerősítette:

```
$ tools/golden-x86.sh check test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart
...
00:57 +14: All tests passed!
```

A teljes §7 gate-sor a golden-újrafelvétel UTÁN, csővezeték/`tail` nélkül:

```
$ tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/features/analyze/analyze_cleanup_test.dart test/features/analyze/mic_error_parity_test.dart test/features/analyze/processing_progress_test.dart test/features/analyze/recording_state_test.dart test/features/audio_analysis/presentation/analysis_overview_screen_test.dart test/features/audio_analysis/presentation/analysis_export_screen_test.dart test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/e13_r27_screens_golden_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart test/core/architecture_dependency_test.dart
...
    format                                                       zöld
    analyze                                                      zöld
    test test/ui/ui_inventory_test.dart                          zöld
    test test/app/navigation/adaptive_scaffold_test.dart         zöld
    test test/app/navigation/legacy_route_redirect_test.dart     zöld
    test test/app/offline_network_guard_test.dart                zöld
    test test/features/analyze/analyze_cleanup_test.dart         zöld
    test test/features/analyze/mic_error_parity_test.dart        zöld
    test test/features/analyze/processing_progress_test.dart     zöld
    test test/features/analyze/recording_state_test.dart         zöld
    test test/features/audio_analysis/presentation/analysis_overview_screen_test.dart zöld
    test test/features/audio_analysis/presentation/analysis_export_screen_test.dart zöld
    test test/ui/goldens/e13_r26_screens_golden_test.dart        zöld
    test test/ui/goldens/e13_r27_screens_golden_test.dart        zöld
    test test/l10n/arb_parity_test.dart                          zöld
    test test/l10n/hardcoded_string_guard_test.dart              zöld
    test test/core/architecture_dependency_test.dart             zöld
    architecture                                                 zöld
MINDEN GATE ZÖLD (exit 0). A teljes suite + randomizált property gate + APK a
CI-ban fut.
```

**B1 valódi-sértés próba, megismételve a javítás UTÁN** (a §10.6 próbája a
felvétel-képernyőn, a B1/M3 szimmetrikus javítás igazolására): a
`_ErrorBody`'s `SsFailureState`-jét ideiglenesen nyers `Text`-re cserélve
(`analysis_recording_screen.dart`), `flutter test
test/features/analyze/analyze_cleanup_test.dart` →

```
00:01 +1 -1: AnalysisRecordingScreen — A5 no orphan microphone an engine
failure mid-start releases the lease it took [E]
  Expected: exactly one matching candidate
  Actual: <Found 0 widgets with type "SsFailureState": []>
```

Az A2 cella PIROSRA váltott, ugyanúgy, mint a §10.6-ban. Visszaállítva (`git
diff` üres erre a fájlra), `flutter test
test/features/analyze/analyze_cleanup_test.dart` → 5/5 zöld;
`flutter analyze lib/ test/` → No issues found.

## 11. Review — a Claude tölti ki
