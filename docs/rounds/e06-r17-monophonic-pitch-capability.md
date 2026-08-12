# E06-R17 — Monofonikus pitch capability

- **Státusz:** PLANNING (előre megírva 2026-08-07; pre-flight lezárva
  2026-08-12, `main` @ `2c08dc5b`, ADR 0235)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 17; §17.1–17.6
- **Branch:** `codex/e06-r17-monophonic-pitch-capability`
- **Előfeltétel:** **E06-R08, E06-R13 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/domain/pitch/pitch_frame.dart",
  "lib/features/audio_analysis/domain/pitch/monophonic_pitch_segment.dart",
  "lib/features/audio_analysis/engine/pitch/pitch_frame_extractor.dart",
  "lib/features/audio_analysis/engine/pitch/monophonic_pitch_segment_builder.dart",
  "lib/features/audio_analysis/engine/pitch/pitch_capability_gate.dart",
  "lib/features/audio_analysis/engine/metrics/pitch_metrics.dart",
  "lib/features/audio_analysis/domain/analysis_metric_catalog.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/engine/pitch_frame_extractor_test.dart",
  "test/features/audio_analysis/engine/pitch_metrics_test.dart",
  "test/features/audio_analysis/engine/pitch_capability_gate_test.dart",
  "test/property/analysis_pitch_property_test.dart",
  "docs/rounds/e06-r17-monophonic-pitch-capability.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
  "test/core",
  "test/features/tuner",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R08/R13 merge.
> Olvasd újra `lib/core/audio/dsp/yin_pitch_detector.dart`-ot (99 sor) és
> `lib/core/audio/dsp/sliding_framer.dart`-ot (26 sor), valamint a
> `lib/core/audio/pitch/pitch_observation*.dart` szerződését — ezek **közös
> core** primitívek, tehát az `audio_analysis` **importálhatja** őket
> cross-feature allowlist-bejegyzés nélkül. Ellenőrizd a Tuner tesztfájának
> tényleges útvonalát (`test/features/tuner` vagy máshol) — a `gate_tests`
> ehhez igazodik, és a **Tuner paritás** kötelező. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight mérés (2026-08-12, baseline `main` @ `2c08dc5b`; E06-R08 és
E06-R13 merge-elve — előfeltétel teljesül). ADR:
[0235](../adr/0235-monophonic-pitch-capability-boundary.md).**

Minden hivatkozott mezőt a tényleges hívási láncon mértem, nem a korábbi
brief állapot-táblájából:

1. A `lib/core/audio/dsp/yin_pitch_detector.dart` (99 sor),
   `lib/core/audio/dsp/sliding_framer.dart` (26 sor) és a
   `lib/core/audio/pitch/pitch_observation*.dart` (23/38/12 sor) mért
   sorszáma egyezik a brief §2 állapotával; az `analysisPitchEnabled` flag
   létezik, default `false` (`lib/app/config/feature_flags.dart`). A Tuner
   tesztfája ténylegesen `test/features/tuner` (4 fájl) — a `gate_tests`
   egyezik, a §0 pre-flight kérdése lezárva.
2. **Brief-lint S5 (mért ütközés):** a tervezett ÚJ
   `lib/features/audio_analysis/domain/pitch/pitch_segment.dart` a
   `PitchSegment` nevet vezetné be, de ez a típus **már létezik és
   exportált** (`lib/features/audio_analysis/domain/analysis_segment.dart:55`,
   E06-R02, PR #212 — `AnalysisTimeline.pitchSegments` üres, 0 producerű
   stub, `start`/`end`/`confidence`/`midiNote` mezőkkel, `public.dart:23`
   barrel-exportálva, `analysis_document_codec.dart` (de)szerializálja). A
   két típus **nem ugyanaz a fogalom** (ld. ADR 0235 Kontextus) — egy
   második, azonos nevű deklaráció ambiguous-export ütközést adna a
   `public.dart` barrelen. **Feloldás (ADR 0235 Döntés 1–3):** az új típus
   neve `MonophonicPitchSegment` (fájl: `monophonic_pitch_segment.dart`), a
   szegmentáló neve `MonophonicPitchSegmentBuilder` (fájl:
   `monophonic_pitch_segment_builder.dart`) — mindkét csere a brief eredeti
   `allowed_paths` listáján belüli fájlnév-csere, nem bővítés. A meglévő
   `analysis_segment.dart`/`analysis_timeline.dart`/
   `analysis_document_codec.dart` fájlokat a kör NEM érinti (ADR 0113
   precedens: az `allowed_paths` bővítése egy már létező, listán kívüli
   fájlra tilos-zóna kérdés, H3). A §3/§4/§8 alábbi szövege és az
   `allowed_paths` blokk ennek megfelelően frissítve.
3. **Második pre-flight forduló (2026-08-12, az implementer első, 0 fájlt
   módosító `stopped` jelzése után) — két további mért ellentmondás, ADR
   0235 Döntés 5:**
   - A §6 „Flag-kapu" kritérium eredetileg egy „stage-lista" ellenőrzést írt
     elő, de **egyetlen Epic 6-os stage sincs ma konkrét
     `AnalysisPipeline`-példányba szerelve** (`grep -rn "AnalysisPipeline("
     lib/` → 0 találat az `engine/analysis_pipeline.dart`-on kívül, amely
     maga is csak egy generikus, `stages`-t paraméterként kapó futtató).
     **Feloldás:** a kritérium kapu-szintű — a §5/§6 alábbi szövege
     frissítve.
   - A „hét kötelező pitch metrika" névvel nem szerepelt a brief szövegében,
     csak a fejlécben hivatkozott SDD §17.3-ban. **Feloldás:** a hét név
     (note hit ratio, median cents error, p90 cents error, pitch stability,
     note transition timing, sustained note duration, unwanted pitch
     dropout ratio) a §3 Scope-ba átemelve — az implementer feladata marad
     a pontos `AnalysisMetricId`/egység/számítási szerződés hozzárendelése.

## 1. Cél

A már meglévő YIN-alapú pitch-detektálás **biztonságos, capability-gate mögötti**
bevezetése az elemzésbe: pitch frame → szegmens → cent-hiba/stabilitás, kizárólag
**monofonikus** bemeneten — a Tuner **változatlan** viselkedése mellett.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Létezik közös YIN:** `lib/core/audio/dsp/yin_pitch_detector.dart` (99 sor)
  és `lib/core/audio/dsp/sliding_framer.dart` (26 sor), plusz a
  `lib/core/audio/pitch/` alatt `pitch_observation.dart` (23),
  `pitch_observation_config.dart` (38), `pitch_observation_gateway.dart` (12).
- A Tuner ezekre épül (`lib/features/tuner/engine/`), és az Epic 3
  pitch-observation útja (`practice`/`song_trainer`) szintén.
- **Az Analyze úton nincs pitch:** a `ClipAnalyzer` kizárólag chroma/chord és
  onset/strum passzt futtat; hangmagasság-fogalom nincs az `AnalyzeResult`-ban.
- Az `analysisPitchEnabled` flag az R02-ből létezik, default OFF.
- Az R13 adja az illesztőt (a note-target illesztéshez), az R08 az
  `originalSamples`-t és a mapping-et.

## 3. Scope

**Benne:** `PitchFrame` (idő, Hz, voiced confidence); `MonophonicPitchSegment`
(range, median Hz/MIDI, cents offset, stability cents, confidence — ld. ADR
0235 a névválasztásról és a meglévő, bekötetlen `PitchSegment` stubtól való
elhatárolásról); `PitchFrameExtractor` (a **meglévő** `YinPitchDetector` +
`SlidingFramer` felhasználásával); `MonophonicPitchSegmentBuilder`
(voiced/unvoiced szegmentálás, minimum hossz); `PitchCapabilityGate`
(**elsőként** `analysisPitchEnabled`; utána monofonikus target, elegendő
voiced frame, polifónia-bizonytalanság, zajkapu — ld. §6 Flag-kapu és ADR
0235 Döntés 5); a hét kötelező pitch metrika (SDD §17.3, szó szerint: note
hit ratio, median cents error, p90 cents error, pitch stability, note
transition timing, sustained note duration, unwanted pitch dropout ratio —
a pontos `AnalysisMetricId`/egység/számítási szerződés az implementer
feladata); katalógus + ARB.

**Kívül — TILOS:** a `YinPitchDetector` **algoritmusának** módosítása, a Tuner
bármely fájlja, bend/vibrato elemzés (későbbi flag), polifonikus transzkripció,
UI.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/pitch/pitch_frame.dart` | ÚJ | frame típus |
| `.../domain/pitch/monophonic_pitch_segment.dart` | ÚJ | szegmens típus (ADR 0235: nem `pitch_segment.dart`/`PitchSegment` — az a név foglalt) |
| `.../engine/pitch/pitch_frame_extractor.dart` | ÚJ | YIN-adapter |
| `.../engine/pitch/monophonic_pitch_segment_builder.dart` | ÚJ | szegmentálás |
| `.../engine/pitch/pitch_capability_gate.dart` | ÚJ | capability-kapu |
| `.../engine/metrics/pitch_metrics.dart` | ÚJ | a hét metrika |
| `.../domain/analysis_metric_catalog.dart` | meglévő | **additív** ID-k |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** kulcsok |
| `test/**` | ÚJ | fixture + gate + property |

**Tilos zóna:** `lib/core/audio/dsp/**`, `lib/core/audio/pitch/**`,
`lib/features/tuner/**`, `lib/features/analyze/**`, `lib/features/live/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A YIN közös core primitív — használni kell, nem másolni.** Az
   `audio_analysis` a `lib/core/audio/dsp/yin_pitch_detector.dart`-ot
   importálja. **NEM elfogadható:** a YIN átmásolása az `audio_analysis` alá
   (két igazságforrás), és **NEM elfogadható** a core detektor
   paramétereinek megváltoztatása.
2. **A Tuner nem regresszál:** a `test/features/tuner` (illetve a pre-flightban
   mért tényleges útvonal) **átírás nélkül** zöld, és a `git diff --stat` nem
   tartalmaz `lib/features/tuner/**` vagy `lib/core/audio/**` útvonalat.
3. **Capability gate ELŐBB, metrika UTÁNA:** ha a kapu nem enged, a metrikák
   **nem számolódnak ki** (nem csak nem publikálódnak) — ezt hívásszámláló
   méri. **NEM elfogadható:** kiszámolni és eldobni (fölösleges költség, és
   csábítás a későbbi „azért kiírjuk"-ra).
4. **Polifonikus bemenetre nincs hamis note score** (SDD §17.6): akkord-
   fixture-ön a `monophonicPitch` capability `unavailable`
   `polyphonicInput` okkal, miközben a chord- és ritmus-elemzés **fut**.
   **NEM elfogadható:** a legerősebb részhang „dallamként" publikálása.
5. **Az intonáció nem diagnózis** (SDD §17.4): az `intonation` metrika
   kizárólag a targethez viszonyított cent-eltérést közli.
   **NEM elfogadható:** „a gitárod hangolása rossz" jellegű üzenetkulcs.
6. **A pitch a `analysisPitchEnabled` flag mögött** fut. Mivel ma egyetlen
   Epic 6-os stage sincs konkrét `AnalysisPipeline`-példányba szerelve (0
   hívás, `grep -rn "AnalysisPipeline(" lib/`), a bizonyíték szintje a
   **kapu**: a `PitchCapabilityGate` az OD-01 (a)–(d) feltételei ELŐTT
   vizsgálja a flaget — hamis érték esetén azonnal `notApplicable`-lel tér
   vissza, és a pitch-metrikák számítója egyszer sem hívódik (ADR 0235
   Döntés 5). A pipeline-szintű „a stage nincs a futó kompozícióban" állítás
   egy jövőbeli bekötő kör dolga.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mikor "monofonikus" a bemenet?
    blocking: true
    resolution_policy: use_default
    default: >-
      A V1 NEM végez polifónia-detektálást. A kapu bemenete: (a) van-e
      monofonikus TARGET (scale/riff) — ha nincs, `notApplicable`;
      (b) voiced frame arány >= 0.35; (c) a YIN voiced confidence mediánja
      >= 0.6; (d) a frame-enkénti pitch szórása a szegmensen belül
      <= 100 cent. Ha (b)–(d) bármelyike bukik → `unavailable`
      (`polyphonicInput` vagy `confidenceTooLow`). Az értékek néven
      nevezettek és ideiglenesek az R29-ig.
  - id: OD-02
    question: Milyen framer-paraméterek?
    blocking: true
    resolution_policy: use_default
    default: >-
      a `pitch_observation_config.dart` MAI értékei, ha alkalmazhatók;
      ha nem, akkor 2048 mintás ablak / 512 hop, néven nevezett konstanssal
      és a §10-ben rögzített indoklással.
  - id: OD-03
    question: Minimum szegmenshossz?
    blocking: false
    resolution_policy: use_default
    default: "80 ms — rövidebb voiced sáv nem lesz szegmens (glitch-szűrés)."
```

## 6. Acceptance criteria

- [ ] **Frekvencia-mátrix — hét cella:** A4 = 440 Hz; a hat üres gitárhúr
      (E2 82.41, A2 110.00, D3 146.83, G3 196.00, B3 246.94, E4 329.63 Hz).
      Mindegyikre a `medianHz` **±2 cent** pontossággal, és a `medianMidi`
      **pontosan** a várt MIDI-szám. A cent-eltérést
      `python3 -c "print(1200*math.log2(a/b))"` alapján kell ellenőrizni.
- [ ] **Cent-offset küszöb hármas** (`intonation` küszöb = ±10 cent):
      egy 440 Hz-hez képest **+9.99**, **+10.00**, **+10.01** cent-re hangolt
      szinusz — a **+10.00** még „a tűrésen belül" (inkluzív), a +10.01 nem.
      A frekvenciákat `python3 -c "print(440*2**(c/1200))"` alapján:
      **440.0000 × 2^(9.99/1200)**, **× 2^(10/1200)**, **× 2^(10.01/1200)**.
- [ ] **Voiced-arány küszöb hármas** (0.35): olyan fixture-ök, ahol a voiced
      frame arány **0.349 / 0.350 / 0.351** — a **0.350** átmegy (inkluzív).
      A frame-számokat `python3 -c`-vel kell megkonstruálni (pl. 200 frame-ből
      **69.8 → 70 / 70 / 71** voiced; a pontos konstrukciót a teszt
      dokumentálja).
- [ ] **Polifónia-kapu:** négyhangos akkord-fixture → `monophonicPitch`
      **`unavailable`** `polyphonicInput` okkal, **és** a pitch-metrikák
      számítója **egyszer sem hívódott** (hívásszámláló `== 0`), **és** a
      chord/ritmus metrikák ettől függetlenül előállnak.
- [ ] **Csend és zaj:** tiszta csend → `unavailable` (`insufficientEvents`
      vagy `confidenceTooLow`, dokumentáltan melyik); fehér zaj → szintén
      `unavailable`, **nem** véletlen hangmagasság.
- [ ] **Vibrato-szerű moduláció:** ±30 cent, 5 Hz-es moduláció → **egy**
      szegmens (nem 10), `stabilityCents ≈ 30` (±5 cent tűrés), és **nincs**
      bend/vibrato **állítás** (a metrika neve stabilitás).
- [ ] **Hangváltás:** A4 → C5 átmenet → **két** szegmens, a határ a tényleges
      váltástól **±40 ms**-on belül.
- [ ] **Tuner-paritás:** a Tuner tesztfája **átírás nélkül** zöld, és a
      `git diff --stat` nem tartalmaz `lib/core/audio/**` vagy
      `lib/features/tuner/**` útvonalat.
- [ ] **Flag-kapu (kapu-szintű bizonyíték — ADR 0235 Döntés 5):**
      `analysisPitchEnabled = false` mellett hívva a `PitchCapabilityGate`
      **elsőként**, minden OD-01 (a)–(d) feltétel kiértékelése ELŐTT a
      flaget vizsgálja: `CapabilityStatus.notApplicable`-lel tér vissza
      (nincs `reason` — a `notApplicable` nem igényel
      `CapabilityUnavailableReason`-t), **és** a pitch-metrikák számítója
      **egyszer sem hívódott** (hívásszámláló `== 0`, ugyanaz a mérce, mint
      a polifónia-cellánál).
- [ ] **NaN-mentesség property:** véletlen bemenetekre minden Hz véges és
      `(0, 5000]`-ben, minden cents érték véges, minden confidence `[0,1]`-ben.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A YIN átmásolva az `audio_analysis` alá | a `git diff --stat` + a Tuner-paritás cella (két igazságforrás elcsúszik) |
| A core YIN paraméterei módosulnak | a Tuner tesztfája **PIROS** |
| Az intonáció-tűrés exkluzív | a **pontosan +10.00 cent** cella |
| A voiced-arány kapu exkluzív | a **pontosan 0.350** átmegy-cella |
| A kapu után is kiszámolja a metrikákat | a polifónia-cella hívásszámláló `== 0` elvárása |
| Polifonikus bemenetre a legerősebb részhangot publikálja | a négyhangos akkord `unavailable` cellája |
| A vibrato 10 szegmensre esik szét | a vibrato **egy szegmens** cellája |
| Csendre véletlen hangmagasságot ad | a csend/zaj `unavailable` cellák |
| A flag OFF mellett is fut | a Flag-kapu cella hívásszámláló `== 0` elvárása |
| **Valódi-sértés próba (§10):** a polifónia-kapu ideiglenes kiszedése → a négyhangos akkord `unavailable` cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/core test/features/tuner
```

Külön processzek, nincs `&&`/pipe/`tail`. (A negyedik útvonal a pre-flightban
mért tényleges Tuner-tesztfa.)

## 8. Implementációs sorrend

1. RED: frekvencia-, cent-, voiced-arány- és kapu-mátrix
   (a fixture-frekvenciák `python3 -c`-vel levezetve).
2. `pitch_frame.dart` + `monophonic_pitch_segment.dart`.
3. `pitch_frame_extractor.dart` (a **meglévő** YIN + framer felhasználásával).
4. `monophonic_pitch_segment_builder.dart` (voiced szegmentálás, minimum hossz).
5. `pitch_capability_gate.dart` (hívásszámlálóval tesztelhető seam;
   `analysisPitchEnabled` az ELSŐ vizsgált feltétel, az OD-01 (a)–(d) előtt).
6. `pitch_metrics.dart` + katalógus + ARB; property; gate.

## 9. Kockázatok

- **A polifónia-detektálás hiánya** (OD-01) proxykkal helyettesített — a
  §10-ben follow-upként rögzítendő, és az eval-mátrix PENDING sort kap.
- **A YIN költsége hosszú klipen** — a §10-ben a mért futásidőt (30 s-os
  klipre) rögzíteni kell; ha > 3 s, a hop növelése **follow-up**, nem
  ebben a körben végzett hangolás.
- **A Tuner és az elemzés eltérő framer-paramétere** zavaró lehet — az OD-02
  elsődlegesen a **meglévő** konfigurációt írja elő.

**STOP:** a core YIN módosítása, a Tuner érintése vagy a kapu megkerülése
helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r17-monophonic-pitch-capability-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
