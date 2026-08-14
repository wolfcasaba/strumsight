# ADR 0251 — A referencia a seeden érkezik, és a hiánya degradál, nem bukik

**Státusz:** elfogadva (2026-08-14). A GOV-30c második lépcsőjének
architekturális döntései.
Épít: [ADR 0250](0250-v2-analysis-work-state-and-ingest-stage-composition.md)
(munkaállapot + ingest-kompozíció), az Epic 6 engine-döntéseire
(ADR 0200–0249), és az [ADR 0087](0087-autonomous-round-pipeline.md)
kör-pipeline szerződésére.

## Kontextus — az értékelő fél kötelező bemenete hiányzik a láncból

A GOV-30c-1 (`E99-R09`) megépítette az ingest hét stage-ét, és a munkaállapot
ma ezt hordozza:

```
input · legacyEvidence? · preprocessedAudio? · signalQuality?
pitchFrames[] · pitchSegments[] · chordSegments[]
beatGrid? · tempoCurve? · events[] · suppressedEvents[]
warnings[] · unavailableCapabilities{}
```

Az értékelő fél viszont **referenciát** igényel — azt, hogy mit kellett volna
játszani:

```dart
// engine/alignment/event_aligner.dart:22-25
AlignmentResult align({
  required List<AnalysisEvent> observed,
  required List<ExpectedEvent> expected,
  required Duration beatDuration, …
```

és a timing-metrikák ezen keresztül függenek tőle
(`metrics/timing_metrics.dart:26`). **A munkaállapotban nincs referencia-mező,
és a `ValidatedPcmAnalysisInput` sem hordoz ilyet.**

A referencia-típus és a termelője viszont **létezik**: a
`domain/target/analysis_target.dart` `AnalysisTarget`-je (expectedEvents,
expectedChords, expectedNotes, sections), amit az E06-R26-ban merge-elt
`practice_analysis_adapter.dart` és `song_analysis_adapter.dart` már elő is
állít. Csak nem jut el a láncig.

**A rendszer előre számolt a hiányával:** a `CapabilityResolver` argumentumai
között ott a `hasReferenceTarget` (`confidence/capability_resolver.dart:16`),
és a négy `AnalysisMode` közül kettőnél (`freePlay`, `importedRecording`)
eleve nincs mihez mérni.

## Döntés

### 1. A referencia a seeden érkezik, nem stage-ben termelődik

`AnalysisWorkState.seed(input: …, target: AnalysisTarget?)`. A `target`
nullable, és a lánc semelyik stage-e nem állítja elő — a hívó adja át.

*Miért nem stage:* a referencia nem az audióból származik, hanem a
gyakorlat/dal kontextusából. Egy „target-építő stage" az alkalmazásréteget
húzná be a DSP-láncba, és megfordítaná az ADR 0250 §2 vékony-adapter elvét.

### 2. A referencia hiánya DEGRADÁL, nem bukik — és az üres lista nem referencia

Ha `target == null` **vagy** `expectedEvents` üres:

- az illesztő stage nem hibázik, hanem `alignment = null`-t hagy;
- `hasReferenceTarget: false` megy a `CapabilityResolver`-nek;
- az illesztés-függő capability-k az `unavailableCapabilities`-be kerülnek;
- a referencia-független metrikák (rhythm, pitch, dynamics, accent,
  subdivision, transition, technique) **ugyanúgy kiszámolódnak**.

*A kritikus tiltás:* **tilos** üres `expected` listával meghívni az
`EventAligner`-t és a kapott eredményt valódi illesztésként publikálni. Az nem
hiányzó adat, hanem HAMIS adat — a felhasználó 0%-os pontosságot látna azért,
mert nem volt mihez mérni. Ez ugyanaz a hibaosztály, mint a projekt máshol már
megtanult csendes `try/catch` no-op: a hiányzó bemenet sikeres mérésnek
álcázva.

### 3. A `hasReferenceTarget` MÉRT, nem az `AnalysisMode`-ból következtetett

Egy `practiceTarget` módú futás is kaphat üres referenciát (hiányos
gyakorlat-terv). Olyankor a mérés az igazság, nem a mód. A `hasReferenceTarget`
ezért a munkaállapot tényleges `target` mezőjéből származik.

### 4. A GOV-30c három lépcsőben zárul, nem kettőben

Az ADR 0250 §4 kétlépcsős vágást írt elő. A GOV-30c-1 lezárása után mérve a
maradék **hét terület** (referencia-beemelés, illesztés, kilenc metrika-modul,
capability/confidence, insights, hotspot-rangsor, dokumentum-összeállítás,
provider-bekötés) egyetlen körbe és egyetlen review-ba túl sok. Ezért:

- **GOV-30c-2 (`E99-R10`):** referencia + illesztés + metrikák +
  capability/confidence.
- **GOV-30c-3:** insights/hotspots + `AnalysisDocument` összeállítás + **csak
  ott** az `analysisV2RunnerProvider` felülírása.

A vágás helye mért: a dokumentum-összeállító **ma nem létezik** az engine-ben
(`grep -rln "AnalysisDocument(" lib/features/audio_analysis/` → csak a
domain-típus, a codec és a legacy adapter), tehát a GOV-30c-3 önálló,
érdemi felületet épít, nem maradék-takarítás.

Az ADR 0250 §4 minden más döntése változatlan; ez az ADR **kizárólag a
lépcsők számát** írja felül.

### 5. A kompozíció bizonyítása szekvenciális teszt-harnessel, nem `AnalysisPipeline`-példánnyal (2026-08-14 revízió, E99-R10 első Terra-dispatch STOP)

Mérve: `engine/analysis_pipeline.dart:68-74` — az `AnalysisPipeline<T>`
konstruktora `ArgumentError`-t dob, ha `stages.length >
AnalysisProgressPhase.values.length` (jelenleg **9**,
`domain/analysis_progress.dart:4-14`). A GOV-30c-2 tizenegy önálló stage-et
(1 illesztés + 9 metrika + 1 capability/confidence) ír elő — ennyi stage-re
az `AnalysisPipeline<AnalysisWorkState>` konstruktora azonnal elszáll.

Ez a decision NEM oldja ezt fel az `AnalysisPipeline`/`AnalysisProgressPhase`
módosításával — mindkettő ezen kör (E99-R10) engedélyezett-fájllistáján
kívül esik, és [ADR 0240](0240-analysis-runner-and-pipeline-boundary.md)
már mérve rögzítette, hogy ma egyetlen konkrét, összeszerelt V2-lánc sem
létezik production kódban (`grep -rln "AnalysisPipeline(" lib/` → nulla
találat) — az ingest-lánc (E99-R09) is csak a `buildIngestStages()`
LISTÁJÁIG jutott, a tényleges `AnalysisPipeline`-példányosítás kizárólag a
TESZT bizonyítási eszköze, sosem production wiring.

**Döntés:** a GOV-30c-2 production kódja (`evaluation_stages.dart`)
tizenegy granular `AnalysisStage<AnalysisWorkState, AnalysisWorkState>`
osztályt épít, ugyanabban a `buildEvaluationStages()` +
`classifyEvaluationStageFailure` alakban, mint az ingest-lánc. A
composition-teszt viszont **közvetlen, szekvenciális `stage.run(...)`
hívásokkal** bizonyítja a láncot (fatálisnál megáll, degradálhatónál
gyűjt), NEM `AnalysisPipeline<AnalysisWorkState>` példányosítással — az
`AnalysisPipeline` motor generikus végrehajtási logikáját (progress-
monotonitás, fatális/degradálható elágazás) már önállóan fedi
`analysis_pipeline_test.dart` (E06-R04), ezért ennek újra-bizonyítása nélkül
sem gyengül a mérce.

**Halasztott, névvel ellátott follow-up:** a teljes, 18 stage-es (7 ingest +
11 evaluation) lánc egyetlen élő `AnalysisPipeline`-példányba drótozása — és
ezzel a 9-es progress-fázis-cap valódi feloldása, pl. a progress-fázis-modell
és a DSP-stage-granularitás szétválasztásával — a **GOV-30c-3** pre-flightjának
mért feladata. A GOV-30c-3 brief-je ezt kötelezően grep-elje ki újra a saját
indulásakor (mennyi stage lesz ekkor ténylegesen, változott-e a cap), ne
ezt az ADR-t idézze bemondásra.

## Következmények

- A `freePlay` és `importedRecording` módú elemzés **teljes értékű marad** —
  csak az illesztés-függő metrikák hiányoznak belőle, és ezt a dokumentum
  `capabilities` mezője ki is mondja.
- A referencia bekötése (melyik hívó honnan veszi az `AnalysisTarget`-et) a
  GOV-30c-3 kérdése; ez a kör csak a **fogadó oldalt** építi meg.
- **Nincs viselkedésváltozás a felhasználó felé.** A kör nulla flaget mozdít,
  és az `analysisV2RunnerProvider` a végén is `StateError`-t dob.

## Mérce

Az `E99-R10` §6.1 mérce-mátrixa, benne a referencia három kötelező cellájával
(nincs referencia / `target` van de `expectedEvents` üres / van referencia) és
a valódi-sértés próbával: az üres-lista ellenőrzést kivéve az `EventAligner`
üres `expected`-del is meghívódna, és az **A6** cellának pirosnak kell lennie.

Az A6 szándékosan **hívás-számlálóval** mér, nem kimenet-ellenőrzéssel: a
hamis illesztés eredménye önmagában hihetőnek látszik.

Lásd: [`docs/rounds/e99-r10-gov-30c-2-evaluation-stage-composition.md`](../rounds/e99-r10-gov-30c-2-evaluation-stage-composition.md).
