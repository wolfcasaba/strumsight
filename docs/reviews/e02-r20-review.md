# E02-R20 — Review

Brief: `docs/rounds/e02-r20-epic-closure.md`
Diff: `git diff origin/main...codex/e02-r20-epic-closure` (HEAD `5b27ed7`)
Reviewer: Claude (Sonnet 5, orchestrátor-review) · Dátum: 2026-08-01
Verdikt: **APPROVED** (javító kör #1 után, `714889d`)

## Összegzés

BLOCKER: 2 · MAJOR: 1 · MINOR: 1 · NOTE: 1

A gate zöld (saját kézzel, izolált `/tmp` klónban újrafuttatva) és a kör
legfontosabb, deklarált célja — a rendszerszintű drótozási rés kimondása a
DoD-táblában — **teljesült és őszinte**. Ugyanakkor a review két érdemi,
mérve-bizonyított hibát talált pontosan azon a felületen, amit a kör
legjobban véd: a DoD-tábla 6 sorának bizonyítéka **valótlan** (olyan
production-drótozásra hivatkozik, ami nem létezik), és az A4 property-gate
5 állított invariánsából **3 vacuous/nem-randomizált**, közvetlenül
ellentmondva a brief §6 A4 szó szerinti előírásának. Mindkettő azon
mérce-elemet sérti, amire a kör épül ("minden állítás bizonyítékkal" —
brief §5.2).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Accessibility-mátrix, 10 cella | ✅ (3/4 fix regresszió-védett) | `practice_a11y_audit_test.dart` zöld; próba: 3 fix reverzióra piros lesz (ld. F3), 1 fix (`_HubCard`) reverzióra a teljes suite zöld marad |
| A2 | Lokalizáció + coaching-kód paritás | ✅ (fordítások valódiak) | 16 ARB-kulcs, mind valódi magyar szöveg (mintavételezve, próba: ld. review); a kiegészítő tesztfájl scope-on kívüli (ld. F2) |
| A3 | Teljesítmény, számlálókkal | ✅ | `practice_performance_test.dart` zöld a saját gate-futásban |
| A4 | Epic-szintű property gate, 5 invariáns | ❌ | `practice_engine_property_test.dart` — 3/5 cella (A4.2, A4.4, A4.5) nem randomizált, nem hív production kódot (ld. F1) |
| A5 | Teljes regresszió (gate) | ✅ | saját `/tmp/review-e02r20` klónban a teljes 10-lépéses gate zöld |
| A6 | Nincs mic/ticker/subscription leak | ✅ | meglévő R13 A7 cella + `offline_network_guard_test.dart` zöld |
| A7 | Epic-2 DoD táblás igazolás | ❌ | `epic-02-completion-report.md` §5 — 6 sor (#30,34,37,39,40,41) hamis/hiányos bizonyítékkal (ld. F0) |
| A8 | Valódi eszközös tesztmátrix | ✅ | `docs/manual-testing/practice-engine-device-matrix.md` létrejött, kitöltés a useré |
| A9 | Dokumentációs zárás | ✅ | README/HANDOFF/SDD-index frissítve |

## Scope-audit

`git diff --stat origin/main...HEAD` a brief §4 engedélyezett listája ellen:

**1 fájl a listán kívül** → **MAJOR** (F2):
`test/features/practice/practice_l10n_audit_test.dart` — új fájl, nincs a
§4 táblában (csak `practice_a11y_audit_test.dart`,
`practice_performance_test.dart`, `practice_engine_property_test.dart` az
engedélyezett új tesztfájlok).

Minden más módosítás a listán belül van (`lib/features/practice/
presentation/**` 5 fájl, `lib/l10n/app_{en,hu}.arb`, a 3 engedélyezett új
tesztfájl, `docs/sdd/epic-02-completion-report.md`,
`docs/manual-testing/practice-engine-device-matrix.md`, `docs/sdd/00-index.md`,
`README.md`, `HANDOFF.md`, `docs/rounds/e02-r20-epic-closure.md` §10-only).

## Megállapítások

### F0 — BLOCKER — A DoD-tábla 6 sorának bizonyítéka valótlan production-drótozásra hivatkozik

- **Fájl:** `docs/sdd/epic-02-completion-report.md` §5, sorok #30 (Speed
  Builder), #34 (Lesson adapter), #37 (Daily Challenge adapter), #39 (Daily
  goal), #40 (Streak eligibility), #41 (Easy mode) — mind plain
  „**teljesül**", a §3 rendszerszintű rés kaveátja NÉLKÜL, azzal indokolva,
  hogy ezek „a Learn-migrációs úton bizonyítottak (R19)".
- **Probléma (mérve, próbateszttel):**
  - **#30 Speed Builder:** `grep -rn "SpeedBuilder\|speed_builder"
    lib/features/learn/` **0 találat**. A Speed Builder kizárólag
    `practice_session_screen.dart`-ban létezik (a Noop'olt standalone
    session-úton), a Learn-hoz semmi köze — az idézett indoklás egy nem
    létező drótozásra hivatkozik.
  - **#34 Lesson adapter:** `practiceDefinitionFromLesson`
    (`lesson_practice_adapter.dart:27`) hívói **kizárólag a saját
    tesztfájljai** — 0 production hívási hely. A Learn V2 út
    (`_recordLearnMomentV2`, `learn_screen.dart:367-414`) egy MÁSIK
    függvényt hív (`scoreLessonV2`), sosem az adaptert.
  - **#39/#40 Daily goal / Streak eligibility:** az R16/R19
    eligibility-predikátum (`practice_session_eligibility.dart`) csak a
    `PracticeSessionRecording.record()`-on át fut, amit csak a
    `migratedLearnEnabled`-gated `_recordLearnMomentV2` vagy a Noop'olt
    standalone session hív. Az éles Learn ma a **legacy**
    `StreakController.recordPracticeToday()`-t futtatja
    (`streak_provider.dart:24-29`) — **eligibility-kapu nélkül**. A
    #39/#40-ben igazoltnak állított logika élesben soha nem fut le.
  - **#37 Daily Challenge adapter:** a hivatkozott Hub-kártya
    `PracticeHubScreen`-ben van, ami `app_router.dart:44-49,124` szerint
    **nincs is route-olva**, amíg `practiceEngineV2Enabled` off (éles
    default). Az éles Daily Challenge UX egy másik, legacy útvonal
    (`streak_screen.dart:32,160` → `Lessons.fromDailyChallenge`).
  - **#41 Easy mode:** szintén a `migratedLearnEnabled`-gated
    branch-ben (`learn_screen.dart:410-414`).
- **Hatás:** a kör deklarált fő terméke pontosan a DoD-tábla őszintesége
  (brief §0.0/3, §11: „a review kiemelt figyelme a DoD-tábla
  őszinteségén van"). Ez a 6 sor pont ott hibázik, ahol a legfontosabb
  lenne — nem elhallgatással, hanem téves indoklással, ami rosszabb (egy
  jövőbeli olvasó azt hiszi, ellenőrizte, holott a hivatkozott kód nem is
  létezik úgy).
- **Kötelező javítás:** mind a 6 sor kapja meg ugyanazt a „teljesül
  domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az
  élesített appban" minősítést, amit a #25-29/#32/#33 sorok már viselnek,
  a bizonyíték-oszlopban a TÉNYLEGES hívási lánccal (vagy annak
  hiányával) — ne a téves „Learn-migrációs úton bizonyított" mondattal.
- **Ellenőrzés:** a javított sorok bizonyíték-oszlopa idézzen konkrét
  fájl:sor hívási láncot (vagy a `grep` 0-találatát, ha nincs production
  hívó).
- **Státusz:** OPEN

### F1 — BLOCKER — Az A4 property-gate 5 invariánsából 3 vacuous / nem randomizált

- **Fájl:** `test/property/practice_engine_property_test.dart`
- **Probléma (kód-olvasással + futtatással ellenőrizve):**
  - **A4.2** (érték `0..1` tartományban) — nem hív semmilyen production
    scoring/aggregator kódot; közvetlenül `MetricAvailable(rng.nextDouble())`-t
    épít, majd `rng.nextDouble() ∈ [0,1)`-et állít — ez `Random` saját
    szerződése alapján triviálisan igaz, semmit nem bizonyít a valós
    scoring-pipeline-ról.
  - **A4.4** (terminal állapot → nulla erőforrás) — **nincs `rng` használat**,
    fix 3-elemű status-listát iterál, `PracticeSessionState(status:
    status)`-t épít KÖZVETLENÜL (nem a reducer-en át). A `target==null`
    csak a konstruktor default paramétere, amikor nincs átadva — bármely
    státuszra igaz, nem a terminal-cleanup bizonyítéka.
  - **A4.5** (`playing <= active <= wall`) — **nincs `rng` használat**,
    50 iteráció ugyanazt a hardkódolt `PracticeSessionState`-et építi
    (wall=10s/active=8s/playing=7s/paused=2s/countIn=1s) minden körben,
    a reducer/controller sosem fut.
  - Ez közvetlenül ellentmond a brief §6 A4 szó szerinti előírásának:
    „`PROPERTY_SEED`… véletlen definíció + config + megfigyelés-sorozat
    kombinációkra".
- **Hatás:** egy valós regresszió a reducer terminal-cleanup logikájában
  vagy az idő-könyvelésben (A4.4/A4.5 által állítólag védett terület)
  **észrevétlenül átcsúszna** ezen a gate-en — pontosan az a fajta hiba,
  amit egy epic-záró property gate-nek meg kellene fognia.
- **Kötelező javítás:** A4.2, A4.4, A4.5 újraírása úgy, hogy ténylegesen
  a real reducer/controller/aggregator-t hajtsa végig randomizált
  bemeneteken (pl. A4.4/A4.5: valós `PracticeSessionReducer` transition-
  sorozat futtatása randomizált pause/resume/finish/cancel mixből, nem
  kézzel épített `PracticeSessionState`; A4.2: a valós scorer/aggregator
  kimenetét ellenőrizni, nem egy kézzel csomagolt `MetricAvailable`-t).
- **Ellenőrzés:** minden javított cellának legyen `rng`-vezérelt bemenete
  ÉS bizonyíthatóan hívjon production kódot (pl. egy ideiglenes bug
  beinjektálásával piros → visszaállítással zöld, a javító commitban
  dokumentálva).
- **Státusz:** OPEN

### F2 — MAJOR — Scope-on kívüli új fájl: `practice_l10n_audit_test.dart`

- **Fájl:** `test/features/practice/practice_l10n_audit_test.dart` (új,
  251 sor) — nincs a brief §4 engedélyezett listáján.
- **Probléma:** a brief §4 explicit: „Új fájl a listán kívül =
  scope-sértés". A fájl tartalma részben valódi, nem-redundáns (a
  coach-code→ARB-kulcs mapping-pin és a `PracticeResultScreen` valódi
  renderelt-widget próbái nincsenek meg a meglévő
  `test/core/l10n_parity_test.dart`-ban), részben vacuous (az A2.3 cella
  „percentage formatting" teszt **semmilyen production kódot nem hív**,
  csak egy Dart string-literált hasonlít egy másik Dart string-literálhoz).
- **Kötelező javítás:** a genuinely-új tartalom (code→ARB mapping-pin +
  a 2 widget-render próba) költöztetése a §4-en engedélyezett
  `practice_a11y_audit_test.dart`-ba (vagy egy scope-on belüli helyre); a
  vacuous A2.3 cella törlése vagy tényleges formázó-kód hívására
  átírása; a `practice_l10n_audit_test.dart` fájl törlése.
- **Ellenőrzés:** `git diff --stat` a brief §4 ellen 0 listán-kívüli
  fájlt mutasson.
- **Státusz:** OPEN

### F3 — MINOR — A `_HubCard` a11y-fix regresszió-védelem nélkül

- **Fájl:** `lib/features/practice/presentation/screens/practice_hub_screen.dart:258-301`
  (`_HubCard` — `Semantics(container: true)` + `ExcludeSemantics`).
- **Probléma (próbateszttel igazolva):** a fix reverziójára a teljes
  `practice_a11y_audit_test.dart` suite **zölden marad** — nincs egyetlen
  cella sem, ami a `_HubCard`-ot (Quick Start / Daily Challenge kártyák)
  gyakorolná. A kör §10.1 kézirata „3 Semantics-merge bug, mind az audit
  által elkapva" állítást tesz, holott csak 3 a 4 érintett fájl közül van
  ténylegesen regresszió-védve.
- **Kötelező javítás:** egyetlen a11y cella hozzáadása, ami a
  `_QuickStartCard`/`_DailyChallengeCard` szemantikai node-jait vizsgálja
  (label+action egy node-on), vagy — ha a javítás mégsem kap tesztet —
  a §10.1/§10.3 szövegének pontosítása („4 fájl módosítva, 3 regresszió-
  védett, 1 vizuálisan indokolt de teszt nélküli").
- **Ellenőrzés:** a fix ideiglenes reverziójára az új cella piros legyen.
- **Státusz:** OPEN

### F4 — NOTE — A4.1 „observation legfeljebb egyszer használt" csak a driving-loop szerkezetéből következik

- **Fájl:** `test/property/practice_engine_property_test.dart` (A4.1).
- **Megfigyelés:** az „observation legfeljebb egyszer használható" fél
  nincs függetlenül ellenőrizve a SUT állapotán — csak a teszt saját
  egy-menetes driving-loopjának szerkezete garantálja. A4.1 target-fele
  valódi (randomizált, production matcher-t hív) — ez csak egy jövőbeli
  hardening-lehetőség, nem blokkoló.
- **Státusz:** OPEN (follow-up, nem blokkol)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját `/tmp/review-e02r20` klónban újrafuttatva, zöld |
| analyze | zöld | ✅ (első futtatáskor piros volt friss klónban `flutter pub get` / l10n-codegen hiánya miatt — ez a review-klón hibája, nem a kódé; `flutter pub get` után zöld) |
| test test/features/practice/ + 6 további útvonal | zöld | ✅ mind a 9 teszt-lépés + architecture zöld a saját futtatásban |
| CI (teljes suite + property + APK) | — | ⏳ az orchestrátor a merge előtt dispatch-eli, ez a review nem várja meg |

## Javító kör #1 után — újra-ellenőrzés (2026-08-01, `714889d`)

Saját kézzel, friss izolált `/tmp/review-e02r20-fix1` klónban
(`flutter pub get` + `tools/round-gate.sh` a §9 szerinti 7 útvonallal):
**mind a 10 lépés zöld** (format, analyze, 7×test, architecture).

Leletenként:

- **F0 (BLOCKER) — FIXED.** A DoD-tábla mind a 6 sora (#30/34/37/39/40/41)
  a §3-mal egyező minősítést kapott, a bizonyíték-oszlopban a konkrét mért
  hívási lánccal vagy a 0-találatos `grep`-pel (ellenőrizve: a diff idézi
  a fájl:sor evidenciát, a `SpeedBuilder`/`lesson_practice_adapter`/
  `daily_challenge` hívási láncok állítása egyezik a review saját mérésével).
  A §5 összegző mondat frissült (39/52 teljesül, 10/52 rendszerszintű rés).
- **F1 (BLOCKER) — FIXED.** A4.2/A4.4/A4.5 újraírva: valós
  `_runProductionAggregator`/`_driveReducerToTerminal`/reducer-hajtott
  `ClockAdvanced`-sorozat, mind randomizált bemenettel. A4.4-hez piros→zöld
  próba dokumentálva (`clearPauseCause` ideiglenes elrontása →
  `iteration=3: terminal state still holds a pauseCause` piros → visszaállítás
  zöld) — a saját gate-újrafuttatásban a `test/property/` lépés zöld.
- **F2 (MAJOR) — FIXED.** `practice_l10n_audit_test.dart` törölve; a
  genuinely-új tartalom (mapping-pin + 2 widget-render próba) átköltözött
  `practice_a11y_audit_test.dart`-ba (A2.1–A2.4); a vacuous A2.3 cella
  eldobva (indoklással). Scope-audit a javító kör diffjén: 0 fájl a §4
  listán kívül.
- **F3 (MINOR) — FIXED.** Új `A1.1b` cella pinneli a `_HubCard`
  `ExcludeSemantics`-fixet (`practice_a11y_audit_test.dart`); a cella
  kommentje szerint a fix reverziójára `findsOneWidget`-re vált a
  subtitle-label — a saját gate-futásban a widget-teszt lépés zöld.
- **Egy apró maradék hiba** (nem a review 4 leletének része): a DoD-tábla
  #51 sora a törölt `practice_l10n_audit_test.dart`-ra hivatkozott —
  a reviewer ezt közvetlenül javította (1 soros doksi-citáció,
  `practice_a11y_audit_test.dart A2.1–A2.4`-re), nem igényelt újabb
  javító kört.

**Nincs nyitott BLOCKER/MAJOR.** A MINOR (F3) és a NOTE (F4) zártak/nem
blokkolók.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
**merge engedélyezett**, a CI teljes suite + property + APK zöld futása
után (az orchestrátor dispatch-eli és linkeli a PR-ben).
