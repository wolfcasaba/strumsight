# E06-R09 — V1 ClipAnalyzer stage adapter és parity

- **Státusz:** PREPARED (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 9; §8.4, §10.1
- **Branch:** `codex/e06-r09-clip-analyzer-stage-adapter-parity`
- **Előfeltétel:** **E06-R04, E06-R08 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart",
  "lib/features/audio_analysis/engine/legacy/legacy_evidence.dart",
  "lib/features/audio_analysis/engine/analysis_provenance_builder.dart",
  "lib/features/audio_analysis/public.dart",
  "tool/check_architecture.dart",
  "test/features/audio_analysis/engine/clip_analyzer_stage_test.dart",
  "test/features/audio_analysis/engine/clip_analyzer_parity_test.dart",
  "test/property/analysis_legacy_parity_property_test.dart",
  "docs/rounds/e06-r09-clip-analyzer-stage-adapter-parity.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R04/R08 merge. Olvasd
> újra `lib/features/analyze/engine/clip_analyzer.dart`-ot (241 sor) és a
> `tool/check_architecture.dart` **10–21. sorát** — a mai allowlist **12**
> `analyze → live/engine/*` bejegyzést tartalmaz. **Az allowlist csak
> SZŰKÜLHET** (ADR 0176): ez a kör **nem** vehet fel `audio_analysis → live`
> bejegyzést. Ha a pre-flight azt méri, hogy az adapter csak új bejegyzéssel
> építhető meg, az **azonnali brief-revízió** (a §5.1 OD-01 feloldása szerint),
> nem néma allowlist-bővítés. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs. Ez a kör a **legérzékenyebb** paritás-kör: a
bizonyított V1 DSP-t köti be a V2 pipeline-ba **viselkedésváltozás nélkül**.

## 1. Cél

A mai `ClipAnalyzer` bekötése az R04 pipeline-ba **stage-adapterként**, úgy
hogy a stage kimenete **köztes evidence** (nem UI-modell), és a V1↔V2
kimenet paritása fixture-ökön **számszerűen** bizonyított.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `ClipAnalyzer` (241 sor) konstruktor-paraméterei: `chunkSize = 2048`,
  `strumRefiner`, `chromaMedianWindow = 1`, `bassWeight` (null → `DspConfig.
  chordBassWeight`). Két passz: `_strumPass` (LivePipeline, `identical`
  alapú új-strum detektálás, `frame.latestStrumTime`) és `_chordPass`
  (`DspConfig.nnlsWindow`/`nnlsHop`, NNLS chroma → `ViterbiChordDecoder.
  decodeBatch` → szegmens-összefűzés, a no-chord frame **fenntartja** a nyitott
  szegmenst), plusz `_bpmFromStrums` (medián intervallum, `dt > 0.05` szűrő,
  `.clamp(30, 300)`).
- A `_refine` a CRNN verdiktjét alkalmazza; hossz-eltérés vagy kivétel →
  **heurisztikus** címkék maradnak (`clip_analyzer.dart` 88–111).
- A `runClipAnalysis` az isolate-belépő; a Lab-ág `MlChordDecoder`-t futtat és
  `MlChordDiagnostics`-ot csatol (`analyze_providers.dart` 41–79).
- `tool/check_architecture.dart` 10–21: **12** engedélyezett cross-feature
  import (`analyze/engine/clip_analyzer.dart` és `ml_chord_decoder.dart` és
  `providers/analyze_providers.dart` → `live/engine/{dsp,ml}/…`).
- Meglévő paritás-őrök: `test/features/analyze/clip_analyzer_test.dart`,
  `batch_chord_timeline_test.dart`, `clip_analyzer_ml_test.dart`,
  `ml_chord_wiring_test.dart`, és `test/property/chord_timeline_property_test.dart`.

## 3. Scope

**Benne:** `ClipAnalyzerStage` (R04-stage, ami a **meglévő** `ClipAnalyzer`-t
hívja a `lib/features/analyze/public.dart` határon keresztül);
`LegacyEvidence` (köztes evidence-típus: strum- és chord-lista + a hívási
paraméterek); `AnalysisProvenanceBuilder` (chunk size, chroma window, bass
weight, strum refiner source, model manifest ID-k rögzítése);
paritás-tesztek; ha a `tool/check_architecture.dart` a fenti határ miatt
szűkíthető, a **szűkítés** is ide tartozik.

**Kívül — TILOS:** a `ClipAnalyzer` **bármely** sorának módosítása, DSP-
konstans, új `analyze → live` allowlist-bejegyzés, a `computeClipAnalysis`
átírása, isolate-futtatás (R22).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/legacy/clip_analyzer_stage.dart` | ÚJ | R04-stage a V1 analyzer köré |
| `.../engine/legacy/legacy_evidence.dart` | ÚJ | köztes evidence típus |
| `.../engine/analysis_provenance_builder.dart` | ÚJ | provenance összeállítás |
| `.../public.dart` | meglévő | evidence export |
| `tool/check_architecture.dart` | meglévő | **kizárólag szűkítés/új szabály hozzáadása** |
| `test/features/audio_analysis/engine/*` | ÚJ | stage + paritás tesztek |
| `test/property/analysis_legacy_parity_property_test.dart` | ÚJ | randomizált paritás |

**Tilos zóna:** `lib/features/analyze/**` (minden fájl), `lib/features/live/**`,
`assets/ml/**`, `docs/rag/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A V1 analyzer bitre változatlan.** A stage **hívja**, nem másolja, nem
   javítja. **NEM elfogadható:** a `ClipAnalyzer` „kis" refaktorálása a
   bekötés kedvéért; **NEM elfogadható** a kód átmásolása az
   `audio_analysis` alá (az duplikált DSP-igazságot hozna létre).
2. **Az import a `public.dart`-on át megy** (ADR 0176): az `audio_analysis`
   a `lib/features/analyze/public.dart`-ot importálja, ami már ma exportálja
   az `AnalyzeResult`-ot és a providereket. **NEM elfogadható:** közvetlen
   import `lib/features/analyze/engine/clip_analyzer.dart`-ra.
3. **Az allowlist csak szűkülhet.** Ez a kör **nem** ad hozzá bejegyzést.
4. **A stage kimenete evidence, nem UI-modell:** a `LegacyEvidence` a
   timeline-építés **bemenete** (R10/R11), nem a végleges `AnalysisTimeline`.
   **NEM elfogadható:** a stage közvetlenül `AnalysisDocument`-et állít elő.
5. **A fallback látszik a provenance-ben:** ha a strum refiner null volt vagy
   kivételt dobott, a provenance `strumRefinerSource = heuristic` +
   `fallbackReason`. **NEM elfogadható:** a fallback néma elnyelése (a mai
   `catch (_)` a V1-ben marad, de a V2 provenance **jelöli**).
6. **A paritás számszerű, nem „hasonló":** a toleranciák a briefben
   rögzítettek (lásd §6), tágításuk brief-revízió.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mi van, ha a public.dart nem exportálja a ClipAnalyzer-t?
    blocking: true
    resolution_policy: use_default
    default: >-
      A mai `analyze/public.dart` az `AnalyzeResult`-ot, a providereket
      (köztük a top-level `runClipAnalysis`/`computeClipAnalysis`
      függvényeket), a `timeline_view`-t és az `ml_chord_decoder`-t exportálja.
      Ha a `ClipAnalyzer` OSZTÁLY nem érhető el a barrelen át, a stage a
      `runClipAnalysis((pcm, sr, null, false, null))` szinkron belépőt hívja
      — ez az EXPORTÁLT út, és pontosan a shipping viselkedést adja.
      Az `analyze/public.dart` bővítése (a ClipAnalyzer exportja) csak akkor,
      ha a fenti út bizonyítottan nem járható → az `stopped` + brief-revízió.
  - id: OD-02
    question: A Lab (ML chord) ág is ide tartozik?
    blocking: false
    resolution_policy: use_default
    default: >-
      NEM ebben a körben — a stage `labMode = false`-szal hívja a belépőt.
      A Lab-ág és a decoder-provenance az E06-R11 dolga.
```

## 6. Acceptance criteria

- [ ] **Paritás-mátrix — kilenc fixture:** csend; két akkord; négy akkord
      (C·G·Am·F 0.8 s-onként); ring-out átfedés; egyetlen strum;
      ismert BPM-ű strum-sorozat; dobó refiner (fallback); üres bemenet;
      `sampleRate = 0`. Mindegyikre a V1 `ClipAnalyzer.analyze` és a V2
      stage kimenete **összevetve**.
- [ ] **Számszerű paritás-tolerancia (rögzített, tágítása brief-revízió):**
      chord-szegmensek **darabszáma azonos**; a szegmenshatárok időben
      |Δ| ≤ **1 µs**; a strum-események **darabszáma azonos**, időben
      |Δ| ≤ **1 µs**, iránya **azonos**; a BPM |Δ| ≤ **1e−9**.
      **NEM elfogadható** a tolerancia tágítása „lebegőpontos zaj" indokkal —
      a stage ugyanazt a kódot hívja, tehát a különbség **nulla** kell legyen
      a `Duration`-átváltás kerekítésén kívül.
- [ ] **Küszöb hármas az időátváltásra:** a `double` másodperc →
      `Duration` mikroszekundum kerekítés cellái a **0.0000005 s**,
      **0.0000015 s** és **0.0000025 s** időpontokra (a `python3 -c`-vel
      számolt várt értékek: **0 µs / 2 µs / 2 µs** banker's rounding esetén,
      **1 µs / 2 µs / 3 µs** `round()` esetén) — a teszt rögzíti, MELYIK
      kerekítés a szerződés, és a másikat pirosra váltja.
- [ ] **Fallback-provenance:** dobó refinerrel a provenance
      `strumRefinerSource == heuristic` **és** `fallbackReason` nem null;
      null refinerrel `strumRefinerSource == none`; működő refinerrel
      `strumRefinerSource == crnn`. Három cella.
- [ ] **Provenance-teljesség:** a `chunkSize`, `chromaMedianWindow`,
      `bassWeight` (a tényleges effektív érték, nem `null`), `nnlsWindow`,
      `nnlsHop` mind szerepel a provenance-ben — teszt méri mind az ötöt.
- [ ] **Randomizált paritás property:** `PROPERTY_SEED`-ből vezérelt
      **legalább 50** véletlen szintetikus klipre a V1 és V2 kimenet a fenti
      toleranciákon belül egyezik.
- [ ] **Architektúra:** `dart run tool/check_architecture.dart` zöld, és a
      cross-feature allowlist **nem nőtt** (a bejegyzések száma ≤ 12 —
      teszt méri a `test/tooling` alatt).
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**` vagy `lib/features/live/**` útvonalat, és
      `test/features/analyze` **átírás nélkül** zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A stage lemásolja a DSP-t az `audio_analysis` alá | a `git diff --stat` + a paritás-mátrix első eltérő fixture-cellája |
| A stage közvetlenül importálja a `clip_analyzer.dart`-ot | `tool/check_architecture.dart` **PIROS** (nincs allowlist-bejegyzés) |
| Új allowlist-bejegyzés kerül be | a „bejegyzések száma ≤ 12" tooling-teszt |
| A `Duration` átváltás `floor`-t használ a szerződött `round` helyett | az időátváltás-küszöb hármas középső/felső cellája |
| A tolerancia utólag 1 ms-ra tágul | a rögzített |Δ| ≤ 1 µs cella (a brief a szerződés) |
| A fallback nem jelenik meg a provenance-ben | a három fallback-cella |
| A `bassWeight = null` nyersen kerül a provenance-be | a provenance-teljesség „effektív érték" cellája |
| A stage `AnalysisDocument`-et állít elő | a „kimenet evidence" típus-cella (a fordító + a teszt) |
| **Valódi-sértés próba (§10):** a `chunkSize` provenance-bejegyzés ideiglenes törlése → a provenance-teljesség cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/tooling test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. Pre-flight: a `analyze/public.dart` exportjainak mérése (OD-01 eldöntése).
2. RED: paritás-mátrix a kilenc fixture-re, V1 referenciával.
3. `legacy_evidence.dart` + `clip_analyzer_stage.dart`.
4. `analysis_provenance_builder.dart` (öt paraméter + refiner source).
5. Randomizált paritás property.
6. Architektúra-teszt (allowlist nem nőtt); gate.

## 9. Kockázatok

- **A `public.dart` határ hiánya** blokkolhat (OD-01) — a feloldás az
  exportált `runClipAnalysis` belépő; ha az sem elérhető, `stopped`.
- **A „paritás" csábítóan tágítható** — a brief számszerűen rögzíti; a
  reviewer a toleranciát a brieffel veti össze, nem a kód kommentjével.
- **A `runClipAnalysis` `compute`-belépőként van megírva** (rekord-paraméter):
  szinkron hívása helyes, de a §10-ben rögzíteni kell, hogy a stage
  **nem** indít isolate-ot — az az R22 dolga.

**STOP:** allowlist-bővítés, `ClipAnalyzer`-módosítás vagy DSP-másolás helyett
`stopped` + dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r09-clip-analyzer-stage-adapter-parity-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
