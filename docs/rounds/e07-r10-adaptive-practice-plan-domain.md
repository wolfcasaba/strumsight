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

## 11. Review — a Claude tölti ki
