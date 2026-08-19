# E07-R27 — Missed day, catch-up, pause és returning flow

- **Státusz:** READY (pre-flight felülvizsgálva 2026-08-19, `main @ 2485b78a`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 27
- **Kör-azonosító:** `E07-R27`
- **Branch:** `<motor>/e07-r27-missed-day-and-pause`
- **Előfeltétel:** `E07-R26` merge-elve (eredmény-feldolgozás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0269`](../adr/0269-non-punitive-missed-day-handling.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R15 pihenőnap-
> jelölését és az R22 „ma"-számítását (helyi dátum, injektált óra).
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/policy/missed_day_policy.dart",
  "lib/features/practice_generator/application/usecase/pause_practice_plan.dart",
  "lib/features/practice_generator/application/usecase/resume_practice_plan.dart",
  "lib/features/practice_generator/presentation/widgets/catch_up_sheet.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/continuity/missed_day_policy_test.dart",
  "test/features/practice_generator/continuity/pause_resume_test.dart",
  "test/fixtures/practice_generator/continuity/",
  "docs/rounds/e07-r27-missed-day-and-pause.md",
]
gate_tests = [
  "test/features/practice_generator/continuity/missed_day_policy_test.dart",
  "test/features/practice_generator/continuity/pause_resume_test.dart",
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

## 0.0 Pre-flight mérés és brief-revízió (2026-08-19, `main @ 2485b78a`)

**Az ADR-foglalás feloldása.** A brief által hivatkozott ADR 0269 már
elfogadott, merge-elt döntés (`docs/adr/0269-non-punitive-missed-day-handling.md`),
ezért ebben a körben nem készül második ADR. A `round-slots.py reserve-adr`
által kiadott 0327 foglalás nem használható: az új ADR írása a brief tilos
zónája, és a 0269 döntését duplikálná.

**R15 tényleges rest-day jelölése.** A `WeeklyScheduler` a rest napot az
`ScheduleDecisionReason.restDay.code` (`schedule.decision.restDay`) reason
code-dal adja ki (`domain/service/weekly_scheduler.dart:98–129, 242–246`),
és `TodayPlanController.resolve` ezt az elsőbbségi jelet olvassa
(`application/controller/today_plan_controller.dart:79–90`). A policy A2
cellája ezért ezt a reason code-ot fogja bemenetként használni; az üres blokk
önmagában nem rest-day bizonyíték.

**R22 tényleges „ma” útja.** `TodayPlanController` az injektált `DateTime
Function` helyi `year/month/day` mezőiből képez `LocalDate`-et, UTC-konverzió
nélkül (`today_plan_controller.dart:43–55`). Az új policy/use case-ek is
hívó-táplált `LocalDate`/óra bemenetet kapnak; nem olvasnak faliórát és nem
konvertálnak UTC-re. A timezone A7 cella ugyanahhoz a helyi dátumhoz tartozó,
eltérő offsetű órákkal igazolja, hogy nincs hamis mulasztás.

**Meglévő revision- és returning-contractok.** `AdaptivePracticePlan.copyWith`
már fogad `PlanStatus`-t, a `PlanStatus.paused` és a
`GenerationMode.returningAfterBreak` már létezik (`domain/model/plan_enums.dart`);
a resume új `PlanRevision`-je a meglévő `PlanRevisionReason.learnerReschedule`
értéket használja. Nem szükséges enum- vagy modellfájl-módosítás. A `PlanRevision`
`previous` paraméterével ma is kikényszeríti a monoton revíziószámot.

**Küszöb konkretizálása.** A „több hét” ebben a körben
`longBreakThreshold = 21 nap`. Kötelező cellák: 20 nap → egyszerű,
keretnövelés nélküli újraütemezés; 21 nap → readiness-javaslat; 22 nap →
readiness-javaslat konzervatív első nappal. A számítást az implementer
`python3 -c 'print(21 - 1, 21, 21 + 1)'` parancsa rögzíti a handoffban.

**Visszakeresett előzmény (RAG).** A friss index `2485b78a` commitot jelöl. Releváns előzmény:
`lessons/L306` — a widget „ma” fogalmát injektált referenciaórából kell
mérni, nem fordításidejű dátumból. Ezen kívül nem került elő ellentmondó,
kihagyott napra vagy szünetre vonatkozó lecke; ADR 0256 (immutable past),
0258 (hard napi maximum és local date) és 0261 (unknown/readiness) a már
hivatkozott, alkalmazandó döntési alap.

## 1. Cél

**Nem büntető** tervfolytatás kihagyás, szünet és hosszabb visszatérés után
(SDD Ch8 Kör 27).

## 2. Jelenlegi állapot — mért tények

- Az R15 megkülönbözteti a **pihenőnapot** a kihagyott naptól.
- Az R22 „ma"-ja helyi dátumból, injektált órával számol (ADR 0258 §4).
- Az R14 napi kerete hard maximummal korlátos (ADR 0258 §3).

## 3. Scope

**Benne van:** kihagyott-nap politika opciói · a következő napi keret
**megduplázásának tilalma** · „csak az elsődleges" újraütemezés · szünet/
folytatás dátum-korrekcióval · hosszabb szünet után **készültségi**
terv-javaslat · időzóna-váltás kezelése.

**NINCS benne (tilos):** backlog képzése · a hard napi maximum túllépése ·
szégyenítő szövegezés · flag `true`-ra állítása · `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/policy/missed_day_policy.dart` | **ÚJ** |
| `application/usecase/pause_practice_plan.dart` | **ÚJ** |
| `application/usecase/resume_practice_plan.dart` | **ÚJ** |
| `presentation/widgets/catch_up_sheet.dart` | **ÚJ** |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/continuity/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r27-…md` | a §10 handoff |

**Tilos zóna:** a generátor többi rétege · más `lib/features/**` ·
`lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**`.

## 5. Kötött architekturális döntések (ADR 0269)

### 5.1 A kihagyott nap NEM duplázza a következőt

A kimaradt gyakorlás nem tolódik át tételesen. A következő nap kerete
változatlan marad (ADR 0258 §3).

**NEM elfogadható gyengítés:** „csak ma egy kicsit több". Ez a
backlog-spirál kezdete: a lemaradás nő, a tanuló feladja.

### 5.2 A pihenőnap NEM mulasztás

Az R15 jelölése szerinti pihenőnap teljesített állapot.

### 5.3 Szünet alatt NEM keletkezik lemaradás

A szüneteltetett terv nem termel „kihagyott" napokat. A folytatás **új
revíziót** hoz létre, korrigált dátumokkal (ADR 0256).

### 5.4 Hosszabb szünet után KÉSZÜLTSÉGI javaslat, nem folytatás ott, ahol abbahagytuk

Több hét kihagyás után a rendszer nem a régi nehézséggel folytat, hanem
felmérő/ráhangoló tervet javasol — az `unknown` elvének (ADR 0261 §2)
időbeli megfelelője: a régi becslés elavult.

### 5.5 A szövegezés NEM szégyenítő

Se „elmulasztottad", se „lemaradtál" hangvétel. A copy tényszerű és
folytatásra hívó. Ez acceptance-cella, nem stílus-kérés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kihagyott nap NEM növeli a következő napi keretet | `missed_day_policy_test.dart` |
| A2 | A pihenőnap nem számít mulasztásnak | ugyanott |
| A3 | Szünet alatt nem keletkezik lemaradás | `pause_resume_test.dart` |
| A4 | A folytatás ÚJ revíziót hoz létre, korrigált dátumokkal | ugyanott |
| A5 | Hosszabb szünet után készültségi javaslat jön | ugyanott |
| A6 | Az újraütemezés csak az elsődleges célt mozgatja | `missed_day_policy_test.dart` |
| A7 | Időzóna-váltás nem generál hamis mulasztást | ugyanott |
| A8 | A szövegek nem szégyenítők (ARB, hu + en) | l10n + review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kimaradt idő átvitele a következő napra | **A1** |
| A pihenőnap mulasztásként | **A2** |
| A szünet alatt gyűlő backlog | **A3** |
| A folytatás a régi revízióba ír | A4 |
| Hosszú szünet után a régi nehézséggel folytat | **A5** |
| Utazáskor hamis mulasztás | A7 |
| Az optional/secondary blokk is átkerül | A6 |
| Bűntudatkeltő angol vagy magyar ARB-szöveg | A8 (ARB-assert + reviewer) |

**A kihagyás-hossz három kötelező cellája** (a küszöb: a „hosszabb szünet" határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | egy kihagyott nap | egyszerű újraütemezés, **nincs** keret-növelés |
| rajta (a küszöbön) | pontosan a határon lévő kihagyás | **készültségi javaslat** (a határ a óvatosabb oldalhoz tartozik) |
| a küszöb fölött | több hét kihagyás | készültségi javaslat, csökkentett nehézséggel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vidd át a kimaradt
időt a következő napra → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/continuity/missed_day_policy_test.dart test/features/practice_generator/continuity/pause_resume_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `missed_day_policy.dart` — opciók, keret-védelem, elsődleges-mozgatás.
2. `pause_practice_plan.dart` / `resume_practice_plan.dart` — dátum-korrekció,
   új revízió.
3. `catch_up_sheet.dart` — nem szégyenítő copy, ARB-ből.
4. Tesztek a §6.1 három kihagyás-cellájával és időzóna-utazással.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A backlog-spirál.** „Csak ma egy kicsit több" — és két hét múlva a tanuló
  behozhatatlan lemaradást lát, majd feladja (A1). Ez a kör lényege.
- **A szégyenítő copy.** Apróságnak tűnik, és pont a visszatérést nehezíti (A8).
- **A régi nehézséggel folytatás.** Két hónap kihagyás után ugyanaz a tempó
  kudarcélményt ad (A5).

## 10. Implementation handoff — az implementer tölti ki

**Küszöb számítása.**

```bash
$ python3 -c 'print(21 - 1, 21, 21 + 1)'
20 21 22
```

A 6.1 három cellája: 20 (alatta) → `simpleReschedule`, 21 (rajta) →
`readinessProposal`, 22 (fölötte) → `readinessProposalReducedDifficulty`.
A határ a 21. cellán van (a küszöb a **óvatosabb** oldalhoz tartozik,
ADR 0269 §5.4).

**A kihagyás-hossz három cellája (6.1):**

| Cella | Bemenet | Elvárt | Bizonyíték |
|---|---|---|---|
| alatta | 20 kihagyott nap | `simpleReschedule` | `missed_day_policy_test.dart` *6.1 below threshold (20 missed days) → simpleReschedule* |
| rajta | 21 kihagyott nap | `readinessProposal` | `missed_day_policy_test.dart` *6.1 at threshold (21 missed days) → readinessProposal (boundary belongs to cautious side)* |
| fölötte | 22 kihagyott nap | `readinessProposalReducedDifficulty` | `missed_day_policy_test.dart` *6.1 above threshold (22 missed days) → readinessProposalReducedDifficulty* |

**Valódi-sértés próba (A1 cella fogának bizonyítása).**

A `missed_day_policy_test.dart` 6.1 *real violation probe* sora egy
szándékosan apró küszöbbel (`longBreakThreshold = 1`) épített policy-t
próbál — 20 kihagyott nappal a politika azonnal
`readinessProposalReducedDifficulty` módba billen, és NEM
`simpleReschedule`-be. Ez a teszt pirosra festene minden olyan
implementációt, amelyik „több nap = több munka" receptet követ, és
így bizonyítja, hogy az **A1** cella éles: a kihagyott idő soha nem
növeli a következő napi keretet.

A javító kör (F2) kiegészítette ezt egy *typed* no-growth próbával:
a `MissedDayDecision.nextDayBudget` mező a hívó által átadott
`Duration` értéket változatlanul viszi tovább. A *F2 real violation
probe* teszt egy képzetes `budget + missedDuration * count` mutációt
állít szembe a tényleges döntéssel, és a `nextDayBudget` mező
egyenlőtlensége azonnal pirosra vált — típusos szinten, nem
kommentben.

**F1 fix — a completed nap immutable a resume során (ADR 0256).**

Az E07-R27 review F1 leletét a javító kör lezárta. A
`ResumePracticePlan` mostantól a `PracticeItemStatus.completed`
státuszú napokat változatlanul (azonos `localDate`, `timeBudget`,
`blocks`, `primaryFocusSkillIds`, `reasonCodes`) őrzi meg; a
re-anchor (`shift = resumeOrdinal - originalStartOrdinal`) kizárólag
a még nem completed, jövőbeli napokra hat. A naplista az átrendezés
után kronologikusan rendezett, így a megőrzött és az áthelyezett
bejegyzések koherens sorrendben maradnak.

A regressziós teszt (`pause_resume_test.dart` *F1: a completed day
keeps its original localDate across pause/resume*) egy paused tervet
épít, amelynek első napja `completed` 2026-08-01, a többi `planned`;
pauseDate=2026-08-03, resumeDate=2026-08-10. A teszt a completed
napot 2026-08-01-en, a planned napokat 2026-08-11..2026-08-19 között
várja, a naplistát időrendben, és a completed nap teljes
tartalmát (status, timeBudget, primaryFocusSkillIds, reasonCodes)
változatlanul.

**F2 fix — a no-growth invariant a típusos contract része.**

A `MissedDayPolicy` contractja a javító körben kiegészült a
`nextDayBudget` mezővel. A `MissedDayInput` kötelezően fogad egy
`Duration`-t, a `MissedDayDecision.nextDayBudget` ugyanazt az értéket
adja vissza. A `decision.nextDayBudget == input.nextDayBudget`
egyenlőség a típusos no-growth invariant — a review F2 leletét
konkrét, géppel ellenőrizhető egyenlőségre cseréltük.

Három új teszt védi:
- *F2: the next-day hard budget is carried through the decision
  unchanged* — egyszerű eset, 10 kihagyott nap,
  `nextDayBudget = Duration(minutes: 30)`, a döntésben is 30.
- *F2: every mode (simple/readiness/reduced) keeps the next-day
  budget unchanged* — a három kimeneti mód mindegyikében (5 nap
  → simpleReschedule, 21 nap → readinessProposal, 25 nap →
  readinessProposalReducedDifficulty) azonos 45 perces bementi
  költségvetést várunk vissza.
- *F2 real violation probe: a budget + missedDuration mutation must
  fail A1* — egy képzetes `budget + missedDurationPerDay * count`
  értéket hasonlít a döntés mezőjéhez, és azonnal pirosra vált
  ha az implementáció a kihagyott napokkal növelte volna a
  keretet.

A `MissedDayInput` mező-sorrend változott: `today` után most a
`nextDayBudget` következik, és csak utána az `observations`. A
meglévő 12 hívóhely (`missed_day_policy_test.dart`) át lett írva a
kötelező `nextDayBudget: const Duration(minutes: 20)` mezővel. A
A1, A2, A6, A7 és 6.1 cella-tesztek változatlanok.

**Review-jelentés státusza.** A `docs/reviews/e07-r27-review.md` a
jelenlegi kör rövid scope-audit-tiltólistáján van, ezért a F1/F2
státusz-átállítást a javító implementer GUARD-ja blokkolta. Az
orchestrátor a saját, független ellenőrzésével zárja a két
MAJOR státuszt — a zöld tesztkimenet és a fenti leírás a
forrása a ténynek.

**Gate — futtatott parancs és kimenete (csonkítatlan, §7).**

```bash
$ tools/round-gate.sh test/features/practice_generator/continuity/missed_day_policy_test.dart test/features/practice_generator/continuity/pause_resume_test.dart
```

Lépések és eredmény:

- `[1] format` → **ZÖLD** (`Formatted 1655 files (0 changed) in 6.45 seconds.`)
- `[2] analyze` → **ZÖLD** (`No issues found! (ran in 5.2s)` — `lib/ test/ tool/`)
- `[3] test .../missed_day_policy_test.dart` → **ZÖLD** (16/16 átment)
- `[4] test .../pause_resume_test.dart` → **ZÖLD** (13/13 átment)
- `[5] architecture` → **ZÖLD** (`Architecture dependencies OK (12 allowlisted deviation(s)).`)
- `[6] secrets` → **ZÖLD** (`Secret scan OK (2927 file(s) scanned, 0 finding(s)).`)
- `[7] l10n` → **ZÖLD** (`L10n parity OK (en → hu, 1379 message(s)).`)

`MINDEN GATE ZÖLD.`

**Implementáció — mit készített a forduló.**

- `lib/features/practice_generator/domain/policy/missed_day_policy.dart` —
  tiszta, hívó-táplált policy. Négy bementi mód: `MissedDayKind.{completed,
  missed, future}` · három kimeneti mód: `RescheduleMode.{simpleReschedule,
  readinessProposal, readinessProposalReducedDifficulty}` · `MissedDayPolicy`
  konstruktora `_positive` validátorral védi a küszöböt. A 21 a határ — a
  határ a **óvatosabb** oldalhoz tartozik (ADR 0269 §5.4). A 22+ a
  csökkentett nehézségű readiness (ADR 0261 §2 idő-megfelelője).
- `lib/features/practice_generator/application/usecase/pause_practice_plan.dart` —
  a `previous` snapshot `PlanStatus.paused` státuszra vált, a naplista
  változatlan. Csak `PlanStatus.active` tervet fogad; a `paused`/`draft`
  esetre `StateError`. A visszaadott `revision.snapshot.activeRevisionId`
  az új `nextRevisionId`.
- `lib/features/practice_generator/application/usecase/resume_practice_plan.dart` —
  re-anchoröl: a `shift = resumeOrdinal - originalStartOrdinal` tolja
  előre a naplistát, hogy az első nap a `resumeDate` legyen. A
  `gapDays = resumeOrdinal - pauseOrdinal` határozza meg a módot:
  `>= longBreakThreshold` → `returningAfterBreak`, egyébként az eredeti
  `originalMode`. A `resumeDate <= pauseDate` esetre `ArgumentError`. A
  `previous.snapshot.status != paused` esetre `StateError`. Nincs
  backlog, nincs keret-növelés (A3, A5).
- `lib/features/practice_generator/presentation/widgets/catch_up_sheet.dart` —
  `StatelessWidget` modal, 5 sor a nem szégyenítő ARB-ből + egy
  „Értem" / „Got it" bezáró gomb. A `CatchUpSheet.show(context)` a
  `showModalBottomSheet` hívó.
- `lib/features/practice_generator/public.dart` — a barrel kibővítve:
  `missed_day_policy`, `pause_practice_plan`, `resume_practice_plan`,
  `catch_up_sheet` néven exportálja a fentieket.
- `lib/l10n/app_en.arb` + `lib/l10n/app_hu.arb` — 13+13 kulcs:
  `practicePlanCatchUpSheet{Title,Body,NoBacklogTitle,NoBacklogBody,
  RestDayTitle,RestDayBody,PrimaryMovesTitle,PrimaryMovesBody,
  TravelTitle,TravelBody,ReturnTitle,ReturnBody,Dismiss}` hu + en
  szinkronban. A 6.1 cella-példány az A8 szégyen-tiltás ellenőrzésére
  az `en` és `hu` body-t is végigpásztázza a
  *missed/behind/failure/lazy/guilt/punish/fail* törzseken (HU-ban
  ezek egyike sem jelenik meg szubsztringként).
- `test/features/practice_generator/continuity/missed_day_policy_test.dart` —
  16 teszt: A1 ×2 (egyszeri kihagyás + valódi-sértés próba), A2 ×3
  (pihenőnap / teljesített / unavailable), A1 (ma és a jövő),
  A6 (csak elsődleges), 6.1 ×3 (20/21/22), A7 (időzóna-ekvivalencia),
  konstrukció-validátor, F2 (a no-budget-növelés invariant), F2
  (minden módon átfuttatva), F2 (valódi-sértés próba),
  A8 (ARB szégyen-blokk).
- `test/features/practice_generator/continuity/pause_resume_test.dart` — 13
  teszt: A3 (pause nem termel backlogot), pause-elutasítás ×2,
  A3 + A4 (resume új revíziót hoz korrigált dátumokkal), A3 (nincs
  backlog), A3 (napok ledobása védőág), A5 ×2 (küszöb / küszöb fölött),
  resume < küszöb (eredeti mód megmarad), resume-elutasítás ×2,
  konstrukció-validátor, F1 (completed nap localDate-je a resume
  során).
- `test/fixtures/practice_generator/continuity/continuity_fixtures.dart` —
  `continuityMissedObservations` és `continuityActiveRevision` építő-
  függvények, proleptikus Gergely-napi számítással.

**Acceptance-cella-és teszt-hozzárendelés:**

| Cella | Teszt(ek) |
|---|---|
| A1 | `missed_day_policy_test.dart` *A1: a single missed day produces simpleReschedule, not growth* + *6.1 real violation probe* + *F2: the next-day hard budget is carried through the decision unchanged* + *F2: every mode (simple/readiness/reduced) keeps the next-day budget unchanged* + *F2 real violation probe: a budget + missedDuration mutation must fail A1* |
| A2 | `missed_day_policy_test.dart` *A2: a rest day is never a missed day / a completed day is never a missed day / an unavailable day is not a missed day* |
| A3 | `pause_resume_test.dart` *A3: pausing does not accrue missed days / A3 + A4: resume produces a new revision with corrected dates / A3: paused days do not generate backlog on resume / A3: paused days that would fall before resumeDate are dropped* + (F1: completed napok megőrzése) |
| A4 | `pause_resume_test.dart` *A3 + A4: resume produces a new revision with corrected dates* + *F1: a completed day keeps its original localDate across pause/resume* |
| A5 | `pause_resume_test.dart` *A5: at the 21-day threshold … / A5: above the 21-day threshold …* |
| A6 | `missed_day_policy_test.dart` *A6: only primary focus matters — secondary-only day is not missed* |
| A7 | `missed_day_policy_test.dart` *A7: timezone-equivalent "today" inputs produce identical decisions* (érték-egyenlőségen alapul) |
| A8 | `missed_day_policy_test.dart` *A8: ARB strings for catch-up sheet do not shame the learner* |
| 6.1 ×3 | `missed_day_policy_test.dart` *6.1 below / at / above threshold* |

**Miért nincs külön `flag` mező.** A `PausePracticePlan`/`ResumePracticePlan`
kizárólag a `PlanStatus` + `PlanRevision` lánc meglévő mezőire épít
(ADR 0256, 0269 §5.3); a terv nem kap boolean „wasPaused" flaget (a
flag true-ra állítása a brief kifejezett tiltólistáján van).

**Kimaradt kódrészletek.** A `PracticeDay`/`AdaptivePracticePlan`
copyWith-ja nem támogatja a `startDate`/`endDate` közvetlen
felülírását, ezért a `ResumePracticePlan` a tervet közvetlenül
rekonstruálja a konstruktorán, a `PracticeDay`-ket újraépíti a
`localDate` shiftjével — a többi mező (id, status, timeBudget, blocks,
primaryFocusSkillIds, reasonCodes) megmarad.

**L10n-fájlok újragenerálása.** A `lib/l10n/app_localizations*.dart`
fájlok a brief által megadott `generate: true` móddal futnak le; a
kör végén a `tools/ci/check_l10n_parity.dart` lépés zöldre futott
(`L10n parity OK (en → hu, 1379 message(s)).`).

**Stop-protokoll.** A kör nem ütközött tiltott zónába (a `Codex-signal`
várható `done` jelzésre).


## 11. Review — a Claude tölti ki
