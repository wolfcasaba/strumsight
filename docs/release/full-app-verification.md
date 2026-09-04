# Full-app verification — measured result (E16-R05)

**Kör:** `E16-R05` (Chapter 16, Kör 5 — a sáv ZÁRÓ köre). **Mérve:** 2026-09-04,
`sonnet-impl/e16-r05-full-app-verification-and-release`.

Ez a dokumentum a kör MÉRT eredményét rögzíti: (1) a placeholder-mérő
(`tool/check_placeholder_wiring.dart`) kimenete, (2) a bejárás
(`test/e2e/full_app_walkthrough_test.dart`) által talált, **NEM javított**
leletek (§5.2 — a `lib/**` ennek a körnek tiltott zónája), és (3) a mért
elérhető képernyő-halmaz (73) diszjunkt, teljes partíciója a bejárt (9) és a
kimaradó (64) képernyők között, gazdával és körrel.

## 1. Placeholder-mérő — mért eredmény

```
$ dart run tool/check_placeholder_wiring.dart --format table
# Placeholder wiring (measured)

H1 (routing) files: 4. H2 (composition provider) files: 14. Findings: 0.
Suppressed by exception: 1. Vacuous exceptions: 0. Exit code: 0.

| Rule | Location | Declaration | Detail |
| --- | --- | --- | --- |

## Suppressed by a real exception-list entry

| Rule | Location | Declaration | Reason |
| --- | --- | --- | --- |
| P3 | `lib/features/progress_v2/application/progress_providers.dart:34` | `progressV2IsOffline` | Progress V2 is 100% local (own doc-comment, §5.7) … |
```

**A1:** 0 lelet, kilépési kód `0`. **A7:** a kivétel-lista pontosan egy,
nem üres indokú bejegyzést tartalmaz (`progressV2IsOffline`) — nem vákuum.
**A8:** H1 = 4 ≥ 4, H2 = 14 ≥ 14, egyik fájlhalmaz sem üres.

A §6.1 KÖTELEZŐ valódi-sértés próba mindkét lépésének szó szerinti kimenete
a `docs/rounds/e16-r05-full-app-verification-and-release.md` §10
szakaszában van dokumentálva.

## 2. A bejárás mért leletei — E16-R06 UTÁN (A3 mérhetően pozitívra fordítva)

A `test/e2e/full_app_walkthrough_test.dart` a szállított
`FeatureFlags.forEnvironment(AppEnvironment.development, accountEnabled:
false)` BE-készlettel bejárja: indítás → Today → gyakorlás (Practice Area
Hub → Setup → Session) → eredmény → Library → Progress → Profile →
Settings. Minden állomás valós adatot vagy explicit állapotot állít — a
teszt zöld. **`E16-R06` (ADR 0508) feloldotta az alább dokumentált L1 és L2
leletet, és eltávolította a bejárás mindhárom teszt-oldali `router.go`
sorát a gerincen** (onboarding → Today → Practice Area Hub → Setup →
Session): a Skip/finish és a first-win ág egyaránt `entryLocationFor(...)`-ra
navigál (`onboarding_screen.dart`, a router SAJÁT belépési logikájával azonos
forrásból), és a Practice Area Hub ajánlott CTA-ja
`?id=<katalógus első elemének id-je>` URI-t nyit
(`practice_area_hub_screen.dart`) — ugyanabban az alakban, mint a legacy Hub
`_openSetup`-ja. `grep -n "session.router.go\|router.go(" test/e2e/full_app_walkthrough_test.dart`
a gerincen (onboarding → Today → Practice Area Hub → Setup → Session) mérve
**0 találatot** ad; a fennmaradó három találat (Library/Progress/Profile
állomás-váltás) a gerincen kívül él és az L3/L4/L5 lelethez tartozik,
változatlan. Emiatt: **A3 — TELJESÜL.** A „BE" besorolású capabilityk core
útjai a termék SAJÁT navigációjával, teszt-oldali híd nélkül, mérhetően
végigjárhatók — az állomások, oda navigálva, valós adatot vagy explicit
állapotot mutatnak (A2 ✅), a mért elérhető halmaz partíciója teljes
(A4 ✅), és a gerinc navigációja megszakítás nélküli (A3 ✅, mérve:
`E16-R06`).

Az öt eredetileg dokumentált lelet közül az **L1** és **L2** ezzel a körrel
feloldva (lásd alant, a saját szakaszuk megmaradt, kiegészítve a feloldás
körével). Az **L3**, **L4** és **L5** továbbra is nyitott, `E16-R06` egyiket
sem érinti (§3 a kör allowed-files listáján kívül esnek). Közülük az **L3**
más jellegű, mint a másik kettő: nem a SZÁLLÍTOTT kompozícióról mér semmit,
hanem a mérés a harness saját határán akad el (l. L3 alatt) — a
Library-állomás ezen a bejáráson ezért **nem** bizonyítja sem azt, hogy a
szállított kompozíció hibás, sem azt, hogy jó.

### L1 — a Practice Area Hub „ajánlott gyakorlás" CTA-ja nem ad át `id`-t

`PracticeAreaHubScreen`'s recommended CTA (`practice_area_hub_screen.dart:55`)
`context.go(AppRoutes.practiceSetup)`-ot hív, **`?id=` paraméter nélkül** —
ellentétben a legacy Hub `_openSetup`-jával (`practice_hub_screen.dart:370-375`),
ami mindig felépíti az URI-t `id: definition.id`-vel.
`PracticeSetupScreen._readArgs` ezért `PracticeSetupRequest.missing`-et
kap, és a képernyő a saját `_RouteError` ágát rendereli — egy valós,
lokalizált, EXPLICIT hibaállapot (nem placeholder-literál, §5.1 nem sérül),
de az adaptív shell EGYETLEN hirdetett belépési pontja egy pontozott
gyakorlásba méréssel zsákutca.

- **Gazda:** Practice Area Hub (UI-06, SDD Ch13).
- **Kör:** `E16-R06` — feloldva. `PracticeAreaHubScreen` `ConsumerWidget`-té
  vált, a `practiceCatalogProvider`-t a `lib/features/practice/public.dart`
  barrelen át olvassa, és a CTA `Uri(path: AppRoutes.practiceSetup,
  queryParameters: {'id': catalog.first.id})`-t nyit — üres katalógusnál a
  kártya nem renderelődik (ADR 0508 D3/D4).

### L2 — az onboarding mindig `/live`-ra fejez be, nem `/today`-ra

`OnboardingScreen._completeFinish` (`onboarding_screen.dart`) mindig
`router.go(AppRoutes.live)`-ot hív a Skip/finish után, függetlenül
`adaptiveShellEnabled`-től — ez a `legacyRedirects` tábla szerint
`/practice/live`-ra (egy Stage útvonalra, elsődleges navigáció nélkül)
fejeződik be, SOHA nem `/today`-ra, pedig a router saját
`initialLocation`-logikája (`app_router.dart`) `/today`-t választaná első
belépéskor, ha a shell BE van kapcsolva.

- **Gazda:** Onboarding feature.
- **Kör:** `E16-R06` — feloldva. `entryLocationFor(bool
  adaptiveShellEnabled)` (`lib/app/routing/adaptive_shell_routes.dart`) az
  EGYETLEN forrás; `_completeFinish` és `_completeFirstWin` egyaránt ezt
  hívja, ugyanabból a flag-forrásból (`ref.read(appConfigProvider).flags
  .adaptiveShellEnabled`), amit a router is olvas (ADR 0508 D1/D2).

### L3 — az Unified Library forrásai olyan repository-kra épülnek, amiket csak a production bootstrap köt be

`libraryV2SourcesProvider` (`library_v2_providers.dart`) feltétel nélkül
olvassa az `analysisRepositoryProvider`/`songRepositoryProvider`/
`setlistRepositoryProvider`-t — mindhárom alap-deklarációja (
`analysis_providers.dart` és megfelelői) szándékosan `throw StateError`-t
dob, amíg a PRODUCTION bootstrap (`main.dart`) be nem köti a boot-változatból.
`bootE2eApp` (E12-R11, ADR 0472) a `ProviderContainer`-t közvetlenül építi,
sosem futtatja ezt a bootstrapot, és nem is override-olja ezt a hármat.
`LibraryV2Controller.build()` ezért MINDEN forrásra elbukik, és
`UnifiedLibraryScreen` a saját, valós, lokalizált `libraryV2LoadFailed`
hibaállapotát rendereli (§5.1 „explicit állapot" ága) a perzisztált
gyakorlás-session helyett.

- **Gazda:** Library V2 feature / E12-R11 harness.
- **Kör:** nincs — a harness-nek vagy a Library kompozíciós rétegének kell
  ezt bekötnie egy jövőbeli körben; a lelet itt van rögzítve.

### L4 — a Profile Hub „sessions" mércéje a V1 „Learn" naplót olvassa, nem a Practice Engine V2 előzményt

`ProfileHubScreen` (és `TodayHubScreen`) a `practiceLogProvider`-t
(`lib/features/progress/providers/practice_log_provider.dart`) olvassa —
ez a V1 „Learn" gyakorlás-napló (`PracticeSessionRecording`,
`practice_session_recording.dart`), egy ETTŐL FÜGGETLEN tároló a Practice
Engine V2 history repository-tól (`practiceHistoryRepositoryProvider`),
amit ez a bejárás ténylegesen ír (Library/Progress ezt olvassa helyesen).
Egy befejezett V2 quick-start session SOHA nem ír a V1 naplóba, ezért ez a
mérce a session után is pontosan azt mutatja, amit előtte — ez egy VALÓS,
a saját forrásából helyesen számított érték (§5.1, nem P1/P2/P3
placeholder-literál), csak épp egy másik, V2-vak tárolót tükröz.

- **Gazda:** Profile Hub / Progress feature (V1↔V2 napló-szétválás).
- **Kör:** nincs — a két napló összehangolása vagy a mérce forrásának
  cseréje a felelős feature kör dolga; a lelet itt van rögzítve.

### L5 — a `practiceHistoryV2ListProvider` sosem frissül egy konténer élettartamán belül

`practiceHistoryV2ListProvider` (`practice_progress_providers.dart`) egy
sima `FutureProvider` — nem `.family`, és `grep -rn
"invalidate(practiceHistoryV2ListProvider\|refresh(practiceHistoryV2ListProvider"
lib/` **0 találatot** ad: a `lib/`-ben SEHOL nem invalidálja/frissíti
senki. Az ELSŐ olvasása (ezen a bejáráson a Today Hub `dailyGoalActiveSecondsProvider`
→ `aggregatedPracticeFeedProvider` → `practiceProgressFeedProvider` láncán
keresztül, MÉG a gyakorlás előtt) a repository AKKORI állapotát
véglegesen gyorsítótárazza a konténer teljes élettartamára — egy később
befejezett session SOHA nem jelenik meg `progressPracticeHistoryProvider`-ben
(sem a Progress dashboardon, sem a Skill Detailben) ugyanabban a
konténerben. A bejárás emiatt egy VALÓS app-újraindítást (`restartE2eApp`,
ugyanazon store-on) végez az eredmény-állomás után, mielőtt a
Library/Progress/Profile állomásokat bejárná — enélkül a Progress-mérce
(§6.1 mutációs célpontja) sosem tudna valós adatot mutatni ebben a
konténerben, még a helyes forráskód mellett sem.

- **Gazda:** Practice feature / Progress V2 (V2 history cache invalidáció).
- **Kör:** nincs — a cache-invalidáció (vagy a provider `.family`/
  `autoDispose` alakra cserélése) a felelős feature kör dolga; a lelet
  itt van rögzítve.

**Egyik lelet sem placeholder-literál (P1/P2/P3) — mindegyik a bejárás
(A2/A3) által mért, valós, explicit állapot vagy valós (de más forrásból
számított) érték. A STOP-protokoll (§0/§5.2) ezért nem egy hallgatólagos
placeholder-adatot talált, hanem öt, névvel, gazdával rögzített, NEM itt
javítandó bekötési hiányosságot — a kör a mérést és a dokumentálást végzi
el, a javítást a felelős feature körök öröklik.**

## 3. A mért elérhető halmaz partíciója (A4/A5)

`dart run tool/check_screen_reachability.dart --format table` →
**Measured screens: 96. Reachable: 73. Unreachable: 23. Flag-gated: 27.**

### 3.1 Bejárt halmaz (9) — a `full_app_walkthrough_test.dart` FUTÁSÁBÓL

A `runCoreWalkthrough` által ténylegesen felépített (és `find.byType`-pal
megfigyelt) képernyő-osztályok:

| # | Screen (mért osztály) | Forrás-útvonal |
|---|---|---|
| 1 | `OnboardingScreen` | `lib/features/onboarding/screens/onboarding_screen.dart` |
| 2 | `TodayHubScreen` | `lib/features/today/screens/today_hub_screen.dart` |
| 3 | `PracticeAreaHubScreen` | `lib/features/practice_hub/screens/practice_area_hub_screen.dart` |
| 4 | `PracticeSetupScreen` | `lib/features/practice/presentation/screens/practice_setup_screen.dart` |
| 5 | `PracticeSessionScreen` | `lib/features/practice/presentation/screens/practice_session_screen.dart` |
| 6 | `UnifiedLibraryScreen` | `lib/features/library_v2/screens/unified_library_screen.dart` |
| 7 | `ProgressDashboardScreen` | `lib/features/progress_v2/screens/progress_dashboard_screen.dart` |
| 8 | `ProfileHubScreen` | `lib/features/profile_hub/screens/profile_hub_screen.dart` |
| 9 | `SettingsScreen` | `lib/features/settings/screens/settings_screen.dart` |

### 3.2 Kimaradó halmaz (64) — gazdával és körrel

| Screen | Indok | Gazda | Kör |
| --- | --- | --- | --- |
| `lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart` | `aiTutorEnabled` KI besorolású (docs/release/capability-rollout.md) — a bekapcsolás külön Termék/User döntés (Epic 4 zárójelentés), nem mérnöki készenlét kérdése (D1 tiltása). | AI Tutor feature (Epic 4) | nincs — GA flag-flip Termék/User döntés (docs/sdd/epic-04-completion-report.md) |
| `lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart` | `aiTutorEnabled` KI besorolású (docs/release/capability-rollout.md) — a bekapcsolás külön Termék/User döntés (Epic 4 zárójelentés), nem mérnöki készenlét kérdése (D1 tiltása). | AI Tutor feature (Epic 4) | nincs — GA flag-flip Termék/User döntés (docs/sdd/epic-04-completion-report.md) |
| `lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart` | `aiTutorEnabled` KI besorolású (docs/release/capability-rollout.md) — a bekapcsolás külön Termék/User döntés (Epic 4 zárójelentés), nem mérnöki készenlét kérdése (D1 tiltása). | AI Tutor feature (Epic 4) | nincs — GA flag-flip Termék/User döntés (docs/sdd/epic-04-completion-report.md) |
| `lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart` | `aiTutorEnabled` KI besorolású (docs/release/capability-rollout.md) — a bekapcsolás külön Termék/User döntés (Epic 4 zárójelentés), nem mérnöki készenlét kérdése (D1 tiltása). | AI Tutor feature (Epic 4) | nincs — GA flag-flip Termék/User döntés (docs/sdd/epic-04-completion-report.md) |
| `lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart` | `aiTutorEnabled` KI besorolású (docs/release/capability-rollout.md) — a bekapcsolás külön Termék/User döntés (Epic 4 zárójelentés), nem mérnöki készenlét kérdése (D1 tiltása). | AI Tutor feature (Epic 4) | nincs — GA flag-flip Termék/User döntés (docs/sdd/epic-04-completion-report.md) |
| `lib/features/analyze/screens/analyze_screen.dart` | A Practice Area Hub Quick Tools sávja (`practice_area_hub_screen.dart`) csak Live/Tuner/Metronome/Chords gombot ad — nincs Analyze/Learn gomb ezen a képernyőn; a route regisztrálva van (`/practice/analyze`, `/practice/learn`), de a bejárás mag-útján (§1) nem érhető el tapintással. | Learn/Analyze (V1) feature | nincs — a bekötés vagy hiánya a felelős feature kör kérdése |
| `lib/features/audio_analysis/presentation/analysis_compare_screen.dart` | Az Audio Analysis V2 capability-csoport (9 flag) KI besorolású — shadow rollout, Epic 6 release-blokkolók nyitva. | Audio Analysis V2 (Epic 6) | nincs — Epic 6 release-blokkolók feloldása (docs/sdd/epic-06-completion-report.md) |
| `lib/features/audio_analysis/presentation/analysis_export_screen.dart` | Az Audio Analysis V2 capability-csoport (9 flag) KI besorolású — shadow rollout, Epic 6 release-blokkolók nyitva. | Audio Analysis V2 (Epic 6) | nincs — Epic 6 release-blokkolók feloldása (docs/sdd/epic-06-completion-report.md) |
| `lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart` | Az Audio Analysis V2 capability-csoport (9 flag) KI besorolású — shadow rollout, Epic 6 release-blokkolók nyitva. | Audio Analysis V2 (Epic 6) | nincs — Epic 6 release-blokkolók feloldása (docs/sdd/epic-06-completion-report.md) |
| `lib/features/audio_analysis/presentation/analysis_overview_screen.dart` | Az Audio Analysis V2 capability-csoport (9 flag) KI besorolású — shadow rollout, Epic 6 release-blokkolók nyitva. | Audio Analysis V2 (Epic 6) | nincs — Epic 6 release-blokkolók feloldása (docs/sdd/epic-06-completion-report.md) |
| `lib/features/audio_analysis/presentation/analysis_timeline_screen.dart` | Az Audio Analysis V2 capability-csoport (9 flag) KI besorolású — shadow rollout, Epic 6 release-blokkolók nyitva. | Audio Analysis V2 (Epic 6) | nincs — Epic 6 release-blokkolók feloldása (docs/sdd/epic-06-completion-report.md) |
| `lib/features/auth/screens/login_screen.dart` | `accountEnabled=false` ebben az összeállításban (a kör a szállított `FeatureFlags.forEnvironment(development, accountEnabled: false)` értéket használja) — a Profile Hub emiatt csak a helyi-only szöveget mutatja, Sign-in CTA nélkül; a bejárás a bejelentkezés NÉLKÜLI utat méri. | Auth feature | nincs — accountEnabled=false ebben az összeállításban, nincs hosztolt backend-döntés |
| `lib/features/chords/screens/chord_library_screen.dart` | A Practice Area Hub Quick Tools egy érintéssel elérhető gombjai (`practice_area_hub_screen.dart`) — a kör mag-útja (§1) nem nevezi meg őket, saját adat-bekötésüket a `hub_navigation_test.dart` A2 cellája már méri. | Practice feature (quick tools) | E13-R17 |
| `lib/features/community/presentation/screens/clubs/club_member_management_screen.dart` | A Community capability-csoport PREVIEW besorolású (`bool.fromEnvironment`, dart-define nélkül mindig KI) — a privacy/threat-model kör még végrehajtás előtt áll. | Community feature (Epic 9) | E12-R17 |
| `lib/features/community/presentation/screens/edit_profile_screen.dart` | A Community capability-csoport PREVIEW besorolású (`bool.fromEnvironment`, dart-define nélkül mindig KI) — a privacy/threat-model kör még végrehajtás előtt áll. | Community feature (Epic 9) | E12-R17 |
| `lib/features/gamification/presentation/screens/achievement_detail_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/achievements_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/gamification_hub_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/level_detail_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/quests_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/reward_inbox_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/gamification/presentation/screens/streak_detail_screen.dart` | Elérhető a Profile Hub „achievements” gombjából (két érintésen belül), de a kör mag-útja (§1) a névvel megnevezett Today→gyakorlás→eredmény→Library→Progress→Profile magistrálist járja be — a gamification-alrendszer saját köre (E08-R30) tesztjei már mérik az adat-bekötést. | Gamification feature (Epic 8) | E08-R30 |
| `lib/features/learn/screens/latency_calibration_screen.dart` | A Practice Area Hub Quick Tools sávja (`practice_area_hub_screen.dart`) csak Live/Tuner/Metronome/Chords gombot ad — nincs Analyze/Learn gomb ezen a képernyőn; a route regisztrálva van (`/practice/analyze`, `/practice/learn`), de a bejárás mag-útján (§1) nem érhető el tapintással. | Learn/Analyze (V1) feature | nincs — a bekötés vagy hiánya a felelős feature kör kérdése |
| `lib/features/learn/screens/learn_screen.dart` | A Practice Area Hub Quick Tools sávja (`practice_area_hub_screen.dart`) csak Live/Tuner/Metronome/Chords gombot ad — nincs Analyze/Learn gomb ezen a képernyőn; a route regisztrálva van (`/practice/analyze`, `/practice/learn`), de a bejárás mag-útján (§1) nem érhető el tapintással. | Learn/Analyze (V1) feature | nincs — a bekötés vagy hiánya a felelős feature kör kérdése |
| `lib/features/learn/screens/lesson_list_screen.dart` | A Practice Area Hub Quick Tools sávja (`practice_area_hub_screen.dart`) csak Live/Tuner/Metronome/Chords gombot ad — nincs Analyze/Learn gomb ezen a képernyőn; a route regisztrálva van (`/practice/analyze`, `/practice/learn`), de a bejárás mag-útján (§1) nem érhető el tapintással. | Learn/Analyze (V1) feature | nincs — a bekötés vagy hiánya a felelős feature kör kérdése |
| `lib/features/learn/screens/lesson_score_preview_screen.dart` | A Practice Area Hub Quick Tools sávja (`practice_area_hub_screen.dart`) csak Live/Tuner/Metronome/Chords gombot ad — nincs Analyze/Learn gomb ezen a képernyőn; a route regisztrálva van (`/practice/analyze`, `/practice/learn`), de a bejárás mag-útján (§1) nem érhető el tapintással. | Learn/Analyze (V1) feature | nincs — a bekötés vagy hiánya a felelős feature kör kérdése |
| `lib/features/library/screens/library_screen.dart` | Legacy (nem-adaptív-shell) regisztráció; ebben az összeállításban (`adaptiveShellEnabled=true`) vagy kizárt a routerből (`if (!adaptiveShellEnabled)`), vagy a `legacyRedirects` a shell-megfelelőjére tereli — a saját adat-bekötését más kör tesztje már méri. | Practice/Progress/Library legacy felület | E13-R08 |
| `lib/features/library/screens/session_detail_screen.dart` | Legacy (V1) munkamenet-részlet, a `/library/session` mélylinken (nem szerepel a `legacyRedirects` táblában, tehát nem redirectel, de a bejárás mag-útja nem nyit ilyen mélylinket). A V2 utód a Library-listából nyitható `LibraryItemDetailScreen`. | Library feature (V1) | E13-R28 |
| `lib/features/library_v2/screens/library_item_detail_screen.dart` | Lista-szintű állomás (Library/Progress) bejárva valós adattal; a listaelem/mérföldkő-sor tovább-nyitása (részletnézet) ezen a futáson nem történt meg (a Progress állomás ezen a mért futáson az explicit new-user ágra esett, sor nélkül) — a részletnézet saját, dedikált tesztje fedi az adat-bekötést. | Library V2 / Progress V2 | E13-R28 |
| `lib/features/live/screens/live_screen.dart` | A Practice Area Hub Quick Tools egy érintéssel elérhető gombjai (`practice_area_hub_screen.dart`) — a kör mag-útja (§1) nem nevezi meg őket, saját adat-bekötésüket a `hub_navigation_test.dart` A2 cellája már méri. | Practice feature (quick tools) | E13-R17 |
| `lib/features/metronome/screens/metronome_screen.dart` | A Practice Area Hub Quick Tools egy érintéssel elérhető gombjai (`practice_area_hub_screen.dart`) — a kör mag-útja (§1) nem nevezi meg őket, saját adat-bekötésüket a `hub_navigation_test.dart` A2 cellája már méri. | Practice feature (quick tools) | E13-R17 |
| `lib/features/offline_ai/screens/model_manager_screen.dart` | Offline AI modellkezelő felület — nem szerepel a `docs/release/capability-rollout.md` táblájában (nem `forEnvironment`-döntés tárgya), nincs hozzárendelt BE/KI besorolás vagy kör. | Offline AI feature | nincs — nincs hozzárendelt kör, a capability-rollout.md táblája nem sorolja fel |
| `lib/features/onboarding/screens/permission_primer_screen.dart` | A mikrofon-engedély primer az onboarding „first win” gyorsútjának állomása; a bejárás a Skip-utat méri (offline mag-út), nem a gyorsutat. | Onboarding feature | nincs — a bejárás a Skip-utat méri, a first-win gyorsút külön eval tárgya (Chapter 14) |
| `lib/features/practice/presentation/screens/practice_history_screen.dart` | MÉRT mérőeszköz-limit (ADR 0471 D7, csak szöveges class-name egyezés): a két osztály csak EGYMÁST hivatkozza imperatíven (`PracticeHistoryScreen` nyitja `PracticeResultScreen`-t, ami vissza `PracticeHistoryScreen`-re mutat) — a valós felület (PracticeAreaHubScreen, ProfileHubScreen, legacy PracticeHubScreen) egyike sem nyit `PracticeHistoryScreen`-t. A statikus mérő ezért reachable-nek jelzi őket, de a bejárható magistrálisról nincs hozzájuk valós belépési pont. | Practice feature | nincs — a bekötés (mélylink a valós felületről) a felelős feature kör dolga |
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | Legacy (nem-adaptív-shell) regisztráció; ebben az összeállításban (`adaptiveShellEnabled=true`) vagy kizárt a routerből (`if (!adaptiveShellEnabled)`), vagy a `legacyRedirects` a shell-megfelelőjére tereli — a saját adat-bekötését más kör tesztje már méri. | Practice/Progress/Library legacy felület | E13-R08 |
| `lib/features/practice/presentation/screens/practice_result_screen.dart` | MÉRT mérőeszköz-limit (ADR 0471 D7, csak szöveges class-name egyezés): a két osztály csak EGYMÁST hivatkozza imperatíven (`PracticeHistoryScreen` nyitja `PracticeResultScreen`-t, ami vissza `PracticeHistoryScreen`-re mutat) — a valós felület (PracticeAreaHubScreen, ProfileHubScreen, legacy PracticeHubScreen) egyike sem nyit `PracticeHistoryScreen`-t. A statikus mérő ezért reachable-nek jelzi őket, de a bejárható magistrálisról nincs hozzájuk valós belépési pont. | Practice feature | nincs — a bekötés (mélylink a valós felületről) a felelős feature kör dolga |
| `lib/features/practice/presentation/screens/speed_builder_screen.dart` | Külön Learn-mód alfelület, dokumentált „provably actionless informational state” (ld. `practice_hub_screen.dart` hivatkozása a saját `_UnavailableLayout`-jára) — a bejárás mag-útján kívül esik. | Learn feature | nincs — külön feature-kör tárgya, dokumentált info-állapot |
| `lib/features/practice_generator/presentation/screens/plan_setup_screen.dart` | `practiceGeneratorEnabled` BE, de a Practice Area Hubon nincs UI-belépési pont a Generátorba (nincs „Plan setup” vagy „Today plan” gomb) — a kör mag-útja nem éri el. | Practice Generator feature | E15-R07 |
| `lib/features/practice_generator/presentation/screens/today_plan_screen.dart` | `practiceGeneratorEnabled` BE, de a Practice Area Hubon nincs UI-belépési pont a Generátorba (nincs „Plan setup” vagy „Today plan” gomb) — a kör mag-útja nem éri el. | Practice Generator feature | E15-R07 |
| `lib/features/progress/screens/progress_screen.dart` | Legacy (nem-adaptív-shell) regisztráció; ebben az összeállításban (`adaptiveShellEnabled=true`) vagy kizárt a routerből (`if (!adaptiveShellEnabled)`), vagy a `legacyRedirects` a shell-megfelelőjére tereli — a saját adat-bekötését más kör tesztje már méri. | Practice/Progress/Library legacy felület | E13-R08 |
| `lib/features/progress_v2/screens/skill_detail_screen.dart` | Lista-szintű állomás (Library/Progress) bejárva valós adattal; a listaelem/mérföldkő-sor tovább-nyitása (részletnézet) ezen a futáson nem történt meg (a Progress állomás ezen a mért futáson az explicit new-user ágra esett, sor nélkül) — a részletnézet saját, dedikált tesztje fedi az adat-bekötést. | Library V2 / Progress V2 | E13-R28 |
| `lib/features/settings/screens/privacy_center_screen.dart` | A Settings-képernyő (bejárva) egyik aloldala — ez a kör a Settings-állomás jelenlétét és adatát méri, nem annak minden aloldalát. | Settings feature | nincs — a Settings-állomás aloldala, külön feature-kör tárgya |
| `lib/features/settings/screens/vision_privacy_screen.dart` | A Computer Vision capability-csoport (11 flag) KI besorolású — HORIZON valós-eszköz elfogadás nyitott (86 PENDING sor, kamera/thermal/soak/latency). | Computer Vision feature (Epic 5) | nincs — HORIZON valós-eszköz elfogadás (docs/sdd/epic-05-completion-report.md) |
| `lib/features/share/screens/share_preview_screen.dart` | Megosztási mellékág (eredmény/history képernyőkről nyitható) — a bejárás mag-útja (§1) az eredmény-állomás explicit „unavailable” ágát méri, a megosztást nem. | Share feature | nincs — megosztási mellékág, a mag-úton kívül esik |
| `lib/features/share/screens/strum_reel_screen.dart` | Megosztási mellékág (eredmény/history képernyőkről nyitható) — a bejárás mag-útja (§1) az eredmény-állomás explicit „unavailable” ágát méri, a megosztást nem. | Share feature | nincs — megosztási mellékág, a mag-úton kívül esik |
| `lib/features/share/screens/wrapped_preview_screen.dart` | Megosztási mellékág (eredmény/history képernyőkről nyitható) — a bejárás mag-útja (§1) az eredmény-állomás explicit „unavailable” ágát méri, a megosztást nem. | Share feature | nincs — megosztási mellékág, a mag-úton kívül esik |
| `lib/features/song_trainer/presentation/screens/song_editor_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_library_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_overview_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_result_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/song_trainer_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart` | `songTrainerV2Enabled` BE, de a Song Trainer saját `/song-trainer` útvonal-fáján él — sem a Practice Area Hub, sem az adaptív shell Songs tabja nem linkel bele; a bekötést a Song Trainer saját funkcionális tesztjei fedik. | Song Trainer feature | nincs — külön BE-capability felület, saját tesztjei fedik, nincs belépési pont a mag-úton |
| `lib/features/songs/screens/setlist_detail_screen.dart` | Az adaptív shell „Songs” tabján (4. navigációs cél) elérhető — a kör mag-útja (§1) csak Today/Practice/Library/Progress/Profile állomásokat nevez meg, a Songs tabot nem. | Songs feature | nincs — a Songs tab a mag-úton kívül esik, saját UI-tesztjei fedik |
| `lib/features/songs/screens/setlist_list_screen.dart` | Az adaptív shell „Songs” tabján (4. navigációs cél) elérhető — a kör mag-útja (§1) csak Today/Practice/Library/Progress/Profile állomásokat nevez meg, a Songs tabot nem. | Songs feature | nincs — a Songs tab a mag-úton kívül esik, saját UI-tesztjei fedik |
| `lib/features/songs/screens/song_builder_screen.dart` | Az adaptív shell „Songs” tabján (4. navigációs cél) elérhető — a kör mag-útja (§1) csak Today/Practice/Library/Progress/Profile állomásokat nevez meg, a Songs tabot nem. | Songs feature | nincs — a Songs tab a mag-úton kívül esik, saját UI-tesztjei fedik |
| `lib/features/songs/screens/song_list_screen.dart` | Az adaptív shell „Songs” tabján (4. navigációs cél) elérhető — a kör mag-útja (§1) csak Today/Practice/Library/Progress/Profile állomásokat nevez meg, a Songs tabot nem. | Songs feature | nincs — a Songs tab a mag-úton kívül esik, saját UI-tesztjei fedik |
| `lib/features/streak/screens/streak_screen.dart` | A Profile Hub nem linkel közvetlenül a `/profile/rewards` útvonalra (csak achievements/library/settings gombja van) — csak a legacy `/streak` deep linken vagy közvetlen URL-en érhető el. Az utód-felület a Gamification Hub `StreakDetailScreen`-je. | Streak/Gamification feature | E08-R30 |
| `lib/features/tuner/screens/tuner_screen.dart` | A Practice Area Hub Quick Tools egy érintéssel elérhető gombjai (`practice_area_hub_screen.dart`) — a kör mag-útja (§1) nem nevezi meg őket, saját adat-bekötésüket a `hub_navigation_test.dart` A2 cellája már méri. | Practice feature (quick tools) | E13-R17 |
| `lib/features/vision/presentation/screens/guitar_calibration_screen.dart` | A Computer Vision capability-csoport (11 flag) KI besorolású — HORIZON valós-eszköz elfogadás nyitott (86 PENDING sor, kamera/thermal/soak/latency). | Computer Vision feature (Epic 5) | nincs — HORIZON valós-eszköz elfogadás (docs/sdd/epic-05-completion-report.md) |
| `lib/features/vision/presentation/screens/vision_result_screen.dart` | A Computer Vision capability-csoport (11 flag) KI besorolású — HORIZON valós-eszköz elfogadás nyitott (86 PENDING sor, kamera/thermal/soak/latency). | Computer Vision feature (Epic 5) | nincs — HORIZON valós-eszköz elfogadás (docs/sdd/epic-05-completion-report.md) |
| `lib/features/vision/presentation/screens/vision_session_screen.dart` | A Computer Vision capability-csoport (11 flag) KI besorolású — HORIZON valós-eszköz elfogadás nyitott (86 PENDING sor, kamera/thermal/soak/latency). | Computer Vision feature (Epic 5) | nincs — HORIZON valós-eszköz elfogadás (docs/sdd/epic-05-completion-report.md) |
| `lib/features/vision/presentation/screens/vision_setup_screen.dart` | A Computer Vision capability-csoport (11 flag) KI besorolású — HORIZON valós-eszköz elfogadás nyitott (86 PENDING sor, kamera/thermal/soak/latency). | Computer Vision feature (Epic 5) | nincs — HORIZON valós-eszköz elfogadás (docs/sdd/epic-05-completion-report.md) |

**Összegzés:** 9 (bejárt) + 64 (kimaradó) = 73 (mért elérhető) — a két
halmaz diszjunkt (egyik screen sem szerepel mindkettőben) és uniójuk
pontosan lefedi a mért elérhető halmazt. Egyik kimaradó sor sem üres
`Indok`/`Gazda`/`Kör` cellával; minden `Kör` érték `E\d+-R\d+` alakú vagy
kimondott `nincs — <indok>`.

## 4. Nyitott tételek

| # | Tétel | Gazda | Kör |
|---|---|---|---|
| 1 | L1 — Practice Area Hub recommended CTA nem ad át `id`-t | Practice Area Hub | **`E16-R06` — feloldva** (ADR 0508 D3/D4, l. a szakasz Kör sorát) |
| 2 | L2 — Onboarding mindig `/live`-ra fejez be | Onboarding feature | **`E16-R06` — feloldva** (ADR 0508 D1/D2, l. a szakasz Kör sorát) |
| 3 | L3 — Library V2 forrásai bootstrap-függők, a harness nem köti be | Library V2 / E12-R11 harness | nincs — a harness-nek vagy a Library kompozíciós rétegének kell ezt bekötnie egy jövőbeli körben; a lelet itt van rögzítve |
| 4 | L4 — Profile Hub „sessions” mércéje a V1 naplót olvassa | Profile Hub / Progress feature | nincs — a két napló összehangolása vagy a mérce forrásának cseréje a felelős feature kör dolga; a lelet itt van rögzítve |
| 5 | L5 — `practiceHistoryV2ListProvider` sosem frissül egy konténer élettartamán belül | Practice feature / Progress V2 | nincs — a cache-invalidáció (vagy a provider `.family`/`autoDispose` alakra cserélése) a felelős feature kör dolga; a lelet itt van rögzítve |
| 6 | A3 — a core utak a termék SAJÁT navigációjával (a két teszt-oldali híd nélkül) mérhetően NEM járhatók végig (l. L1, L2, §2 bevezető) | Practice Area Hub / Onboarding feature | **`E16-R06` — feloldva, A3 mérve TELJESÜL** (l. §2 bevezető) |
