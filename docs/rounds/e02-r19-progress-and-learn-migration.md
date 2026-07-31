# E02-R19 — Progress, streak, daily goal és Learn migráció

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
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

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r19-review.md`

Kiemelt figyelem: az A7 korpusz **teljessége** (17 lecke, nem szűkítve), az A8
rollback tényleges kipróbálása, és **eldobható próbateszt** arra, hogy a flag
OFF ág diffje viselkedésre üres (a legacy tesztek átírás nélkül zöldek).
