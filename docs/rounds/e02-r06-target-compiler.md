# E02-R06 — Target compiler és beat-idő konverzió

- **Státusz:** IMPLEMENTED — REVIEW PENDING (2026-07-30)
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` §12.3, §14, „Kör 6 — Target compiler és beat-idő konverzió"
- **Előfeltétel:** E02-R05 merge-ölve (PR #26) — a domain-modellek, a katalógus és a legacy adapterek készen állnak
- **Branch:** `codex/epic-02-round-06-target-compiler`
- **Implementer motor:** **Codex** ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6: a count-in / ring-out / tempó-skálázás a **befagyasztott** `legacyLearnParity` időzítéssel érintkezik ⇒ baseline-érzékeny kör)
- **Kiosztott ADR:** **0072** — [`docs/adr/0072-practice-target-compiler.md`](../adr/0072-practice-target-compiler.md).
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

**STOP-klauzula:** ha bármelyik követelmény ütközik a §4 engedélyezett-fájllistával
vagy egy meglévő teszttel: **ÁLLJ MEG**, küldd a `stopped` jelzést, és jelentsd az
ütközést — ne kerüld meg csendben.

**Munkamód:** a **§8 a terved** — ne készíts külön task-listát, fázisonként
legfeljebb egy állapotfrissítés. Ne állíts a kódról a doc-commentben olyat,
amit nem ellenőriztél.

## 0.1 A kör legfontosabb tanulsága ELŐRE (E02-R05 review)

**A zöld gate nem bizonyíték.** Az E02-R05-ben mindhárom MINOR úgy csúszott át,
hogy `format` + `analyze` + a teljes suite zöld volt — a review eldobható
próbateszttel, a **legacy referenciával szembe mérve** fogta meg őket (egy
hibátlan Analyze-klip idővonala némán kétszer olyan hosszú lett).

Ebben a körben minden számolt kimenetnek (idő, hossz, határ, szegmens)
**legyen a legacy referenciával vagy egy kipinnelt szekvenciával szembe mérő
tesztje az ÉLEKEN**, nem csak a boldog úton:

- nem-nulla kezdet (nem-0 count-in, loop `startBar > 0`),
- határra eső utolsó esemény (`position + 1 tick == totalBeats`),
- 3/4 (a count-in ott 3 ütés, nem 4),
- 0,5-ös és 0,75-ös practice speed,
- egyetlen eseményből álló és teljesen üres target.

## 1. Cél

Egyetlen kanonikus beat↔idő konverzió (`BeatTimeConverter`) és egy tiszta
`PracticeTargetCompiler`, ami egy `PracticeDefinition` + `PracticeSessionConfig`
párból determinisztikus, időzített `CompiledPracticeTarget`-et készít
(count-in, ring-out, ütemhatárok, expected-chord szegmensek, loop, scoring
applicability). A mai Learn út **egyetlen sorát sem** módosítjuk; hívó UI és
provider ebben a körben NEM készül. A kör kimenete az E02-R07 (session clock és
state machine) és az E02-R08 (matcher/scorer) bemenete.

## 2. Jelenlegi állapot (mért tények, `main @ 7288969`)

### 2.1 A legacy időzítés — ez a parity-referencia (NEM módosítható)

- **`lib/features/learn/lesson_scorer.dart:85`** — `_secPerBeat = 60.0 / (bpm ?? lesson.bpm)`;
  **:87** — `final t = (countInBeats + e.beat) * _secPerBeat;`
  **:241** — `double timeOf(LessonEvent event) => (countInBeats + event.beat) * _secPerBeat;`
  A konstruktor alapértelmezése `countInBeats = 4`.
- **`lib/features/learn/lesson_timing.dart:11`** — `beatForElapsed = elapsedSec * bpm / 60.0`;
  **:15** — `playhead = beatForElapsed - countInBeats`;
  **:30** — `countInNumber`: `playheadBeat.floor() + countInBeats + 1`, `clamp(1, countInBeats)`;
  **:39** — `isFinished(playhead, totalBeats, beatsPerBar) => playhead >= totalBeats + beatsPerBar`
  → **a ring-out pontosan egy ütem.**
- **`lib/features/learn/screens/learn_screen.dart:47`** — `int get _countInBeats => _lesson.beatsPerBar;`
  → **a valódi Learn út count-inje egy ütem** (3/4-ben 3 ütés), nem a scorer 4-es defaultja.
  **:74** — `double get _bpm => _lesson.bpm * _speed;` (a `_speed` a
  `practiceSpeedProvider` értéke, `options = [0.5, 0.75, 1.0]`).
  **:498–510** — `_activeChord()`: végigmegy az eseményeken, egy akkordos esemény
  akkor lesz aktív, ha `e.beat <= _playhead + 0.25`; ha még egy sem érte el a
  playheadet, **az első akkordot mutatja pre-rollként** (tehát már a count-in alatt).
- **`test/support/practice_baseline_scenarios.dart:46`** —
  `double get finishAtSec => (countInBeats + lesson.totalBeats + lesson.beatsPerBar) * 60 / bpm;`
  a tíz befagyasztott baseline-forgatókönyvben (`assert(countInBeats == lesson.beatsPerBar)`).
  **Ez a kör gépi parity-mércéje** (§6.3).

### 2.2 A domain, amire építeni kell (E02-R02/R03 — NEM e kör dolga újraírni)

- **`BeatPosition`** (`domain/model/beat_position.dart`) — 480 PPQ egész tick;
  `ticksPerBeat = 480`; `fromTicks` negatívra `ArgumentError`; `quarters/eighths/
  sixteenths/eighthTriplets`; `fromLegacyBeats` (`(beats*480).round()`, negatív/
  nem-véges → dob); `toLegacyBeats()`; `+`, `-`, `compareTo`, érték-egyenlőség.
- **`Tempo`** — `bpm` `double`, érvényes 30,0–300,0 (`minimumBpm`/`maximumBpm`),
  `validate()`, **a domain nem clampel**.
- **`Meter`** — `beatsPerBar` 1..16, `beatUnit ∈ {2,4,8}` (alap 4);
  **`int get ticksPerBar`** — érvénytelen mezőre `StateError` (fail-fast, E02-R02
  MINOR-1 zárása); `beatUnit` 2 → 960, 4 → 480, 8 → 240 tick / meter-beat.
- **`PracticeDefinition`** — `id, schemaVersion, titleKey, descriptionKey, mode,
  source, meter, defaultTempo, totalBeats, events, scoringProfile, skillTags,
  sourceReference?, difficulty, displayTitle?`. A `validate()` őrzi: rendezettség,
  pozíció-egyediség, `position.ticks < totalBeats.ticks` (**kizárólagos** felső határ),
  scored módnál nem üres eseménylista, a profil súlykulcsainak pontos egyezése a
  mód `scoredDimensions`-ével.
- **`PracticeEvent`** — `id, position, duration?, chord?, direction?, accent,
  optional, marker`; nem-marker eseménynek kell `chord` VAGY `direction`.
- **`PracticeSessionConfig`** (`domain/model/practice_session_config.dart`) —
  `definitionId, definitionSnapshotVersion, effectiveTempo, countInBars (0..4),
  loopCount (1..32), metronomeEnabled, accentEnabled, backingEnabled,
  scoringProfileId, easyVariationId?, inputLatency, visualLatency (0..500 ms),
  expectedChordHintEnabled, sessionTimeout (>0), reducedMotion`, `validate()`,
  `copyWith`, érték-egyenlőség. **Loop-tartomány NINCS benne** — a §5.4
  `PracticeLoopRange` külön paraméter.
- **`PracticeMode`** — `strumPattern.scoredDimensions = {rhythm, direction}`,
  `freePractice.scoredDimensions = {}` (üres).
- **`PracticeValidationCode`** — 61 stabil kód + `allCodes` halmaz;
  `PracticeValidationFailure {code, message}`.
- **`AppResult<T>` / `Success` / `Failure`**, `ValidationFailure`,
  `FailureCode` (`lib/core/foundation/`) — a practice szekcióban ma egyetlen kód:
  `practiceContentUnsupported = 'practice.content_unsupported'`.
- **`test/features/practice/domain/domain_purity_test.dart`** — a
  `lib/features/practice/domain/` teljes fája alatt tiltja: `DateTime.now(`,
  `Stopwatch(`, `Random(`, `print(`, flutter/riverpod/dio/shared_preferences
  import, l10n import. **Az új fájlok is ez alá esnek.**
- **`tool/check_architecture.dart:232`** — a `lib/features/practice/domain/`
  prefix framework-független zónaként van bejegyezve.

### 2.3 Ami MA NINCS (ezt csinálja a kör)

- Nincs `Duration`-t adó beat→idő konverzió a practice domainben (grep:
  `60000|secPerBeat|Duration(` a `lib/features/practice/` alatt csak az
  adapterek `60.0 / bpm` legacy-hídján és a config latency-mezőin talál).
- Nincs `CompiledPracticeTarget`, nincs compiler, nincs loop-normalizálás,
  nincs ütemhatár-lista, nincs expected-chord szegmentálás.

## 3. Scope

**Benne:**

1. `BeatTimeConverter` — az egyetlen kanonikus beat↔idő konverzió (§5.1).
2. `CompiledPracticeTarget` + `CompiledTargetEvent` + `ExpectedChordSegment`
   + `PracticeLoopRange` értékmodellek (§5.2–5.4).
3. `PracticeTargetCompiler` — tiszta fordító `AppResult<CompiledPracticeTarget>`-tel (§5.5).
4. Célzott tesztek, köztük a **legacy parity-mérés** (§6.3) és a **korpusz-szintű
   no-op bizonyítás** (§6.4).
5. `FailureCode.practiceTargetUncompilable` + a szükséges új
   `PracticeValidationCode` kódok.
6. Dokumentáció: traceability-mátrix sor + `docs/rounds/` státusz + §10 handoff.

**Kívül (ebben a körben TILOS):**

- A legacy Learn út bármely fájlja (`lib/features/learn/**`) — még import-rendezés
  szintjén sem. A parity-referenciát nem szabad hozzáigazítani a kimenethez.
- UI, képernyő, widget, provider, Riverpod, ARB/l10n, routing.
- Session clock / state machine (E02-R07), matcher / scorer / metrikák (E02-R08+),
  Speed Builder, adaptív policy.
- Input-latency korrekció (SDD §12.4) és frame-delivery-lag — a scorer köréé.
- DSP/ML paraméter, `docs/rag/chunks/`, modell-bináris (AGENTS.md §9).
- `PracticeDefinition`, `PracticeEvent`, `PracticeSessionConfig`, `ScoringProfile`,
  `Tempo`, `Meter`, `BeatPosition` **viselkedésének** módosítása. A
  `ScoringProfile.legacyLearnParity` **befagyasztott**.
- A `docs/rag/chunks/014` follow-up (HANDOFF §6.3) — nem ez a kör.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak hozhatók létre / módosíthatók. Bármi más → **MEGÁLLÁS
és `stopped` jelzés**.

| Útvonal | Miért |
|---|---|
| `lib/features/practice/domain/model/beat_time_converter.dart` | ÚJ — kanonikus beat↔idő konverzió |
| `lib/features/practice/domain/model/compiled_practice_target.dart` | ÚJ — target + esemény + szegmens + loop-tartomány értékmodellek |
| `lib/features/practice/domain/service/practice_target_compiler.dart` | ÚJ — a fordító (tiszta függvény/osztály) |
| `lib/features/practice/domain/model/practice_validation.dart` | csak ÚJ kódok hozzáadása + `allCodes` bővítése; meglévő kód sem át nem nevezhető, sem el nem távolítható |
| `lib/core/foundation/app_failure.dart` | csak a `// --- practice ---` szekcióba egyetlen új konstans |
| `test/features/practice/domain/beat_time_converter_test.dart` | ÚJ |
| `test/features/practice/domain/compiled_practice_target_test.dart` | ÚJ |
| `test/features/practice/domain/practice_target_compiler_test.dart` | ÚJ |
| `test/features/practice/domain/practice_target_legacy_parity_test.dart` | ÚJ — a legacy referenciával szembe mérő teszt (§6.3–6.4) |
| `test/features/practice/domain/practice_validation_test.dart` | csak az új kódok felvétele a meglévő teljességi ellenőrzésbe |
| `docs/execution/06-requirements-traceability-matrix.md` | csak az `E02-R06` sor |
| `docs/rounds/e02-r06-target-compiler.md` | csak a §10 handoff kitöltése + Státusz |

**Tilos zóna:** `lib/features/learn/**`, `lib/features/songs/**`,
`lib/features/analyze/**`, `lib/features/streak/**`, `lib/features/live/**`,
`lib/features/practice/data/**`, `lib/features/practice/application/**`,
`lib/l10n/**`, `docs/adr/**`, `docs/rag/**`, `docs/sdd/**`, `HANDOFF.md`,
`AGENTS.md`, `.github/**`, `pubspec.yaml`, `tool/check_architecture.dart`,
`test/support/practice_baseline_scenarios.dart`,
`test/fixtures/practice/legacy_scorer_baseline.json`.

A `test/support/practice_baseline_scenarios.dart`-ot **olvasni kell** (a parity
bemenete), **írni tilos** — ez a befagyasztott baseline.

## 5. Kötött architekturális döntések (ADR 0072)

Ezektől új ADR nélkül eltérni nem lehet. Ha valamelyik ütközik a kóddal:
**`stopped` jelzés + jelentés**, nem néma átértelmezés.

### 5.1 `BeatTimeConverter`

```dart
final class BeatTimeConverter {
  const BeatTimeConverter({required this.tempo, required this.meter});

  final Tempo tempo;
  final Meter meter;

  Duration timeOf(BeatPosition position);   // ticks -> Duration a nullponttól
  Duration timeOfTicks(int ticks);          // a fenti nyers-tick változata
  BeatPosition positionAt(Duration time);   // inverz, legközelebbi tickre
  Duration get beatDuration;                // egy negyed (480 tick)
  Duration get barDuration;                 // meter.ticksPerBar
}
```

- Aritmetika: `micros = (ticks * 60000000 / (tempo.bpm * BeatPosition.ticksPerBeat)).round()`
  — **egyszeri** kerekítés a végén, semmilyen esemény-soronkénti akkumuláció.
- `positionAt`: `ticks = (micros * bpm * 480 / 60000000).round()`, negatív
  `Duration`-re `ArgumentError` (a `BeatPosition` nem lehet negatív).
- **Fail-fast**: ha `tempo.validate()` vagy `meter.validate()` nem üres, minden
  konverziós tag `StateError`-t dob (a `Meter.ticksPerBar` mintája). Csendes
  `Infinity`/`NaN` tilos. Ezt tesztben bizonyítsd.
- `const` konstruktor: csak akkor írd ki a doc-commentbe, hogy `const`, ha
  tesztben `const BeatTimeConverter(...)` ténylegesen fordul.

### 5.2 `CompiledPracticeTarget`

Immutable, value-equal (`==`/`hashCode`, a listákra a meglévő
`practice_value_equality.dart` segédek). Az idővonal **nullpontja a session
start**, tehát minden `Duration` a count-innal EGYÜTT értendő.

```dart
final class CompiledPracticeTarget {
  final String definitionId;
  final int definitionSnapshotVersion;
  final Tempo tempo;              // az EFFEKTÍV tempó
  final Meter meter;
  final int countInBars;
  final Duration countInDuration; // countInBars * barDuration
  final List<CompiledTargetEvent> events;      // szigorúan nemcsökkenő idő
  final Duration musicalDuration; // a loopokkal együtt vett zenei hossz
  final Duration ringOutDuration; // pontosan egy ütem
  final Duration totalDuration;   // countIn + musical + ringOut
  final List<Duration> barBoundaries; // lásd §5.3
  final int loopCount;
  final PracticeLoopRange? loopRange;
  final List<ExpectedChordSegment> expectedChordSegments;
  final bool scoringApplicable;
}

final class CompiledTargetEvent {
  final String sourceEventId;
  final int loopIndex;           // 0-alapú
  final BeatPosition position;   // ABSZOLÚT a compiled idővonalon (count-in nélkül)
  final Duration time;           // session-starttól, count-innal együtt
  final int barIndex;            // 0-alapú zenei ütem, count-in nélkül
  final String? chord;
  final StrumDirection? direction;
  final bool accent;
  final bool optional;
}

final class ExpectedChordSegment {
  final String chord;
  final Duration start;          // session-starttól
  final Duration end;            // kizárólagos
}
```

- `marker: true` események **nem** kerülnek a `events` listába (nem targetek),
  de a `barBoundaries`/hossz számítást sem befolyásolják.
- Minden lista `List.unmodifiable`. Ha a doc-comment „unmodifiable"-t állít,
  tesztben bizonyítsd (`expect(() => t.events.add(...), throwsUnsupportedError)`).

### 5.3 Ütemhatárok, count-in, ring-out

- `countInDuration = countInBars * barDuration`. A legacy Learn út **egy** ütemmel
  számol (`_countInBeats = beatsPerBar`), de a compiler a `config.countInBars`-t
  veszi (0..4); a parity-teszt `countInBars = 1`-gyel mér.
- `ringOutDuration = barDuration` (pontosan egy ütem, `lesson_timing.dart:39`).
- `barBoundaries`: **a count-in downbeatjeivel kezdve**, a zenei rész végéig
  **bezárólag**. Azaz `barBoundaries.length == countInBars + musicalBars + 1`,
  `barBoundaries.first == Duration.zero`, és
  `barBoundaries[countInBars] == countInDuration` (az első zenei downbeat),
  `barBoundaries.last == countInDuration + musicalDuration`. Szigorúan növekvő.
- **Pass-hossz mindig egész ütem**: `passTicks = ceil(sourceTicks / ticksPerBar) * ticksPerBar`,
  ahol `sourceTicks` loop nélkül `definition.totalBeats.ticks`, loop esetén
  `(endBarExclusive - startBar) * ticksPerBar`.
  `musicalDuration = timeOfTicks(passTicks * loopCount)`.

### 5.4 Loop

```dart
final class PracticeLoopRange {
  const PracticeLoopRange({required this.startBar, required this.endBarExclusive});
  final int startBar;
  final int endBarExclusive;
}
```

- Érvényesség: `startBar >= 0`, `endBarExclusive > startBar`,
  `endBarExclusive <= definitionBars` (ahol `definitionBars = ceil(totalBeats.ticks / ticksPerBar)`).
  Sértés → **kontrollált `Failure`**, soha nem clamp és soha nem néma vágás.
- A tartományba eső események pass-lokálisra rebase-elődnek
  (`position - startBar * ticksPerBar`), és `loopCount`-szor ismétlődnek
  `loopIndex = 0..loopCount-1`-gyel, `passTicks * loopIndex` eltolással.
- Az esemény-ID-k stabilak és egyediek: `sourceEventId` az EREDETI ID marad, az
  egyediséget a `(sourceEventId, loopIndex)` pár adja.

### 5.5 `PracticeTargetCompiler`

```dart
AppResult<CompiledPracticeTarget> compilePracticeTarget({
  required PracticeDefinition definition,
  required PracticeSessionConfig config,
  PracticeLoopRange? loopRange,
});
```

Ellenőrzési sorrend (az ELSŐ hiba állítja meg, `ValidationFailure` +
`FailureCode.practiceTargetUncompilable`, a `message`-ben a stabil
`PracticeValidationCode`-dal):

1. `definition.validate()` nem üres → `target.definitionInvalid`
2. `config.validate()` nem üres → `target.configInvalid`
3. `config.definitionId != definition.id` → `target.definitionMismatch`
4. `config.easyVariationId != null && config.easyVariationId != definition.id`
   → `target.variationMismatch` (ADR 0072 §5 — az Easy nem tűnhet el csendben)
5. `loopRange` érvénytelen → `target.loopRangeInvalid`

Siker esetén:

- `scoringApplicable = definition.mode.scoredDimensions.isNotEmpty && events.isNotEmpty`
- **Free Practice** (üres eseménylista): NEM hiba — `events` üres,
  `scoringApplicable == false`, `expectedChordSegments` üres, a
  `musicalDuration` viszont a szokásos `passTicks × loopCount` (tehát NEM nulla).
  **Brief-revízió 2026-07-30 (az első futás `stopped` jelzése nyomán):** az
  eredeti szöveg „nulla `totalBeats` esetén `Duration.zero`"-t írt — ez az
  állapot **elérhetetlen**, és a Codex helyesen állt meg rajta. A
  `PracticeDefinition.validate()` (`practice_definition.dart:100`,
  `definitionTotalBeatsNonPositive`) minden `totalBeats <= 0`-t elutasít, és ezt
  meglévő teszt rögzíti (`practice_definition_test.dart:42`). Egy Free Practice
  definition `totalBeats`-e is szigorúan pozitív; a ma szállított két forrás:
  `builtin.freePracticeTemplate.v1` → `BeatPosition.quarters(16)`, az
  eseménymentes Analyze-import → `quarters(beatsPerBar)` (egy ütem).
  Nulla `totalBeats`-ű definition tehát el sem jut a fordításig — a fenti
  1. lépés `target.definitionInvalid`-dal bukik, és **ez a helyes viselkedés**.
  A `PracticeDefinition` validációját és tesztjét ebben a körben **tilos**
  hozzáigazítani; a fájl a §4 tilos zónájában marad.
- **Monotonitás**: a kimeneti `events` ideje nemcsökkenő. Ezt a compiler a
  visszaadás előtt ellenőrizze, és sértésnél `StateError`-t dobjon (belső
  invariáns, nem user-hiba) — a tesztek a korpuszon bizonyítják, hogy nem sül el.

### 5.6 Expected-chord szegmensek (legacy parity)

A legacy `_activeChord()` (`learn_screen.dart:498`) szemantikája:

- egy akkordos esemény akkor válik aktívvá, ha `e.beat <= playhead + 0.25`
  ⇒ **a szegmens 0,25 ütemmel (120 tick) az esemény ELŐTT kezdődik**;
- amíg egyik akkordos esemény sem érte el a playheadet, **az első akkord látszik**
  ⇒ az első szegmens `start == Duration.zero` (már a count-in alatt);
- egymást követő azonos címkék EGY szegmensbe olvadnak;
- egy szegmens vége a következő szegmens kezdete; az utolsóé `totalDuration`
  (a ring-out alatt is az utolsó akkord az aktív).

Nevesített konstans: `PracticeTargetCompiler.expectedChordLookahead`
(= `BeatPosition(120)`), doc-commenttel a legacy forrásra hivatkozva.
Ha `definition`-ban nincs akkordos esemény, a lista üres.

## 6. Acceptance criteria (mérhető)

### 6.1 Konverter

- [ ] `BeatTimeConverter.timeOf` 120 BPM-en: `BeatPosition.quarters(1)` → 500 ms,
      `eighths(1)` → 250 ms, `BeatPosition(1)` (1 tick) → 1042 µs
      (`(1*60000000/(120*480)).round() == 1042`).
- [ ] `positionAt(timeOf(p)) == p` a `[0, 480*64]` tick-tartomány minden
      **32-tick** rácspontjára, 60 / 90 / 120 / 137,5 BPM mellett.
- [ ] Érvénytelen `Tempo(0)` / `Meter(beatsPerBar: 0)` mellett minden konverziós
      tag `StateError`-t dob (nem `Infinity`, nem `NaN`, nem 0).
- [ ] Negatív `Duration`-re `positionAt` `ArgumentError`-t dob.

### 6.2 Compiler — szerkezet

- [ ] 4/4, `countInBars: 1`, `loopCount: 1`: `barBoundaries.length == 1 + musicalBars + 1`,
      `first == Duration.zero`, `[1] == countInDuration`, `last == countIn + musical`.
- [ ] 3/4: `countInDuration` **három** ütés hosszú (nem négy), és a
      `barBoundaries` lépésköze `barDuration`.
- [ ] `loopCount: 3` esetén az események száma `3 × forrás`, a `loopIndex`
      0,1,2, és a k-adik loop minden eseményének ideje pontosan
      `k * passTicks` tick-kel későbbi.
- [ ] `PracticeLoopRange(startBar: 1, endBarExclusive: 2)` egy 4 ütemes
      definitionön: csak a 2. ütem eseményei, pass-lokálisra rebase-elve
      (az első esemény `position` < `ticksPerBar`).
- [ ] Érvénytelen loop (`endBarExclusive == startBar`, `startBar < 0`,
      `endBarExclusive > definitionBars`) → `Failure`, kód `target.loopRangeInvalid`,
      **és** a kimenet nem `Success` (nincs csendes clamp).
- [ ] `definitionId` eltérés, Easy-variáció eltérés, érvénytelen definition és
      érvénytelen config: mind a §5.5 sorrend szerinti kóddal bukik.
- [ ] Free Practice (üres események): `Success`, `events` üres,
      `scoringApplicable == false`, `expectedChordSegments` üres.
- [ ] Egy-eseményes target: `events.length == 1`, ideje
      `countInDuration + timeOf(position)`.
- [ ] Determinisztikus egyenlőség: két külön hívás azonos bemenettel
      `==` és azonos `hashCode`; a listák `unmodifiable`.
- [ ] Minden compiled esemény ideje nemcsökkenő (korpuszon is, §6.4).

### 6.3 Legacy parity — a kör fő mércéje

`test/features/practice/domain/practice_target_legacy_parity_test.dart`:

- [ ] A tíz `practiceBaselineScenarios` mindegyikére, a lecke `Lesson`-jét az
      E02-R05 `practiceDefinitionFromLesson` adapterével `PracticeDefinition`-né
      alakítva, `countInBars: 1`, `loopCount: 1` config mellett:
      **`target.totalDuration.inMicroseconds` és a scenario
      `finishAtSec` mikroszekundumba kerekített értéke között az eltérés ≤ 1 µs.**
- [ ] Ugyanezekre a forgatókönyvekre **eseményszinten**: minden compiled esemény
      `time`-ja és a legacy `(countInBeats + e.beat) * 60 / bpm` másodpercérték
      mikroszekundumba kerekített alakja között az eltérés ≤ 1 µs.
      (A legacy értéket a teszt maga számolja a `scenario.lesson.events`-ből —
      `LessonScorer`-t nem kell példányosítani, de ha mégis, akkor is csak
      OLVASOD, nem módosítod.)
- [ ] Mind a 17 szállított leckére (`Lessons.all` + `Lessons.firstWin`),
      **három practice speeden** (`0.5`, `0.75`, `1.0` — a `bpm * speed` a
      `Tempo` tartományon belül; ami kilóg, azt a teszt nevesítve hagyja ki és
      a kihagyás okát a jelentésbe írod), ugyanez az eseményszintű ≤ 1 µs egyezés.
- [ ] **Élek:** a legkésőbbi eseményű lecke utolsó eseménye
      (`position.ticks == totalBeats.ticks - 1` esethez legközelebbi) és a
      3/4-es lecke is szerepeljen a mért halmazban — a teszt nevezze meg őket.

### 6.4 Korpusz-szintű no-op bizonyítás (ADR 0072 §4)

- [ ] A pass-hossz egész ütemre kerekítése **no-op** a ma szállított tartalom
      egészére: mind a 17 leckére, a 10 `BuiltinPracticeCatalog` gyakorlatra és
      a Daily-Challenge-adapter egy napjára igaz, hogy
      `definition.totalBeats.ticks % meter.ticksPerBar == 0`.
      A teszt **listázza** a vizsgált ID-ket (a szám ne legyen bemondás).
- [ ] Ugyanezen a korpuszon: minden compiled target eseményideje szigorúan
      nemcsökkenő, és `totalDuration == countIn + musical + ringOut`.

### 6.5 Expected-chord

- [ ] Egy kipinnelt, kézzel kiszámolt definitionön (legalább: akkordváltás
      ütemenként, egy ismételt címke, egy akkord nélküli esemény) a
      `expectedChordSegments` **pontos** listája: címke + `start` + `end`
      mikroszekundumban, kiírt várt értékekkel.
- [ ] Az első szegmens `start == Duration.zero`, az utolsó `end == totalDuration`,
      a szegmensek hézagmentesen és átfedés nélkül fedik a `[0, totalDuration)`
      intervallumot, és egymást követő azonos címke nem fordul elő.
- [ ] A lookahead pontosan 120 tick: egy 480 tickre (1 negyed) eső akkordváltás
      szegmens-kezdete `timeOf(BeatPosition(360)) + countInDuration`.

### 6.6 Higiénia

- [ ] `domain_purity_test.dart` zöld az új fájlokkal (nincs `DateTime.now`,
      `Stopwatch`, `Random`, `print`, flutter/riverpod import a domainben).
- [ ] Az új `PracticeValidationCode` kódok szerepelnek az `allCodes` halmazban,
      és a `practice_validation_test.dart` teljességi ellenőrzése zöld.
- [ ] `FailureCode.practiceTargetUncompilable` értéke `'practice.target_uncompilable'`.
- [ ] `git diff --stat` a §4 listán kívül nulla fájlt érint.

## 7. Kötelező ellenőrzések

Külön parancsokként (AGENTS.md §12 — **soha ne láncold `&&`-del**, és az
`analyze` meg a `test` soha nem egy hívásban; ez a box OOM-ol tőle).
Köztes gyors ellenőrzést szűkíthetsz egy tesztfájlra, de a **ZÁRÓ gate-sort
pontosan így**, csővezeték és `tail` nélkül, teljes kimenettel kell lefuttatni:

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/features/practice/
```

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0053](../adr/0053-ci-full-test-suite.md)) — a dispatch **Claude dolga**,
ne hívj `gh`-t.

## 8. Implementációs sorrend (ez a terved)

1. **Konverter.** `beat_time_converter.dart` + `beat_time_converter_test.dart`
   (§6.1). Itt dől el az aritmetika helyessége — előbb ez legyen zöld.
2. **Értékmodellek.** `compiled_practice_target.dart` (+ `PracticeLoopRange`,
   `CompiledTargetEvent`, `ExpectedChordSegment`) + egyenlőség/unmodifiable
   tesztek.
3. **Új kódok.** `PracticeValidationCode` bővítés + `allCodes` +
   `FailureCode.practiceTargetUncompilable`; a meglévő validációs teszt
   teljességi ellenőrzésének frissítése.
4. **Compiler.** `practice_target_compiler.dart` — validációs sorrend, count-in,
   pass-hossz, loop, ütemhatárok, monotonitás-őr.
5. **Expected-chord szegmentálás** + a kipinnelt teszt (§6.5).
6. **Legacy parity teszt** (§6.3) és a korpusz-teszt (§6.4). **Ha itt eltérést
   mérsz, a legacy oldalt NEM igazítod** — `stopped`/`blocked` jelzés a mért
   számokkal.
7. Záró gate-sor (§7), traceability-sor, §10 handoff kitöltése, `done` jelzés.

## 9. Kockázatok

- **Kerekítési parity.** A legacy `double` út és az egész-mikroszekundumos út
  csak akkor egyezik ≤ 1 µs-en belül, ha a compiler is EGYSZER kerekít. Ha
  eseményenként `Duration`-öket adsz össze, a hiba halmozódik és a §6.3 bukik.
- **A count-in kettős default.** A `LessonScorer` alapértelmezése 4 ütés, a
  VALÓDI Learn úté `beatsPerBar` (3/4-ben 3). A parity mércéje a
  `practiceBaselineScenarios` (`assert(countInBeats == lesson.beatsPerBar)`) —
  ne a scorer defaultjához mérj.
- **`totalBeats` kizárólagos.** `position.ticks < totalBeats.ticks`; egy
  `<=`-re írt határellenőrzés a definition-validációval ütközik.
- **Practice speed a `Tempo` tartományon kívül.** `bpm * 0.5` egy 60 BPM-es
  leckén 30 → még érvényes; 50 BPM-esen 25 → **érvénytelen**. Ne clampelj, hagyd
  ki nevesítve és jelentsd.
- **`Meter.ticksPerBar` dob.** Mindig validált metert adj neki; a fail-fast
  szándékos (E02-R02 MINOR-1).
- **Scope-szivárgás a legacy felé.** A `lib/features/learn/**` teljesen zárt —
  ha a parityhez ott kellene bármit megnyitni, az `stopped`, nem szerkesztés.

## 10. Implementation handoff (a Codex tölti ki)

### Megvalósítás fájlonként

- `lib/features/practice/domain/model/beat_time_converter.dart`: kanonikus,
  egész mikroszekundumos beat↔idő konverzió egyszeri kerekítéssel, inverz
  konverzióval és érvénytelen tempo/meter fail-fast őrrel.
- `lib/features/practice/domain/model/compiled_practice_target.dart`:
  `CompiledPracticeTarget`, `CompiledTargetEvent`, `ExpectedChordSegment` és
  `PracticeLoopRange` immutable értékmodellek; teljes value equality/hash és
  védekező `List.unmodifiable` snapshotok.
- `lib/features/practice/domain/service/practice_target_compiler.dart`:
  kötött validációs sorrend, egész ütemre kerekített pass, count-in, együtemes
  ring-out, loop-kiválasztás/rebase/ismétlés, ütemhatárok, marker-szűrés,
  monotonitás-őr és a legacy `_activeChord()` 120 tickes lookahead
  szemantikáját követő expected-chord szegmentálás.
- `lib/features/practice/domain/model/practice_validation.dart` és
  `lib/core/foundation/app_failure.dart`: öt stabil target-validációs kód,
  kanonikus `allCodes` (kompatibilis `values` alias) és
  `practice.target_uncompilable`.
- `test/features/practice/domain/{beat_time_converter,compiled_practice_target,practice_target_compiler,practice_target_legacy_parity}_test.dart`
  és `practice_validation_test.dart`: konverter-, értékmodell-, compiler-,
  validációs sorrend-, loop-, Free Practice-, expected-chord-, legacy parity-
  és teljes szállított korpusztesztek. Külön kipinnelve: nem nulla count-in,
  két count-in ütem, három loop, 3/4 és 3/8 meter, 0,5/0,75/1,0 speed,
  kizárólagos utolsó tick, marker-only, egy-eseményes és üres target, részleges
  utolsó ütem loopja, valamint loop-határon váltó akkord.
- `docs/execution/06-requirements-traceability-matrix.md`: csak az E02-R06 sor
  frissítve ezzel a bizonyítékkal.

### Mért parity és korpusz

- 10 befagyasztott baseline scenario: maximum total/finish eltérés **0 µs**,
  maximum eseményeltérés **0 µs**.
- 17 szállított lecke × 3 speed (0,5 / 0,75 / 1,0): maximum
  eseményeltérés **0 µs**; kihagyott tempó **nincs**.
- 17 lecke + 10 builtin + 1 Daily Challenge, összesen 28 nevesített
  definition: **28/28** whole-bar kerekítési no-op; minden compiled eseményidő
  nemcsökkenő és minden duration-kompozíció pontos.
- Független read-only auditok: scope/API **APPROVE**, compiler-matematika
  **APPROVE**, acceptance/test újraaudit **APPROVE** (53/53 releváns célteszt).

### Záró gate-ek tényleges kimenete

A parancsok külön hívásban, csővezeték és `tail` nélkül futottak:

```text
$ ~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
Formatted 506 files (0 changed) in 1.70 seconds.

$ ~/flutter/bin/flutter analyze lib/ test/
Analyzing 2 items...
No issues found! (ran in 2.7s)

$ ~/flutter/bin/flutter test test/features/practice/
00:15 +289: All tests passed!
```

### Nem futtatott ellenőrzések, eltérések és follow-up

- A teljes `flutter test`, a randomizált property gate és a release APK csak
  CI-ban fut; a dispatch, a PR és a merge az ADR 0064 szerint Claude feladata.
- Backend- és ML-gate nem releváns, mert a kör nem módosított backend-, DSP-
  vagy ML-kódot.
- Implementációs eltérés és ismert funkcionális follow-up nincs. A brief első
  változatának elérhetetlen nulla-`totalBeats` Free Practice elvárását a
  brief-revízió javította; a compiler a javított szerződés szerint az ilyen
  definitiont az első validációs lépésben elutasítja.
- Pontos következő kör: **E02-R07 — Session clock és state machine**.

## 11. Review

_(link: `docs/reviews/e02-r06-review.md`)_
