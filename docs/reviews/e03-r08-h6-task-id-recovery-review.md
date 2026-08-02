# E03-R08 / H6 — Task-ID baseline recovery review

Branch: `heal/E03-R08-H6-1d`
Diff: `origin/main...heal/E03-R08-H6-1d`
Reviewer: Terra, isolated clone review (ADR 0115 engine fallback)
Date: 2026-08-02
Verdict: APPROVED

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The recovery CLI now resolves only a standalone `E##-R##` identifier to one
brief under the supplied worktree. The parsed brief, task lock and scope audit
remain mandatory after resolution.

## Acceptance evidence

| Criterion | Result | Evidence |
|---|---|---|
| Exact halted input no longer becomes `brief is unreadable`. | ✅ | `RouterCliTest.test_rebase_baseline_preserves_a_scoped_model_diff_after_preflight_commit`. |
| A missing or ambiguous task ID remains fail-closed. | ✅ | `_rebase_brief_path()` accepts exactly one `docs/rounds/<id>-*.md` candidate only. |
| Existing scope enforcement is unchanged. | ✅ | The regression first adds an out-of-scope `lib/forbidden.dart`; recovery still exits 50 and leaves the task `BLOCKED`. |

## Scope and probe

- Isolated clone: `/tmp/review-e03-r08-h6-1d`.
- Changed paths: `tools/model-router.py`, `tools/tests/test_router_cli.py`,
  `HANDOFF.md`, `docs/LESSONS.md`; all are self-heal-authorized.
- `git diff --check origin/main...HEAD` passed.
- Deliberate violation: temporarily restored the previous direct
  `load_brief(args.task)` call. The focused test failed with the measured
  `brief is unreadable: E03-R08` exit-50 result. Restoring the resolver made
  the same test pass; the review clone was clean afterward.

## Merge decision

No BLOCKER or MAJOR remains. This Python-only router repair has no Dart or
Android artifact change, so an APK dispatch is not applicable.
