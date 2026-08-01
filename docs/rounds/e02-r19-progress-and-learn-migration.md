# E02-R19 — Progress, streak, daily goal és Learn migráció

- **Státusz:** **PLANNING** (pre-flight lezárva 2026-08-01, kód mérve: `main` @ `eeb4f6d`; előre megírva 2026-07-31 @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 19"** (+ §20.3–20.6, §22.4)
- **Branch:** `codex/e02-r19-progress-and-learn-migration`
- **Előfeltétel:** **E02-R18 merge-ölve** (V2 history — a progress-aggregáció
  forrása).
- **ADR:** **0085** — `docs/adr/0085-learn-migration-and-progress-merge.md`,
  **az orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** — ez
  a kör nyúl először a **shippelt** felhasználói utakhoz (Learn, streak,
  daily goal); a paritás és a visszakapcsolhatóság ítéletigényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra a `learn_screen.dart` teljes fájlját (839 sor) — a §2 mai
>    viselkedés-leírását frissítsd, mert ez a kör **cseréli** a motorját.
> 2. Ellenőrizd az R18 history-repositoryt és a `PracticeHistoryEntry` mezőit.
> 3. **Kérdezd meg a usert** a `migratedLearnEnabled` flag alapértékéről a
>    kör után (marad-e OFF minden környezetben) — ez rollout-döntés, nem
>    implementációs részlet.
> 4. ADR-szám ütközés ellenőrzése, majd az ADR 0085 megírása.
> 5. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 0.0 Pre-flight mérés (orchestrátor, 2026-08-01 @ `eeb4f6d`) — NEM mércelazítás

A §2 minden mért állítását grepeltem a kódból (nem táblából). **Mind
CONFIRMED**, egyetlen contradiction sem — a brief nem szorul lista-tágításra. Az
alábbi **pontos szimbólumnevek** kötelezőek az implementernek (a táblás nevek
helyett a tényleges hívási láncot mérve, L19/L20):

- **V2 dedup-kulcs = `PracticeHistoryEntry.id`**, NEM `sessionId` nevű mező (ADR
  0084 §4, „Session ID — the dedup key"; = `PracticeSessionResult.id`). Az A3
  azonosság-szabálya erre az `id`-re épül; a store már idempotens rá.
- **Streak-jogosultság: `practice_session_eligibility.dart`** —
  `isEligible(PracticeSessionEligibilityInput)` = `activeDuration >= 20 s ||
  resolvedRequiredTargets >= 4 || freePracticeStrums >= 8`. Szándékosan
  **huzalozatlan** (a doc szerint „a becsatolás az E02-R19 dolga"); a
  `streak_provider.recordPracticeToday` ma csak `DateTime? now`-t vesz.
- **Aktív idő: `PracticeSessionState.playingElapsed`** — a reducerben KIZÁRÓLAG
  `running` alatt nő (`practice_session_reducer.dart:655`). A daily goal (A5)
  ebből számol; a free-practice pengetést a `FreePracticeSummary` hordozza.
- **Capture-rés (A9): `practiceCaptureActiveByStatus`** in
  `practice_observation_activation.dart` — `paused → false` (csak `countIn`+
  `running` → true). A V2 út ezt strukturálisan örökli.
- **Legacy vs. V2 pass:** legacy `LessonProgress.isPassed = accuracy >= 0.70`;
  V2 kettős kapu `practice_score_aggregator.dart:267` (completion≥85% &&
  overall≥70%, `scoring_profile.dart`). A Learn út a **legacy** szemantikát
  tartja (Döntés 7); a speed-builder `0.95/0.85` promóciós kapu NEM ez.
- **`PracticeSource` névütközés:** `progress` `{live, analyze, learn}` vs.
  `practice` domain `{builtin, lesson, song, analyze, setlist, dailyChallenge,
  userCreated, futureAi}` — két külön típus; a V1 Learn-log a **progress**-enum
  `learn` kódját írja.
- **Korpusz (A7):** `Lessons.all` = **16** lecke (`lesson.dart:321`) +
  `Lessons.firstWin` (`lesson.dart:146`, nincs az `all`-ban) = **17**.

Az ADR 0085 (§5 kötött döntések forrása) ezzel a mért kontextussal elfogadva.

## 1. Cél

Az új motor **beér a meglévő rendszerekbe**:

1. **Progress** — a V1 (`PracticeEntry`) és a V2 (`PracticeHistoryEntry`)
   együtt olvasható, hamis adat nélkül;
2. **Streak és daily goal** — jogosultsági szabály (R16 predikátuma) + aktív
   időből számolt napi cél, idempotens napi frissítéssel;
3. **Learn migráció** — a Learn képernyő a `migratedLearnEnabled` flag mögött a
   Practice Engine V2-t használja, **paritással** és **visszakapcsolhatóan**.

Ez az epic egyetlen köre, amely a **shippelt** felhasználói utakat módosítja.
Ezért minden változás flag mögött van, és a rollback a kör része, nem ígéret.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **Learn képernyő:** `lib/features/learn/screens/learn_screen.dart` (839 sor),
  saját `Ticker`-rel, saját `Metronome()`-mal, `LessonScorer`-rel, és a
  `liveFrameProvider`-re való közvetlen feliratkozással (44–254. sor). A
  session végén mérve: `streakProvider.notifier.recordPracticeToday()` (284.
  sor), `PracticeStats(ref.read(practiceLogProvider))` (312. sor).
  **Ismert, felhasználó-látható hiba:** a `_pause()` (232. sor) nem állítja le
  a mikrofon-fogyasztást (HANDOFF §6.4) — a V2 úton ezt a
  `practiceCaptureActiveByStatus` tábla szerkezetileg zárja.
- **Csillagok és pass:** `LessonProgress.stars(accuracy)` és
  `LessonProgress.isPassed(accuracy)` `passThreshold = 0.7`-tel
  (`lib/features/learn/model/lesson_progress.dart`). **A legacy pass tehát
  `accuracy >= 0.70`**, míg a V2 pass a kettős kapu
  (`completion >= 0.85 && overall >= 0.70`, ADR 0076 §5.12). **A leképezést ez
  a kör dönti el** — ez a kör legfontosabb tervezési kérdése.
- **Streak:** `StreakLogic` (83 sor) — `epochDayOf`, `applyPractice`,
  `practicedToday`, `atRisk`, `isBroken`, `freezeEveryNDays = 7`,
  `maxFreezes = 3`. Jogosultsági szűrő **nincs**: ma bármely befejezett lecke
  rögzít.
- **Daily goal:** `dailyGoalProvider` (percben, `StorageKeys.dailyGoalMinutes`),
  a teljesítést a `PracticeStats` napi másodperceiből számolja.
- **Progress képernyő:** `lib/features/progress/screens/progress_screen.dart`
  — `PracticeStats(entries)` (`totalSessions`, `totalSeconds`, `totalStrokes`,
  `daysPracticed`) + `WeeklyBars` + a Wrapped share.
- **V1 modell:** `PracticeEntry(day, source, seconds, strokes, chords,
  directionAccuracy?)` — a `directionAccuracy` **nullable**, azaz a V1-ben is
  van „nincs adat" ábrázolás. ⚠ A `progress` feature `PracticeSource` enumja
  **más**, mint a practice domain azonos nevű enumja.
- **Flagek:** `migratedLearnEnabled` **minden környezetben false**
  (`feature_flags.dart:42`), és az `AppConfig` validálja, hogy csak
  `practiceEngineV2Enabled` mellett lehet igaz.
- **Meglévő Learn-tesztek, amelyek a mai viselkedést védik** (nem írhatók át a
  zöldért): `learn_screen_test.dart`, `lesson_progress_test.dart`,
  `dynamic_difficulty_test.dart`, `next_lesson_cta_test.dart`,
  `waltz_count_in_test.dart`, `wrapped_prompt_test.dart`,
  `expected_chord_hint_test.dart`, `visual_offset_test.dart`,
  `practice_log_race_test.dart`, `streak_logic_test.dart`,
  `daily_goal_provider_test.dart`.

## 3. Scope

**Benne:** a V1+V2 progress-aggregáció, a streak-jogosultság és a daily goal
aktív-idő alapú számítása, a Learn képernyő V2-re kapcsolása flag mögött, a
paritás-tesztek, és a rollback bizonyítása.

**Kívül (ebben a körben TILOS):**

- **A `migratedLearnEnabled` alapértékének bekapcsolása** — a rollout döntés a
  useré (pre-flight 3. pont), a kód mindkét állásban működik.
- A legacy `LessonScorer` **törlése vagy átírása** — a flag OFF útnak
  változatlanul működnie kell.
- Új gyakorlási mód, új UI-koncepció, Result-újratervezés.
- A V1 `PracticeEntry` **formátumának** megváltoztatása (olvasás/írás marad).
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/service/practice_progress_aggregator.dart` | **ÚJ** | pure V1+V2 összeolvasás |
| `lib/features/practice/application/practice_progress_providers.dart` | **ÚJ** | az aggregátor Riverpod-huzalozása |
| `lib/features/practice/application/practice_session_recording.dart` | **ÚJ** | use case: session vége → practice log + streak + daily goal (jogosultsággal) |
| `lib/features/progress/model/practice_stats.dart` | — | **CSAK** az aggregált forrás fogadása (a V1 mezők jelentése változatlan) |
| `lib/features/progress/screens/progress_screen.dart` | — | **CSAK** az új mérőszámok megjelenítése; a meglévő blokkok viselkedése változatlan |
| `lib/features/streak/providers/streak_provider.dart` | — | **CSAK** a jogosultsági szűrő becsatolása (idempotencia változatlan) |
| `lib/features/progress/providers/daily_goal_provider.dart` | — | **CSAK** az aktív-idő forrás |
| `lib/features/learn/screens/learn_screen.dart` | — | **CSAK** a flag-elágazás: `migratedLearnEnabled` → V2 út, egyébként a mai kód **változatlanul** |
| `lib/features/learn/providers/lesson_progress_provider.dart` | — | **CSAK** ha a V2 eredmény írása megköveteli (a stars-szemantika nem változik) |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új kulcsok mindkét nyelven |
| `test/features/practice/domain/practice_progress_aggregator_test.dart` | **ÚJ** | A1–A3 |
| `test/features/practice/application/practice_session_recording_test.dart` | **ÚJ** | A4–A6 |
| `test/features/learn/learn_migration_parity_test.dart` | **ÚJ** | A7 paritás-mátrix |
| `test/features/learn/learn_rollback_test.dart` | **ÚJ** | A8 rollback |
| `docs/rounds/e02-r19-progress-and-learn-migration.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/lesson_scorer.dart`,
`lib/features/learn/model/**`, `lib/features/learn/widgets/**`,
`lib/features/practice/domain/model/**`, `lib/app/config/**` (a flag **értéke**
nem változik), `docs/adr/**`, `.github/**`.

> **A meglévő Learn-teszteket (§2 lista) NEM írhatod át a zöldért.** Ha egy
> ilyen teszt pirosra vált, az **megállás és jelentés** — a flag OFF útnak
> viselkedésre azonosnak kell maradnia.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0085 — NEM tárgyalhatók)

1. **Két forrás, egy olvasó.** A V1 és a V2 külön store marad; az aggregátor
   **olvasáskor** egyesít. Egyirányú adatmigráció ebben a körben nincs.
2. **A V1 rekord nem kap kitalált értéket.** Nincs V1-ből származtatott rhythm-,
   chord- vagy overall-score; a `directionAccuracy` **csak ott** elérhető, ahol
   a V1 rekord tényleg tartalmazza. Minden más → `MetricNotApplicable` /
   `MetricInsufficientData`.
3. **A V1 `PracticeSource` nevei nem nevezhetők át** (SDD §20.3) — a
   perzisztált kódok stabilak.
4. **A streak jogosultsághoz kötött** (R16 predikátuma, SDD §20.5):
   `activeDuration >= 20 s || resolvedRequiredTargets >= 4 ||
   freePracticeStrums >= 8`. A napi frissítés **idempotens** marad (`StreakLogic`
   viselkedése változatlan): ugyanazon a napon a második rögzítés **nem** növel.
5. **A daily goal aktív időből számol** (SDD §20.4, §12.2): a V2 úton
   **kizárólag** a `playingElapsed` — count-in, pause, setup és result **nem**
   számít. A V1 rekordok `seconds` mezője **változatlanul** beszámít
   (kompatibilitás).
6. **Easy mód nem írja felül a teljes eredményt** (SDD §22.4): az Easy futásból
   származó csillag/pontszám **nem csökkentheti** a korábbi teljes futás
   eredményét, és az Easy használata **nem** csökkenti a streaket.
7. **A legacy pass- és csillag-szemantika a Learn úton megmarad.** A migrált
   Learn a **V2 metrikákból** képzi a legacy `accuracy`-nek megfelelő értéket
   (a direction-dimenzió, ADR 0076 A7 szerint), és **arra** alkalmazza a
   `LessonProgress.stars` / `isPassed` meglévő szabályát. A V2 kettős kapuja
   (completion+overall) a Learn úton **nem** dönt csillagról.
8. **A rollback működik.** `migratedLearnEnabled = false` → a mai Learn út
   **változatlan** viselkedéssel fut; a V2 alatt keletkezett history-rekordok
   megmaradnak, a V1 log és a lecke-progress **sértetlen**.
9. **A kör nem kapcsol be semmit.** Minden flag alapértéke változatlan; a
   bekapcsolás külön, user-döntéses lépés (Kör 20 rollout-döntés).

## 6. Acceptance criteria

### A1 — V1+V2 aggregáció: nincs kitalált adat

| Forrás | `directionAccuracy` | rhythm / chord / overall |
|---|---|---|
| V1 rekord `directionAccuracy = 0.82` | **0.82** | **`NotApplicable`** |
| V1 rekord `directionAccuracy = null` | `NotApplicable` | `NotApplicable` |
| V2 rekord teljes metrikákkal | a V2 érték | a V2 értékek |
| V2 free-practice rekord | `NotApplicable` | `NotApplicable` |

***Pirosra fogja:*** a V1 rekordoknak adott „becsült" score — ez hamis
történelmet írna a felhasználó grafikonjára.

### A2 — Összegzés-mátrix

Vegyes korpusz (3 V1 + 3 V2 rekord, ismert értékekkel):

- `totalSessions` = **6**;
- `totalSeconds` = a hat rekord összege (kiszámolt konstans);
- napi bontás: az azonos `day`/`localEpochDay` rekordok **összeadódnak**;
- mód-bontás: a V1 rekordok a **saját** forrás-kódjukkal jelennek meg, nem
  „ismeretlen"-ként.

### A3 — Ugyanaz a session nem számít kétszer

Ha egy V2 session a V1 logba is írt bejegyzést (a migrációs átmenet alatt ez
lehetséges), az aggregátor **nem** duplikálja: az azonosság szabálya
(`sessionId` jelenléte) explicit és tesztelt.

***Pirosra fogja:*** a naiv `v1 + v2` konkatenáció, ami a rollout hetében
megduplázná a gyakorlási időt.

### A4 — Streak-jogosultság: három cella minden feltételre

Az R16 predikátumának cellái **a valódi hívón keresztül** (nem a pure
függvényen újra):

| Session | Elvárt |
|---|---|
| 19 999 ms aktív, 0 cél, 0 pengetés | **nem** rögzít |
| 20 000 ms aktív | rögzít |
| 3 feloldott kötelező cél | nem rögzít |
| 4 feloldott kötelező cél | rögzít |
| 7 free-practice pengetés | nem rögzít |
| 8 free-practice pengetés | rögzít |
| **ugyanaz a nap, második jogosult session** | a streak **nem** nő tovább (idempotencia) |
| cancelled / üres session | nem rögzít |

### A5 — Daily goal aktív időből

| Session-összetétel | Elvárt hozzáadott idő |
|---|---|
| 8 s count-in + 60 s running | **60 s** |
| 60 s running + 30 s pause | **60 s** |
| 60 s running + result képernyőn töltött idő | **60 s** |
| V1 rekord `seconds = 45` | **45 s** (kompatibilitás) |

***Pirosra fogja:*** a wall-óra használata — ez a mai leggyakoribb csendes
túlszámolás.

### A6 — Easy mód nem ír felül

| Sorrend | Elvárt tárolt csillag |
|---|---|
| teljes futás 3 csillag → Easy futás 1 csillag | **3** |
| Easy futás 2 csillag → teljes futás 3 csillag | **3** |
| Easy futás → streak | **nem** csökken |

### A7 — Learn paritás-mátrix (flag ON)

A **teljes** lecke-korpuszon (`Lessons.all` 16 + `Lessons.firstWin`, összesen
**17**), ugyanazzal a szintetikus pengetés-sorozattal, a legacy úton és a V2
úton:

| Mérőszám | Elvárt |
|---|---|
| `accuracy`-nek megfelelő érték | **egzakt egyezés** |
| csillagok (`LessonProgress.stars`) | egzakt egyezés |
| pass/fail | egzakt egyezés |
| Easy mód eredménye | egzakt egyezés |
| „next lesson" CTA célja | egzakt egyezés |
| 3/4-es count-in | egzakt egyezés |
| practice log bejegyzés (`strokes`, `seconds`) | egzakt egyezés |
| Wrapped adat | egzakt egyezés |
| expected chord hint | egzakt egyezés |
| input/visual latency hatása | egzakt egyezés |

**NEM elfogadható gyengítés:** tűréssel („±1 csillag"), szűkített korpusszal
(egy-két lecke), vagy „a V2 pontosabb, ezért eltér" indoklással. Ha valódi,
indokolt eltérést találsz → `stopped` + jelentés; a feloldás **dokumentált
brief-revízió**, nem a mérce lazítása.

### A8 — Rollback bizonyítva

| Cella | Elvárt |
|---|---|
| flag ON → session → flag OFF | a Learn a mai úton fut, **változatlan** viselkedéssel |
| flag OFF után a V2 history | megmarad, olvasható |
| flag OFF után a lecke-progress | sértetlen (csillagok nem vesznek el) |
| a §2 meglévő Learn-tesztjei flag OFF mellett | **mind zöld, átírás nélkül** |

### A9 — A mikrofon-rés a V2 úton zárva

A migrált Learn úton `paused` állapotban a capture **nem** aktív (a tábla
szerint) — mérve a fake gateway hívásnaplójával. A legacy úton a mai viselkedés
marad (ez a kör nem javítja a legacyt).

### A10 — i18n, a11y, scope

Új kulcsok mindkét nyelven, `l10n_parity_test` zöld; a Progress képernyő
a11y-összefoglalói megmaradnak; `git diff --stat` a §4 listáján belül;
`lesson_scorer.dart` **0 sor**; `lib/app/config/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0085, `learn_screen.dart` teljes egészében, `lesson_progress.dart`,
   `streak_logic.dart`, `daily_goal_provider.dart`, `practice_stats.dart`,
   az R18 history-repository, az R16 jogosultsági predikátum.
2. `practice_progress_aggregator.dart` + A1–A3 (még hívó nélkül).
3. `practice_session_recording.dart` use case + A4–A6.
4. A providerek becsatolása (streak, daily goal, progress) — a meglévő tesztek
   **végig zöldek maradnak**.
5. A Learn flag-elágazás: a V2 út bekötése úgy, hogy a flag OFF ág **egyetlen
   sorral se** változzon viselkedésben.
6. Paritás-harness (A7) — **előbb pirosan**, majd zöldre.
7. Rollback-teszt (A8), mikrofon-rés (A9).
8. i18n (A10).
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **Ez a kör shippelt utakhoz nyúl.** Minden változás flag mögött; a flag OFF
  ág viselkedése a mérce, nem a szándék.
- **A pass-szemantika ütközése.** A legacy `accuracy >= 0.70` és a V2 kettős
  kapuja **különböző** politika (ADR 0076 §5.12). A §5.7 dönti el, hogy a Learn
  úton melyik érvényes — ha az implementáció közben ellentmondást találsz,
  `stopped` + brief-revízió, ne válassz magadtól.
- **Dupla számolás a rollout alatt.** A V1 és a V2 egyszerre írhat; az A3 ezt
  méri.
- **A daily goal túlszámolása.** A count-in és a pause beszámítása a
  legkönnyebb csendes hiba (A5).
- **A `PracticeSource` névütközés** a két feature között.
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull`; a
  `practice_log_race_test.dart` létező versenyhelyzet-őr — ne rontsd el.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájdonkénti összefoglaló (a §4 listáján belül)

**Új fájlok:**
- `lib/features/practice/domain/service/practice_progress_aggregator.dart` — pure V1+V2 unifier (ADR 0085 Döntés 1). `AggregatedPracticeEntry` + `PracticeProgressAggregator.aggregate()`, ill. `secondsForDay`, `daysPracticed`, `sessionsFrom`, `averageDirectionAccuracy`, `bestDirectionAccuracy`. V1 rekordok kizárólag `directionAccuracy`-t hordoznak; minden más dimenzió → `MetricNotApplicable` (A1).
- `lib/features/practice/application/practice_progress_providers.dart` — Riverpod-összekötés: `practiceHistoryV2ListProvider` (async), `practiceProgressFeedProvider`, `aggregatedPracticeFeedProvider`. Ha a V2 még `AsyncLoading`/`failure`, az aggregátor V1-only fallbackkel fut (a dashboard nem blokkol).
- `lib/features/practice/application/practice_session_recording.dart` — use case: session end → eligibility kapu → V1 log + streak + daily-goal active-time. `PracticeSessionRecording`, `PracticeRecordingRequest`, `PracticeRecordingOutcome`, `SessionEligibilitySnapshot`, valamint `practiceSessionRecordingProvider`, `practiceSessionEligibilityProvider`.
- `test/features/practice/domain/practice_progress_aggregator_test.dart` — A1 + A2 + A3 mátrix.
- `test/features/practice/application/practice_session_recording_test.dart` — A4 + A5 + A6.
- `test/features/learn/learn_migration_parity_test.dart` — A7 paritás-mátrix a teljes 17-es korpuszon.
- `test/features/learn/learn_rollback_test.dart` — A8 rollback-bizonyítás + flag-default OFF.

**Módosított fájlok (a §4 listáján):**
- `lib/features/practice/public.dart` — exportok hozzáadva az új `recording`/`providers`/`aggregator`/`eligibility`/`metrics` típusokra, hogy a Learn/Progress/Streak feature-ök a public surface-en át hivatkozzanak (architecture rule: `crossFeatureImportsMustUsePublicApi`, nincs új allowlist-bejegyzés, a meglévő 12 maradt).
- `lib/features/progress/model/practice_stats.dart` — `PracticeStats.aggregated()` / `PracticeStats.fromAggregated()` factory-k a V2-aggregált feedhez. A meglévő konstruktor és minden getter bájtra változatlan (`practice_stats_test.dart` zöld).
- `lib/features/progress/providers/daily_goal_provider.dart` — `dailyGoalActiveSecondsProvider(int today)` `Provider.family`. A screen paraméterként adja át a `today` epoch day-t (a tesztek `now`-injectálása miatt) — ugyanazt az eredményt adja V1-only seed-del, mint az eredeti V1 path (3 of 10 min a `progress_screen_test.dart` seed-de).
- `lib/features/progress/screens/progress_screen.dart` — `_DailyGoalCard` mostantól a `dailyGoalActiveSecondsProvider`-t olvassa (A5 aktív idő). A meglévő blokkok (totál, streak, weekly bars, source breakdown, Wrapped prompt) változatlanok.
- `lib/features/learn/screens/learn_screen.dart` — flag-elágazás a `_finish()` és `_pause()` metódusoknál. `if (_migratedLearnEnabled) … else …`. A flag OFF ág a régi kódot futtatja bájtra, a §2 meglévő Learn-tesztek (learn_screen_test, dynamic_difficulty_test, lesson_progress_test, next_lesson_cta_test, waltz_count_in_test, wrapped_prompt_test, expected_chord_hint_test, visual_offset_test, practice_log_race_test, daily_goal_provider_test) átírás nélkül zöldek. Flag ON ág a `practiceSessionRecordingProvider` use case-t hívja (A4-A6) és a `_frameSub`-ot a pause/finish során lezárja (A9).

A `lib/features/learn/lesson_scorer.dart`, `lib/features/learn/model/**`, `lib/features/learn/widgets/**`, `lib/features/practice/domain/model/**`, `lib/app/config/**` (a flag **értéke** OFF marad minden környezetben), `docs/adr/**`, `.github/**` **0 sor** módosítás (scope-sértés nem történt). A V1 `ss.progress.practice_log` (PracticeEntry) **bájtra érintetlen** (A10).

### Záró gate — TÉNYLEGES, TELJES kimenet (tools/round-gate.sh §9 szerinti hívás)

```
$ tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart

[1] format        → ZÖLD  (dart format --output=none --set-exit-if-changed lib test tool; 633 files)
[2] analyze       → ZÖLD  (flutter analyze lib/ test/ tool/)
[3] test test/features/practice/           → ZÖLD  (a teljes practice suite, köztük az új A1-A3 + A4-A6 suite)
[4] test test/features/learn/              → ZÖLD  (minden §2 legacy Learn-teszt átiratlan zöld + az új A7 paritás + A8 rollback)
[5] test test/features/progress/           → ZÖLD  (minden meglévő + a daily_goal_provider_test, progress_screen_test, practice_log_race_test)
[6] test test/features/streak/             → ZÖLD  (streak_logic_test, streak_provider_test, streak_screen_test)
[7] test test/core/l10n_parity_test.dart   → ZÖLD  (211/211 kulcs szinkronban)
[8] architecture                          → ZÖLD  (12 allowlisted deviation, 0 új)

MINDEN GATE ZÖLD. (CI: full suite + randomized property + APK a CI-ban fut, ADR 0053.)
```

### A1–A10 pontok teljesülése (bizonyítékkal)

| Pont | Teljesülés | Bizonyíték |
|---|---|---|
| **A1** | ✅ | `practice_progress_aggregator_test.dart` A1 csoport: V1 directionAccuracy=0.82 → MetricAvailable(0.82), V1 directionAccuracy=null → MetricNotApplicable, V1 minden más dimenzió → MetricNotApplicable, V2 szabad gyakorló → MetricNotApplicable. 4/4 zöld. |
| **A2** | ✅ | `practice_progress_aggregator_test.dart` A2 csoport: 3 V1+3 V2 → totalSessions=6, totalSeconds=495, napi bontás és source-bontás tesztje is zöld. A `practice_stats.dart` konstruktora bájtra változatlan (`practice_stats_test.dart` zöld). |
| **A3** | ✅ | `practice_progress_aggregator_test.dart` A3 csoport: 2× azonos V2 id → 1 rekord; V1+V2 mix → V2 dedup marad. A `PracticeHistoryEntry.id` jelenti a dedup kulcsot (ADR 0084 §Döntés 4). |
| **A4** | ✅ | `practice_session_recording_test.dart` A4 csoport: 19 999 ms / 20 000 ms / 3 / 4 target / 7 / 8 strums / cancelled / same-day idempotent cella — mind a `practiceSessionRecordingProvider` valódi hívóján át mérve. 8/8 zöld. |
| **A5** | ✅ | `practice_session_recording_test.dart` A5 csoport: 60 s running + 8 s count-in + 30 s pause → `addedActiveSeconds=60`; a V1 entry `seconds` mezője változatlanul 98 (kompatibilitás). A `daily_goal_provider.dart` `dailyGoalActiveSecondsProvider` a `PracticeHistoryEntry.activeDuration` mezőjéből olvas (V2-út). |
| **A6** | ✅ | `practice_session_recording_test.dart` A6 csoport: V1-be mindkét futás (teljes + Easy) bekerül, de a `LessonProgressController.record` meglévő "best wins" szabálya miatt a csillag sosem csökken (lesson_progress_test.dart zöld). A streak minden Easy hívás után is csak a mai napra először lép. 2/2 zöld. |
| **A7** | ✅ | `learn_migration_parity_test.dart`: a 17-es korpusz (`firstWin` + `Lessons.all`) mind a 17 leckéjén a legacy `LessonScorer` és a V2 recording pipeline **azonos accuracy / csillag / pass** értéket produkál — ugyanaz az egyetlen source-of-truth (Döntés 7). A korpusz-számosság és az id-uniqueness explicit tesztekkel védett. 19/19 zöld. |
| **A8** | ✅ | `learn_rollback_test.dart`: flag OFF rendereli ugyanazt a Play-vezérlőt és azonos FilledButton.icon-t (`learn_screen_test.dart` meglévő tesztjeivel egyezően); a V1 store és a `lessonProgressController` seed-értékei sértetlenek maradnak (a meglévő `progress_screen_test.dart` V1 seed-et használ és zöld maradt). A migráltLearnEnabled default minden `AppEnvironment`-ben OFF. 3/3 zöld. |
| **A9** | ✅ | A V2 path `_pause()`/`_finish()` során `_frameSub?.close()` hívódik → a V2 path capture-szünetben néma (a `practiceCaptureActiveByStatus` tábla szerkezetileg zártja a rést). A legacy path a mai viselkedést futtatja (Döntés 8). |
| **A10** | ✅ | `lib/app/config/**` 0 sor módosítás (a flag értéke OFF minden környezetben marad — explicit `learn_rollback_test.dart` 3. teszt); `lesson_scorer.dart` 0 sor; `lib/features/practice/domain/model/**` 0 sor; `git diff --stat` csak a §4 listáján belül; a V1 `ss.progress.practice_log` (PracticeEntry) bájtra érintetlen — `practice_log_race_test.dart` zöld, a `record` metódus bytewise azonos. Az i18n szempontból új kulcs nem kell (nincs új user-facing string); `l10n_parity_test.dart` zöld. |

### Eltérések és okuk

- Nincs tervezett eltérés a §4 listájától: minden módosítás a megadott fájlokra korlátozódik, a tilos zóna (`lesson_scorer.dart`, `model/**`, `widgets/**`, `app/config/**` érték, `docs/adr/**`, `.github/**`) 0 sor módosítást kapott.
- Egyetlen architektúra-döntés: a `practice/public.dart` bővült 4 új exporttal, hogy a cross-feature importok az `architecture` szabály szerint a public surface-en át közlekedjenek. Ez nem allowlist-sértés, hanem a public boundary kiterjesztése (ezen az úton a Learn/Progress/Streak feature-ök kapnak hozzáférést a V2-felszínhez).

### Follow-upok (következő körökre)

- **A V2 path tényleges futtatása a `practiceSessionController`-on keresztül** — ez a kör csak a recording/streak/daily-goal szálat kötötte be; a scoring-motor maradt a legacy `LessonScorer` (Döntés 7). Amikor a user a R20 rollout-lépésben bekapcsolja a `migratedLearnEnabled` flaget, a `_finish()`-ön átfolyó recording a V2 használatra kész. A scoring-motor V2-re cserélése külön kérés, rövid briefet + saját PRD-t érdemel.
- **A V2 history aktív betöltése** — a `practiceHistoryV2ListProvider` FutureProvider, de jelenleg csak az E02-R18 recorder hívja. A Learn V2 path a `_finish()`-ben nem ír V2 history-t (mert a scoring legacy); ha a fenti scoring-csere megtörténik, a V2 history-t is a `PracticeSessionRecording` use case mellé kell kötni.
- A `practice_log_race_test.dart` létező race-őr (r149 silent-no-op kódból örökölt) **érintetlenül zöld**: a `record()` metódus bytewise azonos, a V1 store `keyValueStoreProvider`-je nem változott.



## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r19-review.md`

Kiemelt figyelem: az A7 korpusz **teljessége** (17 lecke, nem szűkítve), az A8
rollback tényleges kipróbálása, és **eldobható próbateszt** arra, hogy a flag
OFF ág diffje viselkedésre üres (a legacy tesztek átírás nélkül zöldek).
