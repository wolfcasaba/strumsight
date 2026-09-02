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

Fix round 1 (docs/reviews/e12-r26-review.md) — additional cells below the A1/A2
tests, one block per finding:
  MAJOR-1  test_full_backup_restore_verify_chain_matches (rewritten — see its
           docstring), test_verify_rollback_record_counts_fails_when_live_table_missing_from_dump,
           test_verify_rollback_record_counts_fails_on_unknown_dump_table,
           test_verify_rollback_record_counts_pass_detail_reports_compared_count
  MAJOR-3  test_verify_rollback_flag_profile_fails_on_empty_profile
  MAJOR-4  test_verify_rollback_load_flag_profile_does_not_echo_pii_or_password_hash
  MINOR-1  test_verify_rollback_model_manifest_rejects_absolute_path_traversal,
           test_verify_rollback_model_manifest_rejects_dotdot_path_traversal
  MINOR-2  test_verify_rollback_reports_dimension_fail_on_unsupported_driver_url
  MINOR-6  test_verify_rollback_dimension_result_ok_is_allowlist_not_denylist
"""

import json
import os
import subprocess
import sys
from pathlib import Path

from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from alembic import command
from app.config import Settings
from app.database import Base, create_database_engine
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
    """The REAL chain, run the way the drill and the runbook actually run
    it: `backup.py` as its OWN process — matching
    `docs/operations/disaster-recovery-drill.md` step 7 — not folded into
    this test's interpreter via `_build_source_and_backup`'s in-process
    `backup_script.main()` call.

    This distinction is load-bearing (MAJOR-1, docs/reviews/e12-r26-review.md):
    `alembic upgrade` imports EVERY migration file, and each Community
    migration imports its ORM model as a side effect, registering it onto
    the shared `Base.metadata` singleton FOR THE REST OF THE PROCESS. An
    in-process `backup_script.main()` call made AFTER an in-process
    `alembic upgrade` therefore (accidentally) sees the FULL 28-table
    schema in `Base.metadata` and dumps all of it — masking the real bug.
    `backend/scripts/backup.py`, run as its own process (as the runbook and
    every operator actually run it), only ever imports the narrow
    `app.models` (2 ORM tables: `users`, `user_settings`) — while the live
    schema, migrated to head, has 29 tables. The other 27 (Community) are
    created by raw-DDL migrations with no ORM model, so the real backup
    silently drops them (this is also the A6 runbook-lelet in
    docs/operations/disaster-recovery-drill.md §7)."""
    source_url = f"sqlite:///{tmp_path / 'chain-source.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", source_url)
    command.upgrade(_alembic_config(), "head")
    _seed_user(source_url)

    backup_path = tmp_path / "chain-backup.json"
    subprocess_result = subprocess.run(
        [
            sys.executable,
            "scripts/backup.py",
            "--database-url",
            source_url,
            "--output",
            str(backup_path),
        ],
        cwd=_BACKEND_ROOT,
        env={**os.environ, "PYTHONPATH": str(_BACKEND_ROOT)},
        capture_output=True,
        text=True,
    )
    assert subprocess_result.returncode == 0, subprocess_result.stderr

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
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "PASS"
    assert by_name["model_manifest"].status == "PASS"
    # MAJOR-1: the real backup.py only covers 2 of the 29 live tables — this
    # is the measured, CURRENT gap in the runbook chain (a `backend/scripts`
    # fix is out of this round's allowed-files list; see the A6
    # runbook-lelet). record_counts must FAIL, not silently PASS on a 2/29
    # comparison — that silent PASS was the bug this round's fix closes.
    assert by_name["record_counts"].status == "FAIL"
    assert "community_" in by_name["record_counts"].detail
    assert not report.ok

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
    assert cli_exit != 0


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


# ---------------------------------------------------------------------------
# Fix round 1 (docs/reviews/e12-r26-review.md) — one block per finding.
# ---------------------------------------------------------------------------


def test_verify_rollback_record_counts_fails_when_live_table_missing_from_dump(
    tmp_path,
):
    """MAJOR-1: a live table absent from the dump must FAIL — the class of
    bug where `check_record_counts` iterated the dump's own tables and
    silently `continue`d past anything the live database had that the dump
    didn't cover (the pre-fix `Base.metadata.sorted_tables` loop)."""
    database_url = f"sqlite:///{tmp_path / 'extra-live-table.db'}"
    engine = create_database_engine(database_url)
    try:
        Base.metadata.create_all(
            engine, tables=[User.__table__, UserSettings.__table__]
        )
    finally:
        engine.dispose()
    _seed_user(database_url)

    # `user_settings` exists live but the dump only covers `users`.
    backup = {"revision": "irrelevant", "tables": {"users": {"count": 1, "rows": []}}}
    result = verify_rollback.check_record_counts(database_url, backup)
    assert result.status == "FAIL"
    assert "user_settings" in result.detail


def test_verify_rollback_record_counts_fails_on_unknown_dump_table(tmp_path):
    """MAJOR-1: a dump table name with no live counterpart must FAIL, not be
    silently skipped."""
    database_url = f"sqlite:///{tmp_path / 'unknown-dump-table.db'}"
    engine = create_database_engine(database_url)
    try:
        Base.metadata.create_all(
            engine, tables=[User.__table__, UserSettings.__table__]
        )
    finally:
        engine.dispose()
    _seed_user(database_url)

    backup = {
        "revision": "irrelevant",
        "tables": {
            "users": {"count": 1, "rows": []},
            "user_settings": {"count": 1, "rows": []},
            "users_v1": {"count": 4242, "rows": []},
        },
    }
    result = verify_rollback.check_record_counts(database_url, backup)
    assert result.status == "FAIL"
    assert "users_v1" in result.detail


def test_verify_rollback_record_counts_pass_detail_reports_compared_count(tmp_path):
    """MAJOR-1: the PASS detail text must state the number of tables
    ACTUALLY compared (live ∩ dump) — the pre-fix text stated the dump's
    table count, which made a 2/29 comparison read as complete."""
    database_url = f"sqlite:///{tmp_path / 'matching-tables.db'}"
    engine = create_database_engine(database_url)
    try:
        Base.metadata.create_all(
            engine, tables=[User.__table__, UserSettings.__table__]
        )
    finally:
        engine.dispose()
    _seed_user(database_url)

    backup = {
        "revision": "irrelevant",
        "tables": {
            "users": {"count": 1, "rows": []},
            "user_settings": {"count": 1, "rows": []},
        },
    }
    result = verify_rollback.check_record_counts(database_url, backup)
    assert result.status == "PASS"
    assert "2 table(s) compared" in result.detail


def test_verify_rollback_flag_profile_fails_on_empty_profile():
    """MAJOR-3: an empty `{}` profile on either side must FAIL, not PASS —
    the previous empty-vs-empty loop produced `0 flag(s) match` as a PASS,
    bypassing the "opt out ONLY via --no-flag-profile" contract (P4) without
    it ever showing up as SKIPPED in the report."""
    empty: dict = {}
    non_empty = {"communityEnabled": False}

    assert verify_rollback.check_flag_profile(empty, empty).status == "FAIL"
    assert verify_rollback.check_flag_profile(empty, non_empty).status == "FAIL"
    assert verify_rollback.check_flag_profile(non_empty, empty).status == "FAIL"


def test_verify_rollback_load_flag_profile_does_not_echo_pii_or_password_hash(
    tmp_path,
):
    """MAJOR-4: a type-mismatched flag-profile entry must report the key
    and the offending TYPE only, never the value — an operator who points
    --expected-flag-profile at a backup dump by mistake (also "a JSON file
    path") must not get PII or a bcrypt hash echoed into stdout, --json, or
    the drill log."""
    pii_email = "victim@example.com"
    bcrypt_hash = "$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXY"
    profile_path = tmp_path / "backup-mistaken-for-profile.json"
    profile_path.write_text(
        json.dumps(
            {
                "users": {
                    "count": 1,
                    "rows": [{"email": pii_email, "hashed_password": bcrypt_hash}],
                }
            }
        )
    )

    data, error = verify_rollback.load_flag_profile(profile_path)
    assert data is None
    assert error is not None
    assert pii_email not in error
    assert bcrypt_hash not in error
    assert "dict" in error


def test_verify_rollback_model_manifest_rejects_absolute_path_traversal(tmp_path):
    """MINOR-1: an absolute `models[].path` must resolve UNDER
    project_root and FAIL otherwise — not be read and hashed. A manifest is
    a followed input, but the model-rollback use case is exactly a manifest
    arriving from a RESTORED package, where the trust level is lower than
    "on this tree today"."""
    project_root = tmp_path / "root"
    manifest_dir = project_root / "assets" / "ml"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "model_manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "models": [
                    {"filename": "evil.bin", "path": "/etc/passwd", "sha256": "0" * 64}
                ],
            }
        )
    )

    result = verify_rollback.check_model_manifest(project_root)
    assert result.status == "FAIL"
    assert "escapes project_root" in result.detail


def test_verify_rollback_model_manifest_rejects_dotdot_path_traversal(tmp_path):
    """MINOR-1, `..`-escape variant."""
    project_root = tmp_path / "root"
    manifest_dir = project_root / "assets" / "ml"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "model_manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "models": [
                    {
                        "filename": "evil.bin",
                        "path": "../../../etc/passwd",
                        "sha256": "0" * 64,
                    }
                ],
            }
        )
    )

    result = verify_rollback.check_model_manifest(project_root)
    assert result.status == "FAIL"
    assert "escapes project_root" in result.detail


def test_verify_rollback_reports_dimension_fail_on_unsupported_driver_url(tmp_path):
    """MINOR-2: a non-SQLAlchemy exception (a missing DB driver module, e.g.
    `postgresql://` with no `psycopg2` installed — the DB the drill log's §4
    explicitly discusses) inside a DB-touching dimension must still produce
    a FAIL dimension in the report, and the REST of the report must still
    run — not an uncaught traceback that aborts before model_manifest and
    flag_profile ever execute (P4: every dimension carries a status)."""
    backup_path = tmp_path / "backup.json"
    backup_path.write_text(json.dumps({"revision": "irrelevant", "tables": {}}))

    report = verify_rollback.run_verification(
        database_url="postgresql://user:secret-password@localhost/doesnotexist",
        backup_path=backup_path,
        project_root=_REPO_ROOT,
        skip_flag_profile=True,
    )
    assert not report.ok
    by_name = {d.name: d for d in report.dimensions}
    assert by_name["migration_head"].status == "FAIL"
    assert by_name["record_counts"].status == "FAIL"
    # The rest of the report still ran — a DB error in one dimension must
    # not abort the others.
    assert by_name["model_manifest"].status in {"PASS", "FAIL"}
    assert by_name["flag_profile"].status == "SKIPPED"
    assert "secret-password" not in by_name["migration_head"].detail
    assert "secret-password" not in by_name["record_counts"].detail


def test_verify_rollback_dimension_result_ok_is_allowlist_not_denylist():
    """MINOR-6: `DimensionResult.ok` must be an ALLOWLIST (`PASS`/`SKIPPED`),
    not a `!= FAIL` denylist — an unknown or mistyped status must fail
    closed instead of defaulting to `ok=True`."""
    unknown_status = verify_rollback.DimensionResult(
        "some_dimension", "UNKNOWN_STATUS", "n/a", 0.0
    )
    assert unknown_status.ok is False
