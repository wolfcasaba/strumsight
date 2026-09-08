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

### Suite runtime — two test-only levers (measured, round 25)

The CI "Backend test gate" step was cancelled at 14 min 56 s of its 15 min
limit. Profiling (`python -m pytest --durations=60`) found the run was
CPU-bound on two things; both are now handled in TEST code only, and
production behaviour is unchanged. Measured on a 4-core Xeon @ 2.80 GHz
container, Python 3.12: **928 s (15 m 28 s) -> 126 s (2 m 06 s)** for the
same 1052 tests, with no test skipped, removed or weakened.

- **bcrypt cost factor.** `app/security.py::PASSWORD_HASH_ROUNDS` is `12`
  (bcrypt's own default) and is a MODULE CONSTANT, never an environment /
  `Settings` knob, so no deployment can weaken it. Only the pytest process
  rebinds it, in `tests/conftest.py`, to `4` — measured 0.271 s vs 0.001 s
  per hash, and the suite mints thousands of fixture hashes (the three
  `test_club_service.py` A7 cells stage 499 users each: 139 s per test).
  The shipped value keeps explicit coverage in
  `tests/test_auth.py::test_production_cost_factor_hashes_and_verifies`,
  which restores it through the `production_password_hashing` fixture.
- **Per-test Alembic replays.** Roughly twenty test modules provisioned their
  SQLite database with a function-scoped `alembic upgrade head` — 22
  revisions, ~0.30 s per call.
  `tests/migration_template.py::apply_head_schema()` replays the chain ONCE
  per pytest process and byte-copies the resulting database file, so every
  test still opens a schema the production migration chain produced,
  `alembic_version` row included — never a `Base.metadata.create_all`
  shortcut. Tests that assert something ABOUT migrating (upgrade/downgrade
  behaviour, readiness on a stale head, the rollback drill, the
  in-process-migration logging trap) still call `alembic.command` directly.

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
- **AI Tutor proxy (ADR 0131 / 0142, wired R23):** off by default
  (`STRUMSIGHT_TUTOR_ENABLED=false` ⇒ `/tutor/*` is not mounted, the client
  gets a plain 404). When enabled, `STRUMSIGHT_TUTOR_PROVIDER` selects the
  adapter the composition root builds — `fake` (the default and the fallback:
  a canned reply, no socket), `anthropic` (Anthropic Messages API, streaming,
  `app/tutor/provider_gateway.py::AnthropicProviderGateway`) or `openai`
  (Chat Completions). `STRUMSIGHT_TUTOR_ALLOWED_PROVIDERS` is the SEPARATE
  JSON allowlist the registry validates the provider/model pair against; it
  stays fail-closed at `{"fake": ["fake-model"]}`. A real provider also needs
  a non-empty, non-development `STRUMSIGHT_TUTOR_API_KEY`. All three failure
  modes — unknown provider, allowlist miss, unusable key — refuse to BOOT in
  every environment, not just prod, so a misconfigured tutor never serves a
  fake answer that looks real. `GET /tutor/capability` reports the live
  `provider` and `model` (never the key) so a flip is verifiable from outside
  the container. The provider secret stays on the server; provider failures
  are normalized to redacted `ProviderError`/`ProviderTimeoutError` and the
  prompt, the reply and the key are never logged. The client-facing answer is
  the same for every provider failure (`502`, or `504` on a timeout), while the
  SERVER log carries a one-line classification — `configuration` (401/403/404),
  `busy` (429/529/5xx), `invalid_request` (400/413/422), `timeout`, `transport`,
  `malformed_response`, `incomplete_response` — plus at most the HTTP status,
  never the provider body. Flip sequence, the classification table, cost/limit
  knobs and the privacy statement:
  `docs/operations/backend-live-deploy.md` §7.2.
- **Community media upload (javító sáv R27):** off by default.
  `STRUMSIGHT_COMMUNITY_MEDIA_ENABLED=false` ⇒ `POST/GET/DELETE
  /community/media` are not in the route table at all (a registration
  gate, like `clubs` / `leaderboards`), so an un-flipped deploy answers
  the framework's bare 404 and the client's existing "not enabled on this
  server" path applies unchanged. Flipping the flag is NOT enough to make
  an upload succeed — two further switches are fail-closed on purpose:

  | variable | default | effect |
  |---|---|---|
  | `STRUMSIGHT_MEDIA_ROOT` | `backend/media_data` | content-addressed store root (`<sha[0:2]>/<sha[2:4]>/<sha>`); the ONLY writable path the pipeline touches |
  | `STRUMSIGHT_MEDIA_SCANNER` | `disabled` | `disabled` REJECTS every upload (`scanner_not_configured`); `clamd` selects the `INSTREAM` adapter. There is deliberately **no pass-through adapter** |
  | `STRUMSIGHT_MEDIA_SCANNER_SOCKET` | *(empty)* | clamd UNIX socket path; wins over host/port when set |
  | `STRUMSIGHT_MEDIA_SCANNER_HOST` / `_PORT` | `127.0.0.1` / `3310` | clamd TCP endpoint |
  | `STRUMSIGHT_MEDIA_SCANNER_TIMEOUT_SECONDS` | `10.0` | every socket failure — refused, silent, timed out, unparseable — is a REJECT |
  | `STRUMSIGHT_MEDIA_AUDIO_TRANSCODER` | `disabled` | `disabled` rejects every AUDIO upload (`audio_transcoder_unavailable`); `ffmpeg` selects the external re-encoder. Images are always re-encoded in-process by Pillow (a hard dependency) |
  | `STRUMSIGHT_MEDIA_FFMPEG_PATH` | `ffmpeg` | binary the ffmpeg adapter runs (fixed argv, no shell) |
  | `STRUMSIGHT_MEDIA_AUDIO_MAX_DURATION_SECONDS` | `180` | hard truncation, not a trusted container duration |
  | `STRUMSIGHT_MEDIA_MAX_IMAGE_BYTES` | `8388608` | per-kind byte cap, enforced on the bytes actually read (`Content-Length` is not trusted) |
  | `STRUMSIGHT_MEDIA_MAX_AUDIO_BYTES` | `20971520` | per-kind byte cap for audio |
  | `STRUMSIGHT_MEDIA_MAX_ITEMS_PER_PROFILE` | `50` | per-account live-row quota (the second, independent budget next to the per-IP throttle) |
  | `STRUMSIGHT_MEDIA_UPLOAD_RATE_LIMIT_MAX` / `_WINDOW` | `20` / `3600` | per-IP sliding window, keyed through `client_ip_for_throttle` |
  | `STRUMSIGHT_MEDIA_IMAGE_MAX_DIMENSION` | `2048` | longest edge of the re-encoded image |
  | `STRUMSIGHT_MEDIA_IMAGE_QUALITY` | `82` | JPEG/WebP quality factor |
  | `STRUMSIGHT_MEDIA_REVIEW_REQUIRED` | `false` | `true` parks a scanned + transcoded row in `review` until an operator releases it |

  What the surface does with the bytes: magic-byte sniff (the filename and
  the multipart `Content-Type` never participate) → clamd scan of the
  ORIGINAL bytes → re-encode, so the stored bytes are the encoder's output
  and EXIF/GPS + polyglot tails do not survive → content-addressed write.
  Flip sequence, the volume/clamd wiring and the fail-closed probe:
  `docs/operations/backend-live-deploy.md` §7.3.
- **Auth throttling (round 120):** per-IP sliding-window rate limits on
  `/auth/login` (10/min) and `/auth/register` (5/min) → `429` +
  `Retry-After`. The counters are process-local: multiple workers do not share
  them. The single-process target is intentional; production scaling requires
  Redis or another shared store. The attempt is counted BEFORE the credential
  check, so a 429 never confirms a password guess.
- **Throttling behind a reverse proxy (R14):** the bucket key comes from
  `app/client_ip.py::client_ip_for_throttle`. It is the direct socket peer,
  EXCEPT when that peer is listed in `STRUMSIGHT_TRUSTED_PROXY_IPS` (a JSON
  list, empty by default) — then the first `X-Forwarded-For` hop. Without
  this, a proxied deploy gives every caller the same key and the budgets
  become global: measured on `casaba.app/strumsight`, where the container
  sees the docker-bridge address for every phone and the shared 429 reaches
  the app as a generic network error. The header is never trusted from an
  unlisted peer (that would let anyone pick their own bucket), and the image
  `CMD` hands the same variable to uvicorn's `--forwarded-allow-ips`, so the
  ASGI and application layers cannot disagree. The reverse proxy must
  OVERWRITE the header (Caddy: `header_up X-Forwarded-For {remote_host}`) —
  the runbook is `docs/operations/backend-live-deploy.md` §5.1/§7.
- **Login-failure diagnostics (R14):** a failed login answers a uniform
  `401 Incorrect email or password` — deliberately identical for an unknown
  address and a wrong password, so the response never reveals which e-mails
  are registered. The operator gets the distinction SERVER-SIDE instead: one
  INFO record per failure on the `app.routers.auth` logger, e.g.
  `auth.login_failed reason=unknown_email client=203.0.113.7
  email_hash=0748ebb7f38a` (`reason=bad_password` for the other branch, and
  `auth.register_conflict reason=email_exists …` for a 409). The record
  carries no e-mail and no password — `email_hash` is the first 12 hex
  characters of `sha256(lowercased email)`, enough to see the same address
  failing repeatedly, and comparable against a specific suspected address by
  hashing it. `client=` is the throttle bucket key above, so failures and a
  429 line up. Read it on a compose deploy with:

  ```bash
  docker compose --env-file runtime.env logs api | grep auth.login_failed
  docker compose --env-file runtime.env logs --since 30m api | grep auth.
  ```

  `create_app()` attaches a stderr handler to the `app` package logger for
  exactly this reason: uvicorn's own log config handles only `uvicorn*`
  loggers and leaves the root without a handler, so an INFO record from the
  application would otherwise be dropped before it ever reached
  `docker compose logs`. For the same reason `alembic/env.py` calls
  `fileConfig(..., disable_existing_loggers=False)` — with the default `True`,
  one in-process migration switched off every `app.*` logger for the rest of
  the process (measured; guarded by
  `tests/test_auth_failure_logging.py::test_an_in_process_migration_does_not_silence_the_diagnostics`).
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
│   ├── ratelimit.py   # in-memory sliding-window limiter
│   ├── client_ip.py   # trusted-proxy-aware throttle key
│   ├── deps.py        # get_current_user (HTTP bearer)
│   └── routers/       # auth.py, settings.py
├── alembic/           # versioned production schema
├── alembic.ini
└── tests/             # pytest — auth/settings/migration contracts
```
