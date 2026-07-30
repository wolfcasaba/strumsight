# E02-R05 — Legacy adapterek: Lesson, Song, Analyze és Daily Challenge

- **Státusz:** PLANNING (indítás: 2026-07-30, kód olvasva: `main @ 6c2ed3c`)
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` — „Kör 5 — Legacy adapterek: Lesson, Song, Analyze és Daily Challenge"
- **Előfeltétel:** E02-R04 merge-ölve (PR #25) — a domain-szerződések és a katalógus készen állnak
- **Implementer motor:** **MiniMax M3** ([ADR 0069](../adr/0069-two-engine-implementer-pool.md) §15.6 besorolás: adapter, tételesen kipinnelt szerződéssel = volumenmunka; a felderítést a tervező már elvégezte, lásd §2)
- **Kiosztott ADR:** **0071** — [`docs/adr/0071-legacy-practice-adapters.md`](../adr/0071-legacy-practice-adapters.md).
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

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne commitolj, ne
pusholj — a CI-dispatch, a PR és a merge Claude-oldal.

**STOP-klauzula:** ha bármelyik követelmény ütközik a §4 engedélyezett-fájllistával
vagy egy meglévő teszttel: **ÁLLJ MEG**, küldd a `stopped` jelzést, és jelentsd az
ütközést — ne kerüld meg csendben.

**Munkamód:** a **§8 a terved** — ne készíts külön task-listát, fázisonként
legfeljebb egy állapotfrissítés. Ne állíts a kódról a doc-commentben olyat,
amit nem ellenőriztél: ha `const`-ot, `immutable`-t vagy „nem dob" viselkedést
írsz, előbb bizonyítsd tesztben.

## 1. Cél

A meglévő tanulási tartalom — Learn leckék (+ Easy variáns), user Songok,
Analyze-importok és a napi kihívás — átalakítása `PracticeDefinition` formára,
a régi implementáció **egyetlen sorának módosítása nélkül**. Az adapterek
tiszta függvények, `AppResult<PracticeDefinition>`-t adnak, és eseményszinten
egyeznek a mai `Lesson.events` szemantikával. Hívó UI és provider ebben a
körben NEM készül.

## 2. Jelenlegi állapot (mért tények, `main @ 6c2ed3c`)

### 2.1 A legacy tartalom, amit konvertálni kell

- **`lib/features/learn/model/lesson.dart`**
  - `LessonEvent { double beat; String chord; StrumDirection direction; }` —
    a `beat` nyolcadfelbontású (x.0 vagy x.5), a `chord` `''` = strum-only.
  - `Lesson` mezők: `id, name, double bpm, Difficulty difficulty,
    int beatsPerBar, List<LessonEvent> events, double totalBeats`.
  - `Lesson._expand`: `beat = bar * beatsPerBar + slot * 0.5`, a `null` slot
    kimarad, a minta `beatsPerBar * 2` slot hosszú (debug `assert`).
  - `Lesson.simplified`: az on-beat down-strokeok (`isDown && beat % 1.0 == 0`);
    **ha üres vagy minden eseményt megtartana, `this`-t ad vissza** — a
    `totalBeats` változatlan.
  - `Lessons.all` = 16 lecke, plusz a curriculumon kívüli `Lessons.firstWin`.
  - `Difficulty` = `beginner | intermediate | advanced`.
- **`lib/features/songs/model/song.dart`** — `Song { id, name, List<String>
  chords, List<StrumDirection?> pattern, int bpm, int beatsPerBar }`.
  `toLesson()` a `Lesson` bar/slot expanziót használja. A JSON-oldali korlátok:
  `bpm` 1..400, `beatsPerBar` 1..16, a `pattern` `_fitToMeter`-rel pontosan
  `beatsPerBar * 2` hosszúra igazítva — **de a memóriában konstruált `Song`-ra
  ez nem garantált**, ezért az adapternek magának kell ellenőriznie.
- **`lib/features/analyze/model/analyze_result.dart`** — `AnalyzeResult
  { double durationSec, double bpm, List<TimelineChord> chords,
  List<TimelineStrum> strums, int beatsPerBar, … }`;
  `TimelineChord { String label, double startSec, double endSec }`,
  `TimelineStrum { StrumDirection direction, double timeSec, double confidence }`.
  A referencia-konverzió `Lessons.fromAnalyze` (`lesson.dart:361`):
  bpm-fallback 90, `t0` = az első pengetés ideje, `beat = (t - t0) / secPerBeat`,
  akkord = a pengetés idején szóló `TimelineChord.label` (`t >= start && t < end`,
  különben `''`), `bars = max(1, floor(lastBeat / bpb) + 1)`.
- **`lib/features/streak/daily_challenge.dart`** — `DailyChallenge
  { int day, String name, List<StrumDirection> pattern }`, `forDay(epochDay)`
  determinisztikus (4/6/8 hosszú minta). A referencia-konverzió
  `Lessons.fromDailyChallenge` (`lesson.dart:401`): a minta első **legfeljebb 8**
  eleme nyolcad-slotokra, egy ütem, `chords: ['']`, alap bpm 80.

### 2.2 A cél-szerződés (E02-R02/R03/R04 — NEM e kör dolga újraírni)

- `PracticeDefinition` (`practice_definition.dart:19`) — kötelező: `id,
  schemaVersion, titleKey, descriptionKey, mode, source, meter, defaultTempo,
  totalBeats, events, scoringProfile, skillTags`; opcionális: `sourceReference`,
  `difficulty`. **Ebben a körben egészül ki a `displayTitle`-lel (§5.2).**
  `validate()` ellenőrzi: nem üres ID/kulcsok, pozitív `schemaVersion` és
  `totalBeats`, meter/tempo/profil validitás, esemény-validitás,
  scored módnál nem üres eseménylista, rendezettség, esemény-ID- és
  pozíció-egyediség, `position.ticks < totalBeats.ticks` (**kizárólagos**),
  és a profil súlykulcsainak pontos egyezése a mód `scoredDimensions`-ével.
- `PracticeEvent` — `id, position, duration?, chord?, direction?, accent,
  optional, marker`; nem-marker eseménynek kell `chord` VAGY `direction`.
  `isCanonicalPracticeChordLabel(String?)` — `null` vagy a 24 keresztes
  dúr/moll címke egyike.
- `BeatPosition` — 480 PPQ; `BeatPosition.fromLegacyBeats(double)` a
  legközelebbi tickre kerekít, és **negatív vagy nem-véges bemenetre `ArgumentError`-t
  DOB**; `toLegacyBeats()` a visszaút; `quarters/eighths/fromTicks` factoryk;
  `ticksPerBeat = 480`.
- `Tempo(double bpm)` — érvényes tartomány 30,0–300,0 (a domain nem clampel).
- `Meter({required beatsPerBar, beatUnit = 4})` — `beatsPerBar` 1..16,
  `beatUnit` ∈ {2,4,8}.
- `PracticeMode.strumPattern.scoredDimensions` = {rhythm, direction};
  `PracticeMode.freePractice.scoredDimensions` = {} (üres).
- `ScoringProfile.legacyLearnParity` (rhythm 55 / direction 45) — **BEFAGYASZTOTT**,
  egyetlen mezője sem módosulhat. `ScoringProfile.freePracticeOpen` — üres súlyok.
- `PracticeSource` — `lesson`, `song`, `analyze`, `dailyChallenge` értékek már
  léteznek. `PracticeDifficulty` — `beginner | intermediate | advanced`.
- `AppResult<T>` / `Success` / `Failure` + `ValidationFailure`
  (`lib/core/foundation/`), `FailureCode` stabil kódkészlettel.

### 2.3 A felderítés eredménye — ezért nincs nyitott kérdés az adapterekben

1. **A detektor akkord-szótára pontosan a kanonikus 24 címke**
   (`MlChordDecoder.majmin25Labels`, `ChordMatcher._qualities`), a legacy
   tartalom viszont `Em7`, `Cmaj7`, `A7`, `D7`, `Bb`, `Asus4`, `Cadd9`
   címkéket is hordoz. A `LessonScorer._gradeChords` pontos string-egyenlőséget
   használ → ezek a slotok **ma is mindig `chordMiss`-ek**. A veszteséges
   redukció (§5.1) tehát nem ront parityt. Részletes indoklás: ADR 0071 §2.
2. **A `strumPattern` mód nem pontoz akkordot**, a befagyasztott
   `legacyLearnParity` profil súlyai `rhythm`/`direction` — az akkordcímke az
   adaptált tartalomban megjelenítési/kontextus-információ.
3. **A `lib/features/songs/` nem publikál barrel fájlt**, a
   `crossFeatureImportsMustUsePublicApi` architektúra-szabály viszont tiltja a
   `practice → songs/model/song.dart` közvetlen importot, és az allowlist csak
   zsugorodhat → e kör létrehozza a `lib/features/songs/public.dart`-ot (§5.7).
4. **`Song.toLesson()` `assert`-tel bukik** hibás minta-hosszon (release-ben
   némán a következő ütembe csorogna) → az adapter **nem hívhatja**, saját
   előzetes ellenőrzést végez (§5.4).

### 2.4 Gépi őrök, amik már védenek

- `test/features/practice/domain/domain_purity_test.dart` — a
  `lib/features/practice/domain/` fát őrzi (nincs `DateTime.now(`, `Stopwatch(`,
  `Random(`, `print(`, flutter/riverpod/dio/prefs/l10n import). **Az e körben
  módosított `practice_definition.dart` és `practice_validation.dart` ennek az
  őrnek a hatálya alatt marad.**
- `test/features/practice/domain/practice_validation_test.dart` — a stabil
  validációs kódkészletet tételesen kipinneli (ma 60 kód).
- `test/core/architecture_dependency_test.dart` + `tool/check_architecture.dart`
  — cross-feature import csak `public.dart`-on át; az allowlist csak zsugorodhat.
- `test/features/practice/data/builtin_practice_catalog_test.dart` — a Kör 4
  katalógusa; a `displayTitle` bevezetése nem törheti el.

## 3. Scope

### 3.1 Benne van

1. `legacyPracticeChordLabel` normalizáló (§5.1).
2. `PracticeDefinition.displayTitle` + a hozzá tartozó validációs kód (§5.2).
3. Négy adapter: Lesson (+Easy), Song, Analyze, Daily Challenge (§5.3–§5.6).
4. `lib/features/songs/public.dart` barrel (§5.7).
5. `FailureCode.practiceContentUnsupported` (§5.8).
6. Unit- és parity-tesztek (§6).

### 3.2 NINCS benne (kifejezetten kívül)

- **A legacy kód BÁRMILYEN módosítása** (`lib/features/learn/**`,
  `lib/features/songs/model/**`, `lib/features/analyze/**`,
  `lib/features/streak/**` — a `songs/public.dart` ÚJ fájl az egyetlen kivétel).
- ARB szövegek (`lib/l10n/**` tilos zóna) — csak kulcsokat írunk le, fordítás
  az első UI-hívóval jön (ADR 0070 §3).
- UI, képernyő, route, Riverpod provider.
- Target compiler (Kör 6), matcher/scorer (Kör 9–10), perzisztencia (Kör 18).
- Count-in, ring-out, tempó-skálázás, loop, Speed Builder.
- Bármilyen DSP/ML paraméter (AGENTS.md §9).

## 4. Engedélyezett fájlok

| Fájl | Miért |
|---|---|
| `lib/features/practice/data/adapters/legacy_chord_label.dart` | ÚJ — akkordcímke-normalizáló |
| `lib/features/practice/data/adapters/lesson_practice_adapter.dart` | ÚJ |
| `lib/features/practice/data/adapters/song_practice_adapter.dart` | ÚJ |
| `lib/features/practice/data/adapters/analyze_practice_adapter.dart` | ÚJ |
| `lib/features/practice/data/adapters/daily_challenge_practice_adapter.dart` | ÚJ |
| `lib/features/practice/data/adapters/practice_adapter_keys.dart` | ÚJ — a közös ARB-kulcs- és séma-konstansok (§5.9) |
| `lib/features/songs/public.dart` | ÚJ — songs barrel (§5.7) |
| `lib/features/practice/domain/model/practice_definition.dart` | `displayTitle` mező + validáció (§5.2) |
| `lib/features/practice/domain/model/practice_validation.dart` | egy új stabil kód (§5.2) |
| `lib/core/foundation/app_failure.dart` | egy új `FailureCode` konstans (§5.8) |
| `test/features/practice/data/adapters/legacy_chord_label_test.dart` | ÚJ |
| `test/features/practice/data/adapters/lesson_practice_adapter_test.dart` | ÚJ |
| `test/features/practice/data/adapters/song_practice_adapter_test.dart` | ÚJ |
| `test/features/practice/data/adapters/analyze_practice_adapter_test.dart` | ÚJ |
| `test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart` | ÚJ |
| `test/features/practice/domain/practice_definition_test.dart` | meglévő — a `displayTitle` tesztjei ide |
| `test/features/practice/domain/practice_validation_test.dart` | meglévő — a kipinnelt kódkészlet 60 → 61 |

**Tilos zóna** (ha bármelyikhez hozzá kellene nyúlni: MEGÁLLÁS és `stopped`
jelzés): `lib/l10n/**`, `docs/**`, `HANDOFF.md`, `pubspec.yaml`, `.github/**`,
`tool/**`, `ml/**`, `lib/features/learn/**`, `lib/features/live/**`,
`lib/features/analyze/**`, `lib/features/streak/**`,
`lib/features/songs/**` a **`public.dart` kivételével**,
`lib/features/practice/data/builtin_practice_catalog.dart`,
`lib/features/practice/application/**`,
`lib/features/practice/domain/model/scoring_profile.dart` és minden további
`domain/model/*.dart` a `practice_definition.dart` + `practice_validation.dart`
KIVÉTELÉVEL, valamint minden meglévő teszt a §4 táblában NEM szereplő fájlokban.

## 5. Kötött szerződések (ADR 0071 — nem újratárgyalhatók)

Minden adapter **tiszta függvény**: nincs `DateTime.now()`, `Random`,
`Stopwatch`, IO, globális állapot; azonos bemenetre azonos kimenet. Egyik sem
dob kivételt — minden hibaút `Failure`.

### 5.1 `legacy_chord_label.dart`

```dart
/// Reduces a legacy chord label to the detector's canonical major/minor
/// vocabulary. Returns null for absent, blank or unparseable labels.
String? legacyPracticeChordLabel(String? label);
```

Algoritmus, ebben a sorrendben:

1. `label == null` → `null`; `label.trim()` üres → `null`.
2. A `'/'` első előfordulásától a maradék elhagyva (slash-akkord basszusa),
   majd újra `trim`.
3. Gyök: az első karakter `A`–`G` (NAGYBETŰ); ha nem, → `null`. Ha a második
   karakter `#` vagy `b`, az is a gyökhöz tartozik.
4. Utótag = a maradék. Minőség: **moll**, ha az utótag `m`-mel kezdődik ÉS nem
   `maj`-jal; egyébként **dúr**.
5. A gyök hangosztálya a kipinnelt táblából, majd keresztes írásmódra hozva:
   `C=0, B#=0, C#=1, Db=1, D=2, D#=3, Eb=3, E=4, Fb=4, F=5, E#=5, F#=6, Gb=6,
   G=7, G#=8, Ab=8, A=9, A#=10, Bb=10, B=11, Cb=11`, kimenet-nevek:
   `C, C#, D, D#, E, F, F#, G, G#, A, A#, B`.
6. Eredmény = keresztes gyöknév + (`m`, ha moll).

**Utófeltétel:** minden nem-`null` kimenetre `isCanonicalPracticeChordLabel`
igaz. A fájl semmit nem importál a `flutter` / `riverpod` világából.

### 5.2 `PracticeDefinition.displayTitle`

- Új opcionális mező: `final String? displayTitle;`, konstruktor-paraméter
  `this.displayTitle` (alapérték `null`), **a `sourceReference` és
  `difficulty` mellé**, hogy a meglévő hívások (Kör 4 katalógus) változatlanul
  forduljanak.
- Bekerül az `==`-be és a `hashCode`-ba is.
- Doc-comment: „Already-localized display text for adapted user content. The UI
  resolves `displayTitle ?? l10n(titleKey)`."
- `validate()`: ha `displayTitle != null && displayTitle!.trim().isEmpty` →
  új failure, kód **`definition.displayTitle.blank`**, üzenet:
  `'Display title cannot be blank when present.'`
- `practice_validation.dart`: `static const String definitionDisplayTitleBlank =
  'definition.displayTitle.blank';` **és fel kell venni a `values` halmazba is**
  (a fájl végén lévő stabil listába), különben a kipinnelt teszt nem is látja.
- A `practice_validation_test.dart` kipinnelt halmaza 60 → 61 elemre bővül.

### 5.3 Lesson adapter

```dart
AppResult<PracticeDefinition> practiceDefinitionFromLesson(
  Lesson lesson, {
  bool easy = false,
});
```

| mező | érték |
|---|---|
| forrás-lecke | `easy ? lesson.simplified : lesson` |
| `id` | `easy` ? `lesson.<lesson.id>.easy.v1` : `lesson.<lesson.id>.v1` |
| `schemaVersion` | `1` |
| `titleKey` / `descriptionKey` | `practiceSourceLessonTitle` / `practiceSourceLessonDescription` |
| `displayTitle` | `lesson.name.trim()`, üres esetén `null` |
| `mode` / `scoringProfile` | `PracticeMode.strumPattern` / `ScoringProfile.legacyLearnParity` |
| `source` / `sourceReference` | `PracticeSource.lesson` / `lesson:<lesson.id>` (az Easy-variánsnál IS ugyanez) |
| `meter` | `Meter(beatsPerBar: lesson.beatsPerBar)` (beatUnit marad 4) |
| `defaultTempo` | `Tempo(lesson.bpm)` |
| `totalBeats` | `BeatPosition.fromLegacyBeats(lesson.totalBeats)` |
| `difficulty` | `beginner→beginner`, `intermediate→intermediate`, `advanced→advanced` |
| `skillTags` | `const ['lessonImport']`, Easy esetén `const ['lessonImport', 'easyVariation']` |
| `events` | a forrás-lecke eseményei sorrendben: `id: '<definitionId>.e<i>'` (i 0-tól), `position: BeatPosition.fromLegacyBeats(e.beat)`, `direction: e.direction`, `chord: legacyPracticeChordLabel(e.chord)` |

**Előzetes őr (a `fromLegacyBeats` dobása ELŐTT), bármelyik sérül → `Failure`:**
`lesson.bpm` nem véges; `lesson.totalBeats` nem véges vagy `<= 0`; bármely
esemény `beat`-je nem véges vagy negatív; `lesson.events` üres.

### 5.4 Song adapter

```dart
AppResult<PracticeDefinition> practiceDefinitionFromSong(Song song);
```

- **TILOS a `song.toLesson()` hívása** (§2.3/4) — a fájl a `toLesson` szöveget
  sem tartalmazhatja (§6.10 forrás-scan teszt méri).
- Az expanzió a `Lesson._expand`-del **eseményszinten azonos**: minden
  `bar` ∈ [0, `chords.length`), minden `slot` ∈ [0, `pattern.length`), a `null`
  slot kimarad, `beat = bar * beatsPerBar + slot * 0.5`, `chord = chords[bar]`.

| mező | érték |
|---|---|
| `id` | `song.<song.id>.v1` |
| `titleKey` / `descriptionKey` | `practiceSourceSongTitle` / `practiceSourceSongDescription` |
| `displayTitle` | `song.name.trim()`, üres esetén `null` |
| `source` / `sourceReference` | `PracticeSource.song` / `song:<song.id>` |
| `meter` | `Meter(beatsPerBar: song.beatsPerBar)` |
| `defaultTempo` | `Tempo(song.bpm.toDouble())` |
| `totalBeats` | `BeatPosition.quarters(song.chords.length * song.beatsPerBar)` |
| `difficulty` | `PracticeDifficulty.beginner` |
| `skillTags` | `const ['songImport']` |
| mód/profil, `schemaVersion`, esemény-ID, akkord | mint §5.3 |

**Kontrollált hiba (`Failure`), előzetes őrként:** `song.chords.isEmpty`;
`song.pattern.length != song.beatsPerBar * 2`; a mintában nincs egyetlen
nem-`null` slot sem (üres eseménylista); `song.beatsPerBar` a `Meter`
tartományán kívül; a `Tempo` tartományán kívüli `bpm` (ezt a záró `validate()`
is elfogja, de a `Failure`-nek akkor is `practice.content_unsupported`-nak kell
lennie).

### 5.5 Analyze adapter

```dart
AppResult<PracticeDefinition> practiceDefinitionFromAnalyze(
  AnalyzeResult result, {
  required String sourceId,
  required String title,
});
```

1. `sourceId.trim()` üres → `Failure`.
2. `bpm = (result.bpm.isFinite && result.bpm >= 30 && result.bpm <= 300)
   ? result.bpm : 90.0` (a legacy `> 0`-s fallbackjének a `Tempo`-tartományra
   szűkített változata; szándékos, dokumentált eltérés).
3. `secPerBeat = 60.0 / bpm`.
4. A nem-véges `timeSec`-ű pengetések eldobva; a maradék **`timeSec` szerint
   növekvően rendezve** (a legacy is rendez).
5. Ha nem maradt pengetés → **üres-ág**: `mode: PracticeMode.freePractice`,
   `scoringProfile: ScoringProfile.freePracticeOpen`, `events: const []`,
   `totalBeats = BeatPosition.quarters(result.beatsPerBar)` (egy ütem).
   Minden más mező mint a nem-üres ágon. Ez **`Success`**, nem hiba.
6. Nem-üres ág: `t0` = az első (rendezett) pengetés `timeSec`-je;
   `beat_i = (timeSec_i - t0) / secPerBeat`, negatív eredmény 0-ra vágva.
7. `lastBeat` = az utolsó `beat_i`; `bars = max(1, (lastBeat / beatsPerBar).floor() + 1)`;
   `totalBeatsTicks = bars * beatsPerBar * 480`.
8. Tick-hozzárendelés sorrendben: `tick_i = BeatPosition.fromLegacyBeats(beat_i).ticks`;
   ha `tick_i <= előző kiadott tick`, akkor `tick_i = előző + 1`
   (**előre-tolás**); ha az így kapott `tick_i >= totalBeatsTicks`, az esemény
   **eldobva** (és a következőkre az előző kiadott tick marad a referencia).
   Ha ezután a `totalBeatsTicks` mégis `<=` a legutolsó kiadott ticknél, a
   `totalBeats`-et egy további ütemmel meg kell növelni — a `validate()` sosem
   bukhat emiatt.
9. Akkord: a `result.chords`-ból az első olyan `TimelineChord`, amire
   `timeSec >= startSec && timeSec < endSec`, annak `label`-je, különben `''`;
   majd `legacyPracticeChordLabel(...)`.
10. `mode: strumPattern`, `scoringProfile: legacyLearnParity`,
    `source: PracticeSource.analyze`, `sourceReference: 'analyze:<sourceId>'`,
    `id: 'analyze.<sourceId>.v1'` (a **trim-elt** `sourceId`-vel),
    `titleKey/descriptionKey`: `practiceSourceAnalyzeTitle` /
    `practiceSourceAnalyzeDescription`, `displayTitle`: `title.trim()` (üres → `null`),
    `difficulty: PracticeDifficulty.intermediate`,
    `skillTags: const ['analyzeImport']`,
    `meter: Meter(beatsPerBar: result.beatsPerBar)` (tartományon kívül →
    `Failure`).

### 5.6 Daily Challenge adapter

```dart
AppResult<PracticeDefinition> practiceDefinitionFromDailyChallenge(
  DailyChallenge challenge, {
  double bpm = 80,
});
```

- A minta első **legfeljebb 8** eleme (legacy `i < 8`) nyolcad-slotokra:
  a `challenge.pattern[i]` iránya a `beat = i * 0.5` pozíción.
- `challenge.pattern` üres → `Failure`. `bpm` a `Tempo`-tartományon kívül vagy
  nem véges → `Failure`.

| mező | érték |
|---|---|
| `id` / `sourceReference` | `dailyChallenge.<challenge.day>.v1` / `dailyChallenge:<challenge.day>` |
| `titleKey` / `descriptionKey` | `practiceSourceDailyChallengeTitle` / `practiceSourceDailyChallengeDescription` |
| `displayTitle` | `challenge.name.trim()`, üres esetén `null` |
| `meter` / `totalBeats` | `Meter(beatsPerBar: 4)` / `BeatPosition.quarters(4)` |
| `defaultTempo` | `Tempo(bpm)` |
| `difficulty` / `skillTags` | `beginner` / `const ['dailyChallenge']` |
| esemény `chord` | mindig `null` (a legacy `chords: ['']`-t ad) |
| mód/profil, `schemaVersion`, esemény-ID | mint §5.3 |

### 5.7 `lib/features/songs/public.dart`

A többi feature-barrel mintájára (`lib/features/learn/public.dart`,
`lib/features/analyze/public.dart`, `lib/features/streak/public.dart`):
library-doc + `export 'model/song.dart';`. Több NEM kell — a barrel csak
akkora legyen, amennyit ez a kör tényleg használ.

### 5.8 `FailureCode.practiceContentUnsupported`

`lib/core/foundation/app_failure.dart`, új szekcióban:

```dart
  // --- practice -----------------------------------------------------------
  static const String practiceContentUnsupported =
      'practice.content_unsupported';
```

Minden adapter-hibaút ezt adja:
`AppResult.failure(ValidationFailure(code: FailureCode.practiceContentUnsupported, cause: <diagnosztikai ok>))`.
A `cause` lehet a domain validációs kódok listája vagy egy rövid gépi ok-string
— **soha nem felhasználói szöveg**, és sosem renderelt.

### 5.9 `practice_adapter_keys.dart`

A négy forrásfajta ARB-kulcs-párja és az ID/`sourceReference`-előtagok egyetlen
helyen, `const` String konstansként (a négy adapter innen olvassa; a tesztek is
ezekre hivatkozhatnak). Nyers string-literál duplikálása a négy adapterben
tilos.

### 5.10 Záró szabály minden adapterben

A felépített definíción lefut a `validate()`, és **ha nem üres, az adapter
`Failure`-t ad** (a `cause`-ban a kódokkal). Érvénytelen `PracticeDefinition`
nem hagyhatja el az adaptert — ez a belt-and-braces védelem a §5.3–§5.6
előzetes őrei mellett.

## 6. Acceptance criteria (mind gépi)

1. **Lesson-parity, tételesen:** a `[...Lessons.all, Lessons.firstWin]` mind a
   **17** eleme `Success`-t ad, és minden `i`-re:
   `definition.events[i].position.toLegacyBeats() == lesson.events[i].beat`
   (EGZAKT egyenlőség, nem tolerancia), `direction` azonos,
   `chord == legacyPracticeChordLabel(lesson.events[i].chord)`,
   `events.length == lesson.events.length`; továbbá
   `meter.beatsPerBar == lesson.beatsPerBar`, `defaultTempo.bpm == lesson.bpm`,
   `totalBeats.toLegacyBeats() == lesson.totalBeats`, és `validate()` üres.
2. **Easy-parity:** ugyanez a 17 leckére `easy: true`-val, a
   `lesson.simplified.events` ellen mérve; az ID `.easy.v1`-re végződik, a
   `skillTags` tartalmazza az `easyVariation`-t, a `totalBeats` és a
   `sourceReference` azonos a teljes variánséval.
3. **Akkord-konzisztencia (E02-R03 review NOTE-3 zárása):** a 17 lecke
   konverziójában előálló MINDEN esemény `chord` mezőjére
   `isCanonicalPracticeChordLabel(chord)` igaz, és a `twoFingerFrame`
   akkordszekvenciája tételesen `Em`/`C`, a `bluesShuffle`-é `A`/`D`.
4. **Normalizáló-tábla kipinnelve:** az ADR 0071 §2 táblájának minden sora
   (`Em7→Em`, `Cmaj7→C`, `C7→C`, `Am7→Am`, `Emin→Em`, `Asus4→A`, `Cadd9→C`,
   `A7sus4→A`, `Bb→A#`, `Db→C#`, `Cb→B`, `E#→F`, `G/B→G`, `F#m→F#m`,
   `''→null`, `'   '→null`, `null→null`, `H→null`, `x→null`) külön
   assertionként.
5. **Song-parity, `toLesson()` NÉLKÜL:** legalább öt Song-esetre (4/4 nyolcad
   minta 1 és 8 ütemmel, 3/4 hat-slotos minta, csupa-rest-tel kevert minta,
   üres nevű song) az adapter eseménylistája egyezik a
   `song.toLesson().events` azonos leképezésével (pozíció/irány/akkord), és a
   `totalBeats` a `toLesson().totalBeats`-szel.
6. **Song kontrollált hibák:** minta-hossz eltérés (`pattern.length !=
   beatsPerBar * 2`), üres `chords`, csupa-`null` minta, `bpm: 400`, `bpm: 10`
   → mind `Failure`, `error.code == FailureCode.practiceContentUnsupported`,
   és **egyik sem dob kivételt**.
7. **Analyze nem-üres:** szintetikus eredményre (ismert bpm, 3 pengetés, 2
   akkord-sáv) az esemény-számok, tickek, irányok és akkordok tételesen
   kipinnelve; az első esemény tickje 0 (t0-normalizálás); `bpm: 0`, `bpm: 400`
   és `bpm: double.nan` mind 90-re esik vissza; 3/4-es eredmény
   `meter.beatsPerBar == 3`; rendezetlen bemenet rendezett kimenetet ad.
8. **Analyze tick-ütközés:** két pengetés 0,0005 s távolságra ugyanazon a
   tickre kerekedne → a kimenet két esemény, `tick[1] == tick[0] + 1`, és a
   `validate()` üres.
9. **Analyze üres:** `strums: []` → `Success`, `mode == PracticeMode.freePractice`,
   `scoringProfile == ScoringProfile.freePracticeOpen`, `events.isEmpty`,
   `validate()` üres.
10. **A Song-adapter nem használ `toLesson()`-t:** teszt olvassa be a
    `lib/features/practice/data/adapters/song_practice_adapter.dart` forrását,
    és bukjon, ha tartalmazza a `toLesson` szöveget.
11. **Daily Challenge determinizmus:** `DailyChallenge.forDay(20000)` kétszeri
    konverziója `==` definíciót ad; az ID `dailyChallenge.20000.v1`; a
    20000. és 20001. nap definíciója különbözik; a 8-nál hosszabb minta 8
    eseményre csonkolódik; minden esemény `chord`-ja `null`, pozíciója
    `i * 240` tick; üres minta → `Failure`.
12. **`displayTitle`:** mind a négy adapter a §5.3–§5.6 szerinti értéket adja
    (üres/whitespace név → `null`); a `PracticeDefinition.validate()` a
    csak-whitespace `displayTitle`-re a `definition.displayTitle.blank` kódot
    adja, `null`-ra és rendes szövegre semmit; a kód benne van a
    `PracticeValidationCode.values`-ban, és a kipinnelt halmaz 61 elemű.
13. **A Kör 4 katalógusa érintetlen:** a
    `builtin_practice_catalog_test.dart` és a `scoring_profile_test.dart`
    változtatás nélkül zöld; a `legacyLearnParity` és a `freePracticeOpen`
    egyetlen mezője sem módosult.
14. **Architektúra:** `dart run tool/check_architecture.dart` tiszta, az
    allowlist **nem bővült** (a songs-import a `public.dart`-on át megy).
15. **Minden gate zöld** (§7), **piros teszt nélkül**.

## 7. Kötelező ellenőrzések

Köztes gyors ellenőrzést szűkíthetsz (egy tesztfájl, egy alfa), de a **ZÁRÓ
gate-sort pontosan úgy kell lefuttatni, ahogy itt áll** — külön hívásokként,
`&&` láncolás tilos, `analyze` és `test` soha nem egy hívásban (OOM-védelem,
AGENTS.md §12). A záró gate-parancsokat **csővezeték és `tail` nélkül, teljes
kimenettel** futtasd, és a tényleges kimenetet másold a §10.4-be.

```bash
~/flutter/bin/dart format --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/features/practice/
~/flutter/bin/flutter test test/core/foundation/
~/flutter/bin/flutter test test/core/architecture_dependency_test.dart
~/flutter/bin/dart run tool/check_architecture.dart
```

- A **teljes** suite + property gate + APK a CI-ben fut (ADR 0053) — a
  dispatch, a PR és a merge **Claude-oldal**. Az implementer `gh`-t NEM hív és
  NEM commitol.
- Ha egy MEGLÉVŐ teszt bukik: **MEGÁLLÁS és jelentés** — a mai viselkedést védő
  tesztet a zöldért átírni tilos.

## 8. Implementációs sorrend (ez a terved)

1. `legacy_chord_label.dart` + tesztje (§6.4) — RED → GREEN.
2. `practice_definition.dart` + `practice_validation.dart` (`displayTitle`) +
   a két meglévő domain-teszt bővítése (§6.12) — RED → GREEN.
3. `app_failure.dart` (`practiceContentUnsupported`) +
   `practice_adapter_keys.dart` + `songs/public.dart`.
4. `lesson_practice_adapter.dart` + parity-tesztek (§6.1–§6.3).
5. `song_practice_adapter.dart` + tesztek (§6.5, §6.6, §6.10).
6. `analyze_practice_adapter.dart` + tesztek (§6.7–§6.9).
7. `daily_challenge_practice_adapter.dart` + tesztek (§6.11).
8. Teljes gate-sor (§7), majd a §10 kitöltése és a `done` jelzés.

## 9. Kockázatok

- **`BeatPosition.fromLegacyBeats` DOB** negatív/nem-véges bemenetre — minden
  adapternek előzetes őre van (§5.3–§5.6). „Az adapter sosem dob" állítást
  tesztben kell bizonyítani, nem doc-commentben állítani.
- **`totalBeats` kizárólagos felső korlát:** 4 ütem 4/4-ben `quarters(16)`, és
  az utolsó esemény a 15. negyeden (tick 7200) van. Az Analyze-ág §5.5/8
  korrekciója pont ezért kell.
- **`Lesson.simplified` `this`-t adhat vissza** (ha nincs on-beat down-stroke,
  vagy ha minden eseményt megtartana) — az Easy-variáns ilyenkor is külön ID-t
  kap (ADR 0071 §5), és a teszt a `lesson.simplified.events` ellen mér, nem
  feltételezi, hogy rövidebb.
- **A `Song` memóriában konstruálva NEM garantáltan `_fitToMeter`-elt** — a
  minta-hossz ellenőrzése az adapter dolga; `toLesson()` hívása `assert`-tel
  bukna (§2.3/4).
- **Cross-feature import:** `practice → songs` KIZÁRÓLAG a `songs/public.dart`-on
  át; a `learn`, `analyze`, `streak` importok a meglévő `public.dart`
  barrelekből jönnek. Az architektúra-allowlist bővítése tilos.
- **A domain purity-őr** a módosított `practice_definition.dart`-ra is érvényes
  — semmilyen flutter/riverpod import, `DateTime.now(`, `print(` nem kerülhet bele.
- **Riverpod 3:** `AsyncValue.value` (nullable), NEM `.valueOrNull` — ebben a
  körben nincs provider, de ne csússzon be.
- **`AppResult.valueOrNull` viszont LÉTEZIK** (`app_result.dart:34`) — a két
  API neve hasonlít, ne keverd; a tesztekben inkább mintaillesztéssel
  (`switch`/`is Success`) olvasd ki az értéket.

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Módosítások fájlonként

### 10.2 TDD RED → GREEN evidencia

### 10.3 A parity-tesztek (§6.1/§6.2/§6.5) tényleges mérési módja

### 10.4 Végső ellenőrzések tényleges kimenete (szó szerint, csonkolatlanul)

### 10.5 Eltérések, nem futtatott ellenőrzések, follow-up

## 11. Review

(A review-jelentés linkje ide kerül: `docs/reviews/e02-r05-review.md`.)
