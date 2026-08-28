# E15-R05 — Song Trainer képernyők migrálása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 5
- **Kör-azonosító:** `E15-R05`
- **Branch:** `<motor>/e15-r05-song-trainer-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "song trainer editor overview result setup UI migration"` → **[ADR 0125](../adr/0125-song-trainer-setup-configuration-boundary.md)** (a setup-konfiguráció határa) és **[ADR 0092](../adr/0092-song-trainer-practice-engine-integration.md)** (Song Trainer × Practice Engine integráció) — a migráció EZEKET a határokat nem mozdíthatja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/song_trainer/presentation/screens/song_trainer_screen.dart lib/features/song_trainer/presentation/screens/song_overview_screen.dart lib/features/song_trainer/presentation/screens/song_result_screen.dart lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart lib/features/song_trainer/presentation/screens/setlist_session_screen.dart lib/features/song_trainer/presentation/screens/song_editor_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_library_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **9** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

A sáv legnagyobb egyetlen batch-e (kilenc képernyő), és a dal-gyakorlás teljes útját fedi: könyvtár → áttekintés → setup → futás → eredmény, plusz az import és a szerkesztő.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/presentation/screens/song_trainer_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_overview_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_result_screen.dart",
  "lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart",
  "lib/features/song_trainer/presentation/screens/setlist_session_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_editor_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart",
  "lib/features/song_trainer/presentation/screens/song_library_screen.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
  "test/ui/goldens/e13_r25_screens_golden_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r05-song-trainer-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/song_trainer/application/setlists/setlist_session_controller_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "test/features/song_trainer/presentation/song_editor_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_preview_screen_test.dart",
  "test/features/song_trainer/presentation/song_import_screen_test.dart",
  "test/features/song_trainer/presentation/song_library_screen_test.dart",
  "test/features/song_trainer/presentation/song_overview_screen_test.dart",
  "test/features/song_trainer/presentation/song_result_screen_test.dart",
  "test/features/song_trainer/presentation/song_trainer_accessibility_test.dart",
  "test/features/song_trainer/presentation/song_trainer_screen_test.dart",
  "test/features/song_trainer/presentation/trainer_setup_screen_test.dart",
  "test/features/songs/import/editor_draft_test.dart",
  "test/features/songs/import/import_blocking_error_test.dart",
  "test/features/songs/song_asset_state_test.dart",
  "test/features/songs/song_library_test.dart",
  "test/features/songs/trainer/playback_only_result_test.dart",
  "test/features/songs/trainer/playhead_loop_sync_test.dart",
  "test/features/songs/trainer/setlist_run_test.dart",
  "test/features/songs/trainer/trainer_setup_test.dart",
  "test/ui/goldens/e13_r23_screens_golden_test.dart",
  "test/ui/goldens/e13_r24_screens_golden_test.dart",
  "test/ui/goldens/e13_r25_screens_golden_test.dart",
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

A batch 9 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `song_trainer_screen.dart`, `song_overview_screen.dart`, `song_result_screen.dart`, `trainer_setup_screen.dart`, `setlist_session_screen.dart`, `song_editor_screen.dart`, `song_import_screen.dart`, `song_import_preview_screen.dart`, `song_library_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 9 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a `song_trainer_screen` transzport-vezérlője (lejátszás, hurok, tempó) VISELKEDÉSBEN változatlan — csak a megjelenítés kerül design-rendszer-komponensekre
- a `song_editor_screen` szerkesztési modellje és validációja (ADR 0125 határ) érintetlen
- az import-út két képernyője megtartja a licenc/forrás-jelvényt és a `canPersist == false` lakat-jelzést

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_overview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/setlist_session_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/application/setlists/setlist_session_controller_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_editor_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_import_preview_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_import_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_library_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_overview_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_result_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_trainer_accessibility_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/song_trainer_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/song_trainer/presentation/trainer_setup_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/import/editor_draft_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/import/import_blocking_error_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_asset_state_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_library_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/playback_only_result_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/playhead_loop_sync_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/setlist_run_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/trainer/trainer_setup_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r23_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r24_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r25_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

**Tilos zóna:** a batch feature-einek `application/`, `domain/`, `data/`, `providers/` könyvtárai · minden más `lib/features/**` képernyő · `lib/app/**` · `lib/core/design_system/**` (a komponenseket HASZNÁLJUK, nem módosítjuk) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ÚJ ADR. Három kötelező szabály:

### 5.1 A viselkedés bitre azonos marad

Ugyanaz az adat, ugyanaz a sorrend, ugyanazok az állapotok (üres, betöltés, hiba). **NEM elfogadható gyengítés:** „egyszerűsítettük a hibaállapotot" — az információvesztés, nem migráció.

### 5.2 Minden állapotnak van design-rendszer-megfelelője

Üres lista → `SsEmptyState`, hiba → `SsErrorState`, betöltés → a design-rendszer betöltés-komponense. **NEM elfogadható gyengítés:** nyers `CircularProgressIndicator` vagy csupasz `Text('Hiba')` meghagyása.

### 5.3 A szöveg lokalizált marad

Beégetett felhasználói szöveg nem kerülhet a migrált kódba; új szöveg egyszerre `en` ÉS `hu` ARB-kulcsot kap. **NEM elfogadható gyengítés:** angol placeholder „amíg lefordítjuk".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mind a 9 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
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

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cserélj vissza EGY migrált képernyőn egy `SsErrorState`-et nyers `Text`-re, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/routing/app_router_test.dart test/features/song_trainer/application/setlists/setlist_session_controller_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart test/features/song_trainer/presentation/song_editor_screen_test.dart test/features/song_trainer/presentation/song_import_preview_screen_test.dart test/features/song_trainer/presentation/song_import_screen_test.dart test/features/song_trainer/presentation/song_library_screen_test.dart test/features/song_trainer/presentation/song_overview_screen_test.dart test/features/song_trainer/presentation/song_result_screen_test.dart test/features/song_trainer/presentation/song_trainer_accessibility_test.dart test/features/song_trainer/presentation/song_trainer_screen_test.dart test/features/song_trainer/presentation/trainer_setup_screen_test.dart test/features/songs/import/editor_draft_test.dart test/features/songs/import/import_blocking_error_test.dart test/features/songs/song_asset_state_test.dart test/features/songs/song_library_test.dart test/features/songs/trainer/playback_only_result_test.dart test/features/songs/trainer/playhead_loop_sync_test.dart test/features/songs/trainer/setlist_run_test.dart test/features/songs/trainer/trainer_setup_test.dart test/ui/goldens/e13_r23_screens_golden_test.dart test/ui/goldens/e13_r24_screens_golden_test.dart test/ui/goldens/e13_r25_screens_golden_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/song_trainer/presentation/screens/song_trainer_screen.dart lib/features/song_trainer/presentation/screens/song_overview_screen.dart lib/features/song_trainer/presentation/screens/song_result_screen.dart lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart lib/features/song_trainer/presentation/screens/setlist_session_screen.dart lib/features/song_trainer/presentation/screens/song_editor_screen.dart lib/features/song_trainer/presentation/screens/song_import_screen.dart lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart lib/features/song_trainer/presentation/screens/song_library_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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
