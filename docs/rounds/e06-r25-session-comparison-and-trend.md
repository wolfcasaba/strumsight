# E06-R25 — Session comparison és fejlődési trend

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 25; §26.1–26.6
- **Branch:** `codex/e06-r25-session-comparison-and-trend`
- **Előfeltétel:** **E06-R21, E06-R23 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/comparison/analysis_comparison.dart",
  "lib/features/audio_analysis/domain/comparison/metric_metadata.dart",
  "lib/features/audio_analysis/domain/comparison/analysis_trend.dart",
  "lib/features/audio_analysis/engine/comparison/compatibility_evaluator.dart",
  "lib/features/audio_analysis/engine/comparison/trend_builder.dart",
  "lib/features/audio_analysis/application/compare_analyses_use_case.dart",
  "lib/features/audio_analysis/presentation/analysis_compare_screen.dart",
  "lib/features/audio_analysis/presentation/widgets/metric_delta_row.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/routing/app_route.dart",
  "lib/app/config/feature_flags.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/application/compare_analyses_use_case_test.dart",
  "test/features/audio_analysis/engine/compatibility_evaluator_test.dart",
  "test/features/audio_analysis/engine/trend_builder_test.dart",
  "test/features/audio_analysis/presentation/analysis_compare_screen_test.dart",
  "test/property/analysis_comparison_property_test.dart",
  "docs/rounds/e06-r25-session-comparison-and-trend.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R21/R23 merge.
> Olvasd újra a **tényleges** metric katalógust (R02/R14–R17 bővítései) —
> a `MetricMetadata` **minden** publikált metrikára kell hogy irányultságot
> és `minimumMeaningfulDelta`-t adjon, és ezt teljesség-teszt méri.
> Ellenőrizd az R16 dinamika-metrikák provenance-feltételét (ADR /
> SDD §16.3: dinamika csak kompatibilis gain/mic-route mellett hasonlítható).
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — az ADR 0203 (metric verzió-kompatibilitás)
végrehajtása.

**2026-08-13, H3 self-heal (ADR 0112 önjavító kör, 2. kísérlet).** Az első
dispatch (sonnet-impl) a §6 utolsó („Flag-őr") acceptance criteriáját —
„flag OFF esetén a route NEM oldható fel" — a §4 engedélyezett-fájllistával
összevetve helyesen `stopped`-ot jelzett: egy flag-mögötti route tényleges
regisztrációjához kell a router, de sem `lib/app/routing/app_router.dart`,
sem a route-katalógus `lib/app/routing/app_route.dart` nem szerepelt a
listán. Mérve (`/home/ubuntu/ss-sonnet-impl-e06-r25`, és újra-mérve ezen az
önjavító körön): `lib/app/routing/app_router.dart:259–308` az EGYETLEN hely,
ahol Audio Analysis V2 `GoRoute`-ok regisztrálódnak; `lib/app/routing/
app_route.dart:40–45` a route-konstansok katalógusa. Az implementer NULLA
fájlt módosított a halt előtt.

Ez a PONTOSAN ugyanaz a batch-authoring hiba, amit ugyanennek a batchnek
(2026-08-07) két testvérkörén már kimértek: az **E06-R23 saját, dispatch
előtti pre-flightja** (annak §0.0 1. pontja — ott még halt nélkül, mert a
pre-flight a dispatch ELŐTT elkapta) és az **E06-R24 második, halt-vezérelt
pre-flightja** ([`docs/LESSONS.md`](../LESSONS.md) **L250**) — mindkettő
ugyanerre a két fájlra bővítette a saját `allowed_paths`-át. L250
kifejezetten javasolta a batch TÖBBI, még függőben lévő brief-jének
átvizsgálását ugyanerre a mintára; ez az audit elmaradt, és a minta most
harmadszor, R25-ön jelentkezett — ezúttal élő dispatch-halt formájában, nem
pre-flightban elkapva. Ez az önjavítás ezt a konkrét, most kimért esetet
oldja fel; a batch fennmaradó, még nem dispatch-elt brief-jeinek átvizsgálása
ugyanerre a mintára külön, dedikált feladat (nem ennek az önjavításnak a
hatóköre — l. `docs/LESSONS.md` új bejegyzése).

**Feloldás:** `allowed_paths` és §4 bővítve `lib/app/routing/app_router.dart`
és `lib/app/routing/app_route.dart` fájlokkal (a route-konstans:
`AppRoutes.analysisCompare`, a meglévő `analysisOverview`/
`analysisMetricDetail`/`analysisTimeline` konstansok mellé, ugyanabban a
fájlban). **Flag-döntés:** a route a jelen kör SAJÁT, ÚJ
`analysisComparisonEnabled` flagje mögé kerül (§3 Scope már ezt írta elő —
ez NEM változik), a meglévő `if (audioAnalysisV2Enabled) [...]` blokk
mintáját követve, attól függetlenül (külön `if (analysisComparisonEnabled)
[...]` ág, NEM azon belül) — a §6 Flag-őr kritérium kifejezetten a SAJÁT
flagre vonatkozik. Regressziós teszt:
`tools/tests/test_e06_r25_router_scope.py` (a javítás előtt PIROS: az
`allowed_paths` nem tartalmazta a két fájlt).

## 1. Cél

Két elemzés **megbízható** összehasonlítása és a több sessionből épített
trend — kizárólag **kompatibilis** metrikákon, `inconclusive` állapottal, és
„nem minden nagyobb érték jobb" szemantikával.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs összehasonlítás** sehol: a Library listáz és megnyit, a
  `session_detail_screen.dart` egyetlen sessiont mutat.
- A `progress` feature aggregál gyakorlási perceket, de **nem** elemzési
  metrikákat.
- Az R21 adja a repository-t és a summary-t, az R19 a confidence-t, az R14–R17
  a metrikákat, az R23 a kártya-primitíveket.

## 3. Scope

**Benne:** `MetricMetadata` (irányultság: `lowerIsBetter` /
`higherIsBetter` / `targetRange` / `descriptive`; `minimumMeaningfulDelta`;
kompatibilis verziótartomány; input-minőségi követelmény);
`CompatibilityEvaluator`; `AnalysisComparison` + `MetricComparison`
(abszolút és relatív delta, irány: `improved`/`regressed`/`unchanged`/
`inconclusive`, confidence, sampleCount); `TrendBuilder` (minimum
sessionszám, outlier-kezelés, verzió-csoportosítás, confidence-sáv);
`CompareAnalysesUseCase`; összehasonlító képernyő + delta-sor widget;
**egy** új flag: `analysisComparisonEnabled` (default OFF).

**Kívül — TILOS:** felhő-szinkron, a `progress` feature módosítása, új
metrika, extrapoláció/predikció.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/comparison/analysis_comparison.dart` | ÚJ | eredménytípus |
| `.../domain/comparison/metric_metadata.dart` | ÚJ | irány + küszöb |
| `.../domain/comparison/analysis_trend.dart` | ÚJ | trend típus |
| `.../engine/comparison/compatibility_evaluator.dart` | ÚJ | kompatibilitás |
| `.../engine/comparison/trend_builder.dart` | ÚJ | trend |
| `.../application/compare_analyses_use_case.dart` | ÚJ | use case |
| `.../presentation/analysis_compare_screen.dart` | ÚJ | képernyő |
| `.../presentation/widgets/metric_delta_row.dart` | ÚJ | delta-sor |
| `.../public.dart` | meglévő | export |
| `lib/app/routing/app_router.dart` | meglévő | **additív** route, `analysisComparisonEnabled` flag mögött |
| `lib/app/routing/app_route.dart` | meglévő | **additív** route-konstans (`AppRoutes.analysisCompare`) |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 1 flag, OFF |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | kompatibilitás + trend + widget + property |

**Tilos zóna:** `lib/features/progress/**`, `lib/features/library/**`,
`lib/features/analyze/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Inkompatibilis sessionre NINCS összehasonlítás** (SDD §26.1): eltérő
   metric ID, inkompatibilis verzió, eltérő target, vagy érdemben eltérő
   input-minőség esetén a metrika **`inconclusive`**, indokolt okkal.
   **NEM elfogadható:** „azért megmutatjuk, csak jelezzük".
2. **Nem minden nagyobb érték jobb** (SDD §26.4): az irány a
   `MetricMetadata`-ból jön; `descriptive` metrikára (pl. BPM) **soha** nincs
   `improved`/`regressed`. **NEM elfogadható:** a BPM növekedésének
   „javulásként" jelölése.
3. **A zajszintű változás `unchanged`:** ha `|delta| < minimumMeaningfulDelta`,
   az irány `unchanged`. **NEM elfogadható:** 0.3 ms-os timing-változás
   „fejlődésként".
4. **A dinamika csak kompatibilis provenance mellett** hasonlítható
   (SDD §16.3): eltérő normalizációs policy, clipping, vagy érdemben eltérő
   jelminőség → `inconclusive`.
5. **Trend csak minimum sessionszám felett**, verzió szerint csoportosítva,
   outlier-kezeléssel; **nincs** lineáris extrapoláció a jövőbe.
   **NEM elfogadható:** „ilyen ütemben 3 hét múlva…".
6. **A trend lokálisan készül** (SDD §26.6): nincs hálózati hívás.
7. **A `MetricMetadata` teljessége gépi kapu:** minden katalógusbeli
   metric ID-hez tartozik metaadat.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mikor "érdemben eltérő" az input-minőség?
    blocking: true
    resolution_policy: use_default
    default: >-
      ha a két session `SignalQualityReport.overall` fokozata eltér (nem a
      nyers szám!), VAGY az egyik clippelt és a másik nem, VAGY a
      noiseFloorDbfs különbsége > 10 dB. Mindhárom feltétel néven nevezett
      konstanssal.
  - id: OD-02
    question: Minimum sessionszám a trendhez?
    blocking: true
    resolution_policy: use_default
    default: "3 kompatibilis session; ez alatt a trend `unavailable`."
  - id: OD-03
    question: Outlier-kezelés a trendben?
    blocking: true
    resolution_policy: use_default
    default: >-
      a medián köré 3×MAD-on kívül eső pont KIZÁRVA a trendvonalból, de
      LÁTHATÓ marad a pontlistában, és a kizárás jelölve van.
```

## 6. Acceptance criteria

- [ ] **Kompatibilitás-mátrix — kilenc cella:** azonos target + azonos verzió →
      **compatible**; eltérő metric ID → `inconclusive`; eltérő **major**
      verzió → `inconclusive`; eltérő target → `inconclusive`; egyik clippelt →
      `inconclusive`; eltérő quality-fokozat → `inconclusive`;
      noise floor Δ = **9.9 / 10.0 / 10.1 dB** (küszöb hármas: a **10.0** még
      kompatibilis, inkluzív) — a három utóbbi külön cella.
- [ ] **Irány-mátrix — négy cella:** `lowerIsBetter` metrika csökken →
      `improved`; `higherIsBetter` csökken → `regressed`; `descriptive`
      változik → **`unchanged`/`inconclusive`, soha nem improved**;
      `targetRange` metrika a tartományba lép → `improved`.
- [ ] **Meaningful-delta küszöb hármas:** `minimumMeaningfulDelta = 5 ms`
      mellett a delta **4.9 / 5.0 / 5.1 ms** — az **5.0** már **érdemi**
      (inkluzív), a 4.9 `unchanged`.
- [ ] **Trend minimum hármas:** **2 / 3 / 4** kompatibilis session — a **3**-nál
      már készül trend (inkluzív), a 2-nél `unavailable`.
- [ ] **Outlier-kezelés:** öt session, egyikük 3×MAD-on kívül → a trendvonal
      **nélküle** számolódik, de a pont **szerepel** a listában
      `excluded: true` jelöléssel. A MAD-küszöb hármasa
      (**2.99 / 3.0 / 3.01 × MAD**) külön cella, a **3.0** még **bent van**.
- [ ] **Metaadat-teljesség:** teszt iterál a metric katalógus **összes**
      ID-jén, és mindegyikhez talál `MetricMetadata`-t irányultsággal és
      `minimumMeaningfulDelta`-val (hiányzó → PIROS).
- [ ] **Nincs extrapoláció:** forrásolvasó teszt méri, hogy a `trend_builder`
      nem tartalmaz jövőbeli időpontra vonatkozó becslést (nincs
      `predict`/`forecast`/`extrapolate` szimbólum), és a trend **utolsó**
      pontja nem későbbi a legutolsó session dátumánál.
- [ ] **Nincs hálózat:** forrásolvasó teszt méri, hogy sem az engine, sem az
      application fájl nem importál `dio`-t vagy `http`-t.
- [ ] **UI:** a képernyő megjeleníti a before/after értéket, a deltát, az
      `inconclusive` **okát**, a confidence-t és a `sampleCount`-ot; 320 px-en
      és `textScaleFactor 2.0`-n nincs overflow; hu/en paritás.
- [ ] **Flag-őr:** `analysisComparisonEnabled` minden környezetben `false`, és
      flag OFF esetén a route nem oldható fel.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Inkompatibilis sessiont is összehasonlít | a kompatibilitás-mátrix `inconclusive` cellái |
| A noise-floor küszöb exkluzív | a **pontosan 10.0 dB** kompatibilis-cella |
| A BPM növekedése „javulás" | az irány-mátrix `descriptive` cellája |
| A `higherIsBetter` és `lowerIsBetter` felcserélve | az irány-mátrix első két cellája |
| A meaningful-delta exkluzív | a **pontosan 5.0 ms** érdemi-cella |
| A trend 2 sessionből is készül | a **pontosan 3 session** cella |
| Az outlier eltűnik a listából | az `excluded: true` látható-pont cella |
| Hiányzó metaadat egy metrikához | a teljesség-teszt |
| Extrapolál a jövőbe | a „nincs extrapoláció" forrásolvasó + utolsó-pont cella |
| Hálózati hívás a trendhez | a „nincs hálózat" cella |
| **Valódi-sértés próba (§10):** egy metrika `MetricMetadata` bejegyzésének ideiglenes törlése → a teljesség-teszt **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `metric_metadata.dart` + a teljesség-teszt (RED előbb).
2. RED: kompatibilitás-, irány- és küszöb-mátrix.
3. `compatibility_evaluator.dart`.
4. `analysis_comparison.dart` + `compare_analyses_use_case.dart`.
5. `analysis_trend.dart` + `trend_builder.dart` (outlier, minimum).
6. UI (compare screen + delta-sor) + ARB + flag; gate.

## 9. Kockázatok

- **A metaadat-teljesség kapu „hirtelen" piros lehet**, ha egy korábbi kör
  metrikát adott hozzá — ez **szándékos**: a kapu erre való; a hiány pótlása
  ebben a körben történik (a katalógus **nem** módosul, csak a metaadat-tábla).
- **A dinamika-összehasonlítás szinte mindig `inconclusive` lesz** valós
  használatban — ez helyes (SDD §16.3), és az eval-mátrix PENDING sort kap a
  valós eszközös ellenőrzésre.
- **A `targetRange` irány bonyolult** — ha egy metrikára nem egyértelmű,
  `descriptive` a biztonságos default, dokumentáltan.

**STOP:** inkompatibilis összehasonlítás engedélyezése, extrapoláció vagy a
`progress` feature módosítása helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r25-session-comparison-and-trend-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
