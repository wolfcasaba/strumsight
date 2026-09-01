# Screen migration status

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

## Per-feature status (measured 2026-08-27, learn/practice rows updated 2026-08-29 by E15-R04, song_trainer row updated 2026-08-29 by E15-R05, progress/songs rows updated 2026-08-29 by E15-R06, practice_generator row updated 2026-09-01 by E15-R07)

| Feature | Migrated / total | Legacy screens (migration pending) |
| --- | --- | --- |
| ai_tutor | 1/6 | tutor_chat, tutor_data, tutor_home, tutor_privacy, tutor_profile |
| analyze | 0/1 | analyze |
| audio_analysis | 3/8 | analysis_export, analysis_metric_detail, capture/analysis_home, capture/analysis_processing, capture/analysis_recording |
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
`practice_generator` reached 6/6 as of E15-R07 — but per `retirement-plan.md`
§3.2 (re-confirmed §0.0.A/R1), all 6 screens are `unreachable`: fully
migrated is not the same claim as reachable-and-migrated.

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
