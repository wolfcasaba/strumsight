# E12-R14 — Performance budget harness

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 14
- **Kör-azonosító:** `E12-R14`
- **Branch:** `<motor>/e12-r14-performance-budget-harness`
- **Előfeltétel:** `E12-R13` merge-elve (a benchmark-rekord device-metaadata a mátrix eszköz-azonosítóit használja)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0474`](../adr/0474-benchmark-record-and-performance-budget-comparison.md) — a pre-flightban MEGÍRVA (lásd §0.0 R1: a batch-tervezéskor vázolt `0454` avult).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "performance budget benchmark cold start regression threshold"` → **[ADR 0248](../adr/0248-analysis-cache-key-and-performance-budget.md)** (Analysis cache-kulcs és performance budget — a repóban MÁR van performance-budget fogalom az elemzési úton). A kör ezt ÁLTALÁNOSÍTJA egy közös rekord-sémára, nem tervez mellé másikat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `tool/benchmarks/` MEGLÉVŐ két eszközét (`real_audio_dsp_baseline.dart`, `song_trainer_pitch_benchmark.dart`) és a `docs/baseline/epic-0{4,6}-performance.md` mért baseline-jait. A séma ezek MÉRT mezőit fedje le, ne egy elképzelt riportét.

## 0.0 Pre-flight revízió (2026-08-29, `main @ 7b28744a`) — MÉRT állítások, amelyek felülírják a 2026-08-27-i brief-szöveget

A brief előre íródott. Az alábbi hét pontot a pre-flight **kigrepelte a fából**;
ahol a régi szöveg mást mond, **ez a szakasz az érvényes**.

**Visszakeresés (ADR 0312, szűkítve előbb):**
`--corpus lessons,halts,adr "performance budget benchmark regression threshold baseline"`
→ [ADR 0248](../adr/0248-analysis-cache-key-and-performance-budget.md) (a performance
budget fogalma MÁR létezik az elemzési úton; „a szám gépfüggő, nem merge-kapu"),
[ADR 0298](../adr/0298-time-budget-allocation-contract.md) (INKLUZÍV hard maximum +
alatta/határon/fölötte cellahármas — a küszöb-cellahármas mintája).
`--corpus lessons,halts "python tool dart test Process.runSync tooling test fixture"`
→ [L527](../LESSONS.md#l527) (az önvédő cella volt a vakon zöld),
[L110](../LESSONS.md#l110) (`Process.run('rg', …)` a boxon zöld, a CI-runneren piros),
[L85](../LESSONS.md#l85)/[L86](../LESSONS.md#l86) (beágyazott `tool/` package cache
és analyzer-hatókör). Teljes korpuszon: az SDD Ch12 „Fő érintett fájlok" blokkja
(`benchmark/`, `tool/compare_benchmarks.py`, `docs/performance/budgets.md`,
`.github/workflows/benchmark.yml`) — a workflow szándékosan kimarad (§3).

### R1 — az ADR száma `0474`, nem `0454`

MÉRT: `tools/round-slots.py reserve-adr --round E12-R14` → **`0474`**; a lemezen a
legmagasabb ADR a `0473`. A 2026-08-27-i batch-tervezés `0454` placeholderje sosem
ment át a foglalón és időközben elavult (ugyanaz a mintázat, mint az
[ADR 0248](../adr/0248-analysis-cache-key-and-performance-budget.md) fejlécében
dokumentált `0210` → `0248` frissítés). **Minden `0454`-hivatkozás `0474`-re
értendő.** Az ADR-t a Claude MEGÍRTA a pre-flightban; a `docs/adr/**` az
implementer tilos zónája marad.

### R2 — a `docs/baseline/` számai NÉGY, össze nem keverhető osztályba esnek

Ez a kör legfontosabb mért ténye, és a régi §3 („a MÉRT jelenlegi értékek … átemelve")
egyszavas megfogalmazása nem elég pontos hozzá:

| Osztály | Mit jelent | MÉRT előfordulás |
|---|---|---|
| `measured` | valódi futás valódi kimenete | **egyetlen** dokumentum: `docs/baseline/epic-06-analysis-performance.md:10-15` (2026-08-13; cache-miss `30589 µs`, cache-hit `5317 µs`, modell read+parse `43578 µs`, `silence_2s` `190721 µs`, `strums_120_bpm` `496777 µs`, `progression_c_g_am_f` `308328 µs`) |
| `upperBound` | állítás egy mérésről, nem mérés | `docs/baseline/epic-04-performance.md:27-30` — végig `< 0.1 ms` / `< 1 ms` / `< 2 ms`; a doksi maga mondja ki, hogy izolált mérőszáma nincs |
| `derivedContract` | tervezési határ, nem megfigyelés | `docs/baseline/epic-03-backing-drift-benchmark.md:20-31` (17/34/51/68 ms), `docs/baseline/epic-03-pitch-observation-benchmark.md:9-21` (12/35/70 cent, ±80 ms, 0,014 RMS) |
| `target` | cél és küszöb, mérés NÉLKÜL | `docs/manual-testing/vision-performance-benchmark.md:35-40` — öt FPS-metrika, minden „Mért átlag"/„Mért p95" cellája `PENDING` |

**Következmény a `baseline.json`-ra:** minden bejegyzés kötelező `kind` mezőt
hordoz a fenti négy értékkel, és **a `< 0.1 ms` alakú felső korlátot `0.1`-ként
`measured`-nek felvenni TILOS** (ADR 0474 D3). A `measured` bejegyzések száma
kezdetben KEVÉS — ez mért állapot, nem hiányosság.

### R3 — a romlás iránya metrikánként rögzített (ÚJ acceptance: A7)

MÉRT: a fán mindkét irány előfordul — az `epic-06` mikroszekundumai
`lowerIsBetter`, a `vision-performance-benchmark.md:35-40` öt FPS-metrikája
`higherIsBetter` (minimum-küszöbök: 15 / 8 / 5 / 5 / 15 fps). Egy irány-vak,
„nagyobb = rosszabb" összehasonlító a teljes vision-oldalt fordítva ítélné meg, és
pont az FPS-esést engedné át zölden. Minden bejegyzés kötelező `direction` mezőt
hordoz; **alapértelmezett irány NINCS**, a hiányzó `direction` hiba (ADR 0474 D7).

### R4 — az eszköz-szótár ZÁRT, a Kör 13 mátrixából

MÉRT `id`-k a `docs/testing/device-matrix.yaml`-ból: `pixel_6a`, `pixel_7`,
`samsung_galaxy_a54`, `xiaomi_redmi_note_12`. Ezeken felül egyetlen érték
engedett: a gépen futó, nem eszközös mérések CI-host azonosítója. Ismeretlen
`deviceId` hiba (ADR 0474 D2). **Készüléknevet kitalálni TILOS.**

### R5 — a `python3` Dart-tesztből mérve MÉRT, zölden merge-elt precedens

MÉRT: `test/tooling/device_matrix_test.dart:1636-1801` nyolc
`Process.runSync('python3', …)` hívást tartalmaz **skip-ág nélkül**, plusz egy
önvédő cellát, amely a fájl külső-bináris készletét pontosan `{python3}`-ra méri,
és egy `python3 --version` self-checket („PIROS, nem néma skip"). Ez E12-R13-ként
zölden merge-elődött (PR #503). A `benchmark_budget_test.dart` **ezt a mintát
követi**; a tiltott bináris a `rg`/`grep`/`jq`/`gh` ([L110](../LESSONS.md#l110)),
az önvédő cella pedig [L527](../LESSONS.md#l527) miatt kötelező.

### R6 — a `tool/` alatti Dart forrás az analyzer hatókörében van

MÉRT: `tools/round-gate.sh:225-226` → `flutter analyze lib/ test/ tool/`. A
`benchmark_record.dart`-nak tehát analyzer-tisztának kell lennie. **Új
`pubspec.yaml`-függőség vagy beágyazott `tool/<csomag>/pubspec.yaml` TILOS** — a
`pubspec.yaml` nincs az engedélyezett listán, a beágyazott package-cache pedig
mért scope-audit-lelet volt ([L85](../LESSONS.md#l85)/[L86](../LESSONS.md#l86)).
A séma tehát `dart:convert` + `dart:core` eszközökkel írandó.

### R7 — a §2 két állítása pontosítva

`docs/baseline/` **16** dokumentumot tartalmaz (a régi szöveg „12+"-t írt) — ez a
régi szöveggel nem ütközik, csak pontosít. Változatlanul igaz: `tool/compare_benchmarks.py`
és `docs/performance/` **nem létezik**, a `benchmark/` gyökér-könyvtár sem, és a
`.github/workflows/dsp-probe.yml` már futtat mérést CI-ban.

## 0.0.1 Az AGENTS.md §9 DSP-tilalom hatálya

A kör benchmarkot MÉR, nem hangol: DSP- vagy ML-paraméter, küszöb vagy modell-bináris módosítása TILOS (AGENTS.md §9). Ha a mérés regressziót talál, az lelet és jelentés — a javítás külön kör dolga.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/benchmarks/benchmark_record.dart",
  "tool/compare_benchmarks.py",
  "docs/performance/budgets.md",
  "docs/performance/baseline.json",
  "test/tooling/benchmark_budget_test.dart",
  "docs/rounds/e12-r14-performance-budget-harness.md",
]
gate_tests = [
  "test/tooling/benchmark_budget_test.dart",
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

**STOP-protokoll:** ha a harness bekötése egy DSP/ML paraméter módosítását igényelné, a kimenet a `stopped` jelzés — az AGENTS.md §9 tilalma alól ez a kör nem ad felmentést.

## 1. Cél

Egységes, verziózott benchmark-rekord és összehasonlító eszköz, amellyel a cold start, audio, analysis és vision regresszió láthatóvá válik — device- és build-metaadattal.

## 2. Jelenlegi állapot — mért tények

- `tool/benchmarks/` **két** benchmarkot tartalmaz (`real_audio_dsp_baseline.dart`, `song_trainer_pitch_benchmark.dart`), külön kimeneti formával, közös séma NÉLKÜL.
- `docs/baseline/` **12+** mért baseline-dokumentumot tartalmaz (`epic-04-performance.md`, `epic-06-analysis-performance.md`, …) — mind Markdown, gépi összehasonlításra alkalmatlan.
- `benchmark/` gyökér-könyvtár és `tool/compare_benchmarks.py` **nem létezik**; `docs/performance/` **nem létezik**.
- A `.github/workflows/dsp-probe.yml` MÁR futtat mérést CI-ban — a kör NEM ír új workflow-t, a CI-integráció külön döntés.

## 3. Scope

**Benne van:** `tool/benchmarks/benchmark_record.dart` — közös rekord-séma (metrika-név, érték, mértékegység, minta-szám, build-SHA, device-azonosító a Kör 13 mátrixából, timestamp) · `docs/performance/baseline.json` — a MÉRT jelenlegi értékek (a meglévő baseline-dokumentumokból átemelve, forrás-hivatkozással) · `tool/compare_benchmarks.py` — két rekord-halmaz összevetése, **5%-os figyelmeztetési** és **10%-os hiba-küszöbbel** · `docs/performance/budgets.md` · `test/tooling/benchmark_budget_test.dart`.

**NINCS benne (tilos):**

- DSP/ML paraméter, küszöb vagy modell módosítása (AGENTS.md §9).
- Új CI-workflow (`.github/workflows/benchmark.yml`) — a CI-integráció külön kör.
- A meglévő két benchmark-eszköz átírása (a séma-adapterüket a rekord-típus adja).
- `docs/adr/**` — az ADR 0454-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/benchmarks/benchmark_record.dart` | ÚJ — közös rekord-séma |
| `tool/compare_benchmarks.py` | ÚJ — összehasonlító |
| `docs/performance/baseline.json` | ÚJ — a MÉRT baseline |
| `docs/performance/budgets.md` | ÚJ — a költségvetések és forrásaik |
| `test/tooling/benchmark_budget_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `ml/**` · `tool/benchmarks/` meglévő fájljai · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések ([ADR 0474](../adr/0474-benchmark-record-and-performance-budget-comparison.md))

> Az alábbi §5.1–§5.3 az ADR 0474 **D1 / D5 / D6** döntéseinek rövid alakja. Az
> ADR ezen felül köt: **D2** zárt eszköz-szótár, **D3** `kind` mező (a négy
> érték-osztály), **D4** létező forrás-hivatkozás, **D7** kötelező `direction`,
> **D8** `schemaVersion` + `sampleCount` + a MÉRÉS időbélyege, **D9** skip-ág
> nélküli `python3`-mérés önvédő cellával. Ütközés esetén az ADR szövege az
> irányadó.

### 5.1 Device- és build-metaadat NÉLKÜLI mérés nem rekord

A `compare_benchmarks.py` elutasítja a metaadat nélküli bemenetet. **NEM elfogadható gyengítés:** „ismeretlen eszköz" alapérték — két különböző készüléken mért érték összevetése értelmetlen, és pontosan ezt rejtené el.

### 5.2 A hiányzó mérés NEM zöld

Ha egy kötelező metrika hiányzik a release-riportból, az `unknown` — és az `unknown` a release-kapun HIBA, nem siker. **NEM elfogadható gyengítés:** hiányzó metrika kihagyása az összesítésből.

### 5.3 A regresszió-küszöb kétfokozatú, és a határ INKLUZÍV

Az 5%-os figyelmeztetés és a 10%-os hiba a rekordban rögzített, nem a hívó paramétere. **NEM elfogadható gyengítés:** a küszöb futásidejű felülírhatósága „a CI-ban lazábban" indoklással.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A rekord-séma parse-olható, és a metaadat (build-SHA, device) kötelező | `benchmark_budget_test.dart` |
| A2 | Metaadat nélküli bemenet → nem-nulla kilépés | `benchmark_budget_test.dart` |
| A3 | Hiányzó kötelező metrika → `unknown` és nem-nulla kilépés (nem „pass") | `benchmark_budget_test.dart` |
| A4 | A `baseline.json` minden értéke forrás-hivatkozást hordoz (`docs/baseline/…`) | a fájl + a teszt cellája |
| A5 | Az összehasonlító a küszöb-cellahármas szerint dönt | `benchmark_budget_test.dart` |
| A6 | A kör egyetlen DSP/ML paramétert sem módosít | `git diff --stat` a §4 listán |
| A7 | **(ÚJ, §0.0 R3)** A romlás iránya metrikánként rögzített: `higherIsBetter` metrikán a **csökkenés** a romlás, `lowerIsBetter`-en a **növekedés**; hiányzó `direction` → hiba, nem alapérték | `benchmark_budget_test.dart` — tükrözött cellahármas mindkét irányra |
| A8 | **(ÚJ, §0.0 R2)** Minden `baseline.json` bejegyzés `kind` mezőt hordoz a négy osztály valamelyikével, és **csak `measured` ↔ `measured`** párra számol regressziót | `benchmark_budget_test.dart` |
| A9 | **(ÚJ, §0.0 R5)** A teszt `Process.runSync('python3', …)`-szel méri az összehasonlítót, **skip-ág nélkül**, és önvédő cellával bizonyítja, hogy a fájl külső-bináris készlete pontosan `{python3}` | `benchmark_budget_test.dart` |

**Küszöb-cellahármas a regresszióra** (figyelmeztetési küszöb 5%, hiba-küszöb 10%; MINDKÉT határ INKLUZÍV, azaz a pontosan 5%-os romlás MÁR figyelmeztetés, a pontosan 10%-os MÁR hiba): a küszöb **alatt** (4,9% romlás) → PASS; **pontosan rajta** (5,0%) → WARN; a küszöb **fölött vagy rajta** (10,0% és felette) → FAIL.

A §0.0 R3 miatt a cellahármas **TÜKRÖZÖTT: mindkét irányra kötelező**. A hat cella
értéke `python3 -c`-vel kiszámolva (2026-08-29 pre-flight, a kimenet a §10-ben),
és a tesztbe **szó szerinti literálként** írandó — a `baseline * (1 + p)` alakú
futásidejű számítás float-driftet visz be (mérve: `200.0 * 1.1` → `220.00000000000003`):

| Irány | Baseline | 4,9 % romlás → **PASS** | 5,0 % romlás → **WARN** | 10,0 % romlás → **FAIL** |
|---|---:|---:|---:|---:|
| `lowerIsBetter` (pl. µs) | `200.0` | `209.8` | `210.0` | `220.0` |
| `higherIsBetter` (pl. fps) | `30.0` | `28.53` | `28.5` | `27.0` |

Mért relatív romlások (a `python3` kimenete): `lowerIsBetter` → `0.04900000000000006`,
`0.05`, `0.1`; `higherIsBetter` → `0.04899999999999996`, `0.05`, `0.1`. Mindkét
PASS-cella szigorúan `0.05` alatt van, mindkét WARN-cella pontosan `0.05`,
mindkét FAIL-cella pontosan `0.1` — a `>=` / `>` tévesztést tehát a WARN- és a
FAIL-cella EGYÜTT fogja meg.

**Javulás nem regresszió:** a `higherIsBetter` metrika NÖVEKEDÉSE és a
`lowerIsBetter` metrika CSÖKKENÉSE mindig `pass`, tetszőleges mértékben.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó metrika kimarad az összesítésből, és a riport zöld lesz | A3 |
| A küszöb-összehasonlítás szigorúan `>`-t használ `>=` helyett | a küszöb-cellahármas „pontosan rajta" cellája |
| A metaadat opcionálissá válik | A2 |
| A baseline értékei forrás nélkül, „körülbelül" kerülnek be | A4 |
| Az összehasonlító irány-vak (mindig „nagyobb = rosszabb") → az FPS-esést zölden engedi át | **A7** — a `higherIsBetter` cellahármas mindhárom cellája |
| A `direction` hiányában `lowerIsBetter`-re esik vissza | **A7** — a hiányzó `direction`-cella |
| A `< 0.1 ms` felső korlát `0.1`-ként, `measured` osztályban kerül a baseline-ba | **A8** — a `kind`-cella |
| A teszt `python3` hiányában némán skippel | **A9** — az önvédő + self-check cella |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a `compare_benchmarks.py`-ból a hiányzó-metrika ágat, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/benchmark_budget_test.dart
```

Az összehasonlító közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/compare_benchmarks.py --baseline docs/performance/baseline.json --candidate docs/performance/baseline.json
```

## 8. Implementációs sorrend

1. `benchmark_record.dart` — a közös séma.
2. `docs/performance/baseline.json` — a MÉRT értékek forrás-hivatkozással.
3. `tool/compare_benchmarks.py` — a kétfokozatú küszöb.
4. `test/tooling/benchmark_budget_test.dart` — a küszöb-cellahármassal.
5. `docs/performance/budgets.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A „hiányzó = zöld" csapda.** A legveszélyesebb: egy release-riport, ami azért zöld, mert nem mért (A3).
- **Készülékek összekeverése.** Metaadat nélkül két eszköz mérése összehasonlíthatónak látszik (A2).
- **DSP-hangolás csábítása.** Egy talált regresszió javítása ebben a körben AGENTS.md §9 sértés (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
