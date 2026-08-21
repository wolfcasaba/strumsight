# E13-R05 — Spacing, radius, elevation és surface primitívek

- **Státusz:** IN PROGRESS (pre-flight: 2026-08-21, `main @ 1281dc40`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 5
- **Kör-azonosító:** `E13-R05`
- **Branch:** `terra/e13-r05-spacing-and-surfaces`
- **Előfeltétel:** `E13-R04` merge-elve (tipográfia)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0385` — a foglaló adta az E13-R05-nek.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02
> `foundations/ss_spacing.dart` és `ss_radius.dart` TÉNYLEGES konstansait — ez a
> kör ezekre épít felületi primitíveket, nem definiálja újra őket. Eltérésnél
> §0.0 revízió.

## 0.0 Pre-flight revízió — 2026-08-21

- A `tools/round-slots.py reserve-adr --round E13-R05` atomi foglalása a
  `0385` számot adta; a felület-hierarchia, az inset-kezelés és a mérce
  döntéseit az [`ADR 0385`](../adr/0385-surface-hierarchy-and-geometry-contract.md)
  rögzíti. Az ADR orchestrátor pre-flight artefaktum, nem része az implementer
  fázisbaseline utáni scope-jának (`lessons/L380`).
- A tényleges foundation contract változatlanul
  `SsSpacing.values == [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64]` és
  `SsRadius.values == [6, 10, 16, 20, 28, 999]`; ezért a kör ezeket nem
  definiálja újra. A `python3 -c`-vel számolt 4 dp határcellák: `2`, `4`,
  illetve `8 / 12 / 16` dp.
- A tényleges szemantikai színút már létezik:
  `SsColorScheme.surface`, `surfaceRaised`, `surfaceSunken`, `border` és
  `borderStrong`. A legacy paletta jelenleg a `surfaceRaised` értékét a
  `surface` értékével azonosan adja, ezért a kör a szintek vizuális
  megkülönböztetését a saját, központosított elevation/surface contractjában
  oldja meg, új hex szín és `lib/core/theme/**` módosítás nélkül.
- A Chapter 13 Kör 5 kötelező háromtémás surface-mátrixa, token-unit cellája,
  nagy text-scale és nested-surface próbája a már engedélyezett két tesztfájlban
  kap explicit acceptance-cellát. A „golden” itt determinisztikus vizuális
  contract-mátrix: témánként a feloldott háttér, border és shadow értékét méri,
  új PNG corpus nélkül. Ez a brief dokumentált pontosítása a Chapter 13
  bináris golden megfogalmazásához; scope-bővítés nincs.
- A nyers `EdgeInsets`/radius lint az engedélyezett `spacing_grid_test.dart`
  source-contract cellája: a kör nem módosítja a védett architecture-gate-et.
  A compact/medium/expanded screen padding a meglévő spacing tokenekhez kötött
  publikus contractként kerül dokumentálásra.
- A kör nem kezel státuszreducert vagy lifecycle-erőforrást; célállapot-input
  és resource-acquire hívási lánc ezért nem alkalmazandó.
- A kötelező, sorrendi **visszakeresett előzmény** vizsgálata a szűkített
  `lessons,halts,adr`, majd
  `lessons,halts`, végül a teljes korpuszon megtörtént. Közvetlen előzmény az
  [`ADR 0381`](../adr/0381-semantic-theme-and-accessibility-contract.md) és az
  E13-R02/R03/R04 merge-tény; a legfontosabb scope-precedens
  [`lessons/L387`](../LESSONS.md), amely szerint egy integráció meglévő
  contract-fogyasztóját is fel kell mérni. Itt nincs ilyen új, listán kívüli
  owner: a surface-primitívek újak, a katalógus és mindkét célzott teszt exact
  scope-ban van. A teljes korpuszos találatok ezen felül nem adtak relevánsabb
  előzményt.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/design_system/foundations/ss_elevation.dart",
  "lib/core/design_system/components/surfaces/ss_surface.dart",
  "lib/core/design_system/components/surfaces/ss_card.dart",
  "lib/core/design_system/components/surfaces/ss_hero_card.dart",
  "lib/core/design_system/components/surfaces/ss_section.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/surfaces/ss_surface_test.dart",
  "test/core/design_system/surfaces/spacing_grid_test.dart",
  "docs/rounds/e13-r05-spacing-and-surfaces.md",
]
gate_tests = [
  "test/core/design_system/surfaces/ss_surface_test.dart",
  "test/core/design_system/surfaces/spacing_grid_test.dart",
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

Következetes térköz-, sarok- és mélységrendszer, plusz a felületi primitívek
(SDD Ch13 Kör 5) — hogy a képernyők ne egyenként találjanak ki geometriát.

## 2. Jelenlegi állapot — mért tények

- Az R02 letette az `SsSpacing` és `SsRadius` konstansokat; elevation még nincs.
- Az R01 `token-debt.md`-je mérte a hardkódolt spacing-találatokat.
- A Ch13 §9.5 megadja a 4dp rácsot és a felület-hierarchiát
  (base → raised → overlay → modal).

## 3. Scope

**Benne van:** `SsElevation` (a Ch13 felület-hierarchiája) · `SsSurface`
alap-primitív · `SsCard`, `SsHeroCard`, `SsSection` · a felület-szint és a
szemantikai háttérszín összekötése · biztonságos terület és tartalom-inset
kezelése · a 4dp rács kikényszerítése az új komponensekben.

**NINCS benne (tilos):** motion (Kör 6) · interaktív komponensek: gomb, input
(Kör 7–8) · `lib/features/**` · `lib/core/theme/**` · árnyék-alapú mélység
sötét témában dokumentálatlanul · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_elevation.dart` | **ÚJ** — felület-hierarchia |
| `components/surfaces/ss_surface.dart` | **ÚJ** — az alap-primitív |
| `components/surfaces/ss_card.dart` | **ÚJ** |
| `components/surfaces/ss_hero_card.dart` | **ÚJ** — Stage Mode kártya |
| `components/surfaces/ss_section.dart` | **ÚJ** — szekció-fejléc + tartalom |
| `documentation/component_catalog_screen.dart` | a primitívek bemutatása |
| `public.dart` | az export bővítése |
| `test/…/surfaces/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r05-…md` | a §10 handoff |

**Tilos zóna:** `lib/core/theme/**` · `lib/features/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A 4dp rács kötelező az új komponensekben

Minden térköz a `SsSpacing` skálából jön. Rácson kívüli érték csak akkor, ha a
komponens dokumentálja az okot (pl. optikai igazítás ikonnál).

**NEM elfogadható gyengítés:** `EdgeInsets.all(13)` „mert így nézett ki jól".
Ettől a rendszer visszaesik ad hoc geometriára.

### 5.2 Sötét témában a mélységet FELÜLETI SZÍN adja, nem árnyék

A Ch13 §9.5 kimondja: sötét felületen az árnyék alig látszik. A szint
elsődlegesen világosabb felülettel jelenik meg; árnyék legfeljebb kiegészítő.

**NEM elfogadható gyengítés:** erős `BoxShadow` sötét témában „hogy elváljon".
Az piszkos szürke halót ad, és nem közvetít hierarchiát.

### 5.3 A felület-szint és a háttérszín EGYÜTT változik

Nem lehet `raised` szintű kártya `base` háttérszínnel — a primitív ezt köti
össze, nem a hívó.

### 5.4 A tartalom nem csúszik a biztonságos terület alá

A primitívek kezelik a rendszer-inseteket; a hívónak nem kell `SafeArea`-t
duplikálnia.

### 5.5 A `SsHeroCard` NEM tartalmaz üzleti logikát

Prezentációs komponens. Az akkord/confidence adat kívülről jön.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az új komponensek minden térköze a `SsSpacing` skálából jön | `spacing_grid_test.dart` |
| A2 | A felület-szint és a háttérszín együtt változik | `ss_surface_test.dart` |
| A3 | Sötét témában a mélység felületi színnel jelenik meg, nem erős árnyékkal | ugyanott |
| A4 | A tartalom nem csúszik a biztonságos terület alá | `ss_surface_test.dart` |
| A5 | A `SsHeroCard` nem importál feature-logikát | architektúra-guard |
| A6 | A primitívek mindhárom témában renderelnek kivétel nélkül | `ss_surface_test.dart` |
| A7 | Nincs hardkódolt geometriai literál az új kódban | `grep` a diffben |
| A8 | A High Contrast surface-szinteket erős border is megkülönbözteti | `ss_surface_test.dart` |
| A9 | A dark/light/high-contrast × base/raised/overlay/modal vizuális contract-mátrix háttér-, border- és shadow-értékei determinisztikusak | `ss_surface_test.dart` |
| A10 | Nested surface 2.0 text scale-en renderel kivétel és overflow nélkül | `ss_surface_test.dart` |
| A11 | Compact/medium/expanded padding rendre a 16/24/32 dp `SsSpacing` tokenre oldódik | `spacing_grid_test.dart` |
| A12 | A source-contract elutasítja a nyers `EdgeInsets`- és `BorderRadius.circular` geometriai literált az új primitivekben | `spacing_grid_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `EdgeInsets.all(13)` a rács helyett | **A1** |
| A hívó adja meg a háttérszínt a szint mellé | **A2** |
| Erős `BoxShadow` sötét témában | **A3** |
| A primitív figyelmen kívül hagyja az inseteket | A4 |
| A hero kártya maga olvassa a felismerés-állapotot | A5 |
| Nyers `BorderRadius.circular(9)` | A7 |
| High Contrast ugyanazt a gyenge bordert használja, mint a normál téma | **A8** |
| Bármelyik téma/szint feloldása kézzel megadott háttérre vagy shadow-ra változik | **A9** |
| Nested card fix magasságot kap és 2.0 text scale-en overflowol | **A10** |
| Expanded padding 28 dp-re csúszik | **A11** |
| A production primitive `EdgeInsets.all(16)`-ot használ token helyett | **A12** |

**A rács három kötelező cellája** (a küszöb: a 4dp osztó):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 2dp térköz | **elutasítva** — nem rács-érték |
| rajta (a küszöbön) | **4dp** | **elfogadva** — a rács legkisebb egysége |
| a küszöb fölött | 8 / 12 / 16dp | elfogadva |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írj be egy rácson
kívüli térközt az egyik primitívbe → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/surfaces/ss_surface_test.dart test/core/design_system/surfaces/spacing_grid_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_elevation.dart` — a Ch13 §9.5 felület-hierarchiája.
2. `ss_surface.dart` — szint + háttérszín EGYÜTT, insetekkel.
3. `ss_card.dart`, `ss_hero_card.dart`, `ss_section.dart`.
4. A rács-kikényszerítő teszt.
5. Component Catalog: a primitívek mindhárom témában.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az árnyék-reflex.** Világos témán tanult mélység-eszköz, sötéten haló lesz
  belőle (A3).
- **A szint és a szín szétcsúszása.** Ha a hívó adja a hátteret, a hierarchia
  képernyőnként más lesz (A2).
- **Az „egy pixel finomítás".** Rácson kívüli értékek észrevétlenül gyűlnek (A1).

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `lib/core/design_system/foundations/ss_elevation.dart`: a zárt
  `base/raised/overlay/modal` hierarchia egyetlen resolverben állítja elő a
  szemantikus hátteret, bordert, border-szélességet és rövid shadow-elevationt.
  Dark Studio és High Contrast alatt nincs dekoratív shadow; a High Contrast
  emelt szintjei `borderStrong`-ot kapnak.
- `lib/core/design_system/components/surfaces/ss_surface.dart`: a szinthez
  kötött `Material` surface, opcionális névvel ellátott `safeArea` móddal és
  compact/medium/expanded `SsSpacing.space4/space6/space8` padding resolverrel.
- `lib/core/design_system/components/surfaces/ss_card.dart`: raised card
  `SsRadius.md`-vel, tokenes alap-paddinggel.
- `lib/core/design_system/components/surfaces/ss_hero_card.dart`: caller-fed
  overlay felület `SsRadius.lg`-vel; feature/provider/state import nélkül.
- `lib/core/design_system/components/surfaces/ss_section.dart`: cím + tartalom
  kompozíció, új card-réteg létrehozása nélkül.
- `lib/core/design_system/documentation/component_catalog_screen.dart`: a
  development-only katalógus mind a négy surface szintet megmutatja a meglévő
  dark/light/high-contrast választóval; új felhasználói szöveget nem vezet be.
- `lib/core/design_system/public.dart`: az új foundation és surface public
  exportjai.
- `test/core/design_system/surfaces/ss_surface_test.dart`: a három téma × négy
  szint determinisztikus háttér/border/shadow mátrixa, safe-area nested eset,
  2.0 text scale és hero-függetlenség.
- `test/core/design_system/surfaces/spacing_grid_test.dart`: a 2/4/8–16 dp
  küszöbcellák, a 16/24/32 dp responsive padding és a raw geometry source-őr.

### TDD és valódi-sértés bizonyíték

- RED: a két új surface-teszt az implementáció előtt a hiányzó
  `SsElevation`, `SsSurface`, `SsCard`, `SsHeroCard` és `SsSection` symbolokkal
  fordítási hibára futott.
- GREEN (restore után): `flutter test
  test/core/design_system/surfaces/ss_surface_test.dart
  test/core/design_system/surfaces/spacing_grid_test.dart` → **18/18 passed**.
- Kötelező valódi-sértés: az `ss_card.dart` ideiglenes
  `EdgeInsets.all(13)` módosításával a
  `flutter test test/core/design_system/surfaces/spacing_grid_test.dart` A1
  source-contract cellája elvárt módon piros volt: a raw-inset regexp matchje
  `true` lett a konkrét `ss_card.dart` fájlra. A tokenes `EdgeInsets.all(padding)`
  restore után a teljes kétfájlos célzott teszt újra **18/18 passed**.

### Futtatott ellenőrzések

- `dart format` a kilenc módosított Dart fájlon → sikeres.
- `flutter test test/core/design_system/component_catalog_test.dart` →
  **8/8 passed**.
- `git diff --check` → sikeres.
- `tools/round-gate.sh test/core/design_system/surfaces/ss_surface_test.dart
  test/core/design_system/surfaces/spacing_grid_test.dart` → **pass, exit 0**
  (format, analyze, mindkét célzott teszt, architecture, secrets és l10n zöld).

### Nem futtatott ellenőrzések

- Teljes `flutter test`, property gate és CI APK: implementer scope-on kívüli,
  a kör-orchestrátor CI/merge kapuja.

## 11. Review — a Claude tölti ki
