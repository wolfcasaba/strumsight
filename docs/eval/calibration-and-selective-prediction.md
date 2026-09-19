# Konfidencia-kalibráció és selective prediction (E14-R21 / E14-R32)

- **ADR:** [0536](../adr/0536-model-bound-calibration-artefact-and-selective-prediction.md) (strum),
  [0540](../adr/0540-chord-calibration-open-set-and-selective-prediction.md) (chord)
- **Állapot:** a **mechanizmus** kész és tesztelt; **egyetlen mért artefaktum
  sincs a fán**, ezért `StrumPrediction.calibratedConfidence` és
  `ChordPrediction.calibratedConfidence` továbbra is `null`.

## 1. Mi az artefaktum

Egy JSON fájl, sémája:
[`evaluation/recognition/calibration_artefact_schema.json`](../../evaluation/recognition/calibration_artefact_schema.json).
Kötelező mezői: `schemaVersion`, `artefactVersion`, `band`
(`strum` \| `chord`), `model.modelId` + `model.modelSha256`, a teljes
`provenance` blokk (`corpusId`, `corpusSha256`, `foldId`, `sampling`,
`observationCount`, `fittedAtCommit`, `producedBy`) és a `mapping`
(`identity` vagy monoton `piecewiseLinear`). A chord-sávban opcionálisan
`perClassMappings` is lehet, `"<root>:<quality>"` kulccsal (pl. `A:min`).

Parser + validátor:
`lib/features/live/domain/evaluation/confidence_calibration_profile.dart`.
Betöltő (injektált olvasóval, `dart:io`/`rootBundle` nélkül):
`lib/features/live/data/evaluation/calibration_artefact_loader.dart`.

Az app-oldali útvonal, ha egyszer lesz artefaktum:
`assets/ml/<modelId>.calibration.json` — **és egy `pubspec.yaml` asset-sor
is kell hozzá** (az assetek fájlonként vannak felsorolva). Ez a sor ma
szándékosan nincs meg: nincs mit felvenni.

## 2. Miért NEM kerül be a mai Dart knot-lista

`lib/features/live/engine/ml/live_crnn_classifier.dart::calibrate` tartalmaz
egy `0,50→0,55 … 1,00→0,87` piecewise-lineáris leképezést. A saját forrása —
`ml/honest_eval.py::section_calib` docstringje — kimondja, hogy ezt **ugyanazon
a foldon fittelték, amelyen az accuracy-t jelentették** (in-sample). Egy
in-sample leképezés nem korlátozza egy nem látott strum kockázatát, tehát
artefaktumként előléptetve mért állításnak látszó, nem mért számot adna.

A formátum **le tudja írni** ezt az állapotot (`sampling: "inSample"`), a
`ConfidenceCalibrationResolver` viszont **nem szolgálja ki**:
`CalibrationUnavailableReason.inSampleArtefact`. A mai `Strum.confidence`
útja változatlan — ez a kör egyetlen DSP/ML küszöböt sem írt át.

## 3. Fail-closed szabályok

| Helyzet | Válasz |
|---|---|
| nincs artefaktum | `null` + `noArtefact` (ez a mai állapot) |
| más `modelId`/`modelSha256` | `null` + `modelMismatch` |
| másik sáv artefaktuma | `null` + `bandMismatch` |
| `sampling: inSample` | `null` + `inSampleArtefact` |
| hibás JSON / hiányzó provenance | `CalibrationLoadStatus.invalid` + tipizált hiba a `CalibrationLoadResult`-ben (nem néma no-op) |

## 4. Selective prediction

`lib/features/live/domain/evaluation/selective_prediction.dart`:

- `SelectivePredictionPolicy.acceptAll()` — a **szállított** alapérték,
  identitás a mai viselkedésen (semmit nem hallgattat el);
- `SelectivePredictionPolicy.abstainBelow(t)` — a küszöb a **kalibrált**
  konfidencián van; `null` kalibráció esetén **abstain**, sosem visszaesés a
  nyers score-ra;
- `riskCoverageCurve(...)` — determinisztikus risk–coverage görbe (a
  kalibrálatlan megfigyelések a nevezőben maradnak);
- `selectCoverageMaximisingPolicy(..., targetAcceptedAccuracy: 0.92)` — a
  legnagyobb lefedettségű küszöb, amely még tartja az ígért accepted
  accuracy-t; ha egyik sem tartja, **`null`**, nem „a legkevésbé rossz”.

## 5. Mi hiányzik a méréshez (NEEDS-MEASUREMENT)

1. **Strum:** egy held-out fold ECE/Brier-je kalibrálás előtt és után,
   subgroup (player/device) bontással → `ml-train.yml -f sections="calib"`
   (a section már **kiírja** az artefaktumot, lásd
   [training-and-holdout-repro.md](training-and-holdout-repro.md)).
2. **Chord:** ugyanez a `chord-train.yml` GuitarSet-útján, plusz per-class
   (root+quality) támogatottság — ehhez a §7.1 korpusz kell
   ([chord-corpus-plan.md](chord-corpus-plan.md)).
3. **Az abstain-küszöb értéke** (a §7.2 „92% accepted accuracy melletti
   maximális coverage”) csak a fenti görbéből olvasható ki. Amíg nincs görbe,
   a szállított policy `acceptAll`.
4. **Ismert korlát:** `_fit_piecewise` empirikus bucket-pontossága nem
   garantáltan monoton; a nem monoton fitet az emitter **elutasítja**
   (`artefact_error`), izotonikus regresszió a következő mérési kör dolga.
