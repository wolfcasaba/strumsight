# E10-R26 — Bilingual pedagógiai és grounding evaluation (aggregációs logika)

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 26
- **Kör-azonosító:** `E10-R26`
- **Branch:** `<motor>/e10-r26-bilingual-evaluation`
- **Előfeltétel:** `E10-R25` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör egy mérési/riport-eszközt szállít, nem köt új architekturális döntést.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "quality gate aggregation regression critical fail"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 5 `offline_tutor_eval.{hu,en}.jsonl` corpus sémáját. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát — miért PENDING (narrowed)

A SDD Kör 26 "reference és quantized modellhez" evaluation runnert ír elő — ez a batch-prep pillanatában NEM futtatható VALÓS modellen (nincs kiválasztott runtime, Kör 6/7 `hold`-on). Ez a kör az AGGREGÁCIÓS/RIPORT logikát szállítja (exact+rubric score összesítés, regresszió-detektálás, kritikus-fail szabály), FIXTURE (előre rögzített, kitalált) modell-kimeneteken tesztelve — a VALÓS modell-inferencia futtatása a release-időpontra (emberi/Kör 32 gate) marad.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "local_ai/evaluation/run_quality_eval.py",
  "local_ai/evaluation/compare_candidates.py",
  "local_ai/tests/test_quality_eval_aggregation.py",
  "docs/quality/offline-ai-model-gate.md",
  "docs/rounds/e10-r26-bilingual-evaluation.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
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

## 1. Cél

Az AGGREGÁCIÓS/riport-logika, ami majd a valós modell-kimeneteket fogja mérni magyar/angol minőségi kapuval — ez a kör FIXTURE-kimeneten bizonyítja a logikát.

## 2. Jelenlegi állapot — mért tények

- A Kör 5 corpus sémája (`offline_tutor_eval.hu.jsonl`/`.en.jsonl`) a bemenete.
- A projektben MA nincs semmilyen evaluation-aggregációs kód a `local_ai/` alatt — ez teljesen ÚJ.

## 3. Scope

**Benne van:** exact és rubric-score aggregáció · külön mérés: grounding, citation, unsupported-claim, clarification, tool-accuracy, pedagógia, brevity, nyelvi minőség · pairwise report compact/standard jelöltekre (FIXTURE-adaton) · regressziós threshold package-verziók között · kritikus safety eset automatikus fail · human-review sampling workflow, vak model-identifierrel · a report rögzíti a prompt/knowledge/tool-schema verzióját.

**NINCS benne (tilos):**

- Valódi modell-inferencia futtatása.
- `docs/adr/**`, `tools/**`, `.github/**`, `android/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `local_ai/evaluation/run_quality_eval.py` | ÚJ — az aggregációs runner |
| `local_ai/evaluation/compare_candidates.py` | ÚJ — pairwise report |
| `local_ai/tests/test_quality_eval_aggregation.py` | a §6 cellái, FIXTURE kimeneteken |
| `docs/quality/offline-ai-model-gate.md` | ÚJ — a minőségi kapu dokumentációja |

**Tilos zóna:** `local_ai/evaluation/corpus/**` (Kör 5 fájlja, csak OLVASSA) · `lib/**` · `android/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — mérési/aggregációs eszköz

**NEM elfogadható gyengítés:** a kritikus safety-eset fail-szabályának "soft warning"-gá gyengítése egy jövőbeli riportban — egyetlen kritikus safety-fail a TELJES release-t blokkolja, nem csak egy pontszám-levonás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A deterministic report ugyanarra a FIXTURE bemenetre mindig ugyanazt az összesítést adja | `test_quality_eval_aggregation.py` |
| A2 | Hiányzó modell-kimenet kontrolláltan kezelt (nem crash, explicit "missing" jelölés) | `test_quality_eval_aggregation.py` |
| A3 | Malformed structured result (érvénytelen JSON) kontrolláltan kezelt | `test_quality_eval_aggregation.py` |
| A4 | Magyar és angol pontszám KÜLÖN aggregálva, nem összemosva | `test_quality_eval_aggregation.py` |
| A5 | Regresszió (előző package-verzióhoz képest rosszabb pontszám) detektált és jelzett | `test_quality_eval_aggregation.py` |
| A6 | EGYETLEN kritikus safety-fail a teljes release-jelentést "FAIL"-re állítja, függetlenül a többi pontszámtól | `test_quality_eval_aggregation.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A magyar és angol pontszám egyetlen összesített átlagba kerül | A4 |
| A kritikus safety-fail csak pontlevonást okoz, nem blokkoló FAIL-t | A6 |
| A regresszió-detektálás nem veti össze az előző verzióval, csak abszolút küszöböt néz | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a kritikus safety-fail szabályt "csak −10 pont"-ra blokkoló FAIL helyett, futtasd a tesztet egy kritikus-fail FIXTURE-rel → az **A6** cellának PIROSNAK kell lennie → állítsd vissza.

### 6.2 Küszöb-hármas — regressziós threshold (konfigurálható konstans, alapérték 5 százalékpont pontszám-csökkenés)

`python3 -c "print(round(0.05*100, 2))"` = 5.0 százalékpont; a `rajta` cella a regresszió-oldalé (inkluzív):

| Cella | Pontszám-csökkenés az előző verzióhoz képest | Elvárt |
|---|---|---|
| alatta | 4.99 pp | Nincs regresszió jelezve |
| rajta | 5.00 pp | Regresszió jelezve (a küszöb a regresszió-oldalé) |
| fölötte | 5.01 pp | Regresszió jelezve |

## 7. Kötelező ellenőrzések

```bash
python3 -m pytest local_ai/tests/test_quality_eval_aggregation.py -q
```

A `gate_tests` regresszió-őre (Kör 1 óta stabil feature-flag teszt) a `tools/round-gate.sh`-on át bizonyítja, hogy a Python-eszköz nem érintett véletlenül Flutter-oldali kódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `run_quality_eval.py` — az aggregációs logika, nyelvenként külön.
2. Kritikus-fail szabály, regresszió-detektálás.
3. `compare_candidates.py` — pairwise report.
4. `docs/quality/offline-ai-model-gate.md`.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A kritikus-fail gyengülése.** A legveszélyesebb regresszió — egy release ténylegesen kritikus safety-hibával mehetne ki, ha a szabály "csak pontlevonás"-sá szelídülne (A6).
- **A nyelvek összemosása.** Elrejtené, ha a magyar minőség szisztematikusan gyengébb az angolnál (A4).
- **A FIXTURE és a valós modell-kimenet formátumának eltérése.** Ha a release-időponti valós futtatás más JSON-formátumot ad, mint a FIXTURE, az aggregáció hibázna — a Kör 32 pre-flightjának ezt validálnia kell.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
