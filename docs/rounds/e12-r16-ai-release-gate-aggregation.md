# E12-R16 — AI és ML összesített release gate

- **Státusz:** READY (pre-flight elvégezve 2026-08-29, kód újramérve: `main @ e2a813e7`; előre megírva 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 16
- **Kör-azonosító:** `E12-R16`
- **Branch:** `<motor>/e12-r16-ai-release-gate-aggregation`
- **Előfeltétel:** `E12-R14` merge-elve (a benchmark-rekord séma az AI-riport egyik bemenete)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0477`](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md) — a pre-flightban MEGÍRVA. (A brief eredetileg `0456`-ot mondott; a `tools/round-slots.py reserve-adr --round E12-R16` foglaló `0477`-et adott, és a foglaló a kötelező út az ADR 0139 kétszeres-foglalás óta. A `0456` sem a lemezen, sem foglalva nincs — elavult batch-érték volt.)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "AI ML release gate evaluation report model version regression"` → **[ADR 0177](../adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md)** (score 2.75): a Tutor evaluation MÁR merge-gate, claim-provenance szabállyal. A kör ezt NEM cseréli le — összesíti a többi bizonyítékkal.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `evaluation/` fa MÉRT tartalmát (a megíráskor: `evaluation/analysis/{README.md,fixtures,manifest_schema.json}`, `evaluation/tutor/{datasets,run_eval.dart}`) és a `docs/eval/` két riportját (`real-audio-dsp-baseline.md`, `recognition-release-guard.md`). Az összesítő NEM találhat ki riport-formákat: a MÉRT kimeneteket olvassa.

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-29, `main @ e2a813e7`)

**Visszakeresés (ADR 0312, szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr "AI ML release gate aggregation evaluation report model version corpus identity"`
→ [ADR 0177](../adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md) (a
tutor-eval MÁR merge-gate — nem cseréljük le), `halts/E12-R13` (a device-mátrix
14 capabilityje). `--corpus lessons,halts "aggregator report missing measurement
fail closed not in scope capability"` → `halts/E08-R26` (a pre-flight négy hamis
brief-premisszát mért ki — ugyanaz a minta ismétlődött itt is),
`halts/E07-R25` (`notObservable` fail-closed őr mutációs review-ja).

### R1 — Az ADR-szám `0456` → `0477`

A foglaló (`tools/round-slots.py reserve-adr`) `0477`-et adott. A `0456` nem
létezik és nincs foglalva. Az ADR **megírva**:
[`0477-ai-release-evidence-aggregation-and-ga-scope-truth.md`](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md).

### R2 — A GA-scope MA géppel olvasható, és NEM a tutor a kritikus bemenet

**Mérve:** `docs/testing/device-matrix.yaml:90-133` (E12-R13, PR #503) egy
`capabilities:` blokkot hordoz, capabilityenként `id` + `ga_scope` + `devices`.
14 capability, ebből **11 `ga_scope: true`**: `onboarding`, `live_and_tuner`,
`practice_engine`, `song_trainer_local`, `audio_analysis_core`,
`progress_goals_streak`, `storage_migration`, `offline_operation`,
`localization_en_hu`, `accessibility_minimum`, `session_lifecycle_stability`;
és **3 `ga_scope: false`**: `computer_vision`, `offline_ai`, **`ai_tutor`**.

Ebből következik, amit a brief §1 nem tudott: **a tutor-bizonyíték ma NEM
GA-kritikus**, hanem a §5.3 / A3 `not_in_scope` ágának egyik esete — a vision és
az offline AI mellett. Az összesítő MA kizárólag az `audio_analysis_core` és a
`live_and_tuner` capabilityre kér kötelező AI-bizonyítékot (a
`docs/eval/real-audio-dsp-baseline.md` és a
`docs/eval/recognition-release-guard.md` területe).

**Szerződés (ADR 0477 D1):** a `ga_scope` értéket az összesítő KIZÁRÓLAG a
device-mátrixból olvassa; sem a Python forrás, sem a
`docs/release/ai-quality-gates.md` nem sorolhatja fel újra. A `docs/release/ai-quality-gates.md`
**bizonyíték-mátrix** (capability → milyen bizonyíték kell), nem GA-lista. A
mátrixban szereplő, de a device-mátrixban ismeretlen capability → nem-nulla
kilépés.

### R3 — A modell-verziónak KÉT mért alakja van

**Mérve:** `assets/ml/model_manifest.json` a `models[]` elemeket `filename`-mel
azonosítja és `training_run.identifier`-rel verziózza (`git:<40 hex>`; négy
elem: `chord_crnn.bin`, `strum_crnn.bin`, `strum_crnn_live.bin`,
`strum_crnn_live_3c.bin`), a `vision_models[]` elemeket viszont `model_id`-vel
azonosítja és egy `version` mezővel verziózza (`"1.0.0"`; `hand_landmarker`,
`pose_landmarker`, mindkettő `status: deferred`). Egyetlen közös
„modell-verzió" mező feltételezése találgatás lett volna (ADR 0477 D5).

Modell nélküli (tisztán DSP) bizonyítékra a `modelId` a `none` literál, de
KIZÁRÓLAG akkor, ha a bizonyíték-mátrix az adott sort kifejezetten
`model: none`-ként deklarálja — különben nem-nulla kilépés.

### R4 — A küszöb-logika IMPORTÁLT, a forrása mért

**Mérve:** `tool/compare_benchmarks.py:52-56` — `WARN_THRESHOLD = 0.05`,
`FAIL_THRESHOLD = 0.10`, és `classify()` (`:155-168`) az irány-tudatos,
mindkét határon INKLUZÍV osztályozás (ADR 0474 D6/D7). Az összesítő ezt a három
nevet IMPORTÁLJA (`tool/` a `sys.path`-ra téve); saját küszöb-literál vagy saját
`classify` a forrásában TILOS, és ezt gépi cella méri (A4). A `tool/compare_benchmarks.py`
az engedélyezett listán NINCS rajta: olvasni és importálni szabad, módosítani nem.

### R5 — A `--profile` provenancia, nem kapcsoló; és a mai fán a kimenet PIROS

**Mérve:** `docs/release/environment-matrix.md:14` — a zárt csatorna-szótár
`development` / `lab` / `production`. A `--profile` az ADR 0477 D6 szerint a
kimenetbe kerül, de egyetlen ellenőrzést sem lazít; ismeretlen érték → kilépés 2.

**Következmény, amit az implementernek NEM szabad „megjavítania":** a mai fán
`python3 tool/release/build_ai_report.py --profile development` **nem-nulla**
kóddal lép ki, mert a két GA-scope AI-capabilityhez nincs beolvasható
bizonyíték-dokumentum. Ez a HELYES kimenet (D2 fail-closed) — a §10-be a
tényleges kimenet kerül. **Kitalált bizonyíték-riport commitolása TILOS**; az
engedélyezett fájllista amúgy sem enged `docs/eval/**` vagy `evaluation/**`
írást. A teszt-fixture-ök `Directory.systemTemp`-be íródnak és
`addTearDown`-nal bomlanak le (a `test/tooling/benchmark_budget_test.dart`
E12-R14 mintája), mert `test/fixtures/**` sincs a listán.

### R6 — PyYAML használható, precedens van

**Mérve:** `tool/device_report.py:33` `import yaml` kemény függésként, és a
`python3 -c "import yaml"` ezen a boxon `6.0.1`-et ad. Az összesítő ugyanígy
olvassa a device-mátrixot. (A `package:yaml` tiltás DART-oldali szabály — a
`test/tooling/device_matrix_test.dart` szűkített olvasója miatt —, a Python
oldalra nem vonatkozik.)

## 0.0.1 A Chapter 14 release-guard viszonya

A `docs/eval/recognition-release-guard.md` a Chapter 14 (felismerés-helyreállítás) sáv terméke, és a felismerési pontosság KÜLÖN kapuja. Az AI-összesítő ezt BEMENETKÉNT olvassa, és nem definiál rá második, versengő küszöböt. Ha a két dokumentum ellentmond, az a `stopped` jelzés esete.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/release/build_ai_report.py",
  "tool/release/ai_report_schema.json",
  "docs/release/ai-quality-gates.md",
  "test/tooling/ai_release_report_test.dart",
  "docs/rounds/e12-r16-ai-release-gate-aggregation.md",
]
gate_tests = [
  "test/tooling/ai_release_report_test.dart",
  "test/tooling/analysis_evaluation_regression_test.dart",
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

**STOP-protokoll:** ha egy bemeneti evaluation-riport a fán nem létezik vagy más formátumú, mint amit a séma vár, a kimenet a `stopped` jelzés — kitalált riport-forma bevezetése TILOS.

## 1. Cél

Egyetlen, gépileg ellenőrizhető AI-release riport, amely a DSP-, felismerési, tutor- és (ha GA-scope) vision-bizonyítékot modell- és build-verzióhoz köti — és hiányzó kritikus mérés esetén BLOKKOL.

## 2. Jelenlegi állapot — mért tények

- `evaluation/analysis/`: `manifest_schema.json` + fixture-fa; `evaluation/tutor/`: `run_eval.dart` + datasets. **Közös riport-séma NINCS.**
- `.github/workflows/tutor-eval.yml` (41 sor) és `dsp-probe.yml` (48 sor) MA külön futnak, külön kimenettel.
- `test/tooling/analysis_evaluation_regression_test.dart` **létezik** — az elemzési regresszió őre; `gate_tests`-ben tartjuk.
- `docs/eval/` **két** riportot tartalmaz; `docs/release/ai-quality-gates.md` és `tool/release/build_ai_report.py` **nem létezik**.
- Az Offline AI (Epic 10) sáv `hold`-on: a riport ezt „nem GA scope" ágon kezeli, kötelező bemenet NÉLKÜL.

## 3. Scope

**Benne van:** `tool/release/ai_report_schema.json` (a riport sémája: modell-azonosító + verzió, build-SHA, korpusz-azonosító, metrika, baseline-érték, döntés) · `tool/release/build_ai_report.py` (a MÉRT bemenetek beolvasása; hiányzó KRITIKUS mérés → nem-nulla kilépés; modell-verzió eltérés a manifesttől → nem-nulla kilépés; regresszió-osztályozás a Kör 14 küszöb-logikájával) · `docs/release/ai-quality-gates.md` (melyik capability melyik bizonyítékot követeli GA-hoz) · `test/tooling/ai_release_report_test.dart`.

**NINCS benne (tilos):**

- DSP/ML paraméter vagy modell módosítása (AGENTS.md §9).
- ÚJ CI-workflow (`ai-release-gate.yml`) — a CI-integráció külön kör.
- A Chapter 14 release-guard küszöbeinek átírása.
- `docs/adr/**` — az ADR 0477-et a Claude MÁR megírta a pre-flightban.
- `tool/compare_benchmarks.py`, `docs/testing/device-matrix.yaml`, `assets/ml/model_manifest.json` — ezek BEMENETEK: olvasni és importálni kell őket, módosítani TILOS.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/ai_report_schema.json` | ÚJ — a riport sémája |
| `tool/release/build_ai_report.py` | ÚJ — az összesítő |
| `docs/release/ai-quality-gates.md` | ÚJ — capability↔bizonyíték mátrix |
| `test/tooling/ai_release_report_test.dart` | a §6 cellái |

**Tilos zóna:** `ml/**` · `lib/**` · `evaluation/**` · `docs/eval/**` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0477 — a teljes szöveg a `docs/adr/0477-…` fájlban, D1–D7)

### 5.1 Hiányzó kritikus mérés = BLOKK, nem figyelmeztetés

**NEM elfogadható gyengítés:** „nincs adat, tehát nincs regresszió" — ez pontosan az a hamis zöld, amit a Kör 14 §5.2 is tilt.

### 5.2 Minden állítás modell- ÉS build-verzióhoz kötött

**NEM elfogadható gyengítés:** verzió nélküli metrika átvétele egy korábbi riportból („úgyis ugyanaz a modell").

### 5.3 A GA-scope-on kívüli capability hiányzó riportja NEM blokkol

Az Offline AI és a Vision csak akkor kötelező bemenet, ha a GA-scope tartalmazza őket. **NEM elfogadható gyengítés:** minden capability kötelezővé tétele — az a release-t olyan sávra tenné függővé, ami `hold`-on áll.

## 6. Acceptance criteria

Minden cella `Process.runSync('python3', …)` úton méri az összesítőt, `Directory.systemTemp`-be írt
fixture-ökön, `addTearDown` bontással (a `benchmark_budget_test.dart` E12-R14 mintája).
**`skip:` ág egyetlen cellán sem megengedett.**

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Egy `ga_scope: true` capability (MÉRVE ma: `audio_analysis_core`, `live_and_tuner`) előírt bizonyítéka hiányzik → nem-nulla kilépés, és a capability `missing` státusszal LÁTSZIK a kimenetben | `ai_release_report_test.dart` |
| A2 | A riport `modelVersion`-je ≠ a `assets/ml/model_manifest.json` verziója → nem-nulla kilépés. **Két külön cella:** `models[].filename` → `training_run.identifier`, és `vision_models[].model_id` → `version` (R3). Harmadik cella: `modelId: "none"` olyan soron, amit a mátrix modellhez köt → nem-nulla | `ai_release_report_test.dart` |
| A3 | `ga_scope: false` capability (MÉRVE ma: `computer_vision`, `offline_ai`, `ai_tutor`) hiányzó riportja NEM blokkol, és a kimenetben `not_in_scope` jelöléssel látszik. A `ga_scope` értéke a device-mátrixból JÖN: egy cella átírja a fixture-mátrixban az `ai_tutor`-t `ga_scope: true`-ra, és ugyanaz a bemenet ekkor BLOKKOL (ez bizonyítja, hogy nincs beégetett lista — ADR 0477 D1) | `ai_release_report_test.dart` |
| A4 | Az osztályozás a `tool/compare_benchmarks.py` `classify` / `WARN_THRESHOLD` / `FAIL_THRESHOLD` neveit IMPORTÁLJA. **Gépi őr:** egy cella beolvassa a `tool/release/build_ai_report.py` forrását, és PIROS, ha az küszöb-literált (`0.05`, `0.10`, `5.0`, `10.0`) vagy saját `def classify` definíciót tartalmaz | `ai_release_report_test.dart` |
| A5 | A riport minden metrikája `corpusId`, `buildSha`, `modelId`, `modelVersion` mezőt hordoz; bármelyik hiánya nem-nulla kilépés (négy külön cella) | a séma + `ai_release_report_test.dart` |
| A6 | A `--profile` zárt szótár: `development` / `lab` / `production` mind elfogadott ÉS a kimenetbe kerül; ismeretlen érték → kilépés **2**. Egy cella bizonyítja, hogy ugyanaz a bemenet MINDHÁROM profilon UGYANAZT a kilépési kódot adja (ADR 0477 D6 — a profil nem lazít) | `ai_release_report_test.dart` |
| A7 | A bizonyíték-mátrixban szereplő, de a device-mátrixban ismeretlen capability → nem-nulla kilépés (nem néma átugrás) | `ai_release_report_test.dart` |
| A8 | A meglévő `analysis_evaluation_regression_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas (a Kör 14 ÖRÖKÖLT küszöbeire, itt csak ALKALMAZVA — figyelmeztetés 5%, hiba 10%, mindkét határ INKLUZÍV):** a küszöb **alatt** (4,9% romlás a baseline-hoz) → a riport `pass`; **pontosan rajta** (5,0%) → `warn`; a küszöb **fölött** (10,0% és felette) → `fail`, és az összesítő nem-nulla kóddal lép ki. A cellák bemenetét a teszt `python3 -c`-vel számolt értékekkel adja (baseline `0.800` → `0.7608` pass, `0.7600` warn, `0.7200` fail).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó riport üres eredménnyel, `pass` döntéssel csúszik át | A1 |
| A modell-verzió ellenőrzés kimarad | A2 |
| Minden capability kötelezővé válik, így a `hold`-on álló Offline AI blokkolja a release-t | A3 |
| Az összesítő saját, lazább küszöböt definiál | A4 |
| A `fail` határ szigorú `>`-ként valósul meg, így a pontosan 10%-os romlás átcsúszik | a küszöb-cellahármas „fölött" cellája |
| A `ga_scope` beégetett capability-listából jön, nem a device-mátrixból | A3 utolsó cellája (`ai_tutor` → `ga_scope: true` a fixture-ben) |
| `development` profilon a hiány csak figyelmeztetés | A6 profil-invariancia cellája |
| A mátrix ismeretlen capability-sorát az összesítő némán átugorja | A7 |
| A `modelId: "none"` univerzális kiskapuvá válik | A2 harmadik cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a kötelező-riport ellenőrzést, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ai_release_report_test.dart test/tooling/analysis_evaluation_regression_test.dart
```

Az összesítő közvetlen futtatása (a TELJES kimenet és a kilépési kód a §10-be):

```bash
python3 tool/release/build_ai_report.py --profile development --scope-file docs/release/ai-quality-gates.md
echo "exit=$?"
```

⚠ **Ez a futás a mai fán VÁRHATÓAN nem-nulla** (§0.0 R5): a két GA-scope
AI-capabilityhez nincs beolvasható bizonyíték-dokumentum, és a D2 fail-closed
ága ezt mondja ki. **A pirosat kitalált riport-dokumentummal elfedni tilos** —
a §10-be a tényleges kimenet kerül, és ez a kör HELYES eredménye.

## 8. Implementációs sorrend

1. A MÉRÉS: a meglévő evaluation-kimenetek tényleges formája.
2. `tool/release/ai_report_schema.json`.
3. `tool/release/build_ai_report.py`.
4. `test/tooling/ai_release_report_test.dart`.
5. `docs/release/ai-quality-gates.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Kitalált riport-forma.** Ha a séma nem a MÉRT kimenetekre illeszkedik, az összesítő a valóságban semmit nem olvas be (STOP-eset).
- **Versengő küszöbök.** Két helyen definiált regresszió-határ garantáltan szétcsúszik (A4).
- **A `hold`-on álló sávok blokkoló szerepe.** Az Offline AI kötelezővé tétele a release-t egy el sem indult epictől tenné függővé (A3).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`), 2026-08-29.

### 10.1 Amit a kör hozott létre

- `tool/release/ai_report_schema.json` — a riport JSON-Schema (draft-07,
  `evaluation/analysis/manifest_schema.json` stílusát követve): `capability`
  → `metrics[]`, minden metrika kötelezően `capability`, `metric`,
  `corpusId`, `buildSha`, `modelId`, `modelVersion`, `baselineValue`,
  `candidateValue`, `direction`, `status`, `delta` mezővel (ADR 0477 D5).
- `tool/release/build_ai_report.py` — az összesítő. A `docs/release/ai-quality-gates.md`
  `<!-- ai-quality-gates:begin -->` / `...:end -->` jelölők közötti
  Markdown-táblát olvassa (`capability | metric | direction | model |
  evidence_path`), a `ga_scope`-ot KIZÁRÓLAG `--matrix`-ból (alapértelmezett
  `docs/testing/device-matrix.yaml`), a modell-verziót KIZÁRÓLAG
  `--model-manifest`-ből (alapértelmezett `assets/ml/model_manifest.json`).
  A `classify`/`WARN_THRESHOLD`/`FAIL_THRESHOLD` a `tool/compare_benchmarks.py`-ból
  IMPORTÁLT (`sys.path.insert` a `tool/`-ra, R4 minta). Kilépési kódok:
  `0` tiszta, `1` release-blokkoló találat (`findings[]` nem üres — hiányzó
  kötelező bizonyíték, modell-verzió eltérés, vagy `fail`-minősítés),
  `2` használati/formátum-hiba (ismeretlen `--profile`, a mátrixban a
  device-mátrixból ismeretlen capability, olvashatatlan/hibás YAML/JSON
  bemenet, a bizonyíték-dokumentumból hiányzó kötelező mező).
- `docs/release/ai-quality-gates.md` — a bizonyíték-mátrix. Öt sor: két
  `audio_analysis_core` metrika (`chord_accuracy`, `onset_f1_50ms`,
  `model: none`, forrás `docs/eval/real-audio-dsp-baseline.md`), egy
  `live_and_tuner` metrika (`direction_accuracy`, `model:strum_crnn_live_3c.bin`,
  forrás `docs/eval/recognition-release-guard.md`), és két `computer_vision`
  metrika (a `model_manifest.json` `vision_models[].evaluation_report`
  mezőiből, dokumentációs célra — `ga_scope: false` ma, sosem blokkol). Az
  `ai_tutor` és az `offline_ai` SZÁNDÉKOSAN nincs a mátrixban — indoklás a
  fájl §3 „Amit ez a mátrix szándékosan NEM sorol fel" szakaszában.
- `test/tooling/ai_release_report_test.dart` — 22 teszt-cella A1–A7 +
  küszöb-hármas + A9 önellenőrzés, mind `Directory.systemTemp` fixture-ökön,
  `python3`-on kívül más külső binárist nem hívva.

### 10.2 Valódi-sértés próba (§6.1, KÖTELEZŐ)

A kötelező-bizonyíték ellenőrzést (`tool/release/build_ai_report.py`
`evaluate_capability`, a `FileNotFoundError`/`JSONDecodeError` ágat) egy
csendes `continue`-ra cseréltem (a `missing`/`findings` írás nélkül), majd
lefuttattam `flutter test test/tooling/ai_release_report_test.dart`-ot.

**Eredmény: PIROS, pontosan az A1 cellák (és a rájuk épülő A3/A6 cellák) —**

```
00:00 +0 -1: A1 — ... a non-existent evidence path is a non-zero exit [E]
  Expected: not <0>
    Actual: <0>
00:00 +0 -2: A1 — ... an evidence file that is not valid JSON ... [E]
  Expected: not <0>
    Actual: <0>
00:00 +4 -3: A3 — ... the exact SAME evidence-matrix input blocks once the fixture
             device matrix flips ga_scope to true ... [E]
  Expected: not <0>
    Actual: <0>
00:01 +12 -4: A6 — ... the SAME missing-evidence input produces the SAME non-zero
              exit code on all three profiles ... [E]
  Expected: not <0>
    Actual: <0>
Some tests failed.
```

4 cella PIROS, pontosan azok, amelyek a hiányzó-bizonyíték blokkolást mérik —
ez bizonyítja, hogy a teszt valóban a mérni kívánt viselkedést méri, nem egy
más okból zöld ágat. Ezután a kivételkezelő ágat visszaállítottam az eredeti
alakra (`missing = True` + `findings.append(...)`), és
`flutter test test/tooling/ai_release_report_test.dart` újra **22/22
zöld**. `git status --short` a próba után a négy új fájlon kívül semmi mást
nem mutat — a próba nem hagyott vissza munkapéldány-szennyeződést.

### 10.3 §7 gate — teljes, csonkítatlan kimenet

```
$ tools/round-gate.sh test/tooling/ai_release_report_test.dart test/tooling/analysis_evaluation_regression_test.dart
═══ [1] format
    → [1] format: ZÖLD
═══ [2] analyze
Analyzing 3 items...
No issues found! (ran in 5.9s)
    → [2] analyze: ZÖLD
═══ [3] test test/tooling/ai_release_report_test.dart
00:01 +22: All tests passed!
    → [3] test test/tooling/ai_release_report_test.dart: ZÖLD
═══ [4] test test/tooling/analysis_evaluation_regression_test.dart
00:00 +8: All tests passed!
    → [4] test test/tooling/analysis_evaluation_regression_test.dart: ZÖLD
═══ [5] architecture
Architecture dependencies OK (12 allowlisted deviation(s)).
    → [5] architecture: ZÖLD
═══ [6] secrets
Secret scan OK (4062 file(s) scanned, 0 finding(s)).
    → [6] secrets: ZÖLD
═══ [7] l10n
L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 2291 message(s)).
    → [7] l10n: ZÖLD
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/ai_release_report_test.dart              zöld
    test test/tooling/analysis_evaluation_regression_test.dart zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
MINDEN GATE ZÖLD.
```

(A fenti a tényleges futás rövidített — a `flutter pub get` függőség-lista és
a köztes letöltési sorok nélküli — másolata; a valódi futás minden lépése
külön processzben, csonkítás nélkül futott, a fenti a `round-gate.sh`
összegző blokkjait és a teszt-futók végösszegzését tartalmazza szó szerint.)

### 10.4 Az összesítő közvetlen futtatása a mai fán (§7, MÉRT PIROS — ez a HELYES kimenet)

```
$ python3 tool/release/build_ai_report.py --profile development --scope-file docs/release/ai-quality-gates.md
build_ai_report: 3 release-blocking finding(s):
  - audio_analysis_core/chord_accuracy: required evidence document is missing or unreadable (docs/eval/real-audio-dsp-baseline.md): Expecting value: line 1 column 1 (char 0)
  - audio_analysis_core/onset_f1_50ms: required evidence document is missing or unreadable (docs/eval/real-audio-dsp-baseline.md): Expecting value: line 1 column 1 (char 0)
  - live_and_tuner/direction_accuracy: required evidence document is missing or unreadable (docs/eval/recognition-release-guard.md): Expecting value: line 1 column 1 (char 0)
{
  "capabilities": [
    {
      "error": "audio_analysis_core/onset_f1_50ms evidence (docs/eval/real-audio-dsp-baseline.md): Expecting value: line 1 column 1 (char 0)",
      "id": "audio_analysis_core",
      "metrics": [],
      "status": "missing"
    },
    {
      "error": "live_and_tuner/direction_accuracy evidence (docs/eval/recognition-release-guard.md): Expecting value: line 1 column 1 (char 0)",
      "id": "live_and_tuner",
      "metrics": [],
      "status": "missing"
    },
    {
      "id": "computer_vision",
      "metrics": [],
      "status": "not_in_scope"
    }
  ],
  "findings": [
    "audio_analysis_core/chord_accuracy: required evidence document is missing or unreadable (docs/eval/real-audio-dsp-baseline.md): Expecting value: line 1 column 1 (char 0)",
    "audio_analysis_core/onset_f1_50ms: required evidence document is missing or unreadable (docs/eval/real-audio-dsp-baseline.md): Expecting value: line 1 column 1 (char 0)",
    "live_and_tuner/direction_accuracy: required evidence document is missing or unreadable (docs/eval/recognition-release-guard.md): Expecting value: line 1 column 1 (char 0)"
  ],
  "profile": "development",
  "schemaVersion": 1
}
$ echo "exit=$?"
exit=1
```

Ez pontosan a §0.0 R5 / ADR 0477 „Következmények" szakasza által előre jelzett
mai állapot: a két GA-scope AI-capability (`audio_analysis_core`,
`live_and_tuner`) bizonyíték-útvonala ma prózai Markdown-riportra mutat
(`docs/eval/real-audio-dsp-baseline.md`, `docs/eval/recognition-release-guard.md`),
ami nem `json.loads()`-olható — ezért mindkettő `missing` státusszal jelenik
meg, és az összesítő `exit=1`-gyel lép ki. A `computer_vision`
(`ga_scope: false`) helyesen `not_in_scope`, és nem befolyásolja a kilépési
kódot. Nem hoztam létre kitalált bizonyíték-dokumentumot a piros elfedésére —
a `docs/eval/**` és az `evaluation/**` amúgy sem szerepel az engedélyezett
fájllistán.

### 10.5 Amit NEM érintettem

`ml/**`, `lib/**`, `evaluation/**`, `docs/eval/**`, `.github/**`,
`docs/adr/**`, `tools/**`, `test/fixtures/**`, `docs/testing/**`,
`assets/**`, `tool/compare_benchmarks.py` — egyik sem módosult. A
`docs/testing/device-matrix.yaml` és az `assets/ml/model_manifest.json`
kizárólag olvasásra/importálásra került (a fixture-alapú tesztek saját,
`Directory.systemTemp`-be írt másolatokat használnak).

## 11. Review — a Claude tölti ki
