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
  szintetikus strum-sorozatból induló 17 × 3 = 51 cellás legacy–V2 mátrix;
  P2 a végső targetet szigorúan ablakon kívülre (+400 ms) csúsztatja, külön
  cella méri a +150 ms belső offsetet és a 300 ms azonos latency-korrekciót,
  majd a valódi recording utat.

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
| A7.1 | `learn_migration_parity_test.dart`: 17 lecke × P1 tökéletes, P2 vegyes (jó/rossz/miss + extra, a végső miss +400 ms-cel csúsztatott), P3 extra+hiány = 51 egzakt accuracy-, csillag-, pass- és recording-paritáscella; külön +150 ms belső és 300 ms latency cella. |
| A8 | `learn_rollback_test.dart` és a változatlan legacy Learn-tesztek: flag OFF, V1 store és lesson progress sértetlen; az alapérték minden környezetben OFF. |
| A9 | A V2 flag-ág pause/finish során felszabadítja a frame subscriptiont; a `practiceCaptureActiveByStatus` táblának megfelelően paused állapotban nincs capture. |
| A10 | A l10n parity zöld; nincs új felhasználói szöveg. `lesson_scorer.dart`, `practice/domain/model/**`, `app/config/**`, `docs/adr/**`, `.github/**` 0 sor diff. |

### Záró gate — tényleges, csonkítatlan kimenet

```
$ tools/round-gate.sh test/features/practice/ test/features/learn/ test/features/progress/ test/features/streak/ test/core/l10n_parity_test.dart

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 636 files (0 changed) in 2.65 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...
No issues found! (ran in 3.5s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:01 +9: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:01 +10: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:01 +11: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:01 +12: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:01 +13: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:01 +14: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:01 +15: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:01 +16: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:01 +17: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:01 +18: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:01 +19: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:01 +20: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:01 +21: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:02 +27: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:02 +28: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:02 +29: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:02 +30: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:03 +31: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:03 +32: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:03 +33: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:03 +34: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:03 +35: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:03 +36: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:03 +37: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:03 +38: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:03 +39: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:03 +40: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:03 +41: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:04 +42: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:04 +43: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:04 +44: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:04 +45: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:04 +46: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:04 +47: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:04 +48: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:04 +49: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:04 +50: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:05 +51: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:05 +52: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:05 +53: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:05 +54: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:08 +55: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:08 +56: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:08 +57: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:08 +58: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:08 +59: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:10 +60: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios counts strums and direction split
00:10 +61: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios zero strums => InsufficientData for the ratio
00:10 +62: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A3 — strum counts and down/up ratios direction-less definition => NotApplicable for the ratio
00:10 +63: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) three strums => InsufficientData
00:10 +64: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 4 evenly-spaced strums => deviation = 0
00:10 +65: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 12 evenly-spaced strums => deviation = 0
00:10 +66: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) 12 strums with one 1500 ms gap: median-absolute deviation stays small
00:10 +67: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A4 — tempo stability (MAD-style, requires ≥ 4 strums) mixed intervals: median-absolute deviation computes the right value
00:10 +68: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A5 — chord timeline segments G (4s) → null (1s) → C (3s) yields three segments
00:10 +69: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A2 — Free Practice summary never produces a score strumCount and activeDuration are surfaced as facts only
00:10 +70: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/free_practice_summarizer_test.dart: FreePracticeSummarizer A9 — segment durations sum to ≤ activeDuration
00:11 +71: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:11 +72: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:11 +73: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:13 +74: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:14 +75: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:14 +76: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:14 +77: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:14 +78: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:14 +79: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:14 +80: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:14 +81: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:14 +82: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:14 +83: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:14 +84: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 same input returns the same suggestion
00:14 +85: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 fixed list priority selects insufficient signal first
00:14 +86: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 low completion outranks timing bias and direction error
00:14 +87: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 dominant timing bias outranks direction error
00:14 +88: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 direction error is suggested when higher priorities are absent
00:14 +89: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 plain passed outcome alone does not trigger a step-up suggestion
00:14 +90: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/adaptive_practice_policy_test.dart: AdaptivePracticePolicy A7 active attempt always returns null
00:15 +91: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 step BPM accepts the closed 1 to 20 range
00:15 +92: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 max attempts accepts the closed 1 to 100 range
00:15 +93: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 start BPM follows the Tempo closed range
00:15 +94: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 target BPM may equal or exceed start but not precede it
00:15 +95: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 target BPM follows the Tempo closed range
00:15 +96: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 rejects non-finite tempo and step values
00:15 +97: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 consecutive-pass and fail thresholds must be positive
00:15 +98: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_policy_test.dart: SpeedBuilderPolicy A1 returns every independent validation failure
00:17 +99: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A2 — two step-up passes advance once and reset streak
00:17 +100: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine step-up pass uses metrics rather than plain passed outcome
00:17 +101: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine insufficient or unavailable required metrics cannot step up
00:17 +102: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A3 — two fails step down but never below start
00:17 +103: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A3/A4 — target bound is closed and completion needs full streak
00:17 +104: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A5 — max attempts closes idempotently
00:17 +105: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A5 — user finish preserves history and stable BPM
00:17 +106: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine finish derives stable BPM from preserved history
00:17 +107: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/speed_builder_engine_test.dart: SpeedBuilderEngine A6 — highest stable BPM requires consecutive passes per tempo
00:19 +108: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix recognises the first stable target chord with signed delay
00:19 +109: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a stable wrong chord separately
00:19 +110: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix keeps explicit null labels as no detection
00:19 +111: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix reports a target chord that never reaches stability
00:19 +112: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 179999 microseconds of stability remains unstable
00:19 +113: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix 180001 microseconds of stability is correct
00:19 +114: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer outcome matrix separates an empty window and a window without a strum
00:19 +115: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 3/4 change on a bar boundary produces correct statistics
00:19 +116: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer meter boundaries 4/4 change on a bar boundary produces correct statistics
00:19 +117: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation preserves early, on-time, late, and missing delay
00:19 +118: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation uses a median only after three measured changes
00:19 +119: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation treats direction as part of a chord pair
00:19 +120: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_change_analyzer_test.dart: ChordChangeAnalyzer delay and aggregation slowest pair tie-break is canonical and input-order independent
00:20 +121: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:21 +122: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:21 +123: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:21 +124: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:21 +125: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:21 +126: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:21 +127: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:21 +128: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:21 +129: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:21 +130: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:21 +131: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:21 +132: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:21 +133: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:21 +134: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:21 +135: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:21 +136: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:22 +137: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:22 +138: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:22 +139: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:22 +140: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:22 +141: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:22 +142: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:22 +143: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:22 +144: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:22 +145: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:22 +146: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:22 +147: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:22 +148: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:24 +149: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:24 +150: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:24 +151: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:24 +152: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:24 +153: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:24 +154: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:24 +155: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:24 +156: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:24 +157: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:24 +158: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:24 +159: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:24 +160: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:24 +161: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:24 +162: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:24 +163: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:24 +164: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:24 +165: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:24 +166: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:24 +167: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:26 +168: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:26 +169: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:26 +170: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:26 +171: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:26 +172: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:26 +173: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:27 +174: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:27 +175: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:27 +176: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:28 +177: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:28 +178: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:28 +179: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:28 +180: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:28 +181: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:28 +182: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:28 +183: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:28 +184: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:28 +185: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:28 +186: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:28 +187: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:28 +188: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:28 +189: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:28 +190: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:28 +191: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:28 +192: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:28 +193: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:28 +194: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:28 +195: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:28 +196: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:28 +197: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:28 +198: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:28 +199: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:28 +200: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:28 +201: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:28 +202: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:28 +203: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:30 +204: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence zero strum observations → noSignal
00:30 +205: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence completion 0.4 + overall 0.9 → lowCompletion (priority wins)
00:30 +206: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence paired events 80% late (≥ 8 paired, ≥ 70% share) → biasLate
00:30 +207: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence paired events 80% early → biasEarly
00:30 +208: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence direction 0.45 + rhythm 0.9 → directionError
00:30 +209: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence every dimension > 0.9 → positiveReinforcement
00:30 +210: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence chord 0.4 + chord-pair G→D median-worst → chordPairProblem
00:30 +211: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A4: every insight has evidence low completion AND direction error at the same time → completion wins
00:30 +212: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A5: minimum evidence threshold 3 paired events, 2 late → no bias insight (too little evidence)
00:30 +213: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A5: minimum evidence threshold 20 paired events, 16 late → biasLate
00:30 +214: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_coach_test.dart: PracticeCoach — A5: minimum evidence threshold one measured chord-pair → no pair insight (R15 threshold = 3)
00:31 +215: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:31 +216: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:31 +217: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:31 +218: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:31 +219: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:31 +220: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:31 +221: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:32 +222: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:32 +223: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:32 +224: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:32 +225: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:32 +226: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:32 +227: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:33 +228: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:33 +229: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:33 +230: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:33 +231: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity first-waltz explicitly measures the three-beat count-in edge
00:33 +232: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity eighth-drive explicitly measures its closest-to-end event
00:33 +233: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:33 +234: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:34 +235: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A1 — V1+V2 aggregation: no fabricated data V1 record with non-null directionAccuracy exposes that value
00:34 +236: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A1 — V1+V2 aggregation: no fabricated data V1 record with null directionAccuracy → MetricNotApplicable
00:34 +237: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A1 — V1+V2 aggregation: no fabricated data V2 record carries its full V2 metrics through
00:34 +238: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A1 — V1+V2 aggregation: no fabricated data a V2 free-practice record with NotApplicable direction stays that way
00:34 +239: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A2 — totals matrix 3 V1 + 3 V2 → totalSessions == 6, correct seconds sum
00:34 +240: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A2 — totals matrix per-day rollup sums V1 and V2 entries on the same epoch day
00:34 +241: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A2 — totals matrix source breakdown keeps V1 PracticeSource names
00:34 +242: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A3 — same V2 session id is never counted twice two V2 entries sharing an id collapse to one aggregated record
00:34 +243: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: A3 — same V2 session id is never counted twice V1+V2 mix never doubles a V2 entry even when V1 also logs the same session
00:34 +244: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: source code mapping (Döntés 3 — V2 PracticeSource → V1 dashboard enum) live → live
00:34 +245: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: source code mapping (Döntés 3 — V2 PracticeSource → V1 dashboard enum) learn → learn
00:34 +246: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: source code mapping (Döntés 3 — V2 PracticeSource → V1 dashboard enum) analyze → analyze
00:34 +247: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: direction aggregate rollups averageDirectionAccuracy ignores NotApplicable entries
00:34 +248: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_progress_aggregator_test.dart: direction aggregate rollups averageDirectionAccuracy returns null when none scored
00:35 +249: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 19999 ms → false
00:35 +250: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 20000 ms → true
00:35 +251: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix activeDuration threshold (20s) 20001 ms → true
00:35 +252: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 3 targets → false
00:35 +253: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 4 targets → true
00:35 +254: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix resolvedRequiredTargets threshold (4) 5 targets → true
00:35 +255: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 7 strums → false
00:35 +256: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 8 strums → true
00:35 +257: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix freePracticeStrums threshold (8) 9 strums → true
00:35 +258: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix all three below thresholds → false
00:35 +259: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix first-win: short active duration but enough targets → true
00:35 +260: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_eligibility_test.dart: A6 — PracticeSessionEligibility threshold matrix at least one threshold met → true
00:37 +261: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_pair_stats_test.dart: ChordPair is immutable and value equal
00:37 +262: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_pair_stats_test.dart: stats expose immutable counts and measured delays
00:37 +263: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/chord_pair_stats_test.dart: invalid stats report validation failures
00:39 +264: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:39 +265: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:39 +266: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:39 +267: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:39 +268: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:39 +269: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:39 +270: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:40 +271: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:41 +272: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:41 +273: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:41 +274: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:41 +275: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:41 +276: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:41 +277: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:41 +278: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:41 +279: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:41 +280: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:41 +281: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:41 +282: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:41 +283: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:41 +284: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:41 +285: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:41 +286: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:41 +287: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:41 +288: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:41 +289: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:41 +290: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:41 +291: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:41 +292: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:41 +293: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:41 +294: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:41 +295: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:41 +296: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:41 +297: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:41 +298: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:41 +299: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:41 +300: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:42 +301: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:42 +302: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:42 +303: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:42 +304: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:42 +305: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:42 +306: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:42 +307: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:42 +308: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:42 +309: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:42 +310: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:42 +311: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:42 +312: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:42 +313: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:42 +314: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:42 +315: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:42 +316: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:42 +317: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:42 +318: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:42 +319: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:42 +320: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:42 +321: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:42 +322: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:42 +323: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:42 +324: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:42 +325: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:42 +326: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:44 +327: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:44 +328: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:44 +329: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:44 +330: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:44 +331: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:45 +332: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:45 +333: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:45 +334: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:45 +335: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:45 +336: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:45 +337: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:45 +338: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:45 +339: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:45 +340: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:45 +341: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:45 +342: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:45 +343: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:45 +344: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:45 +345: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:45 +346: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:45 +347: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:45 +348: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:45 +349: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:45 +350: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:45 +351: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:45 +352: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:45 +353: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:45 +354: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:45 +355: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:47 +356: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:47 +357: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:47 +358: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:47 +359: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:47 +360: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:47 +361: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:47 +362: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:47 +363: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:47 +364: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:47 +365: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:47 +366: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:47 +367: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:47 +368: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:47 +369: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:50 +370: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:50 +371: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:51 +372: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:51 +373: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:51 +374: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:51 +375: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:51 +376: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:51 +377: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:51 +378: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:51 +379: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:51 +380: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:51 +381: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:51 +382: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:51 +383: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:51 +384: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:51 +385: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:51 +386: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:51 +387: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:51 +388: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:51 +389: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:51 +390: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:51 +391: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:51 +392: /home/ubuntu/ss-codex-e02-r19/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:53 +393: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:54 +394: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix running + background → exactly 1 PausePractice(interruption)
00:54 +395: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix paused + background → 0 commands
00:55 +396: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix preparing + background → 0 commands
00:55 +397: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix ready + background → 0 commands
00:55 +398: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + inactive (overlay) → 0 commands
00:55 +399: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards dispose: 0 transient callbacks, host effect-listener count = 0, lifecycle listener count = 0
00:55 +400: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A1 — targetX pure position function target.time == playhead → exactly strikeX (no closeTo)
00:55 +401: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:55 +402: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:55 +403: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:55 +404: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:55 +405: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_lifecycle_test.dart: A7 — leak guards five mount/unmount cycles → 0 lingering listeners
00:55 +406: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:55 +407: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:56 +408: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:56 +409: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:56 +410: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers two consecutive down strokes build two markers
00:56 +411: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A2 — rest and same-direction neighbours are distinct markers a rest slot is rendered without a direction target
00:56 +412: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A3 — 3/4 and 4/4 meter support 3/4 definition builds cleanly
00:56 +413: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A3 — 3/4 and 4/4 meter support 6/8 definition renders without throwing (cosmetic guard)
00:56 +414: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A3 — 3/4 and 4/4 meter support 90 BPM 3/4 bar and beat lines use the painter geometry
00:56 +415: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A4 — visual latency shifts only the drawing visualOffset = 0 → x at strikeX
00:56 +416: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A4 — visual latency shifts only the drawing visualOffset = 60ms → x shifts by 60ms * pps
00:56 +417: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A4 — visual latency shifts only the drawing visualOffset = 200ms → x shifts by 200ms * pps
00:56 +418: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A9 — left-handed mirrors the layout, not the direction meaning leftHanded: true → down event still uses arrow_downward
00:56 +419: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_test.dart: A9 — left-handed mirrors the layout, not the direction meaning leftHanded: false (default) is identical to leftHanded: true for the icon set
00:57 +420: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_import_guard_test.dart: all six files exist on disk
00:57 +421: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Learn-internal symbols are referenced
00:57 +422: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_import_guard_test.dart: no Practice domain service/ import
00:57 +423: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_import_guard_test.dart: no scoring / matcher in the widget layer
00:58 +424: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: 2 000 events, 4 s visibility → examined ≤ 64 and built markers ≤ 64
00:59 +425: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_result_screen_test.dart: A1 — visibility matrix Strum Pattern: chord block is NOT in the tree
01:00 +426: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:00 +427: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:00 +428: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:00 +429: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:00 +430: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:01 +431: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:03 +432: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:03 +433: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:03 +434: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_highway_scaling_test.dart: playhead advances 100 steps → cumulative examined ≤ 100 × 64 and the marker count stays bounded each step
01:03 +435: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/speed_builder_progress_test.dart: A9 — accepting emits exactly one command
01:04 +436: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/speed_builder_progress_test.dart: A9 — accepting emits exactly one command
01:04 +437: loading /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/rhythm_only_view_test.dart
01:05 +437: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/rhythm_only_view_test.dart: A1 — direction-less definition shows the available rhythm row
01:05 +438: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/rhythm_only_view_test.dart: A1 — direction-less definition shows the available rhythm row
01:06 +439: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +440: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +441: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +442: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +443: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +444: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:06 +445: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
01:07 +446: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A1: empty catalog shows the localized empty state
01:07 +447: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
01:07 +448: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:07 +449: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +450: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +451: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +452: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +453: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +454: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +455: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders current and next chord diagrams with a11y labels
01:08 +456: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: renders no detection and insufficient signal as distinct neutral states
01:08 +457: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: marks lossy detector-label mapping in the breakdown
01:08 +458: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: fits without overflow at Size(320.0, 568.0)
01:08 +459: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_change_view_test.dart: fits without overflow at Size(915.0, 412.0)
01:09 +460: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/free_practice_view_test.dart: A7 — null summary shows the explicit "no strums" copy
01:10 +461: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:10 +462: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:10 +463: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:10 +464: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:10 +465: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:10 +466: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:11 +467: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +468: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +469: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +470: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +471: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +472: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +473: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +474: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +475: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +476: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +477: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
01:12 +478: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice/setup?id=<known> builds the Setup
01:13 +479: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice/setup?id=<unknown> shows the localized error
01:13 +480: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
01:13 +481: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
01:13 +482: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
01:14 +483: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
01:15 +484: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
01:15 +485: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix ready shows Start, no count-in overlay
01:15 +486: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix countIn shows the remaining beats overlay
01:15 +487: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:15 +488: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:15 +489: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:15 +490: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +491: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +492: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +493: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +494: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +495: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +496: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +497: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +498: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +499: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +500: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:16 +501: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:17 +502: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:17 +503: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: current + next + upcoming-bar cells render with ChordDiagram
01:17 +504: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix AnnounceAccessibilityFeedback("anything") → 0 calls, no throw
01:17 +505: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: showChordHint=false clears the chord hint (R10 / legacy parity)
01:17 +506: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: showChordHint=false clears the chord hint (R10 / legacy parity)
01:17 +507: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors failed + ShowRecoverableError renders one panel and one error title
01:17 +508: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
01:17 +509: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: four ChordOutcome values render with pairwise distinct signals
01:17 +510: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix preparing: no confirmation, 0 commands, screen stays
01:17 +511: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: upcoming-bar is the chord at the next bar boundary, not the next segment (two-chord-one-bar scenario)
01:17 +512: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix ready: confirmation skipped, 1 CancelPractice
01:17 +513: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix ready: confirmation skipped, 1 CancelPractice
01:17 +514: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/chord_progression_view_test.dart: chord progression view fits without overflow at Size(412.0, 915.0)
01:17 +515: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
01:17 +516: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
01:18 +517: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation shown, confirmed → 1 CancelPractice
01:18 +518: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix running: confirmation shown, confirmed → 1 CancelPractice
01:18 +519: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix paused: confirmation shown, confirmed → 1 CancelPractice
01:18 +520: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix countIn: confirmation rejected → 0 commands, screen stays
01:18 +521: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix finishing: no exit possible, 0 commands
01:18 +522: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix completed: no confirmation, 0 commands
01:19 +523: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_session_screen_test.dart: A4 — exit matrix cancelled: no confirmation, 0 commands
01:19 +524: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias late bias (positive) renders "late", not "balanced"
01:19 +525: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias late bias (positive) renders "late", not "balanced"
01:19 +526: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias late bias (positive) renders "late", not "balanced"
01:19 +527: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias late bias (positive) renders "late", not "balanced"
01:20 +528: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias early bias (negative) renders "early"
01:20 +529: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias a small bias within ±15 ms renders "balanced"
01:20 +530: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias zero bias renders "balanced"
01:20 +531: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/timing_bias_chart_test.dart: M3 — timing bias label is driven by the signed timingBias an empty detail list renders nothing (no chart card)
01:20 +532: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only BPM 29 invalid, 30 valid, 300 valid, 301 invalid
01:20 +533: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only count-in bars -1 / 0 / 2 / 4 / 5 — only 0..4 are valid
01:20 +534: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only loop count 0 / 1 / 32 / 33 — only 1..32 are valid
01:20 +535: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only default config is seeded from the definition
01:20 +536: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
01:22 +537: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/strum_pattern_view_test.dart: renders the pattern preview with down/up/rest cells
01:22 +538: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Rhythm-only hides the chord-hint control
01:22 +539: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/strum_pattern_view_test.dart: perfect verdict shows the Timing label and the Perfect copy
01:22 +540: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility strumPattern shows the scoring profile row
01:22 +541: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility strumPattern shows the scoring profile row
01:22 +542: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility strumPattern shows the scoring profile row
01:22 +543: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape start() sends exactly one PreparePractice with the UI fields
01:22 +544: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
01:23 +545: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: unknown id shows the localized error state
01:23 +546: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
01:23 +547: /home/ubuntu/ss-codex-e02-r19/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
01:23 +548: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A6 — round-trip an entry round-trips through save → load
01:23 +549: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A6 — round-trip every persisted enum decodes via stable code
01:23 +550: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A6 — round-trip duration fields round-trip with microsecond precision
01:23 +551: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A6 — round-trip every persisted enum code round-trips through the serializer
01:23 +552: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A6 — round-trip unknown enum code fails without fallback
01:23 +553: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A7 — corruption, future version, cap a corrupt record is skipped; the rest still loads
01:23 +554: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A7 — corruption, future version, cap a record with future schemaVersion is skipped
01:23 +555: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A7 — corruption, future version, cap cap evicts the oldest record past maxSessions
01:24 +556: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_repository_test.dart: A7 — corruption, future version, cap beyond N sessions, only summary remains; per-attempt detail is stripped
01:24 +557: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +558: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +559: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +560: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +561: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +562: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +563: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata production provider with placeholder metadata writes 0 loadable records
01:24 +564: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/practice_history_recorder_test.dart: B2 — no write-then-drop under placeholder metadata the placeholder gate uses the documented placeholders (isPlaceholderPracticeMetadata)
01:25 +565: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog contains exactly ten definitions in pinned ID order
01:25 +566: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
01:25 +567: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog definition IDs are globally unique
01:25 +568: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog all() returns the same order on repeated calls
01:25 +569: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byId returns the pinned definition and null for unknown IDs
01:25 +570: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byMode returns only definitions of the requested mode
01:25 +571: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byDifficulty returns only definitions of the requested difficulty
01:25 +572: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog firstWaltz is 3/4 with twelve total beats on the quarter grid
01:25 +573: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog titleKey and descriptionKey follow the practiceCatalog regex
01:25 +574: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog free-practice template has no events and an open scoring profile
01:25 +575: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog strumPattern events carry no chord and chordChanges events do
01:25 +576: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
01:25 +577: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog PracticeDefinition integrity event IDs are unique within every definition
01:25 +578: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability events list rejects add() for every catalog definition
01:25 +579: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability skillTags list rejects add() for every catalog definition
01:25 +580: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.gToDChanges.v1 holds G for the first bar, D for the second
01:25 +581: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.emToCChanges.v1 holds Em for the first bar, C for the second
01:26 +582: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
01:26 +583: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
01:26 +584: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
01:26 +585: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
01:26 +586: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
01:26 +587: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
01:26 +588: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
01:26 +589: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
01:26 +590: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
01:26 +591: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
01:26 +592: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
01:26 +593: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
01:26 +594: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
01:26 +595: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
01:27 +596: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
01:27 +597: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
01:27 +598: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
01:27 +599: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
01:27 +600: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
01:27 +601: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
01:27 +602: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
01:27 +603: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
01:27 +604: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
01:27 +605: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
01:27 +606: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
01:27 +607: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
01:27 +608: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
01:27 +609: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
01:27 +610: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
01:27 +611: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
01:27 +612: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
01:27 +613: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
01:27 +614: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
01:27 +615: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
01:27 +616: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
01:27 +617: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
01:27 +618: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
01:27 +619: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
01:27 +620: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
01:27 +621: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
01:27 +622: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
01:27 +623: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
01:27 +624: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
01:27 +625: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
01:27 +626: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
01:27 +627: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
01:27 +628: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
01:27 +629: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
01:27 +630: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
01:27 +631: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
01:27 +632: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
01:27 +633: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
01:27 +634: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
01:27 +635: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
01:27 +636: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
01:27 +637: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
01:27 +638: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
01:27 +639: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
01:27 +640: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
01:27 +641: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
01:27 +642: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
01:27 +643: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
01:27 +644: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
01:27 +645: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
01:27 +646: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
01:27 +647: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
01:27 +648: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
01:27 +649: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
01:27 +650: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
01:27 +651: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
01:27 +652: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
01:30 +653: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
01:30 +654: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
01:30 +655: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
01:30 +656: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
01:30 +657: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
01:30 +658: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
01:30 +659: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
01:30 +660: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
01:30 +661: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
01:30 +662: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
01:33 +663: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
01:33 +664: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
01:33 +665: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
01:33 +666: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
01:33 +667: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
01:33 +668: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
01:33 +669: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
01:33 +670: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
01:33 +671: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
01:33 +672: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
01:33 +673: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
01:33 +674: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
01:33 +675: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
01:33 +676: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
01:33 +677: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
01:35 +678: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
01:35 +679: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
01:35 +680: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
01:35 +681: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
01:35 +682: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
01:35 +683: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
01:35 +684: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
01:35 +685: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
01:35 +686: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
01:35 +687: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
01:35 +688: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
01:35 +689: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
01:35 +690: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
01:35 +691: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
01:35 +692: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
01:35 +693: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
01:35 +694: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
01:35 +695: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
01:35 +696: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
01:35 +697: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
01:35 +698: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
01:35 +699: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
01:35 +700: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
01:35 +701: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
01:35 +702: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
01:35 +703: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
01:35 +704: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
01:35 +705: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
01:35 +706: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
01:35 +707: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
01:35 +708: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
01:35 +709: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
01:35 +710: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
01:35 +711: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
01:35 +712: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
01:35 +713: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
01:35 +714: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
01:35 +715: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
01:35 +716: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
01:35 +717: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
01:35 +718: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
01:35 +719: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
01:35 +720: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
01:35 +721: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
01:35 +722: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
01:35 +723: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
01:35 +724: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
01:35 +725: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
01:35 +726: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
01:36 +727: /home/ubuntu/ss-codex-e02-r19/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
01:38 +728: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: perfect session: result is non-null, scorePoints > 0, navigateToResult fired exactly once
01:38 +729: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: wrong direction: matched strum with wrong direction → directionOutcome == wrong
01:38 +730: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: chord failure: matched strum with wrong chord → chordOutcome == wrong
01:38 +731: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: pause/resume: playingElapsed freezes, pausedElapsed grows, resume reaches running
01:38 +732: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: restart: from paused → countIn with attemptIndex + 1
01:38 +733: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: cancel: user cancel → result == null, recorder.recordCalls == 0
01:38 +734: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: stream failure: observation stream error → ShowRecoverableError, session stays running
01:38 +735: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: no signal: many unmatched strums → direction+rhythm MetricInsufficientData(noSignal)
01:38 +736: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: complete cleanup: FinishPractice → finished → full resource teardown (gateway dispose, tick stop, recorder called once)
01:38 +737: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_integration_test.dart: expected chord sequence: gateway.setExpectedChord called with each segment chord in order, then null on finish
01:39 +738: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
01:39 +739: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
01:39 +740: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
01:40 +741: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
01:40 +742: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
01:40 +743: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
01:41 +744: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
01:41 +745: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
01:41 +746: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
01:41 +747: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
01:41 +748: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
01:41 +749: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
01:41 +750: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
01:41 +751: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
01:41 +752: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
01:41 +753: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
01:41 +754: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
01:41 +755: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
01:41 +756: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
01:41 +757: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
01:41 +758: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
01:41 +759: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
01:41 +760: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
01:42 +761: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 19999 ms active + 0 targets + 0 strums → no record
01:42 +762: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 20000 ms active → records + advances streak
01:42 +763: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 3 resolved required targets → no record
01:42 +764: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 4 resolved required targets → records
01:42 +765: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 7 free-practice strums → no record
01:42 +766: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) 8 free-practice strums → records
01:42 +767: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) cancelled / empty session (eligible=false) → no record
01:42 +768: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A4 — streak-eligibility cell matrix (real call site) second eligible session same day → streak does NOT advance
01:42 +769: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A5 — daily-goal active-time computation 60s active (and the wall-clock seconds go into V1 untouched)
01:42 +770: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A5 — daily-goal active-time computation an ineligible session contributes zero active seconds
01:42 +771: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A5 — daily-goal active-time computation successive eligible calls accumulate the V1 log per moment
01:42 +772: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A6 — Easy mode never overwrites a higher result / never lowers streak a higher Easy result does NOT replace the recorded higher V1
01:42 +773: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: A6 — Easy mode never overwrites a higher result / never lowers streak Easy-mode second session same day does NOT lower the streak
01:42 +774: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: V1 log byte-identity (A10 — V1 store bájtra érintetlen) logged entry mirrors the recorded fields exactly
01:42 +775: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: convenience: SessionEligibilitySnapshot.toInput round-trip
01:42 +776: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_recording_test.dart: the default ok snapshot already clears the 20s active threshold
01:42 +777: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
01:42 +778: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
01:42 +779: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
01:42 +780: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
01:42 +781: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
01:42 +782: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
01:43 +783: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
01:43 +784: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
01:43 +785: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
01:43 +786: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition idle → preparing → ready on PreparePractice + Succeeded
01:43 +787: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition FinishPractice + tick crosses finishing → completed
01:43 +788: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix startCalls == 1 when entering countIn
01:43 +789: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix countIn → running keeps startCalls unchanged
01:43 +790: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix running → paused stops the gateway exactly once
01:43 +791: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix paused → countIn (resume) restarts the gateway (startCalls == 2)
01:43 +792: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight multiple FinishPractice calls produce exactly one record()
01:43 +793: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight finishReason maps to userFinished on FinishPractice
01:43 +794: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix completed: disposeCalls == 1, recordCalls == 1
01:43 +795: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0
01:43 +796: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (b) gateway-start Failure: cancelled, recordCalls == 0
01:43 +797: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix failed (compileTarget Failure) — preparing → failed, recordCalls == 0
01:43 +798: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix permission denied during preparing → permissionRequired
01:43 +799: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix compileTarget Failure → preparing → failed (reducer-origin effect)
01:43 +800: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix gateway.start() Failure → cancelled, recorder NOT called
01:43 +801: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore
01:43 +802: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics playingElapsed freezes during paused; pausedElapsed grows
01:43 +803: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics resume continues the timeline from the bar-boundary anchor (no jump)
01:43 +804: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=0: pause/resume cycle completes
01:43 +805: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=1: pause/resume cycle completes
01:43 +806: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=2: pause/resume cycle completes
01:44 +807: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=0: pause/resume cycle completes
01:44 +808: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=1: pause/resume cycle completes
01:44 +809: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=2: pause/resume cycle completes
01:44 +810: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source gateway receives exactly the controller-provided config
01:44 +811: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 400ms chordStableDuration: 250ms-stable chord run → MetricInsufficientData(chordUnstable)
01:44 +812: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 180ms chordStableDuration: same 250ms run → MetricAvailable
01:44 +813: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A13 — noSignal pinned (current behaviour, NOT a fix) many unmatched strums → direction+rhythm MetricInsufficientData (noSignal); scorePoints == 0 (no matches, but signal was registered)
01:44 +814: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline 100 ticks in running with no observation → liveScore unchanged
01:44 +815: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a ChordObservation alone → liveScore unchanged
01:44 +816: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a StrumObservation → liveScore changes (new aggregation)
01:44 +817: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline FinishPractice alone does not change liveScore (the final pass updates `result`, not `liveScore`)
01:44 +818: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by user → result == null
01:44 +819: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by gateway failure → result == null
01:44 +820: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping failed → result == null
01:44 +821: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A16 — finishing is observable FinishPractice + tick crosses through finishing
01:44 +822: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from countIn is rejected by the reducer
01:44 +823: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from paused is rejected by the reducer
01:44 +824: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) gateway-start failure → cancelled, recorder NOT called (R14 contract)
01:44 +825: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_controller_test.dart: A9 — controller layer-purity guard no forbidden symbol appears in the controller source (ADR 0077 §10 / R10d / R13)
01:44 +826: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
01:44 +827: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
01:44 +828: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
01:44 +829: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
01:44 +830: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
01:44 +831: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
01:44 +832: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
01:44 +833: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
01:46 +834: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
01:46 +835: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
01:46 +836: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
01:46 +837: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
01:46 +838: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
01:46 +839: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
01:46 +840: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
01:46 +841: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
01:46 +842: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
01:46 +843: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
01:46 +844: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
01:46 +845: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
01:46 +846: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
01:46 +847: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
01:46 +848: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
01:46 +849: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
01:46 +850: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
01:46 +851: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
01:46 +852: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
01:46 +853: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
01:47 +854: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
01:47 +855: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
01:47 +856: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
01:47 +857: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
01:47 +858: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
01:47 +859: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
01:47 +860: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
01:47 +861: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused is a no-op (no fields reset)
01:47 +862: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
01:47 +863: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
01:47 +864: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
01:47 +865: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
01:47 +866: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
01:47 +867: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
01:47 +868: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
01:47 +869: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused is a no-op (no fields reset)
01:47 +870: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
01:47 +871: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
01:47 +872: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
01:47 +873: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
01:47 +874: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause is a no-op (clock stays paused, fields intact)
01:47 +875: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
01:47 +876: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
01:47 +877: /home/ubuntu/ss-codex-e02-r19/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
01:47 +878: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/features/learn/
    $ /home/ubuntu/flutter/bin/flutter test test/features/learn/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_v2_scoring_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_v2_scoring_test.dart: Lesson V2 direction scoring A7.0 mutáció: every reversed direction scores zero
00:00 +1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_v2_scoring_test.dart: Lesson V2 direction scoring A7.0 részleges cellák: exact correct-target ratio
00:00 +2: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_v2_scoring_test.dart: Lesson V2 direction scoring A7.0 kvantálás: seven correct targets preserve the exact ratio
00:00 +3: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_v2_scoring_test.dart: Lesson V2 direction scoring A7.0 import tiltás: adapters never name legacy scorer
00:00 +4: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: correct direction within the window is a hit and builds combo
00:00 +5: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: a small timing error still lands inside the window
00:00 +6: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: wrong direction consumes the event and breaks the combo
00:00 +7: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: advancing past an unmatched event marks it missed
00:00 +8: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: an extra strum with no event nearby is ignored
00:00 +9: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: registerStrum returns how it resolved (null when it matched nothing)
00:00 +10: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: finalize turns the remaining open events into misses
00:00 +11: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: passed requires clearing the threshold
00:00 +12: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: chord grading (secondary, lenient) counts chord slots and grades correct chords as hits
00:00 +13: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: chord grading (secondary, lenient) tolerates chord-detection lag (chord arrives just after the stroke)
00:00 +14: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: chord grading (secondary, lenient) wrong chords are missed and never touch the strum score
00:00 +15: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: chord grading (secondary, lenient) a strum-only lesson reports no chords
00:00 +16: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier a dead-on hit is PERFECT and scores the base 100
00:00 +17: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier a hit inside the good window is GOOD (70)
00:00 +18: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier an in-window off-beat hit is EARLY or LATE by sign
00:00 +19: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier combo builds a multiplier that scales points
00:00 +20: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier a miss resets the multiplier and clears the timing
00:00 +21: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: game-feel: timing, points, multiplier wrong direction clears the timing and breaks the multiplier
00:00 +22: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: a slower practice tempo scales the event times
00:00 +23: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_scorer_test.dart: the nearest open event is chosen when two are in range
00:00 +24: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: a consistently late tapper measures a positive offset (median)
00:00 +25: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: an early tapper (taps before the click) measures NEGATIVE
00:00 +26: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: a botched tap (far from every beat) is discarded, not averaged
00:00 +27: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: a single wild-but-valid tap cannot drag the median
00:00 +28: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: no result until enough valid samples
00:00 +29: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: inconsistent tapping is flagged unstable even with enough taps
00:00 +30: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibrator_test.dart: reset clears the run
00:02 +31: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:02 +32: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:02 +33: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:02 +34: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:03 +35: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:05 +36: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: an EASY-mode pass must NOT offer "Next lesson" — Easy deliberately does not advance the curriculum
00:05 +37: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_highway_test.dart: far-future events are not laid out (windowed)
00:05 +38: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: switching to Jam mid-play releases the mic — the frame subscription must close, not idle behind the backing
00:05 +39: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: switching to Jam mid-play releases the mic — the frame subscription must close, not idle behind the backing
00:05 +40: /home/ubuntu/ss-codex-e02-r19/test/features/learn/review_r100_fixes_test.dart: switching to Jam mid-play releases the mic — the frame subscription must close, not idle behind the backing
00:06 +41: /home/ubuntu/ss-codex-e02-r19/test/features/learn/wrapped_prompt_test.dart: a good run (≥80%) offers the weekly share
00:07 +42: /home/ubuntu/ss-codex-e02-r19/test/features/learn/live_scoring_jitter_test.dart: a stale frame is scored at the strum time, not arrival
00:07 +43: /home/ubuntu/ss-codex-e02-r19/test/features/learn/live_scoring_jitter_test.dart: a stale frame is scored at the strum time, not arrival
00:08 +44: /home/ubuntu/ss-codex-e02-r19/test/features/learn/metronome_pref_test.dart: defaults to unmuted and toggles
00:08 +45: /home/ubuntu/ss-codex-e02-r19/test/features/learn/metronome_pref_test.dart: the mute choice persists across a fresh controller
00:09 +46: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +47: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +48: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +49: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +50: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +51: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +52: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:09 +53: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:10 +54: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:10 +55: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:10 +56: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:10 +57: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:10 +58: /home/ubuntu/ss-codex-e02-r19/test/features/learn/waltz_count_in_test.dart: a 3/4 lesson counts in 1-2-3 — never a fourth beat
00:12 +59: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: Lessons.nextAfter walks the curriculum in order
00:12 +60: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: Lessons.nextAfter the last lesson and one-off lessons have no successor
00:12 +61: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +62: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +63: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +64: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +65: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +66: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +67: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +68: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:12 +69: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +70: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +71: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +72: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +73: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +74: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +75: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +76: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:13 +77: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +78: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +79: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +80: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +81: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +82: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +83: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:14 +84: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a PASSED lesson offers "Next lesson" and it opens the curriculum successor
00:15 +85: /home/ubuntu/ss-codex-e02-r19/test/features/learn/next_lesson_cta_test.dart: a FAILED run keeps the focus on retrying — no next-lesson CTA
00:16 +86: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibration_screen_test.dart: a consistent 8-tap run measures the offset and saves it
00:17 +87: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibration_screen_test.dart: a consistent 8-tap run measures the offset and saves it
00:17 +88: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_score_card_test.dart: score card shows the lesson, accuracy, stars and stats
00:17 +89: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_score_card_test.dart: score card shows the lesson, accuracy, stars and stats
00:18 +90: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibration_screen_test.dart: Visual mode saves to the VISUAL latency provider
00:18 +91: /home/ubuntu/ss-codex-e02-r19/test/features/learn/latency_calibration_screen_test.dart: Visual mode saves to the VISUAL latency provider
00:18 +92: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_score_card_test.dart: preview shares the score card image on tap
00:19 +93: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:19 +94: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:19 +95: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:19 +96: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:19 +97: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:19 +98: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +99: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +100: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +101: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +102: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +103: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +104: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +105: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +106: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +107: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +108: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +109: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +110: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +111: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +112: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +113: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +114: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +115: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +116: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +117: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +118: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +119: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +120: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +121: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +122: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +123: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +124: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +125: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +126: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +127: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +128: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +129: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +130: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +131: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +132: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +133: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +134: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +135: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +136: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +137: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +138: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +139: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +140: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +141: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +142: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +143: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +144: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +145: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +146: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +147: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +148: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:20 +149: /home/ubuntu/ss-codex-e02-r19/test/features/learn/setlist_expected_hint_test.dart: the hint crosses a setlist song boundary
00:21 +150: /home/ubuntu/ss-codex-e02-r19/test/features/learn/practice_speed_test.dart: defaults to full speed (1.0)
00:21 +151: /home/ubuntu/ss-codex-e02-r19/test/features/learn/practice_speed_test.dart: a chosen speed persists across a fresh controller
00:21 +152: /home/ubuntu/ss-codex-e02-r19/test/features/learn/practice_speed_test.dart: an off-grid speed is never stored (chips stay representable)
00:21 +153: /home/ubuntu/ss-codex-e02-r19/test/features/learn/practice_speed_test.dart: a speed picked at startup wins over the stored one
00:22 +154: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: a calibrated scorer grades an on-beat player PERFECT despite detection latency
00:22 +155: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: without calibration the same run is NOT perfect (the problem)
00:22 +156: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: large latency would push strums out of the window — calibration keeps them matchable
00:22 +157: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: misses are judged on corrected time (events stay open for the latency tail)
00:22 +158: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: a wrong-direction hit exposes the EXPECTED direction (016b P6 coaching vocabulary)
00:22 +159: /home/ubuntu/ss-codex-e02-r19/test/features/learn/scorer_latency_test.dart: the snapshot carries the expected direction to the UI
00:22 +160: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: recommendedNext fresh install points at the first lesson
00:22 +161: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: recommendedNext advances past passed lessons and is null when all are done
00:22 +162: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:22 +163: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:22 +164: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:22 +165: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:23 +166: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:23 +167: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:23 +168: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: the Learn home shows a Continue card for the next lesson
00:23 +169: /home/ubuntu/ss-codex-e02-r19/test/features/learn/legacy_scorer_baseline_test.dart: replay advances at frame arrival before a de-jittered strum
00:23 +170: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: recording a pass MOVES the card — the list rebuilds on progress change
00:23 +171: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: recording a pass MOVES the card — the list rebuilds on progress change
00:23 +171: /home/ubuntu/ss-codex-e02-r19/test/features/learn/legacy_scorer_baseline_test.dart: GENERATE legacy LessonScorer baseline JSON
  Skip: Set UPDATE_LEGACY_SCORER_BASELINE=1 and run this test by name.
00:23 +171 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: recording a pass MOVES the card — the list rebuilds on progress change
00:24 +172 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/continue_card_test.dart: all lessons passed → no Continue card
00:24 +173 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/learn_screen_test.dart: starts paused, then plays and scores without settling
00:26 +174 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: the highway draws with the calibrated audio↔display skew
00:26 +175 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: the highway draws with the calibrated audio↔display skew
00:26 +176 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: the highway draws with the calibrated audio↔display skew
00:27 +177 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: the highway draws with the calibrated audio↔display skew
00:27 +178 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: the highway draws with the calibrated audio↔display skew
00:27 +179 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/learn_screen_test.dart: practice-speed control scales the tempo
00:27 +180 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/visual_offset_test.dart: uncalibrated devices draw the true playhead (no shift)
00:28 +181 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: emits its full particle count while active
00:28 +182 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: is empty before it starts and after it ends
00:28 +183 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: isDone flips at the end of life (and agrees with particlesAt)
00:28 +184 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: a burst whose start is in the future is inert but NOT done
00:28 +185 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: particles spread outward and fade over time
00:28 +186 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: a stronger (PERFECT) burst reaches farther than a weak one
00:28 +187 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/hit_burst_test.dart: painter repaints only when the clock, bursts or centre change
00:28 +188 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/lesson_list_screen_test.dart: groups lessons by tier and locks the un-earned ones
00:30 +189 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/expected_chord_hint_test.dart: playing a lesson hints the target chord; leaving clears it
00:30 +190 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/expected_chord_hint_test.dart: playing a lesson hints the target chord; leaving clears it
00:31 +191 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/learn_rollback_test.dart: A8 — flag OFF renders the same Play control as the legacy build
00:32 +192 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/learn_rollback_test.dart: A8 — flag OFF leaves the V1 store and lesson-progress untouched
00:32 +193 ~1: /home/ubuntu/ss-codex-e02-r19/test/features/learn/learn_rollback_test.dart: A8 — FeatureFlags.migratedLearnEnabled default is OFF in every env
00:32 +194 ~1: All tests passed!

    → [4] test test/features/learn/: ZÖLD

═══ [5] test test/features/progress/
    $ /home/ubuntu/flutter/bin/flutter test test/features/progress/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +1: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +2: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +3: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +4: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +5: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +6: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +7: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:00 +8: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: empty log shows the empty-state nudge, no chart
00:01 +9: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: populated log shows totals, weekly chart, strum accuracy
00:01 +10: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: populated log shows totals, weekly chart, strum accuracy
00:01 +11: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: daily goal shows "reached" once today crosses the target
00:01 +12: /home/ubuntu/ss-codex-e02-r19/test/features/progress/progress_screen_test.dart: with practice but no scored run, prompts to score in Learn
00:02 +13: /home/ubuntu/ss-codex-e02-r19/test/features/progress/weekly_bars_a11y_test.dart: each bar speaks its weekday and minutes as one fact
00:03 +14: /home/ubuntu/ss-codex-e02-r19/test/features/progress/weekly_bars_a11y_test.dart: each bar speaks its weekday and minutes as one fact
00:03 +15: /home/ubuntu/ss-codex-e02-r19/test/features/progress/weekly_bars_a11y_test.dart: each bar speaks its weekday and minutes as one fact
00:03 +16: /home/ubuntu/ss-codex-e02-r19/test/features/progress/weekly_bars_a11y_test.dart: each bar speaks its weekday and minutes as one fact
00:03 +17: All tests passed!

    → [5] test test/features/progress/: ZÖLD

═══ [6] test test/features/streak/
    $ /home/ubuntu/flutter/bin/flutter test test/features/streak/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +1: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +2: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +3: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +4: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +5: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +6: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +7: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +8: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +9: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:00 +10: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:01 +11: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:01 +12: /home/ubuntu/ss-codex-e02-r19/test/features/streak/streak_screen_test.dart: shows the streak state and today's challenge
00:01 +13: loading /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart
00:02 +13: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:02 +14: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:02 +15: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:02 +16: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:02 +17: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:02 +18: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: shows skill stats with an accuracy trend arrow
00:03 +19: /home/ubuntu/ss-codex-e02-r19/test/features/streak/skill_reframe_test.dart: the skill section hides while there is nothing built yet
00:03 +20: All tests passed!

    → [6] test test/features/streak/: ZÖLD

═══ [7] test test/core/l10n_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/l10n_parity_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r19/test/core/l10n_parity_test.dart
00:00 +0: (setUpAll)
00:00 +0: en and hu define exactly the same keys
00:00 +1: no locale has an empty translation
00:00 +2: hu uses the same placeholders as en
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!

    → [7] test test/core/l10n_parity_test.dart: ZÖLD

═══ [8] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [8] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/features/learn/                                  zöld
    test test/features/progress/                               zöld
    test test/features/streak/                                 zöld
    test test/core/l10n_parity_test.dart                       zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

CI ellenőrzés (teljes suite, randomizált property gate, APK) **nem futott
lokálisan és nem indítottam**: a brief és ADR 0053 szerint ezt az orchestrátor
futtatja; `gh`-t nem hívtam.

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
