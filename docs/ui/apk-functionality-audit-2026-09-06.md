A sáv záró, teljesen zöld futása: `build-apk.yml` run
[34057751434](https://github.com/wolfcasaba/strumsight/actions/runs/34057751434)
az `a060a86` fejen — **format, analyze, architecture, secrets, l10n, asset,
teszt-suite és a véletlen-magos property-kapu mind ZÖLD**, a development APK
a run artefaktuma. (Ez a záró docs-commit közvetlenül utána következik, kódot
nem érint.) Az odáig vezető piros futások mért leletei, sorrendben: 5
formázó-iteráció (`dart format` tall-stílus), 1 analyze-lelet (hiányzó
import, csomag-belső `copyWithPrevious`, `Override` típus-argumentum), majd
a teszt-kapu 11 → 8 → 5 → 0: `practice_a11y_audit_test` A1.5 (setState-build
közben a valódi jutalom-ledgeren át), `practice_session_after_record_test`
A5 („ledger page cursor did not advance" a `ProfileProjector.rebuild`-ben),
`bookmarks_controller_test` B1 (aszinkron stream-kézbesítés), a négy
folyamat-teszt régi „mindig `PracticeResultFallback`" pinje (walkthrough,
placeholder-őr A4, release-flow semantics/text-scale), a
`practiceHistoryV2ListProvider` lusta flush-e a `PracticeResultRoute`
buildjében (`setState() called during build`), és az eredmény-fejléc
túlcsordulása 412 px-es nézeten en/2.0 + hu/1.5 + hu/2.0 szövegnagyításnál.

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

## 5. Eredmények — a javító körök mért állapota

Ág: `claude/mit-audit-javitasok-v432t5` (bázis: `main`, az audit commitja
`f154139`). Huszonnégy kör futott le rajta (az R9 három részletben: /1, /2, /3;
az R18 commitja a commit-sorrendben az R19 UTÁN landolt). A körök tárgya a §4 tervhez képest a MÉRT
hibákhoz igazodott: amit a §1.3 tábla sora állított, azt vagy bezártuk, vagy —
ahol a mérés mást mondott, mint a terv — a valódi rést zártuk, és a maradékot
itt, indokkal hagytuk nyitva (§5 „Nyitva maradt"). Dart-evidencia innen
kizárólag a CI: a remote konténerben nincs Flutter/Dart SDK.

| Kör | Commit | Mit zárt | Teszt |
|---|---|---|---|
| **R1** | `b9f3da6` | a `origin/ops/community-data-layer` (PR #594, 33 commit) merge-e az ágra. Feloldott ütközések: `onboarding_screen.dart` (a `main` változata maradt), `HANDOFF.md` (mindkét szekció), `e15_r13_full_variant_matrix_test.dart` (a duplikált `e17_first_win_stage` sor törölve), `chapter-15-completion-report.md` (a `main` dátumozott számai maradtak), `full-app-verification.md` (a `first_win_stage_screen` kizárási sor elhagyva). | `build-apk.yml` run 34034973105 **success** a merge-fejen |
| **R2** | `99c3837` (+ `974d78e`, `8c29fe6`) | a rögzített V2 gyakorlás után a hookok frissítik a történet-nézeteket (`practiceHistoryV2ListProvider` invalidálva), jóváírják a streaket (`streakProvider.recordPracticeToday`, ha jogosult) és kiosztják az XP-t a `GamificationPracticeAdapter` → `ActivityEventIngestor.drain` → `LocalRewardLedgerRepository` → `ProfileProjector` láncon; a `rewardLedgerRepositoryProvider` a valódi gamification-ledgert adja a `_NoopRewardLedgerRepository` helyett; az `aggregatedPracticeStatsProvider` táplálja a Profil- és a Today-hubot; a Library forrásai újraolvasnak a munkamenet után. Új fájl: `lib/features/practice/application/practice_session_after_record.dart`. | `test/features/practice/application/practice_session_after_record_test.dart` |
| **R3** | `3ba298a` | a Song Trainer **végigfut a felületről**: a `SongTrainerLauncher` (`lib/features/song_trainer/application/trainer/song_trainer_launcher.dart`) a setup `TrainerConfig`-jából `SongTrainerControllerInputs`-t készít; a router setup-route-ja `onComplete` kezelőt kapott (`song_trainer_launch.dart`), a session-route `autoStart: true`, saját pause/resume/seek fallbackkal, és a controller `NavigateToSongTrainerResult` effektjére navigál az eredmény-képernyőre; a hiba snackbarként látszik (`songTrainerLaunchFailed`). | `song_trainer_launcher_test.dart` A1–A4 |
| **R4** | `cee142b` (+ `c472b93`) | a tervező Today-képernyője a VALÓDI aktív tervet kapja (`activePracticePlanProvider`), a Start/Skip/Shorten/Pause gombjai működnek (`today_plan_actions.dart`: `TodayPlanActions` az `ActivePlanController` + `LocalPracticePlanRepository.activateAndReport` felett; a Start a gyakorlás-setupot nyitja `?id=<exerciseId>`-vel; a Swap **szándékosan tiltott marad**, mert a merge-elt controllernek nincs swap-művelete), a setup-varázsló „Finish"-e tervet generál és aktivál (`plan_generation_launch.dart` → `StartPlanGeneration` → Today), új `activePlanControllerProvider`; a vision setup „Continue audio-only" CTA-ja elhagyja a beállítást (pop vagy go Today). l10n: `planSetupGenerationFailed`, `todayPlanActionFailed`. | `today_plan_actions_test.dart` A1–A4 |
| **R5** | `a24fff6` (+ `9ee46a8`) | a **Könyvjelzők** képernyő valódi: `HttpCommunityPostRepository.listBookmarks` a `GET /community/bookmarks` felett (`limit` + `cursor` query), `CommunityBookmark` domain-entitás, `RepositoryBookmarksController` (`lib/features/community/application/controllers/bookmarks_controller.dart`: első oldal, kurzoros lapozás duplikátum nélkül, optimista és idempotens törlés visszaállítással hibára, a betöltési hiba stream-hibaként újrapróbáló kártyát ad — fiókréteg nélkül `ConfigurationFailure`, nem üres lista). **Klub-taglista**: `HttpCommunityClubRepository.members` a `GET /community/clubs/{public_id}/members` felett (`ClubMembership` entitás; az ismeretlen szerep eldobódik, nem kerekedik `member`-re), a `clubMemberListProvider` ezt olvassa (eddig mindig üres listát adott), a klub-részlet Members füle a szerepcímkés listát rendereli (eddig csak tipp-szöveg). **Követők**: `HttpCommunityProfileRepository.fetchById` a `GET /community/profiles/{public_id}` felett (eddig `UnsupportedError`; hiányzó `display_name` → handle, hiányzó láthatóság → `private`), a `followerProfileProvider` minden követő-sorhoz a valódi profilt oldja fel (placeholder-sor csak sikertelen lekérésnél marad, naplózva). A `docs/contracts/client-backend-endpoints.json` három bekötött GET-sorral bővült. | `bookmarks_controller_test` (B1–B6), `post_repository_bookmarks_test` (K1–K4), `club_repository_members_test` (M1–M3), `profile_repository_fetch_by_id_test` (P1–P3) |
| **R6** | `68ba51f`, `0451ff9` (+ követő javítások) | a `practiceResult` route nem épít többé mindig `PracticeResultFallback`-et („az eredmény nem érhető el"): a `PracticeResultTargetController` (`lib/features/practice/application/practice_result_target.dart`) a kézfogás a munkamenet navigációs sinkje (ami a tartós rögzítés BEFEJEZŐDÉSE ELŐTT tüzel) és az after-record hook között; a `PracticeResultRoute` (`lib/features/practice/presentation/practice_result_route.dart`) feloldja a megnevezett munkamenet történet-bejegyzését (töltés, amíg úton van; fallback csak ha a rögzítés elbukott vagy nincs mit mutatni; hideg deep link a legfrissebb bejegyzést mutatja). | `practice_result_target_test.dart` T1–T4, V1–V4 |
| **R7** | (ez a commit) | a `tool/release/live_backend_smoke.py` **fail-closed leállt** (exit 2, hálózati hívás nélkül) az R5 három új contract-sora miatt (`GET /community/bookmarks`, `GET /community/clubs/{public_id}/members`, `GET /community/profiles/{public_id}` — besorolatlan), és a `backend/tests/test_live_smoke_contract.py` számláló-tesztje is bukott (37 ≠ 34). A CI ezt NEM mérte: a `backend-ci.yml` csak `backend/**` változásra fut, a contract a `docs/contracts/` alatt van. Javítás: a három sor `not_exercised` besorolása indokkal, a teszt 37 / 24-re. | `test_live_smoke_contract.py` (10 passed helyben, venv), smoke-lánc 14/14 PASS a helyi backend ellen (§5.4) |
| **R8** | `acdf73c` (+ `61de4e3`, `22b904b`) | a Song Trainer öt mért rése: `KeyValueSongResumeRepository` a `KeyValueStore` felett (verziózott boríték, 20 legfrissebb checkpoint, sérült dokumentum = olvasási hiba, ami a KÖVETKEZŐ mentést nem blokkolja; a `_InMemorySongResumeRepository` törölve) — a pause (felhasználói és háttér-megszakítás) checkpointot ír, a `prepare()` visszaolvassa; `SongMeasureProgressCommitter`: a terminális ticknél ütemenként EGY `SongPracticeRecord` (idempotencia-kulcs, replay-biztos, az aktív idő a verdiktek száma szerint osztva), a `songProgressAggregateProvider` táplálja az eredmény-képernyő „Song progress" kártyáját; `SongTrainerResultRoute` + `SongTrainerResultArgs`: a Retry ugyanazt a dalt és konfigurációt indítja újra (`pushReplacement`), a Next a következő szakaszt — ha nincs, a dal áttekintőjére lép —, konfiguráció nélkül a CTA-k tiltva maradnak; `SongTrainerController.setPlaybackRate` + `canChangeBackingRate`: valódi sebességváltás **lejátszás-módban** (pause → rate → resume), pontozott munkamenetben tiltva, mert a Practice célütemterv egyszer, a beállítási tempón fordul le; hang-import: új `BackingAudioPickerAdapter` port (mp3/m4a/aac/wav/ogg/opus/flac) a meglévő `file_selector` felett (`songBackingAudioPickerProvider`) — a „Attach backing" CTA eddig a dal-fájl-pickert hívta (csak json/musicxml/midi), ezért hangfájl SOSEM volt kiválasztható. | `key_value_song_resume_repository_test` A1–A6, `song_measure_progress_committer_test` B1–B5, `song_trainer_playback_rate_test` C1–C5, `song_result_route_test` D1–D4, a controller-teszt bővítve |
| **R9** (/1, /2, /3) | `0f4e026`, `f98a601`, `4a0e1bf` | **/1 — a hozzájárulás a KÉRÉS-ÚTVONALON érvényesül (MAJOR-3 teljesítve):** a `_previewTurnRequest` nem drótozza be a `TutorConsent(modelUseGranted: true)` értéket, az új `buildTutorTurnRequest({message, consent})` a `tutorConsentControllerProvider` élő állapotát kapja (read, nem watch — a munkamenet közbeni visszavonás a KÖVETKEZŐ küldésnél hat, a beszélgetés nem vész el); hiányzó/visszavont model-use hozzájárulásnál típusos `ValidationFailure(tutor.consent.model_use_missing)`, kérés-objektum nem épül, gateway nem jön létre. Valódi `TutorPracticePlanProducer.propose` (max 4 blokk, egész perces, a célhosszra pontosan összegző felosztás, minden blokk valódi `ExerciseCandidate`-et nevez; üres katalógus / perc alatti hossz típusos hiba, sosem üres terv) és `compileActivePlan` → `AdaptivePracticePlan`, tartalom-alapú FNV-1a revision-id (a változatlan terv újra-elfogadása idempotens — a repó ismert silent-no-op csapdája ellen); a `PracticePlanPreviewRoute` mindkét elfogadó művelete a `LocalPracticePlanRepository.activateAndReport` úton ment. **/2 — a felhő-gateway BEKÖTVE** a hozzájárulás + fiókréteg + élő stream-kliens hármas kapuja mögött (`selectTutorModelGateway`, minden más eset `LocalTutorModelGatewayStub`; a factory minden próbánál újraolvas, így a visszavonás a KÖVETKEZŐ próbánál hat újraépítés nélkül); `DioFactory.createTutorStreamClient` ugyanazon a `_createDio` úton (auth-interceptor → bearer, korrelációs id, redaktált napló), `Accept: text/event-stream`, 60 s chunk-közi receive-timeout; `/tutor/plan-preview` route az `aiTutorEnabled` blokk alatt; `data-inventory.yaml` `tutor_stream` **wired: true** + új `tutor_stream_client` sor. **/3 — a tutor stream-kliens az auth seamjén:** `_authSessionClosures(ref)` egy helyen adja a readToken / readSessionGeneration / onUnauthorized hármast, az `accountApiClientProvider` és az új `accountStreamClientProvider` ugyanazt kapja (egy credential-holder, egy generáció, egy 401-invalidáció); a `tutorAccessTokenReaderProvider` és a core secure-kulcs olvasása törölve — a tutor feature sosem látja a tokent. | `tutor_turn_consent_test` (5), `consent_enforcement_test` (+2 cella, majd A3' 4 kiválasztási cella), `tutor_practice_plan_producer_test` (10), `practice_plan_preview_route_test` (5, majd +2), `tutor_gateway_selection_test` (9 + a hitelesített 401 az egész fiók-sessiont kijelentkezteti) |
| **R10** | `67b6052` (+ `4b68f05`) | a Today-terv **Swap gombja valódi csere**: az `ActivePlanController.swap` a mai első függő blokkot a generátor saját `PracticeCatalogSnapshot`-jából vett, azonos készség-célú alternatívára cseréli (mérhető sikerkritérium, tempó-támogatás, időkorlátok — minden elutasítás NEVESÍTETT ellenőrzés, nincs try/catch), determinisztikus rangsor, tartós írás a változatlan `TodayPlanActions` → `activateAndReport` úton; a „nincs alternatíva" külön `noAlternative` kimenet saját snackbarral (`todayPlanSwapNoAlternative`), a router `onSwap`-ot köt. **Setlist V2**: `/setlists/v2` és `/setlists/v2/session` route, a lista a valódi `setlistControllerProvider`-ből épül, a tétel érintése a session-képernyőt nyitja; `SetlistSessionCoordinator` + `setlistItemRunner` a meglévő `SongTrainerLauncher.prepare`-rel építi a bemenetet és `await context.push`-sal VÁRJA MEG a Song Trainer session végét — ettől halad tételenként; a nem előkészíthető tétel nevesített availability-vel `skipped`. A `4b68f05` a CI-leletet zárja (run 34104053120, Coverage): a két újonnan elérhető setlist-képernyő bekerült a variáns-mátrixba (A1: elérhető halmaz ⊆ mátrix ∪ kizárási lista), a kizárási lista változatlanul egyelemű, PNG-rögzítés nélkül (a mátrix túlcsordulást mér, nem pixelt). | `today_plan_actions_test` A5–A6, `setlist_session_launch_test` B1–B4, `e15_r13_full_variant_matrix_test` A1 (a `setlist_list_screen_v2.dart` és a `setlist_session_screen.dart` fixture-je) |
| **R11** | `a26b408` | **mért biztonsági rés zárva:** a `CreatePostRequest.club_id` (belső bigint) eddig ellenőrzés NÉLKÜL került a sorra — bármely hitelesített hívó bármely klubba posztolhatott az egész szám kitalálásával, és a klub tagjai klub-tartalomként olvasták; most `club_public_id` (a kliens által ismert azonosító), mindkét címzési forma tagság-ellenőrzött, soft-deleted klub elutasítva, eltérő pár → 400, minden elutasítás ugyanaz a 404, amit a klub-feed olvasás ad (`ClubPostNotAllowed`, `resolve_club_public_id`). Kliens: `HttpCommunityPostRepository.createClubPost`, a klub-azonosító a composer-állapoton → tartós piszkozaton → outbox-rekordon → kérésen át utazik; „New post" CTA a klub-részleten (csak tagnak, `communityWritesEnabled` mögött). Duplikált `/posts` alias NEM készült — a `GET /community/clubs/{public_id}/feed` már létezett és a Feed fül fogyasztotta. **`GET /community/profiles/{public_id}/posts`**: kurzoros (saját HMAC-verzió, közös `project_page` wire-alak), kapu tulajdonos → minden audience, blokk (bármely irány) / privát / followers-only nem-követőnek / ismeretlen profil → egységes 404, sorszűrők: explicit audience-allowlist, moderáció + soft-delete, `club_id IS NULL` (különben a tagsági kapu a szerző profilján át megkerülhető lenne); kliens: `profilePosts` valódi, „Your posts" szekció a community hub `_ReadyView`-jában. Contract +2 mounted sor, smoke-besorolás, számláló-teszt 39 / 26. **Média-feltöltés NEM indult** — mért rés-jelentés: nincs média HTTP-router, a threat-model §6.2 A6.2.1 (magic-byte), A6.2.4 (transcode) és A6.2.5 (valódi scanner) hiányzik, `image_picker` nincs a pubspecben; R-SEC-01 / R-PRIV-01 P1 blokkolók változatlanok. | `post_repository_club_post_test` N1–N4, `community_outbox_club_test` O1–O4, `post_composer_club_test` Q1–Q5, `feed_repository_impl_test` B11–B13; backend `test_club_post_create` C1–C8, `test_profile_posts_router` P1–P9 (helyben mérve: pytest 958 passed + 1 xfail, ruff tiszta, `classify_contract` 39 sor / 0 unclassified) |
| **R12** | `74e4515` | **képernyőn lévő belépési pont** mindkét eddig csak route-on élő felülethez, mindkettő NEM pixel-pinelt képernyőn: a legacy `setlist_list_screen.dart` görgető törzsének első sora egy `SsContentCard` (`setlist-open-v2`) → `/setlists/v2` (kártya, nem AppBar-akció, hogy a hu címke 2.0 szövegnagyításnál görgessen, ne szorítsa a címsort; a `setlist_flow_test` pinjei változatlanul zöldek), a `tutor_profile_screen.dart` egy `SsContentCard` (`tutorProfilePlanPreview`) → `/tutor/plan-preview`, csak `aiTutorEnabled` mellett (kártya, nem SsSection+SsButton, mert az R22-PF6 pin pontosan 3 SsSection + 1 SsButton-t számol; TutorHome/TutorChat érintetlen). **Community „nincs engedélyezve ezen a szerveren":** a `/health/ready` nem közli a community elérhetőségét, a használható jel a 404 TÖRZSE — a felcsatolt router `profile_missing` részletet ad, a le nem csatolt a FastAPI csupasz `Not Found`-ját; a `fetchMyProfile` eddig MINDEN 404-et `null`-ra képezett, így a community nélküli szerver pont úgy nézett ki, mint a profil nélküli felhasználó („Create profile", majd a POST általános hibája). Új feature-lokális `CommunityFailureCode.unavailable` (`community.unavailable` a `NetworkFailure` felett — a core taxonómia érintetlen), `CommunityGateStatus.unavailable`, a gate `_UnavailableView` (kártya + újrapróbálás); a goldenek fixture-ei sosem érik el az új állapotot, a pixel változatlan. l10n: kulcsok a szegmensekben, aggregátum bájtra azonos (en/hu IDENTICAL, paritás 2353/2353). | `setlist_v2_entry_test` V1–V3, `tutor_plan_preview_entry_test` T1–T3, `profile_repository_unavailable_test` U1–U3, `community_gate_unavailable_test` G1–G3 |
| **R13** | `42973ef` | a sebesség-slider **pontozott munkamenetben is valódi**: új `PracticeTargetRescaler` — a pivot az aktuális pozíció előtti/alatti ütemhatár (ugyanaz, ahova a `ResumePractice` visszalép), `map(t)=t` a pivot ELŐTT (a történet, azaz a már pontozott verdiktek befagyasztva) és `pivot+(t−pivot)·ratio` utána; a leképezés folytonos és szigorúan monoton, így az esemény-sorrend és a matcher bináris keresése él, `countIn+musical+ringOut == total` pontosan, az egymás utáni újraidőzítések komponálódnak. Motor-határ: új `RescheduleTempo` parancs CSAK `ready` és `paused` állapotból (futó próbálkozás alatt a reducer elutasít), NEM törli a célt (ellentétben a `ChangeTempoBeforeAttempt`-tel), az `effectiveTempo`/`timelineBase`/`activeBase`/`pausedAtTimeline` egy lépésben áll át, a lejátszófej nem ugrik, a státusz nem változik (egyelemű statusPath — property-kapu-biztos). A Song Trainer controller ezért előbb megállít: pause → újraidőzítés → hang-sebesség → resume EGY zárójelben, a motor szokásos együtemes visszaszámlálásával, már az új tempón. `PracticeEventMatcher.rescheduled`: a feloldott rekordok szó szerint megmaradnak, csak a feloldatlanok nyílnak újra. A slider-húzás `setPlaybackRate`-je single-flight, latest-wins sorral (az átlapolt zárójelek voltak az EGYETLEN út, ahol hang és cél más tempón végezhette volna), azonos érték no-op; a DSP/hangolási paraméterek nem változtak (`docs/rag/chunks/` érintetlen). | `practice_target_rescaler_test` S0–S4, `practice_event_matcher_rescheduled_test` M1–M4, `practice_session_tempo_rescale_test` T0–T5, reducer-mátrix +2 cella, `song_trainer_controller_test` E1–E5 (a „scored session refuses" cella helyett), `song_trainer_screen_test` (futó pontozott munkamenet élő `Slider.onChanged`-del) |
| **R14** | `3d2f0e3` | **backend + szerződés.** Contract-drift: a `GET /community/clubs/{public_id}/pinned` és `/feed` mounted sorok (mért kliens-hívóhelyekkel), smoke-besorolás, számláló **41 / 28** not_exercised. **Throttle a Caddy mögött** (a §5.4 mellékes lelete zárva): `Settings.trusted_proxy_ips` (`STRUMSIGHT_TRUSTED_PROXY_IPS`, JSON-lista) + `client_ip_for_throttle` — a socket-peer, KIVÉVE ha az megbízható, akkor az első `X-Forwarded-For` ugrás; a fejléc FELTÉTEL NÉLKÜL soha nem megbízható (hamisítható); a Dockerfile CMD ugyanabból az env-ből ad `--proxy-headers --forwarded-allow-ips`-t az uvicornnak (üres → az uvicorn saját 127.0.0.1 alapja, nincs új bizalom); a runbook §5.1 a hop mérését és a KÖTELEZŐ Caddy `header_up X-Forwarded-For {remote_host}`-ot írja le (a gyári `reverse_proxy` HOZZÁFŰZ, e nélkül egy hívó hamis első hopot tehetne elé). **Login-diagnosztika a 401 gyengítése nélkül:** egy INFO rekord `auth.login_failed reason=unknown_email` / `reason=bad_password`, `client=<kulcs>`, `email_hash=<sha256 első 12 hex>` és `auth.register_conflict` — a válasz bájtra azonos, e-mail a naplóba nem kerül. MÉRT csapda: az uvicorn alapból kezelő nélkül hagyja a root loggert (az INFO eldobódik) → `_configure_app_logging()` a main-ben, és az alembic `fileConfig(..., disable_existing_loggers=False)` (az alapértelmezett `True` a folyamat hátralevő részére letiltotta az `app.routers.auth` loggert — ez a `test_migrations.py:248` régi workaroundjának oka). Runbook §7.1: a `STRUMSIGHT_COMMUNITY_ENABLED=true` (+ writes/clubs/leaderboard) átbillentése az élő stacken, readiness + mount-próba (404 → 403), az APK viselkedése előtte/utána. Helyben mérve: pytest 976 passed + 1 xfailed, ruff tiszta; falszifikációs próbák — a feltétel nélküli XFF-bizalom 3 cellát, az alembic egysoros visszavonása 2 cellát tesz pirosra. | `test_trusted_proxy_throttle` (13), `test_auth_failure_logging` (9) |
| **R15** | `999f03c` (a commit a `3d2f0e3` ELŐTT landolt) | **két hazug UI-állapot zárva.** Login: a képernyő nem mutat ELAVULT hibát mód-váltás vagy mezőszerkesztés után — képernyő-helyi elvetés a **beküldés-számlálóhoz** kötve, nem hiba-identitáshoz (mérve: a fake-ek és a `const` failure-ök két próbálkozásra UGYANAZT a példányt adhatják vissza, amit egy identitás-jelölő némán elnyelne, így egy új bukás láthatatlan maradna); az `AuthController` érintetlen (őszinte `AsyncError`, nincs hamis `AsyncData(null)`), új bukás mindig látszik; 409-nél a `authEmailTakenHint` második sor („van már fiókod? jelentkezz be") — ez a §5.4 mért 409-ei mellé való felhasználói irány. Klub-feed: a `_ClubFeedTab` MINDKÉT `error:` ága `_ClubFeedErrorCard`-ot ad (`club-feed-error` / `club-feed-pinned-error`) újrapróbálással (`ref.invalidate(clubFeedProvider/clubPinnedProvider)`) — eddig a betöltési hiba „nincs poszt"-ként látszott; a meglévő `_ErrorView` törzse `_ErrorCardBody`-ba emelve, a tag-fül hibaállapota bájtra azonos widget-sorrend. Goldenek: a login-goldenek alapállapotot renderelnek (nincs új widget), az e13_r34 klub-fixture-ök sikeres üres eredményt adnak (csak a `data:` ág fut) — pixel változatlan. | `login_error_lifecycle_test` (5 cella), `club_detail_screen_test` (+2) |
| **R16** | `2dd4fc9` | **contract-lefedettség + a community-routerek throttle-kulcsa.** A `docs/contracts/client-backend-endpoints.json` **41 → 67** bejegyzés, mind `mounted`: az R14 jelentése ~24 hiányzó hívóhelyet BECSÜLT, a mérés 26-ot adott (clubs 9, posts/comments/reactions/bookmarks 11, notifications 5, feed 1). A mérés reprodukálható és a fájl leírásában rögzített: a `_client\.(getJson\|postJson\|putJson\|patchJson\|post\|delete)(<[^(]*>)?\(` regex a `lib/` felett 65 `ApiClient` hívóhelyet ad, plusz a három nyers Dio-hívás (`/tutor/stream`, `/tutor/capability`, `/diagnostics`) és a két auth-token POST — összevonva **67 KÜLÖNBÖZŐ method+path pár**. A korábbi 41 sorból 23 `source` sor-hivatkozása elcsúszott, mind újramérve az ág HEAD-jén; mind a 26 új bejegyzés jelen van a `create_app(...).openapi()["paths"]`-ban (minden opcionális felület bekapcsolva), kiszolgálatlan továbbra is CSAK a 3 `known_gap` challenge-olvasás. A `live_backend_smoke.py` 26 új `_NOT_EXERCISED` besorolást kapott, három indok-családdal: flag mögötti clubs-felület (`STRUMSIGHT_COMMUNITY_CLUBS_ENABLED`), egyetlen fiókos lánc által elő nem állítható id-t igénylő végpont, és tartós tartalmat író végpont törlő lépés nélkül; a számlálók a `test_live_smoke_contract.py`-ban rögzítve: **67 / 10 exercised / 54 not_exercised / 3 known_gap**. **Throttle a Caddy mögött (a §5.2 nyitott tétele zárva):** a `handles.py` (availability 30/min, handle-csere 5/h) és a `search.py` (keresés 60/min) `_client_key`-je a közös `client_ip_for_throttle(request, request.app.state.settings)`-re delegál — e keretek eddig a deploy MINDEN hívójára közösek voltak; a `client_ip.py` docstringje CALLERS szakaszt kapott, és elhagyta a már hamis „still key on the socket peer" állítást. **NOTE — a `handles.py` javítása ma nem érhető el élesben:** a router (`/community/handles/*`) NINCS felcsatolva a `build_community_router`-ben (ADR 0497 D6 fail-closed kizárás, `backend/app/community/__init__.py:96-110`), a végpontjai csak teszt-fixture-ökben élnek, és a kliens nem hívja őket — a javítás tehát helyes, de a `search.py`-val ellentétben egyelőre elérhetetlen felületen. **NOTE — elnevezés, nem hiba:** a `challenge_repository_impl.dart` a `/community/challenges/invites/{invite_public_id}/…` hívásoknál a meghívó-id paramétert `challengeId`-nek nevezi, de a képernyő a VALÓDI meghívó-id-t adja át (`community_challenges_screen.dart:196-198`), így ez csak névadási zavar. Helyben mérve: pytest 986 passed + 1 xfailed (976 volt), ruff check + format tiszta; falszifikáció: mindkét `_client_key` törzsének visszaállítása pontosan 4 cellát tesz pirosra. A `backend-ci` a push-ra fut, az eredménye még nem ismert. | `test_community_trusted_proxy_throttle` (10 cella), `test_live_smoke_contract` (számlálók 67 / 10 / 54 / 3) |
| **R17** | `8e454f6` | **kijutás minden képernyőről** (az újra-audit B5/B6/B7 + M7 tétele, §5.5). Login: a siker-ág a „fiók nélkül tovább" közös `_leaveScreen` helperét kapta (`maybePop`, különben `go(profileHome)`) — a Profil-hubról `go`-val nyitott login sikeres belépéskor `GoError: There is nothing to pop`-ot dobott, ez a felhasználó „nem működik a bejelentkezés" jelzésének legvalószínűbb KÓDBELI oka (§5.4); a Profil-hub Belépés/Eredmények/Közösség belépői `push`-olnak. Eredmény-képernyő: mindkét változat (eredmény + fallback) `BackButton` leadinget és teljes szélességű „Kész" CTA-t kap PONTOSAN akkor, ha van `GoRouter` ÉS nincs mit poppolni (a `/practice/result`-ra `go`-val érkezünk) — a router nélkül pumpált golden-keretek bájtra változatlanok. `tutor_home` → chat `push`, a tutor-chat vissza-nyila `maybePop`, különben `go(tutorHome)` (a csupasz `maybePop` néma no-op volt); a Profil-hub → community/gamification/login és a `today_hub` → vision belépők `push`-ra váltottak; a gyakorlás-munkamenet megszakítása `canPop ? pop : go(practiceHub)` (M7). | `login_success_navigation_test` (3), `practice_result_screen_test` R17 csoport (5), `profile_hub_test` paraméteres push-cellák (3), `tutor_chat` (2), `tutor_home` (1), `today_hub` (2), `practice_session` (1) |
| **R18** | `0207d5a` (a commit a `d0fc96c` UTÁN landolt) | **belépési pontok** (az újra-audit B1–B4, B8 + M5, M6 router-oldala, M10). A Gyakorlás-hub öt kategória-csipje eddig `?id=` NÉLKÜL ment a `/practice/setup`-ra → mind az öt a route-hiba ágára („Ez a gyakorlat nem elérhető"); most `push('/practice/catalog?category=<code>')`, új `PracticeCategory` (skill-tag alapú csoportosítás, `filter`/`matches`/`practiceCategoryFromCode`) + `practiceCategoryLabel`. A **Skálák** csipet MEGTARTOTTUK, és őszintén ÜRES szűrt listát nyit — az eltávolítása golden-pinelt pixeleket mozdítana. Új `practiceCatalog = '/practice/catalog'` **top-level route, az `adaptiveShellEnabled`-től függetlenül** regisztrálva, `PracticeHubScreen(category:)` opcionális szűrővel (null → bájtra a korábbi rajzolat) → **10/10 beépített definíció elérhető**. „További eszközök" szakasz a hub-lista VÉGÉN, a golden-nézetablakon kívül: Összes gyakorlat, Analyze, Learn; a Dalok fül AppBar-akciója a `/song-trainer` könyvtárra (`songTrainerV2Enabled` kapu). Vision: a beállítás `ready` lépése elsődleges „Kamera-munkamenet indítása" CTA-t kapott (`push` visionSession). M5: a készség-bizonyíték sorok a `libraryV2ItemsProvider`-ből feloldott `LibraryItem`-et adják `extra`-ként (feloldhatatlan id → snackbar; eddig némán a Könyvtár-listára estek). M6 router-oldal: a TodayPlan/WeeklyPlan/AnalysisHome építők `.when`-nel külön `_RouteLoadingScaffold` / `_RouteErrorScaffold` + újrapróbálás ágat kapnak (kulcsok: `today-plan-route-{loading,error}` stb.). M10: dedikált `navSongs`/`navProfile` kulcsok, a `TODO(E13-R16)` törölve. l10n: új `lib/l10n/features/shell_{en,hu}.arb` szegmens (9 kulcs; a hu metaadat az en-ből tükrözve, az aggregátumok a generátor Python-portjával újraépítve). `docs/release/full-app-verification.md`: 7 elavult Indok cella javítva, ÚJ §3.2 sor nincs (minden most bekötött képernyő már fixture-özött/bejárt). | `r18_entry_points_test`, `practice_category_test`, `song_trainer_entry_test`, `vision_setup_screen_test` (+2), `progress_composition_test` (+2), nav-címke cellák (`closure_suite`, `tab_state_restoration`, `library_test`, `widget_test`), `arb_parity_test` szegmens-lista |
| **R19** | `d0fc96c` | **igazmondó állapotok** (az újra-audit M3, M4). M3: a produkciós Dio `receiveDataWhenStatusError: false`-t használ, ezért a `_notFoundDetail` MINDEN 404-en `null` törzset látott, és `_isModuleMissing` mindenre „a modul hiányzik"-ot mondott — bekapcsolt community mellett egy profil nélküli felhasználó SOHA nem kapta volna meg a profil-létrehozást (az R12 javítása a mérésben megfordult volna). Fix: `ApiClient.getJson(readsErrorDetail: true)` kérésenkénti opt-in (megtartja a hiba-törzset, `ResponseType.plain`, így hibás JSON-törzs sosem dobja el a response-t és a státuszt; a 401 mérvadó marad; a globális alapérték változatlan), a `fetchMyProfile` opt-inel, `_decodeDetailBody`; a pin újraírva a VALÓDI `DioFactory`-kliensre (U1–U4b) — a régi teszt egy saját `Dio`-t mért, ami élesben nem létezik. M4: a `todayPlanRepositoryProvider` mostantól az `activePracticePlanProvider`-t figyeli → terv esetén `ActivePlanTodayPlanRepository` (a `TodayPlanController` napi feloldása, lokalizált következő blokk, valós számlálók), terv nélkül `unavailable`, olvasási HIBÁRA új `unreadable` állapot (NEM „nincs terv"); `hasPlan` explicit engedőlista; új ARB-kulcs nem kellett. **Nyitva:** az `unreadable`-nek még nincs saját vizuálja a `today_hub_screen.dart`-on (ugyanazt a hőst rajzolja, mint a „nincs terv") — az adatréteg viszont már nem mossa össze a kettőt. | `profile_repository_unavailable_test` U1–U4b (DioFactory-n át), `active_plan_today_plan_repository_test` T1–T5 |
| **R20** | `88ae617` | **community-l10n és két igazmondó állapot** (az újra-audit M8, M9 részben, M6 harmadik helye, és az M4-nél nyitva hagyott `unreadable` vizuál). **M8:** a `post_composer_screen.dart` 21 hardkódolt MAGYAR literálja `communityComposer*` ARB-kulcsokra került (a hibabanner egyetlen ICU-kulcs a hibakóddal), így az angol nyelvű felhasználó nem kap többé magyar szerkesztőt. **M9 (részben):** a Könyvjelzők és a Közösségi keresés minden CÍMKÉJE ARB-ból jön (`communityBookmark*`, `communityBookmarks*`, `communitySearch*`), a könyvjelző-SOR szövege viszont MARAD a szerver azonosítóinál (`Post <id>` az ISO-8601 mentési idő fölött, `bookmarks_screen.dart:235-236`): az emberi szöveg a pixel-pinelt E13-R33 könyvjelző-goldent mozdítaná, ami csak az x86 boxon rögzíthető újra (ADR 0471 D6) — ezért a §5.2-ben golden-újrarögzítő körként marad nyitva. **M6/3:** új `CommunityGateStatus.error` a `profile_controller`-ben — az időtúllépés és az 5xx többé NEM `profileMissing` (a kapu nem ajánl „Hozz létre profilt"-ot hálózati hibára), a `profileMissing` kizárólag SIKERES null-eredményre áll be; a `community_gate_screen` `_GateErrorView`-t rajzol (`community-gate-error`, `community-gate-error-retry`). **M4-maradék:** a Ma-fülön `_PlanUnreadableNotice` KIZÁRÓLAG az `unreadable` állapotra (`today-hub-plan-unreadable`, `…-retry`; a retry az `activePracticePlanProvider`-t invalidálja) — az `unavailable` út bájtra változatlanul rajzol, ezért az `e13_r17` / `e13_r36` / `e15_r01` / `e15_r13` Today-goldenek érintetlenek. MINOR: `'$todayMinutes min'` → `todayHubMinutesShort`. **l10n:** `community_{en,hu}.arb` +40 kulcs, ÚJ `today_{en,hu}.arb` szegmens (4 kulcs), az aggregátumok **2364 → 2408** kulcs (a `tool/gen_l10n_segments.dart` koordinátor-oldali Python-portjával regenerálva). **Golden-kezelés:** az `e13_r33_screens_golden_test.dart` a composer celláját `hu` lokálban pumpálja (`pinnedLocales` térkép; a PNG-k eleve a magyar literálokat rögzítették, a hu ARB-értékek bájtra azonosak velük), minden más cella `en` marad. **Folyamat-lelet:** a CI-javító `3ac36fa` commitba tévedésből besöpört az R20 félkész pillanatképe (lib-oldal + szegmens-ARB-ok regenerált aggregátumok NÉLKÜL), ezért a rá indított 551-es futás megszakítva — a konzisztenciát az R20 commitja állítja helyre. | `community_gate_error_test` E1–E5 (időtúllépés → hibakártya, 500 → hibakártya, null → profil-létrehozó CTA, `unavailable` → R12-kártya, retry visszaáll), `today_hub_test` `unreadable` csoport (+A1 cella), `composer_audience_test` és `community_search_test` ARB-lookupokra átírva (+ lokál-követő cella) |
| **R21** | `2a653bf` | **MINOR-söprés** (az újra-audit §5.5 MINOR-listájából MI5, MI6, MI8–MI10, plusz az M9 maradék literáljai). **MI5:** a poszt-szerkesztő „Média csatolása" stubja KIZÁRÓLAG `communityMediaEnabled` mellett épül fel — a zászló ezzel kapta meg az első fogyasztóját, és mivel minden szállított buildben KI van, a gomb a felhasználó elől REJTVE van; az `e13_r33` composer-golden a zászlót BEKAPCSOLVA pineli, ezért a PNG-k bájtra változatlanok. **MI6:** a community-kapu `loggedOut` ága `_LoggedOutView`-t rajzol a már meglévő, eddig fogyasztó NÉLKÜLI `communityGateLoggedOutCta` kulccsal és `context.push(AppRoutes.login)`-nal (R17-minta: a `push` megőrzi a stacket, a belépés utáni pop visszavisz a kapura); `accountEnabled` nélkül CTA sem jelenik meg. **MI8/MI9/MI10:** három elavult doc-komment javítva — a három hub „az `Ss*` widgetek az első képkockán összeomlanak" állítása (a téma a `strumsight_app.dart`-ban be van kötve), a `LaunchScreen` nulla `lib/`-hivatkozása és a `practiceSessionRecorderProvider` élő úton KÍVÜLI placeholder-ága. **l10n-maradék:** `reaction_bar.dart`, `community_media_player.dart`, `edit_profile_screen.dart` (community **+19** kulcs), `reward_summary_sheet.dart` (gamification **+2**) és `loop_controls.dart` (ÚJ `song_trainer_{en,hu}.arb` szegmens, 3 kulcs) — az aggregátumok **2408 → 2432**. **Nem tett, mérve:** MI1 (`StreakDetailScreen.onRecoveryPressed` üres törzs — valódi streak-visszaszerző viselkedés ÉS `app_router`-oldal kell), MI2 (`RewardInboxScreen.onItemSelected` üres törzs — NINCS célroute, amire a tétel vinne), MI3 (az `insight_card.dart`-ban nincs literál; a hiba az `onPressed: null`, amihez a perzisztált `RecommendedAnalysisAction` payload kell → feature), MI4 (az analízis-import snackbarja MÁR őszinte; az import működővé tétele feature), MI7 (a `setlist_list_screen_v2.dart`-ban nincs felhasználói literál; a nyitott rész az `Ss*`-migráció → golden-újrarögzítő kör). **CI-leletek (run 552, az R17–R20 fejen):** a `r18_entry_points_test` három cellája — a `_tapOnHub` `scrollUntilVisible`-je megáll, ha a cél a `ListView` cache-extentjében MÁR felépült, de a nézetablak ALATT van, ezért a koppintás mellétrafált (a helper azóta `ensureVisible`-lel viszi a nézetbe); format: `app_router.dart` snackbar-lánc célosztás, `bookmarks_screen.dart` dupla üres sor, `progress_composition_test.dart` kollekció-argumentum hug. | `community_gate_test` MI6-csoport (4 cella: van CTA, `/login`-on landol, `push` — a pop visszavisz —, `accountEnabled` nélkül nincs CTA), `composer_audience_test` MI5-csoport (2), `community_media_player_test` ARB-lookupokra átírva, `reduced_motion_test` `rewardSummaryEventXp`, `arb_parity_test` szegmens-lista |
| **R22** | `67e4ada` | **holt vezérlők bekötése** (az újra-audit §5.5 MINOR-listájából MI1, MI2, MI3 — három olyan vezérlő, amit a felhasználó lát és megnyom, és eddig SEMMI nem történt). **MI1:** a `StreakDetailScreen.onRecoveryPressed` üres törzse helyett `context.push(AppRoutes.practiceHub)` — a domain EGYETLEN helyreállítás-fogalma a `StreakEvaluationRequest.recoveryEligible`, azaz egy ALACSONYABB minősítési küszöb egy gyakorlásra (nem megvásárolható zseton, nem türelmi nap; a `lib/`-ben semmi nem állítja be), a CTA saját szövege pedig (`streakV2RecoveryCta`, „Start a recovery practice") pontosan ezt ígéri — a hubra vitel tehát a teljes őszinte viselkedés, állapotot nem mutál. **MI2:** a `RewardInboxScreen.onItemSelected` a MÁR MEGLÉVŐ `RewardSummarySheet`-et nyitja (alsó lap, NEM új route → nincs mátrix-fixture és nincs §3.2 sor): a koppintott, MÁR lokalizált tételből épített egyeseményes `CelebrationSummary`, `gamificationFeedbackFor(preferences)` + `reduceMotion`; az `onMarkSeen` a régi úton perzisztál. **MI3:** új `insight_action_route.dart` — a perzisztált DURVA `AnalysisRecommendedAction` leképezése regisztrált útvonalra (repeatSection/continuePractice → `/practice`, slowDown → `/metronome`, adjustInput → `/analysis/capture`, NEM `/calibrate`: az a késleltetés-varázsló, a két akciót kiadó szabály viszont magáról a felvett jelről szól); per-hotspot mélylink nem LEHETNE őszinte, mert a `document_stages.dart` a szabály gazdag payloadját eldobja. Az `OverviewInsightCard` hordozza az `action`-t, az `InsightCard` opcionális `onAction`-t kapott (bekötés NÉLKÜL marad a régi letiltott + tooltipes állapot), az overview és a metric-detail képernyő `context.push(insightActionRoute(action))`-t ad. ARB-kulcs nem kellett. `docs/ui/legacy-backlog.md` §6.3 **zárva**, §6.2 részben (a `recoveryEligible` MEGADÁSA nyitva). Golden: az `e13_r32` a streak- és a postaláda-képernyőt közvetlenül, saját callbackekkel pumpálja (router-only változás → pixel-semleges), az `e13_r27` overview-PNG-i a második `MetricCard` belsejében érnek véget (az insight-kártyák a hajtás alatt vannak), a metric-detail goldenben pedig nincs insight. | `r22_dead_control_wiring_test` (MI1: navigáció a hubra + forrás-őr; MI2: valódi, seedelt postaláda-soron koppintás → a ledger-eseménnyel megnyíló sheet + forrás-őr), `insight_card_action_test` (leképezés-teljesség, kezelő nélkül letiltott gomb, kezelővel az akciót továbbadó gomb, metric-detail navigáció), `analysis_overview_screen_test` MI3 cella |
| **R23** | `b27a186` | **az AI tutor VALÓDI, konfigurációval kapcsolható provider-kapuja** (az újra-audit M2 BACKEND-fele). Új `AnthropicProviderGateway` a `backend/app/tutor/provider_gateway.py`-ban, httpx-en (nincs új függőség): `POST {base}/messages`, `x-api-key` + `anthropic-version`, `stream: true`, `split_anthropic_messages` a system-kontextus kiemelésére, SSE-összefűzés (`content_block_delta` / `message_delta` / `message_stop`), `message_stop` NÉLKÜL **fail-closed** (nem ad csonka választ késznek). Osztályozott hibaleképezés: `ProviderConfigurationError` (401/403/404), `ProviderBusyError` (429/529/5xx), `ProviderInvalidRequestError` (400/413/422), `ProviderTimeoutError`, plusz transport / malformed / incomplete — mind `ProviderError`, ezért a router 502/504-e és a stream `provider_error` / `provider_timeout` szerződése VÁLTOZATLAN; a napló CSAK az osztályozást + a HTTP-státuszt kapja (soha kulcsot, promptot, választ, provider-törzset). Konfiguráció: egyetlen új mező, a `Settings.tutor_anthropic_base_url` (a `tutor_provider`, `tutor_model`, `tutor_api_key`, `tutor_allowed_providers`, `tutor_timeout_seconds` a meglévők); `main.py::_guard_tutor_provider` **boot-időben fail-closed** (ismeretlen provider, allowlist-hiba, dev-alapértelmezett vagy üres kulcs → `RuntimeError`, a meglévő `_guard_prod` mintájára) — a runbook kimondja az árát is: egy rossz átbillentés az EGÉSZ backendet leviszi, a visszaállás env-visszaírás + `docker compose up -d`; `_build_tutor_gateway` + `app.state.tutor_gateway` + lifespan `aclose()`. A `/tutor/capability` a VALÓDI `provider` + `model` mezőket adja (a kliens csak a státuszkódot olvassa → kompatibilis; a `streaming: false` korábbi megfigyelés, ADR 0142). **Az alapértelmezés marad a `fake`** — a valódi válaszokhoz üzemeltetői flip kell (runbook §7.2), és a flip ELŐTT a `docs/privacy/data-inventory.yaml` `tutor_stream` sorát ki kell egészíteni a harmadik fél feldolgozójával + a megőrzéssel (a runbook BLOKKOLÓKÉNT jelöli). Docs: `backend/README.md`, `backend/deploy/staging.env.example`, runbook **§7.2** „Az AI tutor provider bekapcsolása" + §7.2/4 naplóosztályozás-tábla | `backend/tests/tutor/test_anthropic_provider_gateway.py` (54 cella, `httpx.MockTransport`, hálózat nélkül), `test_tutor_provider_composition.py` (11); helyben pytest **1051 passed + 1 xfailed**, ruff tiszta |
| **R24** | `64b080a` | **az AI tutor felhő-kapujának KLIENS-fele** (az újra-audit M2 kliens-fele). A `selectTutorModelGateway` kötelező `cloudEnabled` és opcionális `capability` paramétert kapott, így **ÖT** fail-closed feltétel dönt: (1) hozzájárulás (`TutorConsent.modelUseGranted`), (2) a build `aiTutorCloudEnabled` zászlaja, (3) fiók-réteg, (4) hitelesített stream-kliens, (5) a szerver `/tutor/capability` válasza VALÓDI providert jelent — `fake` vagy `enabled:false` → helyi stub, mert egy konzerv-válasz felhő-válaszként bemutatva olyan hazugság, amit a tanuló nem tud leleplezni. A factory kísérletenként olvassa a zászlót is (`ref.read`), tehát a menet közben megérkező capability, a visszavont hozzájárulás és a kijelentkezés a KÖVETKEZŐ turnnál hat, a beszélgetés lebontása nélkül. Új `tutorCloudCapabilityProvider`: CSAK a zászló + a kliens megléte mellett szondáz (törzs nélküli, hitelesített GET — tanulói adat nincs benne), a `tutorTurnOrchestratorProvider` `ref.listen`-nel indítja a chat megnyitásakor, offline / 404 / értelmezhetetlen törzs esetén `null` = ISMERETLEN, ami a másik négy feltételt hagyja érvényben. Új értéktípus (`tutor_cloud_capability.dart`: `TutorCloudCapability`, `servesRealModel`, minden mező fail-closed értelmezéssel — a hiányzó `enabled`/`provider` a konzerv alapértelmezésre esik, nem valódi modellre) és `HttpTutorStreamTransport.capability()` (a `health()` státusz-szerződése VÁLTOZATLAN). **Zászló-döntés:** a development build `aiTutorCloudEnabled` értéke KI MARAD (`docs/release/ga-scope.md`: postponed; `capability-rollout.md`: KI; **ADR 0132** — a build-idejű kapcsoló nem helyettesíti a hozzájárulást; a `feature_flags_test` pineli, hogy dart-define sem kapcsolhatja be), tehát a szállított teszt-APK az üzemeltetői flipig NEM éri el a `/tutor/stream`-et, a hozzájárulást adó tanuló pedig a MÁR MEGLÉVŐ, őszinte `fallback` úton a helyi stubot kapja. **Privacy:** a `data-inventory.yaml` `tutor_stream` kapuja HÁROM → ÖT feltétel; a `tutor_turn_message` purpose-a a PONTOS drót-törzs (négy mező: `request_id`, `sequence`, `conversation_id`, `message` — a `message` maga a megrenderelt prompt, benne a redaktált pillanatkép 11 `TutorContextFieldKey` szekciója; nincs benne e-mail, fiók- vagy eszközazonosító és nincs hang); a megőrzés KÉT hopra bontva (amit a kód garantál vs. amit az üzemeltetőnek kell ellenőriznie); a tárolás NEVESÍTI a harmadik fél feldolgozóját — „Anthropic (Claude API)" — az üzemeltetői flip feltételével, a régió üzemeltető-függő. Ugyanez a `tester-consent.md` prózájában és a `data-safety.yaml` purpose-szövegében (a gépi keresztellenőrző blokk és a pinelt számlálók VÁLTOZATLANOK: 25). Golden: UI-fájl nem változott → a PNG-k bájtra azonosak. | `tutor_gateway_selection_test` (zászló-ki cella; `fake` / `enabled:false` capability → stub; valódi provider → felhő; ISMERETLEN capability → a másik négy feltétel dönt; értelmezhetetlen törzs → a konzerv alapértelmezés; a szállított dev build → stub és NINCS capability-kérés), `http_tutor_stream_transport_test` capability-csoport, `consent_enforcement_test` A3' |
| formázó/analyze-javítások | `974d78e`, `8c29fe6`, `c472b93`, `9ee46a8`, `d3d10be`, `98d4b74`, `e460cc3` | a CI format- és analyze-kapujának leletei (lásd a HANDOFF „Csapdák" listáját) — a CI az egyetlen formázó-orákulum ebben a konténerben. | — |
| formázó/analyze-javítások (sáv 3) | `61de4e3`, `22b904b` (+ a FeatureFlags-javítás a `4a0e1bf`-ben) | az R8/R11 CI-leletei: a stub-overview builder `=>`-törzse EGY sorba fér a nyíl utáni tördeléssel (a format-kapu az egyetlen fájlt jelölte, `61de4e3`); az `Override` típusargumentum a `misc.dart` import nélkül nem típus (két új teszt) és a felesleges `meta` import a `song_trainer_launch`-ban (`22b904b`); a `FeatureFlags(aiTutorEnabled:)` a három kötelező paraméter nélkül a `practice_plan_preview_route_test`-ben (run 34107003755, a `4a0e1bf`-en belül javítva). A CI itt is az egyetlen formázó- és analyze-orákulum. | — |

### 5.1 A §1.3 tábla sorai — állapot az ág HEAD-jén

| §1.3 sor | Állapot | Hol |
|---|---|---|
| `lib/main.dart` 6 override / 17 dobó provider | **zárva** — a #594 hozta, R1 integrálta | `lib/app/production_overrides.dart` |
| practice-munkamenet metaadat-kódok (`practice.mode.unknown`…) | **a merge-elt fában már valódiak voltak** (mérve); a tényleges rés a hiányzó hookok voltak → **zárva** (R2) | `practice_session_after_record.dart` |
| `_NoopRewardLedgerRepository` | **zárva** (R2) | `practice_result_providers.dart` |
| `practiceResult` route `PracticeResultFallback` | **zárva** (R6) | `practice_result_route.dart`, `practice_result_target.dart` |
| `_InMemorySongResumeRepository` | **zárva** (R8, `acdf73c`; `key_value_song_resume_repository_test` A1–A6) — `KeyValueSongResumeRepository` a `KeyValueStore` felett (verziózott boríték, 20 legfrissebb checkpoint, sérült dokumentum = olvasási hiba, ami a KÖVETKEZŐ mentést nem blokkolja); a pause (felhasználói és háttér-megszakítás) checkpointot ír, a `prepare()` visszaolvassa; az `_InMemorySongResumeRepository` törölve | `song_trainer_providers.dart` |
| sebesség-`Slider` `onChanged: null`; play/pause no-opok | **zárva**: a paused-állapot Play/Pause/Resume/Seek no-opjai (R3); a sebesség-slider lejátszás-módban (R8, `acdf73c`; `song_trainer_playback_rate_test` C1–C5) **és pontozott munkamenetben is** (R13, `42973ef`; `practice_target_rescaler_test` S0–S4, `practice_session_tempo_rescale_test` T0–T5, `song_trainer_controller_test` E1–E5, `song_trainer_screen_test`) — a motor `RescheduleTempo` művelete affin újraidőzítéssel az ütemhatár körül, a már pontozott verdiktek befagyasztva; futó próbálkozás alatt a reducer ELUTASÍT, a controller ezért pause → újraidőzítés → hang-sebesség → resume zárójelben alkalmazza | `song_trainer_screen.dart`, `practice_target_rescaler.dart` |
| tutor `LocalTutorModelGatewayStub` | **zárva** (R9/2–3, `f98a601` + `4a0e1bf`; `tutor_gateway_selection_test` 9 cella) — a MAJOR-3 feltétel az R9/1-gyel teljesült (a hozzájárulás a KÉRÉS-ÚTVONALON érvényesül, `consent_enforcement_test`), ezért a bekötés legitimmé vált: a felhő-gateway KIZÁRÓLAG model-use hozzájárulás ÉS engedélyezett fiókréteg ÉS élő stream-kliens mellett áll fel (`selectTutorModelGateway`), minden más eset `LocalTutorModelGatewayStub`; a factory minden próbánál újraolvas, így a visszavonás a KÖVETKEZŐ próbánál hat; `data-inventory.yaml` `tutor_stream` **wired: true** | `tutor_gateway_providers.dart`, `dio_factory.dart`, `data-inventory.yaml` |
| vision `vision-audio-only-continue` CTA | **zárva** (R4) | `vision_setup_screen.dart` |
| `_NoopBookmarksController`, üres stream | **zárva** (R5) | `bookmarks_controller.dart` |
| poszt-szerkesztő „Attach media" snackbar | **NYITVA** (R-SEC-01 / R-PRIV-01, változatlanul) — az R11 mért RÉS-JELENTÉST adott, nem kódot: nincs média HTTP-router, a threat-model §6.2 A6.2.1 / A6.2.4 / A6.2.5 hiányzik, `image_picker` nincs a pubspecben | `post_composer_screen.dart` |
| klub tagok-fül tipp-szöveg; követő-sorok placeholder | **zárva** (R5) | `club_detail_screen.dart`, `followers_screen.dart` |

**A §2 „amit a #594 is nyitva hagyott" listája és a korábbi §5.2-tételek —
állapot az R8–R11 után** (ugyanaz az oszlop-forma):

| Sor | Állapot | Hol |
|---|---|---|
| dal-tréner ütemenkénti haladás-commit | **zárva** (R8, `acdf73c`; `song_measure_progress_committer_test` B1–B5) — a terminális ticknél ütemenként EGY `SongPracticeRecord` (idempotencia-kulcs, replay-biztos, az aktív idő a verdiktek száma szerint osztva); a `songProgressAggregateProvider` táplálja az eredmény-képernyő „Song progress" kártyáját | `song_measure_progress_committer.dart` |
| `SongResultScreen` retry/next callbackjei | **zárva** (R8, `acdf73c`; `song_result_route_test` D1–D4) — `SongTrainerResultRoute` + `SongTrainerResultArgs`: a Retry ugyanazt a dalt és konfigurációt indítja újra (`pushReplacement`), a Next a következő szakaszt, ha nincs, a dal áttekintőjére lép; konfiguráció nélkül a CTA-k tiltva | `song_trainer_result_route.dart` |
| hang-import folyamat | **zárva** (R8, `acdf73c`) — új `BackingAudioPickerAdapter` port (mp3/m4a/aac/wav/ogg/opus/flac) a meglévő `file_selector` felett; a „Attach backing" CTA eddig a dal-fájl-pickert hívta (json/musicxml/midi), ezért hangfájl SOSEM volt kiválasztható. Dedikált cella a kör listáján NINCS — az adapter a port mögött, a controller-teszt bővítve | `song_trainer_providers.dart` (`songBackingAudioPickerProvider`) |
| tutor `PracticePlanPreviewScreen` előállítója | **zárva** (R9/1, `0f4e026`; `tutor_practice_plan_producer_test` 10, `practice_plan_preview_route_test` 5 + 2) — valódi `TutorPracticePlanProducer.propose` (max 4 blokk, egész perces, a célhosszra pontosan összegző felosztás, sosem üres terv) és `compileActivePlan` → `AdaptivePracticePlan`, tartalom-alapú FNV-1a revision-id (idempotens újra-elfogadás); a route `/tutor/plan-preview` néven él (R9/2). **A képernyőn lévő belépési pont is zárva** (R12, `74e4515`; `tutor_plan_preview_entry_test` T1–T3): `SsContentCard` (`tutorProfilePlanPreview`) a nem pixel-pinelt `tutor_profile_screen.dart`-on, csak `aiTutorEnabled` mellett | `tutor_practice_plan_producer.dart`, `practice_plan_preview_route.dart` |
| a Today-terv `onSwap`-ja | **zárva** (R10, `67b6052`; `today_plan_actions_test` A5–A6) — `ActivePlanController.swap`: a mai első függő blokk cseréje azonos készség-célú alternatívára a generátor `PracticeCatalogSnapshot`-jából (nevesített elutasítások, nincs try/catch), tartós írás az `activateAndReport` úton; a „nincs alternatíva" külön `noAlternative` kimenet saját snackbarral | `active_plan_controller.dart`, `today_plan_actions.dart` |
| Setlist V2 lista + setlist-session bekötés | **zárva** (R10, `67b6052` + `4b68f05`; `setlist_session_launch_test` B1–B4, `e15_r13_full_variant_matrix_test` A1) — `/setlists/v2` és `/setlists/v2/session` route, a lista a valódi `setlistControllerProvider`-ből épül, a `SetlistSessionCoordinator` + `setlistItemRunner` a `SongTrainerLauncher.prepare`-rel indít és `await context.push`-sal várja meg a session végét. A **belépési pont is zárva** (R12, `74e4515`; `setlist_v2_entry_test` V1–V3): `SsContentCard` (`setlist-open-v2`) a legacy, nem pixel-pinelt `setlist_list_screen.dart` görgető törzsének első soraként. **NYITVA marad:** a lista teljes SsCard/SsButton-migrációja (golden-újrarögzítés az x86 boxon) | `setlist_list_screen_v2.dart`, `setlist_session_screen.dart` |
| klub-poszt `club_id` + `profilePosts` végpont | **zárva** (R11, `a26b408`; `post_repository_club_post_test` N1–N4, `community_outbox_club_test` O1–O4, `post_composer_club_test` Q1–Q5, `feed_repository_impl_test` B11–B13; backend `test_club_post_create` C1–C8, `test_profile_posts_router` P1–P9) — `club_public_id` + tagság-ellenőrzés mindkét címzési formára (a korábbi ellenőrizetlen belső bigint MÉRT biztonsági rés volt), `GET /community/profiles/{public_id}/posts` kurzorosan és kapuval, kliens-oldalon „New post" CTA a klub-részleten és „Your posts" szekció | `post_repository.dart`, `posts.py`, `profile_posts_router` |
| community kapu a community NÉLKÜLI szerveren | **zárva** (R12, `74e4515`; `profile_repository_unavailable_test` U1–U3, `community_gate_unavailable_test` G1–G3) — a `/health/ready` nem közli a community elérhetőségét, a használható jel a 404 TÖRZSE: felcsatolt router → `profile_missing` részlet, le nem csatolt → csupasz FastAPI `Not Found`. A `fetchMyProfile` eddig MINDEN 404-et `null`-ra képezett, ezért a community nélküli szerver a profil nélküli felhasználóval volt azonos („Create profile" → a POST általános hibája); most `CommunityFailureCode.unavailable` + `CommunityGateStatus.unavailable` + `_UnavailableView` („nincs engedélyezve ezen a szerveren", újrapróbálással). A goldenek fixture-ei sosem érik el az új állapotot — pixel változatlan | `profile_repository.dart`, `community_gate` |
| community média-feltöltés | **NYITVA** — az R11 mért rés-jelentése (nincs média HTTP-router, A6.2.1 / A6.2.4 / A6.2.5 hiányzik, nincs `image_picker`); R-SEC-01 / R-PRIV-01 P1 blokkolók változatlanok | lásd a §1.3 „Attach media" sorát |

**A 2026-09-07-i újra-audit BLOCKER-jei (§5.5) — állapot az R17–R19 után**
(ugyanaz az oszlop-forma):

| Sor | Állapot | Hol |
|---|---|---|
| sikeres bejelentkezés a Profil-hubról → `GoError: There is nothing to pop` (B7) | **zárva** (R17, `8e454f6`; `login_success_navigation_test` 3 cella) — a siker-ág a közös `_leaveScreen` helpert használja (`maybePop`, különben `go(profileHome)`), és a Profil-hub `push`-sal nyitja a logint. A KLIENS-oldali ok ezzel zárva; a 401/409 DÖNTÉSE továbbra is szerver-napló kérdése (§5.4) | `login_screen.dart`, `profile_hub_screen.dart` |
| gyakorlás-eredmény zsákutca + `go`-val nyitott héjon kívüli képernyők (B5, B6, M7) | **zárva** (R17) — `BackButton` + „Kész" CTA az eredmény mindkét változatán (pontosan router-rel és nem-poppolható stacken), tutor-chat/community/gamification/vision belépők `push`-ra, a munkamenet-megszakítás `canPop ? pop : go(practiceHub)` | `practice_result_screen.dart`, `tutor_chat_screen.dart`, `today_hub_screen.dart`, `practice_session_screen.dart` |
| a Gyakorlás-hub kategória-csipjei + a 10 beépített gyakorlatból 9 elérhetetlen (B1, B2) | **zárva** (R18, `0207d5a`; `r18_entry_points_test`, `practice_category_test`) — a csipek a szűrt katalógusra `push`-olnak, a `/practice/catalog` top-level route az `adaptiveShellEnabled`-től függetlenül él, **10/10 definíció elérhető** | `practice_area_hub_screen.dart`, `app_router.dart`, `practice_hub_screen.dart` |
| Analyze / Learn / Song Trainer belépő nincs a héjban (B3, B4) | **zárva** (R18) — „További eszközök" szakasz a hub-lista végén (Összes gyakorlat, Analyze, Learn) és a Dalok fül AppBar-akciója a `/song-trainer` könyvtárra (`songTrainerV2Enabled` kapu) | `practice_area_hub_screen.dart`, `song_list_screen.dart` |
| a Vision munkamenet elérhetetlen (B8) | **zárva** (R18; `vision_setup_screen_test` +2) — a `ready` lépés elsődleges „Kamera-munkamenet indítása" CTA-t kapott. **A munkamenet TARTALMA nyitva marad** (M1: nincs felismerés, az eredmény eldobódik) | `vision_setup_screen.dart` |
| a Ma-fül soha nem látta az aktivált tervet (M4) | **zárva** (R19, `d0fc96c`; `active_plan_today_plan_repository_test` T1–T5) — a `todayPlanRepositoryProvider` az `activePracticePlanProvider`-t figyeli; az olvasási hiba önálló `unreadable` állapot. Az `unreadable` VIZUÁLJA nyitva (§5.2) | `today_providers.dart`, `active_plan_today_plan_repository.dart` |
| a community-404 élesben mindig „modul hiányzik" (M3) | **zárva** (R19; `profile_repository_unavailable_test` U1–U4b a valódi `DioFactory`-kliensen) — `getJson(readsErrorDetail: true)` kérésenkénti opt-in | `api_client.dart`, `profile_repository_impl.dart` |

### 5.2 Nyitva maradt (mérve, indokkal)

Az R8–R13 körök zárták a korábbi lista nagy részét (song-resume persistálás,
ütemenkénti haladás-commit, `SongResultScreen` retry/next, hang-import, a
Today-terv `onSwap`-ja, a Setlist V2 lista + session, a tutor felhő-gateway és
a terv-előnézet előállítója, a klub-poszt `club_id` és a `profilePosts`
végpont, a két képernyőn lévő belépési pont (R12) és a sebesség-slider
pontozott munkamenetben (R13)). Az R16 zárta az itt korábban felsorolt két
tételt is: a contract gépi lefedettségét (41 → 67 bejegyzés, mind `mounted`) és
a community-routerek saját `_client_key` helpereit (`search.py`, `handles.py` →
`client_ip_for_throttle`). Az R17–R20 az újra-audit (§5.5) mind a nyolc
BLOCKER-ét, tíz MAJOR-jából pedig hetet TELJESEN zárt (M3–M8, M10), az M9-et
részben (a címkék ARB-ban, a könyvjelző-sor szövege nyitva); az R21 a
MINOR-listából ötöt zárt (MI5, MI6, MI8–MI10), és az M9 maradék literáljait is
ARB-ba vitte — a mentett poszt SORÁNAK szövegén kívül. Az alábbi lista az
onnan megmaradó tételekkel bővült. Ami MÉRHETŐEN nyitva maradt, indokkal:

- **A Setlist V2 lista teljes SsCard/SsButton-migrációja** — az R10 a képernyő
  térközeit `SsSpacing` tokenekre vitte (a golden-pinelt renderelés
  pixel-semlegesen), a teljes design-rendszer-migráció golden-újrarögzítést
  kíván az x86 boxon (ADR 0471 D6 őr) — tulajdonos-kör. (A belépési pont az
  R12-vel megvan; ez már csak a lista vizuális migrációja.)
- **Community média-feltöltés** — az R11 mért RÉS-JELENTÉST adott, nem kódot:
  nincs média HTTP-router, a threat-model §6.2 A6.2.1 (magic-byte-ellenőrzés),
  A6.2.4 (transcode) és A6.2.5 (valódi scanner) hiányzik, az `image_picker`
  nincs a pubspecben. Az R-SEC-01 / R-PRIV-01 P1 blokkolók változatlanok, a
  poszt-szerkesztő „Attach media" CTA-ja őszintén snackbart ad.
- **A bejelentkezési hiba DÖNTÉSE** — a kódban programhiba nem mérhető (§5.4:
  a 401 hitelesítési ítélet, a 409 létező fiók). Az R14 óta a döntés MÉRHETŐ:
  az `auth.login_failed reason=unknown_email|bad_password …` INFO rekord
  szétválasztja a két forgatókönyvet (olvasás: runbook §5.2) — a szerveren
  össze kell gyűjteni. A korábban itt jelzett közös throttle-kulcs **zárva**
  (R14, `client_ip_for_throttle` + `STRUMSIGHT_TRUSTED_PROXY_IPS`, runbook §5.1).
- **Üzemeltetői művelet az élő deployon:** `STRUMSIGHT_COMMUNITY_ENABLED=false`
  — a `live_backend_smoke.py` lánc emiatt a community-lépéseknél megáll, és az
  R5/R11 community-funkciói az élő backenden nem gyakorolhatók. **Az app ezt az
  R12 óta KEGYESEN viseli** („nincs engedélyezve ezen a szerveren", nem hamis
  „Create profile"), de a funkciók bekapcsolása üzemeltetői döntés — a lépéssor
  (átbillentés, readiness + mount-próba 404 → 403, az APK viselkedése
  előtte/utána) az R14-ben leírva: runbook **§7.1**. Ugyanebbe az osztályba
  tartozik az AI Tanár provider-átbillentése is (runbook **§7.2**): az R23 óta a
  szerver a konfigurált, valódi gateway-t építi, de az alapértelmezés a `fake`,
  ezért a Coach VALÓDI válaszai üzemeltetői flipig váratnak.
- **`musicalPosition` a `PracticeSessionState`-en KÖZELÍTŐ újraidőzítés után** —
  a getter egyetlen `BeatTimeConverter(tempo: target.tempo)`-val számol az
  EGÉSZ idővonalon, az R13 újraidőzítése viszont szakaszonként affin (a pivot
  előtt 1:1, utána `ratio`). A `lib/`-ben NINCS fogyasztója (mérve: csak a
  definíció és a teszt hivatkozik rá), ezért a pontosítás nem sürgős — de
  amint egy felület kiírja az ütem/ütés pozíciót, a getternek a rescaler
  szakaszos leképezését kell használnia.
- **A Vision munkamenet nem végez felismerést** (újra-audit M1) — a
  `vision_session_controller.dart:41-44` doc-kommentje kimondja
  („It deliberately does not perform inference"), a `reportQuality` és a
  `reportRealtimeCue` `lib/`-ban hívó nélkül van, a
  `visionSessionResultListenerProvider` `(_) {}` — a kész munkamenet eredménye
  sehova nem íródik. Az R18 a BELÉPÉST nyitotta meg (B8), a TARTALOM nyitva: vagy
  a felismerés kerül be, vagy a Ma-fül kártyája mondja ki, hogy előnézet.
- **Az AI Tanár felhő-kapuja — az üzemeltetői flip és a provenance-jelvény**
  (újra-audit M2). **A backend-fél az R23-mal, a KLIENS-fél az R24-gyel ZÁRVA.**
  Backend: a `main.py::_build_tutor_gateway` a konfigurált adaptert állítja fel, a
  valódi `AnthropicProviderGateway` létezik (osztályozott hibaleképezés, kulcs- és
  törzs-szivárgás nélküli napló, boot-időben fail-closed `_guard_tutor_provider`),
  és a `/tutor/capability` a valódi providert jelenti — a „bekapcsolva is
  `FakeProviderGateway` épülne" állítás tehát MÁR NEM igaz. Kliens: a
  `selectTutorModelGateway` ÖT fail-closed feltételt olvas kísérletenként
  (hozzájárulás, a build `aiTutorCloudEnabled` zászlaja, fiók-réteg, hitelesített
  stream-kliens, és a `/tutor/capability` valódi providert jelentő válasza — a
  `fake` vagy a lekapcsolt tutor helyi stubot választ), tehát az
  „`aiTutorCloudEnabled`-nek nulla fogyasztója van" lelet is zárva; a
  zászló minden szállított buildben KI marad (ga-scope: postponed, ADR 0132 — a
  build-idejű kapcsoló nem helyettesíti a hozzájárulást). Nyitva maradt KETTŐ:
  **(a) üzemeltetői művelet** — az alapértelmezés `tutor_provider=fake` és
  `tutor_enabled=False`, tehát a Coach VALÓDI válaszaihoz az élő deployon kell
  átbillenteni (`STRUMSIGHT_TUTOR_PROVIDER=anthropic`,
  `STRUMSIGHT_TUTOR_MODEL=claude-sonnet-5` vagy `claude-opus-5`, a hozzá tartozó
  `STRUMSIGHT_TUTOR_ALLOWED_PROVIDERS` JSON, az API-kulcs, végül
  `STRUMSIGHT_TUTOR_ENABLED=true`) — a lépéssor runbook **§7.2**. Az
  adatleltár-blokkoló ITT MÁR NEM áll: az R24 óta a
  `docs/privacy/data-inventory.yaml` `tutor_stream` sora NEVESÍTI a harmadik fél
  feldolgozóját („Anthropic (Claude API)", az üzemeltetői flip feltételével), és
  a megőrzést két hopra bontja; ami az ÜZEMELTETŐN marad, az a provider saját
  megőrzési/tanítási politikájának és a feldolgozási RÉGIÓNAK az ellenőrzése és
  rögzítése — ezt a repó nem méri;
  **(b) a chat AppBar „Cloud" provenance-jelvénye** — a `tutorAiModeFor` a
  szállított buildben online állapotban, idle turnnél is felhőt mutat, holott a
  valódi választás (zászló KI) a helyi stub; a tényleges választás bekötése az
  `e13_r29` és az `e15_r13` tutor-celláit mozdítaná, ezért **golden-újrarögzítő
  kör** — ugyanabba az osztályba tartozik, mint a könyvjelző-SOR szövege (lentebb)
  és a Setlist V2 lista `Ss*`-migrációja (MI7).
  **Doc-adósság ugyanitt:** a `docs/privacy/consent-enforcement.md` §1 „What's NOT
  yet true" blokkja még azt állítja, hogy a tutor felhő-transzportnak nincs
  produkciós építési helye a `lib/**`-ban (`wired: false`) — ezt az R9/2 zárta, az
  adatleltár azóta `wired: true`; a szakasz átírása egy jövőbeli docs-kör dolga.
- **A könyvjelző-SOR szövege** (az újra-audit M9 maradéka) — az R20 a
  poszt-szerkesztőt (M8) és a Könyvjelzők / Közösségi keresés minden CÍMKÉJÉT
  ARB-ba vitte, de a mentett poszt sora továbbra is a
  szerver azonosítóit írja ki: `Post <id>` a nyers ISO-8601 mentési idő fölött
  (`bookmarks_screen.dart:235-236`). Az emberi szöveg (lokalizált „mentett
  poszt" címke + `DateFormat.yMMMd`) a pixel-pinelt E13-R33 könyvjelző-goldent
  mozdítaná, ami csak az x86 boxon rögzíthető újra (ADR 0471 D6 őr) — ez tehát
  **golden-újrarögzítő kör**, nem l10n-kör. A korábban itt jelzett kisebb
  hardkódolt literálok (`reaction_bar.dart`, `community_media_player.dart`,
  `edit_profile_screen.dart`, `loop_controls.dart`, `reward_summary_sheet.dart`)
  az **R21-gyel ZÁRVA** — a szegmens-ARB-ok +24 kulccsal, az aggregátumok
  2408 → 2432 —, tehát ebből a tételből CSAK a mentett poszt sorának szövege
  marad nyitva. A `communityWrites` a dev APK-ban BE van.
- **MINOR-lista (újra-audit §3) — az R21 ötöt, az R22 hármat zárt, kettő
  marad nyitva.**
  **Zárva (R21):** a „Média csatolása" stub a `communityMediaEnabled` mögé kötve
  (MI5 — a zászló megkapta az első fogyasztóját, a szállított buildekben a gomb
  rejtve; az `e13_r33` composer-golden a zászlót bekapcsolva pineli, ezért
  pixel-semleges); a community kapu `loggedOut` állapota `_LoggedOutView`-t kapott
  a meglévő `communityGateLoggedOutCta` kulccsal és `context.push(AppRoutes.login)`-nal
  (MI6 — `accountEnabled` nélkül CTA sem jelenik meg); és három ELAVULT
  doc-komment javítva: a hub-ok „az `Ss*` widgetek az első képkockán
  összeomlanak" állítása (MI8, a téma a `strumsight_app.dart:33-34`-ben be van
  kötve), a `LaunchScreen` nulla `lib/`-hivatkozása (MI9) és a
  `practiceSessionRecorderProvider` élő úton kívüli placeholder-ága (MI10 —
  emiatt a §5.1 „a metaadat-kódok már valódiak voltak" sora pontatlan volt: a
  placeholder-ág fizikailag ott van, csak nincs olvasója; a felhasználói hatás
  rendben, a pontosítás most a doc-kommentben áll).
  **Zárva (R22) — a három holt vezérlő:** a `StreakDetailScreen.onRecoveryPressed`
  a gyakorlás-hubra visz (MI1 — a domain egyetlen helyreállítás-fogalma a
  `StreakEvaluationRequest.recoveryEligible`, egy ALACSONYABB minősítési küszöb,
  nem megvásárolható zseton vagy türelmi nap, és a `lib/`-ben semmi nem állítja
  be; a CTA szövege — `streakV2RecoveryCta`, „Start a recovery practice" —
  pontosan a hubra vitelt ígéri, ezért ez a teljes őszinte viselkedés, állapotot
  nem mutál. **Ebből NYITVA marad:** a `recoveryEligible` MEGADÁSA, azaz egy
  repository-művelet, ami a következő munkamenetre tényleg jóváírja a kedvezőbb
  küszöböt — `docs/ui/legacy-backlog.md` §6.2); a
  `RewardInboxScreen.onItemSelected` a MÁR MEGLÉVŐ `RewardSummarySheet`-et nyitja
  (MI2 — alsó lap, nem új route; egyeseményes `CelebrationSummary` a koppintott,
  már lokalizált tételből, az `onMarkSeen` változatlanul perzisztál;
  legacy-backlog §6.3 ZÁRVA); és az Analysis V2 insight-kártyák CTA-ja aktív
  (MI3 — az új `insight_action_route.dart` a perzisztált DURVA
  `AnalysisRecommendedAction`-t képezi le regisztrált útvonalra:
  repeatSection/continuePractice → `/practice`, slowDown → `/metronome`,
  adjustInput → `/analysis/capture`; per-hotspot mélylink nem lehetne őszinte,
  mert a `document_stages.dart` eldobja a szabály gazdag payloadját; kezelő
  nélkül a kártya a régi letiltott + tooltipes állapotot tartja).
  **Nyitva, mért indokkal:** az Analysis kezdőlap „Import file" CTA-ja (MI4 — a
  snackbar MÁR őszinte, az import működővé tétele feature); a Setlist V2 lista
  design-rendszer-migrációja (MI7 — **átsorolva:** a
  `setlist_list_screen_v2.dart`-ban nincs felhasználói literál, a nyitott rész az
  `Ss*`-migráció, azaz golden-újrarögzítő kör; azonos a fenti első ponttal).

### 5.3 CI-bizonyíték

A sáv záró, teljesen zöld futása: `build-apk.yml` run
[34057751434](https://github.com/wolfcasaba/strumsight/actions/runs/34057751434)
az `a060a86` fejen — **format, analyze, architecture, secrets, l10n, asset,
teszt-suite és a véletlen-magos property-kapu mind ZÖLD**, a development APK
a run artefaktuma. (Ez a záró docs-commit közvetlenül utána következik, kódot
nem érint.) Az odáig vezető piros futások mért leletei, sorrendben: 5
formázó-iteráció (`dart format` tall-stílus), 1 analyze-lelet (hiányzó
import, csomag-belső `copyWithPrevious`, `Override` típus-argumentum), majd
a teszt-kapu 11 → 8 → 5 → 0: `practice_a11y_audit_test` A1.5 (setState-build
közben a valódi jutalom-ledgeren át), `practice_session_after_record_test`
A5 („ledger page cursor did not advance" a `ProfileProjector.rebuild`-ben),
`bookmarks_controller_test` B1 (aszinkron stream-kézbesítés), a négy
folyamat-teszt régi „mindig `PracticeResultFallback`" pinje (walkthrough,
placeholder-őr A4, release-flow semantics/text-scale), a
`practiceHistoryV2ListProvider` lusta flush-e a `PracticeResultRoute`
buildjében (`setState() called during build`), és az eredmény-fejléc
túlcsordulása 412 px-es nézeten en/2.0 + hu/1.5 + hu/2.0 szövegnagyításnál.

**Javító sáv 3 (2026-09-07) — az R8–R11 mért CI-leletei, sorrendben:**
1. **format:** egyetlen fájl — a stub-overview builder `=>`-törzse a nyíl utáni
   tördeléssel egy sorba fér (`61de4e3`); a CI format-kapuja az EGYETLEN
   formázó-orákulum ebben a konténerben.
2. **analyze:** az `Override` típusargumentum a `misc.dart` import nélkül nem
   típus — **két új tesztben**; felesleges `meta` import a
   `song_trainer_launch`-ban (`22b904b`); `FeatureFlags(aiTutorEnabled:)` a
   három kötelező paraméter nélkül a `practice_plan_preview_route_test`-ben
   (run 34107003755, a `4a0e1bf`-en belül javítva).
3. **teszt:** `e15_r13_full_variant_matrix_test` **A1** (run 34104053120,
   Coverage) — a `setlist_list_screen_v2.dart` és a `setlist_session_screen.dart`
   az R10 routolása után elérhető, de sem a `_screens` mátrixban, sem az
   `_exclusions` listán nem volt; mindkettő fixture-t kapott (`4b68f05`), a
   kizárási lista változatlanul egyelemű (L180: a lista csak zsugorodhat).
4. **teszt (a szakasz többi lelete):** `setlist_session` fejléc-túlcsordulás
   (2 cella, hu/2.0/landscape), mátrix A1 a terv-előnézet képernyőre,
   `beta_release_notes_test` A6 ×2 és `store_package_test` A2 ×2 (a `tutor_stream`
   mező adatvédelmi közzététele), végül még 1 formázó-lelet — összesen hét,
   időrendben a lenti CI-bizonyíték sorában.

**CI-bizonyíték (sáv 3):** `build-apk.yml` run [34135635783](https://github.com/wolfcasaba/strumsight/actions/runs/34135635783) a `d581ca7` fejen — format, analyze, architecture, secrets, l10n, asset, teljes teszt-suite, véletlen-magos property-kapu és Coverage mind ZÖLD, a development APK a run artefaktuma. Az odáig vezető sáv-3 leletek (időrendben): 1 formázó (arrow-törzs), analyze ×2 (`Override` típusargumentum, felesleges `meta` import), analyze ×1 (`FeatureFlags` kötelező paraméterei), majd a teszt-kapu 7 → 0: mátrix A1 (két setlist-képernyő), setlist_session túlcsordulás (2 cella, hu/2.0/landscape), mátrix A1 (terv-előnézet képernyő), `beta_release_notes_test` A6 ×2 és `store_package_test` A2 ×2 (a `tutor_stream` mező adatvédelmi közzététele), végül 1 formázó (behúzás-csökkenés utáni egysoros hívások). A bukó tesztek neve a naplóeszköz 5000 soros ablakán kívül esett; a futás különböző pontjain megszakított három futás ablakaiból lett kimérve. A szakasz kiadott artefaktuma: a `test-2026-09-07-d581ca7` release-tag.

**Javító sáv 3, második szakasz (R12–R13):** a képernyőn lévő belépési pontok, a community kegyes „nincs engedélyezve ezen a szerveren" állapota (`74e4515`) és a pontozott munkamenetbeli sebesség-slider (`42973ef`).

**CI-bizonyíték (R12–R13):** `build-apk.yml` run [34145358157](https://github.com/wolfcasaba/strumsight/actions/runs/34145358157) az `ebd68b7` fejen — kapuk, teljes suite, property-kapu, Coverage és APK mind ZÖLD. Az odáig vezető leletek: analyze ×2 (`prefer_initializing_formals` a matcher privát konstruktorában — pozicionális `this._…`, mert named paraméter nem lehet privát), majd 1 teszt (`song_trainer_screen_test` R13: a family-kulcs identitás-alapú, a felülíráshoz és a képernyőhöz ugyanaz a `SongTrainerControllerInputs` példány kell), a neve a napló-ablakon kívül esett — két megszakított futás (5,3 és 11 perc) ablakaiból mérve.

**CI-bizonyíték (R14–R16):** `build-apk.yml` run [34152080647](https://github.com/wolfcasaba/strumsight/actions/runs/34152080647) az `f30cf4c` fejen — kapuk, teljes suite, property-kapu, Coverage és APK mind ZÖLD; a `backend-ci.yml` run [34152146643](https://github.com/wolfcasaba/strumsight/actions/runs/34152146643) a `2dd4fc9` (R16) fejen ZÖLD. Az odáig vezető leletek (R15, mindkettő a `club_detail_screen_test`-ben): a klub-feed hibacellák a fül aszinkron providereit `pumpAndSettle`-lel várják be, a pinned-cella a valódi `clubPinnedProvider`-t hajtja dobó feed-repóval (`cff2f41`); majd az `autoDispose` feed-provider a fül újraépítésekor másodszor is lefut, ezért a dobás a teszt által engedélyezett újratöltésig áll fenn (`f30cf4c`). A szakasz kiadott artefaktuma: a `test-2026-09-07-f30cf4c` release-tag.

**CI-bizonyíték (R17–R24):** `build-apk.yml` run [34190326707](https://github.com/wolfcasaba/strumsight/actions/runs/34190326707) az `f59f9ef` fejen — format, analyze, architecture, secrets, l10n, asset, teljes suite (11 049 teszt), véletlen-magos property-kapu, Coverage és APK mind ZÖLD. Az odáig vezető leletek: run 550 (R17+R19: Dio `request<Object?>` → JSON-ra kényszerített `responseType`, rest-day fixture, abort-teszt pump-keret), run 552 (R18 hub-csempék `scrollUntilVisible` cache-extent csapdája, 3 format-lelet), run 553 (format: 80 karakter ≠ 82 bájt), run 554 (analyze: doc-komment `<uuid>`, használatlan import), run 558 (secret-scan: sentinel kulcs marker), és a runs 553/557 egyetlen, minden 5000 soros naplóablakon kívül eső bukása — `test/tooling/data_inventory_test.dart` MINOR-2: az `api_client.dart` Dio-hívóhelyeinek pinje 3 → 4 az R19 `request<String>` ága miatt — amit négy megszakított futás ablakaiból (1,7→14,6 perc) NEM, csak a teszt-lépés első 2,5 percét lefedő ötödik ablakból lehetett kimérni (a tooling-tesztek a suite legelején futnak). A `backend-ci.yml` az R23 (`b27a186`) fejen KÉTSZER megszakadt: először a következő push (branch-szintű concurrency, új futás path-szűrő miatt nem indult), másodszor a teszt-kapu 14 perc 56 másodpercnél — a backend-suite a job időkorlátját súrolja (§5.2 nyitott tétel). A szakasz kiadott artefaktuma: a `test-2026-09-08-f59f9ef` release-tag.

**Javító sáv 3, harmadik szakasz (R17–R21) — a `build-apk.yml` run 552 mért
leletei az R17–R20 fejen (a javításuk az R21 commitjában van):**
1. **teszt:** a `r18_entry_points_test` HÁROM cellája — a `_tapOnHub` helper
   `scrollUntilVisible`-je AKKOR is megáll, amikor a célwidget a `ListView`
   **cache-extentjében** MÁR felépült, de még a nézetablak ALATT van; a rá
   következő `tap` így mellétrafált. A helper azóta `ensureVisible`-lel viszi a
   találatot a nézetablakba, mielőtt koppint.
2. **format:** három fájl — `app_router.dart` (a snackbar-lánc célja külön
   sorba kerül, mert a lánc farka ≤ 80 oszlopba fér), `bookmarks_screen.dart`
   (dupla üres sor), `progress_composition_test.dart` (kollekció-argumentum
   hug). A CI itt is az EGYETLEN formázó-orákulum.
3. A futás **negyedik** bukása a napló-eszköz 5000 soros ablakán KÍVÜL esett, a
   neve tehát ismeretlen — a mérése a következő futásra marad.

### 5.4 Bejelentkezés — mért állapot (2026-09-07)

A felhasználó jelzése: „nem működik a bejelentkezés"; az élő docker-napló
(`casaba.app` → `127.0.0.1:8010`) egy `POST /auth/login 401`-et és két
`POST /auth/register 409`-et mutatott. A remote konténerből a `casaba.app`
a proxy policy-ja miatt NEM érhető el (CONNECT 403, mérve), a docker-napló
pedig az Oracle-boxon van — ezért a mérés itt a KÓDRA és az ARTEFAKTUMRA
szorítkozott:

| Mérés | Eredmény |
|---|---|
| a release-APK (`test-2026-09-06-2f1f76f`, sha256 `137b282c…`) `libapp.so`-ja mindhárom ABI-n | tartalmazza a `https://casaba.app/strumsight` konstanst; a `build-apk.yml` csak `STRUMSIGHT_ENV=development`-et ad, így `AppConfig.apiBaseUrlFor` ezt oldja fel (`test/app/app_config_test.dart`, `app_bootstrap_test.dart` pinneli) |
| a WP-G commit (`1eb751f`, élő URL alapból) | benne van a kiadott `2f1f76f`-ben; a `main`-en NINCS — a `main`-ről épített APK a `10.0.2.2:8000` loopbackre menne |
| backend ugyanerről a kódról helyben (SQLite, `lab`, community BE, port 8001) | `live_backend_smoke.py`: **14/14 PASS** (register → login → `/auth/me` → settings → community-profil → known_gap 404-ek) |
| reprodukált napló-ujjlenyomat | `register 201` → `register 409` → `register 409` (más jelszóval is 409) → `login 401` (rossz jelszó) → `login 401` (ismeretlen e-mail) → `login 200` → `/auth/me 200` → `/settings 200`; fejléc nélkül `/auth/me` **403**, rossz tokennel **401** |

**Következtetés:** a 401 a `/auth/login`-on a kódban KIZÁRÓLAG hitelesítési
ítélet (nincs ilyen e-mail, vagy nem egyezik a jelszó); a 409 azt jelenti, a
fiók már létezik a Postgres-ben. Programhiba a bejelentkezési láncban nem
mérhető. A döntéshez a docker-napló a 409-ek ELŐTTI időszakról kell: ha van
ugyanarról a kliensről egy `register 201` + `GET /auth/me`, a regisztráció
sikerült és a kliens nem mutatta sikerként; ha nincs, az e-mail egy korábbi
mérésből maradt ott, és a jelszó nem egyezik. A boxon futtatható mérés:
`python3 tool/release/live_backend_smoke.py --base-url http://127.0.0.1:8010`
(a community-lépéseknél a lánc megáll, mert az élő deployon
`STRUMSIGHT_COMMUNITY_ENABLED=false`).

**Mellékes lelet (nem a 401 oka):** a login/register throttle
(`backend/app/routers/auth.py`, 10/perc és 5/perc) `request.client.host`
szerint számol, és a Caddy mögötti konténer minden klienst a docker-bridge
címén lát — a keret így az ÖSSZES felhasználóra közös, és a 429 a képernyőn
„hálózati hiba" (`authErrorNetwork`). Több tesztelőnél ez bejelentkezési
hibának tűnhet. Javítási irány: uvicorn `--proxy-headers
--forwarded-allow-ips` a Caddy címére, vagy az `X-Forwarded-For` olvasása a
throttle kulcsához.

**R14 óta a döntés MÉRHETŐ a szerveren** (`3d2f0e3`): a backend minden bukott
bejelentkezésre egy INFO rekordot ír —
`auth.login_failed reason=unknown_email|bad_password client=<throttle-kulcs>
email_hash=<sha256 első 12 hex>` —, és a regisztrációs ütközésre
`auth.register_conflict`-ot; a HTTP-válasz bájtra azonos maradt, e-mail a
naplóba NEM kerül. Ezzel a fenti két forgatókönyv szétválasztható: a
`reason=unknown_email` azt jelenti, az e-mail nincs a Postgres-ben (tehát a
409-ek egy MÁSIK e-mailre vagy egy korábbi mérésből maradtak), a
`reason=bad_password` azt, hogy a fiók létezik és a jelszó nem egyezik. Az
olvasás menete: `docs/operations/backend-live-deploy.md` **§5.2**. (Ha az INFO
nem látszik, az a mért uvicorn-csapda: a root logger kezelő nélkül marad —
a `_configure_app_logging()` javítja.)

**A mellékes lelet (közös throttle-kulcs) zárva** — R14: a throttle
kulcsa `client_ip_for_throttle`, ami a socket-peert használja, KIVÉVE ha az
megbízható proxy (`STRUMSIGHT_TRUSTED_PROXY_IPS`), és akkor az első
`X-Forwarded-For` ugrást; így a Caddy mögött minden hívó SAJÁT keretet kap.
A fejléc feltétel nélkül soha nem megbízható. Az üzembe helyezés lépései (a
hop mérése és a kötelező Caddy `header_up X-Forwarded-For {remote_host}`, mert
a gyári `reverse_proxy` hozzáfűz): runbook **§5.1**. A community-routerek saját
`_client_key` helperei (`search.py`, `handles.py`) EGYELŐRE még a socket-peerre
kulcsolnak (mérve az ág HEAD-jén) — §5.2.

**KLIENS-oldali lelet (a 2026-09-07-i újra-audit, B7) — zárva (R17):** a
`profile_hub_screen.dart:175` `context.go(AppRoutes.login)`-nal nyitotta a
bejelentkezést (stack-csere), a `login_screen.dart:106-108` siker-listenere
viszont csupasz `context.pop()`-ot hívott — egyoldalas stacken ez go_router
`GoError: There is nothing to pop`. Ugyanezen fájl `_continueWithoutAccount`
ága (`:58-63`) MÁR helyesen kezelte az esetet (`maybePop` + `go` fallback), a
siker-ág nem; a Settings felőli belépő `push`-t használ, ezért ott a hiba nem
jelentkezett. Ez a felhasználó „nem működik a bejelentkezés" jelzésének
legvalószínűbb KÓDBELI oka — a fenti szerver-oldali mérés helyesen NEM talált
programhibát a hitelesítési láncban. Az R17 (`8e454f6`) a siker-ágat a közös
`_leaveScreen` helperre vitte (`maybePop`, különben `go(profileHome)`), és a
Profil-hub belépői `push`-olnak (`login_success_navigation_test`, 3 cella).
**A hitelesítési kérdés DÖNTÉSE ettől független és változatlan:** a 401/409
szétválasztásához a szerver-oldali `auth.login_failed reason=…` INFO rekordokat
kell összegyűjteni (runbook §5.2) — a kliens-javítás azt nem váltja ki.

### 5.5 Újra-audit a HEAD-en (2026-09-07)

Az R16 utáni fejen (`2dd4fc9`, kód-azonos a `91f191b` docs-commit alatt) teljes,
forrás-olvasásos újra-audit futott — tárgya a `build-apk.yml` által szállított
**`development`** APK; minden lelet `fájl:sor` hivatkozással (Dart SDK a
konténerben nincs, tehát futtatott Dart-mérés nem volt). A jelentés maga a session
scratchpadjában készült, ami **efemer** — a lényege ez a szakasz.

**Az egész értékelést uraló mért tény:** a szállított buildben
`AppBootstrap` → `FeatureFlags.forShippedBuild(development)` →
**`adaptiveShellEnabled == true`**, tehát a felhasználó az ÖT célpontos adaptív
héjat látja (Ma / Gyakorlás / Dalok / Coach / Profil,
`home_shell.dart:136-163`), és a legacy öt-fülű `HomeShell` fel sem épül. A héj
menüjében **nincs Analyze és nincs Learn célpont**, a `/analyze` és `/learn`
top-level route-okra pedig `lib/**`-ból egyetlen navigáció sem mutatott — a
`legacyRedirects` csak a régi URL-eket vezeti át. Ehhez jött a másik osztály: a
héjon BELÜLI képernyők `context.go`-val ugrottak a héjon KÍVÜLI top-level
route-okra, ami eldobja a stacket, így az érkező képernyőn nincs vissza-nyíl
(`canPop == false`) és nincs alsó sáv. A `previewAll` miatt bekapcsolt felületek
így részben elérhetetlenek, részben zsákutcák voltak. (A `previewAll` egyben
`aiTutorEnabled`, `visionEnabled` + 10 al-flag, `audioAnalysisV2Enabled` + 9,
`plannerAssistEnabled` — az `aiTutorCloudEnabled` szándékosan KI;
`accountEnabled`, `communityEnabled`+3 és a `nonProd` zászlók BE;
`apiBaseUrl = https://casaba.app/strumsight`.)

**BLOCKER — a felhasználót az app elhagyására kényszerítő vagy halott folyamatok:**

| Lelet | Mit mért | Sors |
|---|---|---|
| **B1** | a Gyakorlás-hub öt kategória-csipje `?id=` NÉLKÜL ment a `/practice/setup`-ra → mind az öt a `_RouteError`-re („Ez a gyakorlat nem elérhető") | **zárva** (R18) |
| **B2** | a 10 beépített gyakorlatból 9 elérhetetlen: a teljes katalógust listázó `PracticeHubScreen` csak `!adaptiveShellEnabled` mellett volt regisztrálva, a hub egyetlen definíciót kínált (`catalog.first`) | **zárva** (R18) |
| **B3** | az Analyze fül és vele az Audio Analysis V2 öt felvételi képernyője elérhetetlen (az `AnalyzeScreen` az EGYETLEN képernyős belépő a `/analysis/capture`-re) | **zárva** (R18) |
| **B4** | a Learn lecke-lista elérhetetlen, és vele a `/song-trainer/*` hét képernyője (a `LessonListScreen` az egyetlen képernyős belépő a Song Trainer könyvtárra) | **zárva** (R18) |
| **B5** | a gyakorlás eredmény-képernyője zsákutca MINDEN munkamenet végén: `router.go('/practice/result')` egyoldalas stacket hagy, az `AppBar`-on nincs `leading`, nincs „Kész" CTA, és a héj alsó sávja sincs | **zárva** (R17) |
| **B6** | `context.go(<top-level route>)` a héjból négy további helyen (tutor home → chat, Profil-hub → community és gamification, Ma-fül → vision) — az érkező képernyőn nincs kiút; a tutor-chat vissza-nyila csupasz `maybePop`, azaz néma no-op volt | **zárva** (R17) |
| **B7** | a Profil-hubról `go`-val nyitott login sikeres belépéskor `GoError: There is nothing to pop` (a listener csupasz `context.pop()`) — a „nem működik a bejelentkezés" jelzés legvalószínűbb KÓDBELI oka | **zárva** (R17, §5.4) |
| **B8** | a Vision munkamenet elérhetetlen: a beállítás `ready` lépésén nem volt indító CTA, a `visionSession` route egyetlen képernyős hívóhelye is a setupra ment | **zárva** (R18) |

**MAJOR — hibás vagy félrevezető viselkedés:**

| Lelet | Mit mért | Sors |
|---|---|---|
| **M1** | a Vision munkamenet szándékosan nem végez felismerést (`vision_session_controller.dart:41-44`), a `reportQuality`/`reportRealtimeCue` `lib/`-ban hívó nélkül, az eredmény-listener `(_) {}` — a Ma-fül kártyája mégis teljes funkcióként hirdeti | **NYITVA** (§5.2) |
| **M2** | az `aiTutorCloudEnabled`-nek nulla fogyasztója van (a `selectTutorModelGateway` nem olvassa); a szerveren `tutor_enabled=False`, tehát a `/tutor/*` nincs felcsatolva (404 → hiba-szalag minden üzenetre), és bekapcsolva is `FakeProviderGateway` épülne (`main.py:240`) | **backend zárva** (R23 — `AnthropicProviderGateway`, konfigurációból épülő composition root, fail-closed őr), **kliens zárva** (R24 — öt fail-closed feltétel, köztük az `aiTutorCloudEnabled` és a `/tutor/capability` válasza); **üzemeltetői flip + a „Cloud" provenance-jelvény (golden) NYITVA** (§5.2) |
| **M3** | a produkciós Dio `receiveDataWhenStatusError: false`-a miatt a `_notFoundDetail` MINDEN 404-et „modul hiányzik"-nak látott — bekapcsolt community mellett senki nem kapott volna profil-létrehozást; a régi pin egy saját `Dio`-t mért, ami élesben nem létezik | **zárva** (R19) |
| **M4** | a `todayPlanRepositoryProvider` felülírás nélküli `UnavailableTodayPlanRepository` volt → a Ma-fül (az app kezdőoldala) SOHA nem látta az aktivált tervet | **zárva** (R19); az `unreadable` állapot vizuálja is **zárva** (R20) |
| **M5** | a Készség-részlet „bizonyíték" sorai `extra` nélkül pusholtak, ezért a route redirectje mindig a Könyvtár-listára ejtette őket | **zárva** (R18) |
| **M6** | betöltési hiba „nincs adat"-ként három helyen: a TodayPlan/WeeklyPlan route-építők `.value`-ja, az AnalysisHome `recent.value ?? []`-je, és a `profile_controller` MINDEN nem-`unavailable` hibát `profileMissing`-re képező ága | **router-oldal zárva** (R18); a `profile_controller` sora **zárva** (R20) |
| **M7** | a gyakorlás-munkamenet megszakítása `Navigator.pop()`-ot hívott, holott a `/practice/session`-re `go`-val érkezünk (egyoldalas stack) | **zárva** (R17) |
| **M8** | a poszt-szerkesztő teljes felülete hardkódolt MAGYAR (`_ComposerLabels`) — angol nyelvű felhasználó magyar felületet kap | **zárva** (R20) |
| **M9** | a Könyvjelzők és a Közösségi keresés képernyő l10n-en kívül (hardkódolt angol), a mentett posztok nyers UUID + nyers ISO-időbélyeg, poszt-szöveg nélkül | **részben zárva** (R20: minden CÍMKE ARB-ban; R21: a maradék community-literálok is — reakciók, média-lejátszó, profil-szerkesztő); a könyvjelző-SOR szövege **NYITVA** (§5.2, golden-újrarögzítő kör) |
| **M10** | a héj Dalok célpontja `songLibraryTitle`, a Profil célpont `tutorProfileTitle` („Tutor profil") címkét viselt, miközben a route más képernyőt épít | **zárva** (R18) |

**MINOR (az újra-audit §3, MI1–MI10):** az **R21** ötöt zárt — MI5 (a „Média
csatolása" stub a `communityMediaEnabled` mögé kötve, a szállított buildekben
rejtve), MI6 (a `loggedOut` community-kapu belépés-CTA-ja a meglévő
`communityGateLoggedOutCta` kulccsal, `push`-sal), MI8–MI10 (három elavult
doc-komment: az `Ss*` „első képkocka" állítás, a `LaunchScreen`, a
recorder-placeholder ág) —, és ugyanez a kör vitte ARB-ba az M9 maradék
literáljait. Az **R22** további hármat zárt — MI1 (a helyreállítás-CTA a
gyakorlás-hubra visz; a domain egyetlen fogalma a `recoveryEligible` alacsonyabb
küszöb, aminek a MEGADÁSA marad nyitva), MI2 (a postaláda-sor a már meglévő
`RewardSummarySheet`-et nyitja, új képernyő nélkül) és MI3 (az insight-kártya
CTA-ja a perzisztált durva akcióhoz tartozó útvonalra navigál) —, így a maradék
KETTŐ, indoka a §5.2-ben: MI4 feature (a snackbar már őszinte, a működő import a
munka), MI7 pedig golden-újrarögzítő kör. **MI3 és MI7 ÁTSOROLVA volt:** egyik
sem l10n-lelet — a mért fájlokban (`insight_card.dart`,
`setlist_list_screen_v2.dart`) nincs hardkódolt felhasználói literál; az MI3 így,
bekötésként (nem fordításként) zárult.

**A §5.2 tételek újramérése (az újra-audit ítéletei):** a Setlist V2 lista
`SsCard`/`SsButton`-migrációja **MEGERŐSÍTVE nyitva** (2 `Ss*` találat a
fájlban); a community média-feltöltés **MEGERŐSÍTVE nyitva** (nincs média-router
a `backend/app/community/routers/`-ben, a `communityMediaEnabled`-nek nincs
fogyasztója); a `musicalPosition` **MEGERŐSÍTVE nyitva, nem sürgős** (továbbra
sincs `lib/` fogyasztója); a bejelentkezési hiba DÖNTÉSE innen **nem cáfolható**
(szerver-napló kell) — de kliens-oldalon ott volt B7; a
`STRUMSIGHT_COMMUNITY_ENABLED=false` **MEGERŐSÍTVE**, azzal a lelettel, hogy a
„kegyes viselés" élesben MÁS okból működött (M3), és a community bekapcsolásakor
megfordult volna. **CÁFOLVA (lezárva):** a contract gépi lefedettsége (67 sor,
minden mért kliens-hívóhely szerepel) és a `search.py` / `handles.py` saját
`_client_key`-je (mindkettő a közös `client_ip_for_throttle`-re delegál).

**Amit az újra-audit RENDBEN talált** (a teljes lista a §5-ös körökön kívüli
területeken): ARB-integritás (`app_en.arb`/`app_hu.arb` 2355/2355 kulcs, a
`lib/**` 2060 `l10n.<kulcs>` hivatkozásából 0 hiányzik), tároló-perzisztencia
(nincs in-memory repó az éles ágon), a kompozíciós gyökér, a
beállítás-szinkron kérés-alakja és `_syncedSignature`-fegyelme, az
auth-szerződés, mind a 67 community szerződés-alak, a klub-poszt tagság-ellenőrzés,
a gyakorlás-motor teljes lánca valós metaadat-kódokkal, a session-képernyők
erőforrás-kezelése (mikrofon/wakelock elenged fülváltáskor) és a három gyors
eszköz. A repó ismert „néma no-op" csapdája a backend-/tároló-írásokon **nincs
jelen** — az üres `catch (_) {}` blokkok mind audio-`dispose`/haptika körül vannak.

**Strukturális ok, amiért a CI nem fogta meg a zsákutcákat:** a
`test/e2e/full_app_walkthrough_test.dart:281,296` a gyakorlás-eredmény után
`session.router.go(...)`-val ugrik tovább, nem UI-koppintással — B5 és a
B6-osztály így nem bukhatott el.

**Nem mért maradék-kockázat (nincs Dart SDK a konténerben):** a `GoRouter.maybeOf`
API-alakja a go_router 17.3-on (az R17 használja), és egy `StatefulShellBranch`
route `context.push`-olása (Analyze/Learn) — utóbbira az `app_router`-ben van
precedens. Mindkettőt a CI méri.

**A végső mérce változatlan:** a valós-gitár APK-teszt a felhasználónál; a
szintetikus zöld nem „kész".
