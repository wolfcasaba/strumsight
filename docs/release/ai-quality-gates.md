# AI-quality gates — capability ↔ bizonyíték mátrix

**Kör:** `E12-R16` (Chapter 12, Kör 16). **Normatív forrás:**
[ADR 0477](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md).
Ez a fájl **bizonyíték-mátrix**: melyik capabilityhez milyen AI/ML bizonyíték
tartozik, milyen metrikán, melyik modellel szemben. **NEM GA-lista** — a
`ga_scope` egyetlen igazsága [`docs/testing/device-matrix.yaml`](../testing/device-matrix.yaml)
`capabilities[].ga_scope` mezője (ADR 0477 D1). Ez a dokumentum a `ga_scope`
értéket sehol nem sorolja fel újra, és az összesítő (`tool/release/build_ai_report.py`)
sem olvassa innen — ha egy sor itt olyan capabilityt nevez meg, ami a
device-mátrixban nem szerepel, az összesítő nem-nulla kóddal lép ki (D1).

## 1. Hogyan olvassa ezt a fájlt az összesítő

A §3 elején és végén álló, `ai-quality-gates:begin` / `ai-quality-gates:end`
nevű HTML-komment jelölőpár közötti Markdown-táblázat a GÉPILEG olvasott
rész; minden más szöveg ebben a fájlban dokumentáció, az összesítő nem
elemzi. A táblázat oszlopai:

| Oszlop | Jelentés |
|---|---|
| `capability` | egy `docs/testing/device-matrix.yaml` `capabilities[].id` érték |
| `metric` | a metrika neve (szabad szöveg, a bizonyíték-dokumentumban is ez a kulcs) |
| `direction` | `lowerIsBetter` / `higherIsBetter` — a `tool/compare_benchmarks.py` `DIRECTIONS` halmazából (ADR 0477 D4) |
| `model` | `none` (tisztán DSP, modell nélkül — ADR 0477 D5), `model:<filename>` (`assets/ml/model_manifest.json` `models[].filename`), vagy `vision:<model_id>` (`vision_models[].model_id`) |
| `evidence_path` | repó-relatív útvonal egy JSON bizonyíték-dokumentumhoz, amely `corpusId`, `buildSha`, `modelId`, `modelVersion`, `baselineValue`, `candidateValue` mezőket hordoz (ADR 0477 D5) |

Egy bizonyíték-dokumentum JSON objektum, NEM a `docs/eval/**` alatti prózai
Markdown-riportok formátuma — azok emberi olvasásra készültek, gépi
elemzésre nem. Ha egy `evidence_path` egy ilyen prózai `.md` fájlra mutat
(ma mindkét GA-scope AI-capability erre kényszerül, lásd §3), az összesítő
`json.loads()`-a hibázik, és a capability `missing` státusszal jelenik meg —
ez a SZÁNDÉKOS, mért mai állapot (ADR 0477 §"Következmények"), nem hiba ebben
a mátrixban.

## 2. A modell-verzió egyeztetés

Egy bizonyíték-dokumentum saját `modelId`/`modelVersion` mezőt hordoz — azt
állítja, milyen modellel szemben mérték a `candidateValue`-t. Az összesítő ezt
egyezteti a mátrix `model` oszlopa által megnevezett modellel ÉS
`assets/ml/model_manifest.json` aktuális verziójával; bármelyik eltérés
release-blokkoló találatot ad (`findings[]`, kilépés 1) — a bizonyíték nem
maradhat csendben egy már lecserélt modellváltozathoz kötve.

## 3. A mátrix

<!-- ai-quality-gates:begin -->
| capability | metric | direction | model | evidence_path |
|---|---|---|---|---|
| audio_analysis_core | chord_accuracy | higherIsBetter | none | docs/eval/real-audio-dsp-baseline.md |
| audio_analysis_core | onset_f1_50ms | higherIsBetter | none | docs/eval/real-audio-dsp-baseline.md |
| live_and_tuner | direction_accuracy | higherIsBetter | model:strum_crnn_live_3c.bin | docs/eval/recognition-release-guard.md |
| computer_vision | hand_landmark_detection_rate | higherIsBetter | vision:hand_landmarker | docs/eval/vision/hand_landmarker.md |
| computer_vision | pose_landmark_detection_rate | higherIsBetter | vision:pose_landmarker | docs/eval/vision/pose_landmarker.md |
<!-- ai-quality-gates:end -->

**Miért éppen ezek a sorok:**

- **`audio_analysis_core`** — az akkordfelismerés a változatlan, alapértelmezett
  `const ClipAnalyzer()`-t futtatja (nincs ML-modell az útban), ezért
  `model: none`. A két metrika (`chord_accuracy`, `onset_f1_50ms`) a
  [`real-audio-dsp-baseline.md`](../eval/real-audio-dsp-baseline.md) „Eredmény"
  szakaszának mért számai (67,069% akkord, 67,391% onset F1 @ 50 ms).
- **`live_and_tuner`** — a `direction_accuracy` (80,7%) a live 3-osztályos
  CRNN (`strum_crnn_live_3c.bin`) held-out eval fold mérése, a
  [`recognition-release-guard.md`](../eval/recognition-release-guard.md)
  „Status" szakasza szerint.
- **`computer_vision`** (`ga_scope: false` ma) — a két sor az
  `assets/ml/model_manifest.json` `vision_models[].evaluation_report` mezőjéből
  jön (`hand_landmarker.md` / `pose_landmarker.md`, mindkettő `status: deferred`,
  a fájlok ma nem léteznek). Mivel `ga_scope: false`, ez sosem blokkol — a
  sorok csak azt dokumentálják, milyen bizonyíték kellene, ha a vision valaha
  GA-scope-ba kerülne (ADR 0477 D3).

**Amit ez a mátrix szándékosan NEM sorol fel:**

- **`ai_tutor`** (`ga_scope: false` ma) — a Tutor-evaluation már saját,
  külön merge-gate ([ADR 0177](../adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md),
  `.github/workflows/tutor-eval.yml`), négy metrikával (schema-validity,
  action-validity, groundedness, safety-coverage), amelyek szerkezete NEM a
  baseline/candidate regresszió-sémára illeszkedik, amit ez a mátrix elvár.
  Ez a kör (E12-R16) a Tutor-kaput nem cseréli le és nem duplikálja
  (ADR 0477, kapcsolódó `0177`) — ha az `ai_tutor` valaha `ga_scope: true`-vá
  válik, egy külön kör dolga eldönteni, hogyan illeszkedik ide.
- **`offline_ai`** (`ga_scope: false` ma, Epic 10 `hold`-on) — az epic nem
  indult el, nincs mért bizonyíték, amire egy sort lehetne alapozni; egy
  kitalált metrika-sor pontosan az a hiba lenne, amit a kör brief-je (§9)
  tilt.

<!-- Kitalált riport-forma bevezetése TILOS (ADR 0477 §"Következmények"): ez a
mátrix csak MÉRT dokumentumokra és a model_manifest.json-ban már deklarált
evaluation_report útvonalakra hivatkozik. -->
