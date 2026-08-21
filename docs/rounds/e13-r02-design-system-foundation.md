# E13-R02 — Design system foundation és compatibility layer

- **Státusz:** PRE-FLIGHTED (2026-08-21, kód újramérve: `main @ 15f9936f`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 2
- **Kör-azonosító:** `E13-R02`
- **Branch:** `terra/e13-r02-design-system-foundation`
- **Előfeltétel:** `E13-R01` merge-elve (baseline inventár)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0273`](../adr/0273-design-system-token-source-of-truth.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R01
> `docs/ui/baseline/token-debt.md` tényleges leleteit, és a `lib/core/theme/`
> négy fájljának TÉNYLEGES publikus felületét (`AppColors`, `AppPalette`,
> `AppTheme`) — a §5.2 kompatibilitási adapter ezekre épül. Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió — 2026-08-21

Az indításkori mérés az előre megírt brief négy elavult állítását pontosítja;
az engedélyezett production fájllista nem tágul.

1. Az E13-R01 baseline már a `main @ 15f9936f` része. A kanonikus inventory
   **58 production screen source**-ot tart nyilván, nem 51-et. A jelenlegi
   theme három publikus típusa változatlanul `AppColors`, `AppPalette` és
   `AppTheme`; 44 alkalmazásforrás importálja közvetlenül a három theme-fájl
   valamelyikét. A `lib/core/design_system/` továbbra sem létezik.
2. A `test/core/architecture_dependency_test.dart` 854 soros, nem 467; a
   repository-szintű `checkArchitecture` mellett körspecifikus, valódi
   forrást bejáró őrök mintája él benne. Az új design-system őr ezt a mintát
   követi, mert a közös `tool/check_architecture.dart` tilos zóna.
3. Az ADR 0273 már merge-elt, elfogadott döntés (`903e7a7d`, 2026-08-15).
   A kötelező foglaló ezért ma `0380`-at adna; új ADR létrehozása vagy a
   merge-elt 0273 átírása tilos. Ez a kör a változatlan ADR 0273-at hajtja
   végre.
4. A jelenlegi `FeatureFlags` nem tartalmaz Component Catalog flaget, az
   `lib/app/**` pedig tilos zóna. Ezért ebben a körben nincs router-wiring:
   az új catalog screen saját, default-OFF compile-time flaget és debug-build
   kaput ad, a route factory tiltott állapotban nem hoz létre route-ot. A
   production app routere érintetlen; a későbbi wiring külön kör.

Kipinnelt foundation értékek a Chapter 13 §8, §9 és §13 alapján:

- breakpoint: `599 / 839 / 840 / 1200` dp;
- spacing: `0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64` dp;
- radius: `6, 10, 16, 20, 28, 999` dp;
- motion: `80, 120, 200, 300, 700` ms, reduced-motionhoz `Duration.zero`;
- semantics: minimum interaktív cél `48` dp, támogatott text scale `2.0`.

Kötelező visszakeresett előzmény, szűkített → kockázati → teljes korpusz
sorrendben:
az `adr/0273` közvetlenül megerősítette az egyetlen token-forrást és a
`public.dart` belépőt; az `adr/0002` a fokozatos kompatibilitási réteget; a
`lessons/L190` pedig azt, hogy a barrel-őr az import célját méri. A
Component Catalog flagre nem volt közvetlen, ennél relevánsabb előzmény.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_breakpoints.dart",
  "lib/core/design_system/foundations/ss_spacing.dart",
  "lib/core/design_system/foundations/ss_radius.dart",
  "lib/core/design_system/foundations/ss_motion.dart",
  "lib/core/design_system/foundations/ss_semantics.dart",
  "lib/core/design_system/themes/ss_theme_extensions.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/foundations_test.dart",
  "test/core/design_system/component_catalog_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e13-r02-design-system-foundation.md",
]
gate_tests = [
  "test/core/design_system/foundations_test.dart",
  "test/core/design_system/component_catalog_test.dart",
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

A `core/design_system` alapstruktúra létrehozása **úgy, hogy a meglévő
`core/theme` továbbra is működjön** (SDD Ch13 Kör 2).

## 2. Jelenlegi állapot — mért tények

- `lib/core/design_system/` **nem létezik** — ez a kör hozza létre.
- `lib/core/theme/`: `app_colors.dart`, `app_palette.dart`, `app_theme.dart`,
  `theme_mode_provider.dart` — **58 production screen** marad legacy baseline,
  és 44 alkalmazásforrás importálja közvetlenül a theme API-t.
- `test/core/architecture_dependency_test.dart` létezik (854 sor), és
  „allowlisted dependency deviations" alapon tilt cross-feature importot.

## 3. Scope

**Benne van:** a Ch13 §10 mappastruktúra váza · `SsBreakpoints`, `SsSpacing`,
`SsRadius`, `SsMotion` és alap semantics konstansok · **kompatibilitási
adapter** a meglévő theme felé · development-only Component Catalog **flag
mögött** · a kanonikus token-forrás dokumentálása szakaszonként ·
architektúra-guard, hogy a design system **ne importáljon feature-logikát**.

**NINCS benne (tilos):**

- **A `lib/core/theme/` törlése vagy átírása.** A migráció fokozatos.
- Szemantikai színek és témák (Kör 3), tipográfia (Kör 4).
- Bármely `lib/features/**` módosítása.
- A Component Catalog **production** elérhetővé tétele.
- `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `design_system/foundations/*.dart` (5) | **ÚJ** — breakpoint, spacing, radius, motion, semantics |
| `design_system/themes/ss_theme_extensions.dart` | **ÚJ** — a `ThemeExtension` váz |
| `design_system/documentation/component_catalog_screen.dart` | **ÚJ** — flag mögött |
| `design_system/public.dart` | **ÚJ** — az EGYETLEN belépő |
| `test/core/design_system/*_test.dart` (2) | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | a design-system határa |
| `docs/ui/migration-status.md` | a kanonikus forrás szakaszonként |
| `docs/rounds/e13-r02-…md` | a §10 handoff |

**Tilos zóna:** `lib/core/theme/**` · `lib/features/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0273)

### 5.1 EGY belépő: `public.dart`

A design system kizárólag a `public.dart`-on át importálható. Belső fájl
importja kívülről tilos — az architektúra-guard ezt kikényszeríti.

### 5.2 A meglévő theme TOVÁBB MŰKÖDIK — a színforrás NEM duplikálódik

Az adapter a meglévő `AppColors`/`AppPalette`/`AppTheme` értékeit **olvassa**,
nem másolja. Két igazságforrás mellett a két rendszer csendben elcsúszna.

**NEM elfogadható gyengítés:** a hex-értékek átmásolása az új tokenekbe „amíg
a migráció tart". Onnantól két helyen kellene javítani minden színt.

### 5.3 A design system NEM importál feature-t

Sem `lib/features/**`, sem üzleti logika. A guard ezt kikényszeríti — enélkül
a rendszer nem lenne újrahasznosítható, és körkörös függés keletkezne.

### 5.4 A Component Catalog FLAG mögött, nem production útvonalon

Fejlesztői eszköz. A default-OFF compile-time flag ÉS a debug-build kapu
együtt szükséges; bármelyik hamis értékénél a route factory nem ad route-ot.
Production buildben és a jelenlegi app routerből nem elérhető.

### 5.5 A kanonikus forrás SZAKASZONKÉNT dokumentált

A `migration-status.md` megmondja, melyik token melyik szakaszban a mérvadó
(régi theme vs. új design system). Enélkül a következő 34 kör találgatna.

### 5.6 Nulla UI-regresszió

A meglévő 58 production screen viselkedése nem változik. Ez acceptance-cella
(A6).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A design system EGYETLEN `public.dart`-ból importálható | `foundations_test.dart` + guard |
| A2 | A design system NEM importál `lib/features/**`-t | `architecture_dependency_test.dart` |
| A3 | A meglévő theme API változatlanul működik | a teljes suite zöld |
| A4 | A színforrás NEM duplikálódik (az adapter olvas, nem másol) | `foundations_test.dart` — a meglévő érték megváltoztatása átüt |
| A5 | A Component Catalog default-OFF flag ÉS debug-build kapu mögött van; productionben és az app routerből nem elérhető | `component_catalog_test.dart` — false/true mátrix + dark/light smoke |
| A6 | **Nulla UI-regresszió** — `lib/features/**` és `lib/core/theme/**` érintetlen | gépi scope-audit |
| A7 | A `migration-status.md` megnevezi a kanonikus forrást szakaszonként | review |
| A8 | A foundation konstansok a Ch13 §8/§9 értékeit adják | `foundations_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hex-értékek átmásolva az új tokenekbe | **A4** (a forrás módosítása nem üt át) |
| A design system importál feature-t | **A2** |
| Belső fájl importálható kívülről | A1 |
| A katalógus létrejön kikapcsolt flaggel, vagy release buildben | **A5** false/true kapumátrixa |
| A régi theme átírva | **A6** |
| A migrációs dokumentum nem mondja meg a kanonikus forrást | A7 |
| Bármely breakpoint, spacing, radius, motion vagy semantics érték eltér a kipinnelt táblától | **A8** (`foundations_test.dart`) |

**A token-forrás három kötelező cellája** (a küszöb: a migráció szakasza):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a régi theme a kanonikus | az új token **onnan olvas** |
| rajta (a küszöbön) | átmenet, mindkettő él | a `migration-status.md` **kimondja**, melyik a mérvadó |
| a küszöb fölött | az új token a kanonikus (későbbi kör) | a régi adapterré válik — **nem ebben a körben** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** másold át az egyik
színértéket az új tokenbe a hivatkozás helyett, majd változtasd meg a forrást →
az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/foundations_test.dart test/core/design_system/component_catalog_test.dart test/core/architecture_dependency_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `foundations/` öt konstans-fájlja a Ch13 §8/§9 értékeivel.
2. `themes/ss_theme_extensions.dart` — a `ThemeExtension` váz, adapterrel.
3. `public.dart` — az egyetlen belépő.
4. Architektúra-guard: nincs feature-import, nincs belső import kívülről.
5. `component_catalog_screen.dart` flag mögött.
6. `migration-status.md` — a kanonikus forrás szakaszonként.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A duplikált színforrás.** A másolás gyorsabb, és a két rendszer az első
  színjavításnál csendben elcsúszik (A4). Ez a kör legfontosabb invariánsa.
- **A névütközés.** A Ch13 maga jelzi: az átmeneti dupla export ütközhet —
  explicit prefix vagy deprecation kell.
- **A régi theme „rendbetétele".** Csábító, és 51 képernyőt kockáztat (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
