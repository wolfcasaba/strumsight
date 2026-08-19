# E07-R26 — Outcome ingestion, review update és plan revision

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0afb9994`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 26
- **Kör-azonosító:** `E07-R26`
- **Branch:** `<motor>/e07-r26-outcome-ingestion-and-revision`
- **Előfeltétel:** `E07-R25` merge-elve (evidence-integráció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0256 (immutable múlt),
  0265 (adaptáció) és 0268 (technikai hiba) rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R10
> `PlanChangeSet` és az R19 repository tényleges felületét, valamint az R16
> adaptációs döntés-típusát. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/application/service/outcome_ingestion_service.dart",
  "lib/features/practice_generator/application/usecase/record_practice_outcome.dart",
  "lib/features/practice_generator/application/usecase/revise_practice_plan.dart",
  "lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/outcome/outcome_ingestion_service_test.dart",
  "test/features/practice_generator/outcome/revise_practice_plan_test.dart",
  "test/fixtures/practice_generator/outcome/",
  "docs/rounds/e07-r26-outcome-ingestion-and-revision.md",
]
gate_tests = [
  "test/features/practice_generator/outcome/outcome_ingestion_service_test.dart",
  "test/features/practice_generator/outcome/revise_practice_plan_test.dart",
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

## 0.0 Pre-flight mérés és brief-revízió (Claude Sonnet 5, 2026-08-19, kód olvasva: `main @ a0f764d5`)

A brief fejlécében kért újraolvasás (R10 `PlanChangeSet`, R19 repository felület,
R16 adaptációs döntés) megtörtént. Hat mért pont; **egyik sem bővíti az
`allowed_paths`-t** — mind a §5/§8 mechanizmus-szintű pontosítása.

**1. `PlanChangeSet` (R10) létezik, de a "csak jövőre" és "kis/nagy" logika
NULLA — ez a kör valódi, tiszta lappal induló munkája.** Mérve:
`lib/features/practice_generator/domain/model/plan_change_set.dart:57-96` —
`PlanChange.target` szabad szöveg (`String`), nincs benne állapot-ellenőrzés;
a három meglévő gyártó (`plan_repairer.dart:209`,
`time_budget_allocator.dart:471`, `active_plan_controller.dart:173`) mind
`requiresUserConfirmation: false`-t ír kőbe. Repó-szintű
`grep -rn "changeMagnitude|majorChange|minorChange"` → 0 találat.
**Következmény:** ez NEM eltérés, csak megerősítés — a §5.1/§5.2/§6.1
küszöb- és jövő-only logikája ténylegesen új tervezői munka, nem meglévő kód
összekötése.

**2. [KRITIKUS, de allowed_paths-t NEM bővíti] Két, AZONOS NEVŰ, eltérő alakú
`PracticeOutcome` típus él a fában — a repository-írás ezért ki van zárva
ebből a körből.** Mérve:
- `data/adapter/practice_outcome_adapter.dart:114-143` — az R23
  execution-oldali, `public.dart`-ból exportált `PracticeOutcome`
  (id/planId/revisionId/dayId/blockId/source/startedAt/completedAt/
  activeDuration/completionState/metricEvidence/userFeedback) — pontosan az
  SDD Ch8 §26.1 alakja.
- `data/local/practice_plan_serializer.dart:95-125` — a repository-lokális
  `PracticeOutcome` (id/planId/revisionId/recordedAt/durationMinutes/
  completedBlockCount/plannedBlockCount/summary) — MÁS mezőkészlet.
- `public.dart:25-28`: „A régebbi serializer-rekord repository-lokális. Az
  R23 a gazdagabb execution `PracticeOutcome`-ot publikálja; a lokális
  persistence a SAJÁT rekordtípusát importálja közvetlenül" — a barrel
  explicit `hide PracticeOutcome`-ot ír a serializer exportjára.
- `LocalPracticePlanRepository.appendOutcome(PracticeOutcome outcome)`
  (`data/local/local_practice_plan_repository.dart:451`) a REPOSITORY-lokális
  alakot várja — ehhez a service-nek a `practice_plan_serializer.dart`-ot
  KÖZVETLENÜL kellene importálnia (nem a barrelen át), ami a fenti kommentnek
  ellentmond, és a fájl maga nincs az `allowed_paths`-on.

**Feloldás (`allowed_paths` VÁLTOZATLAN):** az `outcome_ingestion_service.dart`,
a `record_practice_outcome.dart` és a `revise_practice_plan.dart` **tisztán
application-réteg, hívó-táplált szolgáltatás** — az aktív plan/nap/blokk
pillanatkép, a már feldolgozott outcome-azonosítók halmaza, a review-elemek
és az aktív revízió a HÍVÓTÓL érkezik paraméterként, a kimenet (frissített
review-elemek, `AdaptationDecision`, `PlanChangeSet`, esetleg egy új
`PlanRevision`) a HÍVÓNAK adódik vissza — **egyik új fájl sem hív
repository-metódust, és egyik sem importálja a `practice_plan_serializer.dart`-ot.**
Ugyanaz a minta, mint R16 (`AdaptationDecider`), R17 (`ReviewQueue`) és R23
(`PracticeOutcomeAdapter`/`PlanExecutionCoordinator`) — mindegyik
domain-tiszta, `practiceGeneratorEnabled=false`, nulla production hívó. A
repository-perzisztencia bekötése (a két `PracticeOutcome`-alak
összeegyeztetése) egy JÖVŐBELI wiring-kör dolga — az R22 MINOR-jának
([[L309]]) és az R19/R23 mintájának megfelelően.

**3. `outcome_ingestion_service.dart` bemenete a §2 alatti, `public.dart`-ból
exportált R23-alak — SOHA nem a repository-lokális.** A barrel `hide
PracticeOutcome`-ja (line 28) ezt gépileg is kikényszeríti: a
repository-lokális alakra való véletlen hivatkozás a barrelen át fordítási
hiba, nem néma téves kötés.

**4. Az "evidence- és ismétlés-sor frissítése" (§3) tényleges mutáló
logikája NEM a `ReviewQueue` (az csak SZELEKTOR), hanem a
`SpacedRepetitionPolicy.evaluate()`.** Mérve: `domain/service/review_queue.dart`
`ReviewQueue.select(...)` a mai jelöltekből választ, nincs "outcome-ból
frissítés" metódusa. A mutáló lépés:
`domain/policy/spaced_repetition_policy.dart:205-236` —
`SpacedRepetitionPolicy.evaluate({required ReviewItem item, required
ReviewOutcome outcome, required LocalDate today}) -> ReviewIntervalDecision`.
Az `outcome_ingestion_service.dart` ezt HÍVJA minden érintett `ReviewItem`-re
(az `allowed_paths` az írást korlátozza, a meglévő szolgáltatás hívását nem).

**5. Az A8 ("revízió-szám monoton nő") NEM új számláló-mechanizmust igényel:
a `PlanRevision` konstruktora már ma kikényszeríti, ha megkapja a
`previous`-t.** Mérve: `domain/model/plan_revision.dart:22-52` — `if
(previous != null && number <= previous.number) throw ArgumentError(...)`.
**Feloldás:** a `revise_practice_plan.dart` az aktív (hívó-táplált)
`PlanRevision`-t adja át `previous:`-ként az új revízió gyártásakor — az A8
teszt-cellája ezt a meglévő védelmet fedi le, nem egy új számlálót ír. (Az
`ArchivedRevision`, `data/local/practice_plan_serializer.dart:212-230`, a
repository-lokális írott alak, saját validáció nélkül — de a 2. pont szerint
ez a kör nem ír a repositoryba, tehát ez itt irreleváns.)

**6. Az R16/`AdaptationDecision`, az R19 repo-olvasás és az ADR
0256/0265/0268 feltételezése PONTOS, nincs eltérés.**
`AdaptationDecision.evidenceIds` nem-üres, kikényszerítve
(`domain/model/adaptation_decision.dart:187-227`) — ADR 0265 §6 teljesül.
`LocalPracticePlanRepository.readActivePlan()/readArchive()`
(`data/local/local_practice_plan_repository.dart:300,491`) elég egy jövőbeli
wiring-körnek a hívó-táplált olvasáshoz (ez a kör nem hívja őket, ld. 2.
pont). Az ADR 0256/0265/0268 szövege a brief §2/§9 idézeteivel egyezik.

**Visszakeresés (ADR 0312 §4.9 / brief-lint S8):**
`node tools/knowledge-rag.mjs --top 5 "outcome ingestion revise practice plan
change set future-only small large confirmation"` legjobb találata az SDD
Ch8 checklist szakasza
(`docs/sdd/08-epic-07-ai-practice-generator.md:2145-2240`: "Outcome ingestion
idempotens / Completed múlt nem változik / Major plan change confirmationt
igényel / Minden change set reasonnel és evidence refekkel rendelkezik") —
pontosan az A1–A8 fedése. A `--corpus lessons` közvetlen témai precedenst nem
adott; a releváns folyamat-leckék: **[[L304]]** (E07-R19 — ugyanennek a
repositorynak egy mért hibája a MEGÁLLT kör SAJÁT ágára tartozik, nem külön
heal-branch-re — irányadó, ha e kör alatt a repository-rétegben hibát
találunk), **[[L227]]** (egy pre-flight-revízió új szabálya retroaktív
ütközésbe kerülhet egy korábban írt acceptance-cellával — ha az implementer a
fenti 2–5. pont bármelyikét ütközőnek méri egy acceptance-cellával, a helyes
válasz tiszta `stopped`, nem workaround) és **[[L309]]** (a
repository-wiring MINOR-ként explicit egy jövőbeli körre hagyható,
dokumentáltan — pontosan a 2. pont feloldásának mintája).

**Összegzés:** `allowed_paths`, `gate_tests`, a §6 acceptance criteria és a
§3/§4 tiltott zóna **változatlan**. Ez a §0.0 kizárólag a §5/§8
mechanizmus-szintű pontosítása: melyik meglévő típust/metódust hívja a 3 új
fájl, és mit NEM ér el ez a kör (repository-írás). Az implementer a §8
sorrendjét ezzel a pontosítással kövesse.

## 1. Cél

A befejezett blokkok eredményének feldolgozása és **átlátható** jövőbeli
tervmódosítás (SDD Ch8 Kör 26).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0256: a lezárt múlt megváltoztathatatlan, a változás új revízió.
- Az ADR 0268: a technikai hiba nem teljesítmény.
- Az R16 adaptációs döntése evidence-hivatkozást hordoz (ADR 0265 §6).

## 3. Scope

**Benne van:** az eredmény és az **aktív revízió egyezésének** validálása ·
evidence- és ismétlés-sor frissítése · az adaptációs döntés futtatása ·
change set **kizárólag jövőbeli** blokkokra · **kis** és **nagy** változás
szétválasztása · a nagy változás megerősítés előtti megmutatása.

**NINCS benne (tilos):** a lezárt múlt módosítása · automatikus aktiválás nagy
változásnál · flag `true`-ra állítása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `application/service/outcome_ingestion_service.dart` | **ÚJ** |
| `application/usecase/record_practice_outcome.dart` | **ÚJ** |
| `application/usecase/revise_practice_plan.dart` | **ÚJ** |
| `presentation/screens/plan_change_review_screen.dart` | **ÚJ** — a nagy változás áttekintése |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/outcome/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r26-…md` | a §10 handoff |

**Tilos zóna:** a generátor domain-rétege · más `lib/features/**` ·
`lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 A change set CSAK jövőbeli blokkokra vonatkozhat

A lezárt nap és blokk érintetlen (ADR 0256 §1). Egy visszamenőleges „javítás"
meghamisítaná a történetet.

### 5.2 A NAGY változás megerősítést igényel

Kis változás (egy blokk hossza, egy csere) automatikusan mehet; **nagy**
változás (a hét szerkezete, a fókusz váltása) csak a tanuló jóváhagyásával.

**NEM elfogadható gyengítés:** minden változás automatikus, „úgyis jobb lesz".
A terv a tanulóé.

### 5.3 Az elutasított change set AUDITÁLHATÓ, de nem aktív

Ha a tanuló elutasítja a javaslatot, az nyoma megmarad (mit javasolt a
rendszer és mikor), de **nem** lép életbe. Így mérhető, mennyire jók a
javaslatok.

### 5.4 Az eredmény és az AKTÍV revízió egyeznie kell

Ha az eredmény egy már nem aktuális revízióra hivatkozik, az kontrollált
kezelés (nem néma eldobás, nem vak beépítés).

### 5.5 A duplikált eredmény EGYSZER dolgozódik fel

Az ADR 0260 §3 / 0268 §5 folytatása az alkalmazásrétegben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A lezárt múlt változatlan marad | `revise_practice_plan_test.dart` |
| A2 | A change set csak jövőbeli blokkot érint | ugyanott |
| A3 | Duplikált eredmény egyszer dolgozódik fel | `outcome_ingestion_service_test.dart` |
| A4 | Kis változás automatikus, nagy megerősítést kér | `revise_practice_plan_test.dart` |
| A5 | Az elutasított change set auditálható, de nem aktív | ugyanott |
| A6 | Nem aktuális revízióra hivatkozó eredmény kontrolláltan kezelt | `outcome_ingestion_service_test.dart` |
| A7 | A technikai hiba nem indít adaptációt (ADR 0268) | ugyanott |
| A8 | A revízió-szám monoton nő (ADR 0256) | `revise_practice_plan_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A change set a lezárt napot is átírja | **A1/A2** |
| Minden változás automatikus | **A4** |
| Az elutasított javaslat nyomtalanul eltűnik | A5 |
| A duplikált eredmény kétszer könyvelve | A3 |
| A technikai hiba adaptációt indít | A7 |

**A változás-nagyság három kötelező cellája** (a küszöb: a megerősítési határ):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | egyetlen blokk hossza változik | **automatikus** |
| rajta (a küszöbön) | pontosan a határon lévő változás | **megerősítést kér** (a határ a szigorúbb oldalhoz tartozik) |
| a küszöb fölött | a hét szerkezete változik | megerősítést kér, diffel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd a change
setet lezárt blokkra → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/outcome/outcome_ingestion_service_test.dart test/features/practice_generator/outcome/revise_practice_plan_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `outcome_ingestion_service.dart` — validálás, dedup, evidence/review frissítés.
2. `record_practice_outcome.dart` — a use case.
3. `revise_practice_plan.dart` — change set csak jövőre, kis/nagy szétválasztás.
4. `plan_change_review_screen.dart` — a nagy változás diffje.
5. Tesztek a §6.1 három változás-nagyság cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A visszamenőleges „javítás".** Kényelmes lenne a múltat is rendbe tenni,
  és meghamisítaná a történetet (A1).
- **A csendes nagy változás.** A tanuló másnap más tervet talál, mint amit
  jóváhagyott — bizalomvesztés (A4).
- **Az elutasított javaslat elvesztése.** Így nem mérhető, mennyire jók a
  javaslatok (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
