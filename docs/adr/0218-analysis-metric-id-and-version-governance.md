# ADR 0218 — Analysis metric ID and version governance

- **Státusz:** Elfogadva (E06-R01 pre-flight, 2026-08-11)
- **Kör:** E06-R01 — Analyze V1 baseline, mérés és ADR-ek
- **Implementer motor:** Terra — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 1; §10.2 (Analyzer version), §10.3 (Metric version), §9.8 (Metric
  result) — a batch harmadik, keresztmetsző kiegészítése (a brief §0.0
  szerint az SDD Kör 1 három ADR-t nevez meg; ez a batch-bővítés egyike)
- **Kontext-ADR-ek:** [0215](0215-analysis-document-versioning.md)
  (dokumentum-szintű `schemaVersion` — ez az ADR a metrika-szintű
  verziózást rögzíti, más granularitáson)
- **Sorszám-jegyzet:** lásd [ADR 0215](0215-analysis-document-versioning.md)
  fejléce — a teljes hatos blokk 0200–0205-ről 0215–0220-ra tolódott.

## Kontextus

**Mért 2026-08-11-én:**

1. Az SDD Ch7 §10.3 (Metric version) szó szerint: „Minden metrika külön
   verzióval rendelkezzen." Példák: `timing.mean_absolute_error.v1`,
   `rhythm.rush_drag_bias.v1`, `dynamics.strum_consistency.v1`,
   `harmony.chord_coverage.v2`. „Két session automatikus összehasonlítása
   csak kompatibilis metric ID és version mellett engedélyezett."
2. §10.2 (Analyzer version) elválasztja a **dokumentum-szintű** analyzer
   verziót (csak akkor major bump, ha metrika-definíció, event timebase
   vagy confidence-kalibráció inkompatibilisen változik) a **metrika-
   szintű** verziótól — a két granularitás egymástól függetlenül fejlődik.
3. A jelenlegi kódban **nincs** stabil, névtérrel ellátott metrika-ID
   minta erre a feature-re — a `_bpmFromStrums` (`clip_analyzer.dart:229`)
   egy `double` BPM-et ad vissza minden azonosító nélkül; a `TimelineChord`/
   `TimelineStrum` timeline-elemek nem hordoznak metrika-verziót.
4. **Létező, közvetlenül átvehető minta** a `SongDocumentValidationCode`
   (`song_document.dart:24-32`, pl. `'songDocument.schemaVersion.outOfRange'`)
   és a `PracticeMetricReasonCode` (`practice_score_aggregator.dart`,
   `practice_chord_scorer.dart` — `noSignal`/`insufficientSamples`/
   `chordUnstable`) — mindkettő **stabil, névtérrel tagolt string-kód**,
   szó szerint tesztelve, nem szabadon variálható szöveg. A metrika-ID
   ugyanezt a fegyelmet igényli, egy réteggel feljebb (nem hibakód, hanem
   a mérés AZONOSÍTÓJA).
5. A `docs/eval/real-audio-dsp-baseline.md` három számot közöl (akkord-
   pontosság, onset F1@50ms, tempó-egyezés) — ezek MA nincsenek metrika-ID-
   hoz kötve; egy jövőbeli összehasonlító kör (SDD §26 „Session
   comparison") ezen az ADR-en fog megállni, ha a számítás mögötti metrika
   nem azonosítható egyértelműen.

## Döntés

1. **Minden publikált metrika stabil, névtérrel ellátott ID-t kap**, a
   `<domain>.<metric>.v<N>` alakban (SDD §10.3 példák szerint):
   `timing.mean_absolute_error.v1`, `rhythm.rush_drag_bias.v1`,
   `dynamics.strum_consistency.v1`, `harmony.chord_coverage.v1`, stb. A
   névtér (`timing`/`rhythm`/`dynamics`/`harmony`/…) a metrika **kategóriáját**
   kódolja, a `v<N>` szuffix a **saját, önálló verzióját** — nem a
   dokumentum-szintű `schemaVersion`-t.
2. **A metrika-ID és -verzió literál konstansként létezik**, sosem a
   számítás helyén összefűzött string. A `SongDocumentValidationCode`
   mintáját követve: `abstract final class AnalysisMetricId { static const
   String timingMeanAbsoluteError = 'timing.mean_absolute_error.v1'; … }`
   — egyetlen forrás, grep-elhető, elgépelés-biztos.
3. **Két session csak azonos metrika-ID ÉS kompatibilis verzió mellett
   hasonlítható össze automatikusan.** Egy összehasonlító képesség
   (SDD §26 Session comparison) explicit ellenőrzi az ID+verzió egyezést;
   eltérés esetén a metrika `unavailable`-ként jelenik meg az
   összehasonlításban, magyarázattal ([ADR 0219](0219-analysis-capability-aware-publication.md)),
   nem hallgatólagosan egymás mellé rakva.
4. **A metrika-verzió emelése kötelező**, ha a számítási képlet, a
   bemeneti tartomány vagy az egység megváltozik — additív metaadat
   (pl. egy új `details` mező) nem igényel verzióemelést, csak ha a
   SZÁMÉRTÉK jelentése változna.
5. **A metrika-katalógus egyetlen forrásból származik** (a jövőbeli
   metrika-modell fájl, E06-R02+), amit `tool/audio_analysis_baseline.dart`
   és a runtime pipeline egyaránt importál — nem két helyen karbantartott,
   divergálható lista.

**NEM elfogadható:** magic string a számítás helyén (`'timing_mae'` egy
`if`-ágban, verzió nélkül); két különböző számítási képlet ugyanazon
metrika-ID alatt egy verzióemelés nélkül; egy metrika-ID újrafelhasználása
más jelentéssel egy jövőbeli körben.

## Következmények

- A V2 `AnalysisMetricResult` modell (E06-R02, SDD §9.8) a metrika-ID-t és
  -verziót kötelező mezőként hordozza.
- A `docs/manual-testing/analysis-eval-matrix.md` (ez a kör hozza létre)
  a PENDING sorokat metrika-ID-vel (nem csak leíró névvel) azonosítja, ahol
  a mérendő szám egy konkrét metrikához köthető.
- A session-összehasonlítás (E06-R25, SDD §26) erre az ADR-re hivatkozva
  implementálja az ID+verzió-egyezés ellenőrzést — ez a kör csak a
  szerződést rögzíti.
- A jelenlegi V1 `_bpmFromStrums`/timeline-számítás **érintetlen marad** —
  metrika-ID-zés csak a V2 úton jelenik meg
  ([ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)).

## Elutasított alternatívák

- **Metrika-azonosítás pusztán a mező-névvel** (pl. a Dart osztály mezőneve
  legyen az azonosító, külön ID nélkül). Elvetve: egy mező átnevezése
  (refaktor) hallgatólagosan törné az összehasonlítást; egy explicit,
  stringesített ID a refaktortól független, stabil kontraktus.
- **Egyetlen globális `analyzerVersion` a metrika-szintű verziók helyett.**
  Elvetve: az SDD §10.2 kifejezetten elválasztja a két granularitást — egy
  metrika finomítása (pl. jobb rush/drag-becslés) nem indokol dokumentum-
  szintű major bumpot, ha a többi metrika változatlan.
- **Szabad-szöveges metrika-leírás verziószám helyett.** Elvetve: a
  gépi összehasonlítás (SDD §26) programozott egyenlőség-vizsgálatot
  igényel, amit szabad szöveg nem tesz lehetővé determinisztikusan.

## A visszavonás feltétele

Felülvizsgálandó, ha a metrika-katalógus mérete (SDD §9.8+ alapján
várhatóan 15-25 metrika) gyakorlatban egy más csoportosítási elvet
igényel (pl. capability-alapú, nem domain-alapú névtér) — ekkor a
névtér-konvenció migrálható, de csak egy dedikált kör explicit ADR-
felülvizsgálatával és egy dokumentált ID-migrációs táblával, nem a
kódban szétszórt, egyedi átnevezésekkel.
