# E07-R02 — Typed ID-k, enumok és domain primitívek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 31f35161`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 2
- **Kör-azonosító:** `E07-R02`
- **Branch:** `<motor>/e07-r02-typed-ids-enums-and-domain-primitives`
- **Előfeltétel:** `E07-R01` merge-elve (PR #268)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0257`](../adr/0257-planner-typed-ids-and-stable-enum-codes.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/practice_generator/` állapotát (az R01 óta létrejöhetett-e),
> és ellenőrizd, hogy az `test/core/architecture_dependency_test.dart` R01-ben
> hozzáadott generátor-határa mit tilt pontosan. Ha a §2 mért tényei
> elavultak, dokumentált §0.0 brief-revízió, majd Státusz → PLANNING.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/id/planner_ids.dart",
  "lib/features/practice_generator/domain/model/plan_enums.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/domain/planner_ids_test.dart",
  "test/features/practice_generator/domain/plan_enums_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e07-r02-typed-ids-enums-and-domain-primitives.md",
]
gate_tests = [
  "test/features/practice_generator/domain/planner_ids_test.dart",
  "test/features/practice_generator/domain/plan_enums_test.dart",
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

A generátor stabil, **Flutter-független** alaptípusai: typed ID-k, enumok,
stabil JSON-kódokkal (SDD Ch8 Kör 2).

## 2. Jelenlegi állapot — mért tények

### 2.1 A könyvtár még nem létezik

`lib/features/practice_generator/` **nincs** (mérve `main @ 31f35161`). Az
E07-R01 szándékosan nulla alkalmazáslogikát írt. **Ez a kör hozza létre.**

### 2.2 Nincs közös `IdGenerator` absztrakció

`grep -rln "class IdGenerator|abstract.*IdGenerator" lib/` → **nulla** találat.
A projekt bevált mintája az **injektált függvény**:

```dart
// data/capture/analysis_recorder.dart:36
final String Function()? _runIdGenerator;
```

**Ne vezess be új absztrakciót** — kövesd ezt.

### 2.3 A meglévő „ID" minta sima `String`, nem típusos

`domain/events/event_id.dart` — az `EventId` egy statikus gyár, ami
**`String`-et ad vissza** (`<runId>:onset:<sampleIndex>`), validációval.
Ez nem véd a felcseréléstől: egy `String` planId odaadható `dayId` helyére.

A SDD Ch8 Kör 2 kifejezetten **typed** ID-kat kér — tehát ez a kör ÚJ mintát
vezet be, nem a meglévőt másolja. Ezért kap ADR-t (0257).

### 2.4 A `public.dart` barrel-minta adott

Más feature-ök `public.dart`-ja exportálja a kifelé látható típusokat
(pl. `lib/features/audio_analysis/public.dart`). Az architektúra-őr az R01
óta tiltja a generátor **belső** fájljainak importját kívülről.

## 3. Scope

**Benne van:**

1. Typed ID-k: plan, day, block, goal, revision, outcome.
2. Enumok: státusz, mód, block-kind, severity, source — **stabil string
   kódokkal**.
3. JSON round-trip mindkettőre.
4. Ismeretlen enum-kód **kontrollált hiba** (nem néma default).
5. `public.dart` barrel a kifelé látható primitívekkel.

**NINCS benne (tilos):**

- Bármilyen üzleti logika, tervező, validátor, repository, UI, provider.
- `Flutter` import a domainben (A1).
- Flag mozgatása; `lib/app/**`, más `lib/features/**`.
- `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/id/planner_ids.dart` | **ÚJ** — a hat typed ID |
| `domain/model/plan_enums.dart` | **ÚJ** — az öt enum-család stabil kódokkal |
| `public.dart` | **ÚJ** — a barrel |
| `test/…/domain/planner_ids_test.dart` | **ÚJ** |
| `test/…/domain/plan_enums_test.dart` | **ÚJ** |
| `test/core/architecture_dependency_test.dart` | a generátor-határ finomítása, ha az új fájlok igénylik |
| `docs/rounds/e07-r02-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/**` · minden más `lib/features/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0257)

### 5.1 A typed ID **nem cserélhető fel** másik ID-val

Minden ID önálló típus (`extension type` vagy `final class` value object) —
egy `PlanId` **fordítási hibát** adjon, ha `DayId` helyére kerül. Ez a kör
egész értelme; e nélkül a SDD „typed ID" kérése kimerülne egy `typedef`-ben.

**NEM elfogadható gyengítés:** `typedef PlanId = String;`. Az nem típus,
csak név.

### 5.2 Üres és érvénytelen ID **elutasított**, konstrukciókor

Az ellenőrzés a létrehozásnál történik, nem a használatnál. Üres, csak
whitespace-ből álló vagy formátumot sértő érték → `ArgumentError`.

### 5.3 Az enum-kódok STABILAK és a szerializáció NEM a `name`-re épül

A JSON-ban explicit string kód szerepel (pl. `'in_progress'`), **nem** a Dart
enum `name`-je. Enum átnevezése így nem tör el perzisztált adatot.

**NEM elfogadható gyengítés:** `EnumName.values.byName(json)`. Az a Dart-beli
azonosítót teszi adatformátummá.

### 5.4 Ismeretlen enum-kód KONTROLLÁLT hiba

Ismeretlen kód **nem** eshet vissza némán egy default értékre — hibát ad
(`AppResult` failure vagy `ArgumentError`, a hívó rétegnek megfelelően).
A néma default a migrációnál csendes adatromlást okoz.

### 5.5 Az ID-generálás injektált függvény

`String Function()` paraméter, a `analysis_recorder.dart:36` mintájára.
Nincs új absztrakció, nincs statikus/globális generátor, nincs `DateTime.now()`
vagy `Random` a domainben.

### 5.6 A domain NEM importál Fluttert

Sem `package:flutter/...`, sem `dart:ui`. A domain tiszta Dart.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A domain nem importál Fluttert | `architecture_dependency_test.dart` + `grep` a diffben |
| A2 | ID-k **nem cserélhetők fel** — típushiba | `planner_ids_test.dart` — a nem-fordulást a teszt dokumentálja, a futó cellák az egyenlőséget/validációt mérik |
| A3 | Üres / whitespace / formátumsértő ID elutasított | `planner_ids_test.dart` |
| A4 | Azonos érték → egyenlő ID, eltérő → nem egyenlő (`==`, `hashCode`) | `planner_ids_test.dart` |
| A5 | Enum JSON round-trip stabil kódokkal | `plan_enums_test.dart` |
| A6 | Ismeretlen enum-kód KONTROLLÁLT hiba, nem default | `plan_enums_test.dart` |
| A7 | A `public.dart` csak a szükséges primitíveket exportálja | `public.dart` diff + review |
| A8 | Nincs `DateTime.now()`/`Random` a domainben | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `typedef PlanId = String` | A2 (a felcserélés nem ad hibát) |
| A validáció a használatnál, nem a konstrukciónál | A3 |
| `==` felüldefiniálása nélkül (identitás-egyenlőség) | A4 |
| `values.byName(json)` szerializáció | **A5** (enum átnevezése eltörné a round-tripet) |
| Ismeretlen kód → első enum-érték | **A6** |
| A `public.dart` exportálja a belső fájlokat | A7 + az architektúra-őr |
| `DateTime.now()` az ID-ben | A8 |

**Az enum-kód három kötelező cellája** (a határ: a kód ismertsége):

| Cella | Bemenet | Elvárt |
|---|---|---|
| ismert kód | `'in_progress'` | a megfelelő enum-érték |
| a határon | üres string / `null` | kontrollált hiba, NEM default |
| ismeretlen kód | `'valami_uj'` | kontrollált hiba, NEM default |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az ismeretlen
kód ágát default értékre → az **A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/domain/planner_ids_test.dart test/features/practice_generator/domain/plan_enums_test.dart test/core/architecture_dependency_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `planner_ids.dart` — a hat typed ID, konstrukciókori validációval.
2. `plan_enums.dart` — az öt enum-család, stabil kódokkal és kontrollált
   ismeretlen-kód kezeléssel.
3. `public.dart` barrel.
4. Tesztek a §6.1 három enum-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `typedef` csábítása.** Gyors és „működik", de nem véd semmitől — a
  kör értelmét venné el (A2).
- **A `name`-alapú szerializáció.** A legkényelmesebb út, és pont ez teszi a
  Dart-azonosítót adatformátummá (A5).
- **A néma default.** Ismeretlen kódra visszaesni „robusztusnak" hat, de
  migrációkor csendes adatromlás (A6).
- **A scope tágulása.** A domain-primitívek után kézenfekvő „mindjárt a
  modelleket is" — azok a Kör 3 dolga.

## 10. Implementation handoff — az implementer tölti ki

**Végrehajtó:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-15.

### 10.1 Létrehozott fájlok

- `lib/features/practice_generator/domain/id/planner_ids.dart` — hat typed
  ID (`PlanId`, `DayId`, `BlockId`, `GoalId`, `RevisionId`, `OutcomeId`),
  mindegyik önálló `final class`, privát konstruktorral + validáló
  factoryval, explicit `==`/`hashCode`. Közös `_validateId` privát helper
  (üres/whitespace + `^[A-Za-z0-9._:-]+$` formátumellenőrzés).
- `lib/features/practice_generator/domain/model/plan_enums.dart` — öt
  enum-család stabil kódokkal, a SDD Ch8 mért szövegéből véve:
  `PlanStatus` (§7.7), `GenerationMode` (§10.2), `BlockKind` (§16.4),
  `ValidationSeverity` (§17.2), `CandidateSource` (§14.2 „Forrás"). Közös
  privát `_decodeEnumCode<T extends Enum>` helper: üres/`null` kód és
  ismeretlen kód egyaránt `ArgumentError`-t dob, sosem esik vissza egy
  alapértelmezett értékre.
- `lib/features/practice_generator/public.dart` — barrel, kizárólag a két
  fenti fájlt exportálja.
- `test/features/practice_generator/domain/planner_ids_test.dart` (45 teszt),
  `test/features/practice_generator/domain/plan_enums_test.dart` (25 teszt).
- `test/core/architecture_dependency_test.dart` — új csoport
  („practice generator domain stays framework-free (E07-R02)"), ami a
  `lib/features/practice_generator/domain/` valódi fájljait olvassa be és
  keres tiltott mintát (`package:flutter/`, `dart:ui`, `DateTime.now(`,
  `Random(`).

### 10.2 Mért eltérés a `tool/check_architecture.dart`-tól (dokumentált, nem javított)

A `checkArchitecture` `_isSharedDomain` listája ma csak
`lib/core/music/`, `lib/core/audio/codec/` és
`lib/features/practice/domain/` prefixeket ismeri fel Flutter-független
domainként — `lib/features/practice_generator/domain/` **nincs** benne, és
a `tool/check_architecture.dart` NEM szerepel ennek a körnek az
engedélyezett fájllistáján, tehát nem bővíthettem. Emiatt az A1/A8
kritérium bizonyítéka nem a `checkArchitecture` gépén, hanem egy új,
valódi könyvtárat beolvasó teszten (fent, 10.1) és a kézi `grep`-en
(10.3) keresztül él. A prefix bővítése egy jövőbeli, `tool/`-t is
engedélyező körre marad.

### 10.3 Kézi `grep` bizonyíték (A1, A8)

```
grep -rn "package:flutter\|dart:ui\|DateTime.now\|Random(" lib/features/practice_generator/
→ NO MATCHES (clean)
```

### 10.4 Valódi-sértés próba (A6, kötelező)

A `plan_enums.dart` `_decodeEnumCode` függvényében az üres/`null`-ellenőrzést
és az `ArgumentError` dobást ideiglenesen `return values.first;`-re
cseréltem. `flutter test test/features/practice_generator/domain/plan_enums_test.dart`
lefuttatva: mind az öt enum-család mindkét A6-cellája (üres/`null` és
ismeretlen kód) **PIROSRA** váltott (10 megbukott teszt, pl.
„ValidationSeverity empty or null code is a controlled error, not a
default (A6)" → `Expected: throws ArgumentError, Actual: returned
ValidationSeverity:<info>`). Ezután a fájlt visszaállítottam az eredeti
(dobó) implementációra, és a teszt újra 25/25 zöld.

### 10.5 Gate

```
tools/round-gate.sh test/features/practice_generator/domain/planner_ids_test.dart test/features/practice_generator/domain/plan_enums_test.dart test/core/architecture_dependency_test.dart
```

Minden lépés (`format`, `analyze`, mindhárom `test`, `architecture`,
`secrets`, `l10n`) ZÖLD.

### 10.6 Javító kör (`docs/reviews/e07-r02-review.md` MAJOR-1, MAJOR-2)

**Végrehajtó:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-15, egyetlen javító
kör, kizárólag `planner_ids.dart` + `planner_ids_test.dart` + ez a handoff.

**MAJOR-1 (JSON round-trip hiánya) — zárva.** Mind a hat typed ID kapott egy
explicit `String toJson()`-t (a nyers `value`-t adja vissza) és egy statikus
`fromJson(Object? json)`-t, ami a dekódolt bemenetet a `_decodeJsonId` közös
helperen futtatja végig, majd a **ugyanazon konstruktoron** (`PlanId(...)`
stb.) keresztül épít példányt — tehát egy `fromJson`-nal létrehozott ID
sosem kerülheti meg a §5.2 validációt. Új teszt-csoport
(`planner_ids_test.dart` „JSON round-trip"): mind a hat ID érvényes
round-trip cellája, egy nem-`String` dekódolt érték (int/map/null/list/
bool/double) elutasítása mind a hat ID-n, és egy formátumot sértő dekódolt
`String` (üres/whitespace/tiltott karakter) elutasítása mind a hat ID-n.

**MAJOR-2 (injektált ID-generálás hiánya) — zárva.** Mind a hat típus kapott
egy `factory <Id>.generate(String Function() generateId)` belépési pontot,
ami az `analysis_recorder.dart:36` mintáját követi: a paraméter egy
**sima `String Function()`**, nincs új `IdGenerator` absztrakció, nincs
óra/random forrás a domainben. A generátor visszatérési értékét a
**ugyanaz a konstruktor** validálja (`PlanId(generateId())`), tehát a
generálás nem kerülheti meg a §5.2 validációt. Új teszt-csoport
(„injected deterministic generation"): determinisztikus lambda-generátorral
mind a hat ID sikeres construction-je, és egy érvénytelen id-t visszaadó
generátor mind a hat ID-n `ArgumentError`-t dob.

**Gate újrafuttatása javítás után (előtér, csonkítás nélkül):**

```
tools/round-gate.sh test/features/practice_generator/domain/planner_ids_test.dart test/features/practice_generator/domain/plan_enums_test.dart test/core/architecture_dependency_test.dart
```

Minden lépés ZÖLD: `format`, `analyze`, `test planner_ids_test.dart` (60/60,
korábban 45), `test plan_enums_test.dart` (25/25, változatlan),
`test architecture_dependency_test.dart` (18/18, változatlan),
`architecture`, `secrets`, `l10n`.

Módosított/staged fájlok ebben a javító körben:
`lib/features/practice_generator/domain/id/planner_ids.dart`,
`test/features/practice_generator/domain/planner_ids_test.dart`,
ez a brief (`docs/rounds/e07-r02-typed-ids-enums-and-domain-primitives.md`).
Semmi más útvonal nem érintett.

## 11. Review — a Claude tölti ki
