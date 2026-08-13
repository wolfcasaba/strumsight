# ADR 0243 — Analysis timeline: lane data-source and capability-degraded boundary

- **Státusz:** Elfogadva (E06-R24 pre-flight, 2026-08-13)
- **Kör:** E06-R24 — Többrétegű, zoomolható timeline
- **Implementer motor:** Terra (`.pipeline/engine-override`, 2026-08-08 motor-felállás)
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md), Kör 24; §25.6–25.8
- **Kapcsolódó ADR-ek:** [0217](0217-analysis-raw-audio-retention.md) (nyers audio/PCM UI-tilalom), [0219](0219-analysis-capability-aware-publication.md), [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md), [0237](0237-analysis-confidence-combiner-and-capability-resolver.md) (capability resolver, `CapabilityStatus`), [0238](0238-analysis-insight-evidence-and-ranking-boundary.md) (hotspot ranker), [0239](0239-analysis-document-storage.md) (R21 dokumentum-tárolás — a waveform-hiány forrása), [0241](0241-analysis-overview-presentation-boundary.md) (R23 testvérkör — degraded-kezelés precedens)

## Kontextus

**Mért 2026-08-13-án, `main` @ `4d2ff97`.** A brief 2026-08-07-én íródott,
anélkül hogy a nyolc lane-hez konkrét `AnalysisDocument`-mezőt nevezett volna
meg. A pre-flight (célzott kód-olvasás + grep) a következőket mérte:

1. **Adatforrás-térkép.** Az `AnalysisDocument.timeline`
   (`AnalysisTimeline`, `domain/analysis_timeline.dart`) hordozza a ténylegesen
   perzisztált evidence-t: `chordSegments` (chord lane), `beats`+`bars`+
   `tempoPoints` (beat/bar lane), `events: List<AnalysisEvent>` — ez a sealed
   lista `OnsetEvent`/`StrumEvent` MELLETT `ChordChangeEvent`/`BeatEvent`/
   `NoteOnsetEvent`/`AnalysisRegionEvent` altípusokat is tartalmaz, tehát a
   strum/onset lane szűrése **kizárólag** `OnsetEvent`/`StrumEvent`-re megy —,
   `dynamicPoints` (dynamics lane), `pitchSegments` (pitch lane),
   `hotspots: List<AnalysisHotspot>` közvetlenül a dokumentumon (hotspot
   overlay lane).
2. **A gazdagabb R12/R17 domain-típusok sosem kerülnek fűzve.**
   `BeatGrid`/`BeatPoint`/`BarPoint`/`TempoCurvePoint`
   (`domain/rhythm/beat_grid.dart`, `beat_point.dart`,
   `tempo_curve_point.dart`) és `MonophonicPitchSegment`
   (`domain/pitch/monophonic_pitch_segment.dart`) kizárólag engine-belüli
   közbenső számítási eredmények — az `AnalysisDocument`/`AnalysisTimeline`
   egyikük egyetlen példányát sem hordozza (`beat_grid.dart` saját
   doc-commentje: „Never fused with an `AnalysisDocument`… in this round”).
   A beat/bar és a pitch lane ezért a §1-ben nevezett EGYSZERŰBB, ténylegesen
   populált mezőket rajzolja — a gazdagabb típusok után az implementer NEM
   keres az `engine/`-ben.
3. **Nincs plottolható timing-error idősor.** A `timing.*` metrikák
   (`AnalysisMetricResult`, `document.metrics`) szkalár/percentage/duration/
   score payloadot hordoznak (mean/median/p90 absolute error, signed bias,
   on-time/early/late/missed/extra ratio). A `TimeSeriesMetricValue` variáns
   LÉTEZIK a zárt `AnalysisMetricValue` típuscsaládban
   (`domain/analysis_metric.dart:54-58`), de jelenleg **egyetlen** engine
   metrika-számító sem termel ilyet — a típusra mutató összes hivatkozás a
   kódbázisban a codec (szerializációs kerekpálya) és a `labels_adapter.dart`
   defenzív formázó ága (`analysis_metric.dart`-on kívül csak
   `analysis_document_codec.dart:463,494` és `labels_adapter.dart:96`). A
   timing-error lane ezért a `document.hotspots.where((h) => h.kind ==
   AnalysisHotspotKind.timing)` tartomány-listát rajzolja (van `start`/`end`
   Duration, `severity`, `confidence`) — a szkalár timing-metrikák továbbra is
   az Overview képernyő (E06-R23) felelőssége, itt **nem** duplikálódnak.
4. **A `capabilities` mező lapos lista, nem map.**
   `AnalysisDocument.capabilities: List<CapabilityReport>`
   (`domain/analysis_document.dart`) — egy adott `AnalysisCapability`-hoz
   tartozó bejegyzést a lane-logikának keresnie kell. A legacy migrációs
   adapter (`data/legacy_analyze_adapter.dart:161-171`) egy záró `_ =>` ággal
   mind a 14 capabilityhez ad bejegyzést, de ez a teljesség jövőbeli hívóra
   (pl. kézzel épített teszt-fixture) nem terjed ki automatikusan.
5. **`CapabilityStatus` négy értékű**, nem kettő:
   `available | degraded | unavailable | notApplicable`
   (`domain/analysis_capability.dart:19`). A brief §4/§6 „megjelenik ha
   available / rejtve ha unavailable-vagy-notApplicable” kételemű felosztása
   nem nevezi meg a `degraded`-et. A testvérkör (E06-R23, ADR 0241 §Döntés 3)
   már lefektette a mintát erre a helyzetre: a gyenge, de VALÓDI mérést a
   domain nem tünteti el, hanem szöveggel/badge-dzsel teszi láthatóvá
   (`ConfidenceBadge` — ikon **és** szöveg, SDD §25.8 color-only tilalom).
6. **Waveform preview: megerősítve hiányzik.** Sem `AnalysisDocument`, sem
   `AnalysisTimeline`, sem a codec JSON-kulcslistája nem tartalmaz decimált
   min/max mintasort. Az egyetlen releváns találat
   (`domain/audio_retention_policy.dart:18`) egy TILTÓ szabály
   („preview waveform néven tárolt teljes PCM” nem elfogadható), nem
   implementáció. Az OD-01 alapértelmezett feloldása (`unavailable`, „nincs
   preview adat” ok) ezért az egyetlen járható út — ezt a mérés megerősíti,
   nem módosítja.

## Döntés

1. A nyolc lane adatforrása a fenti, mért térkép szerint **kötött**:
   chord→`timeline.chordSegments`; beat/bar→`timeline.beats`+`.bars`+
   `.tempoPoints`; strum/onset→`timeline.events` szűrve
   `OnsetEvent`/`StrumEvent`-re; dynamics→`timeline.dynamicPoints`;
   pitch→`timeline.pitchSegments`; hotspot overlay→`document.hotspots`
   (minden kind); timing error→`document.hotspots.where(kind == timing)`;
   waveform→mindig `unavailable` (nincs forrás, OD-01 default).
2. `CapabilityStatus.degraded` a lane-ek számára **látható** állapot,
   explicit figyelmeztető jelzéssel — nem esik egy kategóriába
   `unavailable`/`notApplicable`-lel. A kilencedik mátrix-cella (§6) ezt méri.
3. A szkalár `timing.*` metrikák (`document.metrics`) NEM jelennek meg újra a
   timeline-on — azok az Overview képernyő (R23) felelőssége maradnak; a
   timing-error lane kizárólag a timing-kind hotspot-tartományokat rajzolja.
4. Hiányzó `CapabilityReport` bejegyzés egy adott `AnalysisCapability`-ra a
   lane-logikában **`unavailable`-ként** kezelendő (fail-closed lookup
   default) — sem kivétel, sem hallgatólagos „elérhető” nem megengedett.
5. `fl_chart` **nem** kerül importálásra és nem kerül a `pubspec.yaml`-be
   (amúgy sincs a kör engedélyezett fájllistáján) — minden lane natív Flutter
   widget/`CustomPainter` rajzolással készül.
6. A gazdagabb, csak engine-belüli domain-típusok (`BeatGrid`,
   `TempoCurvePoint`, `MonophonicPitchSegment`) a timeline lane-ek bemenetei
   között **nem** szerepelnek — az implementer ezekre nem épít és nem keres
   utánuk kötő kódot.

## Következmények

- A review egy konkrét, mért adatforrás-térkép ellen ellenőrizhet ahelyett,
  hogy az implementer saját feltételezésére hagyatkozna — kisebb az esély
  eltérő lane-forrás választására vagy engine-belüli típus téves importjára.
- A `degraded` állapot explicit kezelése konzisztens marad az R23
  overview-mintával (ADR 0241), és nem sérti az AGENTS.md §5 „gyenge
  confidence nem jelenhet meg biztos állításként” szabályát a MÁSIK irányba
  (rejtve/eltüntetve) sem.
- A timing-error lane szűkebb, de VALÓDI adatra épül (hotspot-tartományok),
  nem egy soha nem populált `TimeSeriesMetricValue`-ra váró holt ágra.
- Ha egy jövőbeli kör a szkalár timing-metrikákból mégis idősort akar
  publikálni (`TimeSeriesMetricValue` producer), a timing-error lane
  bővítése külön döntés — ez az ADR csak a MA elérhető adatra szól.
