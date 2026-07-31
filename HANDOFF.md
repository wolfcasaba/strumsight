# HANDOFF — StrumSight 🎸

> **Read this first at the start of every session.** Single source of truth for
> "what's done / what's next" — short operational snapshot (SDD Ch2 §16.6
> structure since E01-R16). Update after every round (see
> [How to update](#how-to-update-this-file)). Last updated: **2026-07-31 (GOV-01)**.
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

`main` @ [PR #31](https://github.com/wolfcasaba/strumsight/pull/31) (GOV-01,
squash-merge `c15ccf8`), CI run
[30623157950](https://github.com/wolfcasaba/strumsight/actions/runs/30623157950)
zöld (build-apk + Coverage). Kör-branch törölve. Ez governance-kör volt, Dart
kódot nem érint, ezért a lokális mérce a grep-mátrix volt, nem a gate — a merge
utáni `main`-en függetlenül újramérve: a `tools/round-gate.sh` artefaktumra
**8 fájl** hivatkozik, a `tools/wait-for-round.sh`-ra a driver-skill.

Az utolsó Dart-érintő kör (E02-R08, PR #30, `e80a878`) CI-runja
[30613858430](https://github.com/wolfcasaba/strumsight/actions/runs/30613858430)
zöld volt; a `main`-en akkor mérve: format 528/0 changed · analyze No issues
found · `test/features/practice/` **440** zöld · property **6** zöld ·
architecture OK (12 allowlisted, változatlan).

## 5. Last completed round

**GOV-01 — A gate- és várakoztató artefaktum átvezetése** (governance-kör,
nem SDD-fejezet, PR #31): a `tools/round-gate.sh` és a `tools/wait-for-round.sh`
**futtatható artefaktumok** átvezetése mindenhova, ahol eddig kézzel felsorolt
parancslista vagy szabad szöveg állt — `AGENTS.md` §12 (a normatív forrás) és
§15.3, `CLAUDE.md`, négy kör-skill (`sdd-round-driver`, `sdd-round-review`,
`round-brief-prep`, `strumsight-how-we-develop`), a `verify-before-done` skill
és a DoD. A `sdd-round-driver` §3-ba bekerült a várakoztató artefaktum mind a
négy kilépési kódjával (`0=done`, `3=stopped`, `4=stalled|timeout|unknown`,
`5=lejárt`) — ez az L12 hatórás vakfoltjának szerkezeti lezárása.
Implementer: **MiniMax M3**.

Review: első kör **CHANGES REQUESTED** (0 BLOCKER · 0 MAJOR · **1 MINOR** ·
2 NOTE), javító kör után **APPROVED**:
[`docs/reviews/gov-01-review.md`](docs/reviews/gov-01-review.md).
A MINOR **az orchestrátor felmérési hibája volt**, nem az implementeré: a
felmérő greppet a hosszabb `flutter analyze lib/ test/` alakra futtattam, ezért
három, a rövidebb alakot használó skill kimaradt a brief §4-listájából — köztük
a `verify-before-done`, amire a `CLAUDE.md:116` **név szerint ráirányít**. Az
implementer helyesen nem tágította a listát, hanem jelentette; a feloldás
dokumentált brief-revízió (§0.2). Ebből lett a `docs/LESSONS.md` **L15**.

### Korábbi kör

**E02-R08 — Observation gateway és audio lifecycle adapter**
([ADR 0074](docs/adr/0074-practice-observation-gateway.md) implementációja,
PR #30): a `LiveFrame → PracticeObservation` híd, és a kör lényege — **a
mikrofon-hallgatás igazságforrása az E02-R07 session-státusza lett, nem egy
widget-mező**. A `practiceCaptureActiveByStatus` `const` tábla mind a 11
státuszra terjed ki, a kulcshalmaz-egyezést teszt őrzi (új státusz ⇒ piros, nem
csendes `false`), és a `paused → false` a `docs/rag/chunks/014-play-along-learn.md`
**pause-résének szerkezeti lezárása a V2 úton**. Az adapter a legacy időfelosztást
őrzi: engine-óra de-jitter a szigorú `<` predikátummal, a kalibrált input latency
a matcheré marad (ADR 0074 §3). Hívó és provider nincs, a legacy Learn út és a DSP
érintetlen, flagek OFF → production viselkedés bitre azonos.
Implementer: **MiniMax M3** (a user döntése).

Review: első kör **CHANGES REQUESTED** (0 BLOCKER · **2 MAJOR** · 1 MINOR · 3 NOTE),
javító kör után **APPROVED**:
[`docs/reviews/e02-r08-review.md`](docs/reviews/e02-r08-review.md).
**Mind a hat lelet 437 zöld teszt és 5 zöld property mellett csúszott át** — két
eldobható próbateszt mérte, a legacy referenciával szemben: a frame-kézbesítési
lag a chord observationökre is rámehetett egy beégett, MÁSIK strum lagjával
(`2.000 s` → `1.700 s`), és a **közös monoton padló kioltotta a strum
de-jittert** (`0.916 s` → `1.000 s`, azaz a 84 ms-os korrekcióból 0 maradt). A
javítás után a próbák eltérése a legacy képlettől **0 µs**.

**Folyamat-hozadék:** a kör három **orchestrátor-oldali** hibát is termelt, mind
a mércét érintve — hiányzó küszöb-fölötti mátrixcella (az implementer
`stopped`-dal fogta meg), kimondatlan korrekciós hatókör, és egy olyan
valódi-sértés próba, amit a kért őr elvileg sem tudott volna kimutatni. Ebből
két dokumentált brief-revízió (§0.0, §0.1), a `docs/LESSONS.md` **L12–L14**, és
a `tools/wait-for-round.sh` futtatható várakoztató artefaktum lett.

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
   APK-val; eredmény vissza → completion report frissítése. Az APK a PR #30
   CI-runjából tölthető
   ([30613858430](https://github.com/wolfcasaba/strumsight/actions/runs/30613858430)).
2. **~~GOV-01~~ — KÉSZ** (PR #31, 2026-07-31).
3. **E02-R09 — Event matcher és legacy timing parity** ÚJ sessionben.
   **A brief és az ADR KÉSZ és kiadható:**
   [`docs/rounds/e02-r09-event-matcher.md`](docs/rounds/e02-r09-event-matcher.md) +
   [ADR 0075](docs/adr/0075-practice-event-matcher.md) (az ADR-t az orchestrátor
   már megírta — az implementer `docs/adr/`-hez NEM nyúl).
   **Implementer motor: Codex** (a user döntése 2026-07-31 — baseline-érzékeny
   matcher). Branch: `codex/e02-r09-event-matcher`.

   > **Kör-számozási javítás (2026-07-31):** ez a sor korábban „E02-R09 =
   > Session controller"-t írt. **Téves volt.** Az SDD-fejezet szerint a Kör 9
   > az **event matcher**, a Kör 10 a három scorer, és a
   > `PracticeSessionController` a **Kör 11** — az eddigi számozás 1:1
   > (E02-R08 = „Kör 8 — Observation gateway"). Következmény: a
   > `practiceCaptureActiveByStatus` tábla első valódi hívója és az E02-R07
   > nyitott clock-NOTE-ja **az E02-R11-ben** zárul, nem az R09-ben.
4. **Az E02-R08 nyitva hagyott follow-upjai** (a review §4 + a brief §10.6):
   - a `ScoringProfile → PracticeObservationConfig` küszöb-leképezés (R09);
   - a chord-confidence felvitele a `LiveFrame`-be — az Analyze úton is közös,
     ezért külön kör; addig a Live adapter `confidence: 1.0` = „nem mért";
   - a `StrumEngine.start()` `AppResult`-osítása, hogy a „foglalt mikrofon"
     szinkron `start()`-hiba lehessen (ADR 0074 §7 ismert korlát);
   - a legacy `learn_screen.dart` `_pause()` pause-rése — **felhasználó-látható**,
     valódi eszközön verifikálandó, a migrációs kör (E02-R11) hatásköre; a
     chunk 014 addig a mai igazságot írja le.
5. **Nyitva hagyott NOTE (E02-R07):** `MonotonicPracticeSessionClock.start()`
   pause alatt teljes resetet végez, a szerződés viszont idempotenciát ír elő.
   Nem blokkol; a **controller-körben (E02-R11)** zárandó, amikor valódi hívó
   lesz — nem az R09-ben (lásd a 3. pont kör-számozási javítását).

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
