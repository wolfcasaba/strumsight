# ADR 0233 — Rhythm consistency and groove proxy boundary

- **Státusz:** Elfogadva (E06-R15 pre-flight, 2026-08-12)
- **Kör:** E06-R15 — Rhythm consistency és groove proxyk
- **Kapcsolódó szerződések:** SDD Ch7 §15.6; [ADR 0218](0218-analysis-metric-id-and-version-governance.md), [ADR 0219](0219-analysis-capability-aware-publication.md), [ADR 0230](0230-beat-grid-tempo-curve-boundary.md), [ADR 0232](0232-timing-metric-identity-and-publication-boundary.md)

## Kontextus

Az R14/ADR 0232 a timing-hibát méri (megfigyelt esemény vs. illesztett
referencia). A ritmikai **egyenletesség** — inter-onset intervallum
konzisztencia, subdivision-stabilitás, beat-relatív fáziseloszlás,
accent-pozíció konzisztencia — más mennyiség: rács-független is mérhető,
nem csak referenciához képest. Az R12 `BeatGrid` (`lib/features/
audio_analysis/domain/rhythm/beat_grid.dart`) target- és becsült-forrású
rácsot egyaránt szolgáltat, de **nincs saját, összesített `confidence`
mezője** — a confidence kizárólag pontonként, a `BeatPoint.confidence`-en
(`beat_point.dart:21`, `[0,1]`-re validált) és a `TempoCurvePoint.
confidence`-en él. A brief eredeti §5.3/§6 szövege („confidence ≤
beatGrid.confidence") ezt a nem létező mezőt feltételezte — pre-flight
mérési eltérés (AGENTS.md §2 „elérhetetlen cél-státusz" mintája), ADR 0087
§2 szerint saját, nem merge-elt brief-artefaktum, orchestrátor-hatáskörben
javítva.

## Döntés

1. **A groove ebben a körben mérhető proxy, nem stílusfelismerés** (SDD
   §15.6): `RhythmMetrics`/`SubdivisionAnalysis` kizárólag mérhető
   mennyiséget publikál. Összesített „groove score" és validálatlan
   stiláris címke („shuffle", „reggae") nem elfogadható.
2. **A target-alapú és a becsült-rács alapú ritmus diszjunkt, mode-kódolt
   ID** (ADR 0232 §1 mintája): `rhythm.target_*` csak target-forrású
   `BeatGrid`-ből (`BeatsPerBarSource.target`/`BeatSource.target`),
   `rhythm.inferred_*` csak becsült rácsból (`BeatSource.estimated`)
   publikálható; a két névhalmaz metszete üres, egy futásban csak az egyik
   publikálódik. A meglévő, más körből származó `rhythm.rush_drag_bias.v1`
   (`analysis_metric_catalog.dart:7`) ettől diszjunkt, informatív placeholder
   — csak `test/features/audio_analysis/domain/analysis_document_test.dart:145`
   hivatkozza, engine-implementáció nem publikálja; ez a kör nem nyúl hozzá.
3. **A `confidence ≤ beatGrid confidence` szabály operacionalizálva:** mivel
   `BeatGrid`-nek nincs skalár `confidence` mezője, a `rhythm.inferred_*`
   metrika confidence-e felülről korlátos **az adott metrika által ténylegesen
   felhasznált `BeatPoint`-ok confidence-ének átlagával**, az R14/ADR 0232
   `buildFreePlayTimingMetrics` (`timing_metrics.dart:150-154`) mintáját
   követve — nem minimum, nem egy nem létező rács-szintű mező. Az acceptance
   „becsült rács `confidence = 0.4`" cellájának fixture-e **homogén**
   `BeatPoint.confidence = 0.4`-et ad minden felhasznált beatre, hogy a
   korlát a mátrixban egyértelmű legyen aggregálási módtól függetlenül.
4. **A swing ratio kizárólag targettel publikálható** (SDD §15.6); target
   nélkül a swing capability `notApplicable`, és a metrika nincs a
   publikált listában.
5. **A minimum eseményszám kaput az R14 `MetricGate`-je adja újra**
   (`engine/metrics/metric_gate.dart`, alapérték
   `minimumMatchedPairs: 8`/`minimumStreakMatchedPairs: 3`) — ez a kör nem
   definiál saját, eltérő küszöbű kaput.
6. Új mennyiség ⇒ RAG-chunk (`docs/rag/chunks/021-rhythm-consistency-groove-proxies.md`)
   ugyanabban a commitban, képlettel és küszöbökkel (AGENTS.md §9).

## Következmények

- A `rhythm.inferred_*` metrikák sosem állíthatnak magasabb bizonyosságot,
  mint amit a mögöttes becsült beat-pontok ténylegesen hordoznak — a rács
  bizonytalansága az aggregáción át öröklődik, nem tűnik el.
- A target és inferred eredmény külön ID miatt sosem hasonlítható össze
  csendben; egy jövőbeli összehasonlító kör (pl. R25 session comparison)
  explicit konverziót igényel.
- A groove-proxyk dokumentált mérőszámok maradnak; UI-megjelenítés (címke,
  „groove score") csak egy jövőbeli, validált kör dönthet be.

## Elutasított alternatívák

- **`BeatGrid`-re új, összesített `confidence` mező felvétele** — kívül esik
  a brief engedélyezett fájllistáján (`domain/rhythm/beat_grid.dart` nincs
  rajta, az R12 „tilos zóna"), és megkettőzné a már létező pontonkénti
  igazságforrást (ADR 0230 §3 ellen).
- **Minimum-alapú (nem átlag-alapú) confidence-korlát** — eltérne az R14/ADR
  0232 már elfogadott átlag-alapú precedensétől ugyanazon a rács-eredetű
  bizonytalanság-öröklési mintán, két versengő konvenciót hozva létre a
  ritmus-metrikák között indokolatlanul.
- **Saját minimum-eseményszám kapu** — duplikálná az R14 `MetricGate`-et,
  eltérő küszöbbel eltérő „elégtelen adat" viselkedést eredményezne
  ugyanazon dokumentumon belül.
