# StrumSight Account API 🎸🔐

Optional **login + cloud settings sync** for StrumSight. **Detection stays 100%
on-device** — this backend never sees audio. Logged-out users get the full app
with settings stored locally; logging in syncs those settings across devices.

- **Stack:** FastAPI · SQLAlchemy 2 · SQLite (Postgres-ready) · JWT (PyJWT) · bcrypt
- **Auth:** email + password → bearer JWT (14-day expiry)
- **Zero-config:** runs with no `.env` and no external services (SQLite file)

## Run

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload            # http://127.0.0.1:8000
# Interactive docs: http://127.0.0.1:8000/docs
```

For the Android emulator, the host machine is reachable at `http://10.0.2.2:8000`.

## Test

```bash
cd backend
source .venv/bin/activate
pytest                                   # in-memory SQLite, isolated per test
```

## API

| Method | Path             | Auth   | Body / returns |
|--------|------------------|--------|----------------|
| GET    | `/health`        | –      | `{status, version}` |
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
- **Tables** are auto-created on boot (`Base.metadata.create_all`) for dev
  convenience. **Production should use Alembic migrations** and a real Postgres.
- **Secrets** come from env (`STRUMSIGHT_*`). The default `secret_key` is
  insecure and for local dev only — override it in production.
- One-to-one `User` ⇄ `UserSettings`; a default profile is created at
  registration so `/settings` never 404s.

## Layout

```
backend/
├── app/
│   ├── main.py        # app factory, CORS, /health, router wiring
│   ├── config.py      # env-driven settings (pydantic-settings)
│   ├── database.py    # engine, SessionLocal, Base, get_db
│   ├── models.py      # User, UserSettings
│   ├── schemas.py     # Pydantic contracts
│   ├── security.py    # bcrypt + JWT
│   ├── deps.py        # get_current_user (HTTP bearer)
│   └── routers/       # auth.py, settings.py
└── tests/             # pytest — auth + settings, in-memory DB
```
