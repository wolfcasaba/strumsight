# ADR 0077 — `PracticeSessionController`: az első valódi hívó és az erőforrás-életciklus tulajdonosa

**Státusz:** elfogadva (E02-R11 pre-flight, 2026-07-31).
Épít az [ADR 0056](0056-audio-session-lease.md) (exkluzív audio lease),
[ADR 0066](0066-practice-beat-position-tick.md) (µs időalap),
[ADR 0072](0072-practice-target-compiler.md) (compiled target),
[ADR 0073](0073-practice-session-state-machine.md) (state machine + reducer),
[ADR 0074](0074-practice-observation-gateway.md) (observation gateway),
[ADR 0075](0075-practice-event-matcher.md) (matcher) és
[ADR 0076](0076-practice-scoring-dimensions.md) (scorerek) döntéseire.
Kör: [`docs/rounds/e02-r11-session-controller.md`](../rounds/e02-r11-session-controller.md).

## Kontextus

Tíz kör alatt felépült a Practice V2 minden alkatrésze — időalap, modellek,
katalógus, legacy adapterek, target compiler, óra + pure reducer, observation
gateway, matcher, négy scorer —, de **egyetlen production hívójuk sincs**.
Mérve (`main` @ `c609b70`):

```
grep -rn "reducePracticeSession" lib/   → csak a reducer saját fájlja
grep -rn "practiceCaptureActiveByStatus" lib/ → csak a definíciója
```

A `lib/features/practice/application/` alatt ma két Riverpod provider él
(`practiceCatalogRepositoryProvider`, `practiceCatalogProvider`), semmi más.

Ez a kör az első hívó. Két kockázata mért, nem elméleti:

1. **A mikrofon-életciklus a valódi eszközön romlik el, nem a tesztben.** A
   chunk 014 rögzített pause-rése (pause alatt futva hagyott capture) és a
   `countIn → running` átmenetnél kiadott felesleges `stop()+start()` pár
   (mikrofon-glitch) olyan hibák, amelyeket csak hívásnapló-alapú mérés fog meg,
   végállapot-ellenőrzés nem.
2. **A `finishing → completed` átmenet a reducerben egy KÖVETKEZŐ
   `ClockAdvanced` tickhez van kötve** (`practice_session_reducer.dart:742–746`:
   `wasFinishing && nextState.status == finishing`). Aki a tick-forrást a
   `finishing` belépésekor lezárja, **örökre `finishing`-ben ragad** — a session
   soha nem fejeződik be, a `NavigateToResult` soha nem születik meg.

## Döntés

### 1. A controller sosem mutál állapotot közvetlenül

Minden státuszváltás a pure `reducePracticeSession(state, input)`-en megy át. A
controller feladata három dolog, és csak ez a három: **input előállítás**
(command/signal), **effekt-továbbítás**, és az **erőforrás-életciklus**
(gateway, tick-forrás, audio lease, subscription, óra).

Következmény: a `PracticeSessionTransition.rejection` nem hiba — a controller
naplózza (redaktáltan) és eldobja; az állapot változatlan marad.

### 2. Tiltott függőségek

A `practice_session_controller.dart` forrásában nem szerepelhet `BuildContext`,
`Navigator`, `GoRouter`, `SharedPreferences`, `StrumEngine(`, `dart:ui`,
`DateTime.now(`, **`AudioSessionCoordinator`** és
**`audioSessionCoordinatorProvider`** (lásd §10). Navigáció **nem** a controller
dolga: a `NavigateToResult` **effekt**, amit a Kör 13 UI-ja hajt végre.

### 3. A capture-aktiváció egyetlen forrása a státusztábla

Minden elfogadott reducer-lépés **után** a controller összeveti a
`practiceCaptureActive(status)` értékét a gateway tényleges (általa vezetett)
állapotával, és **csak eltérésnél** hív `start()`-ot vagy `stop()`-ot. Ez
zárja ki a `countIn → running` átmenet felesleges `stop()+start()` párját: a
tábla mindkét státuszra `true`, tehát nincs teendő.

A `statusPath` **minden köztes elemére** külön kiértékelés történik, nem csak a
végállapotra — a reducer egyetlen lépésben is átvihet több státuszon
(pl. `running → finishing → completed`).

### 4. Egyetlen `PracticeObservationConfig` példány

A controller egy **példányt** tart, azt adja a gatewaynek
(`start(config: …)`), és **ugyanennek a példánynak** a `chordStableDuration`
mezőjét adja a `PracticeChordScorer.score(chordStableDuration: …)` hívásnak.
Két külön beírt alapérték tilos. Ez az E02-R08 nyitva hagyott
„`ScoringProfile → PracticeObservationConfig` küszöb-leképezés" follow-upjának
zárása: a leképezés **iránya** rögzítve — az observation-oldali stabilitási
küszöb a forrás, a scorer ezt kapja, nem fordítva.

### 5. Az input latency az attempt kezdetén befagy

A `PracticeSessionConfig.inputLatency` mezőjét a controller a `StartPractice`
elfogadásakor **egyszer** olvassa ki, és az egész attempt alatt ugyanazt az
értéket adja a `PracticeEventMatcher`-nek. Attempt közbeni beállítás-változás a
**következő** attemptre hat. A settings providereket (`inputLatencyProvider`,
`visualLatencyProvider`) a controller **nem** olvassa — azok a
`PracticeSessionConfig` összeállításakor (Kör 12 UI) kerülnek bele.

### 6. Tick-forrás injektálva, és a terminal státuszig él

A controller nem hoz létre `Timer`-t: `PracticeTickSource` absztrakció mögül
kapja. Production periódus **16 ms**; a teszt determinisztikus fake forrást ad.
A tick **kizárólag** `ClockAdvanced` signalt szül — scorer-számítást **soha**
(SDD §24.1).

A tick-forrás a `finishing` státuszban **is fut**, és csak **terminal**
státuszban (`completed` / `cancelled` / `failed`) áll le. Indoklás: a
`finishing → completed` átmenet a reducerben egy következő `ClockAdvanced`
tickhez kötött (lásd Kontextus/2).

### 7. A scoring pass kizárólag `StrumObservation`-re és finish-kor fut

A `matcher.registerStrum(...)` + a négy scorer + az aggregátor teljes köre
**csak** akkor fut le, amikor új `StrumObservation` érkezik, plusz **egyszer**
a finish során (a `matcher.finalize()` után). `ChordObservation` érkezésekor a
controller csak **gyűjt** (a chord-scorer bemeneti listájába), és tickre semmit
nem számol. Ez SDD §24.1 („csak új observation indítson strum verdict
számítást") szó szerinti olvasata, és ez tartja a tickre eső munkát konstansban.

### 8. A finish idempotens és single-flight

Akárhány `FinishPractice` / automatikus befejezés (timeout, timeline-vég)
érkezik, a `PracticeSessionRecorder.record()` **pontosan egyszer** hívódik, és
**pontosan egy** `NavigateToResult` effekt keletkezik. Az elkészült
`PracticeSessionResult` ezután **ugyanaz az objektum** minden lekérdezésnél
(identitás, nem csak érték-egyenlőség).

### 9. Két `PracticeFinishReason` enum van — a leképezés itt rögzül

Mért tény: a `practice_session_state.dart:389` és a
`practice_session_result.dart:11` **két különböző**, azonos nevű enumot
definiál. A controller a state-oldaliból a result-oldalira képez:

| state-oldali (`practice_session_state.dart`) | result-oldali (`practice_session_result.dart`) |
|---|---|
| `completedTimeline` | `completedAllTargets` |
| `userFinished` | `userFinished` |
| `cancelled` | `cancelled` |
| `timedOut` | `timedOut` |
| `failed` | `failed` |

A result-oldali `interrupted` ebben a körben **nem keletkezik** — az
alkalmazás-életciklus (háttérbe kerülés) kezelése a Kör 18 hatásköre.

### 10. A mikrofon-lease tulajdonosa a `MicCapture`, NEM a controller

**Ez a döntés az eredeti ADR-vázlat javítása** — az implementer a kör indítása
után `stopped` jelzéssel megfogta, hogy a vázlat „a controller szerezzen audio
lease-t" előírása a production utat **halottá tette volna**. A mérés:

| # | Tény | Bizonyíték |
|---|---|---|
| 1 | a `LivePracticeObservationGateway.start()` a `StrumEngine`-t indítja | `live_practice_observation_gateway.dart:113` |
| 2 | a `RealStrumEngine.start()` a `MicCapture.start()`-ot hívja | `real_strum_engine.dart:71` |
| 3 | a `MicCapture._doStart()` **maga szerzi** a lease-t | `mic_capture.dart:82` |
| 4 | a coordinator **nem reentráns**: aktív lease mellett minden `acquire()` `audio.session_busy` hibát ad — **akkor is, ha ugyanaz az `AudioOwner` kéri** | `audio_session_coordinator.dart:38–50` |
| 5 | a `MicCapture` az egyetlen `acquire()` hívó az egész `lib/`-ben | `grep -rn "\.acquire(" lib/` → egyetlen találat |

Ha tehát a controller előbb megszerezné a lease-t, a gateway által indított
`MicCapture` második kérése **szükségszerűen** megbukna, és a production
session soha nem tudna capture-t indítani.

**Döntés:** a controller **soha nem hívja** az `AudioSessionCoordinator`-t, és
nem tart `AudioSessionLease`-t. Az erőforrás-tulajdonos a `MicCapture`, a
gateway alatt egy réteggel. A controller audio-életciklus-felelőssége
kimerül a `gateway.start()` / `stop()` / `dispose()` hívásokban.

A mikrofon felszabadulása így **tranzitív**, és mérve az is:
`gateway.stop()`/`dispose()` → `_stopActiveCapture()` → `_engine.stop()` →
`_mic.stop()` → `lease.release()`
(`live_practice_observation_gateway.dart:159,185` · `real_strum_engine.dart:147`
· `mic_capture.dart:125–131`).

### 10b. Terminal státusz = teljes cleanup, mérve

Mind a három terminal státuszban (`completed`, `cancelled`, `failed`):
observation-subscription lemondva, gateway `stop()` majd `dispose()`,
tick-forrás lezárva, óra megállítva. A controller `dispose()`-a után érkező
observation vagy tick **nem dob** és nem változtat állapotot.

Ez nem ígéret, hanem mért invariáns: a fake-ek számlálókat publikálnak, és a
kör acceptance-e mind a három terminal ágra **külön cellát** ír elő — a
`failed` és a `cancelled` ág az, amelyik valódi eszközön bent hagyja a
mikrofont.

### 11. Hibaosztályok

| Kiváltó | Státusz | Effekt |
|---|---|---|
| mikrofon-engedély megtagadva | `permissionRequired` | `ShowPermissionSettings` |
| gateway `start()` `Failure`-t ad — **beleértve a foglalt mikrofont** (`audio.session_busy`, amit a `MicCapture` ad tovább) | `failed` | `ShowRecoverableError` |
| observation stream **futás közbeni** hibája | **marad** (`countIn`/`running`) | `ShowRecoverableError` |
| recorder mentési hibája finish-kor | `completed` (a session sikeres) | `ShowRecoverableError` |

A recoverable hiba **nem** dobja ki a felhasználót a sessionből (SDD §21.6). A
mentési hibát elnyelő `try/catch` tilos — ez a projekt mért néma-no-op
osztálya (`CLAUDE.md`, „Cloud writes swallowed by try/catch").

### 12. Az eredmény-perzisztencia külön use case, ebben a körben csak határ

A controller a `PracticeSessionRecorder` interfészt ismeri
(`Future<AppResult<void>> record(PracticeSessionResult)`). A production
provider alapértelmezése **`NoopPracticeSessionRecorder`**, amit a Kör 18 cserél
valódi repositoryra. A no-op **`Success`-t ad vissza, de nem nyel el hibát** —
az interfész `AppResult`-ot ad, nem `void`-ot.

### 13. A session-azonosító injektált gyár

A `PracticeSessionResult.id` egy injektált `String Function()`-től származik
(`practiceSessionIdFactoryProvider`). Production: monoton, `DateTime.now()`
alapú; teszt: determinisztikus számláló. Enélkül a kör tesztjei nem tudnának
érték-egyenlőséget állítani a result-ra.

### 14. A matcher csak fordított targetből épülhet

A controller a `PracticeEventMatcher`-t **kizárólag** a
`compilePracticeTarget(...)` kimenetéből (`state.target`) hozza létre, soha
kézzel összerakott `CompiledPracticeTarget`-ből. Ez az E02-R09 **NOTE-3**
zárása: a matcher szándékosan nem rendez át futásidőben, a rendezettséget a
compiler garantálja (`practice_target_compiler.dart:189` fail-fast).

### 15. A `MonotonicPracticeSessionClock.start()` idempotens lesz

Mért mai viselkedés (`practice_session_clock.dart:110`):
`if (_hasStarted && !_isPaused) return;` — azaz **pause alatt hívva teljes
resetet** végez, miközben a saját doc-commentje idempotenciát ígér, az
interfész doc-commentje pedig kifejezetten azt írja, hogy „If invoked while
paused, restarts the session fresh".

Új szerződés: `start()` **csak akkor** zéróz, ha a session még nem indult el
(`!_hasStarted`); már futó **és** pause-olt állapotban is **no-op**. Új session
indítása az explicit úton történik (`resetAttempt()` + a reducer
`RestartAttempt`-je).

Ez az E02-R07 review NOTE-2 zárása. A változás a
`test/support/fake_practice_session_clock.dart` fake-et **is** érinti: a
`practice_session_clock_test.dart` **ugyanazt a szerződés-tesztet futtatja
mindkét implementáción** — a fake ma bitre másolja a reset-ágat, tehát a fake
nélkül a szerződés-teszt a fake-en pirosra váltana.

### 16. A logolás redaktált

Nyers observation-folyam, felhasználói tartalomnév és teljes verdict-lista nem
kerülhet logba (SDD §23). A controller a `appLoggerProvider`-t használja.

## Ismert korlát — szándékosan NEM ez a kör zárja

**A `noSignal` a direction és a rhythm dimenzióban ma „nem párosult", nem
„nem volt jel".** Mérve:

- `practice_direction_scorer.dart:118–124` — `matchedApplicableCount == 0 &&
  observationsByTargetIndex.isEmpty` → `MetricInsufficientData(noSignal)`;
- `practice_timing_scorer.dart:78–80` — `matchedOffsets.isEmpty` →
  `MetricInsufficientData(noSignal)`.

Az `observationsByTargetIndex` map **csak párosult** célindexeket tartalmazhat
(a scorer `StateError`-t dob, ha egy párosult célnak nincs bejegyzése, és
párosulatlan célra nem is olvassa). Ezért a „sokat pengetett, de semmi nem
talált be" eset mindkét dimenzióban `noSignal`-ként fog látszani, holott jel
volt. Ez az E02-R10 review **NOTE-1**-e.

**Miért nem itt zárjuk:** a javítás mindkét scorer *aláírásának* bővítését
igényli (`domain/service/**`, ebben a körben lezárt zóna), és a chord-scorerrel
való szemantikai összehangolást (az `observations.isEmpty`-t használ, azaz
valódi jel-jelenlétet). Ez önálló, két scorer + két teszt terjedelmű kör.
Addig a mai viselkedés **kipinnelve** van egy acceptance-cellában (A13), hogy a
záró körnek legyen piros/zöld horgonya. Follow-up gazdája: **E02-R18**
(result + coaching) pre-flightja.

## Nyitott follow-up — `AudioOwner.practice`

A Practice V2 gateway ma a `strumEngineProvider`-en keresztül a **Live** út
motorját használja, tehát a mikrofon-lease `AudioOwner.live` néven kel el
(`live_providers.dart:12`). Ez működik — a lease exkluzív, és a Practice meg a
Live úgysem futhat egyszerre —, de a lease-ütközési logok félrevezetőek
lesznek („held by live", miközben a Practice tartja).

Egy saját `AudioOwner.practice` enum-tag a `lib/core/**` alatt van (ebben a
körben lezárt zóna), és a Practice-nek saját `StrumEngine`-példányt is adna.
Gazdája: az a kör, amelyik először nyúl a Practice `data/` rétegéhez a
gateway-provider véglegesítésekor (legkésőbb **E02-R13** pre-flight).

## Következmények

- A Kör 12/13 UI-ja innentől egyetlen `practiceSessionControllerProvider`-t
  figyel; saját `Ticker`-t (a legacy `learn_screen.dart:88` mintáját) **nem**
  vezet be.
- A Kör 18 a `NoopPracticeSessionRecorder`-t cseréli le — a controller nem
  változik.
- A flagek OFF-ban maradnak; a mai képernyők közül **egy sem** olvassa az új
  providereket, a production viselkedés változatlan.
