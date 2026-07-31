# E02-R11 — PracticeSessionController orchestration

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 11"** (+ §11–13, §24.1)
- **Branch:** `codex/e02-r11-session-controller`
- **Előfeltétel:** **E02-R09 és E02-R10 merge-ölve** (matcher + scorerek — a
  controller ezeket köti össze). Az **R09 ✅ teljesül** (PR #32, `e7942e6`);
  az R10 még hátravan.
- **ADR:** **0077** — `docs/adr/0077-practice-session-controller.md`, **az
  orchestrátor írja meg a pre-flightban** a §5 tartalmával. Az implementer
  `docs/adr/`-hez NEM nyúl.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** —
  ez az epic legösszetettebb integrációs köre, sok az él és az erőforrás-életciklus.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra a mergelt R09 + R10 API-kat; a §2.2 nevei addig feltételezettek.
> 2. **Ez a kör zárja** az E02-R07 nyitott clock-NOTE-ját és az E02-R08 két
>    follow-upját (§5.9, §5.10) — ellenőrizd, hogy időközben nem zárta-e más kör.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0077 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy egymásnak / a mért állapotnak
ellentmondó előírás → `stopped` + pontos jelentés. **A §7 a terved.**

## 1. Cél

Tíz kör alatt felépült minden alkatrész — időalap, modellek, katalógus,
adapterek, target compiler, óra + state machine, observation gateway, matcher,
scorerek — **de egyetlen hívójuk sincs**. Ez a kör az `application/` rétegben
összeköti őket egyetlen **`PracticeSessionController`-be**, amely UI nélkül,
teljesen végigfuttat egy gyakorló-sessiont: prepare → permission → count-in →
run → pause/resume → restart → finish, minden terminal állapotban teljes
erőforrás-felszabadítással.

Ez a kör a `practiceCaptureActiveByStatus` tábla **első valódi hívója**, és ez
zárja az E02-R07 nyitott clock-NOTE-ját.

**UI ebben a körben sincs** (az a Kör 12/13). A flagek OFF-ban maradnak, a
production viselkedés változatlan — a controller providere létezik, de a mai
képernyők közül **egy sem** olvassa.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

### 2.1 Ami kész és változatlanul használandó

- **State machine (R07):** `domain/model/practice_session_state.dart` (406 sor) —
  11 státusz (`idle`, `preparing`, `permissionRequired`, `ready`, `countIn`,
  `running`, `paused`, `finishing`, `completed`, `cancelled`, `failed`), const
  átmenettábla (287–303. sor), és a `PracticeSessionState` **immutable**
  akkumulátorai: `wallElapsed`, `activeElapsed`, `pausedElapsed`,
  `countInElapsed`, **`playingElapsed`** („a daily goal kizárólag ezt használja,
  SDD §12.2"), `attemptElapsed`, `timelineBase`, `activeBase`.
- **Pure reducer (R07):** `application/practice_session_reducer.dart` (809 sor)
  — minden státuszváltás **kizárólag** rajta keresztül.
- **Command/signal/effect készlet:** `practice_session_command.dart` (142 sor,
  10 command + 4+ signal, köztük `ClockAdvanced`), `practice_session_effect.dart`
  (54 sor: `PlayHaptic`, `PlayCountInClick`, `ShowPermissionSettings`,
  `NavigateToResult`, `ShowRecoverableError`, `AnnounceAccessibilityFeedback`).
- **Óra (R07):** `application/practice_session_clock.dart` (177 sor) —
  `PracticeSessionClock` interfész + `MonotonicPracticeSessionClock`.
  **Nyitott NOTE (E02-R07 review §NOTE-2):** a `start()` **pause alatt teljes
  resetet** végez (110. sor: `if (_hasStarted && !_isPaused) return;`), miközben
  a doc-comment idempotenciát ígér. Eddig nem volt valódi hívó — most lesz.
- **Gateway (R08):** `application/practice_observation_gateway.dart` (87 sor)
  — `start({required PracticeObservationConfig config})`, `setExpectedChord`,
  `stop()`, `dispose()`, `Stream<PracticeObservation> get observations`;
  `PracticeObservationConfig` alapértékei: 0.55 / 0.60 / 180 ms / 500 ms.
  Implementáció: `data/live_practice_observation_gateway.dart` (348 sor).
- **Aktivációs tábla (R08):** `application/practice_observation_activation.dart`
  (25 sor) — `practiceCaptureActiveByStatus` mind a 11 státuszra
  (`countIn` + `running` → true, minden más → false), és a
  `practiceCaptureActive(status)` fail-fast olvasó. ⚠ A doc-comment **„E02-R09
  controller"-t** említ — ez a kör-átszámozás miatt elavult, ebben a körben
  javítandó (`E02-R11`).
- **Katalógus-providerek (R04):** `practice_catalog_repositoryProvider` +
  `practiceCatalogProvider` — ma is csak ez a két Riverpod provider létezik a
  feature-ben.
- **Core (Epic 1):** `MicrophonePermissionGateway`
  (`core/platform/microphone_permission.dart`, `currentState()` / `request()`,
  `MicrophonePermissionState` enum), `AudioSessionCoordinator`
  (`core/audio/lifecycle/audio_session_coordinator.dart`, `acquire(owner,
  onRevoke) → AppResult<AudioSessionLease>`, exkluzív lease, ADR 0056),
  `AppResult`/`AppFailure`, `appLoggerProvider` redakciós logolással.
- **Beállítások:** `inputLatencyProvider` (ms) és `visualLatencyProvider`
  (`lib/features/settings/providers/`), a legacy `learn_screen.dart` mérve így
  használja: `inputLatencySec: ref.read(inputLatencyProvider) / 1000` (222. sor).

### 2.2 Amire épül, de a pre-flightig feltételezett

- **R09 matcher** és **R10 scorerek** API-ja (`domain/service/`). A §5 és §6
  ezek tényleges neveire hivatkozik — a pre-flight igazítja.

### 2.3 Ami MA nincs

- Nincs semmilyen controller; a reducert **egyetlen production hívó sem** hívja
  (mérve: `grep -rn "practiceSessionReducer\|PracticeSessionReducer" lib/` csak a
  reducer saját fájlját adja).
- Nincs eredmény-perzisztencia határ: `PracticeSessionResult` létezik
  (`domain/model/practice_session_result.dart`, 176 sor), de nincs repository,
  ami elmentené (az a **Kör 18**).
- Nincs tick-forrás: a mai legacy `learn_screen.dart` saját `Ticker`-t használ
  (`createTicker(_onTick)`, 88. sor) — ezt a mintát a V2-ben **nem** követjük
  (SDD Kör 13: „ne használjon saját Ticker-based business clockot").
- A `test/support/` alatt már van `fake_practice_observation_gateway.dart` és
  `fake_practice_session_clock.dart` — **ezeket használd**, ne írj újakat.

## 3. Scope

**Benne:** egyetlen application-szintű controller + a Riverpod-huzalozása + a
perzisztencia-határ **interfésze** (implementáció nélkül) + a két nyitott
follow-up zárása (clock-idempotencia, aktivációs doc-comment) + integrációs,
egység- és property-tesztek fake gatewayjel és fake órával.

**Kívül (ebben a körben TILOS):**

- **Bármilyen UI, widget, képernyő, route** — Kör 12/13.
- **Perzisztencia-implementáció**, `SharedPreferences`, history-írás — Kör 18.
  Ebben a körben csak az **interfész** készül el, és a production provider
  alapértelmezése egy **no-op** implementáció.
- Coaching, adaptív javaslat, Speed Builder attempt-lánc — Kör 17/18.
- `lib/features/learn/**` bármilyen módosítása (a legacy út érintetlen marad).
- A reducer, a state, a command/effect készlet, a gateway, a matcher és a
  scorerek **viselkedésének** módosítása. Ha hiányt találsz bennük → `stopped`
  + jelentés, nem csendes javítás. (Kivétel: a §4-ben nevesített két fájl a
  nevesített okból.)
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, `pubspec.yaml`, DSP,
  `docs/rag/chunks/**`.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/application/practice_session_controller.dart` | **ÚJ** | a controller |
| `lib/features/practice/application/practice_session_providers.dart` | **ÚJ** | Riverpod-huzalozás (controller, gateway, óra, tick-forrás, recorder) |
| `lib/features/practice/application/practice_tick_source.dart` | **ÚJ** | injektálható tick-absztrakció + `Timer.periodic` production implementáció |
| `lib/features/practice/domain/repository/practice_session_recorder.dart` | **ÚJ** | eredmény-perzisztencia **határ** (interfész + `NoopPracticeSessionRecorder`) |
| `lib/features/practice/application/practice_session_clock.dart` | — | **CSAK** a `start()` idempotencia-NOTE zárása (§5.9) |
| `lib/features/practice/application/practice_observation_activation.dart` | — | **CSAK** a doc-comment `E02-R09` → `E02-R11` javítása |
| `test/features/practice/application/practice_session_controller_test.dart` | **ÚJ** | egység- és él-tesztek |
| `test/features/practice/application/practice_session_integration_test.dart` | **ÚJ** | a §6 A10 tíz forgatókönyve |
| `test/features/practice/application/practice_session_clock_test.dart` | — | az A7 idempotencia-mátrix cellái |
| `test/support/fake_practice_session_recorder.dart` | **ÚJ** | hívás-számláló fake a recorderhez |
| `test/property/practice_session_controller_property_test.dart` | **ÚJ** | A11 randomizált property gate |
| `docs/rounds/e02-r11-session-controller.md` | — | **CSAK a §10** (handoff) kitöltése |

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/**`, `lib/app/**`
(routing, flagek), `lib/features/practice/domain/model/**`,
`lib/features/practice/domain/service/**`, `lib/features/practice/data/**`,
`docs/adr/**`, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, `tool/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0077 — NEM tárgyalhatók)

1. **A controller sosem mutál állapotot közvetlenül.** Minden státuszváltás a
   pure reduceren megy át; a controller feladata a command/signal előállítása,
   az effektek továbbítása és az **erőforrás-életciklus**.
2. **Tiltott függőségek a controllerben:** `BuildContext`, `Navigator`/`GoRouter`,
   `SharedPreferences` (közvetlenül), `StrumEngine` példányosítás, `dart:ui`.
   Navigáció **nem** a controller dolga: `NavigateToResult` **effekt**, amit a
   Kör 13 UI-ja hajt végre.
3. **A capture-aktiváció EGYETLEN forrása a `practiceCaptureActiveByStatus`
   tábla.** Minden státuszváltás után a controller összeveti a tábla értékét a
   gateway tényleges állapotával, és **csak eltérésnél** hív `start()`/`stop()`-ot
   (nincs ismételt `start()` ugyanabban az aktív állapotban).
4. **Egyetlen `PracticeObservationConfig` példány.** A controller állítja elő,
   és **ugyanazt** adja a gatewaynek és az akkord-scorernek (a
   `chordStableDuration` így nem csúszhat szét a két oldal között). Ez az
   E02-R08 nyitott „küszöb-leképezés" follow-upjának zárása.
5. **Az input latency az attempt kezdetén befagy.** A controller **egyszer**
   olvassa (prepare/start), és az egész attempt alatt ugyanazt az értéket adja
   a matchernek. Attempt közbeni beállítás-változás a **következő** attemptre hat.
6. **Tick-forrás injektálva.** A controller nem hoz létre `Timer`-t közvetlenül:
   `PracticeTickSource` absztrakció mögül kapja. Production periódus **16 ms**;
   a teszt fake forrást ad. A tick **kizárólag** `ClockAdvanced` signalt szül —
   **scorer-számítást soha** (SDD §24.1: „csak új observation indítson strum
   verdict számítást").
7. **A finish idempotens és single-flight.** Akárhány `FinishPractice` /
   automatikus befejezés érkezik, a `PracticeSessionRecorder.record()` **pontosan
   egyszer** hívódik és **pontosan egy** `NavigateToResult` effekt keletkezik.
8. **Minden terminal státuszban (`completed`, `cancelled`, `failed`) teljes
   cleanup:** observation-subscription lemondva, gateway `stop()` + `dispose()`,
   tick-forrás lezárva, audio lease elengedve, óra megállítva. „Terminal állapot
   után nincs subscription" — ez mérendő invariáns, nem ígéret (§6 A4).
9. **A `MonotonicPracticeSessionClock.start()` idempotens lesz.** Mért mai
   viselkedés: pause alatt hívva **teljes resetet** végez. Az új szerződés:
   `start()` **csak akkor** zéróz, ha a session még nem indult el; már futó
   **és** pause-olt állapotban is **no-op**. Új session indítása az explicit
   `restart` úton (`resetAttempt` + a reducer `RestartAttempt`-je) történik.
   Ez az E02-R07 NOTE-2 zárása.
10. **Hibakezelés:** minden hiba `AppFailure`-ré alakul (`AppResult` úton), és a
    státuszba a reduceren keresztül kerül. **Recoverable** hiba (pl. observation
    stream hiba futás közben) nem dobja ki a felhasználót a sessionből:
    `ShowRecoverableError` effekt + a session marad. **Fatal** hiba (audio lease
    nem szerezhető, detektor nem indul) → `failed`.
11. **Az eredmény-perzisztencia külön use case.** A controller csak a
    `PracticeSessionRecorder` interfészt ismeri; a production provider
    alapértelmezése ebben a körben **`NoopPracticeSessionRecorder`**, amit a
    Kör 18 cserél le valódi repositoryra. A no-op **nem** nyel el hibát: az
    interfész `Future<AppResult<void>>`-t ad vissza.
12. **A logolás redaktált.** Nyers observation-folyam, felhasználói tartalomnév
    és teljes verdict-lista **nem** kerülhet logba (SDD §23).

## 6. Acceptance criteria

Minden pont mellett ott van, **melyik hibás implementációt fogja pirosra**.

### A1 — Minden státuszváltás legális, és minden köztes állapot látszik

**A mérés eszköze (ezt MEGADOM, hogy a mérce ne legyen kikerülhető):** a
controller `Stream<PracticeSessionState>`-et publikál, amely **minden** elfogadott
reducer-kimenetet kibocsát — köztes állapotokat **nem von össze** és nem
`distinct()`-el. A teszt begyűjti a teljes státusz-sorozatot, és **minden
egymást követő `(előző, új)` párt** a `practiceSessionTransitions` tábla ellen
ellenőriz.

**NEM elfogadható gyengítés:** csak a kezdő és a végállapot ellenőrzése („a
tranzitív lezárt"); a stream `distinct()`-elése; a köztes `finishing` állapot
elnyelése.

***Pirosra fogja:*** minden olyan implementáció, amely „gyorsítás" céljából
közvetlenül `running → completed`-et állít be a `finishing` kihagyásával.

### A2 — Capture-aktivációs mátrix mind a 11 státuszra

Forgatókönyv-alapú teszt, amely végigviszi a sessiont az
`idle → preparing → ready → countIn → running → paused → running → finishing →
completed` úton, **plusz** a `permissionRequired`, `cancelled` és `failed` ágakat.
A fake gateway hívásnaplója alapján cellánként:

| Státusz | `practiceCaptureActiveByStatus` | Elvárt gateway-állapot |
|---|---|---|
| `idle`, `preparing`, `permissionRequired`, `ready` | false | nem fut |
| `countIn` | **true** | fut (`start()` pontosan egyszer) |
| `running` | **true** | fut, **nincs újabb `start()`** a `countIn → running` átmenetnél |
| `paused` | false | `stop()` pontosan egyszer |
| `paused → running` | true | `start()` **újra** pontosan egyszer |
| `finishing`, `completed`, `cancelled`, `failed` | false | leállítva **és** `dispose()`-olva |

***Pirosra fogja:*** a `countIn → running` átmenetnél kiadott felesleges
`stop()+start()` pár (mikrofon-glitch valódi eszközön), és a `paused`-ben futva
hagyott capture (a chunk 014 pause-rése, amit a V2 úton éppen ez zár).

**NEM elfogadható gyengítés:** a tábla megkerülése bármilyen „a controller
úgyis tudja" logikával; a hívásnapló helyett csak a végállapot ellenőrzése.

### A3 — Finish idempotencia

Három `FinishPractice` command + egy automatikus (utolsó célesemény lezárása
általi) befejezés ugyanazon az attempten:

- `PracticeSessionRecorder.record()` hívásszáma: **pontosan 1**;
- `NavigateToResult` effektek száma: **pontosan 1**;
- a `PracticeSessionResult` **ugyanaz** az objektum minden lekérdezésnél
  (value-equality).

***Pirosra fogja:*** a „minden FinishPractice-re mentünk" implementáció — ez
duplikált history-bejegyzést jelentene a Kör 18-ban.

### A4 — Cleanup-mátrix, MÉRVE

A fake-ek számlálókat publikálnak (`startCount`, `stopCount`, `disposeCount`,
`activeSubscriptions`, `tickSubscriptions`, `leaseReleaseCount`). Mind a három
terminal státuszra **külön** cella:

| Terminal státusz | subscription | gateway `stop` | gateway `dispose` | tick-forrás | audio lease |
|---|---|---|---|---|---|
| `completed` | 0 | ≥1, utolsó hívás a terminal előtt | 1 | lezárva | elengedve |
| `cancelled` | 0 | ≥1 | 1 | lezárva | elengedve |
| `failed` | 0 | ≥1 | 1 | lezárva | elengedve |

Plusz: a controller `dispose()`-a **után** érkező observation vagy tick
**nem dob kivételt** és nem változtat állapotot.

***Pirosra fogja:*** a csak „boldog úton" takarító implementáció — a `failed`
és `cancelled` ág az, amelyik valódi eszközön bent hagyja a mikrofont.

**NEM elfogadható gyengítés:** a számlálók elhagyása és „a teszt nem dobott
kivételt" indoklás; a cleanup ellenőrzése csak a `completed` ágon.

### A5 — Hibaosztály-mátrix

| Kiváltó | Elvárt státusz | Elvárt effekt | `AppFailure`? |
|---|---|---|---|
| mikrofon-engedély megtagadva | `permissionRequired` | `ShowPermissionSettings` | — |
| audio lease nem szerezhető (foglalt mikrofon) | `failed` | `ShowRecoverableError` | igen |
| gateway `start()` `AppResult` hibát ad | `failed` | `ShowRecoverableError` | igen |
| observation stream **futás közbeni** hibája | **marad `running`** | `ShowRecoverableError` | igen |
| recorder mentési hibája finish-kor | `completed` (a session sikeres) | `ShowRecoverableError` | igen |

***Pirosra fogja:*** a stream-hibára sessiont ölő implementáció (SDD §21.6:
„a recoverable hiba ne dobja ki automatikusan a felhasználót"), és a
`try/catch`-be nyelt mentési hiba (a projekt mért néma-no-op osztálya).

### A6 — Pause alatt nincs pontozás, resume nem ugrik

- `paused` állapotban érkező observation-ök: a verdict-ek száma és a
  `scorePoints` **változatlan** (mérve a pause előtti/utáni snapshotból).
- `playingElapsed` **nem nő** pause alatt; `pausedElapsed` nő.
- Resume után a `timelinePosition` a reducer bar-anchor szabálya szerint
  folytatódik — **nincs** visszaugrás és nincs előreugrás.
- Mátrix: `Meter ∈ {4/4, 3/4}` × `countInBars ∈ {0, 1, 2}` — mind a hat cella.

***Pirosra fogja:*** a „pause alatt is fogadjuk a strumokat, majd eldobjuk a
végén" implementáció, és a resume-nál a count-in span-t kihagyó út.

### A7 — Clock `start()` idempotencia (a NOTE zárása)

| Kiinduló állapot | `start()` hatása | Elvárt |
|---|---|---|
| még nem indult | zéróz | `wall == active == paused == attempt == 0` |
| fut | **no-op** | az akkumulátorok **változatlanok** |
| pause-olt | **no-op** | `paused` **nem** nullázódik (ma reset történik!) |

Plusz: a `resetAttempt()` továbbra is **csak** az `attempt` akkumulátort nullázza.

***Pirosra fogja:*** a mai (mért) viselkedés — ez a cella ma **piros**, és ettől
a körtől zöld.

### A8 — Egyetlen observation-config forrás

A gatewaynek átadott `PracticeObservationConfig` és az akkord-scorernek átadott
stabilitási küszöb **ugyanabból a példányból** származik. Mérés: a fake gateway
elmenti a kapott configot, a teszt összeveti a scorer paraméterével —
**value-equality**, nem „mindkettő 180 ms".

***Pirosra fogja:*** a két helyen külön beírt alapérték (ma ez a kockázat:
`PracticeObservationConfig` default 180 ms **és** a scorer saját defaultja).

### A9 — Réteg-tisztaság

- Guard-teszt: a `practice_session_controller.dart` forrása **nem tartalmazza** a
  `BuildContext`, `Navigator`, `GoRouter`, `SharedPreferences`, `StrumEngine(`
  mintákat (forrásszöveg-alapú őr, a `test/tooling/` meglévő guardjainak
  mintájára — de a **saját** tesztfájlban, ne bővítsd a `test/tooling/`-ot).
- `tools/round-gate.sh` **architecture** lépése zöld; az allowlist nem bővül.

### A10 — Integrációs forgatókönyvek (SDD Kör 11, mind a tíz)

Fake gatewayjel és fake órával, UI nélkül: perfect session · wrong direction ·
chord failure · pause/resume · restart · cancel · stream failure · no signal ·
complete cleanup · expected chord sequence.

Mindegyik forgatókönyv **állítson a kimenetre is**, ne csak arra, hogy nem dobott:
a `PracticeSessionResult` metrikái, a státusz-sorozat és a cleanup-számlálók.
Az „expected chord sequence" külön ellenőrizze, hogy a
`gateway.setExpectedChord(...)` a **célesemény-szegmensek** szerint frissül, és
**finish-kor `null`-ra** áll.

**NEM elfogadható gyengítés:** `expect(() => ..., returnsNormally)` típusú
állítás bármelyik forgatókönyvben.

### A11 — Randomizált property gate

`test/property/practice_session_controller_property_test.dart`, `PROPERTY_SEED`
(hiány → 42). Véletlen **command-sorozatokra** (érvényes és érvénytelen
parancsok vegyesen):

1. a controller **soha nem dob** kivételt;
2. minden kibocsátott státusz-pár szerepel az átmenettáblában;
3. terminal státusz elérése után **nulla** aktív subscription és **nulla**
   további állapot-kibocsátás;
4. a `record()` hívásszáma sessiononként **legfeljebb 1**;
5. `playingElapsed <= activeElapsed <= wallElapsed` **minden** snapshotban.

### A12 — Nulla production viselkedésváltozás

`git diff --stat origin/main...HEAD` → a `lib/` alatt kizárólag a §4 listája.
`lib/features/learn/` **0 sor**, `lib/app/` **0 sor**. A `flutter test` teljes
suite-ja a CI-ban változatlanul zöld — a mai képernyők közül **egy sem**
olvassa az új providereket (mérve: `grep -rn "practiceSessionControllerProvider"
lib/features/ | grep -v practice/`).

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **ADR 0077**, a reducer teljes fájlja, a state akkumulátorai, a
   command/effect készlet, a gateway és az aktivációs tábla, az R09 matcher és
   az R10 scorerek API-ja, `audio_session_coordinator.dart`,
   `microphone_permission.dart`.
2. `PracticeTickSource` + a fake tick-forrás a tesztben.
3. `PracticeSessionRecorder` interfész + `NoopPracticeSessionRecorder`.
4. A controller váza: prepare → permission → ready (még capture nélkül).
5. A capture-életciklus a tábla szerint (§5.3) + A2 mátrix.
6. Count-in, tick → `ClockAdvanced`, count-in click effektek.
7. Observation-út: matcher → scorerek → inkrementális snapshot (A6, A8).
8. Pause/resume/restart/cancel + A6 mátrix.
9. Finish (single-flight) + recorder + A3.
10. Hibaágak + A5; cleanup + A4.
11. A clock `start()` idempotencia (§5.9) + A7 — **külön commit**, hogy a
    review a NOTE zárását önmagában is látni tudja.
12. Integrációs forgatókönyvek (A10), property-teszt (A11).
13. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **Ez a legnagyobb integrációs felület az epicben.** Ha a scope tágulni akar
  (pl. „mindjárt megírom a history-mentést is"), az `stopped` + jelentés.
- **Riverpod 3.3.2:** `AsyncValue.value` (nullable), **NEM** `.valueOrNull`.
  A `ref.listenManual` előfizetést **kézzel** kell lemondani — ez pontosan az
  A4 mérésének tárgya.
- **A reducer elutasítja a második `StartPractice`-t** (E02-R07 review). Ha a
  controller „biztonságból" kétszer küldi, néma no-opot kapsz — az A1 státusz-
  sorozata fogja meg.
- **A `MonotonicPracticeSessionClock.start()` átírása viselkedésváltozás** egy
  kész kör fájljában. Ezért van külön acceptance-cellája (A7) és külön commitja;
  ha a meglévő `practice_session_clock_test.dart` bármely tesztje pirosra vált,
  az **megállás és jelentés** — nem a teszt átírása.
- **Fal-óra a tesztben.** Semmilyen `await Future.delayed`-alapú időzítés: a
  fake óra és a fake tick-forrás determinisztikus. Egy flaky teszt itt a teljes
  CI-t megbízhatatlanná teszi.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/practice_session_controller_property_test.dart
```

Csővezeték nélkül (se `| tail`, se `| head`, se `| grep`, se `&&` láncolás), a
teljes kimenetet a §10-be. A teljes suite + property gate + APK a CI-ban fut,
merge előtt, orchestrátor-dispatch-csel (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A12
pontok teljesülése bizonyítékkal · eltérések és okuk · nem futtatott ellenőrzések
és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r11-review.md`

Kiemelt figyelem a review-nak: **valódi-sértés próba** az A4 cleanup-számlálókra
(ideiglenesen kihagyott `stop()` a `failed` ágon → pirosnak kell lennie), az A2
`countIn → running` cellájára (ideiglenes `stop()+start()` beszúrás), és az A7
három cellájára (a mai reset-viselkedés visszaállítása → pirosnak kell lennie).
Ellenőrizendő továbbá, hogy a controller tényleg **nem** számol scorert tickre
(§5.6) — ez teljesítménykérdés, amit csak kódolvasás fog meg.
