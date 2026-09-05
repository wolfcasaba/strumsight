# E17-R14 — A Chapter 17 zárása: 96/96 elérhetőség és APK-evidencia

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: A fejezet minden körén áll**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 14
- **Kör-azonosító:** `E17-R14`
- **Branch:** `<motor>/e17-r14-full-wiring-closure`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0533` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "a chapter 17 zárása: 96/96 elérhetőség és apk-evidencia"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

A fejezet minden körén áll. **Mi oldja fel:** az `E17-R13` lezárása.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/full-wiring-verification.md",
  "test/tooling/screen_reachability_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
  "docs/rounds/e17-r14-full-wiring-closure.md",
]
native_gate = false
gate_tests = [
  "test/tooling/",
  "test/e2e/full_app_walkthrough_test.dart",
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

A fejezet befejezési mércéje MÉRT artefaktumon áll: `check_screen_reachability` `Unreachable: 0`, teljes-app bejárás és zöld APK-evidencia.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A fejezet nyitásakor (`main @ b17e08ef`) a mérés: `Measured screens: 96. Reachable: 73. Unreachable: 23.`
- Az `E16-R05` mintája (`docs/release/full-app-verification.md`) MÉRT bejárást és NEM javított leletek listáját adja — ez a kör ugyanezt a formát követi.
- A `tool/check_screen_reachability.dart` és a `tool/check_placeholder_wiring.dart` a fában él, gépi mérőeszközként.

## 3. Scope

**Benne van:** A záró mérés futtatása és rögzítése · a `Unreachable: 0` cella a `gate_tests`-be emelése · a teljes-app bejárás kiterjesztése az újonnan bekötött állomásokra · APK-evidencia a `build-apk.yml` zöld futásából.

**NINCS benne (tilos):**

- Bármely `lib/**` bekötés — a fejezet korábbi körei zárták le.
- Rollout-döntés bármely kapu alapértékéről.
- Új képernyő.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0533)

### 5.1 A `Unreachable: 0` GÉPI cella, nem doksi-mondat

A fejezet egész értéke azon áll, hogy a mérés reprodukálható. Egy doksiba írt szám a következő körben némán elavul — pont az a hibaosztály, amit az `E14-R01` release-guard hamis manifest-hivatkozása mért.

### 5.2 A NEM javított leletek NEVESÍTVE maradnak, gazdával és körrel

Az `E16-R05` mintája: egy zöld bejárás akkor őszinte, ha a nem javított leleteket is kimondja.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `dart run tool/check_screen_reachability.dart` → `Unreachable: 0` | a parancs csonkítatlan kimenete |
| A2 | A `Unreachable: 0` a `gate_tests` gépi cellája — a szám elmozdulása PIROS | `test/tooling/screen_reachability_test.dart` |
| A3 | A teljes-app bejárás az újonnan bekötött állomásokat is érinti, és zöld | `test/e2e/full_app_walkthrough_test.dart` |
| A4 | A `check_placeholder_wiring.dart` továbbra is 0 leletet ad | a parancs kimenete |
| A5 | A NEM javított leletek nevesítve, gazdával és körrel szerepelnek a záró dokumentumban | `docs/release/full-wiring-verification.md` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Kösd ki az egyik újonnan bekötött képernyőt (töröld a route-ját), futtasd a gate-et → az A1 és A2 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ test/e2e/full_app_walkthrough_test.dart
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

- **A doksiba írt szám.** Némán elavul, és hamis zöldet ad (5.1, A2).
- **A leletek elhallgatása.** Egy zöld bejárás nem javított leletek nélkül félrevezet (5.2, A5).
- **A placeholder-visszacsúszás.** A bekötések konstansra állhattak vissza (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
