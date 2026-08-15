# E07-R03 — Goal, availability és learner constraint domain

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, `main @ a31bb2b1`) — a
  §2.1/§2.2 hivatkozásokat a tényleges `planner_ids.dart`/`plan_enums.dart`
  ellen mérve nincs eltérés (`GoalId` létezik, az öt enum-család egyike sem
  goal-lifecycle-specifikus — ez a kör hozza létre a saját goal-státusz
  típusát a `practice_goal.dart`-ban). ADR 0258 tartalma is mérve, változatlan.
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 3
- **Kör-azonosító:** `E07-R03`
- **Branch:** `<motor>/e07-r03-goal-availability-and-constraints`
- **Előfeltétel:** `E07-R02` merge-elve (typed ID-k és enumok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0258`](../adr/0258-hard-and-soft-planning-constraints.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az E07-R02 által
> létrehozott `domain/id/planner_ids.dart` és `domain/model/plan_enums.dart`
> TÉNYLEGES tartalmát (mely ID-k és enum-családok születtek meg, milyen
> néven), és igazítsd hozzá a §2/§5 hivatkozásait. Ha eltérés van,
> dokumentált §0.0 brief-revízió, majd Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/practice_goal.dart",
  "lib/features/practice_generator/domain/model/weekly_availability.dart",
  "lib/features/practice_generator/domain/model/learner_constraints.dart",
  "lib/features/practice_generator/domain/service/request_validator.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/domain/practice_goal_test.dart",
  "test/features/practice_generator/domain/weekly_availability_test.dart",
  "test/features/practice_generator/domain/learner_constraints_test.dart",
  "test/features/practice_generator/domain/request_validator_test.dart",
  "docs/rounds/e07-r03-goal-availability-and-constraints.md",
]
gate_tests = [
  "test/features/practice_generator/domain/request_validator_test.dart",
  "test/features/practice_generator/domain/weekly_availability_test.dart",
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

A felhasználói szándék (célok), a rendelkezésre álló idő és a tervezési
korlátok típusos modellezése, konfliktus-validátorral (SDD Ch8 Kör 3).

## 2. Jelenlegi állapot — mért tények

### 2.1 Amit az E07-R02 hagyott

`domain/id/planner_ids.dart` (typed ID-k, köztük `GoalId`),
`domain/model/plan_enums.dart` (stabil kódú enumok), `public.dart` barrel.
**A pre-flight kötelezően ellenőrzi a tényleges neveket.**

### 2.2 A domain Flutter-független (ADR 0257 §6)

Ez a kör ugyanezen a szabályon marad: sem `package:flutter/...`, sem
`dart:ui`, és nincs `DateTime.now()` — az idő injektált.

### 2.3 Az idő-kezelés csapdája: helyi dátum ≠ UTC pillanat

A SDD Ch8 Kör 3 kötelező tesztként **„timezone-neutral local date
fixtures"**-t ír elő. A heti elérhetőség **helyi naptári napokhoz** kötődik
(„kedden 20 perc"), nem UTC-időbélyegekhez. A kettő összemosása
nyári-időszámítás-váltáskor és utazáskor csendesen elrontja a tervet.

## 3. Scope

**Benne van:**

1. `PracticeGoal` + metric target modell, **goal lifecycle**-lel.
2. `WeeklyAvailability` — naponta változó, helyi dátum alapú.
3. `LearnerConstraints` — **hard** és **soft** korlát szétválasztva,
   kategóriákkal: equipment, tuning, capability, comfort, accessibility,
   preference, avoid.
4. `RequestValidator` — konfliktus-detektálás a fentiek között.

**NINCS benne (tilos):**

- Tervező-algoritmus, prioritás-motor, ütemező, repository, UI, provider.
- `PracticeGenerationRequest` és a draft-perzisztencia — az a Kör 4.
- Flutter import, `DateTime.now()`, `Random`.
- `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`, más `lib/features/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/practice_goal.dart` | **ÚJ** — cél + metric target + lifecycle |
| `domain/model/weekly_availability.dart` | **ÚJ** — napi bontású elérhetőség |
| `domain/model/learner_constraints.dart` | **ÚJ** — hard/soft korlátok |
| `domain/service/request_validator.dart` | **ÚJ** — konfliktus-validátor |
| `public.dart` | a barrel bővítése az új típusokkal |
| `test/…/domain/*_test.dart` (4 db) | a §6 cellái |
| `docs/rounds/e07-r03-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/**` · minden más `lib/features/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0258)

### 5.1 A hard korlát SOHA nem sérthető, a soft csak költséggel

- **Hard**: a tervező kimenete **nem sértheti meg**. Ha nincs ilyen terv,
  az eredmény hiba vagy csökkentett terv — nem hard-sértő terv.
- **Soft**: preferencia; megsérthető, de a sértés **költséget** kap, amit a
  későbbi körök prioritás-motorja használ.

**NEM elfogadható gyengítés:** a hard korlát „nagyon nagy költségű soft"-ként
kezelése. Az azt jelentené, hogy elég rossz alternatívák mellett a rendszer
mégis megsérti — pont amit a hard szó kizár.

### 5.2 A `comfort` HARD korlátként is megadható

A SDD Ch8 Kör 3 elfogadási feltétele: *„Comfort hard constraintként
kezelhető."* Fájdalom, sérülés vagy fizikai korlát esetén a kényelem nem
preferencia. A kategória tehát **nem** dönti el a keménységet — az külön mező.

### 5.3 A napi hard időmaximum nem sérülhet

Ha egy napra a tanuló 20 percet adott meg hard korlátként, a tervező arra a
napra **nem tehet 21 percet**. A kerekítés is befelé történik.

### 5.4 Az elérhetőség HELYI DÁTUMHOZ kötött, nem UTC-pillanathoz

A modell helyi naptári napot és perceket tárol, nem `DateTime`-ot. Az UTC-re
váltás a megjelenítés és a végrehajtás dolga, nem a domainé.

**NEM elfogadható gyengítés:** `DateTime` mező a domainben „mert egyszerűbb".
Az a nyári-időszámítás-váltást csendes tervhibává teszi.

### 5.5 Túl sok primary goal: WARNING, nem hiba

Több elsődleges cél nem érvénytelen, de a fókusz elvesztésének jele — a
validátor **figyelmeztetést** ad, nem utasítja el. A küszöböt a brief nem
köti meg; a §10-ben dokumentálandó, hogy mi lett és miért.

### 5.6 A custom goal normalizálás nélkül NEM végrehajtható

Szabad szöveges cél megengedett, de amíg nincs ismert skill-re/metrikára
normalizálva, a tervező **nem hajthatja végre** — a validátor ezt jelzi.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hard korlát megsértése a validátorban HIBA, nem költség | `request_validator_test.dart` |
| A2 | Ugyanaz a korlát soft-ként MEGSÉRTHETŐ, költséggel | `request_validator_test.dart` |
| A3 | `comfort` megadható hard korlátként | `learner_constraints_test.dart` |
| A4 | Napi hard időmaximum nem léphető túl (kerekítés befelé) | `weekly_availability_test.dart` |
| A5 | Az elérhetőség helyi dátum alapú; nyári-időszámítás-váltás nem tolja el | `weekly_availability_test.dart` — DST-váltó fixture |
| A6 | Túl sok primary goal → WARNING, nem hiba | `practice_goal_test.dart` |
| A7 | Normalizálatlan custom goal nem végrehajtható | `practice_goal_test.dart` |
| A8 | Goal lifecycle átmenetei kikényszerítettek (érvénytelen átmenet hiba) | `practice_goal_test.dart` |
| A9 | Nincs Flutter import, `DateTime.now()` vagy `Random` | `grep` a diffben + architektúra-őr |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hard korlát nagy költségű soft-ként | **A1** (nem ad hibát) |
| Minden korlát hard | A2 (a soft sértés is hibát adna) |
| A `comfort` fixen soft | **A3** |
| Kerekítés felfelé a napi maximumnál | A4 |
| `DateTime` mező a domainben | **A5** (a DST-fixture eltolódik) |
| Túl sok primary goal → hiba | A6 |
| Normalizálatlan custom goal végrehajthatónak jelölve | A7 |
| A lifecycle bármely átmenetet enged | A8 |

**A napi időkorlát három kötelező cellája** (a határ: a hard maximum):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | hard max 20 perc, terv 19 perc | elfogadva |
| a határon | hard max 20 perc, terv **20** perc | **elfogadva** (a határ inkluzív) |
| fölötte | hard max 20 perc, terv 21 perc | **elutasítva** — hard sértés |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd meg a
hard korlát megsértését költség fejében → az **A1** cellának PIROSNAK kell
lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/domain/request_validator_test.dart test/features/practice_generator/domain/weekly_availability_test.dart test/features/practice_generator/domain/practice_goal_test.dart test/features/practice_generator/domain/learner_constraints_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `learner_constraints.dart` — a hard/soft szétválasztás és a kategóriák.
2. `weekly_availability.dart` — helyi dátum alapú, napi bontás.
3. `practice_goal.dart` — cél, metric target, lifecycle.
4. `request_validator.dart` — a konfliktusok a fenti három között.
5. Tesztek a §6.1 három időkorlát-cellájával és a DST-fixture-rel.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hard/soft összemosása.** A legkényelmesebb megvalósítás egy
  „költség" mező mindenre — és pont ez teszi sérthetővé a sérthetetlent (A1).
- **A `DateTime` csábítása.** Kézenfekvő, és a hiba csak évente kétszer,
  DST-váltáskor jelentkezik — akkor viszont csendben (A5).
- **A validátor túlterjeszkedése.** Konfliktust jelez, de **nem old fel** —
  a javítás a Kör 11 (`PlanValidator és deterministic repair`) dolga.
- **A scope tágulása a Kör 4 felé.** A `PracticeGenerationRequest` és a
  draft-perzisztencia nem ebben a körben van.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `practice_goal.dart`: stabil kódú goal type, priority, lifecycle és metric
  enumok; immutable `MetricTarget` és `PracticeGoal`; az egyetlen engedélyezett
  lifecycle transition graph; normalizálatlan custom goal `isExecutable ==
  false`. A `createdAt` kívülről kapott, UTC-re normalizált időpont; a deadline
  timezone-semleges `LocalDate`.
- `weekly_availability.dart`: `LocalDate` (nincs `DateTime`) és naponta változó
  `DailyAvailability`; perc-alapú preferált kezdés, minimum/target/maximum,
  hard/soft maximum és DST-semleges helyi dátumok.
- `learner_constraints.dart`: equipment, tuning, capability, comfort,
  accessibility, preference és avoid kategóriák; a hard/soft keménység külön
  mező. Hard constrainthez költség nem rendelhető, soft constrainthez pozitív
  költség kötelező.
- `request_validator.dart`: determinisztikus conflict findingok, amelyek hard
  sértésnél error-t, soft sértésnél költséges warningot adnak; nincs javítás,
  schedule-generálás vagy constraint-relaxáció. A napi hard maximum inkluzív.
- `public.dart`: az új domain contractok exportálva.
- A négy célzott tesztfájl lefedi az A1–A8 cellákat, köztük az inkluzív
  19/20/21 perces maximum-hármast és a 2026-03-29 DST-váltó local-date
  fixture-t.

### Valódi-sértés próba

Ideiglenesen a `RequestValidator` hard-constraint ága error helyett warningot
és `softViolationCost: 1`-et adott. A
`flutter test test/features/practice_generator/domain/request_validator_test.dart`
futásban az A1 cella elvárt módon PIROS lett: `Expected: true, Actual: <false>`
(`result.hasErrors`), ezért a teszt valóban a hard kizárást méri. A helyes,
költség nélküli error-ág vissza lett állítva a gate előtt.

### Futtatott ellenőrzések

```text
tools/round-gate.sh test/features/practice_generator/domain/request_validator_test.dart test/features/practice_generator/domain/weekly_availability_test.dart test/features/practice_generator/domain/practice_goal_test.dart test/features/practice_generator/domain/learner_constraints_test.dart
  format: 1508 fájl, 0 módosítás
  analyze: No issues found
  request_validator_test.dart: 2 passed
  weekly_availability_test.dart: 4 passed
  practice_goal_test.dart: 5 passed
  learner_constraints_test.dart: 5 passed
  architecture: Architecture dependencies OK (12 allowlisted deviation(s))
  secrets: Secret scan OK (2562 file(s), 0 finding(s))
  l10n: L10n parity OK (en → hu, 1276 message(s))
```

Nincs eltérés és nincs ki nem futtatott helyi ellenőrzés. CI-dispatch, review
és merge az orchestrátor feladata. Implementációs commit:
`5c42986d feat(planner): model goals availability and constraints`.

## 11. Review — a Claude tölti ki
