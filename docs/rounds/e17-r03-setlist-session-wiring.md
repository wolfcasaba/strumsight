# E17-R03 — A Song Trainer setlist-session bekötése

- **Státusz:** PREPARED (előre megírva 2026-09-05, kód olvasva: `main @ b17e08ef`) — **`hold`: Az `E17-R01` kompozíciós mintájára épül (reachability-cella + literál-útvonal tilalom)**
- **Típus:** Chapter 17 (Teljes bekötés), Kör 3
- **Kör-azonosító:** `E17-R03`
- **Branch:** `<motor>/e17-r03-setlist-session-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0522` — a szám ELŐZETES; a foglaló a kör indulásakor adja a véglegeset (mérve: nyolc egymást követő körön át a queue ADR-oszlopa elavult volt).
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "a song trainer setlist-session bekötése"` — a kör pre-flightjának KÖTELEZŐ lefuttatnia és a találatokat a §2-be beépítenie; a brief előre megírt állapotában a §2 a `main @ b17e08ef` mérésein áll.

## 0.0 MIÉRT `hold`

Az `E17-R01` kompozíciós mintájára épül (reachability-cella + literál-útvonal tilalom). **Mi oldja fel:** az `E17-R01` lezárása.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/songs/screens/setlist_detail_screen.dart",
  "lib/features/song_trainer/application/setlists/setlist_session_providers.dart",
  "lib/features/song_trainer/public.dart",
  "test/features/song_trainer/setlist_session_wiring_test.dart",
  "docs/rounds/e17-r03-setlist-session-wiring.md",
  "test/features/songs/setlist_flow_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/song_trainer/",
  "test/features/songs/",
  "test/features/songs/setlist_flow_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
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

A `SetlistSessionScreen` a szállított kompozícióból elérhető: a setlist-részletből indítható gyakorló- és előadás-módú session.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`)

- A `SetlistSessionScreen` `reachable: false`; a `SetlistDetailScreen` (ami a természetes belépési pontja) imperatívan MÁR elérhető a `SetlistListScreen`-ből (`setlist_list_screen.dart:24`).
- Az application réteg LÉTEZIK: `SetlistSessionController` (`lib/features/song_trainer/application/setlists/setlist_session_controller.dart`), a `SetlistAvailabilityResolver` és a `SetlistItemRunner` typedefekkel.
- A `song_trainer` feature-ben `0` db `UnimplementedError` van — nincs hiányzó seam.
- A képernyő injektált függőségeket vár: `setlist`, `mode`, `availability`, `performanceRunner`, opcionális `createPracticeRunner`.

## 3. Scope

**Benne van:** A session belépési pontja a setlist-részletből (gyakorló és előadás mód) · a kompozíciós providerek, amik a `SetlistAvailabilityResolver`-t és a `SetlistItemRunner`-t a szállított forrásból adják · a session befejezésének visszatérési útja.

**NINCS benne (tilos):**

- A `SetlistSessionController` szemantikájának módosítása.
- Új setlist-viselkedés vagy -modell.
- A `songTrainerV2Enabled` kapu alapértékének megváltoztatása.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0522)

### 5.1 A belépés a setlist-RÉSZLETBŐL megy, nem a listából

A session egy KONKRÉT setlistre vonatkozik. A listából indítás a kiválasztást és az indítást egy gesztusba vonná, és a részlet-képernyő (a mód választásának helye) kimaradna.

### 5.2 A két mód (gyakorlás / előadás) UGYANAZON a belépési ponton megy, paraméterként

A `SetlistSessionMode` már ma is a képernyő paramétere. Két külön belépési pont két kód-utat teremtene ugyanarra az állapotgépre.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `SetlistSessionScreen` `reachable: true` | `dart run tool/check_screen_reachability.dart --format json` |
| A2 | A setlist-részletből mindkét mód elindítható, és a session a VALÓS `SetlistSessionController`-rel fut | widget-teszt valós `ProviderContainer`-rel |
| A3 | A mód a belépési pont PARAMÉTERE — a diff nem visz két külön indító útvonalat | `git diff` + teszt mindkét módra |
| A4 | A session befejezése a setlist-részletre tér vissza, nem a gyökérre | widget-teszt |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** Kösd a két módot két külön belépési pontra, futtasd a gate-et → az A3 cellának PIROSNAK kell lennie → állítsd vissza.

Minden fenti acceptance-cella MÉRT állítás: a §7 gate-parancsa futtatja őket, és a falszifikációs próba bizonyítja, hogy a cellák tényleg pirosra váltanak a hibás implementáción.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/ test/features/songs/ test/features/songs/setlist_flow_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/app/navigation/
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

- **A két kód-út.** Módonként külön indító útvonal ugyanarra az állapotgépre divergáló viselkedést szül (5.2).
- **A visszatérési út elvesztése.** A session végén gyökérre navigálás elveszíti a setlist kontextusát (A4).
- **Az availability-resolver megkerülése.** Ha a bekötés konstans elérhetőséget ad, a session nem létező tételeket próbálna futtatni (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
