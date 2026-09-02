"""E12-R31 — production_smoke.py endpoint-contract cells (round brief §0.0.1
P1-P5, §6, §7).

`tool/release/production_smoke.py`'s `run_checks()` accepts any client
exposing `.get(path, headers=)` / `.post(path, json=, headers=)` — this file
passes it a REAL `fastapi.testclient.TestClient` around a fully migrated,
prod-configured `create_app()` app, so the same functions the CLI calls
against a live deploy are exercised here against the real routers, in
process, with no network.

Acceptance-map:
  A1  test_full_smoke_run_passes_against_a_freshly_migrated_prod_app
  A2  test_lab_routes_absent_by_default_in_prod (legacy reference:
      test_hardening.py::TestProdHardening::
      test_prod_defaults_do_not_register_lab_routes)
      + the §6.1/§7 REAL-BREACH probe (documented in the round brief §10):
      test_real_breach_probe_lab_surface_enabled_turns_the_check_red
      + the MAJOR-1 fix's own isolation cell (review E12-R31, documented in
      the round brief §10): test_apk_download_enabled_alone_turns_the_check_red
  readiness / traffic gate (§0.0.1 P1):
      test_readiness_check_reports_ready_after_migration
      test_business_checks_report_the_traffic_gate_reason_not_a_generic_failure
  fingerprint / model-manifest (§0.0.1 P2/P4, offline/local — the backend-side
  companion to the CLI-argument cells in
  test/tooling/production_readiness_test.dart):
      test_fingerprint_check_matches_sidecar
      test_fingerprint_check_fails_closed_on_missing_key
      test_model_manifest_check_local_artifact
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from alembic.config import Config
from fastapi.testclient import TestClient

from alembic import command
from app.config import Settings
from app.main import create_app

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = _BACKEND_ROOT.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tool.release import production_smoke as smoke  # noqa: E402

_SMOKE_EMAIL = "smoke@strumsight.app"
_SMOKE_PASSWORD = "fake-correct-horse-battery-staple"
_FINGERPRINT = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88"


def _alembic_config() -> Config:
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return config


def _migrated_prod_settings(tmp_path: Path, monkeypatch, **overrides) -> Settings:
    """A migrated-to-head, prod-profile `Settings` — the traffic gate
    (ADR 0449 D1) is satisfied so business endpoints behave normally, not
    with a generic 503 (§0.0.1 P1)."""
    database_url = f"sqlite:///{tmp_path / 'smoke-contract.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")
    defaults = dict(
        env="prod",
        secret_key="fake-a-real-32-char-production-secret",
        cors_origins=["https://app.strumsight.app"],
        diag_token="fake-a-real-deploy-diagnostics-token",
        database_url=database_url,
        allow_sqlite_in_prod=True,
    )
    defaults.update(overrides)
    return Settings(**defaults)


def _write_signing_certificate(
    tmp_path: Path, *, sha256_fingerprint: str | None
) -> Path:
    path = tmp_path / "signing-certificate.json"
    payload: dict[str, str] = {"keyAlias": "release"}
    if sha256_fingerprint is not None:
        payload["sha256Fingerprint"] = sha256_fingerprint
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def _write_model_manifest(asset_root: Path, *, valid: bool = True) -> None:
    manifest_dir = asset_root / "assets" / "ml"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = manifest_dir / "model_manifest.json"
    if valid:
        manifest_path.write_text(json.dumps({"models": []}), encoding="utf-8")
    else:
        manifest_path.write_text("{not json", encoding="utf-8")


def _results_by_name(results) -> dict[str, smoke.CheckResult]:
    return {result.name: result for result in results}


# ---------------------------------------------------------------------------
# A1 — the full check set, run against a real, migrated, prod-configured app
# ---------------------------------------------------------------------------


def test_full_smoke_run_passes_against_a_freshly_migrated_prod_app(
    tmp_path, monkeypatch
):
    settings = _migrated_prod_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": _SMOKE_EMAIL, "password": _SMOKE_PASSWORD},
        )
        assert register.status_code == 201, register.text

        _write_model_manifest(tmp_path)
        signing_certificate = _write_signing_certificate(
            tmp_path, sha256_fingerprint=_FINGERPRINT
        )

        results = smoke.run_checks(
            client,
            email=_SMOKE_EMAIL,
            password=_SMOKE_PASSWORD,
            signing_certificate=signing_certificate,
            expected_fingerprint=_FINGERPRINT,
            asset_root=tmp_path,
        )

    by_name = _results_by_name(results)
    assert set(by_name) == {
        "readiness",
        "auth_login",
        "auth_me",
        "settings",
        "community_feed",
        "lab_routes_absent",
        "fingerprint",
        "model_manifest",
    }
    for name, result in by_name.items():
        assert result.ok, f"{name} unexpectedly failed: {result.detail}"


# ---------------------------------------------------------------------------
# readiness / traffic gate — §0.0.1 P1
# ---------------------------------------------------------------------------


def test_readiness_check_reports_ready_after_migration(tmp_path, monkeypatch):
    settings = _migrated_prod_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        result = smoke.check_readiness(client)

    assert result.ok, result.detail
    assert result.detail == "ready"


def test_business_checks_report_the_traffic_gate_reason_not_a_generic_failure(tmp_path):
    """Deliberately UNMIGRATED — the ADR 0449 D1 gate must 503 every
    business endpoint with `{"status": "not_ready", "reason":
    "migration_mismatch"}`, and the smoke tool must surface that reason
    string, not a generic "unexpected status 503" (§0.0.1 P1)."""
    database_url = f"sqlite:///{tmp_path / 'unmigrated.db'}"
    settings = Settings(
        env="prod",
        secret_key="fake-a-real-32-char-production-secret",
        cors_origins=["https://app.strumsight.app"],
        diag_token="fake-a-real-deploy-diagnostics-token",
        database_url=database_url,
        allow_sqlite_in_prod=True,
    )
    app = create_app(settings)

    with TestClient(app) as client:
        readiness = smoke.check_readiness(client)
        login_result, me_result, token = smoke.check_auth(
            client, email=_SMOKE_EMAIL, password=_SMOKE_PASSWORD
        )

    assert readiness.ok is False
    assert "traffic gate active (not_ready)" in readiness.detail
    assert "migration_mismatch" in readiness.detail

    assert login_result.ok is False
    assert "traffic gate active (not_ready)" in login_result.detail
    assert token is None
    assert me_result.detail == "skipped: auth_login failed"


# ---------------------------------------------------------------------------
# A2 — the Lab-route triple must all 404 by default in prod (ADR 0061)
# ---------------------------------------------------------------------------


def test_lab_routes_absent_by_default_in_prod(tmp_path, monkeypatch):
    monkeypatch.delenv("STRUMSIGHT_DIAGNOSTICS_ENABLED", raising=False)
    monkeypatch.delenv("STRUMSIGHT_APK_DOWNLOAD_ENABLED", raising=False)
    settings = _migrated_prod_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        result = smoke.check_lab_routes_absent(client)

    assert result.ok, result.detail


def test_apk_download_enabled_alone_turns_the_check_red(tmp_path, monkeypatch):
    """MAJOR-1 (review E12-R31 CHANGES REQUESTED): isolates the `/download`
    leg from the two `/diagnostics` legs. The mandatory real-breach probe
    below flips ALL THREE env flags at once, so its aggregate RED cannot
    prove `/download` itself is measured — the `/diagnostics` legs alone are
    enough to redden it. This cell flips ONLY
    `STRUMSIGHT_APK_DOWNLOAD_ENABLED=true` (`STRUMSIGHT_DIAGNOSTICS_ENABLED`
    stays at its prod default, False) and no `STRUMSIGHT_APK_PATH` is
    staged, so `GET /download` still 404s ("no APK staged") exactly like an
    absent route would — only the `POST /download` wrong-method probe (405,
    since the route is registered for GET only) can catch this."""
    monkeypatch.delenv("STRUMSIGHT_DIAGNOSTICS_ENABLED", raising=False)
    settings = _migrated_prod_settings(tmp_path, monkeypatch, apk_download_enabled=True)
    assert settings.diagnostics_enabled is False, (
        "this cell must isolate /download alone"
    )
    app = create_app(settings)

    with TestClient(app) as client:
        result = smoke.check_lab_routes_absent(client)

    assert result.ok is False
    assert "POST /download: expected 404, got 405" in result.detail
    # Isolation proof: the /diagnostics legs are untouched by this flag —
    # if they showed up here too, this cell would not be measuring
    # /download in isolation.
    assert "/diagnostics" not in result.detail


def test_real_breach_probe_lab_surface_enabled_turns_the_check_red(
    tmp_path, monkeypatch
):
    """§6.1/§7 mandatory real-breach probe: enable the Lab surface exactly
    the way `test_hardening.py::test_prod_lab_routes_can_be_enabled_from_environment`
    does, run the SAME `check_lab_routes_absent` the smoke tool ships, and
    prove the A2 cell goes RED. `test_hardening.py` itself is untouched —
    this is an independent, agreeing measurement.

    MEASURED result (see round brief §10 for the transcript): with the Lab
    surface on, `POST /diagnostics` answers 401 (no `X-Diag-Token` sent) and
    `GET /diagnostics/health` answers 200 (unauthenticated by design) —
    neither is 404, so the aggregate check fails closed.
    """
    monkeypatch.setenv("STRUMSIGHT_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("STRUMSIGHT_APK_DOWNLOAD_ENABLED", "true")
    monkeypatch.setenv("STRUMSIGHT_DIAG_TOKEN", "a-real-deploy-diagnostics-token")
    settings = _migrated_prod_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        result = smoke.check_lab_routes_absent(client)

    assert result.ok is False
    assert "POST /diagnostics" in result.detail
    assert "GET /diagnostics/health" in result.detail
    assert "expected 404, got 401" in result.detail
    assert "expected 404, got 200" in result.detail


# ---------------------------------------------------------------------------
# fingerprint / model-manifest — §0.0.1 P2/P4, offline/local checks
# ---------------------------------------------------------------------------


def test_fingerprint_check_matches_sidecar(tmp_path):
    signing_certificate = _write_signing_certificate(
        tmp_path, sha256_fingerprint=_FINGERPRINT
    )
    result = smoke.check_fingerprint(signing_certificate, _FINGERPRINT)
    assert result.ok, result.detail


def test_fingerprint_check_rejects_a_mismatch(tmp_path):
    signing_certificate = _write_signing_certificate(
        tmp_path, sha256_fingerprint=_FINGERPRINT
    )
    result = smoke.check_fingerprint(signing_certificate, "00:11:22:33")
    assert result.ok is False
    assert "mismatch" in result.detail


def test_fingerprint_check_fails_closed_on_missing_key(tmp_path):
    """The mandated fail-CLOSED behaviour (round brief §5, §0.0.1 P2): a
    sidecar with no `sha256Fingerprint` key is a FAILURE, never a 0-exit
    pass."""
    signing_certificate = _write_signing_certificate(tmp_path, sha256_fingerprint=None)
    result = smoke.check_fingerprint(signing_certificate, _FINGERPRINT)
    assert result.ok is False
    assert "sha256Fingerprint" in result.detail


def test_fingerprint_check_fails_closed_on_missing_file(tmp_path):
    result = smoke.check_fingerprint(tmp_path / "does-not-exist.json", _FINGERPRINT)
    assert result.ok is False


def test_model_manifest_check_local_artifact(tmp_path):
    _write_model_manifest(tmp_path)
    result = smoke.check_model_manifest(tmp_path)
    assert result.ok, result.detail


def test_model_manifest_check_fails_on_missing_artifact(tmp_path):
    result = smoke.check_model_manifest(tmp_path)
    assert result.ok is False
    assert "not found" in result.detail


def test_model_manifest_check_fails_on_invalid_json(tmp_path):
    _write_model_manifest(tmp_path, valid=False)
    result = smoke.check_model_manifest(tmp_path)
    assert result.ok is False
    assert "not valid JSON" in result.detail
