# E02-R11 — PracticeSessionController orchestration

- **Státusz:** **PLANNING** (pre-flight lefuttatva 2026-07-31, kód mérve: `main` @ `c609b70`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 11"** (+ §11–13, §24.1)
- **Branch:** `mm/e02-r11-session-controller`
- **Előfeltétel:** **E02-R09 és E02-R10 merge-ölve** — mindkettő **✅ teljesül**
  (PR #32 `e7942e6`, PR #33 `59cbca0`).
- **ADR:** **[0077](../adr/0077-practice-session-controller.md)** — **megírva a
  pre-flightban**. Az implementer `docs/adr/`-hez NEM nyúl.
- **Implementer motor:** **MiniMax M3** (user-döntés, 2026-07-31). Az előre
  megírt brief Codexet ajánlott; a user felülírta.

---

## 0.0 Pre-flight brief-revízió (2026-07-31) — TIZENKÉT mért eltérés

Ez a brief 2026-07-31-én, `main` @ `ce8fbce` állapotban készült előre. A kör
indítása előtti kötelező pre-flight **tizenkét** pontban találta avultnak vagy
tévesnek. Mind a tizenkettő javítva lentebb; a revíziók naplója:

| # | Mit állított az eredeti brief | Mért valóság | Feloldás |
|---|---|---|---|
| R1 | az átmenettábla neve `practiceSessionTransitions` (A1, A11) | **`allowedTransitions`**, `practice_session_state.dart:305–306` | név javítva mindenütt |
| R2 | a clock-viselkedés (§5.9) csak `practice_session_clock.dart`-ot érint | a `practice_session_clock_test.dart` **ugyanazt a szerződés-tesztet futtatja a fake-en is** (`_runClockContract`), és a fake bitre másolja a reset-ágat | `test/support/fake_practice_session_clock.dart` **felkerült** a §4 listára |
| R3 | „az R09/R10 API-k a pre-flightig feltételezettek" | kimérve, lásd §2.2 | a §5/§6 konkrét aláírásokra hivatkozik |
| R4 | A8: „a gatewaynek és a scorernek **ugyanaz a példány** megy, value-equality" | a `PracticeChordScorer.score` **`Duration chordStableDuration`**-t vesz át, nem configot — példány-egyenlőség nem mérhető | A8 **viselkedés-alapú** mércére cserélve (nem-alapértelmezett küszöb → mérhetően más chord-metrika) |
| R5 | egy `PracticeFinishReason` enum van | **kettő** van, azonos néven: `practice_session_state.dart:389` és `practice_session_result.dart:11`, **eltérő tagokkal** | kötelező leképezési tábla, ADR 0077 §9 + **A15** |
| R6 | a tick-forrás „terminal státuszban lezárva" — a `finishing` implicit terminalnak látszott | a `finishing → completed` a reducerben **egy KÖVETKEZŐ `ClockAdvanced` tickhez** kötött (`practice_session_reducer.dart:742–746`) | §5.6 kimondja: a tick a `finishing` alatt **is fut**; **A16** méri |
| R7 | a result `id`-járól nem szólt | `PracticeSessionResult.id` kötelező `String`; `DateTime.now()` a tesztet flakyvé tenné | injektált `String Function()` gyár, ADR 0077 §13 |
| R8 | „az R10 NOTE-1-et (direction `noSignal`) ez a kör zárja" | a javítás **két lezárt scorer aláírását** igényli (`domain/service/**`), és a `PracticeTimingScorer` **ugyanettől szenved** (`:78–80`) | **NEM ez a kör zárja** (ADR 0077 „Ismert korlát"); a mai viselkedés **kipinnelve** az **A13** cellában, gazda: E02-R18 pre-flight |
| R9 | §5.4 „a `ScoringProfile → PracticeObservationConfig` leképezés" | a `PracticeDefinition` **közvetlenül hordoz** egy `ScoringProfile` objektumot (`practice_definition.dart:51`) — nincs id→profil feloldó, és nem is kell írni | a controller `state.definition!.scoringProfile`-t használ; a leképezés iránya az ADR 0077 §4-ben rögzítve |
| R10 | §5.5 „a controller olvassa a settings latency providereket" | a `PracticeSessionConfig` **már hordozza** az `inputLatency`/`visualLatency` mezőt (`:45–46`) | a controller **a configból** fagyasztja be; settings providert **nem** olvas |
| R11 | branch `codex/e02-r11-…` | a motor MiniMax M3 | `mm/e02-r11-session-controller` |
| R12 | §7.7 „observation-út → inkrementális snapshot" (mikor fut a scoring pass, nyitva) | tickre futtatott scoring pass SDD §24.1-et sértene és O(tick) munkát adna | ADR 0077 §7: a pass **csak** `StrumObservation`-re és finish-kor fut; **A14** méri |

**Ami NEM változott:** a kör célja, a scope, a tilos zóna szelleme és az A1–A12
mérési filozófiája.

---

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

**Ez a prompt első kötelezettsége.** A munka megkezdésekor, majd érdemi
mérföldköveknél `progress`, a végén pontosan egy lezáró jelzés:

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = **bukott kör**. `gh`-t NE hívj, ne pusholj, PR-t ne
nyiss — az orchestrátor teszi.

**STOP-klauzula:** ha a §4 listáján kívüli fájlt kellene módosítanod, vagy két
előírás egymásnak / a mért állapotnak ellentmond → **`stopped`** + pontos
jelentés arról, mi ütközik. Csendes scope-tágítás, csendes „javítás" egy lezárt
fájlon, és a mérce lazítása egyaránt bukott kör.

**A §7 a TERVED.** Nincs külön task-lista, nincs saját sorrend — a §7 lépéseit
kell végigvinni, abban a sorrendben.

**Doc-comment fegyelem:** csak olyan állítást írj doc-commentbe, amit teszt
bizonyít. `const`, `immutable`, „idempotens", „soha nem dob" — mindegyikhez
tartozzon cella a §6-ban. Bizonyítatlan állítás = hamis állítás.

## 1. Cél

Tíz kör alatt felépült minden alkatrész — időalap, modellek, katalógus,
adapterek, target compiler, óra + state machine, observation gateway, matcher,
scorerek —, **de egyetlen production hívójuk sincs**. Ez a kör az
`application/` rétegben összeköti őket egyetlen **`PracticeSessionController`**-be,
amely UI nélkül, teljesen végigfuttat egy gyakorló-sessiont:
prepare → permission → count-in → run → pause/resume → restart → finish, minden
terminal állapotban teljes erőforrás-felszabadítással.

Ez a kör a `practiceCaptureActiveByStatus` tábla **első valódi hívója**, és ez
zárja az E02-R07 nyitott clock-NOTE-ját, az E02-R08 küszöb-follow-upját és az
E02-R09 NOTE-3-át.

**UI ebben a körben sincs** (az a Kör 12/13). A flagek OFF-ban maradnak, a
production viselkedés változatlan — a controller providere létezik, de a mai
képernyők közül **egy sem** olvassa.

## 2. Jelenlegi állapot (mért tények, `main` @ `c609b70`)

### 2.1 Ami kész és változatlanul használandó

- **State machine (R07):** `domain/model/practice_session_state.dart` — 11
  státusz, a **`allowedTransitions`** const tábla (**305–306. sor**), és a
  `PracticeSessionState` immutable akkumulátorai: `wallElapsed`,
  `activeElapsed`, `pausedElapsed`, `countInElapsed`, **`playingElapsed`**
  („a daily goal kizárólag ezt használja"), `attemptElapsed`, `timelineBase`,
  `activeBase`. Ugyanitt, a **389. sorban** a **state-oldali**
  `PracticeFinishReason` enum (`completedTimeline`, `userFinished`, `cancelled`,
  `timedOut`, `failed`).
- **Pure reducer (R07):** `application/practice_session_reducer.dart` (809 sor).
  Belépési pont: **`PracticeSessionTransition reducePracticeSession(...)`**
  (169. sor). A `PracticeSessionTransition` mezői: `state`, `effects`,
  **`statusPath`** (a lépés által érintett státuszok sorrendben), `rejection`.
  A reducer **soha nem dob** illegális `(state, input)` páron — `rejection`-t ad
  vissza változatlan állapottal.
  - **`finishing → completed` mérve egy KÖVETKEZŐ `ClockAdvanced` tickhez
    kötött** (742–746. sor: `wasFinishing && nextState.status == finishing`).
    A `NavigateToResult` effekt is ott születik.
  - **`ResumePractice` mérve `paused → countIn`-t ad** (342–379. sor), egy bar
    resume-count-innel — **nem** `paused → running`-ot.
  - Automatikus finish két ágon: timeout (`snapshot.wall > config.sessionTimeout`,
    `running` **és** `paused` alatt) — **erősebb** —, illetve timeline-vég
    (`timelinePosition >= target.totalDuration`, csak `running` alatt).
- **Command/signal/effect készlet:** `practice_session_command.dart` (11 command
  + 4 signal: `PreparationSucceeded`, `PreparationFailed`, `PermissionDenied`,
  **`ClockAdvanced(snapshot)`**), `practice_session_effect.dart` (`PlayHaptic`,
  `PlayCountInClick(beatIndex)`, `ShowPermissionSettings`, `NavigateToResult`,
  `ShowRecoverableError(failure)`, `AnnounceAccessibilityFeedback`).
- **Óra (R07):** `application/practice_session_clock.dart` —
  `PracticeSessionClock` interfész (`now()`, `start()`, `pause()`, `resume()`,
  `resetAttempt()`) + `MonotonicPracticeSessionClock`. **Nyitott NOTE:** a
  `start()` **pause alatt teljes resetet** végez (**110. sor**:
  `if (_hasStarted && !_isPaused) return;`), miközben a doc-comment
  idempotenciát ígér. Eddig nem volt valódi hívó — most lesz.
- **Gateway (R08):** `application/practice_observation_gateway.dart` —
  `Stream<PracticeObservation> get observations`,
  `Future<AppResult<void>> start({required PracticeObservationConfig config})`,
  `void setExpectedChord(String?)`, `Future<AppResult<void>> stop()`,
  `Future<void> dispose()`. A `PracticeObservationConfig` alapértékei:
  `strumMinConfidence` 0.55 · `chordMinConfidence` 0.60 ·
  `chordStableDuration` **180 ms** · `maxFrameDeliveryLag` 500 ms; **van
  `==`/`hashCode`** (value-equality) és `validate()`.
  Implementáció: `data/live_practice_observation_gateway.dart`, konstruktora
  `StrumEngine`-t, `MicrophonePermissionGateway`-t, `Duration Function()`
  timeline-órát és `AppLogger`-t vesz át.
- **Aktivációs tábla (R08):** `application/practice_observation_activation.dart`
  — `practiceCaptureActiveByStatus` mind a 11 státuszra (`countIn` + `running`
  → true, minden más → false), és a `practiceCaptureActive(status)` fail-fast
  olvasó. ⚠ A doc-comment **kétszer** „E02-R09 controller"-t említ (3. és 21.
  sor) — a kör-átszámozás miatt elavult, ebben a körben javítandó (`E02-R11`).
- **Matcher (R09):** `domain/service/practice_event_matcher.dart` —
  `PracticeEventMatcher({required CompiledPracticeTarget target, required
  ScoringProfile scoringProfile, required Duration inputLatency})`;
  `PracticeEventMatchResult? registerStrum(StrumObservation)`,
  `void advance(Duration observedAt)`, `void finalize()`,
  `List<PracticeEventMatchResult> get results`, `resolvedTargetCount`,
  `extraStrumCount`. A `target.events` **nem monoton** listáján a viselkedés
  szerződéssértő — de a compiler `StateError`-ral fail-fast
  (`practice_target_compiler.dart:189`).
- **Scorerek + aggregátor (R10), mind `const` osztály:**
  - `PracticeTimingScorer().score({required List<PracticeEventMatchResult> matches, required ScoringProfile scoringProfile})` → `PracticeTimingScore`
  - `PracticeDirectionScorer().score({required List<PracticeEventMatchResult> matches, required Map<int, StrumObservation> observationsByTargetIndex})` → `PracticeDirectionScore`
  - `PracticeChordScorer().score({required List<PracticeEventMatchResult> matches, required List<ChordObservation> observations, Duration chordStableDuration = 180 ms})` → `PracticeChordScore`
  - `PracticeScoreAggregator().aggregate({required matches, required scoringProfile, required PracticeTimingScore timing, required PracticeDirectionScore direction, required PracticeChordScore chord})` → `PracticeScoreAggregation {metrics, verdicts, outcome, overallPerMille}`
  - ⚠ Az aggregátor `_requireAlignedScores`-szal **fail-fast**: a négy lista
    hossza és a `targetIndex`-ek egyezése kötelező. Mindig **ugyanabból** a
    `matcher.results` listából etesd mind a hármat.
  - ⚠ A `PracticeDirectionScorer` **`StateError`-t dob**, ha egy párosult
    célindexnek nincs bejegyzése az `observationsByTargetIndex`-ben, vagy ha a
    bejegyzés `sequence`-e nem egyezik a `match.matchedObservationSequence`-szel.
- **Modellek:** `PracticeSessionConfig` (`definitionId`, `effectiveTempo`,
  `countInBars`, `loopCount`, `scoringProfileId`, **`inputLatency`**,
  **`visualLatency`**, `expectedChordHintEnabled`, `sessionTimeout`, …);
  `PracticeDefinition` — **hordoz egy `ScoringProfile scoringProfile` mezőt**
  (`:51`); `CompiledPracticeTarget` (`events`, `barBoundaries`, `totalDuration`,
  **`expectedChordSegments`** [`chord`, `start`, `end`], `countInDuration`);
  `PracticeAttemptResult({index, tempo, metrics, verdicts, outcome})`;
  `PracticeSessionResult({id, activeDuration, pausedDuration, attempts,
  finishReason, highestStableTempo, coachingSummary})` — a **result-oldali**
  `PracticeFinishReason` (`completedAllTargets`, `userFinished`, `cancelled`,
  `timedOut`, `interrupted`, `failed`).
- **Compiler (R06):** `AppResult<CompiledPracticeTarget> compilePracticeTarget({required PracticeDefinition definition, required PracticeSessionConfig config, PracticeLoopRange? loopRange})`.
- **Core (Epic 1):** `MicrophonePermissionGateway`
  (`core/platform/microphone_permission.dart`: `currentState()`, `request()`,
  `MicrophonePermissionState` enum `.failure` getterrel);
  `AudioSessionCoordinator` (`core/audio/lifecycle/audio_session_coordinator.dart`:
  `Future<AppResult<AudioSessionLease>> acquire(owner, onRevoke)`, exkluzív
  lease, `lease.release()`, ADR 0056); providerek:
  `lib/core/audio/audio_providers.dart` →
  `audioSessionCoordinatorProvider` (26. sor), mikrofon-engedély provider
  (15. sor); `appLoggerProvider` (`lib/core/logging/logger_provider.dart`);
  `AppResult`/`AppFailure` (`core/foundation/`).
- **Tesztsegédek:** `test/support/fake_practice_observation_gateway.dart`
  (`startCalls`, `stopCalls`, `startConfigs`, `expectedChordCalls`,
  `startResult`, `emit()`, `emitError()`) és
  `test/support/fake_practice_session_clock.dart` (`advance(Duration)`,
  `isRunning`) — **ezeket használd**, ne írj újakat.
  ⚠ A `FakePracticeObservationGateway.start()` ma **nem növeli** a
  `startCalls`-t, ha már fut (`if (_running) return const Success(null);`), és a
  `stop()` sem, ha nem fut — azaz a számlálók a **tényleges** állapotváltásokat
  számolják. Ez pont az A2-höz kell; ne írd át.

### 2.2 Ami MA nincs

- Nincs semmilyen controller; a reducert **egyetlen production hívó sem** hívja
  (mérve: `grep -rn "reducePracticeSession" lib/` → csak a reducer saját fájlja).
- Nincs Riverpod-huzalozás a Practice V2-höz a katalóguson kívül (ma összesen
  `practiceCatalogRepositoryProvider` + `practiceCatalogProvider` létezik).
- Nincs eredmény-perzisztencia határ: a `PracticeSessionResult` létezik, de nincs
  repository, ami elmentené (az a **Kör 18**).
- Nincs tick-forrás: a mai legacy `learn_screen.dart` saját `Ticker`-t használ
  (`createTicker(_onTick)`, 88. sor) — ezt a mintát a V2-ben **nem** követjük.
- Nincs `scoringProfileId → ScoringProfile` feloldó, és **nem is kell**: a
  `PracticeDefinition.scoringProfile` maga a profil.

## 3. Scope

**Benne:** egyetlen application-szintű controller + a Riverpod-huzalozása + a
perzisztencia-határ **interfésze** (implementáció nélkül) + a három nyitott
follow-up zárása (clock-idempotencia, aktivációs doc-comment, matcher-forrás) +
integrációs, egység- és property-tesztek fake gatewayjel és fake órával.

**Kívül (ebben a körben TILOS):**

- **Bármilyen UI, widget, képernyő, route** — Kör 12/13.
- **Perzisztencia-implementáció**, `SharedPreferences`, history-írás — Kör 18.
  Ebben a körben csak az **interfész** készül el, és a production provider
  alapértelmezése egy **no-op** implementáció.
- Coaching, adaptív javaslat, Speed Builder attempt-lánc — Kör 17/18.
- `lib/features/learn/**` bármilyen módosítása (a legacy út érintetlen marad).
- A reducer, a state, a command/effect készlet, a gateway, a matcher és a
  scorerek **viselkedésének** módosítása. Ha hiányt találsz bennük → `stopped`
  + jelentés, nem csendes javítás. (Kivétel: a §4-ben nevesített három fájl a
  nevesített okból.)
- **A direction/rhythm `noSignal` szemantikájának javítása** — az ADR 0077
  „Ismert korlát" szakasza szándékosan **kívül** hagyja; a mai viselkedést az
  **A13** cella pinneli ki.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, `pubspec.yaml`, DSP,
  `docs/rag/chunks/**`.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/application/practice_session_controller.dart` | **ÚJ** | a controller |
| `lib/features/practice/application/practice_session_providers.dart` | **ÚJ** | Riverpod-huzalozás (controller, gateway, óra, tick-forrás, recorder, observation-config, id-gyár) |
| `lib/features/practice/application/practice_tick_source.dart` | **ÚJ** | injektálható tick-absztrakció + `Timer.periodic` production implementáció |
| `lib/features/practice/domain/repository/practice_session_recorder.dart` | **ÚJ** | eredmény-perzisztencia **határ** (interfész + `NoopPracticeSessionRecorder`) |
| `lib/features/practice/application/practice_session_clock.dart` | — | **CSAK** a `start()` idempotencia-NOTE zárása (§5.9) + a doc-comment igazítása |
| `lib/features/practice/application/practice_observation_activation.dart` | — | **CSAK** a doc-comment `E02-R09` → `E02-R11` javítása (3. és 21. sor) |
| `test/support/fake_practice_session_clock.dart` | — | **CSAK** a `start()` szerződés követése (R2 revízió) |
| `test/support/fake_practice_session_recorder.dart` | **ÚJ** | hívás-számláló fake a recorderhez |
| `test/support/fake_practice_tick_source.dart` | **ÚJ** | determinisztikus tick-forrás + `tickSubscriptions`/`closed` számlálók |
| `test/features/practice/application/practice_session_controller_test.dart` | **ÚJ** | egység- és él-tesztek |
| `test/features/practice/application/practice_session_integration_test.dart` | **ÚJ** | a §6 A10 tíz forgatókönyve |
| `test/features/practice/application/practice_session_clock_test.dart` | — | az A7 idempotencia-mátrix cellái |
| `test/property/practice_session_controller_property_test.dart` | **ÚJ** | A11 randomizált property gate |
| `docs/rounds/e02-r11-session-controller.md` | — | **CSAK a §10** (handoff) kitöltése |

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/**`, `lib/app/**`
(routing, flagek), `lib/features/practice/domain/model/**`,
`lib/features/practice/domain/service/**`, `lib/features/practice/data/**`,
`lib/core/**`, `docs/adr/**`, `docs/sdd/**`, `HANDOFF.md`, `.github/**`,
`tools/**`, `test/support/fake_practice_observation_gateway.dart`,
`test/tooling/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0077 — NEM tárgyalhatók)

Az ADR 0077 a normatív forrás; itt a végrehajtás szempontjából lényeges tizenöt
pont kivonata.

1. **A controller sosem mutál állapotot közvetlenül.** Minden státuszváltás
   `reducePracticeSession`-ön megy át. A `rejection` nem hiba: redaktáltan
   naplózni, eldobni, állapot változatlan.
2. **Tiltott függőségek a controllerben:** `BuildContext`, `Navigator`,
   `GoRouter`, `SharedPreferences`, `StrumEngine(`, `dart:ui`. A
   `NavigateToResult` **effekt**, nem navigáció.
3. **A capture-aktiváció EGYETLEN forrása a `practiceCaptureActiveByStatus`
   tábla.** Minden elfogadott lépés után — a `statusPath` **minden** elemére,
   nem csak a végállapotra — a controller összeveti a tábla értékét a gateway
   általa vezetett állapotával, és **csak eltérésnél** hív `start()`/`stop()`-ot.
4. **Egyetlen `PracticeObservationConfig` példány.** A controller egy példányt
   tart; ezt adja a `gateway.start(config: …)`-nak, és **ennek a példánynak** a
   `chordStableDuration` mezőjét a `PracticeChordScorer.score(chordStableDuration: …)`-nak.
   A scorer alapértékére hagyatkozni tilos.
5. **Az input latency az attempt kezdetén befagy.** A `StartPractice`
   elfogadásakor `state.config!.inputLatency` **egyszer** olvasódik, és az egész
   attempt alatt ez megy a matchernek. A controller settings providert **nem**
   olvas.
6. **Tick-forrás injektálva, és a `finishing` alatt IS fut.** Nincs közvetlen
   `Timer` a controllerben. Production periódus **16 ms**. A tick **kizárólag**
   `ClockAdvanced(clock.now())` signalt szül — scorer-számítást soha. A forrás
   csak **terminal** státuszban (`completed`/`cancelled`/`failed`) áll le, mert
   a `finishing → completed` egy következő tickhez kötött.
7. **A scoring pass csak `StrumObservation`-re és finish-kor fut.**
   `ChordObservation` érkezésekor a controller csak **gyűjt**. Tickre semmi.
8. **A finish idempotens és single-flight.** Akárhány `FinishPractice` /
   automatikus befejezés: `recorder.record()` **pontosan 1×**, `NavigateToResult`
   **pontosan 1×**, és a `PracticeSessionResult` **ugyanaz az objektum**
   (identitás) minden lekérdezésnél.
9. **A két `PracticeFinishReason` közti leképezés kötött:**
   `completedTimeline → completedAllTargets` · `userFinished → userFinished` ·
   `cancelled → cancelled` · `timedOut → timedOut` · `failed → failed`.
   A result-oldali `interrupted` ebben a körben **nem keletkezik**.
10. **Minden terminal státuszban teljes cleanup:** subscription lemondva,
    gateway `stop()` majd `dispose()`, tick-forrás lezárva, audio lease
    elengedve, óra megállítva. A `dispose()` után érkező observation/tick nem
    dob és nem változtat állapotot.
11. **Hibakezelés** az ADR 0077 §11 táblája szerint. Recoverable hiba **nem**
    dobja ki a felhasználót a sessionből. `try/catch`-be nyelt mentési hiba
    tilos.
12. **Az eredmény-perzisztencia külön use case.** A controller csak a
    `PracticeSessionRecorder` interfészt ismeri
    (`Future<AppResult<void>> record(PracticeSessionResult result)`); a
    production provider alapértelmezése `NoopPracticeSessionRecorder`.
13. **A session-azonosító injektált `String Function()` gyár**
    (`practiceSessionIdFactoryProvider`). `DateTime.now()` közvetlenül a
    controllerben tilos.
14. **A matcher csak `state.target`-ből (compiler-kimenetből) épülhet** — soha
    kézzel összerakott `CompiledPracticeTarget`-ből (E02-R09 NOTE-3 zárása).
15. **A `MonotonicPracticeSessionClock.start()` idempotens lesz:** csak akkor
    zéróz, ha `!_hasStarted`; futó **és** pause-olt állapotban is **no-op**. A
    `test/support/fake_practice_session_clock.dart` fake-et **ugyanígy** kell
    igazítani (közös szerződés-teszt). Az érintett doc-commenteket
    (interfész + implementáció) igazítsd a **tényleges** viselkedéshez.
16. **A logolás redaktált.** Nyers observation-folyam, tartalomnév és teljes
    verdict-lista nem kerülhet logba.

### 5.1 A controller minimális publikus felülete

Ennél többet ne exportálj (a Kör 12/13 ezen fog állni):

- `Stream<PracticeSessionState> get states` — **minden** elfogadott reducer-kimenet,
  `distinct()` **nélkül**;
- `PracticeSessionState get state`;
- `Stream<PracticeSessionEffect> get effects`;
- `PracticeScoreAggregation? get liveScore` — a legutóbbi scoring pass kimenete;
- `PracticeSessionResult? get result`;
- `PracticeObservationConfig get observationConfig`;
- `Future<void> dispatch(PracticeSessionInput input)` (vagy szinkron `void` +
  belső async — a lényeg: egyetlen belépési pont);
- `Future<void> dispose()`.

## 6. Acceptance criteria

Minden pont mellett ott van, **melyik hibás implementációt fogja pirosra**.

### A1 — Minden státuszváltás legális, és minden köztes állapot látszik

**A mérés eszköze (ezt MEGADOM, hogy a mérce ne legyen kikerülhető):** a
controller `states` streamje **minden** elfogadott reducer-kimenetet kibocsát —
köztes állapotokat **nem von össze** és nem `distinct()`-el. A teszt begyűjti a
teljes státusz-sorozatot, és **minden egymást követő `(előző, új)` párt** az
**`allowedTransitions`** tábla ellen ellenőriz.

**NEM elfogadható gyengítés:** csak a kezdő és a végállapot ellenőrzése („a
tranzitív lezárt"); a stream `distinct()`-elése; a köztes `finishing` állapot
elnyelése.

***Pirosra fogja:*** minden olyan implementáció, amely „gyorsítás" céljából
közvetlenül `running → completed`-et állít be a `finishing` kihagyásával.

### A2 — Capture-aktivációs mátrix mind a 11 státuszra

Forgatókönyv-alapú teszt a
`idle → preparing → ready → countIn → running → paused → countIn → running →
finishing → completed` úton (⚠ a resume **`countIn`-be** megy, nem `running`-ba),
**plusz** a `permissionRequired`, `cancelled` és `failed` ágak. A fake gateway
hívásnaplója (`startCalls`, `stopCalls`) alapján cellánként:

| Átmenet / státusz | `practiceCaptureActiveByStatus` | Elvárt gateway-állapot |
|---|---|---|
| `idle`, `preparing`, `permissionRequired`, `ready` | false | nem fut, `startCalls == 0` |
| `ready → countIn` | **true** | `startCalls == 1` |
| `countIn → running` | **true** | **`startCalls` marad 1**, `stopCalls` marad 0 |
| `running → paused` | false | `stopCalls == 1` |
| `paused → countIn` (resume) | **true** | `startCalls == 2` |
| `countIn → running` (resume után) | **true** | `startCalls` marad 2 |
| `finishing` | false | `stopCalls == 2` |
| `completed` / `cancelled` / `failed` | false | leállítva **és** `dispose()`-olva |

***Pirosra fogja:*** a `countIn → running` átmenetnél kiadott felesleges
`stop()+start()` pár (mikrofon-glitch valódi eszközön), és a `paused`-ben futva
hagyott capture (a chunk 014 pause-rése, amit a V2 úton éppen ez zár).

**NEM elfogadható gyengítés:** a tábla megkerülése bármilyen „a controller
úgyis tudja" logikával; a hívásnapló helyett csak a végállapot ellenőrzése.

### A3 — Finish idempotencia

Három `FinishPractice` command + egy automatikus (timeline-vég általi)
befejezés ugyanazon az attempten:

- `PracticeSessionRecorder.record()` hívásszáma: **pontosan 1**;
- `NavigateToResult` effektek száma: **pontosan 1**;
- a `controller.result` **identikusan ugyanaz** az objektum minden
  lekérdezésnél (`identical(a, b)`, nem csak `==`).

***Pirosra fogja:*** a „minden FinishPractice-re mentünk" implementáció — ez
duplikált history-bejegyzést jelentene a Kör 18-ban.

### A4 — Cleanup-mátrix, MÉRVE

A fake-ek számlálókat publikálnak (`startCalls`, `stopCalls`, `disposeCalls`,
`tickSubscriptions`/`closed`, `leaseReleaseCount`). Mind a három terminal
státuszra **külön** cella:

| Terminal státusz | observation-subscription | gateway `stop` | gateway `dispose` | tick-forrás | audio lease |
|---|---|---|---|---|---|
| `completed` | 0 aktív | ≥1, utolsó hívás a terminal előtt | 1 | lezárva | elengedve |
| `cancelled` | 0 aktív | ≥1 | 1 | lezárva | elengedve |
| `failed` | 0 aktív | ≥1 | 1 | lezárva | elengedve |

Plusz: a controller `dispose()`-a **után** érkező observation vagy tick
**nem dob kivételt** és nem változtat állapotot (a `states` stream nem bocsát ki
többet).

***Pirosra fogja:*** a csak „boldog úton" takarító implementáció — a `failed`
és `cancelled` ág az, amelyik valódi eszközön bent hagyja a mikrofont.

**NEM elfogadható gyengítés:** a számlálók elhagyása és „a teszt nem dobott
kivételt" indoklás; a cleanup ellenőrzése csak a `completed` ágon.

### A5 — Hibaosztály-mátrix

| Kiváltó | Elvárt státusz | Elvárt effekt | `AppFailure`? |
|---|---|---|---|
| mikrofon-engedély megtagadva | `permissionRequired` | `ShowPermissionSettings` | — |
| audio lease nem szerezhető (foglalt mikrofon) | `failed` | `ShowRecoverableError` | igen |
| gateway `start()` `Failure`-t ad | `failed` | `ShowRecoverableError` | igen |
| observation stream **futás közbeni** hibája | **változatlan** (`running`) | `ShowRecoverableError` | igen |
| recorder mentési hibája finish-kor | `completed` (a session sikeres) | `ShowRecoverableError` | igen |

***Pirosra fogja:*** a stream-hibára sessiont ölő implementáció (SDD §21.6:
„a recoverable hiba ne dobja ki automatikusan a felhasználót"), és a
`try/catch`-be nyelt mentési hiba (a projekt mért néma-no-op osztálya).

### A6 — Pause alatt nincs pontozás, resume nem ugrik

- `paused` állapotban érkező `StrumObservation`: a `liveScore.verdicts` hossza,
  a `liveScore.metrics.scorePoints` és a `matcher.resolvedTargetCount`
  **változatlan** (mérve a pause előtti/utáni snapshotból).
- `playingElapsed` **nem nő** pause alatt; `pausedElapsed` nő.
- Resume után a `timelinePosition` a reducer bar-anchor szabálya szerint
  folytatódik — **nincs** visszaugrás és nincs előreugrás.
- Mátrix: `Meter ∈ {4/4, 3/4}` × `countInBars ∈ {0, 1, 2}` — mind a **hat** cella.

***Pirosra fogja:*** a „pause alatt is fogadjuk a strumokat, majd eldobjuk a
végén" implementáció, és a resume-nál a count-in span-t kihagyó út.

### A7 — Clock `start()` idempotencia (a NOTE zárása)

A meglévő `_runClockContract` szerződés-teszt **mindkét** implementációra
(monoton + fake) fusson le az új cellákkal:

| Kiinduló állapot | `start()` hatása | Elvárt |
|---|---|---|
| még nem indult | zéróz | `wall == active == paused == attempt == 0` |
| fut | **no-op** | a state-gép mezők deltái nullák |
| **pause-olt** | **no-op** | `paused` **nem** nullázódik (ma reset történik!), és a clock **pause-olt marad** (`isRunning == false` a fake-en) |

Plusz: a `resetAttempt()` továbbra is **csak** az `attempt` akkumulátort nullázza.

***Pirosra fogja:*** a mai (mért) viselkedés — a pause-olt cella ma **piros**, és
ettől a körtől zöld. Ha a fake-et nem igazítod, a szerződés-teszt a fake-en
marad piros.

### A8 — Egyetlen observation-config forrás, VISELKEDÉSSEL mérve

A `chordStableDuration` példány-azonossága nem mérhető (a scorer `Duration`-t
vesz át), ezért a mérce **viselkedés-alapú**:

1. A teszt a controllert **nem alapértelmezett** observation-configgal indítja:
   `chordStableDuration = 400 ms` (az alapérték 180 ms).
2. `expect(gateway.startConfigs.single.chordStableDuration, const Duration(milliseconds: 400))`.
3. Olyan chord-megfigyelés-sorozatot etet, amely **250 ms**-ig stabil egy
   célesemény ablakában — azaz **elég 180 ms-hoz, kevés 400 ms-hoz**.
4. Elvárás: a `liveScore.metrics.chord` **`MetricInsufficientData`**
   (`chordUnstable` vagy `insufficientSamples` ok), **nem** `MetricAvailable`.
5. Kontroll-cella: ugyanaz a bemenet 180 ms-os configgal → `MetricAvailable`.

***Pirosra fogja:*** a `PracticeChordScorer.score(...)` **alapértékkel** hívása
(a `chordStableDuration:` paraméter elhagyása) — a 4. cella `MetricAvailable`-t
adna.

### A9 — Réteg-tisztaság

- Guard-teszt a **saját** tesztfájlodban (ne bővítsd a `test/tooling/`-ot): a
  `practice_session_controller.dart` forrása **nem tartalmazza** a
  `BuildContext`, `Navigator`, `GoRouter`, `SharedPreferences`, `StrumEngine(`,
  `dart:ui`, `DateTime.now(` mintákat.
- `tools/round-gate.sh` **architecture** lépése zöld; az allowlist nem bővül.

### A10 — Integrációs forgatókönyvek (SDD Kör 11, mind a tíz)

Fake gatewayjel, fake órával és fake tick-forrással, UI nélkül: perfect session ·
wrong direction · chord failure · pause/resume · restart · cancel ·
stream failure · no signal · complete cleanup · expected chord sequence.

Mindegyik forgatókönyv **állítson a kimenetre is**, ne csak arra, hogy nem
dobott: a `PracticeSessionResult` metrikái, a státusz-sorozat és a
cleanup-számlálók. Az „expected chord sequence" külön ellenőrizze, hogy a
`gateway.setExpectedChord(...)` a `target.expectedChordSegments` szerint
frissül (a `expectedChordCalls` napló a szegmensek `chord` értékeit adja,
sorrendben), és **finish-kor `null`-ra** áll.

**NEM elfogadható gyengítés:** `expect(() => ..., returnsNormally)` típusú
állítás bármelyik forgatókönyvben.

### A11 — Randomizált property gate

`test/property/practice_session_controller_property_test.dart`, `PROPERTY_SEED`
(hiány → 42). Véletlen **command-sorozatokra** (érvényes és érvénytelen
parancsok vegyesen), legalább **200 sessionre**:

1. a controller **soha nem dob** kivételt;
2. minden kibocsátott státusz-pár szerepel az **`allowedTransitions`** táblában;
3. terminal státusz elérése után **nulla** aktív subscription és **nulla**
   további állapot-kibocsátás;
4. a `record()` hívásszáma sessiononként **legfeljebb 1**;
5. `playingElapsed <= activeElapsed <= wallElapsed` **minden** snapshotban.

### A12 — Nulla production viselkedésváltozás

- `git diff --stat origin/main...HEAD` → a `lib/` alatt kizárólag a §4 listája;
  `lib/features/learn/` **0 sor**, `lib/app/` **0 sor**, `lib/core/` **0 sor**.
- `grep -rn "practiceSessionControllerProvider" lib/features/ | grep -v practice/`
  → **üres**.
- A `flutter test` teljes suite-ja a CI-ban változatlanul zöld.

### A13 — A `noSignal` mai szemantikája KIPINNELVE (nem javítás, horgony)

Egy attempt, amelyben a felhasználó **sok** strumot ad, de **egyik sem** esik
egyetlen célablakba sem (mind a `matchWindow`-n kívül):

- `liveScore.metrics.direction` **`MetricInsufficientData(noSignal)`**;
- `liveScore.metrics.rhythm` **`MetricInsufficientData(noSignal)`**;
- `matcher.extraStrumCount > 0` (azaz **volt** jel).

A teszt neve és doc-commentje **mondja ki**, hogy ez a **mai** viselkedés
pinnelése, nem a kívánt szemantika, és hivatkozzon az ADR 0077 „Ismert korlát"
szakaszára + az E02-R10 review NOTE-1-re.

***Pirosra fogja:*** minden olyan „javítás", amely a lezárt scorereket
megkerülve, a controllerben hamisítaná meg a bemenetet (pl. szintetikus
bejegyzés az `observationsByTargetIndex`-be) — ez a cella azt is megfogja.

### A14 — A scoring pass csak strumra és finish-kor fut

Számlálós mérés (a teszt a `liveScore` **identitását** figyeli):

| Esemény | Változik-e a `liveScore` referencia? |
|---|---|
| 100 tick `running` alatt, observation nélkül | **nem** (`identical` marad) |
| egy `ChordObservation` | **nem** |
| egy `StrumObservation` | **igen** |
| `FinishPractice` (finish-kori pass) | **igen** |

***Pirosra fogja:*** a tickenként újraszámoló implementáció — valódi eszközön
16 ms-onként végigfuttatná a négy scorert az egész eseménylistán.

### A15 — Finish-reason leképezés mind az öt cellája

| state-oldali kiváltó | `result.finishReason` |
|---|---|
| timeline-vég (`completedTimeline`) | `completedAllTargets` |
| `FinishPractice` (`userFinished`) | `userFinished` |
| `CancelPractice` (`cancelled`) | `cancelled` |
| `sessionTimeout` túllépés (`timedOut`) | `timedOut` |
| fatal hiba (`failed`) | `failed` |

Az `interrupted` **egyetlen** cellában sem keletkezik.

***Pirosra fogja:*** a két azonos nevű enum összekeverése (import-ütközés
„megoldása" rossz irányban) — ez a projekt persistálható kódjait rontaná el.

### A16 — A `finishing` állapot nem ragad be

A `FinishPractice` után a tick-forrásnak **tovább kell futnia**: a teszt
egyetlen további tick kiadásával jusson `finishing → completed`-be, és mérje,
hogy a `finishing` státusz **legalább egy** snapshotban látszott.

***Pirosra fogja:*** a tick-forrást a `finishing` belépésekor lezáró
implementáció — ott a session **örökre** `finishing`-ben ragadna, és a
`NavigateToResult` soha nem születne meg. Ez a kör legvalószínűbb csendes hibája.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **[ADR 0077](../adr/0077-practice-session-controller.md)**, a
   reducer teljes fájlja (különösen a `_reduceClockAdvanced` 637–753. sor és a
   `_reduceResumePractice`), a state akkumulátorai és a **két**
   `PracticeFinishReason` enum, a command/effect készlet, a gateway és az
   aktivációs tábla, a matcher és a négy scorer aláírásai,
   `audio_session_coordinator.dart`, `microphone_permission.dart`,
   `lib/core/audio/audio_providers.dart`, és a három meglévő fake.
2. `PracticeTickSource` (interfész + `Timer.periodic` production) + a fake
   tick-forrás a `test/support/` alatt.
3. `PracticeSessionRecorder` interfész + `NoopPracticeSessionRecorder` + fake.
4. A controller váza: prepare → permission → ready (még capture nélkül) + A1.
5. A capture-életciklus a tábla szerint (§5.3, a `statusPath` minden elemére) + A2.
6. Count-in, tick → `ClockAdvanced`, count-in click effektek + A16.
7. Observation-út: matcher → négy scorer → `liveScore` (A6, A8, A14).
8. Pause/resume/restart/cancel + A6 hat cellája.
9. Finish (single-flight) + recorder + finish-reason leképezés (A3, A15).
10. Hibaágak (A5); cleanup (A4); `noSignal` pinnelés (A13).
11. A clock `start()` idempotencia (§5.15) a production fájlban **és** a
    fake-ben + A7 — **külön commit**, hogy a review a NOTE zárását önmagában is
    lássa.
12. Integrációs forgatókönyvek (A10), property-teszt (A11), réteg-guard (A9),
    diff-ellenőrzés (A12).
13. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **Ez a legnagyobb integrációs felület az epicben.** Ha a scope tágulni akar
  (pl. „mindjárt megírom a history-mentést is"), az `stopped` + jelentés.
- **A `finishing` beragadás** (A16) — a legvalószínűbb csendes hiba; a reducer
  742–746. sora a bizonyíték, hogy a tick a `finishing` alatt is kell.
- **Két azonos nevű `PracticeFinishReason` enum** — importáláskor `as` prefix
  vagy szelektív import kell; a leképezés a §5.9 táblája szerint.
- **Riverpod 3.3.2:** `AsyncValue.value` (nullable), **NEM** `.valueOrNull`.
  A `ref.listenManual` előfizetést **kézzel** kell lemondani — ez pontosan az
  A4 mérésének tárgya.
- **A reducer elutasítja a második `StartPractice`-t.** Ha a controller
  „biztonságból" kétszer küldi, néma no-opot kapsz — az A1 státusz-sorozata
  fogja meg.
- **Az aggregátor és a direction-scorer fail-fast dob** (`_requireAlignedScores`,
  `StateError` a hiányzó/eltérő sequence-ű bejegyzésre). Mindig ugyanabból a
  `matcher.results` listából etesd mind a négy hívást, és az
  `observationsByTargetIndex`-be **pontosan** azt a `StrumObservation`-t tedd,
  amelyet a matcher párosított.
- **A `MonotonicPracticeSessionClock.start()` átírása viselkedésváltozás** egy
  kész kör fájljában — ezért van külön acceptance-cellája (A7) és külön
  commitja, és ezért **kell** a fake-et is igazítani. Ha a meglévő
  `practice_session_clock_test.dart` bármely **más** tesztje pirosra vált, az
  **megállás és jelentés** — nem a teszt átírása.
- **Fal-óra a tesztben.** Semmilyen `await Future.delayed`-alapú időzítés: a
  fake óra és a fake tick-forrás determinisztikus. Egy flaky teszt itt a teljes
  CI-t megbízhatatlanná teszi.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/practice_session_controller_property_test.dart
```

Csővezeték nélkül — **se `| tail`, se `| head`, se `| grep`, se `&&` láncolás** —,
és a **teljes, csonkítatlan** kimenetet másold a §10-be. A teljes suite +
property gate + APK a CI-ban fut, merge előtt, orchestrátor-dispatch-csel
(ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A16
pontok teljesülése bizonyítékkal · eltérések és okuk · nem futtatott ellenőrzések
és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r11-review.md`

Kiemelt figyelem a review-nak: **valódi-sértés próba** az A4 cleanup-számlálókra
(ideiglenesen kihagyott `stop()` a `failed` ágon → pirosnak kell lennie), az A2
`countIn → running` cellájára (ideiglenes `stop()+start()` beszúrás), az A7
három cellájára (a mai reset-viselkedés visszaállítása → pirosnak kell lennie),
az A8-ra (a `chordStableDuration:` paraméter elhagyása → pirosnak kell lennie)
és az A16-ra (a tick-forrás `finishing`-kori lezárása → pirosnak kell lennie).
Ellenőrizendő továbbá kódolvasással, hogy a controller tényleg **nem** számol
scorert tickre (§5.7), és hogy az A13 pinnelés nem fajult a lezárt scorerek
megkerülésévé.
