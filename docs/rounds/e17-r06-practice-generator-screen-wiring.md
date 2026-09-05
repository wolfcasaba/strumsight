# E17-R06 — A Practice Generator 4 maradék képernyőjének bekötése

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Tranzitívan az `E17-R05` két seamjén áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 6
- **Kör-azonosító:** `E17-R06`
- **Branch:** `<motor>/e17-r06-practice-generator-screen-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0525` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "a practice generator 4 maradék képernyőjének bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Tranzitívan az `E17-R05` két seamjén áll. **Mi oldja fel:** az `E17-R05` lezárása.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/app_router.dart",
  "lib/features/practice_generator/presentation/screens/today_plan_screen.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/screen_wiring_test.dart",
  "docs/rounds/e17-r06-practice-generator-screen-wiring.md",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
  "test/app/routing/app_router_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
]
native_gate = false
gate_tests = [
  "test/features/practice_generator/",
  "test/app/routing/",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
  "test/app/routing/app_router_test.dart",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
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

A `PlanPreviewScreen`, `WeeklyPlanScreen`, `PlanPrivacyScreen` és `PlanChangeReviewScreen` a szállított kompozícióból elérhető, a meglévő `practiceGeneratorEnabled` kapu alatt.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- Mind a négy `reachable: false`; a Generator két társ-képernyője (`PlanSetup`, `TodayPlan`) MÁR routolt ugyanazon kapu alatt — ez a bekötés MÉRT mintája.
- A router `E15-R07` megjegyzése kimondja, hogy a négy TRANZITÍVAN a két seamen állt — azokat az `E17-R05` oldja fel.

## 3. Scope

**Benne van:** A négy képernyő route-jai a `practiceGeneratorEnabled` kapu alatt · a terv-előnézet és a heti terv belépési pontja a `TodayPlan`-ból · az adatvédelmi és a terv-változás-áttekintő képernyő belépési pontja.

**NINCS benne (tilos):**

- A két seam módosítása (az `E17-R05` zárta le).
- A `practiceGeneratorEnabled` alapértékének megváltoztatása.
- Új terv-generálási viselkedés.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0525)

### 5.1 Mind a négy a MEGLÉVŐ `practiceGeneratorEnabled` kapu alá kerül

A két társ-képernyő már ott él. Új flag két igazságforrást adna ugyanarra a rollout-döntésre.

### 5.2 A belépési pontok a `TodayPlan`-ból mennek, nem a shell gyökeréből

A négy képernyő a napi terv KONTEXTUSÁBAN értelmes. Shell-szintű belépés kontextus nélküli állapotba dobná a felhasználót.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a négy `reachable: true` és `flagGated: true` (`practiceGeneratorEnabled`) | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | `practiceGeneratorEnabled=true` mellett mind a négy elérhető a `TodayPlan`-ból | widget-teszt valós `ProviderContainer`-rel |
| A3 | `practiceGeneratorEnabled=false` mellett egyik route sem létezik | router-teszt mindkét flag-álláson |
| A4 | A diff nem vezet be új feature-flaget | `git diff` + `test/tooling/feature_flag_audit_test.dart` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Vezess be egy ötödik, generator-specifikus flaget a négy route-hoz, futtasd a gate-et → az A4 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/ test/app/routing/ test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/ test/app/routing/app_router_test.dart test/features/practice_generator/accessibility/planner_accessibility_test.dart
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

- **A második kapu.** Új flag ugyanarra a rollout-döntésre (5.1, A4).
- **A kontextus nélküli belépés.** Shell-gyökérből nyitott terv-előnézet üres állapotot mutat (5.2).
- **A seam-regresszió.** Ha a bekötés megkerüli az `E17-R05` seamjeit, a képernyők konstansra állnak vissza (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
