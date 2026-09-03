# E15-R08 — Gamification képernyők migrálása

- **Státusz:** READY (előre megírva 2026-08-28 `main @ 4cb32eb0`-n; pre-flight
  újramérve és revideálva 2026-09-02, `main @ 289fcaac` — lásd **§0.0.A**)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 8
- **Kör-azonosító:** `E15-R08`
- **Branch:** `<motor>/e15-r08-gamification-migration`
- **Előfeltétel:** `E15-R03` merge-elve (a visszavonási terv dönti el, mit KELL migrálni)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — migrációs kör, kötött ÚJ architekturális döntés nélkül (a hivatkozott szerződéseket korábbi ADR-ek rögzítik).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "gamification achievements quests reward inbox streak UI"` → a `halts/round-status-E13-R32` (Gamification Hub/Quest/Achievement/Reward UI) — a Ch13 a HUB-ot már megépítette design-rendszerrel, a hat részletképernyő maradt legacy.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd be a `docs/ui/retirement-plan.md` (E15-R03) sorait erre a batch-re, és mérd újra, mely képernyők legacyk MÉG:
> ```bash
> for f in lib/features/gamification/presentation/screens/achievements_screen.dart lib/features/gamification/presentation/screens/achievement_detail_screen.dart lib/features/gamification/presentation/screens/quests_screen.dart lib/features/gamification/presentation/screens/level_detail_screen.dart lib/features/gamification/presentation/screens/reward_inbox_screen.dart lib/features/gamification/presentation/screens/streak_detail_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
> ```
> A megíráskor mind a **6** felsorolt képernyő legacy volt. Ami időközben migrálódott, azt a §3 scope-ból ki kell venni.

## 0.0 A kör határa: MEGJELENÉS, nem viselkedés

A migráció a képernyők VIZUÁLIS rétegét cseréli design-rendszer-komponensekre. A képernyő TÍPUSA, route-ja, publikus API-ja és üzleti viselkedése VÁLTOZATLAN — a típus-pinnelő tesztek (§4) ezért maradnak zöldek, és a jogosultság pontosan ennyi: **cella törlése, `skip`-je vagy gyengítése TILOS**. Az `E15-R01` óta az app témája hordozza a tokeneket, tehát ÚJ `*ThemeScope` burkoló NEM vezethető be; a meglévő burkoló eltávolítható, ha a képernyő már az app témájából old fel.

A Ch13-R32 a Gamification HUB-ot megcsinálta, de a hat részletképernyő (kitűzők, küldetések, szint, jutalom-postafiók, sorozat) legacy maradt — a felhasználó a hubról egy kattintásra ezekre esik, és ott törik meg a látvány.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/presentation/screens/achievements_screen.dart",
  "lib/features/gamification/presentation/screens/achievement_detail_screen.dart",
  "lib/features/gamification/presentation/screens/quests_screen.dart",
  "lib/features/gamification/presentation/screens/level_detail_screen.dart",
  "lib/features/gamification/presentation/screens/reward_inbox_screen.dart",
  "lib/features/gamification/presentation/screens/streak_detail_screen.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "test/app/routing/app_router_test.dart",
  "test/features/gamification/presentation/achievements_screen_test.dart",
  "test/features/gamification/presentation/achievement_detail_screen_test.dart",
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "test/features/gamification/presentation/level_detail_screen_test.dart",
  "test/features/gamification/presentation/quests_screen_test.dart",
  "test/features/gamification/presentation/reward_inbox_screen_test.dart",
  "test/features/gamification/presentation/streak_detail_screen_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
  "test/ui/goldens/e13_r32_screens_golden_test.dart",
  "test/ui/goldens/goldens/e13_r32_achievements_compact.png",
  "test/ui/goldens/goldens/e13_r32_achievements_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r32_quests_compact.png",
  "test/ui/goldens/goldens/e13_r32_quests_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r32_reward_inbox_compact.png",
  "test/ui/goldens/goldens/e13_r32_reward_inbox_compact_scale2.png",
  "test/ui/goldens/goldens/e13_r32_streak_detail_compact.png",
  "test/ui/goldens/goldens/e13_r32_streak_detail_compact_scale2.png",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r08-gamification-migration.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/gamification/presentation/achievements_screen_test.dart",
  "test/features/gamification/presentation/achievement_detail_screen_test.dart",
  "test/features/gamification/presentation/gamification_accessibility_test.dart",
  "test/features/gamification/presentation/gamification_hub_screen_test.dart",
  "test/features/gamification/presentation/level_detail_screen_test.dart",
  "test/features/gamification/presentation/quests_screen_test.dart",
  "test/features/gamification/presentation/reward_inbox_screen_test.dart",
  "test/features/gamification/presentation/streak_detail_screen_test.dart",
  "test/features/gamification/ui/reduced_motion_test.dart",
  "test/features/gamification/ui/streak_states_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff felhasználói felületet ír át azon az úton, amit a felhasználó a leggyakrabban jár; egy elveszett állapot- vagy hibajelzés némán rontaná az élményt. A `flutter-reviewer` és a `flutter-devil-advocate` futtatása a review-ban KÖTELEZŐ.

## 0.0.A Pre-flight brief-revízió (orchestrátor, 2026-09-02, `main @ 289fcaac`)

A brief 2026-08-28-án, `main @ 4cb32eb0`-n íródott. Az alábbi revíziók MÉRT
eltéréseket zárnak; ahol ütköznek a lentebbi eredeti szöveggel, **a revízió az
irányadó**. A `brief-lint` (strict) leletet nem adott — ezek a saját
pre-flight-mérésem leletei. A queue sora `ADR = nincs`, a §3 tiltja a
`docs/adr/**`-ot → **ez a kör nem ír ADR-t** (a prompt sablon-sora ehhez képest
általános).

### R1 — Mind a 6 képernyő MÉG legacy: a §3 scope VÁLTOZATLAN

A §7 mérő-parancs kimenete `main @ 289fcaac`-n:

```
legacy achievements_screen.dart    legacy achievement_detail_screen.dart
legacy quests_screen.dart          legacy level_detail_screen.dart
legacy reward_inbox_screen.dart    legacy streak_detail_screen.dart
```

Egyik sem migrálódott időközben, tehát a pre-flight kikötése („ami időközben
migrálódott, azt ki kell venni") nem szűkít.

### R2 — Kör-szám sodródás a `retirement-plan.md` §4-hez képest — MÉRT, és nem javítjuk itt

A `docs/ui/retirement-plan.md` §4 táblája az `E15-R08` sorba a *Practice +
Progress* batch-et írja, a gamification batch-et pedig `E15-R06`-ba. A lánc
tényleges végrehajtása ettől eltért (`migration-status.md`: R06 = Setlist +
Progress, R07 = Practice Generator). **Az irányadó artefaktum a queue sora és
ez a brief** — a `retirement-plan.md` NINCS az `allowed_paths`-on, tehát ez a
kör NEM írja át; a sodródás rögzítése a `migration-status.md`-be megy (A7).

### R3 — `level_detail_screen.dart` MÉRTEN `unreachable`, mégis a scope-ban marad

A `retirement-plan.md` §3.4 és a per-képernyő tábla (`level_detail_screen.dart`
sora: `Reachable = no`, verdikt `unreachable`) szerint a képernyőnek nincs mért
konstrukciós helye a `lib/`-ben. A brief mégis felsorolja, és **bent is marad**:
pontosan ugyanaz a döntési osztály, mint az `E15-R07` (6 unreachable Practice
Generator képernyő migrálva a queue írott szándéka szerint) és az `E15-R11`
batch. Az `unreachable` NEM `retire` (ADR 0471 D5: a nyugdíjazás javaslat, nem
végrehajtás), tehát a migrálása megengedett — de a §10-be a MÉRT elérhetőségi
besorolást is bele kell írni, hogy a döntés auditálható legyen.

### R4 — Az `allowed_paths` KIEGÉSZÍTVE: a brief §6-ja olyan bizonyítékot kért, amit a saját fájllistája nem tudott előállítani

A lista négy mért hézagot zárt be. Egyik hozzávett fájl sem esik a §4 **tilos
zónájába** (nincs köztük `application/`/`domain/`/`data/`/`providers/`, más
feature képernyője, `lib/app/**`, `lib/core/design_system/**`, `docs/adr/**`,
`tools/**`, `.github/**`) — mindegyik a kör SAJÁT gamification-felületének
teszt-, golden- vagy l10n-oldala:

| # | Mért hézag | Hozzávéve |
|---|---|---|
| G1 | **A golden-sáv a batch 4 képernyőjét PNG-re pinneli.** `test/ui/goldens/e13_r32_screens_golden_test.dart` rendereli a `QuestsScreen`, `AchievementsScreen`, `StreakDetailScreen`, `RewardInboxScreen` képernyőt, és 8 committolt PNG-hez hasonlít (`compact` + `compact_scale2`). Vizuális migráció után ezek KONSTRUKCIÓBÓL pirosak — a teljes CI-suite futtatja őket. A fájllista nélkül a kör zöldre hozhatatlan (H7). | a golden-teszt + a 8 érintett PNG |
| G2 | **Négy képernyőnek NINCS teszt-fájlja**, miközben az A2/A3 képernyőnkénti állapot- és `textScaler` cellákat kér: `achievement_detail`, `level_detail`, `reward_inbox` (nincs fájl), `streak_detail` (van fájl, de nem volt a listán). | a 4 teszt-fájl (3 ÚJ + 1 meglévő) |
| G3 | **Meglévő pinek, amiket a migráció újramérhet:** `gamification_accessibility_test.dart` (kontraszt-ellenőrzés a gamification felületen), `ui/reduced_motion_test.dart` és `ui/streak_states_test.dart` (mindkettő `StreakDetailScreen`-t épít). | a 3 teszt-fájl |
| G4 | **A §3 kifejezetten ENGEDI az új ARB-kulcsot** („mindkét locale-ra, egyszerre"), de egyetlen ARB sem volt a listán → a megengedett művelet scope-sértés lett volna. | `lib/l10n/{,base/}app_{en,hu}.arb` |

A `gate_tests` ugyanezekkel bővült, plusz a **`test/l10n/hardcoded_string_guard_test.dart`**: az A6 sor NÉV SZERINT ezt jelöli meg bizonyítéknak, de a `gate_tests`-ből hiányzott.

**Amit a bővítés NEM tesz:** a `GamificationHubScreen` és a két hub-goldenje
(`e13_r32_hub_compact{,_scale2}.png`) KÍVÜL maradt — a hub már migrált (Ch13-R32),
ezért a kör diffjében **bájtra változatlanul** kell maradnia. A közös
gamification widgetek (`pending_rewards_card`, `level_badge`, `xp_progress_bar`,
`reward_summary_sheet`) szintén kívül maradnak.

### R5 — A3: a cellákat TELEFON-viewporton kell mérni, különben hamis zöldek ([L558](../LESSONS.md#l558))

A `flutter_test` alapértelmezett 800×600-as viewportja **szélesebb ÉS magasabb
minden telefonnál**, és a lusta `ListView` a viewport alá eső gyermeket fel sem
építi — az így mért „nincs túlcsordulás" cella akár ÜRES fát is mérhet. Az
E15-R06 A3-cellái pontosan így voltak mind zöldek, miközben a review próbája
telefon-méreten 72 px túlcsordulást mért.

**Kötelező cella-alak** (a §6 küszöb-hármas ezen felül változatlan):

```dart
tester.view.physicalSize = const Size(360, 640);
tester.view.devicePixelRatio = 1.0;
addTearDown(tester.view.reset);
```

Az A3 cellái tehát: `{1.5, 2.0, 2.5} × {en, hu}` **telefon-viewporton**. A `2.0`
INKLUZÍV követelmény; a `2.5` továbbra sem követelmény, és a `2.0` teljesítése
nem hivatkozhat rá.

### R6 — A layout-javítás MINTA-szinten zár ([L559](../LESSONS.md#l559))

Ha egy állapot telefon-viewporton túlcsordul, a javítás (pl. az E15-R06/R07-ben
bevált, képernyő-lokális `_ScrollableIfShort`) **a batch MINDEN olyan
példányára** felkerül, amely ugyanazt a mintát mutatja — nem csak arra az
egyre, amelyik éppen pirosat adott. A §10-be a példányok TÉTELES listája megy.
Az E15-R06 handoffja azért mondott „2 valódi túlcsordulás javítva"-t 2/3
helyett, mert a testvér-példány védtelen maradt.

### R7 — `SsEmptyState` akció-kivétel: kitalált affordancia TILOS (E15-R04/R06/R07 precedens)

A §5.2 („üres lista → `SsEmptyState`") érvényben marad, EGY kikötéssel: ha az
adott állapotnak nincs VALÓDI, a képernyőn már létező akciója, akkor **nem
szabad kitalálni egyet** azért, hogy a komponens beférjen. Ilyenkor a state
képernyő-lokális, de **token-stílusú** widget marad (`SsColorScheme` /
`SsTypography` a témából), és a §10 tételesen indokolja. Ez nem gyengítés: a
kitalált gomb hazudna arról, mit tud a képernyő — ugyanaz az információhűségi
elv, mint a §5.1.

### R8 — A `GamificationThemeScope` osztály MEGMARAD, csak a 6 képernyő burkolója tűnik el

A burkolót a hub és négy közös widget is használja (mérve:
`gamification_hub_screen.dart:87`, `pending_rewards_card.dart:50`,
`level_badge.dart:36`, `xp_progress_bar.dart:53`, `reward_summary_sheet.dart:79`)
— ezek mind a scope-on KÍVÜL vannak. A `gamification_theme_scope.dart` fájlt
tehát **nem töröljük**; csak a 6 migrált képernyő saját `return
GamificationThemeScope(` burkolója szűnik meg (mérve: 5 képernyőn van ilyen,
`achievement_detail_screen.dart`-on nincs).

### R9 — Golden újrafelvétel: a merge-kapu architektúráján, MÉRTEN elérhető

A §7 golden-kikötése él, és a futtatási előfeltétel a boxon MÉRVE megvan:
`docker 29.4.0`, `binfmt qemu-x86_64`, `strumsight-golden-x86:3.44.2` image jelen.
Az újrafelvétel KIZÁRÓLAG:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart
```

Aarch64-en felvett PNG a CI-n (x86_64, nulla toleranciájú `LocalFileComparator`)
mindig piros — ez az ADR 0426 / [L486](../LESSONS.md#l486) / [L493](../LESSONS.md#l493)
mért osztálya. A felvétel után a **hub két PNG-je nem változhat** (R4).

### Visszakeresés (ADR 0312)

`--corpus lessons,halts,adr`: ADR 0471 (elérhetőség mért, nyugdíjazás javaslat),
`halts/round-status-E13-R32` (a hub migrációja). `--corpus lessons,halts`:
[L558](../LESSONS.md#l558) (800×600 hamis zöld → R5), [L559](../LESSONS.md#l559)
(minta-szintű zárás → R6), [L517](../LESSONS.md#l517) (a `textScaler 2.0` keret
VALÓDI hibát mér ki, a kör előtti kódban is), [L452](../LESSONS.md#l452)
(`MediaQuery(size:)` NEM méretez — ezért `tester.view.physicalSize` az R5-ben),
[L477](../LESSONS.md#l477) (mérd a cella BUKÁSI képességét, ne csak a zöldjét →
a §6.1 valódi-sértés próba).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a migrációhoz egy `application/`, `domain/` vagy `data/` réteg módosítása kellene, a kimenet a `stopped` jelzés — a viselkedés-változás nem ennek a körnek a hatásköre ([L478](../LESSONS.md#l478)).

## 1. Cél

A batch 6 képernyője a design-rendszer komponenseit és tokenjeit használja, változatlan viselkedés mellett — hogy a felület egységes legyen, és a 200%-os szövegskála, a képernyőolvasó és a két locale mindenhol működjön.

## 2. Jelenlegi állapot — mért tények

- A batch képernyői (MÉRVE `grep -L design_system`): `achievements_screen.dart`, `achievement_detail_screen.dart`, `quests_screen.dart`, `level_detail_screen.dart`, `reward_inbox_screen.dart`, `streak_detail_screen.dart`.
- Egyik sem importálja a `core/design_system`-et; a stílusuk közvetlen `Theme.of(context)` / `AppColors` / `AppPalette` hivatkozásokból jön.
- Az `E15-R01` óta az app futásidejű témája a design-rendszer témája, tehát a komponensek burkoló NÉLKÜL is feloldják a tokeneket.
- Az `E15-R02` óta az adaptív shell az alapértelmezett belépő, tehát ezek a képernyők a fő navigációból elérhetők.
- A `test/ui/ui_inventory_test.dart` EGZAKT képernyőszámot állít — a kör nem hoz létre és nem töröl képernyőt, tehát a szám VÁLTOZATLAN.

## 3. Scope

**Benne van:** a felsorolt 6 képernyő vizuális migrálása (`SsCard`, `SsButton`, `SsListTile`, `SsEmptyState`, `SsErrorState`, `SsMetricTile` és társaik; `SsSpacing`/`SsTypography` tokenek) · a meglévő `*ThemeScope` burkoló eltávolítása, ahol az `E15-R01` óta felesleges · a `migration-status.md` frissítése a MÉRT új aránnyal.

Batch-specifikus kikötések:

- a `reward_inbox_screen` a MÉRT outbox/karantén állapotokat változatlanul jeleníti meg (ADR 0333) — csak a vizuális réteg cserélődik
- a szint- és sorozat-számítás egyetlen értéke sem változhat; a kör nem nyúl az `application/` réteghez
- a `GamificationThemeScope` burkoló ELTÁVOLÍTHATÓ, mert az `E15-R01` óta az app témája hordozza a tokeneket

**NINCS benne (tilos):**

- `application/`, `domain/`, `data/`, `providers/` réteg módosítása (viselkedés-változás).
- Új képernyő létrehozása vagy meglévő törlése.
- Új `*ThemeScope` burkoló bevezetése.
- ARB-kulcs törlése vagy szöveg-jelentés megváltoztatása (új kulcs FELVEHETŐ, ha a komponens ezt igényli — mindkét locale-ra, egyszerre).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/presentation/screens/achievements_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/gamification/presentation/screens/achievement_detail_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/gamification/presentation/screens/quests_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/gamification/presentation/screens/level_detail_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` | migráció design-rendszer komponensekre |
| `lib/features/gamification/presentation/screens/streak_detail_screen.dart` | migráció design-rendszer komponensekre |
| `test/app/routing/app_router_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/gamification/presentation/achievements_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/gamification/presentation/gamification_hub_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `test/features/gamification/presentation/quests_screen_test.dart` | típus-pinnelő őr — VÁLTOZATLANUL zöld marad (§0.0) |
| `docs/ui/migration-status.md` | a MÉRT arány frissítése |

> **A §0.0.A/R4 kiegészítette ezt a listát** (golden-sáv + 4 képernyő-teszt +
> 3 meglévő pin + ARB-k). A gépi scope-audit forrása a fenti `ai-router`
> blokk `allowed_paths` mezője — ez a tábla annak olvasható kivonata.

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
| A1 | Mind a 6 képernyő importálja a `core/design_system`-et, és a mérés szerint migráltnak számít | a §7 mérő-parancs kimenete a §10-ben |
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
tools/round-gate.sh test/ui/ui_inventory_test.dart test/l10n/hardcoded_string_guard_test.dart test/app/routing/app_router_test.dart test/features/gamification/presentation/achievements_screen_test.dart test/features/gamification/presentation/achievement_detail_screen_test.dart test/features/gamification/presentation/gamification_accessibility_test.dart test/features/gamification/presentation/gamification_hub_screen_test.dart test/features/gamification/presentation/level_detail_screen_test.dart test/features/gamification/presentation/quests_screen_test.dart test/features/gamification/presentation/reward_inbox_screen_test.dart test/features/gamification/presentation/streak_detail_screen_test.dart test/features/gamification/ui/reduced_motion_test.dart test/features/gamification/ui/streak_states_test.dart
```

A golden-sáv (§0.0.A/R9) ezen felül KÖTELEZŐ, mert a batch 4 képernyője
PNG-re pinnelt:

```bash
tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart
```

A migrációs mérés (a kimenet a §10-be, batch-enként MIGRATED/legacy sorokkal):

```bash
for f in lib/features/gamification/presentation/screens/achievements_screen.dart lib/features/gamification/presentation/screens/achievement_detail_screen.dart lib/features/gamification/presentation/screens/quests_screen.dart lib/features/gamification/presentation/screens/level_detail_screen.dart lib/features/gamification/presentation/screens/reward_inbox_screen.dart lib/features/gamification/presentation/screens/streak_detail_screen.dart; do grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"; done
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

### 10.0 Eltérés a brief R8-tól — a `GamificationThemeScope` MINDEN migrált képernyőn megmaradt

A §0.0.A/R8 szerint a burkoló eltávolítható 5 képernyőről (mert „az app témája hordozza a tokeneket"). Ezt a kör MEGMÉRTE és ELLENTMONDÓNAK találta:

- `lib/core/theme/app_theme.dart` `_build()` KIZÁRÓLAG `extensions: [palette]`-et ad hozzá — nincs benne `SsColorScheme`/`SsTypography`/`SsThemeBehavior`.
- A design-rendszer kiterjesztéseit a futásidejű app KIZÁRÓLAG `lib/app/strumsight_app.dart`-on át kapja (`theme: SsLightTheme.data()`, `darkTheme: SsDarkTheme.data()`), NEM `AppTheme`-en keresztül.
- A golden-teszt (`test/ui/goldens/e13_r32_screens_golden_test.dart`) `theme: AppTheme.dark()`-ot pumpál — ez NEM hordozza a kiterjesztéseket.
- A widget-tesztek túlnyomó többsége (`achievements_screen_test.dart`, `quests_screen_test.dart`, `streak_detail_screen_test.dart`, és az új `achievement_detail_screen_test.dart`/`level_detail_screen_test.dart`/`reward_inbox_screen_test.dart`) burkoló NÉLKÜLI `MaterialApp()`-ot pumpál — ez SEM hordozza őket.
- A HUB képernyő (Ch13-R32, már migrált) maga is bizonyíték: TELJESEN design-rendszerre migrált, és MÉGIS megtartja a saját `GamificationThemeScope`-ját.

Mérve: a burkoló eltávolítása bármelyik migrált képernyőn `Theme.of(context).extension<SsColorScheme>()!`/`<SsTypography>()!` null-check összeomlást okozott (kipróbálva `achievement_detail_screen.dart`-on és `level_detail_screen.dart`-on — mindkettőt Builder-lel kellett javítani, lásd 10.6). A döntés: **egyik képernyőről sem távolítottam el a burkolót**; az `AchievementDetailScreen` most kapta meg ELŐSZÖR (korábban nem volt neki, de most SS-komponenseket használ). Ez a brief R8 szó szerinti szövegétől eltér, de annak SAJÁT feltételes kikötését ("ha a képernyő már az app témájából old fel") követi.

**Javító kör (E15-R08 review N1) — a feltétel pontosítása.** A fenti bekezdés
záró mondata ("a feltétel mérve HAMIS") FORDÍTVA mondta ki a premisszát.
Ténylegesen újramérve: a FUTÁSIDEJŰ app a kiterjesztéseket `SsLightTheme.data()`/
`SsDarkTheme.data()`-n át KAPJA (`lib/app/strumsight_app.dart:33-34` ezeket
telepíti) — vagyis a brief R8 feltétele ("ha a képernyő már az app témájából
old fel") a valódi appban IGAZ, nem hamis. Ami valóban HAMIS-nak mérhető, az a
FENTEBB felsorolt HARNESSEK állapota: a golden teszt `AppTheme.dark()`-ot
pumpál (ami CSAK `[palette]`-et ad hozzá `extensions`-ként), a widget-tesztek
túlnyomó többsége burkoló nélküli csupasz `MaterialApp()`-ot — egyik sem
hordozza a kiterjesztéseket. A burkoló megtartása emiatt továbbra is
INDOKOLT (e harnessek zölden tartásához kell), de az indoklás helyesen: „a
teszt-harnessek nem hordozzák a tokeneket", NEM „az app témája nem hordozza
őket" — ez utóbbi állítás egy jövőbeli kör számára tévesen sugallná, hogy a
futásidejű app-nak is szüksége van a burkolóra a tokenek feloldásához.

### 10.1 Képernyőnkénti komponens-csere és állapot-elhelyezés

**`achievements_screen.dart`**
- `SsSpacing` tokenek a lista-paddingre és a tile-ok közti gap-re.
- Üres állapot (`_EmptyAchievementsState`): NEM `SsEmptyState` — nincs valódi akció (a lista caller-fed, nincs "menj csinálj valamit" lépés) → screen-local, de `SsColorScheme`/`SsTypography`/`SsSpacing` token-stílusú widget maradt (R7).
- Szűrő-chipek (`ChoiceChip`/`Wrap`) VÁLTOZATLANOK — natív Material widget, már az ambiens témából (E15-R01 óta) helyesen színez, típus-pinnelt teszt-cellák nem sérülnek.
- `AchievementTile` (widgets/, scope-on kívül) VÁLTOZATLAN.

**`achievement_detail_screen.dart`**
- `GamificationThemeScope` ÚJ burkoló (10.0).
- A fő tartalom `SsTypography` tokeneket használ (`headlineMedium`/`bodyMedium`/`titleMedium`) a korábbi `Theme.of(context).textTheme.*` helyett.
- Az evidence-panel `SsCard`-ba került (korábban puszta `Text`-oszlop volt).
- Nem-található / rejtett állapot (`_notFound`/`_hidden`): NEM `SsEmptyState` — egyiknek sincs valódi következő lépése (R7) → új `_TokenMessage` screen-local widget, `SsColorScheme`/`SsTypography`/`SsSpacing` tokenekkel. Mindkettő `SingleChildScrollView`-t kapott (lásd 10.3 — R6 minta-szintű javítás).

**`quests_screen.dart`**
- `SsSpacing` tokenek a lista-paddingre és a szekció-gap-ekre.
- `_OfflineBanner`: `Container`+kézi `BoxDecoration` → `SsSurface` (a `Key('quests-offline-banner')` VÁLTOZATLAN, típus-pin nem volt rá).
- `_SectionHeader`: `SsTypography.titleLarge`.
- Üres állapot (`_EmptyQuestsState`): NEM `SsEmptyState` — a küldetések caller-fedeltek, a képernyőnek nincs "hozz létre küldetést" akciója (R7) → screen-local, token-stílusú.
- `QuestCard`/`ChallengeCard` (widgets/, scope-on kívül) VÁLTOZATLANOK.

**`level_detail_screen.dart`**
- `SsSpacing` tokenek mindenhol; a fejléc-szövegek `SsTypography`/`SsColorScheme.brand`-ra vált a korábbi `Theme.of(context).textTheme`/`colorScheme.primary` helyett.
- `_XpComponentRow`: kézi `Container`+`BoxDecoration` (szín/border/radius) → `SsCard`.
- Nincs üres/hiba/betöltés állapota a képernyőnek (tiszta adatmegjelenítés) — A2 erre a képernyőre nem alkalmazható cella-szinten, csak a design-rendszer komponens-használat (A1).
- **R3 — mért elérhetőség:** `grep -rn "LevelDetailScreen(" lib/` a saját fájlján kívül NULLA találatot ad → a képernyő MÉRVE `unreachable`, megegyezik a `retirement-plan.md` §3.4 verdiktjével. A migráció mégis megtörtént, ugyanaz a döntési osztály, mint az E15-R07 hat unreachable Practice Generator képernyője (ADR 0471 D5: `unreachable` ≠ `retire`, a nyugdíjazás csak javaslat).

**`reward_inbox_screen.dart`**
- A `Column`+`Expanded(ListView.separated(...))` szerkezet `CustomScrollView`+`SliverList.separated`-re cserélődött MINDKÉT ágon (üres ÉS listás állapot) — lásd 10.3.
- `_EmptyState`: NEM `SsEmptyState` — a postaláda olvasás-only (ADR 0389 §4), nincs "claim" vagy egyéb akció (R7) → screen-local, `SsColorScheme`/`SsTypography`/`SsSpacing` token-stílusú.
- `_InboxEntryTile`: a `Material`+`InkWell` szerkezet MEGMARADT (a látatlan/olvasott állapot vizuális megkülönböztetése — `colors.surface` vs `colors.surfaceRaised` — nem fér bele az `SsCard`/`SsSurface` egy-elevációs modelljébe anélkül, hogy elveszne az információ), de MINDEN szín/tipográfia/térköz `SsColorScheme`/`SsTypography`/`SsSpacing`/`SsRadius` tokenre váltott. Ugyanaz a kompromisszum-osztály, mint a `SetlistDetailScreen` újrarendezhető sorai (E15-R06).
- `PendingRewardsCard` (widgets/, scope-on kívül) VÁLTOZATLAN.

**`streak_detail_screen.dart`**
- `SsSpacing` tokenek a lista-paddingre és a metrika-rács gap-jeire.
- Recovery CTA: `FilledButton.icon` → `SsButton` (valódi akció — `onRecoveryPressed` callback létezik, nincs R7-kivétel). A `Key('streak-recovery-cta')` VÁLTOZATLAN; a meglévő tesztek (`streak_detail_screen_test.dart`, `ui/streak_states_test.dart`) csak a Key-re és a tap-viselkedésre pinnelnek, `FilledButton` TÍPUS-pin nem volt rájuk, ezért a csere nem sértett típus-pinnelő cellát.
- **`_StreakMetricCard` (4 metrika-kártya) VÁLTOZATLAN maradt — `Card` típusú, NEM `SsCard`.** A meglévő `streak_detail_screen_test.dart` A7+A8 csoportja `find.byType(Card, skipOffstage: false)` findsNWidgets(4) ÉS `tester.getSize(metricCards.first).height, greaterThan(80)` cellákat pinnel — ezek típus- ÉS geometria-pinek, amiket egy `SsCard`-csere eltört volna (`SsSurface` nem ad `Card` típust). Ugyanaz a kompromisszum-osztály, mint a `SetlistDetailScreen` reorderable sorai (E15-R06 precedens).

### 10.2 Golden újrafelvétel (R9)

```
tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart
```
kimenet: 10/10 teszt zöld (`hub`/`quests`/`achievements`/`streak_detail`/`reward_inbox` × `compact`/`compact_scale2`).

`git diff --stat -- test/ui/goldens/goldens/`:
```
 test/ui/goldens/goldens/e13_r32_quests_compact.png         | Bin 9910 -> 11189 bytes
 test/ui/goldens/goldens/e13_r32_quests_compact_scale2.png  | Bin 5883 -> 6980 bytes
 test/ui/goldens/goldens/e13_r32_reward_inbox_compact.png       | Bin 8488 -> 8887 bytes
 test/ui/goldens/goldens/e13_r32_reward_inbox_compact_scale2.png| Bin 8526 -> 8910 bytes
```
Csak `quests` és `reward_inbox` PNG-je változott (a látható komponens-csere ott jár pixel-eltéréssel). `achievements` és `streak_detail` PNG-je BÁJTRA VÁLTOZATLAN — a golden fixture a `streak_detail`-t `StreakEvaluationReason.grace` állapotban rendereli, ahol a Recovery CTA (az egyetlen vizuális csere ezen a képernyőn) nem is jelenik meg; az `achievements` fixture a betöltött listát mutatja, az üres állapot (az egyetlen csere) nem.

A hub két PNG-je (`e13_r32_hub_compact{,_scale2}.png`) **SHA256-ra mérve bájtra változatlan** a felvétel előtt/után:
```
efb66f9a21d320ed762cbfbaa68ddf5e7cb632c32a3b651376911ccdfb9b4c67  e13_r32_hub_compact.png
45e0c1d48cc0ea0a9748dfa60f7fb27cee7bf68e412d67dd65f8c8e7fd493cc9  e13_r32_hub_compact_scale2.png
```
(mindkét hash azonos a felvétel előtt és után) — a hub scope-on kívül maradt, ahogy R4 megkövetelte.

### 10.3 R6 — minta-szintű javítás, tételes példány-lista

Két külön mintát mértem, mindkettőt a BATCH MINDEN példányára alkalmaztam, nem csak az elsőre, ami pirosat adott:

1. **Nem-scrollozható `Center` üres/hiba-állapot, ami 200%+ szövegskálán túlcsordulhat.** Mérve: `achievement_detail_screen.dart` `_notFound`/`_hidden` — 2.5 skálán, `hu` locale-on 104 px túlcsordulás mérve PRÓBA ELŐTT. Javítás: mindkettő `SingleChildScrollView`-t kapott (nem csak az, amelyiken a próba pirosat adott).
2. **Fix magasságú fejléc-sor(ok) egy `Expanded(ListView)`-t tartalmazó `Column`-ban, ami nagy szövegskálán negatív helyre szoríthatja a listát.** Mérve: `reward_inbox_screen.dart` — 2.0 skálán (hu) és 2.5 skálán (en+hu) 110–410 px túlcsordulás mérve PRÓBA ELŐTT, MIND a listás, MIND az üres ág ugyanazt a `Column`+`Expanded` mintát használta. Javítás: mindkét ág (nem csak a listás) `CustomScrollView`+`SliverList.separated`/`SliverFillRemaining`-re cserélődött.

A csere UTÁN mind a hat képernyő mind a 6 A3-cellája (`{1.5, 2.0, 2.5} × {en, hu}`, `360×640` telefon-viewport) zöld — beleértve a korábban NEM kötelező 2.5-öst is.

### 10.4 A3 — a telefon-viewportos cellák valóban mérnek

Az `achievement_detail_screen_test.dart`, `level_detail_screen_test.dart`, `reward_inbox_screen_test.dart` (mind ÚJ) és a kiegészített `quests_screen_test.dart`/`streak_detail_screen_test.dart` mind `tester.view.physicalSize = const Size(360, 640)` + `devicePixelRatio = 1.0` + `addTearDown(tester.view.reset)` mintát használ. A `quests_screen_test.dart` eredeti A8 csoportja a flutter_test alap 800×600-as felületén futott (R5 hamis-zöld kockázat) — az ÚJ A3 csoport ezt zárja be a valódi telefon-méreten, a régi cellák VÁLTOZATLANUL megmaradtak (nincs törlés/gyengítés).

A `reward_inbox_screen.dart` és `achievement_detail_screen.dart` fenti (10.3) túlcsordulásai PONTOSAN ezekkel az új cellákkal lettek megmérve — a 10.3 "PRÓBA ELŐTT" számok a javítás előtti kóddal, ugyanezekkel a cellákkal mérve.

### 10.5 Valódi-sértés próba (§6.1, KÖTELEZŐ)

Cél: `level_detail_screen.dart` `_XpComponentRow` — `SsCard` → nyers `Container` (padding-gel, de dekoráció/token nélkül).

PIROS (a csere után, `level_detail_screen_test.dart` A1 cella):
```
Expected: exactly 5 matching candidates
  Actual: _TypeWidgetFinder:<Found 0 widgets with type "SsCard": []>
00:01 +0 -1: A1 — ... all five R06 Xp components render inside SsCard rows [E]
```

Visszaállítás után ZÖLD:
```
00:00 +0: A1 — the screen imports the design system for its component rows all five R06 Xp components render inside SsCard rows
00:01 +1: All tests passed!
```

`git diff --stat -- lib/features/gamification/presentation/screens/level_detail_screen.dart` a próba UTÁN a §8-beli teljes migrációs diffet mutatja (a próba nem hagyott maradék eltérést — a revert szó szerint visszaállította az eredeti `SsCard`-blokkot).

### 10.6 Mért implementer-hiba, ami a próba KÖZBEN derült ki (és javítva lett)

Az `achievement_detail_screen.dart` és `level_detail_screen.dart` build()-je eredetileg a KÜLSŐ (a `GamificationThemeScope`/`Builder` FELETTI) `context`-ből olvasta ki `Theme.of(context).extension<SsColorScheme>()!`/`<SsTypography>()!`-t, MIELŐTT visszaadta a burkolt fát — ez null-check összeomlást okozott minden olyan harnessben, ahol az AMBIENS téma (a burkoló előtti) nem hordozza a kiterjesztéseket (lásd 10.0). Javítás: mindkét képernyő `Builder`-be csomagolta a Scaffold-ot, és a kiterjesztéseket a Builder SAJÁT (a burkoló ALATTI) contextjéből olvassa. A `reward_inbox_screen.dart`-ban ugyanez a hiba egyetlen `Text`-re (a `reward-inbox-count`) korlátozódott — ugyanígy `Builder`-be került.

### 10.7 Migrációs mérés

Batch (§7 parancs kimenete):
```
MIGRATED lib/features/gamification/presentation/screens/achievement_detail_screen.dart
MIGRATED lib/features/gamification/presentation/screens/achievements_screen.dart
MIGRATED lib/features/gamification/presentation/screens/level_detail_screen.dart
MIGRATED lib/features/gamification/presentation/screens/quests_screen.dart
MIGRATED lib/features/gamification/presentation/screens/reward_inbox_screen.dart
MIGRATED lib/features/gamification/presentation/screens/streak_detail_screen.dart
```

Teljes arány: **75/96 (78.125%)** — a `docs/ui/migration-status.md`-be felvéve (E15-R08 bejegyzés).

### 10.8 Amit NEM tettem meg, és miért

- **A `GamificationThemeScope` eltávolítása 5 képernyőről** (a brief §0.0.A/R8 eredeti szándéka) — NEM történt meg, mert a feltétele (az app témája burkoló nélkül is hordozza a tokeneket) ezen a boxon MINDEN mért harnessben (golden, widget-tesztek) HAMIS-nak bizonyult; a burkoló eltávolítása null-check összeomlást okozott volna. Lásd 10.0. A burkoló-osztály maga (ahogy R8 is mondja) NEM törlődött.
- **`SsListTile`/`SsMetricTile`/`SsErrorState` konkrét nevű komponensek** — ezek nem léteznek a design-rendszerben (`core/design_system/public.dart` export-listája nem tartalmazza őket); a brief ezeket illusztratív névként használta. A ténylegesen létező, releváns komponenskészletet használtam: `SsCard`, `SsSurface`, `SsButton`, `SsSpacing`/`SsTypography`/`SsColorScheme`/`SsRadius` tokenek. `SsEmptyState`/`SsFailureState` egyik állapotra sem illett (R7 — lásd 10.1), ezért egyik képernyőn sem használtam őket — ez összhangban van az E15-R04/R06/R07 precedenssel.
- **Viselkedés-változás egyik képernyőn sem történt** — nem kellett STOP-ot jelezni, mert a migráció során egyszer sem merült fel `application/`/`domain/`/`data/`/`providers/` réteg módosításának igénye.

### 10.9 Javító kör (E15-R08 review: 1 BLOCKER, 4 MAJOR, 3 MINOR, 2 NOTE — mind javítva)

Minden leletnél a PIROS mérés a nem javított kódon készült, ugyanazzal a
cellával, ami utána zöldre vált.

**B1 (BLOCKER) — `_EmptyQuestsState` túlcsordult a kötelező 2.0 küszöbön.**
Az üres állapot csupasz `Center`→`Padding`→`Column` volt scroll-szülő nélkül a
`SafeArea` alatt. PIROS (a teljes `{1.5,2.0,2.5}×{en,hu}` ciklus hozzáadása
után, javítás előtt): `2.0/hu → 68px`, `2.5/en → 130px`, `2.5/hu → 205px`
(a review 3 mért száma mind pontosan reprodukálva). Javítás:
`SingleChildScrollView` az üres állapot köré (ugyanaz a minta, mint az
`achievement_detail` `_notFound`/`_hidden`). ZÖLD: mind a 6 cella (a meglévő
`2.0/en` cella is megmaradt, nem lett törölve).

**M2 (MAJOR) — a `reward_inbox` látott/olvasatlan háttere azonos színű
volt.** `colors.surface`/`colors.surfaceRaised` a `ss_colors.dart`-ban
(TILOS ZÓNA, nem nyúltam hozzá) ugyanarra a `palette.surface`-re mutat —
mérve `IDENTICAL=true` mindkét brightnesen. Új cella (widget-szintű
`Material.color` összehasonlítás) PIROS a javítás előtt
(`Color(1,1,1,1) == Color(1,1,1,1)`). Javítás: `colors.surfaceSunken`
(`palette.track` — mérve genuinely eltér `palette.surface`-től mindkét
témán) az olvasott elemekre, `colors.surface` marad az olvasatlanokon. ZÖLD.

**M3+M4 (MAJOR) — a streak recovery CTA felirata csonkolódott, a csere
kikényszerítetlen volt.** Az `SsButton` felirata egy örökké egysoros
`Flexible(overflow: TextOverflow.ellipsis)`-ben ül — mérve (saját próba,
`RenderParagraph.didExceedMaxLines`, a helyes — a label `Text`-jét, NEM az
ikon `RichText`-jét célzó — finderrel): `hu×2.0 → didExceedMaxLines=true,
size=Size(270.0, 40.0)`, egyezik a review mérésével. PIROS mindkét új cella
a nem javított kódon (`M3`: `didExceedMaxLines` igaz; `M4`:
`isA<FilledButton>()` hamis, mert a widget `SsButton`). Javítás: a CTA
visszaállt egy dokumentált-kivétel, token-stílusú `FilledButton.icon`-ra
(ugyanaz az osztály, mint a `_StreakMetricCard` nyers `Card`-ja, E13-R32
review NOTE-2) — a `Text`-nek nincs sor-korlátja, a felirat annyi sorra tör,
amennyi kell. ZÖLD mindkét cella; a teljes `streak_detail_screen_test.dart`
(29 teszt) is zöld marad.

**M5 (MAJOR) — az `achievements_screen`-nek nem volt A3-mátrixa.**
`achievements_screen_test.dart`-nak egyáltalán nem volt 360×640-es cellája,
és az üres állapot egyetlen cellában sem renderelődött. Felvéve a teljes
`{1.5,2.0,2.5}×{en,hu}` mátrix a lista- ÉS az üres állapotra (12+12 cella).
Mindegyik ZÖLD javítás nélkül is — ezen a képernyőn az üres állapot a
`ListView` GYERMEKE (nem a `SafeArea` alá helyezett CSERÉJE, mint a
quests/reward_inbox-nál), tehát sosem volt túlcsordulás-veszélyben; M5
tisztán mérce-hézag volt, nem élő hiba.

**m1 (MINOR) — az `achievement_detail` `_hidden` állapotára nem volt A3
cella**, pedig a `SingleChildScrollView`-javítás valódi volt. Felvéve a
hiányzó cella a meglévő scale/locale ciklusba. Ellenőrizve: a
`SingleChildScrollView` ideiglenes eltávolításával a `2.5/en` és `2.5/hu`
cella PIROS lett (a review 149px/29px mérésével egyező hiba-osztály),
visszaállítás után ismét ZÖLD — a `achievement_detail_screen.dart`
végleges állapota változatlan (`git diff` üres rá).

**m3 (MINOR) — a `reward-inbox-list` kulcs jelentése kitágult.** A kulcs a
scroll-javítással (10.3/2. minta) átkerült a `ListView.separated`-ről (csak
a listás ágon élt) a `CustomScrollView`-re (mindkét ágon jelen van) —
szükséges változás, mert egyetlen folytonos scroll-területnek kell lennie.
Nem visszaállítható a régi jelentés kód nélkül; ehelyett DOKUMENTÁLVA és
próbával rögzítve: a `reward-inbox-list` mostantól a közös scroll-hordozó,
az ág-azonosságot a `reward-inbox-empty` (csak üresben) és a
`reward-inbox-entry-*` (csak listásban) kulcsok viszik. Új teszt mindkét
állapotot lepumpálja és mindkét kulcs-párt ellenőrzi.

**N1 (NOTE) — a §10.0 indoklása fordítva mondta ki a premisszát.** Javítva
10.0 alatt: a FUTÁSIDEJŰ app (`strumsight_app.dart:33-34`,
`SsLightTheme.data()`/`SsDarkTheme.data()`) VALÓBAN hordozza a
kiterjesztéseket — a brief R8 feltétele futásidőben IGAZ. Ami hamis, az a
teszt-harnesseké (golden `AppTheme.dark()`, csupasz `MaterialApp()` a
widget-tesztekben). A burkoló megtartásának döntése változatlan (indokolt),
csak az indoklás lett pontosítva.

**m2 (NOTE-szintű, nincs kódváltozás) — az `achievement_detail` scroll-
javítását egyetlen (nem kötelező `2.5`) cella őrzi.** Tudatosan elfogadva:
a `2.0/en`, `2.0/hu`, `2.5/en` cellák a fix nélkül is zöldek maradnak (a
tartalom rövidebb, mint a `_hidden`/`_notFound` állapotoké), csak a `2.5/hu`
bukik — ez a meglévő, committolt, futó cella; nem gyengítve, nem törölve.

**Gate.** `tools/round-gate.sh` a brief §4 pontos 13 tesztútvonalával: mind
a 18 lépés (`format`, `analyze`, 13×`test`, `architecture`, `secrets`,
`l10n`) ZÖLD, csonkítatlan futással.

**Golden.** `tools/golden-x86.sh record test/ui/goldens/e13_r32_screens_golden_test.dart`
mind a 10 PNG-t (5 képernyő × 2 skála) újra felvette x86-on — a `git status`/
`git diff` a `test/ui/goldens/goldens/` alatt UTÁNA üres, azaz mind a 10 PNG
BÁJTRA azonos maradt a felvétel előtti állapottal (a hub 2 PNG-je is). Ez nem
hiba: egyik golden-fixture sem pinneli azt az állapotot, amit a B1/M2/M3
javítások érintettek (`quests` fixture nem-üres; `reward_inbox` fixture
egyetlen, MINDIG `seen=false` eleme — az unseen ág színe a fix előtt/után
azonos, mert korábban is `colors.surface`-t (a `surfaceRaised`-del
megegyező értéket) kapta; `streak_detail` fixture `reason: grace`, a CTA
`broken`-re kapuzott — lásd N2 a review-ban).
