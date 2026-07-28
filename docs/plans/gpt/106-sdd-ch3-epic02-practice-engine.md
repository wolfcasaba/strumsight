---
id: 106
topic: SDD Ch3 / Epic 2 — Practice Engine: 20 kör (BeatPosition tick-idő, session state machine, matcher, scoring, Speed Builder, LessonScorer parity)
tags: [sdd, epic2, practice-engine, scoring, state-machine, speed-builder, parity]
status: active
depends_on: [105]
canonical_target: docs/sdd/03-epic-02-practice-engine.md
verify: LessonScorer parity fixtures zöld + valós eszközös gate
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# StrumSight Software Design Document

## Chapter 3 — Epic 2: Practice Engine

**Dokumentumverzió:** 1.0  
**Implementációs állapot:** fejlesztésre kész  
**Repository:** `wolfcasaba/strumsight`  
**Előfeltétel:** Chapter 2 — Epic 1 Core Platform & Infrastructure  
**Célplatform:** Flutter, Android-first, később iOS  
**Fő képesség:** teljesen offline, valós idejű gitárgyakorlás és értékelés  
**Végrehajtó:** Codex  
**Végrehajtási mód:** körönként, kis és önálló fejlesztési egységekben

---

# 1. Az Epic célja

Az Epic 2 célja egy egységes, újrahasznosítható és tesztelhető Practice Engine létrehozása, amely a StrumSight meglévő on-device chord- és strum-direction felismerésére építve valódi, interaktív gitárgyakorlást biztosít.

A Practice Engine feladata nem pusztán egy animált lejátszó létrehozása. A rendszernek teljes gyakorlási ciklust kell kezelnie:

- gyakorlat kiválasztása és konfigurálása;
- mikrofon és audio session biztonságos megszerzése;
- count-in és metronóm;
- célakkordok és pengetések időzített megjelenítése;
- valós idejű strum- és chord-megfigyelések fogadása;
- ritmus-, irány- és akkordpontozás;
- pause, resume, restart és loop;
- adaptív nehézségi javaslatok;
- Speed Builder;
- eredmény és érthető coaching;
- progress, streak és napi cél frissítése;
- teljes offline működés.

Az Epic végére a StrumSight rendelkezzen egy közös motorral, amelyet a következő források egyaránt használhatnak:

- beépített gyakorlófeladatok;
- jelenlegi Learn leckék;
- saját Songs;
- Setlists;
- Daily Challenge;
- Analyze eredményből létrehozott gyakorlat;
- későbbi AI Practice Generator;
- későbbi Song Trainer.

A felhasználó számára az eredmény egy külön **Practice** terület legyen, ahol célzottan fejlesztheti a ritmust, a le- és felpengetést, az akkordváltásokat és a tempót.

---

# 2. Termékvízió

A Practice Engine termékígérete:

> A StrumSight nem csak megmutatja, mit kell játszani, hanem meghallgatja, hogyan játszod, megmutatja a konkrét hibát, és a következő próbát a fejlődésedhez igazítja.

A felhasználó minden gyakorlat után kapjon választ legalább az alábbi kérdésekre:

- időben játszottam-e;
- siettem vagy késtem;
- jó irányba pengettem-e;
- a megfelelő akkord szólt-e;
- hol szakadt meg a ritmusom;
- melyik váltás okozta a legtöbb hibát;
- milyen tempón érdemes folytatnom;
- mit gyakoroljak újra.

A rendszer csak olyan állítást jeleníthet meg, amelyet a rendelkezésre álló audiojel és detektor megbízhatóan alátámaszt. Az Epic 2 nem állíthatja például, hogy egy adott húr zörög vagy egy ujj rossz helyen van, mert ehhez még nincs megfelelő string-level vagy computer-vision jel.

---

# 3. Kapcsolat a jelenlegi kódbázissal

A Practice Engine nem nulláról indul. A jelenlegi repository már több értékes komponenst tartalmaz.

## 3.1 Meglévő, újrahasználandó képességek

- `Lesson` és `LessonEvent` időzített chord/strum célokkal;
- `LessonScorer` determinisztikus időzítés- és direction scoringgal;
- `LessonTiming` count-in, playhead és beat-crossing számításokkal;
- `LearnScreen` valós idejű Live frame integrációval;
- engine clock alapú strum de-jitter korrekció;
- input- és visual-latency kalibráció;
- expected-chord hint a detektor számára;
- `Metronome` és `BeatClock`;
- practice speed preference;
- Easy mód és fail-streak alapú egyszerűsítési javaslat;
- lesson progress, stars és curriculum unlock;
- `PracticeEntry`, `PracticeStats` és napi cél;
- streak és Daily Challenge;
- `Song.toLesson()`;
- Analyze eredményből készíthető lesson;
- chord diagram és lesson highway UI;
- sok meglévő unit, widget, property és regressziós teszt.

## 3.2 Jelenlegi korlátok

A jelenlegi Learn implementáció több felelősséget egyetlen stateful screenben kezel:

- clock;
- ticker;
- audio frame subscription;
- scorer lifecycle;
- metronóm;
- backing playback;
- haptika;
- progress mentés;
- streak mentés;
- summary navigáció;
- expected-chord hint;
- dinamikus nehézség;
- UI state.

Ez működőképes, de nem bővíthető biztonságosan több gyakorlási módra. A következő technikai problémákat kell megszüntetni:

1. A `LessonScorer` egy konkrét lesson-formátumhoz kötött.
2. Az idő másodpercben tárolt `double`, ami komplexebb ritmikai felosztásoknál pontatlanná válhat.
3. A scorer a timingot és directiont egyetlen hit verdictbe köti.
4. A chord scoring csak másodlagos számláló, részletes hibainformáció nélkül.
5. A teljes session állapot nincs explicit state machine-ben.
6. A pause és aktív gyakorlási idő nincs külön domain fogalomként kezelve.
7. Nincs közös observation gateway.
8. Nincs egységes gyakorlatkatalógus.
9. A Progress log túl kevés dimenziót tárol a részletes fejlődéshez.
10. Nincs loop- és attempt-szintű modell.
11. Nincs általános Speed Builder policy.
12. A meglévő Learn képernyő közvetlenül függ több más feature belső providerétől.

## 3.3 Migrációs alapelv

A jelenlegi Learn funkciót nem szabad egyszerre lecserélni.

Kötelező migrációs stratégia:

```text
Existing LearnScreen + LessonScorer
                 |
                 | parity fixtures
                 v
Practice adapters + Practice Engine V2
                 |
                 | feature flag
                 v
Migrated Learn experience
```

A régi motor addig maradjon elérhető, amíg:

- a parity tesztek zöldek;
- a valódi eszközös teszt lezárult;
- a pontozási eltérések dokumentáltak;
- a production feature flag engedélyezhető.

---

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- Practice domain modellek;
- beat- és időérték objektumok;
- practice definition és catalog;
- session és attempt state machine;
- count-in, pause, resume, restart és finish;
- audio observation adapter;
- target timeline compiler;
- eseménymatching;
- timing scoring;
- strum-direction scoring;
- chord correctness scoring;
- kombinált és dimenziónkénti eredmények;
- korai/késői ritmikai bias;
- combo és score;
- strum-pattern practice;
- chord-change practice;
- chord-progression practice;
- rhythm-only practice;
- free-practice mérés;
- Speed Builder;
- loop és problem-section retry;
- Practice Hub;
- setup képernyő;
- session képernyő;
- result és coaching képernyő;
- practice history V2;
- streak és daily-goal integráció;
- Learn, Song, Analyze és Daily Challenge adapterek;
- localization és accessibility;
- teljes offline működés;
- unit, property, widget és integration tesztek.

## 4.2 Az Epic nem tartalmazza

- AI által generált egyedi gyakorlóterv;
- felhőalapú LLM;
- offline LLM;
- kamera alapú kéztartás-elemzés;
- string-level zörgésfelismerés;
- egyedi húrok hangjának polifonikus értékelése;
- skála- és dallamhangok teljes pitch trackingje;
- sweep, tapping vagy bend automatikus technikaértékelése;
- Guitar Pro import;
- MusicXML import;
- backing track generálás;
- közösségi ranglista;
- előfizetés;
- új DSP vagy új ML-modell tanítása.

Az Epic 2 architektúrája készítsen bővítési pontot ezekhez, de ne implementáljon spekulatív, használaton kívüli rendszereket.

---

# 5. Felhasználói utak

## 5.1 Gyors kezdés

1. A felhasználó megnyitja a Practice fület.
2. A rendszer kiemeli a legutóbbi vagy ajánlott gyakorlatot.
3. A felhasználó megnyomja a `Start` gombot.
4. Egy ütem count-in indul.
5. A célok a strike line felé haladnak.
6. A rendszer valós időben jelzi a timingot, directiont és chordot.
7. A gyakorlat végén részletes eredmény jelenik meg.
8. A felhasználó újrapróbálhatja, lassíthatja vagy Speed Builderbe teheti.

## 5.2 Akkordváltás gyakorlása

1. A felhasználó kiválaszt két vagy több akkordot.
2. Beállítja a tempót és a váltások gyakoriságát.
3. A rendszer előre jelzi a következő akkordot.
4. A játékos a célütés környékén penget.
5. A rendszer méri, hogy a megfelelő akkord mikor vált felismerhetővé.
6. Az eredmény megmutatja a leglassabb és legbizonytalanabb váltást.

## 5.3 Strumming pattern gyakorlása

1. A felhasználó kiválaszt egy mintát, például `D - D U - U D U`.
2. Kiválaszt egy akkordot vagy muted-strum módot.
3. A rendszer külön méri a ritmust és a directiont.
4. A hibás direction események vizuálisan külön jelennek meg.
5. Az eredmény megmutatja, hogy melyik slot okozta a legtöbb hibát.

## 5.4 Speed Builder

1. A felhasználó kiválaszt egy gyakorlatot.
2. Megadja a kezdő és céltempót.
3. Sikeres attempt után a rendszer emeli a BPM-et.
4. Sikertelen attempt után ismétel vagy csökkenti a tempót a policy szerint.
5. A session végén megjelenik a legmagasabb stabil tempó.

## 5.5 Szabad gyakorlás

1. A felhasználó elindítja a Free Practice módot.
2. Nincs előírt cél és nincs hamis pass/fail eredmény.
3. A rendszer méri a strumszámot, tempóstabilitást, direction-eloszlást és felismert akkordokat.
4. A felhasználó a session után tényszerű összegzést kap.

---

# 6. Funkcionális követelmények

## 6.1 Általános követelmények

A Practice Engine:

- internet nélkül induljon és működjön;
- ne igényeljen felhasználói fiókot;
- kizárólag explicit user action után indítsa a mikrofont;
- egyszerre csak egy audio sessiont használjon;
- kezelje a permission denial állapotot;
- pause alatt ne pontozzon és ne számoljon aktív időt;
- resume után ne ugorjon a playhead;
- restart után teljesen tiszta attemptet indítson;
- app háttérbe kerülésekor biztonságosan pause-oljon vagy álljon le;
- minden eredményt determinisztikusan számoljon;
- ne értékeljen olyan dimenziót, amelyhez nincs elegendő adat;
- ne módosítsa csendben a nehézséget aktív attempt közben;
- minden tartós adatot verziózott formátumban mentsen.

## 6.2 Gyakorlatindítás

A felhasználó legalább az alábbi beállításokat szabályozhassa, ha az adott mód támogatja:

- BPM;
- practice speed;
- count-in bars;
- metronóm be/ki;
- accent be/ki;
- loop count vagy időtartam;
- difficulty/scoring profile;
- chord vagy chord sequence;
- strum pattern;
- easy variation;
- Speed Builder be/ki;
- kezdő BPM;
- cél BPM;
- BPM step.

## 6.3 Sessionvezérlés

Kötelező műveletek:

- prepare;
- start;
- pause;
- resume;
- restart attempt;
- skip count-in, csak fejlesztői vagy megfelelő UX-döntés esetén;
- finish;
- cancel;
- retry;
- exit.

## 6.4 Valós idejű feedback

A UI legfeljebb az alábbi pillanatnyi információkat jelenítse meg:

- aktuális célakkord;
- következő célakkord;
- várt strum direction;
- timing verdict: perfect, good, early, late;
- direction verdict;
- chord verdict;
- combo;
- score;
- input level;
- mikrofon állapot;
- session állapot;
- count-in szám.

A feedback ne villogjon minden audio frame-re. Csak új strum vagy lezárt target esemény változtassa meg az eseményfeedbacket.

---

# 7. Támogatott gyakorlási módok

## 7.1 Strum Pattern Practice

Célja a pengetési kéz ritmusának és irányának fejlesztése.

Céladat:

- egy vagy több bar;
- meter;
- subdivision;
- down/up/rest események;
- opcionális chord target;
- tempo.

Pontozott dimenziók:

- timing;
- direction;
- opcionálisan chord.

Nem pontozandó:

- húronkénti tisztaság;
- pick angle;
- kéztartás.

## 7.2 Chord Change Practice

Célja két vagy több akkord közötti stabil váltás.

A rendszer ne állítsa, hogy a fogás fizikailag helyes. A rendelkezésre álló jel alapján azt mérheti, hogy:

- a várt akkord felismerhető volt-e;
- mikor vált felismerhetővé;
- mennyi ideig maradt stabil;
- hány váltás teljesült;
- melyik chord-pár okozta a legtöbb hibát.

Pontozott dimenziók:

- chord correctness;
- change timing;
- opcionálisan rhythm.

A direction alapértelmezetten információs, nem kötelező pontozási dimenzió.

## 7.3 Chord Progression Practice

Célja chord progression és strumming pattern együttes gyakorlása.

Pontozott dimenziók:

- timing;
- direction;
- chord correctness;
- completion;
- consistency.

Ez a mód lesz a jelenlegi Learn leckék és saját Songs közös alapja.

## 7.4 Rhythm-only Practice

A játékos tompított húrokkal vagy tetszőleges akkorddal játszhat.

Pontozott dimenziók:

- target onset timing;
- groove consistency;
- opcionálisan direction.

A chord detector eredménye ebben a módban nem befolyásolja a score-t.

## 7.5 Free Practice

Nincs target timeline és nincs pass/fail.

Mérhető:

- aktív idő;
- strumszám;
- down/up arány;
- becsült BPM;
- tempóingadozás;
- chord timeline;
- felismert akkordok száma;
- input-signal availability.

A Free Practice eredményében az `accuracy` mező nem jelenhet meg, mert nincs cél, amelyhez pontosságot lehetne számítani.

## 7.6 Speed Builder

A Speed Builder nem külön zenei tartalom, hanem egy orchestration policy bármely támogatott scored practice fölött.

Támogatott alapmódok:

- strum pattern;
- chord changes;
- chord progression;
- rhythm only;
- migrated lesson;
- migrated song.

## 7.7 Legacy és külső forrás adapterek

Források:

```text
Lesson             -> PracticeDefinition
Song               -> PracticeDefinition
AnalyzeResult      -> PracticeDefinition
DailyChallenge     -> PracticeDefinition
Setlist item       -> PracticeDefinition
```

Az adapterek nem duplikálhatják a scorer logikát.

---

# 8. Célarchitektúra

## 8.1 Feature struktúra

```text
lib/features/practice/
├── public.dart
├── domain/
│   ├── model/
│   │   ├── beat_position.dart
│   │   ├── meter.dart
│   │   ├── tempo.dart
│   │   ├── practice_definition.dart
│   │   ├── practice_event.dart
│   │   ├── practice_mode.dart
│   │   ├── practice_source.dart
│   │   ├── practice_session_config.dart
│   │   ├── practice_session_state.dart
│   │   ├── practice_attempt_result.dart
│   │   ├── practice_session_result.dart
│   │   ├── practice_metrics.dart
│   │   ├── practice_observation.dart
│   │   ├── practice_verdict.dart
│   │   ├── scoring_profile.dart
│   │   └── speed_builder_policy.dart
│   ├── repository/
│   │   ├── practice_catalog_repository.dart
│   │   └── practice_history_repository.dart
│   └── service/
│       ├── practice_target_compiler.dart
│       ├── practice_event_matcher.dart
│       ├── practice_scorer.dart
│       ├── practice_coach.dart
│       └── adaptive_practice_policy.dart
├── application/
│   ├── practice_session_controller.dart
│   ├── practice_session_command.dart
│   ├── practice_session_effect.dart
│   ├── practice_session_clock.dart
│   ├── practice_observation_gateway.dart
│   ├── practice_catalog_controller.dart
│   ├── practice_setup_controller.dart
│   └── providers.dart
├── data/
│   ├── builtin_practice_catalog.dart
│   ├── local_practice_history_repository.dart
│   ├── practice_history_serializer.dart
│   ├── live_practice_observation_gateway.dart
│   └── adapters/
│       ├── lesson_practice_adapter.dart
│       ├── song_practice_adapter.dart
│       ├── analyze_practice_adapter.dart
│       └── daily_challenge_practice_adapter.dart
└── presentation/
    ├── screens/
    │   ├── practice_hub_screen.dart
    │   ├── practice_setup_screen.dart
    │   ├── practice_session_screen.dart
    │   ├── practice_result_screen.dart
    │   └── practice_history_screen.dart
    └── widgets/
        ├── practice_highway.dart
        ├── practice_hud.dart
        ├── practice_feedback.dart
        ├── practice_controls.dart
        ├── score_breakdown.dart
        ├── timing_bias_chart.dart
        ├── chord_change_breakdown.dart
        └── speed_builder_progress.dart
```

## 8.2 Függőségi irány

```text
Presentation -> Application -> Domain
       |              |
       |              +----> Domain repository interfaces
       |
       +--------------------> Application providers

Data -> Domain repository interfaces
Data -> Core audio/network/storage adapters
Domain -X-> Flutter, Riverpod, plugins, SharedPreferences, Dio
```

## 8.3 Kódminőségi szabályok

- A domain teljesen pure Dart legyen.
- A scorer ne használjon clockot, IO-t vagy Riverpodot.
- A widget ne tartalmazzon scoring algoritmust.
- A session controller ne rajzoljon UI-t.
- Az audio gateway ne ismerje a presentation réteget.
- A perzisztencia ne tároljon lokalizált szöveget.
- Minden persisted enum stabil string kódot használjon.
- Egy target és egy observation legfeljebb egyszer párosítható.
- Az összes score 0 és 1 között legyen, vagy explicit `notAvailable` állapotot kapjon.
- `DateTime.now()`, `Stopwatch()` és random generátor csak injektálható boundary mögött használható.
- A production kód ne használjon `print` hívást.
- Nincs üres `catch` blokk.
- Nincs `dynamic`, ha statikus típus lehetséges.
- Nincs más feature belső `presentation`, `providers` vagy `data` importja.

---

# 9. Domain időmodell

## 9.1 BeatPosition

A target zenei pozíciót ne `double beat` tárolja. Használjon integer tick alapú értékobjektumot.

```dart
final class BeatPosition implements Comparable<BeatPosition> {
  const BeatPosition(this.ticks);

  static const int ticksPerBeat = 480;

  final int ticks;

  factory BeatPosition.beats(num beats) {
    return BeatPosition((beats * ticksPerBeat).round());
  }
}
```

Támogatott felosztások:

- negyed: 480 tick;
- nyolcad: 240 tick;
- tizenhatod: 120 tick;
- nyolcad triola: 160 tick.

Követelmények:

- negatív target beat tiltott;
- count-in külön session fogalom, nem negatív event pozíció;
- összeadás és kivonás tesztelt;
- JSON integer tick formában tároljon;
- a legacy `double beat` adapter ellenőrizze a kerekítési eltérést.

## 9.2 Tempo

```dart
final class Tempo {
  const Tempo(this.bpm);

  final double bpm;
}
```

Valid tartomány alapértelmezetten:

```text
30.0 <= bpm <= 300.0
```

A UI szűkebb tartományt kínálhat. Az import adapter kontrolláltan clampelhet vagy validation failure-t adhat.

## 9.3 Meter

```dart
final class Meter {
  const Meter({required this.beatsPerBar, this.beatUnit = 4});

  final int beatsPerBar;
  final int beatUnit;
}
```

Epic 2 kötelező támogatás:

- 4/4;
- 3/4.

Az architektúra ne égesse be a `8 slot/bar` feltételezést. Más meter később hozzáadható.

## 9.4 Session time

A session belső időforrása monotonic `Duration` legyen.

Tilos scoringhoz használni:

- wall-clock DateTime;
- UI animation frame számát;
- `Timer.periodic` tickek számát.

A wall-clock csak perzisztált `startedAt` és `endedAt` mezőhöz használható.

---

# 10. Fő domain modellek

## 10.1 PracticeMode

```dart
enum PracticeMode {
  strumPattern,
  chordChanges,
  chordProgression,
  rhythmOnly,
  freePractice,
}
```

A Speed Builder nem külön enum érték, hanem session policy.

## 10.2 PracticeSource

Stabil stringkódokkal:

```text
builtin
lesson
song
analyze
setlist
dailyChallenge
userCreated
futureAi
```

A `futureAi` csak reserved source code lehet; Epic 2 alatt ne generáljon tartalmat.

## 10.3 PracticeEvent

```dart
final class PracticeEvent {
  const PracticeEvent({
    required this.id,
    required this.position,
    this.duration,
    this.chord,
    this.direction,
    this.accent = false,
    this.optional = false,
  });

  final String id;
  final BeatPosition position;
  final BeatPosition? duration;
  final String? chord;
  final StrumDirection? direction;
  final bool accent;
  final bool optional;
}
```

Validáció:

- event ID egy definitionön belül egyedi;
- eventlista pozíció szerint rendezhető;
- chord normalizált label vagy null;
- legalább egy pontozható attribútum szükséges, kivéve marker event;
- optional event kihagyása ne számítson missnek;
- azonos tickre több event csak explicit poly-event támogatással engedhető; Epic 2-ben alapértelmezetten tiltott.

## 10.4 PracticeDefinition

Kötelező mezők:

```dart
final class PracticeDefinition {
  const PracticeDefinition({
    required this.id,
    required this.schemaVersion,
    required this.titleKey,
    required this.descriptionKey,
    required this.mode,
    required this.source,
    required this.meter,
    required this.defaultTempo,
    required this.totalBeats,
    required this.events,
    required this.scoringProfile,
    required this.skillTags,
    this.sourceReference,
    this.difficulty = PracticeDifficulty.beginner,
  });
}
```

A domain ne tároljon közvetlen lokalizált title szöveget a beépített gyakorlatoknál. A `titleKey` ARB kulcsra mutasson. User-created tartalom esetén külön display-name mező vagy source metadata használható.

## 10.5 PracticeSessionConfig

A definition változatlan tartalom. A felhasználói beállítások külön configban legyenek.

Kötelező mezők:

- definition ID és snapshot version;
- effective BPM;
- count-in bars;
- loop count;
- metronome enabled;
- accent enabled;
- backing enabled, ha támogatott;
- scoring profile ID;
- easy variation ID;
- input latency;
- visual latency;
- Speed Builder policy vagy null;
- expected-chord hint engedélyezve;
- session timeout;
- reduced-motion setting.

## 10.6 PracticeObservation

A strum és chord observation legyen külön típus.

```dart
sealed class PracticeObservation {
  const PracticeObservation({required this.at});
  final Duration at;
}

final class StrumObservation extends PracticeObservation {
  const StrumObservation({
    required super.at,
    required this.sequence,
    required this.direction,
    required this.confidence,
  });

  final int sequence;
  final StrumDirection direction;
  final double confidence;
}

final class ChordObservation extends PracticeObservation {
  const ChordObservation({
    required super.at,
    required this.label,
    required this.confidence,
  });

  final String? label;
  final double confidence;
}
```

Szabályok:

- observation idő monotonic;
- duplikált `sequence` eldobandó;
- confidence 0 és 1 között;
- alacsony confidence observation megőrizhető diagnosztikára, de score-ban policy dönt róla;
- raw PCM nem része ennek a modellnek.

## 10.7 PracticeVerdict

Egy target esemény részletes eredménye.

Mezők:

- target event ID;
- matched observation sequence vagy null;
- target time;
- observed time vagy null;
- signed timing offset;
- timing grade;
- expected direction;
- observed direction;
- direction correct vagy not applicable;
- expected chord;
- observed chord;
- chord correct vagy insufficient data;
- event score;
- miss reason;
- coaching code.

A coaching code stabil, lokalizálható gépi kód legyen, például:

```text
practice.coach.early
practice.coach.late
practice.coach.wrong_direction
practice.coach.chord_not_stable
practice.coach.no_signal
```

## 10.8 PracticeMetrics

```dart
final class PracticeMetrics {
  const PracticeMetrics({
    required this.completion,
    required this.rhythm,
    required this.direction,
    required this.chord,
    required this.overall,
    required this.totalTargets,
    required this.resolvedTargets,
    required this.maxCombo,
    required this.scorePoints,
    required this.meanAbsoluteOffset,
    required this.timingBias,
  });
}
```

A dimenzióscore ne egyszerű `double?` legyen, ha meg kell különböztetni:

- nincs alkalmazva;
- nincs elég adat;
- van érvényes score.

Javasolt:

```dart
sealed class MetricValue {
  const MetricValue();
}

final class MetricAvailable extends MetricValue {
  const MetricAvailable(this.value);
  final double value;
}

final class MetricNotApplicable extends MetricValue {
  const MetricNotApplicable();
}

final class MetricInsufficientData extends MetricValue {
  const MetricInsufficientData(this.reasonCode);
  final String reasonCode;
}
```

## 10.9 Attempt és Session

Egy attempt egy fix BPM-en, fix targettel végrehajtott playthrough vagy loop-csoport.

Egy session egy felhasználói gyakorlási alkalom, amely több attemptet tartalmazhat.

```text
PracticeSessionResult
├── session metadata
├── total active duration
├── paused duration
├── attempts[]
│   ├── fixed BPM
│   ├── attempt metrics
│   ├── verdict summary
│   └── completion state
├── best attempt
├── final attempt
├── highest stable BPM
└── coaching summary
```

---

# 11. Session state machine

## 11.1 Állapotok

```dart
enum PracticeSessionStatus {
  idle,
  preparing,
  permissionRequired,
  ready,
  countIn,
  running,
  paused,
  finishing,
  completed,
  cancelled,
  failed,
}
```

## 11.2 Engedélyezett átmenetek

```text
idle -> preparing
preparing -> permissionRequired | ready | failed
permissionRequired -> preparing | cancelled
ready -> countIn | cancelled
countIn -> running | paused | cancelled | failed
running -> paused | finishing | cancelled | failed
paused -> countIn | running | finishing | cancelled
finishing -> completed | failed
completed -> ready | idle
cancelled -> ready | idle
failed -> preparing | idle
```

Tiltott átmenet kontrollált `InvalidSessionTransitionFailure` eredményt adjon. Release buildben sem szabad csendben figyelmen kívül hagyni.

## 11.3 State tartalom

A state legalább tartalmazza:

- status;
- definition;
- config;
- attempt index;
- current BPM;
- session elapsed;
- active elapsed;
- attempt elapsed;
- playhead beat;
- current target;
- next target;
- current metrics snapshot;
- latest feedback;
- mic state;
- metronome state;
- Speed Builder state;
- recoverable failure;
- finish reason.

A state immutable legyen.

## 11.4 Command modell

A UI közvetlen mezőmódosítás helyett commandokat küldjön:

```text
PreparePractice
GrantPermission
StartPractice
PausePractice
ResumePractice
RestartAttempt
FinishPractice
CancelPractice
RetryPractice
ChangeTempoBeforeAttempt
AcceptAdaptiveSuggestion
```

## 11.5 Effect modell

Egyszeri UI eseményeket ne tároljunk tartós state flagként.

Példák:

```text
PlayHaptic
PlayCountInClick
ShowPermissionSettings
NavigateToResult
ShowRecoverableError
AnnounceAccessibilityFeedback
```

Az effect stream vagy egyértelmű one-shot mechanizmus tesztelhető legyen.

---

# 12. Session clock és timing pipeline

## 12.1 PracticeSessionClock

Interfész:

```dart
abstract interface class PracticeSessionClock {
  Duration now();
  void start();
  void pause();
  void resume();
  void resetAttempt();
}
```

A production implementation monotonic Stopwatchra épüljön. A fake clock tetszőleges időre előreléptethető legyen tesztekben.

## 12.2 Aktív és wall idő

Külön kell mérni:

- wall duration;
- active practice duration;
- count-in duration;
- paused duration;
- attempt duration.

A napi gyakorlási célba alapértelmezetten csak az aktív playing idő számítson bele. A count-in és pause ne növelje a daily goal progresszt.

## 12.3 Beat-idő konverzió

Állandó BPM esetén:

```text
targetSeconds = targetBeats * 60 / bpm
```

A production kód ne használjon szétszórt formulákat. A `PracticeTargetCompiler` vagy külön `BeatTimeConverter` legyen az egyetlen kanonikus implementáció.

## 12.4 Input latency

A strum observation pontozási ideje:

```text
playedAt = observedAt - calibratedInputLatency - frameDeliveryLag
```

A `frameDeliveryLag` a Live frame engine clockjaiból számítható:

```text
engineTimeSec - latestStrumTime
```

Sanity guard:

- negatív lag: 0;
- 0.5 másodpercnél nagyobb lag: figyelmen kívül hagyandó és logolandó;
- hiányzó engine clock: csak calibrated input latency használható.

A visual latency kizárólag a megjelenítési playheadet módosítsa. A score-t nem.

## 12.5 Pause és resume

Pause alatt:

- a session clock aktív ideje nem nő;
- observation nem párosítható targethez;
- expected-chord hint törölhető;
- mikrofon policy alapján felszabadítható;
- metronóm leáll;
- animáció leáll.

Resume:

- nem pontozhatja visszamenőleg a pause alatt érkezett frame-eket;
- új observation sequence baseline szükséges;
- opcionális count-in induljon a config szerint;
- a playhead folytonos vagy attempt restart legyen, explicit policy alapján.

Epic 2 alapértelmezése: resume előtt egy rövid, egybaros count-in, majd folytatás a következő biztonságos bar boundarytől.

---

# 13. Observation gateway

## 13.1 Interfész

```dart
abstract interface class PracticeObservationGateway {
  Stream<PracticeObservation> get observations;

  Future<AppResult<void>> start({
    required PracticeObservationConfig config,
  });

  void setExpectedChord(String? chord);
  Future<AppResult<void>> stop();
}
```

## 13.2 Live adapter

A `LivePracticeObservationGateway` a meglévő `StrumEngine` frame-jeit alakítsa át.

Feladata:

- új strum felismerése `strumSeq` alapján;
- strum de-jitter;
- input latency korrekcióhoz szükséges metaadat átadása;
- chord change-point kiszűrése;
- confidence normalizálása;
- duplikált frame eldobása;
- expected-chord hint továbbítása;
- start/stop lifecycle delegálása az Epic 1 audio coordinatorának.

## 13.3 Chord observation sampling

A scorernek nem szükséges minden frame-et tárolnia.

A gateway csak akkor emittáljon chord observationt, ha:

- a label megváltozott;
- a confidence relevánsan változott;
- eltelt a stabilitási mintavételi idő;
- a scorer explicit periodic sample-t kér.

Ezzel csökkenthető a memória és a felesleges state update.

## 13.4 Confidence policy

A confidence küszöbök a scoring profile részei legyenek, ne a UI-ban legyenek hardcode-olva.

Példa:

```text
strumMinConfidence = 0.55
chordMinConfidence = 0.60
chordStableDuration = 180 ms
```

Ezek kezdeti értékek. A meglévő valós-audio tesztek és mérés alapján kell véglegesíteni őket.

---

# 14. Target compiler

## 14.1 Feladat

A `PracticeTargetCompiler` a zenei `PracticeDefinition` eseményeiből időzített, scorer számára használható target timeline-t készít.

Input:

- definition;
- effective BPM;
- count-in;
- loop range;
- difficulty variation;
- scoring profile.

Output:

```text
CompiledPracticeTarget
├── timed events
├── count-in duration
├── target duration
├── ring-out duration
├── bar boundaries
├── expected-chord segments
└── scoring applicability
```

## 14.2 Determinizmus

Ugyanaz az input mindig bitre azonos logikai targetet adjon.

Tilos:

- wall-clock használata;
- random sorrend explicit seed nélkül;
- UI mérettől függő target idő;
- locale-tól függő sorrend.

## 14.3 Loop

A loop boundary csak zeneileg biztonságos ponton legyen:

- bar boundary;
- explicit section boundary;
- user-selected event range, normalizálva.

A loop restartkor:

- új attempt vagy új loop index keletkezzen;
- target assignment resetelődjön;
- combo policy explicit legyen;
- metronóm downbeat megszólaljon;
- expected chord a loop első targetjére álljon.

---

# 15. Eseménymatching

## 15.1 Alapalgoritmus

Egy strum observation a legközelebbi, még nyitott targethez párosítható, ha az időeltérés a match windowon belül van.

Kötelező invariánsok:

- egy observation legfeljebb egy targethez tartozhat;
- egy target legfeljebb egy primary observationt kaphat;
- optional target kihagyása nem miss;
- target window lezárásakor determinisztikus verdict készül;
- extra strum alapértelmezetten nem törli a combo-t;
- ugyanazon időeltérésnél a korábbi target nyer;
- input observations sorrendje normalizálandó monotonic orderre;
- túl későn érkező observation nem nyithat újra lezárt targetet.

## 15.2 Match window

A jelenlegi Learn kompatibilitási profilja:

```text
match window: +/- 280 ms
perfect:      +/- 50 ms
good:         +/- 120 ms
```

Az új profilok használhatnak tempo-aware ablakot, de az értékek egyetlen `ScoringProfile` objektumban legyenek.

Javasolt tempo-aware képlet:

```text
perfect = clamp(beatDuration * 0.10, 45 ms, 75 ms)
good    = clamp(beatDuration * 0.24, 100 ms, 160 ms)
match   = clamp(beatDuration * 0.52, 220 ms, 320 ms)
```

A production default csak mérés és parity review után válthat a legacy konstansokról.

## 15.3 Extra strum policy

Profilonként konfigurálható:

- `ignore`;
- `countInformationally`;
- `penalizeRhythm`.

Beginner és migrated Learn default: `ignore`.

Strict rhythm drill opcionálisan használhat enyhe büntetést, de az extra strum soha nem okozhat negatív score-t.

---

# 16. Pontozási rendszer

## 16.1 Dimenziók

A score dimenziói:

- completion;
- rhythm/timing;
- direction;
- chord correctness;
- consistency;
- overall.

## 16.2 Timing grade

```dart
enum TimingGrade {
  perfect,
  good,
  early,
  late,
  missed,
  notApplicable,
}
```

A signed offset:

```text
observedAt - targetAt
```

- negatív: early;
- pozitív: late.

## 16.3 Rhythm score

Egy lehetséges, determinisztikus event timing score:

```text
perfect = 1.00
good    = 0.80
early   = lineárisan 0.80 -> 0.35
a late  = lineárisan 0.80 -> 0.35
missed  = 0.00
```

A konkrét interpoláció külön pure függvény legyen és boundary tesztekkel rendelkezzen.

## 16.4 Direction score

Csak direction targettel rendelkező események számítanak.

```text
correct = 1
wrong   = 0
missing = 0
```

Alacsony confidence observation esetén a profile dönthet:

- úgy kezelje, mintha nem lenne observation;
- vagy insufficient-data jelzést adjon, ha az egész attempt signal quality-je rossz.

## 16.5 Chord score

A várt chord egy target körüli időablakban értékelendő.

Javasolt ablak:

```text
[targetAt - 120 ms, targetAt + 420 ms]
```

Az utólagos rész a chord detection természetes késését tolerálja.

Egy chord akkor tekinthető korrektnek, ha:

- a normalizált label egyezik;
- confidence eléri a profile küszöbét;
- a label a minimális stabilitási időn keresztül fennáll;
- vagy a target körüli minták többségi eredménye a várt chord.

A chord scorer különböztesse meg:

- correct;
- wrong chord;
- no chord detected;
- unstable;
- insufficient signal.

## 16.6 Overall score

Csak alkalmazható és elérhető dimenziókból számolható.

Alap súlyok:

```text
Strum Pattern:
  rhythm    55%
  direction 45%

Chord Changes:
  chord     60%
  rhythm    40%

Chord Progression:
  rhythm    35%
  direction 30%
  chord     35%

Rhythm Only:
  rhythm   100%

Free Practice:
  nincs overall score
```

A completion külön gate legyen. Például 50%-os completion alatt az attempt nem minősül passednek akkor sem, ha a kevés megjátszott event jó volt.

## 16.7 Pass policy

Alapértelmezett scored practice pass:

```text
completion >= 0.85
and overall >= 0.70
```

Speed Builder step-up:

```text
completion >= 0.95
and overall >= 0.85
and rhythm >= 0.80, ha alkalmazható
```

Ezek policy értékek, nem szétszórt konstansok.

## 16.8 Combo és pontok

A combo játékos motivációs réteg, nem szakmai metrika.

- clean resolved event növeli;
- missed vagy kötelező dimenzióban hibás event nullázza;
- optional event nem befolyásolja;
- pause nem nullázza, ha ugyanaz az attempt folytatódik;
- restart nullázza;
- loop boundary policy szerint megőrizheti.

A pontszám nem használható összehasonlításra eltérő definitionök között, hacsak nincs normalizált max-score.

---

# 17. Coaching rendszer

## 17.1 PracticeCoach

A coach pure service, amely a resultból lokalizálható coaching code-okat választ.

Input:

- metrics;
- event verdict summary;
- chord-pair stats;
- timing histogram;
- attempt history;
- active config.

Output:

- primary insight;
- secondary insight;
- recommended next action;
- optional adaptive suggestion.

## 17.2 Példák

```text
A legtöbb ütésed későn érkezett.
Gyakorold újra 10 BPM-mel lassabban.

A ritmusod stabil, de a felpengetések 34%-a hibás volt.
Ismételd csak a második fél ütemeket.

A G -> D váltás volt a leglassabb.
Indíts Chord Change gyakorlatot ezzel a párral.
```

A dokumentált insight mögött legyen mérési szabály. Tilos véletlenszerű vagy bizonyíték nélküli coaching szöveget adni.

## 17.3 Insight prioritás

Javasolt sorrend:

1. nincs elegendő signal;
2. alacsony completion;
3. domináns early/late bias;
4. direction hiba;
5. chord hiba;
6. konkrét chord-pair probléma;
7. tempó túl magas;
8. pozitív megerősítés;
9. következő nehézség.

---

# 18. Adaptív nehézség

## 18.1 Alapelv

A rendszer aktív attempt közben ne változtassa meg csendben a targetet vagy a BPM-et.

Adaptáció csak:

- attempt után;
- user által elfogadott bannerrel;
- vagy előre bekapcsolt Auto Speed Builder policyvel történhet.

## 18.2 Javaslatok

Lehetséges suggestion:

- csökkentsd a BPM-et;
- válts Easy variationre;
- gyakorolj rövidebb loopot;
- kapcsold be a metronómot;
- fókuszálj csak directionre;
- fókuszálj csak chord changesre;
- emeld a BPM-et;
- lépj tovább.

## 18.3 Pure decision policy

```dart
abstract interface class AdaptivePracticePolicy {
  AdaptiveSuggestion? evaluate({
    required PracticeAttemptResult current,
    required List<PracticeAttemptResult> history,
    required PracticeSessionConfig config,
  });
}
```

A policy tesztjei ne használjanak UI-t vagy storage-t.

---

# 19. Speed Builder specifikáció

## 19.1 Konfiguráció

```dart
final class SpeedBuilderPolicy {
  const SpeedBuilderPolicy({
    required this.startBpm,
    required this.targetBpm,
    required this.stepBpm,
    this.requiredConsecutivePasses = 2,
    this.maxAttempts = 20,
    this.reduceAfterConsecutiveFails = 2,
  });
}
```

Validáció:

- start BPM pozitív;
- target BPM legalább start BPM;
- step 1 és 20 BPM között;
- maxAttempts 1 és 100 között;
- a definition támogatja a kiválasztott tempót.

## 19.2 Determinisztikus policy

Alapértelmezett algoritmus:

1. Indulás `startBpm` értéken.
2. Pass esetén success streak növekszik.
3. Két egymást követő pass után BPM nő `stepBpm` értékkel.
4. Fail esetén success streak nullázódik.
5. Két egymást követő fail után BPM csökken egy steppel, de start BPM alá nem megy.
6. Target BPM-en elért szükséges consecutive pass esetén completed.
7. Max attempt vagy user finish esetén session lezárul.

## 19.3 Highest stable BPM

A legmagasabb stabil BPM az a tempó, amelyen a felhasználó teljesítette a step-up pass policyt.

Egyetlen szerencsés attempt nem számít stabilnak.

## 19.4 UX

A session UI mutassa:

- current BPM;
- target BPM;
- sikeres attempt streak;
- következő step;
- attempt szám;
- legmagasabb stabil BPM.

A BPM-váltás két attempt között történjen. Aktív attempt közben a clock ne változtassa meg a tempót.

---

# 20. Perzisztencia és progress

## 20.1 Új Practice History

A meglévő `PracticeEntry` adatokat meg kell őrizni. Nem szabad azonnal destruktívan lecserélni.

Javasolt új verzió:

```text
practice_history_v2
```

A V2 session summary tartalmazza:

- schema version;
- session ID;
- definition ID;
- definition version;
- source;
- mode;
- startedAt UTC;
- local epoch day;
- active seconds;
- total seconds;
- attempt count;
- completed;
- best overall;
- best rhythm;
- best direction;
- best chord;
- highest stable BPM;
- total targets;
- total strums;
- chord set;
- skill tags;
- config summary.

## 20.2 Részletes verdict tárolása

Minden event verdict korlátlan tárolása túl nagy lenne.

Alapértelmezett policy:

- session summary tartósan tárolható;
- utolsó N session részletes attempt summaryt tárolhat;
- nyers audio soha nem tárolódik automatikusan;
- event-level részletek csak korlátozott, verziózott formában;
- storage cap és migráció tesztelt.

## 20.3 Legacy migráció

A `PracticeEntry` V1 rekordok:

- maradjanak olvashatók;
- progress aggregációban jelenjenek meg;
- ne kapjanak kitalált rhythm vagy chord score-t;
- directionAccuracy csak ott legyen available, ahol valóban rendelkezésre áll;
- source enum meglévő neveit nem szabad átnevezni.

Javasolt stratégia:

- V1 repository olvasó megmarad;
- V2 history külön store;
- stats layer egyesíti a két forrást;
- később opcionális one-way migration.

## 20.4 Daily goal

A napi célhoz hozzáadandó idő:

```text
valid active practice duration
```

Ne számítson:

- pause;
- setup;
- result screen;
- permission dialog;
- üres, signal nélküli session;
- 3 másodperces véletlen indítás.

## 20.5 Streak eligibility

Egy session akkor számítson valódi practice momentnek, ha legalább az egyik igaz:

```text
active duration >= 20 seconds
or resolved required targets >= 4
or free-practice detected strums >= 8
```

Ezzel a jelenlegi rövid first-win továbbra is számíthat, de egy véletlen mikrofonindítás nem.

A streak frissítése idempotens maradjon napon belül.

## 20.6 Skill tags

A definition skill tageket tartalmazhat:

```text
rhythm.quarter_notes
rhythm.eighth_notes
rhythm.syncopation
strum.down
strum.alternating
chord.em
chord.g
chord_change.g_d
meter.three_four
```

Epic 2 alatt ezek egyszerű progress aggregációhoz használhatók. Nem kell AI mastery modellt építeni.

---

# 21. UI specifikáció

## 21.1 Practice Hub

Fő blokkok:

1. Continue Practice;
2. Quick Start;
3. Practice Modes;
4. Daily Challenge;
5. Recent Practices;
6. Speed Builder;
7. Progress shortcut.

A hub ne legyen zsúfolt. A fő CTA a legvalószínűbb következő gyakorlást indítsa.

## 21.2 Practice Setup Screen

Megjelenítendő:

- gyakorlat neve;
- rövid cél;
- chordok;
- pattern;
- meter;
- BPM;
- becsült idő;
- pontozott dimenziók;
- difficulty;
- count-in;
- metronóm;
- loop;
- Speed Builder.

A Start gomb előtt a UI validálja a configot, de a domain validator maradjon a végső forrás.

## 21.3 Practice Session Screen

Kötelező részek:

- top status/HUD;
- target highway vagy mode-specifikus view;
- current és next chord;
- chord diagram, ha releváns;
- direction target;
- strike line;
- count-in overlay;
- score/combo;
- input indicator;
- pause/continue control;
- exit control;
- Speed Builder progress, ha aktív.

A screen ne tartalmazzon session business logicot. Csak state-et renderel és commandot küld.

## 21.4 Mode-specifikus view

- Strum Pattern: egybaros pattern és gördülő highway.
- Chord Changes: nagy current/next chord, change timer és stability feedback.
- Chord Progression: highway, chord diagram, upcoming bars.
- Rhythm Only: egyszerű beat lane, minimal chord UI.
- Free Practice: élő metrics, nincs target lane és nincs score.

## 21.5 Result Screen

Csak alkalmazható részek jelenjenek meg.

Kötelező blokkok scored practice esetén:

- overall score;
- completion;
- rhythm;
- direction;
- chord;
- max combo;
- average timing offset;
- early/late bias;
- strongest point;
- improvement point;
- retry;
- slower;
- Speed Builder;
- next practice.

Free Practice esetén:

- duration;
- strums;
- average detected BPM;
- consistency;
- chord summary;
- down/up distribution;
- nincs overall accuracy.

## 21.6 Hibaállapotok

Felhasználóbarát UI szükséges:

- microphone permission denied;
- microphone busy;
- audio engine unavailable;
- no input signal;
- detector initialization failure;
- corrupted practice definition;
- storage write failure;
- session interrupted by app lifecycle.

A recoverable hiba ne dobja ki automatikusan a sessionből a felhasználót.

---

# 22. Accessibility, localization és UX-szabályok

## 22.1 Accessibility

- A down/up külön szöveges vagy ikonjelölést is kapjon.
- A jelentés ne csak színre épüljön.
- Minimum 48x48 dp touch target.
- Reduced motion módban a highway alternatív statikus beat cursor nézetet kaphat.
- Screen reader ne olvassa fel az összes frame-et.
- Csak lényeges esemény legyen live-region announcement.
- Pause és Exit mindig elérhető legyen.
- Haptika kikapcsolható legyen.
- A progress chartok rendelkezzenek semantics summaryval.
- Landscape és nagy betűméret esetén ne legyen clipping.

## 22.2 Left-handed mód

A fizikai down/up direction jelentése nem változik balkezes módban.

A UI vizuális orientációja tükrözhető, de a scorer target directionje nem invertálható automatikusan.

## 22.3 Localization

Minden user-facing string ARB fájlban legyen.

Nem kerülhet domainbe:

- angol title;
- coaching mondat;
- hibaüzenet;
- score label.

A coaching code-hoz localization mapping szükséges angol és magyar nyelven.

## 22.4 Visszajelzési intenzitás

A UI ne büntesse agresszívan a kezdőt.

- extra strum beginner módban ne villanjon piros hibának;
- confidence-probléma ne jelenjen meg játékosi hibaként;
- a result legalább egy pozitív, tényalapú insightot adjon;
- az Easy mód használata ne csökkentse a streaket;
- Easy score ne írja felül a full lesson stars eredményét.

---

# 23. Adatvédelem

- Minden scoring on-device történik.
- Nyers mikrofonadat nem hagyhatja el az eszközt.
- Nyers audio nem tárolható automatikusan.
- Lab diagnostics csak az Epic 1 szabályai szerint működhet.
- Practice history nem tartalmaz tokent vagy e-mailt.
- Session ID nem tartalmaz személyes adatot.
- Logban nem jelenhet meg teljes nyers observation stream.
- User-created song név logolásakor privacy redaction megfontolandó.

---

# 24. Teljesítménykövetelmények

## 24.1 Real-time útvonal

A hot path:

```text
LiveFrame
  -> observation adapter
  -> event matcher
  -> incremental scorer
  -> state snapshot
  -> UI render
```

Követelmények:

- event matching ne legyen teljes lista O(n) scan minden frame-re nagy targetnél;
- csak új observation indítson strum verdict számítást;
- chord frame sampling legyen ritkított;
- scorer snapshot immutable, de ne másolja minden frame-en a teljes verdict listát;
- UI csak szükséges slice-okat figyeljen Riverpod selecttel;
- audio/DSP ne kerüljön a UI isolate-ra;
- session végén történhet részletes aggregáció.

## 24.2 Célértékek

Elsődleges célok középkategóriás Android készüléken:

- session command response: 100 ms alatt, audio start kivételével;
- új strum feedback: a frame megérkezésétől 50 ms alatt;
- 60 FPS cél a highway alatt;
- 10 perces session alatt nincs folyamatos memóriaemelkedés;
- verdict history memóriája bounded;
- pause után mikrofon és subscription policy szerint felszabadul;
- finish után nincs aktív ticker, stream vagy wakelock.

A konkrét baseline az Epic 1 mérési rendszerével dokumentálandó.

---

# 25. Tesztelési stratégia

## 25.1 Domain unit tesztek

- BeatPosition;
- Meter;
- Tempo;
- definition validation;
- target compiler;
- timing windows;
- matcher;
- chord stability;
- dimension scores;
- overall weights;
- pass policy;
- combo;
- Speed Builder;
- adaptive suggestions;
- coaching priority;
- persistence serialization.

## 25.2 Property tesztek

Invariánsok:

- score mindig 0 és 1 között;
- target legfeljebb egyszer resolved;
- observation legfeljebb egyszer matched;
- resolved count nem csökken;
- playhead pause alatt nem nő;
- resume után nincs időugrás;
- empty target nem crashel;
- random observation sorrend normalizálható;
- serialization roundtrip veszteségmentes;
- Speed Builder soha nem lépi túl a target BPM-et;
- BPM soha nem megy start alá;
- optional event nem csökkenti completiont;
- Free Practice nem generál overall accuracyt.

## 25.3 Fixture parity tesztek

A jelenlegi `LessonScorer` és új compatibility profile ugyanazokra a fixture-ökre adjon azonos eredményt:

- hit;
- wrong direction;
- miss;
- perfect/good/early/late;
- combo;
- max combo;
- input latency;
- chord lag tolerance;
- de-jitter;
- Easy lesson;
- 3/4 count-in;
- Analyze import.

Dokumentált eltérés csak külön ADR-rel fogadható el.

## 25.4 Widget tesztek

- Practice Hub;
- Setup validation;
- permission state;
- count-in;
- pause/resume;
- feedback;
- Speed Builder state;
- result dimension visibility;
- Free Practice result;
- large text;
- localization;
- semantics.

## 25.5 Integration tesztek

Fake observation gateway használatával:

- teljes strum-pattern session;
- chord-change session;
- pause/resume;
- app lifecycle interruption;
- retry;
- Speed Builder több attempt;
- persistence;
- streak eligibility;
- daily-goal update;
- migrated lesson;
- migrated song;
- no-network guarantee.

## 25.6 Valós eszközös ellenőrzés

Legalább:

- akusztikus gitár;
- elektromos gitár erősítőn, ésszerű hangerőn;
- csendes környezet;
- mérsékelt háttérzaj;
- 3/4 lesson;
- 4/4 pattern;
- 50%, 75%, 100% speed;
- Bluetooth audio nélkül és opcionálisan Bluetooth outputtal;
- permission denial;
- háttérbe küldés;
- 10 perces session.

---

# 26. Codex végrehajtási szabályok

Minden kör elején add át a Codexnek:

1. Olvasd el az `AGENTS.md` fájlt.
2. Olvasd el a Chapter 1, Chapter 2 és Chapter 3 releváns részeit.
3. Vizsgáld meg az érintett production fájlokat és teszteket.
4. Csak az aktuális kört implementáld.
5. Ne kezdd el a következő kört.
6. A régi Learn működést ne töröld feature flag és parity nélkül.
7. Ne módosíts DSP vagy ML thresholdot külön mérés nélkül.
8. Ne vezess be új package-et, ha pure Darttal vagy meglévő dependencyvel megoldható.
9. Ne használj code generationt külön architekturális döntés nélkül.
10. Minden business logikához írj unit tesztet.
11. Minden bugfixet reprodukáló teszt előzzön meg.
12. Ne helyezz scoring logikát widgetbe.
13. Ne olvass közvetlenül SharedPreferences-t az új feature-ben.
14. Ne példányosíts közvetlenül StrumEngine-t vagy Dio-t.
15. Ne használj wall clockot scoringhoz.
16. Ne nyeld el az exceptiont.
17. Futtasd a körhöz előírt teszteket külön parancsokban.
18. Frissítsd a `HANDOFF.md` fájlt.
19. A kör végén adj változáslistát, teszteredményt és kockázatlistát.
20. A PR maradjon kicsi és review-zható. Ha a kör túl nagy, bontsd további, számozott sub-commitokra ugyanazon körön belül.

Branch minta:

```text
codex/epic-02-round-01-practice-baseline
codex/epic-02-round-02-domain-time
codex/epic-02-round-03-domain-models
```

---

# 27. Fejlesztési körök

# Kör 1 — Practice baseline, ADR és feature flag

## Cél

A meglévő Learn viselkedés rögzítése, az Epic 2 határainak dokumentálása és biztonságos rollout alap létrehozása.

## Feladatok

### 1.1 Dokumentáció

Hozd létre:

```text
docs/sdd/03-epic-02-practice-engine.md
docs/adr/0005-practice-engine-v2.md
docs/adr/0006-practice-tick-time-model.md
docs/adr/0007-practice-gradual-learn-migration.md
```

### 1.2 Feature flagek

Az Epic 1 config rendszerében:

```text
practiceEngineV2Enabled
migratedLearnEnabled
practiceDetailedHistoryEnabled
```

Alapértelmezés:

- development: V2 bekapcsolható;
- test: explicit override;
- production: rollout döntésig kikapcsolt migrated Learn.

### 1.3 Baseline fixture készlet

Hozz létre stabil fixture-öket a jelenlegi LessonScorerhez:

- 4/4 basic pattern;
- 3/4 waltz;
- all perfect;
- all late;
- wrong direction;
- extra strums;
- chord lag;
- input latency;
- frame de-jitter;
- pause/restart releváns screen behavior.

### 1.4 Baseline report

```text
docs/baseline/epic-02-practice-start.md
```

Tartalmazza:

- jelenlegi lesson count;
- scoring konstansok;
- speed options;
- progress schema;
- practice log cap;
- current screen responsibilities;
- kapcsolódó tesztek;
- real-device ismert viselkedés.

## Kötelező tesztek

```bash
flutter analyze lib/ test/
flutter test test/features/learn
flutter test test/features/progress
flutter test test/features/streak
flutter test test/features/metronome
```

## Elfogadási feltételek

- baseline dokumentált;
- nincs production viselkedésváltozás;
- feature flagek tesztelhetők;
- fixture-k stabilak;
- régi Learn tesztek zöldek.

## Javasolt commit

```text
chore(practice): establish Epic 2 baseline and rollout guards
```

---

# Kör 2 — BeatPosition, Tempo és Meter értékobjektumok

## Cél

A Practice domain pontos, pure Dart zenei időalapjának létrehozása.

## Új fájlok

```text
lib/features/practice/domain/model/beat_position.dart
lib/features/practice/domain/model/tempo.dart
lib/features/practice/domain/model/meter.dart
lib/features/practice/domain/model/practice_validation.dart
test/features/practice/domain/beat_position_test.dart
test/features/practice/domain/tempo_test.dart
test/features/practice/domain/meter_test.dart
```

## Feladatok

- implementáld a 480 PPQ tick modellt;
- biztosíts biztonságos factorykat negyedhez, nyolcadhoz, tizenhatodhoz és triolához;
- implementálj összehasonlítást és alapműveleteket;
- validáld a tempót;
- validáld a meter értékeket;
- készíts legacy double-beat conversion helpert;
- dokumentáld a conversion tolerance-t;
- ne importálj Fluttert.

## Kötelező tesztek

- exact fractions;
- roundtrip;
- negative beat rejection;
- sort order;
- invalid BPM;
- 3/4 és 4/4;
- legacy `0.5`, `1.0`, `1.5` conversion;
- triola precision.

## Elfogadási feltételek

- minden zenei target idő integer tick;
- nincs `double` equality alapú event pozíció az új domainben;
- domain Flutter-független;
- tesztek zöldek.

## Javasolt commit

```text
feat(practice): add deterministic musical time value objects
```

---

# Kör 3 — Practice domain modellek és validáció

## Cél

A gyakorlat, config, observation, verdict, metrics, attempt és session kanonikus modelljeinek létrehozása.

## Feladatok

Implementáld:

- PracticeMode;
- PracticeSource;
- PracticeDifficulty;
- PracticeEvent;
- PracticeDefinition;
- PracticeSessionConfig;
- PracticeObservation hierarchy;
- PracticeVerdict;
- MetricValue;
- PracticeMetrics;
- PracticeAttemptResult;
- PracticeSessionResult;
- ScoringProfile;
- finish reason;
- stable IDs.

A modellek:

- immutable-ek;
- explicit copyWithot csak ott kapjanak, ahol valóban kell;
- egyértelmű equalityvel rendelkezzenek;
- ne tartalmazzanak UI textet;
- ne importáljanak storage vagy Riverpod osztályt.

## Validáció

- duplicate event ID;
- unsorted event list;
- event totalBeatsen kívül;
- üres scored target;
- invalid chord label;
- invalid confidence;
- invalid metric range;
- incompatible scoring weights;
- invalid session config.

## Elfogadási feltételek

- domain modellek teljesek;
- invalid állapot factoryn keresztül nem hozható létre kontrollálatlanul;
- nincs localization a domainben;
- minden modell unit tesztelt.

## Javasolt commit

```text
feat(practice): define validated practice domain contracts
```

---

# Kör 4 — Practice catalog és beépített gyakorlatok

## Cél

Egységes gyakorlatkatalógus létrehozása kis, jól definiált starter tartalommal.

## Új elemek

```text
lib/features/practice/domain/repository/practice_catalog_repository.dart
lib/features/practice/data/builtin_practice_catalog.dart
lib/features/practice/application/practice_catalog_controller.dart
```

## Kezdeti gyakorlatok

Legalább:

1. Quarter-note Downstrokes — Em, 70 BPM;
2. Alternating Eighths — muted/any chord, 70 BPM;
3. Folk Pattern — `D - D U - U D U`, 80 BPM;
4. G to D Changes — negyedek, 60 BPM;
5. Em to C Changes — negyedek, 60 BPM;
6. C-G-Am-F Progression — egyszerű downstroke;
7. First Waltz — 3/4;
8. Syncopated Ups — intermediate;
9. Rhythm Only Quarter Notes;
10. Free Practice template.

## Követelmények

- stabil definition IDs;
- ARB title és description kulcs;
- skill tags;
- difficulty;
- scoring profile;
- mode-specifikus default config;
- catalog order determinisztikus;
- filter mode és difficulty szerint;
- duplicate ID teszt.

## Elfogadási feltételek

- legalább tíz valid gyakorlat;
- minden scored gyakorlat compile-olható;
- 3/4 gyakorlat helyes;
- nincs hardcoded user-facing angol szöveg a domainben;
- catalog pure és offline.

## Javasolt commit

```text
feat(practice): add the offline built-in practice catalog
```

---

# Kör 5 — Legacy adapterek: Lesson, Song, Analyze és Daily Challenge

## Cél

A meglévő tartalom PracticeDefinition formára alakítása a régi implementáció törlése nélkül.

## Új adapterek

```text
lesson_practice_adapter.dart
song_practice_adapter.dart
analyze_practice_adapter.dart
daily_challenge_practice_adapter.dart
```

## Feladatok

### Lesson adapter

- legacy beat -> tick;
- bpm;
- meter;
- events;
- direction;
- chord;
- difficulty;
- source reference;
- Easy variation.

### Song adapter

- ne hívja kötelezően a `toLesson()` metódust;
- közvetlenül, validáltan állítsa elő a definitiont;
- őrizze meg 3/4 meter támogatást;
- hibás pattern kontrollált failure.

### Analyze adapter

- strum time -> beat tick;
- BPM fallback;
- chord timeline lookup;
- empty result safe behavior;
- source reference;
- import title.

### Daily Challenge adapter

- day-stable ID;
- strum-only target;
- megfelelő rests;
- deterministic output.

## Parity tesztek

Az adapter output a meglévő `Lesson.events` szemantikával egyezzen.

## Elfogadási feltételek

- minden meglévő lesson konvertálható;
- minden valid Song konvertálható;
- Analyze empty és non-empty konvertálható;
- Daily Challenge determinisztikus;
- régi API még működik.

## Javasolt commit

```text
feat(practice): adapt existing learning content to Practice V2
```

---

# Kör 6 — Target compiler és beat-idő konverzió

## Cél

A zenei definitionből fix session target timeline készítése.

## Feladatok

- CompiledPracticeTarget modell;
- beat-to-duration conversion;
- count-in duration;
- ring-out;
- bar boundaries;
- expected chord segments;
- loop normalization;
- difficulty variation alkalmazása;
- scoring applicability meghatározása;
- target event time monotonic ellenőrzése.

## Tesztek

- 4/4;
- 3/4;
- 50%, 75%, 100% tempo;
- different BPM;
- empty Free Practice;
- one-event target;
- loop whole bars;
- invalid loop;
- count-in one és two bars;
- deterministic equality.

## Elfogadási feltételek

- nincs szétszórt beat-to-time formula;
- output determinisztikus;
- loop boundary zeneileg valid;
- target idő monotonic;
- Free Practice külön, üres targettel biztonságos.

## Javasolt commit

```text
feat(practice): compile musical definitions into timed targets
```

---

# Kör 7 — Session clock és state machine

## Cél

A teljes session lifecycle pure, tesztelhető state machine-be helyezése audiointegráció nélkül.

## Feladatok

- PracticeSessionClock interface;
- Stopwatch implementation;
- FakePracticeSessionClock;
- session status;
- commandok;
- transition reducer;
- invalid transition failure;
- active/wall/count-in/pause idő;
- attempt reset;
- resume policy;
- finish reason;
- one-shot effect model.

## Kötelező transition tesztek

- happy path;
- permission path;
- pause/resume;
- pause during count-in;
- cancel before start;
- cancel during running;
- failure and retry;
- double start;
- double finish;
- restart attempt;
- background interruption representation.

## Elfogadási feltételek

- minden transition explicit;
- pause alatt active time nem nő;
- invalid command nem rontja el a state-et;
- wall clock nem használható scoringhoz;
- UI nélkül teljesen tesztelhető.

## Javasolt commit

```text
feat(practice): implement the deterministic session state machine
```

---

# Kör 8 — Observation gateway és audio lifecycle adapter

## Cél

A meglévő StrumEngine biztonságos, Practice-specifikus observation streammé alakítása.

## Feladatok

- gateway interface;
- fake gateway;
- Live gateway;
- `strumSeq` dedup;
- engine clock lag calculation;
- chord change-point sampling;
- confidence filtering boundary;
- expected-chord forwarding;
- audio lease megszerzése;
- stop/dispose idempotencia;
- app lifecycle integration;
- gateway error mapping.

## Tesztek

- duplicate frame;
- same direction consecutive strums;
- missing engine clock;
- valid de-jitter;
- invalid lag;
- chord label change;
- no unnecessary chord spam;
- start twice;
- stop twice;
- mic busy;
- permission denied;
- stream error;
- dispose.

## Elfogadási feltételek

- új Practice kód nem figyeli közvetlenül a Live providert;
- observation monotonic;
- raw frame nem jut a domain scorerhez;
- mic lifecycle Epic 1 szabályos;
- nincs DSP-módosítás.

## Javasolt commit

```text
feat(practice): bridge live detection into practice observations
```

---

# Kör 9 — Event matcher és legacy timing parity

## Cél

Pure event matcher létrehozása a jelenlegi LessonScorer timing viselkedésének megőrzésével.

## Feladatok

- open-target cursor;
- nearest eligible event;
- tie-break rule;
- matched observation tracking;
- target window close;
- optional target;
- extra strum policy;
- out-of-order observation guard;
- finalize minden nyitott eventre;
- bounded memory.

## Parity

A `legacyLearn` scoring profile pontosan használja:

- 280 ms match window;
- 50 ms perfect;
- 120 ms good;
- extra strum ignore;
- existing input-latency semantics.

## Property tesztek

- nincs double match;
- nincs target reopen;
- resolved monoton nő;
- finalize után minden kötelező target lezárt;
- random extra strum nem okoz crash-t;
- input order normalization.

## Elfogadási feltételek

- matcher pure;
- fixture parity zöld;
- nagy targetnél cursor-alapú vagy indexelt működés;
- nincs full list scan minden frame-en.

## Javasolt commit

```text
feat(practice): add deterministic one-to-one event matching
```

---

# Kör 10 — Timing, direction és chord scorer

## Cél

A három fő score dimenzió külön, kompozícióval használható implementációja.

## Feladatok

### Timing scorer

- signed offset;
- timing grade;
- event score;
- mean absolute offset;
- early/late bias;
- consistency.

### Direction scorer

- applicable event count;
- correct/wrong/missing;
- low-confidence policy;
- expected direction feedback.

### Chord scorer

- normalized chord label;
- lag window;
- stable duration;
- correct/wrong/no-detection/unstable;
- chord-pair stats input.

### Aggregator

- mode weights;
- unavailable metric handling;
- completion gate;
- overall;
- pass;
- combo;
- point score.

## Kötelező tesztek

- minden timing boundary;
- all early;
- all late;
- unbiased;
- wrong direction;
- no direction target;
- chord lag;
- unstable chord;
- insufficient signal;
- weight normalization;
- score range;
- Free Practice no overall.

## Elfogadási feltételek

- dimenziók külön tesztelhetők;
- overall nem számol unavailable dimenzióval hamis nullát;
- legacy profile parity dokumentált;
- scorer nem importál Fluttert.

## Javasolt commit

```text
feat(practice): implement multidimensional practice scoring
```

---

# Kör 11 — PracticeSessionController orchestration

## Cél

A state machine, clock, target, gateway, scorer, metronóm és persistence boundary egy alkalmazási controllerben történő összekapcsolása.

## Feladatok

- prepare flow;
- config validation;
- permission flow;
- audio acquire;
- count-in;
- observation subscription;
- incremental score update;
- metronóm beat crossing;
- expected chord update;
- pause/resume;
- restart;
- finalize;
- error recovery;
- effect emission;
- cleanup minden terminal state-ben.

## Fontos szabályok

- controller ne használjon BuildContextet;
- controller ne navigáljon;
- controller ne írjon közvetlenül SharedPreferences-t;
- controller ne hozza létre közvetlenül a StrumEngine-t;
- finish egyszer legyen idempotensen végrehajtva;
- a result persistence külön use case-en keresztül történjen.

## Integration tesztek fake gatewayjel

- perfect session;
- wrong direction;
- chord failure;
- pause/resume;
- restart;
- cancel;
- stream failure;
- no signal;
- complete cleanup;
- expected chord sequence.

## Elfogadási feltételek

- teljes session UI nélkül végigfuttatható;
- terminal state után nincs subscription;
- finish nem duplikál history entryt;
- minden hiba AppFailure-ré alakul.

## Javasolt commit

```text
feat(practice): orchestrate complete offline practice sessions
```

---

# Kör 12 — Practice Hub és Setup UI

## Cél

A Practice feature belépési és konfigurációs felületének elkészítése scoring UI nélkül.

## Feladatok

### Practice Hub

- Continue card;
- Quick Start;
- mode cards;
- Daily Challenge adapter;
- recent history placeholder/real data boundary;
- Speed Builder entry;
- loading, empty és error state.

### Setup Screen

- BPM control;
- count-in;
- metronóm;
- loop;
- difficulty profile;
- mode-specifikus mezők;
- Speed Builder config;
- validation;
- Start command.

### Routing

- typed route arguments;
- invalid definition safe fallback;
- feature flag route.

## Widget tesztek

- catalog render;
- mode filter;
- setup defaults;
- invalid BPM;
- 3/4 display;
- Free Practice hides scoring options;
- Speed Builder validation;
- large text;
- English/Hungarian.

## Elfogadási feltételek

- Practice Hub elérhető feature flag alatt;
- nincs business logic widgetben;
- config domain validatorral egyezik;
- minden string lokalizált;
- accessibility alapok zöldek.

## Javasolt commit

```text
feat(practice): add the practice hub and session setup flow
```

---

# Kör 13 — Practice Session UI shell

## Cél

A közös session képernyő elkészítése mode-specifikus scorer nélkül.

## Feladatok

- PracticeSessionScreen;
- state renderer;
- count-in overlay;
- common HUD;
- mic state;
- pause/resume;
- cancel confirmation;
- recoverable error panel;
- input level;
- score snapshot;
- effect listener;
- haptic gateway;
- reduced motion behavior;
- app lifecycle forwarding.

## Követelmények

- ne használjon saját Ticker-based business clockot;
- animációs ticker csak renderelési interpolációra használható;
- state source a controller;
- route exit minden esetben cleanupt kér;
- system back biztonságos.

## Tesztek

- preparing;
- permission required;
- ready;
- count-in;
- running;
- paused;
- failed;
- exit;
- haptic effect;
- no duplicate navigation.

## Elfogadási feltételek

- session lifecycle teljesen state-driven;
- UI nem példányosít scorer vagy engine objektumot;
- background/foreground tesztelt;
- nincs ticker leak.

## Javasolt commit

```text
feat(practice): add the state-driven practice session shell
```

---

# Kör 14 — Strum Pattern és Chord Progression mód

## Cél

Az első teljes, production-minőségű scored practice módok elkészítése.

## Feladatok

### Strum Pattern UI

- one-bar pattern preview;
- scrolling target lane;
- down/up/rest;
- strike line;
- timing feedback;
- direction feedback;
- combo;
- optional chord diagram.

### Chord Progression UI

- current chord;
- next chord;
- upcoming bar;
- chord diagram;
- expected chord hint;
- chord verdict;
- direction és timing verdict.

### PracticeHighway

A régi LessonHighway vizuális koncepcióját újrahasznosíthatja, de:

- PracticeEventet rendereljen;
- ne importálja a Learn belső modelljét;
- visibility window legyen optimalizált;
- 3/4 és 4/4 támogatott;
- visual latency csak drawing offset.

## Tesztek

- exact target positions;
- 3/4;
- rest slots;
- same-direction consecutive events;
- current/next chord;
- expected hint;
- large target list virtualization;
- visual offset.

## Elfogadási feltételek

- két mód végigjátszható;
- score és feedback helyes;
- expected chord törlődik finishkor;
- nincs Learn belső import;
- 60 FPS célhoz nincs nyilvánvaló teljes-listás rebuild.

## Javasolt commit

```text
feat(practice): deliver strum-pattern and progression practice
```

---

# Kör 15 — Chord Change mód

## Cél

Célzott akkordváltás-gyakorlás és chord-pair elemzés.

## Feladatok

- chord pair/multi-chord definition builder;
- váltási boundaryk;
- change target window;
- chord stability scorer;
- change completion time;
- alternating és round-robin sequence;
- current/next chord UI;
- chord diagram;
- no-strum/one-strum policy;
- result chord-pair breakdown.

## Pontos metrikák

- attempts per chord pair;
- correct changes;
- median recognized-change delay;
- unstable changes;
- wrong chord count;
- no detection count;
- slowest pair.

A UI ne használja a `clean chord` kifejezést, ha csak label stability mérhető. Javasolt szöveg: `felismert és stabil akkord`.

## Tesztek

- G -> D;
- D -> G;
- multi-chord sequence;
- detection lag;
- wrong chord;
- unstable label;
- missing observation;
- low confidence;
- 3/4 boundary;
- result ranking.

## Elfogadási feltételek

- chord-pair stats determinisztikus;
- nincs hamis string-level állítás;
- result konkrét problémás váltást mutat;
- signal hiány külön állapot.

## Javasolt commit

```text
feat(practice): add measurable chord-change training
```

---

# Kör 16 — Rhythm-only és Free Practice mód

## Cél

Célakkord nélküli ritmusgyakorlás és objektív szabad session mérés.

## Rhythm-only feladatok

- chord score kikapcsolása;
- direction optional;
- target onset timing;
- timing consistency;
- extra-strum informational mode;
- muted-strum UX instruction.

## Free Practice feladatok

- target nélküli session;
- strum count;
- down/up distribution;
- chord timeline summary;
- detected BPM samples;
- tempo stability;
- active signal tracking;
- no-score result model.

## Fontos szabály

Free Practice alatt:

- nincs miss;
- nincs pass/fail;
- nincs overall accuracy;
- nincs combo, kivéve ha később külön UX indokolja;
- a rendszer ne állítsa, hogy a felhasználó jól vagy rosszul játszott cél nélkül.

## Tesztek

- no chord needed;
- direction disabled;
- no target;
- zero signal;
- short accidental session;
- valid streak eligibility;
- tempo distribution;
- no false accuracy label.

## Elfogadási feltételek

- Rhythm-only score működik chord nélkül;
- Free Practice tényszerű summaryt ad;
- daily goal csak valid active idővel nő;
- nincs hamis score.

## Javasolt commit

```text
feat(practice): add rhythm-only and honest free-practice modes
```

---

# Kör 17 — Speed Builder, loop és adaptív retry

## Cél

Több attemptes, determinisztikus tempóépítő workflow létrehozása.

## Feladatok

- SpeedBuilderPolicy validator;
- state;
- success/fail streak;
- step up;
- step down;
- target completion;
- max attempts;
- attempt history;
- loop counter;
- highest stable BPM;
- session UI progress;
- result timeline;
- adaptive slower/easy/short-loop suggestions;
- user acceptance flow.

## Tesztek

- two pass step-up;
- fail reset;
- two fail step-down;
- no below start;
- no above target;
- target completion;
- max attempt stop;
- user cancel;
- mixed attempts;
- stable BPM definition;
- suggestion priority.

## Elfogadási feltételek

- policy pure és determinisztikus;
- BPM csak attempt boundaryn változik;
- controller nem veszít attempt resultot;
- UI egyértelműen jelzi a változást;
- score threshold profile-ból jön.

## Javasolt commit

```text
feat(practice): add deterministic speed building and adaptive retry
```

---

# Kör 18 — Result, coaching és session history

## Cél

Részletes, tényalapú eredményképernyő és verziózott history persistence.

## Feladatok

### Result UI

- mode-specifikus score breakdown;
- completion;
- timing histogram/bias;
- direction breakdown;
- chord breakdown;
- chord-pair stats;
- Speed Builder summary;
- coaching insight;
- next actions;
- retry;
- slower;
- next definition;
- share boundary, tényleges implementáció nélkül vagy meglévő share adapterrel.

### PracticeCoach

- insight rules;
- priority;
- minimum evidence;
- positive insight;
- localization codes.

### History

- PracticeHistoryRepository;
- V2 serializer;
- schema version;
- cap;
- corruption isolation;
- V1/V2 aggregation;
- idempotent session save;
- no duplicate finish record.

## Tesztek

- each mode visibility;
- unavailable dimension hidden;
- insufficient signal;
- all early;
- all late;
- weak direction;
- weak chord pair;
- positive result;
- serialization roundtrip;
- corrupted record;
- cap;
- duplicate save.

## Elfogadási feltételek

- minden insight mérésből származik;
- unavailable metric nem jelenik meg 0%-ként;
- history adatvesztés nélkül olvasható;
- finish idempotens;
- Free Practice result külön layout.

## Javasolt commit

```text
feat(practice): persist sessions and provide evidence-based coaching
```

---

# Kör 19 — Progress, streak, daily goal és Learn migráció

## Cél

Az új Practice Engine integrálása a meglévő retention és curriculum rendszerekkel, majd a Learn fokozatos átkapcsolása.

## Feladatok

### Progress

- V1 és V2 stats aggregation;
- active minutes;
- mode breakdown;
- rhythm/direction/chord trend;
- highest stable BPM;
- skill tags;
- recent sessions.

### Streak

- eligibility use case;
- idempotent napi frissítés;
- short first-win támogatás;
- cancelled/empty session kizárása.

### Daily goal

- active time;
- no pause/count-in;
- V1 compatibility.

### Learn migráció

Feature flag mögött:

- Lesson adapter;
- Practice Setup bypass vagy lesson-specifikus default;
- Practice Session Screen;
- legacy stars szemantika;
- Easy score ne írja felül full score-t;
- Continue és Next Lesson CTA;
- Daily Challenge flow;
- Song play flow;
- Analyze practice flow.

### Rollback

A feature flag kikapcsolásakor a régi LearnScreen továbbra is működjön a rollout időszakban.

## Parity tesztek

- lesson score;
- stars;
- pass;
- easy mode;
- next lesson;
- 3/4 count-in;
- practice log;
- streak;
- wrapped data;
- expected chord;
- input/visual latency.

## Elfogadási feltételek

- V2 session frissíti a progresszt;
- streak egyszer frissül;
- daily goal helyes;
- migrated Learn parity elfogadott;
- rollback lehetséges;
- régi adatok megmaradnak.

## Javasolt commit

```text
refactor(learn): migrate learning flows onto Practice Engine V2
```

---

# Kör 20 — Accessibility, teljesítmény, regresszió és Epic lezárás

## Cél

A Practice Engine production readiness ellenőrzése és dokumentált lezárása.

## Feladatok

### Accessibility

- semantics audit;
- 200% text scale;
- minimum touch target;
- color-independent verdict;
- reduced motion;
- screen reader summary;
- chart semantics;
- landscape.

### Localization

- angol-magyar parity;
- coaching codes;
- errors;
- pluralization;
- BPM és százalék formázás.

### Performance

- frame timing;
- controller state update rate;
- observation throughput;
- memory 10 perces session alatt;
- cleanup;
- large target;
- history cap.

### Regresszió

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
flutter test test/property
dart run tool/check_architecture.dart
```

Backend csak akkor futtatandó, ha az Epic módosította:

```bash
cd backend
python -m ruff check app tests
python -m pytest -q
```

### Valós eszköz

Dokumentáld a 25.6 fejezet tesztmátrixát.

### Dokumentáció

Hozd létre:

```text
docs/sdd/epic-02-completion-report.md
docs/manual-testing/practice-engine-device-matrix.md
```

Frissítsd:

- README;
- HANDOFF;
- SDD index;
- architecture diagram;
- feature flag állapot;
- known limitations.

## Elfogadási feltételek

- minden CI zöld;
- nincs mic/ticker/subscription leak;
- nincs network request offline practice alatt;
- performance nem romlott indokolatlanul;
- accessibility audit lezárt;
- Hungarian/English parity zöld;
- migrated Learn rollout döntés dokumentált;
- Epic completion report elkészült.

## Javasolt commit

```text
docs(practice): close Epic 2 Practice Engine delivery
```

---

# 28. Epic 2 végső Definition of Done

Az Epic 2 csak akkor tekinthető befejezettnek, ha minden alábbi követelmény teljesül.

## Architektúra

- [ ] Létezik külön Practice feature.
- [ ] A domain pure Dart.
- [ ] A zenei pozíció integer tick alapú.
- [ ] A session explicit state machine-t használ.
- [ ] A UI nem tartalmaz scorer logikát.
- [ ] Az audio observation gateway mögött van.
- [ ] A persistence repository mögött van.
- [ ] Az új feature nem importál más feature belső presentation vagy provider fájlt.

## Session lifecycle

- [ ] Prepare, permission, count-in, run, pause, resume, restart, finish és cancel működik.
- [ ] Pause alatt nincs pontozás.
- [ ] Resume nem ugrik időben.
- [ ] Finish idempotens.
- [ ] Terminal state után minden erőforrás felszabadul.
- [ ] App background viselkedés tesztelt.

## Pontozás

- [ ] Egy target legfeljebb egyszer párosítható.
- [ ] Egy observation legfeljebb egyszer használható.
- [ ] Timing külön metrika.
- [ ] Direction külön metrika.
- [ ] Chord külön metrika.
- [ ] Unavailable dimenzió nem jelenik meg 0%-ként.
- [ ] Free Practice nem generál hamis accuracyt.
- [ ] Early/late bias számolható.
- [ ] Chord-pair probléma azonosítható.
- [ ] Legacy Learn parity dokumentált.

## Gyakorlási módok

- [ ] Strum Pattern működik.
- [ ] Chord Changes működik.
- [ ] Chord Progression működik.
- [ ] Rhythm Only működik.
- [ ] Free Practice működik.
- [ ] Speed Builder működik.
- [ ] 3/4 és 4/4 támogatott.
- [ ] Loop működik.

## Integráció

- [ ] Built-in catalog működik.
- [ ] Lesson adapter működik.
- [ ] Song adapter működik.
- [ ] Analyze adapter működik.
- [ ] Daily Challenge adapter működik.
- [ ] Progress V1 és V2 együtt olvasható.
- [ ] Daily goal aktív időből számol.
- [ ] Streak eligibility helyes.
- [ ] Easy mód nem írja felül a full lesson stars eredményét.

## Minőség

- [ ] Unit tesztek zöldek.
- [ ] Property tesztek zöldek.
- [ ] Widget tesztek zöldek.
- [ ] Integration tesztek zöldek.
- [ ] Architecture guard zöld.
- [ ] Format és analyze zöld.
- [ ] Valós eszközös teszt dokumentált.
- [ ] Nincs ismert audio resource leak.
- [ ] Nincs korlátlan history vagy verdict memória.
- [ ] Minden user-facing string lokalizált.
- [ ] Accessibility követelmények teljesülnek.

---

# 29. Az Epic eredménye

Az Epic 2 végére a StrumSight rendelkezik egy olyan közös gyakorlómotorral, amely:

- a jelenlegi on-device audiointelligenciát tanításra használja;
- több különböző gyakorlási módot kezel;
- valós időben értékeli a ritmust, a pengetési irányt és az akkordot;
- megkülönbözteti a korai és késői játékot;
- konkrét, mérésalapú coachingot ad;
- biztonságosan kezeli a mikrofont és a session lifecycle-t;
- támogatja a tempóépítést és a loopos ismétlést;
- megőrzi a felhasználói progresszt;
- teljesen offline működik;
- közös alapot ad a Learn, Songs, Daily Challenge és Analyze gyakorlásához;
- előkészíti a következő nagy modult.

Az Epic 2 lezárása után kezdhető el:

```text
Chapter 4 — Epic 3: Song Trainer
```
