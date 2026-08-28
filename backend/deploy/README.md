# Backend deploy artifacts (E12-R08, ADR 0449)

This directory holds the staging/production container profile. The full
step-by-step runbooks live in
[`docs/operations/backend-deploy.md`](../../docs/operations/backend-deploy.md)
(deploy, rollback, secret rotation) and
[`docs/operations/database-recovery.md`](../../docs/operations/database-recovery.md)
(backup/restore, RTO/RPO). This README covers the two artifacts that live in
this directory.

## `staging.env.example`

A staging profile template. **No secret-like key carries a real value** —
every one is empty or a `<placeholder>` (ADR 0449 D6); copy it and fill the
placeholders from your secret manager at deploy time, never by committing a
filled-in copy. Staging must use its own database and secrets, never
production's — see
[`docs/release/environment-matrix.md`](../../docs/release/environment-matrix.md)
§3 (an operative rule, not something the backend can verify from a secret's
value alone).

## `Dockerfile`

Builds the runtime image: `python:3.12-slim` pinned by digest, dependencies
from the committed `requirements.txt`, a non-root `USER`, and a
migration-before-start `CMD` (`alembic upgrade head` then `uvicorn`).

Build:

```bash
cd backend
docker build -t strumsight-backend:staging .
```

### Reproducing / updating the base image digest

The digest in the `Dockerfile`'s `FROM` line was measured 2026-08-28 for the
`python:3.12-slim` tag. Reproduce it (or measure a new one before bumping)
with the registry's `docker-content-digest` response header:

```bash
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/python:pull" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])")
curl -s -I \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://registry-1.docker.io/v2/library/python/manifests/3.12-slim" \
  | grep -i docker-content-digest
```

Or, with the Docker CLI already logged in:

```bash
docker manifest inspect --verbose python:3.12-slim | grep -i digest
```

Update the `Dockerfile`'s `FROM` line with the new digest and note the
measurement date in this file when the base image is bumped.
