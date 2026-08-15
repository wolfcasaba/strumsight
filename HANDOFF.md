# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-15
> (E07-R05 merged as PR #274: privacy-safe SkillEvidence normalisation and
> in-memory evidence repository are now on `main`.)**

> ## ✅ E07-R05 KÉSZ — SkillEvidence normalizálás és evidence repository
>
> PR [#274](https://github.com/wolfcasaba/strumsight/pull/274), squash
> `36298ac5`. A `SkillEvidence` csak származtatott mérőszámot, provenance-t és
> strukturált discomfort-kategóriát tartalmaz; a self-report szabad szövege
> tranzitív bemenet, a repository, a log és az exportolható modell előtt
> eldobódik. Outcome-ID deduplikáció, inkluzív expiry és bounded query kész.
> Review + security review APPROVED; a valódi A5-sértés próba négy cellát
> pirosra váltott. Exact-SHA `7e127217`: Full Gate
> [31907935245](https://github.com/wolfcasaba/strumsight/actions/runs/31907935245)
> + Router CI [31908569509](https://github.com/wolfcasaba/strumsight/actions/runs/31908569509)
> success. Egy CI-javítás csak a guard által tiltott komment-literált rewordolta.
>
> ## ✅ [HEAL E07-R04/H-NOSIGNAL] KÉSZ — a Codex `exec_command` korai „yield"-je után az orchestrátor újraindította a CI-várakozást ahelyett, hogy folytatta volna (2026-08-15)
>
> E07-R04 (Terra-orchesztrált) a kötelező `tools/wait-for-ci.sh 31902706136`
> CI-várakozó hívásnál H-NOSIGNAL-lal állt meg. A tmux pane-napló redraw-zaja
> miatt a valódi ok nem volt rekonstruálható belőle; a codex CLI SAJÁT
> strukturált rollout-JSONL-je
> (`~/.codex-terra/sessions/2026/08/15/rollout-2026-08-15T18-35-03-*.jsonl`)
> mutatta meg: a hívás az `exec_command`/`write_stdin` tool-interfészen
> HÁROMSZOR `"Script running with cell ID {94,96,98}"` választ kapott kb. 11
> másodpercnél (a kért `yield_time_ms` — 30000, majd 60000 — nem szabta meg
> ezt az időt), miközben a ténylegesen várt Full Gate futás 13 percig futott
> és zölden zárt (19:00:39→19:13:30Z). Az orchestrátor mindhárom alkalommal
> ÚJRA `exec_command`-ot hívott UGYANAZZAL a paranccsal ahelyett, hogy a
> kapott session/cellát folytatta volna — sosem olvasott valódi eredményt, a
> turn jelzés nélkül véget ért. Két közvetlen repró (`sleep 300`, egy
> `wait-for-ci.sh` alakú `gh` poll-ciklus) igazolta: nincs kemény
> kill-időkorlát — a modell máskor helyesen FOLYTATJA (resume) a yield-elt
> sessiont, csak a preambulum sosem mondta ki, hogy CI-várakozásnál pontosan
> ez a teendő.
>
> Javítás: `docs/execution/pipeline-codex-orchestrator-preamble.md` §2 új
> bullet — megnevezi a mért cella-választ, kimondja: yield után UGYANAZT a
> sessiont kérdezd le újra, SOSE indítsd újra magát a parancsot. Regressziós
> teszt `tools/tests/test_pipeline_codex_orchestrator_preamble.py` (RED a
> javítás előtt, GREEN utána); teljes `pytest tools/tests`: 442 passed, 438
> subtests, nincs regresszió. PR
> [#271](https://github.com/wolfcasaba/strumsight/pull/271), squash
> `769ed42d`, Router CI
> [31904279406](https://github.com/wolfcasaba/strumsight/actions/runs/31904279406)
> success az exact `38e5b11c` SHA-n (docs/tools-only, nincs Dart-változás,
> Full Gate nem releváns). Lecke: `docs/LESSONS.md` **L282**.
>
> **E07-R04 saját tartalmi munkája már merge-elve**: implementáció + 1
> javító kör (F1 — a sérült, hibás típusú `targetDate`/`metricTarget` többé
> nem válhat csendes `null`-lá), review APPROVED. A rebase-elt exact-SHA
> `864cf4ab` Full Gate és Router CI eredménye egyaránt success; PR
> [#272](https://github.com/wolfcasaba/strumsight/pull/272), squash
> `ac12b017`.
>
> ## ✅ E07-R03 KÉSZ — Goal, availability és learner-constraint domain (2026-08-15)
>
> SDD Ch8 Kör 3: `lib/features/practice_generator/domain/model/practice_goal.dart`
> (stabil kódú goal-type/priority/lifecycle enumok + `MetricTarget` +
> `PracticeGoal`, egyetlen engedélyezett lifecycle-átmenetgráf, normalizálatlan
> custom goal `isExecutable == false`), `weekly_availability.dart` (`LocalDate`
> — timezone-semleges helyi naptári nap, NEM `DateTime` —, naponta változó
> `DailyAvailability`, hard/soft napi maximum), `learner_constraints.dart`
> (equipment/tuning/capability/comfort/accessibility/preference/avoid
> kategóriák, a hard/soft keménység a kategóriától FÜGGETLEN mező — a
> `comfort` is lehet hard), `request_validator.dart` (pure konfliktus-detektor:
> hard sértés hiba, soft sértés költséges warning; nem javít, nem ütemez).
> ADR 0258 (hard korlát sosem sérthető, soft költséggel igen; napi hard
> maximum inkluzív, befelé kerekít; elérhetőség helyi dátumhoz kötött).
>
> Correctness review **APPROVED** (0 BLOCKER/MAJOR, 1 MINOR, 2 NOTE) — a
> reviewer a helyi gate-et saját izolált `/tmp` klónban 9/9 zölddel
> újrafuttatta, a `scope-audit.py`-jal mérve mind a 10 megváltozott útvonal az
> `allowed_paths`-on belül volt, és egy eldobható próbateszttel három, a kör
> saját négy tesztfájlában lefedetlen `RequestValidator`-ágat (elérhetetlen nap
> ütemezése, soft-maximum lineáris költsége, validátoron át futó
> `customGoalNotExecutable`) is lefuttatott — mind a három helyesen
> viselkedett (MINOR-1 follow-up, nem blokkoló). `risk = "normal"`, dedikált
> security review nem volt kötelező.
>
> Exact-SHA `93ffe3f`: Full Gate
> [31900345340](https://github.com/wolfcasaba/strumsight/actions/runs/31900345340)
> + Router CI [31900353853](https://github.com/wolfcasaba/strumsight/actions/runs/31900353853)
> mindkettő success; squash-merge PR
> [#270](https://github.com/wolfcasaba/strumsight/pull/270), `f7db0f00`. Egy
> párhuzamos batch-prep kör docs-only commitja (`ba834de8`) miatt a branch az
> első dispatch előtt rebase-elve lett; onnantól `origin/main` a merge-ig nem
> mozdult. A post-merge gate friss `main`-en önállóan újrafuttatva is zöld
> (9/9). Implementer **Terra (Codex)**, egy `done` dispatch, javító kör
> nélkül. `practice_generator` flagek változatlanul `false`, nulla hívó a
> `lib/`-ben a kör saját fájljain kívül.
>
> ## ✅ E07-R02 KÉSZ — Typed ID-k és stabil enum-kódok (2026-08-15, retroaktívan rögzítve)
>
> SDD Ch8 Kör 2: `domain/id/planner_ids.dart` (hat típusos ID —
> `PlanId`/`DayId`/`BlockId`/`GoalId`/`RevisionId`/`OutcomeId` —, mindegyik
> önálló `final class`, tehát a kereszt-típusú behelyettesítés fordítási
> hiba), `domain/model/plan_enums.dart` (öt stabil kódú enum-család:
> `PlanStatus`/`GenerationMode`/`BlockKind`/`ValidationSeverity`/
> `CandidateSource`, fail-loud `fromCode`). ADR 0257.
>
> Correctness review **APPROVED** (0 nyitott lelet) — ez a kör EGY javító
> kört kapott: az első review 2 MAJOR-t talált (a típusos ID-knek nem volt
> JSON round-trip szerződése; hiányzott az injektált ID-generálási seam), a
> `sonnet-impl` javító kör mindkettőt bezárta scope-tágítás nélkül
> (`toJson`/`fromJson`/`generate(String Function())` mind a hat ID-n, a
> validáció a rendes konstruktoron át fut), majd a reviewer friss izolált
> klónban a TELJES gate-et (format, analyze, 60 ID-teszt, 25 enum-teszt,
> architektúra, secrets, l10n) újra zöldre mérte. Az A6 valódi-sértés próba
> (az ismeretlen-kód hiba lecserélése csendes `values.first` fallback-re) az
> öt enum-család mindegyikén pirosra váltott, majd vissza lett állítva.
>
> Exact-SHA `8c6d13c0`: Full Gate
> [31898125573](https://github.com/wolfcasaba/strumsight/actions/runs/31898125573)
> + Router CI [31898243627](https://github.com/wolfcasaba/strumsight/actions/runs/31898243627)
> mindkettő success; squash-merge PR
> [#269](https://github.com/wolfcasaba/strumsight/pull/269), `5bb4f7d9`.
> Implementer **Claude Sonnet 5 (`sonnet-impl`)**, egy javító kör. Review:
> [`docs/reviews/e07-r02-review.md`](docs/reviews/e07-r02-review.md).

> ## 📦 Korábbi kör-narratívák → archívum
>
> A lezárt körök részletes története a
> [`docs/handoff-archive.md`](docs/handoff-archive.md) fájlban van.
> MIÉRT: ezt a fájlt MINDEN session és MINDEN kör elolvassa (orchestrátor +
> implementer), ezért a lezárt körök narratívája itt tiszta kontextus-adó.
>
> **Szabály (ADR 0175 §4):** a fejlécben a friss állapot és a **két legutóbbi**
> kör bannere marad; minden korábbi banner az archívumba kerül a kör lezárásakor.
> 2026-08-15 (E07-R03 zárása): az E07-R01 és az E99-R13 banner (utóbbi a
> saját self-heal jegyzeteivel együtt) archiválva; a fejlécben az E07-R03 és
> a retroaktívan pótolt E07-R02 banner marad.
> A korábbi diéta-bejegyzések teljes szövege: `docs/handoff-archive.md`.

## 1. Current release state

- **StrumSight** — offline, on-device guitar chord + strum-direction detector
  (Flutter, Dart SDK ^3.12.2, Material 3, Riverpod 3 hand-written providers).
- `pubspec` version: **1.0.0+1** (development). No production release yet —
  release signing is fail-closed via `release-apk.yml` (ADR 0062); a version
  bump / release is a separate user decision.
- Development APK per round from CI (`build-apk.yml`), artifact name
  `strumsight-<ver>-<build>-<sha>-development.apk` (ADR 0051).
- **Epic 1 (Core Platform) technikailag kész** — a zárókör (E01-R16) gépi
  gate-jei zöldek; a végső elfogadás a user valódi-eszközös §16.3/§16.4 menetén
  áll (HORIZON-szabály: synthetic green ≠ done). Evidencia:
  [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).
- **Epic 2 (Practice Engine) lezárva** — E02-R20 (epic-zárókör) kész; a
  Practice V2 domain és application réteg kimerítően tesztelt, a migrated
  Learn útvonal (`migratedLearnEnabled`) élesíthető. Az önálló Practice V2
  Hub→Setup→Session út production-drótozása **KÉSZ** (E02-R21, PR #55,
  `6e5cec7`) — a `practiceSessionHostProvider` élesben él, a §3
  rendszerszintű rés pótolva.
  Evidencia: [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md).
- **Epic 3 (Song Trainer) elkezdve** — E03-R01 (kickoff, baseline+ADR-ek+flag),
  E03-R02 (SongDocument V2 identitás/metaadat domain modell + codec),
  E03-R03 (section/measure struktúra + determinisztikus tempo/meter/key map +
  SongTimeMap), E03-R04 (track/event domain modell + monophonic elemzés),
  E03-R05 (validator/normalizer/capability resolver), E03-R06 (legacy
  Song/Setlist migrációs adapter) és E03-R07 (fájlrendszeres Song repository
  és asset store) kész. A modell flagek mögött, hívó UI/import-runner nincs
  — production viselkedés változatlan.
- **Epic 5 (Computer Vision) implementáció TELJES** — E05-R01…R30 mind
  merge-elve: capability audit + hat alapozó ADR, hand/pose landmark
  provider, guitar geometry, metric engine, feedback policy, session
  controller, audio–vision szinkron, observation fusion, posture safety,
  Practice/Song Trainer/AI Tutor/Analyze integráció, device tier + thermal
  hardening, és a záró minőségi kapuk (architektúra-guard, model-integritás,
  vision-off paritás, evaluation harness, completion report, rollout
  runbook). **Mind a 11 vision flag `false` marad minden környezetben** — a
  végső elfogadási kapu a user valódi-eszközös HORIZON-menete (§6 „Kötelező
  sorrend"), nem a technikai készenlét. Evidencia:
  [`docs/sdd/epic-05-completion-report.md`](docs/sdd/epic-05-completion-report.md).
- **Epic 6 (Audio Analysis 2.0) elkezdve** — E06-R01 (kickoff: V1 baseline
  mérés + hat kötött ADR: [0215](docs/adr/0215-analysis-document-versioning.md)–[0220](docs/adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)),
  E06-R02 (`lib/features/audio_analysis/domain/` — verziózott,
  immutable V2 domainmodell, 14 fájl + `public.dart` barrel; 1 MINOR
  security follow-up nyitva), E06-R03 (`lib/features/audio_analysis/data/`
  — determinisztikus `AnalysisDocumentCodec` + `LegacyAnalyzeAdapter`/
  `LegacyViewAdapter` veszteségmentes V1↔V2 migráció, [ADR
  0221](docs/adr/0221-legacy-analysis-v2-migration-mapping.md); 1 MINOR
  follow-up R21-re), E06-R04 (`lib/features/audio_analysis/engine/` +
  `domain/analysis_progress.dart` — moduláris, megszakítható,
  progresszt publikáló pipeline-szerződés fake stage-ekkel, konkrét DSP
  nélkül; 1 MINOR follow-up kötelező R07 pre-flight ellenőrzéssel),
  E06-R05 (`lib/features/audio_analysis/data/input/` +
  `domain/analysis_input.dart` — közös, validált input-boundary a
  mikrofonos és importált audio köré, [ADR
  0217](docs/adr/0217-analysis-raw-audio-retention.md) végrehajtása,
  bounds-safe `WavDecoderAdapter` a bitre változatlan core dekóder körül),
  E06-R06 (`lib/features/audio_analysis/data/capture/` +
  `domain/recording_level.dart` — V2 `AnalysisRecorder`, run ID-alapú
  stale-chunk szűrés, inkluzív maximum kliphossz nem-hibás lezárással,
  öt cellás lifecycle-mátrix, olcsó peak/RMS + hysteresises
  clipping-preview, a meglévő `MicCapture`/`AudioSessionCoordinator`
  (ADR 0056) kompozíciójával, `ClipRecorder` érintése nélkül; a 2 nem
  blokkoló MINOR follow-up (F2/S3/S4) az R07 pre-flightban ÉRTÉKELVE, de
  NYITVA marad — a köztes-chunk preview-hiány a valós idejű `RecordingLevel`
  korlátja, nem az R07 offline stage-jéé, ld. §3) és **E06-R07**
  (`lib/features/audio_analysis/engine/quality/` — determinisztikus,
  verziózott jelminőség-riport: `SignalQualityMath`/`QualityThresholds`/
  `SignalQualityStage`, [ADR
  0224](docs/adr/0224-signal-quality-stage-measurement-boundary.md), a
  riport a felvételről szól, sosem a játékról; `dsp_config.dart` bitre
  változatlan; bekötetlen), **E06-R08** (preprocessing/resampling policy,
  [ADR 0225](docs/adr/0225-analysis-preprocessing-and-resampling-policy.md)),
  **E06-R09** (V1 `ClipAnalyzer` stage-adapter és parity, [ADR
  0226](docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md))
  **E06-R10** (event evidence modell + onset/strum timeline builder,
  [ADR 0228](docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md))
  **E06-R11** (chord frame evidence, verziózott V1-paritásos szegmens-
  összeállítás + DSP-primary/ML-advisory decoder-provenance flag mögött,
  [ADR 0229](docs/adr/0229-analysis-chord-decoder-fusion-strategy.md)),
  **E06-R12** (beat grid + tempo curve, target-first becslő,
  [ADR 0230](docs/adr/0230-beat-grid-tempo-curve-boundary.md)) és
  **E06-R13** (target alignment engine — monoton, sávos DP-illesztő +
  tempófüggő tolerancia-policy, [ADR
  0231](docs/adr/0231-target-alignment-engine-boundary.md)),
  **E06-R14** (target/free-play timing- és rush/drag-metrikák, release-safe
  `MetricGate`, [ADR
  0232](docs/adr/0232-timing-metric-identity-and-publication-boundary.md))
  **E06-R15** (rhythm consistency + groove-proxyk — IOI-konzisztencia,
  subdivision-illesztés, target-only swing, [ADR
  0233](docs/adr/0233-rhythm-consistency-and-groove-proxy-boundary.md)),
  **E06-R16** (dynamics + stroke balance — attack-strength/local-RMS/
  dinamikai tartomány/accent-balance, release-safe `DynamicsGate`, [ADR
  0234](docs/adr/0234-dynamics-evidence-and-gating-boundary.md)) és
  **E06-R17** (monofonikus pitch capability — YIN-alapú frame→szegmens→
  capability-gate→hét metrika, [ADR
  0235](docs/adr/0235-monophonic-pitch-capability-boundary.md)),
  **E06-R18** (technique-proxy kísérleti modul — öt Lab-only, mérésre
  korlátozott proxy név/tartalom-tiltással, [ADR
  0236](docs/adr/0236-analysis-technique-proxy-safety-and-naming.md)) és
  **E06-R19** (confidence combiner + capability resolver — egyetlen döntési
  pont minden capability státuszára/kalibrált confidence-ére, geometriai
  kombináció, verziózott küszöbök és identity-kalibráció, [ADR
  0237](docs/adr/0237-analysis-confidence-combiner-and-capability-resolver.md))
  **E06-R20** (determinisztikus insight engine — kilenc evidence-backed
  coaching-szabály, maximum-policy ranker, hotspot ranker, [ADR
  0238](docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md)),
  **E06-R21** (fájl-alapú `AnalysisRepository` + legacy Library migráció,
  atomikus temp→verify→rename írás, rekord-szintű korrupció-karantén, [ADR
  0239](docs/adr/0239-analysis-document-storage.md)), **E06-R22**
  (analysis runner: 11-állapotos state machine, run-ID-alapú controller,
  futásonkénti isolate-futtató, pipeline-agnosztikus `T = AnalysisDocument`
  határ, [ADR 0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md)),
  **E06-R23** (overview screen + metric cardok, ötállapotú metric card,
  insight-/signal-quality card, [ADR
  0241](docs/adr/0241-analysis-overview-presentation-boundary.md)) és
  **E06-R24** (többrétegű, zoomolható timeline — nyolc capability-vezérelt
  lane, tiszta `TimelineViewport`, adaptív ruler, hotspot-navigátor,
  virtualizáció, [ADR
  0243](docs/adr/0243-analysis-timeline-lane-data-source-and-degraded-boundary.md)),
  **E06-R25** (session-összehasonlítás és fejlődési trend,
  `CompatibilityEvaluator`/`TrendBuilder`, [ADR
  0246](docs/adr/0246-analysis-session-comparison-and-trend-contract.md)) és
  **E06-R26** (Practice/Song/Tutor/Progress integrációs adapterek
  kizárólag publikus barreleken át, redaktált Tutor-snapshot, egyszeri
  progress-kreditálás — új ADR nincs, ADR 0176/0132/0141/0202 végrehajtása),
  **E06-R27** (export/share/privacy: allowlist-alapú `RedactionPolicy`,
  `AnalysisExportCodec`, `ShareCardBuilder`, `ExportAnalysisUseCase`,
  `DeleteAnalysisUseCase`, [ADR 0247](docs/adr/0247-analysis-export-share-and-delete-contract.md))
  **E06-R28** (cache, performance és model-lifecycle infrastruktúra —
  `AnalysisCacheKey`/`AudioFingerprint`/`AnalysisCache`/`ModelByteCache`,
  bekötetlen, [ADR 0248](docs/adr/0248-analysis-cache-key-and-performance-budget.md))
  és **E06-R30** (shadow rollout, migráció, Epic-lezárás — ZÁRÓ KÖR:
  `AnalysisRolloutStage`/`ShadowAnalysisRunner`/`ShadowDiffReport`, teljes
  50-session migrációs+rollback teszt, 29 ADR státusz-frissítés,
  [`docs/sdd/epic-06-completion-report.md`](docs/sdd/epic-06-completion-report.md))
  **kész — az Epic 6 mind a 30 köre lezárult.** A `docs/execution/pipeline-queue.tsv`
  minden sora `done`, a rollout shadow szinten marad, a folytatás
  (valódi kalibráció/GOV-30a, CI evaluation wiring/GOV-30b, V2 pipeline
  összeszerelés/GOV-30c, opt-in/V1-kivezetés) emberi döntést igényel, lásd
  §6. **`audioAnalysisV2Enabled`
  (+ al-flagek) `false` marad minden környezetben a teljes Epic alatt** (ADR
  0220) — a V1 Analyze marad a shipping út, production viselkedés bitre
  változatlan (a V2 domain + a codec/adapter/input-gateway/recorder teljesen
  bekötetlen). Evidencia:
  [`docs/baseline/epic-06-audio-analysis-start.md`](docs/baseline/epic-06-audio-analysis-start.md),
  [`docs/reviews/e06-r06-recorder-audio-session-integration-review.md`](docs/reviews/e06-r06-recorder-audio-session-integration-review.md).
- **Epic 7 (AI Practice Generator) elkezdve** — **E07-R01** (nyitókör:
  baseline, [ADR 0255](docs/adr/0255-deterministic-first-practice-planning.md)
  deterministic-first, [ADR 0256](docs/adr/0256-practice-plan-revisions-immutable-past.md)
  immutable múlt, `practiceGeneratorEnabled` + `plannerAssistEnabled` feature
  flag), **E07-R02** (`domain/id/planner_ids.dart` — hat típusos ID —,
  `domain/model/plan_enums.dart` — öt stabil kódú enum-család —,
  [ADR 0257](docs/adr/0257-planner-typed-ids-and-stable-enum-codes.md)) és
  **E07-R03** (`domain/model/practice_goal.dart` — cél, metric target, goal
  lifecycle —, `domain/model/weekly_availability.dart` — `LocalDate`-alapú
  napi elérhetőség —, `domain/model/learner_constraints.dart` — hard/soft
  korlátok, a keménység a kategóriától független mező —,
  `domain/service/request_validator.dart` — pure konfliktus-detektor —,
  [ADR 0258](docs/adr/0258-hard-and-soft-planning-constraints.md)) kész.
  **Mindkét flag `false` marad minden környezetben**, nulla
  `lib/features/practice_generator/` hívó a domain rétegen kívül — mindhárom
  kör kizárólag a határokat és a típusos domaint rögzítette. SDD forrás:
  [`docs/sdd/08-epic-07-ai-practice-generator.md`](docs/sdd/08-epic-07-ai-practice-generator.md).
  A generátor a legacy Learn/Progress/Songs/Analyze adaptereken keresztül lát
  (az Audio Analysis V2 lánc futtatható, de minden flagje OFF — a generátor
  domainje **nem** igazodhat az ideiglenes adapterhez, SDD Ch8 §4.3).

## 2. What is working

- **SongDocument V2 identitás/metaadat (E03-R02, ADR 0089 §Döntés 2/3):**
  `lib/features/song_trainer/domain/models/` — hat típusos ID (`SongId`,
  `SongSectionId`, `SongTrackId`, `SongEventId`, `SongAssetId`,
  `SongMarkerId`) közös `SongIdValidator`-ral (trim/nem-üres/≤128
  karakter/determinisztikus `safeFilename`); `SongMetadata` (cím kötelező,
  capo 0–15, dedup+lowercase tag-lista, immutable); `SongSource`
  (proveniencia: 7 stabil forrás-típus, SHA-256, importer-verzió,
  warning-summary); `SongAssetReference`, `SongMarker`; a minimális
  `SongDocument` identitás-vázlat (`schemaVersion`/`id`/`revision`/
  `metadata`/`source`/`assets`/`markers`/`createdAt`/`updatedAt` —
  section/track/tempoMap E03-R03-ban bővíti). `data/local/
  song_document_codec.dart` — determinisztikus kulcssorrendű UTF-8 JSON,
  UTC ISO-8601 timestamp policy, ismeretlen source type fail-closed.
  Framework-/Riverpod-/storage-mentes (`Domain purity` teszt-scanner őrzi,
  reviewer-oldali valódi-sértés próbával verifikálva). Hívó UI/repository
  még nincs — production viselkedés változatlan.
- **Songstruktúra és determinisztikus időmodell (E03-R03, ADR 0093):**
  `lib/features/song_trainer/domain/models/` — `SongSection` (kind-enum,
  measure-range validáció), `SongMeasure` (index/durationBeats/pickup/
  repeat-mezők); `TempoMap`/`MeterMap`/`KeyMap` **lokális, tick-alapú**
  idő-primitívekkel (a Practice Engine `BeatPosition`/`Tempo`/`Meter`
  importja a domain-purity scanner és ADR 0092 miatt kizárva — csak a
  tervezési elvek öröklődnek, a típusok nem). `domain/services/
  song_time_map.dart` — 480 PPQ tick, szegmensenkénti egész-mikroszekundum
  összegzés egyetlen kerekítési ponttal, **≤1 tick round-trip tolerancia**
  (500 rendezett, seedelt property-mintán mérve), left-closed tempo/meter
  boundary policy (reviewer-oldali mutáció-tesztelt próbával verifikálva),
  speed-multiplier a forrás mapet nem mutálja. `SongDocument` (R02) bekötve
  az öt új mezővel, **value-equal** `operator==`/`hashCode`-dal minden
  strukturális mezőn (a review F1 MAJOR leletének javítása). Hívó UI/
  repository még nincs — production viselkedés változatlan.
- **Track/event domain modell és monophonic elemzés (E03-R04, ADR 0113):**
  `lib/features/song_trainer/domain/models/` — sealed `SongTrack`
  (`ChordTrack`/`StrumTrack`/`NoteTrack`/`LyricsTrack`/`MarkerTrack`/
  `BackingAudioTrack`) + sealed-szerű event-készlet (`SongChordEvent`
  core `Chord` szimbólummal, `SongStrumEvent` nullable core
  `StrumDirection?` iránnyal — `null` = unknown, `SongNoteEvent` MIDI
  pitch/string/fret/velocity validációval, `SongLyricEvent`,
  `SongMarkerEvent`); `SongInstrument` (opcionális core `Tuning` — az
  EGYETLEN canonical tuning contract); `SongNoteTechnique` (8 ismert
  technika + `unknown` raw/display escape hatch, sosem ad hamis scoring
  capabilityt). `domain/services/note_track_analyzer.dart` —
  `NoteTrackAnalyzer` **active-notes sweep-line**-nal (nem
  adjacent-pair-only — ez volt a review BLOCKER leletének gyökere, ld. §5)
  határozza meg az overlap/tie/monophonic reportot. Codec bővítés
  kanonikus (start asc → track id → event id) sorrenddel és fail-loud
  ismeretlen-altípus kezeléssel (`trackTypeUnknown`/`eventTypeUnknown`).
  `SongDocument.tracks` mező bekötve. Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Validator, normalizer és capability resolver (E03-R05, ADR 0114):**
  `lib/features/song_trainer/domain/services/` — `SongValidator`
  (cross-collection ellenőrzés: section range vs. `measures.length`,
  section-overlap, `StrumEvent.targetChordId` cél-hivatkozás — sorrend-
  független két lépéses gyűjtés+validálás, ld. §5 review-tanulság —,
  ismeretlen chord-root/technique/strum-direction, `NoteTrackAnalyzer`
  polyphony-reuse; sosem dob, mindig `SongValidationReport`-ot ad
  determinisztikus `severity asc, code asc` sorrenddel), `SongNormalizer`
  (idempotens: `normalize(normalize(x)) == normalize(x)`, kanonikus
  `(kind, id)`/`(start, id)` rendezés minden track/event típusra, ID-t
  soha nem ír át), `SongCapabilityResolver` (severity→capability
  szerződés: `fatal` ⇒ minden profil — importPreview/persist/trainer/
  export — `canPersist=false`; chord/pitch display/scoring ÖNÁLLÓ
  tengely a severity-től, a §6 négy kombináció mind reprezentálható).
  Chord-support grammar önálló, domain-lokális (`Root[m?]`), sosem a
  `practice`-feature szótára (ADR 0114 §Döntés 1 — cross-feature import
  + kívül esik az `allowed_paths`-on). Hívó UI/repository még nincs —
  production viselkedés változatlan.
- **Legacy Song/Setlist migrációs adapter (E03-R06, ADR 0116):**
  `lib/features/song_trainer/data/migration/` — `LegacySongReader` (JSON
  DTO boundary, `LegacySongRecord`/`LegacySetlistRecord`, kanonikus
  SHA-256, nincs presentation import), `LegacySongAdapter` (legacy
  `Song` record → `SongDocument`: `ChordTrack`+`StrumTrack`+egy
  `SongSectionKind.custom` „Full Song" section, egyetlen mikroszekundum-
  kerekítési pont eseményenként, `Meter` denominator mindig 4),
  `LegacySetlistAdapter` (sorrend/duplikáció megőrzés, missing id →
  unresolved report, nincs crash), `LegacyMigrationReport` (önálló,
  adapter-lokális fidelity report — NEM a `SongValidationReport`/
  `ImportWarning` kiterjesztése, ADR 0116 §Döntés 1). Veszteségmentes,
  determinisztikus, tartós írás vagy legacy törlés nélkül. Hívó
  UI/migration-runner még nincs — production viselkedés változatlan.
- **Fájlrendszeres Song repository és asset store (E03-R07, ADR 0090):**
  `lib/features/song_trainer/domain/repositories/` — `SongRepository`
  (`list`/`get`/`create`/`update`/`moveToTrash`/`restore`/
  `permanentlyDelete`, optimistic `expectedRevision`), `SongAssetRepository`
  (`put`/`get`/`summary`/`incrementReference`/`decrementReference`/
  `permanentlyDelete`). `data/local/` — `FileSongRepository` (validate→
  temp-serialize→flush→verify→atomic document rename→temp index→atomic
  index rename, `SongValidator`/`SongCapabilityResolver` a mentés előtt),
  `FileSongAssetRepository` (streamelt SHA-256 content-hash store,
  reference count, korrupt sidecar/asset stabil hibakóddal, sosem néma
  playback), `AtomicFileWriter` (temp/flush/verify/rename, staging a
  songs-root `temp/` alatt, előzetes törlés nélküli atomikus rename),
  `SongRepositoryRecovery` (nem-destruktív startup scan: orphan temp,
  orphan document, corrupt index, orphan asset), `InMemorySongRepository`
  (fake). `application/song_trainer_providers.dart` — éles Riverpod
  wiring `path_provider.getApplicationSupportDirectory()` felett
  (tranzitív import, ugyanaz a precedens, mint az E03-R06 `crypto`
  használata). Nincs `SongDocument`/asset SharedPreferences-ben. Három
  független review pass + két javító kör után **APPROVED**
  ([`docs/reviews/e03-r07-song-repository-asset-store-review.md`](docs/reviews/e03-r07-song-repository-asset-store-review.md)) —
  a második pass egy, a saját első javító kör bevezette regressziót
  talált (streamelt-hash `writeFromSync` length/end-index csere,
  `docs/LESSONS.md` L60), amit az orchestrátor javított (implementer-oldal
  mérve nem elérhető: M3 kerete + Terra napi kerete egyaránt kimerült).
  Hívó UI/import-runner még nincs — production viselkedés változatlan.
- **Detektálás (100% on-device):** Live képernyő (akkord + pengetésirány valós
  időben, DSP + CRNN ML), Analyze (felvett klip elemzése), Tuner, metronóm.
  DSP-igazság: `docs/rag/chunks/` — paraméter csak ADR-rel és ugyanabban a
  commitban frissített chunkkal változhat (AGENTS.md §9).
- **Tanulás/tartalom:** Learn (leckék), Songs, Library (sessionök), Progress,
  Streak, onboarding, i18n (en/hu ARB).
- **Opcionális account-réteg:** FastAPI + SQLite + JWT backend (`backend/`),
  login + settings-sync; **az app kijelentkezve teljes értékű**, a 0-request
  offline-garanciát rendszer-szintű teszt őrzi
  (`test/app/offline_network_guard_test.dart`, E01-R16).
- **Core platform (Epic 1):** validált fail-closed AppConfig-bootstrap ·
  `AppResult`/`AppFailure` + redakciós logging · verziózott storage
  (migrátor + karanténos JSON-dokumentumok) · egyetlen `DioFactory`, 401
  session-generációs invalidáció, POST-retry-tilalom · exkluzív mikrofon-session
  (owner+lease, lifecycle guard, ADR 0056) · közös zenei/audio domain
  (`core/music`, `core/audio`, ADR 0057/0058) · route-katalógus + idempotens
  onboarding-redirect (ADR 0059) · Alembic-backend health-endpointokkal és
  prod-hardeninggel (ADR 0060/0061).
- **CI:** `build-apk.yml` + `release-apk.yml` közös gate-sorral
  (`.github/actions/flutter-gates`: format → analyze → architecture → asset →
  test → randomizált property), coverage külön párhuzamos required jobban;
  `backend-ci.yml` (ruff + pytest + alembic-gate); fail-closed release signing.
  ADR 0062/0063 + E01-R16.
- **Practice V2 parity-mérce (E02-R01):** `test/support/practice_baseline_scenarios.dart`
  (10 scorer-semleges forgatókönyv) + `test/fixtures/practice/legacy_scorer_baseline.json`
  (befagyasztott golden, event-szintű verdictekkel). A replay független legacy
  matchert vezet a scorer mellett; a golden regenerálása csak
  `UPDATE_LEGACY_SCORER_BASELINE=1`-gyel, megnevezett okkal (ADR 0067 §1/§3).
- **Practice V2 domain időalap (E02-R02):** `lib/features/practice/domain/model/`
  — `BeatPosition` (480 PPQ integer tick, ADR 0066; egzakt subdivision-factoryk,
  egyetlen auditált legacy `double beat` híd ≤ 1/960 beat toleranciával),
  `Tempo` (30–300 BPM zárt tartomány, clamp nélküli lista-validáció), `Meter`
  (4/4·3/4·6/8, egzakt `ticksPerBar`), stabil validációs kódkészlet. A
  `lib/features/practice/domain/` prefix framework-independence-e GÉPI őr alatt
  (`tool/check_architecture.dart`). Hívója még nincs — production viselkedés
  változatlan.
- **Practice V2 domain-szerződések (E02-R03, ADR 0068):** a teljes modellkészlet
  a `lib/features/practice/domain/model/` alatt — `PracticeEvent`/`PracticeDefinition`
  (kanonikus sharp-spelled chord-labelkészlet, rendezettség/egyediség/tartomány
  aggregáló validációval), `PracticeSessionConfig`, sealed observation-hierarchia,
  `PracticeVerdict` (+TimingGrade/outcome/coaching kódok), `MetricValue`/`PracticeMetrics`,
  attempt/session result (+`PracticeFinishReason`), `ScoringProfile`
  (integer-percent súlyok, összeg=100; `perfect<=good<=match` ablak-rendezés;
  `legacyLearnParity` const profil), mode/source/difficulty enumok stabil
  `code`+fallback-mentes `fromCode` párral — összesen 60 stabil validációs kód,
  mind literálisan tesztelve. `Meter.ticksPerBar` szimmetrikus fail-fast
  (E02-R02 MINOR-1 zárva). Test-oldali purity-őr (`domain_purity_test.dart`).
  Hívó továbbra sincs — production viselkedés változatlan, flagek OFF.

- **Practice V2 accessibility-mátrix és performance-számlálók (E02-R20, nincs új ADR — a zárókör nem hoz architekturális döntést):**
  `test/features/practice/presentation/practice_a11y_audit_test.dart` (A1.1–A1.10) — Hub/Setup/Result képernyőkön a touch-target + label+action + 200%-os szöveg + landscape + reduced motion + chart-szemantika + screen reader + ARB-paritás cellák zöldek, a `_HubCard` / `PracticeModeCard` / `PracticePatternPreview` / `TimingBiasChart` Semantics-merge fixekkel; `test/features/practice/practice_performance_test.dart` (A3) — R14 highway számláló, R09 matcher számlálók, 10 perces szimulált session cap, controller state-emission cap; `practice_a11y_audit_test.dart` A2.1–A2.4 cellái (A2) — minden `PracticeInsightCode` / `PracticeRecommendationKind` értékhez ARB-szöveg mindkét nyelven (a R20-ban hozzáadott 16 kulcs: `practiceInsight*` × 10 + `practiceRecommendation*` × 6; a javító kör #1 az eredetileg különálló `practice_l10n_audit_test.dart`-ot ide olvasztotta, scope-okból); `test/property/practice_engine_property_test.dart` (A4) — öt epic-szintű invariáns (egy target/observation max egyszer, score ∈ [0,1] ∨ NotApplicable, free practice nincs overall accuracy, terminal state tiszta, playing ≤ active ≤ wall). A §3 rendszerszintű rés (önálló Practice V2 session-út drótozatlan) nyíltan dokumentálva a §5 DoD-táblában minden érintett cellánál.

- **Practice V2 tartalom (E02-R04, ADR 0070):** `lib/features/practice/data/`
  `BuiltinPracticeCatalog` — tíz beépített gyakorlat (négy/nyolcad strum-minták,
  folk pattern, G↔D és Em↔C akkordváltás, C-G-Am-F progresszió, 3/4 keringő,
  szinkópált upstroke-ok, rhythm-only, free-practice sablon) stabil
  `builtin.<slug>.v1` ID-kkel, unmodifiable `events`/`const skillTags`
  listákkal; `domain/repository/practice_catalog_repository.dart` szinkron
  szerződés; `application/practice_catalog_controller.dart` két Riverpod
  providerrel. Hívó UI még nincs, ARB-fordítás az első UI-hívóval jön.
- **Practice V2 legacy adapterek (E02-R05, ADR 0071):**
  `lib/features/practice/data/adapters/` — `practiceDefinitionFromLesson`
  (+`easy:`), `…FromSong`, `…FromAnalyze`, `…FromDailyChallenge`: tiszta,
  óra-mentes függvények `AppResult<PracticeDefinition>`-nel (sosem dobnak,
  hibakód `practice.content_unsupported`). Minden adaptált tartalom
  `strumPattern` + befagyasztott `legacyLearnParity` (kivétel: az eseménymentes
  Analyze-import → `freePractice`). `legacyPracticeChordLabel` a legacy
  akkordcímkéket a detektor tényleges 24-elemű maj/min szótárára redukálja
  (`Em7`→`Em`, `Bb`→`A#`, `G/B`→`G`, értelmezhetetlen → strum-only) —
  veszteséges, de nem parity-rontó (ADR 0071 §2).
  `PracticeDefinition.displayTitle` a user-tartalom nevének (61 stabil
  validációs kód). Songs feature-barrel: `lib/features/songs/public.dart`.
  A legacy API (`Lesson`, `Song.toLesson()`, `Lessons.fromAnalyze`,
  `LessonScorer`) érintetlen; hívó UI nincs.
- **Practice V2 időréteg (E02-R06, ADR 0072):**
  `lib/features/practice/domain/model/beat_time_converter.dart` — a domain
  **egyetlen** beat↔idő konverziója (egész µs, egyszeri kerekítés, fail-fast) ·
  `compiled_practice_target.dart` (4 immutable, value-equal modell) ·
  `domain/service/practice_target_compiler.dart` — determinisztikus
  session-timeline count-innal, egész ütemű pass-hosszal, loop-rebase-szel,
  ütemhatárokkal, expected-chord szegmensekkel és scoring applicabilityvel.
  **ADR 0072 §1.1 az egész epic időmodellje:** minden abszolút pillanat a
  nullponttól vett tickszám egyetlen konverziója, minden időtartam két pillanat
  különbsége — így a kompozíció pontos ÉS minden pillanat bitre egyezik a legacy
  képlettel. Parity a szállított korpuszon: **0 µs**. Hívó UI nincs.
- **Practice V2 observation gateway (E02-R08, ADR 0074):** a Live detektor és a
  Practice domain közötti híd. `application/practice_observation_gateway.dart`
  (SDD §13.1 interfész + `PracticeObservationConfig`: 0.55 / 0.60 / 180 ms /
  500 ms) · **`application/practice_observation_activation.dart` — a
  `practiceCaptureActiveByStatus` `const` tábla mind a 11 státuszra**, ez a
  „hallgat-e a mikrofon" EGYETLEN igazságforrása (`countIn` + `running` → be,
  minden más → ki; a `paused → false` a chunk 014 pause-résének szerkezeti
  lezárása a V2 úton), a kulcshalmaz-egyezés gépi őr alatt ·
  `data/live_practice_observation_gateway.dart` — `strumSeq`-dedup, engine-óra
  de-jitter a legacy **szigorú `<`** predikátumával (a kalibrált input latency
  a matcheré marad, ADR 0074 §3), **fajtánként külön** monoton padló, saját sűrű
  `sequence` (§12.5 baseline), change-point + stabilitási chord-mintavétel,
  engedély-elsőség, idempotens start/stop/dispose, hibaleképezés. Fake gateway a
  `test/support/` alatt az R09/R10 számára. Hívó és provider nincs, flagek OFF →
  production viselkedés bitre azonos.
- **Practice V2 event matcher (E02-R09, ADR 0075):**
  `domain/service/practice_event_matcher.dart` — pure, determinisztikus,
  **kurzoralapú** párosító: eldönti, melyik `StrumObservation` melyik
  `CompiledTargetEvent`-hez tartozik, és mikor zárul egy cél kimaradásként.
  Pontozás-mentes (`TimingGrade`/score/combo a Kör 10-é), **megfigyelést nem
  tárol** (`O(célesemény)` memória), az opcionális célt külön feloldással zárja.
  A legacy `LessonScorer` szemantikája (P1–P9) megőrizve: jogosultság `<=`,
  zárás **szigorú `<`**, holtversenynél a **korábbi**, a rossz irány is
  **elfogyasztja** a célt, az extra pengetés **állapotot nem változtat**.
  **A paritás értelmezési tartománya kimondva (ADR 0075 §2b):** a legacy
  kerekítetlen `double`-lel dönt, a compiled target egész µs-mal, ezért a két
  időalap ≤ **0,5 µs**-ban eltér (mérve **0,489795919508 µs** mind a 348
  szállított eseményen) — a **µs-kvantált alap az igazság**, és a levezetett
  védősávon kívül (`≥ 1 µs` a határoktól, `≥ 2 µs` argmin-különbség) a paritás
  **bitre egzakt**, tűrés nélkül. A sávon belüli két divergencia-cella
  (`first-strums[0]`, `anthem-drive[5,6]`) **kipinnelt, őrzött viselkedés**.
  Hívó, provider és flag nincs → production viselkedés bitre azonos.
- **Kétmotoros implementer-készlet (ADR 0069):** `tools/mm-round.sh` +
  `tools/mm-watch.sh` (5 perces korai riasztás) + `tools/mm-trace.py`
  (munkastílus-elemzés) — a MiniMax M3 ugyanazt a kör-jelzés-szerződést
  használja, mint a Codex. Besorolás és a kötelező brief-elemek: AGENTS.md §15.6.

- **Practice V2 pontozás (E02-R10, ADR 0076):** `lib/features/practice/domain/service/`
  — `PracticeTimingScorer` (grade + eseménypont + `meanAbsoluteOffset`/előjeles
  `timingBias`), `PracticeDirectionScorer` (explicit megfigyelés-bemenet,
  fail-fast hiányzó leképezésre), `PracticeChordScorer` (inkluzív
  `[−120 ms, +420 ms]` ablak, `correct`/`wrong`/`noDetection`/`insufficientData`/
  `notApplicable`), `PracticeScoreAggregator` (overall csak az **elérhető**
  dimenziókra, completion + kettős pass-kapu, legacy combo/pont). Minden pontszám
  belül **egész ezrelék**, kifelé `perMille / 1000` — lebegőpontos akkumuláció
  tilos. `PracticeMetricReasonCode` stabil indokkód-készlet; `ChordOutcome`
  ötértékű. **Legacy paritás 51 forgatókönyvön egzakt** (17 lecke × 3 latency,
  nulla kizárt esemény). Hívó nincs → production viselkedés változatlan.

- **Practice V2 result + coaching + history (E02-R18, ADR 0084):** mode-specifikus
  **result képernyő** (`presentation/screens/practice_result_screen.dart` +
  `score_breakdown`/`timing_bias_chart`): csak az **alkalmazható** dimenziók
  látszanak (`MetricNotApplicable` → a blokk nincs a fában; `MetricInsufficientData`
  → lokalizált „nincs elég adat", **nem** 0%); Free Practice külön layout (nincs
  overall/pass-fail/combo). **`PracticeCoach`** pure service
  (`domain/service/practice_coach.dart`): mérésből választott, **bizonyíték-küszöbös**
  insight-kódok (`practice_insight.dart`), determinisztikus prioritás (SDD §17.3),
  legalább egy pozitív insight befejezett sessionre. **Practice History V2**
  (`data/local_practice_history_repository.dart` + `practice_history_serializer.dart`
  + `practice_history_recorder.dart` + `..._mapper.dart`,
  `domain/model/practice_history_entry.dart` + `practice_metric_snapshot.dart`): új
  kulcs `ss.practice.history_v2` (`StorageKeys.all`-ban), verziózott dokumentum,
  karantén a sérült bájtoknak, jövőbeli `schemaVersion` kihagyva, cap
  `maxSessions=200`, a per-attempt **detail-window** csak a legújabb **N=20**
  sessionre, **idempotens** mentés a `sessionId`-re. **A mentési hiba nem néma:** a
  repository közvetlenül a `KeyValueStore`-ral ír (propagálja a `StorageException`-t)
  → `AppResult.failure` → a controller `ShowRecoverableError`-t emittál; a session
  sikeres marad. A V1 `ss.progress.practice_log` **bájtra érintetlen** (egyesítés =
  R19). A live recorder-wiring valós session-metaadatig (mode/source/definition)
  **R19-ig halasztva** (placeholder-metaadatnál `Noop`, hogy ne keletkezzen
  betölthetetlen — write-then-drop — rekord). Flag: `practiceDetailedHistoryEnabled`
  (non-prod ON) → részletes attempt-adat.

## 3. Known blockers / risks
- **E06-R28 cache — 6 lezárandó előfeltétel a jövőbeli BEKÖTŐ körnek, nincs
  kijelölt kör (mérve, `docs/reviews/e06-r28-…-security.md` §6).** A cache-nek
  ma nulla production hívója van (`audioAnalysisV2Enabled` false), úgyhogy
  ezek NEM aktív hibák, csak a wiring-kör előtti kötelező hardening-lista:
  (1) explicit payload-tartalmi szerződés (nyers PCM sosem cache-elhető) +
  a cache-hely újraértékelése Android Auto Backup-jogosultság szempontjából
  (`getTemporaryDirectory()`/backup-kizárás `getApplicationSupportDirectory()`
  helyett); (2) `put()`/`getOrCompute()` ma kivételt propagál a hívóra
  filesystem-hibán (mérve `chmod 500`-zal) — az ADR Döntés 5 szellemével
  ellentétes; (3) a cache minden `*.json` fájlt sajátjának tekint a
  könyvtárában, mérve egy idegen `index.json` törlésével — fájlnév-mintaszűrő
  kell (`^[0-9a-f]{64}\.json$`); (4) `AudioFingerprint` némán clamp-el a
  `[-1,1]` tartományon kívül, ami két KÜLÖNBÖZŐ bemenetet azonos kulcsra
  képezhet — tartományon kívüli mintát el kell utasítani; (5) a mért
  baseline-számok (`docs/baseline/epic-06-analysis-performance.md`) 4 bájtos
  payloadról származnak, a cap közelében (50 MiB) a valós költség ~20×
  nagyobb (mérve: 609 ms + ~90 MiB tranziens allokáció egy `put()`-ra) —
  újramérés kell cap-közeli payloaddal, mielőtt bárki erre budget-döntést
  épít; (6) a `purge()` bekötése a törlési útvonalba (az R27
  `AnalysisCachePort`, `delete_analysis_use_case.dart:10-12`), hogy a
  `ss.analysis.cache` katalógus-bejegyzés valódi törölhetőséget takarjon.
  Content review 2 további MINOR-t is dokumentál (tautologikus
  fingerprint-névfüggetlenségi teszt; a handoff-próza tesztszám-elszámolási
  pontatlansága) — mindkettő dokumentációs, nem kódhiba.
- **E06-R20 follow-up (5 NOTE, review + security) — gate-feltételek egy
  jövőbeli bekötő körnek, nincs kijelölt kör.** (1) review N1: a
  `LowSignalQualityInsightRule` (`lib/features/audio_analysis/engine/insights/insight_rules.dart:268-297`)
  a `dynamics.clipped_event_ratio.v1`-et méri, nem a nyers
  `AnalysisDocument.signalQuality` (R07) riportot — mert az utóbbi nem
  katalogizált metrika, tehát nem használható `factId`-ként; ha egy
  jövőbeli kör a nyers jelminőséget is katalogizálja, érdemes megfontolni,
  hogy a szabály erre váltson-e. (2) review N2: a caller-supplied
  evidence-osztályok (`TimingInsightEvidence` stb.,
  `lib/features/audio_analysis/domain/insights/insight_rule.dart:164-234`)
  csak érték-tartományt validálnak, nem `CapabilityStatus`-t — a „csak
  megbízható mérésből" garancia a jövőbeli hívóra hárul, akinek ezt
  pre-flightban explicit ellenőriznie kell. (3) security NOTE-1 (**a
  bekötés ELŐTT megoldandó**, nem csak follow-up): a
  `ChordTransitionHotspotInsightRule` (`insight_rules.dart:259,261-263`)
  a `hotspot.id`-t verbátim messageArgba és egy action-payload kulcsba
  teszi; ma nincs élő harmony-kind hotspot-termelő, de egy jövőbeli
  decoder/import/sync útvonal szanitálatlan stringet hozhatna be. (4)
  security NOTE-2: a hotspot-alapú `factId`-eknek nincs `isUsable` őre
  (`insight_rules.dart:249`), a `CompatibleImprovementInsightRule`
  mintájára (`:313`) érdemes pótolni egy jövőbeli körben. (5) security
  NOTE-3/NOTE-4: a property-gate nem generál hotspotot (a
  `chord_transition_hotspot` útvonal kívül esik a randomizált mérésen), és
  a `HotspotRanker` duplikált ID esetén nem specifikált sorrendet ad (ma
  nincs élő duplikáció). Mérve:
  `docs/reviews/e06-r20-deterministic-insights-and-hotspots-review.md`
  N1/N2, `docs/reviews/e06-r20-deterministic-insights-and-hotspots-security.md`
  NOTE-1..4.
- **E06-R19 follow-up (F2 review + security NOTE-1) — gate-feltételek egy
  jövőbeli bekötő/kalibrációs körnek, nincs kijelölt kör.** (1) F2: a
  `CapabilityResolver.resolve()` (`lib/features/audio_analysis/engine/confidence/capability_resolver.dart:105-123`)
  a „kritikus capability → min" brief-elvet (§5.2) ma egy bináris hard-gate
  helyettesíti — bármelyik kritikus capability (`signalQuality`/
  `onsetTimeline`) `unavailable` állapota az overall confidence-t nullára
  kényszeríti (`overallStatus` mindig `unavailable`-re esik, sosem
  ténylegesen `degraded`-re), egy MERELY-`degraded` kritikus capability
  pedig csak egyetlen tényezőként hígul a geometriai átlagban a többi
  (akár 13) capabilityvel egyenlő súllyal. Nem sérti a §6 mérhető
  acceptance criteriont, de eltér a brief prózájától — egy jövőbeli
  bekötő/kalibrációs kör (R29 vagy a retrofit-kör) döntse el explicit
  módon, hogy a bináris kapu szándékos-e (ADR 0237 kiegészítéssel), vagy
  a fokozatos „min" viselkedés kell. (2) security NOTE-1: az
  `AnalysisDocument` codec (`lib/features/audio_analysis/data/analysis_document_codec.dart:180-195`,
  a diffen kívül, nem módosult) ma NEM perzisztálja az új
  `CapabilityReport.calibrationVersion`/`calibrationSource` mezőt — egy
  perzisztált-majd-visszatöltött report csendben `identity`-re esik vissza.
  Fail-safe irány (sosem a veszélyes raw→calibrated), de a source-enum
  megfigyelhetőségi célját kiüti perzisztált dokumentumoknál — E06-R29-nél
  a codec round-tripelje mindkét mezőt. Mérve:
  `docs/reviews/e06-r19-confidence-calibration-capability-resolver-review.md`
  F2, `docs/reviews/e06-r19-confidence-calibration-capability-resolver-security.md`
  NOTE-1.
- **E06-R17 security MINOR-1/NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli
  bekötő körnek, nincs kijelölt kör.** (1) MINOR-1:
  `buildPitchMetrics` (`lib/features/audio_analysis/engine/metrics/pitch_metrics.dart`)
  O(szegmens×célhang) — `_targetFor` szegmensenként az összes célhangot
  vizsgálja, `_dropoutRatio` célhangonként az összes szegmenst; mérve:
  8000 célhangra 619 ms, szuperlineáris görbe, ~15 s-ra extrapolál 40 000-re
  (ugyanaz a mérce, mint az E06-R11/E06-R15 precedens). MA elérhetetlen
  (0 fogyasztó, `analysisPitchEnabled=false` mindenhol) — egy jövőbeli
  untrusted/hosszú audióra kötő kör **MUST-fix-before** ezt egyetlen
  bejárásra/indexelésre kell váltania. (2) NOTE-1:
  `PitchCapabilityGate(minimumVoicedRatio: 0)` (nem a default 0.35) csupa
  unvoiced bemenettel `RangeError`-t dobna (`_median([])`) — a default
  biztonságos, csak a konstruktor nem zárja ki a `0` határértéket
  (`maximumPitchSpreadCents` mintájára `<= 0`-ra kellene szigorítani). (3)
  NOTE-2: az exportált `centsBetween` (`monophonic_pitch_segment_builder.dart`,
  `public.dart`-on át cross-feature elérhető) nem-pozitív Hz-re nem-véges
  eredményt adna — ma nincs ilyen belső hívó. Mérve:
  `docs/reviews/e06-r17-monophonic-pitch-capability-security.md`.
- **E06-R11 security NOTE-1/NOTE-2 — gate-feltételek egy jövőbeli bekötő
  körnek, nincs kijelölt kör.** (1) `ChordSegmentAssembler._mergeShortSegments`
  (`lib/features/audio_analysis/engine/harmony/chord_segment_assembler.dart`)
  `removeAt`-alapú O(S²) — mérve: 13 mp @ 40 000 szegmens, `minimumSegment`/
  `mergeTransientSegments` opt-in policy alatt. MA elérhetetlen (a default
  policy `minimumSegment=0` kihagyja ezt az ágat, és a feature bekötetlen) —
  de ha egy jövőbeli kör untrusted/hosszú importált audióra köti be pozitív
  merge-policyval, a security review explicit **MAJOR-ra sorolja át**: a
  merge-t egyetlen bejáráson épített új listával kell megvalósítani,
  `removeAt` nélkül, MIELŐTT a bekötés megtörténik. (2) `ChordSegment.id`
  (`lib/features/audio_analysis/domain/analysis_segment.dart`,
  `_defaultId`) a `label`-t szanitálás nélkül interpolálja
  (`'chord-${startUs}-${endUs}-$label'`) — ha egy jövőbeli hívó ezt fájlnévként/
  DB-kulcsként/log-sorként használja, és egy jövőbeli ML-decoder tetszőleges
  stringet ad `label`-ként, path-traversal- vagy injekció-alakú kulcs
  keletkezhet. Javítás a bekötés ELŐTT: a `label`-komponenst szanitálni/
  hash-elni az ID-ben, vagy dokumentálni, hogy az `id` nem biztonságos útként/
  kulcsként. Mérve: `docs/reviews/e06-r11-chord-evidence-segmentation-provenance-security.md`
  NOTE-1/NOTE-2.
- **E06-R06 F2/S3/S4 follow-up — NYITVA, nincs kijelölt kör.** A live
  level-preview (`RecordingLevel`, E06-R06) csak az éppen throttle-ablakot
  lezáró chunkot méri peak/RMS-re, a köztes chunkokét nem — egy rövid,
  hangos tranziens, ami teljesen egy köztes chunkba esik, nem jelenik meg a
  preview-n (a végleges, teljes PCM-puffer nem érintett). Az E06-R07
  pre-flightja értékelte és kimondta, hogy ez NEM az ő scope-ja (az offline,
  egyszer futó jelminőség-stage más költségszinten dolgozik, mint a valós
  idejű preview) — a follow-up így nyitva marad, jelenleg nincs hozzá
  kijelölt kör.
- **E06-R07 review NOTE-2 — R02 domain-report NaN-vak arány-guard, alacsony
  prioritás.** A meglévő (E06-R02, E06-R07 által NEM módosított)
  `SignalQualityReport` konstruktora (`lib/features/audio_analysis/domain/
  signal_quality_report.dart`) a `clippedSampleRatio`/`silentRatio` mezőkre
  csak `< 0 || > 1` ellenőrzést fut, `isFinite`-et nem — mivel `NaN < 0` és
  `NaN > 1` egyaránt hamis, egy `NaN` arány elméletileg megkerülné az őrt (a
  mai producerek sosem termelnek ilyet). Mérve és dokumentálva:
  `docs/reviews/e06-r07-signal-quality-stage-security.md` NOTE-2. Javítás
  amikor legközelebb valaki ezt a konstruktort érinti: vegye fel a két
  arányt is az `isFinite` ellenőrzésbe.
- **~~A Claude 5 órás session-kerete rendszeresen kimerül és H-NOSIGNAL-lal
  körökbe kerül~~ — MEGOLDVA (ADR 0222, 2026-08-11, user-döntés).** Mért ok: a
  lánc MINDEN körben a Claude-ot ültette az orchestrátor+reviewer székbe
  (~85 perc/kör, `--effort max`, szünet nélkül) → egy 5 órás ablakba ~3,5 kör
  fér. A védőháló (ADR 0115) ráadásul vak volt: a limit-minta egyetlen valós
  CLI-bannerre sem illeszkedett (11 mérés 90→97%-ig az E06-R05 naplójában), a
  második detektor pedig nem létező fájlra mutatott. **Ma:** a körök felét a
  Terra vezényli (`PIPELINE_ORCH_ROTATION=alternate`), ilyenkor a Claude
  implementál (`sonnet-impl`) — a szerepek cserélnek, a mezőny nem gyengül. A
  fogyásmérő a banner százalékát olvassa, és 85% fölött nem indít új kört a
  Claude-dal (futó munkát soha nem szakít meg). Állapot:
  `tools/pipeline-status.sh`. Tanulság: `docs/LESSONS.md` L215.
- ~~**Rendszerszintű rés (E02-R20, mérve): a standalone Practice V2 session nem
  indítható éles buildben.**~~ **JAVÍTVA (E02-R21, PR #55, `6e5cec7`).** A
  `practiceSessionHostProvider`/`practicePrepareSinkProvider` production
  drótozása (A1-A5, ADR 0111) elkészült és merge-elve — a Hub→Setup→Session
  presentation→controller kötés él. Részletek:
  [`docs/sdd/epic-02-completion-report.md`](docs/sdd/epic-02-completion-report.md)
  §3/§5 (a §3 leírás a régi állapotot rögzíti, evidenciaként megmarad).
- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Epic-2 valódi eszközös teszt PENDING** — a Practice Engine device-mátrix
  ([`docs/manual-testing/practice-engine-device-matrix.md`](docs/manual-testing/practice-engine-device-matrix.md))
  kész, a user tölti ki — a standalone Practice V2 út (E02-R21 óta) és a
  Learn-migrációs út egyaránt elérhető éles buildben.
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.
- **~~A `lib/` 43%-a elérhetetlen~~ — TOVÁBB FELOLDVA (GOV-05a+GOV-05c,
  2026-08-09).** Eredeti mérés (2026-08-07): `song_trainer` V2 (25 308 sor),
  `ai_tutor` (14 091), `vision` (5 132) mind hard-kódolt `false` mögött; a
  Learn a legacy motoron futott minden környezetben.
  **Ma:** a `song_trainer` V2 és a `migratedLearnEnabled` is
  `development`/`lab`-ban ON (a Practice V2 szintén — a flagje eddig is ON
  volt, csak belépési pont nem vezetett hozzá); a Learn a Practice Engine
  V2-n fut `production`-ön kívül. **Hátra van:**
  - `ai_tutor` (14 091 sor) — flagje `false` mindenhol, **BLOKKOLT**: hiányzó
    production-drótozás ÉS hiányzó modell-átjáró, emberi döntést igényel →
    **GOV-05b**, lásd alább;
  - `vision` (5 132 sor) — flagje `false`, és **BLOKKOLT**: nem
    flag-kérdés, hanem hiányzó modell-bináris → **GOV-05d**, lásd a
    következő pontot.
  A termék központi állítására eddig egyetlen mért valós-audio szám létezett
  (CRNN pengetés-irány 86,7% vs heurisztika 38,9%, r164 A/B) — akkord-
  pontosságra, onsetre és BPM-re valós felvételen nem volt szám.
  **JAVÍTVA (GOV-06, E99-R04, 2026-08-09):** a szállított, változatlan
  `ClipAnalyzer` mérve 82 valódi telefonos felvételen — akkord-pontosság
  **67,069%** (18,832%-os többségi-osztály baseline fölött), onset F1@50ms
  **67,391%**. Teljes riport:
  [`docs/eval/real-audio-dsp-baseline.md`](docs/eval/real-audio-dsp-baseline.md).
  A korpusz nincs verziókövetve (external, csak ezen a boxon), a mérés ezért
  elkötelezett riport, nem CI-kapu — a verziókövetés nevesített follow-up.
  **A GOV-06 harmadik száma (BPM-MAE 45,067) ÉRVÉNYTELEN volt — VISSZAVONVA
  ÉS JAVÍTVA (GOV-06b, E99-R05, 2026-08-09, ADR 0212, PR #208):** a szám nem
  DSP-tempóhibát mért, hanem a `.strums` pengetés-eseményekből (nem
  ütem-annotációkból) származtatott „ground truth" ellen — két pengetés-
  sűrűség-becslés egyezetlensége volt, nem tempóé. Független
  librosa-beat-tracker referenciával újramérve: szigorú tempó-egyezés
  **11/82 = 13,415%**, metrikai-szint toleráns egyezés (1/3·1/2·2/3·1·3/2·2·3
  szorzók) **32/82 = 39,024%**; a régi szám megőrizve `visszavonva`
  jelöléssel, pengetés-sűrűségként átcímkézve. **A BPM ezen a korpuszon nem
  mérhető, mert nincs validált (kézi) tempó-annotáció** — ez kimondott,
  elfogadott kimenet, nem hiba. Új eszköz: `ml/chords/tempo_reference.py`.
  Az akkord-pontosság és onset F1 (fent) újramérve bitre változatlan.
  **User-döntés (2026-08-07):** az Epic 6 NEM indul, amíg ez nincs meg — a
  §6 „Kötelező sorrend" 3. ÉS 4. pontja is lezárult. **Az 5. pont (Epic 6
  feloldása) is megtörtént** (user-döntés 2026-08-11, „mehet tovább az
  epic 6") — E06-R01 (Kör 1) kész, lásd a fejléc ✅-blokk és §6.
- **Az AI Tutor rollout — a drótozási blokkoló ÉS a backend-adapter FELOLDVA,
  a bekötés és az üzemeltetés hiányzik (frissítve 2026-08-09, GOV-05b-2 /
  E99-R07 merge után).**
  1. ~~Három provider `throw UnimplementedError`-ral indul~~ — ✅ **MEGOLDVA**
     az **E99-R06** (GOV-05b-1, PR #209, `23fdf30a`, ADR 0213) körrel: a
     `tutorOrchestratorProvider`, a `tutorConversationRepositoryProvider` és a
     `tutorMemoryRepositoryProvider` a `lib/main.dart`
     `buildTutorProductionOverrides` függvényén át kap éles implementációt
     (`LocalTutorConversationRepository`, `LocalTutorMemoryRepository`,
     `TutorOrchestrator`). Az avult `tutorMain()` doc-comment-ígéret törölve
     (`grep -rn "tutorMain" lib/` → 0). **Az `aiTutorEnabled` bekapcsolása
     többé nem crash.**
  2. ~~Nincs konkrét `TutorStreamTransport`~~ — ✅ **MEGOLDVA** ugyanabban a
     körben: `HttpTutorStreamTransport` (Dio `ResponseType.stream` a
     `POST /tutor/stream` SSE végpontra, nyers `data:` payloadokat ad tovább;
     a parse és a `seq`-sorrendezés a `RemoteTutorModelGateway` dolga).
     A kliens–backend szerződést a review kézzel összevetette a
     `TutorStreamRequest` `extra="forbid"` sémájával — illeszkedik.
  3. ~~MÉG HIÁNYZIK — a valódi modell-átjáró~~ — ✅ **MEGOLDVA** (**E99-R07**,
     GOV-05b-2, PR [#210](https://github.com/wolfcasaba/strumsight/pull/210),
     squash `f1d57c69`, **ADR 0214**, implementer **Codex (Terra)** 1
     forduló, javító kör nélkül): `OpenAiProviderGateway`
     (`backend/app/tutor/provider_gateway.py`) nyers `httpx`-szel
     implementálja a `ProviderGateway` szerződést — mind a hét hibaágra
     (timeout, 4xx/5xx, kapcsolati hiba, nem-JSON, hiányzó/nem-string
     `content`) normalizált, szivárgásmentes kivétellel (13 új teszt,
     `httpx.MockTransport`, nulla valós hálózat). Review **APPROVED, 0
     BLOCKER/MAJOR/MINOR, 2 NOTE** (reviewer SAJÁT izolált klónban
     újrafuttatott 9/9 zöld gate-tel ÉS a §6.1 valódi-sértés próba KÉTSZERI
     független megismétlésével — a brief mutációja + egy saját
     kulcs-szivárgásra célzó mutáció, mindkettő a várt cellát buktatta meg).
     Dedikált security-review (risk=high) **PASS, 0
     CRITICAL/BLOCKER/MAJOR/MINOR, 4 NOTE** (mind a bekötő körre szóló
     előre-mutató follow-up: `exc.__context__` defense-in-depth,
     `tutor_openai_base_url` validáció, `AsyncClient` lifecycle, válasz-méret
     korlát) — a security-reviewer a kör saját `str(exc)` tesztjén túlmenve a
     teljes traceback + valós `logging.exception()` szintjén is megmérte mind
     a 7 hibaágat szándékosan beültetett titokkal, 7/7 tiszta. **A
     `FakeProviderGateway` érintetlen** (a diffje üres), **a `main.py`
     bekötése ebben a körben TUDATOSAN NEM történt meg** (ADR 0214 Döntés
     2/OD-04): `tutor_provider` marad `"fake"`, `tutor_enabled` marad
     `False`. Zöld kapu exact-SHA `19002611`: Full Gate + Router CI +
     Backend CI mindhárom **success**. Melléktermék: a pre-flight mért egy
     pre-létező, byte-azonos duplikátumot a `config.py` `tutor_*`
     blokkjában (E04-R14 eredetű, `c1c0a771`) — összevonva, viselkedés
     változatlan.
  4. **MÉG HIÁNYZIK — a bekötés.** A backend `main.py`-ban a registry/gateway
     kiválasztás (ma kizárólag `FakeProviderGateway`-t épít, `main.py:147–184`)
     bekötése az OpenAI-adapterre. Külön kör — a briefje **szándékosan még
     nincs megírva**, a pre-flightjának az E99-R07 utáni állapotot kell
     mérnie.
  5. **MÉG HIÁNYZIK — üzemeltetés.** Hosztolt backend + OpenAI API-kulcs; ez
     **user-feladat**. A `/tutor/stream` **JWT-t vár** (`CurrentUser`), tehát a
     `RemoteTutorModelGateway`-t élesítő körnek **authentikált `Dio`-t** kell
     átadnia a transportnak (E99-R06 review NOTE-1).
  **A flagek változatlanul `false` minden környezetben** — az `aiTutorEnabled`
  bekapcsolása a 4. és 5. pont után, külön körben.
- **A vision rollout BLOKKOLT — hiányzó modell-binárisok (mérve 2026-08-09,
  GOV-05a pre-flight; ez NEM flag-kérdés):** az
  `assets/ml/model_manifest.json` `vision_models` mindkét bejegyzése
  (`hand_landmarker` 1.0.0, `pose_landmarker` 1.0.0) `status: "deferred"`,
  `sha256` csupa nulla, és a hivatkozott
  `hand_landmarker_deferred.tflite` / `pose_landmarker_deferred.tflite`
  fájlok **nincsenek a repóban** (`ls assets/ml/` → négy audio `.bin` + a
  manifest). A `NativeHandLandmarkProvider:77` és a
  `NativePoseLandmarkProvider:76` `deferred` bejegyzésre `AppResult.failure`-t
  ad. Következmény: a `visionEnabled` bekapcsolása MA egy zsákutcába futó
  setup-folyamatot tenne láthatóvá — az Epic 5 mind a 30 köre kész, de
  készüléken egyetlen vision-képesség sem tud futni. **Előfeltétel a
  rollouthoz:** a modell-binárisok beszerzése, licenc- és checksum-átvezetés
  a manifestbe (a `test/tooling/vision_model_integrity_test.dart` valódi
  SHA-256-ellenőrzése csak `active` bejegyzésnél fut) → külön **GOV-05d** kör,
  a döntés emberi.
- **`vision/public.dart` wide-barrel szimbólum-rés — a KONKRÉT R26-eset
  zárva, az ÁLTALÁNOS enforcement-rés nyitva (mérve E05-R25 security-review
  MINOR-1 + E05-R26, nem blokkoló):** a wide barrel máig aggregát
  (privacy-safe) ÉS nyers landmark/pose/geometry/koordináta-típusokat +
  landmark-provider osztályokat is exportál, szimbólum-szintű korlát
  nélkül. **E05-R26 lezárta a SAJÁT belépési pontját**: a Song Trainer új
  fájljai egy ÚJ, szűk, domain-safe nested barrelen
  (`lib/features/vision/domain/integration/public.dart`, ADR 0193 Döntés
  4–7) keresztül érik el a vision-t, ami mechanikusan (könyvtár-prefix
  tiltólistával) kizárja a nyers típusokat — ezt gépi őr védi
  (`vision_integration_barrel_boundary_test.dart`). **Nyitva marad:** (1) a
  wide barrel maga változatlan, a Practice (E05-R25) meglévő importja is
  azt célozza még (migrálásuk külön, jövőbeli kör, nem sürgős — a
  security-review szerint ma sem áthágás); (2) a szűk barrel ÖNMAGA is
  csak a saját KÖZVETLEN export-sorait ellenőrzi, a TRANZITÍV
  mező-típus-gráfot nem — E05-R26 review F1/NOTE-1 mérte, hogy a
  `posture_metrics.dart` (domain-safe, exportált) egy mezőjén
  (`PostureMetricDefinition.requiredPoseLandmarkIds`) át egy tiltott enum
  ÉRTÉKEI olvashatók voltak (javítva R26 saját javító körében egy `show`
  kombinátorral, de a MINTA — egy re-exportált „biztonságos" fájl saját
  mezője hordozhat tiltott típust — általánosan nyitva marad). Egy
  dedikált architektúra-kör (tranzitív gráf-ellenőrzés a checkerben, vagy a
  wide barrel teljes migrálása) follow-up marad. Részletek:
  [`docs/reviews/e05-r26-song-trainer-vision-integration-review.md`](docs/reviews/e05-r26-song-trainer-vision-integration-review.md)
  F1, [`docs/reviews/e05-r26-song-trainer-vision-integration-security.md`](docs/reviews/e05-r26-song-trainer-vision-integration-security.md)
  NOTE-1, [`docs/adr/0193-song-trainer-vision-integration-contract.md`](docs/adr/0193-song-trainer-vision-integration-contract.md),
  [`docs/LESSONS.md`](docs/LESSONS.md) L190, L193.
- **A valódi, több-stage V2 DSP pipeline összeszerelése MÉG NEM ÜTEMEZETT
  kör.** Mérve E06-R22 pre-flightjában (2026-08-12): nulla konkrét,
  egymással összefűzhető `AnalysisStage<T, T>` lánc létezik a `lib/`-ben — a
  három meglévő konkrét stage (`SignalQualityStage`, `PreprocessingStage`,
  `ClipAnalyzerStage`) egymással össze nem fűzhető I/O-jú. [ADR
  0240](docs/adr/0240-analysis-runner-and-pipeline-boundary.md) a runner
  réteget (E06-R22) tudatosan pipeline-agnosztikusra rögzítette
  (`T = AnalysisDocument`, `analysisV2RunnerProvider` fail-closed
  `StateError`-ral) — egy jövőbeli kör tervezze meg a közös munka-kontextust
  és szerelje össze a valódi láncot; ez ma NEM blokkolja a V2 utat (a flag
  változatlanul `false`), de a `analysisV2RunnerProvider` felülírás nélkül a
  V2 Analyze képernyő sosem tudna valódi eredményt produkálni.
- **E06-R21 a saját kötelező, dedikált biztonsági review-ja nélkül
  merge-elt** (a brief `risk = "high"`-at jelölt, §11 kifejezetten kérte —
  mérve E06-R22 zárásakor: minden más E06 kör R02-től párosan rendelkezik
  `-review.md` + `-security.md` jelentéssel, R21-nek csak az előbbije volt).
  Az E06-R22 orchesztrátora egy UTÓLAGOS, retroaktív security review-t
  dispatch-elt a már merge-elt kódra (read-only audit, nem blokkol
  semmilyen már megtörtént merge-et) — az eredményt lásd:
  [`docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md`](docs/reviews/e06-r21-analysis-repository-v2-and-migration-security.md),
  ha időközben elkészült, vagy jelezze egy jövőbeli session, ha még hiányzik.

## 4. Current branch

**Aktuális állapot (2026-08-15):** `main` @ `ac12b017` — E07-R04
PracticeGenerationRequest és draft persistence, PR
[#272](https://github.com/wolfcasaba/strumsight/pull/272), squash-merge.
Exact-SHA `864cf4ab`: Full Gate
[31905168438](https://github.com/wolfcasaba/strumsight/actions/runs/31905168438)
+ Router CI [31905169678](https://github.com/wolfcasaba/strumsight/actions/runs/31905169678)
mindkettő success. A branch `344c2fdc`-re konfliktusmentesen rebase-elve lett,
és `origin/main` a dispatch és a merge között nem mozdult.

**Aktuális állapot (2026-08-15):** `main` @ `e5cae94d` — E99-R11
GOV-30c-3 progress-phase decoupling, PR
[#262](https://github.com/wolfcasaba/strumsight/pull/262), squash-merge.
Exact-SHA `211b53c2`: Full Gate
[31872874525](https://github.com/wolfcasaba/strumsight/actions/runs/31872874525)
+ Router CI [31873455184](https://github.com/wolfcasaba/strumsight/actions/runs/31873455184)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között;
post-merge `tools/round-gate.sh` zöld a friss `main`-en.

**Aktuális állapot (2026-08-14):** `main` @ `82cfa588` — E99-R10
GOV-30c-2 evaluation stage composition, PR
[#261](https://github.com/wolfcasaba/strumsight/pull/261), squash-merge.
Exact-SHA `e3c681b6`: Full Gate
[31795147660](https://github.com/wolfcasaba/strumsight/actions/runs/31795147660)
+ Router CI [31795149311](https://github.com/wolfcasaba/strumsight/actions/runs/31795149311)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között.

**Aktuális állapot (2026-08-14):** `main` @ `cb76db0f` — E99-R09
GOV-30c-1 PCM ingest pipeline composition, PR
[#259](https://github.com/wolfcasaba/strumsight/pull/259), squash-merge.
Exact-SHA `5d2e0da0`: Full Gate
[31780988606](https://github.com/wolfcasaba/strumsight/actions/runs/31780988606)
+ Router CI [31781917615](https://github.com/wolfcasaba/strumsight/actions/runs/31781917615)
mindkettő success. `origin/main` nem mozdult a dispatch és merge között.

**Aktuális állapot (2026-08-14):** `main` @ `f257afa7` — E06-R30 (shadow
rollout, migráció és Epic 6 lezárás, ZÁRÓ KÖR), PR
[#257](https://github.com/wolfcasaba/strumsight/pull/257), squash-merge.
Exact-SHA `719c534c`: Full Gate
[31758004379](https://github.com/wolfcasaba/strumsight/actions/runs/31758004379)
+ Router CI [31758041194](https://github.com/wolfcasaba/strumsight/actions/runs/31758041194)
mindkettő success. `origin/main` nem mozdult dispatch és merge között.
Post-merge `tools/round-gate.sh test/features/audio_analysis test/app
test/features/analyze test/features/library` a lokálisan fast-forwardolt,
friss `main`-en 9/9 zöld — lásd a fejléc ✅-blokk a teljes
pre-flight/review/security/javító-kör történetért. **Epic 6 (Audio
Analysis 2.0) mind a 30 köre kész** — a V2 shadow-szinten marad, a V1 a
shipping út, opt-in/default-on rollout és V1-kivezetés külön, jövőbeli,
ember által jóváhagyott GOV-kör dolga (a completion report `GOV-30a/b/c`
néven nevesíti).

**Korábbi állapot (2026-08-13):** `main` @ `d325d601` — E06-R28 (cache,
performance és model lifecycle), PR
[#255](https://github.com/wolfcasaba/strumsight/pull/255), squash-merge.
Exact-SHA `59810b4`: Full Gate
[31744318906](https://github.com/wolfcasaba/strumsight/actions/runs/31744318906)
+ Router CI [31744374712](https://github.com/wolfcasaba/strumsight/actions/runs/31744374712)
mindkettő success. `origin/main` nem mozdult dispatch és merge között. Post-merge
`tools/round-gate.sh test/features/audio_analysis test/property test/core`
egy REMOTE-ról klónozott, friss munkapéldányon (L264) — lásd
`docs/handoff-archive.md` a teljes pre-flight/review/security történetért.

> Ez a §4 log ITT nem lett folyamatosan karbantartva E06-R19…R27 között — a
> fejléc ✅-blokkja (mindig a két legutóbbi kör) és `docs/handoff-archive.md`
> a hiteles, folyamatos forrás azokra a körökre. Az alábbi, E99-R08-cal kezdődő
> szakasz a korábbi (2026-08-12-i) állapotot rögzíti — történeti kontextusként
> hagyva, nem frissítve visszamenőleg.

**Korábbi állapot (2026-08-12):** `main` @ `7a594db6` — E99-R08 H3
self-heal (ADR 0112, NEM egy SDD-kör — pipeline-infra fix), PR
[#243](https://github.com/wolfcasaba/strumsight/pull/243), squash-merge.
Router CI [31682955616](https://github.com/wolfcasaba/strumsight/actions/runs/31682955616)
success az exact-SHA `86c4719f`-en (PR-ág), majd
[31683234986](https://github.com/wolfcasaba/strumsight/actions/runs/31683234986)
success a merge-elt `7a594db6`-on (post-merge `main`). `main`-t NEM
érintette Dart-kód, `build-apk.yml` nem indult. Az E99-R08 SDD-kör saját
commitjai (`ba9b65ea`…`bf413355`) a **round saját branchén**
(`sonnet-impl/e99-r08-gov-07-per-round-orchestrator-rotation`) landoltak,
nem itt — a kör review-jelentése és a merge még hátravan, lásd a fejléc 🔧
blokkját. `origin/main` nem mozdult dispatch és merge között.

**Előző állapot (2026-08-12):** `main` @ `6be36efa` — E06-R23 H3
self-heal (ADR 0112, NEM egy SDD-kör — pipeline-infra fix), PR
[#240](https://github.com/wolfcasaba/strumsight/pull/240), squash-merge.
Router CI [31649793492→31650104969](https://github.com/wolfcasaba/strumsight/actions/runs/31650104969)
success az exact-SHA `569ad2fe`-n (első próba pirosra futott egy CI-shallow-
checkout-specifikus tesztbuggal — ld. lecke L247 —, javítva, a végleges HEAD
zöld). `main`-t NEM érintette Dart-kód, `build-apk.yml` nem indult. Az
E06-R23 SDD-kör saját commitjai (`12bb66d`, `3d4ace8`) a **round saját
branchén** landoltak, nem itt — lásd a fejléc 🔧 blokkját. `origin/main` nem
mozdult dispatch és merge között.

**Korábbi állapot (2026-08-12):** `main` @ `6abdd408` — E06-R22, PR
[#239](https://github.com/wolfcasaba/strumsight/pull/239), squash-merge.
Exact-SHA `ae22ff50`: Full Gate
[31642984516](https://github.com/wolfcasaba/strumsight/actions/runs/31642984516)
+ Router CI [31642980491](https://github.com/wolfcasaba/strumsight/actions/runs/31642980491)
mindkettő success a végleges (javító kör utáni) HEAD-en. `origin/main` nem
mozdult dispatch és merge között. A post-merge
`tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze`
mind a nyolc lépése zöld (`audio_analysis=438`, `app=69`, `analyze=64`).

**Előző állapot (2026-08-12):** `main` @ `98f4c1e1` — E06-R21, PR
[#238](https://github.com/wolfcasaba/strumsight/pull/238), squash-merge.
Exact-SHA `fa736e39`: Full Gate
[31636632388](https://github.com/wolfcasaba/strumsight/actions/runs/31636632388)
+ Router CI [31636633676](https://github.com/wolfcasaba/strumsight/actions/runs/31636633676)
mindkettő success. `origin/main` nem mozdult dispatch és merge között.

**Korábbi állapot (2026-08-12):** `main` @ `f2674099` — E06-R18, PR
[#234](https://github.com/wolfcasaba/strumsight/pull/234), squash-merge.
Az exact merge-előtti SHA `f8ed50b2`: Full Gate
[31609390475](https://github.com/wolfcasaba/strumsight/actions/runs/31609390475)
success (`full-gate` + `Coverage`). A CI-terv `full-gate.yml`-t adott
(`apk_required=false`); Router CI [31607444433](https://github.com/wolfcasaba/strumsight/actions/runs/31607444433)
success az `ae11543c` releváns ősön, mert az utókommitok nem triggerelték.
`origin/main` nem mozdult dispatch és merge között. A post-merge
`tools/round-gate.sh test/features/audio_analysis test/tooling test/app`
mind a nyolc lépése zöld.

**Ennél is korábbi állapot (2026-08-12):** `main` @ `aa41db54` — E06-R09, PR
[#223](https://github.com/wolfcasaba/strumsight/pull/223), squash-merge.
Az exact merge-előtti SHA `29feb745` (a review-dokumentumok utáni végleges
HEAD): Full Gate és Router CI success, mindkettő kézzel `workflow_dispatch`-
elve, mert a review-doksi-only commit egyik workflow push-path-szűrőjét sem
érintette (L112). A post-merge
`tools/round-gate.sh test/features/audio_analysis test/property test/tooling test/features/analyze`
mind a kilenc lépése zöld (lásd lent). Az alábbi régebbi rész történeti kontextus.

`main` @ [PR #211](https://github.com/wolfcasaba/strumsight/pull/211), squash
`62516a4b` (E06-R01, Epic 6 kickoff — Analyze V1 baseline, mérés és hat
kötött ADR; lásd a fejléc ✅-blokk a teljes pre-flight/review/security
történetért). Implementer **Terra (Codex)**, 1 forduló, javító kör nélkül.
`lib/`/`test/` diff üres — `tool/audio_analysis_baseline.dart` (ÚJ),
`docs/baseline/epic-06-audio-analysis-start.md` (ÚJ),
`docs/manual-testing/analysis-eval-matrix.md` (ÚJ), `docs/adr/0215`…`0220`
(ÚJ, orchesztrátor pre-flight) és a brief §0.0/§10 → Full Gate
[31477469515](https://github.com/wolfcasaba/strumsight/actions/runs/31477469515)
+ Router CI mindkettő **success** az exact merge-előtti tip `d7adf53e`-n
(a Router CI automatikus push-trigger, mert a diff `docs/rounds/**`-t
érint; a Full Gate kézzel dispatch-elve, a CI-terv `full-gate.yml`-t írt
elő, `native_gate=false`). Review **APPROVED, 0 BLOCKER/MAJOR/MINOR**, 3
NOTE — a reviewer SAJÁT, izolált `/tmp` klónban a teljes 7-lépéses gate-et
függetlenül újrafuttatta (mind zöld) ÉS a determinisztikus mérő-harnesst
egy HARMADIK, tőle független futtatással bájtra egyező
`DETERMINISM_SHA256`-ra futtatta. Dedikált security-review (risk=high)
**PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
dispatch és a merge között **nem mozdult** (`2334136a` mindvégig), rebase
nem kellett (H8 tiszta). Post-merge gate a friss `main`-en (`62516a4b`) is
önállóan újrafuttatva: mind a 7 lépés zöld.

**Pre-flight kétszeres mért drift-javítás (§0.0 R1+R2, a lánc mintázata
immár hatodszor mérve, `docs/LESSONS.md` L194):** a brief 2026-08-07-i
fejléce `ls`-alapú extrapolációval 0200–0205 ADR-tartományt írt elő; a
`reserve-adr` foglaló a valós, 2026-08-11-i állapotot **0215–0220**-ként
adta (három közbeeső governance-kör foglalta el a köztes számokat anélkül,
hogy a 0200–0211 sávot ténylegesen lefoglalta volna). A `lib/features/analyze/`
fájl/sorszáma is driftelt a brief mérése óta (12→14 fájl, 1866→2168 sor,
E05-R27 eredetű) — mindkettő dokumentált revízióval javítva a dispatch előtt.

> **[Superseded ref — E99-R05 branch]:** `main` @ PR #208, squash
> `c4ce2cc0` (E99-R05, GOV-06b — a GOV-06 BPM-metrikájának javítása).
> Mérce-javító kör, `lib/` diff üres (ADR 0212 Döntés 6). Full Gate
> [31325609456](https://github.com/wolfcasaba/strumsight/actions/runs/31325609456)
> + Router CI [31325597238](https://github.com/wolfcasaba/strumsight/actions/runs/31325597238)
> mindkettő **success** az exact merge-előtti tip `94fb2f6f`-n. Review
> **APPROVED, 2 forduló** (1 impl. + 1 javító kör); dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`caa7751e` mindvégig), rebase
> nem kellett (H8 tiszta). Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E99-R04 branch]:** `main` @ PR #207, squash `5ceed22d`
> (E99-R04, GOV-06 — Valós-audio DSP baseline mérés). Mérési kör, `lib/` diff
> üres (A1) → Full Gate [31302531695](https://github.com/wolfcasaba/strumsight/actions/runs/31302531695)
> + Router CI [31302494856](https://github.com/wolfcasaba/strumsight/actions/runs/31302494856)
> mindkettő **success** az exact merge-előtti tip `ab4024a6`-n. Review
> **APPROVED, 1 forduló, javító kör nélkül**; dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`dc201524` mindvégig), rebase
> nem kellett (H8 tiszta). A BPM-MAE szám azóta **visszavonva** — lásd fent,
> GOV-06b. Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E99-R03 branch]:** `main` @ PR #206, squash `0e9d211c`
> (E99-R03, GOV-05c — Learn migráció a Practice Engine V2-re). Flag+teszt+
> doksi diff (nincs `lib/features/**`, kizárólag
> `lib/app/config/feature_flags.dart`) → Build APK
> [31298706423](https://github.com/wolfcasaba/strumsight/actions/runs/31298706423)
> + Router CI [31298707173](https://github.com/wolfcasaba/strumsight/actions/runs/31298707173)
> mindkettő **success** az exact merge-előtti tip `87ca3f54`-n. Review
> **APPROVED, 1 forduló, javító kör nélkül**; dedikált security-review
> **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR**, 2 NOTE. Az `origin/main` a
> dispatch és a merge között **nem mozdult** (`69ecc661` mindvégig), rebase
> nem kellett (H8 tiszta). Teljes történet: `docs/handoff-archive.md`.

> **[Superseded ref — E05-R30 branch]:** `main` @ PR #204, squash `d3b2caf9`
> (E05-R30, Dataset, evaluation, minőségi kapuk és Epic 5 lezárás — ZÁRÓ
> KÖR). Full Gate [31282481824](https://github.com/wolfcasaba/strumsight/actions/runs/31282481824)
> + Router CI [31282482794](https://github.com/wolfcasaba/strumsight/actions/runs/31282482794)
> **success** a `bbb23079` merge-előtti tipen; review **APPROVED javító kör
> nélkül**, dedikált security-review **PASS**. Teljes történet:
> [`docs/handoff-archive.md`](docs/handoff-archive.md). Lecke: **L202**,
> **L189 kiegészítve**.

**Az Epic 5 (Computer Vision) MIND A 30 KÖRE kész**, és a §6 „Kötelező
sorrend" GOV-05 shipping-rollout hármasa (GOV-05a/b/c) is lezárult. A
pipeline queue egyetlen fennmaradó sora (`E06-R29`/`E06-R30`) `hold`-on van
— nincs automatikusan indítható következő kör. Lásd §6.
_(Történeti product-merge referencia: PR #205 / `d958b75e`, E99-R01
(GOV-05a); PR #204 / `d3b2caf9`, E05-R30; PR #203 / `8e7eb6f9`, E05-R29; PR #202 /
`a9698557`, E05-R28; PR #201 /
`7e43019`, E05-R27; PR #200 /
`242cccb`, E05-R26; PR #199 /
`9b608cf`, E05-R25; PR #197 /
`e9257f4`, E05-R24; PR #196 /
`b54490e`, E05-R23; PR #195 / `997e7be`, E05-R22; PR #194 /
`7b11f26`, E05-R21; PR #193 /
`be38e11`, E05-R20; PR #192 / `a38e0e0`, E05-R19; PR #191 / `75f8766`,
E05-R18; PR #189 / `e979d41`, E05-R17; PR #188 / `6f9c0e1`, E05-R16; PR #187
/ `a351ad3`, E05-R15; PR #185 / `efa4bbe`, E05-R14; PR #184 / `148469c`,
E05-R13; PR #183 / `f39d7b6`, E05-R12; PR #182 / `113976a`, E05-R11; PR #181
/ `39d1c29`, E05-R10; PR #180 / E05-R09, frame quality assessor; PR #169 /
`b5837d9`, E05-R07; PR #168 / `a43f8c1`, E05-R06; PR #162 / `cef864c`,
E05-R01, Epic 5 INDUL; PR #160 / `0cf6323`, E04-R24.)_

> **[Superseded ref — E05-R07 branch]:** `main` @ PR #169, squash
`b5837d9` (E05-R07). Pure Dart/teszt diff → full-gate
[31105913601](https://github.com/wolfcasaba/strumsight/actions/runs/31105913601)
+ router-ci [31105957563](https://github.com/wolfcasaba/strumsight/actions/runs/31105957563)
**success** az exact merge-előtti tip `9c52d74`-n; review **APPROVED 1 javító
kör után** (Terra implementer). Az `origin/main` a dispatch óta **nem
mozdult** (`b6408f0` → merge `b5837d9`), rebase nem kellett (H8 tiszta).

> **[Superseded ref — E04-R22 branch]:** `main` @ PR #157, squash
`faa3f32` (E04-R22). Tisztán Dart/dokumentum-diff → a CI-terv `full-gate.yml`-t
írt elő (nincs natív út), és a `docs/rounds/**` érintés miatt a **router-ci** is a
kapu része: full-gate [31071295264](https://github.com/wolfcasaba/strumsight/actions/runs/31071295264)
+ router-ci [31071295063](https://github.com/wolfcasaba/strumsight/actions/runs/31071295063)
**success** az exact merge-előtti tip `05c7006`-on; review **APPROVED** 1 javító
kör után (MiniMax M3). A dispatch óta a `main` mozdult (#158 DeepSeek engine-registry),
ezért a branchet `origin/main`-re **rebase**-eltem (konfliktus nélkül) és a CI-t
**újra-dispatcheltem** az `05c7006` tip-en (ADR 0086 §2 / H8).
(Történeti product-merge referenciák: PR #156 / `6000b57`, E04-R21; PR #153 / `3ce4afc`, E04-R20; PR #151 / `104e685`, E04-R18;
PR #148 / `1e9b2db`, E04-R17; PR #147 / `df25806`, E04-R16; PR #145 / `1fe91d2`,
E04-R15; PR #140 / `c5b14e5`, E04-R12; PR #137 / `479550f`, E04-R11; PR #129 / `f3d69ef`,
E04-R06; PR #128 / `55d640d`, E04-R05; PR #127 / `0d7ab1b`, E04-R04.)

> **L48 clone-pitfall recurred on a fresh `auto`-router worktree
> (mérve 2026-08-02, E03-R06):** a brand-new worktree's first
> `BASELINE_GATE` run BLOCKED on 625 `AppLocalizations` analyze errors
> (gitignored `lib/l10n/app_localizations*.dart` missing from the fresh
> `git worktree add`). Fix: `flutter pub get && flutter gen-l10n` in the
> worktree, then `python3 tools/model-router.py reset --task-id <ID>`
> (sanctioned, zero-cost) — same recipe as L48, now confirmed systemic
> across `auto`-router worktrees, not a one-off. Also measured in the
> same pre-flight (NOT this session's to fix — a closed round's
> artifact): the currently-`main` E03-R05 brief's `ai-router` TOML
> `allowed_paths` incorrectly includes the ADR 0114 path, which is why
> Router CI (`router-ci.yml`) is red on `main` right now — left for a
> future self-heal round. Details: `docs/LESSONS.md` L59.

> **Two router infra dead ends closed/documented on the E03-R05 branch
> before that round's own work started:** the branch had already been
> through two H6 self-heal cycles (PR #61/#62/#63, `docs/LESSONS.md`
> L54–L56 — async router dispatch, gate-guard scope, and finally a PATH
> git-guard shim closing M3's illegal self-commit at the shell layer).
> That session's pre-flight found the salvageable, scope-clean M3 diff
> sitting uncommitted in an abandoned worktree and reconciled it (L50
> pattern: `git reset --soft` + rebase + independent gate re-run +
> orchestrator commit) instead of re-running the round from scratch.

> **Router `resume` false-`BLOCKED` from a premature orchestrator commit
> (mérve 2026-08-02, E03-R03):** teljes leírás `docs/LESSONS.md` L51-ben —
> röviden: NE commitold a diffet/review-t a `resume` hívás előtt (audit +
> review UNCOMMITTED, vagy külön klón); findings-fájl `.ai/review-findings-
> <slug>.md` néven; csak a TELJES ciklus lezárása után, egyetlen lépésben
> commitolj.

> **`BLOCKED`→`READY_FOR_REVIEW` recovery (mérve 2026-08-02, E03-R02):** ha
> `m3_attempts >= 1` és a self-heal már bizonyította a diff scope-tisztaságát,
> a `model-router.py reset --task-id` + friss `run` a JELENLEGI worktree
> tartalmát kapja új baseline manifestként — ha a diff még a worktree-ben
> van, azonnal újra `BLOCKED`-ba fut ("baseline has untracked files"); ha
> pristine-re tisztítod előbb, egy felesleges, ismételt M3-attempt-et fizetsz
> a már kész munkáért. A helyes út: `git reset --soft <pre-flight commit>` a
> worktree-ben (M3 saját commitját visszabontja uncommitted diffre),
> `git rebase origin/main` a healed baseline-ra, scope-audit a brief
> `allowed_paths` ellen, majd az orchestrátor saját authorship-szel
> commitolja — a router task state-hez nem kell nyúlni. Részletek:
> `docs/LESSONS.md` L50.

> **Router baseline-precheck clone pitfall (mérve 2026-08-02, E03-R01):** egy
> vadonatúj izolált munkapéldány első `ai-router-round.sh run` hívása a lenti
> klón-csapdába fut, de a router SAJÁT `BASELINE_GATE` precheckjében, `BLOCKED`
> státusszal és **`m3_attempts=0`**. A javítás: `flutter pub get && flutter
> gen-l10n` a klónban, majd `python3 tools/model-router.py reset --task-id
> <ID>` (sanctioned, zéró-fogyasztású reset — NEM a tiltott kézi
> state-törlés). Részletek: `docs/LESSONS.md` L48.

> ⚠ **A squash-commit üzenete tévesen a régi, „HALT H3" PR-címet viszi**
> (`0bdee7e`): a `gh pr edit` a merge előtt a Projects-classic GraphQL
> deprecation miatt némán elhasalt, a cím csak utólag, REST-en át (`gh api -X
> PATCH .../pulls/43`) lett javítva. A kör állapota **APPROVED**. Tanulság:
> `gh pr edit` után **ellenőrizd** a címet, mielőtt mergelsz.

> **Klón-/friss-munkafa csapda (mérve 2026-08-01):** a generált
> `lib/l10n/app_localizations*.dart` **gitignore-olt**, ezért egy friss klónban
> — és egy régóta nem regenerált munkafában is — az `analyze` több száz
> `undefined_getter` hibával pirosat ad. Ez klón-artefaktum, nem kör-hiba:
> `flutter gen-l10n` után a gate zöld. Reviewer-oldalon ez a **legelső** lépés.

> **CI-szabály (ADR 0086):** a `build-apk.yml` csak `workflow_dispatch`-re fut;
> merge előtt kötelező az `origin/main` mozgás-ellenőrzés, és a dispatch után a
> run **`headSha`-ját össze kell vetni a lokális HEAD-del** (L21 — az R11-ben
> egy néma `&&`-lánc-bukás miatt először rossz SHA-ra ment a dispatch).

## 5. Last completed round

**E07-R04 — PracticeGenerationRequest és draft persistence** (PR
[#272](https://github.com/wolfcasaba/strumsight/pull/272), squash `ac12b017`,
[ADR 0259](docs/adr/0259-generation-request-versioning-and-draft-isolation.md)).
Immutable, schema-verziózott generation request készült kanonikus SHA-256
content-hash-sel és származtatott seeddel; a hashből kizárt idő/provenance nem
rontja a reprodukálhatóságot. A v1→v2 migráció támogatott, jövőbeli vagy sérült
séma kontrollált hibát ad. A wizard-draft a `KeyValueStore` külön namespaced
kulcsán él, ezért nem írhat aktív tervet; olvasási hiba `StorageFailure`, a
törlés idempotens. Egy MAJOR review-lelet javítva regressziós tesztekkel:
hibás típusú opcionális `targetDate`/`metricTarget` nem veszhet el némán.
Correctness review APPROVED, local gate és exact-SHA Full Gate + Router CI
zöld; flag/provider/UI érintetlen. Implementer `sonnet-impl`, egy javító kör.

**E99-R11 — GOV-30c-3 progress-phase decoupling** (PR
[#262](https://github.com/wolfcasaba/strumsight/pull/262), squash `e5cae94d`,
[ADR 0252](docs/adr/0252-analysis-progress-phase-decoupling.md)).
Az explicit stage-ID → `AnalysisProgressPhase` map a hét ingest és tizenegy
evaluation stage-et egyetlen élő `AnalysisPipeline<AnalysisWorkState>`-ben
futtatja; azonos fázis ismételhető, visszalépés konstrukciókor és futáskor is
tiltott. Map nélküli hívó a legacy 9-stage capet kapja. A correctness review
APPROVED, a high-risk security review F1 MAJOR-ja (hívóoldali map-mutáció)
defensive immutable snapshot + regressziós teszttel zárva PASS. Exact-SHA
CI és post-merge gate zöld. Provider és flag érintetlen. Implementer
`sonnet-impl`, egy javító dispatch.

**E99-R10 — GOV-30c-2 evaluation stage composition** (PR
[#261](https://github.com/wolfcasaba/strumsight/pull/261), squash `82cfa588`,
[ADR 0251](docs/adr/0251-analysis-target-seeding-and-evaluation-stage-composition.md)).
`AnalysisWorkState` bővítve referencia/illesztés/metrika/capability
mezőkkel; tizenegy granular evaluation-stage vékony adaptere a meglévő,
review-zott alignment/metrics/confidence modulok fölött; üres/hiányzó
referencia degradál, nem fabrikál hamis illesztést (mérve, önállóan
megismételt valódi-sértés próbával). Első dispatch `stopped` egy valós
`AnalysisPipeline<T>` stage-count-cap ütközésen, dokumentált §0.0
brief-revízióval + ADR 0251 §5-tel feloldva (composition-teszt szekvenciális
`stage.run(...)`-nal, nem `AnalysisPipeline` példányosítással); második
dispatch `done`, javító kör nélkül. Correctness review APPROVED (0
BLOCKER/MAJOR/MINOR, 4 NOTE) és dedikált security review PASS (0
CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE), mindkettő exact-SHA CI zöld.
Implementer Terra (Codex).

**E99-R09 — GOV-30c-1 PCM ingest pipeline composition** (PR
[#259](https://github.com/wolfcasaba/strumsight/pull/259), squash `cb76db0f`,
[ADR 0250](docs/adr/0250-v2-analysis-work-state-and-ingest-stage-composition.md)).
Immutable V2 work state + hét meglévő lokális engine-modul vékony adaptere;
PCM-only lánc a timeline-alapig, provider/flag érintetlen. 1 MAJOR javítva
(külső legacy evidence helyett `ClipAnalyzerStage`-ből származó evidence);
correctness és security review APPROVED, exact-SHA CI zöld. Implementer
`sonnet-impl`, 1 javító dispatch.

**E06-R28 — Cache, performance és model lifecycle** (PR
[#255](https://github.com/wolfcasaba/strumsight/pull/255), squash `d325d601`,
új [ADR 0248](docs/adr/0248-analysis-cache-key-and-performance-budget.md)).
Determinisztikus, bekötetlen V2 cache-infrastruktúra (`AnalysisCacheKey`,
`AudioFingerprint`, `AnalysisCache`, `ModelByteCache`); a benchmark
DETERMINISM_SHA256-ja bitre egyezik az R01 baseline-éval. Content review
APPROVED (0 BLOCKER/MAJOR, 2 MINOR), dedikált security review APPROVED (0
BLOCKER/MAJOR, 5 MINOR + 5 NOTE, mind latens — lásd fejléc ✅-blokk és §3).
Exact-SHA CI és post-merge gate zöld. Implementer Terra, 1 dispatch `done`,
javító kör nélkül.

> (§5 folytonossági rés E06-R19…R27 között — lásd a §4 megjegyzését fent.)

**E06-R18 — Technique proxy experimental module** (PR
[#234](https://github.com/wolfcasaba/strumsight/pull/234), squash `f2674099`,
új [ADR 0236](docs/adr/0236-analysis-technique-proxy-safety-and-naming.md)).
Lab/flag/confidence-gated proxy report, transition evidence és claim-safe
metrika-katalógus készült; UI/pipeline/persistence/V1 érintetlen. A végső
review APPROVED, a független security re-review PASS; exact-SHA CI és
post-merge gate zöld.

**E06-R10 — Event evidence modell és onset/strum timeline V2** (PR
[#225](https://github.com/wolfcasaba/strumsight/pull/225), squash `eec0aeab`,
új [ADR 0228](docs/adr/0228-event-evidence-model-and-timeline-builder-contract.md)).
A meglévő `OnsetEvent`/`StrumEvent` additív evidence-mezőkkel bővült
(attack/RMS/confidenceSource/fallbackReason mindkét levéltípuson,
directionConfidence+onsetEventId csak StrumEventen); új `EventId`
(determinisztikus `<runId>:<type>:<sampleIndex>`) és `EventTimelineBuilder`
(`Duration`-alapú 50 ms minimum-separation, pár-atomikus suppression,
onset→strum holtverseny-sorrend); `LegacyViewAdapter` zéró kódváltozással
fogyasztja. Pre-flight egy ADR-t írt és három egymást követő, mért
brief-rést zárt (Duration vs. rögzített mintaszám; `onsetEventId`
szintetizálási szabály hiánya; rendezettségi ütközés a párszintézissel) —
mindegyiket Terra saját dispatch-e fedte fel `stopped`-dal, tiszta
munkafával, elvesztett munka nélkül. Egy negyedik dispatch `blocked`-ot
jelzett a L222 fresh-clone l10n-codegen mintázatra (orchesztrátor mulasztás,
azonnal javítva). General review első köre CHANGES REQUESTED (1 MAJOR: a
builder sosem futott a valódi kilenc R09-fixture-ön; 1 MINOR: attack/RMS
számított érték nem mérve) — a javító kör KIZÁRÓLAG két tesztet adott hozzá,
végső verdikt APPROVED. Security review PASS (0 CRITICAL/BLOCKER/MAJOR, 1
látens MINOR a jövőbeli R19-nek, 5 NOTE). Az alábbi régebbi rész történeti
kontextus.

**E06-R09 — ClipAnalyzer stage adapter és V1↔V2 parity** (PR
[#223](https://github.com/wolfcasaba/strumsight/pull/223), squash `aa41db54`,
új [ADR 0226](docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md)).
A bitre változatlan V1 `ClipAnalyzer` bekötve `ClipAnalyzerStage`-ként,
kizárólag a `runClipAnalysis` exportált belépőn át; kettős-hívásos
fallback-provenance technika (`none`/`heuristic`+ok/`crnn`); 9 fixture +
60-mintás randomizált property paritás ≤1 µs / ≤1e-9 tolerancián belül;
architektúra-allowlist bitre változatlan (12); nincs hívó, production
viselkedés bitre azonos. Pre-flight két mért brief-rést zárt dokumentáltan
(ADR 0226): a fallback-provenance mérési technika hiánya és egy hiányzó
`test/tooling` allowed_paths bejegyzés. General review APPROVED (0
BLOCKER/MAJOR/MINOR, 2 NOTE, három saját mutációs próbával igazolva),
security review PASS (0 CRITICAL/BLOCKER/MAJOR/MINOR, 5 NOTE, mind a
jövőbeli E06-R22 bekötő körre). Az alábbi régebbi rész történeti kontextus.

**E06-R08 — Preprocessing context és resampling policy** (PR
[#222](https://github.com/wolfcasaba/strumsight/pull/222), squash `d3ce39b2`,
új [ADR 0225](docs/adr/0225-analysis-preprocessing-and-resampling-policy.md)).
Immutable, native-rate/canonical PCM előfeldolgozási contract, explicit
downmix és fail-closed feature flag; nincs hívó és nincs változás a V1
Analyze/Live DSP útvonalakon. A review F1/MAJOR-ját a canonical PCM-ből
mért valós DC-onset határesettel zártuk; general review APPROVED, security
review PASS, nyitott BLOCKER/MAJOR nélkül. Az alábbi régebbi rész történeti
kontextus.

**E05-R25 — Practice Engine vision integration** (PR
[#199](https://github.com/wolfcasaba/strumsight/pull/199), squash `9b608cf`,
**ÚJ ADR 0192** practice-vision-integration-contract szerződésre (a brief
`nincs` mezője szerint az orchesztrátor írta a pre-flightban); implementer
**Codex (Terra)** (egyetlen forduló, köztes pre-flight-eredetű `stopped`
önjavítva), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `VisionPracticeContract`/
`PracticeVisionAdapter`/additív `PracticeSessionResult.vision`/önálló
`PracticeVisionDimension` widget — lásd a fejléc ✅-blokk a teljes
pre-flight/köztes-megállás/review történetért. **Pre-flight (§0.0, 8 pont)**
mérte, hogy `PracticeSessionResult`-nak nincs saját JSON-kódja (a §6 negyedik
cellája ezért revideálva), hogy a `practice → vision/public.dart` import
mindkét gépi őrrel legális, és hogy a három pilot NEM
`BuiltinPracticeCatalog`-bejegyzés. **0 javító kör**, de egy köztes `stopped`
a pre-flight SAJÁT hibájából (az ADR 0192 útvonala kimaradt az
`allowed_paths`-ból) — Terra megállás-kori munkája hibátlannak bizonyult,
egy §0.0-revízióval és UGYANAZON session folytatásával zárva. Az
orchesztrátor SAJÁT, izolált `/tmp` klónban futtatott gate-tel ÉS egy saját
falszifikációs próbával (a vision-változat `scorePoints`-ját 900→999-re
rontva a parity-fixture PIROSRA fordult, majd visszaállítva) ellenőrizte a
munkát, függetlenül az implementer önjelentésétől. A dedikált security-review
1 nem-blokkoló MINOR-t talált (a `vision/public.dart` barrel nyers
landmark/pose/geometry-típusokat is exportál a ténylegesen használt
aggregátumok mellett, szimbólum-szintű korlát nélkül) — E05-R26 pre-flight
bemenetként rögzítve (§3). Gate zöld az `fb93cb7` merge-előtti SHA-n: Full
Gate ✅ · Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó push
nem érintett trigger-útvonalat). Post-merge gate a friss `main`-en (`9b608cf`)
is zöld, 913+522 teszt. Lecke: **L188**, **L189**, **L190**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r25-practice-vision-integration-review.md) +
[security](docs/reviews/e05-r25-practice-vision-integration-security.md).

**E05-R24 — Vision session controller and realtime overlay** (PR
[#197](https://github.com/wolfcasaba/strumsight/pull/197), squash `e9257f4`,
**nincs új ADR**; implementer **Codex (Terra)** (kezdeti + **2 javító kör**),
orchesztrátor/reviewer **Claude Sonnet 5**, dedikált **security-reviewer**
ágens `risk = "high"` miatt). `VisionSessionController`/`VisionSessionState`/
`VisionSession`/`VisionSessionResult`/`VisionPreviewOverlay` — teljes
történet: [`docs/handoff-archive.md`](docs/handoff-archive.md). **2 javító
kör**: 1. kör zárta F1 BLOCKER-t (silent-null a `start()` async
acquire-ablakában) + F2 MAJOR-t (hiányos állapotgép-mátrix) + F3 MINOR-t; a
review saját próbateszttel egy ÚJ, a javítás saját regressziójaként
bevezetett F4 BLOCKER-t talált (a `dispose()` kivétellel elszállt), amit a
2. kör zárt. A dedikált security-review függetlenül ugyanarra az F1
gyökérokra jutott. **H5 self-heal** (ADR 0112, PR
[#198](https://github.com/wolfcasaba/strumsight/pull/198)): a kör saját
pre-flight `allowed_paths`-bővítése átbillentette a queue mért-motor
szabályát, Router CI kétszer pirosra futott, önjavító kör szinkronizálta a
queue-t. Gate zöld az `e069140` merge-előtti SHA-n (H5 self-heal utáni tip):
Full Gate ✅ · Router CI ✅. Post-merge gate a friss `main`-en (`e9257f4`) is
zöld, izolált klónban újrafuttatott teljes pytest suite (347/347). Lecke:
**L187**. Részletek:
[review](docs/reviews/e05-r24-vision-session-controller-and-overlay-review.md) +
[security](docs/reviews/e05-r24-vision-session-controller-and-overlay-security.md).

**E05-R23 — Feedback policy and realtime cue budget** (PR
[#196](https://github.com/wolfcasaba/strumsight/pull/196), squash `b54490e`,
**ÚJ ADR 0191** feedback-policy-és-cue-budget szerződésre (a brief előzetes
„0162" hivatkozása sosem lett fájl); implementer **Codex (Terra)** (kezdeti
+ **1 javító kör**), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `InsightCode`/
`FeedbackPolicy`/`CueBudget`/`FeedbackPolicyEngine` — lásd a fejléc ✅-blokk a
teljes pre-flight/javítókör/review történetért. **Pre-flight** mért egy
scope-rést (a safety-katalógus fájl hiányzott az `allowed_paths`-ból, a
saját doc-commentje és ADR 0188 §Következmények explicit ezt a kört nevezte
meg a bővítés végrehajtójaként) és reserválta az ADR 0191-et. **1 javító
kör**: F1 BLOCKER-t (a setup-elsőbbség nem tartott a saját cooldown alatt —
a szállított teszt saját `reason`-je a hibás viselkedést pinnelte
elvárásként) + F2/F3 MAJOR-t (a `comparisonEvidence` ungated volt; az
emittált confidence a küszöb alá eshetett) + 4 MINOR-t zárt egyszerre.
Az orchesztrátor mindkét fordulót SAJÁT, minden alkalommal friss klónon
függetlenül futtatott gate-tel ellenőrizte — az ELSŐ próba véletlenül egy
elavult (a saját pre-flight-commitra álló) klónon futott 0 új teszttel,
felismerve és korrigálva (L186). Gate zöld a `943be13` merge-előtti SHA-n:
Full Gate ✅ · Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó
push nem érintett trigger-útvonalat). Post-merge gate a friss `main`-en
(`b54490e`) is zöld, 387/387 teszt. Lecke: **L185**, **L186**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r23-feedback-policy-and-cue-budget-review.md) +
[security](docs/reviews/e05-r23-feedback-policy-and-cue-budget-security.md).

**E05-R22 — Vision observation fusion and evidence engine** (PR
[#195](https://github.com/wolfcasaba/strumsight/pull/195), squash `997e7be`,
**ÚJ ADR 0190** observation-fusion-és-evidence szerződésre (a brief előzetes
„0162" hivatkozása sosem lett fájl); implementer **Codex (Terra)** (kezdeti
+ **2 javító kör**), orchesztrátor/reviewer **Claude Sonnet 5**, dedikált
**security-reviewer** ágens `risk = "high"` miatt). `VisionObservation`/
`VisionEvidence`/`EvidenceProvenance`/`ConfidenceModel` + `ObservationFusion`
pipeline — lásd a fejléc ✅-blokk a teljes pre-flight/javítókörök/review
történetért. **Pre-flight (§0.0, 8 pont)** mérte a négy confidence-komponens
tényleges kód-forrását és pinnelte le az `ObservationState` gyártási
szabályát MIELŐTT az implementer elindult volna. **2 javító kör**: 1. kör
zárta F1 MAJOR-t (memóriakorlát csak `fuse()` mellékhatásaként érvényesült
— saját adverzális próbával 12012 megtartott observation egy sosem-fuse-olt
metrikára) + F2 MINOR-t; 2. kör zárta F4 MINOR-t (a dedikált security-review
saját leletét: `ConfidenceComponents` assert-only határ, release-ben
strippelt). Az orchesztrátor mindhárom fordulót SAJÁT, minden alkalommal
friss GitHub-klónon függetlenül futtatott gate-tel ÉS adverzális
próbatesztekkel (a review saját, nem az implementer tesztjei) újra-
ellenőrizte. Gate zöld a `c63f355` merge-előtti SHA-n: Full Gate ✅ ·
Router CI ✅ (mindkettő kézzel dispatch-elve, mert az utolsó push nem
érintett trigger-útvonalat). Post-merge gate a friss `main`-en (`997e7be`)
is zöld, 367/367 teszt. Lecke: **L184** (`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r22-observation-fusion-and-evidence-review.md) +
[security](docs/reviews/e05-r22-observation-fusion-and-evidence-security.md).

**E05-R21 — Audio–vision clock mapping and latency calibration** (PR
[#194](https://github.com/wolfcasaba/strumsight/pull/194), squash `7b11f26`,
**ÚJ ADR 0189** audio–vision szinkron-szerződésre (a brief előre kiosztott
0170-e a batch-írás óta elavult); implementer **Codex (Terra)** (egyetlen
forduló, `continuations=0`), orchesztrátor/reviewer **Claude Sonnet 5**).
`VisionClock`/`AudioClock` boundary + immutable `ClockMapping` (offset+korlátos
drift+confidence) + `SyncQuality` bucketek + `SyncCalibrationController`
(medián-outlier-elutasítás, opcionális lineáris drift-fit, immutable
observation-provenance recalibráció alatt) — lásd a fejléc ✅-blokk a teljes
pre-flight/review történetért. **Pre-flight (§0.0, 4 pont)** mérte a két
tényleges időalapot (vision: monotonic Stopwatch-eredetű µs; audio: wall-clock
`DateTime`) és rögzítette a boundary-konverziós tervezési szabályt egy új
§5.1-ben, MIELŐTT az implementer elindult volna. **APPROVED elsőre, javító kör
nélkül** — 0 BLOCKER/MAJOR, 4 NOTE (mind follow-up). Az orchesztrátor a gate-et
SAJÁT, izolált `/tmp` klónban futtatta újra, ÉS a §6 „valódi-sértés próba"
kritériumot egy harmadik, eldobható klónban maga is reprodukálta
(`DateTime.now()` beszúrása → a forrás-guard teszt PIROS lett, semmi más).
Gate zöld az `f1bc31a` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅
(mindkettő kézzel dispatch-elve, mert az utolsó push nem érintett
trigger-útvonalat). A Full Gate első futása egy kapcsolhatatlan, load-érzékeny
`song_import_controller_test.dart` flake-en pirosra váltott — a pristine
`main`-en 5× izoláltan reprodukálva (0/5 bukás) igazolva kör-független
flake-ként, mielőtt rerun-t futtattam. Post-merge gate a friss `main`-en
(`7b11f26`) is zöld. Lecke: **L182**, **L183** (`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r21-audio-vision-clock-mapping-review.md).

**E05-R20 — Posture metric engine and safety claim guard** (PR
[#193](https://github.com/wolfcasaba/strumsight/pull/193), squash `be38e11`,
**ÚJ ADR 0188** safety-claim-guard-ra, posture-metrika réteg ADR 0179
végrehajtása; implementer **MiniMax M3** (kezdeti + **1 javító kör**),
orchestrátor/reviewer **Claude Sonnet 5**, dedikált **security-reviewer**
ágens `risk = "high"` miatt). Négy pure-Dart proxy-metrika
(`lib/features/vision/domain/metrics/`) + fail-closed safety claim guard
(`lib/features/vision/domain/safety/`) — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **Pre-flight (§0.0, 9 pont)**
javította a stale ADR-hivatkozást, írt egy ÚJ ADR-t (0188), és beépített
egy az E05-R14 lezárt kör security-review-jából KIFEJEZETTEN E05-R20-ra
hagyott, a brief szövegéből korábban hiányzó follow-upot (R8/§5 pont 7:
`PostureObservation.state` sosem mérvadó, mert MINDIG `good`, ha akár
egyetlen landmark közös a baseline-nal). **1 javító kör** zárt 2 MAJOR-t:
a security-reviewer saját próbája (egy orvosi kód ALLOWED osztályba
deklarálva átjutott a guardon) és a saját lelet (`confidenceFormula`
dokumentáció-vs-kód ellentmondás + egy §6 acceptance-kritérium csendesen
nem teljesült). Az orchestrátor mindkét fordulót SAJÁT, friss
GitHub-klónon függetlenül futtatott gate-tel ÉS a kód közvetlen
olvasásával (nem a handoffra hagyatkozva) újra-ellenőrizte. Gate zöld a
`7ad5c49` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅ (mindkettő kézzel
dispatch-elve, mert az utolsó push nem érintett trigger-útvonalat).
Post-merge gate a friss `main`-en (`be38e11`) is zöld, 334/334 teszt.
Lecke: **L179**, **L180**, **L181** (`docs/LESSONS.md`). A dedikált
security-reviewer teljes jelentése a review-fájlba integrálva, nem külön
fájlban. Részletek:
[review](docs/reviews/e05-r20-posture-metrics-and-safety-policy-review.md).

**E05-R19 — Picking-hand stroke metric engine** (PR
[#192](https://github.com/wolfcasaba/strumsight/pull/192), squash `a38e0e0`,
nincs új ADR (ADR 0179/0181 végrehajtása a picking kézre); implementer
**MiniMax M3** (kezdeti + **1 javító kör**), orchestrátor/reviewer
**Claude Sonnet 5**). Hét pure-Dart proxy-metrika
(`lib/features/vision/domain/metrics/`) — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **Pre-flight (§0.0, 5 pont)**
korrigálta a mirror-paritás kritériumot (4→2 cella, E05-R18 F4/L176
megismétlésének megelőzése) és a picking-zóna enum hivatkozást (SDD §20.2,
nem R15 `GuitarRegion`) MIELŐTT az implementer elindult volna. **1 javító
kör** zárta F1 BLOCKER-t (`StrokeWindow.cut()` szomszédos ablakok
mintáit duplikálta gyors váltogatásnál — a review saját, eldobható
próbateszttel reprodukálta ÉS a javítás után újra megerősítette). Az
orchestrátor mindkét fordulót SAJÁT, friss GitHub-klónon függetlenül
futtatott gate-tel ÉS eldobható mutáció-próbákkal (a review saját, nem az
implementer tesztjei) újra-ellenőrizte. Gate zöld a `79c4f49`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Post-merge gate a friss
`main`-en (`a38e0e0`) is zöld, 292/292 teszt. Lecke: **L177**, **L178**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r19-picking-hand-stroke-metrics-review.md).

**E05-R18 — Fretting-hand metric engine** (PR
[#191](https://github.com/wolfcasaba/strumsight/pull/191), squash `75f8766`,
nincs új ADR (ADR 0179/0181 végrehajtása); implementer **MiniMax M3**
(kezdeti + **2 javító kör**), orchestrátor/reviewer **Claude Sonnet 5**).
Hat pure-Dart proxy-metrika (`lib/features/vision/domain/metrics/`) — lásd
a fejléc ✅-blokk a teljes pre-flight/javítókörök/review történetért.
**2 javító kör**: 1. kör zárta BLOCKER-1/F1 (`readyPositionTime`
szerep+visibility-kapu hiánya) + F2/F3/F5 MAJOR; 2. kör (szűkre skálázva)
zárta F4 MAJOR-t (a szállított „4 cellás" paritás teszt bitre azonos
bemenettel semmit nem bizonyított). Az orchestrátor mindhárom fordulót
SAJÁT, minden alkalommal friss GitHub-klónon függetlenül futtatott
gate-tel ÉS eldobható mutáció-próbákkal (a review saját, nem az
implementer tesztjei) újra-ellenőrizte. Gate zöld a `77d6ee0`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Post-merge gate a friss
`main`-en (`75f8766`) is zöld, 225/225 teszt. Lecke: **L175**, **L176**
(`docs/LESSONS.md`). Részletek:
[review](docs/reviews/e05-r18-fretting-hand-metric-engine-review.md).

**E05-R17 — Automatic guitar detector go/no-go decision** (PR
[#189](https://github.com/wolfcasaba/strumsight/pull/189), squash
`e979d41`, **ADR 0187** (új); implementer **MiniMax M3** (kezdeti + 1
javító kör), orchestrátor/reviewer **Claude Sonnet 5**). Go/no-go/
experimental-only döntési keret egy jövőbeli automatikus gitár/nyak-
geometria detektorhoz (nem épít detektort) — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review/önjavítás történetért. **1 javító kör**:
BLOCKER-1 (a `decision()` promóciós logika inverz irányú egy
hiba-metrikán) + MAJOR-1 (dedikált security-review lelete: consent-séma
6/7 kötelező mező). Gate zöld a `8e71e80` merge-előtti SHA-n: Full Gate ✅
· Router CI ✅. A merge utáni closing-rituálokat egy H-NOSIGNAL szakította
meg, self-heal PR #190 zárta. Lecke: **L173**, **L174**. Részletek:
[`docs/handoff-archive.md`](docs/handoff-archive.md) +
[review](docs/reviews/e05-r17-auto-guitar-detector-decision-review.md).

**E05-R16 — Guitar geometry tracking és calibration loss** (PR
[#188](https://github.com/wolfcasaba/strumsight/pull/188), squash
`6f9c0e1`, nincs új ADR (ADR 0179/0181 bővítése); implementer **MiniMax
M3** (kezdeti + 1 javító kör), orchestrátor/reviewer **Claude Sonnet 5**).
`GeometryTracker`/`EdgeGeometryTracker` (könnyű él-/feature-alapú adapter,
nem ML) + `GeometryConfidence` (drift + confidence) + `CalibrationLossMachine`
(`tracking`→`degraded`→`lost` hiszterézises állapotgép) — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review történetért. **1 javító kör**: BLOCKER-1 (a
tracker `null`-refusala halott kóddá tette a gép SAJÁT, helyesen
implementált forward-escalation logikáját a valódi integrációban — egyik
egységteszt sem kötötte össze a két komponenst) + MINOR-1 (dedikált
security-review lelete: `GeometryConfidence` csak `assert`-tel
validált, release-módban nem futott volna). Az orchestrátor mindkét
lezárt leletet SAJÁT, függetlenül futtatott gate-újrafuttatással ÉS egy
a MiniMax tesztjeitől független eldobható próbateszttel újra-ellenőrizte.
Gate zöld a `43a7bc2` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅.
Post-merge gate a friss `main`-en (`6f9c0e1`) is zöld. Lecke: **L172**
(`docs/LESSONS.md`). Részletek:
[`docs/handoff-archive.md`](docs/handoff-archive.md) +
[review](docs/reviews/e05-r16-geometry-tracking-and-calibration-loss-review.md).

**E05-R15 — Guitar coordinate system és homography** (PR
[#187](https://github.com/wolfcasaba/strumsight/pull/187), squash
`a351ad3`, nincs új ADR; implementer **MiniMax M3** teljes egészében —
javító kör 2 a Codex CLI usage-limit önjavítása után user-döntéssel
folytatva ugyanazon a leleten —, orchestrátor/reviewer **Claude Sonnet 5**).
Pure Dart geometriai mag (`Point2`/`Polygon2`/`Homography`/`GuitarSpace`) +
`GuitarLandmarkMapper`/`GuitarRegion` — lásd a fejléc ✅-blokk a teljes
pre-flight/javítókör/review történetért. **2 javító kör**: MAJOR-1
(`Polygon2.contains` előjel-hiba) + MAJOR-2 (hiányzó side/top fixture-ök)
javító kör 1-ben; BLOCKER-1 (kondíciószám-őr vak a projektív sorra) HÁROM
tervezési iteráción át javító kör 2-ben, mindegyiket egy implementer
helyes `stopped` jelzése zárt (nem hiba) — a végleges megoldás közvetlen
`|uv|`-magnitúdó ellenőrzés, nem küszöb-proxy. Az orchestrátor mindhárom
lezárt leletet SAJÁT, függetlenül futtatott gate-újrafuttatással ÉS egy
valódi-sértés (mutáció) próbával újra-ellenőrizte, nem az implementer
önjelentésére hagyatkozva. Dedikált security-review (risk=high) — innen
indult a BLOCKER-1. Gate zöld a `6b2f854` merge-előtti SHA-n: Full Gate ✅
· Router CI ✅. Post-merge gate a friss `main`-en (`a351ad3`) is zöld.
Lecke: **L171** (`docs/LESSONS.md`), **L27 megerősítve**. Részletek: fejléc
✅-blokk +
[review](docs/reviews/e05-r15-guitar-coordinates-and-homography-review.md) +
[security](docs/reviews/e05-r15-guitar-coordinates-and-homography-security.md).

**E05-R14 — Pose landmark provider és posture baseline** (PR
[#185](https://github.com/wolfcasaba/strumsight/pull/185), squash
`efa4bbe`, **ADR 0186** (új, ADR 0178/0185 kiterjesztéseként); implementer
**MiniMax M3** (kezdeti + javító kör 1) → **Codex/Terra** (javító kör 2,
motor-eszkaláció), orchestrátor/reviewer **Claude Sonnet 5**).
Adatminimalizált felsőtest-pose pipeline arcelemzés nélkül — lásd
[`docs/handoff-archive.md`](docs/handoff-archive.md) a teljes
pre-flight/javítókör/review történetért. **2 javító kör**: F1 MAJOR
(hamis „format: ZÖLD" önjelentés) + S-MAJOR-1 MAJOR (privacy-audit gépi
őr fedezete gyengébb volt, mint ígért), mindkettő az orchestrátor SAJÁT
próbáival újra-ellenőrizve. Dedikált security-review (risk=high) **PASS**
(S-MAJOR-1 fixed). Gate zöld a `fe9d756` merge-előtti SHA-n: Build APK ✅
· Router CI ✅. Lecke: **L167, L168, L169**. Részletek:
[docs/handoff-archive.md](docs/handoff-archive.md) +
[review](docs/reviews/e05-r14-pose-provider-and-posture-baseline-review.md) +
[security](docs/reviews/e05-r14-pose-provider-and-posture-baseline-security.md).

**E05-R13 — Hand track assignment és temporal smoothing** (PR
[#184](https://github.com/wolfcasaba/strumsight/pull/184), squash
`148469c`, nincs új ADR; implementer **MiniMax M3**, orchestrátor/reviewer
**Claude Sonnet 5**). Stabil fretting/picking hand-track jitter és rövid
takarás ellen — lásd a fejléc ✅-blokk a teljes pre-flight/javítókör/review
történetért. **1 javító kör** (MiniMax), mindhárom lelet (F1 BLOCKER — a
jump-rejection nem épült fel valós, tartós pozícióváltásból; F2 MAJOR — a
`TrackContinuity` latency/jitter mezői élettelenek voltak; F3 MINOR — a
simított visibility monoton MAX volt) az orchestrátor SAJÁT, függetlenül
futtatott próbateszteivel újra-ellenőrizve, nem az implementer
önjelentésére hagyatkozva. Dedikált security-review (risk=high) **PASS**,
futott a merge ELŐTT (L162 helyesen alkalmazva). Gate zöld a `2ef9455`
merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Lecke: **L165, L166**.
Részletek: fejléc ✅-blokk +
[review](docs/reviews/e05-r13-hand-track-assignment-and-smoothing-review.md) +
[security](docs/reviews/e05-r13-hand-track-assignment-and-smoothing-security.md).

**E05-R10 — Camera + guitar calibration domain és verziózott tárolás**
(PR [#181](https://github.com/wolfcasaba/strumsight/pull/181), squash
`39d1c29`, nincs új ADR; implementer **MiniMax M3**, orchestrátor/reviewer
**Claude Sonnet 5**). Verziózott kalibrációs domain (kamera + gitárgeometria)
öt-cellás validity-mátrixszal és determinisztikus, migrálható JSON codeckel.
**Örökség-eset** (ADR 0087 §0.2): pre-flight+implementáció egy korábbi,
jelzés nélkül megszakadt sessionből örökölve. **3 javító kör**, mindegyik az
orchestrátor saját mutáció-kill próbáival függetlenül újra-ellenőrizve: (1)
MiniMax — F1 hiányzó falszifikáció a migrációs mátrix vN+1 cellájában (csak
a meglévő envelope-őrt mérte, nem a kör saját codec-szintű őrét) + F2
`neckPolygon` nem valódi immutable; (2) Codex — dedikált security-review
MAJOR-1: `ArgumentError` (nem `Exception`) megszökik a `read()`
`on Exception` őrén korrupt orientationre, crash karantén helyett; (3)
Codex — MAJOR-2, az orchestrátor SAJÁT felfedezése MAJOR-1 javításának
újra-ellenőrzése közben: öt kézzel írt teszt (a MiniMax eredeti köréből
négy, a MAJOR-1 regressziós cellája az ötödik) a hiányzó belső
`schemaVersion` mező miatt csendben a legacy migrációs ágra tévedt, mindegyik
véletlen okra bukva — az acceptance #4/#7 az aktuális (nem-legacy) útra
bizonyítatlan maradt egészen eddig. Review **APPROVED**; dedikált
security-reviewer **PASS**. Gate zöld a `40a3d44` merge-előtti SHA-n:
Full Gate ✅ · Router CI ✅. Lecke: **L160**. Részletek: fejléc ✅-blokk +
[review](docs/reviews/e05-r10-calibration-domain-and-store-review.md) +
[security](docs/reviews/e05-r10-calibration-domain-and-store-security.md).

**E05-R07 — Frame transform és overlay koordinátarendszer** (PR [#169](https://github.com/wolfcasaba/strumsight/pull/169), squash `b5837d9`, nincs új ADR; implementer **Terra**, orchestrátor/reviewer **Claude Sonnet 5**). Pure Dart koordináta-transzformáció-réteg (`CameraTransform<From, To>`, `CameraCoordinateSpace`, `PreviewFit`) a sensor→upright→normalized→preview→overlay terek között. 1 javító kör (F1/MAJOR: az overlay-mapping a brief §1 célja szerint kötelező volt, de eredetileg elérhetetlen maradt — `CameraTransform.previewToOverlay()` identitás-transzformmal zárva). Review **APPROVED** javító kör után; dedikált security-reviewer **PASS** (1 carry-forward MAJOR — assert-only validáció — kötelező R13/R15/R24 előtt). Gate zöld a `9c52d74` merge-előtti SHA-n: Full Gate ✅ · Router CI ✅. Részletek: fejléc ✅-blokk + [review](docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-review.md) + [security](docs/reviews/e05-r07-frame-transform-and-overlay-coordinates-security.md).

**E05-R01 — Vision baseline, capability audit & hat alapozó ADR** (PR [#162](https://github.com/wolfcasaba/strumsight/pull/162), squash `cef864c`, **hat új ADR: [0178](docs/adr/0178-vision-privacy-by-default.md)–[0183](docs/adr/0183-vision-no-raw-frame-persistence.md)**; implementer **DeepSeek v4 Pro**, az ADR-eket az orchestrátor (**Claude Opus 4.8**, ADR 0055) írta a pre-flightban). Az Epic 5 (Computer Vision) INDUL: mérhető baseline (nyers parancs+kimenet), kétoszlopos metrika-lista, device-mátrix/benchmark sablon és a hat kötelező vision architekturális döntés. **Production kód NEM változott** (docs-only Kör 1). Review **APPROVED** javító kör nélkül (0 BLOCKER/MAJOR/MINOR, 1 NOTE). Gate zöld a `7a9d9e0` merge-SHA-n: Full Gate ✅ · Router CI ✅. Lecke: **L143**. Részletek: fejléc ✅-blokk + [review](docs/reviews/e05-r01-vision-baseline-and-adrs-review.md).

**E04-R23 — Tutor safety, prompt-injection, usage & evaluation gate** (PR [#159](https://github.com/wolfcasaba/strumsight/pull/159), squash `04787fa`, **ADR [0177](docs/adr/0177-ai-tutor-safety-injection-usage-evaluation-gate.md)**; implementer **DeepSeek v4 Pro** (`deepseek/deepseek-v4-pro`, Kilo-profil), orchestrátor/reviewer **Claude Opus 4.8**).

**Elkészült:** a tutor production-rollout előtti formális kapui — safety-policy (strictest-wins kategória → verdikt), claim-provenance validator (R16 grounding-taxonómia **újrahasználva**, invented-metric hard blokk), backend safety+redaction+size-guard, evaluation CLI + adversarial/capability dataset + `tutor-eval.yml` merge-gate **négy géppel számított** metrikára (schema/action/groundedness/safety). Injection nem emel tool-permissiont; CI fake/approved provider (nincs cloud-secret).

**Falszifikációs cellák (kipinnelve):** minden safety-kategóriához input→block/refuse unit-cella; invented-metric hard blokk (`unsupportedClaimEvidence`); injection-no-permission dataset-cella; a küszöb-mátrix below/at/above hármasa. Piros-út bizonyítva: `dart run … run_eval.dart` küszöb alatti dataseten safety_coverage 94% → exit 1; tiszta dataseten 100% → exit 0.

**Javító kör (1, DeepSeek) + orchestrátor scope-akciók:** 3 MAJOR zárva — ruff-check red (import-sort+F401, `8ed8db5`), hardcode-olt schema/action metrikák → tényleges dataset-számítás (`aeca3fe`), dispatchelt zöld + reprodukált piros evidencia. Orchestrátor: `public.dart` **scope-szűkítés** vissza az üres baseline-re (a merge-elt E04-R01 boundary-guard miatt, export halasztva; `3d93839`) + backend `ruff format` (`0dd9ed7`). Re-review **APPROVED**; security review **PASS** (0 BLOCKER). Gate zöld a `0dd9ed7` merge-SHA-n: Full Gate ✅ · Router CI ✅ · Backend CI ✅.

_(A korábbi körök részletes története: [`docs/handoff-archive.md`](docs/handoff-archive.md) — E04-R22 és korábbiak; E04-R22 összefoglalója a fejléc ✅-blokkjaiban.)_

**E04-R22 — Tutor Profile, Privacy, Data & Consent UI** — KÉSZ (PR #157, `faa3f32`, nincs új ADR — ADR 0132+0134 hatálya; MiniMax M3; ld. fejléc ✅-blokk).

## 6. Exact next task

**A soron következő SDD-lépés: E07-R06** (Chapter 8, Kör 6 — SkillEstimate
reducer és konfliktuskezelés,
[`e07-r06-skill-estimate-reducer.md`](docs/rounds/e07-r06-skill-estimate-reducer.md)).
Az E07-R05 evidence-contractjaihoz kell mérni; a practice-generator flagek
változatlanul `false` maradnak.

**Egyéb, Epic 7-től FÜGGETLEN, EMBERI döntést igénylő irányok** (az Epic 6
completion report `docs/sdd/epic-06-completion-report.md` „Nyitott tételek"
táblája nevezi meg, változatlan az E06-R30 óta — a GOV-30c mind az öt
lépcsője kész az E99-R13 óta, lásd `docs/handoff-archive.md`):

1. **Valódi eszközös elfogadás** — a 14 pontos Kör 30 lista + a teljes
   `docs/manual-testing/analysis-eval-matrix.md` PENDING sorai (EVAL-01…41,
   Epic 5 device-mátrix is még nyitott) — user-feladat, real gitáros
   teszt.
2. **GOV-30a** — valódi kalibrációs dataset/riport (ma `identity.v1`,
   szintetikus).
3. **GOV-30b** — az R29 evaluation CI-lépés bekötése (`.github/workflows/**`,
   `tool/ci/**` — ez a fájlkör szándékosan tilos zóna minden eddigi GOV-30c
   körben, H-GATEGUARD).
4. **Opt-in/default-on rollout és a V1 kivezetése** — külön, jóváhagyott
   GOV-kör, Product/User döntés (a GOV-30c lezárása óta sem lett elfogadva
   semmilyen flag `true`-ra állítása, sem az Epic 6, sem az Epic 7 flagjeire).
5. **GOV-05b bekötő köre** (AI Tutor `main.py` OpenAI-adapter bekötés) —
   régóta nyitott track, brief-je még nincs megírva (ld. lent, változatlan).

Egyik irány sem automatikusan folytatható a queue-ból — mindegyik vagy
emberi döntést, vagy egy még meg nem írt briefet igényel. **A pipeline a
következő session-ben NE találjon ki magától egy irányt** — kérdezze meg a
usert, melyik legyen a következő SDD-kör vagy GOV-kör.

> (A lenti, E06-R19-cel kezdődő szakasz a 2026-08-12 előtti GOV-05/06
> governance-sagát rögzíti — történeti kontextusként hagyva.)

**Korábbi kijelölt SDD-kör (2026-08-12, azóta lezárult): E06-R19 —
Confidence calibration és capability resolver** (Chapter 7, Kör 19). Új
sessionben induljon; E06-R18 lezárult.
Pre-flightban az új technique-proxy contractot, a flag/Lab kaput és minden
confidence-producer tényleges elérhetőségét újra mérje.

> ### 🔒 Kötelező sorrend az Epic 5 után (user-döntés, 2026-08-07)
>
> **„várjuk meg amíg az Epic 5-tel végzünk, majd csináljuk a shipping kört
> először, majd egy valós audio mérés, és csak ezek után lépjünk az Epic 6-ra."**
>
> 1. ~~**Epic 5 befejezése**~~ — ✅ **KÉSZ** (E05-R30, `d3b2caf9`).
> 2. ~~**Az Epic 5 APK-ellenőrzése** a usernél~~ — **KIHAGYVA, user-döntés
>    2026-08-09** („mehet a 3. 4. pont"). Mért indok: a 11 vision flag
>    hard-kódolt `false` volt minden környezetben, tehát egy akkori APK-menet
>    csak regressziót tudott volna mérni, a vision-t nem. A készülékes
>    bizonyíték a GOV-05a/b/c rollout-körök device-mátrix sorain gyűlik.
> 3. **GOV-05 — Shipping rollout.** **HÁROM körre bomlott** (orchesztrátor-
>    döntés 2026-08-09; mért indok a 3.0 pontban):
>    - **GOV-05a** = `E99-R01` — Practice V2 + Song Trainer V2 → ✅ **KÉSZ**
>      (PR #205, `d958b75e`, ADR 0197).
>    - **GOV-05b** = `E99-R02` — **AI Tutor internal rollout → ⛔ BLOKKOLT,
>      EMBERI DÖNTÉST IGÉNYEL** (mérve 2026-08-09, lásd §3 „AI Tutor
>      production-drótozás"). NEM indítható, amíg a döntés nincs meg.
>    - **GOV-05c** = `E99-R03` — **Learn migráció** (`migratedLearnEnabled`).
>      A legkockázatosabb: egy MÁR szállított feature mögött cseréli a motort.
>      Meglévő őrök: `test/features/learn/learn_migration_parity_test.dart`,
>      `learn_rollback_test.dart`; az `AppConfig.resolve` már kényszeríti a
>      `practiceEngineV2Enabled` függőséget.
> 3.0 **Miért három kör, és miért NEM tartalmazza a vision-t.** Két mérés
>    döntötte el, mindkettő `main @ bbc95187`-en:
>    (a) **Belépési pontok:** a flag-gated route-okra **nulla** hivatkozás
>    mutatott a `lib/`-ben, tehát minden feature-családhoz külön UI-mozdulat
>    kell — három család egyszerre nem lenne review-zható, és egy készülékes
>    hiba nem lenne betudható.
>    (b) **A vision rollout BLOKKOLT** (→ **GOV-05d**, lásd §3): az
>    `assets/ml/model_manifest.json` `vision_models` mindkét bejegyzése
>    (`hand_landmarker`, `pose_landmarker`) `status: "deferred"`, `sha256`
>    csupa nulla, és a hivatkozott `.tflite` fájlok **nincsenek a repóban**
>    (`ls assets/ml/` → négy audio `.bin` + a manifest). A
>    `NativeHandLandmarkProvider:77` / `NativePoseLandmarkProvider:76`
>    `deferred` bejegyzésre `AppResult.failure`-t ad, tehát a `visionEnabled`
>    bekapcsolása egy zsákutcába futó setup-folyamatot tenne láthatóvá. A
>    flag-flip előfeltétele a modell-binárisok beszerzése + licenc-átvezetés.
> 4. ~~**GOV-06 — Valós-audio DSP baseline mérés.**~~ — ✅ **KÉSZ** (E99-R04,
>    `5ceed22d`; BPM-metrikája javítva **GOV-06b, E99-R05, `c4ce2cc0`**). A
>    meglévő shipping DSP pontossága valódi gitárfelvételeken: akkord-
>    pontosság **67,069%** (18,832%-os baseline fölött), onset F1@50ms
>    **67,391%**. A harmadik szám (a GOV-06 eredeti, `.strums`-alapú
>    „BPM-MAE 45,067") **érvénytelennek bizonyult és visszavonva** (GOV-06b) —
>    a helyette mért független (librosa) tempó-egyezés **11/82 = 13,415%**
>    szigorú / **32/82 = 39,024%** metrikai-szint toleráns; a BPM ezen a
>    korpuszon validált kézi annotáció híján **nem mérhető**. A korpusz
>    (`ml/data/klangio/`, 82 felvétel) NEM verziókövetett — a mérés
>    elkötelezett riport, nem CI-kapu; a verziókövetés nevesített follow-up.
>    Teljes riport: [`docs/eval/real-audio-dsp-baseline.md`](docs/eval/real-audio-dsp-baseline.md).
> 5. ~~**Csak ezután Epic 6**~~ — ✅ **FELOLDVA, user-döntés 2026-08-11**
>    („mehet tovább az epic 6"): a 3. ÉS 4. pont lezárult (2026-08-09), az
>    5. pont feltétele teljesült, mind a 30 Epic 6 sor `hold`→`pending`
>    (`docs/execution/pipeline-queue.tsv`, `7d5bfd4a`). **E06-R01** (Epic 6
>    Kör 1: V1 baseline + hat kötött ADR) ✅ **KÉSZ** — lásd a fejléc
>    ✅-blokk. A lánc a szokásos módon folytatható, `PIPELINE_SLOTS=1`
>    (user-döntés 2026-08-11: „nem kell dupla kör haladunk sorban").
>
> A GOV-05b/GOV-05c/GOV-06 briefje **szándékosan még nincs megírva**: mindegyik
> pre-flightjának az ELŐZŐ kör utáni állapotot kell mérnie (mind ugyanazt a
> `feature_flags.dart` / `lesson_list_screen.dart` felületet érinti, tehát az
> előre írt fájllisták ütköznének és avulnának). Az Epic 6 queue-sorai
> addig is `hold`-on védik a sorrendet.
>
> **Governance-kör azonosítás:** a GOV-körök `E99-RNN` alakot kapnak, mert a
> `tools/ai_router/brief.py:19` és a `tools/round-pipeline.sh:278` mintája a
> „GOV-05a" alakú nevet kiejtené a gépi kapukból. Az `E99` **nem valódi epic**.
> A GOV-körök a queue-n KÍVÜL futnak (kézi orchesztrálás), a GOV-01 mintájára.

0a. **Az Epic 6 lánc KÖVETKEZŐ KÖRE: E06-R02** (AnalysisDocument V2
   domainmodell, `docs/rounds/e06-r02-analysis-document-v2-domain.md`) — a
   queue `pending`, a pipeline a szokásos módon dispatch-eli. Az E06-R01
   (Kör 1) ✅ **KÉSZ** (lásd a fejléc ✅-blokk); 28 további Epic 6 kör van
   hátra (`epic-06-batch-index.md`). A queue soronként, EGYESÉVEL halad
   (`PIPELINE_SLOTS=1`, user-döntés 2026-08-11).

0b. **Ettől FÜGGETLENÜL, még nyitva: a GOV-05b bekötő köre — a backend
   `main.py` bekötése az OpenAI-adapterre (briefje még nincs megírva).**
   A GOV-körök a queue-n KÍVÜL futnak (kézi orchesztrálás) — ez a track
   nem az Epic 6 lánc része, és az Epic 6 dispatch-ok nem érintik. A backend adapter
   (E99-R07) és a Dart-oldali transport+provider-bedrótozás (E99-R06) is
   kész; ami hátravan, a `main.py` registry/gateway-kiválasztásának bekötése
   az `OpenAiProviderGateway`-re (ma kizárólag `FakeProviderGateway`-t épít),
   a `RemoteTutorModelGateway` Dart-oldali élesítése (authentikált
   `Dio`-val — a `/tutor/stream` JWT-t vár, E99-R06 review NOTE-1) és a
   flag-rollout. A pre-flightnek az E99-R07 utáni állapotot kell mérnie.

   **A user 2026-08-09-én újranyitotta a GOV-05b-t** („a négy konkrét darab is
   csináljuk meg", provider: „open ai legyen"). A négy darabból:

   | # | Darab | Állapot |
   |---|---|---|
   | 1 | Backend OpenAI provider-adapter | ✅ **KÉSZ** (E99-R07, PR #210, ADR 0214) |
   | 2 | Dart konkrét `TutorStreamTransport` | ✅ **KÉSZ** (E99-R06, PR #209) |
   | 3 | A három provider bedrótozása | ✅ **KÉSZ** (E99-R06, PR #209) |
   | 4 | Hosztolás + OpenAI API-kulcs | **user-feladat** |

   Mind a négy darab elkészült vagy user-feladatra vár — de az adapter (#1)
   MÉG NINCS bekötve a `main.py` bootjába (E99-R07 tudatosan nem tette, ADR
   0214 Döntés 2/OD-04): `tutor_provider` alapértéke `"fake"` marad, az
   `aiTutorEnabled` bekapcsolása változatlanul crash-mentes, de valódi
   OpenAI-hívás még nem érhető el éles úton. Ez a bekötés a fenti következő
   kör dolga.

   **A §6 sorrend mind az 5 pontja LEZÁRULT** (GOV-05a ✅, GOV-05c ✅, GOV-06
   ✅ + GOV-06b ✅, Epic 6 feloldása ✅ 2026-08-11). A GOV-05b lánca ettől
   FÜGGETLENÜL fut, és változatlanul nyitva (0b pont).

   **A pipeline-lánc AKTÍV:** `docs/execution/pipeline-queue.tsv` minden
   E05-sora `done`, E06-R01 `done`, a többi 29 E06-sor **`pending`** — a
   lánc E06-R02-vel folytatódik, `PIPELINE_SLOTS=1` szerint egyesével.

   **~~E06-R01 — Analyze V1 baseline, mérés és ADR-ek~~ — KÉSZ** (PR #211,
   `62516a4b`, **ÚJ ADR 0215–0220**; implementer Codex/Terra, 1 forduló,
   javító kör nélkül; lásd a fejléc ✅-blokk a teljes történetért).

   **~~E99-R04 (GOV-06) — Valós-audio DSP baseline mérés~~ — KÉSZ** (PR
   #207, `5ceed22d`, **ÚJ ADR 0199**; implementer Codex/Terra, 1 forduló,
   javító kör nélkül; lásd a fejléc ✅-blokk a teljes történetért).

   **~~E99-R03 (GOV-05c) — Learn migráció a Practice Engine V2-re~~ — KÉSZ**
   (PR #206, `0e9d211c`, **ÚJ ADR 0198**; implementer Codex/Terra, 1
   forduló, javító kör nélkül — a pre-flight mérése pontosan a szállított
   módosítás alakját írta le; review APPROVED, 0 BLOCKER/MAJOR/MINOR, 1
   NOTE, reviewer SAJÁT izolált-klón gate-újrafuttatással (10/10 zöld) +
   SAJÁT valódi-sértés próbával függetlenül ellenőrizve; dedikált
   security-reviewer risk=high **PASS**, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 2
   NOTE; ld. fejléc + §4).
   **~~E99-R01 (GOV-05a) — Practice V2 + Song Trainer V2 shipping rollout~~ — KÉSZ**
   (PR #205, `d958b75e`, **ÚJ ADR 0197**; implementer Codex/Terra, 1
   implementációs + 1 javító forduló — az első fordulóban helyes `stopped`
   scope-jelzés, dokumentált §0.0 R1 revízióval feloldva; review APPROVED,
   0 BLOCKER/MAJOR, 1 MINOR + 3 NOTE; ld. fejléc).
   **~~E05-R30 — Dataset, evaluation, minőségi kapuk és Epic 5 lezárás~~ — KÉSZ**
   (PR #204, `d3b2caf9`, nincs új ADR — záró-kör waiver; implementer
   Codex/Terra, egyetlen forduló, javító kör nélkül; dedikált
   security-reviewer risk=high PASS; 1+2 MINOR mind forward-looking/lezárva,
   7 NOTE; ld. fejléc + §4 + §5).
   **~~E05-R29 — Device tier, performance és thermal hardening~~ — KÉSZ**
   (PR #203, `8e7eb6f9`, **ÚJ ADR 0196**; implementer Codex/Terra, egyetlen
   forduló, javító kör nélkül; dedikált security-reviewer risk=high PASS;
   1 MINOR + 4 NOTE; ld. `docs/handoff-archive.md`).
   **~~E05-R25 — Practice Engine vision integration~~ — KÉSZ**
   (PR #199, `9b608cf`, **ÚJ ADR 0192** practice-vision-integration-contract
   szerződésre; implementer Codex/Terra, egyetlen forduló (köztes
   pre-flight-eredetű `stopped` önjavítva, 0 javító kör); dedikált
   security-reviewer risk=high PASS, 1 nem-blokkoló MINOR (barrel-szimbólum-
   rés) → E05-R26 pre-flight bemenet; ld. fejléc + §3 + §5).
   **~~E05-R24 — Vision session controller and realtime overlay~~ — KÉSZ**
   (PR #197, `e9257f4`, nincs új ADR; implementer Codex/Terra, 2 javító kör;
   dedikált security-reviewer risk=high; 1 BLOCKER + 1 MAJOR + 1 MINOR pass 1,
   1 önjavítás-eredetű BLOCKER pass 2; H5 self-heal PR #198 a queue
   mért-motor szinkronjára; ld. §5 + `docs/handoff-archive.md`).
   **~~E05-R23 — Feedback policy and realtime cue budget~~ — KÉSZ**
   (PR #196, `b54490e`, **ÚJ ADR 0191** feedback-policy-és-cue-budget
   szerződésre; implementer Codex/Terra, 1 javító kör; dedikált
   security-reviewer risk=high; 1 BLOCKER + 2 MAJOR + 4 MINOR a javító
   körben zárva; ld. fejléc + §5).
   **~~E05-R22 — Vision observation fusion and evidence engine~~ — KÉSZ**
   (PR #195, `997e7be`, **ÚJ ADR 0190** observation-fusion-és-evidence
   szerződésre; implementer Codex/Terra, 2 javító kör; dedikált
   security-reviewer risk=high PASS; 1 MAJOR + 2 MINOR a javító körökben
   zárva; ld. fejléc + §5).
   **~~E05-R21 — Audio–vision clock mapping and latency calibration~~ — KÉSZ**
   (PR #194, `7b11f26`, **ÚJ ADR 0189** audio–vision szinkron-szerződésre;
   implementer Codex/Terra, egyetlen forduló; APPROVED elsőre, javító kör
   nélkül; ld. fejléc + §5).
   **~~E05-R20 — Posture metric engine és safety policy~~ — KÉSZ**
   (PR #193, `be38e11`, **ÚJ ADR 0188** safety-claim-guard-ra, posture-fél
   ADR 0179 végrehajtása; implementer MiniMax M3, 1 javító kör; dedikált
   security-reviewer risk=high, 2 MAJOR a javító körben zárva; ld. fejléc + §5).
   **~~E05-R19 — Picking-hand stroke metric engine~~ — KÉSZ**
   (PR #192, `a38e0e0`, nincs új ADR — ADR 0179/0181 végrehajtása;
   implementer MiniMax M3, 1 javító kör; ld. fejléc + §5).
   **~~E05-R18 — Fretting-hand metric engine~~ — KÉSZ**
   (PR #191, `75f8766`, nincs új ADR — ADR 0179/0181 végrehajtása;
   implementer MiniMax M3, 2 javító kör; ld. fejléc + §5).
   **~~E05-R17 — Automatic guitar detector go/no-go decision~~ — KÉSZ**
   (PR #189, `e979d41`, **ADR 0187** (új); implementer MiniMax M3, 1
   javító kör; dedikált security-reviewer risk=high, MAJOR lelet a javító
   körben zárva; ld. fejléc).
   **~~E05-R16 — Guitar geometry tracking és calibration loss~~ — KÉSZ**
   (PR #188, `6f9c0e1`, nincs új ADR — ADR 0179/0181 bővítése; implementer
   MiniMax M3, 1 javító kör; dedikált security-reviewer risk=high, MINOR
   lelet a javító körben zárva; ld. fejléc).
   **~~E05-R15 — Guitar coordinate system és homography~~ — KÉSZ**
   (PR #187, `a351ad3`, nincs új ADR; implementer MiniMax M3 (mindkét
   javító kör); dedikált security-reviewer risk=high — innen indult
   BLOCKER-1; ld. fejléc + §5).
   **~~E05-R14 — Pose landmark provider és posture baseline~~ — KÉSZ**
   (PR #185, `efa4bbe`, ADR 0186; implementer MiniMax M3 → Codex/Terra
   (javító kör 2); dedikált security-reviewer PASS; ld. docs/handoff-archive.md + §5).
   **~~E05-R13 — Hand track assignment és temporal smoothing~~ — KÉSZ**
   (PR #184, `148469c`, nincs új ADR; implementer MiniMax M3; 1 javító kör;
   dedikált security-reviewer PASS, futott a merge előtt; ld. fejléc + §5).
   **~~E05-R12 — Hand landmark provider adapter és model manifest~~ — KÉSZ**
   (PR #183, `f39d7b6`, ADR 0185; implementer MiniMax M3; 1 javító kör;
   dedikált security-reviewer PASS (post-merge, orchestrátor-mulasztás
   pótolva); ld. fejléc).
   **~~E05-R11 — Manual guitar geometry calibration UI~~ — KÉSZ** (PR #182,
   `113976a`, nincs új ADR; implementer MiniMax M3; 1 javító kör (3
   BLOCKER); dedikált security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).
   **~~E05-R10 — Camera + guitar calibration domain és verziózott tárolás~~ — KÉSZ**
   (PR #181, `39d1c29`, nincs új ADR; implementer MiniMax M3; 3 javító kör
   (MiniMax 1 + Codex 2); dedikált security-reviewer PASS; ld. fejléc + §5).
   **~~E05-R09 — Frame quality assessor~~ — KÉSZ** (PR #180; 1. kísérlet
   külső GitHub-incidensbe futott, önjavító retry; ld. fejléc).
   **~~E05-R08 — Vision setup wizard és camera profile~~ — KÉSZ** (PR #170,
   `eff1eaf`, nincs új ADR; implementer Terra; 0 javító kör; dedikált
   security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).
   **~~E05-R07 — Frame transform és overlay koordinátarendszer~~ — KÉSZ** (PR #169, `b5837d9`,
   nincs új ADR; implementer Terra; 1 javító kör (overlay-mapping pótlása);
   dedikált security-reviewer PASS, 1 carry-forward MAJOR R13/R15/R24 elé; ld. fejléc + §5).
   **~~E05-R06 — Android camera production adapter~~ — KÉSZ** (PR #168, `a43f8c1`,
   nincs új ADR; implementer Terra; 1 javító kör (teszt-minőség); dedikált
   security-reviewer PASS; ld. fejléc + docs/handoff-archive.md).

   _(A korábbi, Epic 4-es „exact next task" bejegyzések innentől lefelé
   történeti maradványok — az Epic 4 lezárult E04-R24-gyel, ld. fejléc-archívum.)_
   **~~E04-R23 — Tutor safety, injection, usage & evaluation gate~~ — KÉSZ** (PR #159, `04787fa`,
   ADR 0177; implementer DeepSeek v4 Pro; 1 javító kör + 2 orchestrátor scope-akció; ld. fejléc + §5).
   **~~E04-R22 — Tutor Profile, Privacy, Data & Consent UI~~ — KÉSZ** (PR #157, `faa3f32`,
   nincs új ADR — ADR 0132+0134 hatálya; implementer MiniMax M3; ld. fejléc + §5).
   **~~E04-R21 — Song Trainer debrief & range action integráció~~ — KÉSZ** (PR #156, `6000b57`,
   nincs új ADR — ADR 0132+0089 hatálya; implementer Codex/Terra; a re-scoped §0.0
   struktúra+capability+redaction szelet; korábbi H3 BLOCKER-1-et a merge-elt ADR 0176
   oldotta fel — rebase a javított main-re; a halasztott result/range/setlist szelet
   külön prerekvizit kört igényel; ld. fejléc + §5).
   **~~E04-R20 — Practice & Analyze post-session tutor integráció~~ — KÉSZ** (PR #153, `3ce4afc`,
   nincs új ADR — ADR 0132 hatálya; implementer Codex/Terra; §0.0-R1 public.dart
   scope-narrowing az E04-R01 boundary-teszt miatt; ld. fejléc + §5).
   **~~E04-R19 — Evidence, source & action card UI~~ — KÉSZ** (PR #152, `f0f74fb`,
   nincs új ADR — ADR 0132+0133 hatálya; implementer MiniMax M3; első futás stalled →
   folytató dispatch salvage; ld. fejléc + §5).
   **~~E04-R18 — Tutor Home, Chat UI & streaming UX~~ — KÉSZ** (PR #151, `104e685`,
   nincs új ADR — ADR 0131+0134 hatálya; implementer MiniMax M3; box-timeout salvage
   + 2 teszt-fix javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R17 — Conversation repository, summary & inspectable memory~~ — KÉSZ** (PR #148, `1e9b2db`,
   nincs új ADR — ADR 0134 hatálya; implementer Codex; 2 MAJOR zárva javító kör #1-ben; ld. fejléc + §5).
   **~~E04-R16 — Tutor orchestration state machine & output validator~~ — KÉSZ** (PR #147, `df25806`,
   ADR 0174; implementer Codex; ld. fejléc + §5).
   **~~E04-R15 — Backend + Flutter streaming transport~~ — KÉSZ** (PR #145, `1fe91d2`,
   ADR 0142; implementer qwen38-max; H3 self-heal #143 után; ld. a fejléc-összefoglalót és §5).
   **~~E04-R14 — Backend tutor proxy, provider registry & usage guard~~ — KÉSZ** (PR #142, `c1c0a77`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-coder-plus; ld. §5 archívum).
   **~~E04-R13 — TutorModelGateway & scripted fake~~ — KÉSZ** (PR #141, `b9d2950`,
   nincs új ADR — ADR 0131 hatálya; implementer qwen-plus; ld. a fejléc-összefoglalót és §5).
   **~~E04-R12 — Prompt templatek, output schema & injection boundary~~ — KÉSZ** (PR #140, `c5b14e5`,
   ADR 0141, ld. a fejléc-összefoglalót és §5).
   **~~E04-R11 — Action proposal & confirmation~~ — KÉSZ** (PR #137, `479550f`,
   ADR 0139, ld. §5 snapshot).
   **~~E04-R10 — Tutor Tool contract & read-only registry~~ — KÉSZ** (PR #136, `2f7fffc`,
   ADR 0137, ld. §5 snapshot).
   **~~E04-R08 — Deterministic debrief coaching~~ — KÉSZ** (a queue sora, ld. archívum).
   **~~E04-R07 — Offline knowledge index & retrieval~~ — KÉSZ** (PR #130, `8182204`,
   ADR 0136, ld. a fejléc-összefoglalót és §5).
   **~~E04-R06 — Knowledge schema & content pack~~ — KÉSZ** (PR #129, `f3d69ef`,
   ADR 0135).
   **~~E04-R05 — Context adapters & snapshot~~ — KÉSZ** (PR #128, `55d640d`).
   **~~E04-R04 — Skill taxonomy & evidence reducer~~ — KÉSZ** (PR #127, `0d7ab1b`).
   **~~E04-R03 — Student/guitar profile, goals & consent~~ — KÉSZ** (PR #126,
   `06ae3f7`).
1. **~~E03-R22 lezárási lánc~~ — KÉSZ** (PR #123, `3ae368a`, Epic 3 zárva).
1. **Historical pipeline snapshot (superseded): ~~E03-R01~~, ~~E03-R02~~, ~~E03-R03~~, ~~E03-R04~~, ~~E03-R05 —
   Validator, normalizer, capabilities~~, ~~E03-R06 — Legacy Song/Setlist
   migrációs adapter~~ és ~~E03-R07 — Fájlrendszeres Song repository és
   asset store~~ — KÉSZ, ld. §5.** Következő:
   **E03-R08 — Legacy adatok tartós V2 migrációja**
   ([docs/rounds/e03-r08-persistent-v2-migration.md](docs/rounds/e03-r08-persistent-v2-migration.md)).
   A `docs/execution/pipeline-queue.tsv` E03-R08 sora `pending` — a driver
   automatikusan folytatja (mid-epic round, nincs emberi kapu, ADR 0087 §7).
1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése. Az APK a PR #37
   CI-runjából tölthető
   ([30673821431](https://github.com/wolfcasaba/strumsight/actions/runs/30673821431)).
2. **~~E02-R20 — Epic 2 lezárás (a11y/l10n/perf audit, DoD-tábla)~~ — KÉSZ**
   (PR #44, `4616aed`, 2026-08-01, implementer **MiniMax M3**, orchestrátor
   **Claude Sonnet 5**, egy javító kör → **APPROVED**). **Epic 2 technikailag
   lezárva.**
   - **~~A rendszerszintű drótozási rés (§3)~~ — KÉSZ (E02-R21, ld. §5).**
   - **A `migratedLearnEnabled` rollout-döntés** — mindenhol OFF, a
     bekapcsolás feltételei (mérföldkövek, monitorozás, visszaállítási
     útvonal) az R19 paritása alapján még **user-döntésre várnak**
     (R20 nem hozott ebben döntést, csak dokumentált).
   (E02-R19 progress/streak/daily-goal + Learn V2-migráció — KÉSZ: PR #43,
   `0bdee7e`.)
3. **A pipeline (ADR 0087, GOV-02) E02-R14…R19-et és E02-R21-et vitte
   (utóbbit a self-heal round 10/H4 zárta le); E02-R20-at és E03-R01-et
   SZÁNDÉKOSAN ember indította** (ADR 0087 §7 — epic-kickoff és epic-zárás
   emberi döntési pont); E03-R02-t és E03-R03-at a user már `pending`-re
   állította, a driver ezeken a körökön keresztül automatikusan folytatta
   (self-heal L49/L50, majd L51 közbeiktatásával) — a
   ([`docs/execution/pipeline-queue.tsv`](docs/execution/pipeline-queue.tsv))
   E03-R01/R02/R03/R04/R05 sora `done`, E03-R06 sora a fájlban még
   `pending` (a driver saját könyvelése frissíti `done`-ra a következő
   firing-en — ez a session nem nyúl a queue-fájlhoz), E03-R07…R21
   `pending` — a driver körönként automatikusan halad, amíg HALT nem éri.

   > **Megállási szerződés (ADR 0087 §2):** az orchestrátor-session önállóan
   > javíthatja a kör SAJÁT, még nem merge-elt briefjét/ADR-jét (§0.0
   > revízióval); H1–H8 esetén (merged ADR, lezárt kör viselkedése, tilos zóna,
   > túlélő BLOCKER/MAJOR, 2× piros CI, `blocked`, gate nem zöldíthető,
   > rebase-konfliktus) a kör HALT-tal megáll.
   >
   > **ÖNJAVÍTÁS (ADR 0112, GOV-03, 2026-08-01 — user-döntés):** a HALT már NEM
   > a lánc vége. A driver a következő firingen friss **önjavító sessiont**
   > indít (`docs/execution/pipeline-selfheal-prompt.md`), amely az
   > infrastruktúrát is javíthatja (`tools/**`, merge-elt ADR jelölt
   > módosítás-blokkal, brief, sor-fájl), kötelező **regressziós teszttel**, a
   > változatlan zöld kapun át merge-elve — majd feloldja a láncot. Korlátok:
   > körönként+halt-kódonként max **3** kísérlet (`PIPELINE_SELFHEAL_MAX`), és
   > a **mércét nem gyengítheti**: ha a teszt-fájlok száma csökken vagy a
   > `round-gate.sh` / `.github/workflows/` változik, a driver `H-GATEGUARD`
   > halttal EMBER elé viszi. Kikapcsolás: `PIPELINE_SELFHEAL=0`.
   > Állapot: `tools/pipeline-status.sh` (önjavítás-blokk + kísérletszámláló).
   >
   > **REVIEW-MOTOR FALLBACK (ADR 0115, 2026-08-02 — user-döntés):** ha a
   > **Claude-kvóta** kimerül, a lánc nem áll meg: ugyanazt a kör- vagy
   > önjavító promptot a **Terra** (`codex exec`, `CODEX_HOME=~/.codex-terra`,
   > `gpt-5.6-terra`) viszi tovább, a
   > `docs/execution/pipeline-codex-orchestrator-preamble.md` motor-előszóval.
   > A váltás kiváltója KIZÁRÓLAG a mért kvóta-minta a session-naplóban —
   > minden más néma halál marad halt. A zárlat 5 óra
   > (`.pipeline/claude-blocked-until`), visszaállítás:
   > `tools/pipeline-status.sh --unblock-claude`; kikapcsolás:
   > `PIPELINE_FALLBACK_ENGINE=none`. **Az implementer-routing (ADR 0088:
   > M3 → Terra) ettől FÜGGETLEN és változatlan** — ez csak arról szól, ki
   > vezényel és ki review-z.
   >
   > **E03-R05 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > `router_result` egyetlen szinkron `ai-router-round.sh run` hívása a
   > Bash-eszköz 600s-es kemény plafonjánál tovább tartó MiniMax-hívásoknál
   > (`model_timeout_seconds=7200`) jelzés nélküli SIGTERM-mel halt meg —
   > docs/LESSONS.md L42 pontos ismétlődése, most az `engine=auto` úton.
   > Javítás: `engine=auto` is a már szentesített leválaszt-és-előtérben-várj
   > mintát követi (`setsid ... & ; tools/wait-for-router.sh`); az örökölt
   > `wait-for-round.sh` a router `progress`/`blocked` jelzéseit nem ismeri
   > fel terminálisnak (mérve, regressziós teszttel dokumentálva), ezért egy
   > ÚJ, dedikált poller kellett. `tools/ai-router-round.sh` és a Python
   > router (`tools/ai_router/**`) VÁLTOZATLAN — a szükséges state-alapú
   > állapotlekérdezés már létezett. PR #61, `3b4707f`, `router-ci` zöld.
   > Részletek: docs/LESSONS.md L54.
   >
   > **E03-R05 H-GATEGUARD önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:**
   > a H6 heal (PR #61) UTÁN a driver `H-GATEGUARD`-dal állt le, holott a PR
   > #61 saját diffje a mércét NEM érintette — a heal ~07:50–08:08 közötti
   > futása KÖZBEN egy tőle FÜGGETLEN, jogos commit (`8715773`, ADR 0115)
   > módosította a `router-ci.yml`-t, és a régi őrszem a teljes main
   > előtte/utána állapotát hasonlította össze, nem a heal SAJÁT diffjét.
   > Javítás: `heal_pr_number`/`heal_pr_gate_violation` a determinisztikus
   > `heal/{ROUND}-{HALT_CODE}-{ATTEMPT}` branch-névhez tartozó, merge-elt PR
   > SAJÁT diffjét nézi (immunis a konkurens, független commitokra); nincs
   > megtalálható PR esetén óvatosságból a régi teljes-fingerprint marad
   > fallback. Regressziós tesztek a VALÓDI PR #61/`3b4707f` (negatív eset) és
   > a VALÓDI, `round-gate.sh`-t módosító `6d61e23` (pozitív eset) adatain.
   > Részletek: docs/LESSONS.md L55.
   >
   > **E03-R05 H6 önjavító kör #2 (2026-08-02) — KÉSZ, `outcome=fixed`:** a
   > H-GATEGUARD heal (PR #62) UTÁN a friss `auto` M3-hívás ÚJRA commitolt
   > (`d0546f0`, worktree `ss-router-e03-r05-2`) a prompt "Do not commit,
   > push..." tiltása ellenére — `security.py` helyesen hard-BLOCKolt, de a
   > `HALTED` saját gyökérok-elmélete ("a tiltás sosincs kimondva") mérve
   > téves volt (a `router.py:353-364` prompt élén ott áll). Ez ugyanaz a
   > tünet, mint L49 (E03-R02) — ott a self-heal SZÁNDÉKOSAN elvetett egy
   > `security.py`-lazítást mércegyengítésként. Javítás most: egy ÚJ,
   > korábbi rétegen ülő kontroll, nem az elvetett lazítás újramérlegelése —
   > `tools/ai_router/git-guard/git` PATH-shim, amit `execution.py`
   > `run_codex()` minden M3/Terra hívás elé tesz, és ami `git commit`/
   > `git push`-t a shell-rétegen utasít el (minden más git-alparancs
   > változatlanul átmegy); `security.py` audit_scope-ja és hard-blockja
   > ÉRINTETLEN. Regressziós tesztek (fix előtt RED, utána GREEN):
   > `tools/tests/test_execution.py::test_git_guard_blocks_commit_and_push_but_passes_through_other_subcommands`,
   > `::test_run_codex_blocks_a_model_commit_at_the_shell_layer` (a `d0546f0`
   > mintát reprodukálja egy hamis "codex" folyamattal). Részletek:
   > docs/LESSONS.md L56.
   >
   > **E03-R08 H6 önjavító kör (2026-08-02) — KÉSZ, `outcome=fixed`:** az
   > auto-router M3 1. próbálkozása `changed_paths=0` mellett terminális
   > `STOPPED`-ot adott vissza; `classification.py`'s catch-all-ja futott,
   > mert egyik ismert minta (quota/429/timeout/network/credential/env) sem
   > talált — a `HALTED` fájl innen csak ezt az egy szót tudta jelenteni,
   > mert `execution.py`'s `run_codex()` a MiniMax CLI nyers `stdout`-ját
   > sorról sorra JSON-ra próbálta parse-olni, és minden NEM-JSON sort
   > (pont ahol egy szöveges self-halt üzenet állna) némán eldobott — a
   > `CodexResult`-nak nem is volt `stdout` mezője. Class A gyökérok (a
   > router SAJÁT diagnosztikai csatornája hiányos, nem a MiniMax-hívás
   > tartalma). Javítás: `CodexResult.stdout` mező (az `events`/
   > `agent_messages` MELLETT) + `router.py`'s új `_record_provider_call()`
   > (az `_record_gate()` mintája) minden M3-/Terra-hívás után a task-state
   > `provider_calls`-listájába teszi a nyers (20000 karakterre vágott)
   > `stdout`/`stderr`-t, a `FailureClass`-szal együtt. Regressziós tesztek
   > (RED a fix előtt, GREEN utána):
   > `test_execution.py::test_run_codex_preserves_raw_stdout_for_non_jsonl_output`,
   > `test_router.py::test_provider_call_history_persists_raw_stdout_for_stopped_diagnosis`.
   > A `tools/tests -q` egy MÁSIK, ehhez a halthoz nem tartozó sub-teszttel
   > (`test_epic3_brief_metadata.py`, E03-R05 brief TOML-drift) továbbra is
   > pirosít — ez az [[L59]]-ben már dokumentált, önálló felhatalmazású
   > önjavító kört vár, SZÁNDÉKOSAN érintetlen ebben a körben (§2 hatóköre
   > csak a MEGÁLLT — E03-R08 — kör briefjére terjed ki). PR #67, `3725f09`.
   > Részletek: `docs/LESSONS.md` L61.
   >
   > **E03-R08 H6 önjavító kör, 2. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti javítás után a H6 más gyökérokkal két
   > egymást követő 5 perces cikluson (15:19, 15:29 UTC) belül ismét
   > lecsapott: a brief `migration`-fragmenst érint, ezért a kötelező Terra
   > high-risk review (ADR 0088 §2) szükséges, de a napi automatikus
   > Terra-budget (`.ai/router.toml` `max_automatic_terra_calls_per_utc_day
   > = 3`) MÉRVE (`terra-ledger.json`, `daily_count=3`) kimerült — ez csak
   > `2026-08-03T00:00:00Z`-kor nyílik meg újra. C osztályú (külső,
   > naptár-kapuzott) akadály, de a driver 5 percenkénti retry-ciklusa
   > ~20-30 percen belül elhasználta volna mind a 3 önjavítási kísérletet
   > egy olyan haltra, ami emberi döntést nem is igényelt. Javítás:
   > `tools/round-pipeline.sh` kör-specifikus, időkorlátos "hold" — egy
   > Terra napi-budget-kimerülésre visszavezetett `retry` után a driver
   > `terra-budget-hold` fájlt ír (`round`, `hold_until=UTC éjfél`), és
   > minden firing a zár után, halt-kezelés/kör-indítás ELŐTT ellenőrzi:
   > ha a soron lévő kör megegyezik, session és önjavítási-kísérlet
   > fogyasztása NÉLKÜL lép ki. Új, tisztán olvasó
   > `StateStore.daily_terra_count()` (state.py) + `terra-status`
   > alparancs (model-router.py, JSON + nemnulla exit kimerülésnél) — a
   > driver ugyanazt a forrást kérdezi, amit `reserve_terra` a döntéséhez
   > használ, nincs duplikált szabály. Regressziós tesztek (RED a fix
   > előtt, GREEN utána): `test_state_store.py::
   > test_daily_terra_count_matches_the_active_status_rule_reserve_terra_enforces`,
   > `test_router_cli.py::
   > test_terra_status_exits_nonzero_and_reports_the_utc_midnight_reset_once_exhausted`,
   > `test_pipeline_integration.py::
   > test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`.
   > A `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít — mérve azonosan a
   > módosítás nélküli `main`-en is, ezen kör hatóköre kívül esik rajta.
   > Részletek: `docs/LESSONS.md` L62.
   >
   > **E03-R08 H6 önjavító kör, 3. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** a fenti L62-hold BEVEZETVE volt (PR #68/#69), a
   > driver mégis NÉGYSZER futott ugyanabba a Terra-budget falba egy nap
   > alatt (14:26, 15:19–15:29, 16:05, 16:15 UTC) — `find .pipeline
   > -iname '*hold*'` a 4. haltkor is ÜRES találatot adott. Gyökérok:
   > `terra_hold_if_exhausted()`-ben `status_json=$(terra_status_json) ||
   > return 0` — de a `terra-status` a DOKUMENTÁLT viselkedése szerint
   > pontosan akkor tér vissza NEMNULLA exit-tel, amikor kimerült; a `||`
   > ezt is lekérdezési hibaként kezelte, a függvény visszatért, mielőtt
   > egyszer is megírta volna a hold-fájlt. A meglévő
   > `test_terra_budget_hold_blocks_a_firing_without_spending_a_selfheal_attempt`
   > csak az OLVASÓ függvényt (`terra_hold_active_for`) tesztelte, kézzel
   > megírt hold-fájllal — az ÍRÓ ág sosem futott le teszt alatt. Javítás:
   > az `|| return 0` törölve, a meglévő `[ -n "$status_json" ] || return
   > 0` marad a valódi lekérdezési hiba (üres kimenet) védelmére. Új
   > `--terra-hold-if-exhausted` teszthorog (a `--terra-hold-active`
   > mintájára) + `test_pipeline_integration.py::
   > test_terra_hold_if_exhausted_writes_the_hold_file_when_terra_status_reports_exhausted`
   > (PATH-stub `python3`, ami a `terra-status` mért exhausted/exit-1
   > viselkedését szimulálja) — RED a régi sorral, GREEN az újjal. A
   > `tools/tests -q` ezen a javításon átfutva is UGYANAZZAL a [[L59]]-ben
   > dokumentált E03-R05 brief-TOML sub-teszttel pirosít, mérve azonosan a
   > módosítás nélküli `main`-en is; `router-ci.yml` (push-only, nem
   > GitHub-required check) ezért erre a heal branch-re is pirosat
   > mutatott, PR #70 a #68/#69 mintáját követve a CodeRabbit-checkkel
   > merge-elődött. Részletek: `docs/LESSONS.md` L63.
   >
   > **E03-R08 H6 önjavító kör, 4. előfordulás (2026-08-02) — KÉSZ,
   > `outcome=fixed`:** az L63-fix (PR #70, 16:27) UTÁN is jött egy 6.
   > azonos H6 halt (16:38 UTC) — a hold-fájl megint hiányzott. Gyökérok:
   > a hold-írás (`terra_hold_if_exhausted`) KIZÁRÓLAG `attempt_selfheal()`
   > `retry`-ágából íródott ki, sosem a driver `halted)` ágából (a HALT
   > ELSŐ, session előtti észlelése). A 3. előfordulás heal-köre
   > (16:20–16:30) maga egy MÁSIK gyökérokra javított (a hold-író saját
   > hibája) — `outcome=fixed`, nem `retry` —, ezért a `retry`-ág EBBEN a
   > ciklusban sem futott le, a hold-fájl a fix után is üres maradt.
   > Javítás: új `handle_round_halt()` (`tools/round-pipeline.sh`) a
   > `halt_file` írása MELLÉ meghívja `terra_hold_if_exhausted()`-et is —
   > a HALT ELSŐ észlelésekor, MIELŐTT bármilyen self-heal elindulna,
   > FÜGGETLENÜL a self-heal későbbi `outcome`-jától. Az
   > `attempt_selfheal()` retry-ágának hívása változatlanul marad
   > (idempotens második réteg). Új `--handle-round-halt` teszthorog +
   > `test_pipeline_integration.py::
   > test_first_halt_detection_writes_the_terra_hold_without_waiting_for_a_selfheal_retry`
   > — RED a hook nélkül (a hívás a case-ágból kiesve a teljes
   > driver-folyamatba zuhan), GREEN a hookkal. A `tools/tests -q` ezen a
   > javításon átfutva is UGYANAZZAL a [[L59]]-ben dokumentált E03-R05
   > brief-TOML sub-teszttel pirosít, mérve azonosan a módosítás nélküli
   > `main`-en is; `router-ci.yml` ezért erre a heal branch-re is pirosat
   > mutatott ugyanazzal az EGY sub-teszttel, a #68/#69/#70 mintáját
   > követve a CodeRabbit-checkkel merge-elődött. Részletek:
   > `docs/LESSONS.md` L64.
   >
   > **A napi Terra-korlát eltávolítása (PR #72, `53b9637`, L65):**
   > user-döntésre `max_automatic_terra_calls_per_utc_day = 0` mostantól
   > korlátlant jelent — a `daily_count=3/3` fal maga szűnt meg, nem csak a
   > driver retry-viselkedése rá. A taskonkénti 1 Terra-hívásos korlát és a
   > magas kockázatú review kötelezettsége változatlan.
   >
   > **E03-R08 H6 önjavító kör, 7. előfordulás (2026-08-02 18:45 UTC) — KÉSZ,
   > `outcome=fixed`:** a napi korlát megszűnése (fent) után az első
   > cron-firing helyesen törölte az elavult `terra-budget-hold` fájlt, de a
   > MELLETTE élő `.pipeline/HALTED` (a MÉG korlátozott policy alatt,
   > `halted_at=16:58:03Z`-kor kiírva) érintetlen maradt — a driver 2.
   > szakasza ettől függetlenül egy ÚJABB, valódi önjavító sessiont indított
   > egy már megszűnt okra (ez a session). **1. javító kör (PR #73):**
   > `terra_clear_stale_halt_for()` a hold-törléssel EGYÜTT, csak akkor
   > futva, ha még LÉTEZIK hold-fájl. **MÉRT hiányosság:** élesben a
   > hold-fájl a HALT előtti firingen már törlődött, tehát PR #73 hívási
   > pontja SOHA nem futott le a valódi incidensen — csak a driver
   > `outcome=fixed` standard könyvelése (a `halt_file` archiválása)
   > oldotta fel EZT a konkrét haltot, nem az új függvény. **2. javító kör
   > (PR #74, ugyanebben a sessionben):** `terra_clear_stale_halt_for()`
   > mostantól ÖNÁLLÓAN kérdezi le a Terra-policy-t, és a driver főágában a
   > hold-fájl létezésétől FÜGGETLENÜL, feltétel nélkül fut — a KÖVETKEZŐ
   > hasonló esetben már ez fog reagálni, nem egy újabb heal-session. Új
   > `--terra-clear-stale-halt` teszthorog + 3 regressziós teszt (RED PR #73
   > állapota ellen, GREEN PR #74 után); `tools/tests -q` 151/151 zöld.
   > **Biztonsági incidens a saját tesztelés közben:** a tesztek első
   > verziója egy ismeretlen CLI-flaget hívott a pre-fix scripten, ami a
   > TELJES driver-folyamatba esett és egy VALÓDI tmux+claude
   > önjavító sessiont indított — azonnal észlelve és leállítva, állapot-
   > károsodás nélkül; javítva az attempt-budget-határ biztonsági minta
   > minden ilyen teszthez való hozzáadásával. Részletek: `docs/LESSONS.md`
   > L66.
4. **Kötelező pre-flight minden körhöz** (az R10 és R11 mért tanulságai):
   minden briefben hivatkozott szimbólumot grep-elj ki; minden előírt
   cél-státuszra mérd meg, melyik INPUT produkálja (L20); minden
   erőforrás-előírásnál mérd ki a tényleges hívási láncot (L19).
   **A javító kör küszöbe EGY** (user-döntés 2026-08-01, `8e719f1` — a korábbi
   HÁROM-ról szigorítva); a második javító kört a **Codex** viszi, H4 halt
   csak utána. **UI-kör esetén a review-nak kötelező eleme a több-belépéses
   és a kombinált-státusz próba** — az R13 három MAJOR-ja mind ilyen volt
   (L22). **Zöld gate mellett is mérj konkrét hívási láncot a DoD-/
   zárójelentés-jellegű állításokra** — az R20 review 6 hamis "teljesül"
   sort talált egy egyébként teljesen zöld gate mellett (L31).
5. **Az E02-R08 nyitva maradt follow-upja:** a chord-confidence felvitele a
   `LiveFrame`-be — az Analyze úton is közös, ezért külön kör; addig a Live
   adapter `confidence: 1.0` = „nem mért".

## 7. Required verification (before any "done")

A lokális mérce **egyetlen futtatható artefaktum** (GOV-01) — a parancssorban
reprodukált lista a csővezeték miatt nem bizonyíték (`docs/LESSONS.md` L09):

```bash
tools/round-gate.sh test/<a kör területe> [további teszt-útvonal ...]
```

A script a `format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket **külön processzként** futtatja (ezért nem OOM-ol), és az első piros
lépésnél a helyes kilépési kóddal megáll. Normatív forrás: `AGENTS.md` §12.
Backend-érintésnél kiegészítő lépés (NEM a gate része):
`cd backend && .venv/bin/python -m pytest`.

- Full suite + property gate + APK: `gh workflow run build-apk.yml --ref <branch>`.
- **Never chain `analyze && test`.** ONE win32 major across the tree
  (`flutter_secure_storage` pinned to v10). Riverpod 3.3.2: `AsyncValue.value`
  (nullable), NOT `.valueOrNull`.
- DSP param change ⇒ `docs/rag/chunks/` update in the SAME commit; new DSP
  behaviour ⇒ randomized property in `test/property/` (`PROPERTY_SEED`).
- Backend writes are easy to lose silently — a failed push must NOT mark state
  synced; verify persistence + offline path.
- Backend dev loop: `cd backend && python3 -m venv .venv &&
  .venv/bin/pip install -r requirements.txt`, then
  `.venv/bin/uvicorn app.main:app --reload` (emulator → host: `10.0.2.2`).
  Deploy-szabály: uvicorn-restart előtt `pip install -r requirements.txt`
  (a `main.py` futásidőben importál `alembic`-ot).
- **HORIZON ritual minden kör-commit után:**
  ```bash
  git notes add -m "round=<n> verdict=pass|fail tests=<n> lesson=<slug>"
  git push origin 'refs/notes/*'
  ```

## 8. Historical archive

A teljes kör-történeti napló (pre-SDD r1–r217 + E01-R01…R15 részletes
összefoglalók, git-notes tükör): [`docs/handoff-archive.md`](docs/handoff-archive.md).
Epic-1 evidencia-gyűjtemény: [`docs/sdd/epic-01-completion-report.md`](docs/sdd/epic-01-completion-report.md).

---

## How to update this file

After **every** round: (1) header date + round; (2) §1/§2 if release state or
capabilities changed; (3) §3 blockers +/-; (4) §4–§6 branch / last round / next
task; (5) move the finished round's detailed story to
`docs/handoff-archive.md` (append, never delete). Keep this file a ~120-line
operational snapshot — history lives in the archive, detail in git.
