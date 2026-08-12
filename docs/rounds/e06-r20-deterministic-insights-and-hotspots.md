# E06-R20 — Determinisztikus insightok és hotspot ranking

- **Státusz:** PREPARED → **revideálva** (ADR 0112 önjavító kör, H3, 2026-08-12
  — a §0.0 rögzíti a mért gyökérokot és a feloldást; eredetileg előre megírva
  2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 20; §20.1–20.7
- **Branch:** `codex/e06-r20-deterministic-insights-and-hotspots`
- **Előfeltétel:** **E06-R14, E06-R15, E06-R16, E06-R19 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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

1. **Az insight nem talál ki tényt** (SDD §20, ADR 0201): minden insight
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
      csak KOMPATIBILIS metric ID + verzió mellett (ADR 0203), és csak ha a
      változás meghaladja a metrika `minimumMeaningfulDelta` értékét.
      A trend-számítás az R25-é; itt a szabály CSAK akkor tüzel, ha a
      kontextus ilyen összehasonlítást KAP — különben `null`.
```

## 6. Acceptance criteria

- [ ] **Szabály-mátrix — 18 cella:** mind a kilenc szabályra egy **trigger** és
      egy **non-trigger** eset, a küszöbök **mindkét** oldaláról.
- [ ] **Outlier-küszöb hármas** (p90 ≥ 3 × medián): medián = 20 ms mellett
      p90 = **59.9 / 60.0 / 60.1 ms** — a **60.0** **tüzel** (inkluzív).
- [ ] **Drift-küszöb hármas** (≥ 1.5×): első fél 20 ms mellett második fél
      **29.9 / 30.0 / 30.1 ms** — a **30.0** tüzel; és egy negyedik cella,
      ahol a második félben **3** pár van → **nem** tüzel (minimum-feltétel).
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

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r20-deterministic-insights-and-hotspots-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
