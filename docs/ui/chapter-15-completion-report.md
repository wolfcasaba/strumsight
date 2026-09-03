# Chapter 15 completion report — E15-R13 (UI closure & release evidence)

**Measured against:** `main @ 9ba54399` + this round's own tree.
**Date:** 2026-09-03.
**Round:** E15-R13, the Chapter 15 (UI-aktiválás és -befejezés) closing round.
**Implementer:** Claude Sonnet 5 (`sonnet-impl`).

## 0. What "done" means for this sáv (brief §0.0)

The Ch15 sáv's záró állítása is **"every screen the user can actually
REACH is on the design system, or is a deliberately retire-planned legacy
screen with a named successor"** — not "96/96 migrated" and not "the
retirement happened." Both halves are measured below, and the second half
(§3) is explicitly still open.

## 1. What this round shipped

- `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` — a PNG-free
  variant matrix over the **MEASURED reachable-screen set** (71) ∪
  `{ProgressDashboardScreen, SkillDetailScreen}` (§0.0.A/R5), minus the one
  screen with no merged pump fixture anywhere in the tree
  (`WrappedPreviewScreen`, §2 below) = **72 screens** × {light, dark} ×
  {en, hu} × {compact portrait 412×915, landscape 915×412} × {textScale
  1.0, 2.0} = **1152 cells**, each asserting no `RenderFlex` overflow and
  no pump exception via `FlutterError.onError`, plus **5 completeness /
  structural cells** (A1) — **1157 tests total, all green** (measured
  locally this session, two commits: 48 "A-level" golden-fixtured screens,
  then the remaining 24 "B-level" `test/features/**`-fixtured screens,
  §8 steps 2–3).
- `docs/ui/legacy-backlog.md` §3 — the stale "53 legacy" table replaced
  with the MEASURED 5, and the `E15-R04` unexecuted retirement recorded as
  an explicit open item (dated, owned, named follow-up round).
- This report.
- No golden PNG was added or changed (this file is PNG-free by
  construction — no `matchesGoldenFile` call anywhere in it).

## 2. Migration + reachability — the MEASURED numbers (§0.0.A/R1)

```bash
total=$(find lib/features -name '*_screen.dart' | wc -l)                     # 96
for f in $(find lib/features -name '*_screen.dart'); do
  grep -q design_system "$f" && echo M
done | wc -l                                                                  # 91
dart run tool/check_screen_reachability.dart --format json
# measuredScreenCount=96 reachableCount=71 unreachableCount=25 flagGatedCount=27
```

- **91 / 96 migrated (94.792%), 5 legacy.** All 5 legacy screens are
  **reachable**, and all 5 carry a `retire` verdict with a named successor
  in `docs/ui/retirement-plan.md` §6 (`library_screen.dart`,
  `session_detail_screen.dart`, `song_list_screen.dart`,
  `song_builder_screen.dart`, `streak_screen.dart` — owner `E15-R04`,
  table reproduced in `legacy-backlog.md` §3).
- **Reachability: 96 measured, 71 reachable, 25 unreachable, 27
  flag-gated.** Zero reachable-and-legacy screen lacks a `migrate`/`retire`
  verdict with a real `E15-Rxx` owner — machine-guarded by
  `test/tooling/screen_reachability_test.dart`'s A3 group (green, this
  session).
- **Fixture coverage** (the matrix's own cost driver, §0.0.A/R3): of the
  71 reachable screens, 46 had an already-merged `test/ui/goldens/**` pump
  fixture, 24 had one under `test/features/**`, and exactly **1**
  (`WrappedPreviewScreen`) had none anywhere — the sole entry left in the
  matrix's screen-coverage exclusion list (`_exclusions` in the test file)
  after the B-level commit.

## 3. OPEN — `E15-R04`'s retirement was never executed

The five `retire`-verdicted legacy screens in §2 are still present, still
reachable, and not deleted or route-redirected — `E15-R04` (the round
`retirement-plan.md` §6 names as owner) closed without performing the
retirement. Per [ADR 0471](../adr/0471-screen-reachability-is-measured-not-assumed.md)
D5 this is not a scope violation (a `retire` verdict is a proposal for a
separate, reviewed round, not deletion authority) — it is recorded as a
dated, owned open item in `docs/ui/legacy-backlog.md` §3.0 (owner: a future
round whose `allowed_paths` covers the five route redirects + file
deletion, SDD, unscheduled; date measured: 2026-09-03).

## 4. The closing variant matrix (A1, A2)

`test/ui/goldens/e15_r13_full_variant_matrix_test.dart`, run locally this
session:

```
flutter test test/ui/goldens/e15_r13_full_variant_matrix_test.dart
# +1157: All tests passed!
```

- **Completeness (A1):** a dedicated test group re-runs
  `ScreenReachability(Directory.current).render()` at test time and
  asserts the measured reachable-screen-path set is a subset of (the 72
  matrix screens ∪ the 1-entry exclusion list). Every exclusion entry is
  machine-checked to carry a non-trivial reason and a named follow-up
  round, and the `"no merged pump fixture"` reason is machine-checked to
  apply to `WrappedPreviewScreen` alone (§0.0.A/R3).
- **Per-cell rendering (A2):** every one of the 1152 screen × variant
  cells sets its OWN `tester.view.physicalSize` + `devicePixelRatio`
  (L558) and asserts zero pump exceptions; overflow-free UNLESS the cell
  is a dated, measured `_ExcludedCell` entry (§5 below) — never `skip`,
  never a raised tolerance (brief §5.1).
- **Threshold triplet (brief §6):** `textScale 1.0` and `textScale 2.0`
  (the mandatory, inclusive threshold) are both fully covered — every one
  of their cells is either green or a dated `_ExcludedCell` finding; no
  cell above 2.0 exists or is referenced.

## 5. Findings — measured `lib/**` layout defects (§5.2: LELET, not fixed)

Four independent, dated, measured overflow defects were found by the
matrix itself. Per brief §5.2, `lib/**` is this round's tilos zona — none
were fixed; all four are recorded as `_ExcludedCell` entries in the test
file (shrink-only, L180) and are new findings not previously tracked
anywhere:

| Screen | Cells affected | Overflow (px) | Likely source |
| --- | --- | --- | --- |
| `StrumReelScreen` | 12 of 16 (all except `landscape\|1.0`, both themes/locales) | 191–935 | `lib/features/share/screens/strum_reel_screen.dart:339` — the tagline `Row` (no `Flexible`/`Expanded`) inside a fixed-aspect-ratio reel card |
| `AnalyzeScreen` | 2 of 16 (`hu\|landscape\|2.0`, both themes) | 36 | `lib/features/analyze/screens/analyze_screen.dart:331` — the mic-error action `Row`, hu-only (longer string) at the least-vertical-room orientation |
| `LatencyCalibrationScreen` | 2 of 16 (`en\|compact_portrait\|2.0`, both themes) | 25 | a fixed-height measurement row that doesn't grow with `textScale` |
| `LearnScreen` | 8 of 16 (every cell at `textScale 2.0`, both themes/locales/viewports) | 26.3 (uniform) | `lib/features/learn/screens/learn_screen.dart:879`'s bottom action `Row` — depends only on `textScale`, not locale/viewport |
| `LessonScorePreviewScreen` | 8 of 16 (every cell at `textScale 2.0`, both themes/locales/viewports) | 366 (uniform) | `lib/features/learn/screens/lesson_score_preview_screen.dart:101` — a fixed-pixel `SizedBox` share-card boundary that doesn't scale with `textScale` |

**32 `_ExcludedCell` entries total.** Each carries the measured px, the
date (2026-09-03), and is machine-verified to still genuinely overflow —
a resolved defect would turn its cell red (`STALE exclusion-list entry`),
not silently stay excluded forever.

## 6. Real-violation probe (brief §6.1/§7, mandatory)

Documented with its actual RED and GREEN output in the round brief's
[§10 handoff](../rounds/e15-r13-ui-closure-and-release-evidence.md#10-implementation-handoff--az-implementer-tölti-ki).

## 7. What this report does NOT claim

- **Not claimed:** the five legacy screens are gone — see §3 (open).
- **Not claimed:** `WrappedPreviewScreen` renders overflow-free at any
  variant — it has no fixture and is excluded from the matrix, not
  measured (§2).
- **Not claimed:** the four `lib/**` defects in §5 are fixed — they are
  measured findings only (§5.2).
- **Not claimed:** CI / APK dispatch ran — that is the orchestrator's step
  (brief §7), linked from the round brief's §10, not this implementer
  round's.

## 8. Report-guard (A5)

`test/ui/goldens/e15_r13_full_variant_matrix_test.dart`'s own `A5 —
completion-report guard` test group re-derives every number in §2/§4/§5
above from the LIVE measurement (`ScreenReachability`, `_screens.length`,
`_excludedCells`) and asserts it is present in THIS file's text — not by
parsing whatever rows happen to be here (L588: a guard that only iterates
present rows stays green on a silently deleted one), but by asserting a
closed-form, independently-derived set of expected facts.
