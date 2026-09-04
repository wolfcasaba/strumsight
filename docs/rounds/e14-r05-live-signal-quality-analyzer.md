# E14-R05 — Live signal quality analyzer

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 7b5315b`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 5
- **Kör-azonosító:** `E14-R05`
- **Branch:** `<motor>/e14-r05-live-signal-quality-analyzer`
- **Előfeltétel:** `E14-R04` merge-elve — a `SignalQualitySnapshot` szerződése
  ott születik, ez a kör TÖLTI MEG.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0507` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**
  (A queue `0357`-et előlegezett; a `tools/round-slots.py reserve-adr` **`0507`**-et foglalta — lásd §0.0 R1.)

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az
> `lib/features/audio_analysis/engine/quality/signal_quality_math.dart`
> TÉNYLEGES publikus felületét (a §2 felsorolása onnan való) és az
> [ADR 0224](../adr/0224-signal-quality-stage-measurement-boundary.md) §3-at
> („a már merge-elt `SignalQualityReport` … nem változik"), valamint a
> `docs/rag/chunks/019-signal-quality-metrics.md` küszöbeit. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/live/engine/quality/live_signal_quality_analyzer.dart",
  "lib/features/live/engine/quality/live_quality_thresholds.dart",
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/public.dart",
  "test/features/live/live_signal_quality_analyzer_test.dart",
  "test/features/live/live_signal_quality_hysteresis_test.dart",
  "docs/rag/chunks/live-signal-quality.md",
  "docs/rounds/e14-r05-live-signal-quality-analyzer.md",
]
gate_tests = [
  "test/features/live/live_signal_quality_analyzer_test.dart",
  "test/features/live/live_signal_quality_hysteresis_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-09-04)

A pre-flight MÉRÉSEI a `main @ f963af1f` fán és az izolált
`/home/ubuntu/ss-sonnet-impl-e14-r05` munkapéldányban készültek.

**R1 — ADR-szám: `0357` → `0507`.** A queue ADR-oszlopa a brief megírása
(2026-08-20) óta elavult; a foglaló (`tools/round-slots.py reserve-adr --round
E14-R05`) **`0507`**-et adta. A kör ADR-je:
`docs/adr/0507-live-signal-quality-analyzer-reuse-route-and-hysteresis.md`.

**R2 — S12 (brief-lint): a §7 gate-parancs a `gate_tests` listát tükrözi.** A
korábbi `tools/round-gate.sh test/features/live` a két kötelező tesztfájlt csak
könyvtár-szinten fedte. A §7 parancs mostantól tételesen felsorolja mindkettőt,
és megtartja a könyvtárat is (az acceptance 7. pontjának regressziós mércéje).

**R3 — Mért sorszámok frissítve.** A §2 `live_pipeline.dart:231/242` hivatkozása
elavult volt; a mért helyek ma `:277` (`final level = (_strums.lastRms * 8)…`)
és `:288` (`inputLevel: level`).

**R4 — MÉRT BLOKKOLÓ: a §5.1 újrahasznosítási szabály az `allowed_paths`-on
belül NEM végrehajtható.** Ez a kör pre-flight-`H3` haltjának oka.

A `tool/check_architecture.dart` `crossFeatureImportsMustUsePublicApi` szabálya
(`:366-392`) szerint cross-feature import CSAK a cél-feature `public.dart`
barreljét célozhatja; a szabályt a `tools/round-gate.sh:232` `architecture`
lépése futtatja. A `lib/features/audio_analysis/public.dart` exportálja a
`quality_thresholds.dart` (`:100`) és a `signal_quality_stage.dart` (`:101`)
fájlt, a **`signal_quality_math.dart`-ot azonban NEM**.

Mindkét út reprodukálva (`dart run tool/check_architecture.dart`, illetve
`flutter analyze` a munkapéldányban):

| Út | Mért eredmény |
|---|---|
| mély import `…/engine/quality/signal_quality_math.dart` | **architecture PIROS**, exit 1: `lib/features/live/engine/quality/live_signal_quality_analyzer.dart -> lib/features/audio_analysis/engine/quality/signal_quality_math.dart [cross-feature imports must target public.dart]` |
| `…/audio_analysis/public.dart` barrel-import | architecture ZÖLD (`12 allowlisted deviation(s)`), de **analyze PIROS**: `error • Undefined name 'SignalQualityMath'` |

A harmadik, exportált útvonal (`SignalQualityStage`) nem helyettesíti a
primitíveket: `async`, `ValidatedPcmAnalysisInput` + `AnalysisStageContext`
bemenetet vár, és minden hívásán feltétel nélkül lefuttatja a `tonalness`
FFT-jét és a `noiseFloorDbfs`-t
(`signal_quality_stage.dart:59-110`) — a Live forró úton blokkonként hívva
pontosan a §6.1 mátrix 6. sorának hibás implementációja.

**A feloldás két sor**, de MINDKETTŐ az orchestrátor hatáskörén kívül esik
(ADR 0087 §2: a lista SZŰKÍTÉSE a saját hatásköröm, a TÁGÍTÁSA nem):

1. `lib/features/audio_analysis/public.dart:100` mellé:
   `export 'engine/quality/signal_quality_math.dart';`
2. ennek a briefnek az `allowed_paths` blokkjába:
   `"lib/features/audio_analysis/public.dart",`

Az `architectureAllowlist` bővítése NEM alternatíva: a lista a saját szabálya
szerint (`tool/check_architecture.dart:8-10`) csak szűkülhet, és a `tool/` a
gate infrastruktúrája (ADR 0087 §4). A `signal_quality_math.dart` tartalma
mindkét feloldásban **bájtra változatlan** marad (ADR 0224 §3, acceptance 6.).

**R5 — Visszakeresés (ADR 0312).** `lessons,halts,adr` szűkítve: ADR 0224 §2–§3
(a merge-elt `SignalQualityReport` nem változik), ADR 0234, ADR 0216;
`lessons,halts` szűkítve: L104 (a lassú boxon a teszteket KIS csomagokban kell
futtatni — az implementer-promptba kötelező), L144, L449. Teljes korpuszon a
döntő találat a `test/core/architecture_dependency_test.dart:501` blokk: egy
korábbi kör ugyanezen a hibaosztályon akadt el („the first cross-feature
consumer … was flagged and the round could not build in scope", ADR 0176) — ez
a mostani R4 mért megismétlődése.

**R6 — AZ R4 BLOKKOLÓ FELOLDVA (ADR 0112 önjavító kör, 2026-09-04).** A
`SignalQualityMath` bekerült az `audio_analysis` **nyilvános szerződésébe**:
`export 'engine/quality/signal_quality_math.dart';`
(`lib/features/audio_analysis/public.dart:101`) — PR
[#571](https://github.com/wolfcasaba/strumsight/pull/571), squash `62e0dce6`,
mérés: `docs/LESSONS.md` L629, őr: `test/core/architecture_dependency_test.dart`
(„audio analysis quality primitives stay barrel-reachable (E14-R05)").

Ami ebből következik erre a körre:

1. **Az `allowed_paths` VÁLTOZATLAN.** Az R4-ben javasolt második sor
   (`"lib/features/audio_analysis/public.dart"`) **NEM kell** és **tilos** is:
   az export a kör indulása ELŐTT landolt a `main`-en, tehát a kör diffjének
   nem szabad tartalmaznia az `audio_analysis` fát. A `signal_quality_math.dart`
   így is **bájtra változatlan** marad (ADR 0224 §3, acceptance 6.).
2. **A használandó import:**
   `import 'package:strumsight/features/audio_analysis/public.dart';` — a mély
   import továbbra is architecture-PIROS.
3. **A munkapéldány legyen friss `origin/main`-ről származtatva** (ez az ág már
   tartalmazza a merge-et) — a régi barrelen a §5.1 továbbra sem fordulna.
   Ellenőrzés egy paranccsal:
   `grep -n signal_quality_math lib/features/audio_analysis/public.dart`.

**R7 — MÉRVE: a snapshot közzététele a pipeline SAJÁT getterén megy, NEM a
`LiveFrame`-en.** A §3/5. pont („a pipeline megtölti a snapshotot") a mért fán
kétértelmű, és a naiv olvasata `H3`-at okozna:

| Mérés (`main @ 62e0dce6`, munkapéldány) | Eredmény |
|---|---|
| `grep -n "final " lib/features/live/model/live_frame.dart` | a `LiveFrame`-nek **nincs** `signalQuality` mezője (12 mező: `current`, `next`, `latestStrum`, `bar`, `bpm`, `inputLevel`, `tuningHz`, `listening`, `strumSeq`, `latestStrumTime`, `engineTimeSec`) |
| `grep -rn "SignalQualitySnapshot" lib/features/live --include=*.dart` | csak a `domain/recognition/**` szerződés-fájlokban (`recognition_frame.dart:21/44`) — a `live_pipeline.dart` **nincs** a `RecognitionFrame`-re átkötve (E14-R04 kimondottan nem kötötte át) |
| `lib/features/live/model/live_frame.dart` | **TILOS zóna** (nincs az `allowed_paths`-on) |

Ebből következik, kötelezően:

1. A `LivePipeline` **új, csak olvasható gettert** publikál a legutóbb mért
   pillanatképre — a fában MÁR MEGLÉVŐ minta szerint
   (`RecognitionRuntimeInfo get runtimeInfo`,
   `lib/features/live/engine/dsp/live_pipeline.dart:302`). Javasolt alak:
   `SignalQualitySnapshot get signalQuality` (a `_buildFrame()` érintése nélkül).
2. A `LiveFrame` szerződése és az `inputLevel` **bájtra változatlan** (§5.5, D8).
   A `live_frame.dart` fájlhoz a kör NEM nyúl — ha az implementer szerint
   nyúlni KELLENE, az `stopped` jelzés, nem néma lista-tágítás.
3. A snapshot UI-ba/`RecognitionFrame`-be kötése **nem ez a kör**: az a
   `live_frame.dart`-ot vagy a V2-átkötést érintené, mindkettő a tilos zónában.
   Ez a kör az elemzőt és a pipeline-oldali mérést szállítja.
4. A `signalQuality` getter a puffer feltöltése előtt
   `SignalQualitySnapshot.unknown`-t ad (acceptance 3.), és a `reset()`
   (`:322`) is erre állítja vissza.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A Live út mondja meg, **miért nem megbízható** a mérés (túl halk, klippel, zajos,
beszéd, instabil) — ne csak egy szintmérőt mutasson (SDD Ch14 Kör 5).

Ez a kör **elemzőt ad, nem UI-t**: a `SignalQualitySnapshot` megtelik, a
képernyő ebben a körben változatlan.

**Kockázat = high, indoklás:** a kör a MIKROFONBÓL érkező nyers PCM-en dolgozik,
és metrikákat publikál róla. A határ, amit nem szabad átlépni, az ADR 0224 §1
szabálya („nyers audio nem kerül logba, hálózatra vagy perzisztens tárolóba") és
§4 (nem osztályoz hangforrást vagy személyt). A router
`high_risk_path_fragments` listája ezt az útvonalat névből nem fogja meg, ezért
az indoklás itt, explicit módon áll.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **[ADR 0224](../adr/0224-signal-quality-stage-measurement-boundary.md)** — a
  batch (Analyze) oldalon **már van** signal-quality stage, mért képletekkel és
  küszöbökkel; §4: a stage „csak felvételi feltételekre utaló, stabil
  `AnalysisWarning` kulcsokat ad. Hangforrást és játékminőséget nem osztályoz."
  Ugyanez a határ köti ezt a kört is.
- **ADR 0234** (dynamics evidence és kapuzási határ) — a minőségi jelzés
  kapuz, nem magyaráz.
- **ADR 0271 §1** — a rossz minőségű bemenetre `unknown` jár, nem magabiztos
  találgatás.

## 2. Jelenlegi állapot — mért tények

- **Live oldalon egyetlen minőségi jel van**, és az egy skálázott RMS:
  `final level = (_strums.lastRms * 8).clamp(0.0, 1.0).toDouble();`
  (`lib/features/live/engine/dsp/live_pipeline.dart:277`), amit a frame
  `inputLevel`-ként visz ki (`:288`). Klipping, zajszint, SNR, csend-arány,
  beszéd-jelleg: **nincs**.
- **A batch oldalon viszont KÉSZ a matematika**:
  `lib/features/audio_analysis/engine/quality/signal_quality_math.dart` —
  `peakDbfs`, `rmsDbfs`, `clippedSampleRatio`, `isSilentFrame`, `silentRatio`,
  `activeRegionRatio`, `noiseFloorDbfs`, `noiseFloorDbfsForFrames`,
  `tonalness` (spektrális laposság FFT-vel), és a küszöbök a
  `QualityThresholds.standard`-ban élnek. Ehhez tartozik a
  `signal_quality_stage.dart` (ADR 0224) és a
  `docs/rag/chunks/019-signal-quality-metrics.md`.
- **Ez a kör tehát NEM ír új DSP-matematikát**: a meglévő, mért függvényeket
  használja fel streaming módban. Ami hiányzik és itt születik: az
  **állapotgép + hiszterézis** és a Live-oldali gyűjtő.
- A `crest factor` és az `SNR proxy` a meglévő API-ból **számolható**
  (`peakDbfs − rmsDbfs`, illetve `rmsDbfs − noiseFloorDbfs`) — ne új képlet
  szülessen rájuk.

## 3. Scope

**Benne:**

1. `LiveSignalQualityAnalyzer` — streaming: PCM-blokkonként frissít, a
   `signal_quality_math` függvényeivel; kimenete a `SignalQualitySnapshot`
   (E14-R04 szerződése).
2. Állapotok: `good`, `tooQuiet`, `tooLoud`, `clipping`, `tooNoisy`,
   `speechLike`, `unstable`, `unknown`.
3. **Hiszterézis**: az állapot csak `enterFrames` egymást követő megerősítés
   után vált, és csak `exitFrames` után enged vissza — a frame-enkénti villogás
   tiltott.
4. `LiveQualityThresholds` — a Live-specifikus küszöbök EGY helyen, verzióval.
5. A pipeline megtölti a snapshotot, és a `LivePipeline` saját, csak olvasható
   getterén publikálja (§0.0 R7 — a `LiveFrame`-en NEM, az a tilos zóna); a
   `inputLevel` mező VÁLTOZATLAN marad.
6. `docs/rag/chunks/live-signal-quality.md` — a küszöbök és a hiszterézis
   paramétereinek forrása (CLAUDE.md: minden hangolt paraméter a chunkba, ugyanabban a commitban).

**Nincs benne (TILOS):** a `signal_quality_math.dart`, a `QualityThresholds`, a
`SignalQualityReport`, a `signal_quality_stage.dart` bármely módosítása (ADR
0224 §3); a meglévő onset/chord DSP-konstansok hangolása (AGENTS.md §9);
UI-változás; hangforrás-, személy- vagy játékminőség-osztályozás; `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/engine/quality/live_signal_quality_analyzer.dart` | a streaming elemző + állapotgép |
| `lib/features/live/engine/quality/live_quality_thresholds.dart` | Live-küszöbök egy helyen, verziózva |
| `lib/features/live/engine/dsp/live_pipeline.dart` | a snapshot bekötése (az `inputLevel` változatlan) |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/live_signal_quality_analyzer_test.dart` | fixture-mátrix (csend, klipping, zaj, beszéd) |
| `test/features/live/live_signal_quality_hysteresis_test.dart` | villogás-tilalom mérése |
| `docs/rag/chunks/live-signal-quality.md` | a paraméterek forrása (DSP-igazság) |
| `docs/rounds/e14-r05-live-signal-quality-analyzer.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten
`lib/features/audio_analysis/engine/quality/**`,
`lib/features/live/engine/dsp/*.dart` a `live_pipeline.dart` kivételével,
`docs/rag/chunks/019-signal-quality-metrics.md`, `docs/adr/**`, `assets/**`,
`ml/**`, `.github/workflows/**`.

## 5. Kötött architekturális döntések (ADR 0357)

### 5.1 A matematika ÚJRAHASZNOSÍTOTT, nem újraírt

A metrikák a meglévő `signal_quality_math` függvényeivel készülnek, és az
elérési út a **`package:strumsight/features/audio_analysis/public.dart`
barrel** (ADR 0507 D1) — a mély import az `architecture` kapuban PIROS (§0.0
R4, mérve). **NEM elfogadható gyengítés:** „a live úthoz gyorsabb saját RMS
kell" indoklású duplikátum — ha teljesítmény-okból tényleg kell, az `stopped`
jelzés és mért javaslat, nem néma másolat. Az `architectureAllowlist` bővítése
szintén tiltott (a lista csak szűkülhet).

### 5.2 Csak audióminőség — semmi más

Az elemző **nem** azonosít hangszert, személyt, hangulatot vagy játéktudást
(ADR 0224 §4 határa). A `speechLike` állapot kizárólag **spektrális** jelzés,
és a neve sem sugallhat személyazonosítást.

### 5.3 Hiszterézis, nem simítás

Az állapot csak `enterFrames` (belépés) és `exitFrames` (kilépés) megerősítés
után vált. **NEM elfogadható gyengítés:** a villogás elkerülése a küszöbök
tágításával — a hiszterézis paramétereit kell használni.

### 5.4 Az `unknown` valódi állapot

Kevés adat (indulás, túl rövid puffer) esetén `unknown` jár. **NEM elfogadható
gyengítés:** a `good` alapértelmezés, mert „még nincs baj".

### 5.5 A meglévő `inputLevel` szerződés érintetlen

A frame `inputLevel` mezője továbbra is ugyanaz a skálázott RMS — a régi UI
addig működik, amíg a későbbi kör le nem váltja.

### 5.6 Minden küszöb a chunkban él

`docs/rag/chunks/live-signal-quality.md` a forrás, és a kódbeli konstansok
onnan hivatkozottak (ugyanabban a commitban, CLAUDE.md HORIZON-szabály).

## 6. Acceptance criteria

1. **Fixture-mátrix**, szintetikus jelekkel, mind a nyolc állapotra legalább egy
   cellával; a `clipping` és a `silence` fixture **100%-ban** a várt állapotot adja.
2. **Hiszterézis mérve**: egy küszöb körül oszcilláló bemenet (±1 dB, 40 frame)
   legfeljebb **egyszer** vált állapotot — a villogás-számláló cellája.
3. `unknown` a puffer feltöltése előtt; `good` csak megerősítés után.
4. A `SignalQualitySnapshot` minden mezője kitöltött (nincs néma `0.0` ott, ahol
   nincs mérés — ilyenkor `null`/`unknown`).
5. **CPU-költség**: a Live pipeline egy blokkjának feldolgozási ideje az elemző
   bekapcsolásával legfeljebb **5%-kal** nő; a mérés futtatható parancsként és
   nyers kimenettel kerül a §10-be (median 3 futásból, azonos bemeneten).
6. A `signal_quality_math.dart` és a `QualityThresholds` **bájtra változatlan**
   (`git diff --stat` nem tartalmazza).
7. `inputLevel` viselkedése változatlan (a meglévő live-tesztek zöldek maradnak).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Saját RMS-implementáció a `signal_quality_math` helyett | 6. pont (ha a math fájlt is „javítja") + 1. pont: a csend-fixture dBFS-e eltér a mért referenciától |
| Hiszterézis nélküli, frame-enkénti döntés | 2. pont: a villogás-számláló |
| `unknown` helyett `good` alapértelmezés induláskor | 3. pont |
| A küszöbök tágítása a villogás ellen | 1. pont: a `tooQuiet`/`good` határcellák elcsúsznak |
| A snapshot hiányzó mezői `0.0`-val kitöltve | 4. pont |
| Az elemző a per-frame forró úton FFT-t futtat minden blokkra | 5. pont: a CPU-cella |
| `speechLike` heurisztika hangforrás-osztályozássá tágítva | review-blokkoló (ADR 0224 §4) + 1. pont: a zaj-fixture téves állapota |

**Numerikus küszöb — `clippedSampleRatio`, a határ a KLIPPING oldalán INKLUZÍV
(a `019-signal-quality-metrics.md` jelöléséhez igazodva; a pontos értéket a
pre-flightban a chunkból vedd át, és `python3 -c`-vel számold ki a fixture
mintaszámait):**

| Cella | `clippedSampleRatio` | Várt állapot |
|---|---|---|
| alatt | küszöb − 1 minta | nem `clipping` (a szint szerinti állapot) |
| pontosan rajta | küszöb | **`clipping`** (inkluzív) |
| fölött | küszöb + 1 minta | `clipping` |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/live_signal_quality_analyzer_test.dart test/features/live/live_signal_quality_hysteresis_test.dart test/features/live
```

A parancs a `gate_tests` MINDKÉT elemét tételesen futtatja (S12), és utánuk a
teljes `test/features/live` könyvtárat is — ez méri az acceptance 7. pontját
(az `inputLevel` viselkedése változatlan, a meglévő live-tesztek zöldek).

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09).

### 7.1 Falszifikációs cella

A 2. ponthoz: a §10-ben dokumentáld, hogy a hiszterézis ideiglenes
kikapcsolásával (`enterFrames = exitFrames = 1`) a villogás-teszt **PIROS**
(másold be a kimenetet), visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `LiveQualityThresholds` + a chunk megírása (a paraméterek forrása).
2. `LiveSignalQualityAnalyzer` a meglévő math függvényeire építve.
3. Állapotgép + hiszterézis.
4. Fixture-mátrix és villogás-teszt.
5. Pipeline-bekötés (az `inputLevel` érintetlen).
6. CPU-mérés (3 futás mediánja), majd a §7 gate-parancs (a `gate_tests` mindkét
   fájlja tételesen + a `test/features/live` könyvtár).

## 9. Kockázatok

- **Forró út**: a `tonalness` FFT-t futtat. Ha minden blokkra fut, a CPU-cella
  megbukik — ritkított (pl. minden N-edik blokk) frissítés kell, és ezt a
  chunkban dokumentálni.
- A batch- és a live-küszöbök **eltérhetnek** (más ablakhossz) — ezért külön
  `LiveQualityThresholds`, de a KÉPLETEK közösek; a különbség indoklása a
  chunkba kerül.
- A `speechLike` a legkockázatosabb állapot (ADR 0224 §4 határa) — ha a fixture
  nem tudja megbízhatóan elkülöníteni, inkább `unknown`-t adjon, mint téves
  osztályozást; ezt a döntést a §10-ben jelentsd.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
