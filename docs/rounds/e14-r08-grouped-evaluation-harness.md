# E14-R08 — Csoportosított evaluation harness és leakage-védelem

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ b0979855`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 8
- **Kör-azonosító:** `E14-R08`
- **Branch:** `<motor>/e14-r08-grouped-evaluation-harness`
- **Előfeltétel:** `E14-R02` (baseline manifest) és `E14-R07` (annotációs
  szerződés) merge-elve — a harness ezek formátumát olvassa.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0360` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `E14-R07`
> annotációs sémáját és a `ml/honest_eval.py` fejlécét. Utóbbi a TANÍTÓ oldal
> saját mérése (leave-one-guitarist-out, bootstrap, kalibráció) — ez a kör a
> SZÁLLÍTOTT felismerési útra épít Dart-oldali harness-t, és NEM írja át a
> Python-oldalt. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/domain/evaluation/recognition_split.dart",
  "lib/features/live/domain/evaluation/recognition_metrics.dart",
  "lib/features/live/data/evaluation/recognition_evaluation_runner.dart",
  "tool/recognition_evaluate.dart",
  "evaluation/recognition/fixtures/ci_manifest.json",
  "test/features/live/evaluation/recognition_split_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
  "docs/rounds/e14-r08-grouped-evaluation-harness.md",
]
gate_tests = [
  "test/features/live/evaluation/recognition_split_test.dart",
  "test/features/live/evaluation/recognition_metrics_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A felismerési mérés ne egyetlen accuracy-szám legyen, és ne szivárogjon:
ugyanaz a játékos, telefon vagy gitár ne szerepelhessen egyszerre a tanító és a
kiértékelő oldalon. A kör csoportosított split-stratégiákat, leakage-detektort
és a Chapter 14 §7 által kért metrika-készletet ad, kézzel ellenőrzött
fixture-értékekkel.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0249 / E06-R29:** a CI kis, szintetikus fixture-ön fut, a valós korpusz
  külső, kézi futtatás — ez a kör ugyanezt a kettősséget örökli.
- **GOV-06b / E99-R05 (`docs/eval/real-audio-dsp-baseline.md`):** a visszavont
  BPM-mérce mért tanulsága, hogy a metrika definíciója maga is bizonyítandó —
  ezért itt minden metrikához fixture-en kézzel ellenőrzött érték tartozik.

## 2. Jelenlegi állapot — mért tények

- `ml/honest_eval.py` — a TANÍTÓ oldal mérése: three-way split, LOGO CV,
  cluster-bootstrap, kalibráció/ECE. Dart-oldali megfelelője **nincs**.
- `tool/audio_analysis_evaluate.dart` + `evaluation/analysis/` — a repó
  bevált harness-alakja (fixture-default, `--manifest`, determinisztikus JSON).
- `lib/features/live/domain/evaluation/` — az `E14-R07` hozza létre; ez a kör
  bővíti.
- Felismerési oldali split/leakage kód a repóban **nincs**.

## 3. Scope

**Benne:** `leave-one-player-out`, `leave-one-device-out`,
`leave-one-guitar-out`, `room-holdout` split; leakage-detektor; onset P/R/F1
25/50/100 ms; irány-osztály F1; any-strum F1; accepted accuracy + coverage;
false visible event/min; latencia p50/p95; ECE; Brier; akkord-metrikák
(weighted accuracy, macro-F1, no-chord F1, unknown false-accept); CLI; fixture.

**Nincs benne:** modellcsere, küszöbhangolás, `ml/**` módosítás, valós korpusz
a repóban, dashboard/HTML (az `E14-R09` köre), UI.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/domain/evaluation/recognition_split.dart` | split-stratégiák + leakage-detektor |
| `lib/features/live/domain/evaluation/recognition_metrics.dart` | metrika-készlet, Flutter-független |
| `lib/features/live/data/evaluation/recognition_evaluation_runner.dart` | manifest → report futtató |
| `tool/recognition_evaluate.dart` | CLI a meglévő harness alakja szerint |
| `evaluation/recognition/fixtures/ci_manifest.json` | kicsi, szintetikus CI-fixture |
| `test/features/live/evaluation/recognition_split_test.dart` | split + leakage mátrix |
| `test/features/live/evaluation/recognition_metrics_test.dart` | kézzel ellenőrzött metrika-értékek |
| `docs/rounds/e14-r08-grouped-evaluation-harness.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `ml/**`, `lib/features/live/engine/**`,
`assets/**`, `docs/adr/**`, `docs/rag/chunks/**`, `.github/workflows/**`,
`tools/round-gate.sh`, és minden shipping DSP/ML konstans (AGENTS.md §9).

## 5. Kötött architekturális döntések (ADR 0360)

### 5.1 A leakage-detektor fail-closed

Ha ugyanaz a csoportkulcs (player/device/guitar/room) két splitben előfordul, a
futtató **hibát ad és megáll** — nem figyelmeztet, nem javít. **NEM elfogadható**
gyengítés: „warning + folytatás", vagy a duplikált csoport csendes eldobása.

### 5.2 Hiányzó csoportkulcs = hiba

Ha egy felvételhez nincs player/device/guitar/room mező, az adott split
stratégia típusos hibát ad. Az `unknown` nem csoportkulcs.

### 5.3 A metrika definíciója a reportban utazik

Minden metrika mellé kerül a definíciója (tolerancia, párosítási szabály,
számláló/nevező), hogy a szám később is olvasható legyen — a visszavont
BPM-mérce (GOV-06b) tanulsága.

### 5.4 Determinisztikus report

Ugyanaz a manifest bitre ugyanazt a JSON-t adja; a splitek sorrendje a
csoportkulcs szerint rendezett, nem hash-sorrend.

### 5.5 A CI fixture kicsi és szintetikus

A CI-fixture nem tartalmaz valós felvételt; a valós korpusz külső manifesttel,
kézi futtatással mérhető (`--manifest`).

## 6. Acceptance criteria

1. Mind a négy split-stratégia előállítja a maga foldjait a fixture-ön, és a
   foldok uniója a teljes felvételhalmaz (nincs elveszett elem).
2. A leakage-detektor a szándékosan elrontott fixture-változaton hibát dob, és
   a hibaüzenet megnevezi az ütköző csoportkulcsot.
3. Az onset-tolerancia (50 ms) határa **inkluzív**, mindhárom cellával mérve: a
   küszöb **alatt** (49 ms) → találat; **rajta** (pontosan 50 ms) → találat, a
   határ az elfogadó oldalhoz tartozik; **fölött** (51 ms) → hiányzó találat.
4. A fixture-re kézzel kiszámolt értékek egyeznek: onset P/R/F1 (25/50/100 ms),
   irány-F1, any-strum F1, accepted accuracy + coverage, false visible
   event/min, latencia p50/p95, ECE, Brier — mindegyikhez a briefben rögzített
   szám a §10-ben megismételve.
5. A report tartalmazza minden metrika definícióját (tolerancia, párosítás).
6. Kétszeri futtatás bájtra azonos JSON-t ad.
7. Hiányzó csoportkulcsnál típusos hiba, nem `unknown` fold.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A leakage-detektor csak logol | 2. pont hibadobás-cellája |
| A párosítás exkluzív határ (`<`) | 3. pont **rajta (50 ms)** cellája |
| A coverage a teljes halmazra oszt, nem az elfogadottakra | 4. pont accepted/coverage cellája |
| A foldok hash-sorrendben állnak elő | 6. pont bájtra-azonos cellája |
| Hiányzó csoportkulcs → `unknown` fold | 7. pont típusos-hiba cellája |
| Az ECE binjei egyenlő darabszámúak egyenlő szélesség helyett | 4. pont ECE-cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a leakage-detektor ideiglenes kikapcsolásával a 2. pont
cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Fixture (a leakage-változattal együtt).
2. Split-stratégiák + detektor, teszttel.
3. Metrikák, kézzel ellenőrzött értékekkel.
4. Runner + CLI.

## 9. Kockázatok

- **A metrikák túl sokan vannak egy körre:** ha a kör mérete futás közben
  aránytalannak bizonyul, a chord-metrikák leválaszthatók egy `E14-R08b`
  körre — ez `stopped` jelzéssel és brief-revízióval történik, nem csendben.
- **Python-oldali duplikáció:** a `ml/honest_eval.py` NEM módosul; ha a két
  oldal eltérő definíciót adna, az a review dolga, nem a kódé.
- **Fixture-túlillesztés:** a fixture-nek tartalmaznia kell nem párosított
  eseményt és elutasított (abstained) eseményt is.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
