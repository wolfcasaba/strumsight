# E03-R08 / H6 — Stale router baseline recovery review

Task: ADR 0112 self-heal, E03-R08 H6
Diff: `73e559d...heal/E03-R08-H6-1`
Reviewer: Terra fallback · Date: 2026-08-02
Verdict: APPROVED

## Review conditions

The primary Claude reviewer was unavailable because of its documented quota
hold. The fallback reviewer repeated the review in a fresh isolated clone at
`/tmp/review-E03-R08-H6-1-final`; no production file was edited during that
review.

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The change does not relax a guard or discard a model diff. It permits a
`BLOCKED` task baseline to advance only when the old baseline was clean. It
then re-runs the normal scope audit before changing state to
`READY_FOR_REVIEW`.

> **Runtime correction (2026-08-02):** the first merged version also required
> the stale head to be an ancestor. The real `8c084268` → `f023b89` recovery
> showed that a reusable worktree can be recreated on a different lineage.
> The follow-up removes that non-security condition and adds a pruned-history
> regression; the complete current-worktree allowlist audit remains mandatory.

## Acceptance evidence

| # | Requirement | Result | Evidence |
|---|---|---|---|
| 1 | Persisted baseline can move past committed pre-flight drift. | ✅ | `rebase_workspace_manifest()` plus `SecurityTest::test_rebased_manifest_excludes_committed_preflight_drift_but_keeps_model_diff` |
| 2 | Existing model diff stays subject to allowlist audit. | ✅ | `RouterCliTest::test_rebase_baseline_preserves_a_scoped_model_diff_after_preflight_commit` |
| 3 | An out-of-scope diff cannot change the task to ready. | ✅ | Same CLI test injects `lib/forbidden.dart`, verifies exit 50 and persisted `BLOCKED`, then removes only the disposable fixture and verifies the allowed case. |
| 4 | Task-state update is locked and does not reset attempt counters. | ✅ | `tools/model-router.py:rebase_blocked_task_baseline`; task-lock is held for load/audit/save and no attempt field is changed. |

## Scope audit

Changed files are the recovery primitive, its CLI bridge, two regression tests,
and required handoff/lesson documentation. No gate artefact, workflow, or
existing test was removed or weakened.

## Verification

| Check | Result |
|---|---|
| `python3 -m py_compile tools/ai_router/security.py tools/model-router.py` | ✅ |
| `python -m pytest tools/tests -q` in isolated clone | ✅ (full tools test suite) |
| `git diff --check 73e559d...HEAD` | ✅ |
| Scope list against `73e559d...HEAD` | ✅; six expected files only before this report |

## Merge decision

No open BLOCKER or MAJOR. The Python/router self-heal gate is ready for PR CI.
No APK dispatch is required because the diff contains no Dart or Android code.
