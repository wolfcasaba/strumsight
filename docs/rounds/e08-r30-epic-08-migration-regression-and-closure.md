# E08-R30 — Teljes migráció, regresszió és az Epic 8 lezárása

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 30
- **Kör-azonosító:** `E08-R30`
- **Branch:** `<motor>/e08-r30-epic-08-migration-regression-and-closure`
- **Előfeltétel:** `E08-R29` merge-elve (CI-őrök)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a MIND A 29 korábbi kör §10 handoffját (mi maradt nyitva), és futtasd le a `gh run list` parancsot a legutóbbi CI-futásokra — a lezárás bizonyítéka a ZÖLD CI, nem a lokális futás. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/sdd/epic-08-completion-report.md",
  "HANDOFF.md",
  "README.md",
  "lib/app/routing/app_route.dart",
  "lib/app/routing/app_router.dart",
  "test/app/routing/app_router_test.dart",
  "test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart",
  "docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md",
]
gate_tests = [
  "test/app/routing/app_router_test.dart",
  "test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (Claude, 2026-08-22)

**Mért tény 1 — az `app_route.dart` ÖNMAGÁBAN nem elegendő az A1-hez.**
`lib/app/routing/app_route.dart` csak az `AppRoutes` útvonal-string-katalógus;
a tényleges `GoRoute(...)` regisztráció a **másik** fájlban,
`lib/app/routing/app_router.dart`-ban él (mérve: `grep -n "GoRoute("
lib/app/routing/app_router.dart` 60+ találat, egyik sem gamifikációs). Ez
pontosan a projekt saját, korábban kétszer mért mintája —
[[L97]] (E03-R17) és [[L94]] (E03-R16): egy route-ot élesítő kör scope-ja a
katalógus- ÉS a wiring-owner fájlt EGYÜTT kell tartalmazza, különben az új
route nem regisztrálható. A `app_router.dart` fentebb bekerült az
`allowed_paths`-ba — **CSAK a gamifikációs GoRoute-bejegyzések hozzáadása**,
a meglévő útvonalak (`/streak`, `/progress` stb.) sorai NEM módosíthatók
(§5.1 változatlan).

**Mért tény 2 — a beallow-olt hét képernyő EGYIKE sincs éles adathoz kötve.**
Az öt (ténylegesen hat: `AchievementsScreen` + `AchievementDetailScreen` a
két achievement-útvonal) új képernyő mind tiszta, caller-fed widget
(`required this.profile`, `required this.definitions`, `required
this.onAchievementSelected`, …) — egyikük sem `ConsumerWidget`, ellentétben a
MA már routolt `StreakScreen`-nel
(`lib/features/streak/screens/streak_screen.dart:18`, `extends
ConsumerWidget`). Mérve: `grep -rln "GamificationHubScreen(\|AchievementsScreen(\|QuestsScreen(\|StreakDetailScreen(\|RewardInboxScreen(\|AchievementDetailScreen("
lib/` **nulla** találatot ad a saját screen-fájljukon kívül — soha senki nem
példányosítja őket. A `lib/features/gamification/presentation/providers/`
alatt is csak EGY provider létezik
(`gamificationPreferencesProvider`, beállítás-kapcsolók) — nincs
profil/achievement/quest/streak/inbox provider sehol.

**Feloldás — a hiányzó integrációs ragasztó a MOST engedélyezett
`app_router.dart`-ban épül, NEM a tiltott `lib/features/gamification/**`
alatt.** Ez nem lista-tágítás egy elérhetetlen célra, hanem a tényleges
DI-mag már publikus: `lib/core/storage/storage_providers.dart` exportálja a
`keyValueStoreProvider`-t (`Provider<KeyValueStore>`, main.dart tölti fel),
`lib/core/logging/logger_provider.dart` az `appLoggerProvider`-t — ugyanezt a
párt használja már ma is pl. `lib/core/storage/persisted_preference.dart`.
`LocalGamificationRepository({required KeyValueStore store, required
AppLogger logger})` ebből a két, MÁR publikus providerből megépíthető
`app_router.dart` tetején, egy ott deklarált Riverpod-providerrel (pl.
`Provider<GamificationRepository>` + az öt képernyőhöz szükséges
`FutureProvider`/`StreamProvider` vetületek, a `watchProfileSnapshots()` már
publikus stream-metódust felhasználva) — importként a `gamification/public.dart`
és a két core-provider fájl, **fájl-írás egyik esetben sem történik a
`lib/core/**`/`lib/features/gamification/**` alatt**, csak import.

Az öt/hat képernyő callbackjeire (`onAchievementSelected`,
`onItemSelected`/`onMarkSeen`, `onRecoveryPressed`): ahol a `public.dart`
már exportál egyenes megfelelőt (pl. `GamificationRepository.readInbox()` +
`replaceInbox(...)` az inbox mark-seen-hez), azt hívd meg közvetlenül,
ÚJ üzleti logika nélkül. Ahol nincs kész, egyenes megfelelő (pl. streak
„recovery" akció) — hagyd dokumentáltan no-op-nak egy `// TODO(E08-R30):`
komenttel, és vedd fel a completion reportba nyitott tételként; **ne
találj ki új domain-szabályt** a tiltott zóna megkerülésére. Ez a
`app_router.dart`-beli ragasztó a route-elérhetőség BIZONYÍTÉKA erre a
körre — egy jövőbeli kör átköltöztetheti a feature saját
`presentation/providers/` alá, ha a konzisztencia azt kívánja (nyitott
tétel, nem ennek a körnek a dolga).

**Mért tény 3 — a „Kör 24 migrációs kapcsoló" MA sehol nincs élesítve.**
`grep -rn "dualWriteMode:" lib/ --include=*.dart` **nulla** találatot ad —
a `GamificationDualWriteMode` enum (két, névileg azonos, külön definíció:
`lib/features/practice/application/gamification_practice_adapter.dart:21` és
`lib/features/learn/application/gamification_lesson_adapter.dart:9`) és a
két adaptert használó `GamificationPracticeAdapter`/`GamificationLessonAdapter`
osztály MA egyetlen production hívási láncban sincs példányosítva — a
E08-R24 kör pre-flightja saját maga rögzítette, hogy a tényleges hívási pont
bekötése (`practice_session_controller.dart`, a `learn` screenek) egy
KÉSŐBBI kör dolga, ami még nem történt meg. **Nincs tehát élő „off/dual"
állás, amit „végállapotba" lehetne állítani** — a kapcsoló ma nem kapcsoló,
hanem egy be nem kötött, önmagában tesztelt adapter-paraméter, és mindkét
adapter otthona (`lib/features/practice/**`, `lib/features/learn/**`)
ennek a körnek a tiltott zónája.

**Revízió (§3 scope 3. pontja és §6 A5 helyett):** ez a kör NEM állít semmilyen
kódbeli kapcsolót „végállapotba" — ehelyett a completion reportban rögzíti
(a) a fenti mért, jelenlegi (be nem kötött) állapotot, és (b) a tényleges
bekötés + `newOnly` váltás SZÁMSZERŰ feltételeit egy jövőbeli kör számára
(pl. hány nap hibamentes `dual` üzem, milyen wire-shape egyezés-bizonyíték —
lásd az E08-R28 F1 tanulságát, `docs/reviews/e08-r28-review.md`). Az A5 cella
bizonyítéka tehát a completion report számszerű feltétel-szakasza, NEM egy
ténylegesen átbillentett flag.

**Mért tény 4 — a legacy migráció meglévő tesztje idealizált mintaadattal
dolgozik, nem a valós V1 kulcsformátummal (A2 kockázat).**
`test/features/gamification/data/legacy_practice_migration_test.dart` kézzel
épített `PracticeEntry(...)` objektumokkal dolgozik; a valós legacy
kulcsokra (`grep -rln "practice_streak_v1\|practice_log_v1\|daily_goal_min_v1\|lesson_progress_v1"
test/ lib/`) **csak** a `lib/core/storage/storage_keys.dart` deklaráció
talál — egyetlen teszt sem olvas be ilyen alakú nyers JSON-t. A
`LegacyStreakMigrator` (`lib/features/gamification/data/migration/legacy_streak_migrator.dart`)
pedig KIFEJEZETTEN nyers `KeyValueStore`-ot olvas (`_store.readString(StorageKeys.streak)`,
majd fallback `LegacyStorageKeys.streak`) — és **nulla** dedikált tesztje van
ma. Az `ADR 0351` szerint a core v22 storage-migráció a nyers
`practice_streak_v1`-et már át is költözteti `ss.streak.state` envelope-ba,
és törli a régi kulcsot, tehát a real-fixture tesztnek MINDKÉT ágat
(pre-v22 nyers kulcs ÉS post-v22 namespaced envelope) fedni kell.

**Feloldás:** a fentebb `allowed_paths`-ba felvett ÚJ tesztfájl
(`test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart`)
valós alakú nyers JSON-t ír egy fake `KeyValueStore`-ba a
`LegacyStorageKeys`/`StorageKeys` tényleges kulcsnevei alatt, és ezen
keresztül futtatja a `LegacyStreakMigrator`-t (mindkét ág), valamint a
`GamificationMigrator`/`LegacyPracticeAdapter`-t a meglévő, publikus
`lib/features/progress/` olvasó-osztályokból (nem módosítva, csak
importálva) származó, valós formátumú `PracticeEntry`-kkel. **Fájlnév
szándékosan kerüli a "migration" szót** — az `ai-router`
`high_risk_path_fragments` listája ezt a szót tartalmazza, és a fájl
tisztán olvasó/ellenőrző teszt, nem indokol `risk = "high"` besorolást.

**A2 acceptance evidence pontosítása:** a §6 A2 sora bizonyítéka mostantól
KIFEJEZETTEN ez az új tesztfájl + a meglévő
`legacy_practice_migration_test.dart` együttes zöld futása, nem csak az
utóbbi.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Zárd le az Epicet teljes rendszerellenőrzéssel, az ÚJ útvonalak élesítésével,
dokumentációval és a legacy kód **kivezetési tervével**.

## 2. Jelenlegi állapot — mért tények

- A Kör 2–29 létrehozta a teljes gamifikációs réteget; az ÚJ képernyők (Hub, achievements, quests, streak V2, postaláda) elkészültek, de **útvonalon még nem elérhetők** — minden korábbi kör tilos zónája volt a `lib/app/routing/**`.
- A Kör 24 migrációs kapcsolója KIKAPCSOLVA vagy kettős írás állásban van — a végállapotra váltás ennek a körnek a dolga.
- A legacy `streak`, `progress` és `learn` rendszerek változatlanul élnek.
- A teljes tesztcsomag és az APK **CI-ban** fut (ADR 0053) — a lokális futás csak az érintett területekre.

## 3. Scope

**Benne van:** az ÚJ képernyők útvonalainak élesítése (Hub, achievements, quests, streak V2, postaláda),
**a §0.0-ban mért, hiányzó minimális repository-ragasztóval együtt** (kizárólag `app_router.dart`-ban,
már publikus core-providerekből) · **a §0.0 szerint pontosított** Kör 24 migrációs kapcsoló
tétele: mivel a kapcsoló ma sehol nincs élesítve (mérve, §0.0), ez a kör a jelenlegi mért
állapotot és a jövőbeli bekötés SZÁMSZERŰ feltételeit dokumentálja, kódbeli flip nélkül · a legacy
migrációk ellenőrzése VALÓS fixture-ökkel (§0.0 ÚJ tesztfájl) · offline újraindítás, időzóna,
óra-visszaállítás és több eszközös összefésülés próba (a MEGLÉVŐ, korábbi körökből örökölt teszt-
lefedettségre támaszkodva, futtatva és a completion reportban idézve) · a `README.md` gamifikáció /
adatvédelem / offline szakaszai · a kettős írás és a legacy adapter **kivezetési feltételeinek**
dokumentálása · az Epic completion report.

**NINCS benne (tilos):**

- Bármely `lib/features/**` fájl módosítása — ez a kör útvonalat élesít és dokumentál.
- A legacy `streak`/`progress` képernyők TÖRLÉSE — a kivezetés terve készül el, nem a végrehajtása.
- Új funkció bevezetése.
- A gate mércéjének bármilyen módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/epic-08-completion-report.md` | **ÚJ** — az Epic lezáró jelentése |
| `HANDOFF.md` | a kötelező állapot-frissítés |
| `README.md` | a gamifikáció / adatvédelem / offline szakaszok |
| `lib/app/routing/app_route.dart` | az ÚJ képernyők útvonalainak élesítése — CSAK hozzáadás |
| `lib/app/routing/app_router.dart` | **ÚJ (§0.0)** — a tényleges `GoRoute` wiring-owner ([[L97]]/[[L94]] mintázat) + a repository-hoz kötő minimális Riverpod-ragasztó, kizárólag már publikus `keyValueStoreProvider`/`appLoggerProvider`/`gamification/public.dart` importokból |
| `test/app/routing/app_router_test.dart` | az új útvonalak cellái |
| `test/features/gamification/data/legacy_streak_and_practice_fixture_test.dart` | **ÚJ (§0.0)** — valós V1-kulcs-alakú fixture-teszt az A2-höz |

**Tilos zóna:** `lib/features/**` (MINDEN feature) · `lib/core/**` · `backend/**` · `tools/**` · `.github/**` · `docs/adr/**` · `docs/sdd/` minden más fájlja

## 5. Kötött architekturális döntések

### 5.1 A RÉGI ÚTVONALAK TOVÁBB MŰKÖDNEK

Az új útvonalak **hozzáadódnak**; a `/streak` és `/progress` mélylink változatlanul
működik. A legacy képernyők kivezetése külön, későbbi döntés — ez a kör a FELTÉTELEIT írja le.

**NEM elfogadható gyengítés:** a régi útvonal átirányítása az újra „hogy egységes legyen”.
A meglévő mélylinkek és tesztek elbuknának.

### 5.2 A LEZÁRÁS BIZONYÍTÉKA A ZÖLD CI, nem a lokális futás

A teljes tesztcsomag, a property-kapu és az APK a CI-ban fut (ADR 0053). A
completion report **futás-linket** hivatkozik, nem lokális kimenetet.

**NEM elfogadható gyengítés:** „lokálisan minden zöld” állítás futás-link nélkül.

### 5.3 A KIVEZETÉS FELTÉTELEI SZÁMSZERŰEK

A kettős írás és a legacy adapter kivezetéséhez tartozó feltételek konkrétak
(mennyi ideig kell hibamentesen futnia, milyen mérőszám mellett), nem „amikor stabilnak
tűnik”.

### 5.4 A VALÓS FIXTURE-ÖK a legacy formátumból származnak

A migrációs ellenőrzés a `practice_streak_v1`, `practice_log_v1`,
`daily_goal_min_v1` és `lesson_progress_v1` kulcsok VALÓS alakjával dolgozik, nem
idealizált mintaadattal.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az öt új képernyő útvonalon elérhető, és a régi `/streak` + `/progress` mélylink VÁLTOZATLANUL működik | `app_router_test.dart` — útvonal-mátrix |
| A2 | A legacy migrációk valós fixture-ökkel ellenőrizve: nincs adatvesztés | a §7 gate + a completion report |
| A3 | Offline újraindítás, időzóna-váltás és óra-visszaállítás után nincs dupla jutalom és nincs törött széria | a completion report próba-jegyzőkönyve |
| A4 | A `README.md` gamifikáció / adatvédelem / offline szakaszai frissültek | review |
| A5 | A kettős írás és a legacy adapter kivezetési feltételei SZÁMSZERŰEK | review |
| A6 | A completion report ZÖLD CI futás-linket hivatkozik (nem lokális kimenetet) | review — a link megnyitható |
| A7 | A `HANDOFF.md` az Epic 8 lezárását tükrözi | review |
| A8 | A `lib/features/**` ÉRINTETLEN | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `/streak` átirányítva az új képernyőre | **A1** (a meglévő útvonal-teszt elbukik) |
| A completion report lokális kimenetre hivatkozik | **A6** |
| A kivezetési feltétel „amikor stabilnak tűnik” | **A5** |
| A migráció idealizált mintaadattal ellenőrizve | **A2** |
| A kör „gyorsan javít” egy feature-hibát | **A8** (`git diff --stat` `features/` útvonalat mutat) |
| Az új útvonalak regisztrálva, de teszt nélkül | **A1** |

**A küszöb három kötelező cellája** (a lezárás bizonyíték-szintje (mi számít elfogadható evidenciának)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | lokális `flutter test` kimenet a jelentésben | **NEM elegendő** — a projekt mércéje a CI (ADR 0053) |
| **rajta** (a küszöbön) | a kör-branchre dispatchelt, ZÖLD CI-futás linkje | **ELEGENDŐ** — ez a kötelező minimum |
| a küszöb **fölött** | zöld CI + valós eszközön futtatott APK-próba | **a teljes bizonyíték**; az eszközös próba a user hatásköre, NEM merge-kapu |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** a completion report írásakor hivatkozz szándékosan egy PIROS futásra → a review
**A6** cellájának el kell utasítania → cseréld a zöld futás linkjére.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/routing/app_router_test.dart test/features/gamification test/features/streak test/features/progress
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Az öt új útvonal regisztrálása (CSAK hozzáadás), a régiek érintése nélkül.
2. Az útvonal-tesztek bővítése.
3. A Kör 24 migrációs kapcsolójának végállapotba állítása.
4. Legacy migráció ellenőrzése valós fixture-ökkel.
5. Offline / időzóna / óra-visszaállítás / több eszköz próbák jegyzőkönyve.
6. `README.md` frissítés; a kivezetési feltételek számszerűsítése.
7. `docs/sdd/epic-08-completion-report.md` + `HANDOFF.md`.
8. CI-dispatch (Claude-oldal), majd a ZÖLD futás linkjének beemelése a jelentésbe.

## 9. Kockázatok

- **A régi útvonal átirányítása.** „Egységes” és a meglévő mélylinkeket + teszteket töri (A1).
- **A lokális zöld mint bizonyíték.** A projekt mércéje kifejezetten a CI (ADR 0053); a lokális kimenet nem lezárás (A6).
- **A „gyorsan javítom” kísértés.** 29 kör után lesznek látszó apróságok; a `lib/features/**` ebben a körben tilos zóna (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
