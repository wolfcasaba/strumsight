# ADR 0254 — A futtatás bemenete önálló típus, és a PCM soha nem lesz dokumentum

**Státusz:** elfogadva (2026-08-15). A GOV-30c ötödik, záró lépcsőjének
architekturális döntései.
Épít: [ADR 0250](0250-v2-analysis-work-state-and-ingest-stage-composition.md),
[ADR 0251](0251-analysis-target-seeding-and-evaluation-stage-composition.md),
[ADR 0252](0252-progress-phase-decoupled-from-stage-granularity.md),
[ADR 0253](0253-document-assembly-and-insight-stage-ordering.md),
[ADR 0240](0240-analysis-runner-and-pipeline-boundary.md) (runner-határ).

## Kontextus — a lánc kész, de az audiónak nincs útja hozzá

A GOV-30c négy lépcsője alatt felépült a teljes, 20 stage-es V2 lánc, és a
végén `AnalysisDocument` születik. Az ADR 0253 §4 nevesített follow-upként
ide halasztotta az utolsó akadályt, azzal a kikötéssel, hogy **újra kell
mérni**. Újramérve (2026-08-15):

```dart
// application/analysis_isolate_runner.dart:33-35
abstract interface class AnalysisRunner {
  AnalysisRunHandle start(AnalysisDocument input);
}
```

```dart
// domain/analysis_input_summary.dart:3
/// Privacy-safe input metadata retained with an analysis document, never PCM.
```

A rés fennáll: a runner bemenete dokumentum, a dokumentum sosem hordoz PCM-et,
a lánc viszont `ValidatedPcmAnalysisInput`-ból indul.

**A jó hír, szintén mérve:** a hívói felület kicsi (`AnalyzeAudioUseCase` és
`ShadowAnalysisRunner`), és a shadow runner **már megkapja** a
`samples`/`sampleRate` párost a V1-hez (`shadow_analysis_runner.dart:45`).
A hiányzó lépés nem adatgyűjtés, hanem továbbadás.

## Döntés

### 1. A futtatás bemenete önálló típus

```dart
final class AnalysisRunRequest {
  final AnalysisDocument seed;            // identitás, mód, provenance-mag
  final ValidatedPcmAnalysisInput audio;  // CSAK memóriában
  final AnalysisTarget? target;           // opcionális referencia (ADR 0251 §1)
}
```

`AnalysisRunner.start(AnalysisRunRequest)`.

*Miért nem a dokumentum bővítése:* a dokumentum a **publikált, perzisztált,
exportálható** artefaktum. Ami bekerül, az kimegy a felhasználó eszközéről is.
A futtatás bemenete és a futtatás eredménye két különböző dolog; eddig azért
látszottak egynek, mert a lánc nem létezett.

### 2. A PCM soha nem lesz dokumentum, és nem perzisztálódik

Az `AnalysisInputSummary` „never PCM" szabálya változatlanul él. A minta a
kérésben utazik a runnerig, onnan az izolátumba, és a futás végén eldobódik.
A dokumentum a fingerprintet viszi, nem a mintát.

*Abszolút tiltás:* a minta beletétele a dokumentumba — akár átmenetileg, akár
base64-ként —, valamint a naplózása vagy ideiglenes fájlba írása. A mérce
ezért a **kódolt JSON-t** vizsgálja, nem a típusokat: egy `Uint8List` mező
típusszinten ártalmatlannak látszik, a kimeneten viszont ott a hang.

### 3. A runner a meglévő láncépítőket használja

A `V2AnalysisRunner` a `buildFullAnalysisStages()`, `analysisStagePhases` és
`classifyAnalysisStageFailure` hármast hívja. Saját, „csak ehhez a
futtatáshoz" összeállított stage-lista tilos — az két igazságforrást csinálna
a láncból, és a következő stage-bővítés némán kihagyná az egyiket.

### 4. Futtatható ≠ bekapcsolt

Ez a kör a providert valódi runnerre cseréli, de a felhasználói út továbbra is
a kilenc OFF flag mögött marad. **A rollout külön, emberi döntés** — a
`lib/core/flags/**` ezért tilos zóna a körben.

*Miért fontos kimondani:* öt lépcső után erős a késztetés „megmutatni, hogy
működik". A V2 lánc első éles futása azonban terméki döntés, nem technikai
mérföldkő — és a valódi eszközös elfogadás (a completion report 1. tétele) is
csak ezután jön.

## Következmények

- **A V2 elemzés futtathatóvá válik**: PCM be → `AnalysisDocument` ki, a
  teljes 20 stage-es láncon, izolátumban, megszakíthatóan.
- A completion report 1. (valódi eszközös elfogadás) és 5. (rollout) tétele
  **feloldódik** — eddig a lánc hiánya miatt fizikailag blokkolt volt.
- A `ShadowAnalysisRunner` végre valódi V2 eredményt kap, tehát a shadow
  összehasonlítás (E06-R30) is értelmet nyer.
- A GOV-30c ezzel **öt lépcsőben** zárul (0250 §4 kettőt, 0251 §4 hármat,
  0253 §4 négyet becsült — a növekmény mindannyiszor MÉRT akadályból jött,
  nem scope-csúszásból).

## Mérce

Az `E99-R13` §6.1 mérce-mátrixa, benne a futtathatóság három kötelező
cellájával (referencia nélkül / üres referenciával / referenciával) és a
valódi-sértés próbával: a mintát a dokumentum egy mezőjébe téve az **A4**
cellának pirosnak kell lennie.

Az A4 szándékosan a **kódolt JSON-t** vizsgálja: a PCM-szivárgás típusszinten
nem látszik.

Lásd: [`docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md`](../rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md).
