# E13-R05 — Spacing, radius, elevation és surface primitívek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 903e7a7d`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 5
- **Kör-azonosító:** `E13-R05`
- **Branch:** `<motor>/e13-r05-spacing-and-surfaces`
- **Előfeltétel:** `E13-R04` merge-elve (tipográfia)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a Ch13 §9.5 geometriája adott.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02
> `foundations/ss_spacing.dart` és `ss_radius.dart` TÉNYLEGES konstansait — ez a
> kör ezekre épít felületi primitíveket, nem definiálja újra őket. Eltérésnél
> §0.0 revízió.

## 0.0.1 H3 scope-revízió — ADR 0112 önjavító kör, 2026-08-21

A megállt PR #392 exact `03788441` Full Gate-je háromszor ugyanazt a meglévő
contract-ütközést mérte. A javított `SsCard` a `SsSurface` egyetlen
`Material`-rétegét használja, ezért szándékosan nincs benne legacy `Card`.
Ezzel szemben a már létező
`test/core/design_system/component_catalog_test.dart:50,68` három katalógus-
cellája `find.byType(Card)` alapján pontosan egy `Card`-ot várt; a tényleges
hiba mindháromszor `Found 0 widgets with type "Card"` volt. A product javítás
így szükségképpen pirosra vitte a briefen és célzott gate-en kívüli tesztet.

Ez B osztályú, tranzakciós brief-hiány, nem production- vagy gate-hiba. Az
allowlist és a célzott gate pontosan a
`test/core/design_system/component_catalog_test.dart` fájllal bővül. A
folytatott product kör ugyanabban a commitban köteles úgy frissíteni a három
katalógus-cellát, hogy a compile-time/debug route-kapu és a dark/light smoke
contract megmaradjon, miközben az `SsCard` jelenlétét és annak pontosan egy
`Material` leszármazottját méri. Más `test/core/design_system/**` út nem
nyílik meg; a self-heal product Dart-kódot nem visz előre.

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
  "test/core/design_system/component_catalog_test.dart",
  "docs/rounds/e13-r05-spacing-and-surfaces.md",
]
gate_tests = [
  "test/core/design_system/surfaces/ss_surface_test.dart",
  "test/core/design_system/surfaces/spacing_grid_test.dart",
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
| `test/core/design_system/component_catalog_test.dart` | a route/smoke contract tranzakciós átállítása `Card`-ról `SsCard` + single-`Material` mérésre |
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
| A8 | A katalógus route/smoke contractja `SsCard`-ot és pontosan egy `Material`-réteget mér, legacy `Card`-követelmény nélkül | `component_catalog_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `EdgeInsets.all(13)` a rács helyett | **A1** |
| A hívó adja meg a háttérszínt a szint mellé | **A2** |
| Erős `BoxShadow` sötét témában | **A3** |
| A primitív figyelmen kívül hagyja az inseteket | A4 |
| A hero kártya maga olvassa a felismerés-állapotot | A5 |
| Nyers `BorderRadius.circular(9)` | A7 |
| Az `SsCard` visszahoz egy második, legacy `Card`/`Material` réteget | **A8** |

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
tools/round-gate.sh test/core/design_system/surfaces/ss_surface_test.dart test/core/design_system/surfaces/spacing_grid_test.dart test/core/design_system/component_catalog_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_elevation.dart` — a Ch13 §9.5 felület-hierarchiája.
2. `ss_surface.dart` — szint + háttérszín EGYÜTT, insetekkel.
3. `ss_card.dart`, `ss_hero_card.dart`, `ss_section.dart`.
4. A meglévő `component_catalog_test.dart` három `Card`-elvárásának
   tranzakciós frissítése: route/smoke contract + `SsCard` + single `Material`.
5. A rács-kikényszerítő teszt.
6. Component Catalog: a primitívek mindhárom témában.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az árnyék-reflex.** Világos témán tanult mélység-eszköz, sötéten haló lesz
  belőle (A3).
- **A szint és a szín szétcsúszása.** Ha a hívó adja a hátteret, a hierarchia
  képernyőnként más lesz (A2).
- **Az „egy pixel finomítás".** Rácson kívüli értékek észrevétlenül gyűlnek (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
