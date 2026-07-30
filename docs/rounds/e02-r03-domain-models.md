# E02-R03 — Practice domain modellek és validáció

Státusz: PLANNING (kód olvasva: `main` @ `a6efc73`, 2026-07-30)
SDD: `docs/sdd/03-epic-02-practice-engine.md` § „Kör 3 — Practice domain modellek és validáció" + §8.1–8.3, §10.1–10.9, §15.2, §16.1–16.8
Branch: `codex/epic-02-round-03-domain-models`
Brief szerzője: Claude · Implementáció: Codex
**Előfeltétel: E02-R02 merge-ölve (PR #23, `main` @ `a3c72d3`).** Teljesült.

## 1. Cél

A Practice V2 **teljes domain-szerződése**: a gyakorlat (definition + event), a
session-config, az observation-hierarchia, a verdict, a metrika, az attempt- és
session-eredmény, valamint a scoring profile kanonikus, immutable, pure-Dart
modelljei — mindegyik **aggregáló validációval** és stabil, perzisztálható
kódokkal. Ez a kör az Epic 2 többi 17 körének a típus-alapja: a katalógus (Kör 4)
`const` adatként írja le magát ezekkel, az adapterek (Kör 5) ezekre képezik a
Lesson/Song/Analyze forrásokat, a target compiler (Kör 6), a state machine
(Kör 7), a matcher/scorer (Kör 9–10) és a perzisztencia (Kör 18) mind ezeket
fogyasztja. Ezért itt kell eldőlnie — [ADR 0068](../adr/0068-practice-domain-model-contracts.md) —,
hogy hol utasítjuk el az érvénytelen adatot, milyen numerikus típus hordozza a
súlyokat/küszöböket, mi a „normalizált akkord-label", és hogyan hasonlítanak
össze a listát tartalmazó aggregátumok.

A kör kimenete **kizárólag könyvtárkód + teszt**: nincs UI, nincs provider,
nincs futásidejű belépési pont, nincs hívó — a felhasználói viselkedés
változatlan (a `practiceEngineV2Enabled` flag wiringje az R05+ köröké).

## 2. Jelenlegi állapot

Mért tények, `main` @ `a6efc73` (2026-07-30) olvasása alapján.

### 2.1 Ami már kész (E02-R02, NEM e kör dolga újraírni)

`lib/features/practice/domain/model/` — 4 fájl, 253 sor:

- `beat_position.dart` (100 sor) — 480 PPQ integer tick, `Comparable`,
  subdivision-factoryk, összeadás/kivonás, az egyetlen auditált legacy
  `double beat` híd (≤ 1/960 beat).
- `tempo.dart` (46 sor) — `double bpm`, 30.0–300.0 zárt tartomány, lista-alapú
  `validate()`, clamp nélkül.
- `meter.dart` (64 sor) — `beatsPerBar`/`beatUnit`, `ticksPerBar`, lista-alapú
  `validate()`.
- `practice_validation.dart` (43 sor) — `PracticeValidationFailure` value-típus
  (stabil `code` + `message`, `==`/`hashCode`/`toString`) és a `PracticeValidationCode`
  öt eddigi konstansa (`tempo.bpm.notFinite`, `tempo.bpm.outOfRange`,
  `meter.beatsPerBar.outOfRange`, `meter.beatUnit.unsupported`,
  `beatPosition.negative`).

Tesztek: `test/features/practice/domain/{beat_position,tempo,meter,practice_validation}_test.dart`
(24 determinisztikus unit teszt). **Ezeket a kör nem gyengítheti**; a `meter_test.dart`
és a `practice_validation_test.dart` BŐVÜL (§3.1/g, §3.1/a).

### 2.2 Gépi őr, ami már véd

`tool/check_architecture.dart:229-231` — a `_isSharedDomain` már tartalmazza a
`lib/features/practice/domain/` prefixet, tehát **minden e körben létrehozott
domain-fájl automatikusan framework-független** kell legyen (tiltott:
`package:flutter/`, `flutter_localizations`, `flutter_riverpod`, `riverpod`,
`dio`, `shared_preferences`, `flutter_gen/gen_l10n`, `lib/l10n*` —
`:233-246`). A szabály tesztje: `test/core/architecture_dependency_test.dart`
(„keeps the practice domain framework-free"). **A checkert e kör NEM módosítja.**

Amit a checker NEM néz (ezért §3.1/h test-oldali őr): `DateTime.now()`,
`Stopwatch()`, `Random()`, `print()` a domainben (SDD §8.3).

### 2.3 Amit a domain importálhat

- `package:meta` **direkt dependency** (`pubspec.yaml:21`, kommentje szerint
  kifejezetten „@immutable for the Flutter-free core domain") — az `@immutable`
  használható, ahogy a `lib/core/music/` is teszi (`strum.dart:1`).
- `lib/core/music/strum.dart:5` — `enum StrumDirection { down, up }`. A
  `PracticeEvent.direction` és a `StrumObservation.direction` ezt használja
  (SDD §10.3/§10.6), NEM új enumot. A `core` nem feature, tehát a checker
  cross-feature szabálya nem érinti; ez feature → core import, megengedett.
- **`package:collection` NINCS a pubspecben** és nem is kerül bele (ADR 0068 §4)
  — a lista-egyenlőséghez saját, négysoros helper készül.

### 2.4 A canonical chord label mért alapja

- `lib/features/live/engine/dsp/chord_matcher.dart:24-35` — a DSP-oldali
  root-készlet: `C, C#, D, D#, E, F, F#, G, G#, A, A#, B` (**csak sharp**).
- `lib/features/analyze/engine/ml_chord_decoder.dart:41-66` — a CRNN
  `majmin25Labels`: `N.C.` + 12 major + 12 minor, ugyanezzel a sharp-írásmóddal
  (`Cm`, `C#m`, …).
- `lib/features/learn/model/lesson.dart:22-23` — a legacy `String chord` mező,
  `''` = strum-only/muted.

Ebből következik az ADR 0068 §3 kanonikus 24-es készlete és az, hogy a
`''`/`N.C.`/flat-írásmód konverziója az adapterek (Kör 5) és a gateway (Kör 8)
dolga, nem a domainé.

### 2.5 Nyitott review-lelet, amit ez a kör zár

**E02-R02 review MINOR-1** (`docs/reviews/e02-r02-review.md:40-51`):
`meter.dart:41-53` — a `ticksPerBar` getter a nem támogatott `beatUnit`-ra
`StateError`-t dob, de az out-of-range `beatsPerBar`-ra csendben számol
(`Meter(beatsPerBar: 0).ticksPerBar == 0`, negatívnál negatív bar-hossz). A
review az R03-ra (legkésőbb R06-ra) bízta a zárást: „vagy mindkét mező fail-fast
a getterben, vagy egyik sem". **E kör döntése: MINDKETTŐ fail-fast** (§5/8).

### 2.6 Nincs más érintett kód

- `lib/features/practice/` alatt csak a `domain/model/` létezik; nincs
  `application/`, `data/`, `presentation/`, `public.dart`, `repository/`,
  `service/`.
- Névütközés-ellenőrzés (grep a `lib/` fán): nem létezik `PracticeEvent`,
  `PracticeDefinition`, `PracticeMode`, `PracticeSource`, `PracticeMetrics`,
  `MetricValue`, `ScoringProfile`, `TimingGrade`, `PracticeVerdict`,
  `PracticeObservation` nevű típus. A `lib/features/learn/lesson_scorer.dart`
  legacy scorere és a `lib/features/progress/**` `practice_*` fájljai MÁS
  feature-ök — a kör nem ér hozzájuk.

### 2.7 ADR-számozás

A legmagasabb foglalt szám **0068** — ezt a kört
[ADR 0068](../adr/0068-practice-domain-model-contracts.md) fedi, amit **Claude
már megírt**. A Codex `docs/adr/` fájlt NEM hoz létre és NEM módosít. A 0069
szabad marad.

## 3. Scope

**Benne (Codex) — mindegyik pure Dart a `lib/features/practice/domain/model/` alatt:**

- **§3.1/a Validációs kódkészlet bővítése.** `practice_validation.dart`: az új,
  §5/9-ben tételesen kötött kódkonstansok + (ha kell) a listaösszefűzést segítő
  pure helper. A meglévő öt kód és a `PracticeValidationFailure` API változatlan.
- **§3.1/b Enumok stabil kódokkal.** `PracticeMode` (5 érték + `scoredDimensions`),
  `PracticeSource` (8 érték, `futureAi` reserved), `PracticeDifficulty`
  (3 érték) — mind `code` + strict `…FromCode` (ADR 0068 §5).
- **§3.1/c Event és definition.** `PracticeEvent` (+ marker-fogalom, canonical
  chord-predikátum, per-event `validate()`), `PracticeDefinition` (kötelező
  mezők SDD §10.4 szerint + aggregáló `validate()`, ami az eventlista-szintű
  szabályokat is futtatja: duplikált ID, rendezetlenség, `totalBeats`-en
  túlnyúlás, azonos tickre eső event, mode-scoring kompatibilitás).
- **§3.1/d Session config.** `PracticeSessionConfig` a SDD §10.5 mezőivel
  (a `speedBuilderPolicy` KIVÉTELÉVEL — §5/12) + `validate()`.
- **§3.1/e Observation, verdict, metrika.** `PracticeObservation` sealed +
  `StrumObservation`/`ChordObservation`; `PracticeVerdict` + `TimingGrade` +
  direction/chord outcome enumok + a coaching-kód készlet; `MetricValue` sealed
  hierarchia + `PracticeMetrics`.
- **§3.1/f Attempt és session eredmény.** `PracticeAttemptResult`
  (+ `PracticeAttemptOutcome`), `PracticeSessionResult`
  (+ `PracticeFinishReason`, determinisztikus `bestAttempt`/`finalAttempt`
  getterek).
- **§3.1/g Scoring profile.** `ScoringProfile` (+ `PracticeScoreDimension`,
  `ExtraStrumPolicy`) integer-percent súlyokkal/küszöbökkel és `Duration`
  ablakokkal, benne az EGYETLEN előre definiált profil: a legacy Learn parity
  profil (280/50/120 ms, `ignore`) — SDD §15.2.
- **§3.1/h A MINOR-1 zárása + purity-őr.** `meter.dart` `ticksPerBar` szimmetrikus
  fail-fast (+ teszt); új test-oldali őr, ami a domain-forrást szkenneli
  `DateTime.now()` / `Stopwatch(` / `Random(` / `print(` mintákra (SDD §8.3).
- **§3.1/i Lista-egyenlőség helper.** `practice_value_equality.dart` — négysoros
  `listEquals`/`listHash` pure helper (ADR 0068 §4), új package nélkül.

**Kívül (ebben a körben TILOS):**

- **Bármilyen production viselkedésváltozás.** A `lib/` diff KIZÁRÓLAG az új
  domain-fájlok + a `meter.dart` MINOR-1 javítása. `lib/features/learn/**`,
  `lib/features/progress/**`, `lib/features/live/**`, `lib/features/analyze/**`,
  `lib/core/**`, `lib/app/**` — egyetlen sor sem.
- **JSON / szerializáció.** Se `toJson`/`fromJson`, se `dart:convert` import, se
  séma-fájl. A stabil `code`/`fromCode` MEGVAN (ez a stable-ID követelmény), de a
  perzisztencia-formátum a Kör 18 dolga.
- **Bármilyen algoritmus.** Nincs matching, nincs score-számítás, nincs
  interpoláció, nincs target-compiler, nincs state machine / reducer, nincs
  coach-logika. A modellek adatot és validációt hordoznak; a `bestAttempt`
  getter az egyetlen megengedett származtatott logika (és az is tiszta
  összehasonlítás).
- **Katalógus-tartalom (Kör 4).** Nincs beépített gyakorlat, nincs ARB-kulcs
  felvétel, nincs `builtin_practice_catalog.dart`, nincs repository-interfész.
- **Adapterek (Kör 5).** Nincs Lesson/Song/Analyze konverzió, nincs
  flat→sharp akkord-normalizálás, nincs `N.C.`→null képzés.
- **`SpeedBuilderPolicy`** (Kör 17) és **`practice_session_state.dart`** (Kör 7)
  — egyik sem készül el, a config nem kap `speedBuilderPolicy` mezőt (§5/12).
- **`lib/features/practice/public.dart`** — amíg nincs cross-feature fogyasztó,
  nincs publikus API-döntés (az R02 briefben lefektetett szabály).
- **`tool/check_architecture.dart` és `test/core/architecture_dependency_test.dart`**
  — a gate-őr E02-R02-ben elkészült és a prefix könyvtár-szintű, tehát az új
  fájlokra magától érvényes. Ezt a kör NEM módosítja (a gate-közeli fájlok
  módosítása szükségtelen kockázat).
- Meglévő teszt átírása/gyengítése/törlése. Piros meglévő teszt = **MEGÁLLÁS és
  jelentés.** (A `meter_test.dart` és `practice_validation_test.dart` BŐVÜLHET,
  meglévő assertion nem változhat.)
- DSP/ML paraméter, modell-bináris, `docs/rag/chunks/` (AGENTS.md §9).
- Új package, code generation, új `--dart-define`.
- `docs/adr/**` (a 0068 készen van, §2.7), `HANDOFF.md`, `README.md`,
  `.github/**`, `backend/**`, `ml/**`, `pubspec.yaml`, `docs/baseline/**`,
  `test/support/**`, `test/fixtures/**`, `test/property/**`.
- Randomizált property-teszt: NEM kell (nem DSP-viselkedés; a domain
  determinisztikus adatszerkezet, fix unit-tesztekkel teljesen fedhető).

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `lib/features/practice/domain/model/practice_validation.dart` | §3.1/a — az új kódkonstansok (meglévő API változatlan) |
| `lib/features/practice/domain/model/practice_value_equality.dart` | ÚJ — §3.1/i lista-egyenlőség helper |
| `lib/features/practice/domain/model/practice_mode.dart` | ÚJ — §3.1/b `PracticeMode` + `scoredDimensions` |
| `lib/features/practice/domain/model/practice_source.dart` | ÚJ — §3.1/b `PracticeSource` |
| `lib/features/practice/domain/model/practice_difficulty.dart` | ÚJ — §3.1/b `PracticeDifficulty` |
| `lib/features/practice/domain/model/practice_event.dart` | ÚJ — §3.1/c event + canonical chord predikátum |
| `lib/features/practice/domain/model/practice_definition.dart` | ÚJ — §3.1/c definition + eventlista-validáció |
| `lib/features/practice/domain/model/practice_session_config.dart` | ÚJ — §3.1/d |
| `lib/features/practice/domain/model/practice_observation.dart` | ÚJ — §3.1/e sealed observation |
| `lib/features/practice/domain/model/practice_verdict.dart` | ÚJ — §3.1/e verdict + `TimingGrade` + outcome enumok + coaching kódok |
| `lib/features/practice/domain/model/practice_metrics.dart` | ÚJ — §3.1/e `MetricValue` + `PracticeMetrics` |
| `lib/features/practice/domain/model/practice_attempt_result.dart` | ÚJ — §3.1/f |
| `lib/features/practice/domain/model/practice_session_result.dart` | ÚJ — §3.1/f + `PracticeFinishReason` |
| `lib/features/practice/domain/model/scoring_profile.dart` | ÚJ — §3.1/g |
| `lib/features/practice/domain/model/meter.dart` | §3.1/h — KIZÁRÓLAG a `ticksPerBar` szimmetrikus fail-fast (MINOR-1) |
| `test/features/practice/domain/practice_validation_test.dart` | bővítés — az új kódok |
| `test/features/practice/domain/meter_test.dart` | bővítés — a MINOR-1 mindkét ága |
| `test/features/practice/domain/practice_enums_test.dart` | ÚJ — `code`/`fromCode` roundtrip + kód-egyediség minden enumra |
| `test/features/practice/domain/practice_event_test.dart` | ÚJ |
| `test/features/practice/domain/practice_definition_test.dart` | ÚJ |
| `test/features/practice/domain/practice_session_config_test.dart` | ÚJ |
| `test/features/practice/domain/practice_observation_test.dart` | ÚJ |
| `test/features/practice/domain/practice_verdict_test.dart` | ÚJ |
| `test/features/practice/domain/practice_metrics_test.dart` | ÚJ |
| `test/features/practice/domain/practice_result_test.dart` | ÚJ — attempt + session eredmény |
| `test/features/practice/domain/scoring_profile_test.dart` | ÚJ |
| `test/features/practice/domain/domain_purity_test.dart` | ÚJ — §3.1/h forrás-szkennelő őr |
| `test/features/practice/domain/practice_value_equality_test.dart` | ÚJ — §3.1/i helper |
| `docs/rounds/e02-r03-domain-models.md` | **kizárólag a 10. szekció** |

**Tilos zóna:** minden más — kiemelten `lib/features/practice/domain/model/{beat_position,tempo}.dart`
(E02-R02 kész, változatlan), `lib/core/**`, `lib/app/**`, a többi
`lib/features/**`, `tool/**`, `test/core/**`, `test/app/**`, `test/support/**`,
`test/fixtures/**`, `test/property/**`, `docs/adr/**`, `docs/sdd/**`,
`docs/baseline/**`, `HANDOFF.md`, `.github/**`, `backend/**`, `ml/**`,
`pubspec.yaml`.

Fájlonként egy fő típus (+ a hozzá szorosan tartozó enumok/outcome-típusok) —
barrel és `public.dart` NINCS; a modellek relatív importtal látják egymást.

## 5. Kötött architekturális döntések

Ezeket a kör NEM tervezheti újra; a kötelező érvényű döntés
[ADR 0068](../adr/0068-practice-domain-model-contracts.md) (+ a már élő
[ADR 0066](../adr/0066-practice-tick-time-model.md)). Az alábbiak ezek e körre
vetített, kötött következményei.

1. **Immutabilitás és egyenlőség.** Minden modell `final class`, `@immutable`
   (`package:meta`), `const` konstruktorral ott, ahol lehetséges (a Kör 4
   `const` katalógusa ezt igényli). `==`/`hashCode` **strukturális**; listát
   tartalmazó mezőnél elem-szintű összehasonlítás a §3.1/i helperrel és
   `Object.hashAll`. `copyWith` **csak** ott, ahol a kör ténylegesen indokolja
   (`PracticeSessionConfig` — a setup UI és a Speed Builder tempóváltása; és
   `PracticeMetrics` NEM kap). Doc-comment rögzíti: a listát a hívó immutable
   listaként adja át (`const` lista vagy `List.unmodifiable`), a domain sosem
   mutálja.
2. **Validáció = érték (ADR 0068 §1).** Minden aggregátum
   `List<PracticeValidationFailure> validate()`-et ad, **aggregálva** (üres lista
   = valid), kivétel nélkül, és a beágyazott értékobjektumok
   (`Tempo`/`Meter`/nested `ScoringProfile`) hibáit **változatlan kóddal**
   továbbengedi a listába. A konstruktor NEM validál.
3. **Kivétel csak programozói hibára.** Származtatott getter, ami érvénytelen
   állapoton értelmes választ nem tud adni, `StateError`-t dob — és **minden
   mezőre szimmetrikusan**, amitől függ. A `BeatPosition` `ArgumentError`-ai
   (negatív tick, negatív legacy beat, negatívba futó kivonás) változatlanok.
4. **Nincs `double` zenei pozíció** (ADR 0066): minden pozíció/duration
   `BeatPosition`, minden idő `Duration`. Kényelmi `toBeats()` getter nem kerül
   új típusra sem.
5. **Súlyok és küszöbök integer percentek** (ADR 0068 §2):
   `Map<PracticeScoreDimension, int> weights` — összeg **pontosan 100**, VAGY
   üres map (mód overall score nélkül: `freePractice`); pass-küszöbök `int`
   percentek (`completionThresholdPercent = 85`, `overallThresholdPercent = 70`
   a defaultban); a match-ablakok `Duration`-ök, kötelező
   `perfect ≤ good ≤ match` sorrenddel. Score-értékek (`MetricAvailable.value`,
   `PracticeVerdict.eventScore`) `double` 0.0–1.0, **véges** és zárt
   intervallumon validálva.
6. **Canonical chord label** (ADR 0068 §3): a domain egyetlen predikátuma a
   `{C, C#, D, D#, E, F, F#, G, G#, A, A#, B} × {"", "m"}` 24-es készlet.
   `null` = nincs akkord-cél / nincs detektált akkord; `''`, `N.C.`, flat
   írásmód (`Bb`), és minden bővebb minőség (`7`, `sus4`, `maj7`) **invalid**.
   Normalizálás nincs ebben a körben.
7. **`PracticeEvent` marker-fogalom.** A mezők SDD §10.3 szerint (`id`,
   `position`, `duration?`, `chord?`, `direction?`, `accent`, `optional`), plusz
   egy `marker` bool (default `false`). Kötött szabályok: nem-marker eventnek
   legalább egy pontozható attribútuma legyen (`chord` VAGY `direction`);
   markernek egyik sem lehet; `duration` ha megadott, akkor **szigorúan
   pozitív** tick. `StrumDirection` a `lib/core/music/strum.dart`-ból (§2.3).
8. **`Meter.ticksPerBar` szimmetrikus fail-fast** (MINOR-1, §2.5): a getter
   `StateError`-t dob **mind** a nem támogatott `beatUnit`-ra, **mind** a
   `validate()` szerint out-of-range `beatsPerBar`-ra; a doc-comment kimondja,
   hogy a getter validált `Meter`-t vár. A `validate()` viselkedése, a hibakódok
   és a meglévő tesztek nem változnak.
9. **Kötött validációs kódkészlet.** A meglévő öt kód mellé pontosan az alábbiak
   kerülnek (`<típus>.<mező>.<probléma>` konvenció; a lista bővítése csak akkor
   megengedett, ha egy §6 kritérium másképp nem teljesíthető, és akkor is
   tesztben rögzített kóddal + a §10-ben jelezve):

   | Terület | Kódok |
   |---|---|
   | event | `event.id.empty`, `event.chord.invalid`, `event.duration.nonPositive`, `event.scorable.missing`, `event.marker.scorable` |
   | eventlista | `events.empty`, `events.unsorted`, `events.idDuplicate`, `events.positionDuplicate`, `event.position.outOfRange` |
   | definition | `definition.id.empty`, `definition.schemaVersion.invalid`, `definition.titleKey.empty`, `definition.descriptionKey.empty`, `definition.totalBeats.nonPositive`, `definition.scoringProfile.incompatibleWithMode` |
   | config | `config.definitionId.empty`, `config.snapshotVersion.invalid`, `config.countInBars.outOfRange`, `config.loopCount.outOfRange`, `config.inputLatency.outOfRange`, `config.visualLatency.outOfRange`, `config.sessionTimeout.nonPositive`, `config.scoringProfileId.empty` |
   | observation | `observation.at.negative`, `observation.sequence.negative`, `observation.confidence.notFinite`, `observation.confidence.outOfRange`, `observation.chord.invalid` |
   | verdict | `verdict.targetEventId.empty`, `verdict.eventScore.notFinite`, `verdict.eventScore.outOfRange`, `verdict.match.inconsistent`, `verdict.coachingCode.unknown` |
   | metrika | `metric.value.notFinite`, `metric.value.outOfRange`, `metric.insufficientData.reasonEmpty`, `metrics.totalTargets.negative`, `metrics.resolvedTargets.exceedsTotal`, `metrics.maxCombo.negative`, `metrics.scorePoints.negative`, `metrics.meanAbsoluteOffset.negative` |
   | attempt/session | `attempt.index.negative`, `attempt.verdicts.targetDuplicate`, `session.id.empty`, `session.attempts.empty`, `session.attempts.unordered`, `session.duration.negative`, `session.coachingSummary.unknownCode` |
   | scoring profile | `scoringProfile.id.empty`, `scoringProfile.window.nonPositive`, `scoringProfile.window.ordering`, `scoringProfile.weights.negative`, `scoringProfile.weights.sumNotHundred`, `scoringProfile.threshold.outOfRange` |

10. **Stabil enum-kódok** (ADR 0068 §5). Kötött kódértékek:
    - `PracticeMode`: `strumPattern`, `chordChanges`, `chordProgression`,
      `rhythmOnly`, `freePractice`.
    - `PracticeSource`: `builtin`, `lesson`, `song`, `analyze`, `setlist`,
      `dailyChallenge`, `userCreated`, `futureAi` (SDD §10.2 — a `futureAi`
      reserved, tartalmat nem generál).
    - `PracticeDifficulty`: `beginner`, `intermediate`, `advanced`.
    - `TimingGrade`: `perfect`, `good`, `early`, `late`, `missed`,
      `notApplicable` (SDD §16.2).
    - `PracticeScoreDimension`: `completion`, `rhythm`, `direction`, `chord`,
      `consistency`, `overall` (SDD §16.1).
    - `ExtraStrumPolicy`: `ignore`, `countInformationally`, `penalizeRhythm`
      (SDD §15.3).
    - `PracticeAttemptOutcome`: `passed`, `failed`, `incomplete`, `notScored`.
    - `PracticeFinishReason`: `completedAllTargets`, `userFinished`, `cancelled`,
      `timedOut`, `interrupted`, `failed`.
    Minden enum: `String get code` + top-level vagy statikus
    `…FromCode(String) -> T?`, ami ismeretlen kódra `null`-t ad (nem dob, nem
    default-ol).
11. **Mód → pontozott dimenziók** (SDD §16.6 alapján, kötött):
    `strumPattern → {rhythm, direction}`, `chordChanges → {chord, rhythm}`,
    `chordProgression → {rhythm, direction, chord}`, `rhythmOnly → {rhythm}`,
    `freePractice → {}` (nincs overall score). A definition validációja
    ellenőrzi, hogy a profil `weights` kulcsai **pontosan** a mód
    `scoredDimensions` készletét adják (`freePractice` ⇒ üres map), különben
    `definition.scoringProfile.incompatibleWithMode`.
12. **`PracticeSessionConfig` mezői** (SDD §10.5, a kör kötött listája):
    `definitionId`, `definitionSnapshotVersion`, `effectiveTempo` (`Tempo`),
    `countInBars` (0–4), `loopCount` (1–32), `metronomeEnabled`,
    `accentEnabled`, `backingEnabled`, `scoringProfileId`, `easyVariationId?`,
    `inputLatency` / `visualLatency` (`Duration`, 0–500 ms zárt),
    `expectedChordHintEnabled`, `sessionTimeout` (`Duration`, szigorúan
    pozitív), `reducedMotion`. **`speedBuilderPolicy` NEM kerül bele** — a
    Speed Builder a Kör 17 köre, a típusát ott kell megtervezni; a
    doc-comment ezt rögzíti (dokumentált eltérés az SDD §10.5 felsorolásától).
13. **Egy előre definiált `ScoringProfile`:** a legacy Learn parity profil
    (`id: 'legacyLearnParity'`, match ±280 ms, perfect ±50 ms, good ±120 ms,
    `ExtraStrumPolicy.ignore`, `completion ≥ 85`, `overall ≥ 70` — SDD §15.2,
    §16.7). Tempo-aware ablak-képlet, más profil, katalógus-profilkészlet: NEM
    e kör dolga.
14. **`PracticeVerdict` konzisztencia.** Ha `matchedObservationSequence == null`,
    akkor `observedAt` is `null` és a `timingGrade ∈ {missed, notApplicable}`;
    különben `verdict.match.inconsistent`. A coaching-kód készlet kötött (SDD
    §10.7): `practice.coach.early`, `practice.coach.late`,
    `practice.coach.wrong_direction`, `practice.coach.chord_not_stable`,
    `practice.coach.no_signal`; a `coachingCode` `null` vagy ebből a készletből
    való (`verdict.coachingCode.unknown`).
15. **`MetricValue` sealed hierarchia** (SDD §10.8): `MetricAvailable(double)`,
    `MetricNotApplicable()`, `MetricInsufficientData(String reasonCode)`. A
    `PracticeMetrics` dimenziómezői (`completion`, `rhythm`, `direction`,
    `chord`, `overall`) `MetricValue`-k — **soha nem `double?`**.
16. **`PracticeSessionResult` származtatott getterei determinisztikusak:**
    `finalAttempt` = a legnagyobb `index`-ű attempt; `bestAttempt` = a
    legnagyobb `MetricAvailable` overall score-ú attempt, **holtverseny esetén a
    kisebb `index`** (a `notApplicable`/`insufficientData` overall nem
    összehasonlítható, tehát nem lehet best, ha van érvényes overall-ú attempt).
    Üres attempt-listán mindkettő `null` (nem dob) — a `validate()` jelzi a
    `session.attempts.empty`-t.
17. **Pure domain, gépi őrökkel** (ADR 0068 §6): tilos import a §2.2 készletből
    (checker őrzi), és tilos `DateTime.now()`, `Stopwatch(`, `Random(`,
    `print(` a `lib/features/practice/domain/` fában — ezt a §3.1/h
    forrás-szkennelő teszt bizonyítja, ami a könyvtárat járja be (nem fix
    fájllistát), tehát a jövőbeli fájlokra is érvényes. Az időpont/időtartam
    mindig injektált mezőérték.
18. **Nincs lokalizált szöveg a domainben.** A definition `titleKey` /
    `descriptionKey` ARB-kulcsra mutat, a coaching- és `reasonCode`-ok gépi
    kódok. A `message` mező a `PracticeValidationFailure`-ben fejlesztői
    diagnosztika (angol, nem user-facing) — ez az R02-ben elfogadott minta.

## 6. Acceptance criteria

Minden pipához tényleges futtatás vagy diffben ellenőrizhető bizonyíték
tartozik; a §10-be a VALÓS kimenet kerül.

- [ ] **Teljes modellkészlet:** a §4 tábla mind a 13 új `lib`-fájlja létezik, és
      együtt lefedi az SDD Kör 3 felsorolását (PracticeMode, PracticeSource,
      PracticeDifficulty, PracticeEvent, PracticeDefinition,
      PracticeSessionConfig, PracticeObservation hierarchia, PracticeVerdict,
      MetricValue, PracticeMetrics, PracticeAttemptResult,
      PracticeSessionResult, ScoringProfile, finish reason, stable IDs).
- [ ] **Minden §9 kód tesztelt:** a §5/9 táblázat MINDEN kódjára van olyan
      teszt, amely előállítja azt a validációs hibát, és a kód-stringet
      literálként állítja (nem konstans-hivatkozáson át) — így egy átnevezés
      elbukik.
- [ ] **SDD Kör 3 kötelező validációs esetei külön-külön tesztelve:** duplikált
      event ID · rendezetlen eventlista · `totalBeats`-en kívüli event · üres
      scored target (`events.empty` scored módban) · invalid chord label ·
      invalid confidence · metrika-range · inkompatibilis scoring-súlyok ·
      invalid session config.
- [ ] **Aggregálás bizonyítva:** van teszt, ahol EGY objektum EGYSZERRE több
      hibát ad vissza (≥ 3 failure egy `validate()` hívásból), és a valid eset
      üres listát.
- [ ] **Beágyazott hibák átjönnek:** érvénytelen `Tempo` (pl. 500 BPM) a
      configban / definitionben `tempo.bpm.outOfRange` kóddal jelenik meg a
      külső `validate()` listájában.
- [ ] **Súly-integritás:** `weights` összeg 99 és 101 → `sumNotHundred`;
      negatív súly → `weights.negative`; `freePractice` + nem üres súlyok →
      `definition.scoringProfile.incompatibleWithMode`; `strumPattern` +
      `{rhythm: 55, direction: 45}` → valid; `strumPattern` +
      `{rhythm: 60, chord: 40}` → inkompatibilis.
- [ ] **Ablak-sorrend:** `perfect > good` vagy `good > match` →
      `window.ordering`; nulla/negatív ablak → `window.nonPositive`; a parity
      profil (280/50/120 ms) valid, és a három érték tesztben literálként
      rögzített.
- [ ] **Canonical chord label:** `'C'`, `'C#m'`, `'Bm'` valid; `null` valid;
      `''`, `'N.C.'`, `'Bb'`, `'Cmaj7'`, `'c'`, `' C'` invalid — event és
      observation oldalon egyaránt.
- [ ] **Marker-szabály:** marker event chord/direction nélkül valid; marker +
      direction → `event.marker.scorable`; nem-marker, attribútum nélkül →
      `event.scorable.missing`.
- [ ] **Eventlista-szabályok tick-egzaktan:** két event ugyanazon a
      `BeatPosition`-on → `events.positionDuplicate`; csökkenő pozíciósorrend →
      `events.unsorted`; `position >= totalBeats` ticks → `event.position.outOfRange`
      (a `totalBeats` határ viselkedése a doc-commentben rögzített és tesztelt).
- [ ] **Confidence és metrika-tartomány:** `0.0` és `1.0` VALID (zárt),
      `-0.01`/`1.01` → `outOfRange`, `NaN`/`±∞` → `notFinite` — observation és
      `MetricAvailable` oldalon egyaránt.
- [ ] **Verdict-konzisztencia:** unmatched verdict `observedAt`-tel →
      `verdict.match.inconsistent`; unmatched + `TimingGrade.perfect` →
      ugyanaz; ismeretlen coaching kód → `verdict.coachingCode.unknown`; az öt
      kanonikus kód literálként tesztelt.
- [ ] **Stabil kódok:** minden §5/10 enumra `code` → `fromCode` roundtrip
      MINDEN értékre; a kódok egyediek az enumon belül; ismeretlen kód → `null`;
      a kód-stringek literálként pinnelve (átnevezés elbukik).
- [ ] **Value semantics:** minden modellre van teszt, ami két külön példány
      (azonos tartalom, listamezőkkel is) `==` és `hashCode` egyezését állítja,
      és egy mező eltérésekor a nem-egyenlőséget; a `Set`/`Map` kulcsként való
      viselkedés legalább a definition + event esetén tesztelt.
- [ ] **`bestAttempt`/`finalAttempt` determinizmus:** holtverseny → kisebb
      index; nincs érvényes overall → `null` best (vagy a §5/16 szerinti
      viselkedés) tesztelve; üres attempt-lista → `null`, nem kivétel.
- [ ] **MINOR-1 zárva:** `Meter(beatsPerBar: 0).ticksPerBar` és
      `Meter(beatsPerBar: -1).ticksPerBar` `StateError`-t dob, ahogy a nem
      támogatott `beatUnit` is; a 4/4 → 1920, 3/4 → 1440, 6/8 → 1440 meglévő
      állítások változatlanul zöldek.
- [ ] **Purity-őr:** a `domain_purity_test.dart` bejárja a
      `lib/features/practice/domain/` fát, és üres találati listát vár
      `DateTime.now()`, `Stopwatch(`, `Random(`, `print(` mintákra + a
      Flutter/Riverpod/Dio/l10n importokra. **Valódi-sértés próba kötelező:**
      ideiglenesen szúrj be egy `print('x');`-et (vagy `DateTime.now()`-ot) egy
      domain-fájlba → a teszt PIROS → visszavonva → ZÖLD; mindkét kimenet a
      §10-be.
- [ ] **Framework-függetlenség géppel:** `dart run tool/check_architecture.dart`
      zöld, és az új fájlok importlistája diffből ellenőrizhetően csak `dart:`
      core, `package:meta/meta.dart`, egymás (relatív) és
      `lib/core/music/strum.dart`.
- [ ] **Nincs JSON:** a diffben nincs `toJson`, `fromJson`, `jsonEncode`,
      `dart:convert`.
- [ ] **Nincs `double` zenei pozíció** az új API-kban (grep a publikus
      szignatúrákon: `double` csak score/confidence/BPM kontextusban).
- [ ] **`git diff --stat` a §4 listán kívül semmit nem érint**; meglévő fájl
      csak `meter.dart`, `practice_validation.dart`, `meter_test.dart`,
      `practice_validation_test.dart` (utóbbi kettő csak bővül).
- [ ] **Meglévő tesztek zöldek** (§7): `test/features/practice`, `test/core`,
      `test/app`, `test/features/learn` — egyet sem módosított a kör a fenti
      kettőn kívül.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — **soha ne láncold `&&`-del**, és
`analyze` + `test` soha nem egy hívásban):

```bash
~/flutter/bin/flutter pub get
```
```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
```
```bash
~/flutter/bin/flutter analyze lib/ test/ tool/
```
```bash
~/flutter/bin/flutter test test/features/practice
```
```bash
~/flutter/bin/flutter test test/core
```
```bash
~/flutter/bin/flutter test test/app
```
```bash
~/flutter/bin/flutter test test/features/learn
```
```bash
~/flutter/bin/dart run tool/check_architecture.dart
```

A teljes suite + randomizált property gate + APK a CI-ban
([ADR 0052](../adr/0052-ci-apk-automerge-session-per-round.md) /
[ADR 0053](../adr/0053-ci-full-test-suite.md)). **A `gh` hívás, a CI-dispatch,
a PR és a merge Claude-oldal** ([ADR 0064](../adr/0064-codex-hands-over-ci-at-code-complete.md))
— a Codex ne futtasson `gh`-t.

## 8. Implementációs sorrend

A kör nagy (13 új modellfájl), ezért **rétegenként, TDD-vel**, és minden réteg
után futtatott `test/features/practice`-szel. Mérföldkőnként `progress` jelzés
javasolt (AGENTS.md §15.2) — az nem zárja le a kört.

1. **Alap:** `practice_value_equality.dart` + tesztje; `practice_validation.dart`
   kódbővítés (a kódok literál-pinnelése a tesztben). RED → GREEN.
2. **Enumok:** `practice_mode.dart` (+ `scoredDimensions`),
   `practice_source.dart`, `practice_difficulty.dart` és a
   `practice_enums_test.dart` (roundtrip + egyediség). A további enumok a saját
   fájljukkal jönnek, de ugyanez a teszt fedi őket a végén.
3. **Scoring profile:** `scoring_profile.dart` (+ `PracticeScoreDimension`,
   `ExtraStrumPolicy`, parity profil) + tesztje.
4. **Event → definition:** `practice_event.dart`, majd
   `practice_definition.dart` (eventlista-szabályok + mode/profil
   kompatibilitás) + tesztjeik. A tesztek előbb (valódi RED).
5. **Config:** `practice_session_config.dart` + tesztje.
6. **Observation / verdict / metrika:** `practice_observation.dart`,
   `practice_verdict.dart`, `practice_metrics.dart` + tesztjeik.
7. **Eredmények:** `practice_attempt_result.dart`,
   `practice_session_result.dart` + `practice_result_test.dart` (best/final
   determinizmus).
8. **MINOR-1:** `meter_test.dart` új esetei előbb (RED — ma csendben számol),
   majd a `meter.dart` szimmetrikus fail-fast (GREEN).
9. **Purity-őr:** `domain_purity_test.dart`, majd a valódi-sértés próba a §6
   szerint (ideiglenes `print`/`DateTime.now()` → piros → visszavonás → zöld),
   a kimenetek a §10-be.
10. `format` → `analyze` → §7 tesztek → `check_architecture` — külön hívásokként;
    a §10 kitöltése a TÉNYLEGES kimenetekkel.
11. Kör-jelzés: `tools/codex-signal.sh done|stopped|blocked` (AGENTS.md §15.2).

## 9. Kockázatok

- **Ez a kör Epic 2 legnagyobb típus-felülete.** 13 új fájl egy körben — a
  csúszás iránya a „még egy kis logika" (matcher-előkészítés, score-számítás,
  katalógus-adat). A §3 „Kívül" listája szó szerint értendő: adat + validáció,
  semmi algoritmus.
- **`const` konstruktor vs. defenzív listamásolat.** Az ADR 0068 §4 a `const`-ot
  választotta (Kör 4 katalógusa miatt), tehát a lista-aliasing kockázata
  megmarad, és CSAK doc-comment-szerződés + „a domain nem mutál" szabály védi.
  Ha a Codex mégis `List.unmodifiable`-t akar használni, az elveszi a
  `const`-ot — az ADR-től eltérés, tehát `stopped` jelzés, nem csendes döntés.
- **A `double` visszaszivárgása.** A score/confidence/BPM legitim `double`, a
  pozíció/idő nem. Egy „kényelmi" `double beat` paraméter bárhol az új API-kban
  az ADR 0066 megkerülése — a review a publikus szignatúrákat végigellenőrzi.
- **Súly-map és egyenlőség.** `Map` mező `==`-ja szintén identitás alapú; a
  `ScoringProfile` egyenlősége csak akkor helyes, ha a súly-map is elem-szinten
  hasonlít (a §3.1/i helper Map-ágat is kap, vagy a profil rendezett
  kulcs-listát tárol). Enélkül a Kör 4 katalógus-tesztjei megmagyarázhatatlanul
  buknának.
- **A purity-teszt önmaga hamis pozitívja.** A minta-szkennelés a
  doc-commentekben és stringekben is találhat `print(`-et vagy `DateTime.now()`-t.
  A tesztnek ezért a mintát úgy kell keresnie, hogy a saját teszt-fájlját és a
  kommenteket ne verje el feleslegesen — de a mérce a valódi-sértés próba
  mindkét iránya (piros a sértéskor, zöld visszavonás után).
- **`sealed` hierarchia és exhaustive switch.** A `PracticeObservation` és a
  `MetricValue` `sealed` — ha egy későbbi kör új leszármazottat ad, minden
  `switch` fordítási hibát ad. Ez SZÁNDÉKOS (ez a `sealed` értelme); e körben a
  hierarchia zárt, új leszármazott nem kerül bele.
- **Formázás az új fájlfán:** a `dart format` a `lib test tool` teljes fáján fut
  — a 13 új fájl is beleértve, különben a CI format-gate bukik.

## 10. Implementation handoff — a Codex tölti ki

<!-- Fájlonkénti összefoglaló · a futtatott parancsok TÉNYLEGES kimenete ·
     TDD RED→GREEN evidencia · a purity-őr valódi-sértés próbája (piros ÉS zöld) ·
     eltérések a tervtől és okuk · nem futtatott ellenőrzések és okuk ·
     follow-up leletek. -->

## 11. Review

<!-- Claude tölti ki: docs/reviews/e02-r03-review.md link + verdikt. -->
