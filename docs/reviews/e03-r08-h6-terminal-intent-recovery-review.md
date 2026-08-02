# E03-R08 / H6 — Router terminal-intent recovery review

Branch: `heal/E03-R08-H6-1c`
Diff: `origin/main...heal/E03-R08-H6-1c`
Reviewer: Terra, isolated clone review
Date: 2026-08-02
Verdict: APPROVED

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The change is limited to the explicit `rebase-baseline` recovery. It clears
only the obsolete, already-finalized Terra terminal intent after the existing
locked scope audit succeeds; it retains the reservation and attempt history.

## Acceptance criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | A rebase cannot leave a stale Terra `BLOCKED` intent that a later resume replays. | ✅ | `tools/model-router.py:97`; CLI regression test. |
| 2 | Scope enforcement remains fail-closed. | ✅ | The test first adds `lib/forbidden.dart`; rebase exits 50 and remains `BLOCKED`. |
| 3 | Terra audit history is retained. | ✅ | The test asserts `terra_reservation` remains while both terminal-intent fields are absent. |

## Scope audit

Implementation diff contains only `tools/model-router.py` and
`tools/tests/test_router_cli.py`; both are authorized self-heal router paths.

## Independent evidence

- Fresh clone: `/tmp/review-e03-r08-h6-1c`
- `/tmp/ss-heal-rvenv/bin/python -m pytest tools/tests -q` → pass.
- `git diff --check origin/main...HEAD` → pass.
- Deliberate probe: temporarily removed the two terminal-intent `pop()` calls;
  the focused CLI regression failed because `terra_terminal_status` remained
  in the returned `READY_FOR_REVIEW` state. Restored the calls; the same test
  passed.
- Router CI: [run 30769461874](https://github.com/wolfcasaba/strumsight/actions/runs/30769461874) → success on the implementation commit.

## Merge decision

No open BLOCKER or MAJOR remains. This is a Python-only router repair; no Dart
or Android artifact changed, so an APK dispatch is not applicable.
