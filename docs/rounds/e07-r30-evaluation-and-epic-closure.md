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
  "test/fixtures/practice_planner/golden_profiles.dart",
  "test/property/planner_invariants_property_test.dart",
  "test/property/planner_golden_fixture_test.dart",
  "lib/features/practice_generator/application/service/shadow_plan_generator.dart",
  "docs/sdd/epic-07-completion-report.md",
  "docs/rounds/e07-r30-evaluation-and-epic-closure.md",
]
gate_tests = [
  "test/property/planner_invariants_property_test.dart",
  "test/property/planner_golden_fixture_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight — mért revízió (Claude, 2026-08-19, `main @ 0d68d72c`)

**Visszakeresett előzmény (ADR 0312, brief-lint S8).**
`node tools/knowledge-rag.mjs --top 5 "shadow plan generator evaluation harness
golden profile GenerationOrchestrator no-op activation property test
PROPERTY_SEED"` legjobb találata pontosan a döntő fájl volt:
`tools/tests/test_e07_r21_activation_boundary_scope.py` — az E07-R21/H2
self-heal regressziós őre, ami épp azt a tényt pinneli, amit lent az
"aktiválás nélküli generálás" szakasz újra levezet. `--corpus lessons`
találatai: L92 (randomizált property-generátor determinizmusa — index, nem
karakterkód-maradék, a §A2/§A3 teszt megírásához releváns), L142 (HARD-seedes
property-gate boundary-flaky lehet kis mintán — a §5.3 NULLA-küszöb erre nem
érzékeny, mert abszolút, nem %-os, de a próbaszám megválasztásánál érdemes
tudni róla), L110 (`Process.run('rg', …)` a boxon zöld, CI-runneren PIROS —
a `plan_quality_report.dart` és az új tesztek NE hívjanak külső binárist).

**1. KRITIKUS — a property-teszt útvonal a mért CI-vel ütközött (javítva
fent, a TOML blokkban).** `.github/actions/flutter-gates/action.yml:47`
mérten `flutter test test/property`-t futtat a "Property gate (randomized
seed)" lépésben, `PROPERTY_SEED: ${{ github.run_id }}` env-vel — ez az
EGYETLEN CI-lépés, ami a randomizált seedet adja. A megelőző "Test gate"
lépés (`flutter test`, teljes fa, minden meglévő `.github/workflows/*.yml`-ben
`PROPERTY_SEED` env NÉLKÜL fut) mindig a 42 default-ra esne vissza. A brief
eredeti `test/features/practice_generator/property/`-je (és az SDD-fejezet
saját fájllistája, `docs/sdd/08-epic-07-ai-practice-generator.md:4330`, ami
ugyanezt írja) NINCS a `test/property` alatt — az új property tesztek a CI-ban
SOHA nem futottak volna a randomizált seeddel, csak a fix 42-vel a sima Test
gate-en belül, ami közvetlenül aláásta volna A2/A3-at (a HORIZON
anti-reward-hacking mérce, `CLAUDE.md`). Nincs is precedens az útvonalra:
`find test/features -type d -iname property` üres, míg a MEGLÉVŐ
planner-property-tesztek (`test/property/planner_repair_property_test.dart`,
`test/property/planner_time_budget_property_test.dart`, mindkettő
`Platform.environment['PROPERTY_SEED']`-et olvas, default 42) mind
`test/property/`-ben élnek. Az SDD-fejezet fájllistája emellett egy nem
létező `.github/workflows/flutter-ci.yml`-t is megnevez (a mai CI
`build-apk.yml`/`full-gate.yml`/`router-ci.yml` hármasra bomlott) — ugyanaz az
elavulási osztály, nem külön hiba (AGENTS.md §2: "Elavult dokumentumot nem
szabad csendben követni. Dokumentáld az eltérést."). **Revízió:** mindkét
property-teszt célja `test/property/` (fent a TOML-ban, lent a §4/§7/§8-ban is
javítva); a `.github/**` tiltott zóna változatlan, egyetlen workflow-fájlhoz
sem nyúlunk.

**2. `golden_profiles` fixture formátum — REVÍZIÓ (`.json` → `.dart`).**
Mérve: `PracticeGenerationRequest`/`WeeklyAvailability`/`PracticeGoal`/
`LearnerConstraints` egyikének SINCS `fromJson`/`toJson`-ja (csak a beágyazott
`GenerationRequestId`-nek, `practice_generation_request.dart:27-31`). A
practice_generator feature MINDEN meglévő fixture-je
(`test/fixtures/practice_generator/**`, pl. `validation/
validation_fixtures.dart`, `plan/plan_fixtures.dart`) Dart builder-függvény
minta — a repóban van 22 JSON fixture, de egyik sem ebben a feature-ben, és
egyik sem szerializál ilyen gazdag, beágyazott domain-objektumot kézzel írt
parserrel. Egy bespoke JSON→domain parser megírása egyetlen záró körben, egy
bevált, meglévő mintával szemben indokolatlan kockázat. **Revízió:**
`test/fixtures/practice_planner/golden_profiles.dart` — Dart
builder-függvények listája, a `validation_fixtures.dart` mintáját követve
(`import 'package:strumsight/features/practice_generator/public.dart';`,
majd egyenkénti, paraméterezhető builder minden golden profilhoz).

**3. Nincs meglévő kompozíciós gyökér — architektúra-iránymutatás (nem
blokkoló, de a helyes megoldáshoz kritikus).** Mérve:
`grep -rl "GenerationPlanInput(" lib/` NULLA találat — a `GenerationPlanInput`
konstruktort SOHA nem hívja `lib/` kód, kizárólag két teszt
(`test/features/practice_generator/application/generation_orchestrator_test.dart`,
`.../plan_generator_controller_test.dart`) építi kézzel, egy jelöltes/egy
napos minimál bemenettel. `PlanGeneratorController` maga sem építi — készen
kapja paraméterként. A `shadow_plan_generator.dart` lesz tehát az Epic 7 ELSŐ
éles vég-az-végig kompozíciója (evidence → skill estimate → priority →
candidate selection → time budget → weekly schedule → `GenerationPlanInput` →
`GenerationOrchestrator.generate()`) — ez lényegesen nagyobb feladat, mint
amit a §8 4. sora sejtet, de VALÓS, a scope-on belüli munka, nem
brief-hiba. Iránymutatás (nem kényszerítő, de mért-ok-alapú):

- Az "aktivál nélküli generálás" mérten bevett mintája ebben a kódbázisban
  (ADR 0266 "Módosítás" záró szakasza + `PlanPreviewController` docstringje +
  `generation_orchestrator_test.dart` `_RecordingActivation`/`_NoopActivation`
  osztályai + a most visszakeresett `test_e07_r21_activation_boundary_scope.py`
  forcing function): `GenerationOrchestrator._run()` a validálást/javítást és
  az aktiválást EGY atomi hívásban fuzionálja (`generate()` maga hívja
  `activation.activate(activePlan)`-t záró hatásként) — ezt a fájlt a brief
  NEM engedi módosítani, és nem is kell: az `activation` paraméter injektált
  interfész pontosan erre az esetre. A `ShadowPlanGenerator` építsen egy SAJÁT,
  no-op `GenerationPlanActivation` implementációt (hívásszámláló, semmilyen
  perzisztencia), és ezzel példányosítsa a VALÓDI `GenerationOrchestrator`-t —
  így a shadow-terv ugyanazon a determinisztikus kódúton születik, mint az
  éles út (nem duplikált, drift-mentes logika), de az "aktiválás" ténylegesen
  semmilyen valódi állapotot nem ír. A4 falszifikálható mérceként ezt
  használd: a no-op activation hívásszáma > 0 (a generálás lefutott), DE a
  `shadow_plan_generator.dart` szerkezetileg sem importál semmit a
  `data/local/`-ból vagy az `application/controller/
  active_plan_controller.dart`-ból (grep-ellenőrizhető invariáns, nem csak
  futásidejű megfigyelés).
- Minden köztes szolgáltatás (`SkillEstimateReducer`, `SkillPriorityEngine`,
  `CandidateSelector`, `TimeBudgetAllocator`, `WeeklyScheduler`) publikusan
  elérhető a `public.dart`-on át; a pontos bemenet/kimenet alakhoz a saját
  tesztjük a hiteles forrás (`test/features/practice_generator/**/
  *_test.dart` az adott szolgáltatáshoz) — ne találj ki új alakot mérés
  nélkül.
- `ValidationSeverity` (`domain/model/plan_enums.dart:90`) legalább `fatal`,
  `error`, `warning` értékeket ismeri; `PlanValidationResult.isActivatable`
  ezekre `false` — ez fedi a brief §2 "error/fatal mellett nem aktiválható"
  állítását, nincs ütközés, nincs revízió szükséges itt.

**ADR:** nem szükséges új szám. A fenti három pont dokumentációs/útvonal-
pontosítás egy MÉG NEM dispatch-elt kör briefjén (§2 szerint teljes egészében
az orchestrátor hatásköre), nem architekturális döntés — az ADR 0255/0263/
0266/0270 változatlan marad, egyiket sem kell módosítani.

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
| `test/fixtures/practice_planner/golden_profiles.dart` | **ÚJ** — a korpusz (Dart builder, ld. §0.0 pont 2) |
| `test/property/planner_invariants_property_test.dart` | **ÚJ** (ld. §0.0 pont 1 — a CI hardcoded `test/property`-t futtat randomizált seeddel) |
| `test/property/planner_golden_fixture_test.dart` | **ÚJ** (ugyanaz) |
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
tools/round-gate.sh test/property/planner_invariants_property_test.dart test/property/planner_golden_fixture_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

A **teljes** suite és az APK a CI-ban fut (ADR 0053), nem itt.

## 8. Implementációs sorrend

1. `golden_profiles.dart` — a fixture-korpusz (több tanulói profil, Dart builder).
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

### Implemented files

- `test/fixtures/practice_planner/golden_profiles.dart`: three deterministic
  Dart-builder learner profiles with checked expected executable candidates,
  including a confirmed-microphone capability path.
- `test/property/planner_invariants_property_test.dart`: 80 seeded trials
  (default `PROPERTY_SEED=42`) assert byte-identical serialized plans, zero
  hard findings, a reached no-op activation boundary, and zero writes.
- `test/property/planner_golden_fixture_test.dart`: asserts zero hard findings
  and exact expected candidates over the corpus.
- `lib/features/practice_generator/application/service/shadow_plan_generator.dart`:
  evaluation-only end-to-end composition through the real orchestrator with a
  counting, no-op `GenerationPlanActivation`; it imports no local repository
  or active-plan controller.
- `tool/practice_plan_eval/plan_quality_report.dart`: prints per-profile
  success, hard-findings, activation/write counts, total latency, and RSS delta.
- `docs/sdd/epic-07-completion-report.md`: completion evidence and explicitly
  named rollout/device/preview/assist open items.

### Measurements and checks run

- `flutter test test/property/planner_invariants_property_test.dart` — pass.
- `PROPERTY_SEED=20260819 flutter test
  test/property/planner_invariants_property_test.dart` — pass.
- `flutter test test/property/planner_golden_fixture_test.dart` — pass after
  restoration.
- `flutter test tool/practice_plan_eval/plan_quality_report.dart` — invoked
  the report: 3/3 successful plans, 0 hard violations, 3 activation calls,
  0 persistent writes, 76,782 microseconds total, 3,735,552-byte RSS delta.
- Real-violation probe: temporarily set the starter profile expected candidate
  to `probe.invalidCandidate`; the golden test failed with actual
  `rhythm.quarterNotes.steady`; restored the expectation afterward.

### Scope and remaining checks

- No feature flag or `.github/**` file was changed.
- `ROUND_GATE_SLEEP_SECONDS=0 tools/round-gate.sh
  test/property/planner_invariants_property_test.dart
  test/property/planner_golden_fixture_test.dart` — pass: format, analyze,
  both targeted tests, architecture, secrets, and l10n all green. The zero
  sleep only removes the gate's configurable inter-step delay; no check was
  skipped. Full CI, randomized property gate, and APK remain
  orchestrator-owned merge evidence.
- Direct `dart run tool/practice_plan_eval/plan_quality_report.dart` stopped
  during package build hooks in this environment without running the report;
  `flutter test` executed the same `main()` and produced the measurement above.

## 11. Review — a Claude tölti ki
