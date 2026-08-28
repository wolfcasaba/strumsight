# E15-R04 — Practice és Learn képernyők migrálása

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 4
- **Kör-azonosító:** `E15-R04`
- **Branch:** `<motor>/e15-r04-practice-and-learn-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "practice hub result history speed builder UI migration design system"` → a `halts/round-status-E13-R22` (Practice results és Speed Builder UI) és a `halts/round-status-E13-R32` merge-elt körei — a Ch13 EZEKRE a képernyőkre MÁR épített design-rendszer-komponenseket, csak a legacy képernyők nem használják őket.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/practice/presentation/screens/practice_hub_screen.dart lib/features/practice/presentation/screens/practice_result_screen.dart lib/features/practice/presentation/screens/practice_history_screen.dart lib/features/practice/presentation/screens/speed_builder_screen.dart lib/features/learn/screens/learn_screen.dart lib/features/learn/screens/lesson_list_screen.dart lib/features/learn/screens/lesson_score_preview_screen.dart lib/features/learn/screens/latency_calibration_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **8** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a leggyakrabban látott felület: a gyakorlás belépője, eredménye és a Learn-út. A `practice_hub` a shell `Practice` destinationjének egyik célja, tehát a felhasználó szinte minden munkamenetben látja.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/presentation/screens/practice_hub_screen.dart",
  "lib/features/practice/presentation/screens/practice_result_screen.dart",
  "lib/features/practice/presentation/screens/practice_history_screen.dart",
  "lib/features/practice/presentation/screens/speed_builder_screen.dart",
  "lib/features/learn/screens/learn_screen.dart",
  "lib/features/learn/screens/lesson_list_screen.dart",
  "lib/features/learn/screens/lesson_score_preview_screen.dart",
  "lib/features/learn/screens/latency_calibration_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/chords/chord_library_test.dart",
  "test/features/learn/continue_card_test.dart",
  "test/features/learn/expected_chord_hint_test.dart",
  "test/features/learn/latency_calibration_screen_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "test/features/learn/learn_screen_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/features/learn/lesson_score_card_test.dart",
  "test/features/learn/live_scoring_jitter_test.dart",
  "test/features/learn/next_lesson_cta_test.dart",
  "test/features/learn/review_r100_fixes_test.dart",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/learn/visual_offset_test.dart",
  "test/features/learn/waltz_count_in_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_result_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/ui/goldens/e13_r20_screens_golden_test.dart",
  "test/ui/goldens/e13_r22_screens_golden_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r04-practice-and-learn-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/chords/chord_library_test.dart",
  "test/features/learn/continue_card_test.dart",
  "test/features/learn/expected_chord_hint_test.dart",
  "test/features/learn/latency_calibration_screen_test.dart",
  "test/features/learn/learn_rollback_test.dart",
  "test/features/learn/learn_screen_test.dart",
  "test/features/learn/learning_path_test.dart",
  "test/features/learn/lesson_list_screen_test.dart",
  "test/features/learn/lesson_offline_test.dart",
  "test/features/learn/lesson_score_card_test.dart",
  "test/features/learn/live_scoring_jitter_test.dart",
  "test/features/learn/next_lesson_cta_test.dart",
  "test/features/learn/review_r100_fixes_test.dart",
  "test/features/learn/setlist_expected_hint_test.dart",
  "test/features/learn/visual_offset_test.dart",
  "test/features/learn/waltz_count_in_test.dart",
  "test/features/practice/history_corrupt_record_test.dart",
  "test/features/practice/presentation/practice_a11y_audit_test.dart",
  "test/features/practice/presentation/practice_hub_screen_test.dart",
  "test/features/practice/presentation/practice_result_screen_test.dart",
  "test/features/practice/presentation/practice_routing_test.dart",
  "test/features/practice/result_confidence_test.dart",
  "test/features/practice/reward_idempotency_test.dart",
  "test/features/practice/speed_ladder_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/ui/goldens/e13_r20_screens_golden_test.dart",
  "test/ui/goldens/e13_r22_screens_golden_test.dart",
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

A batch 8 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `practice_hub_screen.dart`, `practice_result_screen.dart`, `practice_history_screen.dart`, `speed_builder_screen.dart`, `learn_screen.dart`, `lesson_list_screen.dart`, `lesson_score_preview_screen.dart`, `latency_calibration_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 8 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a `practice_result_screen` pontszám- és visszajelzés-blokkjai `SsCard`/`SsMetricTile` komponensekre kerülnek, a MÉRT értékek és a kerekítés változatlanul
- a `speed_builder_screen` lépcső-vezérlője megtartja a jelenlegi BPM-lépéseket — a DSP/időzítés-paraméterekhez NEM nyúlunk (AGENTS.md §9)
- a `latency_calibration_screen` mérési folyamata (a kalibrációs számok és a küszöbök) érintetlen marad

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/practice_result_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/practice_history_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/practice/presentation/screens/speed_builder_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/learn_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/lesson_list_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/lesson_score_preview_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/learn/screens/latency_calibration_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/navigation/legacy_route_redirect_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/core/screen_size_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/chords/chord_library_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/continue_card_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/expected_chord_hint_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/latency_calibration_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learn_rollback_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learn_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/learning_path_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_list_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_offline_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/lesson_score_card_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/live_scoring_jitter_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/next_lesson_cta_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/review_r100_fixes_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/setlist_expected_hint_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/visual_offset_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/learn/waltz_count_in_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/history_corrupt_record_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_a11y_audit_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_hub_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_result_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/presentation/practice_routing_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/result_confidence_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/reward_idempotency_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/practice/speed_ladder_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/setlist_flow_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r20_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/ui/goldens/e13_r22_screens_golden_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
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
| A1 | Mind a 8 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
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
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/core/screen_size_guard_test.dart test/features/chords/chord_library_test.dart test/features/learn/continue_card_test.dart test/features/learn/expected_chord_hint_test.dart test/features/learn/latency_calibration_screen_test.dart test/features/learn/learn_rollback_test.dart test/features/learn/learn_screen_test.dart test/features/learn/learning_path_test.dart test/features/learn/lesson_list_screen_test.dart test/features/learn/lesson_offline_test.dart test/features/learn/lesson_score_card_test.dart test/features/learn/live_scoring_jitter_test.dart test/features/learn/next_lesson_cta_test.dart test/features/learn/review_r100_fixes_test.dart test/features/learn/setlist_expected_hint_test.dart test/features/learn/visual_offset_test.dart test/features/learn/waltz_count_in_test.dart test/features/practice/history_corrupt_record_test.dart test/features/practice/presentation/practice_a11y_audit_test.dart test/features/practice/presentation/practice_hub_screen_test.dart test/features/practice/presentation/practice_result_screen_test.dart test/features/practice/presentation/practice_routing_test.dart test/features/practice/result_confidence_test.dart test/features/practice/reward_idempotency_test.dart test/features/practice/speed_ladder_test.dart test/features/songs/setlist_flow_test.dart test/ui/goldens/e13_r20_screens_golden_test.dart test/ui/goldens/e13_r22_screens_golden_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/practice/presentation/screens/practice_hub_screen.dart lib/features/practice/presentation/screens/practice_result_screen.dart lib/features/practice/presentation/screens/practice_history_screen.dart lib/features/practice/presentation/screens/speed_builder_screen.dart lib/features/learn/screens/learn_screen.dart lib/features/learn/screens/lesson_list_screen.dart lib/features/learn/screens/lesson_score_preview_screen.dart lib/features/learn/screens/latency_calibration_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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
