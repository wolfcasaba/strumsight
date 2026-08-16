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
