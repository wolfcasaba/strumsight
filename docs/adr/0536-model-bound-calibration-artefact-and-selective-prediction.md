# ADR 0536 — Modellhez kötött kalibrációs artefaktum és selective prediction (strum)

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R21 · **Kapcsolódik:** ADR 0505 D2 (a `calibratedConfidence` null-by-design), ADR 0509 (metrika-szerződés), ADR 0511 (fail-closed kapu), ADR 0271 (UNKNOWN > CONFIDENTLY WRONG)

## Kontextus (mért)

- `lib/features/live/domain/recognition/strum_prediction.dart`:
  `calibratedConfidence` **`null`**, kommentben kimondva, hogy csak MÉRT
  kalibráció után kaphat értéket.
- `lib/features/live/engine/ml/live_crnn_classifier.dart::calibrate`
  ugyanakkor tartalmaz egy piecewise-lineáris knot-listát
  (`0,50→0,55 · 0,60→0,58 · 0,80→0,63 · 0,935→0,74 · 0,9825→0,86 · 1,00→0,87`),
  és ez megy ma a `Strum.confidence`-be.
- Ennek a knot-listának a forrása az `ml/honest_eval.py::section_calib`, amely
  a saját docstringjében rögzíti: a shipped knotokat **ugyanazon a foldon
  fittelték, amelyen az accuracy-t jelentették** — **in-sample**.
- Vagyis ma **két igazságforrás** van (`Strum.confidence` kalibrált,
  `StrumPrediction.calibratedConfidence` null), és egyik sincs **a modellhez
  (id + sha256) kötve**: egy súlycsere csendben elavulttá tenné a leképezést.

## Döntés

### D1 — Az artefaktum a kalibráció EGYETLEN belépési pontja

Kalibrált konfidencia kizárólag egy verziózott artefaktumból származhat
(`evaluation/recognition/calibration_artefact_schema.json`, parser:
`domain/evaluation/confidence_calibration_profile.dart`). Nincs kódba írt
knot-lista a domainben, és nincs implicit identitás-fallback: artefaktum
nélkül a válasz `null` + `CalibrationUnavailableReason.noArtefact`. **A fán
ma nincs artefaktum**, tehát `StrumPrediction.calibratedConfidence` marad
`null`. A `live_crnn_classifier.dart` egyetlen sora sem változott.

### D2 — A mai knot-lista NEM léptethető elő artefaktummá

Az in-sample fit nem korlátozza egy nem látott strum kockázatát. A formátum
**le tudja írni** (`provenance.sampling: "inSample"`), a resolver viszont
**nem szolgálja ki** (`inSampleArtefact`). Így az állapot dokumentálható
anélkül, hogy mért állításnak látszana. (A mai `Strum.confidence` út
változatlanul él — ez a kör nem UI- és nem DSP-kör.)

### D3 — Kötelező provenance, üres mező nélkül

`corpusId`, `corpusSha256`, `foldId`, `sampling`, `observationCount` (> 0),
`fittedAtCommit`, `producedBy` — mind kötelező és nem üres. Egy artefaktum,
amely nem tudja megmondani, melyik korpusz melyik foldján készült, nem
bizonyíték (ADR 0354 D2 precedens: `n = 0` séma-sértés, nem „a semmi
mérése”).

### D4 — Modell-kötés minden hívásnál, fail-closed

A resolver minden `calibrate()` híváskor összeveti az artefaktum
`modelId`+`modelSha256` párját a ténylegesen betöltött súlyokéval. Eltérés →
`null` + `modelMismatch`. Egyező id, más sha **eltérés** (a súlyok cseréltek
a kalibráció alatt).

### D5 — Monotonitás konstrukciós invariáns

A `piecewiseLinear` leképezés csak akkor jön létre, ha ≥2 knot van, minden
érték `0..1`-ben, a `raw` szigorúan nő és a `calibrated` nem csökken. A
tartományon kívül **clamp**, sosem extrapoláció (extrapolált farok = olyan
szám, amit egyetlen fold sem mért). Randomizált property:
`test/property/calibration_monotonicity_property_test.dart`.

### D6 — A betöltési hiba látható, nem néma

`CalibrationArtefactLoader` háromállapotú eredményt ad: `loaded` / `absent` /
`invalid`; az `invalid` **magával viszi a tipizált hibát**. A hívó köteles
felszínre vinni (a `RecognitionRuntimeInfo` fallback-ok a szánt nyelő,
PKG-E). Néma `try/catch` tilos (`docs/LESSONS.md` L619).

### D7 — A fit CI-ben történik, és onnan JÖN ki az artefaktum

`ml/honest_eval.py::section_calib` kibővült egy
`emit_calibration_artefact(...)` lépéssel: a VAL-on fittelt knotokat írja ki
`ml/artifacts/<modelId>.calibration.json`-ként, a modell tényleges sha256-ával
és a korpusz-cache tartalom-hashével. Diszpécs:
`gh workflow run ml-train.yml -f sections="calib"`. Bármely hiányzó bemenet
**kivétel**, nem gyengébb artefaktum. Az appba landolás külön, reviewzott
lépés (másolás `assets/ml/`-be **és** `pubspec.yaml` asset-sor).

### D8 — Selective prediction: küszöb a KALIBRÁLT konfidencián

`selective_prediction.dart`: a szállított alapérték
`SelectivePredictionPolicy.acceptAll()` — identitás a mai viselkedésen.
Bármely valódi policy `null` kalibráció esetén **abstain**
(`noCalibratedConfidence`), sosem esik vissza a nyers score-ra. A
risk–coverage görbe determinisztikus, a kalibrálatlan megfigyeléseket a
nevezőben tartja, és a coverage-maximalizáló szelektor **`null`**-t ad, ha
egyetlen küszöb sem tartja az ígért accepted accuracy-t.

## Ami MÉRVE van és ami NINCS

**Mérve (teszttel rögzítve):** a formátum-invariánsok (monotonitás, tartomány,
provenance-kötelezettség), a fail-closed ágak (`modelMismatch`,
`bandMismatch`, `inSampleArtefact`, `invalid`), a görbe determinizmusa és
monotonitása, a szelektor ígéret-tartása, a „degradált jel → nő az
abstention” irány.

**NINCS mérve (NEEDS-MEASUREMENT):** bármely valós ECE/Brier javulás; a
`0,92 accepted accuracy` melletti coverage konkrét értéke; a subgroup
(player/device) kalibrációs eltérés. Mindhez `ml-train.yml` futás és valós
held-out fold kell — lásd `docs/eval/calibration-and-selective-prediction.md`
és `docs/eval/training-and-holdout-repro.md`.

## Következmények

- A `StrumPrediction.calibratedConfidence` bekötése (a resolver hívása a
  predikció építésekor) **PKG-A 2. hullámos** feladata; ez a kör csak az
  értéket előállító típust szállítja.
- Egy jövőbeli artefaktum `pubspec.yaml` asset-sort igényel — a `pubspec.yaml`
  nem ennek a csomagnak a tulajdona, a javasolt patch a kör-jelentésben van.
