# E06-R20 — Determinisztikus insightok és hotspot ranking

- **Státusz:** PLANNING (pre-flight lezárva; két réteg — H3 self-heal
  fixture-scope-fix a `main`-en + ADR 0238 pre-flight-revízió egy korábbi,
  nem merge-elt munkapéldányból újrahasznosítva és a jelen HEAD-en
  újra-ellenőrizve, ld. §0.0; eredetileg előre megírva 2026-08-07, ma
  2026-08-12, kód olvasva: main @ `7dbaa349`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 20; §20.1–20.7
- **Branch:** `codex/e06-r20-deterministic-insights-and-hotspots`
- **Előfeltétel:** **E06-R14, E06-R15, E06-R16, E06-R19 merge**
- **Brief szerzője:** Claude (batch), pre-flight: Claude Sonnet 5 (orchestrátor) ·
  **Implementáció:** Terra

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/insights/insight_rule.dart",
  "lib/features/audio_analysis/domain/insights/recommended_action.dart",
  "lib/features/audio_analysis/engine/insights/insight_registry.dart",
  "lib/features/audio_analysis/engine/insights/insight_rules.dart",
  "lib/features/audio_analysis/engine/insights/hotspot_ranker.dart",
  "lib/features/audio_analysis/engine/insights/insight_ranker.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/engine/insight_rules_test.dart",
  "test/features/audio_analysis/engine/insight_ranker_test.dart",
  "test/features/audio_analysis/engine/hotspot_ranker_test.dart",
  "test/property/analysis_insight_property_test.dart",
  "test/fixtures/analysis/insights",
  "docs/rounds/e06-r20-deterministic-insights-and-hotspots.md",
  "docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R14/R15/R16/R19 merge.
> Gyűjtsd ki a **ténylegesen létező** metric ID-ket a katalógusból — a
> szabályok **csak létező** ID-re hivatkozhatnak, és ezt a referenciális
> integritás-teszt méri. Ellenőrizd, hogy az R18 technique-proxyk a
> diagnosztikai ágban vannak: **insight nem épülhet Lab-only proxyra**.
> PREPARED→PLANNING, brief commit előbb.
>
> **H3 self-heal revízió után (§0.0):** a §6 acceptance criteria (18 cellás
> szabály-mátrix, két küszöb mindkét oldali hármasa, referenciális
> integritás property, lokalizációs paritás) mind ugyanazt a determinisztikus
> `AnalysisDocument`/`AnalysisInsightContext` felépítést igényli, NÉGY külön
> tesztfájlban (három `test/features/audio_analysis/engine/` alatt, egy
> `test/property/` alatt) — ehhez tedd a megosztott builder(ek)et az
> `allowed_paths` új `test/fixtures/analysis/insights` bejegyzése alá, az
> `test/fixtures/vision/posture`-mintát követve (ld. lentebb).
>
> **Második pre-flight réteg (§0.0 vége):** [ADR 0238](../adr/0238-analysis-insight-evidence-and-ranking-boundary.md)
> rögzíti az insight-engine architekturális döntéseit; a §5/§5.1 két stale
> ADR-hivatkozása (0201→0216, 0203→0218) javítva.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → revideálva (ADR 0112 önjavító kör, H3, 2026-08-12).** Új ADR
nincs — ez a revízió kizárólag `allowed_paths`-ot bővíti, normatív döntést
nem hoz.

**Mért gyökérok (H3 halt, MiniMax M3 első futási kísérlete,
2026-08-12T16:53:49+00:00):** az eredeti `allowed_paths` a négy tesztfájlt
(három `test/features/audio_analysis/engine/*.dart` + egy
`test/property/analysis_insight_property_test.dart`) egyenként, névre
szólóan sorolta fel, de **egyetlen megosztott fixture-helyet sem** — miközben
a §6 acceptance criteria mind a négy fájltól **ugyanazt** a determinisztikus
`AnalysisDocument`/`AnalysisInsightContext` felépítést várja el (18 cellás
szabály-mátrix + két küszöb mindkét oldali hármasa + referenciális
integritás property + lokalizációs paritás — a property-tesztnek és a három
engine-tesztnek konzisztens dokumentum-szemantikát KELL látnia, különben a
referenciális integritás mérése hamis pozitívat/negatívat adhat a builder-
verziók közötti eltérésből). Az implementer emiatt a listán kívül hozta létre
a `test/features/audio_analysis/engine/insights/_insight_test_helpers.dart`
fájlt (branch `codex/e06-r20-deterministic-insights-and-hotspots`, commit
`fa836e87`, munkapéldány `/home/ubuntu/ss-mm-e06-r20`), és a saját STOP-
protokollja szerint helyesen `stopped`-ot jelzett, amit a scope-audit
megerősített:

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-mm-e06-r20 \
  --brief docs/rounds/e06-r20-deterministic-insights-and-hotspots.md \
  --base fa836e87
# exit 1 — "path outside allowed scope:
#   test/features/audio_analysis/engine/insights/_insight_test_helpers.dart"
```

**Feloldás:** `allowed_paths` egy `test/fixtures/analysis/insights`
könyvtárral bővült — ugyanaz a minta, mint az E05-R20 brief
`test/fixtures/vision/posture` bejegyzése (a repóban élő, elterjedt
`test/fixtures/<feature>/<alfunkció>/*_fixtures.dart` konvenció, pl.
`test/fixtures/vision/posture/posture_fixtures.dart`,
`test/fixtures/song_trainer/**`), és ugyanaz a feloldási forma, mint a
korábbi, ugyanebben az epicben mért H3 self-heal precedens (E06-R10, PR #224,
ld. [ADR 0228](../adr/0228-event-evidence-model-and-timeline-builder-contract.md)
Kontextus: „allowed_paths retargetelve a meglévő fájlra"). A konkrét
fájlnevet ez a revízió szándékosan NEM rögzíti — a builder(ek) tényleges
felosztása (egy fájl vagy több, pl. `insight_fixtures.dart`) az implementáció
döntése; a `test/fixtures/analysis/insights` könyvtár bármelyik fájlját
lefedi. A halt-olt futás saját, könyvtáron kívüli
`_insight_test_helpers.dart` útvonala továbbra is listán kívüli — ezt a
self-heal saját regressziós tesztje
(`tools/tests/test_e06_r20_insight_fixture_scope.py`) explicit méri, nehogy
a scope szélesítése véletlenül vakfoltot nyisson. 0 produkciós fájl módosult
ennél a self-healnél.

**Második pre-flight réteg (új orchestrátor-session, ugyanaznap, 2026-08-12,
main @ `7dbaa349` — a H3 self-heal UTÁN):** a kör első dispatchja előtt egy
korábbi orchestrátor-session (fallback-motorral, munkapéldány
`/home/ubuntu/ss-mm-e06-r20`) már elvégzett egy rendes pre-flightot —
kiosztotta és megírta [ADR 0238](../adr/0238-analysis-insight-evidence-and-ranking-boundary.md)-at,
és a brief két stale ADR-hivatkozását azonosította javításra —, de ez a
pre-flight-commit (`fa836e87`, branch
`codex/e06-r20-deterministic-insights-and-hotspots`) SOSEM futott be a
`main`-be: a H3 self-heal a `main`-en, ennek a pre-flight-commitnak az
ismerete nélkül revideálta a briefet (a self-heal és a pre-flight-commit
egymástól függetlenül, ugyanarról a `3f5ac41e` bázisról ágaztak el). A jelen
session a driver-skill §0.2 örökség-ellenőrzése szerint megtalálta ezt a
nem-merge-elt pre-flightot, és a felhasználás ELŐTT újra lemérte a kódban:

1. **Stale ADR-hivatkozás.** A §5 1. pontja és a §5.1 OD-03-a „ADR 0201"-et
   ill. „ADR 0203"-at idézett; a hatos ADR-blokk R01-es 0200–0205→0215–0220
   átszámozása után a helyes cím **ADR 0216**
   (`docs/adr/0216-analysis-confidence-calibration-and-abstention.md`, fejléc
   ellenőrizve: „Analysis confidence, calibration and abstention") és
   **ADR 0218** (`docs/adr/0218-analysis-metric-id-and-version-governance.md`,
   fejléc ellenőrizve: „Analysis metric ID and version governance"). Javítva
   lent.
2. **ADR 0238 tartalma.** Minden hivatkozott tény újra-grep-elve a mai kódon:
   `AnalysisHotspot` (`lib/features/audio_analysis/domain/analysis_segment.dart`)
   ma is `metricIds`/`evidenceIds`-t hordoz `AnalysisMetricId.contains`
   validációval; `AnalysisMetricId`
   (`lib/features/audio_analysis/domain/analysis_metric_catalog.dart`) ma is
   öt `technique.*` katalógus-bejegyzést tartalmaz; a meglévő
   `domain/analysis_insight.dart` (R02, bekötetlen) `factIds`-t hordoz,
   `evidenceIds`-t NEM; a technique-proxy modul
   (`lib/features/audio_analysis/engine/metrics/technique_proxies.dart`)
   önálló, `TechniqueProxyGate`/`CapabilityStatus`-mögötti fájl,
   `AnalysisDocument`-bekötés nélkül (HANDOFF E06-R18 banner is megerősíti).
   Minden állítás stimmelt — az ADR-t emiatt VÁLTOZATLAN tartalommal, csak
   egy re-verifikációs jegyzettel hasznosítja újra ez a session (két
   divergens ADR-szöveg ugyanarra a számra rosszabb lenne, mint az
   újrahasznosítás, driver-skill §0.2).
3. **Küszöb-hármas független újraszámítás** (`python3 -c`, ismételten
   ellenőrizve): `20 * 3 = 60.0` → `59.9 / 60.0 / 60.1 ms`; `20 * 1.5 = 30.0`
   → `29.9 / 30.0 / 30.1 ms` — egyezik a §6-ban már rögzített cellákkal.
4. `allowed_paths` az ADR fájl útvonalával bővült
   (`docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md`) — az
   orchestrátor írja a pre-flight-commitban, a teljes kör-PR diffje viszont
   tartalmazza.

0 produkciós fájl módosult ennél a második pre-flight-rétegnél sem.

**Harmadik réteg — kör-közbeni STOP felbontás (ugyanaz a session, 2026-08-12,
Terra első dispatchja UTÁN):** Terra a pre-flight-commit (`2d372dbf`) fölött
elkészítette mind a kilenc szabály WIP-implementációját (commitolatlanul,
`dirty_files=11`), majd helyesen `stopped`-ot jelzett: „A rush/drag,
weak-upstroke és low-signal rule küszöbei nincsenek a briefben vagy ADR
0238-ban rögzítve; saját értéket nem választhatok." Ez a §5.1 valódi hiánya
volt — az OD-01/02/03 csak az outlier/drift/improvement szabályokat oldotta
fel, a rush/drag/weak-upstroke/low-signal négy szabály küszöbét nem. Az
orchestrátor a Terra WIP-jét (nem törölve, a munkapéldányban hagyva) és a
kódot újra megmérte, mielőtt feloldotta:

1. **OD-04 (rush/drag, 20 ms)** — a Terra saját, már megírt
   `_biasThresholdMs = 20.0` konstansa HELYES: egyezik az
   `AnalysisInsightContext.timingTolerance` alapértelmezésével és az OD-01/02
   számpéldáinak bázisával. Nincs kódváltozás, csak formalizálás.
2. **OD-05 (weak upstroke, ×1.2)** — a Terra saját `_upstrokeWeakMultiplier
   = 1.25` értéke **javítandó 1.2-re**: a repóban MÁR létezik egy azonos
   szemantikájú named constant ugyanebben a metrika-családban
   (`dynamicsAccentThresholdRatio = 1.2`,
   `lib/features/audio_analysis/engine/metrics/dynamics_metrics.dart`,
   E06-R16/ADR 0234 — "attack strength exceeds local-window median by more
   than this ratio") — két külön szám ugyanarra a "hány %-kal tér el az
   elvárttól" mintára rosszabb, mint az újrahasznosítás.
3. **OD-06 (low signal quality, ≥0.05)** — a Terra saját
   `_lowQualityClippedRatio = 0.10` értéke **hibás, javítandó 0.05-re**: ez
   nem csak "más szám" kérdése, hanem **mért holt kód** — a
   `DynamicsGate.clippedEventRatioUnavailable` (ADR 0234) MÁR 0.05-nél az
   ÖSSZES dynamics-metrikát (a `clippedEventRatio`-t IS)
   `CapabilityStatus.unavailable`-re állítja
   (`lib/features/audio_analysis/engine/metrics/dynamics_metrics.dart`,
   a `gateResult.status == CapabilityStatus.unavailable` korai `return`-ág);
   a Terra 0.10-es küszöbe SOSEM lenne elérhető éles `buildDynamicsMetrics`
   kimeneten, mert a metrika már 0.05 fölött `null`-t ad
   (`context.scalar()`). A helyes, egyben a gate-tel elméletileg maximálisan
   konzisztens érték a gate SAJÁT unavailable-határa, `>=` (inkluzív,
   ugyanaz a "határon még megfigyelhető" konvenció, mint a
   `DynamicsGate` doksorában: "inclusive at exactly this value stays
   degraded").
4. Egyik javítás sem nyúl az `allowed_paths`-hoz vagy tilos zónához — mind a
   már engedélyezett `insight_rules.dart`/teszt fájlokon belüli
   értékjavítás. A §6/§6.1 három új sorral bővült (Rush/drag-küszöb hármas,
   Upstroke-küszöb hármas, Jelminőség-küszöb hármas + a holt-kód mérce-sor).

0 produkciós fájl módosult ennél a harmadik rétegnél sem (a rétegek maguk
dokumentum-only változtatások; a tényleges `insight_rules.dart`
konstans-javítás Terra következő fordulójának feladata).

## 1. Cél

A mért tényekből **determinisztikus, visszavezethető** coaching-insightok —
generatív modell nélkül, maximum-policyval, és minden insighthoz **létező**
evidence-szel.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai Analyze **nem ad** coaching-szöveget: az eredményből legfeljebb egy
  gyakorlólecke készül (`learn/public.dart` bekötése az `analyze_screen`-ben),
  és a `chordSummary` egy címkefüzér.
- Az AI Tutor (Epic 4) **saját** determinisztikus debrief-fel rendelkezik
  (E04-R08), és az ADR 0141 szerint kizárólag **validált evidence**-t kaphat —
  ez a kör az Analysis-oldali evidence-t szállítja hozzá.
- Az R14–R17 adják a metrikákat, az R19 a státuszokat és confidence-eket,
  az R10/R11 az event- és szegmens-ID-ket.

## 3. Scope

**Benne:** `AnalysisInsightRule` interfész (`id`, `version`, `priority`,
`evaluate`); `InsightRegistry`; a kilenc kezdeti szabály (rush bias; drag bias;
kevés nagy timing-outlier; második félidei drift; gyenge upstroke targethez
képest; chord-váltás hotspot; alacsony jelminőség; javulás kompatibilis
előzőhöz képest; elégtelen adat); `HotspotRanker` (súlyosság + confidence
szerint); `InsightRanker` (maximum-policy: 1 javítandó + 1 erősség +
1 következő gyakorlat + 1 felvételminőségi warning); `RecommendedAnalysisAction`
sealed hierarchia; ARB-kulcsok en+hu.

**Kívül — TILOS:** UI (R23), Tutor-adapter (R26), trend-számítás (R25),
új metrika, LLM-hívás.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/insights/insight_rule.dart` | ÚJ | szabály-szerződés + kontextus |
| `.../domain/insights/recommended_action.dart` | ÚJ | sealed action leíró |
| `.../engine/insights/insight_registry.dart` | ÚJ | regisztráció + verziók |
| `.../engine/insights/insight_rules.dart` | ÚJ | a kilenc szabály |
| `.../engine/insights/hotspot_ranker.dart` | ÚJ | hotspot rangsor |
| `.../engine/insights/insight_ranker.dart` | ÚJ | maximum-policy |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** üzenetkulcsok |
| `test/**` | ÚJ | szabály + rangsor + property |
| `test/fixtures/analysis/insights/**` | ÚJ | megosztott `AnalysisDocument`/`AnalysisInsightContext` builder(ek) a négy tesztfájlhoz (H3 self-heal, §0.0) |

**Tilos zóna:** `lib/features/ai_tutor/**`, `lib/features/audio_analysis/presentation/**`,
`lib/features/analyze/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Az insight nem talál ki tényt** (SDD §20, ADR 0216): minden insight
   `factIds` (metric ID-k) és `evidenceIds` (event/szegmens/hotspot ID-k)
   listát hordoz, és **mindegyik létező** elemre mutat.
   **NEM elfogadható:** üres `factIds`, vagy nem létező ID-re mutató insight.
2. **Az insight nem tartalmaz kész mondatot:** `messageKey` + `messageArgs`
   (R02 §5.5). **NEM elfogadható:** magyar vagy angol szöveg a szabály
   kódjában.
3. **`unavailable` metrikára nem épülhet insight:** ha a szabály bemenete
   `unavailable` vagy `notApplicable`, a szabály **`null`**-t ad.
   **NEM elfogadható:** „nem tudtuk mérni, de valószínűleg siettél".
4. **Determinisztikus rangsor:** azonos prioritású insightok között a
   **`ruleId` lexikografikus** sorrendje dönt; a rangsor 100 futásra azonos.
   **NEM elfogadható:** `Set`/`Map` iterációs sorrendtől függő kimenet.
5. **Maximum-policy** (SDD §20.5): alapból legfeljebb **1** javítandó pont,
   **1** erősség, **1** következő gyakorlat, **1** felvételminőségi warning;
   a többi a részletekben. Az erősség **csak valós evidence** esetén
   (nem „nem találtunk hibát" alapon). **NEM elfogadható:** a maximum
   túllépése, és **NEM elfogadható** a kitalált erősség.
6. **A recommended action leíró, nem callback** (SDD §20.6): sealed típus
   (`PracticeHotspotAction`, `RepeatSlowerAction`, `CalibrateInputAction`,
   `CompareWithPreviousAction`, `OpenChordTransitionExerciseAction`,
   `AskTutorAction`). **NEM elfogadható:** `VoidCallback` vagy route-string
   a domainben.
7. **Insight nem épülhet Lab-only (R18) proxyra** — a szabálykontextus
   kizárólag a **publikus** metrikákat látja.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mikor "domináns" néhány nagy outlier?
    blocking: true
    resolution_policy: use_default
    default: "p90 >= 3 × medián ÉS a medián a toleranciaablakon belül van."
  - id: OD-02
    question: Mikor "második félidei drift"?
    blocking: true
    resolution_policy: use_default
    default: >-
      a klip második felének meanAbsoluteError-ja >= 1.5 × az első feléé,
      ÉS mindkét félben legalább 4 matched pár van.
  - id: OD-03
    question: Mi számít "javulásnak" az előzőhöz képest?
    blocking: true
    resolution_policy: use_default
    default: >-
      csak KOMPATIBILIS metric ID + verzió mellett (ADR 0218), és csak ha a
      változás meghaladja a metrika `minimumMeaningfulDelta` értékét.
      A trend-számítás az R25-é; itt a szabály CSAK akkor tüzel, ha a
      kontextus ilyen összehasonlítást KAP — különben `null`.
  - id: OD-04
    question: Mikor számít a timing signed bias "rush" vagy "drag" torzításnak?
    blocking: true
    resolution_policy: use_default
    default: >-
      |signed bias| >= 20 ms (a `timing.target_signed_bias.v1` /
      `timing.freeplay_signed_bias.v1` metrikán; a katalógus dokumentálja:
      negatív = korán/rush, pozitív = későn/drag). A 20 ms UGYANAZ az érték,
      mint az `AnalysisInsightContext.timingTolerance` alapértelmezése és az
      OD-01/OD-02 fenti számpéldáinak bázisa — nem új szám. Inkluzív a
      határon (a boundary-n tüzel).
  - id: OD-05
    question: Mikor számít az upstroke "gyengének" a target-arányhoz képest?
    blocking: true
    resolution_policy: use_default
    default: >-
      mért `dynamics.down_up_median_ratio.v1` >= a kontextus által megadott
      `StrokeBalanceInsightEvidence.targetDownUpMedianRatio` × **1.2** — UGYANAZ
      a deviation-multiplier, mint a meglévő `dynamicsAccentThresholdRatio`
      (`engine/metrics/dynamics_metrics.dart`, E06-R16, ADR 0234: "attack
      strength exceeds local-window median by more than this ratio"), nem új
      szám. Inkluzív a határon.
  - id: OD-06
    question: >-
      Mikor jelez az "alacsony jelminőség" szabály figyelmeztetést, és melyik
      metrikán?
    blocking: true
    resolution_policy: use_default
    default: >-
      `dynamics.clipped_event_ratio.v1` >= **0.05** — UGYANAZ az érték, mint a
      meglévő `DynamicsGate.clippedEventRatioUnavailable` (E06-R16, ADR 0234),
      nem új szám, és EZ AZ UTOLSÓ ÉRTÉK, amin a metrika még megfigyelhető
      (`degraded`): a `DynamicsGate.evaluate` a `clippedEventRatio >
      clippedEventRatioUnavailable` (szigorúan efölött) esetén az ÖSSZES
      dynamics-metrikát — a `clippedEventRatio`-t IS — `unavailable`-re
      állítja, tehát egy ennél magasabb szabály-küszöb SOSEM lenne elérhető
      (a metrika `context.scalar()`-ja `null`-t adna, mielőtt a küszöb
      egyáltalán számítana). A "jelminőség" itt tudatosan a dynamics-pipeline
      clipping-arányát jelenti (nincs önálló, katalogizált `quality.*`
      metric ID — a nyers `AnalysisDocument.signalQuality` report NEM
      metric-katalogizált, tehát `factId`-ként nem használható, ADR 0238
      Döntés 2), nem a nyers `SignalQualityReport`-ot; ez dokumentált
      interpretáció, nem hallgatólagos scope-nyújtás.
```

## 6. Acceptance criteria

- [ ] **Szabály-mátrix — 18 cella:** mind a kilenc szabályra egy **trigger** és
      egy **non-trigger** eset, a küszöbök **mindkét** oldaláról.
- [ ] **Outlier-küszöb hármas** (p90 ≥ 3 × medián): medián = 20 ms mellett
      p90 = **59.9 / 60.0 / 60.1 ms** — a **60.0** **tüzel** (inkluzív).
- [ ] **Drift-küszöb hármas** (≥ 1.5×): első fél 20 ms mellett második fél
      **29.9 / 30.0 / 30.1 ms** — a **30.0** tüzel; és egy negyedik cella,
      ahol a második félben **3** pár van → **nem** tüzel (minimum-feltétel).
- [ ] **Rush/drag-küszöb hármas (OD-04):** signed bias = **-19.9 / -20.0 /
      -20.1 ms** — a **-20.0** rush-ként tüzel (inkluzív), -19.9 nem; szimmetrikusan
      **19.9 / 20.0 / 20.1 ms** — a **20.0** drag-ként tüzel.
- [ ] **Upstroke-küszöb hármas (OD-05):** target = 1.0 mellett mért ratio =
      **1.19 / 1.20 / 1.21** — az **1.20** (= target × 1.2) tüzel (inkluzív).
- [ ] **Jelminőség-küszöb hármas (OD-06):** `clipped_event_ratio` = **0.049 /
      0.05 / (0.06 unavailable-en keresztül)** — a **0.05** tüzel (inkluzív,
      az UTOLSÓ megfigyelhető érték); **integrációs teszt** (nem csak kézzel
      épített `AnalysisMetricResult`) bizonyítja, hogy a szabály a valódi
      `buildDynamicsMetrics`/`DynamicsGate` kimenetén is elérhető — ne csak
      szintetikus fixture-rel.
- [ ] **Referenciális integritás:** minden generált insight **minden**
      `factId`-je szerepel a dokumentum `metrics` listájában, és **minden**
      `evidenceId`-je létező event/szegmens/hotspot — property-teszt méri
      véletlen dokumentumokon.
- [ ] **`unavailable` bemenet:** ha minden timing metrika `unavailable`,
      **egyetlen** timing-insight sem keletkezik, de az „elégtelen adat"
      szabály **igen** (pontosan 1).
- [ ] **Maximum-policy:** egy olyan dokumentumra, ahol **mind a kilenc**
      szabály tüzelne, a látható lista **pontosan 4** elemű, kategóriánként
      1-1; a többi a `additionalInsights` ágban, **rangsorolva**.
- [ ] **Prioritás-ütközés determinizmus:** két azonos prioritású szabály
      esetén a sorrend a `ruleId` szerinti, és **100 futásra azonos**.
- [ ] **Erősség csak evidence-szel:** egy dokumentum, ahol nincs egyetlen
      metrika sem a „jó" tartományban → az erősség-slot **üres**
      (nem „szuper voltál").
- [ ] **Lokalizációs paritás:** minden `messageKey` **mindkét** ARB-ben
      szerepel, és minden `messageArgs` placeholder feloldható — teszt iterál
      az összes szabály összes kulcsán.
- [ ] **Nincs szöveg a kódban:** teszt (forrásolvasó) méri, hogy az
      `insight_rules.dart` nem tartalmaz nem-ASCII betűs string literált,
      és nem tartalmaz `AppLocalizations` importot.
- [ ] **Action sealed:** `switch` a `RecommendedAnalysisAction` fölött
      exhaustive default nélkül fordul.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az insight kész mondatot ad vissza | a „nincs szöveg a kódban" cella |
| Az outlier-küszöb exkluzív | a **pontosan 60.0 ms** tüzel-cella |
| A drift-küszöb exkluzív | a **pontosan 30.0 ms** tüzel-cella |
| A drift a minimum párszámot nem nézi | a 3 párós **nem tüzel** cella |
| Az insight nem létező ID-re mutat | a referenciális integritás property |
| `unavailable` metrikából insight készül | az „unavailable bemenet" cella |
| A maximum-policy hiányzik | a „pontosan 4 elemű" cella |
| A rangsor `Map` sorrendtől függ | a 100 futásos determinizmus cella |
| Az erősség kitalált | az „erősség-slot üres" cella |
| Az action `VoidCallback` | a sealed `switch` fordítási cella |
| A rush/drag-küszöb nem ±20 ms, vagy a polaritás felcserélt | a **pontosan -20.0/20.0 ms** tüzel-cellák |
| Az upstroke-multiplier nem 1.2× a target-hez képest | a **pontosan target×1.2** tüzel-cella |
| A jelminőség-küszöb a `DynamicsGate.clippedEventRatioUnavailable` (0.05) FÖLÖTT van | a szabály sosem tüzel éles `buildDynamicsMetrics` kimeneten — a metrika `unavailable`-re esik, mielőtt a küszöb elérhető lenne (holt kód); az integrációs teszt kapja el |
| **Valódi-sértés próba (§10):** egy szabály `factIds` listájának ideiglenes kiürítése → a referenciális integritás property **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `insight_rule.dart` + `recommended_action.dart` (sealed).
2. RED: szabály-mátrix (18 cella) + küszöb-hármasok.
3. `insight_rules.dart` (a kilenc szabály, kulcsokkal).
4. `insight_registry.dart` + `insight_ranker.dart` (maximum-policy).
5. `hotspot_ranker.dart`.
6. ARB en+hu; referenciális integritás property; gate.

## 9. Kockázatok

- **A szabályok küszöbei kalibrálatlanok** — az eval-mátrix PENDING sort kap,
  és a `ruleVersion` emelése kötelező bármely küszöbváltozáskor.
- **A „javulás" szabály (OD-03) függ az R25-től** — itt csak a kontextus
  bemeneti mezője létezik; ha az R25 még nincs, a szabály **soha nem tüzel**,
  és ezt teszt méri (nem `null`-pointer).
- **A maximum-policy elrejthet fontos leletet** — a `additionalInsights` ág
  rangsorolt, és a UI (R23) nyithatóvá teszi; ez a §10-ben follow-up.

**STOP:** kész szöveg a kódban, kitalált erősség vagy Lab-proxyra épülő
insight helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

**Állapot: KÉSZ — reviewra átadható.**

### Megvalósítás

- `domain/insights/`: evidence-first insight contract, determinisztikus
  kontextus és sealed recommended-action hierarchy.
- `engine/insights/`: kilenc szabály, registry, maximum-policy ranker és
  severity/confidence/ID hotspot-ranker; a szabályok csak katalogizált,
  nem-`technique.*` tényekre és létező evidence-re mutatnak.
- `test/fixtures/analysis/insights/`: a négy insight-teszt közös,
  determinisztikus document/context builder-e.
- `app_en.arb`, `app_hu.arb`, `public.dart`: additív kulcsok és public export.

### Acceptance és ellenőrzések

Mind a 13 acceptance-pont bizonyított:

1. A 18-cellás szabálymátrix mind a kilenc szabály trigger/non-trigger ágát méri.
2. Az outlier 59.9 / 60.0 / 60.1 ms, inkluzív 60.0 ms határa tesztelt.
3. A drift 29.9 / 30.0 / 30.1 ms és a 3-páros elutasító cella tesztelt.
4. A rush/drag ±20 ms inkluzív küszöbe és polaritása tesztelt.
5. A weak-upstroke 1.19 / 1.20 / 1.21, inkluzív 1.2× target-küszöbe tesztelt.
6. A low-signal 0.049 / 0.05 küszöbe, valamint a valós
   `buildDynamicsMetrics`/`DynamicsGate` útvonalon a 0.05-ös trigger és a
   0.06-os unavailable ág tesztelt.
7. A 200 seedelt dokumentumos property a fact/evidence referenciális zártságát méri.
8. Minden unavailable timing bemenet csak a pontosan egy insufficient-data insightot adja.
9. Kilenc bemenetből pontosan négy látható slot marad, a többi rangsorolt.
10. Azonos prioritásnál a `ruleId` sorrend 100 futáson át azonos.
11. Evidence nélküli erősség-slot üres marad.
12. Mind a kilenc rule saját trigger-kontekstusából ellenőrzött en/hu ARB-kulcsot
    és placeholdert kap; a szabálykód nem lokalizált próza és nem importál l10n-t.
13. A sealed action exhaustive, default nélküli `switch`-e fordul.

Lefuttatva:

```text
flutter test test/features/audio_analysis/engine/insight_rules_test.dart
  → 15 teszt zöld
flutter test test/features/audio_analysis/engine/insight_rules_test.dart \
  test/features/audio_analysis/engine/insight_ranker_test.dart \
  test/features/audio_analysis/engine/hotspot_ranker_test.dart \
  test/property/analysis_insight_property_test.dart
  → 21 teszt zöld
tools/round-gate.sh test/features/audio_analysis test/property test/app
  → format, analyze, mindhárom tesztcsoport, architecture, secrets, l10n zöld
```

`git diff --cached --stat` a handoff előtti implementation-diffre:

```text
14 files changed, 1760 insertions(+), 2 deletions(-)
```

`git diff --check` zöld. Nem futtatott ellenőrzés: teljes `flutter test`, friss
randomizált property gate és release APK — ezek a kör CI-kapui, az
orchestrátor dispatch-eli őket.

### Scope és következő kör

Csak a §4 engedélyezett útvonalai változtak; UI-, Tutor-adapter- és Lab-proxy
integráció nincs. Következő SDD-kör: E06-R21, a reviewer és CI után.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r20-deterministic-insights-and-hotspots-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
