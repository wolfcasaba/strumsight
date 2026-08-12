# E06-R11 — Chord evidence, segmentation és decoder provenance

- **Státusz:** PLANNING (pre-flight revízió: 2026-08-12, main @ `1a61fabe`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 11; §13.3–13.6
- **Branch:** `codex/e06-r11-chord-evidence-segmentation-provenance`
- **Előfeltétel:** **E06-R09, E06-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/harmony/chord_frame_evidence.dart",
  "lib/features/audio_analysis/domain/analysis_segment.dart",
  "lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart",
  "lib/features/audio_analysis/engine/harmony/chord_label_normalizer.dart",
  "lib/features/audio_analysis/engine/harmony/decoder_source.dart",
  "lib/features/audio_analysis/data/legacy_view_adapter.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "test/features/audio_analysis/engine/chord_segment_assembler_test.dart",
  "test/features/audio_analysis/engine/chord_label_normalizer_test.dart",
  "test/property/analysis_chord_segment_property_test.dart",
  "docs/adr/0229-analysis-chord-decoder-fusion-strategy.md",
  "docs/rounds/e06-r11-chord-evidence-segmentation-provenance.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R09/R10 merge.
> **ADR 0229** a foglaló által kiosztva. Olvasd újra a `ClipAnalyzer._chordPass`
> **tényleges** szegmensösszefűzését (`clip_analyzer.dart` 199–226): a
> **no-chord frame FENNTARTJA a nyitott szegmenst**, a záró szegmens a klip
> végéig tart, és a határ a döntő frame **ablakközepe**. A V2 assembler
> alapértelmezett viselkedése ezzel **paritásos** kell legyen. Olvasd újra
> `lib/features/analyze/engine/ml_chord_decoder.dart`-ot (250 sor) az
> `agreementFraction` szemantikájáért. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING — 2026-08-12 pre-flight revízió.**

1. A brief-lint `S5` leletét kódból ellenőriztük: a már exportált
   `lib/features/audio_analysis/domain/analysis_segment.dart:24` deklarálja a
   V2 `ChordSegment` típust, és `AnalysisTimeline.chordSegments` ezt a típust
   tárolja. Ezért a korábbi, új
   `domain/harmony/chord_segment.dart` és az ugyanilyen nevű új típus
   kollíziót/ambiguous exportot okozott volna. A kör a **meglévő
   `ChordSegment` additív bővítését** használja; a hibás új útvonal törölve,
   az engedélyezett lista a meglévő fájlra módosult. Nincs más scope-bővítés.
2. Az előre írt `0207` már nem foglalható: a kötelező
   `tools/round-slots.py reserve-adr --round E06-R11` parancs `0229`-et adott.
   Az ADR-hivatkozások és a fájlnév ezért **ADR 0229**-re változtak.
3. A küszöb-mátrix mért értékei:
   `python3 -c 'print(*(int(ms * 1000) for ms in (199, 200, 201)))'` →
   `199000 200000 201000` mikrosekundum. A 200 ms-es cella inkluzív.

Az implementernek `stopped` jelzést kell adnia, ha a meglévő
`ChordSegment` additív, forráskompatibilis bővítése nélkül nem teljesíthető a
kontraktus, vagy a megoldás a tiltott `lib/features/analyze/**` fájlok egyikét
igényelné.

## 1. Cél

A chord-idővonal mögötti **evidence** és **decoder-forrás** formalizálása:
frame-szintű top-k bizonyíték, verziózott szegmens-összeállítás, és a
DSP↔ML viszony **flag mögötti**, reprodukálható szabálya.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A chord-kimenet ma **csak végleges címke**: `TimelineChord{label, startSec,
  endSec}`. Nincs top-k, nincs no-chord valószínűség, nincs decoder-forrás.
- A szegmensépítés (`clip_analyzer.dart` 199–226): a Viterbi-útvonal
  frame-enkénti címkéiből; **`label == null` (no-chord) frame nem zárja le**
  a nyitott szegmenst („a timeline chord SPAN-eket mutat, és ez a batch előtti
  viselkedés, amire az UI épült"); az utolsó szegmens `duration`-ig tart.
- A gating: `nc.lastTonalness >= DspConfig.chordMinTonalness`, különben
  **nulla-chroma** kerül a dekóderbe (`clip_analyzer.dart` 167–171).
- A ML út **Lab-only**: `MlChordDecoder(chordNet).decode(...)` +
  `MlChordDecoder.agreementFraction(dsp, ml, duration)` → `MlChordDiagnostics`
  (`analyze_providers.dart` 60–77). A shipping timeline **mindig a DSP**.
- Meglévő őrök: `batch_chord_timeline_test.dart`, `clip_analyzer_ml_test.dart`,
  `ml_chord_wiring_test.dart`, `test/property/chord_timeline_property_test.dart`,
  `crnn_ab_property_test.dart`.

## 3. Scope

**Benne:** `ChordFrameEvidence` (frame idő, top címke, top confidence, top-k,
no-chord valószínűség, tonalness, decoder source); `ChordSegment` (V2, ID-vel,
confidence-szel, forrással); `ChordSegmentAssembler` (verziózott policy:
minimum szegmenshossz, tranziens-merge, no-chord/silence kezelés, pontos
záróhatár); `ChordLabelNormalizer` (kanonikus címke; az enharmonikus
**megjelenítés** UI-policy marad); `DecoderSource` enum; **ADR 0229**;
**egy** új flag: `analysisExperimentalFusionEnabled` (default OFF).

**Kívül — TILOS:** a DSP chord-lánc módosítása, `DspConfig`, a CRNN
súlyok/asset, a shipping decoder cseréje, `lib/features/analyze/**`,
`lib/features/live/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/harmony/chord_frame_evidence.dart` | ÚJ | frame-szintű evidence |
| `lib/features/audio_analysis/domain/analysis_segment.dart` | meglévő | A már exportált V2 `ChordSegment` additív evidence/provenance-bővítése |
| `.../engine/harmony/chord_segment_assembler.dart` | ÚJ | verziózott összeállítás |
| `.../engine/harmony/chord_label_normalizer.dart` | ÚJ | kanonikus címke |
| `.../engine/harmony/decoder_source.dart` | ÚJ | forrás + fusion policy |
| `.../data/legacy_view_adapter.dart` | meglévő | V2 → mai `TimelineChord` |
| `.../public.dart` | meglévő | export |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 1 flag, OFF |
| `test/**` | ÚJ | assembler/normalizer/property |
| `docs/adr/0229-…md` | ÚJ | fusion-stratégia |

**Tilos zóna:** `lib/features/live/**`, `lib/features/analyze/**`,
`assets/ml/**`, `docs/rag/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **ADR 0229 — a shipping default: DSP primary, ML advisory.** A ML-eredmény
   kizárólag **diagnosztika** (Lab), a publikus timeline a DSP-é. A fusion
   (`confidence-weighted` vagy `disagreement-aware abstention`) **kizárólag**
   `analysisExperimentalFusionEnabled` mögött. Az ADR rögzíti a **visszavonás
   feltételét**: a default csak az E06-R29 evaluation számszerű eredménye
   alapján változhat. **NEM elfogadható:** a fusion bekapcsolása
   „mert jobbnak tűnik", és **NEM elfogadható**, hogy a flag-off út
   viselkedése bármiben eltérjen a V1-től.
2. **Paritás a V1 szegmentálással:** az assembler **default** policyja
   (minimum szegmenshossz = 0, tranziens-merge = ki, no-chord = a nyitott
   szegmens fenntartása) bitre a V1 viselkedést adja.
   **NEM elfogadható:** a „jobb" alapértelmezés bevezetése — az új policy
   értékek flag/paraméter mögött élnek, és külön mérve vannak.
3. **A top-k evidence nem kerül automatikusan tartós tárolásba** (SDD §13.3):
   a `ChordFrameEvidence` a futás **köztes** adata; a dokumentumba csak
   aggregátum megy. A tárolási policy az R21 dolga.
   **NEM elfogadható:** több ezer frame top-k-ja a mentett dokumentumban.
4. **A decoder-forrás minden szegmensen látszik** (`dsp`/`ml`/`fused`), és a
   provenance hordozza a model manifest ID-t.
5. **A címke-normalizálás nem enharmonikus megjelenítés:** a normalizer a
   **kanonikus** belső címkét adja; a `C#` vs `Db` választás UI-policy.
   **NEM elfogadható:** a megjelenítési döntés beépítése az engine-be.
6. **Nincs kitalált confidence:** a szegmens confidence-e a frame-ek
   dokumentált aggregátuma (súlyozott átlag a frame-hosszal), és
   `confidenceSource = heuristic`. **NEM elfogadható:** konstans 1.0.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Honnan jön a frame-szintű evidence, ha a V1 csak a Viterbi-utat adja?
    blocking: true
    resolution_policy: use_default
    default: >-
      Az R09 stage a V1 belépőt hívja, ami CSAK a kész `TimelineChord` listát
      adja vissza. Ezért a V2 `ChordFrameEvidence` ebben a körben a KÉSZ
      szegmensekből SZÁRMAZTATOTT, csökkentett evidence (frame idő, címke,
      no-chord jelölés) — top-k és no-chord valószínűség NÉLKÜL, és ezt a
      típus `evidenceCompleteness = derived` mezője jelöli. A teljes top-k
      evidence a Lab ML-úton (R18/R29) és egy későbbi, mért körben szerezhető
      meg. NEM elfogadható a top-k "kitalálása" a végleges címkéből.
  - id: OD-02
    question: A minimum szegmenshossz alapértéke?
    blocking: true
    resolution_policy: use_default
    default: >-
      0 (kikapcsolva) a default policyban — a V1-paritás ezt követeli.
      A nem nulla érték a policy paramétere, és külön mátrixcella méri.
```

## 6. Acceptance criteria

- [ ] **V1-paritás mátrix — hat fixture:** C→G; C→G→Am→F (0.8 s-onként);
      ring-out átfedés; gyors váltás (< 0.3 s); csend-rés a közepén; végig
      no-chord. A default policy kimenete a V1 `TimelineChord` listával
      **darabszámra és határra** (|Δ| ≤ 1 µs) egyezik, címkéstül.
- [ ] **No-chord viselkedés:** a „csend-rés" fixture-ön a default policy
      **egyetlen** szegmenst tart nyitva (V1-paritás), a `minSegment > 0`
      **és** `closeOnNoChord = true` policyval viszont **két** szegmens
      keletkezik — a két cella külön méri, hogy a policy tényleg hat.
- [ ] **Minimum szegmenshossz küszöb hármas** (`minSegment = 200 ms`):
      **199000 µs**, **200000 µs**, **201000 µs** (199/200/201 ms) hosszú szegmens — a 200 ms
      **megmarad** (a határ inkluzív), a 199 ms **beolvad** a szomszédba.
      Az időpontokat `python3 -c`-vel számolva, mikroszekundumban.
- [ ] **Záróhatár pontossága:** minden fixture-ön az utolsó szegmens vége
      **pontosan** a klip hossza (|Δ| ≤ 1 µs), és nincs a klip végén túlnyúló
      szegmens (property-teszt).
- [ ] **Nem-átfedő, hézagmentes property:** `PROPERTY_SEED`-ből vezérelt
      véletlen frame-sorozatokra a szegmensek **monoton**, **nem átfedők**, és
      a lefedettség + a jelölt hézagok összege = a klip hossza.
- [ ] **Fusion flag-mátrix:** flag **OFF** → a timeline bitre a DSP-é
      (a paritás-mátrix ezt méri); flag **ON**, egyetértő DSP/ML → azonos
      kimenet; flag **ON**, ellentmondó DSP/ML → a szegmens `source == fused`
      és a confidence **csökken** (dokumentált szabály szerint), a címke a
      magasabb súlyúé. Három cella.
- [ ] **Címke-normalizálás mátrix:** `Cmaj`/`C`/`CM` → `C`; `Cmin`/`Cm` → `Cm`;
      `C#`/`Db` → a **kanonikus** alak (a normalizer szerződése szerint,
      dokumentáltan), és a normalizálás **idempotens**
      (`n(n(x)) == n(x)` property).
- [ ] **Evidence-teljesség jelölés:** minden ebben a körben előállított
      `ChordFrameEvidence` `evidenceCompleteness == derived`, és a top-k lista
      **üres** (nem kitalált) — teszt méri.
- [ ] **Flag-őr + V1 érintetlenség:** az új flag minden környezetben `false`;
      `git diff --stat` nem tartalmaz `lib/features/analyze/**` vagy
      `lib/features/live/**` útvonalat; `test/features/analyze` zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A no-chord frame lezárja a szegmenst a default policyban | a „csend-rés" V1-paritás cella |
| A policy egyáltalán nem hat | a `closeOnNoChord = true` **két szegmens** cellája |
| A minimum szegmenshossz exkluzív | a **pontosan 200 ms** megmarad-cella |
| Az utolsó szegmens a döntő frame közepéig tart, nem a klip végéig | a záróhatár-cella |
| A fusion a flag-off úton is fut | a flag OFF paritás-cellája |
| A top-k a végleges címkéből „kitalálva" | az `evidenceCompleteness == derived` + üres top-k cella |
| A szegmens confidence konstans 1.0 | a fusion ON/ellentmondó cella (nem csökken) |
| A normalizer enharmonikus megjelenítést dönt el | a kanonikus-alak cella + az idempotencia property |
| **Valódi-sértés próba (§10):** a záróhatár `duration`-ról a döntő frame közepére állítása → a záróhatár-cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. ADR 0229 (DSP primary, ML advisory, flag + visszavonási feltétel).
2. RED: V1-paritás mátrix a hat fixture-re.
3. `chord_frame_evidence.dart` + a meglévő `analysis_segment.dart` `ChordSegment`
   bővítése + `decoder_source.dart`.
4. `chord_label_normalizer.dart` (idempotens).
5. `chord_segment_assembler.dart` (verziózott policy, default = V1).
6. Fusion-ág flag mögött; `LegacyViewAdapter`; property; gate.

## 9. Kockázatok

- **A „derived evidence" korlátja** (OD-01) csökkenti az R18/R19 lehetőségeit;
  a §10-ben follow-upként rögzíteni kell, melyik későbbi kör szerzi meg a
  teljes top-k-t, és milyen áron.
- **A paritás és a „jobb" szegmentálás konfliktusa** — a brief a paritást
  teszi elsődlegessé; a jobb policy flag mögött él, és az R29 dönt.
- **A címke-normalizálás visszahathat a legacy adapterre** (R03) — a
  `LegacyViewAdapter` a **nyers** címkét adja vissza, nem a normalizáltat;
  ezt teszt méri.

**STOP:** a shipping decoder cseréje, DSP-konstans vagy a flag default
bekapcsolása helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r11-chord-evidence-segmentation-provenance-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
