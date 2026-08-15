# E13-R10 — Aszinkron állapotkomponensek

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 10
- **Kör-azonosító:** `E13-R10`
- **Branch:** `<motor>/e13-r10-async-state-components`
- **Előfeltétel:** `E13-R09` merge-elve (Stage scaffold)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0277`](../adr/0277-failure-presentation-model.md)
  — **a Claude írja meg a kör indításakor; a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd el a TÉNYLEGES hibatípust,
> amit a Chapter 2 bevezetett (`AppFailure` és a képernyő-állapot típusa) — a
> §5.1 mapping erre épül, és a mezőnevek időközben változhattak. Eltérésnél
> §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/components/feedback/ss_async_state.dart",
  "lib/core/design_system/components/feedback/ss_skeleton.dart",
  "lib/core/design_system/components/feedback/ss_empty_state.dart",
  "lib/core/design_system/components/feedback/ss_failure_state.dart",
  "lib/core/design_system/components/feedback/ss_permission_state.dart",
  "lib/core/design_system/components/feedback/failure_presentation.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/feedback/failure_presentation_test.dart",
  "test/core/design_system/feedback/async_state_test.dart",
  "docs/rounds/e13-r10-async-state-components.md",
]
gate_tests = [
  "test/core/design_system/feedback/failure_presentation_test.dart",
  "test/core/design_system/feedback/async_state_test.dart",
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

A loading, skeleton, empty, offline, sync pending, degraded, permission,
failure és blocked állapotok **egységes** megjelenítése (SDD Ch13 Kör 10).

## 2. Jelenlegi állapot — mért tények

- Az R03 óta a `danger` szemantikája kötött: **offline nem danger**, és
  **alacsony confidence nem danger**.
- Az R05 felületi primitívei adják a geometriát, az R07 az ikonokat.
- Az i18n szabály (CLAUDE.md): minden felhasználói szöveg ARB-n át megy.

## 3. Scope

**Benne van:** a Ch13 kötelező feedback-komponensei stabil API-val ·
**failure-kód → lokalizált prezentációs modell** mapping · cached-content
overlay offline és sync pending állapothoz · mikrofon / kamera / értesítés /
tárhely engedély-prezentációs modellek · retry / beállítások megnyitása /
offline folytatás / támogatás akció-variánsok · annak dokumentálása, mikor
teljes képernyő, banner, inline üzenet vagy snackbar a helyes.

**NINCS benne (tilos):** `lib/features/**` átállítása az új komponensekre
(a migrációs körök dolga) · a hibatípus (`AppFailure`) módosítása · nyers
kivétel megjelenítése · `lib/core/theme/**` · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `feedback/ss_async_state.dart` | **ÚJ** — az állapot-kapcsoló |
| `feedback/ss_skeleton.dart` | **ÚJ** — geometriatartó skeleton |
| `feedback/ss_empty_state.dart` | **ÚJ** |
| `feedback/ss_failure_state.dart` | **ÚJ** |
| `feedback/ss_permission_state.dart` | **ÚJ** |
| `feedback/failure_presentation.dart` | **ÚJ** — a kód → modell mapping |
| `documentation/component_catalog_screen.dart` | állapot-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | az új felhasználói szövegek |
| `test/…/feedback/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r10-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0277)

### 5.1 A design system NYERS kivételt nem fogad és nem mutat

A bemenet mindig **failure-kód**, amit a mapping lokalizált modellé alakít.
Stack trace, `Exception: ...` szöveg vagy HTTP státusz sosem kerül a felületre.

**NEM elfogadható gyengítés:** `Text(error.toString())` fallbackként „ismeretlen
hibára". Az technikai zajt önt a felhasználóra, és néha adatot szivárogtat.

### 5.2 Az offline NEM hiba-stílus, és a cached tartalom LÁTHATÓ marad

Offline állapotban a korábban betöltött tartalom megmarad, fölötte jelzéssel.
A képernyő nem ürül ki.

**NEM elfogadható gyengítés:** offline → teljes képernyős hibaállapot. Az
használhatatlanná tesz egy amúgy működő, on-device terméket.

### 5.3 A retry CSAK újrapróbálható hibánál jelenik meg

Ha a hiba nem oldható meg újrapróbálással (pl. véglegesen megtagadott
engedély), a retry gomb hamis reményt kelt — helyette a valódi kiút látszik.

### 5.4 Az engedély-állapot MEGMONDJA, mire kell

„Miért kérjük" + „mi lesz, ha nem adod meg". Véglegesen megtagadott engedélynél
a beállítások megnyitása az akció, nem az újrakérés.

### 5.5 Az üres állapot ÉRTELMES akciót ad

Az „nincs adat" önmagában zsákutca. Minden üres állapotnak van következő lépése.

### 5.6 A skeleton NEM olvasható tartalomként

Képernyőolvasónak „betöltés" hangzik el, nem álszöveg; és a skeleton megtartja
a végleges layout geometriáját, hogy ne ugorjon a tartalom.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nyers kivétel/`toString()` SEHOL nem jelenik meg | `failure_presentation_test.dart` |
| A2 | Offline nem hiba-stílus, és a cached tartalom látható marad | `async_state_test.dart` |
| A3 | A retry csak újrapróbálható hibánál látszik | `failure_presentation_test.dart` |
| A4 | Véglegesen megtagadott engedélynél a beállítás-akció jelenik meg | ugyanott |
| A5 | Az üres állapot értelmes akciót kínál | `async_state_test.dart` |
| A6 | A skeleton nem olvasható tartalomként, és tartja a geometriát | ugyanott |
| A7 | Minden új felhasználói szöveg ARB-n át megy (en + hu) | `grep` a diffben |
| A8 | Minden állapot mindhárom témában renderel | `async_state_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Text(error.toString())` fallback | **A1** |
| Offline → teljes képernyős hibaállapot | **A2** |
| Retry minden hibánál | **A3** |
| Véglegesen megtagadott engedélynél újrakérés | A4 |
| Üres állapot akció nélkül | A5 |
| Skeleton álszöveggel | **A6** |
| Beégetett angol string | A7 |

**A retry-láthatóság három kötelező cellája** (a küszöb: újrapróbálható-e a hiba):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | nem újrapróbálható (végleges megtagadás) | **nincs** retry — a valódi kiút látszik |
| rajta (a küszöbön) | átmeneti, de ismeretlen okú hiba | **van** retry (a bizonytalan eset újrapróbálható) |
| a küszöb fölött | egyértelműen átmeneti (hálózat) | van retry, offline-folytatás akcióval |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vezess be egy
`toString()` fallbackot az ismeretlen hibakódra → az **A1** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/feedback/failure_presentation_test.dart test/core/design_system/feedback/async_state_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `failure_presentation.dart` — kód → lokalizált modell, ismeretlen kódra is
   **emberi** szöveggel.
2. A retry-láthatóság három cellája.
3. `ss_async_state.dart` + a cached-content overlay.
4. `ss_skeleton.dart` — geometriatartó, semanticsból kizárt.
5. `ss_empty_state.dart`, `ss_failure_state.dart`, `ss_permission_state.dart`.
6. ARB (en + hu) + Component Catalog állapot-mátrix.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az ismeretlen hibakód.** A `toString()` fallback kézenfekvő, és pont ott
  önt technikai zajt a felhasználóra, ahol a legkevésbé érti (A1).
- **Az offline mint hiba.** A leggyakoribb reflex, és egy on-device terméket
  tesz látszólag használhatatlanná (A2).
- **A mindenhol megjelenő retry.** Olcsó egységesség, ami hamis reményt kelt
  véglegesen megtagadott engedélynél (A3/A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
