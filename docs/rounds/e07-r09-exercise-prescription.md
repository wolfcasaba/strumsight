# E07-R09 — ExercisePrescription és success criteria

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ ba834de8`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 9
- **Kör-azonosító:** `E07-R09`
- **Branch:** `<motor>/e07-r09-exercise-prescription`
- **Előfeltétel:** `E07-R08` merge-elve (katalógus-pillanatkép)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0262 §2 (kimondott
  capability) és az ADR 0255 (determinizmus) már rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R08 tényleges
> `exercise_candidate.dart` mezőit (mely capability-k vannak, hogyan jelölt az
> `unsupported`), mert a §5.2 erre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/exercise_prescription.dart",
  "lib/features/practice_generator/domain/model/success_criteria.dart",
  "lib/features/practice_generator/domain/model/progression_rule.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/prescription/exercise_prescription_test.dart",
  "test/features/practice_generator/prescription/success_criteria_test.dart",
  "docs/rounds/e07-r09-exercise-prescription.md",
]
gate_tests = [
  "test/features/practice_generator/prescription/exercise_prescription_test.dart",
  "test/features/practice_generator/prescription/success_criteria_test.dart",
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

A kiválasztott gyakorlat konkrét, **korlátos** végrehajtási receptje, mérhető
sikerkritériummal (SDD Ch8 Kör 9).

## 2. Jelenlegi állapot — mért tények

- Az R08 `ExerciseCandidate`-je hordozza a capability-ket, és a nem
  támogatottat **kimondottan** (`unsupported`, ADR 0262 §2).
- A hard időkorlát az ADR 0258 §3 szerint inkluzív és befelé kerekít.
- A domain Flutter-független, injektált idővel (ADR 0257 §5-6).

## 3. Scope

**Benne van:** időtartam-, tempó-, ismétlés-, hurok- és pihenő-recept ·
típusos `SuccessCriteria` · `ProgressionRule` (nehezítés/könnyítés) ·
fallback-jelöltlista · validáció, hogy a kritérium **mérhető** a jelölt
capabilityjéből.

**NINCS benne (tilos):** terv-összeállítás (Kör 10) · validátor/repair
(Kör 11) · prioritás/választás (Kör 12-13) · Flutter, `DateTime.now()`,
`Random` · más `lib/features/**`, `lib/app/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/exercise_prescription.dart` | **ÚJ** — a recept típusai |
| `domain/model/success_criteria.dart` | **ÚJ** — típusos kritériumok |
| `domain/model/progression_rule.dart` | **ÚJ** — nehezítés/könnyítés |
| `public.dart` | a barrel bővítése |
| `test/…/prescription/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r09-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 NINCS végtelen recept

Minden nyílt végű ismétlés **kötelező felső korláttal** rendelkezik. „Addig,
amíg sikerül" önmagában nem recept — mellé maximum kell.

**NEM elfogadható gyengítés:** nagyon nagy default maximum „gyakorlatilag
végtelen" szándékkal. A korlát legyen értelmes és kimondott.

### 5.2 Tempó CSAK támogatott jelöltnél

Ha a jelölt capabilityje `unsupported` a tempó-vezérlésre, a recept **nem
tartalmazhat** tempó-előírást. A validáció konstrukciókor fut.

### 5.3 A sikerkritérium MÉRHETŐ kell legyen a jelölt capabilityjéből

Nem írható elő olyan kritérium, amit a végrehajtó réteg nem tud megmérni.
Ellenkező esetben a tanuló sosem „teljesíti" a blokkot.

**NEM elfogadható gyengítés:** nem mérhető kritérium „majd a felhasználó
eldönti" alapon — az a sikert szubjektívvá teszi, és a progresszió
kiszámíthatatlanná.

### 5.4 A fallback KOMPATIBILIS a céllal

A fallback-jelöltek ugyanazt a skillt célozzák; nem lehet köztük olyan, ami
más készséget gyakoroltat. A fallback a hozzáférhetőséget oldja meg, nem a
célt cseréli.

### 5.5 A kritérium EXPLICIT, nem implicit default

Minden receptnek van kimondott sikerkritériuma. Hiánya hiba, nem „alapból
teljesült".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nyílt végű ismétlés maximum nélkül → hiba | `exercise_prescription_test.dart` |
| A2 | Tempó-előírás `unsupported` jelöltre → hiba | ugyanott |
| A3 | Nem mérhető kritérium → hiba | `success_criteria_test.dart` |
| A4 | A fallback ugyanazt a skillt célozza | `exercise_prescription_test.dart` |
| A5 | Hiányzó sikerkritérium → hiba, nem „teljesült" | `success_criteria_test.dart` |
| A6 | JSON round-trip veszteségmentes | mindkét teszt |
| A7 | Az időtartam a hard korlát alatt marad (ADR 0258 §3) | `exercise_prescription_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Nagyon nagy default maximum korlát helyett | **A1** |
| A tempó-validáció futásidőre halasztva | A2 |
| Bármilyen kritérium elfogadva | **A3** |
| A fallback más skillt céloz | A4 |
| Hiányzó kritérium „teljesültnek" véve | **A5** |
| Kerekítés felfelé az időtartamnál | A7 |

**Az ismétlésszám három kötelező cellája** (a határ: a maximum):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | max 10, előírás 9 | elfogadva |
| a határon | max 10, előírás **10** | **elfogadva** (inkluzív) |
| fölötte | max 10, előírás 11 | **elutasítva** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedj maximum
nélküli nyílt végű receptet → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/prescription/exercise_prescription_test.dart test/features/practice_generator/prescription/success_criteria_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `success_criteria.dart` — típusos kritériumok, mérhetőség-validáció.
2. `exercise_prescription.dart` — a recept-típusok, korlátokkal.
3. `progression_rule.dart` — nehezítés/könnyítés.
4. Tesztek a §6.1 három ismétlés-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „gyakorlatilag végtelen" default.** Formálisan korlátos, valójában nem —
  a tanuló egy blokkban ragadna (A1).
- **A szubjektív siker.** „Majd eldönti" egyszerűbb, és a progressziót
  kiszámíthatatlanná teszi (A3).
- **A fallback célcseréje.** Elérhetőségi problémát old meg, közben más
  készséget gyakoroltat (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
