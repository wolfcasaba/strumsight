# E99-R09 (GOV-30c-1) — A V2 elemzési lánc ELSŐ fele: munkaállapot + ingest-stage-ek

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-14, `main @ 91b4c37b`)
- **Típus:** **governance-kör** — az Epic 6 lezárása után a completion report
  4. nyitott tétele (GOV-30c), user-döntés 2026-08-14
- **Kör-azonosító:** `E99-R09`. Emberi neve **GOV-30c-1**.
- **Branch:** `codex/e99-r09-gov-30c-1-ingest-pipeline-composition`
- **Előfeltétel:** Epic 6 mind a 30 köre merge-elve (`E06-R30`, PR #257, `f257afa7`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0250`](../adr/0250-v2-analysis-work-state-and-ingest-stage-composition.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
- **Folytatás (NEM ez a kör):** GOV-30c-2 — metrikák, confidence/capability,
  insights/hotspots, dokumentum-összeállítás és a provider felülírása.
  **A briefje szándékosan még nincs megírva** (egy session = egy kör).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/analysis_work_state.dart",
  "lib/features/audio_analysis/engine/stages/ingest_stages.dart",
  "test/features/audio_analysis/engine/analysis_work_state_test.dart",
  "test/features/audio_analysis/engine/stages/ingest_stages_test.dart",
  "test/features/audio_analysis/engine/ingest_pipeline_composition_test.dart",
  "docs/rounds/e99-r09-gov-30c-1-ingest-pipeline-composition.md",
]
gate_tests = [
  "test/features/audio_analysis/engine/ingest_pipeline_composition_test.dart",
  "test/features/audio_analysis/engine/stages/ingest_stages_test.dart",
]
native_gate = false
```

## 0.0 Brief-revízió — 2026-08-14, független review F1/MAJOR

Az eredeti brief a hat felsorolt modul adapterét kérte, de az A4-cellája a
`AnalysisWorkState.seed(input: ...)` PCM-bemenetétől elvárt teljes timeline
alapot csak kívülről beadott `LegacyEvidence`-szel tudta volna elérni. Ez nem
a kör céljának megfelelő self-contained ingest-lánc. A `ClipAnalyzerStage`
azonban már létező, review-zott V1→`LegacyEvidence` adapter, és kizárólag az
engedélyezett új `engine/stages/ingest_stages.dart` fájlban kell vékonyan
becsomagolni.

Ezért a kötelező összetétel hét stage: preprocessing → signal quality → legacy
evidence → pitch → harmony → rhythm → events. A `legacy-evidence` hiba
fatális: nélküle a harmony/rhythm/events inputja nem állítható elő. A
`AnalysisWorkState.seed` nem fogadhat kész `LegacyEvidence`-t; az új adapter
a már előfeldolgozott audio-ból `LegacyClipAnalyzerInput`-ot épít és a meglévő
`ClipAnalyzerStage`-et hívja. A megengedett útvonalak nem változnak, meglévő
engine-fájl tartalma nem módosul, a provider továbbra is érintetlen.

Ennek megfelelően §2.3-ban a `legacy/` a hetedik wrapolandó modul, §3.2/A2
és §6.1 a hét adaptert és az önálló PCM→timeline A4-cellát méri, §5.3 a
`legacy-evidence` fatális besorolását, §8 pedig a hétlépéses sorrendet írja
elő. Ez a kör saját, még nem lezárt briefjének szűk pontosítása; ADR 0250
változatlan.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az Epic 6 mind a 30 köre lezárult, de **a V2 elemzés nem futtatható**:

```dart
// lib/features/audio_analysis/application/analysis_providers.dart:213-218
final analysisV2RunnerProvider = Provider<AnalysisRunner>((_) {
  throw StateError(
    'analysisV2RunnerProvider has no concrete V2 DSP stage list yet. '
    'A future pipeline-composition round must override it.',
  );
});
```

Minden építőelem megvan — **41 engine-fájl 12 modulban** —, de **nincs
összeszerelve lánccá**. Ez a kör a lánc **első felét** építi meg: a
munkaállapot-típust és az ingest-stage-eket a PCM-bemenettől a kész
`AnalysisTimeline`-ig.

**Ez a kör NEM kapcsol be semmit.** A provider a kör végén is `StateError`-t
dob, és mind a kilenc flag OFF marad — a bekötés a GOV-30c-2 dolga.

## 2. Jelenlegi állapot — mért tények

### 2.1 A szerződések, amiket használni KELL (nem újraírni)

`engine/analysis_stage.dart`:

```dart
abstract interface class AnalysisStage<I, O> {
  String get id;
  int get version;
  Future<AppResult<O>> run(I input, AnalysisStageContext context);
}
```

A `StageFailure.degradable(failure, unavailableCapabilities: …)` /
`StageFailure.fatal(failure)` páros és az `AnalysisStageFailureClassifier`
typedef **ADOTT** — a degradálási politika a kompozíció tulajdona, nem a
stage-é.

`engine/analysis_pipeline.dart:56`:

```dart
final class AnalysisPipeline<T> {
  AnalysisPipeline({ required List<AnalysisStage<T, T>> stages, … });
```

**A pipeline AZONOS ÁLLAPOTÚ stage-eket komponál** (`AnalysisStage<T, T>`).
A fájl saját kommentje ki is mondja: *„Future real DSP stages can use their
own work-state type while keeping the SDD's generic stage contract."*

### 2.2 A meglévő három stage TÍPUSAI NEM egyeznek

Mérve (`grep -rn "implements AnalysisStage" lib/features/audio_analysis/`):

| fájl | I → O |
|---|---|
| `engine/preprocessing/preprocessing_stage.dart:15` | `ValidatedPcmAnalysisInput → PreprocessedAudio` |
| `engine/quality/signal_quality_stage.dart:37` | `ValidatedPcmAnalysisInput → SignalQualityStageResult` |
| `engine/legacy/clip_analyzer_stage.dart:11` | `LegacyClipAnalyzerInput → LegacyEvidence` |

Egyik sem `AnalysisStage<T, T>` alakú, tehát **egyik sem tehető közvetlenül
az `AnalysisPipeline` stage-listájára.** Ez a kör központi feladata.

### 2.3 A wrapolandó modulok — MIND léteznek, mind tiszta függvény/osztály

| modul | belépési pont (mért) |
|---|---|
| `preprocessing/` | `PreprocessingStage` (már stage), `MonoDownmix`, `PreprocessingConfig` |
| `quality/` | `SignalQualityStage` (már stage) → `SignalQualityStageResult` |
| `pitch/` | `PitchFrameExtractor`, `MonophonicPitchSegmentBuilder`, `pitch_capability_gate.dart` |
| `harmony/` | `ChordSegmentAssembler` + `ChordSegmentationPolicy`, `decoder_source.dart`, `ChordLabelNormalizer` |
| `rhythm/` | `BeatGridEstimator` (+ `FreePlayBeatInference`), `TempoCurveBuilder` → `TempoCurve` |
| `events/` | `EventTimelineBuilder` → `EventTimelineBuildResult` (`SuppressedEvent`-tel) |

**Ezek a modulok végig-review-zottak és teszteltek** (E06-R05…R20). A kör
NEM ír DSP-matematikát — csak becsomagolja őket.

### 2.4 A cél-dokumentum, amit a MÁSODIK fél tölt majd ki

`domain/analysis_document.dart:58-71` — `signalQuality`, `capabilities`,
`timeline`, `metrics`, `hotspots`, `insights`, `warnings`, `completion`,
`provenance`. **Ebből ez a kör a `timeline`-ig és a `signalQuality`-ig jut
el**; a `metrics`/`capabilities`/`insights`/`hotspots` a GOV-30c-2.

## 3. Scope

**Benne van:**

1. `AnalysisWorkState` — immutable munkaállapot-típus, amely a lánc mentén
   halmozza az artefaktumokat (bemenet, előfeldolgozott audio, jelminőség,
   pitch-keretek/szegmensek, akkord-szegmensek, beat-rács/tempógörbe,
   eseménysáv, figyelmeztetések, elvesztett capability-k).
2. Vékony **stage-adapterek** a 2.3 modulokra, mind
   `AnalysisStage<AnalysisWorkState, AnalysisWorkState>` alakban.
3. Az ingest-lánc **kompozíciója** (`List<AnalysisStage<AnalysisWorkState,
   AnalysisWorkState>>`) + a hozzá tartozó `AnalysisStageFailureClassifier`.
4. Tesztek: állapot-invariánsok, adapterenkénti viselkedés, és egy
   végigfutó kompozíciós teszt.

**NINCS benne (tilos):**

- **Az `analysisV2RunnerProvider` felülírása vagy bármely flag mozgatása.**
  A provider a kör VÉGÉN IS `StateError`-t dob. Ez acceptance-cella (A7).
- DSP-matematika írása vagy meglévő modul algoritmusának módosítása
  (AGENTS.md §9). Az adapter hív, nem számol.
- Metrikák, confidence/capability-feloldás, insights, hotspots,
  dokumentum-összeállítás — GOV-30c-2.
- `public.dart` barrel. A tesztek ma is közvetlenül importálják az
  engine-fájlokat (mérve: 67 import a `test/` fában), tehát nincs rá szükség.
- Bármely `docs/adr/**` fájl (az ADR 0250 megírva), `tools/round-gate.sh`,
  `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `engine/analysis_work_state.dart` | **ÚJ** — a munkaállapot-típus |
| `engine/stages/ingest_stages.dart` | **ÚJ** — a stage-adapterek + a lánc kompozíciója és a failure-classifier |
| `test/…/engine/analysis_work_state_test.dart` | **ÚJ** — állapot-invariánsok |
| `test/…/engine/stages/ingest_stages_test.dart` | **ÚJ** — adapterenkénti viselkedés + degradálás |
| `test/…/engine/ingest_pipeline_composition_test.dart` | **ÚJ** — végigfutó lánc |
| `docs/rounds/e99-r09-…md` | a §10 handoff kitöltése |

**Tilos zóna:** `lib/features/audio_analysis/application/**` (különösen az
`analysis_providers.dart`) · `lib/features/audio_analysis/public.dart` ·
`lib/core/flags/**` · `docs/adr/**` · `tools/**` · `.github/**` · minden
meglévő `engine/**` fájl **tartalma** (olvasni kell őket, írni nem).

## 5. Kötött architekturális döntések (ADR 0250)

### 5.1 EGY munkaállapot-típus, nem stage-enkénti típusfüzér

`AnalysisWorkState` egyetlen immutable osztály; minden stage
`AnalysisStage<AnalysisWorkState, AnalysisWorkState>`. A bővítés `copyWith`-
szerű, nem mutáció.

**NEM elfogadható gyengítés:** az `AnalysisPipeline<T>` általánosításának
megkerülése azzal, hogy a stage-eket `dynamic`-ra vagy `Object`-re vesszük.
A típus-azonosság a pipeline szerződése; aki `dynamic`-kal kerüli meg, az a
fordítási idejű őrt kapcsolja ki.

### 5.2 Az adapter VÉKONY: hív, nem számol

Egy adapter dolga: kiolvasni a bemenetet a munkaállapotból, meghívni a
MEGLÉVŐ modult, az eredményt visszaírni. **Nulla DSP-matematika az adapterben**
(AGENTS.md §9). Ha egy modul hiányzó bemenet miatt nem hívható, az
degradálás vagy fatális hiba — nem helyben pótolt számítás.

**NEM elfogadható gyengítés:** „az adapterben egy kis normalizálás/interpoláció
kellett, hogy illeszkedjenek a típusok". Ha típus-illesztés kell, az önálló,
tesztelt konverziós függvény a munkaállapot fájljában — nem rejtett DSP.

### 5.3 A degradálási politika a KOMPOZÍCIÓÉ, nem a stage-é

A `AnalysisStageFailureClassifier` a kompozícióban dől el, stage-id alapján.
Kötött besorolás:

| stage | hiba esetén |
|---|---|
| preprocessing | **fatális** — nélküle semmi nem értelmezhető |
| signal quality | **fatális** — a jelminőség a dokumentum kötelező mezője |
| pitch | **degradálható** — a pitch-függő capability-k elvesznek |
| harmony | **degradálható** — az akkord-függő capability-k elvesznek |
| rhythm | **degradálható** — a tempó/beat-függő capability-k elvesznek |
| events | **fatális** — az eseménysáv a `timeline` alapja |

Az elvesztett capability-ket a `StageFailure.degradable(…,
unavailableCapabilities: {…})` halmazban KELL megadni, nem csak logolni.

**NEM elfogadható gyengítés:** minden stage degradálhatóvá tétele „a
robusztusság kedvéért". Az a fail-open: egy néma preprocessing-hiba után a
lánc üres, de sikeresnek látszó eredményt adna.

### 5.4 A meglévő két stage ÚJRAHASZNÁLANDÓ, nem újraírandó

A `PreprocessingStage` és a `SignalQualityStage` már `AnalysisStage`; az
adapterük **példányosítja és meghívja** őket, nem másolja a törzsüket.

### 5.5 A kör semmit nem kapcsol be

Az `analysisV2RunnerProvider` érintetlen marad, és a kör végén is
`StateError`-t dob. A lánc létezik, de még nincs bekötve — ez szándékos
kétlépcsős rollout.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `AnalysisWorkState` immutable; a bővítés nem mutálja a korábbi példányt | `analysis_work_state_test.dart` |
| A2 | Mind a hat adapter `AnalysisStage<AnalysisWorkState, AnalysisWorkState>` | fordítás + `ingest_stages_test.dart` |
| A3 | A preprocessing/quality adapter a MEGLÉVŐ stage-et hívja, nem másol logikát | `ingest_stages_test.dart` — a meglévő stage kicserélésével (injektált példány) a kimenet változik |
| A4 | A teljes ingest-lánc végigfut ép bemeneten, és `timeline`-alapot ad | `ingest_pipeline_composition_test.dart` |
| A5 | Degradálható stage hibája NEM állítja meg a láncot, de rögzíti az elvesztett capability-t | kompozíciós teszt, pitch/harmony/rhythm cellák |
| A6 | Fatális stage hibája MEGÁLLÍTJA a láncot, és nincs részleges eredmény | kompozíciós teszt, preprocessing/quality/events cellák |
| A7 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | `git diff` — az `application/**` érintetlen; a tilos zóna audit |
| A8 | Nulla DSP-matematika az adapterekben | scope-audit + review: az adapterek csak hívnak |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A munkaállapot mutálható (a stage helyben módosít) | A1 |
| Az adapter `dynamic`-ot használ a típus-azonosság megkerülésére | A2 (fordítási hiba) |
| Az adapter átmásolja a `PreprocessingStage` törzsét | A3 (az injektált csere nem hat) |
| Minden stage degradálhatóra állítva | A6 — a fatális cellák zölden „átmennének", pedig részleges eredmény születik |
| Egyik stage sem degradálható | A5 — egy pitch-hiba az egész futást megbuktatná |
| A degradálás csak logol, `unavailableCapabilities` üres | A5 (a halmaz assertje) |
| Az adapter helyben számol a hiányzó bemenet helyett | A8 + review |
| A kör „hasznosságból" felülírja a providert | A7 |

**A degradálás három kötelező cellája** (a határ a stage-osztályozás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| fatális alatt | preprocessing hibázik | a lánc MEGÁLL, nincs érték |
| a határon | events hibázik (utolsó fatális) | a lánc MEGÁLL, nincs `timeline` |
| fatális fölött | pitch hibázik | a lánc FUT tovább, a pitch-capability az `unavailableCapabilities`-ben |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a
preprocessing osztályozását ideiglenesen `degradable`-re → az A6 cellának
PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/engine/ingest_pipeline_composition_test.dart test/features/audio_analysis/engine/stages/ingest_stages_test.dart test/features/audio_analysis/engine/analysis_work_state_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. `AnalysisWorkState` + a hozzá tartozó teszt (immutabilitás, bővítés).
2. A két MEGLÉVŐ stage adaptere (preprocessing, quality) — a legkisebb kockázat.
3. Pitch, harmony, rhythm adapterek.
4. Events adapter → `timeline`-alap.
5. Kompozíció + failure-classifier az 5.3 táblázat szerint.
6. Kompozíciós teszt a §6.1 három degradálási cellájával.
7. Valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A munkaállapot elhízása.** Ha minden köztes artefaktum bekerül, a
  `copyWith` lánc kezelhetetlen lesz. Csak azt vedd fel, amit egy KÉSŐBBI
  stage vagy a dokumentum ténylegesen olvas — a többi maradjon a stage-en belül.
- **Isolate-átvihetőség.** A futtatás végül izolátumban megy
  (`AnalysisDocumentIsolateOperation` JSON-t vesz át). A munkaállapot NEM
  kell hogy sendable legyen ebben a körben, de **ne épüljön bele** olyan
  típus (pl. `Stream`, closure), ami később biztosan megakadályozná. Ha
  ilyenre kényszerülnél, az `stopped` és brief-revízió.
- **A GOV-30c-2 tervezhetősége.** Ha a munkaállapot alakja itt rosszul dől
  el, a második kör kényszeredett lesz. Ezért a §5.1 kötött: egy típus,
  immutable, bővítés `copyWith`-tel.
- **Az adapterek csábítása.** A típus-illesztés helyben, „csak egy sorban"
  DSP-vé fajulhat. A §5.2 és az A8 pont ezt méri.

## 10. Implementation handoff — a Codex tölti ki

**Új fájlok** (mind az engedélyezett listán):

- `lib/features/audio_analysis/engine/analysis_work_state.dart` — az
  `AnalysisWorkState` immutable munkaállapot (`copyWith` bővítés) +
  `AnalysisWorkState.seed(...)` a lánc kezdő állapotához.
- `lib/features/audio_analysis/engine/stages/ingest_stages.dart` — a hat
  adapter (`PreprocessingIngestStage`, `SignalQualityIngestStage`,
  `PitchIngestStage`, `HarmonyIngestStage`, `RhythmIngestStage`,
  `EventsIngestStage`), a kompozíció-owned `classifyIngestStageFailure`
  (`AnalysisStageFailureClassifier`) és a `buildIngestStages()` segédfüggvény.
- 3 új tesztfájl a gate-listán, plusz a `docs/rounds/…` jelen handoffja.

**Kulcs-döntés a `LegacyEvidence`-ről (nincs kifejezetten a brief §2.3
táblájában, de a harmony/rhythm/events modulok szerződése megköveteli):** a
`ChordSegmentAssembler` bemenete `ChordFrameEvidence`, az `EventTimelineBuilder`
bemenete pedig közvetlenül `LegacyEvidence` — és egyik típust sem termeli más,
e körben csomagolt modul (a `ClipAnalyzerStage`, ami `LegacyEvidence`-t termel,
NEM szerepel a 2.3 táblázat hat moduljában, és a brief kifejezetten hat
adaptert kér). Ezért az `AnalysisWorkState` egy opcionális `legacyEvidence`
mezőt kapott — ugyanolyan "bemenet" jellegű, mint a `ValidatedPcmAnalysisInput`
— amit a hívó ad át a lánc indításakor (`AnalysisWorkState.seed(...,
legacyEvidence: ...)`), nem ez a kör termeli. A `harmony` adapter a
`legacyEvidence.chords` listát a `ChordFrameEvidence.derived(...)` gyárral
alakítja `ChordFrameEvidence`-listává (a domain fájl saját kommentje szerint
pontosan erre való: *"R11 can only obtain it from finished V1 spans"*), a
`rhythm` adapter a `legacyEvidence.strums` időpontjait olvassa onset-időként,
az `events` adapter pedig közvetlenül átadja a `legacyEvidence`-t a meglévő
`EventTimelineBuilder`-nek. Mindhárom adapter egyetlen preconditionje "van-e
`legacyEvidence`" — hiánya a saját osztályozásuk szerinti hiba (harmony/rhythm
degradálható, events fatális). Ez a döntés a GOV-30c-2-t köti: az a kör fogja
eldönteni, HOGYAN jut `legacyEvidence` a lánc elejére (pl. a
`ClipAnalyzerStage` külön futtatásával a runner-ben).

**A `DecoderSource` mezőhöz** a legközelebbi meglévő érték a `DecoderSource.dsp`
lett (a `derived` V1-kiértékelés maga is DSP-alapú volt) — nincs `legacy`
enum-érték, és a domain fájl bővítése tiltott zóna.

**§6.1 valódi-sértés próba — elvégezve, dokumentálva:**

1. A `classifyIngestStageFailure` `preprocessing` ágát ideiglenesen
   `StageFailure.degradable(failure)`-re állítottam.
2. Első próbálkozásra az A6 teszt (a `calledStageIds` log-alapú assert)
   **nem** vált pirosra — a lánc a degradált preprocessing után a
   signal-quality/pitch/harmony/rhythm stage-eken is végigfutott, majd az
   `events` (ami szintén fatális és `legacyEvidence` nélkül hibázik ebben a
   tesztben) állította meg, ugyanazzal a végkimenettel
   (`completion=failed, value=null`) mint a helyes preprocessing-fatális eset
   — a teszt véletlenül átment egy hibás osztályozással is.
3. Ez saját magában egy mért bizonyíték arra, hogy a `calledStageIds` log
   önmagában nem elég szigorú mérce. A tesztet kicseréltem: a
   `provenance.stageTimings.map((t) => t.id)`-t vizsgálja, ami PONTOSAN
   felsorolja, mely stage-ek futottak le (siker VAGY hiba esetén is, a
   pipeline `finally`-ben rögzíti) — ez már ténylegesen csak
   `['preprocessing']`-t várhat el fatális osztályozásnál.
4. Az újrafuttatott A6 teszt a degradálva állított osztályozással **PIROS**
   lett (a lánc mind a hat stage-en végigfutott, a `stageTimings` 6 elemű
   listát adott vissza a várt 1 elemű helyett).
5. Visszaállítottam a `classifyIngestStageFailure`-t az eredeti (fatális)
   besorolásra, és a teljes `tools/round-gate.sh` újra teljes egészében
   ZÖLD.

**Gate-eredmény:** `tools/round-gate.sh` mindhárom kör-tesztfájlra +
`architecture` + `secrets` + `l10n` — **MINDEN GATE ZÖLD** (a preprocessing
valódi-sértés próba lezajlása és visszaállítása után futtatva).

**A7 — érintetlen provider:** `git status`/`git diff --stat` szerint
kizárólag a fenti öt új fájl jött létre; az
`application/analysis_providers.dart` és minden meglévő `engine/**` fájl
tartalma változatlan. Az `analysisV2RunnerProvider` a kör végén is
`StateError`-t dob.

## 11. Review — a Claude tölti ki
