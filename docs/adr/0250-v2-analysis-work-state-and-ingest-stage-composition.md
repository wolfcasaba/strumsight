# ADR 0250 — A V2 elemzési lánc munkaállapota és az ingest-stage-ek kompozíciója

**Státusz:** elfogadva (2026-08-14, user-döntés az Epic 6 lezárása után:
a completion report hét nyitott iránya közül a **GOV-30c** — a valódi V2
DSP-lánc összeszerelése — az első).
Épít: [ADR 0087](0087-autonomous-round-pipeline.md) (kör-pipeline),
az Epic 6 engine-döntéseire (ADR 0200–0249), és a
[`docs/sdd/epic-06-completion-report.md`](../sdd/epic-06-completion-report.md)
„Nyitott tételek" táblájára.

## Kontextus — 30 kör infrastruktúra egy nem létező lánc körül

Az Epic 6 (Audio Analysis 2.0) mind a 30 köre lezárult és merge-elve van.
Elkészült a V2 dokumentum-modell, a repository és migráció, a runner
progress/cancellation kezeléssel, az overview és metric card UI, a rétegzett
timeline, a session-összehasonlítás, a Practice/Song/Tutor integráció, az
export/share adatvédelmi kontrollokkal, a cache-infrastruktúra, az
evaluation harness és a shadow rollout. **41 engine-fájl 12 modulban.**

Egyetlen dolog hiányzik — az, ami mindezt futtatná:

```dart
// lib/features/audio_analysis/application/analysis_providers.dart:213-218
final analysisV2RunnerProvider = Provider<AnalysisRunner>((_) {
  throw StateError(
    'analysisV2RunnerProvider has no concrete V2 DSP stage list yet. '
    'A future pipeline-composition round must override it.',
  );
});
```

A completion report hét nyitott irányából ezért **nem egyenrangú** egyik sem:
a valódi eszközös elfogadás és az opt-in rollout **fizikailag lehetetlen**,
amíg a lánc nincs összeszerelve. A user 2026-08-07-i elve — *„előbb a
shipping kör, aztán a valós mérés, és csak azután az új epic"* — ugyanide
mutat.

**A mért akadály, amiért ez nem triviális:** az `AnalysisPipeline<T>`
(`engine/analysis_pipeline.dart:56`) **azonos állapotú** stage-eket komponál
(`List<AnalysisStage<T, T>>`), a három meglévő stage típusa viszont mind
eltér:

| stage | I → O |
|---|---|
| `PreprocessingStage` | `ValidatedPcmAnalysisInput → PreprocessedAudio` |
| `SignalQualityStage` | `ValidatedPcmAnalysisInput → SignalQualityStageResult` |
| `ClipAnalyzerStage` (legacy) | `LegacyClipAnalyzerInput → LegacyEvidence` |

Egyik sem tehető közvetlenül a lista elemévé. A pipeline saját kommentje
előre is jelezte a feloldást: *„Future real DSP stages can use their own
work-state type while keeping the SDD's generic stage contract."*

## Döntés

### 1. Egy munkaállapot-típus, nem stage-enkénti típusfüzér

Bevezetjük az `AnalysisWorkState` immutable típust, és minden stage
`AnalysisStage<AnalysisWorkState, AnalysisWorkState>` alakot ölt. A bővítés
`copyWith`-szerű, nem mutáció.

*Miért nem `dynamic`/`Object`:* a típus-azonosság a pipeline szerződése. Aki
`dynamic`-kal kerüli meg, az a fordítási idejű őrt kapcsolja ki, cserébe
semmit nem nyer — a lánc ugyanúgy egyetlen állapotot cipel.

### 2. Az adapterek vékonyak: hívnak, nem számolnak

A meglévő 41 engine-fájl végig-review-zott és tesztelt (E06-R05…R20). Az
adapter dolga kiolvasni a bemenetet, meghívni a MEGLÉVŐ modult, az eredményt
visszaírni — **nulla DSP-matematika** (AGENTS.md §9). Ha típus-illesztés
kell, az önálló, tesztelt konverziós függvény, nem rejtett számítás az
adapter törzsében.

A `PreprocessingStage` és a `SignalQualityStage` már `AnalysisStage`: az
adapterük példányosítja és meghívja őket, nem másolja a törzsüket.

### 3. A degradálási politika a kompozícióé, stage-id alapján

| stage | hiba esetén |
|---|---|
| preprocessing, signal quality, events | **fatális** |
| pitch, harmony, rhythm | **degradálható**, az elvesztett capability-kkel |

Az elvesztett capability-ket a `StageFailure.degradable(…,
unavailableCapabilities: {…})` halmazban kell megadni, nem csak logolni — a
dokumentum `capabilities` mezője ebből fog táplálkozni.

*Miért nem minden stage degradálható:* az fail-open lenne. Egy néma
preprocessing-hiba után a lánc üres, de sikeresnek látszó eredményt adna —
pontosan az a hibaosztály, amit a projekt máshol már megtanult (a
csendes `try/catch` no-op).

### 4. A lánc két lépcsőben épül, és ez a lépcső semmit nem kapcsol be

- **GOV-30c-1 (`E99-R09`, ez a kör):** munkaállapot + ingest-stage-ek a
  PCM-bemenettől a `timeline`-alapig.
- **GOV-30c-2 (a következő kör):** metrikák, confidence/capability-feloldás,
  insights/hotspots, dokumentum-összeállítás, és **csak ott** az
  `analysisV2RunnerProvider` felülírása.

A GOV-30c-1 végén a provider továbbra is `StateError`-t dob, és mind a
kilenc flag OFF marad. A lánc létezik, de nincs bekötve.

*Miért kétlépcsős:* egyetlen körben 12 modul becsomagolása + a dokumentum
összeállítása + a bekötés túl nagy felület egyetlen review-hoz. A vágás ott
van, ahol a `AnalysisDocument` mezői kettéválnak: a `timeline`/`signalQuality`
az ingest terméke, a `metrics`/`capabilities`/`insights`/`hotspots` az
értékelésé.

## Következmények

- Az `AnalysisWorkState` alakja **megköti a GOV-30c-2-t**. Ezért kötött a
  §1: egy típus, immutable, `copyWith`-bővítés — és csak az kerül bele, amit
  egy későbbi stage vagy a dokumentum ténylegesen olvas.
- A munkaállapotnak ebben a körben **nem kell isolate-sendable-nek** lennie
  (a futtatás JSON-on át megy, `AnalysisDocumentIsolateOperation`), de nem
  épülhet bele olyan típus (`Stream`, closure), ami később biztosan
  megakadályozná.
- **Nincs viselkedésváltozás a felhasználó felé.** A kör nulla flaget mozdít.
- Az elemzés futtathatóvá válása a GOV-30c-2 után **feloldja** a completion
  report 1. (valódi eszközös elfogadás) és 5. (rollout) tételét is — ezek ma
  a lánc hiánya miatt blokkoltak.

## Mérce

A döntések gépi mércéje az `E99-R09` kör §6.1 mérce-mátrixa, benne a
degradálás három kötelező cellájával (fatális alatt / a határon / fölötte) és
a valódi-sértés próbával: a preprocessing osztályozását ideiglenesen
`degradable`-re állítva a fatális cellának pirosnak kell lennie.

Lásd: [`docs/rounds/e99-r09-gov-30c-1-ingest-pipeline-composition.md`](../rounds/e99-r09-gov-30c-1-ingest-pipeline-composition.md).
