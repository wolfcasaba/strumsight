# ADR 0235 — Monofonikus pitch capability határ és típusnév-ütközés

- **Státusz:** Elfogadva (E06-R17 pre-flight, 2026-08-12)
- **Kör:** E06-R17 — Monofonikus pitch capability
- **Implementer motor:** `terra`
- **Kapcsolódó szerződések:** [ADR 0215](0215-analysis-document-versioning.md),
  [ADR 0218](0218-analysis-metric-id-and-version-governance.md),
  [ADR 0219](0219-analysis-capability-aware-publication.md),
  [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md),
  [ADR 0225](0225-analysis-preprocessing-and-resampling-policy.md),
  [ADR 0231](0231-target-alignment-engine-boundary.md)

## Kontextus

A meglévő YIN-alapú pitch-detektálás (`lib/core/audio/dsp/yin_pitch_detector.dart`,
99 sor; `sliding_framer.dart`, 26 sor) és a Tuner/Practice pitch-observation
útja (`lib/core/audio/pitch/pitch_observation*.dart`, 23/38/12 sor) ma is éles,
változatlan core primitív. Az Audio Analysis V2 `AnalyzeResult`-jában viszont
nincs hangmagasság-fogalom — a `ClipAnalyzer` kizárólag chroma/chord és
onset/strum passzt futtat. Az E06-R17 ezt a hiányt zárja: frame → szegmens →
capability-gate → hét metrika, kizárólag `analysisPitchEnabled` flag mögött
(ma `false` mindenhol), a core YIN és a Tuner érintése nélkül.

A pre-flight mérés (brief-lint S5) egy valódi ütközést talált: a brief
tervezett ÚJ `lib/features/audio_analysis/domain/pitch/pitch_segment.dart`
fájlja a `PitchSegment` nevet vezetné be, de ez a típus **már létezik és
exportált** (`lib/features/audio_analysis/domain/analysis_segment.dart:55`,
E06-R02, PR #212): egy `start`/`end`/`confidence`/`midiNote` mezőjű, ma **0
producerű** stub, amit az `AnalysisTimeline.pitchSegments` mező hordoz
(`analysis_timeline.dart:33`), amit a `public.dart:23` barrel exportál, és
amit az `analysis_document_codec.dart` már (de)szerializál. A két típus a
néven kívül semmit nem oszt: a meglévő egy jövőbeli, cross-feature
timeline-populáló hely (nincs capability-fogalma), az új a kör saját,
capability-gate mögötti frame→szegmens pipeline kimenete, gazdagabb és más
invariánsú mezőkészlettel (medianHz/medianMidi/centsOffset/stabilityCents). Egy
második, azonos nevű `final class` deklaráció a `public.dart` barrelen
ambiguous-export ütközést adna.

## Döntés

1. **Az új típus és a szegmentáló neve `MonophonicPitchSegment` /
   `MonophonicPitchSegmentBuilder`** (fájlok:
   `lib/features/audio_analysis/domain/pitch/monophonic_pitch_segment.dart`,
   `lib/features/audio_analysis/engine/pitch/monophonic_pitch_segment_builder.dart`),
   nem `PitchSegment` / `PitchSegmentBuilder`. A név a kör saját
   kapu-osztályával (`PitchCapabilityGate`) és a brief §OD-01
   monofonikus-kapu szemantikájával konzisztens, és önmagában jelzi, hogy ez
   a típus KIZÁRÓLAG a monofonikus-kapun átjutott bemenetről szól — szemben a
   meglévő, kapu-fogalom nélküli `PitchSegment` stubbal. A builder nevét is
   át kell nevezni: a repóban következetes minta, hogy a builder/estimator/
   assembler osztály neve az általa gyártott típus nevét viseli (pl.
   `ChordSegmentAssembler` → `ChordSegment`, `BeatGridEstimator` → `BeatGrid`,
   `TempoCurveBuilder` → `TempoCurvePoint`) — a builder néven hagyása,
   miközben a kimenete `MonophonicPitchSegment`, pont ezt a mintát törné meg.
2. **A kör NEM nyúl `analysis_segment.dart`-hoz, `analysis_timeline.dart`-hoz
   vagy `analysis_document_codec.dart`-hoz.** A meglévő `PitchSegment` stub
   (és az őt hordozó `AnalysisTimeline.pitchSegments` mező) egy KÜLÖN,
   jövőbeli bekötő kör kérdése — annak eldöntése, hogy a cross-feature
   timeline a `MonophonicPitchSegment`-et kapja-e meg (adapterrel vagy
   mezőbővítéssel), vagy a mai minimál `PitchSegment` marad valamilyen más
   célra, **nem ennek a körnek a hatásköre**. Az `allowed_paths` bővítése egy
   már létező, listán kívüli fájlra tilos-zóna kérdés (ADR 0087 §2 H3) —
   pontosan az ADR 0113 Elutasított alternatívák szakaszában rögzített
   precedens szerint (amely a `core/music/strum.dart` bővítését ugyanezen az
   alapon utasította el: „a fájl nincs az `allowed_paths` listán, a bővítés
   tilos zónát nyitna").
3. **A meglévő `PitchSegment` stub és a `public.dart` exportja ÉRINTETLEN
   marad.** Nincs deprecation-jelzés, nincs átnevezés rajta — a kör csak egy
   ÚJ, más nevű típust ad hozzá a barrelhez, nem módosít meglévő publikus
   szerződést. Ez `additive`, nem `breaking` a `public.dart` nézetéből.
4. A brief §5 hat kötött architekturális döntése (YIN újrafelhasználás
   másolás nélkül, Tuner-paritás, capability-gate metrika-számítás ELŐTT,
   nincs hamis note-score polifón bemeneten, az intonáció nem diagnózis,
   flag-kapu) **változatlan** — ez az ADR csak az 1–3. pontban rögzített
   típusnév-ütközést oldja fel, más tervezési döntést nem érint.

## Következmények

- A `public.dart` barrel két, névben hasonló, de funkcionálisan független
  típust exportál: `PitchSegment` (bekötetlen stub, E06-R02) és
  `MonophonicPitchSegment` (E06-R17, capability-gate mögötti pipeline
  kimenete). Ez átmeneti állapot — egy jövőbeli bekötő kör dönt a
  konszolidációról vagy a tartós különválásról.
- A kör diffje a brief eredeti `allowed_paths` listáján belül marad (a
  fájlnév-csere `pitch_segment.dart` → `monophonic_pitch_segment.dart` és
  `pitch_segment_builder.dart` → `monophonic_pitch_segment_builder.dart` a
  listán belüli csere, nem bővítés).
- Egy jövőbeli olvasó, aki a `PitchSegment` és a `MonophonicPitchSegment`
  együttes létét különösnek találja, ezt az ADR-t találja meg elsőként
  (mindkét fájl doc-commentje ide mutat vissza).

## Elutasított alternatívák

- **A meglévő `PitchSegment` stub kibővítése/lecserélése ezzel a körrel:**
  elvetve — `analysis_segment.dart` nincs az `allowed_paths` listán, a
  bővítés tilos zónát nyitna (H3, ADR 0113 precedens), és a stub mezőinek
  megváltoztatása egy már exportált, szerializált (bár 0 producerű) publikus
  típus alakját módosítaná egy olyan kör hatáskörén kívül, amelynek brief-je
  ezt nem írta elő.
- **A meglévő `PitchSegment`-et használni módosítás nélkül, a hiányzó
  mezőket (medianHz, centsOffset, stabilityCents) egy kísérő objektumban
  vinni:** elvetve — szétforgácsolná a szegmens-fogalmat két típusra pontosan
  azért, hogy elkerülje az átnevezést; a `MonophonicPitchSegment` egyetlen,
  önmagában értelmezhető típus.
- **Csak a típust átnevezni, a buildert `PitchSegmentBuilder` néven hagyni:**
  elvetve — megtörné a repó következetes builder-név=kimenet-típus mintáját,
  és egy jövőbeli olvasó számára azt sugallná, hogy a builder a (nem létező)
  kapcsolatban áll a meglévő `PitchSegment` stubbal.
- **A `pitch/` almappa törlése, a típus más névtérbe (pl. `engine/pitch/`)
  helyezése az ütközés elkerülésére:** elvetve — a domain/engine
  réteg-elválasztás (ADR 0215) a `PitchSegment`-et is domain típusként
  kezelte; a réteg megváltoztatása a névütközés miatt rossz indokból hozott
  architekturális döntés lenne.
