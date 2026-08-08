# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-08-08
> (E05-R17 MERGED — Automatic guitar detector go/no-go decision:**
> Go/no-go/experimental-only döntési keret egy JÖVŐBELI automatikus
> gitár/nyak-geometria detektorhoz — **ez a kör NEM épít detektort** (nincs
> dataset, nincs modell, nincs tréning, AGENTS.md §9). `ml/vision/dataset_manifest.md`
> — 12 dataset-kategória, 7 mezős consent-séma, 7 tételes tiltott-forrás
> lista; `ml/vision/evaluate_geometry_baseline.py` — pure-stdlib Python
> harness (IoU, mean/p95 anchor error, failure rate, latency,
> determinisztikus `NO_DATA` üres bemenetre); `docs/baseline/epic-05-guitar-detector-evaluation.md`
> — manual-kalibráció költségbecslés (P50≈17s/P95≈30s, anchor-bizonytalanság
> <0.01) + PENDING jelölések a valós-eszközös méréshez; `ml/vision/README.md`
> — bounding-box/line/segmentation output-összehasonlítás. **ADR 0187**
> (új, az orchestrátor írta a pre-flightban, ADR 0179/0181 precedense):
> default `experimental-only`, a manual kalibráció (ADR 0181) marad a
> production út; számszerű átfordítási küszöbök (mean anchor error ≤0.030,
> p95 ≤0.050, failure rate ≤5%, minimum eval-corpus ≥200 frame/≥3
> gitár/≥2 világítás/mindkét kezesség) az R16 `CalibrationLossMachine`
> saját hiszterézis-küszöbeiből származtatva. Implementer **MiniMax M3**
> (kezdeti implementáció + **egy javító kör**), orchestrátor/reviewer
> **Claude Sonnet 5**. PR
> [#189](https://github.com/wolfcasaba/strumsight/pull/189), squash `e979d41`.
>
> **Egy javító kör, egy dedikált security-review, egy lezárt BLOCKER +
> egy lezárt MAJOR:**
>
> 1. **BLOCKER-1 — a `decision()` promóciós logika INVERTÁLT volt egy
>    hiba-metrikán.** `ml/vision/evaluate_geometry_baseline.py:209-253`.
>    NEM implementer-hiba: a kör-brief §6.2 küszöb-mátrixa (amit az
>    orchestrátor egy generikus, batch-írt sablonból konkretizált a
>    pre-flightban) és az ADR 0187 SAJÁT Döntés 4. pontja UGYANAZT a rossz
>    irányt írta elő, ellentmondva az ADR SAJÁT, helyesen `≤ 0.030`-at
>    mondó Döntés 2 táblájának. A `mean_anchor_error` HIBA-metrika
>    (alacsonyabb=jobb) volt, a kód mégis a `> MEAN_ANCHOR_ERROR_MAX`
>    esetben adott `PRODUCTION_CANDIDATE`-et — egy rosszabb detektort
>    magasabbra sorolt, mint egy jobbat. Az implementer szó szerint, hűen
>    implementálta a kapott specifikációt, ÉS saját `§10.7`
>    handoff-jegyzetében jelezte a látszólagos ellentmondást — nem
>    csendben találgatott. A `--self-test` 9/9 zöldsége NEM volt
>    bizonyíték (a fixture-ök ugyanazt a rossz irányt feltételezték).
>    **Javítás:** az irány megfordítva, függetlenül újra-ellenőrizve friss,
>    a self-testtől független szintetikus adattal (mean≈0,0098 →
>    `PRODUCTION_CANDIDATE`, mean≈0,0799 → `EXPERIMENTAL`). Lecke **L173**.
> 2. **MAJOR-1 — a consent-séma hét kötelező mezőből hatot vitt át.**
>    Dedikált `security-reviewer` (risk=high): az SDD §31.2 hét eleméből
>    az „annotátor privacy guideline" hiányzott a `dataset_manifest.md`
>    §2 táblájából. **Javítás:** új sor a táblázatba, mind a 7 elem
>    lefedve.
>
> **Az orchestrátor mindkét lezárt leletet FÜGGETLENÜL újra-ellenőrizte**,
> friss `/tmp` klónban: gate 6/6 ZÖLD, scope-audit OK mindkét fordulóban,
> a BLOCKER-1 javítását friss, önteszt-fixture-öktől független szintetikus
> adattal megismételve.
>
> Zöld kapu (exact-SHA `8e71e80`): Full Gate
> [31220060205](https://github.com/wolfcasaba/strumsight/actions/runs/31220060205)
> **success** + Router CI
> [31220056578](https://github.com/wolfcasaba/strumsight/actions/runs/31220056578)
> **success**.
>
> Lecke: **L173** (egy hiba-metrikára generikus, magasabb=jobb sablonból
> konkretizált küszöb-tábla csendben megfordíthatja a promóciós döntést —
> részletek `docs/LESSONS.md`).
>
> **Operatív utójegyzet — a bookkeeping H-NOSIGNAL önjavítással zárult.**
> A PR #189 merge (21:38 UTC) UTÁN, a closing-rituálok közben az
> orchestrátor-session „API Error: Server error mid-response"-ba futott;
> az interaktív tmux-session életben maradt, de némán, és a driver csak a
> teljes 4 órás abszolút időkorlátnál (1h24m33s néma várakozás után) vette
> észre — `H-NOSIGNAL`. Az önjavító kör (1/3 kísérlet) két dolgot tett: (1)
> **`PIPELINE_ORCH_STALL_MINUTES`** elakadás-őrt adott a `run_tmux_session`-höz
> (PR [#190](https://github.com/wolfcasaba/strumsight/pull/190), squash
> `a7210bf`, Router CI zöld), hogy egy jövőbeli hasonló hiba ~20 perc alatt,
> ne 4 óra alatt derüljön ki; (2) lezárta EZT a bookkeepinget (ezt a
> HANDOFF-bejegyzést, az RTM sort, git-notes), mivel a kör TARTALMI munkája
> már készen és merge-elve volt — a halt bookkeeping-hiány volt, nem
> tartalmi kudarc. Lecke **L174**.
>
> ## ✅ E05-R16 KÉSZ — Guitar geometry tracking és calibration loss (2026-08-07)
>
> **E05-R16** MERGED (PR [#188](https://github.com/wolfcasaba/strumsight/pull/188),
> squash `6f9c0e1`; implementer **MiniMax M3** (kezdeti + egy javító kör),
> orchestrátor/reviewer **Claude Sonnet 5**). Teljes részletes történet
> (BLOCKER-1: a tracker null-refusala halott kóddá tette a gép saját
> forward-escalation logikáját, + MINOR-1: assert-only validáció):
> [`docs/handoff-archive.md`](docs/handoff-archive.md). **Nincs új ADR**
> (ADR 0179/0181 bővítése). Review:
> [docs/reviews/e05-r16-geometry-tracking-and-calibration-loss-review.md](docs/reviews/e05-r16-geometry-tracking-and-calibration-loss-review.md)
> — **APPROVED** egy javító kör után, a dedikált security-review lelete is
> beleolvasztva. Lecke: **L172**.
>
> ## ✅ E05-R17 KÉSZ — Automatic guitar detector go/no-go decision (2026-08-07)
>
> **E05-R17** MERGED (PR [#189](https://github.com/wolfcasaba/strumsight/pull/189),
> squash `e979d41`; implementer **MiniMax M3** (kezdeti + egy javító kör),
> orchestrátor/reviewer **Claude Sonnet 5**). Lásd a fenti „Last updated"
> blokk a teljes pre-flight/javítókör/review/önjavítás történetért — ez a
> szakasz csak a rövid hivatkozási pont a korábbi körök mintája szerint.
> **ADR 0187** (új). Review:
> [docs/reviews/e05-r17-auto-guitar-detector-decision-review.md](docs/reviews/e05-r17-auto-guitar-detector-decision-review.md)
> — **APPROVED** egy javító kör után, a dedikált security-review lelete is
> beleolvasztva. **Következő:** E05-R18 — Fretting-hand metric engine
> (`docs/rounds/e05-r18-fretting-hand-metric-engine.md`), a pipeline új
> sessionben indítja.
>
> ## 📦 Korábbi kör-narratívák → archívum
>
> A lezárt körök részletes története a
> [`docs/handoff-archive.md`](docs/handoff-archive.md) fájlban van.
> MIÉRT: ezt a fájlt MINDEN session és MINDEN kör elolvassa (orchestrátor +
> implementer), ezért a lezárt körök narratívája itt tiszta kontextus-adó.
>
> **Szabály (ADR 0175 §4):** a fejlécben a friss állapot és a **két legutóbbi**
> kör bannere marad; minden korábbi banner az archívumba kerül a kör lezárásakor.
> Mért diéta: 2026-08-08 (H-NOSIGNAL önjavítás zárta le, ld. fent):
> E05-R16 részletes narratívája archiválva (a self-heal PR #190 előtt már
> elkészült, ld. `docs/handoff-archive.md`); E05-R15 rövid bannere törölve
> (a részletes E05-R15 történet már korábban archiválva volt, a rövid
> banner egy duplikált hivatkozás volt, nem újra-archiválva); E05-R17
> részletes narratívája + rövid bannere felkerült (E05-R16 rövid bannere
> marad a második helyen, „Következő" pointere R18-ra frissítve).

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
- **A `lib/` 43%-a ma elérhetetlen (mérve 2026-08-07):** `song_trainer` V2
  (25 308 sor), `ai_tutor` (14 091), `vision` (5 132) — mindhárom flagje
  **hard-kódolt `false`** a `FeatureFlags.forEnvironment`-ben, tehát a CI
  dev-APK-jában sem elérhető; a Learn ma is a **legacy** ágon fut
  (`migratedLearnEnabled: false` mindenhol). Ugyanekkor a termék központi
  állítására egyetlen mért valós-audio szám létezik (CRNN pengetés-irány
  86,7% vs heurisztika 38,9%, r164 A/B) — akkord-pontosságra valós felvételen
  nincs. **User-döntés (2026-08-07):** az Epic 6 NEM indul, amíg ez a kettő
  nincs meg → lásd §6 „Kötelező sorrend".

## 4. Current branch

`main` @ [PR #189](https://github.com/wolfcasaba/strumsight/pull/189), squash
`e979d41` (E05-R17, automatic guitar detector go/no-go decision). Docs/Python-only
diff (`ml/vision/*.py`, `.md`, ADR) → full-gate
[31220060205](https://github.com/wolfcasaba/strumsight/actions/runs/31220060205)
+ router-ci [31220056578](https://github.com/wolfcasaba/strumsight/actions/runs/31220056578)
**success** az exact merge-előtti tip `8e71e80`-n (a javító kör UTÁN).
Review **APPROVED 1 javító kör után** — BLOCKER-1 (`decision()` promóciós
logika inverz irányú egy hiba-metrikán, gyökérok az orchestrátor SAJÁT
pre-flight-specifikációja, nem implementer-hiba) + MAJOR-1 (dedikált
security-review lelete: consent-séma 6/7 kötelező mező), mindkét lelet az
orchestrátor SAJÁT, függetlenül futtatott gate-újrafuttatásával ÉS friss,
önteszt-fixture-öktől független szintetikus adattal újra-ellenőrizve, nem
az implementer önjelentésére hagyatkozva; dedikált security-review
(risk=high) — PASS BLOCKER/MAJOR-ra, a MAJOR-1-et adta. Az `origin/main` a
dispatch óta **nem mozdult**. Post-merge gate
(`python3 ml/vision/evaluate_geometry_baseline.py --self-test`) a friss
`main`-en is zöld.

**Operatív utójegyzet:** a merge UTÁNI closing-rituálokat egy „API Error:
Server error mid-response" szakította meg (session életben, néma
1h24m33s) → `H-NOSIGNAL` → self-heal PR
[#190](https://github.com/wolfcasaba/strumsight/pull/190), squash `a7210bf`
(`PIPELINE_ORCH_STALL_MINUTES` elakadás-őr a `run_tmux_session`-höz, Router
CI zöld) zárta le ezt a bookkeepinget is. Lecke: **L173** (a round saját
BLOCKER-1-e), **L174** (a self-heal gyökéroka).
_(Történeti product-merge referencia: PR #188 / `6f9c0e1`, E05-R16; PR #187
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

> ### 🔒 Kötelező sorrend az Epic 5 után (user-döntés, 2026-08-07)
>
> **„várjuk meg amíg az Epic 5-tel végzünk, majd csináljuk a shipping kört
> először, majd egy valós audio mérés, és csak ezek után lépjünk az Epic 6-ra."**
>
> 1. **Epic 5 befejezése** (E05-R14 … E05-R30) — a queue `pending` sorai.
> 2. **Az Epic 5 APK-ellenőrzése** a usernél (valós eszköz).
> 3. **GOV-05 — Shipping rollout kör.** Nem új képesség: a MÁR KÉSZ, de
>    elérhetetlen 44 531 sor termékké tétele — `songTrainerV2Enabled`,
>    `aiTutorEnabled`, `visionEnabled` bekapcsolása legalább `lab`
>    környezetben, a Learn átállítása a Practice V2-re
>    (`migratedLearnEnabled`), és a hozzá tartozó valós eszközös menet.
> 4. **GOV-06 — Valós-audio DSP baseline mérés.** A meglévő shipping DSP
>    pontossága valódi gitárfelvételeken: akkord-pontosság, onset P/R/F1,
>    BPM-hiba. **Miért ELŐBB, mint az Epic 6:** az Epic 6 harminc köre erre a
>    DSP-re épít metrika-, confidence- és insight-réteget; ha az alap gyenge,
>    azt most olcsó megtudni, harminc kör után nem.
> 5. **Csak ezután Epic 6** — a 30 briefje kész (`epic-06-batch-index.md`),
>    a queue-sorai `hold`-on. A feloldás EMBERI döntés, a 3. és 4. pont után.
>
> A GOV-05/GOV-06 briefje **szándékosan még nincs megírva**: a pre-flightjuk
> az Epic 5 VÉGSŐ állapotát kell hogy mérje (a vision-flagek és a
> device-mátrix csak akkor lesznek véglegesek). Az Epic 6 queue-sorai
> addig is `hold`-on védik a sorrendet.

0. **E05-R18 — Fretting-hand metric engine**
   (`docs/rounds/e05-r18-fretting-hand-metric-engine.md`) — a pipeline új
   sessionben indítja — **ez a session nem kezdi el.**
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
