# strumsight:allow-secret-file — migracios tesztek kitalalt Settings-fixture-okkel.
"""Database lifecycle and migration contract tests."""

import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import SQLAlchemyError

from alembic import command
from app import models as _models  # noqa: F401 -- registers ORM metadata
from app.config import Settings
from app.database import Base, create_database_engine
from app.main import create_app

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_SCRIPTS = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    config = Config(str(_ALEMBIC_INI))
    config.set_main_option("script_location", str(_ALEMBIC_SCRIPTS))
    return config


def _prod_settings(database_url: str) -> Settings:
    return Settings(
        env="prod",
        secret_key="a-real-32-char-production-secret",
        cors_origins=["https://app.strumsight.app"],
        database_url=database_url,
        allow_sqlite_in_prod=True,
    )


def test_importing_application_does_not_create_default_sqlite_file(tmp_path):
    environment = os.environ.copy()
    environment.pop("STRUMSIGHT_DATABASE_URL", None)
    environment.pop("STRUMSIGHT_ENV", None)
    environment["PYTHONPATH"] = str(_BACKEND_ROOT)

    completed = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        check=False,
        text=True,
    )

    assert completed.returncode == 0, completed.stderr
    assert not (tmp_path / "strumsight.db").exists()


def test_upgrade_head_matches_current_orm_schema(tmp_path, monkeypatch):
    database_path = tmp_path / "upgrade.db"
    database_url = f"sqlite:///{database_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)

    command.upgrade(_alembic_config(), "head")

    engine = create_engine(database_url)
    try:
        with engine.connect() as connection:
            migration_context = MigrationContext.configure(
                connection,
                opts={
                    "compare_type": True,
                    "compare_server_default": True,
                },
            )
            expected_head = ScriptDirectory.from_config(
                _alembic_config()
            ).get_current_head()
            assert migration_context.get_current_revision() == expected_head
            assert compare_metadata(migration_context, Base.metadata) == []

            inspector = inspect(connection)
            assert {"users", "user_settings"}.issubset(inspector.get_table_names())
            assert inspector.get_indexes("users") == [
                {
                    "name": "ix_users_email",
                    "column_names": ["email"],
                    "unique": 1,
                    "dialect_options": {},
                }
            ]
            assert inspector.get_unique_constraints("user_settings") == [
                {
                    "name": None,
                    "column_names": ["user_id"],
                }
            ]
            foreign_keys = inspector.get_foreign_keys("user_settings")
            assert len(foreign_keys) == 1
            assert foreign_keys[0]["constrained_columns"] == ["user_id"]
            assert foreign_keys[0]["referred_table"] == "users"
            assert foreign_keys[0]["referred_columns"] == ["id"]
            assert foreign_keys[0]["options"] == {"ondelete": "CASCADE"}
    finally:
        engine.dispose()


def test_downgrade_one_revision_drops_only_community_tables(tmp_path, monkeypatch):
    """One-step downgrade from the current head must reverse at least the head
    migration's own schema change — a table addition/removal *or* a column
    addition/removal — while leaving the E01-R12 account baseline
    (``users``, ``user_settings``) intact at the column-set level.

    Chain-agnostic: this test compares a full schema snapshot
    (``table -> frozenset(column names)``) across the downgrade rather than
    the raw table set, so future Community rounds that only adjust columns
    (a valid ADR 0398 §1 migration shape) do not require rewriting it.
    """
    database_path = tmp_path / "downgrade_one_step.db"
    database_url = f"sqlite:///{database_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    config = _alembic_config()
    command.upgrade(config, "head")

    def _schema_snapshot(engine):
        inspector = inspect(engine)
        snapshot = {}
        for table in inspector.get_table_names():
            columns = frozenset(
                column["name"] for column in inspector.get_columns(table)
            )
            indexes = frozenset(index["name"] for index in inspector.get_indexes(table))
            snapshot[table] = columns | indexes
        return snapshot

    engine = create_engine(database_url)
    try:
        snapshot_at_head = _schema_snapshot(engine)
        command.downgrade(config, "-1")
        snapshot_after = _schema_snapshot(engine)
    finally:
        engine.dispose()
    assert snapshot_after != snapshot_at_head, (
        "one-step downgrade must undo at least the head migration's own "
        "schema change (a table or a column)"
    )
    assert snapshot_after.get("users") == snapshot_at_head.get("users"), (
        "the E01-R12 users table shape must survive a single-step downgrade"
    )
    assert snapshot_after.get("user_settings") == snapshot_at_head.get(
        "user_settings"
    ), "the E01-R12 user_settings table shape must survive a single-step downgrade"


def test_downgrade_to_base_removes_application_schema(tmp_path, monkeypatch):
    """Downgrading all the way to ``base`` should fully reverse both
    migrations in the chain — the Community tables AND the baseline
    ``users`` / ``user_settings`` tables disappear.
    """
    database_path = tmp_path / "downgrade_base.db"
    database_url = f"sqlite:///{database_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    config = _alembic_config()
    command.upgrade(config, "head")

    command.downgrade(config, "base")

    engine = create_engine(database_url)
    try:
        tables = set(inspect(engine).get_table_names())
    finally:
        engine.dispose()
    assert "users" not in tables
    assert "user_settings" not in tables
    assert "community_profiles" not in tables
    assert "community_privacy_settings" not in tables


def test_sqlite_runtime_enforces_foreign_key_cascade(tmp_path, monkeypatch):
    database_url = f"sqlite:///{tmp_path / 'cascade.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")
    engine = create_database_engine(database_url)

    try:
        with engine.begin() as connection:
            assert connection.execute(text("PRAGMA foreign_keys")).scalar_one() == 1
            connection.execute(
                text(
                    "INSERT INTO users "
                    "(id, email, hashed_password, created_at) "
                    "VALUES (1, 'cascade@test.invalid', 'hash', '2026-07-29')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO user_settings "
                    "(id, user_id, theme_mode, locale, "
                    "confidence_threshold, tuning_a4, updated_at) "
                    "VALUES (1, 1, 'system', NULL, 0.45, 440, '2026-07-29')"
                )
            )
            connection.execute(text("DELETE FROM users WHERE id = 1"))
            children = connection.execute(
                text("SELECT COUNT(*) FROM user_settings WHERE user_id = 1")
            ).scalar_one()
            assert children == 0
    finally:
        engine.dispose()


def test_production_startup_never_calls_create_all(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(
        Base.metadata,
        "create_all",
        lambda *args, **kwargs: calls.append((args, kwargs)),
    )
    app = create_app(_prod_settings(f"sqlite:///{tmp_path / 'prod.db'}"))

    with TestClient(app):
        pass

    assert calls == []


def test_dev_schema_initialization_failure_is_logged(
    caplog,
    monkeypatch,
):
    def fail_schema_initialization(*args, **kwargs):
        raise SQLAlchemyError("synthetic schema initialization failure")

    monkeypatch.setattr(
        Base.metadata,
        "create_all",
        fail_schema_initialization,
    )
    app = create_app(Settings(database_url="sqlite://"))
    # Alembic's in-process fileConfig call disables loggers not listed in
    # alembic.ini. Re-enable this logger so the test is order-independent.
    monkeypatch.setattr(logging.getLogger("app.main"), "disabled", False)

    with caplog.at_level(logging.ERROR, logger="app.main"):
        with TestClient(app):
            pass

    assert "Development schema initialization failed" in caplog.messages
    assert not hasattr(app.state, "dev_schema_initialization_failed")


def test_unprefixed_sqlite_permission_environment_is_ignored(monkeypatch):
    monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE", raising=False)
    monkeypatch.setenv("ALLOW_SQLITE_IN_PROD", "true")
    settings = Settings(
        env="prod",
        secret_key="a-real-32-char-production-secret",
        cors_origins=["https://app.strumsight.app"],
    )

    assert settings.allow_sqlite_in_prod is False
    with pytest.raises(RuntimeError, match="SQLite"):
        create_app(settings)


def test_create_app_uses_explicit_database_url_without_override(tmp_path):
    database_path = tmp_path / "factory.db"
    app = create_app(Settings(database_url=f"sqlite:///{database_path}"))

    with TestClient(app) as client:
        response = client.post(
            "/auth/register",
            json={
                "email": "factory@strumsight.app",
                "password": "sixstrings",
            },
        )

    assert response.status_code == 201
    assert database_path.exists()


def test_liveness_does_not_connect_to_database(tmp_path):
    database_path = tmp_path / "missing" / "live.db"
    app = create_app(_prod_settings(f"sqlite:///{database_path}"))

    with TestClient(app) as client:
        response = client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert not database_path.exists()


def test_readiness_returns_sanitized_503_when_database_is_unavailable(tmp_path):
    database_path = tmp_path / "missing" / "private-database-name.db"
    database_url = f"sqlite:///{database_path}"
    settings = _prod_settings(database_url).model_copy(
        update={"secret_key": "never-return-this-secret"}
    )
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "status": "not_ready",
        "reason": "database_unavailable",
    }
    assert settings.secret_key not in response.text
    assert settings.database_url not in response.text


def test_readiness_returns_503_when_database_is_not_at_head(tmp_path):
    database_url = f"sqlite:///{tmp_path / 'unmigrated.db'}"
    app = create_app(_prod_settings(database_url))

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "status": "not_ready",
        "reason": "migration_mismatch",
    }


def test_readiness_returns_200_for_database_at_head(tmp_path, monkeypatch):
    database_url = f"sqlite:///{tmp_path / 'ready.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")
    app = create_app(_prod_settings(database_url))

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_readiness_reports_invalid_runtime_configuration(tmp_path):
    app = create_app(_prod_settings(f"sqlite:///{tmp_path / 'configuration.db'}"))
    app.state.settings = Settings(env="prod")

    with TestClient(app) as client:
        response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "status": "not_ready",
        "reason": "configuration_invalid",
    }


def test_openapi_contract_is_deterministic():
    schema = create_app(Settings(database_url="sqlite://")).openapi()

    assert schema["info"]["title"] == "StrumSight Account API"
    assert schema["info"]["version"] == "0.1.0"
    assert {path: set(operations) for path, operations in schema["paths"].items()} == {
        "/auth/register": {"post"},
        "/auth/login": {"post"},
        "/auth/me": {"get"},
        "/settings": {"get", "put"},
        "/diagnostics/health": {"get"},
        "/diagnostics": {"post"},
        "/health": {"get"},
        "/health/live": {"get"},
        "/health/ready": {"get"},
        "/download": {"get"},
    }

    register = schema["paths"]["/auth/register"]["post"]
    login = schema["paths"]["/auth/login"]["post"]
    current_user = schema["paths"]["/auth/me"]["get"]
    settings_get = schema["paths"]["/settings"]["get"]
    settings_put = schema["paths"]["/settings"]["put"]
    assert register["requestBody"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/UserCreate"
    }
    assert register["responses"]["201"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/Token"
    }
    assert login["requestBody"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/UserLogin"
    }
    assert login["responses"]["200"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/Token"
    }
    assert current_user["responses"]["200"]["content"]["application/json"][
        "schema"
    ] == {"$ref": "#/components/schemas/UserOut"}
    assert settings_put["requestBody"]["content"]["application/json"]["schema"] == {
        "$ref": "#/components/schemas/SettingsUpdate"
    }
    for operation in (settings_get, settings_put):
        assert operation["responses"]["200"]["content"]["application/json"][
            "schema"
        ] == {"$ref": "#/components/schemas/SettingsOut"}
        assert operation["security"] == [{"HTTPBearer": []}]
    assert current_user["security"] == [{"HTTPBearer": []}]

    components = schema["components"]
    assert components["securitySchemes"]["HTTPBearer"] == {
        "type": "http",
        "scheme": "bearer",
    }
    user_create = components["schemas"]["UserCreate"]
    assert set(user_create["required"]) == {"email", "password"}
    assert set(user_create["properties"]) == {"email", "password"}
    assert user_create["properties"]["email"]["format"] == "email"
    assert user_create["properties"]["password"]["minLength"] == 8
    assert user_create["properties"]["password"]["maxLength"] == 72

    user_login = components["schemas"]["UserLogin"]
    assert set(user_login["properties"]) == {"email", "password"}
    assert set(user_login["required"]) == {"email", "password"}
    assert user_login["properties"]["email"]["format"] == "email"

    token = components["schemas"]["Token"]
    assert set(token["properties"]) == {"access_token", "token_type"}
    assert token["required"] == ["access_token"]
    assert token["properties"]["token_type"]["default"] == "bearer"

    user_out = components["schemas"]["UserOut"]
    assert set(user_out["properties"]) == {"id", "email", "created_at"}
    assert set(user_out["required"]) == {"id", "email", "created_at"}
    assert user_out["properties"]["email"]["format"] == "email"
    assert user_out["properties"]["created_at"]["format"] == "date-time"

    settings_out = components["schemas"]["SettingsOut"]
    settings_update = components["schemas"]["SettingsUpdate"]
    settings_fields = {
        "theme_mode",
        "locale",
        "confidence_threshold",
        "tuning_a4",
        "updated_at",
    }
    assert set(settings_out["properties"]) == settings_fields
    assert set(settings_out["required"]) == settings_fields
    assert settings_update["additionalProperties"] is False
    assert set(settings_update["properties"]) == settings_fields - {"updated_at"}
    update_properties = settings_update["properties"]
    assert update_properties["theme_mode"]["anyOf"][0]["enum"] == [
        "light",
        "dark",
        "system",
    ]
    assert update_properties["locale"]["anyOf"][0]["enum"] == ["en", "hu"]
    confidence = update_properties["confidence_threshold"]["anyOf"][0]
    assert confidence["minimum"] == 0.0
    assert confidence["maximum"] == 1.0
    tuning = update_properties["tuning_a4"]["anyOf"][0]
    assert tuning["minimum"] == 400
    assert tuning["maximum"] == 480


def test_boolean_columns_never_use_an_integer_server_default():
    """A ``sa.Boolean()`` oszlop server_default-ja SOSEM egész literál.

    MÉRT hibaosztály (2026-09-05, első valódi Postgres-deploy): három community
    migráció ``server_default=sa.text("0")`` / ``sa.text("1")`` alakot használt.
    SQLite-on ez működik (nincs natív bool), Postgres viszont elutasítja::

        psycopg.errors.DatatypeMismatch: column "is_read" is of type boolean
        but default expression is of type integer

    Ezért az ``alembic upgrade head`` a repó SAJÁT ajánlott adatbázisán
    (``backend/README.md``: "Production database: PostgreSQL is recommended")
    a legelső deployon elhasalt — a meglévő migrációs tesztek mind SQLite-on
    futnak, tehát a rés NÉMA volt.

    A guard SZÁNDÉKOSAN statikus és dialektus-független: nem igényel futó
    Postgrest, ezért CI-ben is fut. A helyes alak ``sa.false()`` / ``sa.true()``
    — a SQLAlchemy dialektusonként rendereli.
    """
    offenders: list[str] = []
    versions = _ALEMBIC_SCRIPTS / "versions"
    for path in sorted(versions.glob("*.py")):
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            stripped = line.strip()
            if not stripped.startswith("server_default=sa.text("):
                continue
            literal = stripped[len("server_default=sa.text(") :].rstrip("),")
            if literal.strip("\"'") not in {"0", "1"}:
                continue
            # A megelőző néhány sor mondja meg az oszlop típusát.
            window = " ".join(lines[max(0, index - 4) : index])
            if "sa.Boolean(" in window:
                offenders.append(f"{path.name}:{index + 1} → {stripped}")

    assert offenders == [], (
        "Boolean oszlop egész literál server_default-tal — Postgresen "
        "DatatypeMismatch. Használj sa.false() / sa.true() alakot:\n  "
        + "\n  ".join(offenders)
    )
