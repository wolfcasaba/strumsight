# E07-R10 — AdaptivePracticePlan, day, block és revision domain

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ ba834de8`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 10
- **Kör-azonosító:** `E07-R10`
- **Branch:** `<motor>/e07-r10-adaptive-practice-plan-domain`
- **Előfeltétel:** `E07-R09` merge-elve (recept + sikerkritérium)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — ez a kör az **ADR 0256** (revízió-alapú
  megváltoztathatatlan múlt) implementációja; új döntést nem hoz.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az ADR 0256 négy
> döntését és az R02 `plan_enums.dart` tényleges státusz-enumjait — ez a kör
> azokat használja, nem újakat vezet be. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/adaptive_practice_plan.dart",
  "lib/features/practice_generator/domain/model/practice_day.dart",
  "lib/features/practice_generator/domain/model/practice_block.dart",
  "lib/features/practice_generator/domain/model/plan_revision.dart",
  "lib/features/practice_generator/domain/model/plan_change_set.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/plan/adaptive_practice_plan_test.dart",
  "test/features/practice_generator/plan/plan_revision_test.dart",
  "test/features/practice_generator/plan/plan_change_set_test.dart",
  "test/fixtures/practice_generator/plan/plan_fixtures.dart",
  "docs/rounds/e07-r10-adaptive-practice-plan-domain.md",
]
gate_tests = [
  "test/features/practice_generator/plan/plan_revision_test.dart",
  "test/features/practice_generator/plan/adaptive_practice_plan_test.dart",
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

## 0.0 Pre-flight brief-revízió (Claude, 2026-08-16, AGENTS.md §2 hatáskör)

**Mért hiányosság.** A brief §5.4 és §6.1 `completed → planned` példája egy
`planned` nevű kódolt státuszértéket feltételez, de a kódban ma **egyetlen**
day/block-szintű státusz-enum sem létezik.
`lib/features/practice_generator/domain/model/plan_enums.dart` `PlanStatus`-a
(7 érték: `draft/active/paused/completed/archived/superseded/cancelled`)
**kizárólag** az `AdaptivePracticePlan`-hoz tartozik — a doc-comment szó
szerint "Lifecycle state of an `AdaptivePracticePlan`-to-be", és az SDD
`docs/sdd/08-epic-07-ai-practice-generator.md` **§7.7 "Tervállapot"** ugyanezt
a 7 értéket adja meg terv-szinten (mérve, grep). Az SDD **§16.5 "Block
status"** szakasza egy MÁSIK, 8-elemű listát ad
(`planned/ready/inProgress/completed/skipped/substituted/unavailable/expired`),
de **nincs külön "Day status" szakasz** sehol a fájlban (grep-elve a teljes
`08-epic-07-ai-practice-generator.md`-n: 0 találat "DayStatus"-ra vagy "Day
status"-ra) — a `PracticeDay.status` (SDD §16.2 kódváz) célenumja nincs
explicit megnevezve.

**Döntés — ez NEM új architekturális döntés (nem kap új ADR-t), csak az ADR
0257 stabil-kódú enum mintájának alkalmazása egy SDD-szinten alulspecifikált
résre:**

1. Egy új, stabil-kódú enum, **`PracticeItemStatus`**, a §16.5 nyolc
   értékével **szó szerint**. Ezt használja **mind** a `PracticeDay.status`,
   **mind** a `PracticeBlock.status` — az SDD egyetlen vocabulary-t ad a 16.
   fejezet Day+Block alszakaszaihoz, külön Day-lista nélkül, és a két modell
   (16.2/16.3) közvetlenül egymás után áll a szakaszban.
2. **A helye `practice_block.dart`** — **NEM** `plan_enums.dart`. A
   `plan_enums.dart` **nincs** ennek a körnek az `allowed_paths` listáján, és
   a benne élő öt család mind R02-es, több modellen átívelő alapcsalád (SDD
   Ch8 §7.7/§10.2/§14.2/§16.4/§17.2) — ezzel szemben a modell-lokális enumok
   a saját modelljük fájljában élnek, mért precedens:
   `PracticeGoalStatus`/`PracticeGoalType`/`GoalPriority`/`MetricDirection`
   a `practice_goal.dart`-ban, `SuccessCriterionKind` a `success_criteria.dart`-ban,
   `CatalogRevisionMismatch`/`CandidateExclusionReason` a
   `practice_catalog_snapshot.dart`-ban. Ez a döntés ezt a mért konvenciót
   követi, és elkerül egy indokolatlan `allowed_paths`-bővítést.
   `practice_day.dart` importálja a típust `practice_block.dart`-ból.
3. **Kötelező mintakövetés.** A `canTransitionTo`/`transitionTo` pár
   pontosan a már bevált `PracticeGoalStatus`/`PracticeGoal` mintát tükrözze
   (`lib/features/practice_generator/domain/model/practice_goal.dart:204-240`):
   `bool canTransitionTo(PracticeItemStatus next) => switch (status) { … }`
   plusz egy `StateError`-t dobó `transitionTo(next)`, amely — mivel minden
   modell immutable — egy ÚJ példányt ad vissza a régi helyett (ahogy
   `PracticeGoal.transitionTo` teszi). Mindkét osztályon (`PracticeDay`,
   `PracticeBlock`) külön-külön implementálva.
4. **A pinnelt átmenet-tábla** (ebből következik a §6.1 `completed → planned`
   cellája: `completed` terminális, minden kimenő éle tiltott):

   | Forrás | Legális célok |
   |---|---|
   | `planned` | `ready`, `inProgress`, `substituted`, `unavailable`, `skipped`, `expired` |
   | `ready` | `inProgress`, `substituted`, `unavailable`, `skipped`, `expired` |
   | `inProgress` | `completed`, `skipped`, `substituted`, `unavailable` |
   | `completed` | *(terminális — immutable, ADR 0256 §Döntés 2, brief §5.3)* |
   | `skipped` | *(terminális)* |
   | `substituted` | *(terminális EBBEN a revízióban — a csere egy ÚJ revízióban jelenik meg, ADR 0256 §Döntés 1/3)* |
   | `unavailable` | *(terminális EBBEN a revízióban)* |
   | `expired` | *(terminális)* |

   `adaptive_practice_plan_test.dart`-ban mind a nyolc forrás-állapot legális
   ÉS legalább egy tiltott célja is tesztelve legyen (nem csak a brief §5.4
   egyetlen `completed → planned` példája) — ez a §6.1 A5 cellájának teljes
   bizonyítéka, nem csak egy mintavétel.

5. **Kifejezetten KÍVÜL esik ezen a körön** (ne építsd meg, és ne is hagyd ki
   emiatt az immutability-ellenőrzést): az SDD §16.7 "kivéve explicit
   adatkorrekciót audit loggal" kivétele. A `completed` tartalom védelme (§5.3,
   A4) EBBEN a körben **feltétel nélküli** hiba — a jövőbeli audit-log-os
   felülbírálási útvonal egy KÉSŐBBI kör (validator/repair, Kör 11 vagy azon
   túl) döntése.

6. **Nem blokkoló javaslat** (implementer szabadsága — egyetlen
   acceptance-cella sem méri a pontos alakot): a `generationProvenance` és
   `policyVersions` mezőkhöz természetes, már létező építőelemek a
   `GenerationRequestId` (R04, `practice_generation_request.dart`) és a
   `PracticeCatalogSnapshot.catalogRevision`/`.contentRevision` (R08,
   `practice_catalog_snapshot.dart`) — nem kötelező ezeket használni, de ha
   szabadon dönt, ne találjon fel egy párhuzamos azonosítót ott, ahol már
   van egy.

**Erőforrás-tulajdonlás ellenőrzés (pipeline-prompt §1, 2. mérési szabály):**
N/A — ez a kör tisztán immutable domain modell, nincs lease/lock/handle/
subscription a scope-ban, nincs `.acquire(` hívási lánc, amit mérni kellene.

### 0.0.1 Kör közbeni kiegészítés (Claude, 2026-08-16, az implementer első `stopped` jelzése után)

A Terra az első fordulóban `stopped`-ot jelzett: „Scope conflict: reusable
test fixture needs a fourth test file, but brief permits exactly three test
files." — a három teszt (`adaptive_practice_plan_test.dart`,
`plan_revision_test.dart`, `plan_change_set_test.dart`) mindegyike ugyanazt a
builder-gráfot igényli (typed ID-k, egy teljes `AdaptivePracticePlan`/
`PracticeDay`/`PracticeBlock`/`ExerciseCandidate` felépítő lánc,
`resolveCandidate`, a nyolc `PracticeItemStatus` átmenet-térképe) — ezt
triplikálni valódi karbantartási kockázat (a három másolat szét tud csúszni).

**Mért precedens.** A `practice_generator` SAJÁT teszt-fájában (mind a 19
meglévő `_test.dart`) MA egyetlen megosztott helper sincs — ez tehát ÚJ minta
ennek a feature-nek. De a REPO EGÉSZÉBEN már négy helyen létezik pontosan ez a
minta, egységes elnevezéssel: `test/fixtures/analysis/insights/insight_fixtures.dart`,
`test/fixtures/vision/posture/posture_fixtures.dart`,
`test/fixtures/vision/picking/picking_fixtures.dart`,
`test/fixtures/vision/tracks/track_fixtures.dart` — mind
`test/fixtures/<feature>/<terület>/<név>_fixtures.dart` alakban.

**Döntés:** EGY új fájl, `test/fixtures/practice_generator/plan/plan_fixtures.dart`,
felvéve az `allowed_paths`-ba (fent) és a §4 táblába — a mért,
repo-szintű konvenciót követve, nem egy önkényes helyet kitalálva. Ez
kizárólag TESZT-kód (nincs production/viselkedési kockázat), és szigorúan a
három meglévő teszt-fájl közös setupját fedi — nem general-purpose
test-support modul, nem kerül a megosztott `test/support/`-ba (az más
feature-ek közötti, session/gateway-szintű fake-eket tart, ide nem illik).

A Terra a meglévő, még nem commitolt munkáját (a három teszt-fájl, jelenleg
`plan_fixtures.dart` nélkül, ezért fordítás előtti állapotban) folytatja —
NEM kezdi újra.

---

## 1. Cél

A többnapos terv kanonikus, **immutable és revíziózott** dokumentummodellje
(SDD Ch8 Kör 10) — az ADR 0256 megvalósítása.

## 2. Jelenlegi állapot — mért tények

- Az ADR 0256 rögzíti: a terv revíziókból áll, rögzített revízió **nem
  módosul**, az eredmény külön artefaktum, az „aktuális" egy **mutató**, és
  minden revízió megnevezi a keletkezésének **okát**.
- Az R02 typed ID-i (`PlanId`, `DayId`, `BlockId`, `RevisionId`) és stabil
  kódú enumjai adottak.
- Az R09 receptjei és sikerkritériumai a blokk tartalmát adják.

## 3. Scope

**Benne van:** `AdaptivePracticePlan` / `PracticeDay` / `PracticeBlock`
státuszokkal · `PlanRevision` (revízió-szám + **teljes pillanatkép**) ·
`PlanChangeSet` (gépi olvasható diff) · generálási provenance és
policy-verziók · UI-nak szánt összefoglaló DTO-k.

**NINCS benne (tilos):** validátor/repair (Kör 11) · tervező-algoritmus
(Kör 12-től) · repository (Kör 19) · UI · Flutter, `DateTime.now()`, `Random` ·
más `lib/features/**`, `lib/app/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/adaptive_practice_plan.dart` | **ÚJ** — a terv |
| `domain/model/practice_day.dart` | **ÚJ** |
| `domain/model/practice_block.dart` | **ÚJ** |
| `domain/model/plan_revision.dart` | **ÚJ** — revízió + provenance |
| `domain/model/plan_change_set.dart` | **ÚJ** — gépi diff |
| `public.dart` | a barrel bővítése |
| `test/…/plan/*_test.dart` (3 db) | a §6 cellái |
| `test/fixtures/practice_generator/plan/plan_fixtures.dart` | **ÚJ, §0.0.1-ben engedélyezve** — a 3 teszt közös builder-je |
| `docs/rounds/e07-r10-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0256 megvalósítása)

### 5.1 A revízió-szám SZIGORÚAN MONOTON

Minden új revízió száma nagyobb az előzőnél. Azonos vagy csökkenő szám → hiba.

### 5.2 A rögzített revízió IMMUTABLE

Nincs olyan művelet, amely egy már rögzített revízió mezőit írja. A revízió
teljes pillanatképet hordoz, nem hivatkozást a „élő" tervre.

**NEM elfogadható gyengítés:** a revízió csak a különbséget tárolja, a
tartalmat az aktuális tervből olvassa. Az visszamenőleg megváltoztatná a
múltat, amikor az aktuális változik.

### 5.3 A befejezett blokk NEM módosítható csendben

`completed` státuszú blokk vagy nap tartalmának változtatása **hiba**, nem
néma felülírás. Ha a jövő átrendeződik, az új revízióban történik, a lezárt
múlt érintetlenül.

### 5.4 A státusz-átmenetek KIKÉNYSZERÍTETTEK

Csak az engedélyezett átmenetek mennek végbe (pl. `completed` → `planned`
nem). Érvénytelen átmenet → hiba.

### 5.5 A change set GÉPI OLVASHATÓ és teljes

A két revízió közti különbség strukturált adat (mi került be, mi tűnt el, mi
változott, és **miért**) — nem szabad szöveg. Erre épül az UI magyarázata és
a modell-javaslatok hatásának mérése (ADR 0256 §4).

### 5.6 Az összefoglaló DTO nem szivárogtat érzékeny szöveget

A tanuló szabad szöveges megjegyzése nem kerül a summary-be (ADR 0260 §4
folytatása).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A revízió-szám szigorúan monoton; azonos/csökkenő → hiba | `plan_revision_test.dart` |
| A2 | Rögzített revízió módosítási kísérlete → hiba | ugyanott |
| A3 | A revízió TELJES pillanatképet hordoz (az aktuális változása nem hat rá) | ugyanott |
| A4 | `completed` blokk módosítása → hiba, nem néma felülírás | `adaptive_practice_plan_test.dart` |
| A5 | Érvénytelen státusz-átmenet → hiba | ugyanott |
| A6 | A change set strukturált, és megnevezi az okot | `plan_change_set_test.dart` |
| A7 | A terv JSON verziózott, round-trip veszteségmentes | `adaptive_practice_plan_test.dart` |
| A8 | A summary DTO nem tartalmaz szabad szöveges megjegyzést | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A revízió csak diffet tárol, tartalmat az élőből olvas | **A3** |
| `completed` blokk csendben felülírva | **A4** |
| Bármely státusz-átmenet engedve | A5 |
| A change set szabad szöveg | A6 |
| A revízió-szám újrahasználható | A1 |
| A summary tartalmazza a megjegyzést | A8 |

**A revízió-szám három kötelező cellája** (a határ: az aktuális revízió):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | új revízió száma = aktuális − 1 | **hiba** |
| a határon | új revízió száma = aktuális | **hiba** (nem lehet azonos) |
| fölötte | új revízió száma = aktuális + 1 | elfogadva |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd meg egy
rögzített revízió mezőjének írását → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/plan/plan_revision_test.dart test/features/practice_generator/plan/adaptive_practice_plan_test.dart test/features/practice_generator/plan/plan_change_set_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `practice_block.dart` és `practice_day.dart` — státuszokkal.
2. `adaptive_practice_plan.dart` — provenance, policy-verziók.
3. `plan_revision.dart` — monoton szám, TELJES pillanatkép, immutabilitás.
4. `plan_change_set.dart` — strukturált diff okkal.
5. Tesztek a §6.1 három revízió-cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A diff-alapú revízió.** Kevesebb tárhely, és visszamenőleg megváltoztatja
  a múltat, amikor az aktuális változik (A3). Ez a kör legfontosabb csapdája.
- **A `completed` „ártatlan" frissítése.** Egy átütemezés kényelmesen
  hozzányúlna a lezárt naphoz is (A4).
- **A szabad szöveges change-reason.** Olvashatóbb, de géppel nem mérhető, és
  az ADR 0256 §4 célja (a javaslatok hatásának mérése) elveszne (A6).

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `practice_block.dart`: nyolc stabil-kódú `PracticeItemStatus`, pinnelt
  átmenetmátrix, immutable `PracticeBlock`, JSON és completed-content guard.
- `practice_day.dart`: ugyanaz a státusz-contract és immutable napmodell,
  JSON-nal és completed-day content guarddal.
- `adaptive_practice_plan.dart`: verziózott, veszteségmentes terv-JSON,
  teljes goal/prescription round-trip, provenance/policy-verziók és
  user-note-mentes `PracticePlanSummary`.
- `plan_revision.dart`: szigorúan monoton revision-szám, teljes snapshot és
  `final` mezők; a korábbi revision csak validációs bemenet, nem élő tartalom.
- `plan_change_set.dart`: typed változástípusok és indokok, strukturált
  before/after értékekkel.
- `public.dart`: a hat új domain-contract publikus exportja.
- A három tervteszt közös, feature-local builderét a jóváhagyott
  `test/fixtures/practice_generator/plan/plan_fixtures.dart` adja.

### Acceptance evidence

- A1–A3: `plan_revision_test.dart` a revision alatt/egyenlő/fölötte három
  celláját, a teljes snapshotot és az írás-tilalmat méri.
- A4–A5: `adaptive_practice_plan_test.dart` mind a nyolc státusz legalább egy
  elfogadott (nem terminális) és egy tiltott célját blockon és napon külön
  méri, továbbá a completed block replacement hibáját.
- A6: `plan_change_set_test.dart` typed indokot és strukturált before/after
  adatot mér.
- A7–A8: a plan JSON round-trip teljes értékegyenlőségét, a summary user-note
  redakcióját méri.

### Valódi-sértés próba

`PlanRevision.snapshot` ideiglenesen nem-`final` mező volt. A
`flutter test test/features/practice_generator/plan/plan_revision_test.dart`
futásban az A2 teszt elvártan PIROS lett: a dynamic assignment visszatért egy
`AdaptivePracticePlan`-nel a várt `NoSuchMethodError` helyett. A mezőt azonnal
visszaállítottam `final`-ra; a teljes célzott tesztcsomag ezután zöld.

### Futtatott ellenőrzések

- `flutter test test/features/practice_generator/plan/plan_revision_test.dart test/features/practice_generator/plan/adaptive_practice_plan_test.dart test/features/practice_generator/plan/plan_change_set_test.dart` — **40 passed**.
- `flutter analyze lib/ test/ tool/` — **No issues found**.
- `tools/round-gate.sh test/features/practice_generator/plan/plan_revision_test.dart test/features/practice_generator/plan/adaptive_practice_plan_test.dart test/features/practice_generator/plan/plan_change_set_test.dart` — **format/analyze/3 célzott teszt/architecture/secrets/l10n zöld**.

### Eltérés / nem futtatott ellenőrzés

- Nincs funkcionális eltérés. Backend vagy natív scope nincs, ezért nincs
  backend pytest vagy lokális APK-build.

## 11. Review — a Claude tölti ki
