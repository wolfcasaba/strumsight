# strumsight:allow-secret-file — csak kitalalt teszt-titkok, staging.env.example titkot nem hordoz.
"""E12-R08 — readiness-vezerelt forgalmi kapu es mentes/visszaallitas (ADR 0449).

Acceptance-terkep (brief SS6):
  A1  test_traffic_gate_blocks_business_endpoint_on_migration_mismatch
  A2  test_traffic_gate_allows_normal_behavior_once_migrated
  A2b test_health_routes_stay_reachable_while_gate_is_active
  A3  test_backup_then_restore_round_trip
  A4  test_restore_refuses_to_overwrite_existing_data_without_double_confirmation
  A5  test_staging_env_example_carries_no_real_secret,
      test_staging_settings_reject_dev_default_secret_key
  A6  test_dockerfile_pins_base_image_by_digest_and_runs_as_non_root
  A7  meglevo backend-cellak (test_migrations.py, conftest-alapu auth/settings
      cellak) — a SS7 gate artefaktum bizonyitja, itt nincs uj cella.
"""

import re
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from alembic import command
from app.config import Settings
from app.database import create_database_engine
from app.main import create_app
from app.models import User, UserSettings
from scripts import backup as backup_script
from scripts import restore as restore_script

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_SCRIPTS = _BACKEND_ROOT / "alembic"

_INVALID_BEARER = {"Authorization": "Bearer not-a-real-token"}


def _alembic_config() -> Config:
    config = Config(str(_ALEMBIC_INI))
    config.set_main_option("script_location", str(_ALEMBIC_SCRIPTS))
    return config


def _deploy_settings(env: str, database_url: str, **overrides) -> Settings:
    """A valid staging/prod profile: both _guard_staging (instantiation) and
    _guard_prod (create_app) accept these fields, so the only reason a
    request is refused is the migration-head gate under test."""
    defaults = dict(
        env=env,
        secret_key="a-real-32-char-deploy-secret-value",
        cors_origins=["https://app.strumsight.example"],
        diag_token="a-real-deploy-diagnostics-token",
        database_url=database_url,
        allow_sqlite_in_prod=True,
    )
    defaults.update(overrides)
    return Settings(**defaults)


# ---------------------------------------------------------------------------
# A1 / A2 / A2b — readiness-driven traffic gate (ADR 0449 D1-D3)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("env", ["staging", "prod"])
def test_traffic_gate_blocks_business_endpoint_on_migration_mismatch(tmp_path, env):
    database_url = f"sqlite:///{tmp_path / f'{env}-unmigrated.db'}"
    app = create_app(_deploy_settings(env, database_url))

    with TestClient(app) as client:
        response = client.get("/settings", headers=_INVALID_BEARER)

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "reason": "migration_mismatch"}
    # A gated business handler never runs: an EXECUTED auth dependency would
    # reject this deliberately-invalid bearer token with 401, not with the
    # gate's 503 (brief SS6 A1: "nem 401/422/200").
    assert response.status_code not in (200, 401, 422)


@pytest.mark.parametrize("env", ["staging", "prod"])
def test_traffic_gate_allows_normal_behavior_once_migrated(tmp_path, monkeypatch, env):
    database_url = f"sqlite:///{tmp_path / f'{env}-migrated.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")

    app = create_app(_deploy_settings(env, database_url))

    with TestClient(app) as client:
        ready = client.get("/health/ready")
        response = client.get("/settings", headers=_INVALID_BEARER)

    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}
    # Normal, un-gated behavior resumes: the auth dependency runs and
    # rejects the invalid token with 401 — not the gate's 503.
    assert response.status_code == 401


def test_health_routes_stay_reachable_while_gate_is_active(tmp_path):
    database_url = f"sqlite:///{tmp_path / 'staging-unmigrated.db'}"
    app = create_app(_deploy_settings("staging", database_url))

    with TestClient(app) as client:
        health = client.get("/health")
        live = client.get("/health/live")
        ready = client.get("/health/ready")

    assert health.status_code == 200
    assert health.json()["status"] == "ok"
    # /health/live must not fall under the 503 block (it never touches the DB).
    assert live.status_code == 200
    assert live.json() == {"status": "ok"}
    # /health/ready stays reachable too — it reports its own not_ready
    # verdict rather than being swallowed by the gate.
    assert ready.status_code == 503
    assert ready.json() == {"status": "not_ready", "reason": "migration_mismatch"}


# ---------------------------------------------------------------------------
# A3 / A4 — backup + restore (ADR 0449 D4-D5)
# ---------------------------------------------------------------------------


def _seed_user(database_url: str) -> None:
    engine = create_database_engine(database_url)
    try:
        session_factory = sessionmaker(bind=engine)
        with session_factory() as session:
            user = User(
                email="restore@strumsight.app",
                hashed_password="not-a-real-hash",
            )
            session.add(user)
            session.flush()
            session.add(
                UserSettings(
                    user_id=user.id,
                    theme_mode="dark",
                    tuning_a4=442,
                    confidence_threshold=0.6,
                )
            )
            session.commit()
    finally:
        engine.dispose()


def test_backup_then_restore_round_trip(tmp_path, monkeypatch):
    source_url = f"sqlite:///{tmp_path / 'source.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", source_url)
    command.upgrade(_alembic_config(), "head")
    _seed_user(source_url)

    backup_path = tmp_path / "backup.json"
    backup_exit = backup_script.main(
        ["--database-url", source_url, "--output", str(backup_path)]
    )
    assert backup_exit == 0

    source_snapshot = backup_script.dump_database(source_url)
    assert source_snapshot["revision"] is not None
    assert source_snapshot["tables"]["users"]["count"] == 1

    target_url = f"sqlite:///{tmp_path / 'target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r08-test-target",
        ]
    )
    assert restore_exit == 0

    target_snapshot = backup_script.dump_database(target_url)
    assert target_snapshot == source_snapshot


def test_restore_refuses_to_overwrite_existing_data_without_double_confirmation(
    tmp_path, monkeypatch
):
    source_url = f"sqlite:///{tmp_path / 'source.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", source_url)
    command.upgrade(_alembic_config(), "head")
    _seed_user(source_url)
    backup_path = tmp_path / "backup.json"
    backup_script.main(["--database-url", source_url, "--output", str(backup_path)])

    target_url = f"sqlite:///{tmp_path / 'target.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", target_url)
    command.upgrade(_alembic_config(), "head")
    _seed_user(target_url)
    target_snapshot_before = backup_script.dump_database(target_url)

    # (1) no --force at all.
    exit_no_force = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r08-test-target",
        ]
    )
    assert exit_no_force != 0

    # (2) --force present, but --confirm-target missing/wrong.
    exit_wrong_confirm = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r08-test-target",
            "--force",
            "--confirm-target",
            "not-the-target-name",
        ]
    )
    assert exit_wrong_confirm != 0

    exit_missing_confirm = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r08-test-target",
            "--force",
        ]
    )
    assert exit_missing_confirm != 0

    target_snapshot_after = backup_script.dump_database(target_url)
    assert target_snapshot_after == target_snapshot_before


# ---------------------------------------------------------------------------
# A5 — staging profile carries no secret; the loaded guard rejects dev
# defaults (ADR 0449 D6)
# ---------------------------------------------------------------------------

_SECRET_LIKE_KEY = re.compile(r"(SECRET|TOKEN|_KEY)\b", re.IGNORECASE)
_PLACEHOLDER_VALUE = re.compile(r"^<.+>$")


def test_staging_env_example_carries_no_real_secret():
    content = (_BACKEND_ROOT / "deploy" / "staging.env.example").read_text()
    checked_any = False
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        if not _SECRET_LIKE_KEY.search(key):
            continue
        checked_any = True
        assert value == "" or _PLACEHOLDER_VALUE.match(value), (
            f"{key} must be empty or a <placeholder> in staging.env.example, "
            f"got {value!r}"
        )
    assert checked_any, "expected at least one secret-like key in staging.env.example"


def test_staging_settings_reject_dev_default_secret_key():
    with pytest.raises(Exception, match="secret key"):
        Settings(
            env="staging",
            cors_origins=["https://staging.strumsight.example"],
            diag_token="a-real-staging-diagnostics-token",
            allow_sqlite_in_prod=True,
        )


# ---------------------------------------------------------------------------
# A6 — Dockerfile pins the base image by digest and drops root (ADR 0449 D7)
# ---------------------------------------------------------------------------


def test_dockerfile_pins_base_image_by_digest_and_runs_as_non_root():
    content = (_BACKEND_ROOT / "Dockerfile").read_text()

    from_lines = [
        line for line in content.splitlines() if line.strip().upper().startswith("FROM")
    ]
    assert from_lines, "Dockerfile must declare a base image"
    for line in from_lines:
        assert "latest" not in line.lower(), f"no floating :latest tag: {line!r}"
        assert re.search(r"@sha256:[0-9a-fA-F]{64}\b", line), (
            f"FROM line must pin the base image by digest: {line!r}"
        )

    user_lines = [
        line.strip()
        for line in content.splitlines()
        if line.strip().upper().startswith("USER")
    ]
    assert user_lines, "Dockerfile must switch to a non-root USER"
    for line in user_lines:
        _, _, user_value = line.partition(" ")
        assert user_value.strip() not in ("root", "0"), (
            f"must not run as root: {line!r}"
        )
