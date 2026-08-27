# E12-R16 — AI és ML összesített release gate

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 16
- **Kör-azonosító:** `E12-R16`
- **Branch:** `<motor>/e12-r16-ai-release-gate-aggregation`
- **Előfeltétel:** `E12-R14` merge-elve (a benchmark-rekord séma az AI-riport egyik bemenete)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0456` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "AI ML release gate evaluation report model version regression"` → **[ADR 0177](../adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md)** (score 2.75): a Tutor evaluation MÁR merge-gate, claim-provenance szabállyal. A kör ezt NEM cseréli le — összesíti a többi bizonyítékkal.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `evaluation/` fa MÉRT tartalmát (a megíráskor: `evaluation/analysis/{README.md,fixtures,manifest_schema.json}`, `evaluation/tutor/{datasets,run_eval.dart}`) és a `docs/eval/` két riportját (`real-audio-dsp-baseline.md`, `recognition-release-guard.md`). Az összesítő NEM találhat ki riport-formákat: a MÉRT kimeneteket olvassa.

## 0.0 A Chapter 14 release-guard viszonya

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
- `docs/adr/**` — az ADR 0456-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/ai_report_schema.json` | ÚJ — a riport sémája |
| `tool/release/build_ai_report.py` | ÚJ — az összesítő |
| `docs/release/ai-quality-gates.md` | ÚJ — capability↔bizonyíték mátrix |
| `test/tooling/ai_release_report_test.dart` | a §6 cellái |

**Tilos zóna:** `ml/**` · `lib/**` · `evaluation/**` · `docs/eval/**` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0456)

### 5.1 Hiányzó kritikus mérés = BLOKK, nem figyelmeztetés

**NEM elfogadható gyengítés:** „nincs adat, tehát nincs regresszió" — ez pontosan az a hamis zöld, amit a Kör 14 §5.2 is tilt.

### 5.2 Minden állítás modell- ÉS build-verzióhoz kötött

**NEM elfogadható gyengítés:** verzió nélküli metrika átvétele egy korábbi riportból („úgyis ugyanaz a modell").

### 5.3 A GA-scope-on kívüli capability hiányzó riportja NEM blokkol

Az Offline AI és a Vision csak akkor kötelező bemenet, ha a GA-scope tartalmazza őket. **NEM elfogadható gyengítés:** minden capability kötelezővé tétele — az a release-t olyan sávra tenné függővé, ami `hold`-on áll.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hiányzó KRITIKUS (GA-scope) riport → nem-nulla kilépés | `ai_release_report_test.dart` |
| A2 | A riportban szereplő modell-verzió ≠ a manifest verziója → nem-nulla kilépés | `ai_release_report_test.dart` |
| A3 | Nem-GA-scope capability hiányzó riportja NEM blokkol, de a kimenetben `not_in_scope` jelöléssel látszik | `ai_release_report_test.dart` |
| A4 | A regresszió-osztályozás a Kör 14 küszöb-logikáját használja (nincs második, versengő küszöb) | `ai_release_report_test.dart` |
| A5 | A riport minden metrikája korpusz-azonosítót hordoz | a séma + a teszt cellája |
| A6 | A meglévő `analysis_evaluation_regression_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas (a Kör 14 ÖRÖKÖLT küszöbeire, itt csak ALKALMAZVA — figyelmeztetés 5%, hiba 10%, mindkét határ INKLUZÍV):** a küszöb **alatt** (4,9% romlás a baseline-hoz) → a riport `pass`; **pontosan rajta** (5,0%) → `warn`; a küszöb **fölött** (10,0% és felette) → `fail`, és az összesítő nem-nulla kóddal lép ki. A cellák bemenetét a teszt `python3 -c`-vel számolt értékekkel adja (baseline `0.800` → `0.7608` pass, `0.7600` warn, `0.7200` fail).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó riport üres eredménnyel, `pass` döntéssel csúszik át | A1 |
| A modell-verzió ellenőrzés kimarad | A2 |
| Minden capability kötelezővé válik, így a `hold`-on álló Offline AI blokkolja a release-t | A3 |
| Az összesítő saját, lazább küszöböt definiál | A4 |
| A `fail` határ szigorú `>`-ként valósul meg, így a pontosan 10%-os romlás átcsúszik | a küszöb-cellahármas „fölött" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a kötelező-riport ellenőrzést, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ai_release_report_test.dart test/tooling/analysis_evaluation_regression_test.dart
```

Az összesítő közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/build_ai_report.py --profile development --scope-file docs/release/ai-quality-gates.md
```

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

## 11. Review — a Claude tölti ki
