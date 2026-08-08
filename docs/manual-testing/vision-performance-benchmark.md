# Computer Vision — teljesítmény-benchmark sablon (E05-R01)

- **Kör:** E05-R01 — Vision baseline, capability audit és alapozó ADR-ek
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md)
- **Státusz:** sablon — a méréseket a későbbi körök és a HORIZON valós-eszközös
  elfogadás töltik ki
- **Precedens:** `docs/baseline/epic-04-performance.md` (E04-R24)

> ⚠ **HORIZON-szabály:** a merge-kapu a `tools/round-gate.sh` + exact-SHA zöld
> CI; a valós eszközös teljesítménymérés a merge UTÁNI termék-elfogadás
> (HORIZON). A táblázatok PENDING sorai **nem merge-blokkolók**.
> E05-R30 nem ír be szintetikus számot valós eszközös eredmény helyett; minden
> alábbi PENDING mérés változatlanul a HORIZON elfogadás része.

## 1. Módszertan

Minden mérés valós Android eszközön, a CI által épített release APK-val
történik. A mérési környezet:

- **Eszköz:** Android 13+ (API 33+), legalább 4 GB RAM
- **Build:** release APK (nem debug)
- **Kamera:** az eszköz elsődleges hátlapi kamerája, 30 fps target
- **Fényviszonyok:** beltéri nappali (standardizált: 500 lux)
- **Gitár:** akusztikus, standard tartásban, a kamerától ~60 cm-re
- **Session hossz:** 5 perc folyamatos hand tracking + audio capture
- **Iterációk:** legalább 3 futás, az átlagot és a p95-öt is rögzíteni kell

A méréshez használt forgatókönyv: nyitott akkordok váltogatása (G–C–D–Em),
4/4, 80 bpm metronómra, folyamatos strumming.

## 2. Mérendő dimenziók

### 2.1 Frame rate (FPS)

| Metrika | Target (production) | Küszöb (minimum) | Eszköz | Mért átlag | Mért p95 | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Kamera capture FPS | 30 fps | 15 fps | PENDING | PENDING | PENDING | PENDING | PENDING |
| Hand tracking inference FPS | 15 fps | 8 fps | PENDING | PENDING | PENDING | PENDING | PENDING |
| Pose tracking inference FPS | 10 fps | 5 fps | PENDING | PENDING | PENDING | PENDING | PENDING |
| Hand + pose egyidejű FPS | 10 fps | 5 fps | PENDING | PENDING | PENDING | PENDING | PENDING |
| Overlay render FPS | 30 fps | 15 fps | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.2 Inference latency

| Metrika | Target (production) | Küszöb (maximum) | Eszköz | Mért átlag | Mért p95 | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hand landmark inference (frame → landmark) | < 33 ms | < 66 ms | PENDING | PENDING | PENDING | PENDING | PENDING |
| Pose landmark inference (frame → landmark) | < 50 ms | < 100 ms | PENDING | PENDING | PENDING | PENDING | PENDING |
| Frame preprocessing (rotation + mirror + crop) | < 5 ms | < 10 ms | PENDING | PENDING | PENDING | PENDING | PENDING |
| Metric engine számítás (frame → insight) | < 5 ms | < 15 ms | PENDING | PENDING | PENDING | PENDING | PENDING |
| Teljes pipeline latency (frame capture → insight) | < 100 ms | < 200 ms | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.3 Frame-drop

| Metrika | Target (production) | Küszöb (maximum) | Eszköz | Mért érték | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- |
| Dropped frame-ek száma (5 perc alatt) | < 30 | < 150 | PENDING | PENDING | PENDING | PENDING |
| Frame-drop arány | < 1% | < 5% | PENDING | PENDING | PENDING | PENDING |
| Frame-drop kaszkád (≥ 3 egymást követő drop események száma) | 0 | ≤ 2 | PENDING | PENDING | PENDING | PENDING |
| Legnagyobb frame-drop gap (ms) | < 200 ms | < 500 ms | PENDING | PENDING | PENDING | PENDING |

### 2.4 Thermal

| Metrika | Target (production) | Küszöb (maximum) | Eszköz | Mért érték | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- |
| Eszköz-hőmérséklet emelkedése (5 perc alatt) | < 5°C | < 10°C | PENDING | PENDING | PENDING | PENDING |
| Thermal throttle észlelve? (5 perc alatt) | NEM | NEM | PENDING | PENDING | PENDING | PENDING |
| Thermal throttle észlelve? (15 perc alatt, soak) | NEM | max 1 enyhe fokozat | PENDING | PENDING | PENDING | PENDING |
| Thermal throttle észlelve? (10 perc alatt, soak) | PENDING — E05-R29 terv | PENDING | PENDING (Pixel 6a) | PENDING | PENDING | PENDING |
| Thermal throttle észlelve? (30 perc alatt, soak) | PENDING — E05-R29 terv | PENDING | PENDING (Samsung Galaxy A54) | PENDING | PENDING | PENDING |

### 2.5 Audio impact (ADR 0182)

| Metrika | Target (production) | Küszöb (maximum romlás) | Eszköz | Audio-only baseline | Audio + vision | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Audio scoring accuracy (vision ON vs OFF) | < 1% romlás | < 3% romlás | PENDING | PENDING | PENDING | PENDING | PENDING |
| Audio frame-drop (vision ON) | 0 | ≤ 2 frame | PENDING | PENDING | PENDING | PENDING | PENDING |
| Audio processing latency növekmény (vision ON) | < 5 ms | < 15 ms | PENDING | PENDING | PENDING | PENDING | PENDING |
| Strum detection accuracy (vision ON vs OFF) | azonos | < 2% romlás | PENDING | PENDING | PENDING | PENDING | PENDING |
| Chord detection accuracy (vision ON vs OFF) | azonos | < 2% romlás | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.6 Memória

| Metrika | Target (production) | Küszöb (maximum) | Eszköz | Mért érték | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- | --- |
| App memória (vision OFF, idle) | < 150 MB | < 200 MB | PENDING | PENDING | PENDING | PENDING |
| App memória (vision ON, 5 perc session) | < 350 MB | < 500 MB | PENDING | PENDING | PENDING | PENDING |
| Memória-növekmény (vision ON vs OFF) | < 200 MB | < 300 MB | PENDING | PENDING | PENDING | PENDING |
| VisionSessionResult aggregátum mérete (5 perc session) | < 100 KB | < 500 KB | PENDING | PENDING | PENDING | PENDING |

### 2.7 Degradációs lánc (ADR 0182 §3)

| Degradációs szint | Trigger (mért) | Eszköz | Észlelve? | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- |
| 1. Overlay rajzolási frekvencia csökkentése | Hand FPS < 12 | PENDING | PENDING | PENDING | PENDING |
| 2. Pose pipeline ritkítása | Hand FPS < 10 | PENDING | PENDING | PENDING | PENDING |
| 3. Hand pipeline FPS csökkentése | Pose FPS < 5 | PENDING | PENDING | PENDING | PENDING |
| 4. Model input resolution csökkentése | Hand FPS < 8 | PENDING | PENDING | PENDING | PENDING |
| 5. Csak egy kéz követése | Hand FPS < 6 | PENDING | PENDING | PENDING | PENDING |
| 6. Csak quality monitor futtatása | Hand FPS < 4 | PENDING | PENDING | PENDING | PENDING |
| 7. Vision leállítása, audio megtartása | Audio scoring romlás | PENDING | PENDING | PENDING | PENDING |

### 2.8 Konfidencia-kalibráció (ADR 0179)

| Metrika | Target (production) | Eszköz | Mért érték | Státusz | Felelős |
| --- | --- | --- | --- | --- | --- |
| Hand landmark confidence (jól megvilágított, tiszta frame) | ≥ 0.8 | PENDING | PENDING | PENDING | PENDING |
| Hand landmark confidence (gyenge fény) | ≥ 0.5 | PENDING | PENDING | PENDING | PENDING |
| Hand landmark confidence (részleges takarás) | visibility flag csökken, confidence arányos | PENDING | PENDING | PENDING | PENDING |
| Pose landmark confidence (jól megvilágított, teljes alak) | ≥ 0.8 | PENDING | PENDING | PENDING | PENDING |
| False feedback arány (confidence < küszöb, mégis feedback) | 0 | PENDING | PENDING | PENDING | PENDING |

## 3. Eszközlista — mérési terv

| Eszköz | Android | CPU / GPU | RAM | Prioritás |
| --- | --- | --- | --- | --- |
| Pixel 6a | 14 (API 34) | Google Tensor, Mali-G78 | 6 GB | Kötelező (elsődleges baseline) |
| Pixel 7 | 14 (API 34) | Google Tensor G2, Mali-G710 | 8 GB | Kötelező |
| Samsung Galaxy A54 | 14 (API 34) | Exynos 1380, Mali-G68 | 6 GB | Ajánlott (középkategóriás) |
| Xiaomi Redmi Note 12 | 13 (API 33) | Snapdragon 685, Adreno 610 | 4 GB | Ajánlott (alsó-közép határ) |

## 4. Reprodukálás

A mérés a CI által épített release APK-val történik. A benchmark futás
részletei a későbbi körökben kerülnek definiálásra (E05-R04 calibration,
E05-R08 first hand tracking milestone, E05-R10 device benchmark kör).

A session logging és a `VisionSessionResult` aggregátum a mérés elsődleges
forrása; az FPS, latency és dropped-frame count a device-mátrixból és a
session aggregátumból nyerhető ki.

## 5. Következő lépés

Az első mérési pont az **E05-R04** (első camera calibration spike) után
válik elérhetővé. Addig minden cella PENDING.
