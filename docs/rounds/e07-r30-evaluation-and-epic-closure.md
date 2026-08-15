# E07-R30 — Evaluation harness, shadow rollout és Epic lezárás

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0afb9994`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 30 — **epic-záró kör**
- **Kör-azonosító:** `E07-R30`
- **Branch:** `<motor>/e07-r30-evaluation-and-epic-closure`
- **Előfeltétel:** `E07-R29` merge-elve (hardening)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a záró kör nem hoz új architekturális
  döntést; a rollout **emberi döntés** (§5.1).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a `.github/workflows/`
> tényleges tartalmát és a property-teszt konvenciót (`PROPERTY_SEED`). A
> **CI-fájlok módosítása H-GATEGUARD-terület** — ha a kör bővítené a gate-et,
> az EMBERI döntés, nem implementer-hatáskör. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/practice_plan_eval/plan_quality_report.dart",
  "test/fixtures/practice_planner/golden_profiles.json",
  "test/features/practice_generator/property/planner_invariants_property_test.dart",
  "test/features/practice_generator/property/planner_golden_fixture_test.dart",
  "lib/features/practice_generator/application/service/shadow_plan_generator.dart",
  "docs/sdd/epic-07-completion-report.md",
  "docs/rounds/e07-r30-evaluation-and-epic-closure.md",
]
gate_tests = [
  "test/features/practice_generator/property/planner_invariants_property_test.dart",
  "test/features/practice_generator/property/planner_golden_fixture_test.dart",
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

A generátor determinisztikus minőségének **mérhető** igazolása, árnyék-módú
futtatás, és az Epic 7 lezárása (SDD Ch8 Kör 30).

## 2. Jelenlegi állapot — mért tények

- Az R01-R29 minden rétege kész; **minden flag OFF**.
- Az ADR 0255 §1: azonos bemenet → azonos terv. Ez a kör ezt **méri**.
- Az ADR 0263: `error`/`fatal` mellett a terv nem aktiválható — a fixture-
  korpuszon **nulla** hard invariáns-sértés az elvárás.
- A property-konvenció: `PROPERTY_SEED` (hiányában 42), CI-ban külön HARD lépés.

## 3. Scope

**Benne van:** golden profil- és szimulációs fixture-ök · invariáns- és
property-tesztek · terv-minőségi riport · **árnyék-módú** generálás
aktiválás nélkül · a determinisztikus és az AI-segített magyarázat
összevetése · késleltetés- és memória-mérés · a completion report és a
HANDOFF frissítése.

**NINCS benne (tilos):** **bármely flag `true`-ra állítása** (§5.1) · a
`.github/**` módosítása implementer-hatáskörben (H-GATEGUARD) · új terméki
funkció · `docs/adr/**`, `tools/**` (a `tool/practice_plan_eval/` kivételével).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/practice_plan_eval/plan_quality_report.dart` | **ÚJ** — a riport |
| `test/fixtures/practice_planner/golden_profiles.json` | **ÚJ** — a korpusz |
| `test/…/property/planner_invariants_property_test.dart` | **ÚJ** |
| `test/…/property/planner_golden_fixture_test.dart` | **ÚJ** |
| `application/service/shadow_plan_generator.dart` | **ÚJ** — árnyék-mód |
| `docs/sdd/epic-07-completion-report.md` | **ÚJ** — a záró jelentés |
| `docs/rounds/e07-r30-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · `.github/**` ·
`docs/adr/**` · más `lib/features/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 A ROLLOUT emberi döntés — ez a kör NEM kapcsol be semmit

A `practiceGeneratorEnabled` és a `plannerAssistEnabled` **OFF marad**. A
bekapcsolás külön, jóváhagyott lépés a release gate után (ADR 0255 §4).
Ez acceptance-cella (A7), nem ajánlás.

### 5.2 Az árnyék-mód GENERÁL, de NEM aktivál

Az árnyék-futtatás tervet állít elő összehasonlítás céljából, és **soha nem**
teszi aktívvá (ADR 0266 §2 folytatása).

### 5.3 A fixture-korpuszon NULLA hard invariáns-sértés az elvárás

Nem „kevés" — nulla. Bármely sértés a korpuszon a kör bukása.

### 5.4 Azonos seed → azonos terv, bitre

A determinizmus mérése nem hasonlóság-alapú: a két futás eredménye azonos.

### 5.5 Az AI-magyarázat NEM mondhat ellent a tervnek

Ha a `plannerAssistEnabled` be lenne kapcsolva, a magyarázatnak a **tényleges**
tervet kell leírnia. Ellentmondás esetén a determinisztikus magyarázat nyer
(ADR 0270 §1/§5).

### 5.6 A CI-gate bővítése EMBERI döntés

Ha a kör úgy ítéli, hogy a property-suite-ot a CI-ba kell kötni, azt
**jelezze** (`blocked`), és ne módosítsa a `.github/**`-ot — az H-GATEGUARD.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A fixture-korpuszon **nulla** hard invariáns-sértés | `planner_golden_fixture_test.dart` |
| A2 | Azonos seed → bitre azonos terv | `planner_invariants_property_test.dart` |
| A3 | A property-suite `PROPERTY_SEED`-del fut (42 default) | ugyanott |
| A4 | Az árnyék-mód generál, de nem aktivál | `planner_invariants_property_test.dart` |
| A5 | A terv-minőségi riport előáll és értelmezhető | `tool/practice_plan_eval` futtatása, §10-ben rögzítve |
| A6 | A késleltetés és memória mérve, a §10-ben rögzítve | §10 |
| A7 | **Egyetlen flag sem mozdult** | `git diff` — `feature_flags.dart` érintetlen |
| A8 | A `.github/**` érintetlen | `git diff --stat` |
| A9 | A completion report megnevezi a nyitott tételeket | review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Kevés sértés belefér" a korpuszon | **A1** |
| Hasonlóság-alapú determinizmus-mérés | **A2** |
| Az árnyék-mód aktiválja a tervet | **A4** |
| A kör bekapcsol egy flaget | **A7** |
| A CI-gate módosítása implementer-hatáskörben | **A8** |
| A completion report elhallgatja a nyitott tételeket | A9 |

**A korpusz-eredmény három kötelező cellája** (a küszöb: a hard invariáns-sértés):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nulla sértés a korpuszon | **zöld** |
| rajta (a küszöbön) | **egyetlen** hard sértés | **PIROS** — a küszöb nulla, nem „kevés" |
| a küszöb fölött | több sértés | piros, a riport felsorolja |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** rontsd el egyetlen
golden profil elvárását → az **A1** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/property/planner_invariants_property_test.dart test/features/practice_generator/property/planner_golden_fixture_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

A **teljes** suite és az APK a CI-ban fut (ADR 0053), nem itt.

## 8. Implementációs sorrend

1. `golden_profiles.json` — a fixture-korpusz (több tanulói profil).
2. `planner_invariants_property_test.dart` — invariánsok + seed-determinizmus.
3. `planner_golden_fixture_test.dart` — nulla hard sértés a korpuszon.
4. `shadow_plan_generator.dart` — generál, nem aktivál.
5. `tool/practice_plan_eval/plan_quality_report.dart` — a riport.
6. Késleltetés- és memória-mérés, §10-be rögzítve.
7. `docs/sdd/epic-07-completion-report.md` — a nyitott tételekkel.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „majdnem zöld" korpusz.** Egyetlen sértés is bukás; a küszöb nulla (A1).
- **A záró kör flag-csábítása.** „Már minden kész, kapcsoljuk be" — a rollout
  emberi döntés, és a valós eszközös elfogadás még hátravan (A7).
- **A CI-gate önhatalmú bővítése.** Jó szándékú, és H-GATEGUARD-sértés (A8).
- **A szépített completion report.** A nyitott tételek elhallgatása a
  következő session-t vezeti félre (A9).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
