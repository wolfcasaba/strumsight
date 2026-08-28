# E15-R06 — Örökség Songs, Library, Progress és Streak képernyők

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 6
- **Kör-azonosító:** `E15-R06`
- **Branch:** `<motor>/e15-r06-legacy-song-library-progress-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy screen retirement route reachability dead code deprecation"` → **[ADR 0065](../adr/0065-practice-engine-v2-parallel-rollout.md)** (a V2 a legacy MELLETT fut) és **[L449](../LESSONS.md#l449)** — ezek a képernyők párhuzamos rétegek, ezért az `E15-R03` visszavonási terve dönti el, melyiket migráljuk.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/songs/screens/song_list_screen.dart lib/features/songs/screens/song_builder_screen.dart lib/features/songs/screens/setlist_list_screen.dart lib/features/songs/screens/setlist_detail_screen.dart lib/features/library/screens/library_screen.dart lib/features/library/screens/session_detail_screen.dart lib/features/progress/screens/progress_screen.dart lib/features/streak/screens/streak_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **8** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

Ez a batch a MÉRHETŐEN párhuzamos örökség-réteg: `songs/` ↔ `song_trainer/`, `library/` ↔ `library_v2/`, `progress/` ↔ `progress_v2/`. A kör KIZÁRÓLAG azokat migrálja, amiket az `E15-R03` terve „migrálandó”-nak jelölt; a „visszavonandó” tételekhez javaslatot ír, végrehajtás nélkül.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/songs/screens/song_list_screen.dart",
  "lib/features/songs/screens/song_builder_screen.dart",
  "lib/features/songs/screens/setlist_list_screen.dart",
  "lib/features/songs/screens/setlist_detail_screen.dart",
  "lib/features/library/screens/library_screen.dart",
  "lib/features/library/screens/session_detail_screen.dart",
  "lib/features/progress/screens/progress_screen.dart",
  "lib/features/streak/screens/streak_screen.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/library/rename_capo_title_test.dart",
  "test/features/library/session_rename_test.dart",
  "test/features/progress/progress_screen_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/features/songs/song_flow_test.dart",
  "test/features/songs/song_meter_test.dart",
  "test/features/songs/song_tap_tempo_test.dart",
  "test/features/streak/skill_reframe_test.dart",
  "test/features/streak/streak_screen_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r06-legacy-song-library-progress-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/offline_network_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/features/library/rename_capo_title_test.dart",
  "test/features/library/session_rename_test.dart",
  "test/features/progress/progress_screen_test.dart",
  "test/features/songs/setlist_flow_test.dart",
  "test/features/songs/song_flow_test.dart",
  "test/features/songs/song_meter_test.dart",
  "test/features/songs/song_tap_tempo_test.dart",
  "test/features/streak/skill_reframe_test.dart",
  "test/features/streak/streak_screen_test.dart",
  "test/features/today/hub_navigation_test.dart",
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

- A batch képernyői (MÉRVE `grep -L design_system`): `song_list_screen.dart`, `song_builder_screen.dart`, `setlist_list_screen.dart`, `setlist_detail_screen.dart`, `library_screen.dart`, `session_detail_screen.dart`, `progress_screen.dart`, `streak_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 8 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a kör ELSŐ lépése a `docs/ui/retirement-plan.md` beolvasása — a batch tényleges tartalmát az adja, nem ez a lista
- a tervben `visszavonandó`-ként jelölt képernyő NEM migrálódik: helyette a §10 rögzíti, melyik kör vonja vissza
- ha a terv és a fa ellentmond (a képernyő időközben elérhetetlenné vált), az `stopped` jelzés

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/songs/screens/song_list_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/songs/screens/song_builder_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/songs/screens/setlist_list_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/songs/screens/setlist_detail_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/library/screens/library_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/library/screens/session_detail_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/progress/screens/progress_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/streak/screens/streak_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/navigation/adaptive_scaffold_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/navigation/legacy_route_redirect_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/offline_network_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/core/screen_size_guard_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/library/rename_capo_title_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/library/session_rename_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/progress/progress_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/setlist_flow_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_flow_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_meter_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/songs/song_tap_tempo_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/streak/skill_reframe_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/streak/streak_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/today/hub_navigation_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
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
tools/round-gate.sh test/ui/ui_inventory_test.dart test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/offline_network_guard_test.dart test/app/routing/app_router_test.dart test/core/screen_size_guard_test.dart test/features/library/rename_capo_title_test.dart test/features/library/session_rename_test.dart test/features/progress/progress_screen_test.dart test/features/songs/setlist_flow_test.dart test/features/songs/song_flow_test.dart test/features/songs/song_meter_test.dart test/features/songs/song_tap_tempo_test.dart test/features/streak/skill_reframe_test.dart test/features/streak/streak_screen_test.dart test/features/today/hub_navigation_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/songs/screens/song_list_screen.dart lib/features/songs/screens/song_builder_screen.dart lib/features/songs/screens/setlist_list_screen.dart lib/features/songs/screens/setlist_detail_screen.dart lib/features/library/screens/library_screen.dart lib/features/library/screens/session_detail_screen.dart lib/features/progress/screens/progress_screen.dart lib/features/streak/screens/streak_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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
