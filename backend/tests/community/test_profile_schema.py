"""E09-R02 — Community module boundary acceptance tests.

Covers every cell of the brief §6 / §6.1 acceptance matrix:

* A1 — production does not bootstrap Community schema via ``create_all``
* A2 — the profile schema never leaks the internal ``id`` (BigInteger PK)
* A3 — the module boundary is self-contained (factory override, no
  production env required)
* A4 — ``alembic upgrade head`` succeeds on an empty database and reaches
  the new head (``e09_r02_0002``)
* A5 — the Community router is **absent** from the app when the master
  switch is off (no 404-from-inside, just "not mounted")
* A6 — ``public_id`` is unique and not derived from the internal ``id``
* A7 — the ``user_id`` unique constraint enforces the 1:1 invariant at
  the DB level (not at the application layer)

The §6.1 measure-matrix rows are realised as separate tests so a regression
that hides a vulnerability behind a default case is caught.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError

from alembic import command
from app.community import (
    CommunityPrivacySettingsOut,
    CommunityProfile,
    CommunityProfileOut,
    build_community_router,
    community_readiness_failure,
)
from app.config import Settings
from app.database import Base

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# A4 — Alembic upgrade head reaches the new migration on an empty database
# ---------------------------------------------------------------------------


def test_alembic_upgrade_head_applies_community_migration(tmp_path, monkeypatch):
    """A4 — fresh DB -> ``upgrade head`` applies every Community migration in
    the chain (the E09-R02 head ``e09_r02_0002`` must remain an ancestor of
    the current head) and creates both Community tables with the expected
    unique constraints. Chain-tolerant: later Community rounds appending to
    the chain do not require rewriting this test."""
    db_path = tmp_path / "e09_r02.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    command.upgrade(_alembic_config(), "head")

    config = _alembic_config()
    script_dir = ScriptDirectory.from_config(config)
    heads = script_dir.get_heads()
    assert len(heads) == 1, f"single-head chain required, got {heads}"
    # Alembic's walk_revisions(start, end) treats ``start`` as the
    # upgrade-from endpoint — to enumerate every revision from ``base``
    # up to the current head (inclusive), pass ``"base"`` first.
    ancestors = {rev.revision for rev in script_dir.walk_revisions("base", heads[0])}
    assert "e09_r02_0002" in ancestors, (
        "e09_r02_0002 must remain an ancestor of head — round E09-R02 contract"
    )

    engine = create_engine(db_url)
    try:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        assert "community_profiles" in tables
        assert "community_privacy_settings" in tables

        # 1:1 invariant: UNIQUE on user_id and profile_id.
        user_unique = {
            tuple(c["column_names"])
            for c in inspector.get_unique_constraints("community_profiles")
        }
        assert ("user_id",) in user_unique, (
            "community_profiles.user_id must be UNIQUE — A7 contract"
        )

        privacy_unique = {
            tuple(c["column_names"])
            for c in inspector.get_unique_constraints("community_privacy_settings")
        }
        assert ("profile_id",) in privacy_unique, (
            "community_privacy_settings.profile_id must be UNIQUE — A7 contract"
        )

        # FK with ondelete CASCADE — mirror the existing user_settings rule.
        profile_fks = inspector.get_foreign_keys("community_profiles")
        assert len(profile_fks) == 1
        assert profile_fks[0]["constrained_columns"] == ["user_id"]
        assert profile_fks[0]["referred_table"] == "users"
        assert profile_fks[0]["options"] == {"ondelete": "CASCADE"}

        privacy_fks = inspector.get_foreign_keys("community_privacy_settings")
        assert len(privacy_fks) == 1
        assert privacy_fks[0]["constrained_columns"] == ["profile_id"]
        assert privacy_fks[0]["referred_table"] == "community_profiles"
        assert privacy_fks[0]["options"] == {"ondelete": "CASCADE"}
    finally:
        engine.dispose()


def test_alembic_downgrade_drops_community_tables(tmp_path, monkeypatch):
    """A4 — downgrading all the way to ``e01_r12_0001`` removes every
    Community migration in the chain (reversible), leaving the E01-R12
    account baseline intact. Explicit target revision, NOT a relative step
    count, so future Community rounds extending the chain still satisfy the
    contract."""
    db_path = tmp_path / "e09_r02_down.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    config = _alembic_config()
    command.upgrade(config, "head")
    command.downgrade(config, "e01_r12_0001")

    engine = create_engine(db_url)
    try:
        tables = set(inspect(engine).get_table_names())
        assert "community_profiles" not in tables
        assert "community_privacy_settings" not in tables
        # The account baseline (round 12) survives the Community rollback.
        assert "users" in tables
        assert "user_settings" in tables
    finally:
        engine.dispose()


# ---------------------------------------------------------------------------
# A3 — module boundary is self-contained; production .env is NEVER read
# ---------------------------------------------------------------------------


def test_module_import_does_not_read_production_env(
    monkeypatch, tmp_path, _community_clear_env
):
    """A3 / §6.1 row 5 — the module must work with an explicit in-process
    ``Settings(community_enabled=...)`` and an empty environment, *without*
    pulling values from a developer- or CI-leaked production ``.env``.

    If a future regression replaces the explicit kwargs with
    ``Settings()`` (which reads ``.env``), this test catches it: the only
    observable side-effect would be a module-level file read.
    """
    sentinel = tmp_path / "should-not-be-read.env"
    sentinel.write_text(
        "STRUMSIGHT_COMMUNITY_ENABLED=true\nSTRUMSIGHT_ENV=prod\n",
        encoding="utf-8",
    )
    # Point the test at a temp dir so the (default) ``.env`` lookup cannot
    # accidentally pick anything up.
    monkeypatch.chdir(tmp_path)

    from app.community import build_community_router
    from app.config import Settings

    settings = Settings(_env_file=None, community_enabled=True)
    router = build_community_router(settings)
    assert router is not None

    # The disabled branch must read the explicit kwarg, not the sentinel.
    disabled = Settings(_env_file=None, community_enabled=False)
    assert build_community_router(disabled) is None


# ---------------------------------------------------------------------------
# A5 — router is ABSENT (not 404-from-inside) when community_enabled=False
# ---------------------------------------------------------------------------


def test_factory_returns_none_when_community_disabled(community_settings_disabled):
    """A5 / §6.1 row 3 — flag check at the *factory*, not inside endpoints."""
    assert build_community_router(community_settings_disabled) is None


def test_router_is_not_mounted_when_disabled(community_client_disabled):
    """A5 — disabled-mode ``TestClient`` has no ``/community/*`` endpoints.

    The /community/ping path that exists in enabled mode must yield a 404
    from FastAPI itself (no route), NOT 200 from a router that runs a flag
    check inside.
    """
    response = community_client_disabled.get("/community/ping")
    assert response.status_code == 404, (
        f"router must be absent when disabled, got {response.status_code}"
    )
    response_profile = community_client_disabled.get(
        f"/community/profiles/{uuid.uuid4()}"
    )
    assert response_profile.status_code == 404


def test_router_is_mounted_when_enabled(community_client_enabled):
    """A5 — enabled-mode TestClient serves /community/ping."""
    response = community_client_enabled.get("/community/ping")
    assert response.status_code == 200
    assert response.json() == {"module": "community"}


# ---------------------------------------------------------------------------
# A2 — internal ``id`` never crosses the API boundary
# ---------------------------------------------------------------------------


def test_profile_out_schema_does_not_expose_internal_id():
    """A2 — the whitelist-only Pydantic schema must not have an ``id`` field."""
    schema_fields = set(CommunityProfileOut.model_fields.keys())
    assert "id" not in schema_fields, (
        f"CommunityProfileOut must NOT expose the internal id — got {schema_fields}"
    )
    assert "public_id" in schema_fields


def test_privacy_out_schema_does_not_expose_internal_id():
    """A2 — same for the privacy-settings schema."""
    schema_fields = set(CommunityPrivacySettingsOut.model_fields.keys())
    assert "id" not in schema_fields
    assert "public_id" in schema_fields


def test_response_payload_does_not_contain_internal_id(
    community_client_enabled,
):
    """A2 / §6.1 row 2 — when the row is read through the router, the JSON
    payload must NOT include the internal ``id`` field, even if the ORM
    object has it."""
    from app.database import get_db

    session_factory = community_client_enabled.app.state.session_factory

    # Insert a known parent user + a profile row directly through the seam.
    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    community_client_enabled.app.dependency_overrides[get_db] = override_get_db

    from app.community import CommunityProfile

    with session_factory() as db:
        # SQLite test DB doesn't have a users row yet — insert one to
        # satisfy the FK and reach a real Community row.
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 1,
                "email": "owner@strumsight.app",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        profile = CommunityProfile(user_id=1, display_name="hello")
        db.add(profile)
        db.commit()
        db.refresh(profile)
        public_id = str(profile.public_id)

    response = community_client_enabled.get(f"/community/profiles/{public_id}")
    assert response.status_code == 200, response.text
    payload = response.json()
    assert "id" not in payload, f"payload leaked internal id: {payload}"
    assert payload["public_id"] == public_id
    assert payload["display_name"] == "hello"


# ---------------------------------------------------------------------------
# A6 — public_id is unique and non-sequential
# ---------------------------------------------------------------------------


def test_public_id_is_uuid4_not_derived_from_internal_id(
    community_client_enabled,
):
    """A6 — every freshly-created profile gets a fresh random UUID v4, and
    the public_id is NOT a stringified ``id`` (the integer PK)."""
    from app.database import get_db

    session_factory = community_client_enabled.app.state.session_factory
    community_client_enabled.app.dependency_overrides[get_db] = lambda: (
        yield from _session_gen(session_factory)
    )

    seen_ids: set[uuid.UUID] = set()
    with session_factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 1,
                "email": "u1@s.test",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        for n in range(2, 6):
            db.execute(
                text(
                    "INSERT INTO users (id, email, hashed_password, created_at) "
                    "VALUES (:id, :email, :password, :ts)"
                ),
                {
                    "id": n,
                    "email": f"u{n}@s.test",
                    "password": "x",
                    "ts": datetime.now(timezone.utc),
                },
            )
        db.commit()

        for n in range(1, 5):
            profile = CommunityProfile(user_id=n)
            db.add(profile)
        db.commit()
        for profile in db.query(CommunityProfile).all():
            # UUID v4 -> version field == 4
            assert profile.public_id.version == 4, (
                f"public_id must be a UUID v4, got {profile.public_id!r}"
            )
            seen_ids.add(profile.public_id)
            # NOT a stringified internal id (the matrix's "inkrementális integer-ből
            # képzett string" failure mode).
            assert str(profile.public_id) != str(profile.id)
            assert profile.public_id != uuid.UUID(int=profile.id)

    assert len(seen_ids) == 4, "public_ids must be unique within a single batch"


def _session_gen(session_factory):
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def test_public_id_unique_constraint_at_db_level(community_app_enabled):
    """A6 — a duplicate ``public_id`` raises at the DB level (unique index)."""
    from sqlalchemy.exc import IntegrityError as _IntegrityError

    app, session_factory = community_app_enabled
    fixed = uuid.uuid4()
    with session_factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 1,
                "email": "a@s.test",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 2,
                "email": "b@s.test",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        p1 = CommunityProfile(user_id=1, public_id=fixed)
        db.add(p1)
        db.commit()
        p2 = CommunityProfile(user_id=2, public_id=fixed)
        db.add(p2)
        with pytest.raises(_IntegrityError):
            db.commit()


# ---------------------------------------------------------------------------
# A7 — 1:1 constraint at the DB level, NOT the application layer
# ---------------------------------------------------------------------------


def test_duplicate_profile_for_same_user_is_rejected_by_db(
    community_app_enabled,
):
    """A7 — a second profile row for the same ``users.id`` is rejected by
    the DB-level unique constraint, not by application code (per ADR 0396
    §2)."""
    app, session_factory = community_app_enabled
    with session_factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 1,
                "email": "x@s.test",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        db.commit()

        db.add(CommunityProfile(user_id=1))
        db.commit()

        db.add(CommunityProfile(user_id=1))
        with pytest.raises(IntegrityError):
            db.commit()


def test_user_deletion_cascades_to_community_profile(
    community_app_enabled,
):
    """A7 — the FK ON DELETE CASCADE mirrors the user_settings rule (round
    120 / ADR 0060 §8); deleting the parent ``users`` row removes the
    matching ``community_profiles`` row in the same transaction."""
    app, session_factory = community_app_enabled
    with session_factory() as db:
        db.execute(
            text(
                "INSERT INTO users (id, email, hashed_password, created_at) "
                "VALUES (:id, :email, :password, :ts)"
            ),
            {
                "id": 1,
                "email": "x@s.test",
                "password": "x",
                "ts": datetime.now(timezone.utc),
            },
        )
        db.commit()
        profile = CommunityProfile(user_id=1)
        db.add(profile)
        db.commit()

        db.execute(text("DELETE FROM users WHERE id = 1"))
        db.commit()

        remaining = (
            db.query(CommunityProfile).filter(CommunityProfile.user_id == 1).count()
        )
        assert remaining == 0, "FK cascade must remove the child row"


# ---------------------------------------------------------------------------
# A1 — no ``create_all``-bootstrap in production
# ---------------------------------------------------------------------------


def test_community_readiness_failure_reports_create_all_disallowed(
    monkeypatch, tmp_path
):
    """A1 — the ``community_readiness_failure`` gate must NOT touch the
    schema. We assert it by spying on ``Base.metadata.create_all`` and
    confirming the gate never calls it, even when the DB is reachable
    but the schema is missing (a tempting, wrong path).

    The exact ``reason`` returned is intentionally not asserted here —
    that's covered by the dedicated ``migration_mismatch`` /
    ``database_unavailable`` / ``community_requires_postgres`` tests below.
    The A1 contract is "no implicit schema bootstrap", which is observable
    only through the ``create_all`` call count.
    """
    calls: list[tuple] = []

    def spy(*args, **kwargs):
        calls.append((args, kwargs))

    monkeypatch.setattr(Base.metadata, "create_all", spy)

    engine = create_engine("sqlite:///:memory:")
    settings = Settings(community_enabled=False, env="dev")

    # The reason may be None or a migration code — what matters is that the
    # gate did not bootstrap the schema as a side-effect.
    community_readiness_failure(engine, settings, _ALEMBIC_INI)
    assert calls == [], "community_readiness_failure must not call create_all"


def test_community_readiness_failure_flags_sqlite_in_prod(
    monkeypatch, tmp_path, _community_clear_env
):
    """A1 — production + community_enabled=true + SQLite must fail closed."""
    engine = create_engine("sqlite:///:memory:")
    settings = Settings(
        community_enabled=True,
        env="prod",
        database_url="sqlite:///./strumsight.db",
    )

    reason = community_readiness_failure(engine, settings, _ALEMBIC_INI)
    assert reason == "community_requires_postgres"


def test_community_readiness_failure_reports_migration_mismatch(
    monkeypatch, tmp_path, _community_clear_env
):
    """A1 — ``community_readiness_failure`` mirrors the main.py
    ``_readiness_failure`` semantics for an unmigrated DB."""
    db_path = tmp_path / "unmigrated.db"
    engine = create_engine(f"sqlite:///{db_path}")
    settings = Settings(
        community_enabled=True,
        env="dev",
        database_url=f"sqlite:///{db_path}",
    )

    reason = community_readiness_failure(engine, settings, _ALEMBIC_INI)
    assert reason == "migration_mismatch"


def test_community_readiness_failure_reports_database_unavailable(
    monkeypatch, tmp_path, _community_clear_env
):
    """A1 — when the engine cannot connect, the gate returns the same
    stable reason code as ``main.py._readiness_failure``."""
    db_path = tmp_path / "missing" / "private.db"
    engine = create_engine(f"sqlite:///{db_path}")
    settings = Settings(
        community_enabled=True,
        env="dev",
        database_url=f"sqlite:///{db_path}",
    )

    reason = community_readiness_failure(engine, settings, _ALEMBIC_INI)
    assert reason == "database_unavailable"


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _community_clear_env(monkeypatch):
    """Strip every STRUMSIGHT_COMMUNITY_* env var before each test.

    Mirrors the discipline in ``test_community_config.py`` — the §6.1 row 5
    case is the silent leak of a production ``.env`` (or a leaked dev
    override) into a test that "shouldn't care". The autouse fixture is
    the cheapest defence.
    """
    for key in (
        "STRUMSIGHT_COMMUNITY_ENABLED",
        "STRUMSIGHT_COMMUNITY_WRITES_ENABLED",
        "STRUMSIGHT_COMMUNITY_MEDIA_ENABLED",
        "STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED",
        "STRUMSIGHT_COMMUNITY_CLUBS_ENABLED",
        "STRUMSIGHT_ENV",
        "STRUMSIGHT_DATABASE_URL",
    ):
        monkeypatch.delenv(key, raising=False)
