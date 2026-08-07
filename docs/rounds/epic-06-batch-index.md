# Epic 6 (Audio Analysis 2.0) — batch előkészítési index

- **Státusz:** PREPARED (batch előre megírva **2026-08-07**, kód olvasva: `main` @ `a6e6f3d`)
- **SDD-forrás:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) (Chapter 7, Kör 1–30)
- **Előfeltétel-epic:** Epic 5 (Computer Vision) lezárva — **E05-R30 merge**.
  A batch készítésekor az E05-R11 volt az utolsó merge-elt kör; az
  E05-R12…R30 `pending`.
- **User-döntés (2026-08-07):** „készítsd el az Epic 6 terveket is, hogy ha
  kész az Epic 5, **APK-ellenőrzés után** tudjam indítani." → a 30 queue-sor
  **`hold`** státusszal kerül a sor végére. A lánc **megáll az epic-határon**;
  az Epic 6 indítása **emberi döntés**, az Epic 5 APK-ellenőrzése után.

> ⚠ **Ez az index nem futtatható artefaktum.** A körök briefjei az
> `e06-rNN-*.md` fájlok. Minden brief `PREPARED`; élesedéskor a kötelező
> ⚠ pre-flight méri újra a driftet, és állítja `PLANNING`-re a kör-branchen.

---

## 0. Indítás (amikor a user zöld utat ad)

```bash
sed -i -E 's/^(E06-R[0-9]+\t.*\t)hold$/\1pending/' docs/execution/pipeline-queue.tsv
```

Egyetlen kör indításához elég az adott sort átírni. **Ne** a `--halt`-ot
használd megállításra (ADR 0112 szerint az önjavító kört indít).

---

## 1. Az Epic 6 négy szerkezeti szabálya (KÖTELEZŐ olvasmány)

Az Epic 6 az **első olyan epic, amely a meglévő shipping DSP köré épül**.
Ezért a batch négy szabályt épít **minden** briefbe:

**(a) A V1 az egész Epic alatt a shipping út marad.** Minden V2 képesség
`audioAnalysisV2Enabled` (+ al-flagek) mögött, **default OFF minden
környezetben, dart-define override nélkül** (ADR 0205, a
`songTrainerV2Enabled` precedense). A meglévő Analyze/Library tesztek a **mai**
viselkedés őrei: **átírásuk tilos**, elbukó meglévő teszt = **megállás és
jelentés**. Minden kör acceptance-e tartalmaz egy „V1 érintetlen" cellát
(`git diff --stat` + a V1 gate zöldje).

**(b) DSP-tilalom, pontosan.** Az Epic 6 **új** mennyiségeket vezet be, de a
**shipping DSP-konstansokat** (`lib/features/live/engine/dsp/dsp_config.dart`,
NNLS/Viterbi/SuperFlux paraméterek, modell-assetek) **nem** hangolja
(AGENTS.md §9). Minden új DSP-mennyiséghez **RAG-chunk** tartozik ugyanabban
a commitban: `019` signal quality (R07), `020` beat grid/tempo (R12),
`021` rhythm/groove (R15), `022` dynamics (R16). Retune ⇒ külön, mért kör.

**(c) Valós-audio evidencia ≠ merge-kapu.** Ezen a boxon nincs valós felvétel,
nincs gitár és nincs Android SDK; az SDD több köre (1, 29, 30) valós mérést ír
elő. A nem mérhető bizonyíték a **`docs/manual-testing/analysis-eval-matrix.md`**
PENDING sora lesz, felelőssel és a mérendő számmal (az Epic 5
device-mátrixának mintájára). **Merge-kapu marad:** `tools/round-gate.sh` +
exact-SHA zöld CI.

**(d) H-GATEGUARD határ az R29/R30-ban.** Az SDD Kör 29 CI-oldali regressziós
kaput kér, de a `.github/workflows/*` és a `tool/ci/*` a **mérce**, amit egy
önmagát mérő session nem írhat át (ADR 0112/0138,
`.claude/hooks/protect_factory_files.py`). Az **E06-R29** ezért a gate
**teszt-oldali** megfelelőjét szállítja
(`test/tooling/analysis_evaluation_regression_test.dart`), az **E06-R30**
completion reportja pedig **nevesíti** a hátralévő CI-munkát → ember által
engedélyezett **governance-kör (`GOV-xx`)**. Tudatos határ, nem hiány.

---

## 2. Kör-térkép (30 kör)

| Kör | Cím | Motor | Előre kiosztott ADR | Előfeltétel (Epic 6-on belül) | Brief |
|---|---|---|---|---|---|
| E06-R01 | Analyze V1 baseline, mérés és ADR-ek | codex | 0200–0205 | — (Epic 5 zárva) | `e06-r01-analyze-v1-baseline-and-adrs.md` |
| E06-R02 | AnalysisDocument V2 domainmodell | codex | — | R01 | `e06-r02-analysis-document-v2-domain.md` |
| E06-R03 | Codec, schema validation és V1 adapter | codex | — | R02 | `e06-r03-codec-schema-and-legacy-adapter.md` |
| E06-R04 | Pipeline contract, stage context, progress | codex | — | R02 | `e06-r04-pipeline-contract-stage-and-progress.md` |
| E06-R05 | Input abstraction és biztonságos import | codex | — | R03, R04 | `e06-r05-input-abstraction-and-safe-import.md` |
| E06-R06 | Recorder + AudioSessionCoordinator | codex | — | R05 | `e06-r06-recorder-audio-session-integration.md` |
| E06-R07 | Signal quality stage | codex | — | R04, R05 | `e06-r07-signal-quality-stage.md` |
| E06-R08 | Preprocessing context és resampling policy | codex | 0206 | R05, R07 | `e06-r08-preprocessing-context-and-resampling.md` |
| E06-R09 | V1 ClipAnalyzer stage adapter és parity | codex | — | R04, R08 | `e06-r09-clip-analyzer-stage-adapter-parity.md` |
| E06-R10 | Event evidence + onset/strum timeline V2 | codex | — | R09 | `e06-r10-event-evidence-onset-strum-timeline.md` |
| E06-R11 | Chord evidence, segmentation, provenance | codex | 0207 | R09, R10 | `e06-r11-chord-evidence-segmentation-provenance.md` |
| E06-R12 | Beat grid és tempo curve | codex | — | R10 | `e06-r12-beat-grid-and-tempo-curve.md` |
| E06-R13 | Target alignment engine | codex | — | R10, R12 | `e06-r13-target-alignment-engine.md` |
| E06-R14 | Timing és rush/drag metrikák | codex | — | R13 | `e06-r14-timing-and-rush-drag-metrics.md` |
| E06-R15 | Rhythm consistency és groove proxyk | codex | — | R12, R14 | `e06-r15-rhythm-consistency-and-groove.md` |
| E06-R16 | Dynamics és stroke balance | codex | — | R08, R10 | `e06-r16-dynamics-and-stroke-balance.md` |
| E06-R17 | Monofonikus pitch capability | codex | — | R08, R13 | `e06-r17-monophonic-pitch-capability.md` |
| E06-R18 | Technique proxy kísérleti modul | codex | 0208 | R11, R16, R17 | `e06-r18-technique-proxy-experimental-module.md` |
| E06-R19 | Confidence calibration + capability resolver | codex | — | R07, R14, R16, R17 | `e06-r19-confidence-calibration-capability-resolver.md` |
| E06-R20 | Determinisztikus insightok és hotspotok | codex | — | R14, R15, R16, R19 | `e06-r20-deterministic-insights-and-hotspots.md` |
| E06-R21 | AnalysisRepository V2 + legacy migráció | codex | 0209 | R03, R20 | `e06-r21-analysis-repository-v2-and-migration.md` |
| E06-R22 | Analysis runner, progress UI, cancellation | codex | — | R04, R06, R21 | `e06-r22-analysis-runner-progress-cancellation.md` |
| E06-R23 | Overview screen és metric cardok | **minimax** | — | R20, R22 | `e06-r23-analysis-overview-and-metric-cards.md` |
| E06-R24 | Többrétegű, zoomolható timeline | **minimax** | — | R23 | `e06-r24-layered-zoomable-timeline.md` |
| E06-R25 | Session comparison és fejlődési trend | codex | — | R21, R23 | `e06-r25-session-comparison-and-trend.md` |
| E06-R26 | Practice, Song és Tutor integráció | codex | — | R13, R20, R22 | `e06-r26-practice-song-tutor-integration.md` |
| E06-R27 | Export, share és privacy controls | codex | — | R21, R26 | `e06-r27-export-share-and-privacy-controls.md` |
| E06-R28 | Cache, performance és model lifecycle | codex | 0210 | R21, R22 | `e06-r28-cache-performance-and-model-lifecycle.md` |
| E06-R29 | Evaluation harness és confidence calibration | codex | 0211 | R19, R28 | `e06-r29-evaluation-harness-and-calibration.md` |
| E06-R30 | Shadow rollout, migráció, Epic zárás (ZÁRÓ) | codex | — | MIND (R01–R29) | `e06-r30-shadow-rollout-migration-and-epic-closure.md` |

---

## 3. ADR-kiosztás (PROVIZÓRIKUS — pre-flightban reconcile KÖTELEZŐ)

A batch készítésekor a legmagasabb ADR **0184**. A **0185–0199** blokk az Epic 5
hátralévő 19 körének (E05-R12…R30, benne az R12/R17/R21 renumberelése) és a
governance-munkának **fenntartott** — az Epic 6 ezért **0200-tól** oszt:

| ADR | Kör | Tárgy |
|---|---|---|
| 0200 | R01 | Analysis document versioning (schemaVersion, mikroszekundum időalap) |
| 0201 | R01 | Analysis confidence calibration és abstention |
| 0202 | R01 | Analysis raw audio retention (privacy by default) |
| 0203 | R01 | Metric ID és metric version governance (összehasonlíthatóság) |
| 0204 | R01 | Capability-aware publikáció (status + reason + küszöb) |
| 0205 | R01 | Audio Analysis V2 párhuzamos rollout határa (V1 marad shipping) |
| 0206 | R08 | Preprocessing és resampling policy (a V1 nem resampol) |
| 0207 | R11 | Chord decoder fusion stratégia (DSP primary, ML advisory) |
| 0208 | R18 | Technique proxy elnevezési és állítás-biztonsági határ |
| 0209 | R21 | Analysis document storage (fájl-alapú, atomikus, index) |
| 0210 | R28 | Cache-kulcs és performance budget |
| 0211 | R29 | Evaluation dataset governance (licenc, privacy, küszöbök) |

**Reconciliation-szabály (minden brief ⚠ pre-flightjában):** indítás előtt
`ls docs/adr/ | sort | tail` a valós next-free számhoz; ha az Epic 5 hátralévő
körei vagy egy párhuzamos governance-munka a 0199 fölé fogyasztott, **told el
az egész 0200–0211 blokkot**, és javítsd az érintett briefek §5-ét és ezt a
táblát. A gépi őr: `tools/tests/test_adr_numbering.py`.

---

## 4. Motor-besorolás (ADR 0069 mért szabály, gépileg ellenőrizve)

A `pipeline-queue.tsv` szabálya
(`tools/tests/test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule`):
`risk == "normal"` → minimax; `risk == "high"` **és** UI/ARB > domain+app+data
→ minimax; egyébként → codex.

Az Epic 6 túlnyomó része core/domain/data, DSP-paritás-, adatvédelem- vagy
invariáns-kritikus (codec, pipeline, illesztés, metrikák, confidence,
persistence, export) → **codex (Terra)**. Kizárólag a két UI-dominált kör —
**R23** (overview + metrikakártyák) és **R24** (zoomolható timeline) — megy
**minimax**-ra. A szabályt a batch minden briefjének `allowed_paths` mezőjére
lefuttattuk (2026-08-07): mind a 30 sor egyezik.

---

## 5. Új feature flagek (mind default OFF, dart-define override nélkül)

| Flag | Kör | Mit kapcsol |
|---|---|---|
| `audioAnalysisV2Enabled` | R02 | a teljes V2 út |
| `analysisBeatGridEnabled` | R02 | beat grid + tempo curve |
| `analysisPitchEnabled` | R02 | monofonikus pitch |
| `analysisPreprocessingExperimentalEnabled` | R08 | DC-offset + normalizáció |
| `analysisExperimentalFusionEnabled` | R11 | DSP/ML chord fusion |
| `analysisTechniqueProxiesEnabled` | R18 | Lab-only technique proxyk |
| `analysisComparisonEnabled` | R25 | session-összehasonlítás + trend |
| `analysisPracticeIntegrationEnabled` | R26 | Practice evidence-adapter |
| `analysisTutorIntegrationEnabled` | R26 | Tutor snapshot |

Az **E06-R30** flag-őre mind a kilencet méri **minden** környezetre.

---

## 6. Globális pre-flight emlékeztetők (minden Epic 6 brief örökli)

- **Greenfield feature-könyvtár:** ma nincs `lib/features/audio_analysis/`.
  A meglévő `lib/features/analyze/` (12 fájl, 1 866 sor) és
  `lib/features/library/` **változatlan** marad.
- **A cross-feature allowlist csak SZŰKÜLHET** (ADR 0176,
  `tool/check_architecture.dart` 10–21. sora: 12 `analyze → live` bejegyzés).
  Az `audio_analysis` **nem** vehet fel újat; a V1 DSP-t a
  `analyze/public.dart` határon át hívja (E06-R09).
- **A közös core primitívek szabadon használhatók:** `lib/core/audio/dsp/`
  (YIN, sliding framer), `lib/core/audio/codec/` (WAV),
  `lib/core/audio/lifecycle/` (`AudioSessionCoordinator`, ADR 0056,
  `isBackgroundLifecycleState` — `paused|hidden|detached`, az `inactive`
  **NEM**), `lib/core/foundation/` (`AppResult`, `AppFailure`,
  `json_validation.dart`), `lib/core/storage/`.
- **Storage:** `ss.` névtér a `storage_keys.dart`-ban, kulcs helyben SOHA nem
  írható át; a file-alapú tárolás bizonyított mintája a
  `lib/features/song_trainer/data/local/atomic_file_writer.dart` — **követni**
  kell, nem importálni (cross-feature határ).
- **Domain purity:** `lib/features/*/domain/` framework-mentes; a cross-feature
  import csak `public.dart`-on át.
- **Gate:** `tools/round-gate.sh <érintett test-útvonalak>` — egyetlen lokális
  záró gate, külön processz format/analyze/test/architecture, nincs `&&`/pipe;
  full suite + property + APK CI = orchestrátor exact-SHA dispatch.
- **`native_gate = false` minden körben:** ezen a boxon nincs Android SDK; a
  natív fordítás bizonyítéka a CI `build-apk.yml` futása.
- **Riverpod 3.3.2:** `AsyncValue` `.value` (nullable), **nem** `.valueOrNull`.
