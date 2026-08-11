# E06-R07 — Signal quality stage

- **Státusz:** PLANNING (pre-flight felülvizsgálva 2026-08-11, main @ `10e2d495`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 7; §11.2–11.6
- **Branch:** `codex/e06-r07-signal-quality-stage`
- **Előfeltétel:** **E06-R04, E06-R05 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/quality/signal_quality_stage.dart",
  "lib/features/audio_analysis/engine/quality/signal_quality_math.dart",
  "lib/features/audio_analysis/engine/quality/quality_thresholds.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/engine/signal_quality_stage_test.dart",
  "test/features/audio_analysis/engine/signal_quality_math_test.dart",
  "test/property/analysis_signal_quality_property_test.dart",
  "docs/rag/chunks/019-signal-quality-metrics.md",
  "docs/adr/0223-signal-quality-stage-metric-and-provenance-policy.md",
  "docs/rounds/e06-r07-signal-quality-stage.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R04/R05 merge. Olvasd
> újra az R02 `SignalQualityReport` **típusát** (mezőnevek, mértékegységek) és
> az R04 stage-szerződését; ha az R02 típusa eltér az itt feltételezettől, a
> mezőnevek a **típushoz** igazodnak, nem fordítva. Ellenőrizd, hogy a
> `docs/rag/chunks/` következő szabad sorszáma tényleg **019** (a batch idején
> a legmagasabb `018-strum-ml-pipeline.md`); ha nem, told el.
> PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**R1 — friss mérés, `main` @ `10e2d495` (2026-08-11).** A brief eredeti
baseline-ja `a6e6f3d` volt; E06-R05 és E06-R06 azóta merge-elt. A R02
`SignalQualityReport` tényleges, zárt publikus contractja
(`domain/signal_quality_report.dart:4-42`) kizárólag `overall`, `peakDbfs`,
`rmsDbfs`, `noiseFloorDbfs`, `clippedSampleRatio`, `silentRatio`,
`tonalness`, `measured` és `warnings` mezőket ad. Nincs `activeRegionRatio`,
`spectralFlatness`, külön `degraded` mező vagy szabad provenance-bag; ezért
ez a kör nem bővíti a domain típust. Az aktív-régió arány csak belső,
warning-döntési primitív; a rövid klip `tonalness`/noise-floor korlátját egy
stabil `AnalysisWarningKind.inputQuality` warning jelöli. A
`QualityThresholds.version` a stage `version` értékével egyezik, így az R04
pipeline `AnalysisPipelineProvenance.stageVersions` mechanikusan rögzíti az
eredményt anélkül, hogy új provenance-mezőt vezetnénk be.

**R2 — R04 security MINOR-1.** Az `AnalysisStageContext.publishResult`
(`engine/analysis_context.dart:89-90`) stage-választotta terminális eseményt
injektálhat; ez nincs ebben a körben engedélyezve. A `SignalQualityStage`
soha nem hívhatja ezt a metódust, csak legfeljebb egyszer a saját
`context.reportProgress()` metódusát. A pipeline marad a terminális állapot
egyedüli szerzője. A context/pipeline hardening továbbra is a megfelelő
későbbi kör scope-ja.

**R3 — dokumentációs scope.** A `docs/rag/chunks/` következő szabad száma
valóban `019`. A korábbi §9 által kért
`docs/manual-testing/analysis-eval-matrix.md` PENDING-sor a listán kívüli
fájl lenne; a mérési eredményt az RAG-chunk ideiglenes, E06-R29-ig nem
kalibrált státusza rögzíti, a manuális mátrix frissítése pedig E06-R29
feladata. Az engedélyezett lista nem bővül erre a fájlra.

**R4 — ADR.** A foglaló `tools/round-slots.py reserve-adr --round E06-R07`
futása `0223`-at adott. Az új
`0223-signal-quality-stage-metric-and-provenance-policy.md` rögzíti a
mértékegység-, threshold- és provenance-leképezést. **DSP-szabály:** ez a
kör **új** mérőszámokat vezet be (nem retunolja a shipping DSP-t), ezért az
AGENTS.md §9 szerint a paraméterek forrása a
**`docs/rag/chunks/019-signal-quality-metrics.md`**, ugyanabban a commitban.

## 1. Cél

Determinisztikus, verziózott **input-jelminőség riport**, amely a későbbi
metrikák capability-kapuját táplálja — és amely **soha nem minősíti a
játékot**, csak a felvételt.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- **Nincs semmilyen jelminőség-mérés** az Analyze úton: az `AnalyzeResult`-ban
  nincs peak, RMS, clipping, csend vagy zaj mező; a `ClipAnalyzer.analyze`
  üres PCM-re `AnalyzeResult.empty`-t ad, minden más bemenetet feltétel nélkül
  elemez (`clip_analyzer.dart` 65–78).
- Egyetlen közelítő fogalom a **tonalness**: a `NnlsChroma.lastTonalness`
  értéket a chord-pass a `DspConfig.chordMinTonalness` küszöbhöz hasonlítja
  (`clip_analyzer.dart` 167–168) — de ez **belső gating**, nem publikált riport.
- Az R06 felvétel közbeni `RecordingLevel` peak/RMS-t számol — a **közös
  primitívek** innen származnak, de a végleges riport **más költségszinten**
  fut (SDD Kör 7 §4).
- Az R02 adja a `SignalQualityReport` típusát, az R04 a stage-szerződést.

## 3. Scope

**Benne:** `SignalQualityMath` (tiszta függvények: peak dBFS, RMS dBFS,
clipped sample ratio, silent ratio, active region ratio, noise floor proxy,
spectral flatness / tonalness proxy); `QualityThresholds` (verziózott,
néven nevezett küszöbök); `SignalQualityStage` (R04 stage, warningokat és
`SignalQualityReport`-ot ad); RAG-chunk a formulákkal.

**Kívül — TILOS:** capability-feloldás (R19), a `DspConfig` bármely
konstansának módosítása, HPSS/chroma paraméter, `lib/features/live/**`,
`lib/features/analyze/**`.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/quality/signal_quality_math.dart` | ÚJ | tiszta formulák |
| `.../engine/quality/quality_thresholds.dart` | ÚJ | verziózott küszöbök |
| `.../engine/quality/signal_quality_stage.dart` | ÚJ | R04-stage implementáció |
| `.../public.dart` | meglévő | riport export |
| `test/features/audio_analysis/engine/*` | ÚJ | fixture + formula tesztek |
| `test/property/analysis_signal_quality_property_test.dart` | ÚJ | NaN/tartomány property |
| `docs/rag/chunks/019-signal-quality-metrics.md` | ÚJ | a formulák forrása (AGENTS.md §9) |

**Tilos zóna:** `lib/features/live/engine/dsp/**` (különösen `dsp_config.dart`),
`lib/features/analyze/**`, `assets/ml/**`. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A riport a FELVÉTELRŐL szól, nem a játékról** (SDD §2.2, §11.3): minden
   warning szövegkulcsa a felvételi körülményre mutat.
   **NEM elfogadható:** `quality.bad_playing` jellegű kulcs vagy olyan
   warning-név, ami a felhasználó teljesítményét minősíti.
2. **Determinizmus:** ugyanaz a PCM ugyanazt a riportot adja, bitre.
   **NEM elfogadható:** véletlenszerű mintavételezés vagy időfüggő ág.
3. **A grade nem rejti el a részmetrikákat** (SDD Kör 7 §3): az összesített
   `overall` mellett minden részérték **elérhető marad**.
   **NEM elfogadható:** csak a grade publikálása.
4. **Nincs hangforrás-állítás** (SDD §11.5): a zaj/háttérzene kizárólag
   **proxyként** jelenik meg (tonalness, spectral flatness, onset density).
   **NEM elfogadható:** „beszéd", „dob", „másik hangszer" címke külön modell
   nélkül.
5. **A küszöbök verziózottak és néven nevezettek**, a `QualityThresholds`
   verziója a provenance-be kerül. **NEM elfogadható:** magic number a
   formula helyén.
6. **A dBFS-konvenció rögzített:** teljes skálájú szinuszra a peak
   **0 dBFS**, a csendre `−infinity` helyett a dokumentált
   `silenceFloorDbfs = −120.0` padlóérték. **NEM elfogadható:** `-Infinity`
   vagy `NaN` a riportban.
7. **Új DSP-mennyiség ⇒ RAG-chunk ugyanabban a commitban** (AGENTS.md §9,
   CLAUDE.md HORIZON): a chunk tartalmazza a képletet, a küszöböket és a
   választás indokát.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A spectral flatness FFT-t igényel — melyik implementációt használja?
    blocking: true
    resolution_policy: use_default
    default: >-
      SAJÁT, a quality/ alatt élő, egyszerű Hann-ablakos magnitúdóspektrum —
      a `lib/features/live/engine/dsp/` importálása új cross-feature
      allowlist-bejegyzést igényelne, ami TILOS (az allowlist csak szűkülhet).
      A költség elfogadható: a stage a klipen egyszer fut, nem valós időben.
  - id: OD-02
    question: A noise floor proxy hogyan számoljon?
    blocking: true
    resolution_policy: use_default
    default: >-
      a keretenkénti RMS eloszlás 10. percentilise (dBFS-ben), dokumentált
      keretmérettel (2048 minta, 50 % átfedés) — determinisztikus és
      küszöb-független.
```

## 6. Acceptance criteria

- [ ] **Fixture-mátrix — nyolc cella:** (1) tiszta csend; (2) −40 dBFS szinusz;
      (3) teljes skálájú (0 dBFS) szinusz **clippeléssel**; (4) impulzusszerű
      clipping (rövid, ismétlődő); (5) fehér zaj; (6) tiszta akkord-fixture
      (`test/support/synth.dart` mintájára); (7) 200 ms-os (rövid) klip;
      (8) csend + egyetlen hangos szakasz (aktív-régió arány). Mindegyikre a
      **teljes** riport ellenőrzött, nem csak egy mező.
- [ ] **Clipping-küszöb hármas:** a `clippedSampleThreshold = 0.999`
      (abszolút mintaérték) mellett a mátrix cellái **0.9989 / 0.9990 /
      0.9991**… — pontosabban: a küszöb **inkluzív**, ezért a cellák
      `|x| = 0.99889`, `|x| = 0.999`, `|x| = 0.99911`; a középső **clippeltnek
      számít**. A `clippedSampleRatio` küszöbére
      (`clippedRatioWarning = 0.001`) külön hármas: **999 / 1000 / 1001**
      clippelt minta 1 000 000-ból (a `python3 -c`-vel számolt arányok
      `0.000999`, `0.001`, `0.001001`; a **0.001 warningot vált ki**).
- [ ] **Csend-küszöb hármas:** `silentSampleDbfs = −60.0` mellett
      **−60.01 / −60.0 / −59.99 dBFS** RMS-ű keretek — a **−60.0 csendnek
      számít** (inkluzív), és a `silentRatio` ennek megfelelően lép.
      A lineáris amplitúdókat `python3 -c "print(10**(-60.0/20))"` alapján
      kell előállítani, nem becsülni.
- [ ] **Determinizmus:** minden fixture kétszer futtatva **bitazonos** riportot
      ad (az összes `double` mező `==`-vel egyezik).
- [ ] **NaN-mentesség property:** `PROPERTY_SEED`-ből vezérelt véletlen
      PCM-ekre (köztük csupa 0, csupa ±1, extrém dinamikájú) a riport
      **egyetlen** mezője sem `NaN`/`±Infinity`, és minden arány `[0,1]`-ben,
      minden dBFS `[−120, +6]`-ban van.
- [ ] **Rövid klip:** a 200 ms-os fixture riportja **elkészül** (nem hiba), és
      a `tonalness`/noise-floor korlátját stabil `inputQuality` warning jelöli
      (a R02 contractban nincs mezőszintű `degraded` flag) — a rövid klip
      **nem** blokkolja a peak/RMS/clipping mérését.
- [ ] **Nincs játék-minősítés:** teszt méri, hogy egyetlen warning kulcsa sem
      illeszkedik a `(?i)(bad|poor|wrong|sloppy|rossz|gyenge)_?play` mintára.
- [ ] **A `DspConfig` bitre változatlan:** `git diff --stat` nem tartalmazza
      `lib/features/live/engine/dsp/dsp_config.dart`-ot, és a
      `test/features/analyze` + `test/property/dsp_property_test.dart` zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A clipping-küszöb exkluzív (`>` a `>=` helyett) | a `|x| = 0.999` **clippelt**-cella |
| A clipped-ratio warning exkluzív | a **pontosan 0.001** arány warning-cellája |
| A csend-küszöb exkluzív | a **pontosan −60.0 dBFS** csend-cella |
| A csendre `−Infinity` kerül a riportba | a NaN-mentesség property + a csend-fixture cella |
| A grade elnyeli a részmetrikákat | a fixture-mátrix „teljes riport ellenőrzött" cellái |
| A noise floor átlagot használ percentilis helyett | az (5) fehér zaj és a (8) csend+hangos cella eltérő elvárt értéke |
| A rövid klip hibát ad | a (7) 200 ms-os cella |
| A warning kulcsa játékot minősít | a kulcs-minta teszt |
| A stage a `DspConfig`-ot módosítja | `git diff --stat` cella + a V1 DSP property-teszt |
| **Valódi-sértés próba (§10):** a `silenceFloorDbfs` padló ideiglenes kiszedése (hagyjuk `−Infinity`-t) → a NaN-mentesség property **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `docs/rag/chunks/019-signal-quality-metrics.md` (formulák + küszöbök + indok).
2. `quality_thresholds.dart` a chunkból, verzióval.
3. RED: fixture-, küszöb- és determinizmus-mátrix.
4. `signal_quality_math.dart` (tiszta függvények).
5. `signal_quality_stage.dart` (R04-stage, warningok).
6. Property-teszt; gate.

## 9. Kockázatok

- **A spectral flatness saját FFT-t igényel** → a §5.1 OD-01 feloldása
  tudatosan duplikál egy kis primitívet a cross-feature allowlist tágítása
  helyett; a §10-ben a mért futásidőt rögzíteni kell (30 s-os klipre).
- **A küszöbök most még nem valós felvételen kalibráltak** — a chunk
  kimondja, hogy az értékek **ideiglenesek** az E06-R29 evaluation-jéig; a
  `docs/manual-testing/analysis-eval-matrix.md` PENDING-sora az E06-R29
  scope-ja (R3), nem ennek a körnek a listán kívüli módosítása.
- **A tonalness fogalmi ütközése** a `NnlsChroma.lastTonalness`-szel: a kettő
  **külön** mennyiség, külön néven; a chunk explicit kimondja a különbséget.

**STOP:** ha a formula csak a `DspConfig` valamely konstansának
megváltoztatásával adna elfogadható eredményt, az **megállás és jelentés** —
DSP-retune ebben a körben tilos.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r07-signal-quality-stage-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
