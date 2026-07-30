# E02-R07 — Session clock és state machine

- **Státusz:** PLANNING (indítás: 2026-07-30, kód olvasva: `main @ a490019`)
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` §11, §12.1–12.2, §12.5, „Kör 7 — Session clock és state machine"
- **Előfeltétel:** E02-R06 merge-ölve (PR #27) — a `CompiledPracticeTarget` és a `BeatTimeConverter` készen állnak
- **Branch:** `mm/epic-02-round-07-session-clock`
- **Implementer motor:** **MiniMax M3** (a user 2026-07-30-i döntése; a kör állapotgép + könyvelés, tételesen kipinnelt szerződéssel — a felderítést és a tervezést a §2/§5 elvégezte)
- **Kiosztott ADR:** **0073** — [`docs/adr/0073-practice-session-state-machine.md`](../adr/0073-practice-session-state-machine.md).
  **Az ADR-t Claude írta; az implementer NEM hoz létre és NEM módosít `docs/adr/` fájlt.**

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

Te vagy ennek a körnek az IMPLEMENTERE. Nem te tervezel és nem te review-zol.
Probléma esetén a jelzés az ELSŐ lépés, nem az utolsó:

```bash
tools/codex-signal.sh progress "<egy sor>"   # opcionális, nem zárja le a kört
tools/codex-signal.sh done    "<egy sor>"    # lezárja: kész, minden gate zöld
tools/codex-signal.sh stopped "<egy sor>"    # lezárja: brief-ütközés, nincs mit implementálni
tools/codex-signal.sh blocked "<egy sor>"    # lezárja: a gate 3 javítási kísérlet után is piros
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne commitolj a `main`-re,
ne pusholj — a CI-dispatch, a PR és a merge Claude-oldal.

**STOP-klauzula:** ha bármelyik követelmény ütközik a §4 engedélyezett-fájllistával,
egy meglévő teszttel vagy egy meglévő API-val: **ÁLLJ MEG**, küldd a `stopped`
jelzést, és jelentsd az ütközést — ne kerüld meg csendben, és ne írj át
listán kívüli fájlt.

**Munkamód:** a **§8 a terved** — ne készíts külön task-listát, fázisonként
legfeljebb egy állapotfrissítés. Ne állíts a kódról a doc-commentben olyat,
amit nem ellenőriztél: ha `const`-ot, `immutable`-t, „monoton" vagy „nem dob"
viselkedést írsz, előbb bizonyítsd tesztben.

## 0.1 A kör legfontosabb tanulsága ELŐRE (E02-R04/R05/R06 review)

**A zöld gate nem bizonyíték.** Az elmúlt három körben MINDEN lelet úgy csúszott
át, hogy `format` + `analyze` + a teljes suite zöld volt: mutábilis `List` mező
`final` mögött (R04), némán kétszeres hosszú idővonal (R05), ugyanaz a zenei
pillanat két különböző µs-értékkel (R06). Mindhármat a review **eldobható
próbatesztje** fogta meg, nem a gate.

Ebben a körben ezért **minden számolt mennyiségnek** (idő-akkumulátor,
idővonal-pozíció, resume-anchor, count-in kattanás) legyen **invariánsra mérő**
tesztje az ÉLEKEN, nem csak a boldog úton:

- pause a count-in KÖZBEN (nem a zene alatt),
- pause pontosan egy ütemhatáron és pontosan 1 µs-mal utána,
- két egymást követő pause/resume ugyanabban az ütemben,
- `countInBars == 0` (nincs kezdeti count-in),
- 3/4-es `Meter` (a resume count-in ott 3 ütés, nem 4),
- `RestartAttempt` közvetlenül a pause után, majd egy teljes második attempt,
- 0,5-ös practice speed (a `Tempo` fele).

## 1. Cél

A practice session teljes életciklusa **pure, determinisztikus állapotgépbe**
kerül: `PracticeSessionClock` (monoton `Stopwatch` implementációval és
teszt-fake-kel), `PracticeSessionStatus` + a SDD §11.2 átmenettáblája,
command/signal bemenetek, one-shot effect-modell, és a §12.2 négyféle
időszámláló. Audio-, mikrofon- és UI-integráció **nincs** ebben a körben;
Riverpod provider és képernyő **nem készül**. A kör kimenete az E02-R08
(observation gateway) és az E02-R09+ (matcher/scorer) bemenete.

**A production viselkedés nem változik**: a mai Learn út egyetlen sorát sem
módosítjuk, és a practice flagek OFF állapotban maradnak.

## 2. Jelenlegi állapot (mért tények, `main @ a490019`)

### 2.1 Amire építeni kell (E02-R06, NEM e kör dolga újraírni)

- **`lib/features/practice/domain/model/beat_time_converter.dart`** —
  `BeatTimeConverter({required Tempo tempo, required Meter meter})`;
  `Duration timeOf(BeatPosition)`, `Duration timeOfTicks(int)`,
  `BeatPosition positionAt(Duration)`, `Duration get beatDuration`,
  `Duration get barDuration`. Érvénytelen `Tempo`/`Meter` mellett `StateError`.
  Az aritmetika egész mikroszekundum: `round(ticks * 60e6 / (bpm * 480))`.
- **`lib/features/practice/domain/model/compiled_practice_target.dart`** —
  `CompiledPracticeTarget` mezői: `definitionId`, `definitionSnapshotVersion`,
  `tempo`, `meter`, `countInBars`, **`countInDuration`**, `events`,
  `musicalDuration`, `ringOutDuration`, **`totalDuration`**,
  **`barBoundaries`**, `loopCount`, `loopRange`, `expectedChordSegments`,
  `scoringApplicable`. Immutable, érték-egyenlő, a listák konstruktorban
  `List.unmodifiable`-lel snapshotolva.
  - **`barBoundaries` a NULLPONTTÓL indul és a count-in ütemeket IS tartalmazza:**
    `[0, 1×ticksPerBar, …, countInBars×ticksPerBar, countInTicks+1×ticksPerBar, …]`
    (`practice_target_compiler.dart:176-187`). Tehát count-in közbeni pause-ra is
    van értelmes ütemhatár. **Mindig nemüres és nemcsökkenő.**
  - `countInDuration == 0`, ha `config.countInBars == 0`.
- **`lib/features/practice/domain/service/practice_target_compiler.dart`** —
  `AppResult<CompiledPracticeTarget> compilePracticeTarget({required PracticeDefinition definition, required PracticeSessionConfig config})`.
- **ADR 0072 §1.1 időszabály (KÖTELEZŐ):** minden abszolút **pillanat** a
  nullponttól vett tickszám EGYETLEN konverziója; minden **időtartam** két
  pillanat különbsége. Ebben a körben ez azt jelenti: **saját beat→idő képletet
  NEM írsz** — minden időt a `CompiledPracticeTarget` előre kiszámolt mezőiből
  vagy a `BeatTimeConverter`-ből veszel.

### 2.2 Konfiguráció

- **`lib/features/practice/domain/model/practice_session_config.dart`** —
  `countInBars` (0..4), `loopCount` (1..32), `inputLatency`, `visualLatency`
  (0..500 ms), **`sessionTimeout`** (`Duration`, > 0), `effectiveTempo`,
  `metronomeEnabled`, `accentEnabled`, `backingEnabled`, `scoringProfileId`,
  `easyVariationId?`, `expectedChordHintEnabled`, `reducedMotion`;
  `validate()`, `copyWith`, érték-egyenlőség.

### 2.3 Hiba- és validációs infrastruktúra

- **`lib/core/foundation/app_failure.dart`** — a practice szekció ma **két**
  kódot tartalmaz (`:49-53`):
  `practiceContentUnsupported = 'practice.content_unsupported'`,
  `practiceTargetUncompilable = 'practice.target_uncompilable'`.
- **`lib/features/practice/domain/model/practice_validation.dart`** —
  `PracticeValidationCode` ma **66** stabil kód + `allCodes` halmaz,
  `PracticeValidationFailure { code, message }`.
- `AppResult<T>` / `Success` / `Failure` / `ValidationFailure` —
  `lib/core/foundation/`.

### 2.4 Purity- és architektúra-őrök (ezekbe fogsz ütközni, ha rossz helyre teszed a kódot)

- **`test/features/practice/domain/domain_purity_test.dart`** — a
  `lib/features/practice/domain/` teljes fájában **tiltja**: `DateTime.now(`,
  **`Stopwatch(`**, `Random(`, `print(`, `package:flutter…`/`riverpod`/`dio`/
  `shared_preferences` import, l10n import. Comment és string-literál kivétel.
  ⇒ **A `Stopwatch`-alapú óra NEM kerülhet a `domain/` alá.**
- **`tool/check_architecture.dart`** — `lib/features/practice/domain/` shared
  domain: nem importálhat Fluttert/Riverpodot/Diót/l10n-t; cross-feature import
  csak `public.dart`-on át. Az `application/` réteg **nem** tartozik a shared
  domain szabály alá.
- **`lib/features/practice/` mai fái:** `application/` (ma egyetlen fájl:
  `practice_catalog_controller.dart`), `data/` (+`data/adapters/`),
  `domain/model/`, `domain/repository/`, `domain/service/`.
  A SDD §8.1 a `practice_session_clock.dart`, `practice_session_command.dart`,
  `practice_session_effect.dart` fájlokat az **`application/`** alá,
  a `practice_session_state.dart`-ot a **`domain/model/`** alá teszi — ezt kövesd.

### 2.5 Property gate

`test/property/` — a fájlok a `PROPERTY_SEED` env változót olvassák
(hiányzik → 42, CI HARD lépésben `github.run_id`). Példa a konvencióra:
`test/property/chord_timeline_property_test.dart:1-20`.

## 3. Scope

**Benne:**

- `PracticeSessionStatus` enum (11 érték) + a §11.2 átmenettábla `const` adatként.
- `PracticeSessionState` — immutable, érték-egyenlő, `copyWith`.
- `PracticeSessionInput` = `PracticeSessionCommand` (11 db) ∪ `PracticeSessionSignal` (4 db).
- `PracticeSessionEffect` (6 variáns) — one-shot, a state-ben NEM tárolt.
- `reducePracticeSession(...)` pure reducer + `PracticeSessionTransition`.
- `InvalidSessionTransitionFailure` + 1 új `FailureCode`.
- `PracticeSessionClock` interfész + `PracticeClockSnapshot` +
  `MonotonicPracticeSessionClock` (`Stopwatch`).
- `FakePracticeSessionClock` a `test/support/` alatt.
- A §12.2 hat akkumulátora és a §12.5 resume-policy.
- Unit tesztek (a 11 kötelező transition-teszt) + 1 randomizált property teszt.

**Kívül (ebben a körben TILOS):**

- Riverpod provider, `practice_session_controller.dart`, bármilyen képernyő
  vagy widget.
- Mikrofon, audio, metronóm, observation gateway, `LiveFrame` — E02-R08.
- Esemény-kurzor (`currentTarget` / `nextTarget`), expected-chord hint kiadása,
  matching, pontozás, metrikák, feedback — **szándékosan elhalasztva** az
  E02-R08/R09-re. A `PracticeSessionState` NE tartalmazzon `metrics`,
  `latestFeedback`, `micState`, `metronomeState`, `speedBuilderState` mezőt.
- Speed Builder, adaptív nehézség, perzisztencia, daily goal **kiszámítása**
  (csak a `playingElapsed` mezőt szolgáltatod, a napi célt nem itt számoljuk).
- A legacy Learn út (`lib/features/learn/**`) bármilyen módosítása.
- `docs/adr/**` létrehozása vagy módosítása.
- `pubspec.yaml`, CI-workflow, `tool/check_architecture.dart` módosítása.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak hozhatók létre / módosíthatók. Bármi más → **MEGÁLLÁS**
(`stopped` jelzés) és jelentés.

| Útvonal | Miért |
|---|---|
| `lib/features/practice/domain/model/practice_session_state.dart` | ÚJ — status enum, átmenettábla, state, finish reason, pause cause |
| `lib/features/practice/application/practice_session_clock.dart` | ÚJ — `PracticeSessionClock` interfész + `PracticeClockSnapshot` + `MonotonicPracticeSessionClock` |
| `lib/features/practice/application/practice_session_command.dart` | ÚJ — `PracticeSessionInput` / `PracticeSessionCommand` / `PracticeSessionSignal` |
| `lib/features/practice/application/practice_session_effect.dart` | ÚJ — `PracticeSessionEffect` sealed hierarchia |
| `lib/features/practice/application/practice_session_reducer.dart` | ÚJ — a pure reducer + `PracticeSessionTransition` + `InvalidSessionTransitionFailure` |
| `lib/core/foundation/app_failure.dart` | **CSAK** a practice szekció (`:49-53`) bővítése egyetlen új kóddal |
| `test/support/fake_practice_session_clock.dart` | ÚJ — `FakePracticeSessionClock` |
| `test/features/practice/domain/practice_session_state_test.dart` | ÚJ — status/átmenettábla/state érték-egyenlőség |
| `test/features/practice/application/practice_session_clock_test.dart` | ÚJ — óra-szerződés (valódi + fake) |
| `test/features/practice/application/practice_session_reducer_test.dart` | ÚJ — a 11 kötelező transition-teszt + elutasítások |
| `test/features/practice/application/practice_session_timing_test.dart` | ÚJ — a §12.2 akkumulátorok és a resume-policy élei |
| `test/property/practice_session_property_test.dart` | ÚJ — randomizált invariáns-gate (`PROPERTY_SEED`) |
| `docs/rounds/e02-r07-session-clock.md` | **CSAK a §10** (implementation handoff) kitöltése |

**Tilos zóna:** `lib/features/learn/**`, `lib/features/live/**`,
`lib/features/songs/**`, `lib/features/practice/domain/service/**`,
`lib/features/practice/domain/model/**` (a fenti EGY új fájlon kívül),
`lib/features/practice/data/**`, `lib/app/**`, `docs/adr/**`, `docs/sdd/**`,
`tool/**`, `pubspec.yaml`, `.github/**`, `HANDOFF.md`, `AGENTS.md`.

A `lib/core/foundation/app_failure.dart`-ba **kizárólag** a
`// --- practice ---` szekcióba írhatsz, a meglévő két kód alá.

## 5. Kötött architekturális döntések

Amit a kör NEM tervezhet újra. Eltérés csak `stopped` jelzéssel, új ADR-rel.

### 5.1 Az óra

```dart
final class PracticeClockSnapshot {
  const PracticeClockSnapshot({
    required this.wall,
    required this.active,
    required this.paused,
    required this.attempt,
  });
  final Duration wall;     // start() óta minden idő (pause-t IS tartalmazza)
  final Duration active;   // wall - paused
  final Duration paused;   // felhalmozott pause-idő
  final Duration attempt;  // active a legutóbbi resetAttempt() óta
}

abstract interface class PracticeSessionClock {
  PracticeClockSnapshot now();
  void start();
  void pause();
  void resume();
  void resetAttempt();
}
```

- `MonotonicPracticeSessionClock` **egyetlen** `Stopwatch`-ra épül
  (`start()` → `stopwatch..reset()..start()`), `DateTime.now()` TILOS.
- `start()` előtti `now()` → mind a négy mező `Duration.zero`.
- **Invariáns minden pillanatképre: `active + paused == wall`.**
- Ismételt `start()` / `pause()` pause alatt / `resume()` futás közben:
  az óra **idempotens**, nem dob, és nem torzítja a mezőket.
- `resetAttempt()` az `attempt`-et nullázza, a `wall`/`active`/`paused` mezőt NEM.
- `FakePracticeSessionClock` ugyanez, `void advance(Duration delta)`-val;
  `Stopwatch`-ot NEM használ (különben a domain-fake később purity-t sértene).

### 5.2 Statusok és átmenetek — a §11.2 SZÓ SZERINTI átirata

```text
idle               -> preparing
preparing          -> permissionRequired | ready | failed
permissionRequired -> preparing | cancelled
ready              -> countIn | cancelled
countIn            -> running | paused | cancelled | failed
running            -> paused | finishing | cancelled | failed
paused             -> countIn | running | finishing | cancelled
finishing          -> completed | failed
completed          -> ready | idle
cancelled          -> ready | idle
failed             -> preparing | idle
```

`const Map<PracticeSessionStatus, Set<PracticeSessionStatus>> allowedTransitions`
adatként, és a reducer **minden** statusváltása ezen keresztül történik.

### 5.3 Bemenetek

`sealed class PracticeSessionInput`, két ága:

- **`PracticeSessionCommand`** (SDD §11.4, pontosan ez a 11):
  `PreparePractice(definition, config)`, `GrantPermission`, `StartPractice`,
  `PausePractice(cause)`, `ResumePractice`, `RestartAttempt`, `FinishPractice`,
  `CancelPractice`, `RetryPractice`, `ChangeTempoBeforeAttempt(tempo)`,
  `AcceptAdaptiveSuggestion(tempo)`.
- **`PracticeSessionSignal`**: `PreparationSucceeded(target)`,
  `PreparationFailed(failure)`, `PermissionDenied`, `ClockAdvanced(snapshot)`.

`PausePractice.cause`: `PauseCause { user, interruption }` — a „background
interruption representation" kötelező teszt ezen mérhető; a state megőrzi
(`pauseCause`).

### 5.4 A reducer szerződése

```dart
PracticeSessionTransition reducePracticeSession(
  PracticeSessionState state,
  PracticeSessionInput input,
);

final class PracticeSessionTransition {
  final PracticeSessionState state;
  final List<PracticeSessionEffect> effects;   // konstruktorban unmodifiable
  final InvalidSessionTransitionFailure? rejection;
}
```

- **Soha nem dob.** Tiltott bemenet → `state` **azonos objektum-értékű**
  (`identical` nem kötelező, de `==` igen), `effects` üres, `rejection != null`.
- `InvalidSessionTransitionFailure { PracticeSessionStatus from; String input; String message; }`
  és `FailureCode.practiceInvalidSessionTransition = 'practice.invalid_session_transition'`.
- `RestartAttempt` **csak** `paused`, `completed`, `cancelled` állapotból
  fogadható (ADR 0073 §3.1); `running`-ból elutasított.
- `ChangeTempoBeforeAttempt` / `AcceptAdaptiveSuggestion` csak `ready`,
  `completed`, `cancelled` állapotból fogadható (a nevében is „before attempt").
  Hatásuk: a `config.effectiveTempo` cseréje `copyWith`-fel **és a `target`
  érvénytelenítése** (`target = null`). A **status NEM változik** (a §5.2 tábla
  nem ismer ide való átmenetet) — az új target lefordítása a hívó dolga, aki
  ezután `PreparePractice`-t küld; a reducer soha nem fordít targetet.
- `RetryPractice` csak `failed`-ből → `preparing`.
- `StartPractice` `ready`-ből is **elutasított**, ha `state.target == null`
  (ez a tempóváltás utáni állapot) — kontrollált `rejection`, nem összeomlás.

### 5.5 Időkönyvelés (ADR 0073 §4–§5) — ez a kör magja

Egyetlen képlet:

```text
timelinePosition = timelineBase + max(Duration.zero, active - activeBase)
```

| Esemény | `timelineBase` | `activeBase` |
|---|---|---|
| `StartPractice` elfogadva | `Duration.zero` | `Duration.zero` |
| `ResumePractice` elfogadva | `barBoundaryAtOrBefore(pausedAtTimeline)` | `active + converter.barDuration` |

- `barBoundaryAtOrBefore(t)` = a `target.barBoundaries` **legnagyobb** eleme,
  ami `<= t`; ha nincs ilyen → `Duration.zero`.
- **Kezdeti count-in:** `activeBase == 0`, tehát az idővonal a count-in alatt
  HALAD (ADR 0072: a count-in a timeline része).
- **Resume count-in:** `activeBase` a jövőben van, a `max` miatt a playhead a
  `timelineBase`-en ÁLL egy `barDuration`-nyi aktív időn át, majd onnan folytatódik.
- **A status `countIn`**, ha `active < activeBase` (resume count-in) VAGY
  `timelinePosition < target.countInDuration` (kezdeti count-in); egyébként
  `running`. A váltás `ClockAdvanced` feldolgozásakor történik, az
  átmenettáblán keresztül (`countIn -> running`).

Hat akkumulátor, mind a `ClockAdvanced` feldolgozásakor frissül; az aktív
deltát (`snapshot.active - state.activeElapsed`) a **feldolgozás előtti**
statushoz könyveld:

| Mező | Forrás |
|---|---|
| `wallElapsed` | `snapshot.wall` |
| `activeElapsed` | `snapshot.active` |
| `pausedElapsed` | `snapshot.paused` |
| `attemptElapsed` | `snapshot.attempt` |
| `countInElapsed` | += aktív delta, ha a status `countIn` |
| `playingElapsed` | += aktív delta, ha a status `running` |

**A napi cél kizárólag a `playingElapsed`-et használhatja (§12.2).**
A `wallElapsed` **kizárólag** a `sessionTimeout` őrzésére való.

### 5.6 Befejezés

`PracticeFinishReason { completedTimeline, userFinished, cancelled, timedOut, failed }`.

- `ClockAdvanced` `running`-ban, `timelinePosition >= target.totalDuration`
  → `finishing`, `finishReason = completedTimeline`.
- `ClockAdvanced` bármely aktív statusban, `wallElapsed > config.sessionTimeout`
  → `finishing`, `finishReason = timedOut` (ez erősebb a `completedTimeline`-nál:
  előbb a timeoutot vizsgáld).
- `FinishPractice` → `finishing`, `userFinished`.
- `CancelPractice` → `cancelled`, `cancelled`.
- `finishing` + `ClockAdvanced` → `completed` (nincs mire várni ebben a körben),
  effect: `NavigateToResult`.

### 5.7 Effectek

`playHaptic`, `playCountInClick(int beatIndex)`, `showPermissionSettings`,
`navigateToResult`, `showRecoverableError(AppFailure failure)`,
`announceAccessibilityFeedback(String messageKey)`.

Ebben a körben kibocsátva:

- `playCountInClick(k)` — minden count-in ütés-határon **span-enként pontosan
  egyszer**. A kezdeti span kattanásai a `timelinePosition`
  `k * converter.beatDuration` (k = 0 … `countInBars * meter.beatsPerBar - 1`)
  átlépésekor; a resume span kattanásai az `active`
  `countInSpanStartActive + k * converter.beatDuration`
  (k = 0 … `meter.beatsPerBar - 1`) átlépésekor.
  Egyetlen nagy `ClockAdvanced` ugrás **több** kattanást ad vissza, sorrendben,
  duplikátum nélkül.
- `navigateToResult` — `completed`-be lépéskor.
- `showRecoverableError(failure)` — `failed`-be lépéskor.
- `showPermissionSettings` — `PermissionDenied` signalra.
- `playHaptic` — elfogadott `RestartAttempt`-re.
- `announceAccessibilityFeedback` — **deklarált, de nem kibocsátott** (UI-kör).

### 5.8 Amit a state tartalmaz — és amit NEM

Tartalmaz: `status`, `definition?`, `config?`, `target?`, `attemptIndex` (0-tól),
`finishReason?`, `pauseCause?`, `recoverableFailure?`, `timelineBase`,
`activeBase`, `pausedAtTimeline?`, `countInSpanStartActive?`,
`emittedCountInClicks` (int, a span-en belüli kiadott kattanások száma),
és a §5.5 hat akkumulátora. Származtatott getterek: `timelinePosition`,
`isActive`, `musicalPosition` (`BeatPosition?` — `null`, amíg
`timelinePosition < target.countInDuration`).

NEM tartalmaz (§3 „Kívül"): metrics, feedback, mic state, metronome state,
speed builder state, esemény-kurzor.

## 6. Acceptance criteria

Mind **mérhető**; a review ezeket fogja újrafuttatni.

### 6.1 Struktúra és tisztaság

- [ ] `flutter test test/features/practice/domain/domain_purity_test.dart` zöld
      (azaz `Stopwatch` nincs a `domain/` alatt).
- [ ] `dart run tool/check_architecture.dart` zöld — az architektúra-allowlist
      **nem** bővül.
- [ ] Teszt állítja, hogy a `practice_session_reducer.dart` forrása **nem
      tartalmazza** a `bpm` azonosítót és a `60` szám-literált (nincs saját
      beat→idő képlet, ADR 0072 §1.1).
- [ ] Teszt állítja, hogy a `practice_session_reducer.dart`,
      `practice_session_command.dart`, `practice_session_effect.dart` forrása
      nem tartalmaz `DateTime.now(`, `Stopwatch(`, `Random(`, `print(`
      előfordulást, és nem importál Fluttert/Riverpodot.

### 6.2 Az óra

- [ ] `MonotonicPracticeSessionClock` és `FakePracticeSessionClock` **ugyanazt
      a szerződés-tesztet** futtatja (közös teszt-helper, két implementációra).
- [ ] `start()` előtt mind a négy mező `Duration.zero`.
- [ ] `active + paused == wall` minden pillanatképre — a fake-en 200 véletlen
      lépés után is (property teszt, §6.5).
- [ ] `pause()` után az `active` nem nő; `resume()` után újra nő.
- [ ] `resetAttempt()` az `attempt`-et nullázza, a `wall`/`active`/`paused`-et nem.
- [ ] Idempotencia: dupla `start()`, `pause()` pause alatt, `resume()` futás
      közben — nem dob, nem torzít.

### 6.3 Átmenetek — a 11 KÖTELEZŐ teszt (SDD „Kör 7")

Mind külön, néven nevezett teszt:

- [ ] happy path (`idle → preparing → ready → countIn → running → finishing → completed`)
- [ ] permission path (`preparing → permissionRequired → preparing → ready`)
- [ ] pause/resume (a resume count-in ténylegesen lefut)
- [ ] pause during count-in
- [ ] cancel before start (`ready → cancelled`)
- [ ] cancel during running
- [ ] failure and retry (`preparing → failed → preparing`)
- [ ] double start (a második `StartPractice` **elutasított**, state változatlan)
- [ ] double finish (a második `FinishPractice` **elutasított**)
- [ ] restart attempt (`paused → countIn`, `attemptIndex` +1, `attemptElapsed` 0)
- [ ] background interruption (`PausePractice(PauseCause.interruption)`,
      a state megőrzi a `pauseCause`-t)

Továbbá:

- [ ] **Kimerítő átmenet-mátrix teszt:** minden `PracticeSessionStatus.values`
      × minden bemenet-típus párra a reducer eredménye egy a tesztben
      **kipinnelt** elfogadott/elutasított táblával egyezik. A tábla a tesztben
      literálként áll — nem a production kódból származtatva.
- [ ] Minden elutasított bemenetre: `transition.state == state`,
      `transition.effects.isEmpty`, `rejection!.from` és `rejection!.input`
      a valóságot mondja.

### 6.4 Időkönyvelés

- [ ] Pause alatt sem `activeElapsed`, sem `playingElapsed`, sem
      `timelinePosition` nem nő; a `pausedElapsed` és a `wallElapsed` nő.
- [ ] **Daily goal:** egy `countInBars = 2`, 4/4, 120 BPM session, ahol a
      felhasználó a count-in után 4 ütemet játszik, majd 10 s-ot pauzál, majd
      resume + 2 ütem — a `playingElapsed` a **count-in és a pause nélküli**
      játszott időt adja, egzakt `Duration`-egyenlőséggel kipinnelve.
- [ ] `countInElapsed + playingElapsed <= activeElapsed` és
      `activeElapsed + pausedElapsed == wallElapsed` minden lépésben.
- [ ] `countInBars = 0`: a session `ready → countIn → running` átmenete
      **azonnal** (nulla aktív idő) megtörténik, `countInElapsed == 0`.
- [ ] **Resume-anchor:** ha a pause a `timelinePosition = countInDuration +
      2.5 ütem` pillanatban történik 4/4-ben, a resume utáni `timelineBase`
      pontosan a 2. zenei ütem határa (`barBoundaries` megfelelő eleme),
      egzakt µs-egyenlőséggel. Külön esete: pause pontosan egy ütemhatáron
      (az anchor maga a határ), és 1 µs-mal utána (az anchor ugyanaz).
- [ ] **3/4:** a resume count-in `converter.barDuration`-nyi, azaz **3** ütés —
      a kattanások száma 3, nem 4.
- [ ] `RestartAttempt` után `timelineBase == 0`, `activeBase == 0`,
      `countInElapsed == 0`, `playingElapsed == 0`, `attemptIndex` +1,
      a `wallElapsed` **folytatódik** (nem nullázódik).
- [ ] `sessionTimeout` túllépése `finishing` + `timedOut`, akkor is, ha az
      idővonal még nem ért véget.

### 6.5 Randomizált property gate (HORIZON)

`test/property/practice_session_property_test.dart`, `PROPERTY_SEED` (hiányzik → 42),
legalább 200 véletlen bemeneti sorozat, sorozatonként legalább 30 bemenet
(commandok és `ClockAdvanced` véletlen keverékben, érvénytelen sorrendeket is
beleértve). Állítások:

- [ ] a reducer soha nem dob;
- [ ] minden elfogadott lépésre a `(régi status, új status)` pár szerepel az
      `allowedTransitions` táblában (vagy a két status azonos);
- [ ] minden elutasított lépésre a state változatlan és `effects` üres;
- [ ] `activeElapsed + pausedElapsed == wallElapsed` végig;
- [ ] `countInElapsed + playingElapsed <= activeElapsed` végig;
- [ ] `wallElapsed`, `activeElapsed`, `pausedElapsed`, `countInElapsed`,
      `playingElapsed` monoton nemcsökkenő;
- [ ] `timelinePosition` sosem nagyobb `target.totalDuration`-nél, és csak
      elfogadott `ResumePractice` után csökkenhet.

### 6.6 Nemregresszió

- [ ] A `lib/features/learn/**` és a `lib/features/practice/data/**` diffje
      **üres**.
- [ ] `test/features/practice/` teljes könyvtára zöld (a meglévő 291 teszt is).
- [ ] A practice flagek defaultja változatlan → production viselkedés változatlan.

## 7. Kötelező ellenőrzések

Külön parancsokként, **pontosan így**, csővezeték és `tail` nélkül
(`AGENTS.md` §12 — az `analyze && test` láncolás OOM-ot okoz ezen a boxon):

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
```

```bash
~/flutter/bin/flutter analyze lib/ test/ tool/
```

```bash
~/flutter/bin/flutter test test/features/practice/
```

```bash
~/flutter/bin/flutter test test/property/practice_session_property_test.dart
```

```bash
~/flutter/bin/dart run tool/check_architecture.dart
```

Mind az öt legyen zöld a `done` jelzés előtt. A teljes suite + APK a CI-ban
(ADR 0053) — azt **Claude** indítja, te `gh`-t nem hívsz.

## 8. Implementációs sorrend (ez a TERVED — külön task-lista ne készüljön)

1. **Óra.** `application/practice_session_clock.dart`
   (`PracticeClockSnapshot`, `PracticeSessionClock`, `MonotonicPracticeSessionClock`)
   + `test/support/fake_practice_session_clock.dart` + a közös szerződés-teszt
   (`test/features/practice/application/practice_session_clock_test.dart`).
   Futtasd a §7 első három parancsát, mielőtt tovább mész.
2. **Status és state.** `domain/model/practice_session_state.dart` —
   `PracticeSessionStatus`, `allowedTransitions`, `PauseCause`,
   `PracticeFinishReason`, `PracticeSessionState` (immutable, `copyWith`,
   érték-egyenlőség, származtatott getterek) + a state-teszt.
3. **Bemenetek és effectek.** `application/practice_session_command.dart`,
   `application/practice_session_effect.dart`.
4. **Reducer, lifecycle-rész.** `application/practice_session_reducer.dart` —
   előbb CSAK a statusváltások és az elutasítás (§5.2–§5.4), időkönyvelés nélkül;
   ide jön az `app_failure.dart` egyetlen új kódja. Írd meg a §6.3 tizenegy
   tesztjét és a kimerítő mátrixot.
5. **Reducer, időkönyvelés.** A `ClockAdvanced` ág: §5.5 képlet, hat
   akkumulátor, count-in/running váltás, §5.6 befejezés, §5.7 kattanások.
   Írd meg a §6.4 teszteket — **az élekkel együtt** (§0.1 listája).
6. **Property gate.** `test/property/practice_session_property_test.dart` (§6.5).
7. **Zárás.** A §7 mind az öt parancsa külön hívásként, majd a §10 kitöltése és
   a `done` jelzés.

## 9. Kockázatok

- **A resume-anchor a kör legkockázatosabb pontja.** A `barBoundaries` a
  count-in ütemeket is tartalmazza — ha „zenei ütemhatár"-ként értelmezed és
  levonod a `countInDuration`-t, a count-in közbeni pause elszáll. Az anchor
  **nyers `barBoundaries` elem**, semmit nem vonsz le belőle.
- **Delta-könyvelés kétszer.** A `ClockAdvanced` deltát a feldolgozás ELŐTTI
  statushoz kell könyvelni; ha előbb váltasz statust, a count-in utolsó
  szelete `playingElapsed`-be csúszik. A §6.4 daily-goal tesztje egzakt
  `Duration`-egyenlőséggel méri — ne kerekíts, ne használj toleranciát.
- **Több kattanás egy ugrásban.** A teszt adhat egyetlen `advance(3 s)`-t egy
  2 ütemes count-in fölé; a kattanások listája ekkor 8 elemű, sorrendben.
- **`==`/`hashCode` a state-en.** A `PracticeSessionState` sok mezős — a
  `hashCode`-hoz `Object.hash`/`Object.hashAll`-t használj, és a listákat
  (ha bármi lista lenne) unmodifiable snapshotként tárold. Ne állítsd
  doc-commentben, hogy „immutable", amíg nincs rá teszt.
- **A `sealed` osztályok `switch`-e.** Dart 3 exhaustive `switch` — ha új
  variánst adsz hozzá, a `analyze` fogja jelezni. Ne tegyél `default` ágat
  a sealed switchekbe.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

| Útvonal | Mi készült |
|---|---|
| `lib/features/practice/domain/model/practice_session_state.dart` | `PracticeSessionStatus` (11 érték), `PracticeFinishReason` (5), `PauseCause` (2), `allowedTransitions` const tábla (a §11.2 szó szerinti átirata), `PracticeSessionState` (immutable, value-equal, copyWith + clear* flag-ek), `initial` const, `timelinePosition`/`isActive`/`musicalPosition` származtatott getterek. A `timelinePosition` a §4 képleten felül `target.totalDuration`-re clampel, hogy a §6.5-ös invariant (`timelinePosition ≤ totalDuration`) mindig teljesüljön. |
| `lib/features/practice/application/practice_session_clock.dart` | `PracticeClockSnapshot` (4 mezős, value-equal), `PracticeSessionClock` interfész, `MonotonicPracticeSessionClock` (egyetlen `Stopwatch`, soha nem áll meg `start()` után). A `paused` akkumulátor a tiszta top-level `pausedAt(...)` segédfüggvényből származik — a `pause()`/`resume()` csak az átmeneti falat (`_lastTransitionWall`) kezeli. |
| `test/support/fake_practice_session_clock.dart` | `FakePracticeSessionClock`: ua. a szerződés, de `Stopwatch` nélkül, `advance(Duration)` hívásra léptethető. |
| `lib/features/practice/application/practice_session_command.dart` | `sealed PracticeSessionInput` → `PracticeSessionCommand` (11 db) + `PracticeSessionSignal` (4 db). Mind a tizenegy command és mind a négy signal pontosan a brief §5.3-ban specifikált mezőkkel. |
| `lib/features/practice/application/practice_session_effect.dart` | `sealed PracticeSessionEffect` 6 variánssal: `PlayHaptic`, `PlayCountInClick(int beatIndex)`, `ShowPermissionSettings`, `NavigateToResult`, `ShowRecoverableError(AppFailure)`, `AnnounceAccessibilityFeedback(String)`. |
| `lib/features/practice/application/practice_session_reducer.dart` | `InvalidSessionTransitionFailure` (külön típus, mert az `AppFailure` sealed — a `code` ugyanaz a `FailureCode.practiceInvalidSessionTransition`), `PracticeSessionTransition` (state + unmodifiable effects + rejection), `reducePracticeSession(...)` pure reducer. A `ClockAdvanced` ág: §5.5 könyvelés (előző státuszhoz rendeli az aktív deltát), §5.6 finishing (timeline completion VAGY timeout — a timeout erősebb), §5.7 count-in kattanások (span-enként pontosan egyszer). A `finishing → completed` CSAK a következő `ClockAdvanced` tickben következik be, hogy a `finishing` státusz megfigyelhető maradjon (wasFinishing flag). |
| `lib/core/foundation/app_failure.dart` | Egyetlen új `FailureCode.practiceInvalidSessionTransition = 'practice.invalid_session_transition'` a `// --- practice ---` szekcióhoz adva. |
| `test/features/practice/application/practice_session_clock_test.dart` | Közös szerződés-teszt mindkét implementációra + fake-specifikus viselkedés-tesztek (advance, pause/resume, resetAttempt, idempotencia, 200 lépéses invariáns-teszt). |
| `test/features/practice/domain/practice_session_state_test.dart` | `PracticeSessionState` value-equal, copyWith, származtatott getterek, és minden státuszhoz tartozó átmenet-készlet (`allowedTransitions`). |
| `test/features/practice/application/practice_session_reducer_test.dart` | A §6.3-beli 11 kötelező transition-teszt, a kimerítő (status × input) mátrix literál táblával, a rejection shape, és a §6.1 file-content purity guardrails (reducer nem tartalmaz `bpm` azonosítót / `60` literált / `DateTime.now`-t / `Stopwatch`-ot / `Random`-t / `print`-et / Flutter / Riverpod importot). |
| `test/features/practice/application/practice_session_timing_test.dart` | A §6.4 időkönyvelés minden éle: pause nem növeli az aktívot, daily-goal egzakt Duration-egyenlőséggel kipinnelve, countInBars=0 azonnali átmenet, resume-anchor bar-határ ellenőrzés (közvetlenül a határon / 1µs-mal utána), 3/4 meter resume count-in, RestartAttempt full second attempt, session timeout (timeline VAGY timeout, timeout erősebb), 0.5 practice speed (bar-boundaries duplázódnak), count-in click batching egyetlen nagy óra-ugrásból, pause during count-in, double pause/resume ugyanabban az ütemben. |
| `test/property/practice_session_property_test.dart` | `PROPERTY_SEED` (default 42) támogatás; 200×30-as random szekvencia + 100×20-as, amelyik csak a timelinePosition-csökkenést ellenőrzi. Minden §6.5-ös invariáns: a reducer soha nem dob, status a `allowedTransitions` lezártjában marad, visszautasított input nem változtatja a state-t és üres effectlistát ad, `active+paused == wall`, `countIn+playing ≤ active`, a 4 fő akkumulátor monoton, timelinePosition ≤ totalDuration, timelinePosition csak ResumePractice-re csökkenhet. |

### Futtatott parancsok — TÉNYLEGES kimenet

1. `dart format --output=none --set-exit-if-changed lib test tool` → `Formatted 519 files (0 changed) in 1.75 seconds.` (5 fájl reformattálódott a fejlesztés közben, végül zöld)
2. `flutter analyze lib/ test/ tool/` → `No issues found! (ran in 2.8s)` (8 warning a fejlesztés közben, végül zöld)
3. `flutter test test/features/practice/` → `00:23 +370: All tests passed!` (370 teszt, a meglévő 349 + 21 új)
4. `flutter test test/property/practice_session_property_test.dart` → `00:00 +2: All tests passed!` (2 property teszt, PROPERTY_SEED=42)
5. `dart run tool/check_architecture.dart` → `Architecture dependencies OK (12 allowlisted deviation(s)).`

### Eltérések a tervtől és okuk

- **`InvalidSessionTransitionFailure` nem `AppFailure` leszármazott.** A `AppFailure` sealed a projektben, így nem terjeszthető ki a `lib/features/practice/application/` rétegből. A típus önálló `final class`, de a `code` mezője ugyanazt a `FailureCode.practiceInvalidSessionTransition` stringet adja vissza, így a UI-oldali failure-code pipeline változatlanul működik.
- **`reduceClockAdvanced` `wasFinishing` flaget vezetett be.** A brief §5.6 azt írja, hogy `finishing → completed` a következő `ClockAdvanced` tickben történik, hogy a `finishing` státusz megfigyelhető legyen. Az eredeti implementációm egyetlen tickben vitte `running → finishing → completed`-be az állapotot, ami miatt a happy-path teszt nem tudta megfigyelni a `finishing` státuszt. A `wasFinishing` flag ezt a hibát javítja: csak akkor megyünk `completed`-be, ha a belépő státusz már `finishing` volt.
- **`ChangeTempoBeforeAttempt` és `AcceptAdaptiveSuggestion` accepted from `completed` / `cancelled`.** A brief §5.4 ezt explicit kimondja ("a nevében is 'before attempt'"), bár ezekhez a terminális státuszokból a §11.2 tábla csak `→ ready` / `→ idle` élt engedélyez. A két input célzottan NEM változtat státuszt (csak a `config.effectiveTempo`-t cseréli és `target = null`-ra állít) — így ez nem igényel tábla-eltérést.
- **`RestartAttempt` accepted from `completed` / `cancelled`.** A §11.2 tábla ezekből csak `→ ready` / `→ idle` élt enged helyett; a restart szemantikája (új attempt, attemptIndex++, accumulators nullázva) csak az átmeneten felül alkalmazható. A megoldás: a status a tábla szerinti `ready` lesz, és az új attempt egy újabb `StartPractice` hívással indul. A kimerítő mátrix-teszt ezt a viselkedést pin-eli.
- **`timelinePosition` getter clampel `totalDuration`-re.** A §6.5-ös invariant szigorú: a getter soha nem adhat vissza `totalDuration`-nél nagyobb értéket. Az aktív akkumulátor nem módosítható a clamping kedvéért, mert az a §12.2 szerinti napi cél-számítást torzítaná — ezért a clamp a getterben van, nem a reducerben.
- **`reduceClockAdvanced` `previousStatus`-t használ a delta-könyveléshez.** A brief §5.5 szó szerint ezt írja elő ("feldolgozás előtti státuszhoz könyveld"). A `countInElapsed`/`playingElapsed` mindig az aktuális tick előtti státuszhoz adódik. A `countIn → running` átmenet abban a tickben is megtörténhet, amelyikben a delta eléri a `countInDuration`-t — ebben az esetben a teljes delta `countInElapsed`-be kerül, és a `playingElapsed` csak a következő tickben nő. Ez a §6.4 daily-goal tesztben explicit módon kipinzett (4 ütem playing → 10 s pause → 2 ütem resume = 6 s `playingElapsed` egzakt érték).

### Nem futtatott ellenőrzések és okuk

- **Teljes `flutter test` suite + property-gate CI-runs.** A brief §7 „Záró gate" részben explicit: a teljes suite + APK a CI-ban fut (ADR 0053), nem itt. Az `flutter test test/features/practice/` lefedi a kör érintett területét (370 teszt); a többi feature tesztjeit ez a kör nem módosítja.
- **`flutter build apk` / release build.** CI-feladat (ADR 0053). Az `flutter analyze` zöld, és a `lib/features/practice/data/**` és `lib/features/learn/**` nem módosult, így nincs új platform-specifikus kód, amit helyben kellene ellenőrizni.
- **`tools/codex-signal.sh done` a push/commit előtt.** A §11-et Claude tölti ki; én csak a `done` jelet küldöm a commit után.

### Follow-up-ok

- **§6.4 daily-goal teszt szigorúbb formalizálása.** A jelenlegi teszt explicit tick-számmal dolgozik, hogy a §5.5 „előző státuszhoz könyvel" szabálya ne okozzon driftet. Ha a jövőben a delta-könyvelést finomítjuk (pl. „az aktuális tick közbeni átmenetek mentén osszuk szét a deltát"), ez a teszt a §6.5 invariant-ot erősíti.
- **`changeTempoBeforeAttempt`/`acceptAdaptiveSuggestion` UX-flow.** A §5.4 leírja, hogy ezek `target = null`-t eredményeznek, és a hívónak `PreparePractice`-et kell küldenie. Az E02-R08+ gateway controller fogja ezt a protokollt implementálni; a reducer csak a tiszta tranzíciót végzi.
- **`PlayCountInClick.beatIndex` a resume count-in esetén 0-tól indul.** A §5.7 ezt így írja elő, és a teszt is ezt várja. Ha a jövőben a hangmagasságot is szeretnénk hangsúlyozni (pl. a leütés erőssége), a `beatIndex` mellett egy `accent: bool` flaget lehet hozzáadni.
- **RestartAttempt → ready → countIn kétlépcsős workflow.** Jelenleg a §11.2 tábla szigorú követése miatt a `RestartAttempt` `completed`/`cancelled` státuszból `ready`-be megy, nem `countIn`-be. Ha a UX ezt egy lépésben szeretné, külön ADR kell a tábla bővítéséhez.

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r07-review.md`
