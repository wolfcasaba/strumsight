# E03-R09/H6 — Review

Brief: ADR 0112 self-heal prompt for E03-R09/H6
Diff: `origin/main...heal/E03-R09-H6-1` (`9e4e850`)
Reviewer: Codex/Terra, isolated `/tmp/review-heal-e03-r09-h6` clone
Date: 2026-08-03
Verdict: APPROVED (merge remains conditional on exact-HEAD CI)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The measured root cause is reproduced by the regression: a clean Flutter
worktree has no ignored localization output, so baseline analyze fails before
the first model attempt. The change generates only Flutter prerequisites in
the baseline phase; the source-changing post-model normalizer remains absent.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A clean-worktree baseline no longer fails for missing localization output. | ✅ | Isolated clone: `_gate_runner(..., baseline=True)` → `baseline_outcome=pass`; generated l10n output exists. |
| 2 | Baseline preparation does not run `dart fix`. | ✅ | `GateNormalizeTest.test_baseline_gate_generates_flutter_l10n_without_normalizing`; isolated run reported `baseline_ran_dart_fix=False`. |
| 3 | The recurrence is covered by a regression test. | ✅ | `tools/tests/test_router_gate_normalize.py`, the named test was RED before the implementation and GREEN afterwards. |
| 4 | Scope/gate policy is not weakened. | ✅ | `tools/round-gate.sh`, `.github/workflows/`, router scope-audit and redaction are absent from the diff; `git diff --check` is clean. |

## Scope-audit

The self-heal authority permits router, tests and required documentation. The
isolated clone's `git diff --name-only origin/main...HEAD` contained exactly:

- `HANDOFF.md`
- `docs/LESSONS.md`
- `tools/model-router.py`
- `tools/tests/test_router_gate_normalize.py`

No prohibited router configuration, pipeline queue, gate artifact or workflow
path changed.

## Adversarial probes

- Direct gate without router bootstrap is retained as the RED companion test
  `test_without_normalize_the_same_worktree_would_have_stopped_on_analyze`.
- The new baseline test uses an l10n-enabled fresh fake repo and verifies both
  sides of the boundary: generated localization output must exist, while the
  `dart fix` marker must not exist.
- A pristine isolated clone ran the actual baseline adapter, not merely the
  fake: `pub get` + `gen-l10n` restored the generated output and the complete
  format/analyze/architecture baseline gate returned `pass`.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrizve |
|---|---|
| targeted regression | `3 passed` in the isolated clone |
| router test suite | `155 passed, 53 subtests passed` in the isolated clone |
| actual baseline format/analyze/architecture | `pass` in the isolated clone |
| exact-HEAD CI / property / APK | Pending at review time; required before merge |

## Merge-döntés

There are no open BLOCKER or MAJOR findings. Merge is permitted only after the
branch's CI suite, property gate and APK workflow succeed on the exact final
HEAD, as required by ADR 0052/0086.
