# Backend deploy runbook — staging / production (E12-R08, ADR 0449)

> **Audience:** whoever runs a staging or production deploy of the StrumSight
> account backend. Reference: [ADR 0449](../adr/0449-staging-readiness-traffic-gate-and-recovery.md)
> (the architectural decisions this runbook operationalizes), [ADR 0060](../adr/0060-alembic-schema-source-and-injected-engine-lifecycle.md)
> (Alembic is the only production schema source), [ADR 0445](../adr/0445-environment-value-set-and-staging-isolation.md)
> (the closed `env` value set and the staging/production isolation rule).
>
> There is no running staging infrastructure on this box today (E12-R08
> §0.0.1) — this runbook is the reproducible, locally-verified procedure; the
> actual cloud deploy step is an operator action outside this repo's tests.

## 1. What backs this runbook

- `backend/Dockerfile` — digest-pinned base image, non-root user,
  migration-before-start `CMD` (`alembic upgrade head && uvicorn ...`).
- `backend/deploy/staging.env.example` — the staging profile template (no
  secret carries a real value).
- The readiness-driven **traffic gate** in `backend/app/main.py`: in
  `staging`/`prod`, every business endpoint returns `503
  {"status": "not_ready", "reason": ...}` and its handler never runs while
  the applied migration head doesn't match `alembic heads`. `/health`,
  `/health/live`, `/health/ready` stay reachable throughout (ADR 0449 D1-D3).
  Proven by `backend/tests/test_readiness_and_recovery.py` (A1/A2/A2b).

## 2. Deploy sequence

1. **Build the image** (from `backend/`):

   ```bash
   docker build -t strumsight-backend:<tag> .
   ```

2. **Prepare the environment file.** Copy `backend/deploy/staging.env.example`
   to your deploy tooling's secret store and fill every `<placeholder>` —
   never commit a filled-in copy. Staging must use its own `secret_key`,
   `diag_token`, and database — never production's
   (`docs/release/environment-matrix.md` §3).

3. **Start the container.** The image's `CMD` already runs
   `alembic upgrade head` before `uvicorn` — this is the migration-before-start
   step. If your orchestrator runs migrations as a separate pre-deploy job
   instead of relying on the container `CMD`, run it against the same
   `STRUMSIGHT_DATABASE_URL`:

   ```bash
   docker run --rm --env-file staging.env python -m alembic upgrade head
   ```

4. **Verify readiness** before routing production traffic to the new
   container:

   ```bash
   curl -sf http://<host>:8000/health/ready
   # 200 {"status": "ready"}  → traffic gate open, safe to route
   # 503 {"status": "not_ready", "reason": "migration_mismatch"}  → migration
   #     step above did not complete; do not route traffic
   ```

   Even if step 4 is skipped or races the deploy, the traffic gate refuses
   every business endpoint with `503 not_ready` until the migration head
   matches — a forgotten `alembic upgrade head` becomes a service outage,
   never a write against a stale schema (ADR 0449, "Következmények").

5. **Health-check wiring.** Point your orchestrator's liveness probe at
   `/health/live` (never touches the DB — safe to poll aggressively) and its
   readiness probe at `/health/ready` (reflects the same predicate the
   traffic gate uses).

## 3. Rollback

Rolling back the **application** is an image swap: redeploy the previous
image tag. The traffic gate means a rollback to an image whose ORM expects an
*older* schema than what's applied will itself see `migration_mismatch` and
refuse traffic — it will not silently corrupt data by running old code
against a newer schema.

Rolling back the **schema** (only when the new migration itself must be
undone) uses Alembic directly, one step at a time:

```bash
docker run --rm --env-file staging.env python -m alembic downgrade -1
```

Downgrading is a schema-only operation — no data-restoring step is implied.
If the migration also needs its data undone (not just its schema), use the
backup/restore procedure in
[`docs/operations/database-recovery.md`](database-recovery.md) against a
pre-migration backup instead of `downgrade`.

## 4. Secret rotation

1. Generate the new secret (e.g. `openssl rand -hex 32` for `secret_key`).
2. Update the value in your secret store (never in a committed file).
3. Redeploy — `_guard_prod` / `Settings._guard_staging` (`backend/app/config.py`)
   refuse to boot/instantiate on a dev-default secret, so a deploy with a
   missing or accidentally-reverted secret fails at startup rather than
   serving traffic with a weak key.
4. Rotating `secret_key` invalidates every previously-issued JWT (14-day
   expiry, `backend/app/config.py::access_token_expires_minutes`) — users are
   signed out and must log in again. There is no dual-key grace period today;
   plan rotations accordingly.
5. Rotating `diag_token` only affects the `/diagnostics` surface
   (`STRUMSIGHT_DIAGNOSTICS_ENABLED`) — no user-facing impact.

## 5. Base image maintenance

The `Dockerfile`'s `FROM` digest is measured, not evergreen — see
`backend/deploy/README.md` for the reproducing command and update procedure.
