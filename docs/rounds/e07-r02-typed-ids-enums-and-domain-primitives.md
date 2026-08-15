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

## 11. Review — a Claude tölti ki
