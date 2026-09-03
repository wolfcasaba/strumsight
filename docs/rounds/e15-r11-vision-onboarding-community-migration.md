# E15-R11 — Vision, onboarding és a maradék közösségi képernyő

- **Státusz:** READY (pre-flight brief-revízió §0.0, 2026-09-03, `main @ aead0d49`; előre megírva 2026-08-28, `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 11
- **Kör-azonosító:** `E15-R11`
- **Branch:** `<motor>/e15-r11-vision-onboarding-community-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "vision setup session calibration onboarding UI"` → **[ADR 0181](../adr/0181-vision-manual-calibration-fallback.md)** (kézi kalibrációs tartalék) — a kalibrációs folyamat lépései és tartalék-útja nem változhat.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/vision/presentation/screens/vision_setup_screen.dart lib/features/vision/presentation/screens/vision_session_screen.dart lib/features/vision/presentation/screens/guitar_calibration_screen.dart lib/features/onboarding/screens/onboarding_screen.dart lib/features/community/presentation/screens/followers_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **5** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 Pre-flight brief-revízió (orchestrátor, 2026-09-03, `main @ aead0d49`)

A pre-flight a brief MINDEN hivatkozott komponensnevét és minden érintett
kipinnelt harnesst kimért a kódból. A `brief-lint --level strict` (a PR #543 /
S14 utáni tooling) **0 leletet** adott — az alábbi hét lelet a lint hatókörén
KÍVÜL esik, ezért kézi mérés fogta meg őket. **Ez a szakasz ERŐSEBB a brief
többi részénél**: ahol eltér, ez érvényes.

### R1 (BASE) — a §3/§5.2 három komponense NEM LÉTEZIK

MÉRVE (`grep -rl "class Ss…" lib/core/design_system/`):

| Brief-név | Mérés | Amit HELYETTE használsz |
|---|---|---|
| `SsListTile` | **ABSENT** | `SsContentCard` / `SsEventListRow` (lista-sor), `SsSwitchRow` (kapcsolós sor) |
| `SsErrorState` | **ABSENT** | **`SsFailureState`** (+ `SsFailurePresentation` / `SsFailureAction`) |
| `SsMetricTile` | **ABSENT** | `SsMetricCard` (skeletonja: `SsMetricCardSkeleton`) |

`lib/core/design_system/**` **tilos zóna** (§4), tehát hiányzó komponenst
létrehozni NEM szabad. A §5.2 szerződése változatlan tartalommal, MÉRT nevekkel:
üres → `SsEmptyState`, hiba → **`SsFailureState`**, betöltés → `SsSkeleton`
(vagy `SsAsyncState`). A vision-út engedély-állapotára létezik dedikált
komponens: **`SsPermissionState`** — ahol a képernyő ma engedély-elutasítást
rajzol, azt használd.

A ténylegesen létező felület (a `public.dart` barrel mögött) 53 `Ss*` osztály;
ha egy állapothoz nem találsz komponenst, az **STOP** (`stopped` jelzés), nem
saját komponens.

### R2 (BASE, L593) — a kipinnelt harnessek téma NÉLKÜL pumpolnak

MÉRVE — csupasz `MaterialApp`, `theme:` nélkül:
`vision_setup_screen_test.dart:23`, `guitar_calibration_screen_test.dart:80`,
`vision_one_cue_test.dart:36`, `vision_degraded_test.dart:29`,
`block_mute_test.dart:37`, `onboarding_test.dart:52` és `:108`.

A migrált képernyő `SsCard`-ja `ss_surface.dart:42` → `ss_elevation.dart:14-15`
úton **két `!`-es** `theme.extension<SsColorScheme>()!` /
`theme.extension<SsThemeBehavior>()!` olvasást végez → téma nélkül
**null-check crash**. Ez pontosan az [L593](../LESSONS.md#l593) (E15-R09
BLOCKER-1) hibaosztálya.

**Kötelező:** minden érintett harness a VALÓDI futásidejű témát adja
(`SsLightTheme.data()` / `SsDarkTheme.data()`, [ADR 0466](../adr/0466-app-runtime-theme-is-the-design-system-theme.md)),
`theme:`-ként a `MaterialApp`-ra. Ez a harness **valósághűbbé tétele**, nem
gyengítés: cella törlése, `skip`-je vagy állítás-lazítása továbbra is TILOS
(§0.0 alap-szabály, A4).

### R3 (L593) — egy kipinnelt harness kimaradt a kapuból

`test/app/offline_network_guard_test.dart:293` **`VisionSessionScreen`**-t
állít (`find.byType`), de a brief sem az `allowed_paths`-on, sem a
`gate_tests`-ben nem sorolta fel → a kör saját kapuja nem mérné.

Felvéve a **`gate_tests`-be, MÉRÉS-ONLY** (az `allowed_paths`-ra NEM): a fájl
`:170`-en a valódi `StrumSightApp`-ot pumpolja, tehát az ADR 0466 óta a
design-rendszer témáját ÖRÖKLI — R2-okból nem bukhat el. Ha mégis pirosra vált,
a **képernyőt** kell javítani, nem a tesztet; ha a teszt módosítása lenne
szükséges, az **STOP** (a fájl az `allowed_paths`-on kívül van → H3).

### R4 — barrel-import KÖTELEZŐ, mély import TILOS

Az öt képernyő a design-rendszert KIZÁRÓLAG a barrelen át éri el:

```dart
import 'package:strumsight/core/design_system/public.dart';
```

Mély import (`…/design_system/components/…`, `…/foundations/…`) tilos
([ADR 0273](../adr/0273-design-system-token-source-of-truth.md) §1,
[ADR 0494](../adr/0494-derived-completion-matrix-and-h5-counter-reset.md)) — ez
volt az E15-R09 **BLOCKER-2** (24 mély import). MÉRVE: a szabály azóta a
`tool/check_architecture.dart`-ban él (`ss_… designSystemRoot` ág), tehát a
`tools/round-gate.sh` **`architecture`** lépése LOKÁLISAN méri. A
`test/core/architecture_dependency_test.dart` a `gate_tests`-be felvéve
(§0.0.C/R20 mintájára).

### R5 — az A3 bizonyítéka COMMITOLT cella, nem `/tmp`-próba

Az E15-R09-ben az A3 mércéje egy törölt `/tmp`-próbateszt volt. Képernyőnként a
variáns-cellák (textScale **1.5 / 2.0 / 2.5** × `en`/`hu`) HELYE kötött, és
mind az `allowed_paths`-on van — ÚJ tesztfájl nem kell:

| Képernyő | A variáns-cellák fájlja |
|---|---|
| `vision_setup_screen` | `test/features/vision/presentation/vision_setup_screen_test.dart` |
| `guitar_calibration_screen` | `test/features/vision/presentation/guitar_calibration_screen_test.dart` |
| `vision_session_screen` | `test/features/vision/vision_one_cue_test.dart` |
| `onboarding_screen` | `test/features/onboarding/onboarding_test.dart` |
| `followers_screen` | `test/features/community/block_mute_test.dart` |

A §6 küszöb-hármasa változatlan: `1.5` és `2.0` → **túlcsordulás nélkül
kötelező**; `2.5` → NEM követelmény, és a `2.0` teljesítése nem hivatkozhat rá.
Ugyanezekben a fájlokban kell legalább EGY design-rendszer **típus-állítás**
képernyőnként (`expect(find.byType(SsFailureState), …)` és társai) — az A2
mércéje nem lehet pusztán szöveg-keresés.

### R6 — `*ThemeScope`: pontosan EGY fájl érintett

MÉRVE (`grep -n ThemeScope` az öt fájlon): kizárólag
`followers_screen.dart:163` → `CommunityThemeScope`. A másik négy képernyőn ma
NINCS burkoló. A §3 „burkoló eltávolítása" tehát egyetlen fájlra vonatkozik;
`vision_result_screen.dart:37` (`VisionThemeScope`) **NINCS a scope-ban**, ne
nyúlj hozzá.

### R7 — az A7 mért aránya

MÉRVE a `docs/ui/migration-status.md:4` szerint a kör ELŐTT: **80/96
(83,333%)**. Az öt képernyő migrálása után az elvárt érték
**85/96 = 88,542%** (`python3 -c "print(round(85/96*100,3))"` → `88.542`). A
dokumentum ezt az arányt írja, a §7 mérő-parancsának kimenetével együtt.

### ADR

**Nincs új ADR**, és nem is kerül kiosztásra: a kör egyetlen ÚJ architekturális
döntést sem köt — a hivatkozott szerződéseket az ADR 0181 / 0184 / 0196 / 0273 /
0291 / 0399 / 0466 / 0494 már rögzíti. (Azonos az `E15-R08` és `E15-R09`
lezárásának mintájával; a `docs/adr/**` a §4 szerint tilos zóna.)

## 0.0.1 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a sáv utolsó migrációs batch-e: a kamera-út három képernyője, az onboarding (az ELSŐ, amit egy új felhasználó lát) és az egyetlen maradék közösségi képernyő.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/presentation/screens/vision_setup_screen.dart",
  "lib/features/vision/presentation/screens/vision_session_screen.dart",
  "lib/features/vision/presentation/screens/guitar_calibration_screen.dart",
  "lib/features/onboarding/screens/onboarding_screen.dart",
  "lib/features/community/presentation/screens/followers_screen.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
  "test/ui/goldens/e13_r33_screens_golden_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r11-vision-onboarding-community-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/community/block_mute_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/features/vision/presentation/guitar_calibration_screen_test.dart",
  "test/features/vision/presentation/vision_setup_screen_test.dart",
  "test/features/vision/vision_cleanup_test.dart",
  "test/features/vision/vision_degraded_test.dart",
  "test/features/vision/vision_one_cue_test.dart",
  "test/features/vision/vision_permission_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r30_screens_golden_test.dart",
  "test/ui/goldens/e13_r33_screens_golden_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/architecture_dependency_test.dart",
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

A batch 5 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `vision_setup_screen.dart`, `vision_session_screen.dart`, `guitar_calibration_screen.dart`, `onboarding_screen.dart`, `followers_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 5 képernyő vizuális migrálása (`SsCard`, `SsSection`, `SsButton`, `SsIconButton`, `SsContentCard`, `SsEmptyState`, `SsFailureState`, `SsSkeleton`, `SsPermissionState`, `SsMetricCard` és társaik — a MÉRT nevek a §0.0/R1-ben; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a kamera-életciklus (lease, engedély, hőmérsékleti degradáció) ÉRINTETLEN (ADR 0184/0196)
- az onboarding lépés-sorrendje és a `seen` állapot kezelése változatlan; a permission-primer az `E15-R02`-ben MÁR javítva lett
- a `followers_screen` privát-profil szabályai (ADR 0291/0399) érvényben maradnak

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/vision/presentation/screens/vision_setup_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/vision/presentation/screens/vision_session_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/vision/presentation/screens/guitar_calibration_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/onboarding/screens/onboarding_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/community/presentation/screens/followers_screen.dart` | migráció design-rendszer komponensekre |
| `test/accessibility/closure_suite_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/routing/onboarding_first_win_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/core/screen_size_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/community/block_mute_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/first_win_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/onboarding_resume_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/onboarding_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/onboarding/permission_primer_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/presentation/guitar_calibration_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/presentation/vision_setup_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_cleanup_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_degraded_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_one_cue_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/vision/vision_permission_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r16_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r30_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r33_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/ui_baseline_screenshot_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → **`SsFailureState`** (a `SsErrorState` NEM létezik — §0.0/R1), betöltés → `SsSkeleton` (vagy `SsAsyncState`), engedély-elutasítás → `SsPermissionState`. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 5 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
| A2 | Minden migrált képernyő üres/betöltés/hiba állapota design-rendszer-komponens | a batch célzott widget-tesztjei |
| A3 | A képernyők `textScaler 2.0` mellett, `en` ÉS `hu` locale-on túlcsordulás nélkül renderelnek | a batch variáns-cellái |
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

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsFailureState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/offline_network_guard_test.dart test/core/architecture_dependency_test.dart test/accessibility/closure_suite_test.dart test/app/routing/app_router_test.dart test/app/routing/onboarding_first_win_test.dart test/core/screen_size_guard_test.dart test/features/community/block_mute_test.dart test/features/onboarding/first_win_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/onboarding_test.dart test/features/onboarding/permission_primer_test.dart test/features/vision/presentation/guitar_calibration_screen_test.dart test/features/vision/presentation/vision_setup_screen_test.dart test/features/vision/vision_cleanup_test.dart test/features/vision/vision_degraded_test.dart test/features/vision/vision_one_cue_test.dart test/features/vision/vision_permission_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e13_r30_screens_golden_test.dart test/ui/goldens/e13_r33_screens_golden_test.dart test/ui/ui_baseline_screenshot_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/vision/presentation/screens/vision_setup_screen.dart lib/features/vision/presentation/screens/vision_session_screen.dart lib/features/vision/presentation/screens/guitar_calibration_screen.dart lib/features/onboarding/screens/onboarding_screen.dart lib/features/community/presentation/screens/followers_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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
