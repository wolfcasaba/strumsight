# Computer Vision — valódi eszközös tesztmátrix (E05-R01)

- **Kör:** E05-R01 — Vision baseline, capability audit és alapozó ADR-ek
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md)
- **Státusz:** sablon — a méréseket a későbbi körök és a HORIZON valós-eszközös
  elfogadás töltik ki
- **Precedens:** `docs/manual-testing/practice-engine-device-matrix.md`
  (E02-R20 A8)

> ⚠ **HORIZON-szabály:** a merge-kapu a `tools/round-gate.sh` + exact-SHA zöld
> CI; a valós eszközös elfogadás a merge UTÁNI termék-elfogadás (HORIZON).
> A mátrix PENDING sorai **nem merge-blokkolók** — a státusz rögzítése a cél.

## 1. Kitöltési útmutató

### 1.1 Mit jelent a státusz

- **PASS** — a készüléken futó APK-val a teszteset lejátszható, a mért
  érték a dokumentált küszöbön belül van, és nincs megfigyelt crash / frame-drop
  kaszkád / audio degradáció / UI fagyás.
- **PARTIAL** — a teszteset lejátszható, de a mért érték a küszöbön kívül esik,
  VAGY egy-két specifikus eltérés van a mért és az elvárt között; a megjegyzés
  mezőben rögzíteni kell a pontos eltérést.
- **FAIL** — a teszteset nem játszható le (crash, kamera nem indul, engedély
  végleg megtagadva, empty frame stream, stb.) VAGY a mért eredmény a küszöbön
  kívül esik és a használhatóság sérül.
- **PENDING** — a teszteset még nem futott le ezen az eszközön; a felelős
  személy és a tervezett időpont ismert.

### 1.2 Mit kell rögzíteni minden cellában

- **Eszköz:** pontos modell (pl. „Pixel 6a") és Android-verzió
  (pl. „Android 14, API 34").
- **Build:** az APK artifact neve (a CI-runjából, pl.
  `strumsight-1.0.0+1-N-sha-development.apk`).
- **Kamera spec:** felbontás, max FPS, autofókusz megléte (pl. „12 MP, 30 fps,
  AF").
- **Fényviszonyok:** beltéri nappali / beltéri mesterséges / gyenge fény /
  kültéri napos.
- **Gitár:** akusztikus / elektromos, és a gitár elhelyezkedése a kamerához
  képest.
- **Mért érték:** numerikus érték, ahol van (pl. „28 fps", „p50 latency 45 ms").
- **Megjegyzés:** szabad szöveges, max 200 karakter.

### 1.3 Mikor „done"

A mátrix akkor tekinthető **lezártnak**, ha az alábbi 5 kötelező cella
**PASS** minősítésű legalább 2 különböző Android eszközön:

1. Kameraengedély megadása → preview elindul → legalább 15 fps, nincs crash
2. Kézi kalibráció (4 sarokpont) → a geometria érvényes, a kalibrációs ablak
   ≤ 30 másodperc
3. Hand tracking (jobb kéz) → landmark confidence ≥ 0.6, legalább 10 fps
4. 5 perces folyamatos session → nincs frame-drop kaszkád, nincs thermal
   throttle miatti leállás, audio scoring változatlan
5. App háttérbe küldése futó kamera mellett → kamera leáll, audio pausol,
   visszatéréskor mindkettő újraengedélyezhető

A többi cella **PARTIAL** vagy **FAIL** is lehet — azokat a tesztelő
dokumentálja, és a következő kör tervét ez alapján frissíti.

---

## 2. Mátrix

### 2.1 Kamera alapfunkciók

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Kameraengedély első kérése — a dialog megjelenik, „Allow" → preview indul | Preview FPS, indítási idő | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Kameraengedély „Deny" → `blockedByPermission` státusz, nincs crash | Capability státusz | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Kameraengedély „Deny & don't ask again" → `permanentlyDenied`, setup-útmutató | UI fallback | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Preview elindul, a minőségjelző (blur/lighting) ≤ 3 mp alatt frissül | Quality assessor latency | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Gyenge fény → quality assessor `degraded` státusz, felhasználói cue | Quality státusz | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Kamera leáll route-leave esetén, a lifecycle guard dispose-ol | Frame stream státusz | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| App háttérbe → kamera azonnal leáll (ADR 0178 §3) | Camera state | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Visszatérés előtérbe → kamera újraeengedélyezhető, nem indul automatikusan | Camera state | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.2 Kézi kalibráció (ADR 0181)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Négy sarokpont kijelölése → gitárnyak-geometria érvényes | Kalibrációs idő, geometria validitás | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Újrakalibrálás más kameraállásból → az új geometria felülírja a régit | Geometria update | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Kalibráció nélküli hand tracking → `notObservable`, setup-javaslat (ADR 0179) | Capability státusz | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.3 Hand tracking (production)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Jobb kéz landmark detektálás → confidence ≥ 0.6 | Landmark confidence, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Bal kéz landmark detektálás → confidence ≥ 0.6 | Landmark confidence, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Mindkét kéz egyidejű követése → legalább 8 fps | FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Kéz eltűnik a frame-ből → `notObservable` ≤ 1 mp alatt | State transition latency | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Részleges takarás → landmark visibility mező frissül | Visibility flag | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.4 Pose tracking (production)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Váll landmark detektálás → confidence ≥ 0.7 | Landmark confidence, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Törzs landmark detektálás → confidence ≥ 0.7 | Landmark confidence, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Referencia-pose felvétele → a posture metric a kalibrált baseline-hoz képest számítódik | Metric érték | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.5 Audio-vision együttműködés (ADR 0182)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Audio + kamera egyidejű futása → audio scoring nem romlik (±1%) | Audio score | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| CPU-limitált eszközön a vision degradálódik, az audio nem (ADR 0182) | Audio score, vision FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Vision leáll → audio session folytatódik, nincs gap | Audio continuity | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Audio-vision sync offset ≤ 50 ms (legalább 3 párosított event) | Sync offset (ms) | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.6 Tartós session (thermal / soak)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 5 perc folyamatos hand tracking → nincs frame-drop kaszkád | FPS stabilitás, dropped-frame count | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| 15 perc folyamatos session → nincs thermal throttle miatti leállás | Thermal állapot, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Session eredménye → `VisionSessionResult` aggregátum mentése, raw frame nélkül (ADR 0183) | Persistence tartalom | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### 2.7 Experimental (csak `visionExperimentalFineFretEnabled` flag mögött)

| Teszteset | Mérendő | Eszköz | Android | Kamera | Státusz | Felelős | Mért érték / Megjegyzés |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Automatikus geometria-detektálás → felajánlja a kalibrációt, de nem írja felül a manualt (ADR 0181) | Detektálási idő, pontosság | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Fine fret tracking → exact fret position confidence ≥ 0.8 | Landmark confidence, FPS | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| Flag OFF → experimental metric nem készül, a production metric változatlan | Metric lista | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

---

## 3. Eszközlista — tervezett

| Eszköz | Android verzió | Kamera | Prioritás |
| --- | --- | --- | --- |
| **Pixel 6a** | 14 (API 34) | 12.2 MP, 30 fps, AF | Kötelező (elsődleges teszteszköz) |
| **Pixel 7** | 14 (API 34) | 50 MP, 30 fps, AF | Kötelező |
| **Samsung Galaxy A54** | 14 (API 34) | 50 MP, 30 fps, AF | Ajánlott (középkategóriás) |
| **Xiaomi Redmi Note 12** | 13 (API 33) | 48 MP, 30 fps, AF | Ajánlott (olcsó, nagy piaci részesedés) |
| **Samsung Galaxy S23** | 14 (API 34) | 50 MP, 30 fps, AF | Opcionális (csúcskategóriás) |
| **Pixel 4a** | 13 (API 33) | 12.2 MP, 30 fps, AF | Opcionális (régebbi, limitált CPU) |
