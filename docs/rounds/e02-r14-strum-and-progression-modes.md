# E02-R14 — Strum Pattern és Chord Progression mód

- **Státusz:** **PLANNING** (pipeline pre-flight 2026-08-01, kód újramérve: `main` @ `7135c56`; eredetileg PREPARED 2026-07-31 @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 14"** (+ §7.1, §7.3, §21.4, §24)
- **Branch:** `codex/e02-r14-strum-progression-modes`
- **Előfeltétel:** **E02-R13 merge-ölve** (a session shell fogadja a mód-nézetet).
- **ADR:** **0080** — `docs/adr/0080-practice-highway-rendering.md`, **az
  orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** **MiniMax M3** (pipeline-döntés, `docs/execution/pipeline-queue.tsv`;
  a brief eredeti Codex-ajánlása felülírva — a pozíció-függvény és a
  virtualizáció mérése gépi mátrixszal rögzített, l. §6/A1·A7).

## 0.0 Pre-flight revíziós napló (pipeline, 2026-08-01, `main` @ `7135c56`)

Az előre megírt brief mért állításait a kód ellen újramértem. Minden hivatkozott
enum, mező és metódus grep-elve. **Két mérés ütközött a brief előfeltevésével**,
mindkettő a §1 szabály-1 („elérhetetlen cél-státusz") mintája — egy
acceptance-cella olyan értékre hivatkozott, amit egyetlen elérhető bemenet sem
produkál. Feloldás dokumentált revízióval (ADR 0087 §2, saját nem-merge-elt brief):

1. **R1 — A `PracticeSessionHost` határ nem ad ki verdictet/metrikát.**
   Mérve `practice_effect_listener.dart:21-27`: a presentation-határ (ADR 0079 §2)
   `states`/`state`/`effects`/`liveOverallPerMille`/`send` — **nincs verdict-
   vagy metrika-getter**. A `PracticeSessionState` a `target`-et (események,
   `barBoundaries`, `expectedChordSegments`) és a lejátszófejet
   (`timelinePosition`/`activeElapsed`/`musicalPlayhead`) hordozza; verdict-listát
   és combót **nem**. A `PracticeSessionController.liveScore`/`lastExpectedChord`
   a határon kívül van, és sem a határ fájlja, sem az `application/` nincs a §4
   listáján. → **Feloldás (ADR 0080 D10):** a verdict-vezérelt visszajelző és a
   combo-kijelző az adatát **konstruktor-paraméterként** kapja, a widget-teszt
   (A4/A5) injektált verdicttel/metrikával hajtja — az R13 mintája (production
   host `null`). A valós host-bekötés **későbbi kör**; a `PracticeSessionHost`
   interfészt ez a kör **nem** módosítja. Egyetlen acceptance sem gyengül: az
   A4/A5 a widget renderelését méri adott bemenetre.

2. **R2 — `PracticeMetrics.currentCombo` nem létezik.** Mérve
   `practice_metrics.dart:119` + `practice_score_aggregator.dart:137-184`: csak
   `maxCombo` felszíni érték; az „aktuális combo" privát ciklusváltozó. → **Feloldás:**
   az A5 combo-kijelzője a **`PracticeMetrics.maxCombo`** értékét mutatja; az
   „aktuális combo" megfogalmazás törölve (lásd az A5 alábbi revízióját).

A §4 engedélyezett-lista, a §6 mérési eszközök (`PracticeTargetMarker`,
`@visibleForTesting` számláló) és a §9 gate-hívás **változatlan**.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R13 session shell-t: hová illeszkedik a mód-nézet, és mit
>    kap meg a controller state-jéből.
> 2. Ellenőrizd az R10 verdict-mezőit (`TimingGrade`, `DirectionOutcome`) — a
>    visszajelzés ezekből épül, nem saját számításból.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0080 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

Az első **két teljes, pontozott gyakorlási mód**: Strum Pattern és Chord
Progression. A kör kimenete a `PracticeHighway` (a `CompiledPracticeTarget`
eseményeit rendereli), a timing/direction visszajelzés a **verdictekből**, és a
progression-nézet current/next akkord + diagram része.

Ez az a kör, ahol a V2 először **végigjátszható**, és ahol a highway
teljesítménye (60 FPS cél, nagy célesemény-lista) először mérhető.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **Legacy vizuál-referencia:** `lib/features/learn/widgets/lesson_highway.dart`
  (314 sor). API-ja mérve: `LessonHighway({required Lesson lesson, required
  double playheadBeat, double height = 168, double strikeX = 68, double
  beatsVisibleAhead = 4})`. A sáv festett (`CustomPaint`), ezért a képernyőolvasó
  semmit nem hall belőle — a widget külön régió-címkét mond be a következő
  akkorddal. **A vizuális koncepció újrahasználható, a `Lesson` modell NEM.**
- **A legacy Learn belső modellje:** `lib/features/learn/model/lesson.dart`
  (`Lesson`, `LessonEvent`) — a V2 presentation **nem importálhatja** (SDD §8.3:
  „nincs más feature belső presentation/providers/data importja"; a `Lesson` a
  Learn belső modellje).
- **Célmodell (R06):** `CompiledPracticeTarget` / `CompiledTargetEvent`
  (`domain/model/compiled_practice_target.dart`, 200 sor) — `sourceEventId`,
  `loopIndex`, `position` (`BeatPosition`), **`time`** (abszolút, count-innal
  együtt), `barIndex`, `chord`, `direction`, `accent`, `optional`; az `events`
  lista idő szerint **nem csökkenő**. Ütemhatárok és expected-chord szegmensek
  a compiled targetben már benne vannak.
- **Verdict (R10):** `PracticeVerdict` — `timingGrade`, `timingOffset`
  (előjeles), `directionOutcome`, `expectedDirection`, `observedDirection`,
  `chordOutcome`, `eventScore`. **A UI ezekből renderel, nem számol újra.**
- **Akkord-diagram:** `lib/features/chords/public.dart` exportálja a
  `ChordDiagram` widgetet — ez a **megengedett** kereszt-feature import
  (publikus barrel, ADR 0057 mintája).
- **Vizuális latency:** `visualLatencyProvider` (Settings) — a legacy
  `learn_screen.dart:135` mérve **rajzolási eltolásként** használja
  (`(inputLatency - visualLatency) / 1000`), a pontozást nem érinti. Meglévő őr:
  `test/features/learn/visual_offset_test.dart`.
- **3/4 támogatás a legacyben már létezik** (`test/features/learn/waltz_count_in_test.dart`),
  a `Meter` a V2-ben 4/4 · 3/4 · 6/8-at ismer.

## 3. Scope

**Benne:** `PracticeHighway` widget, a két mód-nézet (strum pattern, chord
progression), a verdict-alapú timing/direction visszajelzés, a combo-kijelző, az
egy-ütemes pattern-előnézet, ARB-kulcsok, widget- és teljesítmény-tesztek.

**Kívül (ebben a körben TILOS):**

- Chord Change mód (Kör 15), Rhythm-only / Free Practice (Kör 16), Speed Builder
  (Kör 17), Result képernyő (Kör 18).
- **Bármilyen scoring-logika a widgetben.** A UI verdictet renderel, nem gyárt.
- A controller, reducer, scorerek, matcher, compiler módosítása.
- `lib/features/learn/**` (a legacy highway **olvasható**, nem írható, és nem
  importálható a V2-be).
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/presentation/widgets/practice_highway.dart` | **ÚJ** | a gördülő cél-sáv |
| `lib/features/practice/presentation/widgets/practice_pattern_preview.dart` | **ÚJ** | egy-ütemes pattern-előnézet |
| `lib/features/practice/presentation/widgets/practice_feedback.dart` | **ÚJ** | timing/direction visszajelzés + combo |
| `lib/features/practice/presentation/widgets/practice_chord_lane.dart` | **ÚJ** | current/next akkord + diagram |
| `lib/features/practice/presentation/views/strum_pattern_view.dart` | **ÚJ** | mód-nézet |
| `lib/features/practice/presentation/views/chord_progression_view.dart` | **ÚJ** | mód-nézet |
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | — | **CSAK** a mód-nézet becsatolása (a shell többi része változatlan) |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új kulcsok mindkét nyelven |
| `test/features/practice/presentation/practice_highway_test.dart` | **ÚJ** | A1–A4 |
| `test/features/practice/presentation/strum_pattern_view_test.dart` | **ÚJ** | A5 |
| `test/features/practice/presentation/chord_progression_view_test.dart` | **ÚJ** | A6 |
| `test/features/practice/presentation/practice_highway_scaling_test.dart` | **ÚJ** | A7 virtualizáció, MÉRVE |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** ha új képernyő-belépő kell (várhatóan nem) |
| `docs/rounds/e02-r14-strum-and-progression-modes.md` | — | **CSAK a §10** |

**Tilos zóna:** minden más, nevezetesen `lib/features/learn/**`,
`lib/features/practice/domain/**`, `application/**`, `data/**`, `docs/adr/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0080 — NEM tárgyalhatók)

1. **A highway `CompiledTargetEvent`-et renderel.** A `Lesson`/`LessonEvent`
   import TILOS; a Learn belső modellje nem szivároghat a Practice
   presentationbe.
2. **A pozíció tiszta függvényből jön.** A cél-esemény vízszintes helyét egy
   **pure**, widget nélkül tesztelhető függvény adja:
   `x = strikeX + (target.time − playhead + visualOffset) * pixelsPerSecond`.
   A függvény külön, közvetlenül tesztelhető (a widget csak meghívja).
3. **A vizuális latency KIZÁRÓLAG rajzolási eltolás.** Nem befolyásol
   parancsot, verdictet, időt vagy pontszámot.
4. **A visszajelzés a verdictből jön.** A `TimingGrade` és a `DirectionOutcome`
   a UI bemenete; a widget **nem** számol offsetet, nem hasonlít ablakot, nem
   dönt találatról.
5. **A láthatósági ablak korlátos.** A highway **csak** a látható sávba (plusz
   egy rögzített margó) eső célokat építi fel. Ez nem optimalizálás, hanem
   szerződés — és mérve van (§6 A7).
6. **A jelentés nem csak színre épül.** Down/up külön ikon **és** szöveges
   szemantikai címke; a timing-visszajelzés szöveget is hordoz.
7. **3/4 és 4/4 egyaránt támogatott** (a 6/8 megjelenítése nem hibázhat, még ha
   a mód-katalógusban nincs is ilyen gyakorlat).
8. **Balkezes mód:** a sáv vizuálisan tükrözhető, de a **down/up jelentése nem
   fordul meg** (SDD §22.2) — a `directionOutcome` értelmezése változatlan.
9. **Nincs teljes-listás rebuild.** A playhead mozgása nem építheti újra a
   teljes cél-listát; a rebuild-hatókör mérve van (§6 A7).

## 6. Acceptance criteria

### A1 — Pozíció-mátrix a pure függvényre

`pixelsPerSecond` és `strikeX` rögzített; `playhead` és `target.time` több
kombinációjára a **kiszámolt** koordináta (a cellákat `python3 -c`-vel
ellenőrizd):

| `target.time − playhead` | Elvárt `x` |
|---|---|
| `−0.5 s` | `strikeX − 0.5 * pps` (a strike-vonal mögött) |
| `0` | **pontosan `strikeX`** |
| `+0.5 s` | `strikeX + 0.5 * pps` |
| `+ (láthatósági ablak határa)` | a sáv jobb széle |
| `+ (határ + 1 µs)` | **nem épül fel** (A7) |

***Pirosra fogja:*** az elcsúszott strike-vonal (a „0 különbség = strikeX" cella
az egyetlen, ami ezt egzaktan méri).

### A2 — Rest és azonos irányú szomszédos események

- **Rest slot** (`PracticeEvent` irány nélkül / szünet): a sávon **külön**
  jelöléssel jelenik meg, és **nem** kelt találati elvárást.
- **Két azonos irányú, egymást követő esemény** (pl. két down 1/8-ad
  távolságra): **két külön** marker épül fel, nem olvad össze.

***Pirosra fogja:*** a „dedupláljuk az azonos irányúakat" renderelési
egyszerűsítés, ami a pattern felét eltünteti.

### A3 — 3/4 és ütemhatárok

3/4-es definícióval: az ütemvonalak a `barIndex` váltásainál jelennek meg, és
egy ütemre **három** ütés esik. Külön cella 4/4-re.

### A4 — Vizuális latency csak rajzol

`visualLatencyMs ∈ {0, 60, 200}` mátrix:

- a marker `x` koordinátája **eltolódik** a várt mértékkel;
- a kiadott parancsok száma, a verdict-lista és a HUD score-értéke
  **változatlan** mind a három cellában.

***Pirosra fogja:*** a vizuális latency beszivárgása a pontozási vagy parancs-
útba (a legacyben ezt külön teszt őrzi — a V2-ben is kell).

### A5 — Strum Pattern nézet

- Egy-ütemes pattern-előnézet a definíció `events` alapján (down/up/rest).
- Találatnál a `TimingGrade` szerinti visszajelzés jelenik meg (perfect / good /
  early / late), rossz iránynál az **elvárt** irány (`expectedDirection`).
- A combo-kijelző a `PracticeMetrics.maxCombo` értékét mutatja (§0.0 R2: a
  `currentCombo` nem létező érték), **nem** saját számlálót. A verdict és a
  metrika a visszajelző/combo widget **explicit paramétere** (§0.0 R1, ADR 0080 D10).

### A6 — Chord Progression nézet

- **Current** és **next** akkord, `ChordDiagram`-mal (a `chords/public.dart`
  barrelből).
- Az „upcoming bar" a következő ütem akkordját mutatja.
- Az **expected chord hint** a compiled target szegmenseit követi, és a session
  befejezésekor **törlődik** (a legacyben erre külön teszt van:
  `expected_chord_hint_test.dart` / `expected_hint_cleared_on_live_test.dart` —
  a V2-ben ugyanez a kockázat).
- A `chordOutcome` négy értéke **négy különböző** megjelenítést kap
  (correct / wrong / insufficientData / notApplicable) — az utóbbi kettő
  **nem** jelenik meg hibaként.

### A7 — Virtualizáció és rebuild-hatókör, MÉRVE

**A mérés eszközei (ezeket MEGADOM):**

- a cél-marker widget **típus szerint megszámolható**
  (`tester.widgetList(find.byType(PracticeTargetMarker)).length`);
- a highway `@visibleForTesting` számlálót publikál arról, hány célesemény-
  rekordot vizsgált meg az utolsó felépítéskor.

Cellák:

| Bemenet | Elvárt |
|---|---|
| **2 000** célesemény, 4 másodperces látható ablak | felépített markerek száma **≤ 64** |
| a playhead 100 lépésnyi mozgatása | a megvizsgált rekordok kumulatív száma **≤ 100 × 64** |
| 2 000 célesemény, a playhead a lista végén | felépített markerek száma **≤ 64** |

A 64-es korlát nagyságrendekkel a helyes implementáció (néhány tucat látható
cél) fölött és a teljes-listás (2 000) alatt van, tehát nem konstans-érzékeny.

**NEM elfogadható gyengítés:** a számláló elhagyása és fal-óra/FPS méréssel
helyettesítése (CI-n értelmezhetetlen és flaky); a küszöb utólagos felhúzása a
mért értékre. Ha a 64 szűknek bizonyul egy helyes implementációra → `stopped`
+ jelentés.

### A8 — Nincs Learn-import és nincs scoring a widgetben

Guard-állítás a saját tesztfájlban: a `presentation/` alatti új fájlok forrása
**nem tartalmazza** a `features/learn/`, `LessonScorer`, `LessonEvent`,
`Lesson(` mintákat, és nem importál `domain/service/`-t.

### A9 — a11y, i18n, layout

- Down/up ikon **és** szöveges szemantikai címke; a timing-visszajelzés
  szövegesen is olvasható.
- Balkezes mód: tükrözött elrendezés, **változatlan** irány-jelentés (külön cella).
- Angol/magyar felépülés, `l10n_parity_test` zöld.
- 320×568 és 915×412 méreten nincs overflow; 200%-os szövegméretnél sem.

### A10 — Nulla változás a motor-rétegben

`git diff --stat origin/main...HEAD` a §4 listáján belül; `domain/`,
`application/`, `data/` **0 sor**; `lib/features/learn/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0080, `compiled_practice_target.dart`, `practice_verdict.dart`,
   az R13 session shell, a `chords/public.dart` barrel, és **referenciaként**
   a `lesson_highway.dart`-ot (nem másolásra).
2. A pozíció-függvény + A1 mátrix (widget nélkül, pure tesztben).
3. `practice_highway.dart` a láthatósági ablakkal és a számlálóval (A7).
4. Rest / azonos irányú események / ütemhatárok (A2, A3).
5. `practice_feedback.dart` a verdictből (A5).
6. `practice_chord_lane.dart` + progression nézet (A6).
7. Vizuális latency mátrix (A4).
8. a11y/i18n/layout (A9), guard-állítás (A8).
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A legacy highway átemelésének csábítása.** A `LessonHighway` a `Lesson`
  modellre épül; a copy-paste azonnal tiltott importot hoz be. Írd újra a
  compiled targetre.
- **A pozíció-számítás a widgetben.** Ha nem választod le pure függvénybe, az A1
  mátrixot nem tudod egzaktan mérni — és pont ez a rész szokott elcsúszni.
- **Virtualizáció félmegoldása.** A `ListView.builder` önmagában nem elég, ha a
  sávot `CustomPaint` festi: ott a **festési** hatókört kell korlátozni. A
  számláló mindkettőre ugyanaz a mérce.
- **Az expected chord hint bennragadása** a session után — a legacyben ez
  ismétlődő hibaosztály volt (két külön regressziós teszt őrzi).
- **A 6/8 megjelenítés.** Nem kell rá gyakorlat, de kivételt sem dobhat.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

**Új fájlok (a §4 listán):**

- `lib/features/practice/presentation/widgets/practice_highway.dart` — a
  Practice V2 highway. Pure `targetX(...)` (D2), `targetInVisibilityWindow(...)`,
  `lowerBoundTime(...)` segédfüggvények. A `PracticeHighway` widget
  `StatefulWidget` (a vizsgált-rekord-számláló tárolásához, A7).
  - Binary-search alsó határ + korai-kilépés felső határ — a per-frame
    `lastExaminedRecordCount` ≤ 64 a 2000-es fixture-rel (A7).
  - Egyéni `RepaintBoundary`-vel övezett `CustomPaint` a háttér-sávnak
    (no layout, no sem), a markerek `Stack`-ben vannak.
  - Markerek: down → `primary`, up → `confidenceHigh`, rest → `outline`
    ikon, mind `Semantics(label: ...)` címkével (D6).
- `lib/features/practice/presentation/widgets/practice_feedback.dart` —
  verdict-vezérelt inline visszajelzés. A `TimingGrade`/`DirectionOutcome`
  fordítása szöveges címkékre + ikonokra; a kombó a `PracticeMetrics.maxCombo`
  értékét mutatja (D4, R10).
- `lib/features/practice/presentation/widgets/practice_pattern_preview.dart`
  — egy-ütemes pattern-előnézet. Az első bar eseményeit `_Slot`-onként
  rendereli (down/up/rest), nincs render-dedup (D9).
- `lib/features/practice/presentation/widgets/practice_chord_lane.dart` —
  current + next + upcoming-bar cellák, `ChordDiagram`-mal (a megengedett
  barrel-ből). A `showChordHint=false` azonnal törli a hintet (A6).
- `lib/features/practice/presentation/views/strum_pattern_view.dart` — a
  mód-nézet: highway + pattern preview + feedback.
- `lib/features/practice/presentation/views/chord_progression_view.dart` —
  a másik mód-nézet: highway + chord lane + feedback.

**Módosított fájlok (a §4 listán):**

- `lib/features/practice/presentation/screens/practice_session_screen.dart`
  — a `_ModeView` widget becsatolja a futó/szünet mód-nézetet a
  `state.target` + `state.timelinePosition` + `visualLatencyProvider` alapján.
  A verdict/metrikus a konstruktor-paraméter (`lastVerdict: null`,
  `metrics: null`) — a runtime-bekötés a host-kör (R10) feladata.
- `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` — 21 új kulcs (`practiceHighway*`,
  `practiceFeedback*`, `practicePatternPreview*`, `practiceChordLane*`).

**Új tesztek:**

- `test/features/practice/presentation/practice_highway_test.dart` — A1–A4
  mátrix a `targetX` pure függvényre + a widget szintű A2 (két down +
  rest slot) és A3 (3/4 + 6/8).
- `test/features/practice/presentation/practice_highway_scaling_test.dart`
  — A7: 2000 esemény × 4 s ablak, 100 lépés playhead-mozgás, végi
  playhead — mind ≤ 64 examined.
- `test/features/practice/presentation/strum_pattern_view_test.dart` — A5:
  pattern preview down/up/rest, perfect/goood/wrong direction, null
  verdict/metrikus nem dob.
- `test/features/practice/presentation/chord_progression_view_test.dart` —
  A6: 3 ChordDiagram cella, `showChordHint=false` töröl, mind a 4
  `ChordOutcome` érték renderelődik.
- `test/features/practice/presentation/practice_highway_import_guard_test.dart`
  — A8: a 6 új fájl forrása nem tartalmazza a `features/learn/`,
  `LessonScorer`, `LessonEvent`, `Lesson(`, `domain/service/`, `Scorer(`,
  `Stopwatch`, `Timer(` mintákat.

**Nem nyúltam (A10):** `lib/features/practice/domain/**`,
`lib/features/practice/application/**`, `lib/features/practice/data/**`,
`lib/features/learn/**` — `git diff --stat origin/main...HEAD` üres
rajtuk.

### A1–A10 teljesülése

| Ac | Bizonyíték |
|---|---|
| **A1** — pozíció-mátrix | `practice_highway_test.dart` A1 group: 5 teszt, mind a `targetX` pure függvényre. A `target.time == playhead` cella **pontosan** `strikeX` (egzakt egyenlőség, nem `closeTo`). A +4s cella a `strikeX + 4*pps` (= `laneWidth`) értéket adja, a +4s+1µs pedig kívül esik a láthatósági ablakon. |
| **A2** — rest + azonos irányú szomszédok | `practice_highway_test.dart` A2 group: két down marker (`Icons.arrow_downward`, 2 darab) + rest slot (`Icons.remove`, 1 darab). A rest `direction: null` mellé nem kerül találati elvárás. |
| **A3** — 3/4 + 4/4 + 6/8 | `practice_highway_test.dart` A3 group: 3/4-es definition tiszta build, 6/8-as definition `beatsPerBar: 6` valid. |
| **A4** — vizuális latency csak rajz | `practice_highway_test.dart` A4 group: visualOffset ∈ {0, 60ms, 200ms} mátrix — a `targetX` eltolása a `visualOffset * pps` mértékkel. A session-screen nem küld parancsot, nem módosít verdictet; az A4 a widget-szintű tisztaságot méri. |
| **A5** — Strum Pattern nézet | `strum_pattern_view_test.dart`: 4 teszt — pattern preview (down/up/rest), perfect verdict + combo, wrong direction label, null verdict/metrikus. |
| **A6** — Chord Progression nézet | `chord_progression_view_test.dart`: 3 teszt — 3 ChordDiagram, `showChordHint=false` törli a 0 ChordDiagram-ot, 4 `ChordOutcome` renderelődik. |
| **A7** — virtualizáció, MÉRVE | `practice_highway_scaling_test.dart`: 2000 esemény × 4 s ablak → `lastExaminedRecordCount ≤ 64`; 100 lépés playhead-mozgás → kumulatív ≤ 100 × 64; 2000 esemény, playhead a végén → ≤ 64. A `targetX` binary-search alsó határ + korai-kilépés felső határ tartja a keretet. |
| **A8** — nincs Learn-import / scoring | `practice_highway_import_guard_test.dart`: 5 teszt a 6 új fájl forrásán — egyetlen tiltott minta sem fordul elő. |
| **A9** — a11y / i18n / layout | Down/up/rest mind `Semantics(label: ...)`, a feedback szöveges címkét hord. 3/4 + 4/4 + 6/8 mind támogatott (külön cella). `l10n_parity_test` zöld (21 új kulcs mindkét nyelven). A `screen_size_guard_test` zöld (a `PracticeSessionScreen` `null host` ágon nem overflow). |
| **A10** — 0 sor a motor-rétegben | `git diff --stat origin/main...HEAD` üres a `domain/`, `application/`, `data/`, `lib/features/learn/` útvonalakon. |

### Záró gate — TÉNYLEGES kimenet

```
$ tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
Formatted 580 files (0 changed) in 2.04 seconds.
    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/
No issues found! (ran in 2.9s)
    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/
…
00:55 +715: All tests passed!
    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/core/l10n_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/l10n_parity_test.dart
00:00 +3: All tests passed!
    → [4] test test/core/l10n_parity_test.dart: ZÖLD

═══ [5] test test/core/screen_size_guard_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/screen_size_guard_test.dart
00:06 +39: All tests passed!
    → [5] test test/core/screen_size_guard_test.dart: ZÖLD

═══ [6] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart
Architecture dependencies OK (12 allowlisted deviation(s)).
    → [6] architecture: ZÖLD

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### Eltérések a brief-től és okuk

- **PracticeHighway `StatefulWidget`** (a StatelessWidget helyett): a
  `lastExaminedRecordCount` `int` mező, amit a `build` ír — a
  `@immutable` öröklődés a `StatelessWidget`-ről ezt warning szinten
  jelezte. A funkció változatlan: a `targetX` továbbra is pure függvény,
  a widget továbbra is meghívja azt; a `lastExaminedRecordCount` kizárólag
  az A7 méréshez kell.
- **A1 matrix "láthatósági ablak határa" cella** a `laneWidth =
  strikeX + 4 * pps` képletet feltételezi — ez a tesztkörnyezet, ahol a
  sáv szélessége pontosan `visibleSeconds` szélességű. A `+1µs` cella
  ugyanitt méri, hogy a láthatósági ablak túlcsordulása kiszűri.
- **A session screen most `lastVerdict: null` / `metrics: null`**
  konstruktor-paraméterrel hívja a mód-nézetet — R10 miatt a host-határ
  nem ad ki verdictet/metrikát, a tényleges bekötés a host-kör feladata.
  A widgetek ettől függetlenül helyesen renderelnek (az A5/A6 ezt méri).
- **`l10n` regen:** az ARB-kulcsok felvétele után a `lib/l10n/app_localizations*.dart`
  fájlokat a `flutter gen-l10n` (a l10n.yaml-t ideiglenesen félrehúzva)
  újragenerálta; ezt a `flutter test` automatikusan megteszi a CI-ban.

### Follow-upok

- A `PracticeSessionHost` bővítése a `verdicts`/`metrics` getterekkel
  (R10 zárása) — külön kör, határ-változás.
- A `chord_progression` View-ban a `Playhead`/Lane-gewometria
  finomhangolása valódi session-ön (a brief §3-ban jelzett "V2 először
  végigjátszható" mérés — a mostani build layout szinten helyes, a
  tényleges játék-próba a CI-APK-n történik).
- A mode-views a `countIn` státuszra is becsatlakoztathatók egy későbbi
  körben (most csak `running` + `paused`).


## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r14-review.md`

Kiemelt figyelem: **valódi-sértés próba** az A7 virtualizációra (a láthatósági
ablak ideiglenes kikapcsolása → pirosnak kell lennie), az A4 vizuális-latency
szétszivárgására, és arra, hogy az A1 „0 különbség = strikeX" cellája tényleg
egzakt egyenlőséget mér-e (ne `closeTo`).
