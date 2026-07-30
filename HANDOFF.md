# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-07-30 (E02-R06)**.
> Full round-by-round history: [`docs/handoff-archive.md`](docs/handoff-archive.md).

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
- **Epic 2 (Practice Engine) elindult** — E02-R01 (baseline-befagyasztás +
  rollout-guardok) kész; a három practice-flag minden környezetben OFF, tehát a
  felhasználói viselkedés még változatlan.

## 2. What is working

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
- **Kétmotoros implementer-készlet (ADR 0069):** `tools/mm-round.sh` +
  `tools/mm-watch.sh` (5 perces korai riasztás) + `tools/mm-trace.py`
  (munkastílus-elemzés) — a MiniMax M3 ugyanazt a kör-jelzés-szerződést
  használja, mint a Codex. Besorolás és a kötelező brief-elemek: AGENTS.md §15.6.

## 3. Known blockers / risks

- **§16.3/§16.4 készülékes menet PENDING** — az Epic-1 zárás végső elfogadási
  kapuja a user valódi-gitáros APK-tesztje; eredménye a completion reportba kerül.
- **Login-backend nincs hosztolva** (a :8019-es uvicorn lokális); auth-hiányok:
  nincs jelszó-reset / e-mail-verifikáció / refresh token (14 napos JWT),
  mid-session token-lejárat interceptor szándékosan halasztva.
- **Coverage-küszöb nincs:** `config` 79,66%, `foundation` 76,19% a Ch2 §14.8
  90%-os célja alatt (kritikus modulok együtt 88,07%) — küszöbösítés későbbi kör.
- **User-inputra vár:** Contents:write token (release-publikálás) ·
  Workflows:R+W PAT · Hermes-kutatás továbbítása.
- iOS build Mac nélkül nem lehetséges.
- Nyitott follow-up lista tételesen: completion report §2.

## 4. Current branch

`main` @ [PR #27](https://github.com/wolfcasaba/strumsight/pull/27) (E02-R06,
merge `491f2d0`, CI run
[30573906740](https://github.com/wolfcasaba/strumsight/actions/runs/30573906740)
zöld: gate-sor + teljes suite + randomizált property gate + APK + coverage).
Kör-branch: `codex/epic-02-round-06-target-compiler` (merge után törölve).
Merge után a `main`-en függetlenül újrafuttatva: format 506/0 changed · analyze
No issues found · `test/features/practice/` 291 zöld.

## 5. Last completed round

**E02-R06 — Target compiler és beat-idő konverzió**
([ADR 0072](docs/adr/0072-practice-target-compiler.md) implementációja, PR #27):
`BeatTimeConverter` — a practice domain **egyetlen** beat↔idő konverziója, egész
mikroszekundum (`round(ticks * 60e6 / (bpm * 480))`), egyszeri kerekítés, inverz
`positionAt`, fail-fast `StateError` érvénytelen `Tempo`/`Meter` mellett ·
`CompiledPracticeTarget` + `CompiledTargetEvent` + `ExpectedChordSegment` +
`PracticeLoopRange` immutable, value-equal modellek konstruktorbeli
`List.unmodifiable` snapshottal · `compilePracticeTarget` — ötlépcsős validációs
sorrend stabil kódokkal, count-in, egész ütemre kerekített pass-hossz,
loop-kiválasztás/rebase/ismétlés, ütemhatárok, marker-szűrés, monotonitás-őr,
és a legacy `_activeChord()` **120 tickes** lookahead szemantikáját követő
expected-chord szegmentálás · öt új `PracticeValidationCode` +
`FailureCode.practiceTargetUncompilable`. Ezzel a Learn út hat szétszórt
`double` időképlete (`lesson_scorer.dart:85/87/241`, `lesson_timing.dart:11/15/39`,
`learn_screen.dart:47/74/498`) helyett egy auditálható pont van — a legacy kód
maga **érintetlen**, hívó UI nincs, flagek OFF → production viselkedés változatlan.
**Mért parity:** 10 befagyasztott baseline scenario (`finishAtSec` + eseményszint)
és 17 szállított lecke × 3 practice speed → **0 µs** max eltérés; korpusz
28/28 whole-bar kerekítési no-op. Implementer: **Codex**.
Review: első kör **CHANGES REQUESTED** (1 MINOR), két javító kör után
**APPROVED**: [`docs/reviews/e02-r06-review.md`](docs/reviews/e02-r06-review.md).
**A MINOR-t 289 zöld teszt mellett a reviewer próbatesztje fogta meg** (ugyanaz a
zenei pillanat két különböző időt kapott: 90 BPM-en 5 333 333 vs 5 333 334 µs), és
a javítása egy valódi tervezői kérdést kényszerített ki — egész µs mellett nem
tartható egyszerre „minden időtartam egyszeri konverzió" és „a részek összege az
egész". A feloldás az **ADR 0072 §1.1**: *pillanat pontos, időtartam származtatott*
(minden abszolút pillanat a nullponttól vett tickszám egyetlen konverziója, minden
időtartam két pillanat különbsége). **A Codex mindkét megállása helyes volt.**

### Korábbi kör

**E02-R05 — Legacy adapterek: Lesson / Song / Analyze / Daily Challenge**
([ADR 0071](docs/adr/0071-legacy-practice-adapters.md) implementációja, PR #26):
négy tiszta adapter a `lib/features/practice/data/adapters/` alatt, mind
`AppResult<PracticeDefinition>`-t ad és sosem dob · **Lesson (+Easy)**
esemény-szintű parity mind a 17 szállított leckére, egzakt tick-egyenlőséggel ·
**Song** a `toLesson()` hívása NÉLKÜL (forrás-scan teszt őrzi), kontrollált
hibával rossz mintahosszra/BPM-re · **Analyze** t0-normalizálással,
`Tempo`-tartományra szűkített BPM-fallbackkel, tick-ütközés előre-tolással
(pengetés nem vész el), üres klip → `freePractice` · **Daily Challenge**
nap-stabil ID-vel, óra-mentesen. Kísérő szerződés: `legacyPracticeChordLabel`
(veszteséges maj/min redukció a detektor tényleges 24-címkés szótárára),
`PracticeDefinition.displayTitle` (+61. stabil validációs kód),
`FailureCode.practiceContentUnsupported`, `lib/features/songs/public.dart`
barrel — az architektúra-allowlist **nem** bővült. Hívó UI nincs, flagek OFF →
production viselkedés változatlan. Implementer: **MiniMax M3**. Review: első kör
**CHANGES REQUESTED** (0 BLOCKER/MAJOR · 3 MINOR: az Analyze-idővonal egy hibátlan
klipnél némán kétszer olyan hosszú lett, a növelő ág és a t0-normalizálás
tesztfedetlen), javító kör után **APPROVED**:
[`docs/reviews/e02-r05-review.md`](docs/reviews/e02-r05-review.md).
**Mindhárom MINOR zöld gate mellett csúszott át** — a review eldobható
próbateszttel, a legacy `Lessons.fromAnalyze` referenciával szembe mérve fogta meg.

### Korábbi kör

**E02-R04 — Practice catalog és beépített gyakorlatok** (ADR 0070
implementációja, PR #25): tíz beépített gyakorlat `const` adatként, stabil
`builtin.<slug>.v1` ID-kkel és determinisztikus deklarációs sorrendben ·
`PracticeCatalogRepository` szinkron domain-szerződés (`all`/`byId`/`byMode`/
`byDifficulty`, ismeretlen ID-re `null`) · `BuiltinPracticeCatalog` · négy
mód-specifikus `const ScoringProfile` a **befagyasztott** `legacyLearnParity`
mellett · két Riverpod provider (override-olható repository). Hívó UI nincs;
production viselkedés változatlan.
**Ez volt az első kör, amit MiniMax M3 implementált** ([ADR 0069](docs/adr/0069-two-engine-implementer-pool.md),
`engine=minimax-m3`). Review: első kör **CHANGES REQUESTED** (3 MAJOR — mutábilis
`events`/`skillTags`, valótlan `const` doc-comment, ütésenként váltó akkordok az
előírt ütemenkénti helyett), javító kör után **APPROVED**:
[`docs/reviews/e02-r04-review.md`](docs/reviews/e02-r04-review.md). Mindhárom
MAJOR zöld gate mellett csúszott át — a review eldobható próba-teszttel mérte,
nem bemondásra fogadta el.

### Korábbi kör

Korábbi körök (E02-R03 részletes története is):
[`docs/handoff-archive.md`](docs/handoff-archive.md).

## 6. Exact next task

1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése.
2. **E02-R07 — Session clock és state machine**
   (`docs/sdd/03-epic-02-practice-engine.md`, „Kör 7") ÚJ sessionben,
   kör-brieffel (ADR 0055): `PracticeSessionClock` interfész + monotonic
   Stopwatch-implementáció + `FakePracticeSessionClock`, session status,
   commandok, transition reducer, invalid-transition failure, aktív/wall/
   count-in/pause idő, attempt reset, resume policy, finish reason, one-shot
   effect model. **Motorválasztás: KÉRDEZD MEG A USERT indítás előtt** — a kör
   a befagyasztott parity-időzítéssel érintkezik (ADR 0069 §15.6 „érzékeny"
   sor), és a user 2026-07-30-i szabálya szerint az érzékeny körök motorja
   egyeztetendő. Bemenet: az R06 `CompiledPracticeTarget` (a timeline
   nullpontja a session start, a count-in a timeline RÉSZE) és az ADR 0072
   §1.1 időszabálya — a clock ne vezessen be saját beat→idő képletet.
   A briefbe kötelezően: a §12.2 szerint a **daily goalba csak az aktív
   playing idő** számít, a count-in és a pause NEM.
3. **Follow-up (E02-R08/R11-ig nyitva):**
   `docs/rag/chunks/014-play-along-learn.md` elavult — a „liveFrameProvider only
   while playing / closed on pause" állítás ma NEM igaz (`_pause()` nem zárja a
   subscriptiont), plusz 4-beat count-in és 12 lecke. A chunk javítása a
   pause-rés lezárásával EGY commitban (AGENTS.md §9).
4. **Governance-döntés LEZÁRVA (2026-07-30):** a `docs/LESSONS.md` létrejött
   (commit `65c280f`) — hét mért tanulság hivatkozható forrással. Új tanulság
   oda kerül, a saját köre commitjában.

## 7. Required verification (before any "done")

Run as **SEPARATE** calls (chaining OOMs this box):

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
~/flutter/bin/flutter analyze lib/ test/ tool/
~/flutter/bin/flutter test test/<a kör területe>     # full suite: CI-ben (ADR 0053)
~/flutter/bin/dart run tool/check_architecture.dart
cd backend && .venv/bin/python -m pytest             # ha backendhez nyúltál
```

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
