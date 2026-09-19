# E14-R21 — Strum konfidencia-kalibráció és selective prediction

- **Státusz:** LESZÁLLÍTVA (mechanizmus) / **PARTIAL** (mérés hiányzik)
- **ADR:** [`0536`](../adr/0536-model-bound-calibration-artefact-and-selective-prediction.md)
- **Csomag:** PKG-B (mérés / kalibráció / open-set / release-kapuk)
- **Készült:** 2026-09-09, Epic 14 befejező hullám, 1. hullám
- **Doksi:** [`docs/eval/calibration-and-selective-prediction.md`](../eval/calibration-and-selective-prediction.md)

## 1. Cél

Legyen **egyetlen, modellhez kötött** helye annak, ahonnan kalibrált
konfidencia származhat, és legyen egy tiszta függvényes selective-prediction
politika a tetején — úgy, hogy **a mai viselkedés bitre változatlan marad**,
amíg mért artefaktum nincs.

## 2. Mért kiindulóállapot

- `StrumPrediction.calibratedConfidence` = `null` (ADR 0505 D2).
- `live_crnn_classifier.dart::calibrate` piecewise-lineáris knot-listája megy
  a `Strum.confidence`-be; a forrása (`ml/honest_eval.py::section_calib`
  docstring) kimondja, hogy **in-sample** fit.
- A knot-lista **nincs** a modellhez (id + sha256) kötve.

## 3. Scope

BENNE: artefaktum-séma + parser/validátor + betöltő + resolver; selective
prediction (policy, risk–coverage görbe, coverage-maximalizáló szelektor);
az `ml/honest_eval.py::section_calib` artefaktum-kiírása; doksi + ADR.

KÍVÜL (szándékosan): a `live_crnn_classifier.dart` knotjai (PKG-A zóna, és
ADR 0536 D2 szerint nem is léptethetők elő); a `StrumPrediction` bekötése
(PKG-A, 2. hullám); bármely küszöb behangolása.

## 4. Fájlok

Új:
- `lib/features/live/domain/evaluation/confidence_calibration_profile.dart`
- `lib/features/live/domain/evaluation/selective_prediction.dart`
- `lib/features/live/data/evaluation/calibration_artefact_loader.dart`
- `evaluation/recognition/calibration_artefact_schema.json`
- `test/features/live/evaluation/confidence_calibration_profile_test.dart`
- `test/features/live/evaluation/selective_prediction_test.dart`
- `test/features/live/evaluation/calibration_artefact_loader_test.dart`
- `test/property/calibration_monotonicity_property_test.dart`
- `docs/eval/calibration-and-selective-prediction.md`
- `docs/eval/training-and-holdout-repro.md`

Módosított:
- `ml/honest_eval.py` (`emit_calibration_artefact` + a `calib` section
  kiírási lépése)

## 5. Kockázatok

- A `_fit_piecewise` empirikus bucket-pontossága nem garantáltan monoton; a
  nem monoton fitet az emitter **elutasítja** (`artefact_error` a
  `honest_results.json`-ben). Izotonikus regresszió: következő mérési kör.
- A `ml/**` ebben a konténerben **nem futtatható** (nincs numpy/TF); a Python
  változás szintaktikailag ellenőrzött (`py_compile`), viselkedésében nem.

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | Artefaktum nélkül a kalibrált konfidencia `null`, megnevezett okkal | **PINNED-BY-TEST** (`confidence_calibration_profile_test`, `calibration_artefact_loader_test`) |
| 2 | A leképezés monoton, `0..1`-ben marad, clamp-el, determinisztikus | **PINNED-BY-TEST** (+ randomizált property) |
| 3 | Rossz `modelId`/sha → fail-closed, nem néma fallback | **PINNED-BY-TEST** |
| 4 | In-sample artefaktum ábrázolható, de nem kiszolgálható | **PINNED-BY-TEST** |
| 5 | Hibás artefaktum tipizált hibát visz ki, nem no-opot | **PINNED-BY-TEST** |
| 6 | Selective policy: `null` kalibráció → abstain; alapérték = identitás | **PINNED-BY-TEST** |
| 7 | Risk–coverage determinizmus és monotonitás; szelektor `null`-ja | **PINNED-BY-TEST** (+ property) |
| 8 | ECE/Brier javulás, 92%-os accepted accuracy melletti coverage | **NEEDS-MEASUREMENT** (`ml-train.yml -f sections="calib"`) |
| 9 | Subgroup (player/device) kalibrációs eltérés | **NEEDS-MEASUREMENT** (a §7.1 korpusz hiányzik) |

## 7. Verifikáció

Lokálisan **nem futtatható** (nincs Dart SDK ezen a boxon). A mérce a
session végi `full-gate.yml` + `build-apk.yml`. Ez a brief a megírt
teszt-cellákat sorolja, sikeres futást **nem** állít (Ch14 §9/9).

## 10. Handoff

- **PKG-A (2. hullám):** a `StrumPrediction` építésekor hívja a
  `ConfidenceCalibrationResolver.calibrate(...)`-t, és a `null` kimenetet
  hagyja `null`-ként a predikcióban; az `unavailableReason` a
  `RecognitionRuntimeInfo`-ba való (PKG-E).
- **PKG-E:** a `CalibrationLoadResult` `invalid` ága kapjon látható
  `fallbackReason`-t.
- **Orchestrátor:** egy jövőbeli artefaktum `pubspec.yaml` asset-sort igényel
  (`- assets/ml/strum_crnn_live_3c.calibration.json`) — ma nincs mit felvenni.
