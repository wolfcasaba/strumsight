# Unlimited Automatic Terra Daily Budget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `max_automatic_terra_calls_per_utc_day = 0` mean unlimited automatic Terra calls while preserving the one-call-per-task limit, audit ledger, escalation rules, and provider fail-closed behavior.

**Architecture:** Keep the existing integer TOML field and interpret zero at the policy boundary. `StateStore` always records reservations but skips only the UTC-day rejection in unlimited mode. The CLI exposes an explicit `unlimited` status, and the pipeline uses that authoritative status to remove stale finite-budget holds before continuing.

**Tech Stack:** Python 3.12, TOML, `unittest`, Bash

---

## Task 1: Configuration and reservation contract

**Files:**

- Modify: `tools/tests/test_router_config.py`
- Modify: `tools/tests/test_state_store.py`
- Modify: `tools/ai_router/config.py`
- Modify: `tools/ai_router/state.py`
- Modify: `.ai/router.toml`

- [ ] Add a config test proving zero is accepted and a separate test proving a negative daily limit is rejected.
- [ ] Add a state test reserving more than three distinct tasks with `daily_limit=0`, plus an assertion that a second reservation for the same task still raises `BudgetError`.
- [ ] Run the new tests and confirm they fail for the missing unlimited contract.
- [ ] Change only the daily config minimum from one to zero.
- [ ] In `reserve_terra`, reject negative daily limits, retain positive task limits, and enforce the daily count only when `daily_limit > 0`.
- [ ] Set `.ai/router.toml` to `max_automatic_terra_calls_per_utc_day = 0`.
- [ ] Re-run the two test modules and confirm they pass.

Commands:

```bash
python3 -m unittest tools.tests.test_router_config tools.tests.test_state_store -v
```

## Task 2: Status API and stale-hold recovery

**Files:**

- Modify: `tools/tests/test_router_cli.py`
- Modify: `tools/tests/test_pipeline_integration.py`
- Modify: `tools/model-router.py`
- Modify: `tools/round-pipeline.sh`

- [ ] Add a CLI test proving limit zero reports `unlimited=true`, `exhausted=false`, and null reset fields while retaining the live ledger count.
- [ ] Add a pipeline integration test proving an existing hold is removed and treated as inactive when `terra-status` reports unlimited.
- [ ] Run both new tests and confirm expected RED failures.
- [ ] Make `terra_status_payload` emit the unlimited contract and keep finite-limit output unchanged.
- [ ] Make `terra_hold_active_for` query authoritative status before honoring an existing hold, remove it only for `unlimited=true`, and otherwise remain fail-closed.
- [ ] Re-run the CLI and pipeline tests and confirm they pass.
- [ ] Run `bash -n tools/round-pipeline.sh`.

Commands:

```bash
python3 -m unittest tools.tests.test_router_cli tools.tests.test_pipeline_integration -v
bash -n tools/round-pipeline.sh
```

## Task 3: Governance and operational documentation

**Files:**

- Modify: `docs/adr/0088-minimax-first-development-router.md`
- Modify: `docs/execution/02-codex-playbook.md`
- Modify: `AGENTS.md`
- Modify: `docs/LESSONS.md`

- [ ] Replace the obsolete fixed `3/UTC day` contract with the user-approved unlimited daily policy and state that positive values remain an emergency finite cap.
- [ ] Document the unchanged per-task limit and provider-side quota behavior.
- [ ] Add L65 with the measured 3/3 E03-R08 calendar wall and why a local aggregate cap must not duplicate the available subscription capacity.
- [ ] Confirm no stale normative text still declares three automatic calls per UTC day.

Commands:

```bash
rg -n "3/UTC|legfeljebb 3|max_automatic_terra_calls_per_utc_day" AGENTS.md docs .ai/router.toml
git diff --check
```

## Task 4: Verification, commit, and E03-R08 recovery

**Files:**

- Verify all files above.
- Update external state: `~/.local/state/strumsight-ai-router/tasks/E03-R08.json` only after exact precondition validation.
- Preserve: `/home/ubuntu/ss-router-e03-r08` staged implementation diff.

- [ ] Run all router unit/integration tests; record the already-baselined E03-R05 metadata failure separately and require no new failure.
- [ ] Run syntax, diff, secret, scope, and status checks.
- [ ] Commit and push the policy branch without touching `main`.
- [ ] Validate E03-R08's persisted baseline SHA, diff hash, attempts, zero Terra calls, and `DEFERRED` reason, then atomically set only `resume_phase=M3_ATTEMPT_1`.
- [ ] Remove the obsolete Terra hold and run `model-router.py resume` from this tested policy worktree against `/home/ubuntu/ss-router-e03-r08`.
- [ ] Confirm provider history gains no second M3 call and does gain one Terra call; verify the router reaches `READY_FOR_REVIEW` or report the exact provider failure.
- [ ] Signal the resulting router state to the pipeline and resume orchestration only when the state is review-ready.

Commands:

```bash
python3 -m unittest discover -s tools/tests -p 'test_*.py' -v
bash -n tools/round-pipeline.sh tools/ai-router-round.sh
git diff --check
git status --short
```
