# StrumSight Software Design Document

## Chapter 7 — Epic 6: Audio Analysis 2.0

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Elemzési végrehajtás:** on-device, isolate-ban futó DSP/ML pipeline  
**Adatkezelési alapelv:** offline-first, nyers audio alapértelmezetten nem hagyja el az eszközt  
**Kapcsolódó fejezetek:** Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher  
**Végrehajtó:** Codex  
**Végrehajtási mód:** külön branchben vagy külön commitban végzett, kis fejlesztési körök

---

# 1. Az Epic célja

Az Epic 6 célja a jelenlegi StrumSight Analyze funkció professzionális, verziózott és többdimenziós gitárteljesítmény-elemző rendszerré fejlesztése.

A jelenlegi megoldás már képes:

- mikrofonról klipet rögzíteni;
- WAV-fájlt importálni;
- a hosszabb DSP-feldolgozást UI isolate-on kívül futtatni;
- akkord-idővonalat készíteni;
- pengetéseket és pengetési irányt felismerni;
- hozzávetőleges BPM-et számítani;
- a mentett elemzést Libraryben tárolni;
- egy elemzésből gyakorlóleckét létrehozni;
- Lab módban DSP és chord CRNN eredményt összehasonlítani.

Az Audio Analysis 2.0 ezt az alapot nem dobja el. A meglévő, tesztekkel védett DSP- és ML-képességeket egy stabil elemzési platform mögé rendezi, majd új, bizonytalanságtudatos metrikákkal bővíti.

Az új rendszernek választ kell adnia legalább az alábbi kérdésekre:

- Mit játszott a felhasználó?
- Mikor játszotta az egyes eseményeket?
- Mennyire stabil a tempója?
- Sietett vagy késett a belső ritmusrácshoz képest?
- Mennyire egyenletes a pengetési dinamika?
- Melyik szakaszban romlott a pontosság?
- Mely megállapítások biztosak, és melyek csak gyenge becslések?
- Mi legyen a következő, konkrét gyakorlási feladat?
- Mérhető-e fejlődés két hasonló session között?

Az Epic végeredménye nem diagnosztikai „műszerfal” önmagáért. A rendszer célja, hogy a technikai méréseket érthető, cselekvésre fordítható tanulási visszajelzéssé alakítsa.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

A StrumSight elemzője a gyakorlás után ne csak ezt mondja:

> 118 BPM, 42 pengetés, C · G · Am · F.

Hanem például ezt:

> Az első 20 másodpercben stabilan tartottad a 116–119 BPM-et. A második ismétlésben a váltások előtt átlagosan 58 ms-ot siettél, és az upstroke-ok halkabbak lettek. Gyakorold a G–Am váltást 105 BPM-en, kétütemes loopban.

A visszajelzés csak akkor lehet ilyen konkrét, ha a mérés megbízhatósága ezt valóban lehetővé teszi. Amennyiben a rendszer nem tud biztosan következtetni, ezt őszintén jeleznie kell.

## 2.2 Alapelv: mérés, nem ítélkezés

Az UI és a coaching nyelvezete:

- ne szégyenítse meg a felhasználót;
- ne állítson biztos tényt gyenge jelből;
- ne minősítse a felhasználót „rossz gitárosnak”;
- különítse el a felvételi minőséget a játék minőségétől;
- mutasson konkrétan javítható részt;
- mindig adjon egy következő lépést.

## 2.3 Alapelv: offline-first

Az elemzés alapértelmezett útvonala teljes egészében az eszközön fut.

Internet csak az alábbi opcionális esetekben használható:

- felhőszinkron;
- a felhasználó által engedélyezett AI Tutor összegzés;
- explicit Lab diagnosztikai feltöltés;
- későbbi modellfrissítés.

Az alapmetrikák és a session részletes megtekintése internet nélkül is működjön.

## 2.4 Alapelv: capability-aware elemzés

Nem minden klipből lehet minden metrikát megbízhatóan előállítani.

Példák:

- zajos, teljes zenekari felvételből a gitár dinamikája nem feltétlenül mérhető;
- akkordozásból nem következtethető egyes húrok intonációja;
- monofonikus dallamból nem értelmes chord-change smoothness metrikát számolni;
- backing trackkel felvett játékban a beat becslése lehet erős, miközben a gitáresemények elkülönítése bizonytalan;
- rövid, három másodperces klipből nem szabad hosszú távú tempóstabilitást állítani.

Minden elemzési modulnak deklarálnia kell:

- milyen inputot igényel;
- milyen minimum jelminőség szükséges;
- milyen confidence mellett publikál eredményt;
- milyen okból válhat elérhetetlenné.

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Meglévő, újrahasználandó elemek

A jelenlegi repository már rendelkezik az Epic fontos technikai alapjaival.

### Analyze feature

```text
lib/features/analyze/
├── engine/
│   ├── chroma_denoise.dart
│   ├── clip_analyzer.dart
│   ├── clip_recorder.dart
│   ├── hpss.dart
│   ├── ml_chord_decoder.dart
│   └── wav_decoder.dart
├── model/
│   └── analyze_result.dart
├── providers/
│   └── analyze_providers.dart
├── screens/
│   └── analyze_screen.dart
└── widgets/
    ├── analyze_skeleton.dart
    └── timeline_view.dart
```

### Jelenlegi elemzési eredmény

A `AnalyzeResult` jelenleg tartalmazza:

- `durationSec`;
- `bpm`;
- akkord-idővonal;
- pengetési események;
- `beatsPerBar`;
- opcionális Lab diagnosztika;
- JSON szerializáció;
- egyszerű chord summary;
- down/up stroke számlálás.

### Jelenlegi pipeline

A `ClipAnalyzer` két fő feldolgozási utat használ:

1. a Live pipeline-on keresztül futó strum és tempo pass;
2. batch NNLS chroma és teljes-szekvenciás Viterbi alapú chord pass.

A pengetési irány opcionálisan CRNN-refinerrel javítható. Modellhiba esetén a rendszer visszaesik a heurisztikus eredményre.

### Jelenlegi import és lifecycle

A rendszer már támogat:

- mikrofonos felvételt;
- `.wav` importot;
- UI isolate-on kívüli feldolgozást;
- képernyőelhagyás közbeni felvételmegszakítást;
- mikrofonindítási versenyhelyzetek elleni védelmet;
- permission denied és mic error állapotot.

### Jelenlegi Library

A `AnalyzedSession` jelenleg:

- azonosítót;
- létrehozási időt;
- címet;
- `AnalyzeResult` objektumot;
- custom title jelzőt

tárol.

### Jelenlegi tesztalap

Az Analyze feature már rendelkezik többek között:

- importtesztekkel;
- WAV-dekóder tesztekkel;
- recorder hardening tesztekkel;
- batch chord timeline tesztekkel;
- onset időzítési tesztekkel;
- BPM tesztekkel;
- CRNN wiring és fallback tesztekkel;
- DSP–ML agreement tesztekkel;
- HPSS és chroma denoise tesztekkel;
- timeline widget tesztekkel;
- JSON round-trip tesztekkel;
- mic lifecycle regressziós tesztekkel.

Ezeket az Epic alatt meg kell őrizni.

## 3.2 Jelenlegi korlátok

A jelenlegi rendszer korlátai:

1. Az `AnalyzeResult` egyszerű, lapos modell, nincs schema version és provenance.
2. Egyetlen BPM szám túl sok információt rejt el.
3. Nincs beat- és bar-rács.
4. Nincs időbeli tempógörbe.
5. Nincs timing error, rush/drag vagy groove metrika.
6. Nincs dinamikai egyenletesség.
7. Nincs bemeneti jelminőség-értékelés.
8. Nincs clipping, túl halk jel vagy zaj explicit kimutatása.
9. Nincs metrikánkénti confidence és availability reason.
10. Nincs progress reporting a hosszú elemzés alatt.
11. Nincs cancellable elemzés.
12. Nincs elemzési cache vagy fingerprint.
13. A pipeline több helyen közvetlenül más feature belső DSP-fájljait importálja.
14. Az eredmény UI elsősorban lista, nem részletes, zoomolható idővonal.
15. Nincs két session összehasonlítása.
16. Nincs részszakasz-kijelölés vagy hotspot navigáció.
17. Nincs verziózott insight engine.
18. A Library egy teljes JSON tömböt tárol egyetlen SharedPreferences kulcs alatt.
19. A nyers audio nincs formálisan elkülönítve a származtatott elemzési adattól.
20. A Lab diagnostics nem általános provenance rendszer, csak egy opcionális extra mező.

## 3.3 Kapcsolat a Chapter 2-höz

Az Epic feltételezi, hogy a Core Platform fejezetből legalább az alábbi absztrakciók rendelkezésre állnak, vagy ebben az Epicben kompatibilis adapter készül hozzájuk:

- `AppResult`;
- `AppFailure`;
- `AppLogger`;
- `Clock`;
- `KeyValueStore` vagy verziózott repository storage;
- `AudioSessionCoordinator`;
- validált `AppConfig` és feature flags;
- közös zenei és audio domain modellek;
- architekturális dependency guard.

## 3.4 Kapcsolat a Chapter 3-hoz

A Practice Engine lesz az elsődleges fogyasztója az új elemzési eredményeknek.

A Practice Engine átadhat:

- elvárt eseményeket;
- tempót;
- beat gridet;
- target chordokat;
- target strum patternöket;
- target note-okat;
- technikai célt.

Az Audio Analysis 2.0 ezekhez képest pontosabb, célfüggő pontozást készíthet.

## 3.5 Kapcsolat a Chapter 4-hez

A Song Trainer biztosíthat referencia-timeline-t:

- zenei ütemek;
- akkordok;
- hangok;
- szakaszok;
- backing track timebase;
- A–B loop.

A célhoz kötött elemzés pontosabb, mint a teljesen szabad játék elemzése. Ezért a rendszernek külön kell kezelnie:

- free-play analysis;
- practice-target analysis;
- song-reference analysis.

## 3.6 Kapcsolat a Chapter 5-höz

Az AI Guitar Teacher nem értelmezhet nyers PCM-et közvetlenül.

Az AI Tutor kizárólag:

- validált metrikákat;
- confidence értékeket;
- determinisztikus insightokat;
- rövidített timeline summaryt;
- felhasználó által engedélyezett session metaadatot

kaphat meg.

A tutor nem találhat ki olyan hibát, amelyet az elemző nem mért.

---

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- verziózott `AnalysisDocument` domainmodell;
- elemzési input és provenance modell;
- capability és metric availability rendszer;
- többfázisú, progress-reporting pipeline;
- cancellable elemzés;
- input signal quality elemzés;
- mono/stereo normalizáció;
- resampling policy;
- clipping és silence detection;
- onset és strum event timeline;
- akkord-evidence és chord segment timeline;
- beat, tempo és metre becslés;
- tempógörbe és tempóstabilitás;
- timing deviation, rush és drag metrikák;
- strum-direction balance;
- dinamikai egyenletesség;
- monofonikus pitch/note capability;
- note stability, intonation és transition metrikák, csak támogatott inputon;
- technikai proxy metrikák capability gate mögött;
- metrikánkénti confidence;
- quality gate és degraded result;
- determinisztikus coaching insightok;
- elemzési hotspotok;
- Library V2 és migráció;
- részletes overview és timeline UI;
- két session összehasonlítása;
- trendaggregáció;
- Practice Engine, Song Trainer és AI Tutor adapterek;
- exportálható, adatvédelmi szempontból biztonságos elemzési összefoglaló;
- feature flags és fokozatos rollout;
- DSP/ML evaluation és regression gates.

## 4.2 Az Epic nem tartalmazza

- polifonikus tab-transzkripció teljes megoldását;
- minden egyes húr és bund biztos felismerését akkordozás közben;
- stúdióminőségű stem separationt;
- felhőalapú kötelező elemzést;
- diagnosztikai célú nyers audio automatikus feltöltését;
- egészségügyi vagy ergonómiai diagnózist;
- kéztartás vagy ujjpozíció kamerás elemzését;
- teljes hangszerhangzás-modellezést;
- erősítő- és effektlánc pontos felismerését;
- több hangszerből álló mixben a gitár teljesen megbízható izolálását;
- generatív AI által kitalált mérőszámokat;
- új ML-modell automatikus tanítását a kliensen.

## 4.3 Kifejezetten tiltott állítások

A rendszer nem állíthatja biztosan az alábbiakat megfelelő evidence nélkül:

- „rossz ujjat használtál”;
- „a harmadik húr zörgött”;
- „a csuklód helytelenül állt”;
- „pontosan a hetedik bundot fogtad le”;
- „a pengetőd szöge hibás”;
- „a gitárod nyaka görbe”;
- „ezt a hangot biztosan te játszottad a backing track helyett”.

Ezekhez vagy kamerás evidence, vagy izolált hangforrás, vagy külön technikai modell szükséges.

---

# 5. Felhasználói utak

## 5.1 Szabad játék elemzése

1. A felhasználó megnyitja az Analyze képernyőt.
2. Kiválasztja a „Szabad játék” módot.
3. Elindítja a felvételt.
4. A rendszer valós időben mutatja a bemeneti szintet és figyelmeztet clippingre vagy túl halk jelre.
5. A felhasználó leállítja a felvételt.
6. Az elemzés több lépésben fut, progressszel.
7. A rendszer overviewt mutat.
8. A felhasználó megnyitja a timing, chord vagy dynamics részleteket.
9. A hotspotra koppintva az idővonal a problémás részhez ugrik.
10. A felhasználó ebből Practice Engine feladatot készíthet.

## 5.2 Importált felvétel

1. A felhasználó WAV vagy később támogatott audiofájlt választ.
2. A rendszer validálja a formátumot.
3. Megjelenik az input összefoglaló: hossz, mintavétel, csatornák, becsült minőség.
4. Az elemzés ugyanazon pipeline-on fut, mint a mikrofonos felvétel.
5. A provenance jelzi, hogy importált fájlról van szó.
6. A rendszer nem tárolja automatikusan az eredeti fájlt.

## 5.3 Célzott gyakorlat elemzése

1. A Practice Engine átad egy `AnalysisTarget` objektumot.
2. A rendszer ismeri az elvárt tempót, mintát és eseményeket.
3. Az elemzés az elvárt rácshoz illeszti a megfigyeléseket.
4. Pontozza a pontosságot, timingot és folyamatosságot.
5. A szabad játékra jellemző bizonytalan beat inference helyett a target timebase használható.

## 5.4 Dalrészlet elemzése

1. A Song Trainer átad egy dalrész referencia-timeline-t.
2. A felhasználó backing trackkel vagy anélkül játszik.
3. A rendszer a backing track timebase-hoz igazít.
4. Külön jelzi, ha a gitár elkülönítése bizonytalan.
5. A visszajelzés szakaszonként és ütemenként megnyitható.

## 5.5 Két session összehasonlítása

1. A felhasználó kiválaszt két kompatibilis sessiont.
2. A rendszer ellenőrzi az összehasonlíthatóságot.
3. Csak azonos vagy kompatibilis metrikákat hasonlít össze.
4. Megmutatja a változást, confidence-dzsel.
5. Nem állít fejlődést, ha a két felvétel körülményei túl eltérőek.

## 5.6 AI Tutor debrief

1. A felhasználó befejez egy elemzést.
2. A determinisztikus insight engine előállítja a tényeket.
3. A Tutor csak ezeket a tényeket kapja meg.
4. A Tutor érthető magyarázatot és gyakorlási javaslatot ad.
5. A felhasználó visszanyithatja az eredeti timeline evidence-t.

## 5.7 Gyenge minőségű felvétel

1. Az input quality gate zajt vagy clippinget talál.
2. A rendszer nem rejti el a problémát.
3. A megbízhatatlan metrikák unavailable állapotot kapnak.
4. Az UI konkrét újrafelvételi tanácsot ad.
5. A biztosan mérhető adatok ettől még megjelenhetnek.

---

# 6. Funkcionális követelmények

## 6.1 Elemzési módok

Kötelező módok:

```dart
enum AnalysisMode {
  freePlay,
  practiceTarget,
  songReference,
  importedRecording,
}
```

Az `importedRecording` inkább input source, de a kezdeti verzióban külön mód maradhat, ha ez egyszerűsíti az UX-et. A domainben az input source és az analysis intent lehetőség szerint külön mező legyen.

## 6.2 Inputforrások

Kezdeti támogatás:

- mikrofonos mono PCM;
- WAV PCM 16-bit;
- WAV IEEE float 32-bit;
- interleaved stereo WAV mono downmix;
- Practice Engine session buffer;
- Song Trainer session buffer.

Későbbi, feature flag mögötti támogatás:

- AAC/M4A;
- FLAC;
- MP3.

Ezek csak platform- vagy megbízható dekóder bevezetése után engedélyezhetők.

## 6.3 Elemzési kimenet

A kimenet legalább tartalmazza:

- dokumentumazonosító;
- schema version;
- létrehozási idő;
- input provenance;
- analyzer version;
- model manifest verziók;
- signal quality report;
- detected events;
- chord segments;
- beat grid;
- tempo curve;
- metric results;
- confidence és availability;
- hotspotok;
- determinisztikus insightok;
- warnings;
- target match summary, ha volt target;
- privacy metadata;
- persistence metadata.

## 6.4 Progress reporting

Az elemzés közben az UI ne csak spinner legyen.

A pipeline publikálja:

```dart
sealed class AnalysisProgressEvent {
  const AnalysisProgressEvent();
}
```

Példa fázisok:

```text
preparing
validatingInput
preprocessing
extractingEvents
estimatingHarmony
estimatingBeatGrid
computingMetrics
buildingInsights
finalizing
```

A százalék csak akkor mutatható, ha determinisztikusan becsülhető. Egyébként fázis és részlépés jelenjen meg.

## 6.5 Megszakítás

A felhasználó megszakíthatja a hosszú elemzést.

Követelmény:

- cancel után ne publikálódjon későn érkező eredmény;
- isolate felszabaduljon;
- temp fájl törlődjön;
- progress stream lezáródjon;
- UI visszatérjen stabil állapotba;
- cancel ne számítson hibának;
- már mentett session ne sérüljön.

## 6.6 Részleges eredmény

Bizonyos modulok hibája ne semmisítse meg az egész elemzést.

Példa:

- chord CRNN hiba esetén DSP chord timeline megmarad;
- pitch module unavailable esetén rhythm metrics még megjelenhet;
- metre estimation failure esetén event timeline megmarad;
- insight generation failure esetén a nyers metrikák megmaradnak.

Az eredmény jelölje a degraded állapotot.

## 6.7 Reprodukálhatóság

Azonos input, azonos analyzer version, azonos model manifest és azonos config esetén az eredmény determinisztikus legyen, a platform lebegőpontos tolerancián belül.

## 6.8 Mentés

A felhasználó eldöntheti:

- csak az elemzési eredményt menti;
- az elemzési eredményt és rövid preview waveformot menti;
- későbbi feature flag mellett az eredeti audio lokális másolatát is menti.

Az alapértelmezés: nyers audio nem kerül tartós tárolásra.

---

# 7. Elemzési capability modell

## 7.1 Capability azonosítók

```dart
enum AnalysisCapability {
  signalQuality,
  onsetTimeline,
  strumDirection,
  chordTimeline,
  beatGrid,
  tempoCurve,
  timingAccuracy,
  dynamicConsistency,
  monophonicPitch,
  intonation,
  noteStability,
  transitionSmoothness,
  targetAlignment,
  sectionComparison,
}
```

## 7.2 Capability status

```dart
enum CapabilityStatus {
  available,
  degraded,
  unavailable,
  notApplicable,
}
```

## 7.3 Unavailable reason

```dart
enum CapabilityUnavailableReason {
  clipTooShort,
  insufficientEvents,
  inputTooNoisy,
  inputClipped,
  polyphonicInput,
  backingTrackDominant,
  confidenceTooLow,
  modelUnavailable,
  unsupportedFormat,
  unsupportedSampleRate,
  noReferenceTarget,
  cancelled,
  internalFailure,
}
```

## 7.4 CapabilityReport

```dart
final class CapabilityReport {
  const CapabilityReport({
    required this.capability,
    required this.status,
    required this.confidence,
    this.reason,
    this.details = const {},
  });

  final AnalysisCapability capability;
  final CapabilityStatus status;
  final double confidence;
  final CapabilityUnavailableReason? reason;
  final Map<String, Object?> details;
}
```

## 7.5 Publikációs szabály

Egy metrika csak akkor jelenhet meg normál értékként, ha:

- capability `available` vagy megfelelően jelölt `degraded`;
- confidence a metrika küszöbe felett van;
- input quality nem zárja ki;
- elegendő esemény áll rendelkezésre;
- a metrika definíciója érvényes az adott analysis mode-ban.

Ellenkező esetben az UI magyarázott unavailable állapotot mutat.

---

# 8. Célarchitektúra

## 8.1 Flutter feature struktúra

```text
lib/features/audio_analysis/
├── public.dart
├── domain/
│   ├── analysis_document.dart
│   ├── analysis_input.dart
│   ├── analysis_target.dart
│   ├── analysis_event.dart
│   ├── analysis_segment.dart
│   ├── analysis_metric.dart
│   ├── analysis_insight.dart
│   ├── analysis_hotspot.dart
│   ├── analysis_capability.dart
│   ├── signal_quality_report.dart
│   ├── analysis_provenance.dart
│   ├── analysis_repository.dart
│   └── analysis_comparison.dart
├── application/
│   ├── analyze_audio_use_case.dart
│   ├── cancel_analysis_use_case.dart
│   ├── save_analysis_use_case.dart
│   ├── compare_analyses_use_case.dart
│   ├── build_practice_from_hotspot_use_case.dart
│   ├── analysis_controller.dart
│   ├── analysis_state.dart
│   └── analysis_progress.dart
├── data/
│   ├── local_analysis_repository.dart
│   ├── analysis_document_codec.dart
│   ├── analysis_migrator.dart
│   ├── audio_fingerprint.dart
│   └── analysis_cache.dart
├── engine/
│   ├── analysis_pipeline.dart
│   ├── analysis_stage.dart
│   ├── analysis_context.dart
│   ├── analysis_cancellation.dart
│   ├── input/
│   ├── preprocessing/
│   ├── events/
│   ├── harmony/
│   ├── rhythm/
│   ├── pitch/
│   ├── dynamics/
│   ├── metrics/
│   ├── confidence/
│   └── insights/
├── presentation/
│   ├── analysis_screen.dart
│   ├── analysis_overview_screen.dart
│   ├── analysis_timeline_screen.dart
│   ├── analysis_metric_detail_screen.dart
│   ├── analysis_compare_screen.dart
│   ├── controllers/
│   └── widgets/
└── adapters/
    ├── legacy_analyze_adapter.dart
    ├── practice_analysis_adapter.dart
    ├── song_analysis_adapter.dart
    └── tutor_analysis_adapter.dart
```

## 8.2 Közös audio engine boundary

A több feature által használt tiszta DSP primitívek végső célhelye:

```text
lib/core/audio/dsp/
lib/core/audio/codec/
lib/core/music/
```

Az Epic nem végezhet kontrollálatlan tömeges fájlmozgatást. A migráció compatibility exportokkal, parity tesztekkel és kis lépésekben történjen.

## 8.3 Függőségi irány

```text
Presentation
    ↓
Application
    ↓
Domain
    ↑
Data / Engine implementations
```

Kötelező szabályok:

- domain nem importál Fluttert;
- engine nem importál widgetet vagy localizationt;
- UI nem hív közvetlenül DSP-osztályt;
- repository nem generál coaching szöveget;
- AI Tutor nem importál engine implementációt;
- Practice és Song feature adapteren keresztül kapcsolódik.

## 8.4 Pipeline kompozíció

```text
AnalysisInput
    ↓
InputValidator
    ↓
Preprocessor
    ↓
SignalQualityStage
    ↓
FeatureExtractionStage
    ├── onset / strum
    ├── chord evidence
    ├── beat / tempo
    ├── pitch, ha támogatott
    └── dynamics
    ↓
MetricComputationStage
    ↓
ConfidenceCalibrationStage
    ↓
InsightBuilderStage
    ↓
AnalysisDocumentAssembler
```

## 8.5 Stage contract

```dart
abstract interface class AnalysisStage<I, O> {
  String get id;
  int get version;

  Future<AppResult<O>> run(
    I input,
    AnalysisStageContext context,
  );
}
```

A tiszta CPU stage használhat szinkron belső algoritmust, de az application számára aszinkron és cancellable szerződést kell biztosítani.

---

# 9. Fő domain modellek

## 9.1 AnalysisDocument

```dart
final class AnalysisDocument {
  const AnalysisDocument({
    required this.id,
    required this.schemaVersion,
    required this.createdAt,
    required this.mode,
    required this.input,
    required this.provenance,
    required this.signalQuality,
    required this.capabilities,
    required this.timeline,
    required this.metrics,
    required this.hotspots,
    required this.insights,
    required this.warnings,
    required this.completion,
  });

  final String id;
  final int schemaVersion;
  final DateTime createdAt;
  final AnalysisMode mode;
  final AnalysisInputSummary input;
  final AnalysisProvenance provenance;
  final SignalQualityReport signalQuality;
  final List<CapabilityReport> capabilities;
  final AnalysisTimeline timeline;
  final List<AnalysisMetricResult> metrics;
  final List<AnalysisHotspot> hotspots;
  final List<AnalysisInsight> insights;
  final List<AnalysisWarning> warnings;
  final AnalysisCompletion completion;
}
```

A listák immutable snapshotként kezelendők.

## 9.2 AnalysisCompletion

```dart
enum AnalysisCompletionStatus {
  complete,
  degraded,
  cancelled,
  failed,
}
```

Menthető dokumentum csak `complete` vagy `degraded` lehet. Cancelled vagy failed run külön run logban tárolható, de Library sessionként nem.

## 9.3 AnalysisInput

```dart
sealed class AnalysisInput {
  const AnalysisInput();
}

final class PcmAnalysisInput extends AnalysisInput {
  const PcmAnalysisInput({
    required this.samples,
    required this.sampleRate,
    required this.channelCount,
    required this.source,
    this.sourceName,
  });

  final Float32List samples;
  final int sampleRate;
  final int channelCount;
  final AnalysisInputSource source;
  final String? sourceName;
}
```

Nagy input esetén a végső implementáció használhat file-backed buffert vagy transferable typed data megoldást a fölösleges másolás csökkentésére.

## 9.4 AnalysisTarget

```dart
final class AnalysisTarget {
  const AnalysisTarget({
    required this.id,
    required this.kind,
    required this.timebase,
    this.expectedEvents = const [],
    this.expectedChords = const [],
    this.expectedNotes = const [],
    this.sections = const [],
  });
}
```

A target verziózott snapshot legyen. Ne tartalmazzon közvetlen provider referenciát.

## 9.5 AnalysisTimeline

```dart
final class AnalysisTimeline {
  const AnalysisTimeline({
    required this.duration,
    required this.events,
    required this.chordSegments,
    required this.beats,
    required this.bars,
    required this.tempoPoints,
    required this.pitchSegments,
    required this.dynamicPoints,
  });
}
```

## 9.6 AnalysisEvent

```dart
sealed class AnalysisEvent {
  const AnalysisEvent({
    required this.id,
    required this.time,
    required this.confidence,
  });

  final String id;
  final Duration time;
  final double confidence;
}
```

Kezdeti event típusok:

- `OnsetEvent`;
- `StrumEvent`;
- `ChordChangeEvent`;
- `BeatEvent`;
- `NoteOnsetEvent`;
- `SilenceRegionEvent`;
- `ClippingRegionEvent`.

## 9.7 Időábrázolás

Domainben előnyben részesítendő:

- `Duration`;
- vagy egész mikroszekundum / samples index.

A lebegőpontos másodperc csak serializációs és UI boundaryn használható.

Minden event opcionálisan hordozhat sample indexet a reprodukálható timebase érdekében.

## 9.8 Metric result

```dart
final class AnalysisMetricResult {
  const AnalysisMetricResult({
    required this.id,
    required this.version,
    required this.status,
    required this.confidence,
    required this.value,
    required this.unit,
    required this.sampleCount,
    required this.evidence,
    this.unavailableReason,
  });
}
```

A `value` ne legyen korlátlan `dynamic`. Használható sealed metric value hierarchia:

- scalar;
- percentage;
- duration;
- distribution;
- time series;
- category;
- score.

## 9.9 AnalysisHotspot

```dart
final class AnalysisHotspot {
  const AnalysisHotspot({
    required this.id,
    required this.kind,
    required this.range,
    required this.severity,
    required this.confidence,
    required this.metricIds,
    required this.evidenceIds,
  });
}
```

Hotspot nem tartalmaz végleges coaching mondatot. A lokalizált szöveg template és insight alapján készül.

## 9.10 AnalysisInsight

```dart
final class AnalysisInsight {
  const AnalysisInsight({
    required this.id,
    required this.ruleId,
    required this.ruleVersion,
    required this.priority,
    required this.kind,
    required this.factIds,
    required this.messageKey,
    required this.messageArgs,
    required this.recommendedAction,
  });
}
```

Az insight determinisztikus, tesztelhető szabályból származik.

---

# 10. Provenance és verziózás

## 10.1 AnalysisProvenance

Tartalmazza:

- app version;
- analyzer version;
- pipeline version;
- stage versionök;
- DSP config hash;
- model manifest ID-k;
- input fingerprint;
- platform;
- target version;
- feature flag snapshot;
- locale nem szükséges a méréshez, csak a megjelenítéshez.

## 10.2 Analyzer version

Az analyzer version csak akkor változzon major módon, ha:

- metrika definíció változik;
- event timebase változik;
- confidence kalibráció inkompatibilisen változik;
- új modell alapértelmezetté válik és kimenete nem közvetlenül összevethető.

## 10.3 Metric version

Minden metrika külön verzióval rendelkezzen.

Példa:

```text
timing.mean_absolute_error.v1
rhythm.rush_drag_bias.v1
dynamics.strum_consistency.v1
harmony.chord_coverage.v2
```

Két session automatikus összehasonlítása csak kompatibilis metric ID és version mellett engedélyezett.

## 10.4 Input fingerprint

A fingerprint célja:

- cache;
- duplikált import felismerése;
- reproducibility;
- diagnosztika.

A fingerprint ne legyen felhasználóazonosító. Nyers audio nem rekonstruálható belőle.

Javasolt input:

- normalizált minták vagy fájlbájtok hash-e;
- sample rate;
- channel mapping;
- preprocessing config.

## 10.5 Migráció

A jelenlegi `AnalyzeResult` és `AnalyzedSession` adatokból automatikus V2 migráció szükséges.

Migrált dokumentum esetén:

- a meglévő chord és strum timeline megmarad;
- BPM megmarad legacy metrikaként;
- új metrikák unavailable státuszt kapnak;
- provenance jelzi a `legacyMigration` forrást;
- semmilyen új mérés nem található ki a régi adatokból;
- a custom title megmarad;
- a session ID és createdAt megmarad.

---

# 11. Input validáció és jelminőség

## 11.1 Kötelező inputellenőrzések

- nem üres minta;
- pozitív sample rate;
- támogatott csatornaszám;
- véges számértékek;
- NaN és infinity elutasítása vagy biztonságos sanitization;
- maximum hossz;
- minimum hossz;
- fájlméretkorlát;
- támogatott WAV chunk struktúra;
- channel interleave integritás.

## 11.2 SignalQualityReport

```dart
final class SignalQualityReport {
  const SignalQualityReport({
    required this.overall,
    required this.peakDbfs,
    required this.rmsDbfs,
    required this.noiseFloorDbfs,
    required this.clippedSampleRatio,
    required this.silentRatio,
    required this.tonalness,
    required this.warnings,
  });
}
```

## 11.3 Clipping

Mérendő:

- abszolút peak;
- közel full-scale minták aránya;
- egymást követő clipped régiók;
- clipped region időtartam.

A clipping warning ne állítsa automatikusan, hogy a játék rossz. Azt jelezze, hogy a felvétel torzult, ezért bizonyos metrikák kevésbé megbízhatók.

## 11.4 Túl halk jel

A túl halk jel meghatározása:

- RMS;
- peak;
- zajpadlóhoz viszonyított jel;
- aktív régiók száma.

A statikus globális küszöb mellett kalibrációs vagy adaptív becslés használható, de determinisztikus és tesztelt legyen.

## 11.5 Zaj és háttérzene

A rendszer kezdetben proxykat használhat:

- tonalness;
- harmonic/percussive arány;
- onset density;
- spectral flatness;
- voice rejection evidence;
- chord consistency.

Nem szabad biztosan kijelenteni, hogy egy adott hangforrás emberi beszéd, dob vagy másik hangszer, ha erre nincs külön modell.

## 11.6 Live recording feedback

Felvétel közben könnyű, olcsó mérés futhat:

- input level;
- clipping indicator;
- mic unavailable;
- túl halk jel;
- maximum duration.

A teljes elemzési pipeline ne fusson kétszer csak azért, mert felvétel közben preview látható.

---

# 12. Előfeldolgozás

## 12.1 Mono downmix

Stereo input esetén:

- interleaving validáció;
- determinisztikus átlagolás;
- clipping ellenőrzés downmix után;
- phase cancellation kockázat dokumentálása.

A rendszer később választhat jobb csatornát, de a V1 viselkedés legyen reprodukálható.

## 12.2 DC offset eltávolítás

DC removal csak akkor vezessük be, ha:

- fixture teszt bizonyítja;
- onset és chroma parity nem romlik;
- verziózott preprocessing config tartalmazza.

## 12.3 Resampling

A pipeline belső kanonikus sample rate-et használhat.

Követelmények:

- minőségi resampler;
- anti-alias filtering;
- determinisztikus output;
- sample-to-time mapping megőrzése;
- resampling latency dokumentálása;
- fixture parity több bemeneti sample rate-re.

Tilos egyszerű nearest-neighbor resampling productionben.

## 12.4 Normalizáció

Automatikus peak normalization csak óvatosan használható, mert eltorzíthatja a dinamikai metrikákat.

Szabály:

- chord/pitch feature extraction kaphat normalizált másolatot;
- dynamics metric az eredeti amplitúdóarányokat használja;
- preprocessing context külön tárolja az eredeti és feldolgozott reprezentációt;
- hard clippinget normalizáció nem javít meg.

## 12.5 HPSS

A jelenlegi HPSS implementáció kísérleti feature extraction ágként használható.

Követelmények:

- inputot nem módosíthatja;
- dimensions preserved;
- hard/soft mask külön verziózott;
- chord evidence-re gyakorolt hatás evaluationnel igazolandó;
- alapértelmezett shipping path csak mérés után változhat.

## 12.6 Chroma denoise

A temporal median és bass weighting konfiguráció:

- analyzer provenance része;
- nincs rejtett magic number;
- real-audio evaluationnel validált;
- rövid klipen safe fallbacket használ.

---

# 13. Esemény- és harmóniaelemzés

## 13.1 Onset timeline

A rendszer megtartja a jelenlegi SuperFlux/onset alapot.

Új követelmények:

- minden onset event sample indexet és időt kap;
- confidence kalibrált tartományban legyen;
- minimum separation dokumentált;
- suppression reason opcionálisan diagnosztikában elérhető;
- túl sűrű event sorozat quality warningot válthat ki;
- onset event és strum event ne legyen automatikusan azonos fogalom.

## 13.2 Strum event

A strum event tartalmazhatja:

- irány;
- irány confidence;
- onset confidence;
- attack strength;
- local RMS;
- source classifier;
- fallback flag.

A CRNN és heurisztikus classifier közti fallback legyen látható provenance-ben.

## 13.3 Chord evidence

A chord output ne csak végleges címke legyen.

A belső representation tartalmazhat:

- frame time;
- top label;
- top confidence;
- top-k evidence;
- no-chord probability;
- tonalness;
- decoder source;
- bass/treble evidence summary.

A teljes top-k timeline nem feltétlenül kerül tartós Library storage-ba. Tárolási policy szükséges.

## 13.4 Chord segmentation

Követelmények:

- minimum segment duration;
- transient merge policy;
- silence/no-chord kezelés;
- clip end pontos lezárása;
- gyors chord change fixture;
- overlapping ring-out fixture;
- label normalization;
- enharmonic display külön UI policy.

## 13.5 DSP és ML fusion

Az Epic lehetővé teszi fusion kísérletet, de shipping default csak evaluation után változhat.

Lehetséges stratégia:

- DSP primary, ML advisory;
- ML primary, DSP fallback;
- confidence-weighted fusion;
- disagreement-aware abstention.

A választott stratégia feature flag és model manifest alapján reprodukálható legyen.

## 13.6 Chord metric target nélkül

Free-play módban mérhető:

- chord vocabulary;
- segment count;
- change density;
- chord confidence;
- transition duration proxy;
- no-chord ratio.

Nem mérhető objektíven „chord accuracy”, ha nincs elvárt referencia.

## 13.7 Chord metric targettel

Target mellett mérhető:

- chord coverage;
- correct chord duration ratio;
- chord change timing error;
- missed changes;
- extra changes;
- confusion pairs;
- target section accuracy.

Az alignment algoritmus toleranciaablakot és confidence súlyozást használjon.

---

# 14. Beat, tempo és metre

## 14.1 Beat grid

A beat grid ne kizárólag egy BPM számból származzon.

```dart
final class BeatPoint {
  const BeatPoint({
    required this.index,
    required this.time,
    required this.confidence,
    required this.source,
  });
}
```

Források:

- onset interval inference;
- target timebase;
- song reference;
- backing track sync;
- tap/known tempo.

## 14.2 Tempo curve

A tempo curve időbeli pontokból álljon.

Mérhető:

- median BPM;
- interquartile range;
- local tempo deviation;
- drift slope;
- sudden jumps;
- stable region ratio.

## 14.3 Rövid klip

Rövid klipből:

- BPM confidence alacsony lehet;
- tempó trend nem publikálható;
- metre nem becsülhető;
- timing target nélkül unavailable lehet.

## 14.4 Metre

Kezdeti támogatás:

- ismert targetből 3/4 vagy 4/4;
- free-play esetén metre inference kísérleti, feature flag mögött;
- gyenge confidence esetén nincs metre állítás.

## 14.5 Known target előnye

Practice vagy Song target esetén a target beat grid elsődleges. A detected eventeket ehhez kell alignolni, nem kell újra kitalálni a tempót.

## 14.6 Tempo ambiguity

A half-time és double-time ambiguity kezelésére:

- target esetén target BPM;
- free-play esetén alternatív hypothesis;
- confidence reduction;
- UI-ban ne jelenjen meg hamis precizitás.

Például 60 és 120 BPM közti bizonytalanság esetén a rendszer jelezze, hogy a pulzusértelmezés bizonytalan.

---

# 15. Timing és groove metrikák

## 15.1 Target alignment

Minden detected eventet csak szabályozott módon lehet expected eventhez rendelni.

Lehetséges algoritmus:

- monotonic dynamic programming;
- költség: time distance, event type mismatch, direction mismatch, confidence;
- missed és extra event penalty;
- maximum match window;
- determinisztikus tie-break.

Greedy matching csak bizonyítottan egyszerű use case-ben engedélyezett.

## 15.2 Timing error

Egy matched event hibája:

```text
observed_time - expected_time
```

- negatív: sietés;
- pozitív: késés.

A UI lokalizált és könnyen érthető nyelvet használjon.

## 15.3 Kötelező timing metrikák

- mean absolute timing error;
- median absolute timing error;
- p90 absolute timing error;
- signed timing bias;
- early event ratio;
- late event ratio;
- on-time ratio;
- missed event ratio;
- extra event ratio;
- longest stable streak.

## 15.4 Toleranciaablak

A tolerancia ne legyen minden tempón ugyanaz a fix milliszekundum.

Lehetséges policy:

- beat duration arány;
- minimum és maximum ms clamp;
- difficulty és exercise type;
- analyzer versionben rögzített formula.

## 15.5 Free-play timing

Target nélküli timing csak becsült beat gridhez mérhető.

Ilyenkor a metric:

- külön ID-t kapjon;
- alacsonyabb confidence-et kapjon;
- ne legyen közvetlenül összehasonlítva target-alapú timinggal.

## 15.6 Groove

Az első verzióban groove alatt nem stílusérzékelést értünk.

Mérhető proxyk:

- subdivision consistency;
- alternating long/short pattern stabilitása;
- accent position consistency;
- beat-relative timing distribution.

A „swing” csak ismert target vagy elég erős, validált pattern esetén jelenjen meg.

---

# 16. Dinamika és kontroll

## 16.1 Dinamikai event érték

Minden strumhoz számítható:

- attack peak;
- local RMS;
- short-term energy;
- normalized strength a session mediánjához képest.

## 16.2 Kötelező dinamikai metrikák

- stroke strength coefficient of variation;
- downstroke/upstroke median ratio;
- accidental outlier ratio;
- accent target accuracy, ha van target;
- dynamic drift;
- quiet region ratio;
- clipped event ratio.

## 16.3 Felvételi távolság hatása

A dinamikai metrika sessionön belül megbízhatóbb, mint sessionök között.

Két session dinamikája csak akkor hasonlítható össze, ha:

- input gain és mic route kompatibilis;
- nincs clipping;
- signal quality hasonló;
- normalizációs policy azonos;
- provenance ezt engedélyezi.

## 16.4 Direction balance

A down/up arány önmagában nem minőségi mutató.

Csak akkor adható értékelő jelentés, ha:

- target pattern ismert;
- expected direction ismert;
- classifier confidence megfelelő.

Free-play módban csak leíró statisztika.

## 16.5 Accent detection

Accent target esetén mérhető:

- expected accent event strength percentile;
- non-accent eventhez viszonyított ratio;
- missed accent;
- accidental accent.

A globális hangerőváltozás és a valódi accent különválasztása szükséges.

---

# 17. Pitch és monofonikus capability

## 17.1 Scope

A projektben már van YIN alapú tuner. Ez újrahasznosítható, de nem jelenti azt, hogy teljes polifonikus note transcription készen áll.

A pitch modul első verziója kizárólag capability gate mellett futjon.

Támogatott kezdeti esetek:

- izolált egyhangos gyakorlat;
- scale practice target;
- monofonikus riff target;
- referenciahanghoz viszonyított kitartott hang.

## 17.2 Pitch segment

```dart
final class PitchSegment {
  const PitchSegment({
    required this.range,
    required this.medianHz,
    required this.medianMidi,
    required this.centsOffset,
    required this.stabilityCents,
    required this.confidence,
  });
}
```

## 17.3 Kötelező pitch metrikák támogatott inputon

- note hit ratio;
- median cents error;
- p90 cents error;
- pitch stability;
- note transition timing;
- sustained note duration;
- unwanted pitch dropout ratio.

## 17.4 Intonation

Az intonation metric nem diagnosztizál gitárbeállítási problémát. Csak azt jelzi, hogy a mért pitch a targethez képest magasabb vagy alacsonyabb volt.

## 17.5 Bend és vibrato

Bend/vibrato elemzés csak későbbi feature flag mögött indulhat.

Kezdeti proxyk:

- pitch excursion;
- target interval reach;
- overshoot;
- hold stability;
- vibrato rate;
- vibrato extent.

Shipping előtt szükséges:

- izolált monofonikus dataset;
- ground-truth annotation;
- evaluation report;
- minimum confidence;
- félreérthető UI állítások felülvizsgálata.

## 17.6 Polifonikus input

Ha a pitch tracker instabil vagy több hang dominál:

- monophonic capability unavailable;
- nincs hamis note score;
- a chord és rhythm elemzés ettől még folytatódhat.

---

# 18. Tisztaság és technikai proxyk

## 18.1 Alapelv

A „cleanliness” nem közvetlenül megfigyelhető egyetlen számmal. Az első verzió csak auditálható proxykat használhat.

## 18.2 Lehetséges proxyk

- onset után tartós magas frekvenciás zaj;
- nem kívánt extra onset density;
- chord confidence dip;
- no-chord gap a váltás körül;
- sustained note pitch dropout;
- attack utáni instabilitás;
- signal-to-noise változás;
- target chord transition körüli evidence collapse.

## 18.3 Tiltott elnevezés

A metric UI-neve ne legyen egyszerűen „Technique score”, ha csak hangproxykat mér.

Javasolt nevek:

- „Hangindítás tisztasága”;
- „Váltás folyamatossága”;
- „Kitartás stabilitása”;
- „Nem várt extra hangindítások”.

## 18.4 Confidence gate

Ezek a proxyk csak akkor jelenjenek meg, ha:

- target ismert;
- input nem clipped;
- backing track nem domináns;
- elegendő ismétlés van;
- evaluation igazolja a kapcsolatot.

## 18.5 Nincs egészségügyi állítás

A rendszer nem adhat sérülésmegelőzési, fizioterápiás vagy orvosi diagnózist hang alapján.

---

# 19. Confidence és bizonytalanság

## 19.1 Confidence jelentése

A confidence nem azonos a felhasználó teljesítményével.

A confidence azt jelzi, mennyire bízik a rendszer a saját mérésében.

## 19.2 Confidence összetevők

- signal quality;
- model confidence;
- event count;
- target alignment quality;
- hypothesis agreement;
- temporal consistency;
- input capability;
- calibration result.

## 19.3 Kalibráció

A nyers softmax vagy cosine score nem publikálható automatikusan probabilityként.

Szükséges:

- calibration dataset;
- reliability diagram;
- expected calibration error;
- threshold kiválasztás;
- model/version szerinti kalibráció.

## 19.4 Confidence aggregation

A dokumentum overall confidence-e nem lehet egyszerű átlag, ha kritikus capability unavailable.

Javasolt:

- per-metric confidence;
- per-section confidence;
- overall quality grade csak információs célra;
- a részletek mindig megnyithatók.

## 19.5 UI megjelenítés

Normál felhasználónak:

- „Magas megbízhatóság”;
- „Közepes megbízhatóság”;
- „Bizonytalan mérés”.

Lab módban:

- numerikus confidence;
- source;
- calibration version;
- disagreement;
- unavailable reason.

## 19.6 Abstention

A rendszernek joga és kötelessége azt mondani:

> Ezt a részletet ebből a felvételből nem tudtam megbízhatóan megmérni.

Ez jobb, mint egy hamis pontszám.

---

# 20. Determinisztikus insight engine

## 20.1 Cél

Az insight engine a mért tényeket cselekvési javaslattá alakítja generatív modell nélkül.

## 20.2 Input

- metric resultök;
- hotspotok;
- capability report;
- analysis target;
- session hossza;
- learner preference, ha engedélyezett;
- előző session trend, ha kompatibilis.

## 20.3 Rule contract

```dart
abstract interface class AnalysisInsightRule {
  String get id;
  int get version;
  int get priority;

  AnalysisInsight? evaluate(AnalysisInsightContext context);
}
```

## 20.4 Példa szabályok

- stabil tempó, de irányarány targettől eltér;
- második félidőben növekvő timing error;
- chord change hotspot ismétlődően ugyanott;
- túl halk felvétel miatt újrafelvétel ajánlott;
- p90 timing jelentősen rosszabb a mediánnál, tehát néhány nagy hiba dominál;
- downstroke erős, upstroke gyenge targethez képest;
- session túl rövid értékelhető trendhez;
- előző sessionhöz képest javulás csak kompatibilis metrikán.

## 20.5 Prioritás

Egy overview legfeljebb:

- 1 elsődleges javítandó pont;
- 1 erősség;
- 1 következő gyakorlat;
- 1 felvételminőségi warning

jelenjen meg alapból.

A részletek külön nyithatók.

## 20.6 Action descriptor

A javasolt action ne közvetlen navigációs callback legyen.

```dart
sealed class RecommendedAnalysisAction {
  const RecommendedAnalysisAction();
}
```

Példák:

- practice hotspot;
- repeat slower;
- calibrate input;
- compare with previous;
- open chord transition exercise;
- ask tutor.

## 20.7 AI Tutor integráció

A Tutor megkapja:

- insight ID;
- rule ID;
- metric factokat;
- hotspot range-et;
- confidence-et;
- ajánlott actiont.

A Tutor nem módosíthatja a mérés számértékeit.

---

# 21. Elemzési state machine

## 21.1 Állapotok

```dart
sealed class AudioAnalysisState {
  const AudioAnalysisState();
}
```

Kötelező állapotok:

- idle;
- acquiringInput;
- recording;
- validating;
- analyzing;
- completed;
- degradedCompleted;
- cancelled;
- permissionDenied;
- inputError;
- analysisError.

## 21.2 Run ID

Minden elemzési futás egyedi run ID-t kap.

Későn érkező progress vagy result csak akkor írhat state-et, ha a run ID még aktív.

## 21.3 Transition szabályok

Példák:

- idle → recording;
- recording → analyzing;
- analyzing → completed;
- analyzing → cancelled;
- acquiringInput → inputError;
- permissionDenied → recording csak új explicit user action után;
- completed → idle új elemzéskor;
- completed result ne vesszen el tab switch miatt, ha termékdöntés szerint megőrzendő.

## 21.4 Invalid transition

Invalid transition:

- debug módban assert/log;
- productionben kontrollált no-op vagy failure;
- nem okozhat dupla mic startot;
- nem okozhat késői result overwrite-ot.

## 21.5 Controller felelősség

A controller:

- koordinál;
- state-et publikál;
- use case-eket hív;
- cancellationt kezeli.

Nem végez:

- FFT-t;
- JSON serializációt;
- repository implementációt;
- localized insight szöveggyártást;
- közvetlen pluginhívást.

---

# 22. Elemzési végrehajtás, isolate és memória

## 22.1 Isolate runner

A jelenlegi `compute` helper jó alap, de az új rendszerhez szükséges:

- progress event;
- cancellation;
- több stage;
- model loading cache;
- error envelope;
- large buffer transfer optimalizáció.

Javasolt dedikált runner abstraction.

## 22.2 TransferableTypedData

Nagy PCM inputnál vizsgálandó:

- `TransferableTypedData`;
- file-backed temp input;
- Float32 használat Float64 helyett, ahol parity megengedi;
- fölösleges másolatok száma.

Bármilyen numeric típusváltás előtt parity és teljesítménymérés kötelező.

## 22.3 Modellbetöltés

A model asset:

- checksum-ellenőrzött;
- manifesttel verziózott;
- fő isolate-on egyszer betöltött vagy dedikált workerben cache-elt;
- parse hiba esetén biztonságosan fallbackel;
- ne töltődjön újra minden stage-ben.

## 22.4 Cancellation token

```dart
abstract interface class AnalysisCancellationToken {
  bool get isCancelled;
  void throwIfCancelled();
}
```

A hosszú ciklusok rendszeres checkpointot használjanak.

## 22.5 Maximum input duration

A maximum kliphossz konfigurált legyen.

Első shipping érték csak mérés után választható. Példaként 5–10 perc, de ezt nem szabad vakon beégetni.

Hosszabb inputnál:

- user-facing hiba;
- opcionális trim;
- későbbi chunked analysis.

## 22.6 Chunked analysis

A V2 architektúra tegye lehetővé, de az első implementation csak akkor használja, ha:

- segment boundary handling tesztelt;
- Viterbi/global context igény kezelve;
- tempo continuity megőrzött;
- duplicate onset elkerülve;
- memory benefit mérve.

## 22.7 Performance budget

Mérendő legalább:

- wall-clock analysis time;
- real-time factor;
- peak memory;
- model load time;
- stage duration;
- UI dropped frames;
- cancel latency.

Célként:

- tipikus 30 másodperces klip elemzése középkategóriás támogatott Android eszközön ne legyen indokolatlanul hosszabb a klip hosszánál;
- konkrét küszöb baseline mérésből kerüljön rögzítésre;
- Epic utáni regresszió legfeljebb dokumentált tolerancia lehet.

---

# 23. Cache és újraelemzés

## 23.1 Cache kulcs

```text
input fingerprint
+ analyzer version
+ model manifest IDs
+ DSP config hash
+ target hash
+ feature flag snapshot
```

## 23.2 Cache tartalom

Tárolható:

- végleges AnalysisDocument;
- drága köztes feature, ha tárhelypolicy engedi;
- waveform preview;
- stage timing.

Nem tárolható automatikusan:

- nyers audio korlátlanul;
- auth token;
- érzékeny diagnosztikai payload.

## 23.3 Cache invalidáció

- analyzer version változik;
- metric version inkompatibilis;
- model manifest változik;
- target változik;
- preprocessing config változik;
- user explicit reanalyze.

## 23.4 Reanalyze policy

Régi session új analyzerrel újraelemezhető csak akkor, ha az eredeti audio elérhető.

Ha nincs audio:

- nincs új mérés;
- legacy document marad;
- UI ne ígérjen reanalysis lehetőséget.

## 23.5 Tárhelykorlát

- LRU vagy recency alapú cap;
- cache méret mérhető;
- felhasználó törölheti;
- mentett session document nem törlődik cache clear esetén;
- raw audio retention külön policy.

---

# 24. Persistence és Library V2

## 24.1 Repository contract

```dart
abstract interface class AnalysisRepository {
  Future<AppResult<List<AnalysisSummary>>> list();
  Future<AppResult<AnalysisDocument?>> getById(String id);
  Future<AppResult<void>> save(AnalysisDocument document);
  Future<AppResult<void>> rename(String id, String title);
  Future<AppResult<void>> delete(String id);
  Future<AppResult<void>> replace(AnalysisDocument document);
}
```

## 24.2 Storage stratégia

A nagy AnalysisDocument nem ideális egyetlen SharedPreferences JSON tömbben.

Javasolt megoldás:

- index külön;
- dokumentumonként külön fájl vagy lokális adatbázis rekord;
- atomikus write;
- temp file + rename;
- checksum;
- schema version;
- részleges korrupció izolálása.

A konkrét storage technológia külön ADR-ben döntendő el. Lehet file-based JSON, SQLite/Drift vagy más támogatott lokális store.

## 24.3 Summary és full document

A Library lista ne töltse be minden session teljes timeline-ját.

```dart
final class AnalysisSummary {
  const AnalysisSummary({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.duration,
    required this.primaryMetrics,
    required this.completionStatus,
  });
}
```

## 24.4 Nyers audio retention

Külön entitás:

```dart
final class AudioRetentionPolicy {
  const AudioRetentionPolicy({
    required this.keepOriginal,
    required this.autoDeleteAfter,
  });
}
```

Alapértelmezés:

- `keepOriginal = false`;
- preview waveform tárolható;
- felhasználó explicit dönthet később.

## 24.5 Törlés

Session törlésekor:

- document törlődik;
- index frissül;
- opcionális audio törlődik;
- cache törlődik;
- kapcsolódó cloud sync tombstone kezelhető később;
- practice history aggregált adata külön retention policy szerint maradhat.

## 24.6 Legacy migráció

A migráció:

- idempotens;
- megszakítható;
- részleges hibát izolál;
- backupot készíthet a régi raw JSON-ról;
- siker után jelöli a schema versiont;
- nem törli a régi store-t addig, amíg az új dokumentumok validálása nem sikerült.

---

# 25. UI és információs architektúra

## 25.1 Analyze landing

Kezdeti lehetőségek:

- Új felvétel;
- Hangfájl importálása;
- Legutóbbi elemzés folytatása;
- összehasonlítás;
- felvételi tippek.

A képernyő ne legyen túlzsúfolt. A haladó módok secondary actionként jelenjenek meg.

## 25.2 Recording UI

Mutassa:

- elapsed time;
- input level;
- clipping warning;
- túl halk jel warning;
- stop;
- cancel;
- maximum duration közelítése.

A warning ne ugráljon frame-enként. Debounce/hysteresis szükséges.

## 25.3 Analysis progress UI

Mutassa:

- aktuális fázis;
- rövid magyarázat;
- cancel gomb;
- accessibility semantics;
- reduced motion támogatás;
- nem hamis százalék.

## 25.4 Overview screen

Fő blokkok:

1. elsődleges insight;
2. erősség;
3. következő javasolt gyakorlat;
4. timing summary;
5. rhythm/tempo summary;
6. dynamics summary;
7. harmony/pitch summary capability szerint;
8. signal quality;
9. mentés, összehasonlítás, megosztás, Tutor.

## 25.5 Metric card

Minden card tartalmazza:

- metrika neve;
- érték;
- rövid jelentés;
- confidence jelzés;
- trend, ha kompatibilis;
- detail action;
- unavailable esetén ok és javítási tanács.

## 25.6 Timeline screen

Kötelező lane-ek capability alapján:

- waveform preview;
- chord segments;
- strum/onset events;
- beat/bar grid;
- timing error;
- dynamics;
- pitch;
- hotspot overlay.

## 25.7 Zoom és navigáció

- pinch zoom;
- horizontal pan;
- hotspot next/previous;
- jump to section;
- current selection range;
- minimum és maximum zoom;
- nagy listák virtualizálása;
- tabular time labels.

## 25.8 Accessibility

- lane-ek szemantikailag leírhatók;
- grafikon információja szöveges összegzésként is elérhető;
- color-only encoding tiltott;
- nagy szöveg támogatás;
- minimum touch target;
- screen reader számára hotspot lista;
- reduced motion.

## 25.9 Lab panel

A Lab panel külön marad a normál UX-től.

Mutathat:

- raw confidence;
- decoder source;
- DSP–ML disagreement;
- stage durations;
- model version;
- quality components;
- suppression diagnostics.

---

# 26. Session összehasonlítás és trend

## 26.1 Kompatibilitás

Két session összehasonlítható, ha legalább:

- azonos metric ID és kompatibilis version;
- azonos target vagy kompatibilis free-play mód;
- hasonló input quality;
- elegendő sample count;
- nincs confidence conflict.

## 26.2 Comparison result

```dart
final class AnalysisComparison {
  const AnalysisComparison({
    required this.leftId,
    required this.rightId,
    required this.metricComparisons,
    required this.compatibility,
    required this.warnings,
  });
}
```

## 26.3 Változás

A változás tartalmazza:

- abszolút delta;
- relatív delta, ha értelmes;
- direction: improved, regressed, unchanged, inconclusive;
- confidence;
- minimum meaningful change threshold;
- sample count.

## 26.4 Nem minden nagyobb érték jobb

Metric metadata deklarálja:

- lower is better;
- higher is better;
- target range;
- descriptive only.

Példa:

- timing error: lower better;
- on-time ratio: higher better;
- BPM: descriptive, önmagában nem jobb vagy rosszabb;
- down/up ratio: targetfüggő.

## 26.5 Trend

Trend csak több kompatibilis sessionből készülhet.

Kötelező:

- minimum session count;
- outlier handling;
- date range;
- metric version grouping;
- confidence band;
- nincs túlzó lineáris extrapoláció.

## 26.6 Privacy

A trend lokálisan készül. Cloud sync csak explicit account funkcióval.

---

# 27. Integrációk

## 27.1 Practice Engine adapter

A Practice Engine adapter átad:

- `AnalysisTarget`;
- session ID;
- exercise ID;
- expected event grid;
- difficulty;
- target tempo;
- active section.

Visszakap:

- scoring facts;
- hotspotokat;
- recommended retry tempo;
- completion eligibility;
- progress evidence.

A Practice Engine saját pontozási contractja marad a termék elsődleges session score forrása. Az Audio Analysis részletes evidence-t ad hozzá, nem írja felül önkényesen.

## 27.2 Song Trainer adapter

Átad:

- song document ID/version;
- section;
- beat grid;
- expected chords/notes;
- backing track offset;
- playback speed;
- transposition;
- capo context.

Az eredmény concert pitch és display pitch külön kezelendő.

## 27.3 AI Tutor adapter

A Tutor számára készüljön compact snapshot.

Tartalmazhat:

- top insights;
- key metrics;
- confidence;
- hotspot ranges;
- target context;
- trend facts.

Nem tartalmaz:

- nyers audio;
- teljes waveform;
- több ezer event alapértelmezetten;
- személyes fájlnevet consent nélkül.

## 27.4 Progress adapter

A progress rendszer csak stabil, verziózott evidence-t kapjon.

Példák:

- practice minutes;
- completed session;
- timing skill evidence;
- chord transition skill evidence;
- dynamics control evidence.

A skill state frissítés confidence-weighted és verziózott.

## 27.5 Share adapter

A megosztott kártya:

- ne tartalmazzon érzékeny fájlnevet;
- ne mutasson alacsony confidence metrikát biztos tényként;
- legyen lokalizált;
- használjon kiválasztott, pozitív vagy semleges insightot;
- ne osszon nyers audiofájlt automatikusan.

---

# 28. Adatvédelem és biztonság

## 28.1 Nyers audio

Alapértelmezés:

- memóriában vagy temp fájlban feldolgozódik;
- elemzés után törlődik;
- nem kerül logba;
- nem kerül crash reportba;
- nem kerül Tutor contextbe;
- nem kerül backupba explicit policy nélkül.

## 28.2 Temp fájl

- app-private directory;
- random név;
- extension ne hordozzon személyes adatot;
- cancel és crash recovery során cleanup;
- path traversal lehetetlen;
- limitált retention.

## 28.3 Fájlnév

Importált fájlnév opcionális display metadata.

- logban redaktálandó;
- share-ben alapból nem jelenik meg;
- Tutorhoz nem továbbítandó consent nélkül;
- storage migration megőrzi, de privacy flaggel.

## 28.4 Diagnostics

Lab feltöltés:

- külön explicit kapcsoló;
- külön consent;
- külön feature flag;
- payload preview;
- raw audio jelölés;
- upload failure nem rontja az elemzés eredményét.

## 28.5 Adattörlés

A felhasználó törölheti:

- egy sessiont;
- minden elemzést;
- cache-t;
- megtartott audiofájlokat;
- Tutorhoz továbbított session summaryt, ha lokálisan tárolt;
- cloud copyt, ha később létezik.

## 28.6 Biztonságos dekódolás

Import decoder:

- méretkorlát;
- bounds check;
- chunk length validáció;
- integer overflow védelem;
- unsupported codec clean rejection;
- fuzz/property tesztek;
- nem végez hálózati fetch-et fájl alapján.

---

# 29. Tesztelési stratégia

## 29.1 Unit tesztek

Kötelező legalább:

- domain validáció;
- schema codec;
- migration;
- metric calculations;
- confidence aggregation;
- target alignment;
- insight rules;
- signal quality;
- cancellation state;
- comparison compatibility;
- cache key.

## 29.2 DSP fixture tesztek

- csend;
- impulzusok;
- ismert BPM;
- gyors chord progression;
- ring-out overlap;
- stereo downmix;
- clipped audio;
- low level audio;
- noise;
- isolated note;
- bend fixture később;
- vibrato fixture később.

## 29.3 Property-based tesztek

- event time monoton;
- segmentek nem fedik hibásan egymást;
- duration boundary;
- NaN nem jut outputba;
- confidence 0 és 1 között;
- cancellation után nincs result;
- serializer round-trip;
- random WAV chunk nem okoz crash-t;
- alignment monotonic;
- insight fact reference létezik.

## 29.4 Golden tesztek

- overview több screen widthön;
- unavailable metric;
- degraded result;
- timeline lanes;
- zoomolt timeline;
- comparison screen;
- dark/light theme;
- magyar/angol;
- large text.

## 29.5 Integration tesztek

- record → analyze → save → reopen;
- import → analyze → save;
- cancel analysis;
- app background recording közben;
- legacy session migráció;
- Practice target analysis;
- Song reference analysis;
- Tutor snapshot;
- cache hit;
- cache invalidation.

## 29.6 Real-audio evaluation

Külön eval készlet szükséges:

- különböző gitárok;
- különböző telefonok;
- közeli/távoli mikrofon;
- tiszta és zajos szoba;
- kezdő és haladó játék;
- akkordozás;
- egyhangos gyakorlat;
- 3/4 és 4/4;
- különböző tempók;
- left-handed játék nem audio-specifikus, de UX-ben tesztelendő.

## 29.7 Ground truth

Ground truth tartalmazhat:

- event timestamp;
- chord segment;
- expected beat;
- target note;
- strum direction;
- clipping label;
- input quality label.

Kettős annotáció és disagreement review javasolt a kritikus dataseten.

## 29.8 Regression gate

Shipping algoritmus csak akkor változhat, ha:

- fixture parity zöld;
- real-audio eval dokumentált;
- nem romlik kritikus szelet indokolatlanul;
- confidence újrakalibrált;
- analyzer version megfelelően frissült;
- migráció/összehasonlítás policy frissült.

---

# 30. Feature flagek és rollout

## 30.1 Javasolt feature flagek

```text
audioAnalysisV2Enabled
analysisBeatGridEnabled
analysisPitchEnabled
analysisTechniqueProxiesEnabled
analysisComparisonEnabled
analysisAudioRetentionEnabled
analysisExperimentalFusionEnabled
```

## 30.2 Rollout szintek

1. unit és fixture teszt;
2. developer-only;
3. Lab mode;
4. internal dogfood;
5. opt-in beta;
6. default-on;
7. legacy Analyze eltávolítása.

## 30.3 Shadow mode

A V2 futhat shadow módban a V1 mellett Lab környezetben.

Követelmények:

- V1 user result változatlan;
- V2 csak diagnosztikában;
- performance overhead mérve;
- raw audio upload továbbra is consenthez kötött;
- output diff aggregáltan vizsgálható.

## 30.4 Rollback

- feature flaggel V1 visszakapcsolható;
- V2 dokumentum nem sérül;
- Library olvasni tudja mindkét verziót;
- új storage migration nem legyen irreverzibilis backup nélkül.

---

# 31. Codex végrehajtási szabályok

Minden kör elején add át a Codexnek:

1. Olvasd el az `AGENTS.md`, a Chapter 2, Chapter 3, Chapter 4 és ezt a fejezetet.
2. Vizsgáld meg az érintett jelenlegi forrásfájlokat és teszteket.
3. Csak az aktuális kör scope-ját valósítsd meg.
4. Ne kezdj következő körbe.
5. Minden viselkedésváltozást előbb teszttel rögzíts.
6. Ne változtass DSP-konstanst mérés és dokumentáció nélkül.
7. Modellassetet ne cserélj manifest, parity és eval nélkül.
8. Ne találj ki hamis metrikát vagy confidence-et.
9. Ne használj `dynamic` metrikaértéket korlátlanul.
10. Ne hívj DSP-t widgetből.
11. Ne nyeld el a hibát üres `catch` blokkal.
12. Ne logolj nyers audiot, fájlnevet, tokent vagy személyes adatot.
13. Tartsd meg a V1 regressziós teszteket, amíg a migráció nincs lezárva.
14. Futtasd külön a format, analyze és test parancsokat.
15. A kör végén frissítsd a `HANDOFF.md` fájlt.
16. Jelentsd a módosított fájlokat, teszteket, kockázatokat és elhalasztott tételeket.

Branch minta:

```text
codex/epic-06-round-01-baseline
codex/epic-06-round-02-domain
codex/epic-06-round-03-pipeline
```

---

# 32. Fejlesztési körök

---

# Kör 1 — Analyze V2 baseline, mérés és ADR-ek

## Cél

A jelenlegi Analyze funkció pontos technikai baseline-jának rögzítése változtatás nélkül.

## Feladatok

1. Hozd létre:

```text
docs/sdd/07-epic-06-audio-analysis-2.md
docs/baseline/audio-analysis-v1.md
docs/adr/00xx-analysis-document-versioning.md
docs/adr/00xx-analysis-confidence-and-abstention.md
docs/adr/00xx-analysis-raw-audio-retention.md
```

2. Dokumentáld:

- jelenlegi Analyze állapotgép;
- `AnalyzeResult` schema;
- `AnalyzedSession` schema;
- recorder lifecycle;
- WAV támogatás;
- ClipAnalyzer passok;
- CRNN fallback;
- Lab diagnostics;
- Library persistence;
- Learn/Progress/Streak integráció;
- érintett tesztek.

3. Mérd és dokumentáld legalább három fixture esetén:

- elemzési idő;
- peak memória, ha elérhető;
- event count;
- chord timeline;
- BPM;
- model load overhead.

4. Készíts dependency mapet a cross-feature importokról.

## Kötelező ellenőrzések

```bash
flutter analyze lib/ test/
flutter test test/features/analyze
flutter test test/features/library
flutter test test/property
```

## Elfogadási feltételek

- alkalmazáskód nem változott;
- baseline reprodukálható;
- minden jelenlegi teszt eredménye dokumentált;
- ismert flake vagy környezeti limit őszintén feljegyzett;
- létrejöttek az ADR-ek.

## Javasolt commit

```text
docs(analysis): establish Audio Analysis V1 baseline
```

---

# Kör 2 — AnalysisDocument V2 domainmodell

## Cél

A verziózott, immutable V2 domainmodell létrehozása a V1 eltávolítása nélkül.

## Feladatok

1. Hozd létre a domain könyvtárat.
2. Implementáld:

- `AnalysisDocument`;
- `AnalysisCompletion`;
- `AnalysisMode`;
- `AnalysisInputSummary`;
- `AnalysisProvenance`;
- `AnalysisTimeline`;
- `CapabilityReport`;
- `AnalysisMetricResult`;
- `AnalysisHotspot`;
- `AnalysisInsight`;
- warning típusok.

3. Minden modell:

- immutable;
- constructor validation;
- value equality a projekt konvenciója szerint;
- explicit serializer boundary;
- domainben Flutter-import nélkül.

4. Hozz létre metric ID katalógust magic stringek helyett.
5. A `Duration` serializáció mikroszekundumban vagy dokumentált integer egységben történjen.

## Tesztek

- valid dokumentum;
- negatív duration elutasítás;
- confidence range;
- duplicate metric ID;
- invalid segment range;
- invalid completion status;
- equality;
- immutable list snapshot.

## Elfogadási feltételek

- V2 domain lefordul;
- V1 kód változatlanul működik;
- domain nem importál Fluttert vagy más feature belső UI-fájlját;
- tesztlefedettség legalább 90% az új domain validációra.

## Javasolt commit

```text
feat(analysis): add versioned AnalysisDocument domain
```

---

# Kör 3 — Codec, schema validation és V1 adapter

## Cél

A V2 dokumentum biztonságos szerializációja és a jelenlegi `AnalyzeResult` adapterének létrehozása.

## Feladatok

1. Implementáld az `AnalysisDocumentCodec`-ot.
2. A JSON tartalmazzon explicit `schemaVersion` mezőt.
3. Ismeretlen kötelező enum érték kontrollált failure.
4. Opcionális új mező backward-compatible legyen.
5. Hozd létre:

```text
legacy_analyze_adapter.dart
```

6. A V1 → V2 adapter:

- megőrzi durationt;
- BPM-et legacy metricbe teszi;
- chord timeline-t migrálja;
- strum eventeket migrálja;
- Lab agreementet provenance/diagnostics mezőbe teszi;
- hiányzó V2 metricet unavailable státusszal jelöl;
- semmit nem talál ki.

7. Készüljön V2 → legacy view adapter, amíg a régi UI ezt igényli.

## Tesztek

- V2 round-trip;
- V1 fixture migráció;
- pre-3/4 legacy document;
- Lab diagnostics;
- unknown schema;
- corrupted metric;
- NaN JSON;
- extra mezők;
- custom title megőrzése adapteren keresztül.

## Elfogadási feltételek

- régi mentett session fixture olvasható;
- V2 dokumentum determinisztikusan serializálható;
- nincs adatvesztés a meglévő mezőkben;
- ismeretlen schema nem omlasztja össze az appot.

## Javasolt commit

```text
feat(analysis): add schema codec and legacy result adapter
```

---

# Kör 4 — Pipeline contract, stage context és progress

## Cél

A moduláris elemzési pipeline szerződésének létrehozása, még a jelenlegi DSP változtatása nélkül.

## Feladatok

1. Implementáld:

- `AnalysisPipeline`;
- `AnalysisStage`;
- `AnalysisStageContext`;
- `AnalysisProgressEvent`;
- `AnalysisCancellationToken`;
- stage result envelope;
- stage timing diagnostics.

2. A pipeline:

- sorrendben futtat stage-eket;
- progresset publikál;
- cancellationt ellenőriz;
- degradable és fatal failure-t különít el;
- stage ID/versiont provenance-be ír;
- késői eventet run ID-val szűr.

3. Készíts fake stage-eket teszthez.

## Tesztek

- stage order;
- progress order;
- cancellation stage előtt;
- cancellation stage közben;
- degradable failure;
- fatal failure;
- duplicate stage ID;
- provenance timing;
- late progress rejection.

## Elfogadási feltételek

- pipeline Flutter UI nélkül tesztelhető;
- nincs globális mutable state;
- cancellation determinisztikus;
- V1 még nem változik.

## Javasolt commit

```text
feat(analysis): introduce cancellable staged analysis pipeline
```

---

# Kör 5 — Input abstraction és biztonságos import

## Cél

A mikrofonos és importált input közös, validált boundary mögé helyezése.

## Feladatok

1. Implementáld:

- input source modellek;
- decoder gateway;
- input validator;
- maximum byte és duration policy;
- channel metadata;
- source display metadata privacy flag.

2. A jelenlegi WAV decoder kerüljön adapter mögé.
3. A decoder ne adjon nullt indoklás nélkül; használjon typed failure-t.
4. Védelmek:

- invalid RIFF;
- truncated chunk;
- túl nagy chunk size;
- integer overflow;
- unsupported bit depth;
- unsupported format;
- NaN float;
- odd stereo sample count.

5. Készíts fuzz-szerű property tesztet random byte inputra.

## Tesztek

- 16-bit mono;
- 16-bit stereo;
- float 32;
- unknown chunk;
- malformed header;
- oversized file;
- unsupported codec;
- NaN sample;
- privacy-safe source summary.

## Elfogadási feltételek

- import invalid fájlnál nem crash-el;
- hiba lokalizálható failure code-dal;
- régi WAV fixture továbbra is működik;
- parser bounds-safe.

## Javasolt commit

```text
refactor(analysis): centralize validated audio input decoding
```

---

# Kör 6 — Recorder és AudioSessionCoordinator integráció

## Cél

A felvételi útvonal összehangolása a Core audio lifecycle szabályaival.

## Feladatok

1. A `ClipRecorder` mögé kerüljön `AudioCapture` interfész.
2. Használd az `AudioSessionCoordinator` lease-t.
3. A state machine kapjon run ID-t.
4. Kezeld:

- két start;
- start közbeni cancel;
- stop közbeni tab switch;
- app background;
- permission denied;
- permanently denied;
- mic busy;
- plugin exception;
- elapsed timer cleanup.

5. Felvétel közben olcsó signal-level preview publikálható.

## Tesztek

- meglévő recorder hardening tesztek;
- lease conflict;
- background release;
- cancel handshake;
- double stop;
- stale run result;
- preview stream close.

## Elfogadási feltételek

- nincs hot-mic regresszió;
- egyszerre egy mic owner;
- UI és controller nem példányosít közvetlen plugin capture-t;
- régi Analyze screen működik adapteren keresztül.

## Javasolt commit

```text
refactor(analysis): integrate recording with shared audio lifecycle
```

---

# Kör 7 — Signal quality stage

## Cél

Megbízható input quality report létrehozása, amely a későbbi metrikákat gate-eli.

## Feladatok

1. Implementáld:

- peak dBFS;
- RMS dBFS;
- clipped sample ratio;
- silent ratio;
- active region ratio;
- noise floor proxy;
- spectral flatness vagy tonalness proxy;
- quality warningok.

2. Minden formula dokumentált és verziózott.
3. Készíts quality grade policyt, de a részmetrikák maradjanak elérhetők.
4. A recording preview és final quality közös primitíveket használjon, de külön költségszinten.

## Tesztek

- silence;
- low amplitude sine;
- full-scale clipped sine;
- impulse clipping;
- white noise;
- clean chord fixture;
- NaN-free output;
- short clip.

## Elfogadási feltételek

- quality report determinisztikus;
- clipping és silence pontosan jelzett fixture-ön;
- nincs hamis „rossz játék” szöveg;
- confidence gate felhasználhatja az eredményt.

## Javasolt commit

```text
feat(analysis): add calibrated input signal quality stage
```

---

# Kör 8 — Preprocessing context és resampling policy

## Cél

Az eredeti és feature extractionre előkészített audio biztonságos szétválasztása.

## Feladatok

1. Hozd létre `PreprocessedAudio` típust.
2. Tartalmazza:

- original metadata;
- canonical samples;
- sample rate mapping;
- normalization gain;
- preprocessing config/version.

3. Implementálj támogatott resampling megoldást vagy készíts explicit ADR-t, ha a V1-ben minden stage natív sample rate-en marad.
4. Dynamics számára őrizd meg az eredeti amplitude arányokat.
5. DC offset removal és normalization feature flag mögött, parity tesztekkel.

## Tesztek

- 44.1 kHz;
- 48 kHz;
- rövid input;
- stereo downmix;
- time mapping;
- no input mutation;
- dynamics preservation;
- anti-alias fixture, ha resampling készül.

## Elfogadási feltételek

- sample-to-time mapping dokumentált;
- nincs fölösleges normalizációs hatás a dynamics metricen;
- meglévő chord/onset parity nem romlik.

## Javasolt commit

```text
feat(analysis): add versioned preprocessing and timebase context
```

---

# Kör 9 — V1 ClipAnalyzer stage adapter és parity

## Cél

A jelenlegi, bizonyított ClipAnalyzer bekötése az új pipeline-ba viselkedésváltozás nélkül.

## Feladatok

1. Készíts stage adaptert a V1 analyzer köré.
2. A stage output köztes evidence legyen, ne közvetlen UI model.
3. Rögzítsd provenance-ben:

- chunk size;
- chroma window;
- bass weight;
- strum refiner source;
- model manifest.

4. V1 és V2 adapter outputot fixture-ön hasonlítsd össze.
5. A meglévő `computeClipAnalysis` maradjon kompatibilitási útvonal, majd deprecálható.

## Tesztek

- silence;
- two chord;
- four chord;
- ring-out;
- strum timestamp;
- BPM;
- throwing refiner fallback;
- Lab diagnostics;
- empty input.

## Elfogadási feltételek

- V1 timeline parity dokumentált tolerancián belül;
- shipping DSP paraméter nem változott;
- V2 pipeline képes V1 equivalent dokumentumot készíteni.

## Javasolt commit

```text
refactor(analysis): adapt proven clip analyzer into V2 pipeline
```

---

# Kör 10 — Event evidence modell és onset/strum timeline V2

## Cél

A pengetési és onset események gazdag, auditálható reprezentációja.

## Feladatok

1. Különítsd el az onset és strum eventet.
2. Tárold:

- sample index;
- timestamp;
- onset confidence;
- direction;
- direction confidence;
- attack strength;
- source;
- fallback flag.

3. Implementálj stable event ID generálást runon belül.
4. Suppressed event csak Lab diagnosticsban jelenjen meg.
5. Event listák legyenek időrendben és duplicate-free.

## Tesztek

- timestamp parity ± dokumentált tolerancia;
- direction fallback;
- duplicate onset suppression;
- event ordering;
- boundary at zero/end;
- confidence range;
- no NaN.

## Elfogadási feltételek

- event timeline auditálható;
- a régi `TimelineStrum` view adapter működik;
- event ID referálható hotspotból és metric evidence-ből.

## Javasolt commit

```text
feat(analysis): model auditable onset and strum evidence
```

---

# Kör 11 — Chord evidence, segmentation és decoder provenance

## Cél

A chord timeline mögötti evidence és decoder source formalizálása.

## Feladatok

1. Hozd létre chord frame evidence modellt.
2. Implementáld a segment assembler contractot.
3. Kezeld:

- no-chord;
- silence;
- minimum segment;
- transient merge;
- end boundary;
- label normalization;
- confidence aggregation.

4. A DSP és ML decoder result külön source-t kapjon.
5. Lab módban disagreement region hotspot készülhet.
6. Fusion csak feature flag mögött.

## Tesztek

- C→G;
- C→G→Am→F;
- ring-out;
- fast transition;
- silence gap;
- low confidence;
- majmin reduction;
- DSP–ML agreement.

## Elfogadási feltételek

- chord segmentek nem fednek túl hibásan;
- duration határ pontos;
- source/provenance elérhető;
- legacy chord list adapter működik.

## Javasolt commit

```text
feat(analysis): add chord evidence and versioned segmentation
```

---

# Kör 12 — Beat grid és tempo curve

## Cél

Az egyetlen BPM szám helyett időbeli beat- és tempómodell létrehozása.

## Feladatok

1. Implementáld:

- `BeatPoint`;
- `BarPoint`;
- `TempoPoint`;
- beat source;
- tempo hypothesis;
- confidence.

2. Free-play esetén a jelenlegi onset spacing/BPM logika adapterként használható.
3. Target esetén target timebase elsődleges.
4. Kezeld half/double-time ambiguityt.
5. Rövid klipnél capability unavailable/degraded.
6. Számíts:

- median BPM;
- tempo IQR;
- drift;
- stable region ratio.

## Tesztek

- 60 BPM;
- 120 BPM;
- half-time ambiguity;
- accelerando synthetic;
- ritardando synthetic;
- insufficient events;
- 3/4 target;
- 4/4 target.

## Elfogadási feltételek

- legacy BPM summary továbbra is előállítható;
- tempo curve időrendezett;
- target beat grid nem kerül újrabecslésre indokolatlanul;
- confidence őszinte.

## Javasolt commit

```text
feat(analysis): derive beat grid and local tempo curve
```

---

# Kör 13 — Target alignment engine

## Cél

Detected és expected események monoton, determinisztikus illesztése.

## Feladatok

1. Implementálj alignment domain contractot.
2. Használj dynamic programming vagy egyenértékű monotonic algoritmust.
3. Költségek:

- időeltérés;
- direction mismatch;
- event type mismatch;
- missed event;
- extra event;
- confidence weight.

4. Készíts alignment resultot:

- matched pairs;
- missed expected;
- extra observed;
- total cost;
- confidence;
- diagnostics.

5. Tolerancia tempófüggő.

## Tesztek

- perfect match;
- one missing;
- one extra;
- early cluster;
- late cluster;
- duplicate candidate;
- direction mismatch;
- deterministic tie;
- long sequence performance.

## Elfogadási feltételek

- matching monoton;
- inputot nem módosít;
- nincs O(n³) véletlen teljesítményromlás dokumentálatlanul;
- Practice és Song adapter használhatja.

## Javasolt commit

```text
feat(analysis): add deterministic target event alignment
```

---

# Kör 14 — Timing és rush/drag metrikák

## Cél

A target-alapú timing visszajelzés bevezetése.

## Feladatok

1. Implementáld a timing metric katalógust.
2. Számíts:

- mean absolute error;
- median absolute error;
- p90;
- signed bias;
- on-time ratio;
- early ratio;
- late ratio;
- missed ratio;
- extra ratio;
- longest stable streak.

3. Definiáld a tempófüggő tolerance policyt.
4. Készíts timing hotspotokat.
5. Free-play timing külön metric ID-t kapjon.
6. Minimum event count gate.

## Tesztek

- perfect;
- all early;
- all late;
- alternating;
- few large outliers;
- empty;
- one event;
- tolerance clamp;
- confidence weighting.

## Elfogadási feltételek

- millisecond értékek helyes előjellel;
- UI message key külön kezeli sietést/késést;
- nincs timing score reference nélkül normál target metric néven;
- hotspot evidence visszamutat eventekre.

## Javasolt commit

```text
feat(analysis): compute target-aware timing and rush-drag metrics
```

---

# Kör 15 — Rhythm consistency és groove proxyk

## Cél

A timing hibán túl a ritmikai egyenletesség és subdivision stabilitás mérése.

## Feladatok

1. Implementáld:

- inter-onset interval consistency;
- subdivision deviation;
- beat-relative phase distribution;
- stable streak;
- accent position consistency;
- swing ratio csak target esetén.

2. Különítsd el:

- target-based rhythm;
- inferred-grid rhythm.

3. Free-play metric confidence a beat grid confidence-től függjön.
4. Ne adj stilisztikai címkét validálatlanul.

## Tesztek

- even eighths;
- uneven pattern;
- deliberate swing target;
- random onsets;
- tempo drift;
- inferred grid low confidence;
- insufficient data.

## Elfogadási feltételek

- groove nem marketing-pontszám, hanem dokumentált proxy;
- target és free-play eredmény nem keveredik;
- confidence propagation tesztelt.

## Javasolt commit

```text
feat(analysis): add rhythm consistency and subdivision metrics
```

---

# Kör 16 — Dynamics és stroke balance

## Cél

Sessionön belüli pengetési erő és accent kontroll mérése.

## Feladatok

1. Eventenként számíts:

- attack peak;
- local RMS;
- normalized strength;
- clipped flag.

2. Metric:

- coefficient of variation;
- down/up median ratio;
- dynamic drift;
- outlier ratio;
- accent accuracy targettel;
- clipped event ratio.

3. Quality gate:

- clipping;
- auto gain bizonytalanság;
- túl halk jel;
- backing track dominance.

4. Session comparisonben dynamics csak kompatibilis provenance mellett.

## Tesztek

- equal strokes;
- increasing strength;
- alternating accent;
- one outlier;
- clipped attack;
- down/up imbalance;
- normalized gain invariance sessionön belül.

## Elfogadási feltételek

- dynamics metric az eredeti amplitude evidence-t használja;
- nincs „rossz” minősítés target nélkül;
- accent target értékelhető.

## Javasolt commit

```text
feat(analysis): measure strum dynamics and accent control
```

---

# Kör 17 — Monofonikus pitch capability

## Cél

A YIN alapú pitch elemzés biztonságos, targethez kötött bevezetése.

## Feladatok

1. Extractáld vagy adaptereld a tuner YIN algoritmust közös DSP boundarybe.
2. Implementáld:

- pitch frame;
- voiced confidence;
- pitch segment;
- note target alignment;
- cents error;
- stability.

3. Capability gate:

- monofonikus target;
- elegendő voiced frame;
- polyphonic uncertainty;
- noise gate.

4. A Tuner viselkedése parity teszttel védett.

## Tesztek

- A4;
- több gitárhúr frekvenciája;
- cent offset;
- vibrato-like modulation;
- silence;
- chord/polyphonic fixture unavailable;
- note transition;
- tuner parity.

## Elfogadási feltételek

- Tuner nem regresszál;
- pitch metric csak támogatott inputon jelenik meg;
- nincs polifonikus hamis note score;
- target nélküli isolated note analysis külön capabilityként kezelhető.

## Javasolt commit

```text
feat(analysis): add gated monophonic pitch analysis
```

---

# Kör 18 — Technique proxy kísérleti modul

## Cél

Váltási folyamatosság, extra onset és note stability proxyk bevezetése Lab módban.

## Feladatok

1. Implementálj kizárólag dokumentált proxykat:

- chord change gap;
- confidence collapse duration;
- extra onset around transition;
- sustained note dropout;
- attack instability.

2. Minden proxy:

- experimental flag;
- külön metric ID/version;
- confidence gate;
- UI-ban óvatos név;
- nincs „finger placement” állítás.

3. Készíts eval tervet és fixture-ket.
4. Alapértelmezetten csak Lab panelen jelenjen meg.

## Tesztek

- clean transition;
- silence gap;
- extra attack;
- ring-out;
- low-quality input;
- unavailable reason.

## Elfogadási feltételek

- normál shipping UX nem mutat validálatlan proxykat;
- Lab result auditálható;
- minden insight language safety review-ra előkészített.

## Javasolt commit

```text
feat(analysis): add experimental technique proxy metrics
```

---

# Kör 19 — Confidence calibration és capability resolver

## Cél

Metrikánkénti availability, degraded state és confidence egységes meghatározása.

## Feladatok

1. Implementáld a `CapabilityResolver`-t.
2. Inputok:

- signal quality;
- event count;
- model confidence;
- target availability;
- alignment quality;
- mode;
- model availability.

3. Definiálj threshold konfigurációt verzióval.
4. Implementálj confidence combination policyt.
5. Nincs egyszerű, indokolatlan átlag.
6. Készíts Lab diagnostics breakdownot.

## Tesztek

- high-quality target;
- clipped;
- noisy;
- too short;
- no model;
- low alignment;
- partial capability;
- boundary thresholds;
- confidence range.

## Elfogadási feltételek

- minden metrika statuszt kap;
- unavailable reason lokalizálható;
- low confidence nem jelenik meg biztos score-ként;
- policy reprodukálható version alapján.

## Javasolt commit

```text
feat(analysis): calibrate metric confidence and capability gates
```

---

# Kör 20 — Determinisztikus insightok és hotspot ranking

## Cél

A metrikákból rövid, bizonyítható coaching insightok létrehozása.

## Feladatok

1. Hozd létre insight rule registryt.
2. Kezdeti szabályok:

- rush bias;
- drag bias;
- few large timing outliers;
- second-half drift;
- weak upstroke targethez képest;
- chord transition hotspot;
- low signal quality;
- improvement vs compatible previous;
- insufficient data.

3. Minden insight:

- fact ID;
- evidence ID;
- rule version;
- message key;
- recommended action;
- confidence.

4. Ranking ne mutasson túl sok negatív insightot.
5. Legalább egy erősség csak valós evidence esetén.

## Tesztek

- rule trigger;
- non-trigger;
- priority conflict;
- max visible insight;
- unavailable metric;
- low confidence;
- evidence referential integrity;
- localization key parity.

## Elfogadási feltételek

- insight nem talál ki új tényt;
- minden insight visszavezethető metrikára;
- UI maximum policyt követ;
- Tutor adapter felhasználhatja.

## Javasolt commit

```text
feat(analysis): build deterministic evidence-backed coaching insights
```

---

# Kör 21 — AnalysisRepository V2 és legacy Library migráció

## Cél

A nagy, verziózott elemzési dokumentumok biztonságos helyi tárolása.

## Feladatok

1. Válassz storage megoldást ADR-ben.
2. Implementáld:

- summary index;
- document read/write;
- atomic save;
- checksum;
- rename;
- delete;
- cap;
- corruption isolation.

3. Migráld a jelenlegi `library_sessions` adatot.
4. A régi kulcs csak validált migráció után törölhető.
5. Készíts backup/rollback policyt.
6. A Library lista summaryt tölt, nem full timeline-t.

## Tesztek

- save/load;
- atomic failure;
- corrupted one document;
- index rebuild;
- cap;
- rename;
- delete;
- V1 migration;
- repeated migration;
- custom title;
- 3/4 field.

## Elfogadási feltételek

- meglévő felhasználói session nem vész el;
- egy sérült session nem üríti a teljes Libraryt;
- nagy dokumentum nem egyetlen SharedPreferences tömbben tárolódik;
- listázás gyors.

## Javasolt commit

```text
refactor(library): persist versioned analysis documents safely
```

---

# Kör 22 — Analysis runner, progress UI és cancellation

## Cél

Az új pipeline bekötése a felhasználói state machine-be progress és cancel támogatással.

## Feladatok

1. Implementáld az application use case-eket.
2. Controller run ID-val.
3. Progress stream/throttling.
4. Cancel gomb.
5. Late result rejection.
6. Isolate/resource cleanup.
7. Retry policy csak explicit user actionra.
8. Degraded result külön UI állapot.
9. A régi Analyze Controller adapterrel vagy feature flaggel megmarad.

## Tesztek

- full success;
- degraded success;
- cancel;
- stage failure;
- late result;
- new run after cancel;
- tab switch;
- app background;
- progress semantics;
- no duplicate practice credit.

## Elfogadási feltételek

- elemzés megszakítható;
- cancel után nincs késői result;
- progress nem árasztja el az UI-t;
- practice/streak credit pontosan egyszer történik complete resultnál.

## Javasolt commit

```text
feat(analysis): run V2 pipeline with progress and cancellation
```

---

# Kör 23 — Overview screen és metric cardok

## Cél

A V2 eredmény érthető, nem túlzsúfolt áttekintő UI-jának elkészítése.

## Feladatok

1. Készíts overview screen-t.
2. Blokkok:

- primary insight;
- strength;
- next action;
- primary metrics;
- signal quality;
- detail navigation.

3. Készíts reusable metric cardot.
4. Kezeld:

- available;
- degraded;
- unavailable;
- not applicable;
- low confidence.

5. Magyar és angol localization.
6. Large text és kis képernyő.
7. Ne használj color-only állapotot.

## Tesztek

- complete result;
- degraded result;
- unavailable metrics;
- empty-but-valid analysis;
- Hungarian;
- English;
- 320 px width;
- large text;
- semantics;
- golden.

## Elfogadási feltételek

- nincs horizontális overflow;
- nincs hamis score;
- confidence érthető;
- minden action biztonságos és elérhető.

## Javasolt commit

```text
feat(analysis): add capability-aware analysis overview
```

---

# Kör 24 — Többrétegű, zoomolható timeline

## Cél

A részletes időbeli evidence interaktív megjelenítése.

## Feladatok

1. Implementáld lane architecture-t.
2. Lane-ek:

- waveform preview;
- chord;
- beat/bar;
- strum/onset;
- timing error;
- dynamics;
- pitch;
- hotspots.

3. Implementáld:

- zoom;
- pan;
- range selection;
- hotspot jump;
- adaptive labels;
- lane hide/show;
- virtualized rendering.

4. Grafikon mellett szöveges accessibility summary.
5. A jelenlegi `TimelineView` maradjon kompatibilitási view, majd deprecálható.

## Tesztek

- short timeline;
- long timeline;
- zoom bounds;
- hotspot navigation;
- no chord lane;
- pitch lane unavailable;
- 3/4 bar labels;
- semantics;
- performance benchmark;
- golden.

## Elfogadási feltételek

- hosszú session nem épít több ezer teljes widgetet indokolatlanul;
- pan/zoom stabil;
- hotspot evidence megnyitható;
- accessibility alternatíva elérhető.

## Javasolt commit

```text
feat(analysis): add layered zoomable evidence timeline
```

---

# Kör 25 — Session comparison és fejlődési trend

## Cél

Kompatibilis elemzések megbízható összehasonlítása.

## Feladatok

1. Implementáld a compatibility evaluatort.
2. Metric metadata:

- directionality;
- meaningful delta;
- comparable versions;
- input quality requirements.

3. Készíts comparison use case-t.
4. Készíts UI-t:

- before/after;
- delta;
- inconclusive;
- warning;
- trend sparkline.

5. Trend minimum sample counttal.
6. Nincs BPM „javulás” target nélkül.

## Tesztek

- compatible same target;
- incompatible versions;
- poor quality;
- meaningful improvement;
- within noise;
- regression;
- descriptive metric;
- trend outlier;
- UI semantics.

## Elfogadási feltételek

- összehasonlítás nem készül inkompatibilis sessionre;
- inconclusive állapot létezik;
- metric direction helyes;
- confidence és sample count látható detailben.

## Javasolt commit

```text
feat(analysis): compare compatible sessions and trends
```

---

# Kör 26 — Practice, Song és Tutor integráció

## Cél

A V2 elemzés bekötése a többi fő Epic szerződéseihez feature-to-feature belső import nélkül.

## Feladatok

1. Practice adapter:

- target compile;
- result facts;
- hotspot practice action;
- retry tempo.

2. Song adapter:

- reference timeline;
- section;
- transposition;
- capo;
- playback speed;
- backing offset.

3. Tutor adapter:

- compact redacted snapshot;
- top insight;
- facts;
- confidence;
- no raw audio.

4. Progress adapter:

- practice entry egyszer;
- skill evidence;
- versioned source.

5. Public API fájlok és architecture guard.

## Tesztek

- Practice target round-trip;
- Song section alignment;
- capo/concert pitch;
- Tutor redaction;
- no raw audio;
- progress credit once;
- forbidden cross-feature import.

## Elfogadási feltételek

- integráció public contracton keresztül;
- Tutor csak evidence-t kap;
- Practice score nem duplikálódik;
- Song transposition helyes.

## Javasolt commit

```text
feat(analysis): integrate analysis evidence across learning features
```

---

# Kör 27 — Export, share és privacy controls

## Cél

Biztonságosan megosztható és exportálható elemzési összefoglaló.

## Feladatok

1. Készíts redacted export modellt.
2. Formátumok:

- JSON technikai export;
- user-friendly summary;
- share card;
- később CSV metric export opcionálisan.

3. Export preview mutassa, mi kerül ki.
4. Alapból kizárt:

- raw audio;
- importált fájlnév;
- device azonosító;
- secret;
- full internal diagnostics.

5. A Lab export külön, erős figyelmeztetéssel.
6. Session delete és audio retention UI.

## Tesztek

- redaction;
- low confidence omitted/marked;
- no filename;
- no audio;
- JSON schema;
- share localization;
- delete cleanup.

## Elfogadási feltételek

- export privacy-safe alapból;
- felhasználó előnézetet kap;
- share nem állít bizonytalan tényt;
- deletion teljes.

## Javasolt commit

```text
feat(analysis): add privacy-safe analysis export and sharing
```

---

# Kör 28 — Cache, performance és model lifecycle

## Cél

A V2 elemzés költségének kontrollálása és reprodukálható cache bevezetése.

## Feladatok

1. Implementáld audio fingerprintet.
2. Implementáld cache keyt.
3. Cache hit/miss diagnostics.
4. LRU cap.
5. Model bytes/parsed model reuse.
6. Mérd:

- analysis real-time factor;
- peak memory;
- stage duration;
- model load;
- cache hit;
- cancel latency.

7. Vizsgáld `TransferableTypedData` vagy file-backed inputot.
8. Optimalizálás csak benchmark alapján.

## Tesztek

- same input hit;
- analyzer version miss;
- target change miss;
- model change miss;
- corrupted cache;
- LRU;
- concurrent identical request;
- no stale result.

## Elfogadási feltételek

- cache nem ad inkompatibilis eredményt;
- performance baseline dokumentált;
- nincs kontrollálatlan memórianövekedés;
- model nem parse-olódik fölöslegesen minden stage-ben.

## Javasolt commit

```text
perf(analysis): add reproducible cache and pipeline benchmarks
```

---

# Kör 29 — Evaluation harness és confidence calibration

## Cél

A metrikák valós pontosságának mérhető, CI-kompatibilis evaluation rendszere.

## Feladatok

1. Hozz létre evaluation manifestet.
2. Ground truth schema.
3. Metric riport:

- onset precision/recall/F1;
- timestamp MAE;
- chord frame/segment accuracy;
- strum direction accuracy;
- BPM error;
- beat alignment;
- pitch cents error;
- confidence calibration;
- slice breakdown.

4. Dataset licence és privacy dokumentáció.
5. Small CI fixture és nagy manuális eval külön.
6. Baseline és regression thresholds.
7. Model card/analyzer card frissítés.

## Tesztek

- manifest parser;
- missing annotation;
- deterministic report;
- threshold fail;
- slice aggregation;
- calibration metric;
- no private path leak.

## Elfogadási feltételek

- algoritmusváltozás számszerűen értékelhető;
- confidence calibration dokumentált;
- critical regression CI-ben blokkolható;
- nagy eval manuálisan futtatható.

## Javasolt commit

```text
test(analysis): add real-audio evaluation and calibration harness
```

---

# Kör 30 — Shadow rollout, migráció és Epic lezárás

## Cél

A V2 biztonságos bevezetése és a V1 kontrollált kivezetésének előkészítése.

## Feladatok

1. Feature flag:

- V1 default;
- V2 shadow Lab;
- V2 opt-in;
- V2 default.

2. Shadow diff report:

- event count;
- chord segments;
- BPM;
- duration;
- runtime;
- failures.

3. Teljes legacy Library migráció teszt.
4. Rollback teszt.
5. Frissítsd:

- README;
- HANDOFF;
- SDD completion report;
- ADR-ek;
- architecture diagram;
- privacy documentation;
- model/analyzer card.

6. Készíts `epic-06-completion-report.md` fájlt.
7. A V1 eltávolítása csak külön döntés és stabil V2 release után történhet.

## Kötelező ellenőrzések

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
flutter test test/property
dart run tool/check_architecture.dart
```

Ha backend vagy Tutor schema változott:

```bash
cd backend
python -m pytest -q
python -m ruff check app tests
python -m ruff format --check app tests
```

## Valódi eszköz ellenőrzés

- record;
- cancel;
- background;
- import;
- 30 s klip;
- hosszabb klip;
- overview;
- timeline zoom;
- save/reopen;
- compare;
- Practice action;
- Tutor action;
- offline mode;
- audio deletion.

## Elfogadási feltételek

- V2 feature flaggel biztonságosan kapcsolható;
- V1 rollback működik;
- legacy session megmarad;
- CI zöld;
- performance regresszió dokumentált határon belül;
- nyers audio nem kerül ki consent nélkül;
- Epic completion report elkészült.

## Javasolt commit

```text
docs(analysis): close Audio Analysis 2.0 epic
```

---

# 33. Epic 6 végső Definition of Done

## Domain és architektúra

- [ ] Létezik verziózott `AnalysisDocument`.
- [ ] A domain Flutter-független.
- [ ] Minden metric stabil ID-val és versionnel rendelkezik.
- [ ] Minden evidence időalapja reprodukálható.
- [ ] A pipeline stage-ek modulárisak és tesztelhetők.
- [ ] A V1 adapter rendelkezésre áll a migráció alatt.
- [ ] Nincs új tiltott cross-feature belső import.

## Input és lifecycle

- [ ] Mikrofonos és importált input közös boundary mögött van.
- [ ] WAV parser bounds-safe.
- [ ] Túl nagy vagy hibás input kontrollált failure.
- [ ] Elemzés megszakítható.
- [ ] Cancel után nincs késői result.
- [ ] Mikrofon és isolate minden útvonalon felszabadul.
- [ ] App background nem hagy hot micet.

## Jelminőség

- [ ] Clipping mérhető.
- [ ] Túl halk jel mérhető.
- [ ] Silence ratio mérhető.
- [ ] Quality warning nem minősíti a felhasználót.
- [ ] Quality gate hat a capabilitykre.
- [ ] Nyers amplitúdó dynamics célra megmarad.

## Timeline és harmónia

- [ ] Onset és strum külön event.
- [ ] Eventek sample indexszel vagy pontos timebase-szel rendelkeznek.
- [ ] Chord segmentek source és confidence adatot kapnak.
- [ ] DSP/ML fallback provenance-ben látható.
- [ ] Beat grid és tempo curve rendelkezésre áll, ha mérhető.
- [ ] Half/double-time bizonytalanság kezelt.

## Metrikák

- [ ] Timing metric csak megfelelő reference vagy külön free-play ID mellett jelenik meg.
- [ ] Rush/drag előjel helyes.
- [ ] Rhythm consistency dokumentált.
- [ ] Dynamics sessionön belül mérhető.
- [ ] Accent metric targetfüggő.
- [ ] Pitch metric capability gate mögött van.
- [ ] Technique proxyk kísérletiek, amíg nincs eval.
- [ ] Nincs hamis ujj- vagy kéztartás diagnózis.

## Bizonytalanság

- [ ] Minden metric statuszt és confidence-et kap.
- [ ] Unavailable reason megjeleníthető.
- [ ] Nyers model score nem probability kalibráció nélkül.
- [ ] Low-confidence eredmény nem jelenik meg biztos tényként.
- [ ] A rendszer képes abstainelni.

## Insight és integráció

- [ ] Insight determinisztikus szabályból készül.
- [ ] Minden insight evidence-re hivatkozik.
- [ ] Practice hotspotból feladat készíthető.
- [ ] Song target adapter működik.
- [ ] Tutor csak redaktált facts snapshotot kap.
- [ ] Practice és Streak credit pontosan egyszer történik.

## Persistence

- [ ] Library V2 nem egyetlen nagy SharedPreferences JSON tömb.
- [ ] Atomic save működik.
- [ ] Egy sérült session izolálható.
- [ ] Legacy migráció idempotens.
- [ ] Custom title megmarad.
- [ ] Nyers audio retention alapból kikapcsolt.
- [ ] Session és audio törlés teljes.

## UI

- [ ] Overview capability-aware.
- [ ] Unavailable metric magyarázott.
- [ ] Timeline zoomolható és hosszú sessionön is használható.
- [ ] Hotspot navigáció működik.
- [ ] Grafikonoknak van szöveges accessibility alternatívája.
- [ ] Magyar és angol localization parity zöld.
- [ ] Kis képernyő és nagy szöveg támogatott.

## Comparison és trend

- [ ] Csak kompatibilis metrika hasonlítható.
- [ ] Meaningful delta threshold dokumentált.
- [ ] Inconclusive állapot létezik.
- [ ] Nem minden nagyobb érték minősül javulásnak.
- [ ] Trend minimum sample counttal készül.

## Minőség és rollout

- [ ] V1 baseline dokumentált.
- [ ] DSP fixture regresszió zöld.
- [ ] Real-audio eval elérhető.
- [ ] Confidence calibration riport készül.
- [ ] Performance baseline és budget dokumentált.
- [ ] Cache verzióhelyes.
- [ ] V2 shadow/opt-in rollout lehetséges.
- [ ] V1 rollback működik.
- [ ] Privacy dokumentáció frissült.

---

# 34. Az Epic eredménye

Az Epic lezárása után a StrumSight nem csupán felismeri, hogy milyen akkordok és pengetések hallhatók egy klipben.

A rendszer:

- pontos, verziózott evidence timeline-t készít;
- értékeli a felvétel minőségét;
- elválasztja a biztos és bizonytalan következtetéseket;
- target esetén mérhető timing- és ritmusvisszajelzést ad;
- elemzi a pengetési dinamika egyenletességét;
- támogatott gyakorlatnál monofonikus pitch metrikát készít;
- konkrét problémás szakaszokat jelöl;
- determinisztikus gyakorlási javaslatot ad;
- összehasonlíthatóvá teszi a későbbi sessionöket;
- adatvédelmi szempontból biztonságosan kapcsolódik a Practice Enginehez, Song Trainerhez és AI Tutorhoz;
- a nyers audio feltöltése nélkül, offline is teljes értékűen működik.

Az Epic után a következő magas szintű fejezet közvetlenül felhasználhatja az elemzés stabil, auditálható kimenetét:

```text
Chapter 8 — Epic 7: AI Practice Generator
```
