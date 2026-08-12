# E06-R15 — Rhythm consistency és groove proxyk

- **Státusz:** PLANNING (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`;
  pre-flight lezárva 2026-08-12, `main` @ `be93642d`, ADR 0233)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 15; §15.6
- **Branch:** `codex/e06-r15-rhythm-consistency-and-groove`
- **Előfeltétel:** **E06-R12, E06-R14 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/metrics/rhythm_metrics.dart",
  "lib/features/audio_analysis/engine/metrics/subdivision_analysis.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/domain/rhythm_metric_catalog_test.dart",
  "test/features/audio_analysis/engine/rhythm_metrics_test.dart",
  "test/features/audio_analysis/engine/subdivision_analysis_test.dart",
  "test/property/analysis_rhythm_property_test.dart",
  "docs/rag/chunks/021-rhythm-consistency-groove-proxies.md",
  "docs/rounds/e06-r15-rhythm-consistency-and-groove.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R12/R14 merge.
> Olvasd újra az R12 `BeatGrid` confidence-mezőit (a free-play ritmus-metrikák
> confidence-e **ebből** származik) és az R14 `MetricGate`-jét (a minimum
> eseményszám logikát **újra kell használni**, nem duplikálni). Ellenőrizd a
> `docs/rag/chunks/` következő szabad sorszámát (várhatóan **021**).
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérés (2026-08-12, orchestrátor: Claude Sonnet 5, baseline
`main` @ `be93642d`, E06-R12 és E06-R14 mindkettő merge-elve — előfeltétel
teljesül). ADR: [0233](../adr/0233-rhythm-consistency-and-groove-proxy-boundary.md).**

A brief minden hivatkozott enumját, mezőjét és sorszámát grep-elve
újramértem (AGENTS.md §2 pre-flight szabály). Egy mérési eltérés:

1. **MÉRT ELTÉRÉS — `BeatGrid`-nek nincs skalár `confidence` mezője.**
   `lib/features/audio_analysis/domain/rhythm/beat_grid.dart:34-77` a
   `BeatGrid` mezői: `beats`, `bars`, `beatsPerBar`, `beatsPerBarSource`,
   `status`, `meterStatus` — `confidence` nincs köztük. A confidence
   kizárólag pontonként él: `BeatPoint.confidence`
   (`beat_point.dart:9,21`, konstruktorban `[0,1]`-re validálva). Az eredeti
   §5.3 „confidence ≤ beatGrid.confidence" és a §6 „becsült rács
   `confidence = 0.4`" megfogalmazása egy nem létező mezőt feltételezett.
   **Feloldás (ADR 0233 Döntés 3):** az R14/ADR 0232 már elfogadott
   `buildFreePlayTimingMetrics` mintáját követve (`timing_metrics.dart:150-154`,
   a felhasznált `BeatPoint`-ok confidence-ének átlaga), a `rhythm.inferred_*`
   metrikák confidence-e felülről korlátos **a metrika által ténylegesen
   felhasznált `BeatPoint`-ok confidence-ének átlagával**. A §5.3 és a §6
   „Confidence-korlát" cella szövege lentebb ennek megfelelően javítva; a
   cella fixture-e minden felhasznált beatre **homogén** `confidence = 0.4`-et
   ad, hogy a korlát az aggregálás módjától (átlag vs. minimum) függetlenül
   egyértelmű legyen a mátrixban.

Minden más hivatkozás mérve egyezik: a `docs/rag/chunks/` következő szabad
sorszáma **021** (utolsó: `020-beat-grid-tempo-curve.md`); az R14
`MetricGate` (`engine/metrics/metric_gate.dart`) API-ja pontosan a brief §5.5
szerint újrahasználható (`isAvailable`/`isStreakAvailable`,
`minimumMatchedPairs: 8`/`minimumStreakMatchedPairs: 3`); a tilos zóna
`engine/rhythm/**` valóban az R12 saját, létező könyvtára
(`beat_grid_estimator.dart`, `tempo_curve_builder.dart`,
`tempo_hypothesis.dart`), diszjunkt az új `engine/metrics/**` fájloktól; a
`CapabilityStatus.degraded` és a `CapabilityUnavailableReason.
insufficientEvents` már léteznek (`analysis_capability.dart:19,23`), nincs
szükség új enum-értékre az „ambiguous → degraded" és „elégtelen adat"
cellákhoz; a `docs/sdd/07-epic-06-audio-analysis-2.md:3414-3459` Kör 15
szakasza 1:1 egyezik a brief scope-jával, nincs fejezet-drift.

**Új DSP-mennyiség ⇒ RAG-chunk** ugyanabban a commitban (AGENTS.md §9).

## 1. Cél

A timing-hibán **túli** ritmikai egyenletesség: inter-onset intervallum
konzisztencia, subdivision-eltérés, beat-relatív fáziseloszlás, stabil
sorozat, accent-pozíció konzisztencia — és **swing kizárólag ismert target
mellett**.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs ritmikai konzisztencia-mérés.** A mai `_bpmFromStrums` a medián
  intervallumot használja, de a **szórást** eldobja.
- Az R14 a target-alapú timing hibát méri (illesztéshez képest); a
  **rács-független** egyenletesség (IOI-szórás) ma sehol nem szerepel.
- Az R12 adja a beat-rácsot + confidence-t; free-play módban ez a rács
  **becsült**, tehát a rá épülő metrikák confidence-e nem lehet magasabb.

## 3. Scope

**Benne:** `RhythmMetrics` (IOI konzisztencia = az intervallumok
variációs együtthatója; subdivision-eltérés; beat-relatív fáziseloszlás;
leghosszabb stabil sorozat; accent-pozíció konzisztencia; **swing ratio csak
targettel**); `SubdivisionAnalysis` (a legvalószínűbb felosztás becslése a
beat-rácshoz képest); a target-alapú és a becsült-rács alapú metrikák
**szigorú elkülönítése**; katalógus- és ARB-bővítés; RAG-chunk.

**Kívül — TILOS:** stiláris címke („shuffle", „reggae"), dinamika (R16),
beat-rács becslés módosítása (R12 területe), UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/metrics/rhythm_metrics.dart` | ÚJ | konzisztencia-metrikák |
| `.../engine/metrics/subdivision_analysis.dart` | ÚJ | felosztás-becslés |
| `.../domain/analysis_metric_catalog.dart` | meglévő | **additív** ID-k |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | fixture + property |
| `docs/rag/chunks/021-…md` | ÚJ | képletek + küszöbök |

**Tilos zóna:** `lib/features/audio_analysis/engine/rhythm/**` (az R12
területe), `lib/features/live/**`, `lib/features/analyze/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A groove itt PROXY, nem stílus** (SDD §15.6): a metrikanevek mérhető
   mennyiséget írnak le. **NEM elfogadható:** „Groove score" néven publikált
   összesített szám, és **NEM elfogadható** stiláris címke validáció nélkül.
2. **A target-alapú és a becsült-rács alapú ritmus KÜLÖN metric ID**
   (`rhythm.target_*` vs `rhythm.inferred_*`), és a kettő **nem** hasonlítható
   össze. **NEM elfogadható:** azonos ID két különböző referenciával.
3. **A free-play (inferred) ritmus confidence-e felülről korlátos:**
   `confidence ≤ mean(BeatPoint.confidence a metrika által felhasznált
   beatekre)` — a `BeatGrid`-nek nincs saját `confidence` mezője (ld. §0.0,
   ADR 0233 Döntés 3). **NEM elfogadható:** a rács bizonytalanságának
   eltüntetése az aggregálásban.
4. **A swing ratio kizárólag targettel** publikálható (SDD §15.6); target
   nélkül a capability `notApplicable`. **NEM elfogadható:** swing-becslés
   szabad játékból.
5. **A minimum eseményszám kaput az R14 `MetricGate`-je adja** — nem
   duplikálva. **NEM elfogadható:** saját, eltérő küszöbű kapu.
6. **Új mennyiség ⇒ RAG-chunk**, a képlettel és a küszöbökkel, ugyanabban a
   commitban.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hogyan definiáljuk az IOI-konzisztenciát?
    blocking: true
    resolution_policy: use_default
    default: >-
      1 − CV, ahol CV = szórás/átlag a szomszédos onsetek intervallumain,
      az eredmény [0,1]-be clamp-elve; a képlet és a clamp a chunkban.
      Az "atlag" a MEDIÁN (robusztusabb), és ezt a chunk kimondja.
  - id: OD-02
    question: A subdivision becslés jelöltjei?
    blocking: true
    resolution_policy: use_default
    default: >-
      {1, 2, 3, 4} beatenkénti felosztás; a nyertes az, amelyiknél a
      beat-relatív fázisok szórása minimális; ha két jelölt szórása 5 %-on
      belül van, a felosztás `ambiguous`, és a subdivision-metrika
      `degraded`.
  - id: OD-03
    question: Mi a "stabil" sorozat feltétele?
    blocking: false
    resolution_policy: use_default
    default: >-
      egymást követő intervallumok, ahol |IOI − medián IOI| ≤ 10 % × medián IOI;
      a küszöb néven nevezett konstans a chunkban.
```

## 6. Acceptance criteria

- [ ] **Fixture-mátrix — hét cella:** egyenletes nyolcadok; egyenetlen minta
      (véletlen ±20 % IOI); szándékos swing **targettel**; véletlen onsetek;
      tempódrift (accelerando); becsült rács **alacsony** confidence-szel;
      elégtelen adat (< minimum). Mindegyikre a **teljes** metrikahalmaz.
- [ ] **IOI-konzisztencia küszöb hármas:** tökéletesen egyenletes → **1.0**;
      olyan sorozat, ahol a CV pontosan **0.1** → a metrika **0.9**
      (|Δ| ≤ 1e−9); CV = **0.5** → **0.5**. A bemeneti intervallumokat
      `python3 -c`-vel kell megkonstruálni úgy, hogy a CV **pontosan** a kívánt
      érték legyen (medián-alapú definícióval), és a teszt ezt a konstrukciót
      dokumentálja.
- [ ] **Subdivision-mátrix:** tiszta nyolcadok (subdivision **2**);
      tiszta triolák (**3**); tiszta tizenhatodok (**4**); negyedek (**1**);
      és egy **ambiguous** cella, ahol két jelölt szórása 5 %-on belül van →
      `degraded` státusz. Az ambiguous cellát szintetikusan kell előállítani,
      és a fixture konstrukcióját a teszt dokumentálja.
- [ ] **Ambiguitás-küszöb hármas** (5 %): a két jelölt szórásának aránya
      **1.049**, **1.05**, **1.051** — az **1.05** még **ambiguous**
      (inkluzív), az 1.051 már egyértelmű. `python3 -c`-vel számolt fixture.
- [ ] **Confidence-korlát:** becsült rács, amelyben minden felhasznált
      `BeatPoint.confidence` homogén **0.4** (ld. §0.0, ADR 0233 Döntés 3)
      mellett minden `rhythm.inferred_*` metrika confidence-e **≤ 0.4** —
      teszt méri mindegyikre külön.
- [ ] **Swing-kapu:** target **nélkül** a swing capability `notApplicable`
      és a metrika **nincs** a listában; targettel a swing ratio
      egy ismert 2:1 fixture-re **2.0 ± 0.05** (a tolerancia rögzített).
- [ ] **Metric ID diszjunkció:** a `rhythm.target_*` és `rhythm.inferred_*`
      halmaz metszete **üres**; egy futásban **csak az egyik** halmaz
      publikálódik.
- [ ] **Nincs stiláris címke:** teszt méri, hogy egyetlen ARB-kulcs és
      metrikanév sem illeszkedik a `(?i)(swing|shuffle|groove)_?(score|style)`
      mintára a **`swing.ratio`-n kívül** (ami mért mennyiség, targettel).
- [ ] **NaN-mentesség + tartomány property:** véletlen bemenetekre minden
      metrika véges, minden arány `[0,1]`-ben, a subdivision `{1,2,3,4}`-ben.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A CV átlagot használ medián helyett | az IOI-konzisztencia **CV = 0.1 → 0.9** cella (a fixture medián-alapú) |
| A konzisztencia nincs `[0,1]`-be clamp-elve | a CV = 0.5 és a véletlen-onset cella (negatív érték) |
| Az ambiguitás-küszöb exkluzív | a **pontosan 1.05** ambiguous-cella |
| A subdivision jelöltek közt nincs 3 | a triola-cella |
| A free-play confidence nem korlátos | a `≤ 0.4` cella (metrikánként) |
| Swing target nélkül is publikál | a swing `notApplicable` cella |
| Azonos ID target és inferred módban | a diszjunkció-cella |
| Saját, eltérő minimum-kapu | az „elégtelen adat" fixture-cella (eltérő státusz az R14-hez képest) |
| **Valódi-sértés próba (§10):** a confidence-korlát (`min(...)`) ideiglenes kiszedése → a `≤ 0.4` cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `docs/rag/chunks/021-…` (CV-definíció, subdivision-jelöltek, küszöbök).
2. RED: fixture-, küszöb- és diszjunkció-mátrix (a fixture-konstrukciók
   `python3 -c`-vel levezetve, a levezetés a tesztben kommentként).
3. `subdivision_analysis.dart`.
4. `rhythm_metrics.dart` (az R14 `MetricGate` újrahasználásával).
5. Katalógus + ARB; property; gate.

## 9. Kockázatok

- **A „pontosan CV = 0.1" fixture nehezen konstruálható** — a §8.2 előírja a
  `python3 -c` levezetést; ha a konstrukció nem pontos, a cella
  **nem mérhet** semmit (ez a mércét mérő szabály, LESSONS L13).
- **A swing 2:1 tolerancia** (±0.05) rögzített; tágítása brief-revízió.
- **Az R12 rács-confidence hiánya** blokkolhat: ha az R12 nem publikál
  rács-szintű confidence-t, a §5.3 mérhetetlen → **`stopped`**.

**STOP:** stiláris címke bevezetése, saját minimum-kapu vagy a rács
újrabecslése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r15-rhythm-consistency-and-groove-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
