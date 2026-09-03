# Screen migration status

**E15-R10 javító kör (1. javító menet, 2026-09-03)** — the review
(`docs/reviews/e15-r10-review.md`) measured 1 BLOCKER + 4 MAJOR + 6 MINOR + 1
NOTE against the round below; all fixed, full evidence per lelet in the round
brief's §10.8 (`docs/rounds/e15-r10-analysis-migration.md`). The ratio stays
**86/96 (89.583%)** — no screen left the migrated set. Two component-map
entries below changed shape as part of the fix: `AnalyzeScreen`'s **idle**
phase no longer uses `SsEmptyState` (its own required action would only ever
duplicate the bottom control bar's real "Record" CTA — B1/M4 defect class);
`AnalysisHomeScreen`'s two cards no longer use `SsContentCard` (its fixed
`maxLines`+`ellipsis` silently truncated real user content at `textScaler
2.0` — M1), replaced by a screen-local `_UntruncatedContentCard` built on the
same `SsSurface`/`SsCardActionRegion` primitives, without the line limit.

**E15-R10 update (2026-09-03) — Audio Analysis + Analyze 6 screens migrated,
measured 86/96 (89.583%).** `AnalysisHomeScreen`, `AnalysisRecordingScreen`,
`AnalysisProcessingScreen`, `AnalysisMetricDetailScreen`,
`AnalysisExportScreen`, `AnalyzeScreen` now import `core/design_system`.
Measurement command:
`for f in <the 6 batch paths>; do grep -q design_system "$f" && echo MIGRATED
|| echo legacy; done` — all 6 report `MIGRATED` (§7 of the round brief).

The two `audio_analysis`/`analyze` features have NO `*ThemeScope` wrapper
(§0.0.A/R2, measured — `grep -rn "ThemeScope" lib/features/audio_analysis/
lib/features/analyze/` → 0 hits), so this constraint was a no-op for the
batch; the §3 tiltás (no NEW `*ThemeScope`) is unchanged. Component mapping,
per the batch's mért component-name correction (§0.0.A/R3 — `SsErrorState`/
`SsListTile`/`SsMetricTile` do not exist in the design system):

- **Empty states → `SsEmptyState`.** `AnalysisHomeScreen`'s empty recent-list
  (a real action existed: `onStartRecording`, reused — not fabricated;
  `title`/`message` reuse the existing `analysisHomeRecentSectionTitle`/
  `analysisHomeRecentEmpty` keys, so the standalone section heading now only
  renders in the non-empty branch — no duplicate heading), `AnalyzeScreen`'s
  micDenied phase (a REAL existing action, `openAppSettings`, that the
  pre-migration bespoke Column could not model — `SsEmptyState` fits it
  natively; title fixed in the javító kör to
  `analysisRecordingPermissionDeniedTitle`, so it no longer repeats the
  screen header — see below), and `AnalysisMetricDetailScreen`'s newly-added
  empty case (no metrics AND no insights — previously rendered a blank
  `ListView`, action = close/back via `commonClose` + `Navigator.maybePop`;
  title/message fixed in the javító kör to
  `analysisOverviewUnavailable`/`analysisOverviewNotApplicable`, replacing a
  key pair that misreported an existing document as missing — see the
  javító-kör note above). `AnalyzeScreen`'s **idle** phase was moved OUT of
  this bucket in the javító kör — see the exception-class bullet below.
  **No new ARB key was added this round** (§0.0.A/R7 read the brief's §3
  "new key allowed" permission at face value; measured mid-round that
  `lib/l10n/app_en.arb`/`app_hu.arb` — the two files the brief's
  `allowed_paths` names — are a GENERATED aggregate (ADR 0307 §4,
  `tool/gen_l10n_segments.dart`) assembled from `lib/l10n/base/` +
  `lib/l10n/features/*` fragments, neither of which is on `allowed_paths`;
  a hand-edit to the aggregate is silently overwritten by the gate's own
  `l10n` step. Every new-string need was satisfiable by reusing an existing
  key instead, so no STOP was needed — but a future round adding a GENUINE
  new string here must get the fragment file on its `allowed_paths`, not the
  aggregate).
- **Real failures → `SsFailureState`.** `AnalysisRecordingScreen`'s
  `_RecordingStage.error` branch and `AnalysisProcessingScreen`'s
  `AnalysisInputError`/`AnalysisError` branches carry a real `AppFailure`, so
  `SsFailurePresentation.from(l10n, failure)` renders the code-mapped
  title/message/action instead of the raw `failure.code` string that used to
  leak into the UI on the processing screen.
- **Exception class — no real action/failure available (§0.0.A/R12).**
  `AnalysisRecordingScreen._PermissionDeniedBody` (always shows "retry",
  independent of `retryable` — forcing `SsFailureState`'s code-mapped actions
  here would silently swap the always-available retry for "open settings" on
  a permanently-denied permission, a BEHAVIOUR change, not a visual one),
  `AnalysisProcessingScreen`'s `AnalysisPermissionDenied` branch (no
  `AppFailure` object exists on that state — fabricating one would invent an
  unmeasured code), `AnalyzeScreen`'s `micError` phase (busy-mic copy has
  no action of its own by design — Retry lives in the separate big control
  below, parity with Live r13/Tuner r68; forcing an action here would
  duplicate it), `AnalyzeSkeleton` (loading) and `analyzeNoChords` (the
  empty-result `done` branch). **The javító kör added a fifth member:**
  `AnalyzeScreen`'s **idle** phase — the bottom control bar already offers
  the one real next step (start recording), so `SsEmptyState`'s required
  second action could only ever duplicate it (review B1/M4 defect class);
  moved out of the `SsEmptyState` bucket above into this one. All members
  stay token-styled local widgets (`SsColorScheme`/`SsTypography`/
  `SsSpacing`), not raw `Theme.of(context)`.
- **Loading → the existing `LinearProgressIndicator`, token-coloured.**
  `AnalysisProcessingScreen`'s indeterminate/phase bar is pinned BY TYPE in
  `processing_progress_test.dart` (`tester.widget<LinearProgressIndicator>`)
  — no design-system component reimplements a progress bar, so this one
  keeps its Material type and gains `color: colors.brand` /
  `backgroundColor: colors.surfaceSunken`.
- **`AnalysisMetricDetailScreen` is a SHALLOW migration (§0.0.A/R9, mért
  scope-korlát).** Its full visual body is delegated to two shared widgets —
  `MetricCard` (`widgets/metric_card.dart`) and `InsightCard`
  (`widgets/insight_card.dart`) — that are NOT on this round's
  `allowed_paths` (other screens use them too). Only the screen's own layer
  migrated: scaffold, `ListView` padding/spacing tokens, the new empty state,
  and the "More insights" section header typography. The two cards' own
  design-system migration is a follow-up, tracked here.
- **`AnalyzeScreen`'s `AppColors` references became `SsColorScheme` tokens**
  (the `_BigButton` class was deleted — every call site now wraps `SsButton`
  in a `SizedBox(width: double.infinity, height: 52, ...)`, matching the
  `SsContentCard`/`analysis_export_screen.dart` full-width-CTA precedent).
  The "Save"/"New recording" pair in the `done` phase became
  `SsButtonVariant.secondary`/`.primary` respectively; the two icon-only
  share/practice `IconButton.filledTonal`s were left as Material stock
  widgets (out of scope — they carry no `AppColors`/legacy-token reference,
  and `SsIconButton` requires a NAMED icon-catalog entry that `ios_share`/
  `school_outlined` do not have).

Test-harness theme wiring (§0.0.A/R4 — 6 harnesses were pumping a themeless
`MaterialApp`, which the migrated components' `Theme.of(context)
.extension<...>()!` reads would null-check-crash under): `analyze_cleanup_
test.dart`, `processing_progress_test.dart`, `recording_state_test.dart`,
`mic_error_parity_test.dart`, `analysis_overview_screen_test.dart` (both its
`_harness` and the inline empty-state `MaterialApp`), and
`analysis_export_screen_test.dart` all now pass `theme: SsLightTheme.data()`.
**A seventh spot the brief did not name:** `analysis_overview_screen_test.
dart`'s `_routedHarness` (a THIRD `MaterialApp`-builder in that file, used by
the pre-existing "maximum-policy" test) was ALSO themeless — the gate's first
full run caught it as a real `AnalysisMetricDetailScreen` null-check crash on
a PINNED cell, fixed the same way. Every pre-existing pinned cell (keys,
types, texts) is byte-for-byte unchanged; new cells only ADD coverage (A2
`find.byType(SsEmptyState|SsFailureState)` pins, A3 textScaler-2.0 en+hu
no-overflow cells on all 6 screens — one of which, `AnalyzeScreen`'s idle
state, surfaced a REAL overflow this round fixed with a `SingleChildScrollView`
wrap, since `SsEmptyState` only centers and does not itself reserve scroll
room on a short viewport).

Golden re-record (§0.0.A/R5): both `test/ui/goldens/e13_r26_screens_golden_
test.dart` and `e13_r27_screens_golden_test.dart` switched their shared
`_pump` theme from `AppTheme.dark()` to `SsDarkTheme.data()` (the app's
actual runtime dark theme, `strumsight_app.dart:34` — ADR 0466) and all 14
`e13_r26_*`/`e13_r27_*` PNGs were re-recorded via `tools/golden-x86.sh record
test/ui/goldens/e13_r26_screens_golden_test.dart test/ui/goldens/
e13_r27_screens_golden_test.dart` (exit 0, all 14 cells green). Only the 6
`e13_r26_*` PNGs (the 3 batch screens this round touches, ×2 scales) changed
bytes; all 8 `e13_r27_*` PNGs are byte-identical — `AppTheme.dark()` and
`SsDarkTheme.data()` share the same base `ColorScheme`/`textTheme` (ADR
0466), so a screen that reads no `SsColorScheme`/`SsTypography` extension
(the three already-migrated `e13_r27` screens) or whose migrated code path
isn't exercised by the golden's fixture (`AnalysisMetricDetailScreen`'s
empty-state branch, given the fixture always supplies a non-empty metric
list) renders pixel-identically either way.

**E15-R09 update (2026-09-03) — AI Tutor 5 screens migrated, measured
80/96 (83.333%).** `TutorHomeScreen`, `TutorChatScreen`, `TutorProfileScreen`,
`TutorDataScreen`, `TutorPrivacyScreen` now import `core/design_system`.
Measurement command:
`dart run tool/ui_inventory.dart` (96 total, unchanged — A5) piped through the
round's own `for f in ...; do grep -q design_system "$f" ...` loop over all 96
listed paths, not just the batch — 80/96 confirmed both ways.

The `ai_tutor` feature has NO `*ThemeScope` wrapper (§0.0.A/R2, measured —
unlike `gamification`'s `GamificationThemeScope`), and none was introduced
(§3 tiltás, unchanged). All 5 screens' own pinned tests are now wired with
`theme: SsLightTheme.data()` — including `TutorHomeScreen`'s
(`tutor_home_screen_test.dart`, fixed in the javító kör, §0.0.B/R10 — its
first migration pass left this test's bare `MaterialApp.router` unthemed,
which crashed 2 cells once the screen's own components started reading a
theme extension) — so every screen can use the full theme-extension `Ss*`
catalog, not just the extension-free primitives:

- **`TutorHomeScreen` uses the theme-extension `Ss*` components.**
  `SsModelStatusCard` (which renders `SsProvenanceBadge` internally) replaces
  the screen-local `_ModelStatusCard`/`_ModeChip`, and `SsButton` replaces
  the `FilledButton.icon` CTA. **Correction (§0.0.B/R11 — the first
  migration pass's claim was measured FALSE):** `SsCard`/`SsSurface` are
  **NOT** extension-free — both resolve
  `Theme.of(context).extension<SsColorScheme>()!`/`<SsThemeBehavior>()!` via
  `SsElevation.resolve` (measured: `ss_card.dart:15-17` →
  `ss_surface.dart:42` → `ss_elevation.dart:14-15`, two `!`-reads). Only
  `SsSection` reads no extension. Icons stay raw `Icon(IconData)` for an
  UNCHANGED, independent reason: `SsIcon`'s catalog (`play`/`pause`/
  `settings`/`close`/`check`/`info` + 14 guitar glyphs, measured in
  `ss_icons.dart`) does not cover `smartphone_outlined`/`cloud_outlined`/
  `chat_bubble_outline`/`arrow_back`/`stop_circle_outlined`/
  `download_outlined`/`delete_forever_outlined`/`remove_circle_outline`/`add`
  — an unmapped name resolves to `SsIcon`'s visible "missing glyph" fallback
  mark, which would be a real regression, not a safe substitution. This
  applies to icons on ALL 5 screens.
- **All 5 screens' own pinned tests are on `allowed_paths`**, so the round
  wired `theme: SsLightTheme.data()` directly into the bare `MaterialApp`s in
  the 7 test files this needed (§0.0.A/R3 + §0.0.B/R10 — no `Builder`
  workaround required, since `ai_tutor` has no per-screen theme wrapper to
  sit above/below): `tutor_home_screen_test.dart` (`MaterialApp.router`),
  `tutor_chat_screen_test.dart:196`, `tutor_data_screen_test.dart:247`,
  `tutor_privacy_screen_test.dart:146`, `tutor_profile_screen_test.dart:61`,
  `ai_mode_visibility_test.dart:125` and `:146`,
  `streaming_announcement_test.dart:119`. Every pinned expectation in those
  7 files (widget types, keys, text, semantics labels) was left byte-for-byte
  unchanged; only the `theme:` argument was added. `TutorChatScreen`'s
  AI-mode indicator now uses the real `SsProvenanceBadge` (local/cloud) with
  a fallback-message suffix; its empty-conversation prompt is the
  §0.0.A/R6 exception (no caller-wireable action exists — the real next step
  is typing in the always-visible `TutorComposer`, a different widget this
  one cannot invoke), kept screen-local but `SsColorScheme`/`SsTypography`/
  `SsSpacing`-styled. `TutorDataScreen`'s two `FutureProvider.when` error
  branches (`tutorMemoryFactsProvider`/`tutorConversationsProvider`) are
  `SsFailureState` with a working retry (`ref.invalidate`) — MEASURED
  practically unreachable today (the providers collapse a repository
  `Failure` to an empty list/page rather than rethrowing), so the round
  added `R22-DA8` (a genuine new test forcing the fake repository to
  `throw`) to give this cell REAL gate coverage rather than leaving it an
  untested code path; see §10.1 (real-violation probe) in the round file.
  `TutorPrivacyScreen`'s and `TutorProfileScreen`'s `SwitchListTile`/
  `TextFormField` widgets are UNCHANGED (batch-specific brief note: consent
  switches/copy are ADR 0132's sensitive surface; `TextFormField`'s
  `initialValue`-per-rebuild pattern has no `SsTextField` equivalent without
  introducing new controller-owning state, a behaviour change out of this
  visual-only round's scope) — both screens still gained `SsSection`/
  `SsButton`/`SsSpacing` everywhere else. `TutorDataScreen`'s per-row `Card`s
  became `SsCard` where a bespoke `Padding` wrapper already existed
  (`_MemoryFactRow`); `_ConversationRow`'s `Card`+`ListTile` combo was left
  alone to avoid double-padding a `ListTile`'s own built-in insets.

Golden re-record (§0.0.A/R4): `test/ui/goldens/e13_r29_screens_golden_test.dart`
switched its shared `_pump` theme from `AppTheme.dark()` to
`SsDarkTheme.data()` (the app's actual runtime dark theme) and all 6
`e13_r29_*` PNGs were re-recorded via
`tools/golden-x86.sh record test/ui/goldens/e13_r29_screens_golden_test.dart`
(exit 0, all 6 cells green). Only the 4 Coach Home / Coach Chat PNGs changed
bytes; the 2 Practice Plan Preview PNGs are byte-identical (that screen,
already migrated pre-round, reads no theme-extension widget either way).

**E15-R08 update (2026-09-02) — Gamification 6 screens migrated, measured
75/96 (78.125%).** `AchievementsScreen`, `AchievementDetailScreen`,
`QuestsScreen`, `LevelDetailScreen`, `RewardInboxScreen`, `StreakDetailScreen`
now import `core/design_system`. Kör-számsodródás mérve (§0.0.A/R2): a
`retirement-plan.md` §4 táblája ezt a batch-et `E15-R06`-ba, az `E15-R08`
sorába pedig a Practice + Progress batch-et írja — a tényleges végrehajtás
(`E15-R06` = Setlist + Progress, `E15-R07` = Practice Generator, `E15-R08` =
Gamification) ettől eltért; az irányadó a queue sora és e kör brief-je, a
`retirement-plan.md` NINCS az `allowed_paths`-on, tehát változatlan marad.
`LevelDetailScreen` MÉRTEN `unreachable` (nincs `LevelDetailScreen(` hívás
`lib/`-ben a saját fájlján kívül, megegyezik a `retirement-plan.md` §3.4
tábla verdiktjével) — a migráció mégis bekerült, ugyanaz a döntési osztály,
mint az `E15-R07` hat unreachable Practice Generator képernyője (ADR 0471 D5:
`unreachable` NEM `retire`). A `GamificationThemeScope` burkoló minden
migrált képernyőn MEGMARADT (öt már hordozta, az `AchievementDetailScreen`
most kapta meg elsőként) — mérve: `core/theme/app_theme.dart` csak
`AppPalette`-et ad hozzá a témához, a design-rendszer `SsColorScheme`/
`SsTypography` kiterjesztéseit KIZÁRÓLAG a futásidejű app gyökere
(`lib/app/strumsight_app.dart`, `SsLightTheme`/`SsDarkTheme`) és a
`GamificationThemeScope`-hoz hasonló feature-szintű burkolók biztosítják —
sem az `AppTheme.dark()`-ot használó golden-teszt, sem a burkoló nélküli
`MaterialApp()`-ot pumpáló widget-tesztek nem kapják meg őket. A burkoló
eltávolítása (a brief §0.0.A/R8 eredeti szándéka) ezért ezen a boxon minden
mért harnessben null-check összeomlást okozott volna — a döntés ellentétben
áll R8 szó szerinti szövegével, de annak SAJÁT feltételes kikötését követi
("eltávolítható, HA a képernyő már az app témájából old fel" — ez a feltétel
mérve HAMIS). Egyik státusz-állapotnak sincs valódi akciója (üres lista,
nem-található/rejtett részlet, üres postaláda) → `SsEmptyState`/`SsFailureState`
NEM használt, ugyanaz a kivétel-osztály, mint az E15-R04/R06/R07 precedens —
az állapotok képernyő-lokális, `SsColorScheme`/`SsTypography`/`SsSpacing`
token-stílusú widgetek maradtak. A `_StreakMetricCard` (streak_detail) raw
`Card` típusa VÁLTOZATLAN maradt — a meglévő `streak_detail_screen_test.dart`
`find.byType(Card, skipOffstage: false)` 4-es darabszámot és magasság-mérést
pinnelt rá, ugyanaz a kompromisszum-osztály, mint a `SetlistDetailScreen`
reorderable sorai (E15-R06). A `RewardInboxScreen` `Column`+`Expanded(ListView)`
szerkezete `CustomScrollView`+`SliverList.separated`-re cserélődött (mindkét
ágon, üres ÉS listás állapot) — a régi szerkezet 2.0-ás (hu) és 2.5-ös
szövegskálán ténylegesen túlcsordult telefon-viewporton (110–410 px, mérve),
az `AchievementDetailScreen` `_notFound`/`_hidden` állapota `SingleChildScrollView`-t
kapott ugyanazon okból (2.5-ös hu-n 104 px túlcsordulás mérve) — mindkettő a
§0.0.A/R6 minta-szintű javítási kötelezettség alá esik. Lásd a round `§10`
handoffját a képernyőnkénti kompromisszum-listáért, a valódi-sértés próbáért
és a golden-újrafelvétel mérésért.

**E15-R07 F1 update (2026-09-02, ADR 0491) — 2 of the 6 Practice Generator
screens are now reachable.** `PlanSetupScreen` and `TodayPlanScreen` are
wired behind `practiceGeneratorEnabled` (`nonProd` rollout boundary,
production stays OFF), via the practice hub's one entry point
(`lib/features/practice/presentation/screens/practice_hub_screen.dart`).
This SUPERSEDES the "all 6 screens are unreachable" claim in the F2 note
directly below (written the same round, before F1 landed) for those two
screens only — `PlanPreviewScreen`, `PlanChangeReviewScreen`,
`PlanPrivacyScreen`, `WeeklyPlanScreen` remain `unreachable`: their
providers transitively depend on two seams
(`exerciseCandidateResolverProvider`, `generationPlanInputBuilderProvider`)
that still throw `UnimplementedError` (`retirement-plan.md` §3.2, revised).
See the round's own `§10` handoff for the reachability measurement
before/after and the real-violation probe.

**E15-R07 update (2026-09-01) — Practice Generator 6 screens migrated,
measured 69/96 (71.875%).** `TodayPlanScreen`, `WeeklyPlanScreen`,
`PlanSetupScreen`, `PlanPreviewScreen`, `PlanChangeReviewScreen`,
`PlanPrivacyScreen` now import `core/design_system`. All 6 screens are
`unreachable` per `retirement-plan.md` §3.2 (no route, no construction site
in `lib/app/**` — §0.0.A/R1 pre-flight measurement); the round ran anyway per
the queue's written intent (§0.0.A/R2), same class of decision as the
`E15-R11` batch. `SsButton`/`SsCard`/`SsSkeleton` and `Ss*` tokens replace
raw `Theme.of`/`FilledButton`/`OutlinedButton`/`TextButton`/`Card` and the
`plan_setup_screen.dart:65` raw `CircularProgressIndicator` (now a
`SsSkeleton` pair). No screen in this batch has a genuine `AppFailure`- or
`SsEmptyState`-shaped action (no `SsEmptyState`/`SsFailureState` usage —
same E15-R04-established exception class: a fabricated action would lie
about what the screen can do), so status/empty/message states stay
screen-local, token-styled widgets reading `SsColorScheme`/`SsTypography`
off the theme. The one exception carved for `plan-preview-confirm`
(`plan_preview_screen.dart`): it stays a raw `FilledButton`, not `SsButton`,
because `plan_preview_screen_test.dart`'s own type-pinning cells cast that
key with `tester.widget<FilledButton>(...)` — `SsButton` sets the key on
itself, not on an inner `FilledButton`, so swapping it would fail a frozen
cell. `TodayPlanScreen` gained a `_ScrollableIfShort` wrapper (the
E15-R06-established pattern) after its own new phone-viewport A3 cells
(360×640, `textScaler` 2.0, `en`+`hu`) measured a 104px overflow on the
empty/message/planned-day states; the planned-day button block's
`Spacer()` became a fixed gap because a flex child cannot live inside the
wrapper's scrollable branch (unbounded main axis) — same buttons, same
order, only no longer pinned to the bottom of the viewport. See the round's
own `§10` handoff for the per-screen list and the required real-violation
probe (reverting `_ScrollableIfShort` measured RED on 4 cells, restored to
green).

**E15-R06 update (2026-08-29) — Setlist + Progress 3 screens migrated,
measured 63/96 (65.625%).** `SetlistListScreen`, `SetlistDetailScreen`,
`ProgressScreen` now import `core/design_system`. `SetlistListScreen` uses
`SsContentCard` for each row (single action = open, matching the legacy
`ListTile.onTap`) and `SsEmptyState` for the empty list, with the action
wired to the SAME `_create` callback the FAB already used (§0.0.A/R9 G3 — no
fabricated affordance). `SetlistDetailScreen` uses `SsEmptyState` for the
empty-detail state (action wired to the existing `_addSong` FAB callback)
and `SsButton` for "Play set"; its reorderable song rows keep `Card`/
`ListTile` (retoken color only) because `SsContentCard`'s single-action
model would make the whole row a delete trigger — a behavior change, not a
migration (see the round's `§10` for the full compromise list).
`ProgressScreen`'s empty state (no genuine action exists for an empty
practice log) keeps the E15-R04-established screen-local, token-styled
exception pattern instead of `SsEmptyState`, and additionally cannot call
`Theme.of(context).extension<SsColorScheme>()!` directly at all — it's
reachable through a bare, unthemed `MaterialApp.router` in
`test/features/today/hub_navigation_test.dart` (frozen zero-diff S11 guard)
that never installs `SsLightTheme.data()`, and every styled `Ss*` component
force-unwraps that extension internally. The screen resolves tokens through
a local fallback function (`Theme.of(context).extension<SsColorScheme>() ??
SsColorScheme.forBrightness(...)`) instead — not a `*ThemeScope` wrapper (§0.0
prohibits introducing a new one). Two new ARB keys were added, `en`+`hu`
together: `setlistsEmptyTitle`, `setlistEmptyDetailTitle` (the design
system's `SsEmptyState` requires a title separate from the existing
single-string message; the pre-existing string is kept verbatim as
`message`, so no wording was lost or changed). See the round's own `§10`
handoff for the measured pre-existing `weekly_bars.dart` overflow this
round's new textScaler cells surfaced (out of this round's allowed paths,
not fixed here).

**E15-R05 update (2026-08-29) — Song Trainer 9 screens migrated, measured
60/96 (62.5%).** `SongTrainerScreen`, `SongOverviewScreen`, `SongResultScreen`,
`TrainerSetupScreen`, `SetlistSessionScreen`, `SongEditorScreen`,
`SongImportScreen`, `SongImportPreviewScreen`, `SongLibraryScreen` now import
`core/design_system` (`SsCard`/`SsButton`/`SsSkeleton`/`SsSpacing`/
`SsTypography`/`SsColorScheme` replace the raw `Theme.of`/`CircularProgressIndicator`
references — no `SsEmptyState`/`SsFailureState` on this batch: none of the
9 screens' failure/empty states carry a genuine `AppFailure` with a
`retryable` flag or a pre-existing action, so each keeps a screen-local,
token-styled state widget instead of fabricating one, mirroring the
E15-R04-established `_HistoryError`/`_EmptyCatalogLayout` exception pattern
— see the round's own `§10` handoff for the full list). **Owner-round
correction against `retirement-plan.md` §4 (§0.0/R9):** that table's owner-round
column assigns these 8 Song Trainer screens (`setlist_session` excluded, see
below) to `E15-R09`, and `E15-R05` to AI Tutor — the queue and every written
brief instead run `E15-R05` = Song Trainer, `E15-R09` = AI Tutor. The
`migrate` DECISION is unchanged, only which round executed it differs;
`retirement-plan.md` itself is out of this round's allowed paths and is not
edited here (same pattern as the E15-R04 entry below).

**ARB-source correction (measured this round, corrected in the fix round —
§0.0/R12, review m/n7):** `lib/l10n/app_en.arb`/`app_hu.arb` are GENERATED
output (`tool/gen_l10n_segments.dart`, a deterministic union of
`lib/l10n/base/app_<locale>.arb` and `lib/l10n/features/<feature>_<locale>.arb`
fragments) — editing them directly is reverted by the round's own `l10n` gate
step. `lib/l10n/base/app_<locale>.arb` is the true source and, after
§0.0/R12, IS on this round's `allowed_paths`. The round's A6 (no hardcoded
string in the 9 files) was met by a mix: 3 of the 6 measured hardcoded
sentences already had an exact pre-existing ARB match (`songTrainerTitle`,
`songTrainerOverlayCountIn`, `songTrainerSpeedDisabledReason`); the fix round
added two new base keys (`songTrainerSpeedResumesOnRestart`,
`songTrainerSpeedLabel`) for the two that had no pre-existing equivalent
without changing meaning; `songTrainerFailed` (differently-worded, same
meaning as the pre-migration "Failed: {code}") was kept as a reuse — see the
round's `§10` handoff.

**E15-R04 update (2026-08-29) — Practice + Learn 8 screens migrated,
measured 51/96 (53.1%).** `PracticeHubScreen`, `PracticeResultScreen`,
`PracticeHistoryScreen`, `SpeedBuilderScreen`, `LearnScreen`,
`LessonListScreen`, `LessonScorePreviewScreen`, `LatencyCalibrationScreen`
now import `core/design_system` (`SsCard`/`SsButton`/`SsEmptyState`/
`SsFailureState`/`SsSkeleton` and `Ss*` tokens replace the raw `Theme.of`/
`AppColors` references and `core/widgets/empty_state.dart`). **Owner-round
correction against `retirement-plan.md` §4:** that table's owner-round
column assigns these 8 screens to `E15-R07` (Learn + Onboarding, 5 rows) and
`E15-R08` (Practice + Progress, 5 rows) — `E15-R04` executed the `migrate`
decision for 8 of those 10 rows early (all except `OnboardingScreen` and
`ProgressScreen`, which remain `E15-R07`/`E15-R08` work). The `migrate`
DECISION in `retirement-plan.md` is unchanged; only which round executed it
differs — `retirement-plan.md` itself is out of this round's allowed paths
and is not edited here.

```bash
find lib/features -name '*_screen.dart' | wc -l
for f in $(find lib/features -name '*_screen.dart' | sort); do
  grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"
done | grep -c '^MIGRATED'
```

Measured: 96 total, 51 migrated.

**E15-R03 update (2026-08-28) — reachability is now MEASURED, not counted by
router presence.** `tool/check_screen_reachability.dart` (ADR 0471) replaces
the "migrated/legacy" split below as the input to Ch15 round planning — see
`docs/ui/retirement-plan.md` for the full per-screen decision table
(migrate / retire / keep / unreachable) and named `E15-R04`…`E15-R11` owner
rounds. Measure it yourself with:

```bash
dart run tool/check_screen_reachability.dart --format table
```

Measured totals: **68/96 screens reachable** (declarative router reference OR
imperative construction anywhere in `lib/`), **28/96 unreachable**, **25/96**
reachable only behind a feature flag today. Of the 68 reachable screens, 27
are already migrated (`keep`, no Ch15 action) and 41 are legacy — 35 get a
`migrate` round, 6 get a `retire` proposal (`retirement-plan.md` §5).

**This measurement corrects one claim below.** The "Superseded pairs measured
this round" list under the E13-R36 section (unchanged historical text) states
the `progress` ↔ `progress_v2` pair is "both still reachable". Measured now:
**false** — `lib/app/routing/app_router.dart` builds the legacy
`ProgressScreen` for both `/progress` and `/profile/progress`;
`ProgressDashboardScreen` and `SkillDetailScreen`
(`lib/features/progress_v2/screens/`) have no declarative reference and no
construction site anywhere in `lib/`. See `retirement-plan.md` §3.1. The
`library` ↔ `library_v2` and `streak` ↔ gamification-hub pairs in that same
list ARE confirmed still accurate by this round's measurement.

Also newly measured (not previously documented): the entire Community feature
(15 screens, `communityEnabled` flag) has no route registered anywhere in
`lib/app/routing/**`, and Practice Generator (6 screens) plus the Audio
Analysis V2 capture wizard (3 screens) have no measured entry point either —
`retirement-plan.md` §3.2–§3.4.

**E15-R01 update (2026-08-28):** the app's runtime theme (`MaterialApp.theme`
/ `darkTheme`, and the bootstrap-failure recovery screen) is now
`SsLightTheme.data()` / `SsDarkTheme.data()` instead of legacy
`AppTheme.light()`/`AppTheme.dark()` (ADR 0466 D1–D4). **This changes
what "token availability" means, not what "migrated" means below:** all
**96/96** production screen sources can now resolve `SsColorScheme` /
`SsTypography` / `SsStateOverlays` / `SsThemeBehavior` from
`Theme.of(context)` without any feature-level wrapper, because those
extensions now live on the app's actual `ThemeData` (measured by
`test/app/theme_adoption_test.dart`'s A6 cell, which pins the count to
`Directory('lib/features').listSync(...)` — currently 96, matching
`tool/ui_inventory.dart`). The **"Per-feature status" table below is
UNCHANGED by this round**: it counts screens that import
`core/design_system` (directly or via a `*ThemeScope`), which is a
component-migration measurement, not a token-availability one — a legacy
screen not yet touched by a migration round still renders with
`AppTheme`-driven, non-`Ss*` widgets even though the tokens it *could* read
off the theme are now there. The color/typography *values* are unchanged
(ADR 0466 D2, additive-only adoption): `SsLightTheme.data()` /
`SsDarkTheme.data()` still derive from the legacy `AppPalette`/`AppColors`,
so this round does not itself move any screen between "migrated" and
"legacy" in the table below.

**Chapter 13 closure measurement (E13-R36, 2026-08-27), `main @ 126d0dfc`.**
Supersedes the E08-R15 snapshot below the fold: this table replaces the
"all legacy" baseline with the MEASURED post-migration state after
`E13-R01`–`E13-R35`.

`dart run tool/ui_inventory.dart` still reports the canonical file counts —
**96 production screen sources**, 119 reusable widget/view sources, 25
dialog/bottom-sheet sources — but its own "Baseline status" column is a
static E13-R01 label, not migration-aware (it does not look at each
screen's imports). The migration column below is measured separately:

```bash
for f in $(find lib/features -name '*_screen.dart' | sort); do
  grep -q design_system "$f" && echo "MIGRATED $f" || echo "legacy $f"
done
```

A screen counts as **migrated** when it imports `core/design_system`
(directly, or through a per-feature `*ThemeScope` — the R30/R31/R32/R33/R34
pattern for screens whose cards need `SsColorScheme`/`SsTypography` but
whose runtime theme is still `AppTheme`, per those rounds' golden-file
comments). It does not certify that every widget on the screen uses a
design-system component, only that the screen's own migration round ran.

## Measured total

**69 of 96 production screens migrated (71.875%)** as of E15-R07, up from
63/96 (65.625%) after E15-R06, 60/96 (62.5%) after E15-R05, 51/96 (53.1%)
after E15-R04, 43/96 (44.8%) before E15-R04, and 0/60 at the E08-R15
baseline (the file count grew from 60 to 96 as Epics 8–13 added screens —
Community, Gamification, Library V2, Progress V2, Offline AI, Share — most
of which shipped already migrated).

## Canonical token source by migration phase

| Phase | Canonical source | Compatibility rule |
| --- | --- | --- |
| E13-R02 foundation | `lib/core/theme/AppColors`, `AppPalette`, and `AppTheme` | `core/design_system` reads the legacy theme through its adapter; it does not copy color values. |
| Component and screen migration (E13-R16…R35) | Design-system component tokens (`SsColorScheme`/`SsTypography` theme extensions, `Ss*` components) | A screen migrates only in its assigned round; all unassigned screens remain on the legacy theme (`AppTheme` / `AppColors` / `AppPalette`). |
| Screens needing design-system extensions without `AppTheme` carrying them | **MEASURED OBSOLETE as of E15-R01.** A local `*ThemeScope` — the **nine** wrappers on the tree are `ProgressThemeScope` (progress_v2), `AuthThemeScope` (auth), `SettingsThemeScope` (settings), `LibraryThemeScope` (library_v2), `ShareThemeScope` (share), `GamificationThemeScope` (gamification), `CommunityThemeScope` (community), `OfflineAiThemeScope` (offline_ai), `VisionThemeScope` (vision) | Wrapped the screen so its `Ss*` cards could resolve `SsColorScheme`/`SsTypography` when those extensions were NOT yet on the app's runtime `ThemeData` (the gap this row used to describe). Since E15-R01 the app's actual `ThemeData` carries all four extensions directly (ADR 0466 D1), so the wrapper is now redundant for every screen it wraps — but the wrappers themselves are NOT removed by this round (tilos zóna, `lib/features/**`); their retirement is a per-screen follow-up round's job. |

## Per-feature status (measured 2026-08-27, learn/practice rows updated 2026-08-29 by E15-R04, song_trainer row updated 2026-08-29 by E15-R05, progress/songs rows updated 2026-08-29 by E15-R06, practice_generator row updated 2026-09-01 by E15-R07, analyze/audio_analysis rows updated 2026-09-03 by E15-R10 — ai_tutor/gamification rows below are NOT updated by their own migration rounds (E15-R09/E15-R08 did not touch this table) and stay stale until a future round measures them)

| Feature | Migrated / total | Legacy screens (migration pending) |
| --- | --- | --- |
| ai_tutor | 1/6 | tutor_chat, tutor_data, tutor_home, tutor_privacy, tutor_profile |
| analyze | 1/1 | — |
| audio_analysis | 8/8 | — |
| auth | 1/1 | — |
| chords | 1/1 | — |
| community | 14/15 | followers |
| gamification | 1/7 | achievement_detail, achievements, level_detail, quests, reward_inbox, streak_detail |
| learn | 4/4 | — |
| library | 0/2 | library, session_detail (superseded by `library_v2`, see below) |
| library_v2 | 2/2 | — |
| live | 1/1 | — |
| metronome | 1/1 | — |
| offline_ai | 1/1 | — |
| onboarding | 2/3 | onboarding |
| practice | 6/6 | — |
| practice_generator | 6/6 | — |
| practice_hub | 1/1 | — |
| profile_hub | 1/1 | — |
| progress | 1/1 | — |
| progress_v2 | 2/2 | — |
| settings | 3/3 | — |
| share | 3/3 | — |
| song_trainer | 9/9 | — |
| songs | 2/4 | song_builder, song_list (`retire`-verdiktűek, §0.0.A/R2 — nem ennek a körnek a hatásköre) |
| streak | 0/1 | streak (superseded by `gamification`'s hub, see below) |
| today | 1/1 | — |
| tuner | 1/1 | — |
| vision | 1/4 | guitar_calibration, vision_session, vision_setup |

**Superseded pairs measured this round** (the legacy screen and its
migrated successor both still compile and are both still reachable —
`test/app/navigation/legacy_route_redirect_test.dart` is the machine guard
that the eleven Ch13 §7.5 legacy routes redirect to their adaptive-shell
target only when `adaptiveShellEnabled` is on; with the flag off, the
legacy screen is still the live one):

- `library/library_screen.dart` + `library/session_detail_screen.dart` →
  `library_v2/unified_library_screen.dart` + `library_item_detail_screen.dart`.
- `streak/streak_screen.dart` → `gamification/gamification_hub_screen.dart`
  (the hub is migrated; `streak_detail_screen.dart` itself is still legacy).

**E15-R06 correction:** `progress/progress_screen.dart` → `progress_v2/
progress_dashboard_screen.dart` is REMOVED from the superseded-pairs list
above. `progress_v2` was never actually a live successor — per the
retirement-plan (§0.0.A/R2 measurement, `docs/ui/retirement-plan.md` §3.1)
`ProgressDashboardScreen` has no route and no construction site anywhere in
`lib/`, so the retirement-plan's verdict for `ProgressScreen` is `migrate`
(not `retire`), and E15-R06 executed it: the legacy screen is now the
migrated, actively-reachable one (`progress` row above, 1/1) while
`progress_v2` (2/2 in its own row) remains orphaned/unreachable.

**Not yet superseded — full feature migration still pending:** `learn`,
`songs`, `analyze`. `song_trainer` is fully migrated as of E15-R05 (9/9); it
is notable because despite its name suggesting a V2 rewrite of `songs`, the
"V2" there was an architecture rewrite (E09), not a Chapter 13 design
migration — `songs` (the pre-V2 feature, 0/4) remains separately legacy.
`practice_generator` reached 6/6 (migration) as of E15-R07 F2. **E15-R07 F1
update (2026-09-02, ADR 0491), same round:** 2 of the 6 — `PlanSetupScreen`,
`TodayPlanScreen` — are now also reachable, flag-gated behind
`practiceGeneratorEnabled`, via the practice hub's one entry point. The
other 4 remain `unreachable` per `retirement-plan.md` §3.2 (revised): their
providers transitively depend on two seams
(`exerciseCandidateResolverProvider`, `generationPlanInputBuilderProvider`)
that still throw `UnimplementedError` — a real seam, not an oversight, and
out of this round's STOP-protocol scope. Fully migrated was never the same
claim as reachable-and-migrated; now 2/6 are both.

## Legacy route safety (A6)

The eleven Ch13 §7.5 legacy routes and their adaptive-shell redirect
targets are already documented and machine-guarded — not repeated here:
`test/app/navigation/legacy_route_redirect_test.dart` pins the redirect map
(no self-edge, no value also a key, every value reachable, exact key set)
and `test/app/routing/app_router_test.dart` covers the plain (non-adaptive)
legacy deep links (`/streak`, `/progress`) directly. Both suites are green
on this tree (measured via this round's `flutter test` runs of each file).

## Token debt

The pre-migration token-debt baseline is `docs/ui/baseline/token-debt.md`
(tilos zona for this round — referenced, not edited).

## Remaining gap

See `docs/ui/legacy-backlog.md` for the dated backlog covering the
still-legacy screens above (45 as of E15-R04, down from 53 — that file
itself is outside this round's allowed paths and is not edited here), the
two dated variant-matrix/closure-suite exclusion-list defects, and the
deferred UI-architecture guard (§0.0.B/B3).
As of E15-R03, `docs/ui/retirement-plan.md` is the canonical per-screen
REACHABILITY decision table (migrate / retire / keep / unreachable, with
named `E15-R04`…`E15-R11` owner rounds) — the "Per-feature status" table
above only ever measured design-system import presence, not whether a user
can reach the screen at all.

The canonical per-file list of screens, reusable widget/view sources, and
dialog/bottom-sheet sources is the deterministic generator output in
`tool/ui_inventory.dart` (96/119/25, measured 2026-08-27); its test holds
the measured screen count and guards against traversal-order drift.
