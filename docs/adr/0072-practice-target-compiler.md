# ADR 0072 — Practice target compiler és kanonikus beat-idő konverzió

- **Státusz:** Elfogadva (2026-07-30)
- **Kör:** E02-R06 — Target compiler és beat-idő konverzió
- **SDD:** `docs/sdd/03-epic-02-practice-engine.md` §12.3, §14, „Kör 6"
- **Előzmények:** [ADR 0066](0066-practice-tick-time-model.md) (480 PPQ tick-idő),
  [ADR 0068](0068-practice-domain-model-contracts.md) (domain-szerződések),
  [ADR 0070](0070-builtin-practice-catalog-contract.md), [ADR 0071](0071-legacy-practice-adapters.md)

## Kontextus

Az E02-R02..R05 körök után létezik a *zenei* réteg (`PracticeDefinition`,
480-PPQ `BeatPosition`, `Tempo`, `Meter`), a beépített katalógus és a legacy
adapterek — de **egyetlen sor sem fordítja le a zenei pozíciókat valós időre**.
A mai (legacy) Learn út ezt szétszórt `double` képletekkel teszi:

| Hely | Képlet | Szerep |
|---|---|---|
| `lib/features/learn/lesson_scorer.dart:85,87` | `_secPerBeat = 60.0 / bpm`; `t = (countInBeats + e.beat) * _secPerBeat` | esemény abszolút ideje |
| `lib/features/learn/lesson_timing.dart:11,15` | `beat = elapsedSec * bpm / 60`; `playhead = beat - countInBeats` | playhead |
| `lib/features/learn/lesson_timing.dart:39` | `playhead >= totalBeats + beatsPerBar` | ring-out / befejezés |
| `lib/features/learn/screens/learn_screen.dart:47,74` | `countInBeats = beatsPerBar`; `bpm = lesson.bpm * speed` | count-in és practice speed |
| `lib/features/learn/screens/learn_screen.dart:498` | `e.beat <= playhead + 0.25` | expected-chord hint |
| `lib/features/learn/model/lesson.dart:363` | `secPerBeat = 60.0 / bpm` | Analyze-import |

Öt fájlban hat képlet, mind `double`, mind implicit szerződéssel (egy ütem
count-in, egy ütem ring-out, 0,25 ütem chord-lookahead). Az SDD §12.3
elfogadási feltétele explicit: **„nincs szétszórt beat-to-time formula"**.

A V2 pontozó (E02-R08+) determinisztikus, bitre reprodukálható target
timeline-t vár, a `PracticeSessionClock` (E02-R07) pedig `Duration`-ben mér —
tehát a konverziónak *elé* kell kerülnie mindkettőnek.

## Döntés

### 1. `BeatTimeConverter` — az EGYETLEN kanonikus beat↔idő konverzió

`lib/features/practice/domain/model/beat_time_converter.dart`, tiszta érték-típus
(`Tempo` + `Meter`). Minden más practice-kód rajta keresztül számol időt.

Az aritmetika **egész mikroszekundum**, nem lebegőpontos akkumuláció:

```text
micros(ticks) = (ticks * 60_000_000 / (bpm * 480)).round()
```

Indoklás: a `ticks` egész, a `bpm` az egyetlen `double` bemenet, és a
kerekítés **egyszer**, a végén történik — így nincs esemény-számmal növekvő
drift (a legacy `(countIn + beat) * secPerBeat` szintén egyszeri szorzás, ezért
a két út parityje mérhető). A `Duration` mikroszekundum-felbontású, tehát ez a
lehető legpontosabb ábrázolás; a maradék kerekítési hiba ≤ 0,5 µs, öt
nagyságrenddel a 50 ms-os `perfect` ablak alatt.

Az inverz (`positionAt`) a **legközelebbi tickre** kerekít, összhangban a
`BeatPosition.fromLegacyBeats` szerződésével (ADR 0066).

**Fail-fast szimmetria** (E02-R02 MINOR-1 tanulsága, `Meter.ticksPerBar` mintája):
érvénytelen `Tempo`/`Meter` mellett a konverter getterei `StateError`-t dobnak,
nem adnak csendben végtelent vagy NaN-t. A hívó dolga `validate()`-elni.

### 2. `CompiledPracticeTarget` — befagyasztott session-timeline

A `PracticeTargetCompiler` egy `PracticeDefinition` + `PracticeSessionConfig`
(+ opcionális `PracticeLoopRange`) hármasból **immutable, value-equal**
`CompiledPracticeTarget`-et készít. Bemenet-azonosság ⇒ bitre azonos kimenet;
a compiler tiszta (nincs óra, nincs random, nincs locale-függés) — ezt a
meglévő `domain_purity_test.dart` gépileg őrzi.

Az idővonal nullpontja a **session start**, tehát a count-in a timeline
RÉSZE (ahogy a legacy `LessonScorer` is a count-innal együtt számol
abszolút időt) — nem külön eltolás, amit minden hívónak újra hozzá kell adnia.

### 3. A legacy időzítési konstansok szerződéssé emelése

A mai implicit értékek nevesített, egy helyen álló konstansok lesznek, és a
compiler kimenete **mérhetően egyezik** a legacy úttal:

| Szerződés | Érték | Legacy forrás |
|---|---|---|
| count-in hossza | `config.countInBars` × ütem (a legacy Learn 1 ütemmel indít) | `learn_screen.dart:47` |
| ring-out | pontosan **1 ütem** a definition meterében | `lesson_timing.dart:39` |
| expected-chord lookahead | **0,25 ütem = 120 tick** | `learn_screen.dart:502` |
| pre-roll chord | az első akkord már a count-in alatt aktív | `learn_screen.dart:505` |
| teljes hossz | `countIn + zenei + ring-out` | `practice_baseline_scenarios.dart` `finishAtSec` |

A `finishAtSec` a befagyasztott E02-R01 baseline szerves része — a compiler
`totalDuration`-jének a tíz baseline-forgatókönyvre **mikroszekundum-pontossággal**
egyeznie kell vele. Ez a kör gépi parity-mércéje.

### 4. Loop: csak egész ütem

A loop tartomány **ütemindexekben** van megadva (`startBar`, `endBarExclusive`),
és egy loop-áthaladás hossza mindig `bar-ok × ticksPerBar` — akkor is, ha a
definition utolsó üteme részleges (a maradékot csend tölti ki). Indoklás: az SDD
§14.3 „a loop boundary csak zeneileg biztonságos ponton legyen"; egy ütem
közepén visszaugró loop a metronóm downbeatjét és a taktusérzetet töri el.
Érvénytelen tartomány → **kontrollált `Failure`**, nem clamp: egy csendben
megvágott loop pontosan az a néma no-op osztály, amit a projekt szabálya tilt.

Következmény: a pass-hossz felfelé kerekül egész ütemre akkor is, ha nincs loop.
A ma szállított tartalom mindegyikére (17 lecke, 10 beépített gyakorlat, Song-,
Analyze- és Daily-Challenge-adapter) ez **no-op** — a kör tesztje ezt gépileg
kipinneli, nem bemondásra állítja.

### 5. Nehézség-variáció: a compiler NEM vág újra

Az Easy variánst az E02-R05 adaptere állítja elő (saját `.easy.v1` ID-vel), a
compiler nem csinál saját egyszerűsítést. A `config.easyVariationId` szerepe
**konzisztencia-ellenőrzés**: ha nem null és nem egyezik a `definition.id`-vel,
a fordítás kontrollált hibával áll meg. Így egy Easy-re állított session nem
tud csendben a teljes leckét lejátszani (silent no-op osztály).

### 6. Scoring applicability

`scoringApplicable = definition.mode.scoredDimensions.isNotEmpty && van
nem-marker esemény`. A Free Practice így **nem hiba**, hanem üres, biztonságos
target: nulla eseménnyel, nulla zenei hosszal, `scoringApplicable == false` —
az SDD Kör 6 elfogadási feltétele szerint.

## Alternatívák

1. **`double` másodperc mindenütt (a legacy folytatása).** Elvetve: az SDD
   elfogadási feltétele a szétszórt képletek megszüntetése, és a `double`
   akkumuláció loopolt sessionben mérhető driftet ad.
2. **Idő a `PracticeEvent`-ben, fordítás nélkül.** Elvetve: a tempó és a
   count-in session-beállítás, a definition viszont tartalom — ADR 0068 óta a
   kettő szándékosan külön él.
3. **Loop tetszőleges esemény-tartományon.** Elvetve ebben a körben: az SDD
   §14.3 megengedi user-választotta esemény-tartományt is, de „normalizálva" —
   a normalizálás célja épp az egész ütem. Ha később kell finomabb loop, az
   külön ADR-t kap.

## Következmények

- **Pozitív:** egyetlen auditálható konverziós pont; a V2 scorer és a session
  clock ugyanazon a befagyasztott idővonalon dolgozik; a legacy parity
  mikroszekundumban mérhető, nem szemre.
- **Negatív:** a legacy `LessonTiming`/`LessonScorer` képletek **egyelőre
  megmaradnak** (a mai Learn út érintetlen, a flagek OFF) — átmenetileg két
  implementáció él egymás mellett. A legacy út kivezetése az E02-R11+ migrációs
  körök dolga; addig a parity-teszt köti össze őket.
- **Nyitott (nem e kör):** input latency korrekció (§12.4), frame delivery lag,
  Speed Builder tempó-rámpa — ezek a session/scorer köröké.
