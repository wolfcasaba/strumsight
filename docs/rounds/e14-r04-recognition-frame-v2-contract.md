# E14-R04 — RecognitionFrame V2 domain contract

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 7b5315b`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 4
- **Kör-azonosító:** `E14-R04`
- **Branch:** `<motor>/e14-r04-recognition-frame-v2-contract`
- **Előfeltétel:** `E14-R03` merge-elve — a `RecognitionRuntimeInfo` ott
  születik meg, és ez a kör HIVATKOZIK rá (nem írja újra).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0356` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd újra a `LiveFrame` hívóinak
> számát (`grep -rl "LiveFrame" lib/ test/ | wc -l` — a brief írásakor **19**),
> és olvasd újra a `live_frame.dart` mezőlistáját. Ha az `E14-R03` átnevezte a
> `RecognitionRuntimeInfo` mezőit, a §5.4 ahhoz igazodik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/domain/recognition/recognition_decision.dart",
  "lib/features/live/domain/recognition/chord_prediction.dart",
  "lib/features/live/domain/recognition/strum_prediction.dart",
  "lib/features/live/domain/recognition/signal_quality_snapshot.dart",
  "lib/features/live/domain/recognition/recognition_frame.dart",
  "lib/features/live/domain/recognition/live_frame_adapter.dart",
  "lib/features/live/public.dart",
  "test/features/live/recognition_frame_contract_test.dart",
  "test/features/live/live_frame_adapter_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e14-r04-recognition-frame-v2-contract.md",
]
gate_tests = [
  "test/features/live/recognition_frame_contract_test.dart",
  "test/features/live/live_frame_adapter_test.dart",
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

Olyan **verziózott, Flutter-független felismerési szerződés**, amelyben a UI
meg tudja különböztetni a biztos, a bizonytalan, az ideiglenes és az elutasított
felismerést — és külön látja az **akkord-** és az **irány-**confidence-t
(SDD Ch14 Kör 4).

Ez a kör **szerződést ad, nem UI-t** és **nem hangol felismerést**. A Live
képernyő ebben a körben változatlan marad.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0271 §1** (`UNKNOWN > CONFIDENTLY WRONG`) — a döntési állapotok
  létjogosultsága; a bizonytalanság megjelenítése követelmény, nem opció.
- **ADR 0216** (analysis confidence, calibration and abstention) — a
  kalibrálatlan valószínűséget tilos confidence-ként közölni; ugyanaz a
  határ érvényes itt is (Ch14 §9.6).
- **ADR 0116** (legacy migration adapter: report boundary) — az adapter
  mintája: a régi hívók változatlanul működnek, a fordítás lokális típusban él.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/model/live_frame.dart` — **108 sor, 11 mező**: `current`,
  `next`, `latestStrum`, `bar`, `bpm`, `inputLevel`, `tuningHz`, `listening`,
  `strumSeq`, `latestStrumTime`, `engineTimeSec`.
- **Egyetlen confidence van**, és az a STRUM-é:
  `double get confidence => latestStrum?.confidence ?? 0;` (`:69`). Az akkordnak
  nincs saját közölt confidence-e.
- Az akkord ma **bináris**: `showChord = _lastChord != null && _chordLatched`
  (`live_pipeline.dart:233-236`) — ha a latch nem áll be, a UI SEMMIT nem lát,
  „bizonytalan" állapot nem létezik.
- **19 fájl** hivatkozik a `LiveFrame`-re (`lib/` + `test/`), köztük a
  `live_screen.dart`, a `live_status_bar.dart`, a `chord_timeline_provider.dart`
  és a `live_practice_observation_gateway.dart` — ezért kötelező az adapter.
- `lib/features/live/domain/` **nem létezik** — a feature ma `model/`,
  `engine/`, `providers/`, `screens/`, `widgets/` mappákat használ. Ez a kör
  hozza létre a `domain/recognition/` alkönyvtárat.
- Architektúra-őr: `test/core/architecture_dependency_test.dart` +
  `tool/check_architecture.dart` létezik — az új domain réteg tilalmait ide kell
  bekötni.

## 3. Scope

**Benne:**

1. `RecognitionDecision` — állapot-enum: `candidate`, `provisional`,
   `confirmed`, `uncertain`, `rejected`, `expired`, plusz
   `RecognitionRejectReason` (zárt enum: `lowConfidence`, `unstable`,
   `signalQuality`, `noChord`, `modelUnavailable`, `timeout`).
2. `StrumPrediction` — `onsetTimeSec`, `verdictTimeSec`, `pDown`, `pUp`,
   `pNoStrum`, `calibratedConfidence` (nullable!), `directionMargin`,
   `modelId`, `decision`.
3. `ChordPrediction` — `label`, `root`, `quality`, `pNoChord`, `pUnknown`,
   `calibratedConfidence` (nullable!), `stabilityFrames`, `sourceEngine`,
   `decision`.
4. `SignalQualitySnapshot` — a `E14-R05` által megtöltendő, ebben a körben
   **csak a szerződés** (mezők + `unknown` default).
5. `RecognitionFrame` — a fentiek + `RecognitionRuntimeInfo` (E14-R03) +
   `schemaVersion`, `frameTimeSec`.
6. `LiveFrameAdapter` — kétirányú fordítás a régi `LiveFrame`-re, hogy a 19
   hívó ÉRINTETLEN maradjon.
7. JSON round-trip mindkét irányban + architektúra-guard bővítés.

**Nincs benne (TILOS):** a `LiveFrame` mezőinek törlése/átnevezése; a
`live_pipeline.dart` vagy bármely engine-fájl átkötése az új szerződésre (az a
következő kör); UI-változás; kalibrációs számítás implementálása; DSP/ML
konstans (AGENTS.md §9); `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/domain/recognition/recognition_decision.dart` | döntési állapotok + reject-okok |
| `lib/features/live/domain/recognition/strum_prediction.dart` | irány-jóslat szerződése |
| `lib/features/live/domain/recognition/chord_prediction.dart` | akkord-jóslat szerződése |
| `lib/features/live/domain/recognition/signal_quality_snapshot.dart` | minőség-pillanatkép (R05 tölti meg) |
| `lib/features/live/domain/recognition/recognition_frame.dart` | az összefogó, verziózott frame |
| `lib/features/live/domain/recognition/live_frame_adapter.dart` | kompatibilitás a 19 hívóval |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/recognition_frame_contract_test.dart` | szerződés + JSON round-trip |
| `test/features/live/live_frame_adapter_test.dart` | backward compatibility mátrix |
| `test/core/architecture_dependency_test.dart` | „a domain nem importál Fluttert" őr |
| `docs/rounds/e14-r04-recognition-frame-v2-contract.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/model/live_frame.dart`
(nem módosul!), `lib/features/live/engine/**`, `lib/features/live/screens/**`,
`lib/features/live/widgets/**`, `docs/adr/**`, `.github/workflows/**`.

## 5. Kötött architekturális döntések (ADR 0356)

### 5.1 A domain réteg nem lát Fluttert

`lib/features/live/domain/recognition/**` egyetlen fájlja sem importálhat
`package:flutter/*`-ot vagy `package:flutter_riverpod/*`-ot — és ezt az
architektúra-teszt méri, nem a review szeme. **NEM elfogadható gyengítés:**
`package:flutter/foundation.dart` behúzása a `@immutable` annotációért; a
domain osztályok `const` konstruktorral és `final` mezőkkel immutable-ök
annotáció nélkül is.

### 5.2 Kalibrálatlan valószínűség NEM confidence

`pDown`/`pUp`/`pNoStrum`/`pNoChord` **nyers modell-kimenet**. A
`calibratedConfidence` **nullable**, és `null` marad addig, amíg nincs mért
kalibráció (a kalibráció külön kör). **NEM elfogadható gyengítés:** a nyers
valószínűség átmásolása a `calibratedConfidence`-be „ideiglenesen" — épp ez a
hazugság ellen szól az ADR 0216 és a Ch14 §9.6.

### 5.3 A `decision` a jóslat része, nem a UI-é

Az állapotot a domain számolja ki (a jelenlévő bemenetekből), és a UI CSAK
megjeleníti. **NEM elfogadható gyengítés:** `decision`-t a widget-rétegben
kitalálni küszöbökből.

### 5.4 Az adapter fordít, nem dönt

A `LiveFrameAdapter` a régi `LiveFrame`-et állítja elő. **NEM elfogadható
gyengítés:** az `uncertain`/`provisional` állapot `confirmed`-ként való
átfordítása, hogy „legyen mit mutatni" — a régi frame ilyenkor `current: null`
(pontosan a mai `_chordLatched == false` viselkedés), azaz a kompatibilitás
nem ront a mai igazságtartalmon.

### 5.5 Verziózott szerződés

`RecognitionFrame.schemaVersion` konstans (`1`), és a JSON-parse ismeretlen
verzióra TÍPUSOS hibát ad, nem próbál „legjobb tudása szerint" olvasni.

## 6. Acceptance criteria

1. Architektúra-teszt bizonyítja: a `domain/recognition/**` nem importál
   Fluttert/Riverpodot.
2. JSON round-trip mind az öt modellre zöld (`toJson`/`fromJson` fixpont).
3. **Backward compatibility mátrix**: a hat `RecognitionDecision` állapot ×
   `{van akkord, nincs akkord}` — az adapter kimenete minden cellában a MAI
   `LiveFrame`-viselkedést adja (a `confirmed` mutat akkordot; a `candidate`,
   `provisional`, `uncertain`, `rejected`, `expired` NEM).
4. A `calibratedConfidence` `null` marad, ha a bemenet kalibrálatlan; a teszt
   kimondottan méri, hogy nem a nyers `pDown` került bele.
5. `RecognitionFrame` külön hordozza a chord- és a direction-confidence-t (a
   régi `LiveFrame.confidence` továbbra is a strum értékét adja — nem változik).
6. Ismeretlen `schemaVersion` → típusos hiba (nem `null`, nem részleges objektum).
7. `public.dart` additív; a `LiveFrame` fájl **bájtra változatlan**
   (`git diff --stat` nem tartalmazza).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `package:flutter/foundation.dart` import a domainben (`@immutable`-ért) | 1. pont: architektúra-teszt |
| `calibratedConfidence = pDown` „ideiglenes" kitöltés | 4. pont: kalibrációs cella |
| Az adapter `uncertain` esetén is beírja a `current` akkordot | 3. pont: a mátrix `uncertain × van akkord` cellája |
| Az adapter `expired` állapotot `confirmed`-ként kezel | 3. pont: az `expired` sor |
| Ismeretlen `schemaVersion` „best effort" olvasása | 6. pont: verzió-cella |
| A `decision` kiszámítása kimarad (mindig `confirmed`) | 3. pont: mind az öt nem-confirmed sor |
| A `LiveFrame` mezőinek átszabása a kompatibilitás helyett | 7. pont: a „bájtra változatlan" cella |

**Numerikus küszöb — `directionMargin` (|pDown − pUp|), a határ az
ELUTASÍTÁSHOZ tartozik (inkluzív):**

| Cella | `directionMargin` | Várt `decision` |
|---|---|---|
| alatt | `0.02` | `uncertain` (reject-ok: `lowConfidence`) |
| pontosan rajta | `0.05` | `uncertain` — a küszöb INKLUZÍV az elutasítás oldalán |
| fölött | `0.30` | `confirmed` |

> A `0.05` küszöb ebben a körben a **szerződés alapértéke**, nem hangolt DSP-
> paraméter: a domain konstansként hordozza, és a későbbi, MÉRT kalibrációs kör
> írja felül ADR-rel. Ezt a briefet ez a mondat köti — küszöbhangolás itt TILOS.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live test/core
```

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09).

### 7.1 Falszifikációs cella

Az 1. ponthoz: a §10-ben dokumentáld, hogy egy ideiglenes
`import 'package:flutter/foundation.dart';` a domain egyik fájljába a
`test/core/architecture_dependency_test.dart`-ot **PIROSRA** váltja (másold be a
kimenetet), majd eltávolítva **ZÖLD**.

## 8. Implementációs sorrend

1. Enumok (`RecognitionDecision`, `RecognitionRejectReason`).
2. `StrumPrediction`, `ChordPrediction`, `SignalQualitySnapshot`.
3. `RecognitionFrame` + JSON.
4. Architektúra-guard bővítés + teszt.
5. `LiveFrameAdapter` + a hatszor kettes mátrix.
6. `public.dart`, majd `tools/round-gate.sh test/features/live test/core`.

## 9. Kockázatok

- **A 19 hívó**: ha bármelyik közvetlenül a `LiveFrame` konstruktorát hívja
  (mockok!), az adapter kimenetének pontosan illeszkednie kell — a mátrix ezt
  méri, de a mockok frissítése NEM engedélyezett ebben a körben; ha muszáj
  lenne, az `stopped` jelzés és jelentés.
- A `public.dart` generált barrel lehet — generátorral frissítsd.
- A `domain/` mappa bevezetése új mintát hoz a `live` feature-be: a többi
  feature (`audio_analysis`, `gamification`) már `domain/`-t használ, tehát ez
  konvergencia, nem új konvenció.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
