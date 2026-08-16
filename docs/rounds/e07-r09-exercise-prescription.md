# E07-R09 — ExercisePrescription és success criteria

- **Státusz:** PLANNING (pre-flight: 2026-08-16, baseline: `origin/main @ 22257ffc`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 9
- **Kör-azonosító:** `E07-R09`
- **Branch:** `<motor>/e07-r09-exercise-prescription`
- **Előfeltétel:** `E07-R08` merge-elve (katalógus-pillanatkép)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [0294](../adr/0294-exercise-prescription-measurability-and-bounded-execution.md)
  — a pre-flight rögzítette a meglévő candidate-capabilityk és a
  sikerkritériumok közti, nem kitalálható határt.

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
  "docs/adr/0294-exercise-prescription-measurability-and-bounded-execution.md",
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

## 0.0 Pre-flight revízió (mérve 2026-08-16)

Az R08 tényleges `ExerciseCandidate` konstruktorát és a két adapter tényleges
hívási helyét újramértük (`exercise_candidate.dart:141-218`,
`practice_engine_catalog_adapter.dart:58-92`,
`legacy_lesson_candidate_adapter.dart:61-79`). A candidate kötelező,
nem üres `skillTargets`-et és a teljes `ExerciseCapability` mapet hordozza;
az utóbbi minden ma ismert capabilityt explicit `supported` vagy
`unsupported` értékkel jelöl. A mapnek **nincs** külön, szabad szöveges
metric- vagy criteria-measurement truthja. A két meglévő scoring-capability
(`supportsDirectionScoring`, `supportsChordScoring`, `supportsPitchScoring`)
és az executor-control capabilityk jelentése ugyanakkor pontosan a R08-ból
érkezik, ezért nem szabad belőlük új, név-alapú metrikát következtetni.

Ennek megfelelően a §5.3 és az A3 implementálható, nem találgató
operacionalizálása az ADR 0294 szerint: minden `SuccessCriteria` explicit,
nem üres `requiredCapabilities` halmazt hordoz, amelynek minden eleme a
candidate-en `supported`; a konstrukció más esetben hibát ad. A kör **nem**
vezet be szabad szöveges metric-code → capability leképezést és nem módosítja
az R08 candidate-contractot. A `completion` és `assessmentOnly` sem kaphat
implicit, üres „mérhető” defaultot; a későbbi executor csak a most
deklarált capability-ig állíthat sikert.

A fallback „ugyanaz a skill” mért, többértékű candidate-mezőhöz igazodik:
a primary és minden fallback `skillTargets.toSet()` értéke pontosan egyezzen;
a sorrend nem pedagógiai különbség. A hard időkorlát későbbi tervszintű
korlát, ezért a recept saját, explicit `hardElapsedLimit` mezőt hordoz és
annál hosszabb aktív+rest idő nem konstruálható. Ez az ADR 0258 §3 inkluzív
határát alkalmazza, nem próbál hozzáférni a Kör 10 plan-időkeretéhez.

Az ADR 0294-et a pre-flight foglalta és írta; a §4 és az `ai-router`
`allowed_paths` blokk egyetlen dokumentum-kivételként tartalmazza. Minden
más `docs/adr/**` továbbra is tilos. A brief-lint jelentés (`strict`) üres,
így további lint-revízió nem szükséges.

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
`Random` · más `lib/features/**`, `lib/app/**`, `tools/**`. Egyetlen
dokumentum-kivétel az ADR 0294; más `docs/adr/**` továbbra is tilos.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/exercise_prescription.dart` | **ÚJ** — a recept típusai |
| `domain/model/success_criteria.dart` | **ÚJ** — típusos kritériumok |
| `domain/model/progression_rule.dart` | **ÚJ** — nehezítés/könnyítés |
| `public.dart` | a barrel bővítése |
| `test/…/prescription/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r09-…md` | a §10 handoff |
| `docs/adr/0294-exercise-prescription-measurability-and-bounded-execution.md` | **ÚJ, pre-flight** — §0.0 capability/criterion és bounded-elapsed döntése |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · minden más
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

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

Minden `SuccessCriteria` explicit, nem üres `requiredCapabilities` halmazt
hordoz. Konstrukciókor minden tagjának a candidate-en `supported` értékűnek
kell lennie; nincs szabad szöveges metric-code-ból következtetés és nincs
implicit, üres „completion” vagy „assessment” kivétel. Ellenkező esetben a
tanuló sosem „teljesíti" a blokkot.

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
| Hiányzó/unsupported required capabilityvel bíró kritérium elfogadva | **A3** |
| A fallback más skillt céloz | A4 |
| Hiányzó kritérium „teljesültnek" véve | **A5** |
| `hardElapsedLimit` fölötti vagy felfelé kerekített teljes idő elfogadva | A7 |

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

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-16.

**Módosított/új fájlok** (mind a §4 engedélyezett listáján):

- `lib/features/practice_generator/domain/model/success_criteria.dart` (ÚJ)
  — `SuccessCriterionKind` (`completion`, `assessmentOnly`,
  `accuracyThreshold`, `tempoSustained`), `SuccessCriteria` explicit,
  nem üres `requiredCapabilities` halmazzal, `ensureMeasurableFor` /
  `isMeasurableFor`, `toJson`/`fromJson`.
- `lib/features/practice_generator/domain/model/exercise_prescription.dart`
  (ÚJ) — `RepetitionPrescription` (target/maximum, inkluzív határ),
  `FallbackReference`, `ExercisePrescription` (candidate-hez kötött
  konstrukció-időbeli validáció: tempó csak `supportsTempo=supported`
  esetén, `successCriteria.ensureMeasurableFor`, `elapsed <=
  hardElapsedLimit` inkluzívan, fallback skillTargets-halmaz egyezés),
  `toJson`/`fromJson`.
- `lib/features/practice_generator/domain/model/progression_rule.dart` (ÚJ)
  — `ProgressionDirection`, `ProgressionStep`, `ProgressionRule`
  (advance/regress pár, előjel-konzisztencia validáció). Csak típus ebben
  a körben (ADR 0294 Kontextus); alkalmazása Kör 10+.
- `lib/features/practice_generator/public.dart` — a három új modul
  exportja (`exercise_prescription.dart`, `progression_rule.dart`,
  `success_criteria.dart`).
- `test/features/practice_generator/prescription/exercise_prescription_test.dart`
  (ÚJ) — 24 teszt: A1 (3 cellás ismétlés-mátrix + fromJson hiányzó
  maximum), A2, A3, A4, A6 (2x veszteségmentes round-trip + 2x kontrollált
  decode-hiba), A7 (alatta/határon/fölötte/loop-szorzás), konstrukciós
  validáció, egyenlőség.
- `test/features/practice_generator/prescription/success_criteria_test.dart`
  (ÚJ) — 16 teszt: A3 (mérhetőség, részleges lefedettség,
  completion/assessmentOnly nem kivétel), A5 (üres requiredCapabilities
  mindkét kindra, hiányzó/üres JSON mező), validáció (minimumAccuracy
  határ, ismeretlen enum/capability kód), A6 (2x round-trip), egyenlőség.
- `docs/rounds/e07-r09-exercise-prescription.md` — ez a §10.

**Tényleges parancsok és eredmények:**

```
$ flutter analyze lib/features/practice_generator/domain/model/exercise_prescription.dart \
    lib/features/practice_generator/domain/model/success_criteria.dart \
    lib/features/practice_generator/domain/model/progression_rule.dart \
    lib/features/practice_generator/public.dart
No issues found! (ran in 4.2s)

$ flutter analyze test/features/practice_generator/prescription/exercise_prescription_test.dart \
    test/features/practice_generator/prescription/success_criteria_test.dart
No issues found! (ran in 4.1s)

$ flutter test test/features/practice_generator/prescription/exercise_prescription_test.dart \
    test/features/practice_generator/prescription/success_criteria_test.dart
00:00 +40: All tests passed!

$ tools/round-gate.sh test/features/practice_generator/prescription/exercise_prescription_test.dart \
    test/features/practice_generator/prescription/success_criteria_test.dart
format: zöld · analyze: zöld ·
test .../exercise_prescription_test.dart: zöld (24/24) ·
test .../success_criteria_test.dart: zöld (16/16) ·
architecture: zöld (12 allowlisted deviation) · secrets: zöld · l10n: zöld
MINDEN GATE ZÖLD.
```

**Valódi-sértés próba (§6.1, KÖTELEZŐ, A1):** `exercise_prescription.dart`
`RepetitionPrescription` konstruktorában a `this.target > this.maximum`
feltételt ideiglenesen `false && this.target > this.maximum`-ra cseréltem
(a felső korlát tényleges kikapcsolása), majd újrafuttattam
`flutter test test/features/practice_generator/prescription/exercise_prescription_test.dart`-ot:

```
00:00 +2 -1: RepetitionPrescription — bounded repetition (A1) rejects a target above the maximum [E]
00:00 +23 -1: Some tests failed.
Failing tests:
  .../exercise_prescription_test.dart: RepetitionPrescription — bounded repetition (A1) rejects a target above the maximum
```

Az A1 cella a vártnak megfelelően PIROSRA váltott (a többi 23/24 továbbra is
zöld maradt, mert azok más invariánst mérnek). Ezután a feltételt
visszaállítottam az eredeti `this.target > this.maximum`-ra, és a teljes
gate-et újra lefuttattam — mind a 40 teszt zöld (l. fent).

**Architekturális döntések, amiket követtem:**

- `ExercisePrescription` nem tárolja a teljes `ExerciseCandidate`-et (az
  `exercise_candidate.dart` a tiltott zónában van, nincs rajta
  `toJson`/`fromJson`, és a §4 nem engedi módosítani). Csak a
  konstrukció-időben szükséges azonosító mezőket (`exerciseId`, `source`,
  `skillTargets`) másolja le a candidate-ből — a candidate maga csak
  átmeneti validációs bemenet (tempó-capability, `successCriteria`
  mérhetősége, fallback skillTargets-egyezés).
- A `SuccessCriteria` mérhetőségi ellenőrzése (`ensureMeasurableFor`) a
  típuson önmagában közvetlenül tesztelhető (l. `success_criteria_test.dart`
  A3/A5), az `ExercisePrescription` konstruktora pedig ugyanezt hívja meg a
  candidate ismeretében — így az A3-cella mindkét szinten (unit + integrált)
  ténylegesen bizonyított.
- `ProgressionRule` ebben a körben csak típus (advance/regress pár,
  előjel-validáció); a scope kizárja az alkalmazását (§3 NINCS benne).

**Ismert korlátok / későbbi körre hagyott döntés:** a `SuccessCriterionKind`
négy értéke (`completion`, `assessmentOnly`, `accuracyThreshold`,
`tempoSustained`) a §5.3 explicit igényét fedi le; a metrika-specifikus
mezők (pl. tényleges pontosság-mérés bekötése) egy későbbi, saját scope-ú
kör feladata marad (ADR 0294 „Következmények").

## 11. Review — a Claude tölti ki
