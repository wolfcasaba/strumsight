"""Settings profile: defaults, partial update, null-locale, validation, auth.

Also covers `Settings.env` itself (ADR 0445, E12-R04 §0.0 R3): the closed
`dev | lab | staging | prod` value set with client-alias normalization
(`TestEnvironmentValueSet`) and the staging instantiation-time fail-closed
guard (`TestStagingIsolation`). The production guard
(`main.py::_guard_prod`, fired from `create_app()`) is out of scope here —
its regression coverage lives in `test_hardening.py::TestProdBootGuards`,
which this round does not edit.
"""

import pytest
from pydantic import ValidationError

from app.config import Settings
from app.main import create_app


def test_settings_default_on_new_user(client, auth_headers):
    resp = client.get("/settings", headers=auth_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["theme_mode"] == "system"
    assert data["locale"] is None
    assert data["confidence_threshold"] == 0.45
    assert data["tuning_a4"] == 440


def test_partial_update_only_touches_sent_fields(client, auth_headers):
    resp = client.put(
        "/settings",
        headers=auth_headers,
        json={"theme_mode": "dark", "confidence_threshold": 0.7},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["theme_mode"] == "dark"
    assert data["confidence_threshold"] == 0.7
    # Untouched fields keep their defaults.
    assert data["tuning_a4"] == 440
    assert data["locale"] is None


def test_set_and_clear_locale(client, auth_headers):
    client.put("/settings", headers=auth_headers, json={"locale": "hu"})
    assert client.get("/settings", headers=auth_headers).json()["locale"] == "hu"

    # Explicit null clears it (follow system) — distinct from omitting the key.
    client.put("/settings", headers=auth_headers, json={"locale": None})
    assert client.get("/settings", headers=auth_headers).json()["locale"] is None


def test_update_persists_across_requests(client, auth_headers):
    client.put("/settings", headers=auth_headers, json={"tuning_a4": 432})
    assert client.get("/settings", headers=auth_headers).json()["tuning_a4"] == 432


def test_validation_rejects_out_of_range(client, auth_headers):
    assert (
        client.put(
            "/settings", headers=auth_headers, json={"confidence_threshold": 1.5}
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/settings", headers=auth_headers, json={"tuning_a4": 700}
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/settings", headers=auth_headers, json={"theme_mode": "neon"}
        ).status_code
        == 422
    )
    # Unknown fields are rejected (extra="forbid").
    assert (
        client.put("/settings", headers=auth_headers, json={"nope": 1}).status_code
        == 422
    )


def test_explicit_null_on_nonnullable_fields_is_422_not_500(client, auth_headers):
    # Round 122 — the "omit vs null" contract is only valid for `locale`.
    # An explicit null on a NOT-NULL column used to reach the ORM and 500
    # (IntegrityError / response-validation failure); it must be a clean 422.
    for field in ("theme_mode", "confidence_threshold", "tuning_a4"):
        resp = client.put("/settings", headers=auth_headers, json={field: None})
        assert resp.status_code == 422, f"{field}: {resp.status_code}"
    # A rejected update must not have mutated anything.
    data = client.get("/settings", headers=auth_headers).json()
    assert data["theme_mode"] == "system"
    assert data["confidence_threshold"] == 0.45
    assert data["tuning_a4"] == 440


def test_settings_require_auth(client):
    assert client.get("/settings").status_code == 403
    assert client.put("/settings", json={"theme_mode": "dark"}).status_code == 403


def test_settings_are_per_user(client):
    a = client.post(
        "/auth/register", json={"email": "a@ex.com", "password": "sixstrings"}
    ).json()["access_token"]
    b = client.post(
        "/auth/register", json={"email": "b@ex.com", "password": "sixstrings"}
    ).json()["access_token"]

    client.put(
        "/settings",
        headers={"Authorization": f"Bearer {a}"},
        json={"tuning_a4": 432},
    )
    # B is unaffected by A's change.
    b_settings = client.get(
        "/settings", headers={"Authorization": f"Bearer {b}"}
    ).json()
    assert b_settings["tuning_a4"] == 440


class TestEnvironmentValueSet:
    """`Settings.env` closed value set + client-alias normalization
    (ADR 0445 D1-D2, E12-R04 acceptance A1/A1b/A2/A3)."""

    @pytest.mark.parametrize("raw", ["prod uction", "qa", "PRODUCTION!"])
    def test_unknown_value_refuses_to_instantiate(self, raw):
        with pytest.raises(ValidationError, match="not a recognized environment"):
            Settings(env=raw)

    @pytest.mark.parametrize(
        "raw, expected",
        [
            ("", "dev"),
            ("  ", "dev"),
            ("development", "dev"),
            ("DEV", "dev"),
            ("production", "prod"),
            ("PROD ", "prod"),
            ("lab", "lab"),
        ],
    )
    def test_aliases_normalize_to_canonical_values(self, raw, expected):
        # "staging" is deliberately excluded here: it also instantiation-time
        # guards on repo-default secrets (D4), so its normalization is
        # covered together with that guard in
        # TestStagingIsolation::test_real_secrets_instantiate_cleanly_with_lab_flags_off_by_default.
        assert Settings(env=raw).env == expected

    def test_staging_alias_normalizes_with_real_secrets(self):
        assert (
            Settings(
                env="STAGING ",
                secret_key="fake-staging-secret-not-the-dev-default",
                cors_origins=["https://staging.strumsight.app"],
                allow_sqlite_in_prod=True,
            ).env
            == "staging"
        )

    def test_missing_value_defaults_to_dev(self):
        assert Settings().env == "dev"

    def test_prod_with_dev_secret_instantiates_but_create_app_still_refuses_to_boot(
        self,
    ):
        """Regression guard (E12-R04 §0.0 R2): the production secret check
        stays in `main.py::_guard_prod`, fired from `create_app()` — it must
        NOT move to `Settings` instantiation, or the existing
        `test_hardening.py::TestProdBootGuards` cells that instantiate
        `Settings(env="prod", ...)` with a dev secret before asserting on
        `create_app()` would break."""
        settings = Settings(env="prod", cors_origins=["https://app.strumsight.app"])
        assert settings.env == "prod"
        with pytest.raises(RuntimeError, match="secret"):
            create_app(settings)

    def test_production_alias_gets_the_same_production_guard_as_prod(self):
        settings = Settings(
            env="production",
            secret_key="fake-production-secret-not-the-dev-default",
            cors_origins=["https://app.strumsight.app"],
            diagnostics_enabled=True,
        )
        assert settings.env == "prod"
        with pytest.raises(RuntimeError, match="diagnostics token"):
            create_app(settings)


class TestStagingIsolation:
    """Staging instantiation-time fail-closed guard (ADR 0445 D4, E12-R04
    acceptance A4). Unlike production, an insecure staging config never
    reaches `create_app()` — `Settings(...)` itself refuses."""

    _REAL_SECRET = "fake-staging-secret-not-the-dev-default"
    _REAL_CORS = ["https://staging.strumsight.app"]

    def test_dev_secret_key_refuses_to_instantiate(self):
        with pytest.raises(ValidationError, match="secret"):
            Settings(
                env="staging",
                cors_origins=self._REAL_CORS,
                allow_sqlite_in_prod=True,
            )

    def test_wildcard_cors_refuses_to_instantiate(self):
        with pytest.raises(ValidationError, match="CORS"):
            Settings(
                env="staging",
                secret_key=self._REAL_SECRET,
                allow_sqlite_in_prod=True,
            )

    def test_dev_diag_token_with_diagnostics_enabled_refuses_to_instantiate(self):
        with pytest.raises(ValidationError, match="diagnostics token"):
            Settings(
                env="staging",
                secret_key=self._REAL_SECRET,
                cors_origins=self._REAL_CORS,
                allow_sqlite_in_prod=True,
                diagnostics_enabled=True,
            )

    def test_sqlite_without_escape_hatch_refuses_to_instantiate(self, monkeypatch):
        monkeypatch.delenv("STRUMSIGHT_ALLOW_SQLITE", raising=False)
        with pytest.raises(ValidationError, match="SQLite"):
            Settings(
                env="staging",
                secret_key=self._REAL_SECRET,
                cors_origins=self._REAL_CORS,
            )

    def test_real_secrets_instantiate_cleanly_with_lab_flags_off_by_default(self):
        settings = Settings(
            env="staging",
            secret_key=self._REAL_SECRET,
            cors_origins=self._REAL_CORS,
            allow_sqlite_in_prod=True,
        )
        assert settings.env == "staging"
        assert settings.diagnostics_enabled is False
        assert settings.apk_download_enabled is False
