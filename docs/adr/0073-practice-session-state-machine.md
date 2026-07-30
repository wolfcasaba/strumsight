# ADR 0073 — Practice session clock és determinisztikus state machine

- **Státusz:** Elfogadva (2026-07-30)
- **Kör:** E02-R07 — Session clock és state machine
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` §11 (state machine), §12.1–12.2, §12.5, „Kör 7"
- **Előzmények:** [ADR 0066](0066-practice-tick-time-model.md) (480 PPQ tick-idő),
  [ADR 0068](0068-practice-domain-model-contracts.md) (domain-szerződések),
  [ADR 0072](0072-practice-target-compiler.md) (target compiler, **§1.1 időszabály**)

## Kontextus

Az E02-R06 után létezik a `CompiledPracticeTarget`: egy `PracticeDefinition` +
`PracticeSessionConfig` párból determinisztikus, `Duration`-alapú idővonal
(count-in a timeline RÉSZE, nullpont = session start, minden abszolút pillanat
a nullponttól vett tickszám EGYETLEN konverziója — ADR 0072 §1.1).

Ami hiányzik: az az egység, ami ezt az idővonalat *lejátssza* — session
lifecycle, pause/resume, attempt-újraindítás, és a §12.2 szerinti **négyféle
időszámláló** (wall / active / count-in / paused). A mai Learn út ezt a
`learn_screen.dart` `State`-jében, mutábilis mezőkkel és a widget-életciklushoz
kötve teszi; tesztelni csak widget-teszttel lehet, és a pause-számlálás
mérten hiányos (`_pause()` nem zárja a frame-subscriptiont —
`docs/rag/chunks/014-play-along-learn.md` nyitott follow-up).

Két követelmény ütközik naiv megvalósításban:

1. **§12.2:** a napi célba (daily goal) *csak az aktív playing idő* számíthat —
   a count-in és a pause NEM.
2. **§12.5:** resume után „egy rövid, egybaros count-in, majd folytatás a
   következő biztonságos bar boundarytől" — azaz a playhead resume-kor
   **visszaugrik** egy ütemhatárra, tehát az eltelt aktív idő és az idővonal-pozíció
   **nem azonos** mennyiség.

Ha ezt nem szabályozzuk pontosan, a session hossza és a napi cél némán elcsúszik,
és a hiba a zöld gate alatt láthatatlan (E02-R04/R05/R06 mért tanulsága).

## Döntés

### 1. Az óra minimális és monoton — a könyvelés a state-ben van

`PracticeSessionClock` (`lib/features/practice/application/practice_session_clock.dart`)
a SDD §12.1 négy mutátorát adja (`start`, `pause`, `resume`, `resetAttempt`),
és **`PracticeClockSnapshot now()`**-t ad vissza:

```dart
final class PracticeClockSnapshot {
  final Duration wall;      // start() óta eltelt teljes idő (pause-t IS tartalmazza)
  final Duration active;    // wall − paused
  final Duration paused;    // felhalmozott pause-idő
  final Duration attempt;   // active a legutóbbi resetAttempt() óta
}
```

**Invariáns (gépi mérce):** `active + paused == wall`, és mind a négy mennyiség
monoton nemcsökkenő az `attempt` kivételével, amit a `resetAttempt()` nulláz.

A production implementáció **`MonotonicPracticeSessionClock`** egyetlen
`Stopwatch`-ra épül (monoton, nem wall-clock — a `DateTime.now()` a practice
úton tiltott). A `Stopwatch` az `application/` rétegben van, mert a
`domain/` purity-teszt (`test/features/practice/domain/domain_purity_test.dart`)
tiltja — ez szándékos: az óra I/O-jellegű, nem domain-érték.

A **`FakePracticeSessionClock`** (`test/support/`) tetszőleges időre
előreléptethető (`advance(Duration)`), ugyanazt a szerződést tartja, és **nem
használ `Stopwatch`-ot** — a teljes state machine így UI és valós idő nélkül
tesztelhető (§ „Elfogadási feltételek: UI nélkül teljesen tesztelhető").

### 2. Egyetlen bemeneti csatorna: command + signal

A SDD §11.4 tizenegy **command**ja a felhasználói szándék. Ezen felül a
környezet **kimenetei** (előkészítés eredménye, engedély megtagadva, óra
előrelépett) nem felhasználói szándékok, mégis állapotot váltanak. Ezért a
reducer bemenete egy közös `PracticeSessionInput` sealed típus két ágon:

- `PracticeSessionCommand` — a §11.4 tizenegy command ja (UI szándék);
- `PracticeSessionSignal` — környezeti tény: `preparationSucceeded(target)`,
  `preparationFailed(failure)`, `permissionDenied`, `clockAdvanced(snapshot)`.

**Indoklás:** a §11.2 átmenettáblája `preparing -> permissionRequired | ready |
failed` háromfelé ágazik — ezt commandból nem lehet levezetni, mert az ág az
előkészítés eredményétől függ. Az idő előrehaladása (`clockAdvanced`) ugyanígy
tény, nem szándék; így viszont a **teljes state machine egyetlen pure
függvény**, és nincs rejtett `Timer` a domainben.

### 3. A reducer pure, és a tiltott átmenet kontrollált eredmény

```dart
PracticeSessionTransition reducePracticeSession(
  PracticeSessionState state,
  PracticeSessionInput input,
);
```

`PracticeSessionTransition { PracticeSessionState state, List<PracticeSessionEffect> effects, InvalidSessionTransitionFailure? rejection }`.

- Elfogadott bemenet → új (immutable) state + 0..n effect, `rejection == null`.
- **Tiltott** bemenet → a state **bitre változatlan**, `effects` üres, és
  `rejection` megnevezi a kiinduló statust és a bemenet nevét
  (`FailureCode.practiceInvalidSessionTransition = 'practice.invalid_session_transition'`).
  Release buildben sem csendes no-op (§11.2 explicit követelménye).
- A reducer **soha nem dob** — a kontrollált elutasítás a szerződés.

Az átmenettábla a §11.2 szövegének **szó szerinti** átirata, `const` adatként
(`PracticeSessionStatus.allowedTransitions`), és a reducer minden statusváltása
ellenőrzötten ebből a táblából történik.

#### 3.1 `RestartAttempt` csak `paused` / `completed` / `cancelled` állapotból

A §11.2 táblájában `running -> countIn` **nincs benne**. Ezért a `RestartAttempt`
futás közben kontrollált `rejection`-t ad; a UI-nak előbb `PausePractice`-t kell
küldenie. Megfontolt alternatíva volt a tábla bővítése `running -> countIn`-nal,
de egy baseline-érzékeny körben a SDD-tábla szó szerinti követése a kisebb
kockázat; ha a UX ezt később megkívánja, külön ADR bővíti.

### 4. Időkönyvelés — az idővonal-pozíció NEM az eltelt aktív idő

A state két bázist tart, és **egyetlen** képletet használ:

```text
timelinePosition = timelineBase + max(Duration.zero, active − activeBase)
```

| Esemény | `timelineBase` | `activeBase` |
|---|---|---|
| `StartPractice` elfogadva | `Duration.zero` | `Duration.zero` |
| `ResumePractice` elfogadva | `barBoundaryAtOrBefore(pausedAtTimeline)` | `active + barDuration` |

- **Kezdeti count-in:** `activeBase == 0`, tehát az idővonal a count-in alatt
  **halad** — ez az ADR 0072 szerződése (a count-in a timeline része, az
  események ideje tartalmazza).
- **Resume count-in:** `activeBase` a jövőben van, a `max(zero, …)` miatt a
  playhead a `timelineBase`-en **áll** egy ütemnyi aktív időn át, majd onnan
  folytatódik. Ez a §12.5 „következő biztonságos bar boundary" szabálya:
  az anchor a `CompiledPracticeTarget.barBoundaries` legnagyobb olyan eleme,
  ami `<= pausedAtTimeline` (a lista a count-in ütemeket IS tartalmazza, tehát
  count-in közbeni pause-ra is definiált).

**Nincs új beat→idő képlet:** minden időtartam a `CompiledPracticeTarget`
előre kiszámolt mezőiből vagy a `BeatTimeConverter`-ből jön. A reducer forrása
nem tartalmazhatja a `bpm` azonosítót (gépi mérce, §6).

### 5. Négy akkumulátor — a daily goal szabálya definíció szerint igaz

Minden `clockAdvanced` a legutóbbi pillanatkép óta eltelt **aktív** deltát a
**pillanatnyi statushoz** könyveli, a pause-deltát pedig a `pausedElapsed`-hez:

| Akkumulátor | Mit gyűjt |
|---|---|
| `wallElapsed` | `snapshot.wall` (a session start óta minden idő) |
| `activeElapsed` | `snapshot.active` |
| `countInElapsed` | aktív delta, amíg a status `countIn` |
| `playingElapsed` | aktív delta, amíg a status `running` |
| `pausedElapsed` | `snapshot.paused` |
| `attemptElapsed` | `snapshot.attempt` |

**A napi cél kizárólag a `playingElapsed`-et használhatja** (§12.2). Ebből
következik és gépi teszttel mért:

- `countInElapsed + playingElapsed <= activeElapsed`,
- pause alatt sem `activeElapsed`, sem `playingElapsed` nem nő,
- a resume count-in a `countInElapsed`-et növeli, a `playingElapsed`-et nem,
- `activeElapsed + pausedElapsed == wallElapsed`.

A `wallElapsed` **kizárólag** a `sessionTimeout` őrzésére használható,
pontozásra és a napi célra soha (§12.2, §11.2 „wall clock nem használható
scoringhoz").

### 6. Effect-modell — one-shot, a state-ben nem marad flag

`PracticeSessionEffect` sealed típus: `playHaptic`, `playCountInClick(beatIndex)`,
`showPermissionSettings`, `navigateToResult`, `showRecoverableError(failure)`,
`announceAccessibilityFeedback(messageKey)`. A reducer a `PracticeSessionTransition.effects`
listában adja vissza őket; a state **nem** tárolja őket (nincs „már megjelenítettem" flag).

Ebben a körben ténylegesen kibocsátott effectek: `playCountInClick` (minden
count-in ütés-határon, span-enként pontosan egyszer), `navigateToResult`
(`completed`-be lépéskor), `showRecoverableError` (`failed`-be lépéskor),
`showPermissionSettings` (`permissionDenied` signalra), `playHaptic`
(elfogadott `RestartAttempt`-re). Az `announceAccessibilityFeedback` deklarált,
de kibocsátása a UI-kör (E02-R13+) dolga.

### 7. Befejezési ok

`PracticeFinishReason { completedTimeline, userFinished, cancelled, timedOut, failed }`.
A `timedOut` akkor áll elő, ha `wallElapsed > config.sessionTimeout`; a
`completedTimeline`, ha `timelinePosition >= target.totalDuration` és a status
`running`.

## Következmények

**Pozitív**

- A teljes lifecycle UI, audio és valós idő nélkül tesztelhető; a kötelező
  tizenegy transition-teszt (§ „Kör 7") pure unit teszt.
- A daily goal / streak (§20.4–20.5, E02-R14) szerződése már itt gépi
  invariáns, nem későbbi jóhiszeműség.
- A pause-rés (`chunk 014`) lezárása az E02-R08-ban mechanikus lesz: a
  gateway a `status == running` állapotot kérdezi, nem widget-flaget.

**Negatív / kockázat**

- A `PracticeSessionSignal` bővíti a SDD §11.4 command-listáját. Ez tudatos,
  a §11.2 háromfelé ágazása miatt kényszerű, és a jelen ADR rögzíti.
- A resume-anchor visszaugrás miatt `playingElapsed` **nagyobb** lehet, mint a
  lejátszott idővonal hossza (az újrajátszott ütem kétszer számít playing
  időként). Ez szándékos: a felhasználó valóban gyakorolt akkor is. A pontozás
  (E02-R08+) az idővonal-pozíciót használja, nem a `playingElapsed`-et.
- `RestartAttempt` futás közben elutasított (§3.1) — a UI-nak komponálnia kell.

## Alternatívák

- **Az óra számolja a count-in/playing bontást.** Elvetve: az óra nem ismeri a
  statust; a bontás állapotfüggő, tehát a reducer dolga.
- **`Timer`-alapú self-tick a domainben.** Elvetve: nemdeterminisztikus és
  sérti a domain purity-t; a `clockAdvanced` signal a hívó felelőssége.
- **Resume azonnali folytatással (count-in nélkül).** Elvetve: a SDD §12.5
  Epic-2 alapértelmezése explicit.
