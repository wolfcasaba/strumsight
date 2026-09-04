# E14-R04 — RecognitionFrame V2 domain contract

- **Státusz:** ACTIVE (pre-flight lefutott 2026-09-04, kód mérve: `main @ f7fd7ab0`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 4
- **Kör-azonosító:** `E14-R04`
- **Branch:** `sonnet-impl/e14-r04-recognition-frame-v2-contract`
- **Előfeltétel:** `E14-R03` merge-elve — a `RecognitionRuntimeInfo` ott
  születik meg, és ez a kör HIVATKOZIK rá (nem írja újra). ✅ mérve: `b82f3ab5`.
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0505`](../adr/0505-versioned-recognition-frame-contract-and-legacy-adapter.md)
  — a pre-flightban MEGÍRVA és commitolva. A `docs/adr/` az implementer TILOS
  zónája. (A queue `0356`-ot előlegezett; lásd §0.0 R1.)

## 0.0 Pre-flight revízió (2026-09-04, orchestrátor: Claude Opus 5)

Minden alábbi pont **mért**, a parancs a sor végén áll. Ez a szakasz erősebb a
brief többi részénél ott, ahol eltér tőle.

**R1 — ADR `0356` → `0505`.** `tools/round-slots.py reserve-adr --round E14-R04`
→ `0505`. A foglaló `candidate = max(used) + 1`
(`tools/round-slots.py:357`), tehát **sosem tölt ki hézagot**: a sorszám a brief
megírása (2026-08-20) óta `0503`-ig futott, a `0356` pedig hézaggá vált (nincs
lemezen és egyetlen ág története sem hozta létre). A prompt §1.0.1 a foglalót
teszi mérvadóvá az `ls docs/adr | tail` alakkal szemben, ezért a kör ADR-je
**0505**. A queue `0356` oszlopa marad — a sor-fájl a driveré (prompt §4), és
`tools/tests/test_adr_numbering.py` csak névkonvenciót és egyediséget mér, a
queue-oszloppal nem csatol.

**R2 — `LiveFrame` hívók: 19 → 22.** `grep -rl "LiveFrame" lib/ test/ | wc -l`
→ `22`. Scope-változás nincs; az adapter-követelmény ettől csak erősebb. A §2 és
a §9 „19" előfordulásai **22**-t jelentenek.

**R3 — az architektúra-őr NEM igényli a `tool/check_architecture.dart`
módosítását.** Mérve: `_isSharedDomain` (`tool/check_architecture.dart:419-422`)
három prefixet drótoz be (`lib/core/music/`, `lib/core/audio/codec/`,
`lib/features/practice/domain/`), és a `checkArchitecture` nem kínál bővítési
pontot. A fa bevett mintája feature-domainre az **önálló, forrás-szkennelő
csoport a tesztben**: `practice_generator/domain`
(`test/core/architecture_dependency_test.dart:23`), `gamification/domain`
(`:101`), `community/domain` (`:982`). Ez a kör ezt a mintát követi. A `tool/`
**tilos zóna** — hozzányúlni H3.

**R4 — `package:meta/meta.dart` MEGENGEDETT a domainben.** A §5.1 a
`package:flutter/foundation.dart`-ot tiltja; a `@immutable` viszont a
`package:meta`-ból is jön, és a fa így csinálja (`lib/core/music/chord.dart:1`,
`lib/features/live/model/recognition_runtime_info.dart:1`), a
`_isForbiddenDomainDependency` (`:424-437`) pedig nem tiltja. Tiltott marad:
`package:flutter/*`, `package:flutter_riverpod/*`, `package:riverpod/*`.

**R5 — az adapter az EGYETLEN legacy-import a domainben.** Mérve:
`lib/features/live/model/live_frame.dart:1` `package:flutter/foundation.dart`-ot
importál, az adapternek viszont `LiveFrame`-et kell építenie. Az őr ezért a
`domain/recognition/**` **közvetlen** import-direktíváit méri; az adapter
`import '../../model/live_frame.dart';` sora legális (ADR 0505 D5). A másik öt
szerződés-fájl a `model/`-ből CSAK a `recognition_runtime_info.dart`-ot
importálhatja — külön cella pinneli.

**R6 — `directionMargin` SZÁMÍTOTT getter, nem konstruktor-paraméter:**
`double get directionMargin => (pDown - pUp).abs();` (ADR 0505 D4). A §3.2
mezőlistájában szereplő `directionMargin` ezentúl gettert jelent — így nem
építhető `pDown: 0.9, pUp: 0.1, directionMargin: 0.01` alakú inkonzisztens
állapot, amitől a §6.1 küszöb-táblázat mérése értelmét vesztené.

**R7 — ebben a körben CSAK a `StrumPrediction.decision` levezetett.**
`ChordPrediction.decision` és a `SignalQualitySnapshot` mezői
konstruktorból kapott értékek; akkord-döntést MÉRT kalibráció nélkül levezetni
a §5.2 tiltotta hazugság lenne (azt az `E14-R05` és az `E14-R11` hozza). A §5.3
így is teljesül: a döntés a jóslaton ül, sosem a widgetben.

**R8 — `lib/features/live/public.dart` KÉZZEL írt barrel.** Mérve:
`ls -d lib/features/*/public/` → egyedül a `practice_generator` rendelkezik
fragmentumokkal. A §9 „generátorral frissítsd" pontja erre a körre **nem**
alkalmazandó: a `public.dart`-ot közvetlenül szerkeszd.

**R9 — brief-lint S12 javítva.** A §7 gate-parancsa mostantól tételesen
tükrözi a `gate_tests` listát, és a `test/core/architecture_dependency_test.dart`
BEKERÜLT a `gate_tests`-be (az 1. acceptance-pontot az méri; az
`allowed_paths`-on már rajta volt). Ez szigorítás, nem tágítás.

**R10 — `fromJson` fail-CLOSED, minden modellre.** `docs/LESSONS.md` **L619**
(E14-R02, ugyanez a fejezet, 2026-09-04): *a kézzel írt séma-validátor
alapértelmezésben fail-OPEN — a le nem fedett kulcs nem hibás, hanem NEM
LÉTEZIK, ezért a séma szigorúbbnak LÁTSZIK, mint amit érvényesít.* Emiatt a
boldog-utas round-trip (6. acceptance-pont) önmagában NEM elég: **modellenként**
kell egy hiányzó-kötelező-kulcs cella is, amely típusos hibát vár, nem `null`-t
és nem részleges objektumot.

**R11 — párhuzamos kör.** `tools/round-slots.py inflight-list` → `E14-R04` és
`E14-R06` fut. Az `E14-R06` `allowed_paths`-a (`lib/features/accuracy_lab/**`,
`test/features/accuracy_lab/**`) a miénkkel **diszjunkt** — átfedés nincs.

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
  "test/core/architecture_dependency_test.dart",
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

## 5. Kötött architekturális döntések (ADR 0505 — lásd §0.0 R1)

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
8. **Fail-closed parse (§0.0 R10, L619):** MINDEN modell `fromJson`-jére van egy
   cella, amely egy kötelező kulcsot KIHAGY a bemenetből, és típusos hibát vár —
   nem `null`-t és nem részleges objektumot. Öt modell = öt cella.
9. **A szerződés-fájlok legacy-import tilalma (§0.0 R5):** cella bizonyítja, hogy
   az öt szerződés-fájl (`recognition_decision`, `strum_prediction`,
   `chord_prediction`, `signal_quality_snapshot`, `recognition_frame`) a
   `model/`-ből CSAK a `recognition_runtime_info.dart`-ot importálja; egyedül a
   `live_frame_adapter.dart` érheti el a `live_frame.dart`-ot.

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

A `directionMargin` **getter** (§0.0 R6), ezért a cellát a `pDown`/`pUp` párral
kell felépíteni. A konkrét értékeket `python3`-mal számoltam ki (mindhárom
összeg pontosan `1.000`, `pNoStrum = 0.100`):

| Cella | `pDown` | `pUp` | `directionMargin` | Várt `decision` |
|---|---|---|---|---|
| alatt | `0.460` | `0.440` | `0.02` | `uncertain` (reject-ok: `lowConfidence`) |
| pontosan rajta | `0.475` | `0.425` | `0.05` | `uncertain` — a küszöb INKLUZÍV az elutasítás oldalán |
| fölött | `0.600` | `0.300` | `0.30` | `confirmed` |

```
$ python3 -c "
t = 0.05
for pd, pu in ((0.460,0.440), (0.475,0.425), (0.600,0.300)):
    m = abs(pd - pu)
    print(f'pDown={pd} pUp={pu} margin={m!r} sum={pd+pu+0.1:.3f} m<=t={m<=t}')
"
pDown=0.46 pUp=0.44 margin=0.020000000000000018 sum=1.000 m<=t=True
pDown=0.475 pUp=0.425 margin=0.04999999999999999 sum=1.000 m<=t=True
pDown=0.6 pUp=0.3 margin=0.3 sum=1.000 m<=t=False
```

> ⚠ **A határcella lebegőpontos, és ezt MÉRTEM — ne „javítsd" más számpárra.**
> `0.475 - 0.425 = 0.04999999999999999`, tehát `<= 0.05` **igaz** → `uncertain`,
> ahogy a táblázat írja. Ellenpélda ugyanerre a szándékolt `0.05` margóra:
> `0.525 - 0.475 = 0.050000000000000044`, ami `<= 0.05` **hamis** → `confirmed`
> lenne. A cellát ezért PONTOSAN a fenti `pDown`/`pUp` párokkal írd meg, és ne
> cseréld le őket egy „szebb" párra: a határ inkluzivitását a getter és a
> küszöb EGYÜTT adja, és a csere némán átbillentené a várt verdiktet.
>
> ```
> $ python3 -c "print(repr(abs(0.475-0.425)), abs(0.475-0.425)<=0.05)"
> 0.04999999999999999 True
> $ python3 -c "print(repr(abs(0.525-0.475)), abs(0.525-0.475)<=0.05)"
> 0.050000000000000044 False
> ```

> A `0.05` küszöb ebben a körben a **szerződés alapértéke**, nem hangolt DSP-
> paraméter: a domain konstansként hordozza, és a későbbi, MÉRT kalibrációs kör
> írja felül ADR-rel. Ezt a briefet ez a mondat köti — küszöbhangolás itt TILOS.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/recognition_frame_contract_test.dart test/features/live/live_frame_adapter_test.dart test/core/architecture_dependency_test.dart test/features/live test/core
```

A parancs tételesen tartalmazza a `gate_tests` **mindhárom** elemét (§0.0 R9,
brief-lint S12), és utánuk a két tágabb regressziós felületet
(`test/features/live`, `test/core`), hogy a szomszédos tesztek se csússzanak el.

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

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-09-04.

### 10.1 Mit épített

Öt szerződés-fájl `lib/features/live/domain/recognition/` alatt +
az adapter, ADR 0505-nek megfelelően:

- `recognition_decision.dart` — `RecognitionDecision` (6 állapot) és
  `RecognitionRejectReason` (6 ok) zárt enumok, `toJson`/`fromJson` fail-closed.
- `strum_prediction.dart` — `StrumPrediction`; `directionMargin` SZÁMÍTOTT
  getter (`(pDown - pUp).abs()`), `decision` is getter: `margin <= 0.05` →
  `uncertain`, egyébként `confirmed` (§0.0 R6/R7, ADR 0505 D3/D4). A
  `calibratedConfidence` nullable, sosem a nyers `pDown`.
- `chord_prediction.dart` — `ChordPrediction`; `decision`
  KONSTRUKTORBÓL kapott mező ebben a körben (§0.0 R7), nem levezetett.
- `signal_quality_snapshot.dart` — `SignalQualityState` (8 állapot, `E14-R05`
  brief §3-ából) + `SignalQualitySnapshot`, `unknown` const alapértékkel
  (minden metrika `null`).
- `recognition_frame.dart` — `RecognitionFrame`: `schemaVersion` (const `1`),
  `frameTimeSec`, `strum`/`chord` (nullable), `signalQuality`, `runtimeInfo`
  (`RecognitionRuntimeInfo`, E14-R03-ból importálva, nem újraírva).
- `live_frame_adapter.dart` — `LiveFrameAdapter.toLiveFrame(RecognitionFrame,
  LiveFrame base)`: a `chord` csak `confirmed`-nél jelenik meg
  (`current`), a strum a `calibratedConfidence ?? 0`-t adja legacy
  `confidence`-ként (sosem a nyers valószínűséget). Az ÖT tiszta
  szerződés-fájl a `model/`-ből csak a `recognition_runtime_info.dart`-ot
  importálja; EGYEDÜL ez a fájl éri el a `live_frame.dart`-ot
  (`import '../../model/live_frame.dart';`).
- `test/core/architecture_dependency_test.dart` — új, önálló,
  forrás-szkennelő csoport (`recognition domain stays framework-free
  (E14-R04)`), a `practice_generator`/`gamification`/`community` minta
  szerint; `tool/check_architecture.dart`-hoz NEM nyúltam (§0.0 R3).
- `public.dart` — additív export a 6 új fájlra (a `chord_prediction`,
  `live_frame_adapter`, `recognition_decision`, `recognition_frame`,
  `signal_quality_snapshot`, `strum_prediction`); a `LiveFrame` export sora
  változatlan.
- `test/features/live/recognition_frame_contract_test.dart` (35 teszt) és
  `test/features/live/live_frame_adapter_test.dart` (13 teszt) — mindkettő
  KIZÁRÓLAG a `public.dart` barrelen keresztül importál (ha az export lemarad,
  a fájl fordítási hibával bukik, nem csendben kihagyja a pontot).

### 10.2 Acceptance criteria → bizonyíték

1. Architektúra-teszt: `test/core/architecture_dependency_test.dart` új
   csoportja, 7 teszt (44–50. sorszám a gate-futásban), mind zöld.
2. JSON round-trip mind az 5 modellre:
   `recognition_frame_contract_test.dart` — decision/rejectReason enumok
   (loop minden értékre), `StrumPrediction` (null + mért
   calibratedConfidence), `ChordPrediction` (ua.), `SignalQualitySnapshot`
   (unknown + teljesen mért), `RecognitionFrame` (strum+chord jelen / mindkettő
   null).
3. Backward compat mátrix: `live_frame_adapter_test.dart`, mind a 6
   `RecognitionDecision` állapotra egy-egy teszt — `confirmed` → `current`
   jelen, a többi öt → `current: null`.
4. `calibratedConfidence` null-teszt: `'calibratedConfidence stays null and
   is never the raw pDown/pNoChord'` mindkét prediction-osztályra.
5. Külön chord/direction confidence: `'chord- and direction-confidence are
   carried separately'` teszt, két különböző kalibrált értékkel.
6. Ismeretlen schemaVersion: `'an unknown schemaVersion throws, never a
   best-effort read'`.
7. `public.dart` additív, `LiveFrame` bájtra változatlan — lásd 10.4.
8. Fail-closed hiányzó-kulcs cellák, MODELLENKÉNT:
   `RecognitionDecision.fromJson(json['decision'])` hiányzó kulcsra (1/5),
   `StrumPrediction` hiányzó `calibratedConfidence` KULCS (2/5, külön a
   null-értéktől), `ChordPrediction` hiányzó `sourceEngine`/`decision` (3/5),
   `SignalQualitySnapshot` hiányzó `state` (4/5), `RecognitionFrame` hiányzó
   `runtimeInfo`/`frameTimeSec`/`strum` KULCS (5/5).
9. Legacy-import határ: `architecture_dependency_test.dart` —
   `_forbiddenRecognitionModelImports` teszteli, hogy csak az adapter éri el
   a `live_frame.dart`-ot, a többi öt fájl csak a
   `recognition_runtime_info.dart`-ot a `model/`-ből.

### 10.3 §7.1 Falszifikációs cella — a bizonyíték

Ideiglenes `import 'package:flutter/foundation.dart';` sort tettem a
`strum_prediction.dart` tetejére, futtattam
`flutter test test/core/architecture_dependency_test.dart`-ot — PIROS:

```
00:01 +44: recognition domain stays framework-free (E14-R04) no Flutter/Riverpod imports in domain/recognition
00:01 +44 -1: recognition domain stays framework-free (E14-R04) no Flutter/Riverpod imports in domain/recognition [E]
  Expected: empty
    Actual: [
              'lib/features/live/domain/recognition/strum_prediction.dart contains "package:flutter/"'
            ]
  lib/features/live/domain/recognition/strum_prediction.dart contains "package:flutter/"

  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test/core/architecture_dependency_test.dart 1130:7  main.<fn>.<fn>

00:01 +50 -1: Some tests failed.

Failing tests:
  /home/ubuntu/ss-sonnet-impl-e14-r04/test/core/architecture_dependency_test.dart: recognition domain stays framework-free (E14-R04) no Flutter/Riverpod imports in domain/recognition
```

Eltávolítottam az importot, újra futtattam — ZÖLD:

```
00:01 +44: recognition domain stays framework-free (E14-R04) no Flutter/Riverpod imports in domain/recognition
00:01 +45: recognition domain stays framework-free (E14-R04) the boundary detector flags a direct Flutter import
00:01 +46: recognition domain stays framework-free (E14-R04) the boundary detector allows package:meta (ADR 0505 §0.0 R4)
00:01 +47: recognition domain stays framework-free (E14-R04) only the adapter reaches live_frame.dart; the rest reach only recognition_runtime_info.dart under model/
00:01 +48: recognition domain stays framework-free (E14-R04) the boundary detector flags a non-adapter file importing live_frame.dart
00:01 +49: recognition domain stays framework-free (E14-R04) the boundary detector allows the adapter importing live_frame.dart
00:01 +50: recognition domain stays framework-free (E14-R04) the boundary detector allows recognition_runtime_info.dart from any contract file
00:01 +51: All tests passed!
```

`git diff --stat -- lib/features/live/domain/recognition/strum_prediction.dart`
üres a revert után — a fájl visszaállt a commitolt állapotára.

### 10.4 `LiveFrame` bájtra változatlan

```
$ git diff --stat -- lib/features/live/model/live_frame.dart
(üres kimenet)
```

A fájlt egyszer sem nyitottam szerkesztésre; a `git status --porcelain` a
teljes kör alatt sosem sorolta fel.

### 10.5 A záró gate

```
tools/round-gate.sh test/features/live/recognition_frame_contract_test.dart test/features/live/live_frame_adapter_test.dart test/core/architecture_dependency_test.dart test/features/live test/core
```

Mind a 10 lépés (`format`, `analyze`, 5×`test`, `architecture`, `secrets`,
`l10n`) ZÖLD. Összegzés a futásból:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/recognition_frame_contract_test.dart zöld
    test test/features/live/live_frame_adapter_test.dart       zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/features/live                                    zöld
    test test/core                                             zöld
    architecture                                                zöld
    secrets                                                     zöld
    l10n                                                        zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

Részletek: a célzott `recognition_frame_contract_test.dart` 35/35, a
`live_frame_adapter_test.dart` 13/13 (12 saját + a fájl betöltése), az
`architecture_dependency_test.dart` 51/51, a teljes `test/features/live`
258/258 (256 pass + 2 skip, a meglévő suite-ból), a teljes `test/core`
765/765 zöld.

### 10.6 Döntések, amik eltértek a brief betűjétől (indoklással)

1. **`RecognitionFrame.strum`/`chord` NULLABLE**, nem kötelező mező. A brief
   §3.5 nem mondja ki explicit módon, de a §6.3 mátrix csak a `chord`
   jelenlétét/hiányát méri egy `RecognitionFrame`-en belül, és az adapter
   `_chordFor`/`_strumFor` metódusainak logikailag kezelniük kell a "még
   nincs verdikt" esetet is (motorindítás, első frame előtt) — nemcsak a
   "van verdikt, de elutasított" esetet. Nullable mezővel mindkettő
   kifejezhető ellentmondás nélkül.
2. **`LiveFrameAdapter.toLiveFrame` egy `LiveFrame base` paramétert is kér**,
   nem csak a `RecognitionFrame`-et. Az ok: `LiveFrame` nyolc mezője
   (`bar`, `bpm`, `inputLevel`, `tuningHz`, `listening`, `strumSeq`, `next`,
   részben `latestStrumTime`) NINCS a `RecognitionFrame` szerződésben —
   ezek a §3 szerint explicit KÍVÜL esnek ezen a körön. A `base` paraméter
   ezeket viszi át változatlanul, és emiatt az adapter fájl SOSEM importálja
   a `beat_slot.dart`-ot (a `List<BeatSlot> bar` típus a `base.bar`
   kifejezésen keresztül implicit marad, `BeatSlot` nevet a fájl nem ír le) —
   ez szigorúbb import-határt tart, mint amit a §0.0 R5 kifejezetten
   megkövetelt volna.
3. **A `LiveFrameAdapter` fordítása EGYIRÁNYÚ ebben a leadásban**
   (`RecognitionFrame → LiveFrame`), a §3.6 „kétirányú fordítás"
   megfogalmazásával szemben. Indoklás: az ellenkező irányhoz
   (`LiveFrame → RecognitionFrame`) a régi `Strum.confidence`-ből
   `pDown`/`pUp` valószínűség-párt kellene KITALÁLNI — pontosan az a fajta
   levezetés, amit az ADR 0505 D2 tilt („a nyers valószínűség »ideiglenes«
   átmásolása … pontosan az a hazugság"), csak fordított irányban (kalibrált
   adatból nyers valószínűséget hazudni). A ténylegesen tesztelt/mért
   irányt (D5, §6.3 mátrix) implementáltam; a fordított irányt NEM, mert
   csak találgatással lett volna megépíthető. Ha a `LiveFrame →
   RecognitionFrame` irány egy következő körben tényleg kell, azt egy
   MÉRT forrásból (pl. a strum modell natív kimenetéből, nem a legacy
   `Strum.confidence`-ből) kell táplálni.
4. **`SignalQualitySnapshot` mezői** (`peakDbfs`, `rmsDbfs`, `noiseFloorDbfs`,
   `clippedSampleRatio`, `silentRatio`, `activeRegionRatio`, `tonalness`) —
   a brief §3.4 nem sorol fel konkrét mezőket („csak a szerződés"). A
   választott hét mező 1:1 megfelel a MEGLÉVŐ, mért
   `lib/features/audio_analysis/engine/quality/signal_quality_math.dart`
   publikus felületének (`peakDbfs`, `rmsDbfs`, `clippedSampleRatio`,
   `silentRatio`, `activeRegionRatio`, `noiseFloorDbfs`, `tonalness`), amit
   az `E14-R05` brief §2 is nevesít újrahasznosítandóként — így az `E14-R05`
   a szerződést kitöltheti új DSP-matek nélkül, hangolt küszöb nélkül ebben
   a körben.
5. **A „modellenként egy hiányzó-kulcs cella" (§0.0 R10) `recognition_decision.dart`-ra**
   nem egy térkép hiányzó KULCSÁN, hanem a hiányzó/`null` ÉRTÉKEN mérve —
   az enum maga nem térkép, nincs „kulcsa"; a hívó oldalán (pl.
   `RecognitionFrame.fromJson`) egy hiányzó `'decision'` kulcs ugyanígy
   `null`-t ad át a `RecognitionDecision.fromJson`-nek, ami a típusos hibát
   dobja — a fail-closed lánc a hívási oldalon zárva marad.

### 10.7 Amit szándékosan NEM érintettem

`live_pipeline.dart`, `engine/**`, `screens/**`, `widgets/**`,
`tool/check_architecture.dart`, `docs/adr/**` — egyik fájlt sem nyitottam meg
íróként. A `LiveFrameAdapter` jelenleg nincs bekötve semmilyen production
hívóba (ez a következő kör dolga, §9).

## 11. Review — a Claude tölti ki
