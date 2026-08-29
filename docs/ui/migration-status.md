# Screen migration status

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

**51 of 96 production screens migrated (53.1%)** as of E15-R04, up from
43/96 (44.8%) before this round and 0/60 at the E08-R15 baseline (the file
count grew from 60 to 96 as Epics 8–13 added screens — Community,
Gamification, Library V2, Progress V2, Offline AI, Share — most of which
shipped already migrated).

## Canonical token source by migration phase

| Phase | Canonical source | Compatibility rule |
| --- | --- | --- |
| E13-R02 foundation | `lib/core/theme/AppColors`, `AppPalette`, and `AppTheme` | `core/design_system` reads the legacy theme through its adapter; it does not copy color values. |
| Component and screen migration (E13-R16…R35) | Design-system component tokens (`SsColorScheme`/`SsTypography` theme extensions, `Ss*` components) | A screen migrates only in its assigned round; all unassigned screens remain on the legacy theme (`AppTheme` / `AppColors` / `AppPalette`). |
| Screens needing design-system extensions without `AppTheme` carrying them | **MEASURED OBSOLETE as of E15-R01.** A local `*ThemeScope` — the **nine** wrappers on the tree are `ProgressThemeScope` (progress_v2), `AuthThemeScope` (auth), `SettingsThemeScope` (settings), `LibraryThemeScope` (library_v2), `ShareThemeScope` (share), `GamificationThemeScope` (gamification), `CommunityThemeScope` (community), `OfflineAiThemeScope` (offline_ai), `VisionThemeScope` (vision) | Wrapped the screen so its `Ss*` cards could resolve `SsColorScheme`/`SsTypography` when those extensions were NOT yet on the app's runtime `ThemeData` (the gap this row used to describe). Since E15-R01 the app's actual `ThemeData` carries all four extensions directly (ADR 0466 D1), so the wrapper is now redundant for every screen it wraps — but the wrappers themselves are NOT removed by this round (tilos zóna, `lib/features/**`); their retirement is a per-screen follow-up round's job. |

## Per-feature status (measured 2026-08-27, learn/practice rows updated 2026-08-29 by E15-R04)

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
| practice_generator | 0/6 | plan_change_review, plan_preview, plan_privacy, plan_setup, today_plan, weekly_plan |
| practice_hub | 1/1 | — |
| profile_hub | 1/1 | — |
| progress | 0/1 | progress (superseded by `progress_v2`, see below) |
| progress_v2 | 2/2 | — |
| settings | 3/3 | — |
| share | 3/3 | — |
| song_trainer | 0/9 | setlist_session, song_editor, song_import_preview, song_import, song_library, song_overview, song_result, song_trainer, trainer_setup |
| songs | 0/4 | setlist_detail, setlist_list, song_builder, song_list |
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
- `progress/progress_screen.dart` → `progress_v2/progress_dashboard_screen.dart`.
- `streak/streak_screen.dart` → `gamification/gamification_hub_screen.dart`
  (the hub is migrated; `streak_detail_screen.dart` itself is still legacy).

**Not yet superseded — full feature migration still pending:** `learn`,
`practice_generator`, `song_trainer`, `songs`, `analyze`. `song_trainer` is
notable: despite its name suggesting a V2 rewrite of `songs`, none of its
nine screens import `core/design_system` yet — the "V2" here was an
architecture rewrite (E09), not a Chapter 13 design migration.

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
