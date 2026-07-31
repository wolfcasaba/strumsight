# E02-R10 — Timing, direction és chord scorer

- **Státusz:** **PLANNING** (pre-flight lefuttatva 2026-07-31, kód újramérve:
  `main` @ `d7595c3`; előre megírva ugyanaznap `ce8fbce`-nél)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 10"** (+ §16 Pontozási rendszer)
- **Branch:** `codex/e02-r10-practice-scorers`
- **Előfeltétel:** **E02-R09 merge-ölve** (a matcher a scorer bemenete).
  ✅ **Teljesül:** PR #32 merge-elve 2026-07-31 (`e7942e6`); a §2.2 az így
  **mért** matcher-API-ra hivatkozik.
- **ADR:** **0076** — `docs/adr/0076-practice-scoring-dimensions.md`, **az orchestrátor
  írja meg a pre-flightban**, a §5 tartalmával. Az implementer **NEM hoz létre és
  NEM módosít `docs/adr/` fájlt**.
- **Implementer motor:** a pre-flightban a user dönt (ADR 0069 §15.6). *Ajánlás:*
  **Codex** — baseline-érzékeny kör, a legacy pont- és combo-paritás ítéletigényes.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra a mergelt matchert (`domain/service/practice_event_matcher.dart`,
>    **257 sor** — a brief eredeti 283-as száma elavult volt, lásd §0.0/R1) és a paritás-harnessét
>    (`test/features/practice/domain/practice_event_matcher_parity_test.dart`,
>    **652 sor**) — a §2.2 és az A7 erre épül.
> 2. Ellenőrizd az R09 review nyitott NOTE-jait: ami a scorert érinti, ide kerül §0.0-ként.
> 3. Ellenőrizd az ADR-szám ütközését (`ls docs/adr/`), majd írd meg az ADR 0076-ot.
>    **Az ADR 0076 kötelezően hivatkozzon az [ADR 0075 §2b](../adr/0075-practice-event-matcher.md)
>    védősáv-döntésére** — a scorer küszöbei ugyanazt az időalap-eltérést öröklik.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0.0 Pre-flight eredménye — BRIEF-REVÍZIÓ (2026-07-31, orchestrátor)

A pre-flight újramérte a brief minden load-bearing állítását `main` @ `d7595c3`-en.
**Az ADR 0076 megírva** (`docs/adr/0076-practice-scoring-dimensions.md`).

**Ami stimmel** (ne mérd újra, de ne is bízz benne vakon — a §9 gate a mérce):
`legacyLearnParity` ablakok 50/120/280 ms · a legacy konstansok (100/70/40,
`passThreshold 0.7`, `_chordLagSec 0.37`, multiplier-lépcsők 5/10/20) · a
matcher API §2.2 szerinti alakja · `Lessons.all` = **16** és a `firstWin`
**nincs** benne (⇒ a korpusz 17) · `chordStableDuration` alapérték **180 ms** a
`PracticeObservationConfig`-on · **az A1, A4 és A6 minden cellája** (`python3`-mal
újraszámolva, egyezik a briefben írtakkal, a 650-es hibás-implementáció-cellát
is beleértve).

**R1 — A matcher 257 sor, nem 283.** A ⚠ pre-flight 1. pontja és a §2.2
sorszáma elavult (a szám a merge előtti állapotból származott). A fájl
tartalma és API-ja változatlanul az, amit a §2.2 leír. **Semmit nem kell
emiatt másképp csinálnod** — a szám javítva, hogy ne keress nem létező 26 sort.

**R2 — `ChordOutcome.noDetection` MA NEM LÉTEZIK (blokkoló ütközés, feloldva).**
Mérve: `enum ChordOutcome { correct, wrong, insufficientData, notApplicable }`
(`practice_verdict.dart:33`) — négy érték. A §5.6 és az A3 viszont ötödikként
`noDetection`-t ír elő, miközben a §4 a `practice_verdict.dart`-ot **tiltott
zónába** tette. Ez az a hibaosztály, amit a projekt már mért („ne írj elő
viselkedést lezárt fájlra").

**Feloldás (ADR 0076 §5b):** a `practice_verdict.dart` felkerül az engedélyezett
fájlok listájára **CSAK ADDITÍV** jogosultsággal, és a `ChordOutcome` bővül a
`noDetection` értékkel, **az enum végére fűzve**. Meglévő érték átnevezése,
törlése, átsorolása, vagy bármi más módosítása ebben a fájlban → **`stopped`**.
Biztonságos: a `ChordOutcome`-nak ma egyetlen production fogyasztója sincs
(mérve: három találat, mind teszt-oldali konstrukció), tehát nincs kimerítő
`switch`, amit a bővítés törne.

**R3 — Az E02-R09 review NOTE-3 NEM ennek a körnek szól.** A „rendezetlen,
kézzel épített target" viselkedése a **hívó** felelőssége → E02-R11. Ha emiatt
akarnál a matcheren vagy a compileren változtatni: `stopped`.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy egymásnak / a mért állapotnak
ellentmondó előírás → `stopped` + pontos jelentés. **A §7 a terved.**

## 1. Cél

Az R09 matcher megmondja, **melyik megfigyelés melyik célesemény** — de nem mond
ítéletet. Ez a kör a **három score-dimenziót** (timing / direction / chord) és az
**aggregátort** hozza létre: pure, egymástól függetlenül tesztelhető domain
service-ekként, amelyek `PracticeVerdict` + `PracticeMetrics` értékeket állítanak
elő (mindkét modell az R03 óta kész, ez a kör az **első előállítójuk**).

Két dolog dönti el, hogy a kör sikerült-e:

1. a `legacyLearnParity` profilon a **pontszám, a combo és a találati arány
   bitre egyezik** a legacy `LessonScorer`-rel;
2. az **el nem érhető dimenzió nem jelenik meg 0%-ként** — sem a metrikában, sem
   az overall súlyozásában.

Hívó UI és provider **nincs** ebben a körben; a practice flagek OFF-ban maradnak,
a production viselkedés **változatlan**.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`; a pre-flight `d7595c3`-en újramérte — §0.0)

### 2.1 A paritás-referencia: `lib/features/learn/lesson_scorer.dart` (343 sor)

A pontozási magja (mérve, 136–148. és 262–290. sor):

```dart
static const _pointsPerfect = 100;   // |offset| <= perfectWindowSec (0.05)
static const _pointsGood    = 70;    // |offset| <= goodWindowSec    (0.12)
static const _pointsOffBeat = 40;    // window-on belül, de azon kívül
int get multiplier => combo >= 20 ? 4 : combo >= 10 ? 3 : combo >= 5 ? 2 : 1;
// hit:  combo++ ELŐSZÖR, majd score += base * multiplier  (a MÁR NÖVELT comboval)
// wrong: combo = 0, pont NEM jár
// missed (advance/finalize): combo = 0, pont NEM jár
```

További mért tények:

- `accuracy = hits / total` — a **helyes irányú** találatok aránya az **összes**
  céleseményre (nem a feloldottakra).
- `passed = total > 0 && accuracy >= 0.7` (`passThreshold`, 164. sor).
- `perfectHits` csak `Timing.perfect` esetén nő; a `Timing.early`/`late` a
  `goodWindow`-n kívüli, de a `windowSec`-en belüli találat (190–195. sor).
- Az akkord-pontozás **teljesen külön** ág (`_chordSlots`, `_chordObs`,
  `_chordLagSec = 0.37`, `_evalChords`): a `chordHits/chordTotal` **soha nem
  kapuzza** a strum-találatot, és a legacyben **NEM része** sem a `score`-nak,
  sem az `accuracy`-nek.
- A legacy akkord-ablak: a slot akkor értékelhető, ha
  `s.time + 0.37 + windowSec < elapsed`, és akkor helyes, ha
  `_chordAt(s.time) == s.chord || _chordAt(s.time + 0.37) == s.chord` — tehát
  **két mintavételi pont**, nem intervallum-többség (224–236. sor).

### 2.2 Amire épül (kész, változatlanul használandó)

- **R09 matcher (mérve, `practice_event_matcher.dart` 257 sor):**
  `PracticeEventMatcher({required CompiledPracticeTarget target, required
  ScoringProfile scoringProfile, required Duration inputLatency})`, és
  céleseményenként egy `PracticeEventMatchResult`:
  `targetIndex` · `target` (`CompiledTargetEvent`) · `resolution`
  (`PracticeTargetResolution { open, matched, missed, optionalUnmatched }`) ·
  `matchedObservationSequence` · `observedAt` · **`timingOffset`** (előjeles,
  negatív = korai) · `isMatched` / `isResolved` / `isMissed`.
  A matcher publikál `results` (unmodifiable, a `target.events` sorrendjében),
  `resolvedTargetCount`, `extraStrumCount`, és `@visibleForTesting`
  `examinedTargetRecordCount` / `retainedTargetRecordCount` számlálókat.
  **A konstruktorok privátak** (`PracticeEventMatchResult._`), tehát a scorer
  tesztjei a matcheren keresztül állítanak elő eredményt — mezőnként izolált
  konstrukció nem lehetséges (ez az E02-R09 mért tanulsága, `docs/LESSONS.md` L16).
- **`optionalUnmatched`** külön feloldás: párosítatlan **opcionális** cél —
  **nem** kimaradás. A scorer sem completionben, sem dimenzióban nem
  büntetheti.
- ⚠ **A matcher eredménye a párosított megfigyelés IRÁNYÁT nem hordozza**
  (E02-R09 review NOTE-2 — szándékos: a matcher pontozás-mentes, `O(célesemény)`
  memóriájú, és megfigyelést nem tárol). Csak a `matchedObservationSequence`
  van meg. **Következmény a direction-scorerre:** a hívónak (a scorer bemenetét
  összeállító oldalnak) **párban kell tartania** a `StrumObservation`-t a
  visszakapott `PracticeEventMatchResult`-tal — `sequence` szerinti
  megfeleltetéssel. Ezt a scorer API-jának **explicit bemenetként** kell
  kérnie (pl. `sequence → StrumObservation` leképezés vagy a megfigyelés-lista),
  **nem** szabad emiatt a matchert bővíteni (az kész, lezárt kör → `stopped`).
- `PracticeVerdict` + `TimingGrade` + `DirectionOutcome` + `ChordOutcome` +
  `PracticeCoachingCode` (`domain/model/practice_verdict.dart`, 176 sor). Mért
  validációs kényszerek, amelyeket a scorer kimenetének teljesítenie kell:
  - `eventScore` **véges és 0..1 között**;
  - ha `matchedObservationSequence == null`, akkor `observedAt == null` **és** a
    `timingGrade` csak `missed` vagy `notApplicable` lehet;
  - a `coachingCode` csak a `PracticeCoachingCode.values` ötelemű halmazból jöhet.
- `PracticeMetrics` + `MetricValue` sealed hierarchia
  (`MetricAvailable` 0..1 · `MetricNotApplicable` · `MetricInsufficientData(reasonCode)`).
  A `PracticeMetrics` **kötelező** mezői: `completion`, `rhythm`, `direction`,
  `chord`, `overall`, `totalTargets`, `resolvedTargets`, `maxCombo`,
  `scorePoints`, `meanAbsoluteOffset`, `timingBias` (előjeles, negatív = korai).
- `ScoringProfile` (233 sor) — öt const profil. **Mért drift az SDD §16.6-hoz
  képest:** a `chordProgressionDefault` súlyai a kódban **40/25/35**
  (rhythm/direction/chord), az SDD §16.6-ban 35/30/35. **A kód a mérce**
  (R03-ban így ment át a review-n és a validáció is erre épül); az eltérést az
  ADR 0076 rögzíti, **a súlyokat ebben a körben NEM írod át**.
- `StrumObservation` / `ChordObservation` (`practice_observation.dart`).
  A `ChordObservation.label` **nullable** (`null` = explicit „nincs akkord") és
  `isCanonicalPracticeChordLabel`-lel validált — tehát a scorernek **nem kell**
  címke-normalizálást végeznie, és **nem is szabad**: a `legacyPracticeChordLabel`
  a `data/adapters/` alatt van, a domain onnan nem importálhat.
- `PracticeAttemptResult` — `verdicts` listája **egyedi `targetEventId`**-kkal
  (mért validáció, 65–79. sor).

### 2.3 Ami MA nincs

- Nincs egyetlen scorer sem; a `domain/service/` alatt az R06 target compiler és
  (az R09 után) a matcher van.
- `PracticeVerdict`-et és `PracticeMetrics`-et **semmi nem állít elő** — csak
  tesztek konstruálják kézzel.
- Nincs metrika-hiány indokkód-készlet (`MetricInsufficientData.reasonCode`
  ma bármilyen nem üres string lehet).
- A `test/features/practice/domain/` **lapos** (nincs `service/` alkönyvtár) —
  kövesd ezt a mintát.

## 3. Scope

**Benne:** négy pure domain service (timing / direction / chord scorer +
aggregátor), a metrika-indokkódok stabil készlete, és a hozzájuk tartozó
egység-, paritás- és property-tesztek.

**Kívül (TILOS):**

- **`lib/features/learn/**` bármilyen módosítása** — a legacy `LessonScorer` a
  paritás **referenciája**. Olvasni és tesztből importálni szabad, írni nem.
- A `ScoringProfile` súlyainak / ablakainak megváltoztatása (lásd §2.2 drift).
- `PracticeSessionController`, provider, UI, hívó — **Kör 11+**.
- Coaching-szöveg, insight-prioritás, `PracticeCoach` — **Kör 18**. Ebben a
  körben a `coachingCode` **eseményszintű** és csak a meglévő öt kódból jöhet.
- Adaptív nehézség, Speed Builder küszöbök — **Kör 17**.
- Perzisztencia, history, progress — **Kör 18/19**.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, `pubspec.yaml`, DSP,
  `docs/rag/chunks/**`.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/domain/service/practice_timing_scorer.dart` | **ÚJ** | timing grade + event score + offset-statisztikák |
| `lib/features/practice/domain/service/practice_direction_scorer.dart` | **ÚJ** | direction outcome + dimenzió-érték |
| `lib/features/practice/domain/service/practice_chord_scorer.dart` | **ÚJ** | chord outcome + dimenzió-érték |
| `lib/features/practice/domain/service/practice_score_aggregator.dart` | **ÚJ** | verdict-lista + `PracticeMetrics` + pass/combo/pont |
| `lib/features/practice/domain/model/practice_metrics.dart` | — | **CSAK additív**: `PracticeMetricReasonCode` stabil kódkészlet (§5.7). Meglévő tag módosítása TILOS |
| `lib/features/practice/domain/model/practice_verdict.dart` | — | **CSAK additív, EGYETLEN változás** (§0.0/R2, ADR 0076 §5b): a `ChordOutcome` enum **végére** fűzött `noDetection` érték. Bármi más ebben a fájlban (meglévő érték átnevezése/törlése/átsorolása, mező, validáció, doc-comment) → **`stopped`** |
| `test/features/practice/domain/practice_timing_scorer_test.dart` | **ÚJ** | A1 mátrix |
| `test/features/practice/domain/practice_direction_scorer_test.dart` | **ÚJ** | A2 mátrix |
| `test/features/practice/domain/practice_chord_scorer_test.dart` | **ÚJ** | A3 mátrix |
| `test/features/practice/domain/practice_score_aggregator_test.dart` | **ÚJ** | A4–A6 |
| `test/features/practice/domain/practice_scorer_legacy_parity_test.dart` | **ÚJ** | A7 paritás a `LessonScorer`-rel |
| `test/property/practice_scorer_property_test.dart` | **ÚJ** | A9 randomizált property gate |
| `docs/rounds/e02-r10-practice-scorers.md` | — | **CSAK a §10** (handoff) kitöltése |

**Tilos zóna:** minden más. Nevezetesen `lib/features/learn/**`,
`lib/features/practice/` minden más fájlja (beleértve a `scoring_profile.dart`-ot;
a `practice_verdict.dart` a fenti táblázat szerinti EGYETLEN additív enum-értékre
szűkítve kivétel), `docs/adr/**`, `docs/sdd/**`, `HANDOFF.md`,
`.github/**`, `pubspec.yaml`, `tool/**`, `docs/rag/chunks/**`.

**Új fájl a fenti listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0076 — NEM tárgyalhatók)

1. **Négy külön, pure service.** Mindegyik önállóan példányosítható és
   tesztelhető; egyik sem hívja a másikat a bemenetén kívül. Flutter/Riverpod/Dio
   import TILOS (`package:meta` megengedett).
2. **A bemenet a matcher kimenete**, nem a nyers megfigyelés-folyam. A scorer
   **nem párosít újra** és nem lát `matchWindow`-t a profilon kívül.
3. **Minden pontszám belül EGÉSZ ezrelék (0..1000), kifelé `perMille / 1000`.**
   Ez teszi a kerekítést determinisztikussá és a teszt-egyenlőséget egzakttá
   (ugyanaz az `int → double` konstrukció mindkét oldalon). Lebegőpontos
   akkumuláció TILOS.
4. **Timing event score (ezrelék), `off = |observedAt − targetAt|`:**

   ```text
   off <= perfectWindow                    -> 1000   (TimingGrade.perfect)
   off <= goodWindow                       ->  800   (TimingGrade.good)
   off <= matchWindow -> 800 - (450 * (off - goodWindow)) ~/ (matchWindow - goodWindow)
                                                    (early ha offset < 0, egyébként late)
   nincs párosítás                         ->    0   (TimingGrade.missed)
   ```

   A `~/` **csonkoló** osztás (nulla felé) — a score sosem kerekedik fölfelé.
   A grade-határok **`<=`**-ek, a legacy `_timingFor` szerint.
5. **Direction:** csak azok a célesemények számítanak, amelyeknek **van**
   elvárt iránya. `correct = 1000`, `wrong = 0`, párosítatlan = `0`.
   Ha nulla ilyen célesemény van → `MetricNotApplicable` (**nem** 0).
   **A megfigyelt irány a bemenet része** (§2.2 utolsó pontja): a
   direction-scorer a `matchedObservationSequence`-hez tartozó
   `StrumObservation`-t **paraméterként** kapja. Hiányzó leképezés esetén
   fail-fast (`StateError`), **nem** csendes `wrong` — a néma hibás ítélet
   rosszabb, mint a leállás.
6. **Chord ablak:** `[targetAt − 120 ms, targetAt + 420 ms]`, mindkét vég
   **inkluzív**. A döntés az ablakba eső `ChordObservation`-ök alapján:
   - nincs egyetlen megfigyelés sem az ablakban → `ChordOutcome.insufficientData`;
   - az ablakban a **legtovább fennálló** címke (a `chordStableDuration`-nál
     rövidebb ideig fennálló címkék összevonás nélkül) egyezik az elvárttal →
     `correct`; ha nem egyezik → `wrong`;
   - ha minden ablakbeli megfigyelés `label == null` → `noDetection` (a
     `wrong`-tól **külön** érték: `insufficientData` NEM használható rá).
     ⚠ Ez az enum-érték MA NEM LÉTEZIK — **ez a kör hozza létre**, additívan,
     a `ChordOutcome` végére fűzve (§0.0/R2, ADR 0076 §5b);
   - ha egyetlen címke sem éri el a profil `chordStableDuration`-jét
     (⚠ ez a **gateway** configján van, nem a `ScoringProfile`-on — a scorer
     ezt **paraméterként kapja**, alapértéke `Duration(milliseconds: 180)`) →
     `wrong` **nem** adható; a kimenet `insufficientData`.
   Célesemény elvárt akkord nélkül → `ChordOutcome.notApplicable`.
7. **Metrika-indokkódok stabil készlete** (`PracticeMetricReasonCode`, additív a
   `practice_metrics.dart`-ban), legalább:
   `practice.metric.no_signal` · `practice.metric.no_applicable_targets` ·
   `practice.metric.chord_unstable` · `practice.metric.insufficient_samples`.
   Szabad string reason-code a scorerből **nem** kerülhet ki.
8. **Overall: EGYETLEN csonkoló osztás, az elérhető dimenziókra.**

   ```text
   overallPerMille = Σ(weight_i * scorePerMille_i) ~/ Σ(weight_i)
   ```

   ahol `i` **kizárólag** az `MetricAvailable` dimenziókon fut. Nem elérhető
   dimenzió **kimarad a nevezőből is** — nulla értékkel beszámítani TILOS.
   Ha nincs egyetlen elérhető súlyozott dimenzió sem (pl. `freePracticeOpen`
   üres súlyokkal) → `overall = MetricNotApplicable`.
9. **Completion:** `resolvedTargets / totalTargets` ezrelékben, ahol „resolved" =
   minden **kötelező** (nem `optional`) célesemény, amit a matcher lezárt.
   Külön kapu: a pass **csak akkor** igaz, ha
   `completionPerMille >= completionThresholdPercent * 10`
   **és** `overallPerMille >= overallThresholdPercent * 10`.
10. **Combo és pont — legacy-paritással.** `combo++` a tiszta feloldás
    **előtt** növekszik, majd `points += base * multiplier(combo)`; a
    multiplier lépcsői `5/10/20 → ×2/×3/×4`; a base `100/70/40` a
    `perfect/good/egyéb-találat` szerint. `wrong` és `missed` **nullázza** a
    combót és nem ad pontot. `optional` célesemény a combót **nem** befolyásolja.
11. **`timingBias` előjeles**: a párosult célesemények `observedAt − targetAt`
    értékeinek átlaga egész µs-ban, csonkolva nulla felé. `meanAbsoluteOffset`
    ugyanez abszolút értékekkel. Párosítás nélkül mindkettő `Duration.zero`.
12. **A legacy pass-szabály NEM ez.** A legacy `accuracy >= 0.70` és a
    §5.9 kettős kapuja **különböző** politika. A scorer az újat implementálja;
    a migrált Learn pass-leképezése az **E02-R19** hatásköre. Ezt az ADR 0076
    rögzíti, és a paritás-teszt (A7) **nem** a `passed` mezőt hasonlítja.
13. **A µs-kvantált időalap az igazság** ([ADR 0075 §2b](../adr/0075-practice-event-matcher.md)).
    A scorer a compiled targetet követi, nem a legacy `double`-t; a legacyvel
    való egyezés a döntési határoktól **levezetett** védősávon kívül érvényes
    (A7 / A7b / A7c). A `double` időalap visszahozása a domainbe **TILOS** —
    két lezárt kört nyitna újra (ADR 0066 / 0072).

## 6. Acceptance criteria

Minden pont mellett ott van, **melyik hibás implementációt fogja pirosra**.

### A1 — Timing-mátrix a származtatott ezrelék-értékre

`legacyLearnParity` ablakokkal (perfect 50 ms, good 120 ms, match 280 ms). A
táblázat oszlopa a **származtatott** érték, nem a bemenet:

| `off` (µs) | elvárt ezrelék | elvárt grade |
|---|---|---|
| 0 | 1000 | perfect |
| 49 999 | 1000 | perfect |
| **50 000** | **1000** | **perfect** (`<=`) |
| 50 001 | 800 | good |
| 119 999 | 800 | good |
| **120 000** | **800** | **good** (`<=`) |
| 120 001 | 800 | early/late |
| 200 000 | 575 | early/late |
| 279 999 | 351 | early/late |
| **280 000** | **350** | **early/late** (`<=`) |
| nincs párosítás | 0 | missed |

Mindegyik cella **mindkét előjellel** (korai és késői), és az előjel dönti el az
`early`/`late` grade-et. A cellák értékeit `python3 -c`-vel ellenőriztem, az
implementernek is így kell (ne fejben).

***Pirosra fogja:*** a `<` / `<=` felcserélése bármelyik határon; a lineáris
szakasz fordított iránya; a lebegőpontos `0.8 - 0.45 * ratio` alak (ez a
`match` határon `0.35000000000000003`-at ad, tehát a 350-es cella megbukik).

**NEM elfogadható gyengítés:** `closeTo`/epszilon a cella-ellenőrzésben; a
határcellák elhagyása „a lineáris szakasz úgyis folytonos" indoklással.

### A2 — Direction-mátrix

| Cél iránya | Párosítás | Megfigyelt irány | Elvárt outcome | Dimenzióba számít? |
|---|---|---|---|---|
| van | van | egyezik | `correct` | igen, 1000 |
| van | van | eltér | `wrong` | igen, 0 |
| van | nincs | — | `wrong` *(párosítatlan)* | igen, 0 |
| nincs | van | bármi | `notApplicable` | **nem** |
| nincs | nincs | — | `notApplicable` | **nem** |

Plusz: **nulla irányos célesemény** → `direction == MetricNotApplicable`;
**van irányos célesemény, de nulla strum-megfigyelés érkezett** →
`MetricInsufficientData(PracticeMetricReasonCode.noSignal)` — **nem** 0.

***Pirosra fogja:*** a „nincs jel = 0% irányhelyesség" implementáció, ami a
felhasználót olyasmiért bünteti, amit meg sem mértünk.

**NEM elfogadható gyengítés:** a `notApplicable` és az `insufficientData`
összevonása egyetlen „nincs adat" ágba — a kettő **különböző** UI-t és
coachingot jelent (Kör 18).

### A3 — Chord-ablak mátrix (három cella minden határon)

Cél `targetAt = T`, elvárt akkord `G`. Egyetlen `ChordObservation` `G` címkével:

| Megfigyelés ideje | Elvárt |
|---|---|
| `T − 120 001 µs` | ablakon KÍVÜL |
| **`T − 120 000 µs`** | **ablakon belül** (inkluzív) |
| `T − 119 999 µs` | ablakon belül |
| `T + 419 999 µs` | ablakon belül |
| **`T + 420 000 µs`** | **ablakon belül** (inkluzív) |
| `T + 420 001 µs` | ablakon KÍVÜL |

Plusz mind az öt kimeneti ág külön esete: `correct` · `wrong` (más címke) ·
`noDetection` (csak `label == null` az ablakban) · `insufficientData` (üres ablak
**vagy** a stabilitási küszöböt egyik címke sem éri el) · `notApplicable`
(elvárt akkord nélküli célesemény).

***Pirosra fogja:*** a szimmetrikus ±270 ms-os ablak (a chord detection késését
figyelmen kívül hagyó „egyszerűsítés"), és a `null` címke `wrong`-ként kezelése.

**NEM elfogadható gyengítés:** a `noDetection` beolvasztása a `wrong`-ba
„úgyis nulla pont" indoklással, vagy az `insufficientData`-ba „úgyis nincs adat"
indoklással — a `ChordOutcome` enum **öt** értéke (a körben hozzáadott
`noDetection`-nel együtt) a szerződés, és az E02-R15 UI-ja már erre épül.

### A4 — Overall: az el nem érhető dimenzió nem nulla

`chordProgressionDefault` (40/25/35), `rhythm = 1000`, `direction = 1000`,
`chord = MetricNotApplicable`:

- **helyes:** `overall = (1000*40 + 1000*25) ~/ 65 = 1000`;
- a nulla-kitöltéses hibás implementáció `(40000 + 25000) ~/ 100 = 650`-et ad.

További kötelező cellák (mind `python3`-mal számolva):

| Profil | rhythm | direction | chord | elvárt overall |
|---|---|---|---|---|
| `legacyLearnParity` (55/45) | 750 | 500 | n/a | **637** |
| `chordProgressionDefault` | 333 | 777 | n/a | **503** |
| `chordChangeDefault` (chord 60 / rhythm 40) | 600 | n/a | 900 | **780** |
| `rhythmOnlyDefault` (rhythm 100) | 642 | n/a | n/a | **642** |
| `freePracticeOpen` (üres súlyok) | — | — | — | **`MetricNotApplicable`** |

***Pirosra fogja:*** a nulla-kitöltés, a kétlépcsős (előbb súly-újranormálás,
majd szorzás) kerekítés, és a `freePracticeOpen`-re adott 0-s overall.

**NEM elfogadható gyengítés:** „a Free Practice overall úgyis rejtve van a
UI-ban" — a modellben `MetricNotApplicable`-nek kell lennie, mert az R18 result
és az R19 progress ebből olvas.

### A5 — Completion-kapu és pass

`completionThresholdPercent = 85`, `overallThresholdPercent = 70`, 20 kötelező
célesemény. Három cella a completionre (`resolved = 16 / 17 / 18` → 800 / 850 /
900 ezrelék) × két cella az overallra (699 / 700 ezrelék):

- `completion = 850` **és** `overall = 700` → **passed**;
- `completion = 850`, `overall = 699` → **failed**;
- `completion = 800`, `overall = 1000` → **failed** (a completion-kapu fog);
- egyetlen célesemény sem oldódott fel → `incomplete`, **nem** `failed`.

***Pirosra fogja:*** a „kevés, de jó eventtel is átmegy" hiba (SDD §16.6 külön
kiemeli), és a `>=` → `>` csúszás bármelyik küszöbön.

### A6 — Combo és pont

- `combo` a **növelés utáni** multiplierrel szoroz (legacy-sorrend): öt egymás
  utáni perfect találat pontszáma `100*1 + 100*1 + 100*1 + 100*1 + 100*2 = 600`.
- `wrong` és `missed` nulláz; `optional` célesemény **nem** nulláz és nem növel.
- `maxCombo` a futás maximuma.

***Pirosra fogja:*** a „szorozzunk a növelés ELŐTTI multiplierrel" sorrend-csúszás
(az ötödik találatnál tér el először), és az `optional` események combóba számítása.

### A7 — Legacy paritás a levezetett védősávon KÍVÜL, egzakt

> **A mérés alakja itt kötött, és NEM „tűrés nélküli mindenhol".** Az E02-R09
> kimérte ([ADR 0075 §2b](../adr/0075-practice-event-matcher.md),
> [`docs/LESSONS.md` L16](../LESSONS.md)): a legacy `LessonScorer` **kerekítetlen
> `double` másodpercekkel** dönt, a compiled target **egész µs**-mal, és a két
> időalap **legfeljebb 0,5 µs**-ban eltér (mérve: **0,489795919508 µs**,
> `anthem-drive[23]`). A feltétel nélküli µs-paritás ezért **matematikailag
> teljesíthetetlen** — ne is próbáld, és ne is lazíts rajta tűréssel.

Paritás-teszt, ami ugyanazt a lecke-tartalmat és ugyanazt a pengetés-sorozatot
futtatja át a legacy `LessonScorer`-en és az új láncon (matcher → scorer →
aggregátor), `legacyLearnParity` profillal. **Egzakt egyenlőség minden olyan
futásra, amely a levezetett védősávon kívül van** — a sáv a §5.4 három
küszöbére (`perfectWindow`, `goodWindow`, `matchWindow`) az ADR 0075 §2b
mintájára: egy esemény akkor esik a sávba, ha
`| |offset| − küszöb | < 1 µs` bármelyik küszöbre. Sávon kívül **tűrés nincs**:

| Legacy | Új |
|---|---|
| `score` | `metrics.scorePoints` |
| `maxCombo` | `metrics.maxCombo` |
| `hits` | `DirectionOutcome.correct` verdictek száma |
| `wrong` | `DirectionOutcome.wrong` **párosult** verdictek száma |
| `missed` | párosítatlan verdictek száma |
| `accuracy` | `metrics.direction` (**mert minden strum-target irányos**) |
| `perfectHits` | `TimingGrade.perfect` verdictek száma |

A korpusz a **teljes szállított lecke-katalógus**: `Lessons.all` (**16 lecke**,
`lib/features/learn/model/lesson.dart:321–338`) **plusz** `Lessons.firstWin`
(uo. 146. sor) — összesen **17**, mindegyik legalább három latency-értékkel
(`0 ms`, `40 ms`, **`300 ms`** — az utolsó szándékosan NAGYOBB a 280 ms-os
match window-nál).

A **`passed`/`outcome` mezőt NEM hasonlítod** (§5.12) — az eltérő pass-politika
szándékos, és az ADR 0076 rögzíti.

***Pirosra fogja:*** a pontrendszer bármelyik konstansának elcsúszása, a
combo-sorrend, és a timing-sávok határainak eltolása.

**NEM elfogadható gyengítés:** a korpusz egyetlen leckére szűkítése; `closeTo`
vagy epszilon-tűrés a **sávon kívüli** cellákban; a `chordHits` bevonása a
paritásba (a legacyben külön ág, lásd §2.1); a védősáv **kiszélesítése** azért,
hogy egy eltérés beleférjen.

### A7b — A védősáv szélessége MÉRVE, nem feltételezve

A paritás-harness minden vizsgált eseményre kiszámolja a legacy `double`-ból és
a compiled targetből adódó időt, és **állítja**, hogy az eltérés
`<= 0,5 µs`. A mért maximumot és az azt adó eseményt a §10-be be kell írni.
A **kizárt** (sávba eső) események száma is jelentendő — ha ez a szám nagy,
az lelet, nem részlet.

**A mérés eszköze:** az R09 harness (`practice_event_matcher_parity_test.dart`,
652 sor) ezt már megcsinálta a párosítási küszöbre — **azt a mintát** vedd át a
három grade-küszöbre.

### A7c — A sávba eső cellák KIPINNELVE

Minden olyan (lecke, esemény, latency) hármas, ahol a scorer szándékosan eltér a
legacytől, **saját tesztcellát** kap a konkrét számokkal — a divergencia
megnevezett, őrzött viselkedés, nem meglepetés. A cellákat a **tényleges**
esemény-listából generáld (`python3`-mal bejárva), soha nem idealizált rácsból
(ez az E02-R09 második mért hibája volt).

> **Ha a te mérésed eltér az itt írtaktól, az `stopped` a két számmal — NEM
> csendes hozzáigazítás.** (Ez a mondat fogta meg az E02-R09-ben a hibás
> referenciacellát.)

### A8 — A verdict-lista érvényes

Minden előállított `PracticeVerdict.validate()` **üres** listát ad, és a
`PracticeAttemptResult.validate()` is — beleértve a `targetEventId` egyediségét.
Ez a mérés a §5.2 szerződését köti a meglévő R03 modell-validációhoz.

***Pirosra fogja:*** a párosítatlan verdictre adott `TimingGrade.late`
(a modell `verdictMatchInconsistent` kóddal bukik), és a nem kanonikus
`coachingCode`.

### A9 — Randomizált property gate

`test/property/practice_scorer_property_test.dart`, `PROPERTY_SEED` (hiány → 42),
a meglévő property-tesztek mintája szerint. Legalább:

1. minden dimenzió-érték `MetricAvailable` esetén **0..1** között van;
2. `overall` sosem nagyobb az elérhető dimenziók maximumánál és sosem kisebb a
   minimumuknál (súlyozott átlag-invariáns);
3. `scorePoints` monoton nő, ha egy `wrong` verdictet `correct`-ra cserélünk
   (minden más változatlan);
4. `resolvedTargets <= totalTargets` **minden** generált futásra;
5. **nulla megfigyelés** esetén egyetlen dimenzió sem `MetricAvailable(0)` —
   vagy `NotApplicable`, vagy `InsufficientData`.

A küszöbök invariáns-jellegűek vagy %-alapúak (nem flaky-k).

### A10 — Domain-tisztaság és nulla viselkedésváltozás

`tools/round-gate.sh` **architecture** lépése zöld, `domain_purity_test.dart`
zöld, az architektúra-allowlist **nem bővül**. `git diff --stat origin/main...HEAD`
→ a `lib/` alatt kizárólag a négy új service + a `practice_metrics.dart` additív
blokkja + a `practice_verdict.dart` **egysoros** `noDetection` enum-bővítése
(§0.0/R2); `lib/features/learn/` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **ADR 0076**, az R09 matcher API-ja, `practice_verdict.dart`,
   `practice_metrics.dart`, `scoring_profile.dart`, és a legacy
   `lesson_scorer.dart` 136–321. sorát.
2. **Előbb a paritás-harness (A7)**, pirosan — a mérce legyen kész a kód előtt.
3. `practice_timing_scorer.dart` + A1 mátrix.
4. `practice_direction_scorer.dart` + A2 mátrix.
5. `practice_chord_scorer.dart` + A3 mátrix.
6. `PracticeMetricReasonCode` (additív) — csak amikor az első valódi hívója kész.
7. `practice_score_aggregator.dart` (overall + completion + pass + combo/pont) +
   A4–A6.
8. A7 zöldre; A8 modell-validációs teszt.
9. A9 property-teszt.
10. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **Az időalap-eltérés a grade-küszöbökön.** A párosításnál az E02-R09 már
  kimérte; a **timing grade** három küszöbén (perfect/good/match) ugyanez a
  ≤ 0,5 µs eltérés flippelheti a `perfect`/`good` besorolást, és azon keresztül
  a **pontszámot** (100 vs. 70). Ezért van A7b (a sáv mérése) és A7c (a
  divergencia-cellák kipinnelése). Ha úgy találod, hogy a sáv szélesebb a
  levezetettnél → `stopped` a mért számmal.
- **Lebegőpontos csúszás.** A `0.8 - 0.45` alak `0.35000000000000003`-at ad —
  ezért kötelező az egész-ezrelék belső ábrázolás (§5.3). Ha bárhol `double`
  akkumulációt látsz a saját kódodban, az hiba, nem stílus.
- **A legacy combo-sorrend.** A `score += base * multiplier` a **már növelt**
  combóval számol. Ez az a fajta „nyilvánvalóan mindegy" részlet, ami a
  paritás-tesztet az ötödik találatnál buktatja.
- **A chord-ág külön világ.** A legacy `chordHits` nem része sem a `score`-nak,
  sem az `accuracy`-nek; ha bevonod a paritásba, hamis pirosat kapsz és
  „javítani" kezded a helyes kódot.
- **`ScoringProfile` drift (§2.2).** Csábító lesz a `chordProgressionDefault`-ot
  az SDD 35/30/35-re „javítani". **Ne.** Az a fájl tilos zóna; az eltérést az
  ADR rögzíti.
- **A stabilitási küszöb nem a profilon van.** A `chordStableDuration` a
  `PracticeObservationConfig`-on él (gateway, R08). A scorer paraméterként kapja
  — ha a `ScoringProfile`-ba akarod tenni, az `stopped` + jelentés, nem csendes
  modellbővítés.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/property/practice_scorer_property_test.dart
```

Csővezeték nélkül (se `| tail`, se `| head`, se `| grep`, se `&&` láncolás), a
teljes kimenetet a §10-be. A teljes suite + a randomizált property gate + az APK
a CI-ban fut, merge előtt, orchestrátor-dispatch-csel (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · nem futtatott ellenőrzések
és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r10-review.md`

Kiemelt figyelem a review-nak: **eldobható próbateszt** az A4 nulla-kitöltéses
hibára (a helyes kódnak 1000-et, a hibásnak 650-et kell adnia), a §5.3 egész-
ezrelék szerződés **valódi-sértés próbája** (ideiglenes `double`-akkumuláció →
az A1 350-es cellájának pirosra kell futnia), és az A7 korpusz teljességének
ellenőrzése (17 lecke × 3 latency, ne egy szűkített lista).
