# ADR 0080 — Practice highway-renderelés: pure pozíció-függvény, korlátos láthatósági ablak, verdict-vezérelt visszajelzés

**Státusz:** elfogadva (E02-R14 pre-flight, 2026-08-01).
Épít az [ADR 0072](0072-practice-time-layer.md) (`CompiledPracticeTarget`/
`CompiledTargetEvent` időréteg), [ADR 0076](0076-practice-scoring.md)
(`PracticeVerdict` + `TimingGrade`/`DirectionOutcome`/`ChordOutcome`) és
[ADR 0079](0079-state-driven-practice-session-shell.md) (állapotvezérelt
session-héj, `PracticeSessionHost` presentation-határ) döntéseire.
Kör: [`docs/rounds/e02-r14-strum-and-progression-modes.md`](../rounds/e02-r14-strum-and-progression-modes.md).

## Kontextus

Az Epic 2 tizenhárom köre után a Practice V2-nek van időrétege
(`CompiledPracticeTarget`, ütemhatárokkal és expected-chord szegmensekkel),
matchere, négy scorere (`PracticeVerdict`) és állapotvezérelt session-héja
(ADR 0079) — de **nincs látható gyakorlási felülete**. A felhasználó a
`running`/`paused` státuszban ma egy szöveges HUD-ot lát (`PracticeHud`), nem a
gördülő cél-sávot.

Ez a kör az első **két teljes, pontozott mód**: Strum Pattern és Chord
Progression. A tétje nem a tartalom (az a katalógusban kész, E02-R04), hanem a
**renderelés szerződése**: hol van egy cél-esemény a sávon, mit épít fel a
highway, és honnan jön a visszajelzés. A DSP-hez hasonlóan itt a csábítás a
legacy `LessonHighway` átemelése — de az a `Lesson` belső modellre épül, amit a
V2 presentation nem importálhat (SDD §8.3).

A döntéseket **hat mérés** rögzíti (`main` @ `7135c56`), és több közülük
ellentmond a brief előzetes feltételezésének:

1. **`CompiledTargetEvent` a renderelési egység.** Mezői:
   `sourceEventId`, `loopIndex`, `position` (`BeatPosition`), **`time`**
   (`Duration`, abszolút, count-innal), `barIndex`, `chord` (`String?`),
   `direction` (`StrumDirection?`), `accent`, `optional`
   (`compiled_practice_target.dart:95-123`). Az `events` lista idő szerint nem
   csökkenő. Ütemhatárok (`barBoundaries`) és expected-chord szegmensek
   (`expectedChordSegments`) a compiled targetben **már benne vannak** — a
   highway nem számol újra.
2. **A verdict a renderelés bemenete.** `PracticeVerdict.timingGrade`
   (`TimingGrade`: `perfect`/`good`/`early`/`late`/`missed`/`notApplicable`),
   `directionOutcome` (`DirectionOutcome`: `correct`/`wrong`/`notApplicable`),
   `expectedDirection`/`observedDirection` (`StrumDirection?`), `chordOutcome`
   (`ChordOutcome`: `correct`/`wrong`/`insufficientData`/`notApplicable`/
   `noDetection`) (`practice_verdict.dart:7-91`). A UI ezekből renderel.
3. **A `PracticeSessionHost` presentation-határ (ADR 0079 §2) NEM ad ki élő
   verdictet vagy metrikát.** Mérve (`practice_effect_listener.dart:21-27`): a
   határ mindössze `states`, `state`, `effects`, `liveOverallPerMille`, `send`.
   A `PracticeSessionState` a `target`-et (események, ütemhatárok,
   expected-chord szegmensek) és a lejátszófejet (`timelinePosition`,
   `activeElapsed`, `musicalPlayhead`) hordozza — a **highway geometriájához és
   az expected-chord jelzéshez elég**, de **verdict-listát és combót nem**. A
   konkrét `PracticeSessionController` `liveScore`-ja (→`verdicts`/`metrics`) és
   `lastExpectedChord`-ja **nincs a határon**, és sem a határ fájlja, sem az
   `application/` nincs a kör engedélyezett-listáján. → Következmény: **D10**.
4. **A `PracticeMetrics` csak `maxCombo`-t ad ki** (`practice_metrics.dart:119`);
   **`currentCombo` nincs** — az „aktuális combo" a `PracticeScoreAggregator`
   privát ciklusváltozója (`practice_score_aggregator.dart:137-184`), sehol nem
   felszínre hozott érték. → Következmény: **D4** (a combo-kijelző `maxCombo`-t
   mutat).
5. **A vizuális latency Settings-provider** (`visualLatencyProvider`,
   `visual_latency_provider.dart:33`), a legacy csak **rajzolási eltolásként**
   használja (`learn_screen.dart` `(inputLatency − visualLatency)/1000`), a
   pontozást nem érinti. → **D3**.
6. **A `ChordDiagram` a megengedett kereszt-feature import**
   (`chords/public.dart` barrel exportálja, `ChordDiagram({required String
   label, double size = 96, bool showLabel = true})`), belül a `leftHandedProvider`-t
   nézi. → **D8** (balkezes mód a diagramban már kezelt; a sáv iránya külön).

## Döntés

**D1 — A highway `CompiledTargetEvent`-et renderel.** A `Lesson`/`LessonEvent`
import TILOS; a Learn belső modellje nem szivároghat a Practice presentationbe.

**D2 — A pozíció tiszta függvényből jön.** A cél-esemény vízszintes helyét egy
**pure**, widget nélkül tesztelhető függvény adja:
`x = strikeX + (target.time − playhead + visualOffset) * pixelsPerSecond`,
ahol minden idő `Duration` másodpercekben, a `visualOffset` a D3 rajzolási
eltolás. `target.time == playhead` (és `visualOffset == 0`) esetén az eredmény
**pontosan `strikeX`** (egzakt egyenlőség, nem `closeTo`). A függvény külön,
közvetlenül tesztelhető; a widget csak meghívja.

**D3 — A vizuális latency KIZÁRÓLAG rajzolási eltolás.** Nem befolyásol
parancsot, verdictet, időt vagy pontszámot; egyedül a D2 `visualOffset`-jén át hat.

**D4 — A visszajelzés a verdictből jön, a combo `maxCombo`.** A `TimingGrade` és
a `DirectionOutcome` a visszajelző widget bemenete; a widget **nem** számol
offsetet, nem hasonlít ablakot, nem dönt találatról. A combo-kijelző a
`PracticeMetrics.maxCombo` értékét mutatja (D-finding 4: `currentCombo` nincs),
**nem** saját számlálót.

**D5 — A láthatósági ablak korlátos, és ez SZERZŐDÉS.** A highway **csak** a
látható sávba (plusz egy rögzített margó) eső célokat építi fel. Ez nem
optimalizálás; mérve van (`@visibleForTesting` megvizsgált-rekord-számláló +
`find.byType(PracticeTargetMarker)`). A lejátszófej mozgása **nem** építheti újra
a teljes cél-listát.

**D6 — A jelentés nem csak színre épül.** Down/up külön ikon **és** szöveges
szemantikai címke; a timing-visszajelzés szöveget is hordoz.

**D7 — 3/4 és 4/4 egyaránt támogatott;** a 6/8 megjelenítése nem hibázhat, még
ha a mód-katalógusban nincs is ilyen gyakorlat.

**D8 — Balkezes mód:** a sáv vizuálisan tükrözhető, de a **down/up jelentése nem
fordul meg** (SDD §22.2) — a `directionOutcome` értelmezése változatlan.

**D9 — Rest és azonos irányú szomszédok külön markerek.** A szünet-slot külön
jelölést kap és nem kelt találati elvárást; két azonos irányú, egymást követő
esemény **két külön** markert épít (nincs render-dedup).

**D10 — A verdict/metrika/combo a mód-nézet widgetek EXPLICIT bemenete;
a runtime-bekötés későbbi kör.** Mivel a `PracticeSessionHost` (D-finding 3) ma
nem ad ki verdictet/metrikát, és a határ bővítése kívül esik a kör
engedélyezett-listáján, a verdict-vezérelt visszajelző és a combo-kijelző az
adatait **konstruktor-paraméterként** kapja, és a widget-teszt (A4/A5) injektált
verdicttel/metrikával hajtja. Ez pontosan az R13 mintája: a production
`practiceSessionHostProvider` `null`, a felület injektált adaton át mérve. A
`practice_session_screen.dart` a mód-nézetet a `state`-ből elérhető adattal
(`target` + lejátszófej + `expectedChordSegments`) csatolja be; a
verdict→visszajelzés valós host-bekötése **külön, későbbi kör** (az, amelyik a
controllert host-ként bepányvázza), és **nem** módosíthatja a `PracticeSessionHost`
interfészt ebben a körben. Ez egyetlen acceptance-kritériumot sem gyengít: az
A4/A5 a widget renderelését méri adott bemenetre, ami host nélkül is teljes.

## Következmények

- A pozíció-számítás egzakt, gépi mátrixszal mérhető (A1), mert leválik a
  widgetről. A „0 különbség = strikeX" cella egzakt egyenlőséget mér.
- A virtualizáció **szerződés, nem optimalizálás**: a rekord-számláló és a
  marker-szám mérve van (A7), a küszöb (≤64) nagyságrendekkel a helyes
  implementáció fölött és a teljes lista (2000) alatt.
- A vizuális latency szétszivárgása a pontozásba **regressziós teszttel** tiltott
  (A4), ahogy a legacyben.
- A verdict/metrika runtime-forrása nyitott follow-up (D10): egy későbbi kör a
  `PracticeSessionHost`-ot bővíti vagy külön live-nézetet ad. Addig a mód-nézetek
  a beépített felületen injektált adaton mérve helyesek, production host `null`
  → a képernyő „nem elérhető" állapotot rajzol (viselkedés változatlan).
- A motor-réteg (`domain/`, `application/`, `data/`) 0 sort változik (A10); a
  `lib/features/learn/` 0 sort.
