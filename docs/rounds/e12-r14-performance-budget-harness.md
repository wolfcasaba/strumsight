# E12-R14 — Performance budget harness

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 14
- **Kör-azonosító:** `E12-R14`
- **Branch:** `<motor>/e12-r14-performance-budget-harness`
- **Előfeltétel:** `E12-R13` merge-elve (a benchmark-rekord device-metaadata a mátrix eszköz-azonosítóit használja)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0454` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "performance budget benchmark cold start regression threshold"` → **[ADR 0248](../adr/0248-analysis-cache-key-and-performance-budget.md)** (Analysis cache-kulcs és performance budget — a repóban MÁR van performance-budget fogalom az elemzési úton). A kör ezt ÁLTALÁNOSÍTJA egy közös rekord-sémára, nem tervez mellé másikat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `tool/benchmarks/` MEGLÉVŐ két eszközét (`real_audio_dsp_baseline.dart`, `song_trainer_pitch_benchmark.dart`) és a `docs/baseline/epic-0{4,6}-performance.md` mért baseline-jait. A séma ezek MÉRT mezőit fedje le, ne egy elképzelt riportét.

## 0.0 Az AGENTS.md §9 DSP-tilalom hatálya

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

## 5. Kötött architekturális döntések (ADR 0454)

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

**Küszöb-cellahármas a regresszióra** (figyelmeztetési küszöb 5%, hiba-küszöb 10%; MINDKÉT határ INKLUZÍV, azaz a pontosan 5%-os romlás MÁR figyelmeztetés, a pontosan 10%-os MÁR hiba): a küszöb **alatt** (4,9% romlás) → PASS; **pontosan rajta** (5,0%) → WARN; a küszöb **fölött** (10,0% és felette) → FAIL. A cellák értékét a teszt `python3 -c`-vel számolt bemenettel adja (pl. baseline `200.0` → `209.8` PASS, `210.0` WARN, `220.0` FAIL).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó metrika kimarad az összesítésből, és a riport zöld lesz | A3 |
| A küszöb-összehasonlítás szigorúan `>`-t használ `>=` helyett | a küszöb-cellahármas „pontosan rajta" cellája |
| A metaadat opcionálissá válik | A2 |
| A baseline értékei forrás nélkül, „körülbelül" kerülnek be | A4 |

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
