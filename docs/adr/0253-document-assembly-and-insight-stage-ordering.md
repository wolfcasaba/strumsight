# ADR 0253 — A dokumentum-összeállítás és az insight-futtatás sorrendje

**Státusz:** elfogadva (2026-08-15). A GOV-30c negyedik lépcsőjének
architekturális döntései.
Épít: [ADR 0250](0250-v2-analysis-work-state-and-ingest-stage-composition.md),
[ADR 0251](0251-analysis-target-seeding-and-evaluation-stage-composition.md),
[ADR 0252](0252-progress-phase-decoupled-from-stage-granularity.md).

## Kontextus

A GOV-30c-3 után a 18 stage-es lánc egyetlen élő `AnalysisPipeline`-ban áll
össze, és a munkaállapot minden nyersanyagot hordoz — de `AnalysisDocument`
még nem születik belőle. `grep -rln "AnalysisDocument(" lib/features/audio_analysis/`
→ csak a domain-típus, a codec és a legacy adapter: **az engine egyetlen
helyen sem állít össze dokumentumot.**

Az insight-szabályok pedig **kész dokumentumon** dolgoznak:

```dart
// domain/insights/insight_rule.dart:53-73
final class AnalysisInsightContext {
  AnalysisInsightContext({ required this.document, … });
  final AnalysisDocument document;
  …
}
```

A sorrend tehát nem ízlés kérdése, hanem a típusokból következik.

## Döntés

### 1. Két stage, nem egy

`DocumentAssemblyStage` (előzetes dokumentum, üres `insights`/`hotspots`) →
`InsightsStage` (`InsightRegistry.evaluate` → `InsightRanker.rank` →
`HotspotRanker.rank` → végleges dokumentum).

*A kritikus tiltás:* az insight-szabályokat **tilos** a munkaállapotból
összerakott ál-dokumentummal etetni. A szabályok azon a dokumentumon
fussanak, amelyik publikálásra kerül — különben a felhasználó olyan tanácsot
kap, ami nem az általa látott adatokból következik.

### 2. Az előzetes dokumentum minden más mezője végleges

Az összeállító stage kizárólag az `insights` és a `hotspots` mezőt hagyja
üresen. A `signalQuality`, `capabilities`, `timeline`, `metrics`, `warnings`,
`completion`, `provenance` már a végleges értékét kapja — egy dokumentumnak
egy igazságforrása van.

### 3. A hiányzó nyersanyag nem kitalált érték

Ha egy mező forrása hiányzik (degradált stage miatt), a dokumentum azt üresen
vagy `unavailable`-ként viszi tovább, és a `capabilities` mondja meg, miért.
Tilos default-tal, nullával vagy „jobb híján" számított értékkel pótolni.

*Miért ez a kör legfontosabb invariánsa:* a felhasználó nem tudná
megkülönböztetni a **„nem mérhető"**-t a **„rossz"**-tól. Ez ugyanaz a
hibaosztály, mint az ADR 0251 §2 üres-referencia tiltása — hiányzó bemenet
sikeres mérésnek álcázva.

### 4. A runner-határ audió-útja ÖNÁLLÓ döntés (GOV-30c-5), nem ennek a körnek a dolga

A GOV-30c-4 pre-flightja kimérte, és itt rögzítjük, hogy a következő kör ne
fusson bele vakon:

```dart
abstract interface class AnalysisRunner {
  AnalysisRunHandle start(AnalysisDocument input);   // dokumentum, nem audió
}
```

```dart
/// Privacy-safe input metadata retained with an analysis document, never PCM.
final class AnalysisInputSummary { … }
```

A runner bemenete dokumentum; a dokumentum bemenet-mezője szándékosan **soha
nem hordoz PCM-et**; a futtatás `AnalysisDocumentCodec`-kel JSON-ként megy át
az izolátumra. A 18 (most 20) stage-es lánc viszont
`ValidatedPcmAnalysisInput`-ból indul. **Az audiónak ma nincs útja a V2 láncba
a runner-határon keresztül.**

Ez valódi architekturális rés, amit az Epic 6 harminc köre nem érintett, mert
egyik sem kötötte be a láncot. A feloldása — hogyan jut a minta az izolátumba
a dokumentum adatvédelmi szabályának megsértése nélkül — önálló ADR-t és kört
érdemel. **A GOV-30c-4-ben tilos hozzányúlni**; a GOV-30c-5 pre-flightja
mérje újra (változott-e a szerződés), ne ezt az ADR-t idézze bemondásra.

## Következmények

- A lánc 20 stage-es lesz; a `buildingInsights` és a `finalizing` fázis eddig
  kihasználatlan volt, a két új stage ezeket kapja.
- A dokumentum a lánc TERMÉKE lesz, de még nem jut el a felhasználóig: a
  provider változatlanul `StateError`-t dob.
- A V2 elemzés **a GOV-30c-5 után** lesz először futtatható — a §4 rés miatt
  egy lépcsővel később, mint az ADR 0251 §4 becsülte.

## Mérce

Az `E99-R12` §6.1 mérce-mátrixa, benne a dokumentum-teljesség három kötelező
cellájával (minden ép / egy degradált / minden degradálható elbukott) és a
valódi-sértés próbával: az insight-kontextus dokumentumát egy másik, nem
publikálandó példányra cserélve az **A3** cellának pirosnak kell lennie.

Az A3 szándékosan **injektált registryvel** mér: a szabályok által KAPOTT
dokumentumot hasonlítja az összeállítotthoz, nem a végeredményt nézi.

Lásd: [`docs/rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md`](../rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md).
