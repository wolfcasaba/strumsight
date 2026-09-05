# E17-R01 — Onboarding First-Win állomás bekötése

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`)
- **Típus:** Chapter 17 (Teljes bekötés), Kör 1
- **Kör-azonosító:** `E17-R01`
- **Branch:** `<motor>/e17-r01-onboarding-first-win-stage-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0520` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "onboarding first-win állomás bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/onboarding/screens/onboarding_screen.dart",
  "lib/features/onboarding/public.dart",
  "test/features/onboarding/first_win_stage_wiring_test.dart",
  "docs/rounds/e17-r01-onboarding-first-win-stage-wiring.md",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/shell_entry_location_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/onboarding/",
  "test/e2e/full_app_walkthrough_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/shell_entry_location_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/onboarding/first_win_test.dart",
  "test/features/onboarding/onboarding_resume_test.dart",
  "test/features/onboarding/onboarding_test.dart",
  "test/features/onboarding/permission_primer_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/app/navigation/",
]
```

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A `FirstWinStageScreen` a szállított kompozícióból elérhető: az onboarding folyamat a first-win kísérlet után erre az állomásra lép, valós konfidencia-forrásból.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A `FirstWinStageScreen` a fában él (`lib/features/onboarding/screens/first_win_stage_screen.dart`), de a `check_screen_reachability` mérése szerint SEM route, SEM imperatív hívás nem éri el.
- A képernyő adatforrása MÁR LÉTEZIK: `onboardingFirstWinConfidenceProvider` (`lib/features/onboarding/first_win_providers.dart:39`, `StreamProvider.autoDispose<double>`), és a siker-küszöb az `isFirstWinSuccess(confidence)` predikátumban él.
- Az `OnboardingScreen` routolt és működik; a `PermissionPrimerScreen`-t MÁR imperatívan hívja (`onboarding_screen.dart:181`) — ez a bekötés MÉRT mintája.

## 3. Scope

**Benne van:** A First-Win állomás belépési pontja az onboarding folyamatból · a képernyő `onContinue` / `onSkip` visszahívásainak valós navigációhoz kötése · a folyamat kimenete az `entryLocationFor(...)` EGYETLEN forráson át (ADR 0508 D1).

**NINCS benne (tilos):**

- Az `OnboardingScreen` lépés-gépének átírása.
- Új képernyő létrehozása.
- A first-win konfidencia-forrás (`first_win_providers.dart`) szemantikájának módosítása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0520)

### 5.1 A belépés az onboarding folyamatból megy, nem új top-level route-ból

A First-Win állomás a folyamat egy LÉPÉSE. Külön `/first-win` route két belépési pontot adna ugyanahhoz az állapothoz, és a `entryLocationFor(...)` egy-forrás szabályát (ADR 0508 D1) sértené.

### 5.2 A `onContinue` / `onSkip` SOSEM navigál közvetlenül literál útvonalra

Mindkettő az `entryLocationFor(adaptiveShellEnabled)` eredményét használja — ugyanaz a forrás, amit az `onboarding_screen.dart` Skip/finish ága már ma is (E16-R06 mérése).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `check_screen_reachability` a `FirstWinStageScreen`-t `reachable: true`-ként méri | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | Az onboarding folyamat a first-win kísérlet után a First-Win állomásra lép | widget-teszt valós `ProviderContainer`-rel |
| A3 | A `onContinue` és a `onSkip` egyaránt az `entryLocationFor(...)` által adott célra navigál — literál útvonal EGYIK ágban sincs | widget-teszt + `grep` a diffre |
| A4 | A képernyő a VALÓS `onboardingFirstWinConfidenceProvider`-t olvassa, nem tesztkonstansot | a szállított kompozíció tesztje |
| A5 | A siker-küszöb **alatt** lévő konfidencia a „még nem sikerült" ágra visz | widget-teszt a küszöb alatti értékkel |
| A6 | A küszöbön **rajta** álló konfidencia a siker-ágra visz (a predikátum inkluzív határa mérve) | widget-teszt pontosan a küszöb-értékkel |
| A7 | A küszöb **fölött** lévő konfidencia ugyanarra a siker-ágra visz — a határ fölött nincs harmadik viselkedés | widget-teszt a küszöb fölötti értékkel |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Cseréld a `onSkip` ágat literál `'/live'` útvonalra, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza. Második próba a küszöb-hármasra: fordítsd a határt exkluzívra, futtasd → az A6 cellának PIROSNAK kell lennie (az A5 és A7 zöld marad, tehát a hármas tényleg a HATÁRT méri) → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/onboarding/ test/e2e/full_app_walkthrough_test.dart test/app/routing/app_router_test.dart test/app/routing/onboarding_first_win_test.dart test/app/routing/shell_entry_location_test.dart test/core/screen_size_guard_test.dart test/features/onboarding/first_win_test.dart test/features/onboarding/onboarding_resume_test.dart test/features/onboarding/onboarding_test.dart test/features/onboarding/permission_primer_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_baseline_screenshot_test.dart test/app/navigation/
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §2 mért tényeinek ÚJRAMÉRÉSE a kör indulásakor (a brief alapja elmozdulhatott).
2. A §5 döntéseinek rögzítése az ADR-ben.
3. Az implementáció a §4 engedélyezett fájljain belül.
4. A §6 acceptance-cellák tesztjei.
5. A §6.1 valódi-sértés próba lefuttatása és a §10-be dokumentálása.
6. A §7 gate futtatása csonkítatlan kimenettel.

## 9. Kockázatok

- **A kettős belépési pont.** Egy külön route ugyanahhoz az állapothoz az ADR 0508 D1 egy-forrás szabályát sérti (5.1).
- **A literál útvonal.** Az E16-R06 pont ezt a hibaosztályt mérte és távolította el a gerincről (5.2).
- **A folyamat megszakadása.** Ha az állomás a konfidencia-stream első értéke előtt navigál, a felhasználó üres állapotot lát (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
