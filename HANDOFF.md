# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-07-30 (E02-R04)**.
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

`main` @ [PR #25](https://github.com/wolfcasaba/strumsight/pull/25) (E02-R04,
merge `b1ab7ab`, CI run
[30562187556](https://github.com/wolfcasaba/strumsight/actions/runs/30562187556)
zöld: gate-sor + teljes suite + randomizált property gate + APK + coverage).
Kör-branch: `mm/epic-02-round-04-practice-catalog` (merge után törölve).

## 5. Last completed round

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

**E02-R03 — Practice domain modellek és validáció** (ADR 0068 implementációja):
13 új pure-Dart modellfájl + `meter.dart` MINOR-1 zárás a
`lib/features/practice/domain/model/` alatt — a Practice V2 teljes
domain-szerződése (event/definition, session config, sealed observation,
verdict, metrikák, attempt/session result, scoring profile, enumok), minden
aggregátum immutable, aggregáló `validate()`-tel, 60 stabil validációs kóddal
és strukturális lista/map-egyenlőséggel · test-oldali purity-őr valódi-sértés
RED→GREEN próbával · 101 új determinisztikus unit-teszt (a domain könyvtárban
125), rétegenkénti TDD-evidenciával. Hívó kód nincs — production viselkedés a
`ticksPerBar` fail-fast-on kívül változatlan. Az implementáló process menet
közben gépoldali okból megszakadt; ugyanaz a Codex-session resume-mal zárta a
kört, a teljes gate-mátrix friss újrafuttatásával (brief §10.4). Review:
**APPROVED** (0 BLOCKER/MAJOR/MINOR · 3 NOTE — caller-immutability szerződés,
`listEquals` névütközés-kockázat nem-domain hívóknál, chord-label
konzisztencia-teszt az R05 adapter-körre), izolált-klónos független
gate-újrafuttatással és tételes 29/29 scope-audittal:
[`docs/reviews/e02-r03-review.md`](docs/reviews/e02-r03-review.md).
Korábbi körök: [`docs/handoff-archive.md`](docs/handoff-archive.md).

## 6. Exact next task

1. **User:** §16.3 audio-regresszió + §16.4 teljesítmény-megfigyelések a friss
   APK-val; eredmény vissza → completion report frissítése.
2. **E02-R05 — Legacy adapterek (Lesson / Song / Analyze / Daily Challenge)**
   (`docs/sdd/03-epic-02-practice-engine.md`, „Kör 5") ÚJ sessionben,
   kör-brieffel (ADR 0055). **Implementer: a besorolás szerint** (ADR 0069
   §15.6) — az adapterek jól specifikált, parity-teszttel mérhető munkák, tehát
   alapesetben MiniMax M3; ha a brief írásakor kiderül, hogy a legacy
   `Lesson.events` szemantika felderítést igényel, Codex. A briefbe kötelezően:
   az R03 review NOTE-3 (chord-label konzisztencia-teszt) és az **R04 tanulsága
   — minden szövegesen leírt tartalmi előírás mellé gépi mérce is kell**
   (kipinnelt szekvencia), különben a tartalmi csúszás átmegy a zöld gate-en.
   Az R04 katalógus `const` adatként
   írja le magát az R03 domain-modellekkel. A briefbe: az R03 review NOTE-1
   (const-forrásból épülő katalógus → a caller-immutability szerződés itt
   triviálisan teljesül, de rögzítendő).
3. **Follow-up (E02-R08/R11-ig nyitva):**
   `docs/rag/chunks/014-play-along-learn.md` elavult — a „liveFrameProvider only
   while playing / closed on pause" állítás ma NEM igaz (`_pause()` nem zárja a
   subscriptiont), plusz 4-beat count-in és 12 lecke. A chunk javítása a
   pause-rés lezárásával EGY commitban (AGENTS.md §9).
4. **Governance-döntés (user):** a Codex E02-R02 §10 lelete — a globális
   együttműködési szabályzat `docs/LESSONS.md`-re hivatkozik, ami ebben a
   repóban nem létezik (létrehozni vagy a hivatkozást kivezetni).

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
