# E17-R05 — A Practice Generator két `UnimplementedError` seamje

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A kör két hiányzó seamet IMPLEMENTÁL (nem bekötés)**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 5
- **Kör-azonosító:** `E17-R05`
- **Branch:** `<motor>/e17-r05-practice-generator-seams`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0524` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "a practice generator két `unimplementederror` seamje"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A kör két hiányzó seamet IMPLEMENTÁL (nem bekötés). **Mi oldja fel:** az `E17-R01`..`E17-R04` kompozíciós sáv lezárása, hogy a seam-implementáció mért bekötési mintára épüljön.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/presentation/providers/practice_generator_providers.dart",
  "lib/features/practice_generator/application/",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/seam_implementation_test.dart",
  "docs/rounds/e17-r05-practice-generator-seams.md",
]
native_gate = false
gate_tests = [
  "test/features/practice_generator/",
  "test/features/practice/",
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

A Practice Generator két production-seamje valós implementációt kap: az exercise-candidate resolver és a generation-plan-input builder.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- `lib/features/practice_generator/presentation/providers/practice_generator_providers.dart:88` és `:151` — két `throw UnimplementedError` a production úton.
- A router MÉRT megjegyzése szerint a Generator 6 képernyőjéből 2 (`PlanSetup`, `TodayPlan`) MÁR routolt a `practiceGeneratorEnabled` kapu alatt, a maradék 4 pedig TRANZITÍVAN e két seamen áll.
- A `practiceGeneratorEnabled` `forEnvironment`-ben `nonProd` — a dev buildben BE van, tehát a két routolt képernyő MA is elérhető.

## 3. Scope

**Benne van:** A két seam valós implementációja · a gyakorlat-jelölt feloldás a szállított gyakorlat-katalógusból · a terv-generálás bemenetének összeállítása valós gyakorlás-előzményből.

**NINCS benne (tilos):**

- A 4 még nem routolt Generator-képernyő bekötése — az az `E17-R06`.
- A `plannerAssistEnabled` (modell-segített javaslat) bekapcsolása.
- A generálási algoritmus szemantikájának megváltoztatása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0524)

### 5.1 A gyakorlat-jelölt feloldás a MEGLÉVŐ katalógusból dolgozik, nem épít másodikat

A Practice feature már hordoz gyakorlat-katalógust. Egy generator-specifikus második katalógus két igazságforrást adna ugyanarra a gyakorlat-halmazra.

### 5.2 A terv-bemenet a VALÓS gyakorlás-előzményből épül, konstans nélkül

A `check_placeholder_wiring.dart` P1/P2/P3 szabályai konstans-placeholderre pirosat adnak; a seam értéke pont az, hogy valós forrást ad.

### 5.3 A `plannerAssistEnabled` KI marad

A modell-segített javaslat külön rollout-döntés (a `forEnvironment` minden környezetben `false`-ra köti). A seam determinisztikus úton is teljes.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A két seam production úton NEM dob `UnimplementedError`-t | `grep` a fájlra + teszt, ami a production providert olvassa |
| A2 | A gyakorlat-jelölt feloldás a szállított katalógusból ad jelöltet, nem saját listából | teszt, ami a katalógust üresre állítva üres jelölt-halmazt vár |
| A3 | A terv-bemenet valós gyakorlás-előzményből épül — üres előzményen explicit üres állapot, nem konstans | teszt + `dart run tool/check_placeholder_wiring.dart` 0 lelet |
| A4 | A `plannerAssistEnabled` értéke a diffben nem változik | `git diff` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Állítsd a terv-bemenetet konstans értékre, futtasd a `check_placeholder_wiring.dart`-ot → a P-szabálynak leletet kell adnia és az A3 cellának PIROSNAK → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/ test/features/practice/
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

- **A második katalógus.** Divergáló gyakorlat-halmaz a Practice és a Generator között (5.1).
- **A konstans-placeholder.** Pont az a hibaosztály, amit az `E16-R05` mérőeszköze fog (5.2, A3).
- **A rollout-döntés elkövetése.** A `plannerAssistEnabled` bekapcsolása termékdöntés (5.3, A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
