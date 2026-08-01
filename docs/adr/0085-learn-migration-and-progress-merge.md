# ADR 0085 — Learn-migráció, V1+V2 progress-egyesítés és streak-jogosultság

**Státusz:** elfogadva (E02-R19 pre-flight, 2026-08-01).
Épít az [ADR 0068](0068-practice-domain-model-contracts.md) (`PracticeMetrics`,
`MetricValue` — `MetricAvailable`/`MetricNotApplicable`/`MetricInsufficientData`),
[ADR 0076](0076-practice-scoring-dimensions.md) (scorerek, `PracticeScoreAggregator`,
completion+overall kettős kapu), [ADR 0077](0077-practice-session-controller.md)
(`PracticeSessionController`, `PracticeSessionResult`, `PracticeSessionState`),
[ADR 0079](0079-state-driven-practice-session-shell.md) (állapotgép, capture-aktiváció),
[ADR 0082](0082-free-practice-honest-summary.md) (`FreePracticeSummary`, free-practice
pengetésszám), [ADR 0083](0083-speed-builder-and-adaptive-policy.md) és
[ADR 0084](0084-practice-history-v2-and-coaching.md) (Practice History V2,
`PracticeHistoryEntry`, idempotens perzisztencia) döntéseire. A streak-jogosultsági
predikátumot az E02-R16 vezette be (`practice_session_eligibility.dart`, szándékosan
huzalozatlanul, „a becsatolás az E02-R19 dolga").
Kör: [`docs/rounds/e02-r19-progress-and-learn-migration.md`](../rounds/e02-r19-progress-and-learn-migration.md).
SDD: [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md)
§20.3–20.6, §22.4, „Kör 19".

## Kontextus

Ez az Epic 2 egyetlen köre, amely a **shippelt** felhasználói utakhoz nyúl
(Learn, streak, daily goal, Progress). A Practice Engine V2 (R13–R18) eddig egy
flag (`practiceEngineV2Enabled`) mögött, a shippelt Learn úttól elkülönítve
épült. A V2 immár mér, tárol (Practice History V2) és coachol, de a felhasználó
által **látott** rendszerek — a Progress-dashboard, a streak és a daily goal —
még kizárólag a V1 `PracticeEntry`-logot olvassák, a Learn képernyő pedig a saját
legacy motorján (`LessonScorer`, saját `Ticker`/`Metronome`, közvetlen
`liveFrameProvider`-feliratkozás) fut.

A kör három összetartozó dolgot old meg úgy, hogy **minden változás flag mögött**
van és a **rollback a kör része, nem ígéret**:

1. **Progress-egyesítés** — a V1 és a V2 store külön marad; egy pure aggregátor
   **olvasáskor** egyesíti, hamis adat és dupla számolás nélkül.
2. **Streak + daily goal** — a streak jogosultsághoz kötött (R16 predikátuma), a
   daily goal a V2 úton kizárólag az **aktív játékidőből** számol.
3. **Learn-migráció** — a Learn képernyő a `migratedLearnEnabled` flag mögött a
   Practice Engine V2-t használja, **paritással** és **visszakapcsolhatóan**.

### Mért kiindulás (`main` @ `eeb4f6d`, pre-flight 2026-08-01 — grepelt, nem táblából)

1. **Learn képernyő:** `lib/features/learn/screens/learn_screen.dart` (839 sor),
   saját `Ticker` (49/88), `Metronome()` (50), `LessonScorer` (76, 218/248),
   közvetlen `ref.listenManual(liveFrameProvider, _onFrame)` (224/254). A
   session vége (`_finish`, 273–309): `streakProvider.notifier.recordPracticeToday()`
   (284, **jogosultsági szűrő nélkül**, csak `snap.total > 0` kapuval),
   `lessonProgressProvider.notifier.record(id, snap.accuracy)` (289–291, Easy
   módban **kihagyva**), majd V1 `PracticeEntry(source: PracticeSource.learn, …)`
   (298–306). `_pause()` (232–237) **nem** zárja a `_frameSub`-ot → a mikrofon
   feliratkozás szünetben is él (ismert, felhasználó-látható rés, HANDOFF §6.4).
2. **Legacy pass/csillag:** `LessonProgress.stars(accuracy)` és
   `isPassed(accuracy)` `passThreshold = 0.7`-tel
   (`lib/features/learn/model/lesson_progress.dart`): 3★ ≥0.90, 2★ ≥0.80,
   1★ ≥0.70, pass = `accuracy >= 0.70`.
3. **V2 kettős kapu:** `pass = completionPerMille >= completionThresholdPercent*10
   && overallPerMille >= overallThresholdPercent*10`
   (`practice_score_aggregator.dart:267`); alapértelmezett küszöbök 85 / 70
   (`scoring_profile.dart`). Ez **más politika**, mint a legacy pass. (A
   speed-builder `0.95`/`0.85` promóciós kapu — `speed_builder_engine.dart:12–13`
   — **nem** ez, ne keverd össze.)
4. **Streak-jogosultsági predikátum (R16, huzalozatlan):**
   `practice_session_eligibility.dart` — `isEligible(PracticeSessionEligibilityInput)`
   = `activeDuration >= 20 s || resolvedRequiredTargets >= 4 ||
   freePracticeStrums >= 8` (mind `>=`). A `streak_provider.recordPracticeToday`
   ma **csak** opcionális `DateTime? now`-t vesz, jogosultsági bemenetet nem.
5. **Aktív játékidő:** `PracticeSessionState.playingElapsed` (Duration), amely a
   reducerben **kizárólag `running` alatt** nő (`practice_session_reducer.dart:655`).
   Count-in / pause / setup / result nem növeli. A free-practice pengetésszám a
   `FreePracticeSummary`-ban él (R16/ADR 0082).
6. **Capture-tábla:** `practiceCaptureActiveByStatus`
   (`practice_observation_activation.dart`) — capture **csak** `countIn` és
   `running` alatt `true`; `paused` (és minden más) `false`. A controller
   forrásigazsága ez (`practice_session_controller.dart:407`).
7. **Progress/daily goal:** `PracticeStats(List<PracticeEntry>)` getterei
   (`practice_stats.dart`): `totalSessions`, `totalSeconds`, `totalStrokes`,
   `daysPracticed`, `secondsForDay(day)`. A daily goal-gyűrű a
   `progress_screen.dart:107–108` szerint `stats.secondsForDay(today)` vs.
   `dailyGoalProvider` (percben). A `dailyGoalProvider` **csak a célt** tárolja,
   a teljesítést a `PracticeStats` számolja.
8. **V1 modell:** `PracticeEntry({day, source, seconds, strokes, chords,
   directionAccuracy?})` (`practice_entry.dart`) — `directionAccuracy` **nullable**.
9. **`PracticeSource` névütközés:** a `progress` feature enumja
   `{live, analyze, learn}` (`.name`-mel perzisztálva); a `practice` domainé
   `{builtin, lesson, song, analyze, setlist, dailyChallenge, userCreated,
   futureAi}` (mind stabil `.code`-dal). **Két külön típus.**
10. **V2 history dedup-kulcs:** a `PracticeHistoryEntry` **`id`** mezője (ADR 0084
    §4, „Session ID — the dedup key", = `PracticeSessionResult.id`). A perzisztens
    store már idempotens erre. **Nincs** külön `sessionId` nevű mező — az
    aggregátor azonosság-szabálya (A3) erre az `id`-re épül.
11. **Flag:** `migratedLearnEnabled` minden környezetben `false`
    (`feature_flags.dart`), és az `AppConfig` validálja, hogy csak
    `practiceEngineV2Enabled` mellett lehet igaz (`app_config.dart:115`).

## Döntés (NEM tárgyalható — a kör kötött korlátai)

1. **Két forrás, egy olvasó.** A V1 (`PracticeEntry`) és a V2
   (`PracticeHistoryEntry`) külön store marad; az aggregátor **olvasáskor**
   egyesít. **Egyirányú adatmigráció ebben a körben nincs**, a V1
   `ss.progress.practice_log` **bájtra érintetlen** (olvasás/írás formátuma
   változatlan).
2. **A V1 rekord nem kap kitalált értéket.** Nincs V1-ből származtatott rhythm-,
   chord- vagy overall-score; a `directionAccuracy` **csak ott** elérhető, ahol a
   V1 rekord tényleg tartalmazza (`!= null`). Minden más dimenzió →
   `MetricNotApplicable` / `MetricInsufficientData`, sosem `0`.
3. **A V1 `PracticeSource` nevei nem nevezhetők át** (SDD §20.3) — a perzisztált
   kódok stabilak; a V1 rekordok a **saját** forrás-kódjukkal jelennek meg, nem
   „ismeretlen"-ként.
4. **A streak jogosultsághoz kötött** (R16 predikátuma, SDD §20.5): a rögzítés
   feltétele `activeDuration >= 20 s || resolvedRequiredTargets >= 4 ||
   freePracticeStrums >= 8`. A napi frissítés **idempotens** marad (a
   `StreakLogic.applyPractice` viselkedése változatlan): ugyanazon a napon a
   második (akár jogosult) session **nem** növel tovább.
5. **A daily goal aktív időből számol** (SDD §20.4, §12.2): a V2 úton **kizárólag**
   a `playingElapsed` — count-in, pause, setup és result **nem** számít. A V1
   rekordok `seconds` mezője **változatlanul** beszámít (kompatibilitás).
6. **Easy mód nem írja felül a teljes eredményt** (SDD §22.4): az Easy futásból
   származó csillag/pontszám **nem csökkentheti** a korábbi teljes futás
   eredményét, és az Easy használata **nem** csökkenti a streaket.
7. **A legacy pass- és csillag-szemantika a Learn úton megmarad.** A migrált Learn
   a **V2 metrikákból** képzi a legacy `accuracy`-nek megfelelő értéket (a
   direction-dimenzió, ADR 0076 A7 szerint), és **arra** alkalmazza a meglévő
   `LessonProgress.stars` / `isPassed` szabályt (`passThreshold = 0.7`). A V2
   kettős kapuja (completion+overall) a Learn úton **nem** dönt csillagról.
8. **A rollback működik.** `migratedLearnEnabled = false` → a mai Learn út
   **egyetlen sorral se** változik viselkedésben; a V2 alatt keletkezett
   history-rekordok megmaradnak, a V1 log és a lecke-progress sértetlen.
9. **A kör nem kapcsol be semmit.** Minden flag alapértéke változatlan; a
   `migratedLearnEnabled` bekapcsolása külön, user-döntéses rollout-lépés (Kör 20).

## Következmények

- **Pozitív:** a V2 mérés és tárolás beér a felhasználó-látott rendszerekbe hamis
  történelem nélkül; a streak és a daily goal a valós aktív játékot jutalmazza; a
  Learn-migráció paritással és bizonyított rollbackkel, kockázat nélkül élesíthető
  egy későbbi körben.
- **Ár / kockázat:** a rollout hetében a V1 és a V2 egyszerre írhat ugyanarról a
  sessionről — az aggregátor azonosság-szabálya (Döntés 1/10, A3) ezt méri; a
  daily goal aktív-idő számítása a legkönnyebb csendes túlszámolási pont (A5); a
  `PracticeSource` névütközés import-hibát rejt (Döntés 3).
- **Visszafordíthatóság:** teljes — a flag OFF ág a mai kód, a V1 store
  változatlan, a V2 store additív. A bekapcsolás nem ennek a körnek a döntése.

## Alternatívák (elvetve)

- **Egyirányú V1→V2 adatmigráció most.** Elvetve: visszafordíthatatlan, és a
  rollout előtt a paritás nincs bizonyítva. A „két forrás, egy olvasó" additív és
  rollbackelhető.
- **A legacy pass-szemantika lecserélése a V2 kettős kapujára a Learn úton.**
  Elvetve: a Learn-paritás (A7) megkövetelné a felhasználó-látott
  csillag/pass viselkedés megőrzését; a politika-váltás külön, szándékos döntés
  lenne, nem a migráció mellékhatása (Döntés 7).
- **A streak jogosultság nélkül hagyása.** Elvetve: a 20 s alatti / üres session
  ma is streaket rögzít — ez a retenciós mechanika hitelességét rontja (SDD §20.5).
