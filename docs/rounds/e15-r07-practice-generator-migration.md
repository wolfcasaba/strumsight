# E15-R07 — Practice Generator képernyők migrálása

- **Státusz:** REVISED (előre megírva 2026-08-28; pre-flight §0.0.A revízió 2026-09-01, kód újramérve: `main @ c2c38014`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 7
- **Kör-azonosító:** `E15-R07`
- **Branch:** `<motor>/e15-r07-practice-generator-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "practice generator plan preview weekly today plan UI"` → **[ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md)** (plan-preview aktiválási határ) — a preview-felület a core útra nem hathat, és ezt a migráció nem lazíthatja fel.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/practice_generator/presentation/screens/today_plan_screen.dart lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart lib/features/practice_generator/presentation/screens/plan_setup_screen.dart lib/features/practice_generator/presentation/screens/plan_preview_screen.dart lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **6** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

~~Az `E15-R02` óta a Practice Generator flag BE van kapcsolva az előnézeti/nem-production buildekben, tehát a terv-képernyők a felhasználó útjába kerültek — a legacy megjelenésük itt a legszembetűnőbb.~~ **VISSZAVONVA — mérve hamis, lásd §0.0.A/R1.**

## 0.0.A Pre-flight brief-revízió (orchestrátor, 2026-09-01, `main @ c2c38014`)

Az alábbi hét pont a brief MÉRT javítása. A kör ezzel a revízióval indul; ahol
a revízió és a brief eredeti szövege ütközik, **a revízió az érvényes**.

### R1 — A flag NINCS bekapcsolva; a 6 képernyő MA IS elérhetetlen (a §0.0 állítás hamis)

```
lib/app/config/feature_flags.dart:22   this.practiceGeneratorEnabled = false,   # default ctor
lib/app/config/feature_flags.dart:84   practiceGeneratorEnabled: false,         # FeatureFlags.forEnvironment — MINDEN környezet
test/app/config/feature_flags_test.dart:14,26,36  expect(flags.practiceGeneratorEnabled, isFalse)
```

A `forEnvironment` gyár a `nonProd` értéket a `practiceEngineV2Enabled`,
`migratedLearnEnabled`, `songTrainerV2Enabled` mezőkre adja — a
`practiceGeneratorEnabled` **literál `false`**, tehát nem-production buildben
SEM kapcsol be, és ezt három kipinnelt cella őrzi. A `docs/rounds/e15-r02-*.md`
a „Practice Generator" kifejezést egyszer sem említi, tehát a hivatkozott
eredet sem áll fenn.

Építési hely és route ugyancsak nincs (mérve `main @ c2c38014`-en):

```bash
for c in TodayPlanScreen WeeklyPlanScreen PlanSetupScreen PlanPreviewScreen \
         PlanChangeReviewScreen PlanPrivacyScreen; do
  grep -rn "$c" lib/ --include=*.dart | grep -v practice_generator/presentation/screens/
done                                   # → 0 találat (a PlanPreviewScreen-re jövő
                                       #   ai_tutor-találat a MÁS osztály, PracticePlanPreviewScreen)
grep -rn practice_generator lib/app/   # → 0 találat
```

Ez pontosan megerősíti az `E15-R03` mérését ([ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md),
`docs/ui/retirement-plan.md` §3.2): mind a 6 képernyő `unreachable`.

### R2 — A kör ettől függetlenül FUT, de a valódi indoklással

A retirement-plan §2 prózája szerint egy elérhetetlen képernyőhöz Ch15-kört
rendelni pazarlás. Ez **indoklás, nem tiltás**: az ADR 0471 kötött döntései
közül a **D5** csak a törlést tiltja („this round deletes nothing"), a **D6**
csak azt írja elő, hogy minden **elérhető** legacy képernyőnek legyen gazdája,
a **D7** pedig kimondja, hogy a statikus mérés korlátos és a verdikt javaslat,
nem automatikus felhatalmazás. Egy `unreachable` verdiktű képernyő
migrálását egyik sem tiltja, és ezeknek a soroknak a verdiktje **nem** `retire`.

A kört a **commitolt sor-fájl** rendeli el (`docs/execution/pipeline-queue.tsv:558`,
`E15-R07 … pending`), és a Ch15 sorozat szándékosan tágabb a terv §4-énél: az
`E15-R11` (`vision-onboarding-community`) ugyanígy olyan felületeket visz,
amelyeket a terv `unreachable`-nek mért. A kör tehát a sorozat írott
szándékát követi.

**Amit ez a kör ettől NEM tesz:** nem töröl képernyőt vagy route-ot (D5), nem
köt be belépési pontot (az a §3 tiltott `lib/app/**` zónája), és **nem írja át
a `docs/ui/retirement-plan.md`-t** — az a lezárt `E15-R03` artefaktuma
(H1/H2). A `test/tooling/screen_reachability_test.dart` A3-cellája kizárólag
`isReachable` képernyőkre állít (`if (!verdict.isReachable) continue;`), az
A4 csak a `retire` sorokra — ezért ez a diff egyiket sem billenti pirosra.

### R3 — Gazda-kör eltérés a terv §4-étől (dokumentált, nem új)

A `retirement-plan.md` §4 az `E15-R07`-et a Learn + Onboarding batch-re osztja,
a Practice Generatorhoz pedig egyáltalán nem rendel kört. A commitolt sor-fájl
és minden megírt brief ettől eltérően számoz (`E15-R04` = Practice+Learn,
`E15-R07` = Practice Generator, …). Ez ugyanaz a már dokumentált eltérés, amit
a `docs/ui/migration-status.md` az `E15-R05` bejegyzésében rögzít
(„Owner-round correction against `retirement-plan.md` §4"). A sor-fájl a
mérvadó; a terv §4 oszlopát ez a kör **nem** írja át.

### R4 — Három megnevezett komponens NEM LÉTEZIK (a §3/§5.2 javítva)

Mérve (`grep -rn "class Ss…" lib/core/design_system/`):

| A briefben | Valóság |
|---|---|
| `SsErrorState` | **nincs** → a hibaállapot komponense **`SsFailureState`** (`components/feedback/ss_failure_state.dart`), amely `SsFailurePresentation`-t vár |
| `SsListTile` | **nincs** → sorokhoz `SsContentCard`, kapcsolós sorhoz `SsSwitchRow`, listaelemhez `SsEventListRow` |
| `SsMetricTile` | **nincs** → **`SsMetricCard`** (`components/cards/ss_metric_card.dart`) |

Létező és ide illő komponensek: `SsCard`, `SsContentCard`, `SsButton`,
`SsEmptyState`, `SsFailureState`, `SsSkeleton`, `SsAsyncState`, `SsSwitchRow`,
`SsSection`, `SsMetricCard`, `SsStatusBadge`, `SsTextField`, `SsChoice`,
`SsValueSlider`; tokenek: `SsSpacing`, `SsTypography`, `SsColorScheme`, `SsRadius`.

**`SsEmptyState` kötelező paraméterei:** `icon`, `title`, `message`,
`actionLabel`, `onAction` — **mind `required`**. Ahol a képernyőn nincs VALÓDI,
már létező akció, ott `SsEmptyState`-et használni akciót HAZUDNA: ilyenkor az
`E15-R04` óta bevett, képernyő-lokális, tokenizált üres-állapot a helyes
megoldás (`migration-status.md` `E15-R05`/`E15-R06` bejegyzés). Ugyanez áll az
`SsFailureState`-re: valódi `SsFailurePresentation` nélkül tokenizált,
képernyő-lokális hibaállapot a megoldás — **nyers `Text('Hiba')` és nyers
`CircularProgressIndicator` viszont NEM marad** (§5.2).

### R5 — ARB-útvonalak: a §3 engedélye eddig út nélkül állt

A §3 megengedi új ARB-kulcs felvételét, de az `allowed_paths` egyetlen ARB-fájlt
sem tartalmazott — az engedély így végrehajthatatlan volt. Az `E15-R06`
mérése szerint (`migration-status.md`, „ARB-source correction") a
`lib/l10n/app_*.arb` **generált** kimenet (`tool/gen_l10n_segments.dart`), az
igazi forrás a `lib/l10n/base/app_*.arb`. Mind a négy fájl felkerül az
engedélyezett listára; új kulcs **`en` és `hu` egyszerre**.

### R6 — Két létező teszt konstruálja a migrált képernyőket, de nem volt a listán

```
test/features/practice_generator/presentation/today_plan_screen_test.dart:15,38,63  TodayPlanScreen(
test/features/practice_generator/presentation/plan_preview_screen_test.dart:387     PlanPreviewScreen(
test/features/practice_generator/accessibility/planner_privacy_test.dart:166        PlanPrivacyScreen(
```

Ezek a migrációtól elbukhatnak, miközben sem az `allowed_paths`-on, sem a
`gate_tests`-en nem voltak. Mindhárom felkerül **típus-pinnelő őrként**: a §0.0
jogosultsága rájuk is szó szerint áll — **cella törlése, `skip`-je vagy
gyengítése TILOS**, csak a migrációt követő szerkezeti illesztés megengedett.
A `gate_tests` a `test/l10n/hardcoded_string_guard_test.dart`-tal is bővül (az
A6 bizonyítéka).

### R7 — A `textScaler` cellák TELEFON-méretű viewporton mérjenek (L558/L559)

A `flutter_test` alapértelmezett viewportja **800×600** — szélesebb ÉS magasabb
minden telefonnál, és a lusta `ListView` a viewport alá eső gyermeket fel sem
építi, ezért a rajta mért „nincs túlcsordulás" akár ÜRES fát is mérhet
([L558](../LESSONS.md#l558), `E15-R06`). Az A3 cellái ezért **kötelezően**:

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1.0;
addTearDown(tester.view.reset);
```

És [L559](../LESSONS.md#l559): ha a migráció MINTA-szintű elrendezési kockázatot
hoz (pl. az `SsEmptyState` négy eleme a korábbi kettő helyett), a védelmet
**minden testvér-példányra** fel kell tenni, nem csak az elsőre — a §10-ben
tételesen sorold fel, hány példány van és mindegyik védve van-e.

### R8 — A `presentation/widgets/` a tiltott zónában marad

A 6 képernyő közös widgeteket használ
(`availability_editor.dart`, `catch_up_sheet.dart`, `plan_block_card.dart`,
`plan_day_card.dart`, `plan_reason_sheet.dart`, `practice_goal_picker.dart`).
Ezek **nincsenek** az `allowed_paths`-on, tehát nem módosíthatók (H3). A kör a
KÉPERNYŐ-fájlokat migrálja; a beágyazott widgetek megjelenése változatlan
marad, és ez nem hiányosság, hanem a kör határa. Ha egy képernyő A1/A2
teljesítése CSAK egy ilyen widget módosításával lenne elérhető, az a §0
**STOP-protokoll** esete (`stopped` jelzés), nem listatágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart",
  "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r07-practice-generator-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/today_plan_screen_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 6 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `today_plan_screen.dart`, `weekly_plan_screen.dart`, `plan_setup_screen.dart`, `plan_preview_screen.dart`, `plan_change_review_screen.dart`, `plan_privacy_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 6 képernyő vizuális migrálása (`SsCard`, `SsContentCard`, `SsButton`, `SsSwitchRow`, `SsEmptyState`, `SsFailureState`, `SsSkeleton`, `SsSection`, `SsMetricCard` és társaik; `SsSpacing`/`SsTypography`/`SsColorScheme`/`SsRadius` tokenek — a MÉRT komponens-lista a §0.0.A/R4-ben) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a `plan_change_review_screen` diff-nézete megtartja a MÉRT változás-kategóriákat; a megjelenítés kerül csak komponensekre
- a `plan_privacy_screen` szövegei és consent-kapcsolói VÁLTOZATLANOK (adatvédelmi felület)
- az ADR 0306 határa érvényben marad: a preview-felület a core flow-t nem blokkolhatja

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice_generator/presentation/screens/today_plan_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice_generator/presentation/screens/plan_setup_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice_generator/presentation/screens/plan_preview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart` | migráció design-rendszer komponensekre |
| `test/features/practice_generator/accessibility/planner_accessibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice_generator/presentation/plan_setup_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice_generator/accessibility/planner_privacy_test.dart` | típus-pinnelő őr (`PlanPrivacyScreen`) — §0.0.A/R6 |
| `test/features/practice_generator/presentation/plan_preview_screen_test.dart` | típus-pinnelő őr (`PlanPreviewScreen`) — §0.0.A/R6 |
| `test/features/practice_generator/presentation/today_plan_screen_test.dart` | típus-pinnelő őr (`TodayPlanScreen`) — §0.0.A/R6 |
| `lib/l10n/base/app_en.arb`, `lib/l10n/base/app_hu.arb` | ARB-FORRÁS, ha a komponens új kulcsot igényel — §0.0.A/R5 |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | a fentiek GENERÁLT kimenete (`tool/gen_l10n_segments.dart`) — §0.0.A/R5 |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsFailureState`, betöltés → `SsSkeleton`
(a design-rendszer betöltés-komponense). **NEM elfogadható gyengítés:** nyers
`CircularProgressIndicator` (ma: `plan_setup_screen.dart:65`) vagy csupasz
`Text('Hiba')` meghagyása.

**Kivétel, §0.0.A/R4 szerint:** ahol nincs VALÓDI, már létező akció
(`SsEmptyState` mind az 5 paramétere `required`), illetve nincs valódi
`SsFailurePresentation`, ott a bevett képernyő-lokális, **tokenizált**
állapot-widget a helyes megoldás — akciót vagy hibamodellt kitalálni tilos. A
§10-ben minden ilyen kivételt tételesen indokolj.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 6 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek — **TELEFON-méretű viewporton** (`360×640`, `devicePixelRatio 1.0`), az alapértelmezett 800×600 NEM elfogadható (§0.0.A/R7, [L558](../LESSONS.md#l558)) | a batch variáns-cellái |
| A4 | A típus-pinnelő tesztek VÁLTOZATLANUL zöldek, egyetlen cellájuk sem törölt/`skip`-elt | a §7 gate + `git diff` a teszt-fájlokon |
| A5 | A `ui_inventory_test.dart` egzakt száma VÁLTOZATLAN | a §7 gate |
| A6 | Nincs beégetett felhasználói szöveg a migrált kódban | `test/l10n/hardcoded_string_guard_test.dart` |
| A7 | A `migration-status.md` a MÉRT új arányt írja (a mérés parancsával) | a dokumentum |

**Küszöb-cellahármas a szövegskálára** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → nincs túlcsordulás; **pontosan rajta** (`2.0`) → nincs túlcsordulás, EZ az A3 feltétele; a küszöb **fölött** (`2.5`) → nem követelmény, és a `2.0` teljesítése nem hivatkozhat rá.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A képernyő megkapja a komponenseket, de a hibaállapot nyers `Text` marad | A2 |
| A migráció csak `en` locale-on lett kipróbálva, a hosszabb `hu` szöveg túlcsordul | A3 |
| A migráció közben egy típus-pinnelő teszt cellája `skip`-re kerül a zöldért | A4 |
| Egy szöveg beégetve kerül a kódba | A6 |
| A képernyő importálja a design-rendszert, de a stílus továbbra is `AppColors`-ból jön | A1 (a mérés a MIGRÁLT/legacy besorolást is ellenőrzi a kód alapján) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsErrorState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/l10n/hardcoded_string_guard_test.dart test/features/practice_generator/accessibility/planner_accessibility_test.dart test/features/practice_generator/accessibility/planner_privacy_test.dart test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/plan_preview_screen_test.dart test/features/practice_generator/presentation/today_plan_screen_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/practice_generator/presentation/screens/today_plan_screen.dart lib/features/practice_generator/presentation/screens/weekly_plan_screen.dart lib/features/practice_generator/presentation/screens/plan_setup_screen.dart lib/features/practice_generator/presentation/screens/plan_preview_screen.dart lib/features/practice_generator/presentation/screens/plan_change_review_screen.dart lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
```

Ha a batch képernyőjének VAN golden PNG-je, az újrafelvétel KIZÁRÓLAG a merge-kapu architektúráján (ADR 0426):

```bash
tools/golden-x86.sh record <a batch érintett golden-teszt fájljai>
```

## 8. Implementációs sorrend

1. A `retirement-plan.md` beolvasása → a tényleges képernyő-lista.
2. Képernyőnként: komponens-csere → állapotok (üres/betöltés/hiba) → tokenek → `*ThemeScope` eltávolítása.
3. A batch célzott widget-tesztjei (állapotok + `textScale 2.0` + `en`/`hu`).
4. A mérés futtatása, `migration-status.md` frissítése.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma információvesztés.** A migráció közben elveszett állapot vagy mező a leggyakoribb hiba (A2).
- **Locale-vak elrendezés.** A magyar szövegek hosszabbak; az `en`-re szabott elrendezés túlcsordul (A3).
- **Scope-csúszás a viselkedés felé.** Egy „apró" providers-módosítás a kör mérhetőségét rontja (STOP-eset).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
