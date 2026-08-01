# E02-R19 — Progress, streak, daily goal és Learn migráció

- **Státusz:** **PLANNING — REVIDEÁLVA (R19/b, 2026-08-01)** a HALT H3 user-döntése után (lásd **§0.1**). Pre-flight lezárva 2026-08-01, kód mérve: `main` @ `eeb4f6d`; előre megírva 2026-07-31 @ `ce8fbce`. Kiindulási commit a branchen: `7cf1ca4` (plumbing, megtartva).
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

## 0.1 Brief-revízió — R19/b újra-scope (user-döntés 2026-08-01)

> **Ez a szakasz felülírja a §4 tilos zónáját és a §6 A7-et.** A korábbi
> (revízió előtti) állapotot a `7cf1ca4` implementáció és a
> [`docs/reviews/e02-r19-review.md`](../reviews/e02-r19-review.md) 3.1 MAJOR
> rögzíti — ne ahhoz igazodj, hanem ehhez a szakaszhoz.

**Mi történt.** Az első futás (`7cf1ca4`) a plumbing-oldalt (A1–A6, A8–A10)
valósan megcsinálta, de a **Learn-migráció scoring-útját tautológiaként**
készítette el: a flag-ON ág a legacy `LessonScorer` `snap.accuracy`-jét adta
tovább `directionAccuracy`-ként, V2 scoring-út nélkül, és az A7 paritás-teszt
ugyanazt az egy értéket hasonlította önmagához („trivially identical"). A hű
megvalósítás a §4 listán kívüli fájlokat igényelt → **HALT (H3)**.

**A user döntése: (b) — R19 újra-scope-olása.** A §4 lista bővül a V2-scoring
felszínnel, és a kör **valódi, piros→zöld** A7-tel fut újra. A plumbing-commit
(`7cf1ca4`) **megmarad** kiindulásnak (a review mérte: genuine, nem tautológia);
az implementer erre építi rá a valódi scoring-utat, és **a teljes A1–A10-ért
felel**, nem csak a scoring-részért.

### Mért paritás-alap (orchestrátor, 2026-08-01) — ez teszi az A7-et teljesíthetővé

A HALT után kimértem, hogy a két mérték **strukturálisan azonos**, tehát az
egzakt paritás nem irreális elvárás. Mind grepelt/olvasott tény, nem tábla:

| Szempont | legacy `LessonScorer` | V2 `PracticeEventMatcher` + `PracticeDirectionScorer` |
|---|---|---|
| óra-korrekció | `playedSec = elapsedSec - inputLatencySec` (`lesson_scorer.dart:245`) | `playedAt = observation.at - inputLatency` (`practice_event_matcher.dart:148`) |
| illesztés | legközelebbi **nyitott** esemény, `d <= windowSec && d < bestDelta` (`:249-256`) | legközelebbi **nyitatlan** target, `delta <= matchWindow && delta < best` (`:156-170`) |
| ablak | `windowSec = 0.28` (default, `:79`) | `matchWindow = Duration(milliseconds: 280)` — **mind az 5 profilban** (`scoring_profile.dart:70,85,100,116,128`) |
| extra ütés | „no open event nearby" → `null`, **büntetlen** (`:258`) | `_extraStrumCount++` → `null`, **büntetlen** (`:172-175`) |
| rossz irány | az esemény **elhasználva** (`best.matched = true`), `wrong`, nem hit (`:259,286`) | a target **resolved**, `DirectionOutcome.wrong`, 0 pont, **nevezőben marad** (`practice_direction_scorer.dart:103-114`) |
| miss-zárás | `advance()` korrigált órán, nyitott esemény ablakon túl → miss (`:294-300`) | `advance()` korrigált órán, nem-növekvő óra figyelmen kívül (`:191-198`) |
| **számláló** | `hits` = ablakon belüli **és jó irányú** ütés | `correctCount` = `observation.direction == expected` |
| **nevező** | `total` = a lecke eseményeinek száma | `applicableCount` = irány-viselő, nem-kihagyott target |

`LessonEvent.direction` **nem-nullable** (`lesson.dart:24`) → ha az adapter
minden lecke-eseményt **kötelező** (nem `optional`) targetként fordít le,
`applicableCount == total`. A count-in: a Learn képernyő
`countInBeats: _countInBeats = lesson.beatsPerBar` (`learn_screen.dart:47,220`),
ami a fordítóban `config.countInBars = 1`; a target-idő
`(countInBeats + e.beat) * secPerBeat` ↔ `converter.timeOfTicks(countInTicks + eventTicks)`.

**Következtetés:** az egzakt paritás **tervezetten elérhető**; ha eltérést mérsz,
az az adapter konfigurációs hibája (ablak, latency, count-in, tick-rács,
`optional` jelölés), nem a mérce hibája. A mércét NEM lazítjuk.

### Mi változik ebben a revízióban

1. **§4** — a lista bővül a V2-scoring felszínnel (lásd az ott jelölt
   „**R19/b**" sorokat) és a `public.dart`-tal (a review 4.1 NOTE-ja).
2. **§5.7 (ADR 0085 Döntés 7)** — pontosítva: a Learn accuracy forrása a **V2
   direction-dimenzió**, a legacy `LessonScorer` a **referencia**, nem a forrás.
3. **§6 A7** — valódi, két-utas paritás-mátrix, kötelező **anti-tautológia
   őrökkel** és mutációs cellával.
4. **§7** — az implementációs sorrend a scoring-úttal kezdődik.

Minden más (A1–A6, A8–A10, §9 gate, tilos zóna maradéka) **változatlanul
érvényes**, és a `7cf1ca4`-ben már teljesül — de a záró gate-nek a végén is
zöldnek kell lennie.

## 0.2 Brief-revízió — ezrelék-kvantálás (orchestrátor, 2026-08-01)

**Az implementer `stopped`-ot jelzett, helyesen.** Mért lelet: a
`down-up-groove` részleges cellán (7 jó irány 24 targetből) a legacy
`accuracy = 7/24 = 0.2916666666666667`, a V2 `direction` viszont **`0.291`**.

**Ok (mérve, `practice_direction_scorer.dart:129-131`):** a V2 direction-dimenzió
**ezrelékre kvantál**, a legacy nem:

```dart
directionPerMille = correctCount * 1000 ~/ applicableCount;   // egész-osztás
direction = MetricAvailable(directionPerMille / 1000);
```

Ez **valódi, strukturális eltérés**, nem konfigurációs hiba — a §0.1 táblája a
számlálót és a nevezőt mérte össze, a záró osztás kvantálását nem. Az A7 négy
ismert hibaforrása (matchWindow, inputLatency, count-in, `optional`) **nem**
magyarázza.

**Hatásmérés (orchestrátor, `python3`):** minden `k/n` cellára `n ≤ 63`-ig
összevetve az egzakt és a csonkított értéket a `0.70 / 0.80 / 0.90` küszöbökön:
**0 olyan cella van, ahol a csonkítás csillag- vagy pass-határt flippelne.** Ez
szerkezeti: a küszöbök pontosan 1‰ többszörösei, a csonkítás pedig lefelé
kerekít 1‰-re, tehát `x >= t ⟺ floor(x·1000)/1000 >= t`. A **felhasználó-látott**
szemantika (csillag, pass) tehát már most is egzaktul egyezik.

### Döntés — a mércét nem lazítjuk, hanem az adaptert pontosítjuk

**NEM** fogadjuk el a `direction` kvantált értékét accuracy-ként, és **NEM**
lazítunk tűrésre. Helyette az adapter az **egzakt arányt** számolja a V2 scorer
**saját per-event kimenetéből**:

1. `lesson_v2_scoring.dart` a `PracticeDirectionScore.events` listából számol:
   - `applicable` = `outcome != DirectionOutcome.notApplicable` események száma,
   - `correct` = `outcome == DirectionOutcome.correct` események száma,
   - `accuracy = applicable == 0 ? 0.0 : correct / applicable`.

   Ez **továbbra is 100%-ban a V2 scorer döntése** arról, melyik ütés helyes —
   csak a záró osztás nem kvantál. A Döntés 7 („a V2 metrikákból képzi")
   maradéktalanul teljesül, tautológia nincs.
2. **Konzisztencia-őr (ÚJ, kötelező — A7.0/5.):** ugyanez a teszt mérje, hogy az
   egzakt arány **ezrelékre csonkítva** megegyezik a scorer saját
   `direction` `MetricAvailable` értékével:
   `(accuracy * 1000).floor() / 1000 == direction.value`. Ez bizonyítja, hogy az
   adapter nem valami mástól számol, hanem ugyanattól a scorertől.
3. A `practice_direction_scorer.dart` **változatlan marad** (§4 „olvasandó"
   lista) — a kvantálás a V2 pontszám-aggregáció sajátja, annak ott helye van.

**Az A7.1 elvárása változatlan: egzakt egyezés**, tűrés nélkül, mind az 51
cellán. A `DirectionOutcome` a `practice_verdict.dart`-ban él; ha nincs
exportálva, a `practice/public.dart` (§4 listán) bővíthető export-sorral.

## 0.3 Brief-revízió — az ablak-határ dokumentált kizárása (orchestrátor, 2026-08-01)

A review (`docs/reviews/e02-r19-review.md` 4.1 MAJOR) eldobható próbateszttel
valós paritás-eltérést mért **pontosan az ablak-határon**:

| offset | legacy accuracy | V2 accuracy |
|---|---|---|
| +0 / +150 / +270 / +279 ms | egyezik | egyezik |
| **+280 ms** | **0.0** | **0.041666666666666664** (= 1/24) |
| +281 / +300 / +400 ms | egyezik | egyezik |
| latency 50 / 150 / 300 ms | egyezik | egyezik |

**Ok:** a legacy `d <= windowSec` **double**-összehasonlítás (a `0.28`
legközelebbi double-je `0.28000000000000002665`), a V2
`deltaMicroseconds <= matchWindow.inMicroseconds` **egész**. A pontos határon a
két numerikus alap eltér — minden más offseten és minden mért latencyn a
paritás **tart**.

### Döntés

A paritás elvárása **kötelező marad** minden **szigorúan az ablakon belüli** és
**szigorúan az ablakon kívüli** offsetre. A **pontos határpont**
(`|d| == matchWindow` egzaktul, azaz `±280.000 ms`) **dokumentált, elfogadott
mikro-eltérés**, és a paritás-állításból **kizárandó**.

**Miért nem mércelazítás:** a legacy referencia ezen a ponton **maga sem jól
definiált** — a `d <= 0.28` kimenete a double-ábrázolás kerekítésén múlik, nem
a lecke szemantikáján. Valós mikrofonos időbélyeg nem esik pontosan ide
(mikroszekundumra egybeeső véletlen kellene hozzá), és a flag OFF. A mércét
tehát nem gyengítjük, hanem **ott definiáljuk pontosan, ahol a referencia
maga sem definiált**.

Ezt a döntést az orchestrátor hozta a saját, még nem merge-elt briefjén
(ADR 0087 §2) — nem igényel HALT-ot.

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
| **`lib/features/learn/adapter/lesson_practice_target.dart`** | **ÚJ — R19/b** | `Lesson` → `PracticeDefinition` → `CompiledPracticeTarget` fordító (count-in, tick-rács, kötelező targetek, `ScoringProfile`-választás) |
| **`lib/features/learn/adapter/lesson_v2_scoring.dart`** | **ÚJ — R19/b** | a **valódi V2 scoring-út**: megfigyelés-lista → `PracticeEventMatcher` → `PracticeDirectionScorer` → legacy-alakú `accuracy` (§5.7) |
| **`lib/features/practice/public.dart`** | — **R19/b** | **CSAK export-sorok** az in-scope szimbólumokra (matcher, direction-scorer, compiler, definíció-típusok, az R19 use case-ek). Nulla viselkedés. Ezt a review 4.1 NOTE-ja tette a listára. |
| **`test/features/learn/lesson_v2_scoring_test.dart`** | **ÚJ — R19/b** | az adapter + V2 scoring-út egység-tesztje, **köztük az A7.0 mutációs cellák** |

> **R19/b — amit OLVASNOD kell, de MÓDOSÍTANOD TILOS** (a paritás referenciái;
> ha bármelyiket módosítanod kellene a zöldért, az **`stopped`**, nem
> lista-tágítás): `lib/features/practice/domain/service/practice_event_matcher.dart`,
> `practice_direction_scorer.dart`, `practice_target_compiler.dart`,
> `lib/features/practice/domain/model/**` (`practice_definition.dart`,
> `practice_event.dart`, `scoring_profile.dart`, `practice_observation.dart`,
> `compiled_practice_target.dart`, `meter.dart`, `tempo.dart`,
> `beat_position.dart`), `lib/features/learn/lesson_scorer.dart`,
> `lib/features/learn/model/lesson.dart`, `lesson_progress.dart`.
>
> Ezek **változatlanul** hordozzák a paritást (§0.1 mérés) — az adaptert kell
> hozzájuk igazítani, nem fordítva.

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/lesson_scorer.dart`,
`lib/features/learn/model/**`, `lib/features/learn/widgets/**`,
`lib/features/practice/domain/model/**`,
`lib/features/practice/domain/service/**` **egyetlen kivétellel**: a fenti
listán néven nevezett `practice_progress_aggregator.dart` (az R19 saját új
fájlja) szerkeszthető — minden más service-fájl, köztük a négy **olvasandó**
paritás-referencia, **0 sor**. Továbbá `lib/app/config/**` (a flag **értéke**
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

   > **R19/b pontosítás (§0.1 revízió) — ez a kör magja.** A „V2 metrikákból
   > képzi" **szó szerint** értendő: a flag-ON út accuracy-je
   > `PracticeDirectionScorer.score(...).direction` `MetricAvailable` értéke,
   > amit a `PracticeEventMatcher` illesztéseiből számol a `lesson_v2_scoring.dart`.
   > A legacy `LessonScorer` a flag-ON úton **REFERENCIA** (amivel a paritást
   > mérjük), **NEM forrás**. Tilos a `ScoreSnapshot.accuracy` továbbadása
   > `directionAccuracy`-ként — pontosan ez volt a `7cf1ca4` tautológiája.
   >
   > `MetricNotApplicable` / `MetricInsufficientData` esetén (nulla
   > irány-viselő target, vagy egyetlen megfigyelés sem) az accuracy **`0.0`**
   > — ez a legacy `total == 0 ? 0 : hits/total` viselkedésének felel meg.
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

### A7 — Learn paritás-mátrix (flag ON) — **R19/b: újraírva**

> A revízió előtti A7-et a `7cf1ca4` tautológiával „teljesítette" (a legacy
> kimenetét hasonlította önmagához). Az alábbi A7.0 őrök ezt **szerkezetileg**
> zárják ki; enélkül az A7 nem elfogadható, akkor sem, ha a gate zöld.

#### A7.0 — Anti-tautológia őrök (KÖTELEZŐ, mind a négy)

1. **Típus-zár.** A V2 accuracy-t egyetlen **production** függvény állítja elő a
   `lesson_v2_scoring.dart`-ban, amelynek szignatúrája **kizárólag**
   `(Lesson lesson, List<StrumObservation> observations, {…konfiguráció})` →
   `double`. `ScoreSnapshot`, `LessonScorer` és `HitResult` **nem szerepelhet**
   sem a paraméterei közt, sem a fájl importjai közt. Így a teszt **nem tudja**
   becsempészni a legacy kimenetet a V2 ágba.
2. **Import-tilalom, gépiesen.** `lesson_v2_scoring.dart` és
   `lesson_practice_target.dart` **nem importálja** a `lesson_scorer.dart`-ot.
   Ezt a `lesson_v2_scoring_test.dart` egy tesztje **méri** (a forrásfájl
   beolvasása és `contains('lesson_scorer')` → `isFalse`), nem csak állítja.
3. **Mutációs cella (a piros bizonyítéka).** Ugyanaz a lecke, ugyanaz az
   időzítés, de **minden megfigyelés iránya megfordítva** → a V2 accuracy
   **`0.0`**, miközben a target-szám változatlan. Ha ez a cella nem megy 0.0-ra,
   a V2 út nem olvassa az irányt.
4. **Részleges cella.** `n` targetből pontosan `k` jó irányú, `n-k` fordított,
   azonos időzítéssel → V2 accuracy **egzaktul `k/n`** (legalább két különböző
   `k`-val). Ez zárja ki a „mindig 1.0" és a „mindig legacy" degenerációt.
5. **Kvantálás-konzisztencia (§0.2 revízió).** Ugyanazon a cellán az egzakt
   arány **ezrelékre csonkítva** egyezzen a scorer saját `direction`
   `MetricAvailable` értékével:
   `(accuracy * 1000).floor() / 1000 == direction.value`. Ez bizonyítja, hogy az
   adapter ugyanattól a V2 scorertől számol, csak a záró osztásnál nem kvantál.

***Pirosra fogja:*** a `7cf1ca4` megoldása — az 1. és 2. őr **fordítási/mérési
szinten** lehetetlenné teszi a legacy-passthrough-t.

#### A7.1 — Paritás a teljes korpuszon

A **teljes** lecke-korpuszon (`Lessons.all` 16 + `Lessons.firstWin`, összesen
**17**), **ugyanabból az egyetlen szintetikus pengetés-sorozatból** származtatva
a két bemenetet — a legacy út `registerStrum(dir, elapsedSec)` hívásokat kap, a
V2 út **ugyanazokból** az `(irány, időpont)` párokból épített
`List<StrumObservation>`-t —, a legacy úton és a V2 úton:

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

**Mind a 17 leckén, mind a HÁROM pengetés-alakkal** (a paritás nem mérhető egy
tökéletes futáson, mert ott minden út 1.0-t ad):

| Alak | Mit fed le |
|---|---|
| **P1 — tökéletes** | minden target pontosan a rácson, jó iránnyal → mindkét út `1.0` |
| **P2 — vegyes** | ~1/3 fordított irány, ~1/3 az ablakon **kívülre** csúsztatva (miss), ~1/3 pontos | 
| **P3 — extra + hiány** | 2 target teljesen kihagyva + 2 „extra" ütés target nélkül (büntetlennek kell lennie mindkét úton) |

17 lecke × 3 alak = **51 paritás-cella**; a §10-be a cellák számát és a
mért egyezést írd be.

**NEM elfogadható gyengítés:** tűréssel („±1 csillag"), szűkített korpusszal
(egy-két lecke), egyetlen (tökéletes) pengetés-alakkal, vagy „a V2 pontosabb,
ezért eltér" indoklással.

**Ha valódi eltérést mérsz** (§0.1 szerint ez konfigurációs hibát jelez): előbb
ellenőrizd a négy ismert forrást — (1) `matchWindow` ≠ `windowSec = 0.28`,
(2) `inputLatency` mértékegység/előjel, (3) count-in (`countInBars = 1`,
`meter` = `lesson.beatsPerBar`), (4) `optional` targetek a nevezőben. Ha
mind a négy rendben van és az eltérés **megmarad** → **`stopped` + jelentés**
a konkrét leckével, cellával és a két számmal. A feloldás dokumentált
brief-revízió, **nem** a mérce lazítása és **nem** a paritás-referenciák
(§4 „olvasandó" lista) módosítása.

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

## 7. Implementációs sorrend (ez a TERVED) — **R19/b: újraírva**

**Kiindulás:** a `7cf1ca4` commit (plumbing) a branchen már **rajta van**, és a
review mérése szerint A1–A6 és A8–A10 valósan teljesül. A 2–4. lépést tehát
**ne írd újra** — ellenőrizd, hogy zöld, és menj tovább. A kör magja az 5–7.

1. Olvasd el: a §0.1 revíziót (ez a legfontosabb), az ADR 0085 Döntés 7-et,
   a `docs/reviews/e02-r19-review.md` 3.1 leletét (mit rontott el az előző
   futás), majd a §4 „olvasandó" listáját — különösen a
   `practice_event_matcher.dart`, `practice_direction_scorer.dart`,
   `practice_target_compiler.dart`, `practice_definition.dart`,
   `scoring_profile.dart` fájlokat.
2. **Ellenőrzés, nem újraírás:** `practice_progress_aggregator.dart` + A1–A3.
3. **Ellenőrzés, nem újraírás:** `practice_session_recording.dart` + A4–A6.
4. **Ellenőrzés, nem újraírás:** a providerek becsatolása (streak, daily goal,
   progress) — a meglévő tesztek végig zöldek maradnak.
5. **`lesson_practice_target.dart`** — `Lesson` → `PracticeDefinition` →
   `compilePracticeTarget`. A rácsnak **egzaktul** a legacy
   `(countInBeats + e.beat) * secPerBeat` időket kell adnia (§0.1). Minden
   lecke-esemény **kötelező** (nem `optional`) target, `direction` kitöltve.
   A `PracticeDefinition.validate()` megköveteli, hogy
   `mode.scoredDimensions == scoringProfile.weights.keys` — ehhez válaszd a
   megfelelő `PracticeMode`/`ScoringProfile` párost, ne a modellt írd át.
6. **`lesson_v2_scoring.dart`** — a valódi V2 út: `StrumObservation`-lista →
   `PracticeEventMatcher` (`inputLatency`, `scoringProfile`) → `advance()` a
   session végéig → `PracticeDirectionScorer.score(...)` → `accuracy`.
   A szignatúra az A7.0/1. őr szerint kötött.
7. **`lesson_v2_scoring_test.dart`** — az A7.0 négy őre. **Előbb pirosan:**
   írd meg a mutációs cellát (A7.0/3) az adapter kész állapota ELŐTT, és a
   §10-be írd be, hogy pirosan mit adott.
8. A Learn flag-elágazás átkötése: a flag-ON ág accuracy-je a 6. lépés
   függvényéből jön (a `snap.accuracy` átadása **megszűnik**); a flag OFF ág
   **egyetlen sorral se** változzon viselkedésben.
9. `learn_migration_parity_test.dart` — az A7.1 51 cellája (17 lecke × P1/P2/P3).
10. Rollback-teszt (A8), mikrofon-rés (A9), i18n (A10) — ellenőrzés.
11. Záró gate (§9), majd a §10 **újraírása** (a jelenlegi tartalom az előző,
    elutasított futásé — töröld és írd újra, ne told hozzá).

## 8. Kockázatok

- **Ez a kör shippelt utakhoz nyúl.** Minden változás flag mögött; a flag OFF
  ág viselkedése a mérce, nem a szándék.
- **A pass-szemantika ütközése.** A legacy `accuracy >= 0.70` és a V2 kettős
  kapuja **különböző** politika (ADR 0076 §5.12). A §5.7 dönti el, hogy a Learn
  úton melyik érvényes — ha az implementáció közben ellentmondást találsz,
  `stopped` + brief-revízió, ne válassz magadtól.
- **R19/b — a kör legnagyobb kockázata: a tautológia megismétlése.** Az előző
  futás a scoring-utat úgy „teljesítette", hogy a legacy értéket adta tovább, és
  ezt **zöld gate mellett** tette (`docs/LESSONS.md` L28). A §6 A7.0 négy őre
  ezt szerkezetileg zárja; ha bármelyik őr kényelmetlen vagy megkerülhetőnek
  tűnik, az **jelzés, hogy a V2 út nincs kész** — ilyenkor `stopped`, nem
  őr-lazítás.
- **Az adapter-illesztés a nehéz rész, nem a scoring.** A `PracticeDefinition`
  validációja (mode ↔ scoringProfile dimenziók), a tick-rács és a count-in a
  három hely, ahol a paritás elcsúszhat. A §0.1 táblája a referencia.
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

### Fájlonkénti összefoglaló

- `lib/features/practice/domain/service/practice_progress_aggregator.dart`,
  `lib/features/practice/application/practice_progress_providers.dart`,
  `lib/features/practice/application/practice_session_recording.dart` és a
  hozzájuk tartozó tesztek: a meglévő R19 plumbing változatlanul egyesíti a
  V1/V2 feedet, a jogosultságot és az aktív időt.
- `lib/features/learn/adapter/lesson_practice_target.dart`: a legacy
  `Lesson` eseményeiből kötelező irány-targeteket tartalmazó
  `PracticeDefinition` és egybaros count-inű V2 target készül.
- `lib/features/learn/adapter/lesson_v2_scoring.dart`: a flag-ON accuracy
  tényleges V2 útja. A matcher eredményét a `PracticeDirectionScorer` értékeli;
  az adapter a per-event `DirectionOutcome`-okból oszt, ezért az eredmény
  egzakt, nem ezrelékre csonkított.
- `lib/features/learn/screens/learn_screen.dart`: flag ON alatt a rögzített
  `StrumObservation`-ök V2 accuracy-je megy a recordingbe és a lesson progressbe;
  flag OFF ág változatlan.
- `lib/features/practice/public.dart`: kizárólag a szükséges V2 contractok és
  `DirectionOutcome` exportjai; `practice_stats.dart` import-diszambiguálása.
- `test/features/learn/lesson_v2_scoring_test.dart`: A7.0 import-tilalom,
  teljes irányfordítás, két részleges arány, és az ezrelék-konzisztencia őre.
- `test/features/learn/learn_migration_parity_test.dart`: valódi, közös
  szintetikus strum-sorozatból induló 17 × 3 = 51 cellás legacy–V2 mátrix,
  majd a valódi recording út ellenőrzése.

### A7.0 piros → zöld bizonyíték

A korábbi adapter a V2 aggregált `direction` értékét adta vissza. Az új
részleges-mutatációs cella (`down-up-groove`, 7 helyes / 24 target) előbb
helyesen piros volt:

~~~
Expected: <0.2916666666666667>
Actual:   <0.291>
test/features/learn/lesson_v2_scoring_test.dart:70
~~~

A javítás után ugyanaz a teszt az egzakt `7 / 24` arányt kapja; külön őr méri,
hogy annak ezrelékre csonkított értéke `MetricAvailable(0.291)`, vagyis
ugyanannak a V2 scorernek a kimenete. A teljes irányfordítási mutáció továbbra
is `0.0`.

### A1–A10 teljesülése

| Pont | Bizonyíték |
|---|---|
| A1–A3 | `practice_progress_aggregator_test.dart`: V1/V2 metric-mátrix, 3+3 rekordos összegzés, V2-`id` deduplikáció. |
| A4–A6 | `practice_session_recording_test.dart`: 20 s / 4 target / 8 strum küszöbök, idempotencia, kizárólag `playingElapsed`, és Easy „best wins”. |
| A7.0 | `lesson_v2_scoring_test.dart`: típus- és import-zár, fordított irány = 0.0, két részleges egzakt arány, 7/24 ezrelék-konzisztencia. |
| A7.1 | `learn_migration_parity_test.dart`: 17 lecke × P1 tökéletes, P2 vegyes (jó/rossz/miss + extra), P3 extra+hiány = 51 egzakt accuracy-, csillag-, pass- és recording-paritáscella. |
| A8 | `learn_rollback_test.dart` és a változatlan legacy Learn-tesztek: flag OFF, V1 store és lesson progress sértetlen; az alapérték minden környezetben OFF. |
| A9 | A V2 flag-ág pause/finish során felszabadítja a frame subscriptiont; a `practiceCaptureActiveByStatus` táblának megfelelően paused állapotban nincs capture. |
| A10 | A l10n parity zöld; nincs új felhasználói szöveg. `lesson_scorer.dart`, `practice/domain/model/**`, `app/config/**`, `docs/adr/**`, `.github/**` 0 sor diff. |

### Záró gate — tényleges kimenet

~~~
$ tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart
round_gate_exit=0

[1] format                                           ZÖLD (636 fájl, 0 változás)
[2] analyze                                          ZÖLD (No issues found)
[3] test test/features/practice/                     ZÖLD
[4] test test/features/learn/                        ZÖLD (192 teszt + 1 skip)
[5] test test/features/progress/                     ZÖLD (17 teszt)
[6] test test/features/streak/                       ZÖLD (20 teszt)
[7] test test/core/l10n_parity_test.dart             ZÖLD (3 teszt)
[8] architecture                                     ZÖLD (12 allowlisted deviation)

MINDEN GATE ZÖLD.
~~~

A gate teljes terminál-streamje a futáskor megszületett; a fenti kivonat a
végső `round_gate_exit=0` és minden szakasz tényleges státusza. CI ellenőrzés
(teljes suite, randomizált property gate, APK) **nem futott lokálisan és nem
indítottam**: a brief és ADR 0053 szerint ezt az orchestrátor futtatja;
`gh`-t nem hívtam.

### Eltérések, scope és follow-up

- A korábbi, elutasított §10 teljesen eltávolítva. A valós V2 scoring-út és az
  anti-tautológia őrök kerültek a helyére.
- Az első záró gate analyzer-szakasza egy felesleges tesztimport miatt piros
  volt; az import eltávolítása után a fenti, friss teljes gate zöld.
- A `practice_direction_scorer.dart` kvantálása szándékosan változatlan. Az
  adapter nem lazít tűrést: a per-event V2 eredményből képez egzakt arányt.
- Új architektúra-allowlist nincs, secret vagy generált artefaktum nincs.
- Következő SDD-kör: E02-R20, rollout-döntés és Epic 2 lezárási regresszió
  (külön user-döntés a `migratedLearnEnabled` bekapcsolásáról).

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r19-review.md`

Kiemelt figyelem: A7.0 anti-tautológia és 7/24 kvantálás-őr, az A7.1 teljes
51-cellás korpusz, a flag-OFF viselkedés és a scope-audit.
