# ADR 0240 — Analysis runner: run-ID authority and pipeline-agnostic isolate boundary

- **Státusz:** Elfogadva (E06-R22 pre-flight, 2026-08-12)
- **Kör:** E06-R22 — Analysis runner, progress UI és cancellation
- **Implementer motor:** Terra (`gpt-5.6-terra`), `.pipeline/engine-override=terra` szerint.
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 22; §6.5, §21, §22.1–22.4
- **Kontext-ADR-ek:** [0215](0215-analysis-document-versioning.md) (dokumentum-
  verziózás), [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md) (V2
  flag-mögötti rollout), [0224](0224-signal-quality-stage-measurement-boundary.md)
  (`SignalQualityStage`), [0225](0225-analysis-preprocessing-and-resampling-policy.md)
  (`PreprocessingStage`), [0226](0226-clip-analyzer-stage-boundary-and-fallback-provenance.md)
  (`ClipAnalyzerStage`), [0239](0239-analysis-document-storage.md)
  (`AnalysisRepository`/`AnalysisSaveRequest`).

## Kontextus

**Mért 2026-08-12-én, `main` @ `e0c6754e`.** A kör briefjét 2026-08-07-én,
`main@a6e6f3d`-n (Epic 6 kezdete ELŐTT) írták — a brief §2 "Az R04 adja a
pipeline-t + cancellation tokent" mondata tehát előrejelzés volt, nem mérés.
A pre-flight ezt újramérte:

1. `lib/features/audio_analysis/engine/analysis_pipeline.dart` — az
   `AnalysisPipeline<T>` (E06-R04) egy ÁLTALÁNOS, `List<AnalysisStage<T, T>>`
   szerződés: minden stage bemenete ÉS kimenete UGYANAZ a `T`. A pipeline
   maga generálja a run ID-t (`'analysis-run-${++_nextRunNumber}'`,
   példány-lokális számláló), és egy `_activeRunId` mezővel szűri a késői
   progress-eseményeket a STREAM-en — de ez a szűrés ugyanazon a
   `AnalysisPipeline`-példányon belül él, nem szinkronizál isolate-határon
   át, és nem akadályozza meg, hogy egy szuperszedált futás `result` Future-je
   normálisan felbontsa magát annak, aki közvetlenül rá vár.
2. `grep -rln "AnalysisPipeline(" lib/` **nulla** találatot ad — ma egyetlen
   konkrét, összeszerelt V2 DSP-pipeline sem létezik.
3. `grep -rn "AnalysisStage<" lib/features/audio_analysis --include="*.dart"`
   három konkrét implementációt ad, EGYMÁSSAL ÖSSZE NEM FŰZHETŐ I/O-val:
   `SignalQualityStage: AnalysisStage<ValidatedPcmAnalysisInput,
   SignalQualityStageResult>` (E06-R07/ADR 0224), `PreprocessingStage:
   AnalysisStage<ValidatedPcmAnalysisInput, PreprocessedAudio>` (E06-R08/ADR
   0225), `ClipAnalyzerStage: AnalysisStage<LegacyClipAnalyzerInput,
   LegacyEvidence>` (E06-R09/ADR 0226). Egyik párnak sincs `stage[i].O ==
   stage[i+1].I` illeszkedése, és egyiket sem szánták önmagában a lánc
   végállomásának (ADR 0226 a `ClipAnalyzerStage`-et kifejezetten "evidence"-
   forrásként, nem kész `AnalysisDocument`-ként definiálja). Egy valódi,
   preprocessing→quality→harmony→rhythm→pitch→metrics→insights láncot
   összefűző, közös munka-kontextus típus **nincs megtervezve** — ennek
   megtervezése saját, jövőbeli kör (nincs a `pipeline-queue.tsv`-ben
   megnevezve).
4. A brief §6 acceptance criteria mind a tíz állapot-mátrix cellája, a
   kredit-mátrix, a throttle-hármas, a cancel-takarítás cella és az
   isolate-smoke cella kifejezetten **fake**/**minimális** pipeline-t ír elő
   (a `§6.1` mérce-mátrix, valamint az OD-01 alapértelmezése szó szerint:
   "a TESZT az `AnalysisIsolateRunner` interfészét fake-eli... Legalább EGY
   teszt viszont valódi isolate-ot indít egy MINIMÁLIS pipeline-nal"). Egyik
   acceptance-cella sem igényel valódi, összeszerelt DSP-t.
5. R21 (`domain/analysis_repository.dart`, ADR 0239) `AnalysisRepository.save
   (AnalysisSaveRequest)` egy TELJES `AnalysisDocument`-et vár — ez az
   egyetlen konkrét típus, amit ennek a körnek mindenképp elő kell tudnia
   állítani (fake stage-ekkel tesztelve) a `SaveAnalysisUseCase` számára.

## Döntés

1. **`AnalysisState` — pontosan a SDD §21.1 tizenegy állapota** (`idle`,
   `acquiringInput`, `recording`, `validating`, `analyzing`, `completed`,
   `degradedCompleted`, `cancelled`, `permissionDenied`, `inputError`,
   `analysisError`), sealed hierarchia. Minden futáshoz köthető állapot
   (`analyzing`/`completed`/`degradedCompleted`/`cancelled`/`analysisError`)
   hordozza a saját `runId`-ját.
2. **A run ID EGYETLEN igazságforrása a controller saját `_activeRunId`
   mezője — SOHA a pipeline-példány belső számlálója.** A controller a
   futtatás indításakor kapott run ID-t (amit az `AnalysisIsolateRunner`
   szinkron visszaad) elfogadja OPAK azonosítóként, de a késői
   progress/result-elutasítás kizárólag a SAJÁT `_activeRunId`-jával való
   összevetésen alapul — nem a pipeline `_activeRunId`/`_droppedLateEvents`
   diagnosztikáján, ami isolate-onként újraindul (ld. Elutasított
   alternatívák). Eltérés → `rejectedLateResults++`, state érintetlen.
3. **`AnalysisIsolateRunner` egy-lövetű: minden `run()` egy FRISS isolate-ot
   spawnol**, progress-stream + result handle-t ad vissza; `cancel()` megöli
   az isolate-ot és lezárja a portokat/streameket. Nem hosszú-élettartamú,
   újrahasznosított isolate (ld. Elutasított alternatívák) — ez teszi jól
   definiálttá a "fake isolate `disposed == true`" és a "cancel utáni új
   futás" acceptance-cellákat.
4. **Ez a kör pipeline-agnosztikus — NEM szerel össze valódi, több-stage DSP
   pipeline-t.** `AnalysisIsolateRunner`/`AnalyzeAudioUseCase`/
   `AnalysisController` a meglévő generikus `AnalysisPipeline<T>`/
   `AnalysisStage<T, T>` szerződésre épül, **`T = AnalysisDocument`-re
   rögzítve** (ez az egyetlen típus, amire a controllernek ÉS a
   `SaveAnalysisUseCase`-nek is szüksége van) — de a stage-lista mindig
   INJEKTÁLT paraméter. A tesztek fake `AnalysisStage<AnalysisDocument,
   AnalysisDocument>` implementációkat adnak (kanonikus fixture-
   dokumentumokat visszaadó/módosító lépéseket — pl. a meglévő
   `test/fixtures/analysis/**` mintákra építve). A production wiring
   (`analysis_providers.dart`) a valódi stage-listát **nyíltan dokumentált,
   nyitva hagyott résként** kezeli — egy `StateError`-t dobó provider,
   pontosan az `analysisRepositoryProvider`/`legacyLibraryMigratorProvider`
   (ADR 0239) már bevált mintája szerint —, amíg egy JÖVŐBELI kör meg nem
   tervezi a közös munka-kontextust és össze nem szereli a valódi láncot. Ez
   nem hiba, és a brief §10/HANDOFF kötelezően megnevezi nyitott
   follow-up-ként.
5. **A progress-throttle esemény-számláló, nem `Timer`.**
   `minEventsBetweenEmits = 5`, a küszöb INKLUZÍV (az 5. minősítő esemény
   már kibocsát, a 4. még nem) — a brief §6 már ezt írja elő, ez a döntés
   csak megerősíti a mechanizmust (számláló nullázása minden kibocsátás
   után), hogy a teszt determinisztikusan vezérelhesse a 4/5/6 hármast.
6. **A kredit-feltétel a V1-gyel BITRE azonos, futásonként egyszer, KIZÁRÓLAG
   `complete`-en.** `document.chords.isNotEmpty || document.strums.isNotEmpty`
   — ugyanaz a predikátum-alak, mint `lib/features/analyze/providers/
   analyze_providers.dart:225`, run ID-nkénti reteszeléssel (egy már
   jóváírt futás késői/duplikált result-eventje nem ír jóvá másodszor).
7. **A cancel sosem hiba és sosem hagy szemetet.** `CancelAnalysisUseCase` az
   AKTUÁLIS futást `cancelled`-re zárja, felszabadítja ANNAK a futásnak az
   isolate/port/temp-fájl erőforrásait, és nem nyúl egy KORÁBBAN, egy előző
   futásból már elmentett dokumentumhoz.

## Következmények

- A valódi, több-stage DSP pipeline összeszerelése (közös munka-kontextus
  típus + konkrét stage-lánc) egy önálló, MÉG NEM ÜTEMEZETT jövőbeli kör
  feladata marad — a HANDOFF §3-ban nyíltan megnevezendő nyitott rés, nem
  hallgatólagos hiány (az epic eddigi mintája szerint: R02–R21 mindegyike
  "0 fogyasztó" állapotban zárt legalább egy réteget).
- Az `AnalyzeAudioUseCase`/`AnalysisController` teljes egészében tesztelt és
  gate-zöld valódi DSP nélkül; a V2 Analyze képernyő ma sem tudna valódi
  eredményt produkálni — de ennek nincs production/user-facing hatása, mert
  az `audioAnalysisV2Enabled` flag `false` marad (ADR 0220) függetlenül ettől
  a körtől.
- A `T = AnalysisDocument` rögzítés azt jelenti, hogy a jövőbeli valódi-
  pipeline kör csak egy `List<AnalysisStage<AnalysisDocument,
  AnalysisDocument>>`-et és egy provider-felülírást ad hozzá — a runner/
  controller/use-case réteget nem kell újraírni.

## Elutasított alternatívák

- **Minimális, valódi single-stage production pipeline összeszerelése MÁR
  ebben a körben** (pl. `runClipAnalysis`/`ClipAnalyzerStage` +
  `LegacyAnalyzeAdapter` egyetlen adapter-stage mögé csomagolva). Elutasítva:
  a `ClipAnalyzerStage` `I ≠ O`, ezért önmagában nem elégíti ki az
  `AnalysisPipeline<T>` egyenletes-`T` megkötését; egy új wrapper-típus
  `engine/` vagy `domain/` alá kellene, mindkettő KÍVÜL esik ennek a körnek
  az `allowed_paths`-án — és csendben egy önálló, review-t érdemlő DSP-
  döntést (melyik stage-kimenet a mérvadó, hogyan térképeződnek a
  warning/capability mezők) kötne a runner-kör mellékhatásaként.
- **A pipeline saját belső run ID-ját (`analysis-run-N`) használni a
  controller késői-eredmény szűrőjeként**, a controller saját számlálója
  helyett. Elutasítva: ez a számláló PÉLDÁNYONKÉNT nullázódik, és az
  egy-lövetű, futásonkénti isolate-spawn azt jelenti, hogy KÉT egymást követő
  futás a controller szemszögéből egyaránt `analysis-run-1` lenne — ez
  teljesen érvénytelenítené a késői-eredmény ellenőrzést.
- **Hosszú-élettartamú, újrahasznosított isolate** (egyszer spawnolva, minden
  futás ugyanazon keresztül megy). Elutasítva: a SDD §22.1 "dedikált runner
  abstrakciót" javasol, újrahasznosítást nem ír elő; egy megosztott isolate-
  nak nincs tiszta, futásonkénti "kill" határa — a cancel-takarítás
  (`disposed == true`) és a cancel-utáni-új-futás cellák egyaránt kemény
  isolate-killt igényelnek, amit egy megosztott isolate csak a controller
  run-ID szűrőjét megkettőző, isolate-belső könyveléssel tudna adni.
- **Generikus `AnalysisIsolateRunner<T>`/`AnalyzeAudioUseCase<T>` publikus
  API, a `T` megválasztását egy jövőbeli körre hagyva.** Elutasítva: a
  `SaveAnalysisUseCase`-nek MÁR MA konkrét `AnalysisDocument`-et kell
  tudnia adni az R21 `AnalysisRepository.save`-nek — a `T` nyitva hagyása a
  mai kétértelműséget csak három hívási helyre tolná szét, ahelyett hogy itt,
  egyszer eldöntené.

## A visszavonás feltétele

Felülvizsgálandó, ha egy jövőbeli kör ténylegesen megtervezi és összeszereli
az első valódi, több-stage DSP pipeline-t, és méréssel azt találja, hogy a
`T = AnalysisDocument` választás (pl. a stage-ek közötti részleges/nullable
mezők miatt) nem életképes munka-kontextus — akkor az a kör egy külön
working-context típust vezethet be a pipeline `T`-jeként, ADR-frissítéssel,
nem néma cserével.
