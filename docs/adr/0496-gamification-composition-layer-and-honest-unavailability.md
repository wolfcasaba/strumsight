# ADR 0496 — A Gamification kompozíciós rétege a feature-ben él, és a nem számítható adat EXPLICIT hiány, nem hamis nulla

- **Státusz:** elfogadva (2026-09-03)
- **Kontextus:** ADR 0333 (activity outbox — kész reward-műveletet továbbít),
  ADR 0353 („hívó-adta" prezentáció: a képernyő paramétert kap, nem providert
  olvas), ADR 0123 + `docs/LESSONS.md` L90 (route-regisztrációhoz a
  kör-scope-nak a composition rootot IS birtokolnia kell), ADR 0393
  (gamifikációs kapcsolók), kör `E16-R01`
- **Döntéshozó:** Claude (Opus 5) orchestrátor, az E16-R01 pre-flight mérése alapján
- **Megjegyzés a számozásról:** a kör briefje `ADR 0490`-et jelölt előre; a
  `tools/round-slots.py reserve-adr --round E16-R01` mérése szerint a `0490` már
  FOGLALT (`0490-hotfix-path-gates-incident-binding-and-regression-obligation.md`),
  a foglaló a `0496`-ot adta ki. Az ADR ezen a számon él (ADR 0087 §1.0.1: a
  foglaló a hiteles forrás, nem az előre írt brief-fejléc).

## Kontextus — a mért hiba

Az E16-R01 pre-flight a `main @ 4ca8785f` fán a következőket **mérte**:

- `lib/features/gamification/application/` → **12** szolgáltatás, `data/` →
  4 repository + lokális implementációk; a réteg kész.
- `lib/features/gamification/` → **0** Riverpod-provider. Az egyetlen bekötés a
  ROUTERBEN él: 3 privát provider (`_gamificationRepositoryProvider`,
  `_gamificationProfileProvider`, `_streakStateProvider`, `_rewardInboxProvider`)
  és egy **beégetett négyszintes `LevelCurve`** (`app_router.dart:108-131`).
- A képernyők konstans placeholdert kapnak: `activeQuestCount: 0`,
  `masteryUnlockedCount: 0`, `progressByAchievement: const {}` (kétszer),
  `dailyChallenge: null`, `weeklyConsistencyDays: 0`, `items: const []`.
- **8** `TODO(E08-R30)` marker (`:150, :699, :715, :746, :761, :766, :780, :784`).

A pre-flight második — és a kör szempontjából DÖNTŐ — mérése az volt, hogy a
tizenkét szolgáltatás **tiszta számítási motor**: mindegyik a hívótól kapja a
bemenetét, és egyik sem olvas repositoryt. A ténylegesen PERZISZTÁLT állapot
ezzel szemben szűk (`gamification_storage_schema.dart` +
`RewardLedgerRepository`):

| Perzisztált | Mező |
|---|---|
| `GamificationProfileSnapshot` | `schemaVersion`, `totalXp` |
| `GamificationCatalogVersion` | `catalogVersion` |
| `GamificationInboxItem` | `id`, `createdAt`, `viewedAt` |
| `GamificationMigrationState` | `processedCount` |
| `RewardLedgerEntry` (page-elve) | `ledgerId`, `sourceEventId`, `createdAt`, `baseXp`, `bonusXp`, `totalXp`, `reasonCodes`, `policyVersion` |
| legacy streak | `LegacyStreakMigrator.migrate()` → `StreakState` |

Ami **NINCS** perzisztálva sehol: achievement-evidencia-történet
(`AchievementEvaluationEvidence` a fa EGYETLEN fájljában, magában az
evaluatorban fordul elő), mastery-evidencia és -progress, quest-generálási
snapshot (`DailyQuestGenerationSnapshot.plannedObjectives`,
`WeeklyQuestGenerationSnapshot.availableDays/baselineWeeklyMinutes`), valamint
a daily-challenge completion store tartalma.

Ebből következik a kör központi feszültsége: a felület egy részéhez van valós
forrás, egy részéhez **nincs**, és a hiányzó forrás megépítése ÚJ üzleti logika
lenne — ami ennek a körnek kifejezetten tilos.

## Döntés

### 1. A kompozíció a FEATURE-ben él, nem a routerben

A gamification providerek egyetlen publikus fájlba kerülnek
(`lib/features/gamification/application/gamification_providers.dart`), és a
`public.dart` barrelen keresztül vezetődnek ki. A router ezeket **olvassa**;
katalógus, szintgörbe és projekció a router fájlban nem élhet.

**NEM elfogadható gyengítés:** „egyszerűbb itt hagyni" — a beégetett
`LevelCurve` pontosan így keletkezett.

### 2. Placeholder konstans TILOS; a nem számítható adat EXPLICIT hiány

Ha egy értéket a perzisztált állapotból **nem** lehet kiszámítani, a bekötés
NEM adhat át „amíg nincs jobb" alapon hamis nullát. A megengedett kimenet a
képernyő MEGLÉVŐ hiány-szerződése (pl. `QuestsScreen.dailyChallengeAvailable:
false`, `QuestViewProjection.contentAvailable`, `GamificationHubScreen.
isLegacyEmpty`, üres lista/`SsEmptyState`-hez vezető üres kollekció), és a
hiány okát a provider **típusban** hordozza (nem `int`, hanem „nincs adat"
megkülönböztetést lehetővé tevő nullable/rekord alak), hogy a képernyő ne
tudjon véletlenül nullát renderelni.

A képernyők „hívó-adta" szerződését (ADR 0353) a kör **nem** írja át: a
képernyő-fájlok a tilos zónában maradnak. Ahol a képernyő ma nem tud „nincs
adat" állapotot kifejezni (pl. `AchievementsScreen.progressByAchievement`
kötelező, nem nullable `Map`), ott az üres map a szerződés SZERINTI „nincs
ismert haladás" érték — de csak akkor, ha a provider ezt **mérte** (a ledger
nem tartalmaz receiptet), nem pedig azért, mert a bekötés meg sem próbálta.

### 3. A jutalom-adat forrása a ledger, nem újraszámítás

Az XP, a szint és a jutalom-tételek kizárólag a MEGLÉVŐ ledger-/outbox-rétegből
(ADR 0333) és a profil-snapshotból származnak. Párhuzamos XP-számítás a
providerben tilos; kétszeri `watch` nem duplázhat.

Az achievement-haladás forrása ugyanez: a projekció az
`AchievementEvaluator` MEGLÉVŐ metódusán keresztül készül, a ledgerben tárolt
idempotens receiptekből — a provider nem implementál újra kiértékelési
szabályt, és nem ír a ledgerbe.

### 4. A route-regisztráció a kompozíciós réteg része (ADR 0123, L90)

A `LevelDetailScreen` a fán **létezik és tesztelt**
(`test/features/gamification/presentation/level_detail_screen_test.dart`), de
**nincs route-ja**, mert a `TODO(E08-R30)` szerint „a route-konstans hiányzik".
A hiányzó konstans a composition root (`lib/app/routing/app_route.dart`)
dolga — ezért az E16-R01 scope-ja ezt az EGY fájlt is birtokolja, pontosan egy
új konstans erejéig. Az L90/ADR 0123 mért tanulsága ugyanez: egy route-ot
aktiváló kör allowlistjének a composition rootot IS tartalmaznia kell,
különben a kör kényszerű H3-ba fut.

Mérve: a fán **nincs** kimerítő route-leltár-teszt (`test/app/routing/
app_router_test.dart` konkrét útvonalakat navigál, nem `AppRoutes` konstansokat
számol), ezért egy új konstans nem visz pirosra meglévő őrt — az új route saját
cellát kap.

### 5. A nem feloldható tétel nem eltüntetve, hanem DATÁLT, GAZDÁS backlog-tétel

Az a `TODO(E08-R30)`, amelynek feloldása bizonyítottan új üzleti logikát vagy
tilos zónát igényelne, nem törölhető és nem „mozgatható át" némán egy másik
fájlba: a `docs/ui/legacy-backlog.md`-be kerül, dátummal, gazdával és a mért
akadály megnevezésével. A brief §3 ezt már előírta, csak a fájlt nem sorolta
az `allowed_paths` közé — a §0.0 revízió ezt javítja (különben a szabálykövető
implementer kényszerű `stopped`-ot jelentene egy tisztán adminisztratív
lépésért).

## Következmények

- A router gamification-blokkja a feature publikus providereit olvassa; a
  3 privát provider és a beégetett `LevelCurve` megszűnik.
- A `public.dart` barrel a providerekkel bővül (architecture-teszt: a
  feature-en kívülről csak a barrelen át importálható).
- A felület egy része továbbra sem mutat quest-adatot — de ez mostantól
  **mért és kimondott** hiány (explicit „nincs adat"), nem néma nulla, és
  datált backlog-tétel tartozik hozzá.
- A `LevelDetailScreen` elérhetővé válik a hubról.
