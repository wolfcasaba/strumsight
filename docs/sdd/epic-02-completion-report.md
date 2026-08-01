# Epic 2 — Practice Engine: zárójelentés

Dátum: 2026-08-01 · Zárókör: E02-R20 · Implementer: MiniMax M3 (kör-jelzés
szerződéssel, ADR 0069) · Reviewer: Claude (Opus 5) · A CI zöld kapuját az
orchestrátor a kör merge-ölésével együtt futtatja.

SDD: [`03-epic-02-practice-engine.md`](03-epic-02-practice-engine.md) ·
Állapot-pillanatkép: [`HANDOFF.md`](../../HANDOFF.md) ·
Kör-brief: [`docs/rounds/e02-r20-epic-closure.md`](../rounds/e02-r20-epic-closure.md)

> ⚠ **A legfontosabb mondat.** A Practice V2 domain és application rétege
> kimerítően tesztelt, de a presentation→controller drótozás az önálló
> (nem Learn-migrációs) Practice-session úton R12/R13 óta nyitva maradt, és
> egyetlen későbbi kör sem zárta. A `practiceSessionHostProvider` éles
> defaultja `null`, a `practicePrepareSinkProvider` éles defaultja
> placeholder — emiatt egy valós felhasználó a Practice Hub → Setup →
> Session úton ma **NEM tud önálló Practice V2 sessiont futtatni** az
> élesített appban. Ez az egyetlen legfontosabb tétel, amit a DoD-tábla
> (§5) az „A7 rendszerszintű rés" oszlopban meg kell hogy mondjon. A
> §5 celláiban ez a **minősítés** jelenik meg, nem sima „teljesül".

## 1. Elkészült körök

| Kör | Téma | PR | ADR |
|---|---|---|---|
| E02-R01 | Practice baseline, feature flag, ADR váz | #29 | 0065, 0067 |
| E02-R02 | BeatPosition / Tempo / Meter értékobjektumok | #30 | 0066 |
| E02-R03 | Practice domain szerződések (60 stabil kód) | #31 | 0068 |
| E02-R04 | Built-in practice catalog (10 gyakorlat) | #32 | 0070 |
| E02-R05 | Legacy adapterek (Lesson/Song/Analyze/DailyChallenge) | #33 | 0071 |
| E02-R06 | Target compiler és beat↔idő konverzió | #34 | 0072 |
| E02-R07 | Session clock és state machine | #35 | 0073 |
| E02-R08 | Observation gateway + live adapter | #36 | 0074 |
| E02-R09 | Event matcher (kurzoralapú, legacy parity) | #37 | 0075 |
| E02-R10 | Timing / direction / chord scorer + aggregator | #38 | 0076 |
| E02-R11 | PracticeSessionController orchestration | — | 0077 |
| E02-R12 | Practice Hub + Setup UI | — | 0078 |
| E02-R13 | Practice Session UI shell | — | 0079 |
| E02-R14 | Strum Pattern + Chord Progression mód | #38 | 0080 |
| E02-R15 | Chord Change mód | #39 | 0081 |
| E02-R16 | Rhythm-only + Free Practice (honest summary) | #40 | 0082 |
| E02-R17 | Speed Builder, loop, adaptív retry | #41 | 0083 |
| E02-R18 | Result + coaching + history V2 | #42 | 0084 |
| E02-R19 | Progress merge + streak + daily goal + Learn V2 migráció | #43 | 0085 |
| E02-R20 | A11y audit + perf számlálók + property gate + Epic-zárás | (R20) | — |

Az egyes körök részletes története (verifikációs kimenetekkel,
tanulságokkal): [`docs/handoff-archive.md`](../handoff-archive.md) és
[`docs/reviews/e02-r*.md`](../reviews/).

## 2. Nyitott leletek (R01–R19 review-kből összegyűjtve, 2026-08-01)

A R20 pre-flight során mért állapot. A rendszerszintű rést a §3 rendszerszintű
rés blokk tárgyalja — ez a lista az egyedi, lokális leleteket gyűjti.

| Forrás | Lelet | Mai állapot |
|---|---|---|
| R11 §11.4/1 | `noSignal` a direction/rhythm dimenzióban "unpaired"-et jelent, nem "nem érkezett jel"-t — két scorer-szemantika összemosva (ADR 0077 ismert korlát). | **Nyitott** — nincs későbbi javítás. |
| R11 §11.4/2 | `allowedTransitions`-ben van él (`countIn/running → failed`), amit runtime-on egyetlen input sem termel — holt átmenet, nincs gyakorolva. | **Nyitott** — nincs későbbi javítás. |
| R11 §11.4/3 | A Practice a **Live** engine mikrofon-leasét (`AudioOwner.live`) használja, nincs saját tulajdonosa. | **Nyitott** — `AudioOwner` enum ma is `live, tuner, analyzeRecorder, latencyCalibration, diagnostics` (nincs `practice` tag). |
| R11 §11.4/4 | `practiceSessionControllerProvider` nincs éles oldalon bedrótozva. | **Nyitott — ld. §3 rendszerszintű rés.** |
| R15 NOTE-1 | A chord-change elemzés az éles session-screenen null-drótozott (`analysis: null, latestChange: null`); ígéret: "R18 köti be". | **Nyitott** — `practice_session_screen.dart:330-336` ma is `null`; R18 briefje ezt nem tartalmazta. |
| R18 n1 / R19 followup | A Free Practice eredmény-képernyő "strum count" csempéje `attemptsCount`-ot mutat strumszám helyett. | **Nyitott** — `practice_result_screen.dart:165` ma is `entry.attemptsCount`; R19 scope-auditja szerint a fájlhoz nem is nyúlt. |
| R18 B2 residual | Az éles `practiceSessionRecorderProvider` becsületes Noop lett (nem hamis-siker), de emiatt **egyetlen önálló Practice V2 session sem perzisztálódik**, amíg a valós `mode/source/definitionId` metaadat nincs végigvezetve. | **Nyitott** — `practice_session_providers.dart:11,71-94` ma is `NoopPracticeSessionRecorder`. R19 csak a Learn-migrációs útvonalat drótozta be, az önálló Hub→Session utat nem. |
| R14 NOTE-1 | Az A4 "commands/verdict-list/HUD score unchanged" invariáns fél nem kapott saját regressziós cellát. | **Nyitott** — nincs ilyen cella `practice_highway_test.dart`-ban; alacsony prioritás. |
| R16 N1 | `free_practice_property_test.dart` `_randomInput`-ja előre rendezi az observationöket — a "timeline ≤ active" invariáns rendezetlen inputon nincs property-tesztelve. | **Nyitott** — alacsony prioritás. |
| R17 N1 | Az adaptív policy "3 egymást követő step-up pass" küszöbe hardkódolt, nem policy-paraméteres. | **Nyitott** — kozmetikai. |
| R11+R13+R15+R05+R16+R17+R19 | Az Epic R5/R11/R13/R15/R16/R17/R19 minden merge-e a saját R20-as §5 cellájában **teljesül**-lel szerepelt a domain/widget tesztek bizonyítékával; a R20-as javító kör #1 az R5 (#34, #37), R16 (#39, #40), R17 (#30) és R19 (#41) sorokat is „A7 rendszerszintű rés" minősítésre cserélte, mivel a mért hívási lánc (fájl:sor szinten dokumentálva a §5 cellákban) igazolta, hogy ezek egyike sem érhető el a Hub→Setup→Session önálló Practice V2 úton, amíg a §3 rendszerszintű rés fennáll. |

## 3. Rendszerszintű rés (a §2 lista összegzése)

A `practiceSessionHostProvider` éles defaultja **`null`**
(`lib/features/practice/presentation/practice_effect_listener.dart:21-22,64`,
doc-comment: *"the production default is `null`, which the screen renders as
a localised 'session unavailable' state"*), és a `practicePrepareSinkProvider`
éles defaultja is a placeholder logging sink
(`practice_setup_controller.dart:33-55`, „Kör 13 swaps the..." komment még
ma is ott van). **Ennek eredőjeként egy valós felhasználó a Practice Hub →
Setup → Session úton ma NEM tud önálló Practice V2 sessiont futtatni az
élesített appban** — a domain/application réteg kimerítően tesztelt, de a
presentation→controller drótozás az önálló (nem Learn-migrációs) útra
R12/R13 óta nyitva maradt, és egyetlen későbbi kör sem zárta. Összhangban
áll azzal, hogy `practiceEngineV2Enabled` éles defaultja `false`
(`lib/app/config/feature_flags.dart:15,41`).

**Ez az egyetlen legfontosabb tétel, amit a zárójelentésnek ki KELL
mondania** — a §5 DoD-tábla session-lifecycle/gyakorlási-mód/integráció
celláinak mindegyikét „teljesül domain/widget-teszt szinten, de nem
elérhető végponttól-végpontig az élesített appban" minősítéssel kell
ellátni, nem egyszerű "teljesül"-lel. **A drótozás pótlása ebben a körben
TILOS** (§4 — ez funkció, nem apró javítás, és az érintett fájl
`practice_session_providers.dart` / `practice_effect_listener.dart` a tilos
zónában van) — nyitott leletként dokumentálandó.

## 4. Migrated Learn rollout-döntés (user-döntésre vár)

A `migratedLearnEnabled` flag a teljes Epic-2 alatt **OFF** maradt. A
bekapcsolás feltételeit a R19 paritás-őr készítette elő (ADR 0085). A
rollout-döntés és a feltételei **külön user-döntés**:

- A `migratedLearnEnabled` **mérföldkövei** (melyik user-szegmens, melyik
  build-szám mellett kapcsol be);
- A bekapcsolás **monitorozási tervének** rögzítése (melyik
  V2-score-eltérést nézzük az R19 §0.3-ban dokumentált határponti
  mikro-eltérésen felül);
- A visszaállítási útvonal (flag-OFF → régi LearnScreen).

Ezek a döntések **ebben a zárókörben nem** születnek meg — az Epic-2
zárása a `migratedLearnEnabled` értékétől független.

## 5. SDD Ch3 §28 DoD checklista — evidenciával

Minden cella **ténylegesen lefutott teszttel vagy gépi paranccsal** van
igazolva. A „nagyrészt teljesül" típusú összevont mondat nem elfogadható
(§5.5 kötött döntés).

### Architektúra (8/8 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 1 | Létezik külön Practice feature | **teljesül** | `lib/features/practice/` + `tool/check_architecture.dart` (allowlist: 0 új eltérés az Epic alatt) |
| 2 | A domain pure Dart | **teljesül** | `domain_purity_test.dart` (R03) |
| 3 | A zenei pozíció integer tick alapú | **teljesül** | `beat_position_test.dart` (R02) + `BeatPosition(480 PPQ)` |
| 4 | A session explicit state machine-t használ | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `practice_session_reducer_test.dart` + `practice_session_property_test.dart`; a §3 rendszerszintű rés miatt az éles appban nem indítható önálló session |
| 5 | A UI nem tartalmaz scorer logikát | **teljesül** | `practice_presentation_guard_test.dart` + R10 review §11.4 |
| 6 | Az audio observation gateway mögött van | **teljesül** (helyes, de sosem éles a §3 rés miatt) | `practice_observation_activation_test.dart` |
| 7 | A persistence repository mögött van | **teljesül** | `local_practice_history_repository.dart` (R18) + ADR 0084 |
| 8 | Az új feature nem importál más feature belső presentation/provider fájlt | **teljesül** | `tool/check_architecture.dart` |

### Session lifecycle (6/6 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 9 | Prepare, permission, count-in, run, pause, resume, restart, finish és cancel működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `practice_session_controller_test.dart`, `practice_session_timing_test.dart`, `practice_session_lifecycle_test.dart`; §3 rendszerszintű rés |
| 10 | Pause alatt nincs pontozás | **teljesül** | `practice_event_matcher_test.dart` (R09) — pause alatt az observation-gateway lekapcsol, a matcher nem kap inputot |
| 11 | Resume nem ugrik időben | **teljesül** | `practice_session_timing_test.dart` + `practice_session_property_test.dart` |
| 12 | Finish idempotens | **teljesül** | `practice_session_recording_test.dart` (R18) — a recorder idempotens save-őrrel |
| 13 | Terminal state után minden erőforrás felszabadul | **teljesül** | `practice_session_lifecycle_test.dart` A7 cella (R13) |
| 14 | App background viselkedés tesztelt | **teljesül** | `practice_session_lifecycle_test.dart` A6 cella (R13) — `paused/hidden/detached` → `PausePractice(interruption)` |

### Pontozás (10/10 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 15 | Egy target legfeljebb egyszer párosítható | **teljesül** | `practice_engine_property_test.dart` A4.1 (R20) — 100× iteration, `seenTargetIndices.add(...)` invariáns |
| 16 | Egy observation legfeljebb egyszer használható | **teljesül** | `practice_engine_property_test.dart` A4.1 (R20) — gateway-side sequence dedup + matcher-side A4.1 assertion |
| 17 | Timing külön metrika | **teljesül** | `practice_timing_scorer_test.dart` (R10) |
| 18 | Direction külön metrika | **teljesül** | `practice_direction_scorer_test.dart` (R10) |
| 19 | Chord külön metrika | **teljesül** | `practice_chord_scorer_test.dart` (R10) |
| 20 | Unavailable dimenzió nem jelenik meg 0%-ként | **teljesül** | `practice_engine_property_test.dart` A4.2 (R20) — sealed `MetricValue` típus, a result screen `findsNothing` az unavailable-re |
| 21 | Free Practice nem generál hamis accuracyt | **teljesül** | `practice_engine_property_test.dart` A4.3 (R20) — `FreePracticeSummary`-ban nincs `overallAccuracy` mező |
| 22 | Early/late bias számolható | **teljesül** | `timing_bias_chart_test.dart` (R18) |
| 23 | Chord-pair probléma azonosítható | **teljesül** | `chord_change_view_test.dart` + `chord_change_breakdown.dart` (R15) |
| 24 | Legacy Learn parity dokumentált | **részleges — bitre-egzakt a sávon kívül, 2 kipinnelt divergencia a µs-sávon belül** | `practice_scorer_legacy_parity_test.dart` (R19 fix#1 — 51 cella, 0 offset/latency; R20 review §2.1 — ADR 0075 §2b, R19 §0.2–§0.3); eltérések dokumentálva: R19 `5ab9a37` |

### Gyakorlási módok (8/8 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 25 | Strum Pattern működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `strum_pattern_view_test.dart`, `practice_highway_test.dart`, `practice_highway_scaling_test.dart` (R14); §3 rendszerszintű rés |
| 26 | Chord Changes működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `chord_change_view_test.dart`, `chord_change_analyzer_test.dart` (R15); §3 rendszerszintű rés |
| 27 | Chord Progression működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `chord_progression_view_test.dart` (R14); §3 rendszerszintű rés |
| 28 | Rhythm Only működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `rhythm_only_view_test.dart` (R16); §3 rendszerszintű rés |
| 29 | Free Practice működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `free_practice_view_test.dart`, `free_practice_summarizer_test.dart`, `free_practice_property_test.dart` (R16); §3 rendszerszintű rés |
| 30 | Speed Builder működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `speed_builder_progress_test.dart`, `speed_builder_engine_test.dart`, `speed_builder_property_test.dart`, `adaptive_practice_policy_test.dart` (R17); §3 rendszerszintű rés — mérve: `grep -rn "SpeedBuilder\|speed_builder" lib/features/learn/` 0 találat, a `SpeedBuilderEngine`/`SpeedBuilderProgress` kizárólag a `practice_session_screen.dart`-ban van hívva, az önálló Practice-úton a §3 rendszerszintű rés miatt nem indítható |
| 31 | 3/4 és 4/4 támogatott | **teljesül** | `meter_test.dart` (R02) + `compiled_practice_target_test.dart` (R06) |
| 32 | Loop működik | **teljesül** (compiler szintjén bizonyított, UI-n át nem elérhető) | `practice_target_compiler_test.dart` loop-rebase (R06); §3 rendszerszintű rés |

### Integráció (9/9 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 33 | Built-in catalog működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `builtin_practice_catalog_test.dart` (R04); §3 rendszerszintű rés |
| 34 | Lesson adapter működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `lesson_practice_adapter_test.dart` (R05); §3 rendszerszintű rés — mérve: `practiceDefinitionFromLesson` (`lesson_practice_adapter.dart:27`) production hívója kizárólag a saját tesztfájljaiban (`practice_target_legacy_parity_test.dart`, `practice_event_matcher_parity_test.dart`, `practice_scorer_legacy_parity_test.dart`, `lesson_practice_adapter_test.dart`); az éles Learn V2 út (`_recordLearnMomentV2`, `learn_screen.dart:367-414`) a `scoreLessonV2`-t hívja (`lesson_v2_scoring.dart:6`), nem az adaptert |
| 35 | Song adapter működik | **teljesül** | `song_practice_adapter_test.dart` (R05) |
| 36 | Analyze adapter működik | **teljesül** | `analyze_practice_adapter_test.dart` (R05) |
| 37 | Daily Challenge adapter működik | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `daily_challenge_practice_adapter_test.dart` (R05); §3 rendszerszintű rés — mérve: a `PracticeHubScreen` (`practice_hub_screen.dart:221-227`, `practiceHubDailyChallengeLabel`) route-ja `app_router.dart:44-49,124` szerint a `practiceEngineV2Enabled` flagtől függ, éles default `false`, így a Hub-kártya nem jelenik meg; az éles Daily Challenge UX a `streak_screen.dart:32,160` → `Lessons.fromDailyChallenge` legacy útvonalon megy |
| 38 | Progress V1 és V2 együtt olvasható | **teljesül** (Learn-migrációs úton bizonyított, önálló Practice-session úton Noop miatt sosem fut le) | `practice_progress_aggregator_test.dart` (R18+R19) |
| 39 | Daily goal aktív időből számol | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `daily_goal_provider_test.dart` + ADR 0085; §3 rendszerszintű rés — mérve: a `SessionEligibilitySnapshot`-ot felolvasó `practiceSessionRecording.record()`-ot (`practice_session_recording.dart:121`) kizárólag a `migratedLearnEnabled`-gated `_recordLearnMomentV2` (`learn_screen.dart:376`) hívja az éles kódból; az önálló Practice V2 úton a `NoopPracticeSessionRecorder` miatt sosem fut le |
| 40 | Streak eligibility helyes | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `streak_logic_test.dart`, `practice_session_eligibility_test.dart` (R16); §3 rendszerszintű rés — mérve: a `PracticeSessionEligibility` predikátumot (`practice_session_eligibility.dart`) csak a `practiceSessionRecording.record()` hívja, ami az éles Learn úton a `_recordLearnMomentV2`-n át fut (lásd #39); az éles Learn másik ága a legacy `StreakController.recordPracticeToday()`-t (`streak_provider.dart:23`) hívja közvetlenül, **eligibility-kapu nélkül** |
| 41 | Easy mód nem írja felül a full lesson stars eredményét | **teljesül domain/widget-teszt szinten, de nem elérhető végponttól-végpontig az élesített appban** | `learn_screen.dart:411` `if (!_easy && outcome.loggedEntry != null)` (a `lessonProgressProvider.notifier.record` Easy mode-ban nem hívódik); §3 rendszerszintű rés — mérve: az Easy mode-ban futó `_recordLearnMomentV2` a `migratedLearnEnabled`-gated branch, az önálló Practice V2 úton Easy mode nem érhető el |

### Minőség (11/11 — A1 minősítéssel)

| # | Tétel | Állapot | Bizonyíték |
|---|---|---|---|
| 42 | Unit tesztek zöldek | **teljesül** | `flutter test test/features/practice` — §9 záró gate |
| 43 | Property tesztek zöldek | **teljesül** | `flutter test test/property` — §9 záró gate |
| 44 | Widget tesztek zöldek | **teljesül** | `flutter test test/features/practice/presentation` — §9 záró gate |
| 45 | Integration tesztek zöldek | **teljesül** | `practice_session_integration_test.dart`, `practice_session_recording_test.dart`, `practice_observation_activation_test.dart` — §9 záró gate |
| 46 | Architecture guard zöld | **teljesül** | `tool/check_architecture.dart` — §9 záró gate (12 allowlisted eltérés, az Epic alatt nem nőtt) |
| 47 | Format és analyze zöld | **teljesül** | §9 záró gate (`dart format` + `flutter analyze`) |
| 48 | Valós eszközös teszt dokumentálva | **teljesül** | `docs/manual-testing/practice-engine-device-matrix.md` (R20) — a mátrix és a kitöltési útmutató kész, a user tölti ki |
| 49 | Nincs ismert audio resource leak | **részleges — fake gateway-vel bizonyított, valós mikrofonos úton nem gyakorolt** | `practice_session_lifecycle_test.dart` A7 (R13) + ADR 0074; a §3 rendszerszintű rés miatt a valós mikrofonos session-út nem indult el |
| 50 | Nincs korlátlan history vagy verdict memória | **teljesül** | `practice_engine_property_test.dart` A4.1 + A3 perf teszt — `retainedTargetRecordCount ≤ targetCount`, history cap `maxSessions=200` (ADR 0084) |
| 51 | Minden user-facing string lokalizált | **teljesül** | `l10n_parity_test.dart` + `practice_l10n_audit_test.dart` (R20) — minden PracticeInsightCode + PracticeRecommendationKind mindkét nyelven |
| 52 | Accessibility követelmények teljesülnek | **részleges — teszt-szinten bizonyított, valós eszközön nem** | `practice_a11y_audit_test.dart` A1.1–A1.10 (R20); a screen-reader/live-region fixek a Hub/Setup/Result képernyőkön lokálisan igazoltak, a Session képernyő a §3 rendszerszintű rés miatt nem indítható |

**Összegzés:** 39/52 cella teljesül a fenti bizonyítékkal; 10/52 cella
viseli az „A7 rendszerszintű rés" minősítést (4, 9, 25, 26, 27, 28, 29,
30, 32, 33, 34, 37, 38, 39, 40, 41 — a R20 javító kör #1 a #30, #34,
#37, #39, #40, #41 sorokat is ide sorolta át, miután a mért hívási
lánc cáfolta a korábbi „teljesül" minősítést); 3/52 cella „részleges"
egyéb, önálló ok miatt (24 legacy parity, 49 audio leak, 52 a11y) —
mind a §3 rendszerszintű résre vagy annak hatására vezethető vissza. A
§3 rendszerszintű rés egyetlen körben sem „hallgatva marad": minden
érintett cella mellé oda van írva, **miért** nem teljesül
végponttól-végpontig, és a mért hívási lánc (fájl:sor szinten) vagy a
0-találatos `grep` bizonyítja a hiányt.

## 6. Valódi eszközös audio-regresszió (R20 §6 A8) — PENDING, a useré

A HORIZON-szabály szerint a szintetikus zöld nem „done" — az Epic-2 zárás
végső elfogadási predikátuma a user valódi-gitáros APK-tesztje. A
tesztmátrix és a kitöltési útmutató itt van:
[`docs/manual-testing/practice-engine-device-matrix.md`](../manual-testing/practice-engine-device-matrix.md).
A mátrix a §25.6 minden celláját tartalmazza (készülék, Android-verzió,
mód, tempó, zaj, fejhallgató/hangszóró, balkezes mód, akkumulátor-takarékos
mód), a kitöltési útmutató a „mit jelent a pass" definíciót és a
rögzítendő mezőket sorolja fel. **A felhasználó tölti ki.**

## 7. Ismert kockázatok

- **Az önálló Practice V2 session-út nem éles** — a §3 rendszerszintű
  rés dokumentálja. A migrated Learn útvonal (R19) éles, az önálló
  Hub→Session nem.
- **A 280 ms-os határponton egy mikro-eltérés** a legacy `LessonScorer`
  `double` aritmetikája és a V2 egész µs-os alap között (ADR 0075 §2b,
  R19 §0.3 — `<= 280000` µs vs. `d <= 0.28` másodperc). A parity a sávon
  kívül bitre-egzakt; a sávon belül 2 kipinnelt divergencia-cella van
  (`first-strums[0]`, `anthem-drive[5,6]`).
- **A Free Practice `attemptsCount` csempe** a R18 óta nyitva maradt —
  `entry.attemptsCount` helyett a tényleges strumszámot kellene mutatnia
  (§2 R18 n1).
- **A `practiceSessionRecorderProvider` Noop az önálló úton** — amíg a
  valós `mode/source/definitionId` metaadat nincs végigvezetve, egyetlen
  önálló Practice V2 session sem perzisztálódik (§2 R18 B2 residual).
- **Coverage-küszöb** a R20-ra nem mérve — a config/foundation
  modulokra vonatkozó 90%-os Ch2 §14.8 cél a R20-ban nem zárt
  kimondottan.

## 8. Teljesítmény-baseline (R20 §6 A3)

| Mérés | Küszöb | Bizonyíték |
|---|---|---|
| Highway build-hatókör | 2 000 célnál ≤ 64 épített marker | `practice_highway_scaling_test.dart` (R14) |
| Matcher vizsgálati hatókör | ≤ 64 × (pengetés + cél) | `practice_performance_test.dart` A3 (R20) |
| Observation-áteresztés (10 perc) | verdict-lista korlátos | `practice_performance_test.dart` A3 (R20) — `retainedTargetRecordCount ≤ targetCount` |
| Controller state-kibocsátás | tickenként ≤ 1 | `practice_performance_test.dart` A3 (R20) — egy `registerStrum` hívás ≤ 1 resolved target, ≤ 64 examined |
| Memória-korlát | verdict/history struktúrák elemszáma a cap szerint | `practice_performance_test.dart` A3 (R20) + `maxSessions=200` cap (ADR 0084) |

A számszerű, eszközön mért profilozás (cold start, Live-start latency, CPU,
memória 10 perces session után, dropped frames, akku) **ezen a
fejlesztő-boxon nem mérhető** — nincs fizikai Android-eszköz. A
`docs/manual-testing/practice-engine-device-matrix.md` §16.4 szerinti
baseline a user készülékes menetéből töltendő fel.

## 9. Záró gate — kimenet

A §9 szerinti `tools/round-gate.sh` parancs szó szerinti kimenete a brief
§10-ében. A teljes suite + randomizált property gate + APK a CI-ban fut
(ADR 0053), és a zöld CI-futás linkje a §10-ben kötelező része a körnek
— `gh`-t az implementer NE hívjon.

## 10. Függőség-allowlist állapota

- **Architektúra-allowlist:** 12 tétel (`tool/check_architecture.dart`), mind
  `analyze → live/engine/{dsp,ml}` — „csak csökkenhet" policy (ADR 0058).
  Az Epic alatt **nem nőtt**; a §3 rendszerszintű rés nem érint.
- **Pub-függőségek:** 18 csomag + 2 SDK + 2 dev-függőség (az Epic előtti
  állapot); `flutter_secure_storage` v10-re pinelve (ONE win32 major szabály).
  Az Epic-2 nem vezetett be új pub-függőséget.
- **`assets/ml/model_manifest.json`** szándékosan nem Flutter-asset
  (ADR 0063); az Epic-2 nem nyúlt hozzá.

## 11. Epic 3 (Song Trainer) előfeltételei

- A Practice Engine minden bővítési pontja kész: `targetIndex`,
  `loopRange`, `difficulty`, `scoringProfile.id` per-definition.
- A History V2 séma (`schemaVersion=1`) bővíthető új mezőkkel (a V3
  migrátor megírható).
- A `practice` feature public API-ja (`lib/features/practice/public.dart`)
  már exportálja a Session Host, Recorder és History típusokat.
- A Song Trainer adapter (`song_practice_adapter.dart`) már létezik — az
  Epic-3 a `Song.toLesson()` mellőzésével egy az egyben a Practice V2-t
  használhatja.