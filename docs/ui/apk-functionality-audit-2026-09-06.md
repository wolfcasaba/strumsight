# Audit — „APK build után minden működjön az appban" (2026-09-06)

Mérce: a `build-apk.yml` által szállított `development` APK-ban minden
fejlesztett képernyő és folyamat legyen elérhető ÉS működjön. Ez az audit
azt méri, mi hiányzik ehhez, és milyen körökben zárható.

Minden állítás mérésből származik. Környezet: Claude Code remote konténer
(nincs Flutter SDK — Dart-oldali állítás csak kód-olvasásból és a CI-ból;
a `tools/tests` Python-suite lefut: **786 passed, 4 skipped, 1 failed** — a
bukó cella a dokumentált környezeti `gh`-előfeltétel,
[`docs/execution/remote-container-environment.md`](../execution/remote-container-environment.md) §5).

## 0. Összkép

| Fa | Állapot | Bizonyíték |
|---|---|---|
| `main @ 1ae9e55` | Full Gate **zöld** (run 33998450680); Router CI a `4186057` docs-commiton **piros** (completion-matrix drift, 2 cella), amit az `1ae9e55` fail-safe commit javított (`sync-completion-matrix.py --check` → in sync) | MCP `actions_list` + helyi `--check` |
| `ops/community-data-layer @ abb486d` (PR #594) | `build-apk.yml` **zöld** a `4489307` HEAD-en (run 34022459707, 10 656 teszt); teszt-APK kiadva (`test-2026-09-06-4489307`). **`mergeable_state: dirty`** — a `main` azóta 6 commitot lépett (E17-R01 + két heal). | MCP `pull_request_read`, `actions_list` |
| PR #593 (`ops/e17-parallel`) | 5 E17-sor hold → pending; **dirty**. A #594 után a queue-döntés újraértékelendő (a #594 a Ch17 R02–R12 tartalmát lényegében szállítja). | MCP |

**A döntő tény:** a `main` a Ch17-ből EGY kört zárt le (E17-R01, First-Win
állomás); a `ops/community-data-layer` ág viszont ugyanazt a fejezetet (és
két, a Ch17-terv által NEM ismert kompozíciós hibaosztályt) 33 committal már
lezárta — CI-zölden. A „minden működjön" út tehát nem a 13 hold-on álló E17
kör újraimplementálása, hanem **a #594 integrálása a mai `main`-nel**, majd a
#594 által mérve nyitva hagyott rések bezárása.

## 1. Mi hiányzik a `main`-en (a #594 NÉLKÜL) — mért

`dart run tool/check_screen_reachability.dart` a Ch17 nyitásakor:
`96 képernyő, 73 elérhető, 23 elérhetetlen, 27 flag-kapuzott`; az E17-R01
óta 22 elérhetetlen.

### 1.1 Halott (sehonnan nem hivatkozott) képernyők — 22

| Feature | db | Akadály (fájl:sor) |
|---|---|---|
| community | 13 | 0 route a routerben; 11 `throw UnimplementedError` seam (`feed_controller.dart:213,225`, `notification_controller.dart:183`, `challenge_controller.dart:132`, `challenge_result_controller.dart:111`, `club_list_screen.dart:91`, `club_detail_screen.dart:112,121,133`); a `feed/post/club/notification/social_graph` repository-impl **nem létezik**; a 3 létező impl-t (`challenge`, `profile`, `relationship`) semmi nem importálja |
| practice_generator | 4 | `practice_generator_providers.dart:88` (`exerciseCandidateResolverProvider`) és `:151` (`generationPlanInputBuilderProvider`) dob — a flag BE van a dev buildben, tehát ez ÉLES hiba a 4 nem routolt képernyőn |
| audio_analysis (V2 capture) | 3 | nincs route, nincs kompozíció (`data/capture/analysis_recorder.dart` létezik) |
| ai_tutor | 1 | `PracticePlanPreviewScreen` — nincs `PracticePlanDraft`-előállító |
| song_trainer | 1 | `SetlistSessionScreen` — a `SetlistItemRunner` typedefnek nincs éles impl-je |

### 1.2 Routolt, de MINDEN környezetben KI (12 képernyő)

`FeatureFlags.forEnvironment` hardkódolt `false`: `aiTutorEnabled` (5
képernyő), `visionEnabled` + 10 al-flag (3), `audioAnalysisV2Enabled` +
`analysisComparisonEnabled` (4). A `communityEnabled` + 4 al-flag csak
dart-define-nal kapcsol, amit a `build-apk.yml` nem ad át. `accountEnabled`
ugyanígy KI → a Profil hub Sign-in nélkül.

### 1.3 Routolt és BE, de NEM működik (a Ch17-terv által NEM ismert osztály)

| Hely | Mért hiba | Hatás a felhasználónál |
|---|---|---|
| `lib/main.dart:88-102` | 6 override; a fában **17** provider dob override nélkül (`analysisRepositoryProvider`, `setlistRepositoryProvider`, …) | a **Library fül** `StateError`-t kap a dev buildben is |
| `practice_session_providers.dart:76-100` | a metaadat-kódok placeholderek (`practice.mode.unknown`…) → mindig `NoopPracticeSessionRecorder` | **egyetlen gyakorlás sem íródik a történetbe** |
| `practice_result_providers.dart:37-40` | `_NoopRewardLedgerRepository` az alapérték, nincs felülírva | az eredmény-képernyő sosem mutat jutalmat |
| `app_router.dart:406-409` | a `practiceResult` route `PracticeResultFallback`-et épít | nem a valódi eredmény-képernyő |
| `song_trainer_providers.dart:432-434` | `_InMemorySongResumeRepository` | a dal-tréner folytatási pontja app-újraindításkor elvész |
| `song_trainer_screen.dart:278` / `:308` | sebesség-`Slider` `onChanged: null`; `onPlay: () {}` | inert vezérlők a lejátszás alatt |
| `tutor_providers.dart:376` | `LocalTutorModelGatewayStub` → minden kérésre `tutor.model_gateway.unavailable` | flag BE mellett sem ad egy tokent sem |
| `vision_setup_screen.dart:312` | a `vision-audio-only-continue` CTA `onPressed: () {}` | enabled gomb, ami nem csinál semmit |
| `bookmarks_screen.dart:168-189` | `_NoopBookmarksController`, üres stream | a könyvjelző-képernyő üres és tétlen |
| `post_composer_screen.dart:171` | „Attach media" snackbar, feltöltés nincs | ismert (R-SEC-01 / R-PRIV-01) |
| `club_detail_screen.dart:573-598`, `followers_screen.dart:12` | tagok-fül csak tipp-szöveg; követő-sorok placeholder | nincs valós lista |

## 2. Mit zárt le a `ops/community-data-layer` (#594) — mért a HEAD-jén

| Terület | Állapot |
|---|---|
| Elérhetetlen képernyők | 23 → **3** (`setlist_session`, `practice_plan_preview`, `SetlistListScreenV2`); a populáció 96 → 97 (a `V2` utótag most mért) |
| Kompozíciós gyökér | `lib/app/production_overrides.dart`: analysis V2 + setlist/haladás + community cache/kv/logger/repo-k bekötve; őr: `production_composition_test.dart`, `production_repository_wiring_test.dart` |
| Community | 13 route, kapu-képernyő HUB-ként, `HttpCommunityPostRepository` (10 met.), `HttpCommunityClubRepository` (9 met.), `ApiClient.patchJson`, `getJson` query-param javítás; backend: komment/értesítés/klub/reakció routerek + értesítés-kibocsátás (13 → 17 router, +20 végpont) |
| Belépési pontok | analysis V2 capture, tervező (Today/Setup, adaptív hub), tutor, vision geometria; útvonal-konstans bejövő hivatkozás nélkül 39 → 17 |
| Flag-ek | `STRUMSIGHT_PREVIEW_ALL` + `FeatureFlags.forShippedBuild`: a `development` build KÓDBÓL hordozza a teljes tesztkonfigot (fiók BE, `https://casaba.app/strumsight`, community BE, preview-all BE, média KI); `lab`/`production` bájtra változatlan |
| Mérce | golden variáns-mátrix 72 → 93 képernyő (4 valódi 2.0-s textscale-hiba javítva), 21 bejárás-kizárási sor, adatleltár + data-safety |

**Amit a #594 maga is nyitva hagyott (mérve, HANDOFF a HEAD-jén):** klub-poszt
írás kliensről (belső `club_id`), `profilePosts` végpont, hang-import
folyamat, `songTrainerResult` effect-listener, tervező preview/change-review
`extra` nélkül, a 3 elérhetetlen képernyő, community média. Az 1.3 táblából
a #594 **nem** érinti: practice-történet (`NoopPracticeSessionRecorder`),
jutalom-ledger, `PracticeResultFallback`, dal-tréner resume/slider/play,
tutor gateway-stub, vision CTA, bookmarks noop. (Mind mérve `git grep`-pel az
ág HEAD-jén.)

A HANDOFF szerint „WP-H1–H5 folyamatban (5 párhuzamos ügynök)" — az ág
utolsó commitja a HANDOFF-frissítés, a H-csomagokból **semmi nincs az ágon**,
és nincs őket hordozó remote ág sem (176 head átnézve).

## 3. Az integráció mért ütközései (`main` ⟵ `ops/community-data-layer`)

Próba-merge eldobható worktree-ben: **2 textuális konfliktus**, 7 közösen
módosított fájl.

| Fájl | Mi ütközik | Feloldás |
|---|---|---|
| `lib/features/onboarding/screens/onboarding_screen.dart` | az ág a Stage-et a lecke ALÁ tolja (`router.go` mindkét ágon, majd `push(LearnScreen)`); a `main` (E17-R01, review BLOCKER-1/MAJOR-1 után) a Stage-et ELŐRE teszi, `onContinue → pushReplacement(Learn)`, `onSkip → pop()` | a `main` változata (review-zott, 4 teszt őrzi: `shell_entry_location_test`, `onboarding_first_win_test`, `first_win_production_engine_test`, `full_app_walkthrough_test`) |
| `HANDOFF.md` | két fejléc-szekció | mindkettő marad |
| `lib/l10n/app_{en,hu}.arb` + `base/` | auto-merge; a generált aggregátum egyezése a szegmensekkel **Python-emulációval ellenőrizve: egyezik** (en 3114 / hu 3093 kulcs, 0 duplikátum) | nincs teendő |
| `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` | auto-merge; a `main` A5-cellái a RÖGZÍTETT fixture-ből (72/1152/1163) mérnek, az ág 93 képernyőre bővítette az élő mátrixot | a fixture a jelentés bázisát rögzíti, nem az élő mátrixot → konzisztens; CI-n mérendő |
| `test/tooling/placeholder_wiring_test.dart` partíció | a `main` bejárja a `FirstWinStageScreen`-t; az ág 21 kizárási sort adott | a kizárási tábla NEM tartalmaz FirstWinStageScreen-sort (mérve) → nincs átfedés |

## 4. Kör-terv

A CI az egyetlen Dart-evidencia innen: minden kör a munka-ágra dispatchelt
`build-apk.yml` futással zárul (MCP `actions_run_trigger`), ADR 0052 §1.

| Kör | Tárgy | Zárás |
|---|---|---|
| **R1** | a #594 integrálása a mai `main`-nel a `claude/mit-audit-javitasok-v432t5` ágon (§3), CI zöld | `build-apk.yml` success |
| **R2** | practice-történet persistálása (valós metaadat-kódok a recorderben), jutalom-ledger bekötése, valódi eredmény-képernyő a `practiceResult` route-on | CI + őrteszt |
| **R3** | dal-tréner: file-backed resume-repository, sebesség-slider és play bekötése, setlist-session futtató (`SetlistItemRunner`) + `SetlistListScreenV2` | CI + reachability |
| **R4** | tutor: `PracticePlanDraft` előállító a chat-ből a preview-ra; a gateway-stub helyett őszinte állapot vagy valós helyi gateway; vision setup CTA | CI |
| **R5** | community-maradékok: bookmarks controller, klub-tagok fül, követő-sorok, klub-poszt `public_id`, `profilePosts` végpont | CI + backend CI |
| **R6** | zárás: `check_screen_reachability` → `Unreachable: 0` gépi cellaként, teljes-app bejárás, HANDOFF, queue (E17-R02…R14 státusz a VALÓS állapotra), PR a `main`-re a #594 helyett | CI + a felhasználó valós-gitár APK-tesztje |

**A végső mérce változatlan:** a valós-gitár APK-teszt a felhasználónál; a
szintetikus zöld nem „kész".

## 5. Eredmény — a körök mérve (2026-09-06, ág `claude/mit-audit-javitasok-v432t5`)

A körök tárgya a §4 tervhez képest a MÉRT hibákhoz igazodott: ami a §1.3
táblában szerepelt, azt zártuk, ami a tervben csak feltételezés volt (pl. a
tutor-gateway), azt a mérés után dokumentált hiányként hagytuk (§5.2).

| Kör | Commit | Mit zárt |
|---|---|---|
| **R1** | `b9f3da6` | a #594 (33 commit) merge a mai `main`-nel; 2 textuális + 3 szemantikus ütközés feloldva (§3 + a duplikált `e17_first_win_stage` mátrix-sor, a completion-report számai, a `first_win_stage_screen.dart` kizárási sor). CI `build-apk.yml` run 34034973105 **success**. |
| **R2** | `99c3837` | a befejezett V2 gyakorlás **látszik**: `PracticeSessionRecorderWithHooks` (történet-nézetek invalidálása, streak-jóváírás, XP a gamification-láncon), `aggregatedPracticeStatsProvider` a Today/Profile hubon, a jutalom-ledger a valódi `gamificationRewardLedgerRepositoryProvider` (a `_NoopRewardLedgerRepository` törölve). |
| **R3** | `3ba298a` | a Song Trainer **végigfut a felületről**: `SongTrainerLauncher` (dokumentum → kompiláció → controller-bemenet, `songMissing`/`staleConfig` hibakódok), a setup `onComplete` bekötve, a session route `autoStart`, a képernyő saját pause/resume/seek fallbackja és a `NavigateToSongTrainerResult` effekt-hallgató. |
| **R4** | `cee142b` | a tervező **Today képernyője valódi tervet mutat**, Skip/Shorten/Pause működik (`TodayPlanActions`), a Setup „Finish" tervet generál és aktivál (`launchPlanGeneration`), a Start a blokk gyakorlását nyitja; a vision „audio-only" CTA elhagyja a beállítást. |
| **R5** | `a24fff6` | a **Könyvjelzők** képernyő valódi listát tölt/lapoz/töröl (`RepositoryBookmarksController` a `GET /community/bookmarks` felett), a klub **Members fül és a tagkezelő** a szerver taglistáját mutatja (`GET /community/clubs/{id}/members`), a **követő-sorok** a valódi profilt kérik le (`fetchById` → `GET /community/profiles/{public_id}`). |
| **R6** | (ez a commit) | a `practiceResult` route **a most befejezett gyakorlás eredményét mutatja** (`PracticeResultTarget` kézfogás a navigációs sink és az after-record hook között; fallback csak, ha tényleg nincs mit mutatni). |
| format-javítások | `974d78e`, `c472b93`, `9ee46a8` | a CI format-kapu leletei (a formázó „magas" alakja); a CI az egyetlen Dart-evidencia ebben a konténerben. |

### 5.1 A §1.3 tábla sorai — állapot a HEAD-en

| §1.3 sor | Állapot | Hol |
|---|---|---|
| `main.dart` 6 override / 17 dobó provider | **zárva** (#594 WP-A, R1) | `lib/app/production_overrides.dart` |
| metaadat-kódok placeholderek → `NoopPracticeSessionRecorder` | **téves lelet**: a család-provider VALÓDI kódokat ad; a valódi rés a történet-nézetek frissítése + streak + XP volt → **zárva** (R2) | `practice_session_after_record.dart` |
| `_NoopRewardLedgerRepository` | **zárva** (R2) | `practice_result_providers.dart` |
| `practiceResult` route `PracticeResultFallback` | **zárva** (R6) | `practice_result_route.dart`, `practice_result_target.dart` |
| `_InMemorySongResumeRepository` | **nyitva** — a folytatási pont app-újraindításkor elvész; fájl-alapú tároló + kodek kell (`SongResumeCheckpoint`: songId/revision/range/attemptCounter/resumedFrom/recordedAt) | `song_trainer_providers.dart:432` |
| sebesség-`Slider` `onChanged: null`; `onPlay: () {}` | **részben**: a paused-ág play/pause/resume/seek a képernyő saját controller-hívásaira esik vissza (R3). A sebesség-slider **őszintén tiltott marad**: a controllernek nincs rate-művelete (`backingRateSupported` csak jelző). | `song_trainer_screen.dart:345` |
| tutor `LocalTutorModelGatewayStub` | **nyitva, szándékosan**: a felhő-transport (`RemoteTutorModelGateway` + `HttpTutorStreamTransport`) létezik, de az adatleltár MAJOR-3 lelete szerint az egyetlen produkciós `TutorTurnRequest`-építő (`_previewTurnRequest`) nem olvassa a `tutorConsentControllerProvider`-t; a transport bekötése ELŐBB a hozzájárulás bekötését kívánja (`test/privacy/consent_enforcement_test.dart` őrzi). | `data-inventory.yaml` `tutor_stream` |
| vision `vision-audio-only-continue` `() {}` | **zárva** (R4) | `vision_setup_screen.dart` |
| `_NoopBookmarksController` | **zárva** (R5) | `bookmarks_controller.dart` |
| „Attach media" snackbar | **nyitva** (R-SEC-01 / R-PRIV-01, fenyegetés-modell kör) | `post_composer_screen.dart` |
| tagok-fül tipp-szöveg; követő-sorok placeholder | **zárva** (R5) | `club_detail_screen.dart`, `followers_screen.dart` |

### 5.2 Tudottan nyitva (mérve, indokkal)

- **Setlist V2 lista + setlist-session** (`SetlistListScreenV2`, `setlist_session`): a képernyő nincs a design-rendszeren; az ADR 0471 D6 őr (elérhető-és-legacy képernyő E15-Rxx tulajdonos-kört kér) hamis tulajdonos-sort kívánna — ez saját kör.
- **Song resume persistálás** és **sebesség-slider** — fent.
- **Tutor felhő-gateway** — fent (hozzájárulás-bekötés az előfeltétel).
- **Klub-poszt írás kliensről** (belső `club_id`), **`profilePosts`** és a **kihívás GET-végpontok** (`known_gap` a szerződésben) — szerver-oldali felület hiányzik.
- **Hang-import folyamat**, a dal-tréner **ütemenkénti haladás-commit** és a `SongResultScreen` retry/next callbackjei.

### 5.3 Mérce

A körök CI-evidenciája a `build-apk.yml` futás a HEAD-en (a §4 szerint az
egyetlen Dart-evidencia innen). **A végső mérce változatlan:** a felhasználó
valós-gitár tesztje a `development` APK-n — a szintetikus zöld nem „kész".
