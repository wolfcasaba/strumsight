# E06-R12 — Beat grid és tempo curve

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 12; §14.1–14.6
- **Branch:** `codex/e06-r12-beat-grid-and-tempo-curve`
- **Előfeltétel:** **E06-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/rhythm/beat_point.dart",
  "lib/features/audio_analysis/domain/rhythm/tempo_point.dart",
  "lib/features/audio_analysis/domain/rhythm/beat_grid.dart",
  "lib/features/audio_analysis/engine/rhythm/beat_grid_estimator.dart",
  "lib/features/audio_analysis/engine/rhythm/tempo_curve_builder.dart",
  "lib/features/audio_analysis/engine/rhythm/tempo_hypothesis.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/engine/beat_grid_estimator_test.dart",
  "test/features/audio_analysis/engine/tempo_curve_builder_test.dart",
  "test/property/analysis_beat_grid_property_test.dart",
  "docs/rag/chunks/020-beat-grid-tempo-curve.md",
  "docs/rounds/e06-r12-beat-grid-and-tempo-curve.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R10 merge. Olvasd újra
> a `ClipAnalyzer._bpmFromStrums`-t (`clip_analyzer.dart` 229–240): **medián
> intervallum**, `dt > 0.05` szűrő, `(60 / median).clamp(30, 300)`, és
> `strums.length < 2` esetén **0**. A legacy BPM-nek ezzel **paritásosnak**
> kell maradnia. Ellenőrizd a `docs/rag/chunks/` következő szabad sorszámát
> (az R07 után várhatóan **020**). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs. **Új DSP-mennyiség ⇒ RAG-chunk ugyanabban a
commitban** (AGENTS.md §9).

## 1. Cél

Az egyetlen BPM-szám helyett **időbeli** beat-rács és tempógörbe, forrás- és
confidence-jelöléssel, half/double-time bizonytalanság kezelésével — a mai
BPM-összefoglaló **megőrzése** mellett.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai tempó **egyetlen** szám: `AnalyzeResult.bpm`, a
  `_bpmFromStrums`-ból: 0.05 s-nál nagyobb strum-közök **mediánja**,
  `60 / median`, `.clamp(30, 300)`; kettőnél kevesebb strum → **0**.
- **Nincs** beat-rács, **nincs** bar-fogalom (a `beatsPerBar` mező létezik, de
  a recorded klipeken mindig **4**; csak a felhasználói SONG-ból származó
  szintetikus eredmény hoz mást — `analyze_result.dart` 128–131).
- **Nincs** tempógörbe, drift, IQR vagy stabil-régió mérés.
- A `lib/features/live/engine/dsp/tempo_tracker.dart` létezik, de a
  `ClipAnalyzer` **nem** használja (az allowlist sem tartalmazza) — a V2 sem
  importálhatja (az allowlist csak szűkülhet).
- Az R10 adja az `OnsetEvent`/`StrumEvent` listát sample indexszel.
- Az `analysisBeatGridEnabled` flag az R02-ből létezik, default OFF.

## 3. Scope

**Benne:** `BeatPoint` (index, idő, confidence, **source**), `BarPoint`,
`TempoPoint`, `BeatGrid` aggregátum; `BeatGridEstimator` (free-play: onset-köz
alapú inferencia; target esetén a **target timebase elsődleges**);
`TempoHypothesis` (half/double-time alternatívák + confidence-csökkentés);
`TempoCurveBuilder` (medián BPM, IQR, lokális eltérés, drift slope, ugrások,
stabil-régió arány); RAG-chunk.

**Kívül — TILOS:** target-illesztés (R13), timing metrikák (R14), metre
**inferencia** free-play módban (kísérleti, későbbi kör), `tempo_tracker.dart`
importálása, DSP-konstans, `lib/features/analyze/**`, `lib/features/live/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/rhythm/beat_point.dart` | ÚJ | beat + forrás |
| `.../domain/rhythm/tempo_point.dart` | ÚJ | tempógörbe pont |
| `.../domain/rhythm/beat_grid.dart` | ÚJ | rács + bar aggregátum |
| `.../engine/rhythm/beat_grid_estimator.dart` | ÚJ | inferencia / target-átvétel |
| `.../engine/rhythm/tempo_hypothesis.dart` | ÚJ | half/double-time |
| `.../engine/rhythm/tempo_curve_builder.dart` | ÚJ | görbe + stabilitás |
| `.../public.dart` | meglévő | export |
| `test/**` | ÚJ | fixture + property |
| `docs/rag/chunks/020-…md` | ÚJ | formulák + küszöbök |

**Tilos zóna:** `lib/features/live/**`, `lib/features/analyze/**`,
`lib/app/config/feature_flags.dart` (a flag már létezik). Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A legacy BPM megmarad, paritásosan:** a `tempo.legacy_bpm.v1` metrika
   értéke **pontosan** a `_bpmFromStrums` képlete (medián, 0.05 s szűrő,
   clamp 30–300, <2 esemény → 0) — a V2 saját tempóbecslése **külön** metrika
   (`tempo.median_bpm.v1`). **NEM elfogadható:** a legacy BPM
   „megjavítása" (pl. a clamp elhagyása), és **NEM elfogadható** a két
   metrika összemosása.
2. **Target esetén a target rács az elsődleges** (SDD §14.5): ha van
   `AnalysisTarget` timebase, a beat-pontok **onnan** jönnek,
   `BeatSource.target` jelöléssel, és a becslés **nem fut le**.
   **NEM elfogadható:** a target rács „ellenőrzésképpen" újrabecslése.
3. **Half/double-time = alternatív hipotézis, nem hallgatólagos választás**
   (SDD §14.6): free-play módban, ha a rács 2× vagy ½× is konzisztens, a
   `TempoHypothesis` **mindkettőt** hordozza, és a publikált confidence
   **csökken** a dokumentált szabály szerint. **NEM elfogadható:** a
   „legvalószínűbb" néma kiválasztása confidence-csökkentés nélkül.
4. **Rövid klipen nincs tempótrend** (SDD §14.3): a minimum eseményszám alatt
   a `tempoCurve` capabilityje `unavailable`
   (`CapabilityUnavailableReason.insufficientEvents`), miközben a beat-rács
   `degraded`-ként még előállhat. **NEM elfogadható:** egyetlen intervallumból
   számolt „drift".
5. **A tempógörbe időrendezett és NaN-mentes**; a drift slope
   mértékegysége dokumentált (**BPM/perc**).
6. **Nincs metre-állítás gyenge confidence-szel** (SDD §14.4): free-play
   metre-inferencia ebben a körben **nem készül**; a `beatsPerBar` a targetből
   vagy a legacy 4-ből jön, forrásjelöléssel.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mennyi a minimum eseményszám a tempógörbéhez?
    blocking: true
    resolution_policy: use_default
    default: >-
      8 onset/strum esemény ÉS legalább 4 másodperc klip-hossz — mindkettő
      néven nevezett konstans a RAG-chunkban, ideiglenesként jelölve az
      E06-R29 evaluationig.
  - id: OD-02
    question: Hogyan dől el a half/double-time ambiguitás free-play módban?
    blocking: true
    resolution_policy: use_default
    default: >-
      a becsült BPM a [60, 180] "preferált" sávba tolódik ×2 / ÷2 lépésekkel,
      DE az eredeti hipotézis is megmarad a listában, és a confidence
      szorzója 0.7, ha volt tolás. A sáv és a szorzó a chunkban rögzített.
  - id: OD-03
    question: A stabil-régió arány definíciója?
    blocking: true
    resolution_policy: use_default
    default: >-
      azon TempoPoint-ok időarányos hányada, ahol a lokális BPM a medián
      ±5 %-án belül van (a küszöb néven nevezett konstans).
```

## 6. Acceptance criteria

- [ ] **Legacy BPM paritás:** a `tempo.legacy_bpm.v1` értéke a kilenc R09-
      fixture-re **bitre** egyezik a V1 `AnalyzeResult.bpm`-mel
      (|Δ| ≤ 1e−9), beleértve a `< 2 esemény → 0` és a `clamp` eseteket.
- [ ] **Tempó-fixture mátrix:** 60 BPM; 120 BPM; szintetikus accelerando
      (60→90); szintetikus ritardando (120→90); egyenetlen (véletlen)
      onsetek; **7** esemény (a minimum alatt); **8** esemény (a minimumon);
      3/4 target; 4/4 target — kilenc cella, mindegyik a **teljes**
      `BeatGrid` + `TempoCurve` kimenetre.
- [ ] **Minimum eseményszám küszöb hármas:** **7 / 8 / 9** esemény — a **8**
      esetén a tempógörbe **elkészül** (a határ inkluzív), a 7 esetén
      `unavailable` `insufficientEvents` okkal. A klip-hossz küszöbre külön
      hármas: **3.999 s / 4.0 s / 4.001 s**.
- [ ] **Half/double-time mátrix:** 55 BPM-es fixture (a preferált sáv alatt) →
      a hipotézis-lista **két** elemű (55 és 110), a publikált a **110**, a
      confidence szorzója **0.7**; 120 BPM-es fixture → **egy** hipotézis,
      **nincs** confidence-csökkentés. A `0.7`-es szorzót teszt méri
      (|Δ| ≤ 1e−9).
- [ ] **Stabil-régió küszöb hármas** (medián ±5 %): egy 120 BPM medián mellett
      a **113.9 / 114.0 / 114.1** BPM-es lokális pontok — a **114.0**
      (= 120 × 0.95) **stabilnak** számít (inkluzív határ), a 113.9 nem.
      Az értékeket `python3 -c "print(120*0.95)"` alapján.
- [ ] **Target-elsődlegesség:** targettel futtatva minden `BeatPoint.source ==
      BeatSource.target`, és a becslő **nem futott** (számlálós fake:
      `estimateCallCount == 0`).
- [ ] **Rendezettség + NaN-mentesség property:** véletlen bemenetekre a
      beat-pontok és tempópontok **szigorúan monoton** időrendben állnak,
      minden BPM véges és `(0, 400]`-ban van, minden confidence `[0,1]`-ben.
- [ ] **Nincs metre-állítás:** teszt méri, hogy free-play módban a
      `beatsPerBar` forrása `legacyDefault`, és a `meter` capability
      `notApplicable`.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A legacy BPM elhagyja a clampet | a 300 BPM feletti fixture legacy-paritás cellája |
| A legacy és az új BPM ugyanaz a metrika | a két metrika **külön ID** cellája + a paritás |
| A minimum eseményszám exkluzív | a **pontosan 8 esemény** cella |
| Az ambiguitást némán feloldja | az 55 BPM-es fixture „két hipotézis" + 0.7-szorzó cellája |
| A confidence-szorzó más érték | a 0.7 |Δ| ≤ 1e−9 cella |
| A stabil-régió küszöb exkluzív | a **pontosan 114.0 BPM** cella |
| Target esetén is fut a becslés | az `estimateCallCount == 0` cella |
| Egyetlen intervallumból számol driftet | a 7-eseményes `insufficientEvents` cella |
| Free-play metre-t állít | a `meter` capability `notApplicable` cella |
| **Valódi-sértés próba (§10):** a target-ág ideiglenes kikapcsolása (mindig becsül) → az `estimateCallCount == 0` cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `docs/rag/chunks/020-beat-grid-tempo-curve.md` (formulák, küszöbök, indok).
2. RED: legacy-paritás, tempó-fixture, küszöb- és ambiguitás-mátrix.
3. `beat_point.dart` / `tempo_point.dart` / `beat_grid.dart`.
4. `tempo_hypothesis.dart` (sáv + szorzó).
5. `beat_grid_estimator.dart` (target-elsődlegesség, számlálós teszt-seam).
6. `tempo_curve_builder.dart` (medián, IQR, drift, stabil régió).
7. Property; gate.

## 9. Kockázatok

- **A saját beat-inferencia gyengébb lehet a `tempo_tracker`-nél** — de az
  importja allowlist-bővítés lenne (tilos). A §10-ben rögzítendő follow-up:
  a közös DSP-boundary (SDD §8.2) egy későbbi, mért körben oldja fel.
- **A küszöbök kalibrálatlanok** — a chunk „ideiglenes az R29-ig" jelöléssel,
  és az eval-mátrix kap egy PENDING sort.
- **A `beatsPerBar` kettős forrása** (target vs legacy 4) könnyen összekeverhető
  — a forrásjelölés kötelező, és teszt méri.

**STOP:** `tempo_tracker.dart` importálása, allowlist-bővítés vagy a legacy
BPM „javítása" helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r12-beat-grid-and-tempo-curve-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
