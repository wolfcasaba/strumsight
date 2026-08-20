# E14-R05 — Live signal quality analyzer

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 7b5315b`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 5
- **Kör-azonosító:** `E14-R05`
- **Branch:** `<motor>/e14-r05-live-signal-quality-analyzer`
- **Előfeltétel:** `E14-R04` merge-elve — a `SignalQualitySnapshot` szerződése
  ott születik, ez a kör TÖLTI MEG.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0357` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

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
  (`lib/features/live/engine/dsp/live_pipeline.dart:231`), amit a frame
  `inputLevel`-ként visz ki (`:242`). Klipping, zajszint, SNR, csend-arány,
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
5. A pipeline megtölti a snapshotot (a `inputLevel` mező VÁLTOZATLAN marad).
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

A metrikák a meglévő `signal_quality_math` függvényeivel készülnek. **NEM
elfogadható gyengítés:** „a live úthoz gyorsabb saját RMS kell" indoklású
duplikátum — ha teljesítmény-okból tényleg kell, az `stopped` jelzés és mért
javaslat, nem néma másolat.

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
tools/round-gate.sh test/features/live
```

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
6. CPU-mérés (3 futás mediánja), majd `tools/round-gate.sh test/features/live`.

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
