# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-07-30 (E02-R07)**.
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

`main` @ [PR #28](https://github.com/wolfcasaba/strumsight/pull/28) (E02-R07,
merge `b5e0dfc`) + [PR #29](https://github.com/wolfcasaba/strumsight/pull/29)
(hiánypótlás, merge `0c9ab51`, CI run
[30584474704](https://github.com/wolfcasaba/strumsight/actions/runs/30584474704)
zöld: gate-sor + teljes suite + randomizált property gate + APK + coverage).
Kör-branchek törölve. **Figyelmeztetés a jövőre (L11):** a PR #28 az E02-R07
javító körének kódja NÉLKÜL ment fel — a munkapéldányban készült commitot nem
húzták vissza a fő repóba. A PR #29 pótolta; a `main` most tartalmilag helyes.
Merge után a `main`-en függetlenül újrafuttatva (`tools/round-gate.sh`):
format 520/0 changed · analyze No issues found · `test/features/practice/` 379
zöld · property +2 · architecture OK.

## 5. Last completed round

**E02-R07 — Session clock és determinisztikus state machine**
([ADR 0073](docs/adr/0073-practice-session-state-machine.md) implementációja,
PR #28 + #29): `PracticeSessionClock` interfész + `PracticeClockSnapshot`
(`wall`/`active`/`paused`/`attempt`, invariáns `active + paused == wall`) +
monoton `Stopwatch`-alapú `MonotonicPracticeSessionClock` az **`application/`**
rétegben (a domain purity-teszt tiltja a `Stopwatch`-ot) + `FakePracticeSessionClock`
a `test/support/` alatt · `PracticeSessionStatus` (11 érték) és a SDD §11.2
átmenettáblájának **szó szerinti** `const` átirata, amin a reducer MINDEN
statusváltása átmegy · egyetlen pure reducer, bemenete a 11 SDD-command és 4
környezeti signal (`PreparationSucceeded/Failed`, `PermissionDenied`,
`ClockAdvanced`); soha nem dob, tiltott bemenetre a state változatlan +
`InvalidSessionTransitionFailure` (`FailureCode.practiceInvalidSessionTransition`) ·
**időkönyvelés (SDD §12.2):** hat akkumulátor,
`timelinePosition = timelineBase + max(0, active − activeBase)`, **a napi célba
kizárólag a `playingElapsed` számít** (count-in és pause NEM) · resume: egy
ütemnyi count-in, majd folytatás a `barBoundaries` szerinti ütemhatárról ·
one-shot effect-modell. Saját beat→idő képlet nincs (ADR 0072 §1.1). Hívó UI
és provider nincs, a legacy Learn út érintetlen, flagek OFF → production
viselkedés változatlan. Implementer: **MiniMax M3** (a user döntése, érzékeny kör).

Review: első kör **CHANGES REQUESTED** (0 BLOCKER · 4 MAJOR · 3 MINOR · 2 NOTE),
javító kör után **APPROVED**:
[`docs/reviews/e02-r07-review.md`](docs/reviews/e02-r07-review.md).
**Mind a hét lelet 370 zöld teszt és zöld gate-sor mellett csúszott át** — a
reviewer eldobható próbatesztje mérte: a 2. attempt idővonala 0 helyett 3 s-nál
indult · a reducer a §11.2 táblán KÍVÜLI élt hajtott végre
(`permissionRequired → ready`) · a property gate a tábla **tranzitív lezártját**
mérte az élenkénti pár helyett, és pont ez rejtette el az előzőt · 2 ütemes
count-in 4 kattanást adott 8 helyett. A hétből **három gyökere maga a kör-brief
volt** — dokumentált brief-revízióként felülírva (§0.0), nem utólagos
lista-tágítással. A javító kör után a reviewer saját próbatesztje mind a hetet
zártnak mérte, és a felélesztett property-őr **valódi-sértés próbája** (a
`_canTransition` szándékos eltávolítása) pirosra váltott.

**Folyamat-hozadék ugyanebben a körben:** `tools/round-gate.sh` — a záró gate
futtatható artefaktumként (az implementer háromszor futtatta `| tail -N`-nel a
szó szerinti tiltás ellenére); a `docs/execution/08-round-brief.md` sablon négy
új szabálya; `docs/LESSONS.md` **L09–L11**; és a kiadható
[`docs/rounds/gov-01-gate-artifact-rollout.md`](docs/rounds/gov-01-gate-artifact-rollout.md)
brief a gate-artefaktum rendszer-szintű átvezetésére.

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
2. **GOV-01 — a gate-artefaktum átvezetése** ÚJ sessionben. A brief KÉSZ és
   kiadható: [`docs/rounds/gov-01-gate-artifact-rollout.md`](docs/rounds/gov-01-gate-artifact-rollout.md).
   Mechanikus szövegátvezetés (AGENTS.md §12, CLAUDE.md verify-gate, három
   skill, DoD, a két round-wrapper fejléce) — **javasolt motor: MiniMax M3**,
   az acceptance két `grep` + `git diff --stat`. Dart kódot nem érint.
3. **E02-R08 — Observation gateway és audio lifecycle adapter**
   (`docs/sdd/03-epic-02-practice-engine.md`, „Kör 8") ÚJ sessionben,
   kör-brieffel. Bemenete az R07 állapotgépe: a gateway a
   `status == running` állapotot kérdezze, ne widget-flaget — ezzel zárható a
   `docs/rag/chunks/014-play-along-learn.md` pause-rése is (lásd 4. pont).
   Előre kiosztható ADR: **0074**.
4. **Follow-up (E02-R08/R11-ig nyitva):**
   `docs/rag/chunks/014-play-along-learn.md` elavult — a „liveFrameProvider only
   while playing / closed on pause" állítás ma NEM igaz (`_pause()` nem zárja a
   subscriptiont), plusz 4-beat count-in és 12 lecke. A chunk javítása a
   pause-rés lezárásával EGY commitban (AGENTS.md §9).
5. **Nyitva hagyott NOTE (E02-R07):** `MonotonicPracticeSessionClock.start()`
   pause alatt teljes resetet végez, a szerződés viszont idempotenciát ír elő.
   Nem blokkol (a reducer a második `StartPractice`-t elutasítja); az E02-R09
   controller-körben zárandó, amikor valódi hívó lesz.

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
