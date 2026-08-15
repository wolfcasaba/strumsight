# E99-R11 (GOV-30c-3) — A progress-fázis leválasztása a stage-granularitásról

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, `main @ eb7ecc0c`)
- **Típus:** **governance-kör** — a GOV-30c harmadik lépcsője (ADR 0251 §4–5)
- **Kör-azonosító:** `E99-R11`. Emberi neve **GOV-30c-3**.
- **Branch:** `sonnet-impl/e99-r11-gov-30c-3-progress-phase-decoupling`
- **Előfeltétel:** `E99-R10` (GOV-30c-2) merge-elve (PR #261, `82cfa588`)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Sonnet 5 (`sonnet-impl`)
- **Előre kiosztott ADR:** [`0252`](../adr/0252-progress-phase-decoupled-from-stage-granularity.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
  Az ADR 0252 **felülírja** az E06-R04 szigorú-monotonitás invariánsát (lásd §5.2).
- **Folytatás (NEM ez a kör):** GOV-30c-4 — insights/hotspots, az
  `AnalysisDocument` összeállítása, és **csak ott** az
  `analysisV2RunnerProvider` felülírása. A briefje még nincs megírva.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/analysis_pipeline.dart",
  "lib/features/audio_analysis/engine/stages/analysis_stage_phases.dart",
  "test/features/audio_analysis/engine/analysis_pipeline_test.dart",
  "test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart",
  "test/features/audio_analysis/engine/full_pipeline_composition_test.dart",
  "docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md",
]
gate_tests = [
  "test/features/audio_analysis/engine/full_pipeline_composition_test.dart",
  "test/features/audio_analysis/engine/analysis_pipeline_test.dart",
]
native_gate = false
```

### §0.0 Pre-flight revízió — a tényleges implementer-azonosság (2026-08-15)

Az eredeti, előre elkészített brief `codex` / Terra implementert és az ennek
megfelelő branch-prefixet jelölt. Ennek a firingnek a driver által feloldott,
explicit motorja **`sonnet-impl`**; a registry szerint ez `claude` harnesses
Sonnet 5. A branch-prefix ezért `sonnet-impl/…`, hogy az ADR 0242 szerinti
reviewer-függetlenség a valós implementer-azonosságból mérhető legyen. A
váltás csak orchesztrációs metadata: az `allowed_paths`, az ADR 0252 és az
összes acceptance-kritérium változatlan.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A GOV-30c-1 hét ingest-stage-et, a GOV-30c-2 tizenegy értékelő stage-et
épített — **összesen 18**. Az `AnalysisPipeline` viszont **kilencnél** többet
nem fogad, ezért a teljes lánc ma **nem szerelhető össze egyetlen példányba**;
a GOV-30c-2 emiatt kényszerült szekvenciális teszt-harnessre (ADR 0251 §5).

Ez a kör a sapkát a gyökerénél oldja fel: **leválasztja a felhasználónak
mutatott progress-fázist a DSP-stage-ek granularitásáról**, és a teljes,
18 stage-es láncot egyetlen ÉLŐ `AnalysisPipeline`-példányban bizonyítja.

**Ez a kör sem kapcsol be semmit.** Az `analysisV2RunnerProvider` érintetlen
marad és a végén is `StateError`-t dob.

## 2. Jelenlegi állapot — mért tények

### 2.1 A sapka és az oka (újramérve, ahogy az ADR 0251 §5 előírta)

```dart
// engine/analysis_pipeline.dart:68-74
if (_stages.length > AnalysisProgressPhase.values.length) {
  throw ArgumentError.value(stages, 'stages',
    'cannot exceed the nine ordered progress phases');
}
```

```dart
// engine/analysis_pipeline.dart:177 — a POZICIONÁLIS leképezés, a sapka oka
phase: AnalysisProgressPhase.values[index],
```

`AnalysisProgressPhase` (`domain/analysis_progress.dart:4-14`) **kilenc**
érték: `preparing, validatingInput, preprocessing, extractingEvents,
estimatingHarmony, estimatingBeatGrid, computingMetrics, buildingInsights,
finalizing`. Ez **felhasználói progress-modell**, nem stage-azonosító.

**A mai lánc-hossz mérve:** `buildIngestStages()` **7** +
`buildEvaluationStages()` **11** = **18** stage.

### 2.2 A szigorú monotonitás — az invariáns, amit fel KELL oldani

```dart
// engine/analysis_pipeline.dart:134-140
if (event is AnalysisPhaseProgressEvent) {
  if (latestPhase != null && event.phase.index <= latestPhase!.index) {
    throw StateError('Analysis progress phases must be strictly monotonic.');
  }
```

A fázis-eseményt a **stage** publikálja
(`engine/analysis_context.dart:74-83`, `reportProgress()`), a saját
hozzárendelt fázisával. Ma minden stage-nek SAJÁT fázisa van (pozicionálisan),
ezért a szigorú `<=` tiltás működik.

**18 stage / 9 fázis mellett ez lehetetlen:** több stage osztozik egy fázison,
és ha közülük kettő is jelent, a `<=` ág azonnal `StateError`-t dob —
duplikátumra, nem visszalépésre.

### 2.3 Ki publikál fázis-eseményt (teljes lista, mérve)

`grep -rn "AnalysisPhaseProgressEvent(" lib/` → **három** találat:
a domain-típus definíciója, az `analysis_context.dart:77`
(`reportProgress()`), és az `analysis_isolate_runner.dart:133`. A tesztekben
négy hivatkozás. **Nincs más publikáló** — a változás felülete zárt.

### 2.4 Amit a két korábbi lépcső hagyott

`AnalysisWorkState` mezői ma: az ingest-artefaktumok + `alignment?`,
`metrics[]`, `capabilityReports{}`, `overallConfidence?`. A két lánc-építő
függvény (`buildIngestStages()`, `buildEvaluationStages()`) és a két
classifier (`classifyIngestStageFailure`, `classifyEvaluationStageFailure`)
production kódban **létezik** — ez a kör ezeket fűzi össze, nem írja újra.

## 3. Scope

**Benne van:**

1. Az `AnalysisPipeline` opcionális **stage-id → fázis** leképezése a
   pozicionális helyett.
2. A konstruktor-validáció cseréje: hossz-sapka helyett a leképezés
   teljességének és nem-csökkenő voltának ellenőrzése.
3. A szigorú monotonitás enyhítése **nem-csökkenőre** (a visszalépés tiltása
   MARAD).
4. `analysis_stage_phases.dart`: a 18 stage fázis-térképe + a teljes lánc
   összefűzése (`buildFullAnalysisStages()`, `classifyAnalysisStageFailure`).
5. A teljes lánc bizonyítása **ÉLŐ `AnalysisPipeline`-példányban**.

**NINCS benne (tilos):**

- **Az `analysisV2RunnerProvider` felülírása vagy bármely flag mozgatása.**
  Acceptance-cella (A9).
- Az `AnalysisProgressPhase` enum bővítése. A megoldás a **leválasztás**, nem
  a fázisok szaporítása — kilenc felhasználói fázis elég, a stage-ek száma
  nőni fog még.
- Insights, hotspot-rangsor, `AnalysisDocument` összeállítás — GOV-30c-4.
- Új DSP-matematika vagy meglévő engine-modul módosítása (AGENTS.md §9).
- A `stages/ingest_stages.dart` és `stages/evaluation_stages.dart` **tartalma**
  (olvasni kell, írni nem).
- `docs/adr/**`, `tools/**`, `.github/**`, `public.dart`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `engine/analysis_pipeline.dart` | a leképezés, a validáció és az invariáns |
| `engine/stages/analysis_stage_phases.dart` | **ÚJ** — a fázis-térkép + a teljes lánc |
| `test/…/engine/analysis_pipeline_test.dart` | a megváltozott invariáns celláinak SZÁNDÉKOS frissítése |
| `test/…/engine/stages/analysis_stage_phases_test.dart` | **ÚJ** — a térkép invariánsai |
| `test/…/engine/full_pipeline_composition_test.dart` | **ÚJ** — 18 stage élő pipeline-ban |
| `docs/rounds/e99-r11-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/audio_analysis/domain/analysis_progress.dart` ·
`engine/stages/{ingest,evaluation}_stages.dart` tartalma ·
`lib/features/audio_analysis/application/**` · `public.dart` ·
`lib/core/flags/**` · `docs/adr/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0252)

### 5.1 A fázis a KOMPOZÍCIÓ tulajdona, nem a stage pozíciójáé

Az `AnalysisPipeline` opcionális
`Map<String, AnalysisProgressPhase> stagePhases` paramétert kap (stage-id →
fázis). Megadva ez dönt; **elhagyva a mai pozicionális viselkedés és a
kilences sapka VÁLTOZATLANUL él tovább** — a meglévő hívók és tesztek nem
törnek.

Konstruktor-validáció a térkép megadásakor:

- minden stage-id szerepel a térképben (hiányzó id → `ArgumentError`);
- a fázisok a stage-sorrend mentén **nem csökkennek** (visszalépő térkép →
  `ArgumentError`);
- a hossz-sapka **nem érvényes** (18 > 9 legális).

**NEM elfogadható gyengítés:** a sapka egyszerű törlése a leképezés
megoldása nélkül. Akkor a pozicionális `values[index]` a 10. stage-nél
`RangeError`-t dobna — a hiba csak arrébb csúszna, futásidőre.

### 5.2 A szigorú monotonitás NEM-CSÖKKENŐRE enyhül — a visszalépés tiltása MARAD

Ez az [E06-R04](../adr/0240-analysis-runner-and-pipeline-boundary.md) körben
rögzített invariáns **szándékos** megváltoztatása, amit az ADR 0252
dokumentál és felülír. **A kör NEM áll meg H2-vel emiatt** — az engedély
explicit.

- **Tilos marad:** `event.phase.index < latestPhase.index` (visszalépés).
- **Legális lesz:** `event.phase.index == latestPhase.index` (ugyanaz a fázis
  többször — több stage osztozik rajta, és a `completedUnits` finomabb
  haladást visz).

A meglévő `analysis_pipeline_test.dart` szigorú-monotonitás celláit
**frissíteni kell, nem törölni**: a visszalépést továbbra is bizonyítottan
`StateError` fogadja, és ÚJ cella bizonyítja, hogy az azonos fázis ismétlése
már NEM dob.

**NEM elfogadható gyengítés:** az ellenőrzés teljes eltávolítása. A
visszafelé ugró progress a felhasználónak látható hazugság.

### 5.3 A fázis-térkép ADATVEZÉRELT és teljes

A 18 stage-hez tartozó térkép a `analysis_stage_phases.dart`-ban él, a
`IngestStageIds` és a GOV-30c-2 stage-id konstansaira hivatkozva —
**nem string-literálokkal**. A térkép a stage-listával együtt tesztelt: ha egy
későbbi kör új stage-et ad hozzá és lefelejti a térképről, a konstruktor
`ArgumentError`-t dob, és az A5 cella pirosra vált.

### 5.4 A kör semmit nem kapcsol be

Az `analysisV2RunnerProvider` érintetlen; a kör végén is `StateError`.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Térkép NÉLKÜL a pozicionális viselkedés és a 9-es sapka változatlan | a meglévő `analysis_pipeline_test.dart` cellái módosítás nélkül zöldek |
| A2 | Térképpel 18 stage **elfogadható** | `full_pipeline_composition_test.dart` — élő `AnalysisPipeline` példány |
| A3 | Hiányzó stage-id a térképben → `ArgumentError` | `analysis_stage_phases_test.dart` |
| A4 | Visszalépő térkép (csökkenő fázis) → `ArgumentError` | `analysis_stage_phases_test.dart` |
| A5 | A 18 stage MINDEGYIKE szerepel a térképen | `analysis_stage_phases_test.dart` — a lista és a térkép kulcsainak halmaza egyezik |
| A6 | **Visszalépő** fázis-esemény továbbra is `StateError` | `analysis_pipeline_test.dart` — frissített cella |
| A7 | **Azonos** fázis ismétlése már NEM dob | `analysis_pipeline_test.dart` — ÚJ cella |
| A8 | A teljes lánc végigfut, és a publikált fázisok nem csökkennek | `full_pipeline_composition_test.dart` — a publikált fázis-sorozat rögzítve |
| A9 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | `git diff` — az `application/**` érintetlen |
| A10 | A `domain/analysis_progress.dart` érintetlen (9 fázis marad) | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A sapkát törli, de a pozicionális leképezést hagyja | A2 (`RangeError` a 10. stage-nél) |
| A térképet megadva is pozicionálisan képez | A8 (a publikált fázisok nem a térkép szerintiek) |
| A validáció nem nézi a hiányzó id-t | A3 |
| A validáció nem nézi a csökkenő sorrendet | A4 |
| Az ellenőrzést TELJESEN kiveszi a `publish`-ból | **A6** — a visszalépés is átmenne |
| Csak `<`-re javítja a `<=`-t, de a térkép-validáció nélkül | A4 (a csökkenő térkép futásidőre csúszna) |
| A térkép string-literálokkal, nem a stage-id konstansokkal | A5 (egy átnevezés némán kihagyna egy stage-et) |
| Az `AnalysisProgressPhase`-t bővíti 18-ra | A10 |
| A kör „hasznosságból" felülírja a providert | A9 |

**A fázis-sorozat három kötelező cellája** (a határ: az előző publikált fázis):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | `phase.index < latest.index` | `StateError` — visszalépés |
| a határon | `phase.index == latest.index` | **átmegy** — ez az új viselkedés |
| fölötte | `phase.index > latest.index` | átmegy (változatlan) |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a `<`-t
vissza `<=`-re → az **A7** cellának PIROSNAK kell lennie; majd vedd ki az
egész ellenőrzést → az **A6** cellának PIROSNAK kell lennie. Állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/engine/full_pipeline_composition_test.dart test/features/audio_analysis/engine/analysis_pipeline_test.dart test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. `analysis_stage_phases.dart`: a 18 stage fázis-térképe a stage-id
   konstansokból + a lánc-összefűzés + a classifier-összefűzés.
2. Az `AnalysisPipeline` opcionális `stagePhases` paramétere és a
   konstruktor-validáció (A3, A4, A5).
3. A monotonitás `<=` → `<` enyhítése, a meglévő cellák SZÁNDÉKOS frissítése
   (A6) és az új cella (A7).
4. `full_pipeline_composition_test.dart`: 18 stage ÉLŐ pipeline-ban, a
   publikált fázis-sorozat rögzítésével (A2, A8).
5. A §6.1 három fázis-cellája + a kétlépcsős valódi-sértés próba.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Lezárt kör invariánsának módosítása.** Az §5.2 engedélye explicit, de a
  meglévő teszt-cellákat **frissíteni** kell, nem törölni. Törölt cella =
  MAJOR a review-ban.
- **A pozicionális ág csendes elhalása.** Az A1 pont azt védi, hogy a térkép
  nélküli hívás bitre ugyanaz maradjon — a meglévő tesztek módosítás nélküli
  zöldsége a bizonyíték.
- **A térkép és a lista szétcsúszása.** Egy későbbi kör új stage-et adhat a
  listához a térkép frissítése nélkül. Az A5 ezért halmaz-egyezést mér, nem
  csak azt, hogy a térkép nem üres.
- **A kör mérete csábít a továbblépésre.** Az insights és a
  dokumentum-összeállítás NEM ennek a körnek a dolga, még ha „már csak az
  hiányzik" érzés is támad. Az A9 ezt méri.

## 10. Implementation handoff — a Codex tölti ki

## 11. Review — a Claude tölti ki
