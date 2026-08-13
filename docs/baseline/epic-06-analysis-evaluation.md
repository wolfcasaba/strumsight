# Epic 06 — Analysis evaluation baseline (E06-R29, ADR 0249)

**Mérés dátuma:** 2026-08-13. **Parancs:** `dart run tool/audio_analysis_evaluate.dart`.
Manifest: `evaluation/analysis/fixtures/ci_manifest.json` (13 szintetikus eset,
teljes tartalom a fájlban). Környezet: Linux `6.17.0-1019-oracle`, aarch64.

Ez a szám **kizárólag a harness/parser/regressziós szerződést** méri — nem
valódi modellpontosságot (ADR 0249 §Döntés 3). A `ci_manifest.json` minden
esetének `detected` mezője kézzel írt, determinisztikus perturbációja az
`expected` mezőnek; nincs valós vagy szintetizált audio a mérés mögött. A
`docs/manual-testing/analysis-eval-matrix.md` PENDING sorait ez a szám nem
zárja le.

## Determinizmus

A `tool/audio_analysis_evaluate.dart` ugyanazon manifest mellett kétszer,
egymást követő futtatásban **bájtazonos** stdout-ot adott (`diff` üres kimenet
a két futás JSON-ja között). Az alábbi kimenet a második futásból származik.

## Teljes riport

```json
{
  "manifestSchemaVersion": "1.0",
  "caseCount": 13,
  "overall": {
    "caseCount": 13,
    "onset": {
      "precision": 0.9361702127659575,
      "recall": 0.8979591836734694,
      "f1": 0.9166666666666666,
      "truePositives": 44,
      "falsePositives": 3,
      "falseNegatives": 5
    },
    "timestampMaeMs": 3.977272727272727,
    "chordFrameAccuracy": 0.9680088251516823,
    "chordSegmentAccuracy": 0.9375,
    "strumDirectionAccuracy": 0.9285714285714286,
    "bpmErrorPercent": 0.7651515151515151,
    "beatAlignmentAccuracy": 0.8928571428571429,
    "pitchCentsErrorMean": 4.510224936967485,
    "confidenceCalibration": {
      "expectedCalibrationError": 0.2796428571428572,
      "insufficientData": true,
      "observationCount": 28,
      "tableVersion": "identity.v1"
    }
  }
}
```

A `slices` tömb (13 elem: `tempoBand:*` × 4, `signalQualityTier:*` × 4,
`mode:*` × 3) és minden reliability-bin a teljes futtatott kimenetben szerepel;
a fenti kivonat a regressziós kapu és a kalibráció-döntés szempontjából
releváns `overall` blokk. A teljes, csonkítatlan JSON reprodukálható:

```bash
dart run tool/audio_analysis_evaluate.dart
```

## Regressziós referenciaszámok (ADR 0249 §Döntés 5)

A `test/tooling/analysis_evaluation_regression_test.dart` az alábbi négy
számhoz mér, dokumentált tolerával:

| Metrika | Baseline | Tolerancia |
|---|---|---|
| `overall.onset.f1` | `0.9166666666666666` | legfeljebb 2 százalékpont ROMLÁS |
| `overall.chordSegmentAccuracy` | `0.9375` | legfeljebb 2 százalékpont ROMLÁS |
| `overall.timestampMaeMs` | `3.977272727272727` | legfeljebb 10% ROMLÁS (relatív, nagyobb rosszabb) |
| `overall.bpmErrorPercent` | `0.7651515151515151` | legfeljebb 10% ROMLÁS (relatív, nagyobb rosszabb) |

Javulás (a metrika jobb, mint a baseline) sosem bukik. A küszöb **gyengítése**
ember által engedélyezett `GOV-xx` kör, nem implementer- vagy CI-módosítás
(ADR 0249 §Döntés 5–6).

## Kalibráció

`confidenceCalibration.insufficientData: true` és `tableVersion:
"identity.v1"` a teljes riport minden szeletében — ez a **helyes, őszinte**
kimenet: a 13 szintetikus eset összesen 28 `confidenceObservations`-t ad
(minden bin messze a 30-as, az összes messze a 300-as minimum alatt, ADR 0249
§Döntés 4). A `CalibrationTable` addig `identity.v1` marad, amíg egy külön,
címkézett valós-audio dataset a küszöböt nem éri el (`GOV-xx`, lásd
`docs/manual-testing/analysis-eval-matrix.md` EVAL-06).

## H-GATEGUARD

A fenti szám CI-gate-ként **nem** aktív: a `.github/workflows/**` és a
`tool/ci/**` ebben a körben tiltott módosítási zóna. A teszt-oldali megfelelő
(`test/tooling/analysis_evaluation_regression_test.dart`) a merge-előtti,
helyi/CI `flutter test` futásban fut; a tényleges workflow-lépés bekötése egy
külön, ember által engedélyezett governance-kör feladata.
