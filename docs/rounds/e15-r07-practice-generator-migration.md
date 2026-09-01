# E15-R07 — Practice Generator bekötése (route + flag), majd migrálása

- **Státusz:** PREPARED (újraírva 2026-09-01 user-döntés alapján, kód olvasva: `main @ c2c3801`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 7
- **Kör-azonosító:** `E15-R07`
- **Branch:** `<motor>/e15-r07-practice-generator-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv mérte meg, hogy a flow bekötetlen)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0480` — **placeholder**: a pre-flight ELSŐ dolga `tools/round-slots.py reserve-adr --round E15-R07`-tal a VALÓDI számot kérni (a `0477`/`0479` precedens szerint az előre kiosztott szám elavulhat), és a brief + a queue-sor `adr` oszlopa arra íródik át.

**Visszakeresett előzmény:** [ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md) (plan-preview aktiválási határ — a preview-felület a core útra nem hathat), [ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md) (az elérhetőség MÉRT tulajdonság; a `retire` verdikt JAVASLAT, a bekötés/nyugdíjazás produkt-döntés), [ADR 0255](../adr/0255-deterministic-practice-plan-generation.md) (a generátor szerződése).

## 0.0 MIÉRT íródott újra ez a brief — a régi premisszái MÉRTEN hamisak voltak

A kör korábbi változata tiszta megjelenés-migráció volt, két kimondott premisszára építve. **Mindkettő hamis**, ezért futott a lánc HALT-ra (2026-09-01):

| Régi állítás | MÉRT valóság |
|---|---|
| „az `E15-R02` óta a Practice Generator flag BE van kapcsolva az előnézeti buildekben" | `lib/app/config/feature_flags.dart:84` — `practiceGeneratorEnabled: false` a `forEnvironment` gyárban is, MINDEN környezetben. A mezőt a `feature_flag_registry.dart:144` `killSwitchPath`-ja szó szerint így írja le: „hardcoded to `false` in every environment … enabling it requires a source change". |
| „ezek a képernyők a fő navigációból elérhetők" | `docs/ui/retirement-plan.md:241–246` — mind a 6 képernyő `unreachable`: **nincs route és nincs építési hely sehol a `lib/`-ben**. A `lib/app/routing/app_route.dart` egyetlen `plan*` útvonalat sem deklarál. |

A `retirement-plan.md` §3.2 ezt „built, unwired" néven tartja nyilván, és kimondja: *„design tokens are moot on a screen nobody can open"* — a bekötés vagy nyugdíjazás **produkt/navigációs döntés**, amit az E15-R03 javasolt, de nem hozott meg.

> **A döntés megszületett (user, 2026-09-01): BEKÖTNI.** A Practice Generator kap belépési pontot (route + flag), és **utána** megy át a design-rendszerre. A `plannerAssistEnabled` (modell-segített javaslatok) ebben a körben **NEM** kapcsol be — a bekötés a determinisztikus generátorra szól.

Ezért a kör KÉT fázisú, és a fázisok sorrendje kötött: **F1 bekötés → F2 migráció**. Az F2 acceptance-e (szövegskála, locale, állapotok) csak akkor jelent bármit, ha az F1 után a képernyő valóban megnyitható.

### 0.0.A Pre-flight (indítás előtt KÖTELEZŐ)

1. **ADR-szám:** `tools/round-slots.py reserve-adr --round E15-R07` → a kapott számra írd át a brief fejlécét, a §5 ADR-hivatkozásait és a queue-sor `adr` oszlopát.
2. **Elérhetőség újramérése** (a kör KIINDULÓ bizonyítéka, a §7 parancsával): a 6 képernyő ma `unreachable`. Ha bármelyik időközben bekötődött, vedd ki az F1 scope-ból.
3. **Migráltság újramérése** (a §7 `grep design_system` parancsa): a megíráskor mind a 6 legacy volt. Ami migrálódott, az az F2 scope-ból kerül ki.
4. **Belépési pont helye:** a brief §5.2 a `practiceHub` (`/practice`) alá javasolja a flow-t. **Mérd meg** a mai shell-szerkezetet (`lib/app/routing/app_router.dart`, `adaptive_shell_routes.dart`), és ha a mérés más gazdát ad ki, a §5.2-t a MÉRÉSRE javítsd — az ADR a mért helyet rögzíti, nem a feltételezettet.
5. **Scope-fedezet:** ha a pre-flight mérése szerint az F1+F2 együtt nem fér egy körbe (az `E15-R06` precedense: a brief 8 képernyőt sorolt, a mérés hármat engedett), akkor **az F1 a kör**, és az F2 külön, ide hivatkozó körbe kerül — a §0.0.A-ban dokumentált mérésel. A fordítottja TILOS: F2 önmagában, F1 nélkül értelmetlen.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "lib/app/config/feature_flags.dart",
  "lib/core/feature_flags/feature_flag_registry.dart",
  "lib/features/practice/presentation/screens/practice_hub_screen.dart",
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "docs/adr/0480-practice-generator-entry-point-and-rollout.md",
  "docs/ui/migration-status.md",
  "docs/ui/retirement-plan.md",
  "docs/rounds/e15-r07-practice-generator-migration.md",
]
gate_tests = [
  "test/tooling/screen_reachability_test.dart",
  "test/tooling/feature_flag_audit_test.dart",
  "test/tooling/route_literal_guard_test.dart",
  "test/app/config/feature_flags_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/ui/ui_inventory_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff **új felhasználói utat nyit** egy eddig lezárt flow-hoz, és egy feature-flag rollout-határt mozdít el. A `security-reviewer` futtatása KÖTELEZŐ (a `plan_privacy_screen` consent-felület, és a bekötés adatgyűjtő utat tehet elérhetővé), a `flutter-reviewer` és a `flutter-devil-advocate` szintén.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bekötéshez a `practice_generator` `application/`, `domain/` vagy `data/` rétegét kellene módosítani (pl. mert egy provider hiányzik a képernyő futásához), a kimenet `stopped` — a generátor-motor viselkedése NEM ennek a körnek a hatásköre ([ADR 0255](../adr/0255-deterministic-practice-plan-generation.md), [L478](../LESSONS.md#l478)). A képernyők a meglévő providereikből élnek; ha nem, az önálló kör.

## 1. Cél

A Practice Generator flow-ja **megnyithatóvá** válik egy mért belépési ponton a nem-production buildekben (production változatlanul zárt), és a 6 képernyője a design-rendszer komponenseit használja — hogy a felhasználó a megtervezett tervkészítő utat végig tudja járni, egységes felülettel, 200%-os szövegskálán és mindkét locale-on.

## 2. Jelenlegi állapot — mért tények

- **Flag:** `practiceGeneratorEnabled` létezik (`feature_flags.dart:22,84,169`), de `false` a default konstruktorban ÉS a `forEnvironment` gyárban. A `plannerAssistEnabled` ugyanígy.
- **Registry:** `feature_flag_registry.dart:144` — `risk: medium`, `failClosedDefault: false`, `adr: '0255'`, és a `killSwitchPath` a mai „forráskód-változás kell hozzá" állapotot írja le.
- **Pinnelő cellák:** `test/app/config/feature_flags_test.dart` HÁROM cellája rögzíti a `false`-t: default konstruktor (14), `production` (26), `development` (36).
- **Route:** `lib/app/routing/app_route.dart` egyetlen `plan*`/`generator*` útvonalat sem deklarál; `app_router.dart` egyetlen `practice_generator` képernyőt sem nevez meg.
- **Elérhetőség:** `docs/ui/retirement-plan.md:241–246` — mind a 6 képernyő `unreachable`, „no route and no measured construction site anywhere in lib/".
- **Migráltság:** a 6 képernyő egyike sem importálja a `core/design_system`-et.
- **Minta a flag-kapuzott route-ra:** `app_router.dart:561–573` (`if (visionEnabled && visionSetupEnabled) ...[ GoRoute(path: AppRoutes.visionSetup, …) ]`) — a bekötés EZT a bevett alakot követi.
- **Képernyő-leltár:** `test/ui/ui_inventory_test.dart:26` egzakt `hasLength(96)`. A kör **nem hoz létre és nem töröl** képernyőt, tehát ez a szám VÁLTOZATLAN — a bekötés route-ot ad, nem képernyőt.

## 3. Scope

### F1 — bekötés (a kör kötelező magja)

**Benne van:** route-konstansok a 6 képernyőhöz az `AppRoutes`-ban · a hozzájuk tartozó, `practiceGeneratorEnabled`-re kapuzott `GoRoute` regisztrációk `app_router.dart`-ban a §2 mért mintája szerint · EGY mért belépési pont, amiről a flow megnyitható (§5.2) · a flag `forEnvironment` határának átállítása a `nonProd` mintára (production továbbra is OFF) · a registry `killSwitchPath`/`adr` mezőjének igazítása az ÚJ igazsághoz · a három pinnelő cella átírása az ÚJ szerződésre (nem törlés, nem `skip`) · az ÚJ ADR.

### F2 — migráció

**Benne van:** a 6 képernyő vizuális migrálása a design-rendszer komponenseire (`SsContentCard`, `SsButton`, `SsEmptyState`, `SsFailureState`, `SsMetricCard` és társaik; `SsSpacing`/`SsTypography` tokenek) · a felesleges `*ThemeScope` burkoló eltávolítása (az `E15-R01` óta az app témája hordozza a tokeneket, ÚJ burkoló NEM vezethető be) · a `migration-status.md` és a `retirement-plan.md` érintett sorainak frissítése a MÉRT új értékekre.

> ⚠ **Komponens-nevek MÉRÉSBŐL:** az `E15-R05`/`E15-R06` kétszer mérte, hogy a briefekben szereplő `SsListTile`/`SsErrorState`/`SsMetricTile` **nem létezik** — a valódi nevek `SsContentCard`/`SsFailureState`/`SsMetricCard`. A pre-flight a `lib/core/design_system/public.dart`-ból ellenőrizze a használt neveket, mielőtt egy sort is ír.

Batch-specifikus kikötések:

- a `plan_change_review_screen` diff-nézete megtartja a MÉRT változás-kategóriákat; csak a megjelenítés kerül komponensekre
- a `plan_privacy_screen` szövegei és consent-kapcsolói VÁLTOZATLANOK (adatvédelmi felület) — a bekötés sem lazíthat a consent-úton
- az ADR 0306 határa érvényben marad: a preview-felület a core flow-t nem blokkolhatja

**NINCS benne (tilos):**

- a `practice_generator` `application/`, `domain/`, `data/`, `providers/` rétege (viselkedés-változás → STOP).
- `plannerAssistEnabled` bekapcsolása — külön rollout-döntés.
- Új képernyő létrehozása vagy meglévő törlése (a `ui_inventory` száma VÁLTOZATLAN).
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (ÚJ kulcs felvehető, egyszerre `en` ÉS `hu`).
- `tools/**`, `.github/**`, `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk).
- Minden más `lib/features/**` képernyő.

## 4. Engedélyezett fájlok

| Útvonal | Indok | Fázis |
|---|---|---|
| `lib/app/routing/app_route.dart` | a 6 route-konstans | F1 |
| `lib/app/routing/app_router.dart` | a flag-kapuzott `GoRoute` regisztrációk + belépési pont | F1 |
| `lib/app/config/feature_flags.dart` | a `forEnvironment` határ átállítása `nonProd`-ra | F1 |
| `lib/core/feature_flags/feature_flag_registry.dart` | `killSwitchPath` + `adr` az ÚJ igazságra | F1 |
| `test/app/config/feature_flags_test.dart` | a három pin átírása az ÚJ szerződésre | F1 |
| `test/app/routing/app_router_test.dart` | a route-ok és a flag-kapu cellái | F1 |
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | a flow EGY belépési pontja (§5.2) — flag-kapuzva | F1 |
| `test/app/navigation/{adaptive_scaffold,tab_state_restoration,legacy_route_redirect}_test.dart` | navigációs őrök — a jogosultság PONTOSAN §5.5 szerinti | F1 |
| `docs/adr/0480-practice-generator-entry-point-and-rollout.md` | az ÚJ döntés (a szám a pre-flightból) | F1 |
| a 6 `*_screen.dart` a `practice_generator/presentation/screens/`-ben | migráció design-rendszer komponensekre | F2 |
| `test/features/practice_generator/presentation/{plan_setup,plan_preview,today_plan}_screen_test.dart` | állapot- és variáns-cellák | F2 |
| `test/features/practice_generator/accessibility/planner_accessibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad | F2 |
| `docs/ui/migration-status.md`, `docs/ui/retirement-plan.md` | a MÉRT új arány és az elérhetőségi verdikt | F2 |

## 5. Kötött architekturális döntések (ADR 0480 — a pre-flight erősíti meg a számot)

### 5.1 A production zárva marad

A flag a `practiceEngineV2Enabled` mintáját veszi át: `nonProd` → ON, `production` → OFF. **NEM elfogadható gyengítés:** a flag globális `true`-ra állítása „hogy a teszt egyszerűbb legyen". A production-cella (`feature_flags_test.dart:26`) marad, és `isFalse`-t vár TOVÁBBRA IS.

### 5.2 EGY belépési pont, mérten

A flow-nak pontosan egy gazdája van (a pre-flight §0.0.A/4 méri meg; a javaslat a `practiceHub` = `/practice` felület). **NEM elfogadható gyengítés:** hat különálló, egymásra nem hivatkozó route bekötése belépési pont nélkül — az az elérhetőség-mérőt kielégítené, a felhasználót nem.

### 5.3 A route-literálok az `AppRoutes`-ból jönnek

Beégetett útvonal-string a routerben tilos (a `test/tooling/route_literal_guard_test.dart` gépi őre). **NEM elfogadható gyengítés:** az őr fellazítása a kör kedvéért.

### 5.4 A viselkedés bitre azonos marad (F2)

Ugyanaz az adat, sorrend, és ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés.

### 5.5 A navigációs őrök jogosultsága PONTOSAN a belépési pont felvétele

A `test/app/navigation/` őrei (`adaptive_scaffold_test.dart`, `tab_state_restoration_test.dart`, `legacy_route_redirect_test.dart`) route-onként PINNELIK a renderelt képernyő típusát, ezért a shell egy destination-builderének átkötése pirosra váltja őket (MÉRVE: E13-R17 pre-flight, `flutter test test/app/navigation/` +33 → +30 -3 három destination átkötésével). Ez a kör **egyetlen meglévő destination buildert sem köt át** — ÚJ, flag-kapuzott route-okat vesz fel, és a `practice_hub_screen.dart`-ra EGY belépési pontot (§5.2). A jogosultság ezért PONTOSAN ennyi: az ÚJ belépési pont miatt szükséges cella-kiegészítés. Ugyanez áll a `practice_hub_screen.dart` TÍPUSÁT pinnelő négy őrre (`test/core/screen_size_guard_test.dart`, `test/features/practice/presentation/{practice_a11y_audit,practice_hub_screen,practice_routing}_test.dart`): a kör a hub képernyőt **nem cseréli le és nem alakítja át** — EGY belépési pont elemet vesz fel rá, flag-kapuzva —, tehát a jogosultság pontosan az ÚJ elem cellája. **Cella törlése, `skip`-je vagy gyengítése TILOS**, és a §10-ben szerepelnie kell a `flutter test test/app/navigation/` cellaszámának ELŐTTE és UTÁNA — a különbség csak az ÚJ cellák számával nőhet, csökkennie tilos.

### 5.6 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a kódba; ÚJ szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték | Fázis |
|---|---|---|---|
| A1 | A 6 képernyő verdiktje `unreachable`-ből **reachable**-be fordul, a MÉRŐ ESZKÖZ kimenetében | `dart run tool/check_screen_reachability.dart` előtte/utána (§7) | F1 |
| A2 | A route-ok a `practiceGeneratorEnabled` kapuja MÖGÖTT vannak: a flag OFF-ra állítva a 6 route NEM regisztrálódik | `app_router_test.dart` flag-be/ki cellapár | F1 |
| A3 | A flag `nonProd`-on ON, `production`-ön OFF; a default konstruktor OFF marad | `feature_flags_test.dart` három átírt cellája | F1 |
| A4 | A belépési pontról a flow ténylegesen megnyitható (nem csak a route létezik) | célzott widget-teszt: a belépési pont megnyomása a terv-képernyőre navigál | F1 |
| A5 | A `feature_flag_registry` `killSwitchPath`-ja az ÚJ igazságot írja le (nem a „hardcoded false"-t) | `feature_flag_audit_test.dart` + `git diff` | F1 |
| A6 | A `ui_inventory_test.dart` egzakt `hasLength(96)` VÁLTOZATLAN | a §7 gate | F1 |
| A7 | Mind a 6 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben | F2 |
| A8 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei | F2 |
| A9 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek **telefon-viewporton** | a küszöb-cellahármas (§6.2) | F2 |
| A10 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | `git diff` a teszt-fájlokon + a §7 gate | F2 |
| A11 | Nincs beégetett felhasználói szöveg | `test/l10n/hardcoded_string_guard_test.dart` | F1+F2 |
| A12 | A `migration-status.md` és a `retirement-plan.md` a MÉRT új értékeket írja | a dokumentumok + a mérés parancsa | F2 |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A route bekötve, de a flag-kapu lemaradt (production is megnyitná) | A2 + A3 |
| A flag globálisan `true`-ra állítva | A3 (production-cella) |
| Hat route bekötve, de egyikre sem mutat semmi a felületen | A4 |
| A registry `killSwitchPath`-ja a régi „hardcoded false" szöveget hagyja | A5 |
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A8 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A9 |
| Egy pinnelő cella `skip`-re kerül a zöldért | A10 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A7 |

**Valódi-sértés próbák (KÖTELEZŐ, a §10-ben dokumentálva):**
1. Vedd ki a flag-feltételt EGY route regisztrációjából → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.
2. Cserélj vissza EGY migrált képernyőn egy `SsFailureState`-et nyers `Text`-re → az **A8** cellának PIROSNAK kell lennie → állítsd vissza.

### 6.2 A szövegskála-cellák MÉRT szerződése (E15-R06 lecke, [L558](../LESSONS.md#l558)/[L559](../LESSONS.md#l559))

A `flutter_test` alapértelmezett viewportja **800×600** — szélesebb ÉS magasabb minden telefonnál, ezért a rajta mért „nincs túlcsordulás" **semmit nem bizonyít**. Az A9 cellái KÖTELEZŐEN:

- kipinnelt `tester.view.physicalSize = Size(360, 640)` + `devicePixelRatio = 1.0`, `addTearDown(tester.view.reset)`-tel;
- küszöb-cellahármas: a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A9 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá;
- `en` ÉS `hu` locale mindegyiken;
- lusta `ListView` esetén `scrollUntilVisible(...)` a mérendő widgetre **a `takeException()` ELŐTT** — különben a cella ÜRES fát mér, és a zöld mérési artefaktum.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/screen_reachability_test.dart test/tooling/feature_flag_audit_test.dart test/tooling/route_literal_guard_test.dart test/app/config/feature_flags_test.dart test/app/routing/app_router_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/core/screen_size_guard_test.dart test/features/practice/presentation/practice_a11y_audit_test.dart test/features/practice/presentation/practice_hub_screen_test.dart test/features/practice/presentation/practice_routing_test.dart test/ui/ui_inventory_test.dart test/features/practice_generator/accessibility/planner_accessibility_test.dart test/features/practice_generator/presentation/plan_setup_screen_test.dart
```

Az elérhetőség-mérés (a kimenet a §10-be, ELŐTTE és UTÁNA):

```bash
dart run tool/check_screen_reachability.dart | grep -i practice_generator
```

A migráltság-mérés (a kimenet a §10-be, MIGRATED/legacy sorokkal):

```bash
for f in lib/features/practice_generator/presentation/screens/today_plan_screen.dart lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart lib/features/practice_generator/presentation/screens/plan_setup_screen.dart lib/features/practice_generator/presentation/screens/plan_preview_screen.dart lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján ([ADR 0426](../adr/0426-golden-rasterization-on-the-gate-architecture.md)):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. **Pre-flight** (§0.0.A): ADR-szám, elérhetőség- és migráltság-mérés, a belépési pont gazdájának megmérése, komponens-nevek ellenőrzése a `design_system/public.dart`-ból.
2. **F1/a:** route-konstansok → flag-kapuzott `GoRoute` regisztrációk → belépési pont.
3. **F1/b:** a flag `nonProd` határa + registry `killSwitchPath`/`adr` → a három pin átírása → `app_router_test` flag-be/ki cellapár + a belépési pont cellája.
4. **F1/c:** ADR megírása, elérhetőség-mérés ÚJRA (A1 bizonyíték), valódi-sértés próba 1.
5. **F2:** képernyőnként komponens-csere → állapotok → tokenek → `*ThemeScope` eltávolítás; cellák a 360×640 viewporton (§6.2); valódi-sértés próba 2.
6. `migration-status.md` + `retirement-plan.md` frissítése a MÉRT értékekre.

## 9. Kockázatok

- **Néma bekötés.** A route létezik, de semmi nem navigál rá — a mérő eszköz zöld, a felhasználó nem jut oda (A4 fogja).
- **Kapu-szivárgás production-be.** Egy elfelejtett flag-feltétel élesben nyit meg egy nem kész flow-t (A2+A3 fogja; a `security-reviewer` kötelező).
- **Rossz viewport.** A 800×600-as alapértelmezésen mért zöld szövegskála-cella mérési artefaktum (§6.2, L558/L559).
- **Scope-csúszás a viselkedés felé.** Ha a képernyő futásához provider-módosítás kellene, az STOP-eset, nem „apró kiegészítés".
- **Kétfázisú túlvállalás.** Ha az F1+F2 nem fér egy körbe, az F1 a kör — a §0.0.A/5 szerint, MÉRÉSSEL dokumentálva.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
