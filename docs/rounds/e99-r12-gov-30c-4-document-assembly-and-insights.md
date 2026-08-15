# E99-R12 (GOV-30c-4) — Dokumentum-összeállítás és insights

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, `main @ 8341f600` utáni friss `main`)
- **Típus:** **governance-kör** — a GOV-30c negyedik lépcsője
- **Kör-azonosító:** `E99-R12`. Emberi neve **GOV-30c-4**.
- **Branch:** `<motor>/e99-r12-gov-30c-4-document-assembly-and-insights`
  (a prefix a driver által feloldott TÉNYLEGES implementer neve, ADR 0242 §5.2)
- **Előfeltétel:** `E99-R11` (GOV-30c-3) merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0253`](../adr/0253-document-assembly-and-insight-stage-ordering.md)
  — **MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**
- **Folytatás (NEM ez a kör):** **GOV-30c-5** — a runner-határ audió-útja és a
  provider bekötése. Ennek a körnek a pre-flightja mérte ki, hogy ez önálló
  architekturális döntés (ADR 0253 §4) — lásd §2.5.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/analysis_work_state.dart",
  "lib/features/audio_analysis/engine/stages/document_stages.dart",
  "lib/features/audio_analysis/engine/stages/analysis_stage_phases.dart",
  "test/features/audio_analysis/engine/stages/document_stages_test.dart",
  "test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart",
  "test/features/audio_analysis/engine/full_pipeline_composition_test.dart",
  "docs/rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md",
]
gate_tests = [
  "test/features/audio_analysis/engine/full_pipeline_composition_test.dart",
  "test/features/audio_analysis/engine/stages/document_stages_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A GOV-30c-3 után a 18 stage-es lánc egyetlen élő `AnalysisPipeline`-ban áll
össze, és a munkaállapotban ott van minden nyersanyag — de **`AnalysisDocument`
még nem születik belőle**. Ez a kör összeállítja a dokumentumot, és ráfuttatja
az insight-szabályokat.

**Ez a kör sem kapcsol be semmit.** Az `analysisV2RunnerProvider` érintetlen
marad és a végén is `StateError`-t dob.

## 2. Jelenlegi állapot — mért tények

### 2.1 A munkaállapot MINDEN nyersanyagot tartalmaz

`engine/analysis_work_state.dart` mezői ma: az ingest-artefaktumok
(`preprocessedAudio?`, `signalQuality?`, `pitchFrames[]`, `pitchSegments[]`,
`chordSegments[]`, `beatGrid?`, `tempoCurve?`, `events[]`,
`suppressedEvents[]`), az értékelés eredményei (`alignment?`, `metrics[]`,
`capabilityReports{}`, `overallConfidence?`), plus `warnings[]` és
`unavailableCapabilities{}`.

### 2.2 A cél-típus mezői (a kimenet szerződése)

`domain/analysis_document.dart:58-71`:
`id`, `schemaVersion`, `createdAt`, `mode`, `input`, `provenance`,
`signalQuality`, `capabilities`, `timeline`, `metrics`, `hotspots`,
`insights`, `warnings`, `completion`.

### 2.3 Dokumentum-összeállító MA SINCS

`grep -rln "AnalysisDocument(" lib/features/audio_analysis/` → a domain-típus,
a `data/analysis_document_codec.dart` és a `data/legacy_analyze_adapter.dart`.
**Az engine egyetlen helyen sem állít össze dokumentumot.**

### 2.4 Az insights KÉSZ DOKUMENTUMON dolgozik — ez KÖTI a sorrendet

```dart
// domain/insights/insight_rule.dart:53-73
final class AnalysisInsightContext {
  AnalysisInsightContext({ required this.document, … });
  final AnalysisDocument document;
  final Duration timingTolerance;
  final TimingInsightEvidence? timingEvidence;
  final StrokeBalanceInsightEvidence? strokeBalance;
  final PreviousMetricComparison? previousComparison;
}
```

`InsightRegistry.evaluate(...)` (`engine/insights/insight_registry.dart:17`)
ezt a kontextust kapja, és `List<EvidenceBackedAnalysisInsight>`-ot ad;
`InsightRanker.rank(...)` (`insight_ranker.dart:32`) rendezi,
`HotspotRanker.rank(...)` (`hotspot_ranker.dart:7`) a hotspotokat.

**Következmény:** a dokumentumot ELŐBB kell összeállítani (insights és
hotspots nélkül), és csak azután futtathatók a szabályok. A sorrend nem
ízlés kérdése, hanem a típusokból következik.

### 2.5 MÉRT AKADÁLY a KÖVETKEZŐ körhöz — az audiónak nincs útja a runner-határon

Ez a kör pre-flightja kimérte, és a briefben azért szerepel, hogy a GOV-30c-5
ne fusson bele vakon:

```dart
// application/analysis_isolate_runner.dart — a runner szerződése
abstract interface class AnalysisRunner {
  AnalysisRunHandle start(AnalysisDocument input);
}
// a futtatás: AnalysisDocumentCodec().encode(input) → isolate → String → decode
```

```dart
/// Privacy-safe input metadata retained with an analysis document, never PCM.
final class AnalysisInputSummary { … duration, sampleRate, fingerprint … }
```

A runner bemenete **dokumentum**, a dokumentum bemenet-mezője pedig
szándékosan **soha nem hordoz PCM-et**. A 18 stage-es lánc viszont
`ValidatedPcmAnalysisInput`-ból indul. **Az audiónak ma nincs útja a V2 láncba
a runner-határon keresztül** — ez önálló architekturális döntés (hogyan jut a
minta az izolátumba a dokumentum adatvédelmi szabályának megsértése nélkül),
és a GOV-30c-5 dolga. **Ebben a körben tilos hozzányúlni.**

## 3. Scope

**Benne van:**

1. `AnalysisWorkState` bővítése egyetlen `document` mezővel.
2. `DocumentAssemblyStage` — a munkaállapotból ELŐZETES `AnalysisDocument`
   (üres `insights`/`hotspots`).
3. `InsightsStage` — a szabályok futtatása az előzetes dokumentumon, majd a
   VÉGLEGES dokumentum (insights + hotspots) visszaírása.
4. A fázis-térkép és a teljes lánc kiegészítése a két új stage-dzsel (18 → 20).
5. Tesztek.

**NINCS benne (tilos):**

- **Az `analysisV2RunnerProvider` felülírása vagy bármely flag mozgatása.**
  Acceptance-cella (A9).
- **A runner-határ vagy az `application/**` bármilyen módosítása** — a §2.5
  akadály a GOV-30c-5 dolga.
- Új DSP-matematika vagy meglévő engine-modul módosítása (AGENTS.md §9).
- `domain/**` (a dokumentum- és insight-típusok adottak), `public.dart`,
  `docs/adr/**`, `tools/**`, `.github/**`.
- A `stages/{ingest,evaluation}_stages.dart` **tartalma** (olvasni igen).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `engine/analysis_work_state.dart` | a `document` mező |
| `engine/stages/document_stages.dart` | **ÚJ** — az összeállító és az insight stage |
| `engine/stages/analysis_stage_phases.dart` | a térkép + a teljes lánc 20 stage-re |
| `test/…/stages/document_stages_test.dart` | **ÚJ** |
| `test/…/stages/analysis_stage_phases_test.dart` | a bővült térkép invariánsai |
| `test/…/engine/full_pipeline_composition_test.dart` | 20 stage élő pipeline-ban |
| `docs/rounds/e99-r12-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/audio_analysis/application/**` ·
`lib/features/audio_analysis/domain/**` · `public.dart` · `lib/core/flags/**` ·
`engine/stages/{ingest,evaluation}_stages.dart` tartalma · `docs/adr/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0253)

### 5.1 KÉT stage, nem egy — az insights kész dokumentumot kap

A §2.4 típus-kényszer miatt: `DocumentAssemblyStage` (előzetes dokumentum) →
`InsightsStage` (szabályok + rangsor + végleges dokumentum).

**NEM elfogadható gyengítés:** az insight-szabályok „megetetése" a
munkaállapotból összerakott ál-dokumentummal, ami nem az, amit a felhasználó
lát. A szabályok azon a dokumentumon fussanak, amelyik publikálásra kerül.

### 5.2 Az előzetes dokumentum MINDEN más mezője VÉGLEGES

Az összeállító stage csak az `insights` és a `hotspots` mezőt hagyja üresen.
A `signalQuality`, `capabilities`, `timeline`, `metrics`, `warnings`,
`completion`, `provenance` már a végleges értékét kapja.

**NEM elfogadható gyengítés:** „majd az insight stage kitölti a többit is". Az
két igazságforrást csinálna egy dokumentumból.

### 5.3 A hiányzó nyersanyag NEM kitalált érték

Ha egy mező forrása hiányzik a munkaállapotból (degradált stage miatt), a
dokumentum azt **üresen/`unavailable`-ként** viszi tovább, és a
`capabilities` mondja meg, miért. Tilos default-tal, nullával vagy
„jobb híján" számított értékkel pótolni.

**NEM elfogadható gyengítés:** üres `metrics` helyett nulla értékű metrikák
publikálása. A felhasználó nem tudná megkülönböztetni a „nem mérhető"-t a
„rossz"-tól.

### 5.4 A fázis-térkép a két új stage-dzsel is TELJES

A `buildingInsights` és a `finalizing` fázis eddig kihasználatlan volt; a két
új stage ezeket kapja. A GOV-30c-3 validációja miatt a hiányzó bejegyzés
konstruktor-hibát ad — ezt az A5 cella méri.

### 5.5 A kör semmit nem kapcsol be

Az `analysisV2RunnerProvider` érintetlen; a kör végén is `StateError`.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ép bemenetből a lánc végén VAN `AnalysisDocument` a munkaállapotban | `full_pipeline_composition_test.dart` |
| A2 | Az előzetes dokumentum `insights`/`hotspots` mezője ÜRES, minden más végleges | `document_stages_test.dart` |
| A3 | Az insight-szabályok a PUBLIKÁLANDÓ dokumentumot kapják kontextusként | `document_stages_test.dart` — injektált registry, a kapott `context.document` azonos az összeállítottal |
| A4 | A végleges dokumentum `insights` és `hotspots` mezője rangsorolt | `document_stages_test.dart` |
| A5 | A 20 stage MINDEGYIKE szerepel a fázis-térképen | `analysis_stage_phases_test.dart` — halmaz-egyezés |
| A6 | Degradált futásnál a hiányzó mező ÜRES marad, nem kitalált | `document_stages_test.dart` — pitch-degradált eset: nincs pitch-metrika, a capability unavailable |
| A7 | 20 stage elfogadható az élő pipeline-ban | `full_pipeline_composition_test.dart` |
| A8 | A publikált fázisok nem csökkennek a bővült lánc mellett sem | `full_pipeline_composition_test.dart` |
| A9 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | `git diff` — az `application/**` érintetlen |
| A10 | A `domain/**` érintetlen | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy stage-ben állít össze és futtat insightot | **A3** (a szabály nem a publikálandó dokumentumot kapja) |
| Az összeállító a `metrics`-et is üresen hagyja | A2 |
| Az insight stage felülírja a `capabilities`/`timeline` mezőt | A2 |
| Hiányzó pitch-metrikát nullával pótol | **A6** |
| A két új stage kimarad a fázis-térképről | A5 (konstruktor-hiba) |
| A rangsorolást kihagyja, nyers listát ír vissza | A4 |
| A kör „hasznosságból" felülírja a providert | A9 |
| A `domain/` insight-típusait „kényelmesebbre" írja | A10 |

**A dokumentum-teljesség három kötelező cellája** (a határ: a degradálás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| minden ép | egyik stage sem degradált | minden mező kitöltve, `capabilities` mind `available` |
| a határon | EGY degradált stage (pitch) | a pitch-metrikák hiányoznak, a capability `unavailable`, a TÖBBI mező kitöltve |
| minden degradálható elbukott | pitch + harmony + rhythm + alignment degradált | a dokumentum LÉTREJÖN, a `capabilities` mind `unavailable`, a `metrics` üres — **nem** kitalált nullák |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az
insight-kontextus dokumentumát egy másik (nem publikálandó) példányra → az
**A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/engine/full_pipeline_composition_test.dart test/features/audio_analysis/engine/stages/document_stages_test.dart test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. `AnalysisWorkState.document` mező + teszt.
2. `DocumentAssemblyStage` — az 5.2/5.3 szerint, a §2.2 mezőlista mentén.
3. `InsightsStage` — registry → ranker → hotspot ranker → végleges dokumentum.
4. A fázis-térkép és a teljes lánc 20 stage-re.
5. A §6.1 három dokumentum-teljesség cellája + a valódi-sértés próba.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kitalált érték csábítása.** A dokumentum sok mezője „üresen csúnya", és
  kísért a nullákkal töltés. Az 5.3 és az A6 pont ezt méri — ez a kör
  legfontosabb invariánsa.
- **A két stage összevonása.** Egyetlen stage-ben összeállítani és insightot
  futtatni egyszerűbbnek tűnik, de akkor a szabályok nem a publikálandó
  dokumentumot látják. Az A3 injektált registryvel méri.
- **A §2.5 akadály átlépése.** „Már csak a provider hiányzik" érzés támadhat.
  A runner-határ audió-útja önálló döntés (GOV-30c-5); az A9 méri.
- **A fázis-térkép elfelejtése.** A GOV-30c-3 validációja miatt ez
  konstruktor-hiba, nem néma elcsúszás — de a lista és a térkép EGYÜTT
  bővüljön.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
