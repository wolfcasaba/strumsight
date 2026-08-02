# Unlimited Automatic Terra Daily Budget Design

**Date:** 2026-08-02
**Status:** Approved
**Decision owner:** User instruction, 2026-08-02

## 1. Problem

The router currently rejects the fourth automatic Terra call in one UTC day.
E03-R08 has a green, staged M3 implementation, but its mandatory high-risk
review is `DEFERRED` solely because the shared `3/3` calendar budget is full.
The actual Codex/Terra service is still available, so the local governance cap
is preventing useful work.

## 2. Decision

`max_automatic_terra_calls_per_utc_day = 0` means **unlimited**. The router
continues reserving every Terra call in the private ledger for audit and crash
safety, but it does not reject calls based on the number already used that UTC
day.

The following safeguards remain unchanged:

- at most one automatic Terra call per task;
- Terra is reached only after the existing objective escalation rules or a
  mandatory high-risk review;
- one interrupted reservation still consumes that task's Terra allowance;
- provider-side quota, authentication, rate-limit and transport failures keep
  their existing fail-closed classification;
- M3 quota/service failures never trigger Terra.

## 3. Configuration and state contract

The TOML field remains an integer to avoid a schema migration:

```toml
max_automatic_terra_calls_per_utc_day = 0
```

Values below zero are invalid. Positive values retain the existing finite-cap
behavior, which keeps tests and emergency rollback simple. `StateStore`
continues counting and recording UTC-day reservations even in unlimited mode.

`terra-status` reports:

```json
{
  "daily_limit": 0,
  "daily_count": 3,
  "unlimited": true,
  "exhausted": false,
  "next_reset_utc": null,
  "next_reset_epoch": null
}
```

## 4. Pipeline behavior

Unlimited mode never creates a Terra budget hold. If a finite-policy hold file
already exists when the policy changes, the driver queries `terra-status`,
recognizes `unlimited=true`, removes the stale hold and continues normally.
If status cannot be queried, the driver keeps the hold fail-closed.

## 5. E03-R08 recovery

The existing `/home/ubuntu/ss-router-e03-r08` staged diff and baseline remain
untouched. Its persisted task state is re-anchored to
`resume_phase=M3_ATTEMPT_1`, which makes resume audit and gate the existing
diff before entering the mandatory Terra review. It must not invoke M3 again.

The resumed command uses the tested policy worktree's router and config while
pointing `--worktree`, `--task` and `--result-json` at E03-R08. Only after the
policy tests are green are the obsolete hold and `HALTED` signal released.

## 6. Verification

- config accepts zero and rejects negative daily limits;
- unlimited state accepts more than three distinct task reservations while
  still enforcing one Terra call per task;
- `terra-status` reports unlimited/non-exhausted with null reset fields;
- a stale finite-policy hold self-clears under unlimited policy;
- all router tests pass except the pre-existing E03-R05 brief metadata failure
  documented in `docs/LESSONS.md` L59;
- E03-R08 resume shows no additional M3 provider call and reaches Terra review.

## 7. Out of scope

- removing the one-Terra-call-per-task safety boundary;
- changing Terra reasoning level or model;
- modifying the E03-R08 implementation diff;
- weakening high-risk review requirements.
