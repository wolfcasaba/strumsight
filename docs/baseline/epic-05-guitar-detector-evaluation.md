# Epic 5 — automatic guitar/neck detector evaluation (E05-R17)

- **Státusz:** kísérleti-only baseline; valós eszköz-mérés még nem történt
- **Scope:** csak az **értékelési keret** (harness + manual-kalibráció
  költségbecslés + detektorral való összevetés). A modell, a dataset és a
  production-kód **nem** a kör része (lásd a tiltott zónát).
- **Döntés-fogyasztó:** [ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)
- **Mérési eljárás:** [`ml/vision/evaluate_geometry_baseline.py`](../../ml/vision/evaluate_geometry_baseline.py)
  (`--self-test` belső, JSONL-bemenetű futtatás valós adaton)
- **Aktiváló kör mérése:** [`docs/manual-testing/vision-device-matrix.md`](../manual-testing/vision-device-matrix.md)
  §2.7 (PENDING sorok)

## 1. Miért fontos ez a dokumentum

A [ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)
Döntés 1 kimondja: a **manual kalibráció a production út** (ADR 0181),
és egy automatikus detektor legfeljebb a `visionExperimentalFineFretEnabled`
flag mögött élhet. A Döntés 2 rögzíti a számszerű átfordítási
küszöböket (mean anchor error ≤ 0.030 / p95 ≤ 0.050 / failure rate ≤ 0.05)
és a minimum eval-korpuszt (≥ 200 frame, ≥ 3 gitár, ≥ 2 fény, mindkét
kezesség). **Ez a dokumentum NEM módosítja ezeket a számokat** — csak
azt a kontextust adja meg, hogy a detektorral szemben támasztott küszöb
a manual út MÁR MÉRT költségeihez képest mennyire szigorú, és mely
számokat kell valós eszközön megmérni, hogy egy jövőbeli aktiváló kör
az átfordítást egyáltalán megvitathassa.

A mérés *most* azért nem történik meg, mert:

1. **Nincs consentelt adat.** A [`ml/vision/dataset_manifest.md`](../../ml/vision/dataset_manifest.md)
   minden kategóriája `PENDING_COLLECTION`.
2. **`AGENTS.md` §9** tiltja a traininget normál fejlesztési körben —
   csak külön előírással, ami a Kör 17-ben a consent-feloldáshoz van
   kötve (R17 §2).

## 2. Manuális kalibráció — idő- és hibaköltség (becslés)

A manual út a ma szállított R10/R11 UI: 4 sarokpont (nut + bridge)
megérintése a képernyőn, neck polygon ellenőrzése, majd a
`GuitarCalibration` widget commit. A költségek **becsült** értékek —
valós eszközön a §3 PENDING sorok mérik meg.

| Lépés | Becsült idő (s) | Becsült hibaforrás | Kontextus |
|---|---|---|---|
| Session megnyitása, kamera preview indul | 3–6 | first-frame init (M01) | a [`vision-camera-spike-runbook`](../manual-testing/vision-camera-spike-runbook.md) M01 sora |
| 4 sarokpont megérintése (nut + bridge × 2, vagy polygon) | 8–15 | ujj-pozíció pontatlansága, frame-szintű „mi a pontos pixel" kétértelműség | tipikus R11 UX-flow; a sarokpont-koordináta a normalizált kamera-tér `[0,1]×[0,1]`-jében rögzül |
| Polygon ellenőrzés, esetleges újrapontosítás | 4–8 | a felhasználó nem veszi észre a driftet (a polygon „majdnem jó") | a R10 widget vizuális visszajelzése |
| Commit + persist | < 1 | nincs érdemi hiba | `lib/features/vision/calibration/` |
| **Teljes (P50)** | **~17 mp** | — | — |
| **Teljes (P95, tapasztalatlan felhasználó)** | **~30 mp** | — | a device-mátrix §2.2 sora (kézi kalibráció) ezt a küszöböt tartja |
| **Becsült anchor-anchor hiba a manual úton** | **< 0.01** (normalizált) | maga a user a ground truth (R10 `GuitarCalibration`), így a tracker viszonyítási pontja | ha a tracker driftje > 0.05 (`degradedDriftBound`), a R16 `CalibrationLossMachine` átvált `degraded`-be; ha > 0.10 (`lostDriftBound`), `lost` |

A manual út **nem nulla hibájú** — a sarokpont-kijelölés maga
tartalmaz ±1–3 pixeles bizonytalanságot, ami a tipikus 1080×1920
kamera-térben normalizálva ~0.005–0.015 közé esik. Ez az érték a
detektor-küszöb (0.030 mean) **harmada** — vagyis a detektornak nem
csak „jónak" kell lennie, hanem **a manual bizonytalanságánál
szigorúan jobbnak**, hogy egyáltalán megvitathassa a felajánlás
minőségét.

## 3. Detektor-kimenetek összevetése — a harness-szel mérve

A [`ml/vision/README.md`](../../ml/vision/README.md) részletesen
tárgyalja a három reális kimeneti formátumot (bbox / line /
segmentation). Itt csak a harness-szel való mérhetőség szempontjából
foglaljuk össze:

| Kimenet | Anchor-ek | Mean anchor error várható tartomány | Megjegyzés |
|---|---|---|---|
| **Bounding box** | bbox sarok → anchor proxy | 0.04–0.08 (jellemzően a küszöb felett) | a sarokpontok nem konzisztensek a valós anchor-pontokkal |
| **Line** (nyak-tengely) | nut + bridge végpontok | 0.015–0.035 (küszöb körül) | közvetlen 1-1 leképezés a manual anchorokra |
| **Segmentation** | polygon csúcsok | 0.025–0.06 (a polygon-pontosság függvénye) | a csúcsokból származtatott anchor proxy-szerű |

A `decision()` függvény az [ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)
Döntés 2 küszöbjeire épít, és a brief §6.2 szerinti
boundary-conventriont követi (boundary a szigorúbb / ≤ oldalhoz
tartozik). A `--self-test` kilenc belső mintán bizonyítja a
számítást.

## 4. PENDING mérendő számok — a device-mátrix §2.7-ben

A [`docs/manual-testing/vision-device-matrix.md`](../manual-testing/vision-device-matrix.md)
§2.7 már tartalmazza a PENDING sorokat. Ezek a mérendő számok, amelyek
kitöltése az aktiváló kör feladata (ÉS a §2.2 manual-kalibráció P95
sorának megmérése is, hogy a fenti becslés helyébe mért érték
kerüljön):

| Mérési sor | Mit mér | Miért fontos |
|---|---|---|
| §2.7 row 1 — „Automatikus geometria-detektor felajánlja a kalibrációt" | detektálási idő (ms) + pontosság (mean anchor error) | a detektor sebessége ÉS minősége; mindkettő a `decision()` bemenete |
| §2.7 row 2 — Fine fret tracking → confidence ≥ 0.8 | landmark confidence + FPS | a finom-fret prefill minősége |
| §2.7 row 3 — Flag OFF → experimental metric nem készül, production metric változatlan | metric lista (melyek készülnek, melyek nem) | a flag izolációja; a production út nem változhat |
| §2.2 — Manuális kalibráció P95 ideje | másodperc, valós eszközön | a §2 tábla becslésének validálása; ha a mért P95 < 30 mp, a detektor küszöbe (0.030) „méltányos"; ha > 30 mp, a detektor küszöbe szigorúbb lehet (de ezt csak ADR-kiegészítéssel, ADR 0187 §Döntés 5 mintája) |

Egyik PENDING cella sem „performance claim" — kizárólag mért érték
helye, a fenti táblázatok kontextusával.

## 5. Ideiglenes következtetés

A detektor kísérleti útja **most** (E05-R17, 2026-08-07) az alábbi
állapotban van:

- A döntési keret (ADR 0187 Döntés 1–5) **rögzített és zárt**.
- A kiértékelő harness (`ml/vision/evaluate_geometry_baseline.py`)
  **reprodukálható** és a `--self-test` 9/9 PASS.
- A dataset-manifest **struktúrája kész** (12 kategória, consent-séma,
  tiltott források listája), de **nincs adat** — minden kategória
  `PENDING_COLLECTION`.
- A detektor **nem** készült el; a természeténél fogva adat- és
  training-igényes, és a `AGENTS.md` §9 mindkettőt kizárja a normál
  körből.

Ez a baseline **nem** nyit meg semmilyen production utat. Aktiváló
kör csak a fenti PENDING mérések kitöltése + a tiltott zóna
feloldása (consent + AGENTS.md §9 mentesítés) után jöhet szóba —
és csak akkor, ha a mért értékek a §4 küszöb-sorhoz képest a
detektor javára szólnak.

## 6. Hivatkozások

- [ADR 0187](../adr/0187-vision-automatic-guitar-geometry-detection.md)
  — kísérleti státusz, számszerű küszöbök, hamis-geometria kockázat;
- [ADR 0181](../adr/0181-vision-manual-calibration-fallback.md) —
  a manual kalibráció a production út;
- [ADR 0179](../adr/0179-vision-capability-aware-feedback.md) —
  `notObservable` > hamis ítélet;
- [ADR 0178](../adr/0178-vision-privacy-by-default.md) —
  kizárólag on-device feldolgozás;
- [`ml/vision/README.md`](../../ml/vision/README.md) — kísérleti út
  vázlata, három detektor-kimenet összevetése;
- [`ml/vision/dataset_manifest.md`](../../ml/vision/dataset_manifest.md)
  — kategóriák, consent-séma, tiltott források;
- [`docs/manual-testing/vision-device-matrix.md`](../manual-testing/vision-device-matrix.md)
  §2.7 — a PENDING mérések helye.
