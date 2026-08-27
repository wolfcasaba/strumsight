# Screen migration status

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

**43 of 96 production screens migrated (44.8%)**, up from 0/60 at the
E08-R15 baseline (the file count grew from 60 to 96 as Epics 8–13 added
screens — Community, Gamification, Library V2, Progress V2, Offline AI,
Share — most of which shipped already migrated).

## Canonical token source by migration phase

| Phase | Canonical source | Compatibility rule |
| --- | --- | --- |
| E13-R02 foundation | `lib/core/theme/AppColors`, `AppPalette`, and `AppTheme` | `core/design_system` reads the legacy theme through its adapter; it does not copy color values. |
| Component and screen migration (E13-R16…R35) | Design-system component tokens (`SsColorScheme`/`SsTypography` theme extensions, `Ss*` components) | A screen migrates only in its assigned round; all unassigned screens remain on the legacy theme (`AppTheme` / `AppColors` / `AppPalette`). |
| Screens needing design-system extensions without `AppTheme` carrying them | A local `*ThemeScope` (`VisionThemeScope`, `ProgressThemeScope`, `GamificationThemeScope`, `CommunityThemeScope`, `LibraryThemeScope`) | Wraps the screen so its `Ss*` cards resolve `SsColorScheme`/`SsTypography` without registering those extensions on the app's actual runtime `ThemeData` (measured gap, R30 handoff). |

## Per-feature status (measured 2026-08-27)

| Feature | Migrated / total | Legacy screens (migration pending) |
| --- | --- | --- |
| ai_tutor | 1/6 | tutor_chat, tutor_data, tutor_home, tutor_privacy, tutor_profile |
| analyze | 0/1 | analyze |
| audio_analysis | 3/8 | analysis_export, analysis_metric_detail, capture/analysis_home, capture/analysis_processing, capture/analysis_recording |
| auth | 1/1 | — |
| chords | 1/1 | — |
| community | 14/15 | followers |
| gamification | 1/7 | achievement_detail, achievements, level_detail, quests, reward_inbox, streak_detail |
| learn | 0/4 | latency_calibration, learn, lesson_list, lesson_score_preview |
| library | 0/2 | library, session_detail (superseded by `library_v2`, see below) |
| library_v2 | 2/2 | — |
| live | 1/1 | — |
| metronome | 1/1 | — |
| offline_ai | 1/1 | — |
| onboarding | 2/3 | onboarding |
| practice | 2/6 | practice_history, practice_hub, practice_result, speed_builder |
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

See `docs/ui/legacy-backlog.md` for the dated backlog covering the 53
still-legacy screens above, the two dated variant-matrix/closure-suite
exclusion-list defects, and the deferred UI-architecture guard (§0.0.B/B3).

The canonical per-file list of screens, reusable widget/view sources, and
dialog/bottom-sheet sources is the deterministic generator output in
`tool/ui_inventory.dart` (96/119/25, measured 2026-08-27); its test holds
the measured screen count and guards against traversal-order drift.
