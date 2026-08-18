# E07-R24 — Correctness review

Brief: `docs/rounds/e07-r24-song-goal-integration.md`  
Diff: `git diff 2dd27bed..1da19b7d` (`minimax/e07-r24-song-goal-integration`)  
Reviewer: Codex / Terra orchestrátor · Dátum: 2026-08-18  
Verdikt: **APPROVED** — F1 MAJOR fixed in `1da19b7d` and independently remeasured.

## Összegzés

BLOCKER: 0 · MAJOR: 1 (**FIXED**) · MINOR: 0 · NOTE: 2

The review used two fresh isolated clones directly from origin: `05f0f45f` for the first review and `1da19b7d` after repair. Both scope audits passed. The reviewer’s ratio-cap mutation (`0.4` → `1.0`) made two A1 cells fail, then was reverted inside the review clone; the branch was not changed.

## Acceptance criteria

| # | Result | Evidence |
|---|---|---|
| A1 | ✅ | A1 cells; ratio-cap mutation made the overflow test return 3 instead of 2 assignments. |
| A2 | ✅ | A2 and signed `-1` cell return `SongGoalPlanningNoOpAfterTarget`. |
| A3 | ✅ | Producer-first cell; no-producer input has explicit `unsatisfiedPrerequisite` drop and no assignment. |
| A4 | ✅ | New-skill drop and known-skill keep simulation cells. |
| A5 | ✅ | Reader A5 cells and explicit `missingUsableAsset` drop. |
| A6 | ✅ | Stale-revision reader and propagation cells. |
| A7 | ✅ | Architecture gate; adapter imports only `features/song_trainer/domain/public.dart`. |
| A8 | ✅ | Completed/partial carry evidence; skipped/technical/unavailable do not. |

## Scope-audit

```text
Legacy scope audit OK (2dd27bed..1da19b7d, 8 changed path(s), 0 generated/ignored)
```

No production paths outside the brief were changed. This review file is the scope-audit generated/ignored exception.

## Megállapítások

### F1 — MAJOR — A hiányzó prerequisite csak annotáció volt, miközben a dalblokk mégis ütemeződött

- **Affected:** `song_goal_planner.dart:615-634` in the initial `05f0f45f` implementation.
- **Reproduction:** a temporary reviewer test expected no assignment for a `pentatonic-scale` prerequisite with no producer; the initial code failed with `Actual: [Instance of 'SongGoalPhaseAssignment']`.
- **Fix:** `1da19b7d` tracks caller-known and previously accepted producer skills. An unresolved prerequisite now yields `SongGoalDropReason.unsatisfiedPrerequisite`; it never creates an assignment.
- **Independent closure:** the durable no-producer A3 test passes with an empty assignment list and typed drop; the reversed producer/dependent test verifies the producer is strictly first.
- **Status:** **FIXED** (`1da19b7d`).

### N1 — NOTE — No public section-to-asset mapping exists yet

ADR 0318 deliberately forbids guessing this mapping. A real `SongDocument` therefore reaches explicit `missingUsableAsset`, not a false success. A later Song Trainer-side public-contract round must add a tested section-asset/hotspot contract before end-to-end song blocks can start.

### N2 — NOTE — Two phase-policy knobs are not yet behaviorally wired

`foundationWindowDays` and `integrationWindowDays` do not affect `_phaseForDistance`; only the signed target-day and `lightReviewWindowDays` branches are measured. There is no production consumer, so this is non-blocking; later policy wiring should either use the fields with boundary tests or remove them.

## Gate-bizonyíték

On exact `1da19b7d`, in fresh `/tmp/review-e07-r24-r1`:

```text
tools/round-gate.sh test/features/practice_generator/song_goal/song_goal_planner_test.dart test/features/practice_generator/song_goal/song_goal_reader_adapter_test.dart
```

Format, analyze, 15 planner tests, 7 reader tests, architecture, secrets, and l10n all passed.

## Merge-döntés

No BLOCKER or open MAJOR remains. Correctness review permits merge once the exact final-SHA Full Gate and Router CI are green and the required security delta-review passes.
