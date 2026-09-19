# Tanítás, grouped holdout és eszköz-mérés — repro-szerződés (E14-R20 / E14-R22)

- **ADR:** [0536](../adr/0536-model-bound-calibration-artefact-and-selective-prediction.md) §D7
- **Állapot:** **BLOCKED (mérés)** — ez a dokumentum a *hogyan*, nem az
  *eredmény*. Ebben a konténerben nincs numpy/TF, nincs dataset, nincs
  Android eszköz; egyetlen szám sem született itt.

## 1. A pontos CI-diszpécsek

```bash
# Strum-sáv (ml/honest_eval.py::SECTIONS)
gh workflow run ml-train.yml -f sections="calib"
gh workflow run ml-train.yml -f sections="threeway logo bootstrap seeds"

# Chord-sáv (workflow_dispatch, ÉS automatikus push a main-re, ha ml/chords/** változik)
gh workflow run chord-train.yml
```

Az `ml-train.yml` egyetlen bemenete a `sections` — a `SECTIONS` szótár
kulcsai: `threeway`, `logo`, `logo_aug`, `threeway_aug`, `bootstrap`,
`seeds`, `calib`, `noreject_fast`, `noreject`. **Új mérés = új section az
`ml/honest_eval.py`-ban, nem új script** (a `tools/**` és a `.github/**`
tiltott zóna, a CLI-belépési pontok nem bővülnek).

A `calib` section az E14-R21 óta **artefaktumot is kiír**:
`ml/artifacts/strum_crnn_live_3c.calibration.json`
(`emit_calibration_artefact`). A workflow artefaktum-csomagjából kell
kiemelni; az appba landolása KÜLÖN, reviewzott lépés (másolás
`assets/ml/`-be **és** egy `pubspec.yaml` asset-sor).

## 2. Mit jelent nálunk a „grouped holdout”

A `lib/features/live/domain/evaluation/recognition_split.dart` négy
csoportkulcsot ismer: **player, device, guitar, room**. A szabály (ADR 0509
D1/D2): egy fold eval-oldalán egyetlen csoportérték van, és ugyanaz az érték
a train-oldalon **nem fordulhat elő**; a hiányzó csoportkulcs **tipizált hiba**
(`missingGroupKey`), nem „unknown” gyűjtő — egy `unknown` bucket pontosan azt
a szivárgást hozná vissza, ami ellen a split készült. A `LeakageDetector`
minden foldon lefut, akkor is, ha a fold építése elvileg nem szivároghat.

A korpusz-oldali ugyanez: `ChordCorpusManifest.buildFolds(strategy)` — a
korpusz-manifest tételeit `RecognitionCase`-ekké vetíti, és **ugyanazt** a
shipped buildert/detektort hajtja meg (nem egy második implementációt).

## 3. Amit a mai korpusz NEM tud (a §7.1 hiánya)

A Ch14 §7.1 minimum: 8 gitáros · 6 telefonmodell · 4 gitár · pick és finger ·
quiet/medium/loud · ≥4 szoba és több távolság · 24 kiegyensúlyozott maj/min
osztály · hard-negatív audio · player/device/guitar grouped holdout.

Mért állapot:

| Korpusz | Amit ad | Amit NEM ad |
|---|---|---|
| Klangio (82 felvétel) | 3 gitáros, egy rögzítési elrendezés | device/guitar/room variancia → **device- és guitar-szerinti grouped holdout ma nem is definiálható**, csak `leaveOnePlayerOut` értelmes (3 fold) |
| GuitarSet (`chord-train.yml`) | valódi gitár, valódi akkordcímke, gitáros-szintű LOGO | telefon-mikrofon, szoba/távolság, capo, pick/finger |

**Ezért nem született „grouped holdout” section az `ml/honest_eval.py`-ban:**
a `logo` (leave-one-guitarist-out) már megvan, device/guitar szerinti fold
pedig olyan metaadatot igényelne, ami egyik elérhető korpuszban sincs. Egy
ilyen section ma csak látszat-mérést adna.

## 4. Amit a FELHASZNÁLÓNAK kell rögzítenie

Felvételenként (a
[`evaluation/recognition/chord_corpus_manifest_schema.json`](../../evaluation/recognition/chord_corpus_manifest_schema.json)
kötelező mezői, lásd [chord-corpus-plan.md](chord-corpus-plan.md)):

- `player` (≥8 különböző), `device` (≥6 telefonmodell), `guitar` (≥4),
  `room` (≥4), `distanceCm` (több érték), `pickStyle`, `loudness`, `capo`,
  `voicing`, `label`, `tempoBpm`, `durationMs`;
- hard-negatív felvételek (`hardNegativeCategory`, a
  `evaluation/recognition/negative_taxonomy.json` kategóriáival),
  `label: "noChord"`;
- **nyers audió a repóba SOSEM kerül** (ADR 0354 D1) — csak a manifest és a
  `corpusSha256`.

## 5. E14-R22: eszköz-mérés (mobil perf-kapu)

Itt nem mérhető: nincs Android eszköz, nincs GPU, a Dart inferencia-út nem
kvantált, és a perf-budget rekord `tool/benchmarks/**`-ben él (tiltott zóna).
Amit a felhasználónak rögzítenie kell egy APK-futásból, low/mid/high tier
telefononként: verdict latency **p50 és p95** (ms), memória-csúcs (MB),
thermal throttling belépési idő, és hogy melyik modell-ág futott
(`RecognitionRuntimeInfo`). A kapu-oldali sorok (`latencyP50Ms`,
`latencyP95Ms`) már léteznek a
[release-gate-stages.md](release-gate-stages.md) szerinti Alpha sorokban —
hiányzó mérés esetén a kapu **FAIL**, nem „nincs adat = PASS”.
