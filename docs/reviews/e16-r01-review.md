# E16-R01 review — Gamification kompozíciós réteg (ADR 0496)

- **Reviewer:** Claude (Opus 5) orchestrátor, read-only (ADR 0055)
- **Implementer:** `sonnet-impl`, HEAD `8bc5cc95`, fa tiszta, `scope_audit=ok`
  (`scope_audit_changed=8`, mind az `allowed_paths`-on)
- **Dátum:** 2026-09-03
- **Módszer:** orchestrátor saját diff-olvasása + két kötelező ügynök
  (`flutter-reviewer`, `flutter-devil-advocate` — a brief `risk = "high"`
  előírása). A két ügynök egymástól függetlenül futott; a lenti leletek a
  KONVERGÁLÓ halmaz, mindegyik fájl:sor bizonyítékkal újraellenőrizve.

## VÉGSŐ DÖNTÉS: CHANGES REQUESTED — 3 BLOCKER, 3 MAJOR, 5 MINOR

A kör érdemi része megvan: a három privát provider és a beégetett `LevelCurve`
eltűnt a routerből, a kompozíció a feature-ben él, a barrel exportál, a nyolc
`TODO(E08-R30)` markerből 0 maradt, a `LevelDetailScreen` végre elérhető, és az
A4 (nincs párhuzamos XP-számítás, kétszeri olvasás nem duplázik) valódi,
erős cellával mért. A leletek NEM ezt vonják vissza — hanem azt, hogy a kör
SAJÁT központi szabálya (ADR 0496 §2: placeholder-literál tilos, a hiány
explicit) három helyen nem teljesül, és egy helyen új, felhasználót érintő
hibát vezet be.

---

## BLOCKER

### B1 — `?? const <String, AchievementProgress>{}` a routerben: a NEM MÉRT üres map

`lib/app/routing/app_router.dart:645` és `:664`

```dart
ref.watch(achievementProgressProvider).value ?? const <String, AchievementProgress>{}
```

Az ADR 0496 §2 pontosan erre való: az üres map csak akkor megengedett, ha a
provider ezt **MÉRTE** (a ledger nem tartalmaz receiptet) — nem azért, mert a
bekötés meg sem próbálta. Az `achievementProgressProvider` `FutureProvider`
(`gamification_providers.dart:219`), tehát az `AsyncValue.value` **loading ÉS
error** esetén is `null`:

- **minden első frame** „egyetlen kitűző sincs feloldva" állapotot renderel;
- bármely dobás a `rebuild` alatt (`achievement_evaluator.dart` `StateError`,
  `local_reward_ledger_repository.dart:60-62` `ArgumentError` ismeretlen
  kurzorra) **tartósan** „0 kitűző"-t mutat, holott a receiptek a ledgerben
  vannak — ez szó szerint a brief §9 #1 kockázata.

Ráadásul a pre-flight által placeholderként SZÁMOLT
`progressByAchievement: const {}` (kétszer) **szövegszerűen is a fán maradt**,
tehát az A2 betűje sem teljesül.

**Feloldás az engedélyezett fájlokon belül:** a router `AsyncValue`-t kezeljen
(`when`/`maybeWhen`) — loading és error NEM eshet egybe a mért üressel; error
ágon logolj (`appLoggerProvider`), és a képernyő a saját üres-állapotát kapja,
ne a „nincs adat"-tal azonos csendet.

### B2 — A Quests-útvonal 100%-ban placeholder-literál; se provider, se backlog

`lib/app/routing/app_router.dart:680-683`

```dart
dailyChallenge: null,
dailyChallengeAvailable: false,
dailyQuests: const <QuestViewProjection>[],
weeklyQuests: const <QuestViewProjection>[],
```

Az A2 szó szerint tiltja a `null` / üres-kollekció literált a routerben, a
brief §3 pedig névvel írta elő a *quest-providereket*. A hiányt itt semmilyen
típus nem hordozza, és a `docs/ui/legacy-backlog.md` új §6 szakasza **csak
hármat** tartalmaz (R3 #1/#6/#7) — a quest-felületre nincs datált, gazdás
bejegyzés. Így az ADR 0496 §5 („nem eltüntetve, hanem DATÁLT backlog-tétel")
is sérül.

**Feloldás:** `questBoardProvider` (a hiányt TÍPUSBAN hordozó alak, a
`GamificationDerivedCount` mintájára) + router-átadás, **és** a negyedik
backlog-bejegyzés a quest-forrás hiányáról. Új quest-üzleti logika továbbra is
tilos — a provider a hiányt jelenti, nem generál questet.

### B3 — Beégetett ANGOL felhasználói szöveg a kompozíciós rétegben, nyersen renderelve

`lib/features/gamification/application/gamification_providers.dart:270` és
`:287-293`

```dart
titleKey: _rewardTitleFor(kind),   // 'Achievement unlocked' | 'Quest completed' | …
bodyKey: '+${entry.totalXp} XP',
```

A `RewardInboxScreen` ezeket **nyersen** rendereli
(`reward_inbox_screen.dart:267`, `:294`, és a szemantikában `:229-232`).
Ez a kör az, amelyik ELŐSZÖR juttat ide nem üres listát (korábban
`items: const []` volt), tehát a hiba oka a kör diffje, nem a képernyőé:
`hu` locale-ban lefordítatlan angol szöveg, `intl` nélkül formázott szám, és
az XP kétszer jelenik meg (`:294` nyers `+N XP`, `:301` már
`l10n.rewardInboxEarnedXpLabel`). Sérti a CLAUDE.md i18n-szabályát („minden
felhasználónak szóló szöveg ARB → `AppLocalizations`"), és provenance-szag is:
megjelenítendő szöveg megy `titleKey`/`bodyKey` NEVŰ mezőkbe.

**Feloldás az engedélyezett fájlokon belül:** a leképezés a router-builderbe
kerül, ahol az `AppLocalizations` rendelkezésre áll (a quests/level-detail
ágban használod is) — MEGLÉVŐ ARB-kulcsokkal. Ha nincs alkalmas kulcs, az
adott mező nem kaphat kitalált angol szöveget: akkor backlog-tétel + a
képernyő a meglévő hiány-útján marad. ARB-fájlt NEM módosítasz (tilos zóna).

---

## MAJOR

### M1 — A TÍPUSBAN hordozott hiányt SENKI nem olvassa; a hamis nulla megmaradt

`grep -rn "GamificationDerivedCount" lib/` → egyetlen fogyasztó sincs a
provider-fájlon kívül. A router csak a `.value`-t adja tovább
(`app_router.dart:604`, `:606`, `:715`), tehát a `GamificationHubScreen`
továbbra is „0 aktív quest" és „0 mastery" feliratot rendereli (a szemantikai
címkékben is), a `StreakDetailScreen` pedig 0 konzisztencia-napot. **A literál
a routerből a providerbe költözött, a felhasználói hazugság megmaradt** — az
ADR 0496 §2 célja („a képernyő ne tudjon véletlenül nullát renderelni") nem
teljesül.

Ugyanide tartozik a `latestSessionXpProvider` (`gamification_providers.dart:200`):
`ExperiencePoints.empty()` megy a `LevelDetailScreen`-re, amely a session-összeget
rendereli (`level_detail_screen.dart:150`) — a felhasználó „+0 XP"-t lát egy
olyan képernyőn, amit ÉPP EZ A KÖR tett elérhetővé, miközben a ledgerben ott a
valódi `totalXp`. Itt még a hiány-típus sincs meg.

**Feloldás (az R5 szerint, az engedélyezett fájlokon belül):** (a) a
`latestSessionXp` is a hiányt hordozó alakot kapja; (b) mind a NÉGY
kifejezhetetlen-hiány értékre (`activeQuestCount`, `masteryUnlockedCount`,
`weeklyConsistencyDays`, `latestSessionXp`) datált, gazdás backlog-bejegyzés
készül — a §0.0.A/R5 ezt kifejezetten előírta, és jelenleg egyik sincs meg.

### M2 — A bekötött olvasásoknak nincs ÍRÓJA a fán, és ezt a kör nem mondja ki

`replaceProfileSnapshot(` / `ActivityEventIngestor(` / `DailyChallengeService(`
hívási hely a `lib/`-ben: **nulla** (a saját definíciójukon kívül). A kör tehát
valós forrásra köt, de a forrást ma semmi nem tölti fel — a zöld cellák a
tesztek seedelt store-ján állnak. Ez a kör hatáskörén KÍVÜL esik (a producer
bekötése új üzleti logika lenne, §3 tiltja), **de a §10 handoffnak ki kell
mondania**, különben a kör azt állítja magáról, amit nem tud: hogy a felhasználó
mostantól valós adatot lát.

**Feloldás:** NEM implementálás — egy kimondott mondat a §10-ben és egy
backlog-bejegyzés a producer-hiányról. Scope-tágítás tilos.

### M3 — A mérce-mátrix négy sorát egyetlen cella sem váltja pirosra

| §6.1 sor | Állapot |
|---|---|
| „Provider a routerben marad, csak ÁTNEVEZVE" | **nem méri** — a cella öt konkrét RÉGI privát nevet grepel (`gamification_composition_test.dart:92-96`), bármely átnevezett privát provider átcsúszik. Alak-ellenőrzés kell (`final _\w+Provider =`). |
| „Hiányzó adatra `0` megy a képernyőnek" | **nem méri** — a cella csak a provider `available == false` mezőjét állítja, miközben a router a `.value`-t (0) adja tovább, és A3 mégis zöld (lásd M1). |
| „Quest-provider instabil" | tárgytalan/nem méri (nincs quest-provider — B2). |
| „Egy BACKLOG-tétel némán törölve" | **nem létezik** — `grep -rln "legacy-backlog" test/` a kör egyik teszt-fájljában sem ad találatot; az A5 második fele csak §10-beli kézi `grep`. |

Az **A1** bizonyítékául megjelölt `gamification_composition_test.dart` ezen
felül EGYETLEN útvonal-szintű cellát sem tartalmaz az R3 #3 (achievement-haladás),
#4 (quest-akció routing), #5 (streak-reason) és #8 (inbox-join) bekötésére —
ezek csak provider-szinten mértek, a router `onAction` switch-ére
(`app_router.dart:684-698`) sehol a fán nincs teszt.

**Feloldás:** a négy hiányzó cella pótlása a kör két teszt-fájljában, és az A1
útvonal-szintű cellái (router-szintű `pumpWidget` + a projekció megjelenése).

---

## MINOR

- **m1** — `gamification_providers.dart:238-246`: a ledger-lapozás a domain-oldali
  *nem-haladó kurzor* őr nélkül másolva (`achievement_evaluator.dart` `StateError`);
  szinkron provider-buildben (UI-szál) egy nem haladó `nextCursor` végtelen ciklus.
- **m2** — `app_router.dart:740-745`: `markGamificationInboxItemSeen` fire-and-forget
  (`onMarkSeen` `void`), a `Future` elveszik → kezeletlen aszinkron hiba, és a
  `GamificationInboxWriteReport.trimmedCount` eldobódik.
- **m3** — `app_router.dart:15` mély importtal éri el a most kivezetett réteget, nem
  a barrelen át; a `tool/check_architecture.dart` a `lib/app/**`-ot nem méri, tehát
  az ADR 0496 §1 barrel-előírását a TÉNYLEGES fogyasztón semmi nem pinneli.
- **m4** — nincs invalidálási út: a profil/streak/achievement/inbox provider mind
  keepAlive, semmi nem invalidálja gyakorlás után (az achievement- és inbox-felületre
  ez ÚJONNAN igaz).
- **m5** — `gamification_providers.dart:96-107`: a `LegacyStreakMigrator.migrate()`
  őrizetlen (romlott dokumentumon `FormatException`), és a blast radius most a hubra
  ÉS a streak-detailre is kiterjed.

---

## PASS (mérve, nem bemondva)

- A három privát provider + a beégetett `LevelCurve` eltűnt a routerből
  (`LevelDefinition(` → 0 találat a router forrásában); a réteg a feature-ben él.
- `grep -c "TODO(E08-R30)" lib/app/routing/app_router.dart` → **0**; a három
  backlog-tétel datált (`2026-09-03`), nem néma törlés.
- **A4:** nincs párhuzamos XP-számítás; a `store.writeLog isEmpty` cella valódi
  anti-dupla-írás őr; a `rebuild(history: const [])` nem ír a ledgerbe.
- **A7:** az `AppRoutes.levelDetail` regisztrálva, a hubról elérhető, és a
  `LevelDetailScreen` a VALÓS profil-projekciót kapja; a `buildR06XpComponents`
  a képernyő saját, meglévő helpere (nem kitalált komponens-lista).
- Riverpod 3 konvenciók: kézzel írt providerek, nulla codegen, `.value`
  (NEM `.valueOrNull`).
- `streakEvaluationProvider`: `activity: null` mellett a `StreakService` SAJÁT
  reason-je megy a képernyőre, és nincs hamis streak-reset.

---

## A javító kör tennivalói (prioritás szerint)

1. **B1** — a router `AsyncValue`-kezelése (loading/error ≠ mért üres) + error-log.
2. **B2** — quest-provider a hiányt hordozó típussal + negyedik backlog-tétel.
3. **B3** — a jutalom-szövegek l10n-feloldása a router-builderben (ARB-t nem írsz).
4. **M1** — `latestSessionXp` hiány-típusa + a négy kifejezhetetlen hiány datált,
   gazdás backlog-bejegyzése.
5. **M2** — a producer-hiány kimondása a §10-ben + backlog-bejegyzés (NEM implementálás).
6. **M3** — a négy hiányzó mérce-cella + A1 útvonal-szintű cellák.
7. **m1–m5** — ahol az engedélyezett fájlokon belül olcsó (m1, m2 biztosan).

A tilos zóna VÁLTOZATLAN: `presentation/**` képernyők, `domain/**`, `data/**`,
ARB-fájlok, `tools/**`, más feature-ök, `test/app/routing/app_router_test.dart`
(a párhuzamos `E15-R11` köré).
