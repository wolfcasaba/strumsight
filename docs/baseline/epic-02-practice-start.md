# Epic 2 practice baseline — a legacy Learn kiinduló állapota

**Felvéve:** 2026-07-30 (E02-R01)<br>
**Production-kód alapja:** `main@90c0996`; a kör dokumentációs előkészítése:
`27ef496`<br>
**Cél:** a működő `LearnScreen` + `LessonScorer` út mérhető kiindulópontja,
nem új pontozási specifikáció

Az E02-R01 a legacy Learn production kódját nem módosítja. A viselkedési
baseline a befagyasztott
`test/fixtures/practice/legacy_scorer_baseline.json`, a determinisztikus
bemenet pedig `test/support/practice_baseline_scenarios.dart`. Eltérés csak az
[ADR 0067](../adr/0067-practice-gradual-learn-migration.md) szerint fogadható
el.

## Rollout-guard állapot

A korábbi három availability flag mellé három practice flag került. A direkt
`FeatureFlags` konstruktorban mindhárom opcionális és `false` az alapja
(`lib/app/config/feature_flags.dart:11-18`), ezért a hét korábbi direkt
konstruktorhívás érintetlen maradt: hat `const` hívás
(`test/app/app_config_test.dart:116-120,131-135,146-150,161-165,185-189`;
`test/app/app_bootstrap_test.dart:203-207`) és egy nem-`const` direkt hívás
(`test/features/diagnostics/diagnostics_providers_test.dart:24-28`).

| Flag | development | lab | production |
|---|---:|---:|---:|
| `practiceEngineV2Enabled` | `true` | `true` | `false` |
| `migratedLearnEnabled` | `false` | `false` | `false` |
| `practiceDetailedHistoryEnabled` | `true` | `true` | `false` |

A táblát a `nonProd`-származtatás és az explicit migrációs alap adja
(`lib/app/config/feature_flags.dart:32-44`). A két függőség
`migratedLearnEnabled ⇒ practiceEngineV2Enabled` és
`practiceDetailedHistoryEnabled ⇒ practiceEngineV2Enabled`; mindkettő külön
problémaként gyűlik, majd a config egyszer dob
(`lib/app/config/app_config.dart:112-124,168`).

A practice flagek nem hálózati kapcsolók: `usesNetwork` továbbra is kizárólag
`accountEnabled || diagnosticsEnabled`
(`lib/app/config/feature_flags.dart:66-67`). Így minden practice flag lehet
bekapcsolva üres API URL mellett is, ha a két függőség teljesül.

## Tartalom- és időmodell

- **16 tantervi lecke** van (`lib/features/learn/model/lesson.dart:321-338`),
  plusz a tanterven kívüli onboarding `firstWin`
  (`lib/features/learn/model/lesson.dart:142-152`).
- A 16-ból **2 lecke 3/4-es**: `firstWaltz`
  (`lib/features/learn/model/lesson.dart:202-212`) és `waltzTime`
  (`lib/features/learn/model/lesson.dart:266-276`). A konstruktor alapja 4/4
  (`lib/features/learn/model/lesson.dart:40-49`).
- `LessonEvent.beat` ma `double`
  (`lib/features/learn/model/lesson.dart:13-24`). A pattern-expander
  beat-enként két slotot, azaz `beatsPerBar * 2` hosszú pattern-t vár, és
  `slot * 0.5` pozíciókat képez
  (`lib/features/learn/model/lesson.dart:74-100`).
- Az Easy-vágás pontos lebegőpontos maradékra épül:
  `e.beat % 1.0 == 0` (`lib/features/learn/model/lesson.dart:103-120`).
- Külső lesson-forrás az Analyze adapter
  (`lib/features/learn/model/lesson.dart:358-390`) és a Daily Challenge
  (`lib/features/learn/model/lesson.dart:399-414`).

Ezt a `double`/nyolcad-grid modellt az E02-R02 integer 480 PPQ modellje váltja
ki; a legacy átalakítás auditált határa az E02-R05.

## Legacy scorer contract

A `LessonScorer` 343 soros pure scorer, saját clock és IO nélkül
(`lib/features/learn/lesson_scorer.dart:71-93,323-343`).

| Érték | Legacy konstans | Forrás |
|---|---:|---|
| scorer count-in alap | `4 beat` | `lib/features/learn/lesson_scorer.dart:77-85` |
| match window | `±0.28 s` | `lib/features/learn/lesson_scorer.dart:79-80,243-260` |
| perfect window | `±0.05 s` | `lib/features/learn/lesson_scorer.dart:81,188-195` |
| good window | `±0.12 s` | `lib/features/learn/lesson_scorer.dart:82,188-195` |
| input-latency alap | `0 s` | `lib/features/learn/lesson_scorer.dart:83,98-103` |
| chord-lag mintapont | `+0.37 s` | `lib/features/learn/lesson_scorer.dart:115-117,220-235` |
| pont perfect/good/off-beat | `100 / 70 / 40` | `lib/features/learn/lesson_scorer.dart:136-139,269-280` |
| combo tierek | `5→×2, 10→×3, 20→×4` | `lib/features/learn/lesson_scorer.dart:141-148` |
| Easy-javaslat | `failStreak >= 4` | `lib/features/learn/lesson_scorer.dart:154-161` |
| pass | `total > 0 && accuracy >= 0.7` | `lib/features/learn/lesson_scorer.dart:163-169` |

Mért szemantika:

- a legközelebbi nyitott event nyer; pontos távolságholtnál a korábbi
  listapozíció, mert az összehasonlítás szigorúan `d < bestDelta`
  (`lib/features/learn/lesson_scorer.dart:251-262`);
- egy observation legfeljebb egy eventet fogyaszt, az extra strum `null` és nem
  bont combót (`lib/features/learn/lesson_scorer.dart:243-262`);
- wrong direction elfogyasztja az eventet, növeli a fail streaket, nullázza a
  combót és megőrzi az elvárt irányt
  (`lib/features/learn/lesson_scorer.dart:281-289`);
- az input latency a strumra, chord-observationre és a miss-záró órára is
  alkalmazódik (`lib/features/learn/lesson_scorer.dart:197-204,248-250,292-310`);
- a chord külön, másodlagos számláló. A strum verdictet nem gátolja; a célakkord
  csak a stroke pillanatában vagy pontosan `stroke + 0.37 s`-nél mintázódik
  (`lib/features/learn/lesson_scorer.dart:220-237`);
- a combo a pontszámítás előtt nő, ezért már az 5. perfect hit ×2-t ér
  (`lib/features/learn/lesson_scorer.dart:263-280`);
- `finalize()` minden nyitott eventet missre zár és minden chordot kiértékel
  (`lib/features/learn/lesson_scorer.dart:313-322`).

## Befagyasztott fixture-mérés

Minden 4/4 fixture 60 BPM-es, negyedes, 8 eventes adatsor; a 3/4 eset a valódi
`Lessons.firstWaltz`, 76 BPM és 12 event. A count-in minden esetben
`lesson.beatsPerBar`, a de-jitter fixture pedig már a képernyő által korrigált
időbélyeget adja a scorernek. A replay ettől külön kezeli a frame dispatch
idejét: előbb a `frameArrivalSec` órán advance-el, majd a korrigált
strum-idővel regisztrál, ahogy a ticker és `_onFrame` külön órája működik
(`test/features/learn/legacy_scorer_baseline_test.dart:169-185,380-405`). A
golden a következő végállapotot rögzíti:

| Scenario | hit / wrong / miss | combo / max | perfect | score | mult | chord | accuracy | pass | fail streak |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `p44_basic_all_perfect` | 8 / 0 / 0 | 8 / 8 | 8 | 1200 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p44_all_late` | 8 / 0 / 0 | 8 / 8 | 0 | 480 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p44_timing_tiers` | 7 / 0 / 1 | 0 / 7 | 2 | 550 | 1 | 8 / 8 | 0.875 | igen | 1 |
| `p44_wrong_direction` | 5 / 3 / 0 | 0 / 5 | 5 | 600 | 1 | 8 / 8 | 0.625 | nem | 3 |
| `p44_extra_strums` | 8 / 0 / 0 | 8 / 8 | 8 | 1200 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p44_chord_lag` | 8 / 0 / 0 | 8 / 8 | 8 | 1200 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p44_input_latency` | 8 / 0 / 0 | 8 / 8 | 8 | 1200 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p44_dejittered` | 8 / 0 / 0 | 8 / 8 | 8 | 1200 | 2 | 8 / 8 | 1.000 | igen | 0 |
| `p34_waltz` | 9 / 1 / 2 | 1 / 5 | 4 | 700 | 1 | 12 / 12 | 0.750 | igen | 0 |

A golden a végállapot mellett event-index szerint a `HitResult`, `Timing` és
wrong-direction esetén az elvárt irány sorozatát is tárolja. Az indexet egy
független, befagyasztott legacy matcher vezeti; az input target-annotációt
ellenőrzi, de nem abból írja a verdictet
(`test/features/learn/legacy_scorer_baseline_test.dart:180-257,335-365`). A
replay a JSON teljes szövegét hasonlítja, nem csak a dekódolt összesítést
(`test/features/learn/legacy_scorer_baseline_test.dart:115-149,283-302`).

## A valódi Learn út felelősségei

A 839 soros `LearnScreen` egyetlen `ConsumerStatefulWidget`
(`lib/features/learn/screens/learn_screen.dart:30-44,839`). Egy helyen kezeli:

- a tickert, monotonic elapsed értéket, playheadet és egybaros ring-outot
  (`lib/features/learn/screens/learn_screen.dart:49-55,125-160`;
  `lib/features/learn/lesson_timing.dart:9-16,36-41`);
- a metronómot és backing playbacket
  (`lib/features/learn/screens/learn_screen.dart:49-51,147-155`);
- a scorer, mikrofon-frame subscription és expected-chord hint lifecycle-ját
  (`lib/features/learn/screens/learn_screen.dart:76-83,94-123,208-230`);
- a frame de-jittert, hit-haptikát, burstöt és multiplier milestone-t
  (`lib/features/learn/screens/learn_screen.dart:163-205,450-494`);
- az Easy/Jam/speed állapotot és dinamikus nehézségi ajánlatot
  (`lib/features/learn/screens/learn_screen.dart:56-74,512-522,589-616`);
- a lesson progress-, streak- és practice-log írást, valamint a summary
  navigációt (`lib/features/learn/screens/learn_screen.dart:273-330`).

A képernyő a scorer 4-es defaultját felülírva egy teljes saját ütemet számol be:
`_countInBeats => _lesson.beatsPerBar`
(`lib/features/learn/screens/learn_screen.dart:45-47,218-223,248-253`). A
de-jitter is képernyő-felelősség: csak érvényes clockok és `0 < lag < 0.5 s`
esetén vonja le a frame érkezési késését
(`lib/features/learn/screens/learn_screen.dart:163-182`). A scorer már ezt a
korrigált időt kapja.

## Practice speed és Progress V1

A választható speed-grid **3 értéke** `[0.5, 0.75, 1.0]`, az alap `1.0`;
ismeretlen/off-grid tárolt vagy új érték nem marad meg
(`lib/features/learn/providers/practice_speed_provider.dart:13-31`). A képernyő
ezzel szorozza a lesson BPM-et, a váltás pedig új attemptet indít
(`lib/features/learn/screens/learn_screen.dart:61-74,512-522`).

A `PracticeEntry` V1:

| Modellmező | JSON kulcs | Jelentés |
|---|---|---|
| `day` | `day` | local epoch day |
| `source` | `src` | `live`, `analyze` vagy `learn` |
| `seconds` | `sec` | best-effort másodperc |
| `strokes` | `str` | lejátszott/pontozott strum |
| `chords` | `chd` | érintett akkordok száma |
| `directionAccuracy` | `dir` | opcionális 0..1 Learn direction pontosság |

A mezők és a tömör kulcsok forrása
`lib/features/progress/model/practice_entry.dart:5-53`. Ismeretlen `src`
szándékosan `live`-ra esik vissza
(`lib/features/progress/model/practice_entry.dart:55-71`). A log
**newest-last**, maximum **400** bejegyzés
(`lib/features/progress/data/practice_log_repository.dart:9-20,35-49`); az új
elem a lista végére kerül, túlcsorduláskor a legrégebbi eleje esik ki
(`lib/features/progress/providers/practice_log_provider.dart:23-34`).

## Teszt-baseline

A `main@90c0996` git-tree mérése:

```text
test/features/learn       28 fájl
test/features/progress     5 fájl
test/features/streak       5 fájl
test/features/metronome    3 fájl
```

Az E02-R01 egy új Learn replay-t ad, ezért a kör-branch aktuális Learn száma
29. A közvetlen baseline-fedezet:

- scorer, timing, combo és chord:
  `test/features/learn/lesson_scorer_test.dart:20-243`;
- input latency és korrigált miss-óra:
  `test/features/learn/scorer_latency_test.dart:23-80`;
- képernyőoldali de-jitter:
  `test/features/learn/live_scoring_jitter_test.dart:54-92`;
- playhead, count-in és ring-out:
  `test/features/learn/lesson_timing_test.dart:6-67`;
- 3/4 count-in:
  `test/features/learn/waltz_count_in_test.dart:13-49`;
- Easy/fail streak:
  `test/features/learn/dynamic_difficulty_test.dart:28-53`;
- expected-chord lifecycle:
  `test/features/learn/expected_chord_hint_test.dart:20-61`;
- Analyze adapter:
  `test/features/learn/lesson_from_analyze_test.dart:24-91`;
- speed-grid és perzisztencia:
  `test/features/learn/practice_speed_test.dart:14-67`;
- az új kilenc-scenario parity alap:
  `test/features/learn/legacy_scorer_baseline_test.dart`.

## Valódi eszközös evidencia

Az ADR 0065 azt rögzíti, hogy a legacy play-along utat valódi gitáron már
használták (`docs/adr/0065-practice-engine-v2-parallel-rollout.md:19-34`).
Ugyanakkor a repositoryban nincs Learn-specifikus, eszköz/model/dátum szerinti
reprodukálható mérési mátrix; a szélesebb Epic-1 valódi-gitáros regresszió és
latency-megfigyelés még pending
(`docs/sdd/epic-01-completion-report.md:112-129`;
`docs/rag/chunks/016b-animation-gamefeel.md:83-94`). Ezért a jelen golden
szintetikus parity-mérce, nem valódi-eszközös elfogadás.

## Ismert rések

1. **Pause alatt tovább pontozhat.** `_pause()` csak a tickert állítja meg; nem
   zárja a frame subscriptiont, `_onFrame` pedig nem ellenőrzi `_playing`
   állapotát (`lib/features/learn/screens/learn_screen.dart:163-206,232-237`).
   A strum a befagyott `_elapsedSec` időn pontozódhat, a chord observation is
   folytatódik. Nem került golden assertionbe. Aktív idő: E02-R07; mic és
   observation lifecycle: E02-R08; orchestration: E02-R11.
2. **Lebegőpontos ablakhatár.** Bár a kód `<=` összehasonlítást használ
   (`lib/features/learn/lesson_scorer.dart:188-195,253-260`), az abszolút
   másodpercek kivonása miatt a matematikai `+120 ms` lehet
   `0.1200000000000001`, így `late`; a `+280 ms` találat is abszolút
   időpontfüggő lehet. A `p44_timing_tiers` ezt a tényleges legacy eredményt
   rögzíti. Integer zenei idő: E02-R02; matcher parity: E02-R09; timing scorer:
   E02-R10.
3. **Korai direkt `finalize()` állapota.** A függvény növeli a `missed`
   számlálót, de nem növeli a `failStreak`-et, nem nullázza a combo/multiplier
   állapotot, és nem frissíti a legutóbbi result/timing mezőt
   (`lib/features/learn/lesson_scorer.dart:313-322`). A normál screen egy bar
   ring-out alatt `advance()`-el előbb
   (`lib/features/learn/lesson_timing.dart:36-41`;
   `lib/features/learn/screens/learn_screen.dart:140-160`). Session state:
   E02-R07; orchestration: E02-R11.
4. **A chord csak másodlagos, kétpillanatos mintavétel.** Wrong vagy miss mellett
   is lehet chord hit, és a röviden helyes, de `+370 ms` előtt eltűnő akkord nem
   kap creditet (`lib/features/learn/lesson_scorer.dart:220-237`). A külön
   chord-dimenzió az E02-R10 köre.
5. **Nincs pause-frame és teljes restart end-to-end regresszióteszt.** A jelen
   pause teszt csak UI-állapotot, a Jam teszt csak mic-release-t fed
   (`test/features/learn/learn_screen_test.dart:41-67`;
   `test/features/learn/review_r100_fixes_test.dart:88-109`). A lifecycle
   fixture-k E02-R08/R11 feladatai.
6. **Valódi eszközös mátrix hiányzik.** A szintetikus golden nem méri a
   készülékfüggő mic-latencyt, AGC-t, frame cadence-et, thermalt vagy gitárérzetet;
   a végső ellenőrzés E02-R20.

Történeti dokumentációban még található elavult 4-beat/12-lesson/pause-release
leírás (`docs/rag/chunks/014-play-along-learn.md:37-53,65-71`); a jelen
production hivatkozások és ez a baseline az aktuális állapotot rögzítik.
