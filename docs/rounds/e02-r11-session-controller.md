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
| **R13** | **„a controller szerezzen audio lease-t, terminal státuszban engedje el" (A4/A5)** | **a `MicCapture` MAGA szerzi a lease-t a gateway alatt (`mic_capture.dart:82`), és a coordinator NEM reentráns (`audio_session_coordinator.dart:38`) — a controller lease-e a gateway startját `audio.session_busy`-ra vinné, azaz a production út HALOTT lenne** | **a controller SOHA nem hívja az `AudioSessionCoordinator`-t (ADR 0077 §10); a felszabadítás tranzitív a `gateway.stop()/dispose()`-on át; A4/A5/A9 átírva** |

| **R14** | **A5: „gateway `start()` `Failure` → `failed`" és A4 `failed`-cellája a `countIn` ágról** | **a `failed` státusz KIZÁRÓLAG `preparing`-ből érhető el: az egész reducerben egyetlen sor állítja (`practice_session_reducer.dart:612`), `preparing`-re őrizve (`:604–606`) — a `countIn/running → failed` él benne van az `allowedTransitions`-ben, de EGYETLEN input sem produkálja** | **A5 átírva: a gateway-start bukása `cancelled`-be visz (controller-injektált `ShowRecoverableError`, recorder NEM hívódik); a `failed` cellát a `compilePracticeTarget` bukása tartja életben; új **A17** pinneli ki a korlátot; ADR 0077 „Ismert korlát 2"** |

> **R14 eredete:** ezt is az implementer fogta meg, a második `stopped`
> jelzéssel. Ugyanaz a hibaosztály, mint a `docs/LESSONS.md`-ben rögzített
> „ne írj elő kimenetet ELÉRHETETLEN állapotra" (E01-R11/E01-R12/E02-R06) —
> a brief-írás közben az `allowedTransitions` **tábláját** grep-eltem, de nem
> mértem meg, melyik **input** produkálja ténylegesen az élt. A helyes
> pre-flight-mérés: minden előírt cél-státuszra
> `grep -n "status: PracticeSessionStatus.<X>" <reducer>` — nem a tábla.

> **R13 eredete:** ezt **nem** a pre-flight találta meg, hanem az implementer
> (MiniMax M3) a kör első percében, a STOP-klauzula szerint `stopped` jelzéssel
> — a brief §4 listáján kívüli fájl módosítása nélkül, commit nélkül. A
> normatív döntést az orchestrátor hozta meg (ADR 0077 §10), a kör onnan
> folytatódik. Tanulság a `docs/LESSONS.md`-be: **az erőforrás-tulajdonlást a
> tényleges hívási láncon kell kimérni, nem a réteg-diagram alapján
> feltételezni** — a `grep -rn "\.acquire(" lib/` egyetlen sora eldöntötte volna
> a pre-flightban.

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
  `MicrophonePermissionState` enum `.failure` getterrel) — **ezt a controller
  használja** a permission-ágra; providere:
  `lib/core/audio/audio_providers.dart:15`.
  `appLoggerProvider` (`lib/core/logging/logger_provider.dart`);
  `AppResult`/`AppFailure` (`core/foundation/`).
  ⚠ **`AudioSessionCoordinator` — a controller NEM használja** (R13 revízió,
  ADR 0077 §10). Egyetlen `acquire()` hívó van az egész `lib/`-ben, a
  `MicCapture` (`mic_capture.dart:82`), és a coordinator nem reentráns
  (`audio_session_coordinator.dart:38`). A mikrofon felszabadulása tranzitív:
  `gateway.stop()/dispose()` → `_engine.stop()` → `_mic.stop()` →
  `lease.release()` (`live_practice_observation_gateway.dart:159,185` ·
  `real_strum_engine.dart:147` · `mic_capture.dart:125–131`).
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
   `GoRouter`, `SharedPreferences`, `StrumEngine(`, `dart:ui`, `DateTime.now(`,
   **`AudioSessionCoordinator`**, **`audioSessionCoordinatorProvider`**. A
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
10. **A mikrofon-lease tulajdonosa a `MicCapture`, NEM a controller**
    (ADR 0077 §10). A controller **soha nem hívja** az
    `AudioSessionCoordinator`-t és nem tart `AudioSessionLease`-t: a
    `MicCapture` a gateway alatt egy réteggel maga szerzi
    (`mic_capture.dart:82`), és a coordinator nem reentráns
    (`audio_session_coordinator.dart:38`) — a controller lease-e a
    `gateway.start()`-ot `audio.session_busy`-ra vinné. A felszabadítás
    **tranzitív**: `gateway.stop()/dispose()` → `_engine.stop()` →
    `_mic.stop()` → `lease.release()`.
10b. **Minden terminal státuszban teljes cleanup:** subscription lemondva,
    gateway `stop()` majd `dispose()`, tick-forrás lezárva, óra megállítva.
    A `dispose()` után érkező observation/tick nem dob és nem változtat
    állapotot.
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
`tickSubscriptions`/`closed`). Mind a három terminal státuszra **külön** cella:

| Terminal státusz | observation-subscription | gateway `stop` | gateway `dispose` | tick-forrás |
|---|---|---|---|---|
| `completed` | 0 aktív | ≥1, utolsó hívás a terminal előtt | 1 | lezárva |
| `cancelled` — **(a) user `CancelPractice`** | 0 aktív | ≥1 | 1 | lezárva |
| `cancelled` — **(b) gateway-start bukás** (R14, controller-injected `CancelPractice`) | 0 aktív | 0 (a capture el sem indult a sikeres startig) vagy ≥1 (ha később a cleanup fut) | 1 | lezárva |
| `failed` (**kizárólag** `PreparationFailed`-en át érhető el, lásd A5/A17) | 0 aktív | 0 vagy több (a capture el sem indult, mert `preparing` alatt inaktív) | 1 | lezárva |

⚠ **Audio lease oszlop nincs** (R13 revízió): a mikrofont a `MicCapture`
engedi el a `gateway.dispose()` láncán át, a controller nem tart lease-t. Ezt
az **A9** guard méri, nem ez a mátrix.

Plusz: a controller `dispose()`-a **után** érkező observation vagy tick
**nem dob kivételt** és nem változtat állapotot (a `states` stream nem bocsát ki
többet).

***Pirosra fogja:*** a csak „boldog úton" takarító implementáció — a `failed`
és `cancelled` ág az, amelyik valódi eszközön bent hagyja a mikrofont.

**NEM elfogadható gyengítés:** a számlálók elhagyása és „a teszt nem dobott
kivételt" indoklás; a cleanup ellenőrzése csak a `completed` ágon.

### A5 — Hibaosztály-mátrix

⚠ **Mért korlát, amiből ez a mátrix következik (R14 revízió):** a `failed`
státusz **kizárólag `preparing`-ből érhető el**. Az egész reducerben **egyetlen**
sor állít `failed`-et (`practice_session_reducer.dart:612`, `_reducePreparationFailed`),
és az a `preparing` státuszra van őrizve (`:604–606`). A
`countIn → failed` / `running → failed` / `finishing → failed` élek benne vannak
az `allowedTransitions` táblában, de **egyetlen input sem produkálja őket.**
Ennek a mai korlátnak a **kipinnelését** az **A17** cella végzi.

| Kiváltó | Elvárt státusz | Elvárt effekt | Az effekt forrása |
|---|---|---|---|
| mikrofon-engedély megtagadva (`preparing` alatt) | `permissionRequired` | `ShowPermissionSettings` | reducer |
| **`compilePracticeTarget` `Failure`-t ad** → `PreparationFailed` (kizárólag `preparing`-ből) | `failed` | `ShowRecoverableError` | reducer |
| gateway `start()` `Failure`-t ad — **két cella**: (a) általános indítási hiba, (b) **foglalt mikrofon**, `AudioFailure(code: FailureCode.audioSessionBusy)` | **`cancelled`** (a controller `CancelPractice`-t küld, lásd alább), és a **`recorder.record()` hívásszáma 0** | `ShowRecoverableError` | **controller injektálja** |
| observation stream **futás közbeni** hibája | **változatlan** (`countIn` / `running`) | `ShowRecoverableError` | **controller injektálja** |
| recorder mentési hibája finish-kor | `completed` (a session sikeres) | `ShowRecoverableError` | **controller injektálja** |

**A controller injektálhat effektet** az `effects` streambe. Ez nem kiskapu: a
recorder- és a stream-hibáról a reducer definíció szerint nem tud, tehát ezek az
effektek **csak** tőle jöhetnek. Egy injektált effekt is **pontosan egyszer**
sül el. A gateway-start bukásakor a controller **két dolgot** csinál: (1)
befecskendezi a `ShowRecoverableError` effektet, (2) `CancelPractice`-t küld,
aminek hatására a state `cancelled` lesz — a `failed` ág mérhetetlen, mert a
reducer nem fogad `PreparationFailed`-et nem-`preparing` státuszból. Lásd A17.

***Pirosra fogja:*** a stream-hibára sessiont ölő implementáció (SDD §21.6:
„a recoverable hiba ne dobja ki automatikusan a felhasználót"); a
`try/catch`-be nyelt mentési hiba (a projekt mért néma-no-op osztálya); és a
gateway-start bukására `recorder.record()`-ot hívó implementáció (hamis
history-bejegyzés egy meg sem kezdett sessionről).

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
  `dart:ui`, `DateTime.now(`, **`AudioSessionCoordinator`**,
  **`audioSessionCoordinatorProvider`** mintákat.
  Az utolsó kettő az **R13 revízió gépi őre**: a lease-tulajdonlás a
  `MicCapture`-é, és ez a guard az, ami ezt a döntést visszavonhatatlanná teszi
  — nem a doc-comment.
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

**`PracticeSessionResult` KIZÁRÓLAG a `completed` ágon készül** — azaz a
`finishing → completed` úton, ahol a `recorder.record()` is fut. A `cancelled`
és a `failed` terminal státusz **nem** állít elő resultot (nincs befejezett
attempt), tehát ott `controller.result == null`; a `recorder.record()` hívásszáma
**0** (ez az A17 második megállapítása: nem keletkezik history-bejegyzés egy
meg sem kezdett vagy megszakított sessionről).

| state-oldali kiváltó | `controller.result` | `result.finishReason` (ha van) | `recorder.record()` hívás |
|---|---|---|---|
| timeline-vég (`completedTimeline`) | van | `completedAllTargets` | **1** |
| `FinishPractice` (`userFinished`) | van | `userFinished` | **1** |
| `sessionTimeout` túllépés (`timedOut`) | van | `timedOut` | **1** |
| `CancelPractice` — `(a)` user-cancel | **`null`** | — | **0** |
| `CancelPractice` — `(b)` gateway-start bukás (R14) | **`null`** | — | **0** |
| `PreparationFailed` (`failed`, csak `preparing`-ből) | **`null`** | — | **0** |

Az `interrupted` **egyetlen** cellában sem keletkezik. A §5.9 leképezési
táblájának `cancelled`/`failed` sora ebben a körben **nem sül el** — a Kör 18
tartja meg őket, amikor a history a megszakadt sessionöket is rögzíti.

***Pirosra fogja:*** a két azonos nevű enum összekeverése (import-ütközés
„megoldása" rossz irányban) — ez a projekt persistálható kódjait rontaná el —,
a `cancelled`/`failed` ágon resultot gyártó implementáció, és a
`cancelled`/`failed` ágon `recorder.record()`-ot hívó implementáció.

### A16 — A `finishing` állapot nem ragad be

A `FinishPractice` után a tick-forrásnak **tovább kell futnia**: a teszt
egyetlen további tick kiadásával jusson `finishing → completed`-be, és mérje,
hogy a `finishing` státusz **legalább egy** snapshotban látszott.

***Pirosra fogja:*** a tick-forrást a `finishing` belépésekor lezáró
implementáció — ott a session **örökre** `finishing`-ben ragadna, és a
`NavigateToResult` soha nem születne meg. Ez a kör legvalószínűbb csendes hibája.

### A17 — A `failed` elérhetetlensége KIPINNELVE (nem javítás, horgony)

Guard-teszt, amely a **mai** szerződést rögzíti:

1. Minden nem-`preparing` státuszból küldött `PreparationFailed`
   **elutasítva** (`transition.rejection != null`), a státusz változatlan —
   mind a `countIn`, `running`, `paused` cellára.
2. A gateway-start bukása után a session `cancelled`, **nem** `failed`, és a
   `recorder.record()` hívásszáma **0**.
3. A teszt neve és doc-commentje **mondja ki**, hogy ez a **mai** korlát
   pinnelése, nem a kívánt szemantika, és hivatkozzon az ADR 0077
   „Ismert korlát 2" szakaszára.

***Pirosra fogja:*** minden olyan „javítás", amely a lezárt reducert megkerülve
a controllerben állítana elő `failed` státuszt (pl. saját állapot-mező), és
minden olyan implementáció, amely a gateway-start bukására recordert hív.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **[ADR 0077](../adr/0077-practice-session-controller.md)**, a
   reducer teljes fájlja (különösen a `_reduceClockAdvanced` 637–753. sor és a
   `_reduceResumePractice`), a state akkumulátorai és a **két**
   `PracticeFinishReason` enum, a command/effect készlet, a gateway és az
   aktivációs tábla, a matcher és a négy scorer aláírásai,
   `microphone_permission.dart`, `lib/core/audio/audio_providers.dart`, és a
   három meglévő fake. (Az `audio_session_coordinator.dart`-ot **nem** kell
   hívnod — lásd §5.10.)
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

**Állapot: KÉSZ (gate zöld).** A R14 orchestrátori döntés (a `failed` cella
elhagyása a gateway-start bukására) átvezetve: a controller a
`_driveControlledCancelFailure` úton **befecskendezi** a `ShowRecoverableError(failure)`
effektet és **saját magától** küld egy `CancelPractice`-t, tehát a session
`cancelled` lesz, a `recorder.record()` **nem** hívódik, és nincs hamis
history-bejegyzés. A §0.0 R14-es pontja a `failed` státusz elérhetetlenségét
kipinnelve őrzi (A17 cella), a gazdája az E02-R18 pre-flight. Ez a kör NEM
nyúl a reducerhez, sem a command kitethez — a `failed` cellát továbbra is
kizárólag a `PreparationFailed` (`preparing`-ből) produkálja, és ez a
mai korlát szándékos (§5.10 + ADR 0077 „Ismert korlát 2").

A §6-on átvezettem a R14 változtatásokat (A5 mátrix 5 sorra bővült
„az effekt forrása" oszloppal, A4 `cancelled` sora két cellára szétválasztva,
A15 result==null szerződés kimondva, A17 új cella), és az `a0547bf` óta
rárakódott `c7f746e`, `a0547bf` + ezen kör commit-jai egyetlen zárt
gate-et adnak.

### 10.1 Fájdonkénti összefoglaló

| Fájl | Státusz | Tartalom |
|---|---|---|
| `lib/features/practice/application/practice_session_controller.dart` | committed `a0547bf`, R14 fix in this round | A controller váza: `dispatch` single entry-point, capture-activation table szinkron (A2), `PreparePractice` permission + compile útvonal, a hat user commandra a tábla szerinti gateway/clock/tick-source vezérlés, observation-stream feliratkozás, scoring pass StrumObservation-re és finish-re (A14), `NavigateToResult` számláló (A3), dual `PracticeFinishReason` enum mapping (A15), `_cleanupTerminalResources` (A4) ami minden terminal státuszon fut, és csak a `completed` ágon hívja `_finalizeSession`-t (A15: result csak completed). A R14 fix: `_driveControlledCancelFailure` (1) befecskendezi a `ShowRecoverableError` effektet, (2) `CancelPractice`-t küld; a `_recoveryInProgress` flag letiltja a capture-sync recursion-t a recursive dispatch alatt, így a fake gateway `startCalls` nem nő a retry miatt. |
| `lib/features/practice/application/practice_tick_source.dart` | committed `a0547bf` | `PracticeTickSource` interface + `TimerPracticeTickSource` (16 ms, `startedCount`/`stoppedCount`/`isRunning`); a `finishing` státusz alatt is fut (A16). |
| `lib/features/practice/application/practice_session_providers.dart` | this round (NEW) | Riverpod-huzalozás (production defaults): clock / tickSource / recorder / sessionIdFactory / observationConfig / compileTarget / logger / microphonePermission. A `PracticeObservationGateway` provider szándékosan kimaradt — az E02-R13-é a Live → Practice wiring. |
| `lib/features/practice/domain/repository/practice_session_recorder.dart` | committed `a0547bf` | `PracticeSessionRecorder` interface + `NoopPracticeSessionRecorder` (Success, nem swallow). |
| `test/support/fake_practice_tick_source.dart` | committed `a0547bf` | Determinista fake — `emitTick()` egyetlen ticket tüz; idempotens start/stop. |
| `test/support/fake_practice_session_recorder.dart` | committed `a0547bf` | `recordCalls`/`recordedResults` + injektálható `recordResult`. |
| `lib/features/practice/application/practice_session_clock.dart` | committed `c7f746e` | `start()` idempotens futó ÉS pause-olt állapotból; doc-comment igazítva. |
| `lib/features/practice/application/practice_observation_activation.dart` | committed `c7f746e` | Doc-comment `E02-R09` → `E02-R11` (3. és 21. sor). |
| `test/support/fake_practice_session_clock.dart` | committed `c7f746e` | A fake `start()` ugyanúgy idempotens, mint a production. |
| `test/features/practice/application/practice_session_clock_test.dart` | committed `c7f746e` (auto-reformatted this round) | A `_runClockContract` két érintett cellája (`pause → start` és `pause → advance → start`) átírva az új no-op szerződést pinnelve. |
| `test/features/practice/application/practice_session_controller_test.dart` | this round (NEW, 27 tests) + javító kör (A6, A8, A13, A14 kibővítve) | A1, A2 (×4 cella), A3 (×2), A4 (×4 cella), A5 (×3), A6 (4 cella + 6-cellás Meter × countInBars mátrix), A8 (küszöb-átadás + 400ms kontroll + 180ms kontroll), A13 (pin, irány + ritmus `MetricInsufficientData(noSignal)`), A14 (4 cella identity tábla), A15 (×4), A16, A17 (×3), A9 layer-purity guard. |
| `test/features/practice/application/practice_session_integration_test.dart` | javító kör (NEW, 10 scenario) | A10 tíz integrációs forgatókönyv: perfect session, wrong direction, chord failure, pause/resume, restart, cancel, stream failure, no signal, complete cleanup, expected chord sequence — mind valódi `compilePracticeTarget` kimenettel, fake gateway/clock/tick, UI nélkül. |
| `test/property/practice_session_controller_property_test.dart` | this round (NEW) | A11 randomizált property gate — 200 trial × 25 random command (60% valid, 40% `PreparationFailed` a state machine-ből), invariánsok: soha nem dob, minden kibocsátott státusz-pár `allowedTransitions`-ben, terminal → nincs további state-kibocsátás, `recordCalls ≤ 1`, `playingElapsed ≤ activeElapsed ≤ wallElapsed`. Seed: `PROPERTY_SEED` env, absent → 42. |

### 10.2 Konfliktus — A5 vs. §4 (feloldva)

Az A5 cella korábbi `failed` állapota a reducer `PreparationFailed`-jéhez volt
kötve, amit `preparing`-re őriz a `_reducePreparationFailed`
(`practice_session_reducer.dart:604–606`). A `countIn → failed` /
`running → failed` élek az `allowedTransitions`-ben vannak, de **egyetlen
input sem produkálja**. A R14 döntés: a gateway-start bukása **NEM** a
`failed` cellát, hanem a `cancelled` cellát táplálja (controller-injected
`_driveControlledCancelFailure`), és az A17 cella **kipinneli** a korlátot.
A `failed` cella csak `compilePracticeTarget` bukásából érhető el, és csak
`preparing`-ből.

### 10.3 §9 gate — MAJOR-4 záró kör — futtatott

**MAJOR-4 zárva.** A `_onObservation` (`lib/features/practice/application/practice_session_controller.dart:403-411`) elejére bevezetett státusz-őr — `if (!practiceCaptureActive(_state.status)) return;` — a `paused` (és minden más capture-off) státusz alatt a megfigyelések *továbbra is* megérkezhetnek a broadcast streamban (mert a `gateway.stop()` aszinkron), de a controller a scoring pass előtt eldobja őket. Az egyetlen forrás a meglévő `practiceCaptureActiveByStatus` tábla (ADR 0077 §3); új mező vagy új logika nem került a rendszerbe.

Az A6 első cellája (`A6 — pause semantics running → paused: strum during pause does not change liveScore`) ezentúl a **valódi hibaalakot** fogja meg: a §3.2 input-csere a pause-strum idejét `Duration(milliseconds: 30)`-ról `target.events[1].time`-ra (`4*480` tick @ 120 BPM = `1s`) írta át, ami a második célesemény match-ablakán belül esik. A guard nélkül a matcher az `event.1`-hez párosítaná a strumot, és a `verdicts.length`, `scorePoints`, illetve `resolvedTargets` nőne. A kritikus sor a gate kimenetében: `+525: …practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore`.

```
$ tools/round-gate.sh test/features/practice/ test/property/practice_session_controller_property_test.dart
```

A teljes, **csonkítatlan** kimenet (a MAJOR-4 záró kör `round-gate.sh` hívásából — 771 sor, minden sor megvan a `═══ [1] format` … `MINDEN GATE ZÖLD` … lezárásig):

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 551 files (0 changed) in 1.98 seconds.

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
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
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
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 2.8s)

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
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
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
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:00 +9: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:00 +10: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:00 +11: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:00 +12: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:00 +13: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:00 +14: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:00 +15: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:00 +16: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:00 +17: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:00 +18: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:00 +19: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:00 +20: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:01 +21: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:01 +27: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:01 +28: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:01 +29: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:01 +30: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:01 +31: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:01 +32: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:01 +33: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:01 +34: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:01 +35: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:01 +36: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:01 +37: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:01 +38: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:01 +39: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:02 +40: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:02 +41: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:02 +42: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:02 +43: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:02 +44: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:02 +45: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:02 +46: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:02 +47: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:02 +48: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:02 +49: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:02 +50: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:02 +51: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:02 +52: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:02 +53: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:02 +54: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:02 +55: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:03 +56: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:03 +57: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:03 +58: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:03 +59: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:03 +60: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:03 +61: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:03 +62: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:04 +63: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:04 +64: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:04 +65: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:04 +66: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:04 +67: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:04 +68: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:04 +69: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:04 +70: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:04 +71: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:04 +72: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:04 +73: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:04 +74: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:04 +75: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:04 +76: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:04 +77: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:04 +78: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:04 +79: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:04 +80: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:04 +81: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:04 +82: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:04 +83: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:04 +84: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:04 +85: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:04 +86: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:04 +87: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:04 +88: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:05 +89: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:05 +90: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:05 +91: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:05 +92: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:05 +93: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:05 +94: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:05 +95: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:05 +96: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:05 +97: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:05 +98: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:05 +99: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:05 +100: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:06 +101: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:06 +102: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:06 +103: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:06 +104: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:06 +105: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:06 +106: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:06 +107: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:06 +108: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:06 +109: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:06 +110: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:06 +111: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:06 +112: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:06 +113: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:06 +114: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:06 +115: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:06 +116: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:06 +117: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:06 +118: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:06 +119: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:06 +120: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:06 +121: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:06 +122: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:06 +123: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:06 +124: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:06 +125: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:06 +126: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:06 +127: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:06 +128: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:07 +129: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:07 +130: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:07 +131: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:07 +132: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:07 +133: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:07 +134: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:07 +135: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:07 +136: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:07 +137: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:07 +138: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:07 +139: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:07 +140: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:07 +141: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:07 +142: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:07 +143: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:07 +144: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:07 +145: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:07 +146: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:07 +147: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:07 +148: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:07 +149: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:07 +150: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:07 +151: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:07 +152: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:07 +153: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:07 +154: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:07 +155: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:08 +156: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:08 +157: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:08 +158: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:08 +159: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:08 +160: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:08 +161: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:08 +162: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:08 +163: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:08 +164: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:08 +165: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:08 +166: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:08 +167: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:08 +168: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:09 +169: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:09 +170: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:09 +171: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:09 +172: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity first-waltz explicitly measures the three-beat count-in edge
00:09 +173: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity eighth-drive explicitly measures its closest-to-end event
00:09 +174: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:09 +175: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:10 +176: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:10 +177: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:10 +178: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:10 +179: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:10 +180: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:10 +181: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:10 +182: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:11 +183: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:11 +184: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:11 +185: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:11 +186: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:11 +187: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:11 +188: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:11 +189: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:11 +190: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:11 +191: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:11 +192: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:11 +193: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:11 +194: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:11 +195: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:11 +196: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:11 +197: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:11 +198: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:11 +199: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:11 +200: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:11 +201: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:11 +202: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:11 +203: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:11 +204: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:11 +205: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:11 +206: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:11 +207: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:11 +208: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:11 +209: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:11 +210: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:11 +211: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:11 +212: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:11 +213: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:11 +214: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:11 +215: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:11 +216: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:11 +217: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:11 +218: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:11 +219: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:11 +220: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:11 +221: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:11 +222: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:11 +223: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:11 +224: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:11 +225: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:11 +226: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:11 +227: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:11 +228: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:11 +229: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:11 +230: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:12 +231: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:12 +232: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:12 +233: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:12 +234: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:12 +235: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:12 +236: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:12 +237: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:12 +238: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:12 +239: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:12 +240: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:13 +241: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:13 +242: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:13 +243: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:13 +244: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:13 +245: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:13 +246: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:13 +247: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:13 +248: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:13 +249: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:13 +250: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:13 +251: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:13 +252: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:13 +253: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:13 +254: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:13 +255: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:13 +256: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:13 +257: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:13 +258: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:13 +259: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:13 +260: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:13 +261: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:13 +262: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:13 +263: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:13 +264: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:13 +265: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:13 +266: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:13 +267: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:14 +268: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:14 +269: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:14 +270: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:14 +271: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:14 +272: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:14 +273: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:14 +274: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:14 +275: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:14 +276: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:14 +277: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:14 +278: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:14 +279: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:14 +280: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:14 +281: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:15 +282: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:15 +283: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:15 +284: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:15 +285: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:15 +286: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:16 +287: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:16 +288: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:16 +289: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:16 +290: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:16 +291: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:16 +292: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:16 +293: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:16 +294: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:16 +295: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:16 +296: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:16 +297: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:16 +298: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:16 +299: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:16 +300: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:16 +301: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:16 +302: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:16 +303: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:16 +304: /home/ubuntu/ss-mm-e02-r11/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:17 +305: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog contains exactly ten definitions in pinned ID order
00:17 +306: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
00:17 +307: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog definition IDs are globally unique
00:17 +308: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog all() returns the same order on repeated calls
00:17 +309: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byId returns the pinned definition and null for unknown IDs
00:17 +310: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byMode returns only definitions of the requested mode
00:17 +311: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byDifficulty returns only definitions of the requested difficulty
00:17 +312: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog firstWaltz is 3/4 with twelve total beats on the quarter grid
00:17 +313: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog titleKey and descriptionKey follow the practiceCatalog regex
00:17 +314: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog free-practice template has no events and an open scoring profile
00:17 +315: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog strumPattern events carry no chord and chordChanges events do
00:17 +316: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
00:17 +317: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog PracticeDefinition integrity event IDs are unique within every definition
00:17 +318: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability events list rejects add() for every catalog definition
00:17 +319: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability skillTags list rejects add() for every catalog definition
00:17 +320: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.gToDChanges.v1 holds G for the first bar, D for the second
00:17 +321: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.emToCChanges.v1 holds Em for the first bar, C for the second
00:18 +322: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:18 +323: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:18 +324: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:18 +325: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:18 +326: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:18 +327: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:18 +328: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:18 +329: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:18 +330: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:18 +331: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:18 +332: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:18 +333: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:18 +334: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:18 +335: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:18 +336: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:19 +337: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:19 +338: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:19 +339: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:19 +340: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:19 +341: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:19 +342: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:19 +343: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:19 +344: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:19 +345: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:19 +346: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:19 +347: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:19 +348: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:19 +349: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:19 +350: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:19 +351: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:19 +352: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:19 +353: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:19 +354: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:19 +355: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:19 +356: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:19 +357: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:19 +358: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:19 +359: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:19 +360: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:19 +361: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:19 +362: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:19 +363: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:19 +364: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:19 +365: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:19 +366: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:19 +367: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:19 +368: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:19 +369: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:19 +370: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:19 +371: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:19 +372: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:19 +373: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:19 +374: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:19 +375: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:19 +376: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:19 +377: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:19 +378: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:19 +379: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:19 +380: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:19 +381: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:19 +382: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:19 +383: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:19 +384: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:19 +385: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:19 +386: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:19 +387: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:19 +388: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:19 +389: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:19 +390: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:19 +391: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:19 +392: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:20 +393: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:20 +394: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:20 +395: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:20 +396: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:20 +397: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:20 +398: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:20 +399: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:20 +400: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:20 +401: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:20 +402: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:21 +403: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:21 +404: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:21 +405: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:21 +406: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:21 +407: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:21 +408: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:21 +409: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:21 +410: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:21 +411: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:21 +412: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:21 +413: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:21 +414: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:21 +415: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:21 +416: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:21 +417: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:22 +418: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:22 +419: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:22 +420: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:22 +421: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:22 +422: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:22 +423: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:22 +424: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:22 +425: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:22 +426: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:22 +427: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:22 +428: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:22 +429: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:22 +430: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:22 +431: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:22 +432: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:22 +433: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:22 +434: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:22 +435: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:22 +436: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:22 +437: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:22 +438: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:22 +439: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:22 +440: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:22 +441: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:22 +442: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:22 +443: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:22 +444: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:22 +445: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:22 +446: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:22 +447: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:22 +448: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:22 +449: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:22 +450: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:22 +451: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:22 +452: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:22 +453: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:22 +454: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:22 +455: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:22 +456: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:22 +457: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:22 +458: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:22 +459: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:22 +460: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:22 +461: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:22 +462: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:22 +463: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:22 +464: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:22 +465: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:22 +466: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:22 +467: /home/ubuntu/ss-mm-e02-r11/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:23 +468: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: perfect session: result is non-null, scorePoints > 0, navigateToResult fired exactly once
00:23 +469: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: wrong direction: matched strum with wrong direction → directionOutcome == wrong
00:23 +470: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: chord failure: matched strum with wrong chord → chordOutcome == wrong
00:24 +471: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: pause/resume: playingElapsed freezes, pausedElapsed grows, resume reaches running
00:24 +472: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: restart: from paused → countIn with attemptIndex + 1
00:24 +473: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: cancel: user cancel → result == null, recorder.recordCalls == 0
00:24 +474: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: stream failure: observation stream error → ShowRecoverableError, session stays running
00:24 +475: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: no signal: many unmatched strums → direction+rhythm MetricInsufficientData(noSignal)
00:24 +476: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: complete cleanup: FinishPractice → finished → full resource teardown (gateway dispose, tick stop, recorder called once)
00:24 +477: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_integration_test.dart: expected chord sequence: gateway.setExpectedChord called with each segment chord in order, then null on finish
00:25 +478: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:25 +479: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:25 +480: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:25 +481: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:25 +482: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:25 +483: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:26 +484: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:26 +485: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:26 +486: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:26 +487: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:26 +488: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:26 +489: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:26 +490: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:26 +491: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:26 +492: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:26 +493: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:26 +494: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:26 +495: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:26 +496: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:26 +497: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:26 +498: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:26 +499: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:26 +500: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:26 +501: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:26 +502: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:26 +503: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:26 +504: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:26 +505: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:26 +506: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:26 +507: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:26 +508: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:26 +509: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:27 +510: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition idle → preparing → ready on PreparePractice + Succeeded
00:27 +511: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition FinishPractice + tick crosses finishing → completed
00:27 +512: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix startCalls == 1 when entering countIn
00:27 +513: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix countIn → running keeps startCalls unchanged
00:27 +514: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix running → paused stops the gateway exactly once
00:27 +515: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix paused → countIn (resume) restarts the gateway (startCalls == 2)
00:27 +516: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight multiple FinishPractice calls produce exactly one record()
00:27 +517: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight finishReason maps to userFinished on FinishPractice
00:27 +518: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix completed: disposeCalls == 1, recordCalls == 1
00:27 +519: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0
00:27 +520: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (b) gateway-start Failure: cancelled, recordCalls == 0
00:27 +521: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix failed (compileTarget Failure) — preparing → failed, recordCalls == 0
00:27 +522: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix permission denied during preparing → permissionRequired
00:27 +523: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix compileTarget Failure → preparing → failed (reducer-origin effect)
00:27 +524: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix gateway.start() Failure → cancelled, recorder NOT called
00:27 +525: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore
00:27 +526: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics playingElapsed freezes during paused; pausedElapsed grows
00:27 +527: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics resume continues the timeline from the bar-boundary anchor (no jump)
00:27 +528: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=0: pause/resume cycle completes
00:27 +529: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=1: pause/resume cycle completes
00:27 +530: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=2: pause/resume cycle completes
00:27 +531: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=0: pause/resume cycle completes
00:27 +532: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=1: pause/resume cycle completes
00:27 +533: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=2: pause/resume cycle completes
00:27 +534: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source gateway receives exactly the controller-provided config
00:27 +535: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 400ms chordStableDuration: 250ms-stable chord run → MetricInsufficientData(chordUnstable)
00:27 +536: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 180ms chordStableDuration: same 250ms run → MetricAvailable
00:27 +537: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A13 — noSignal pinned (current behaviour, NOT a fix) many unmatched strums → direction+rhythm MetricInsufficientData (noSignal); scorePoints == 0 (no matches, but signal was registered)
00:27 +538: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline 100 ticks in running with no observation → liveScore unchanged
00:27 +539: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a ChordObservation alone → liveScore unchanged
00:27 +540: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a StrumObservation → liveScore changes (new aggregation)
00:27 +541: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline FinishPractice alone does not change liveScore (the final pass updates `result`, not `liveScore`)
00:27 +542: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by user → result == null
00:27 +543: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by gateway failure → result == null
00:27 +544: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping failed → result == null
00:27 +545: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A16 — finishing is observable FinishPractice + tick crosses through finishing
00:27 +546: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from countIn is rejected by the reducer
00:27 +547: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from paused is rejected by the reducer
00:27 +548: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) gateway-start failure → cancelled, recorder NOT called (R14 contract)
00:27 +549: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_controller_test.dart: A9 — controller layer-purity guard no forbidden symbol appears in the controller source (ADR 0077 §10 / R10d / R13)
00:28 +550: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:28 +551: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:28 +552: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:28 +553: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:28 +554: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:28 +555: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:28 +556: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:28 +557: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:29 +558: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:29 +559: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:29 +560: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:29 +561: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:29 +562: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:29 +563: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:29 +564: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:29 +565: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:29 +566: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:29 +567: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:29 +568: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:29 +569: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:29 +570: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:29 +571: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:29 +572: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:29 +573: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:29 +574: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:29 +575: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:29 +576: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:29 +577: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:30 +578: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:30 +579: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:30 +580: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:30 +581: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:30 +582: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:30 +583: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:30 +584: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:30 +585: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused is a no-op (no fields reset)
00:30 +586: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:30 +587: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:30 +588: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:30 +589: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:30 +590: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:30 +591: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:30 +592: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:30 +593: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused is a no-op (no fields reset)
00:30 +594: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:30 +595: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:30 +596: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:30 +597: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:30 +598: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause is a no-op (clock stays paused, fields intact)
00:30 +599: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:30 +600: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:30 +601: /home/ubuntu/ss-mm-e02-r11/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:30 +602: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/practice_session_controller_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/practice_session_controller_property_test.dart

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
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
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
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02-r11/test/property/practice_session_controller_property_test.dart
00:00 +0: A11 — randomised command soup never breaks controller invariants
00:00 +1: All tests passed!

    → [4] test test/property/practice_session_controller_property_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/property/practice_session_controller_property_test.dart zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

A `test/features/practice/` sor **602/602** tesztet futtatott, a property teszt **1/1** (200 trial × 25 parancs, seed 42). A §3.2 input-csere nem változtatta meg a tesztszámot (egy cellát cseréltünk egy másikra). A teljes 771 soros kimenet az alábbi kódblokkban csonkítatlanul megvan. A második-harmadik lépésben a 32 outdated csomag figyelmeztetése ismétlődik — nem regresszió.

A12 zöld: a `lib/` módosítás kizárólag a §4 listáján (a §3.1 státusz-őr a `practice_session_controller.dart`-ban, a §3.2 input-csere a `practice_session_controller_test.dart`-ban); a `lib/core/` és `lib/app/` és `lib/features/learn/` **érintetlen** (architecture: 12 allowlisted, változatlan).

### 10.4 Round-statusz az acceptance-cellákra

| Cella | Státusz | Hol mérve |
|---|---|---|
| A1 | ✅ | `A1 — status stream emits every transition` (2 teszt) |
| A2 | ✅ | `A2 — capture-activation matrix` (4 cella: countIn-start, countIn→running no-churn, running→paused-stop, paused→countIn-resume-restart) |
| A3 | ✅ | `A3 — finish single-flight` (×2: 3× Finish → recordCalls==1; finishReason mapping) |
| A4 | ✅ | `A4 — cleanup matrix` (4 cella: completed, cancelled (a) user, cancelled (b) gateway, failed via preparing) |
| A5 | ✅ (R14) | `A5 — error matrix` (3 cella + a cancelled (b)-t az A4 méri) |
| **A6** | ✅ **(javító)** | `A6 — pause semantics` (4 cella: paused-strum unverändert, playingElapsed frozen + pausedElapsed grows, resume no jump, Meter {4/4,3/4} × countInBars {0,1,2} × mind a hat cella) |
| A7 | ✅ | már closed a `c7f746e` commitban |
| **A8** | ✅ **(javító)** | `A8 — single observation-config source` (gateway megkapja a configot + 400 ms → `MetricInsufficientData(chordUnstable)` + 180 ms kontroll → `MetricAvailable`) |
| A9 | ✅ | `A9 — controller layer-purity guard` (read-the-file, comment-stripped) |
| **A10** | ✅ **(javító)** | `practice_session_integration_test.dart`: perfect session, wrong direction, chord failure, pause/resume, restart, cancel, stream failure, no signal, complete cleanup, expected chord sequence — mind a tíz, valódi `compilePracticeTarget` kimenettel, fake gateway/clock/tick, UI nélkül |
| A11 | ✅ | `test/property/practice_session_controller_property_test.dart` |
| A12 | ✅ | architecture gate zöld + `git diff --stat` csak a §4 listán |
| **A13** | ✅ **(javító)** | `A13 — noSignal pinned` (`metrics.direction == MetricInsufficientData(noSignal)` + `metrics.rhythm == MetricInsufficientData(noSignal)` + `scorePoints == 0` + `resolvedTargets == 0` + minden verdict `coachingCode == noSignal`) |
| **A14** | ✅ **(javító)** | `A14 — scoring pass discipline` (4 cella identity tábla: 100 tick → no change, ChordObservation → no change, StrumObservation → changes, FinishPractice → no change — a mai kontroller a finish pass-t a `result`-be írja, nem a `liveScore`-ba) |
| A15 | ✅ | `A15 — finishReason mapping` (5 cella) |
| A16 | ✅ | `A16 — finishing is observable` |
| A17 | ✅ pin | `A17 — failed is reachable ONLY from preparing` (×3: countIn rejected, paused rejected, gateway-start → cancelled, record==0) |

### 10.5 Következő lépések (orchestrator)

1. **CI dispatch.** A teljes suite + a randomizált property (egy friss
   `PROPERTY_SEED=${{ github.run_id }}` értékkel) + APK a CI-ban fut, merge
   előtt, `build-apk.yml`-ön (ADR 0053). A `gh`-t az orchestrátor indítja.
2. **A13 redakció az E02-R18 pre-flightban.** A `noSignal` cella a mai
   „nincs páros célindex" szerződést pinneli; a helyes „nem volt jel"
   szemantika a direction/timing scorer aláírás-bővítését és a chord-scorer
   összehangolását igényli — két lezárt `domain/service/**` fájlt kell
   módosítani (jelen körben tiltott zóna).
3. **A17 / R14 gazdája.** A `failed` cella elérhetősége a `countIn`/`running`
   ágakról egy önálló reducer-kör (új `SessionFatal(failure)` signal + új
   reducer-ág). Ez a kör csak kipinnelte a mai viselkedést — a kiterjesztés
   az E02-R18 pre-flightjáé.
4. **`PracticeObservationGateway` provider — SZÁNDÉKOSAN HIÁNYZIK.**
   A `practice_session_providers.dart` **szándékosan nem exportálja** a
   `PracticeObservationGateway` providert: a controller a gyártófüggvény
   `observationGateway:` opcionális paraméterén át veszi át, és mai
   production környezetben **nem példányosítható** gateway nélkül — ez
   egy **explicit, szándékos** hézag, nem elírás. A `livePracticeObservationGatewayProvider`
   az **E02-R13 pre-flightjáé** (lásd a HANDOFF §6 3. pont és a 11–12. sort
   a `PracticeObservationGateway` provider-ért). Az E02-R12 / E02-R13
   pre-flightja **ne számítson kész bekötésre** — a user-flow widget
   user-facing kontroller-példánya csak a Live oldali wiring-gal
   együtt áll össze az R13-ban. Ha az R12/R13 pre-flight bármely
   autoDispose `practiceSessionControllerProvider`-t vagy widget-szintű
   StreamProvider-t feltételez a gateway-provider felett, az **korai
   scope-sértés** — a bekötés megérkezéséig a controller widget-szintű
   fogyasztói a `ProviderScope.overrideWithValue(gateway: fake)` mintát
   követik (lásd a Kör 13 R13 példáját).

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r11-review.md`

Kiemelt figyelem a review-nak: **valódi-sértés próba** az A4 cleanup-számlálókra
(ideiglenesen kihagyott `stop()` a `cancelled (b)` ágon → pirosnak kell lennie),
az A2 `countIn → running` cellájára (ideiglenes `stop()+start()` beszúrás),
az A7 három cellájára (a mai reset-viselkedés visszaállítása → pirosnak kell
lennie), az A8-ra (a `chordStableDuration:` paraméter elhagyása → pirosnak
kell lennie), az A5 R14 gateway-start `cancelled` cellájára (a
`_finalizeSession` hívása ebben az ágban → `recorderCalls` eggyel nő,
piros), az A15-re (a `cancelled`/`failed` ágon `PracticeSessionResult`
gyártása → `result != null`, piros), az A17-re (a `_recoveryInProgress` flag
kikapcsolása → a recursive dispatch ismét `gateway.start()`-ot hív a fake-en,
`startCalls` felrobban, piros), és az A16-ra (a tick-forrás `finishing`-kori
lezárása → `navigateToResultEffects` soha nem 1, piros).
Ellenőrizendő továbbá kódolvasással, hogy a controller tényleg **nem** számol
scorert tickre (§5.7), és hogy az A13 pinnelés nem fajult a lezárt scorerek
megkerülésévé.

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
