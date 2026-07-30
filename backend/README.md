# StrumSight Account API 🎸🔐

Optional **login + cloud settings sync** for StrumSight. **Detection stays 100%
on-device** — this backend never sees audio. Logged-out users get the full app
with settings stored locally; logging in syncs those settings across devices.

- **Stack:** FastAPI · SQLAlchemy 2 · Alembic · SQLite (Postgres-ready) · JWT
  (PyJWT) · bcrypt
- **Auth:** email + password → bearer JWT (14-day expiry)
- **Zero-config:** runs with no `.env` and no external services (SQLite file)

## Python and dependencies

The backend supports **Python 3.12**. Runtime packages live in
`requirements.txt`; tests and quality tools (`pytest`, `httpx`, Ruff) live in
`requirements-dev.txt`. Production needs only the runtime file, while local
development and CI install both:

```bash
# Production/runtime:
pip install -r requirements.txt

# Development/CI:
pip install -r requirements.txt -r requirements-dev.txt
```

## Run

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m alembic upgrade head
uvicorn app.main:app --reload            # http://127.0.0.1:8000
# Interactive docs: http://127.0.0.1:8000/docs
```

For the Android emulator, the host machine is reachable at `http://10.0.2.2:8000`.

## Database migrations

Alembic is the only production schema source. Its database URL comes from the
same `Settings` field as the app (`STRUMSIGHT_DATABASE_URL`); no connection
string is duplicated in `alembic.ini`.

```bash
cd backend
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m alembic current
.venv/bin/python -m alembic downgrade -1  # rollback verification / development
```

The dev app retains a zero-setup `create_all` helper, but it runs only during
the app lifespan and never in production. If an existing local
`strumsight.db` was already created by that helper and its schema matches the
current ORM, adopt it explicitly once instead of replaying the initial
migration over existing tables:

```bash
.venv/bin/python -m alembic stamp head
```

Stamping records migration ownership; it does not change the schema. Back up
valuable local data and inspect the schema before stamping. A fresh database
must use `upgrade head`. Until an existing dev database is explicitly stamped,
`/health/ready` remains `503 migration_mismatch`; run
`.venv/bin/python -m alembic stamp head` only after verifying that its schema
matches the current ORM.

## Test

```bash
cd backend
.venv/bin/python -m ruff check app tests
.venv/bin/python -m ruff format --check app tests
.venv/bin/python -m pytest -q            # isolated SQLite databases
```

`.github/workflows/backend-ci.yml` runs the same Ruff and pytest gates on
Python 3.12 for backend changes, then applies `alembic upgrade head` to an
isolated temporary SQLite database. It can also be started manually.

## API

| Method | Path             | Auth   | Body / returns |
|--------|------------------|--------|----------------|
| GET    | `/health`        | –      | compatibility health: `{status, version}` |
| GET    | `/health/live`   | –      | process liveness; never touches the DB |
| GET    | `/health/ready`  | –      | DB + Alembic head + config readiness |
| POST   | `/auth/register` | –      | `{email, password}` → `{access_token}` (auto-login, 201) |
| POST   | `/auth/login`    | –      | `{email, password}` → `{access_token}` |
| GET    | `/auth/me`       | bearer | `{id, email, created_at}` |
| GET    | `/settings`      | bearer | → `SettingsOut` |
| PUT    | `/settings`      | bearer | partial `SettingsUpdate` → `SettingsOut` |

**Settings profile:** `theme_mode` (`light`/`dark`/`system`), `locale`
(`en`/`hu`/`null`=system), `confidence_threshold` (0..1), `tuning_a4` (400..480).
`PUT` is a partial update — only fields present in the body change; sending
`locale: null` clears it, omitting `locale` leaves it untouched.

## Design notes

- **Password hashing** uses `bcrypt` directly (not passlib) to dodge the
  passlib/bcrypt-4.x version-probe breakage. bcrypt caps at 72 bytes — enforced
  in the schema and defensively in `security.py`.
- **Schema lifecycle:** local dev may auto-create tables for zero-setup use.
  Production never calls `Base.metadata.create_all`; run Alembic before
  starting or updating the service. Readiness returns `503` with a stable
  `database_unavailable`, `migration_mismatch`, or `configuration_invalid`
  reason and never includes a secret or database URL.
- **Secrets** come from env (`STRUMSIGHT_*`). The default `secret_key` is
  insecure and for local dev only — override it in production.
- **Prod boot guards (round 120):** set `STRUMSIGHT_ENV=prod` on any public
  deploy — the app then REFUSES to boot with the dev `secret_key` or a
  wildcard CORS origin (`STRUMSIGHT_CORS_ORIGINS=["https://your.app"]`).
  A misconfigured deploy fails at startup, never serves traffic.
- **Lab service isolation:** diagnostics and APK download are enabled by
  default only in dev. Production does not register either surface unless
  `STRUMSIGHT_DIAGNOSTICS_ENABLED=true` and/or
  `STRUMSIGHT_APK_DOWNLOAD_ENABLED=true` is set explicitly. Enabling
  diagnostics in production also requires a non-empty, non-development
  `STRUMSIGHT_DIAG_TOKEN`; otherwise the process refuses to boot. Configure
  upload storage with `STRUMSIGHT_DIAG_DIR` and stage the optional APK with
  `STRUMSIGHT_APK_PATH`.
- **Auth throttling (round 120):** per-IP sliding-window rate limits on
  `/auth/login` (10/min) and `/auth/register` (5/min) → `429` +
  `Retry-After`. The counters are process-local: multiple workers do not share
  them. The single-process target is intentional; production scaling requires
  Redis or another shared store. The attempt is counted BEFORE the credential
  check, so a 429 never confirms a password guess.
- **Production database:** PostgreSQL is recommended. Set a
  `postgresql+psycopg://...` `STRUMSIGHT_DATABASE_URL` and install a compatible
  Psycopg driver in the deployment image (the driver is intentionally not a
  mandatory local/test dependency). Production SQLite fails closed; the
  exceptional single-node escape hatch is the explicit
  `STRUMSIGHT_ALLOW_SQLITE=true`, and migrations are still required.
- One-to-one `User` ⇄ `UserSettings`; a default profile is created at
  registration so `/settings` never 404s.

## Layout

```
backend/
├── app/
│   ├── main.py        # app factory, CORS, /health, router wiring
│   ├── config.py      # env-driven settings (pydantic-settings)
│   ├── database.py    # engine/session factories, Base, get_db
│   ├── models.py      # User, UserSettings
│   ├── schemas.py     # Pydantic contracts
│   ├── security.py    # bcrypt + JWT
│   ├── deps.py        # get_current_user (HTTP bearer)
│   └── routers/       # auth.py, settings.py
├── alembic/           # versioned production schema
├── alembic.ini
└── tests/             # pytest — auth/settings/migration contracts
```
