# ADR 0252 — A progress-fázis leválik a stage-granularitásról

**Státusz:** elfogadva (2026-08-15). A GOV-30c harmadik lépcsőjének
architekturális döntései.
Épít: [ADR 0250](0250-v2-analysis-work-state-and-ingest-stage-composition.md),
[ADR 0251](0251-analysis-target-seeding-and-evaluation-stage-composition.md)
(különösen §5, amely ezt a feladatot ide halasztotta), és az
[ADR 0240](0240-analysis-runner-and-pipeline-boundary.md) runner/pipeline
határára.

**Felülírja** az E06-R04-ben rögzített **szigorú** progress-monotonitás
invariánsát (lásd Döntés 2). Az `AnalysisPipeline` minden más szerződése —
fatális/degradálható elágazás, cancellation, provenance — változatlan.

## Kontextus — 18 stage egy kilences sapka alatt

A GOV-30c-1 hét ingest-, a GOV-30c-2 tizenegy értékelő stage-et épített:
**18 stage**. Az `AnalysisPipeline` konstruktora viszont kilencnél többet nem
fogad:

```dart
// engine/analysis_pipeline.dart:68-74
if (_stages.length > AnalysisProgressPhase.values.length) {
  throw ArgumentError.value(stages, 'stages',
    'cannot exceed the nine ordered progress phases');
}
```

A sapka oka a **pozicionális** leképezés (`:177`):

```dart
phase: AnalysisProgressPhase.values[index],
```

Az `AnalysisProgressPhase` kilenc értéke (`preparing … finalizing`) azonban
**felhasználói progress-modell**, nem stage-azonosító: azt írja le, mit lát a
felhasználó a folyamatjelzőn, nem azt, hány DSP-lépés fut. A kettő
összekötése a stage-ek számát a UI-modell méretéhez láncolta.

A GOV-30c-2 emiatt kényszerült arra, hogy a kompozíciót szekvenciális
teszt-harnessel bizonyítsa élő `AnalysisPipeline`-példány helyett
(ADR 0251 §5), és ugyanaz az ADR nevesített follow-upként ide halasztotta a
valódi feloldást — azzal a kikötéssel, hogy a következő kör **mérje újra**.
Újramérve (2026-08-15, `main @ 0d4dbfa5`): a sapka **továbbra is 9**, a lánc
**18**.

## Döntés

### 1. A fázis a kompozíció tulajdona, nem a stage pozíciójáé

Az `AnalysisPipeline` opcionális `Map<String, AnalysisProgressPhase>
stagePhases` paramétert kap (stage-id → fázis). Több stage **osztozhat**
egy fázison; a leképezés adatvezérelt, a stage-id konstansokra hivatkozva.

Konstruktor-validáció a térkép megadásakor: minden stage-id szerepel benne, a
fázisok a stage-sorrend mentén nem csökkennek, és a hossz-sapka nem érvényes.

**Visszafelé kompatibilis:** térkép nélkül a mai pozicionális viselkedés és a
kilences sapka változatlanul él tovább. A meglévő hívók és tesztek nem törnek.

*Miért nem az enum bővítése 18-ra:* az a UI-modellt rontaná el, hogy a
DSP-implementáció kényelmesebb legyen — és a stage-ek száma tovább fog nőni.
Kilenc felhasználói fázis pont elég ahhoz, hogy a folyamatjelző értelmes
legyen.

*Miért nem a sapka egyszerű törlése:* a pozicionális `values[index]` a
tizedik stage-nél `RangeError`-t dobna. A hiba nem szűnne meg, csak
futásidőre csúszna.

### 2. A szigorú monotonitás nem-csökkenőre enyhül; a visszalépés tiltása marad

```dart
// ma, engine/analysis_pipeline.dart:135
if (latestPhase != null && event.phase.index <= latestPhase!.index) {
  throw StateError('Analysis progress phases must be strictly monotonic.');
}
```

A fázis-eseményt a stage publikálja (`analysis_context.dart:74-83`,
`reportProgress()`), a saját hozzárendelt fázisával. Ha két stage osztozik egy
fázison és mindkettő jelent, a `<=` ág **duplikátumra** dob — nem
visszalépésre.

- **Tilos marad:** `phase.index < latest.index` (visszalépés).
- **Legális lesz:** `phase.index == latest.index` — ugyanaz a fázis többször,
  a `completedUnits` finomabb haladást visz rajta belül.

*Miért nem az ellenőrzés eltávolítása:* a visszafelé ugró folyamatjelző a
felhasználónak látható hazugság. A relaxáció pontosan addig megy, ameddig a
sok-az-egyhez leképezés megköveteli.

*A változás felülete zárt:* `grep -rn "AnalysisPhaseProgressEvent(" lib/` →
három találat (a domain-típus, a `reportProgress()`, és az isolate-runner).
Nincs más publikáló.

### 3. A meglévő teszt-cellák frissülnek, nem törlődnek

Az `analysis_pipeline_test.dart` szigorú-monotonitás cellái **átíródnak**: a
visszalépést továbbra is bizonyítottan `StateError` fogadja, és ÚJ cella
bizonyítja, hogy az azonos fázis ismétlése már nem dob. Törölt cella a
review-ban MAJOR — a mérce nem tűnhet el a változással együtt.

## Következmények

- A teljes, 18 stage-es lánc **egyetlen élő `AnalysisPipeline`-példányban**
  összeszerelhető; a GOV-30c-2 kényszerű teszt-harnesse megszűnik.
- A stage-ek száma szabadon nőhet: egy új DSP-lépés a térképen kap fázist,
  nem az enumban.
- Egy későbbi kör, amely stage-et ad a listához a térkép frissítése nélkül,
  **konstruktor-hibát** kap, nem néma elcsúszást.
- **Nincs viselkedésváltozás a felhasználó felé.** A kör nulla flaget mozdít,
  és az `analysisV2RunnerProvider` a végén is `StateError`-t dob — a
  bekötés a GOV-30c-4 dolga.

## Mérce

Az `E99-R11` §6.1 mérce-mátrixa, benne a fázis-sorozat három kötelező
cellájával (visszalépés → `StateError` / azonos fázis → átmegy / előrelépés →
átmegy) és a **kétlépcsős** valódi-sértés próbával: a `<` visszacserélése
`<=`-re az A7 cellát, az ellenőrzés teljes kivétele az A6 cellát pirosítja.

Lásd: [`docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md`](../rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md).
