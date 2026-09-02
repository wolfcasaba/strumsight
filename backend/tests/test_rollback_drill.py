"""E12-R26 — rollback verification and post-restore client compatibility.

Acceptance-map (round brief §0.0.1 P1-P8, §6):
  A1  test_full_backup_restore_verify_chain_matches
      test_verify_rollback_fails_closed_on_missing_backup
      test_verify_rollback_fails_on_record_count_mismatch
      test_verify_rollback_fails_on_migration_head_mismatch
      test_verify_rollback_flag_profile_fails_closed_unless_explicitly_opted_out
  A2  test_restored_database_smoke_passes_registration_login_and_settings_read
      (revised per §0.0.1 P2: no API versioning exists in the backend — the
      smoke cell is the client's ACTUAL endpoint set against the restored
      schema, not a "previous client version" protocol negotiation)

The restore target is ALWAYS a `tmp_path` file — this round's drill never
touches the developer's `backend/strumsight.db` (brief §0.0.1 P8).
"""

import json
import sys
from pathlib import Path

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
_REPO_ROOT = _BACKEND_ROOT.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tool.release import verify_rollback  # noqa: E402


def _alembic_config() -> Config:
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return config


def _seed_user(database_url: str, *, email: str = "drill@strumsight.app") -> None:
    engine = create_database_engine(database_url)
    try:
        session_factory = sessionmaker(bind=engine)
        with session_factory() as session:
            user = User(email=email, hashed_password="not-a-real-hash")
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


def _build_source_and_backup(tmp_path, monkeypatch, *, name: str) -> Path:
    source_url = f"sqlite:///{tmp_path / f'{name}-source.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", source_url)
    command.upgrade(_alembic_config(), "head")
    _seed_user(source_url)
    backup_path = tmp_path / f"{name}-backup.json"
    exit_code = backup_script.main(
        ["--database-url", source_url, "--output", str(backup_path)]
    )
    assert exit_code == 0
    return backup_path


# ---------------------------------------------------------------------------
# A1 — verify_rollback.py after a real backup → restore chain
# ---------------------------------------------------------------------------


def test_full_backup_restore_verify_chain_matches(tmp_path, monkeypatch):
    backup_path = _build_source_and_backup(tmp_path, monkeypatch, name="chain")

    target_url = f"sqlite:///{tmp_path / 'chain-target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r26-drill-chain",
        ]
    )
    assert restore_exit == 0

    report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=backup_path,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    assert report.ok, report.format()
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "PASS"
    assert by_name["record_counts"].status == "PASS"
    assert by_name["model_manifest"].status == "PASS"
    # A5's input: every dimension carries a measured (non-negative) duration.
    for dimension in report.dimensions:
        assert dimension.elapsed_seconds >= 0

    cli_exit = verify_rollback.main(
        [
            "--database-url",
            target_url,
            "--backup",
            str(backup_path),
            "--project-root",
            str(_REPO_ROOT),
            "--no-flag-profile",
        ]
    )
    assert cli_exit == 0


def test_verify_rollback_fails_closed_on_missing_backup(tmp_path):
    """P4's fail-closed rule: a missing input is FAIL, never SKIPPED, and the
    CLI exit code is non-zero — the class of bug the [L566] halt measured."""
    target_url = f"sqlite:///{tmp_path / 'no-target.db'}"
    missing_backup = tmp_path / "does-not-exist.json"

    report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=missing_backup,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    assert not report.ok
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "FAIL"
    assert by_name["record_counts"].status == "FAIL"
    # Neither of these depends on a discretionary opt-out (unlike
    # flag_profile, explicitly skipped above) — a missing backup dump must
    # never turn them SKIPPED.
    assert by_name["migration_head"].status != "SKIPPED"
    assert by_name["record_counts"].status != "SKIPPED"

    cli_exit = verify_rollback.main(
        [
            "--database-url",
            target_url,
            "--backup",
            str(missing_backup),
            "--project-root",
            str(_REPO_ROOT),
            "--no-flag-profile",
        ]
    )
    assert cli_exit != 0


def test_verify_rollback_fails_on_record_count_mismatch(tmp_path, monkeypatch):
    backup_path = _build_source_and_backup(tmp_path, monkeypatch, name="countdiff")

    target_url = f"sqlite:///{tmp_path / 'countdiff-target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r26-drill-countdiff",
        ]
    )
    assert restore_exit == 0

    # Mutate the RESTORED target so its row count diverges from the backup —
    # this must turn record_counts PIROS even though the migration head still
    # matches (mátrix row: "a fej egyezik, de a rekordszámok nem
    # ellenőrzöttek" — the whole point of a numeric, not connectivity, check).
    _seed_user(target_url, email="extra-after-restore@strumsight.app")

    report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=backup_path,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    assert not report.ok
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "PASS"
    assert by_name["record_counts"].status == "FAIL"
    assert "users" in by_name["record_counts"].detail


def test_verify_rollback_fails_on_migration_head_mismatch(tmp_path, monkeypatch):
    """A restore whose target is being reconciled against the WRONG backup
    (recorded revision does not match the live head) must FAIL — this is
    also the cell the §10 valódi-sértés próba (mutating check_migration_head
    to a warning) is expected to turn PIROS."""
    backup_path = _build_source_and_backup(tmp_path, monkeypatch, name="headdiff")

    target_url = f"sqlite:///{tmp_path / 'headdiff-target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r26-drill-headdiff",
        ]
    )
    assert restore_exit == 0

    tampered_backup_path = tmp_path / "headdiff-backup-tampered.json"
    tampered = json.loads(backup_path.read_text())
    tampered["revision"] = "e01_r12_0001"
    tampered_backup_path.write_text(json.dumps(tampered))

    report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=tampered_backup_path,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    assert not report.ok
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "FAIL"


def test_verify_rollback_flag_profile_fails_closed_unless_explicitly_opted_out(
    tmp_path, monkeypatch
):
    backup_path = _build_source_and_backup(tmp_path, monkeypatch, name="flagprofile")

    target_url = f"sqlite:///{tmp_path / 'flagprofile-target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r26-drill-flagprofile",
        ]
    )
    assert restore_exit == 0

    # No --expected/--observed given, no opt-out: FAIL, not silently SKIPPED.
    report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=backup_path,
        project_root=_REPO_ROOT,
    )
    assert not report.ok
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["flag_profile"].status == "FAIL"

    # The ONLY way to leave it out is the explicit opt-out, and the skip is
    # itself visible in the report (never silent).
    skipped_report = verify_rollback.run_verification(
        database_url=target_url,
        backup_path=backup_path,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    skipped_by_name = {d.name: d for d in skipped_report.dimensions}
    assert skipped_by_name["flag_profile"].status == "SKIPPED"
    assert skipped_report.ok


# ---------------------------------------------------------------------------
# A2 — restored schema serves the shipped client's actual endpoint set
# (§0.0.1 P2 revision: no API versioning exists in this backend)
# ---------------------------------------------------------------------------


def test_restored_database_smoke_passes_registration_login_and_settings_read(
    tmp_path, monkeypatch
):
    backup_path = _build_source_and_backup(tmp_path, monkeypatch, name="smoke")

    target_url = f"sqlite:///{tmp_path / 'smoke-target.db'}"
    restore_exit = restore_script.main(
        [
            "--database-url",
            target_url,
            "--input",
            str(backup_path),
            "--target-name",
            "e12-r26-drill-smoke",
        ]
    )
    assert restore_exit == 0

    # create_app + TestClient hitting the RESTORED database FILE — not the
    # conftest.py in-memory `client` fixture, which builds its schema with
    # `Base.metadata.create_all` and would never exercise the restore path.
    app = create_app(Settings(database_url=target_url))
    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": "smoke@strumsight.app", "password": "sixstrings"},
        )
        assert register.status_code == 201, register.text
        token = register.json()["access_token"]

        login = client.post(
            "/auth/login",
            json={"email": "smoke@strumsight.app", "password": "sixstrings"},
        )
        assert login.status_code == 200, login.text

        settings_read = client.get(
            "/settings", headers={"Authorization": f"Bearer {token}"}
        )
        assert settings_read.status_code == 200, settings_read.text
