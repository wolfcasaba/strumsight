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

## 11. Review — a Claude tölti ki
