# E06-R19 — Confidence calibration és capability resolver

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 19; §7.5, §19.1–19.6
- **Branch:** `codex/e06-r19-confidence-calibration-capability-resolver`
- **Előfeltétel:** **E06-R07, E06-R14, E06-R16, E06-R17 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/confidence/capability_resolver.dart",
  "lib/features/audio_analysis/engine/confidence/confidence_combiner.dart",
  "lib/features/audio_analysis/engine/confidence/calibration_table.dart",
  "lib/features/audio_analysis/engine/confidence/capability_thresholds.dart",
  "lib/features/audio_analysis/domain/analysis_capability.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/capability_report_test.dart",
  "test/features/audio_analysis/engine/capability_resolver_test.dart",
  "test/features/audio_analysis/engine/confidence_combiner_test.dart",
  "test/property/analysis_confidence_property_test.dart",
  "docs/rounds/e06-r19-confidence-calibration-capability-resolver.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R07/R14/R16/R17 merge.
> Gyűjtsd ki a **tényleges** capability-kapukat, amiket az R12/R14/R15/R16/R17
> szórtan bevezetett (`MetricGate`, `DynamicsGate`, `PitchCapabilityGate`) —
> ez a kör **egységesíti** őket, nem duplikálja. Ha egy kapu logikája
> nem mozgatható át a fájllista tágítása nélkül, az **`stopped`** + brief-revízió.
> Az R02 `analysis_capability.dart` bővítése kizárólag **additív**.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — az R01 ADR 0201 (confidence/abstention) és 0204
(capability-publikáció) végrehajtása.

## 1. Cél

**Egyetlen** helyen eldönteni, hogy melyik metrika publikálható, milyen
státusszal és milyen confidence-szel — verziózott küszöbökkel, indokolt
kombinációval és Lab-diagnosztikai lebontással.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai V1-ben **nincs** confidence a metrikákon: az `AnalyzeResult` egyetlen
  confidence-e a `TimelineStrum.confidence`, ami a CRNN softmaxa vagy a
  heurisztika értéke — **kalibrálatlan**, és semmilyen publikációs kaput nem
  vezérel.
- A `settings` ad egy felhasználói `confidenceThreshold` beállítást
  (`ss.settings.confidence_threshold`), amit a **Live** felület használ — az
  Analyze nem.
- Az Epic 6 eddigi körei **szórtan** vezettek be kapukat: R14 `MetricGate`
  (minimum eseményszám), R16 `DynamicsGate` (clipping/zaj), R17
  `PitchCapabilityGate` (voiced arány/polifónia), R12 (rövid klip),
  R15 (rács-confidence korlát).
- Az R07 riportja adja a jelminőséget, az R13 az illesztés minőségét.

## 3. Scope

**Benne:** `CapabilityResolver` (**egy** belépő: bemenete a jelminőség,
eseményszám, modell-confidence, target elérhetőség, illesztési minőség, mód és
modell-elérhetőség; kimenete `CapabilityReport` **minden** capabilityre);
`ConfidenceCombiner` (indokolt kombináció, **nem** egyszerű átlag);
`CalibrationTable` (verziózott, monoton leképezés a nyers score → kalibrált
confidence irányba); `CapabilityThresholds` (verziózott küszöbök egy helyen);
Lab-diagnosztikai breakdown; ARB az `unavailable` okok lokalizálásához.

**Kívül — TILOS:** új metrika, a meglévő metrikák **számításának**
módosítása, insight (R20), UI, kalibrációs **dataset** (R29).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/confidence/capability_resolver.dart` | ÚJ | egyetlen döntési pont |
| `.../engine/confidence/confidence_combiner.dart` | ÚJ | kombinációs policy |
| `.../engine/confidence/calibration_table.dart` | ÚJ | verziózott leképezés |
| `.../engine/confidence/capability_thresholds.dart` | ÚJ | küszöbök egy helyen |
| `.../domain/analysis_capability.dart` | meglévő | **additív** ok-értékek |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** `unavailable` szövegek |
| `test/**` | ÚJ | mátrix + property |

**Tilos zóna:** `.../engine/metrics/**` (az R14–R18 területe — a kapuk
**hívása** átalakítható, a metrikaszámítás **nem**), `lib/features/analyze/**`,
`lib/features/settings/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Egyetlen resolver, egyetlen igazság:** minden capability státusza és
   confidence-e a `CapabilityResolver`-ből jön. **NEM elfogadható:** a
   metrika-modulokban maradó, párhuzamos kapu-döntés — a metrika legfeljebb
   **bemenetet** ad a resolvernek (eseményszám, nyers score).
2. **Nincs indokolatlan átlag** (SDD §19.4): a dokumentum overall
   confidence-e **nem** a metrikák számtani átlaga; a szabály:
   `min` a kritikus capabilityken, súlyozott aggregátum a többin, és
   **kritikus capability `unavailable` → overall legfeljebb `degraded`**.
   **NEM elfogadható:** `metrics.map((m) => m.confidence).average`.
3. **A nyers score nem probability** (ADR 0201): a resolver a
   `CalibrationTable`-ön keresztül képez le, a tábla **verziózott** és a
   provenance-be kerül. A V1 táblája **identitás** (nincs valós kalibráció),
   de **explicit** `calibrationVersion = "identity.v1"` jelöléssel.
   **NEM elfogadható:** a nyers softmax `calibrated` jelöléssel.
4. **Az abstention első osztályú** (SDD §19.6): a resolver adhat
   `unavailable`-t **magas** input-minőség mellett is, ha a hipotézisek
   ellentmondanak (`confidenceTooLow`).
5. **Minden `unavailable` ok lokalizálható**: mind a 13 (R02)
   `CapabilityUnavailableReason` értékhez van ARB-kulcs **mindkét** nyelven.
   **NEM elfogadható:** „ismeretlen ok" fallback szöveg.
6. **A küszöbök verziózottak és egy helyen élnek**; a `thresholdsVersion` a
   provenance-be kerül, és a változtatása **metric version** emelést von maga
   után (ADR 0203).
7. **Determinizmus:** azonos bemenetre azonos kimenet; a resolver
   állapotmentes.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Melyek a "kritikus" capabilityk?
    blocking: true
    resolution_policy: use_default
    default: >-
      signalQuality és onsetTimeline — enélkül a dokumentum érdemi része
      nem áll meg. A lista néven nevezett konstans, a doc-comment indokolja.
  - id: OD-02
    question: Hogyan kombináljon a ConfidenceCombiner?
    blocking: true
    resolution_policy: use_default
    default: >-
      geometriai átlag a FÜGGETLEN tényezőkön (signal quality, model
      confidence, alignment quality), majd `min` a KEMÉNY kapukkal
      (event count elég? modell elérhető?). A geometriai átlag azért, mert
      egyetlen gyenge tényező érdemben lehúzza az eredményt — a számtani
      átlag elrejtené. A képlet a doc-commentben.
  - id: OD-03
    question: Hol a degraded/available határ?
    blocking: true
    resolution_policy: use_default
    default: >-
      confidence >= 0.7 → available; 0.4 <= confidence < 0.7 → degraded;
      < 0.4 → unavailable (confidenceTooLow). Néven nevezett konstansok,
      ideiglenesek az R29-ig.
```

## 6. Acceptance criteria

- [ ] **Capability-mátrix — kilenc bemeneti eset:** magas minőségű + target;
      clippelt bemenet; zajos bemenet; túl rövid klip; modell hiányzik;
      gyenge illesztés; részleges capability (pitch OK, dynamics nem);
      **határon** lévő confidence; ellentmondó hipotézisek. Mindegyikre
      **minden** capability státusza + oka ellenőrzött (nem csak egyé).
- [ ] **Available/degraded/unavailable küszöb hármasok — hat cella:**
      confidence **0.3999 / 0.4 / 0.4001** (a **0.4** már `degraded`,
      inkluzív) és **0.6999 / 0.7 / 0.7001** (a **0.7** már `available`).
      A hat érték `python3 -c`-vel generált, és a teszt közvetlenül a
      resolvernek adja őket.
- [ ] **Nincs átlag:** egy eset, ahol öt metrika confidence-e
      `[0.9, 0.9, 0.9, 0.9, 0.1]` — a számtani átlag **0.74**, a szerződött
      overall viszont ettől **eltér** (a geometriai átlag `python3 -c`-vel
      számolva **0.5581…**), és a teszt a **szerződöttre** mér, valamint
      **explicit** kimondja, hogy a 0.74 **PIROS**.
- [ ] **Kritikus capability hatása:** `signalQuality` `unavailable` esetén az
      overall completion **legfeljebb** `degraded`, akkor is, ha minden más
      metrika 1.0 confidence-ű.
- [ ] **Kalibráció-jelölés:** minden publikált confidence mellett szerepel a
      `calibrationVersion`, és a V1-ben ez **`identity.v1`**; teszt méri, hogy
      **egyetlen** confidence sincs `calibrated` forrásjelöléssel valódi
      tábla nélkül.
- [ ] **Monotonitás property:** a `CalibrationTable` leképezése **monoton
      nemcsökkenő** — véletlen bemenetekre `x1 ≤ x2 ⇒ f(x1) ≤ f(x2)`, és
      `f(x) ∈ [0,1]`.
- [ ] **Ok-lokalizáció teljesség:** teszt iterál a
      `CapabilityUnavailableReason.values` **összes** értékén, és mindegyikre
      **mindkét** ARB-ben talál kulcsot (a hiányzó → PIROS).
- [ ] **Egyetlen döntési pont:** teszt (statikus, forrásolvasó a
      `test/tooling` mintájára **vagy** hívásszámlálós seam) méri, hogy a
      metrika-modulok **nem** állítanak be capability-státuszt közvetlenül —
      minden `CapabilityReport` a resolverből származik.
- [ ] **Determinizmus:** ugyanaz a bemenet 100 futásra bitazonos kimenet.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Számtani átlag az overall confidence-hez | a „nincs átlag" cella (0.74 explicit PIROS) |
| A `degraded` küszöb exkluzív | a **pontosan 0.4** `degraded` cella |
| Az `available` küszöb exkluzív | a **pontosan 0.7** `available` cella |
| A kritikus capability nem húzza le az overallt | a `signalQuality` unavailable cella |
| A nyers score `calibrated` jelöléssel megy ki | a `calibrationVersion == identity.v1` cella |
| A kalibrációs tábla nem monoton | a monotonitás property |
| Hiányzik egy `unavailable` ok ARB-kulcsa | az ok-lokalizáció teljesség cella |
| A metrika-modul maga állít státuszt | az „egyetlen döntési pont" cella |
| A resolver állapotot tart (cache) | a 100 futásos determinizmus cella |
| **Valódi-sértés próba (§10):** egy `CapabilityUnavailableReason` ARB-kulcs ideiglenes törlése → a teljesség-cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `capability_thresholds.dart` (a szórt küszöbök összegyűjtése, verzióval).
2. RED: capability-mátrix, küszöb-hármasok, „nincs átlag" cella.
3. `calibration_table.dart` (identity.v1, monoton szerződés).
4. `confidence_combiner.dart` (geometriai átlag + kemény kapuk).
5. `capability_resolver.dart` (egyetlen belépő).
6. A metrika-modulok kapu-hívásainak átvezetése (a **hívás**, nem a számítás).
7. ARB-teljesség; property; gate.

## 9. Kockázatok

- **A kapuk átvezetése érintheti az R14–R18 fájljait** — a §4 tilos zóna
  szerint azok **nem** módosíthatók. Ha az átvezetés enélkül nem megy, az
  **`stopped`** + brief-revízió a fájllista bővítéséről (ez a legvalószínűbb
  pre-flight lelet ebben a körben — a §0.0-ban kell eldönteni).
- **A geometriai átlag 0-ra érzékeny** — a képlet `max(ε, x)` alsó vágást
  használ, `ε = 1e−6`, dokumentáltan.
- **A küszöbök kalibrálatlanok** — az eval-mátrix PENDING sort kap, és az
  R29 kalibrálja őket.

**STOP:** párhuzamos kapu meghagyása, számtani átlag vagy a nyers score
`calibrated` jelölése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r19-confidence-calibration-capability-resolver-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
