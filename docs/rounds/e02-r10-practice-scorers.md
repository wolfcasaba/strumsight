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

### Összefoglaló

Az ADR 0076 szerinti négy pure domain service elkészült. A timing, direction, chord és aggregátor útvonal belül kizárólag egész ezreléket akkumulál; a nem mérhető dimenziók kimaradnak az overall számlálójából és nevezőjéből. A záró gate alábbi, friss futása mind az öt lépésen zöld volt.

### Fájlonkénti összefoglaló

- `lib/features/practice/domain/model/practice_metrics.dart` — additív `PracticeMetricReasonCode` kódkészlet és stabil `values` halmaz.
- `lib/features/practice/domain/model/practice_verdict.dart` — a `ChordOutcome` enum végére fűzött `noDetection`; a formatter miatti sortörésen túl ez az egyetlen szemantikai változás.
- `lib/features/practice/domain/service/practice_timing_scorer.dart` — egész ezrelékes timing-grade és pont, valamint előjeles bias és abszolút offset-statisztika.
- `lib/features/practice/domain/service/practice_direction_scorer.dart` — target-index alapú, restart-biztos observation-társítás, fail-fast konzisztencia-ellenőrzés és iránymetrika.
- `lib/features/practice/domain/service/practice_chord_scorer.dart` — inkluzív `[-120 ms, +420 ms]` ablak, stabil szegmensválasztás, öt outcome és egész ezrelékes aggregáció.
- `lib/features/practice/domain/service/practice_score_aggregator.dart` — overall, completion/pass, legacy combo/pont, verdict- és attempt-előállítás.
- `test/features/practice/domain/practice_timing_scorer_test.dart` — A1 határmátrix, integer aggregáció, jelhiány, optional célok és csak olvasható event-score nézet.
- `test/features/practice/domain/practice_direction_scorer_test.dart` — A2 mátrix, reason code-ok, restart-biztos mapping, optional célok és hibás mapping fail-fast esetei.
- `test/features/practice/domain/practice_chord_scorer_test.dart` — A3 ablak-, outcome-, stabilitás-, aggregáció-, optional- és nézetmódosítási tesztek.
- `test/features/practice/domain/practice_score_aggregator_test.dart` — A4–A6 és A8, completion/optional izoláció, combo reset és loop-ID egyediség.
- `test/features/practice/domain/practice_scorer_legacy_parity_test.dart` — A7 egzakt legacy paritás, A7b időalap-mérés és A7c tényleges eseménylistás divergenciaháló.
- `test/property/practice_scorer_property_test.dart` — A9 seedelt randomizált invariánsok.
- `docs/rounds/e02-r10-practice-scorers.md` — ez az implementation handoff és a teljes záró gate-evidencia.

### Acceptance criteria — bizonyíték

- **A1:** `practice_timing_scorer_test.dart` / `PracticeTimingScorer A1 boundary matrix` a 10 numerikus offsetet mindkét előjellel, egzakt grade-del és ezrelékkel ellenőrzi; `an unmatched required target is a zero-score miss` a párosítatlan ágat, `uses integer accumulation and one truncating mean division` az integer aggregációt köti.
- **A2:** `practice_direction_scorer_test.dart` / `PracticeDirectionScorer A2 matrix` fedi a correct, wrong, unmatched, notApplicable és nulla-jeles noSignal cellákat. A `target-index pairing supports restarted observation sequences` és a két fail-fast mapping teszt az explicit, restart-biztos társítást őrzi.
- **A3:** `practice_chord_scorer_test.dart` / `PracticeChordScorer A3 inclusive asymmetric window` mind a hat határcellát, az `A3 outcome branches` pedig a correct, wrong, noDetection, két insufficientData és notApplicable ágat ellenőrzi.
- **A4:** `practice_score_aggregator_test.dart` / `does not fill an unavailable chord dimension with zero` egzakt 1000-et vár a hibás 650 helyett; `pins every integer overall table cell` a 637/503/780/642 cellákat, `free practice has no overall score` a `MetricNotApplicable` eredményt köti.
- **A5:** ugyanott a `PracticeScoreAggregator A5 completion and pass gate` a 16/17/18 × 699/700 teljes mátrixot fedi; külön teszt köti az `incomplete` nulla-resolved ágat és a matched/unmatched optional célok completionből való kizárását.
- **A6:** `A6 increments combo before the fifth-hit multiplier` az öt perfect találatra 600 pontot és 5-ös max combót vár. A wrong/miss reset tesztek a reset utáni tiszta találatot is ellenőrzik; a matched correct/wrong optional esetek sem növelést, sem nullázást nem engednek.
- **A7:** `practice_scorer_legacy_parity_test.dart` kipinneli a 16 katalógusleckét plusz `first-win`-t, majd 17 × 3 = 51 scenario esetén egzakt `score`, `maxCombo`, hits/wrong/missed, direction és perfectHits paritást vár. A szándékosan eltérő pass/outcome nincs összehasonlítva.
- **A7b:** `measures the compiled timebase guard at at most 0.5 us` 348 tényleges eseményt mér. A maximum **0.489795919508 µs**, eseménye **`anthem-drive[23]`** (`legacyTarget=11938775.51020408 µs`, `compiledTarget=11938776 µs`). Ez target-időalapból eredő, latency-független eltérés, tehát **0, 40 és 300 ms latency mellett holtversenyben ugyanaz**; konkrét hármasként: **`anthem-drive[23] @ 0 ms`**. A mért maximum megegyezik a brief 0.489795919508 µs értékével, és kisebb a levezetett 0.5 µs korlátnál. Az A7 paritás során a sávba eső, ezért kizárt események száma: **0**.
- **A7c:** `pins 18 representative extrema divergence cells` 18 kézi szélső cellát őriz; `discovers and pins every actual boundary divergence cell` a tényleges 348 esemény × 3 küszöb × 3 latency × 2 előjel terét járja, minden divergencián per-case assertiont futtat. Mért divergenciacellák: **3213**, teljes fingerprint: **375672841**.
- **A8:** `A8 every verdict and the complete attempt result are valid` minden verdictre és az attemptre üres `validate()` eredményt vár; az ismételt source ID-kből `repeat@0`, `repeat@1`, `repeat@2` egyedi target ID-k készülnek.
- **A9:** `practice_scorer_property_test.dart`, lokális seed **42**. Az `available metrics are normalized and overall stays in range` az 1., 2. és 4. invariánst, a `changing one wrong direction to correct never lowers points` a 3.-at, a `zero observations never become a zero-valued scoring dimension` az 5.-et fedi.
- **A10:** a záró gate `analyze`, practice domain purity és `architecture` lépése zöld (`Architecture dependencies OK (12 allowlisted deviation(s))`). A scope-audit szerint `lib/features/learn/` változása 0; a `lib/` diff kizárólag a briefben engedélyezett hat production fájlra korlátozódik, az allowlist nem bővült.

### Mért A7 összegzés

- Leckekorpusz: 17; latencyk: 0/40/300 ms; paritási scenariók: 51.
- Mért target események: 348.
- A7b maximum: 0.489795919508 µs, `anthem-drive[23]`, mindhárom latency mellett; konkrét cella: `anthem-drive[23] @ 0 ms`.
- Védősávba eső, paritásból kizárt események: 0.
- A7c reprezentatív cellák: 18; exhaustive divergenciacellák: 3213; fingerprint: 375672841.

### Eltérések és okuk

- Kötött termék-, algoritmus- vagy fájlscope-eltérés nincs; a mért A7b maximum megegyezik a brief értékével.
- Az A7c 3213 cellája egy exhaustive teszten belüli per-case assertionnel és teljes fingerprinttel van kipinnelve, nem 3213 külön `test()` deklarációval; a tényleges eseménylista teljes vizsgált tere így végigellenőrzött.
- A direction bemenet target-index szerint társít, és külön ellenőrzi a matched sequence egyezését. Erre azért van szükség, mert a gateway observation sequence-e újraindulhat; a sequence-only map érvényes eseményt felülírhatna. Ez a §5.5 explicit mapping szerződésének restart-biztos megvalósítása.
- A lezárás során nem volt piros gate-lépés és nem kellett kódot javítani. Két korábbi, ugyanezzel a pontos paranccsal indított zöld futás kimenetét az eszközgyűjtő előbb elvesztette, majd egy csomagban csonkította; ezért a lent közölt futást sűrű, 60 000 tokenes csomaggyűjtéssel ismételtem meg. A közölt kimenet a friss, exit 0-s, teljes és csonkítatlan futás.

### Nem futtatott ellenőrzések

- A teljes `flutter test`, a friss randomizált CI property gate és a release APK nem futott lokálisan: ADR 0053 szerint ezeket az orchestrátor dispatch-eli CI-ban merge előtt.
- `gh`, push, PR-nyitás és CI-dispatch nem történt, az implementer-prompt kifejezett tiltása szerint.
- Backend- és ML-gate nem futott, mert a kör nem módosít backend- vagy ML-fájlt.

### Follow-upok

- Claude független review-ja, majd a teljes suite/property/APK CI-dispatch, PR és a zöld-kapus merge az orchestrátor feladata.
- A sequence-restart és az exhaustive A7c-háló tanulsága a reviewer/orchestrátor által emelhető át `docs/LESSONS.md`-be; ez a fájl nem volt az implementer engedélyezett listáján.
- Következő SDD-kör: **E02-R11**.

### Záró gate — friss, teljes kimenet

Parancs (exit code: 0):

````text
tools/round-gate.sh test/features/practice/ test/property/practice_scorer_property_test.dart
````

Tényleges, teljes, csonkítatlan kimenet:

````text

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 542 files (0 changed) in 1.84 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...
No issues found! (ran in 2.7s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:00 +9: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:00 +10: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:00 +11: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:00 +12: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:00 +13: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:00 +14: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:00 +15: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:00 +16: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:00 +17: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:00 +18: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:00 +19: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:00 +20: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:01 +21: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:01 +27: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:01 +28: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:01 +29: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:01 +30: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:02 +31: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:02 +32: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:02 +33: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:02 +34: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:02 +35: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:02 +36: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:02 +37: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:02 +38: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:02 +39: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:02 +40: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:02 +41: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:02 +42: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:02 +43: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:02 +44: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:02 +45: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:02 +46: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:02 +47: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:02 +48: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:02 +49: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:02 +50: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:03 +51: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:03 +52: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:03 +53: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:03 +54: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:03 +55: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:03 +56: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:03 +57: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:03 +58: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:03 +59: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:04 +60: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:05 +61: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:05 +62: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:06 +63: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:06 +64: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:06 +65: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:06 +66: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:06 +67: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:06 +68: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:06 +69: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:06 +70: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:06 +71: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:06 +72: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:07 +73: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:07 +74: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:07 +75: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:07 +76: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:07 +77: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:07 +78: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:07 +79: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:07 +80: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:07 +81: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:07 +82: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:07 +83: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:07 +84: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:07 +85: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:07 +86: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:07 +87: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:07 +88: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:07 +89: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:07 +90: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:07 +91: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:07 +92: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:07 +93: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:07 +94: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:07 +95: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:07 +96: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:07 +97: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:07 +98: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:07 +99: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:07 +100: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:07 +101: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:08 +102: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:08 +103: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:08 +104: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:08 +105: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:08 +106: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:08 +107: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:08 +108: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:08 +109: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:08 +110: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:08 +111: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:08 +112: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:08 +113: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:08 +114: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:08 +115: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:08 +116: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:08 +117: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:08 +118: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:08 +119: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:08 +120: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:08 +121: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:08 +122: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:08 +123: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:08 +124: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:08 +125: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:08 +126: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:08 +127: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:08 +128: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:09 +129: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:09 +130: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:09 +131: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:09 +132: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:09 +133: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:09 +134: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:09 +135: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:09 +136: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:09 +137: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:09 +138: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:09 +139: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:09 +140: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:09 +141: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:09 +142: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:09 +143: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:09 +144: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:09 +145: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:09 +146: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:09 +147: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:09 +148: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:09 +149: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:09 +150: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:09 +151: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:09 +152: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:09 +153: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:09 +154: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:09 +155: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:09 +156: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:09 +157: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:09 +158: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:09 +159: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:09 +160: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:09 +161: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:09 +162: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:09 +163: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:09 +164: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:09 +165: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:09 +166: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:09 +167: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:09 +168: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:11 +169: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:11 +170: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:11 +171: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:11 +172: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:11 +173: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:11 +174: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:11 +175: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:11 +176: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:11 +177: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:11 +178: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:11 +179: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:11 +180: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:11 +181: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:11 +182: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:13 +183: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:13 +184: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:13 +185: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:13 +186: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:13 +187: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:13 +188: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:13 +189: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:13 +190: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:13 +191: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:13 +192: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:13 +193: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:13 +194: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:13 +195: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:13 +196: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:13 +197: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:13 +198: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:13 +199: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:13 +200: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:13 +201: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:13 +202: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:13 +203: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:13 +204: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:13 +205: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:13 +206: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:13 +207: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:13 +208: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:13 +209: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:13 +210: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:13 +211: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:13 +212: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:13 +213: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:13 +214: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:13 +215: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:13 +216: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:13 +217: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:13 +218: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:13 +219: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:13 +220: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:13 +221: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:13 +222: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:13 +223: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:13 +224: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:13 +225: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:13 +226: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:13 +227: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:14 +228: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:14 +229: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:14 +230: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:14 +231: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:14 +232: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:14 +233: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:14 +234: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:14 +235: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:14 +236: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:14 +237: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:14 +238: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:15 +239: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:15 +240: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:15 +241: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:15 +242: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:15 +243: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:15 +244: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:15 +245: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:15 +246: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:15 +247: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:15 +248: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:15 +249: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:15 +250: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:15 +251: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:15 +252: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:15 +253: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:15 +254: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:15 +255: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:15 +256: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:15 +257: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:15 +258: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:15 +259: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:15 +260: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:15 +261: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:16 +262: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:16 +263: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:16 +264: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:16 +265: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:16 +266: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:16 +267: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:16 +268: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:16 +269: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:16 +270: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:16 +271: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:16 +272: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:16 +273: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:16 +274: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:16 +275: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:16 +276: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:16 +277: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:16 +278: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:16 +279: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:16 +280: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:16 +281: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:16 +282: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:16 +283: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:16 +284: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:17 +285: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:17 +286: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:17 +287: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:17 +288: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:17 +289: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:17 +290: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:17 +291: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:17 +292: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:17 +293: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:17 +294: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:17 +295: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:17 +296: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:17 +297: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:17 +298: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:17 +299: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:17 +300: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:17 +301: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:17 +302: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:17 +303: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:17 +304: /home/ubuntu/ss-codex-e02-r10/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:18 +305: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog contains exactly ten definitions in pinned ID order
00:18 +306: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog every definition validates with no failures
00:18 +307: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog definition IDs are globally unique
00:18 +308: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog all() returns the same order on repeated calls
00:18 +309: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byId returns the pinned definition and null for unknown IDs
00:18 +310: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byMode returns only definitions of the requested mode
00:18 +311: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog byDifficulty returns only definitions of the requested difficulty
00:18 +312: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog firstWaltz is 3/4 with twelve total beats on the quarter grid
00:18 +313: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog titleKey and descriptionKey follow the practiceCatalog regex
00:18 +314: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog free-practice template has no events and an open scoring profile
00:18 +315: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog strumPattern events carry no chord and chordChanges events do
00:18 +316: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog data layer purity source forbids ambient IO, randomness, framework, and l10n imports
00:18 +317: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog PracticeDefinition integrity event IDs are unique within every definition
00:18 +318: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability events list rejects add() for every catalog definition
00:18 +319: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog per-definition immutability skillTags list rejects add() for every catalog definition
00:18 +320: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.gToDChanges.v1 holds G for the first bar, D for the second
00:18 +321: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/builtin_practice_catalog_test.dart: BuiltinPracticeCatalog chord-change bar grouping builtin.emToCChanges.v1 holds Em for the first bar, C for the second
00:19 +322: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:19 +323: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:19 +324: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:19 +325: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:19 +326: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:19 +327: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:19 +328: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:19 +329: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:19 +330: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:19 +331: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:19 +332: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:19 +333: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:19 +334: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:19 +335: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:20 +336: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:20 +337: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:20 +338: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:20 +339: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:20 +340: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:20 +341: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:20 +342: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:20 +343: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:20 +344: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:20 +345: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:20 +346: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:20 +347: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:20 +348: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:20 +349: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:20 +350: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:20 +351: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:20 +352: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:20 +353: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:20 +354: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:20 +355: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:20 +356: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:20 +357: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:20 +358: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:20 +359: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:20 +360: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:20 +361: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:20 +362: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:20 +363: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:20 +364: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:20 +365: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:20 +366: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:20 +367: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:20 +368: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:20 +369: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:20 +370: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:20 +371: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:20 +372: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:20 +373: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:20 +374: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:20 +375: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:20 +376: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:20 +377: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:20 +378: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:20 +379: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:20 +380: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:20 +381: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:20 +382: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:20 +383: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:20 +384: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:20 +385: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:20 +386: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:20 +387: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:20 +388: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:20 +389: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:20 +390: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:20 +391: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:20 +392: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:21 +393: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:21 +394: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:21 +395: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:21 +396: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:21 +397: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:21 +398: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:21 +399: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:21 +400: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:21 +401: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:21 +402: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:22 +403: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:22 +404: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:22 +405: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:22 +406: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:22 +407: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:22 +408: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:22 +409: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:22 +410: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:22 +411: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:22 +412: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:22 +413: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:22 +414: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:22 +415: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:22 +416: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:22 +417: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:23 +418: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:23 +419: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:23 +420: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:23 +421: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:23 +422: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:23 +423: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:23 +424: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:23 +425: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:23 +426: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:23 +427: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:23 +428: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:23 +429: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:23 +430: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:23 +431: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:23 +432: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:23 +433: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:23 +434: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:23 +435: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:23 +436: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:23 +437: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:23 +438: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:23 +439: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:23 +440: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:23 +441: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:23 +442: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:23 +443: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:23 +444: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:23 +445: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:23 +446: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:23 +447: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:23 +448: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:23 +449: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:23 +450: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:23 +451: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:23 +452: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:23 +453: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:23 +454: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:23 +455: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:23 +456: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:23 +457: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:23 +458: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:23 +459: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:23 +460: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:23 +461: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:23 +462: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:23 +463: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:23 +464: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:23 +465: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:23 +466: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:23 +467: /home/ubuntu/ss-codex-e02-r10/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:23 +468: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:23 +469: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:23 +470: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:25 +471: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:25 +472: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:25 +473: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:26 +474: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:26 +475: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:26 +476: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:26 +477: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:26 +478: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:26 +479: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:26 +480: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:26 +481: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:26 +482: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:26 +483: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:26 +484: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:26 +485: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:26 +486: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:26 +487: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:26 +488: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:26 +489: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:26 +490: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:26 +491: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:27 +492: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:27 +493: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:27 +494: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:27 +495: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:27 +496: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:27 +497: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:27 +498: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:27 +499: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:28 +500: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:28 +501: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:28 +502: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:28 +503: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:28 +504: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:28 +505: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:28 +506: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:28 +507: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:29 +508: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:29 +509: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:29 +510: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:29 +511: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:29 +512: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:29 +513: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:29 +514: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:29 +515: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:29 +516: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:29 +517: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:29 +518: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:29 +519: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:29 +520: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:29 +521: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:29 +522: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:29 +523: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:29 +524: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:29 +525: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:29 +526: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:29 +527: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:30 +528: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:30 +529: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:30 +530: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:30 +531: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:30 +532: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:30 +533: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:30 +534: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:30 +535: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused restarts the session fresh
00:30 +536: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:30 +537: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:30 +538: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:30 +539: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:30 +540: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:30 +541: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:30 +542: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:30 +543: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused restarts the session fresh
00:30 +544: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:30 +545: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:30 +546: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:30 +547: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:30 +548: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause resets the clock fully
00:30 +549: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:30 +550: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:30 +551: /home/ubuntu/ss-codex-e02-r10/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:30 +552: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/property/practice_scorer_property_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/property/practice_scorer_property_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.2 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.1 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
32 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-codex-e02-r10/test/property/practice_scorer_property_test.dart
PROPERTY_SEED=42
00:00 +0: Practice scorer randomized invariants available metrics are normalized and overall stays in range
00:00 +1: Practice scorer randomized invariants changing one wrong direction to correct never lowers points
00:00 +2: Practice scorer randomized invariants zero observations never become a zero-valued scoring dimension
00:00 +3: All tests passed!

    → [4] test test/property/practice_scorer_property_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [5] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/property/practice_scorer_property_test.dart      zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
````

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r10-review.md`

Kiemelt figyelem a review-nak: **eldobható próbateszt** az A4 nulla-kitöltéses
hibára (a helyes kódnak 1000-et, a hibásnak 650-et kell adnia), a §5.3 egész-
ezrelék szerződés **valódi-sértés próbája** (ideiglenes `double`-akkumuláció →
az A1 350-es cellájának pirosra kell futnia), és az A7 korpusz teljességének
ellenőrzése (17 lecke × 3 latency, ne egy szűkített lista).
