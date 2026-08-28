# StrumSight account backend — production/staging image (ADR 0449 D7).
#
# Base image pinned by DIGEST, not tag: a tag can move under you, a digest
# cannot. Measured 2026-08-28 for the `python:3.12-slim` tag — reproduce with
# the command in deploy/README.md before bumping this digest.
FROM python:3.12-slim@sha256:09f7da3bc104798d0afb40bc08d23ab2da20a76130cec1f2ef170848f5d85217

WORKDIR /app

# Runtime-only dependencies (requirements-dev.txt — pytest, ruff — never
# ships). Installed before the app layer so dependency changes, not app
# edits, invalidate this layer.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic ./alembic
COPY alembic.ini ./

# Non-root runtime user (ADR 0449 D7) — a compromised process gets no write
# access outside what it's explicitly given.
RUN groupadd --system strumsight \
    && useradd --system --gid strumsight --home-dir /app --no-create-home strumsight \
    && chown -R strumsight:strumsight /app
USER strumsight

EXPOSE 8000

# Migration-before-start (docs/operations/backend-deploy.md): `alembic
# upgrade head` runs before uvicorn on every container start. The runtime
# traffic gate (app/main.py, ADR 0449 D1) is the second, always-on layer —
# it refuses business traffic even if this step were ever skipped.
CMD ["sh", "-c", "python -m alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]
