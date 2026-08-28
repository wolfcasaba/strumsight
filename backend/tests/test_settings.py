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

    @pytest.mark.parametrize("blank_secret", ["", "   "])
    def test_empty_or_blank_secret_key_refuses_to_instantiate(self, blank_secret):
        # B2 regression: an empty/whitespace secret_key is not the dev
        # default, so a bare `== dev_secret` check would let it through —
        # a blank HS256 signing key is trivially forgeable.
        with pytest.raises(ValidationError, match="secret"):
            Settings(
                env="staging",
                secret_key=blank_secret,
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


class TestSecretsNeverLeakIntoErrors:
    """B1 regression (AGENTS.md §5 / 3. nem tárgyalható határ): a
    `ValidationError` HUMÁN-OLVASHATÓ alakja (`str(exc)`) — ami az
    `import app.config` alatt el nem kapott kivétel esetén szó szerint a
    boot-logba (uvicorn/gunicorn traceback) kerül — nem tartalmazhatja a
    beállított titkot, még akkor sem, ha a hiba egy MÁSIK mezőn (pl. `env`)
    dől el. pydantic alapból az egész bemeneti dict-et (`input_value`)
    visszaechózza ide; ezt `Settings.model_config`-ban a
    `hide_input_in_errors=True` némítja.

    Megjegyzés a `exc.errors()` (strukturált, nem-str alak) kapcsán: a
    pydantic-core `ValidationError.errors()`-nak van egy `include_input`
    paramétere, aminek az ALAPÉRTÉKE `True`, és ezt a `hide_input_in_errors`
    modellkonfig NEM módosítja (mért tény, pydantic 2.13 / pydantic-core
    2.46 — sem a régi, sem az új konfiggal nem redaktált). Egy `errors()`
    hívó tehát csak explicit `include_input=False`-fal kap redaktált
    kimenetet — de mivel `include_input=False` a titkot a JAVÍTÁS NÉLKÜL is
    kiszűrné, egy ilyen assert nem lenne valódi regresszió-őr (a
    falszifikációs próba nem váltana pirosra). Ezért ez a teszt `str(exc)`-et
    ellenőrzi (ez az, amit a `hide_input_in_errors` ténylegesen befolyásol,
    és ami a mért boot-log-reprodukcióban ténylegesen megjelent), plusz azt,
    hogy a `errors()[0]['msg']` humán szövege — amit a validátorok írnak —
    sosem ágyazza be a titkot közvetlenül (`grep -rn "\\.errors(" app/`
    megerősíti: a `Settings` `ValidationError`-ját semmilyen in-scope hívó
    nem szerializálja `errors()`-szel, tehát az `include_input=True`
    alapérték itt nem aktív kockázat)."""

    # NOTE on canary shape: pydantic-core reorders `input_value` to FIELD
    # DECLARATION order (not kwarg-call order — measured), then truncates
    # the dict's repr to a short head + a short (~22-25 char) tail. Only a
    # value short enough to fit that tail window is guaranteed to survive
    # truncation and thus prove the leak either way — this mirrors the
    # orchestrator's own repro, where the (short) DB password fully leaked
    # but the (longer) secret_key did not. Markers below are sized to that
    # window and placed as the LAST explicitly-set field in declaration
    # order (`env` < `secret_key` < `database_url`), so each test actually
    # exercises the leak path instead of trivially passing either way.
    _CANARY_SECRET = "cnrySecretX1"
    _CANARY_DATABASE_URL = "postgresql://a:cnryPW9@h/d"
    _CANARY_DB_MARKER = "cnryPW9"

    def test_unknown_env_error_does_not_leak_secret_key(self):
        # `secret_key` is the last explicitly-set field here, so its value
        # (not `database_url`, which is left at its default) sits in the
        # truncated tail.
        with pytest.raises(ValidationError) as excinfo:
            Settings(env="qa", secret_key=self._CANARY_SECRET)
        message = str(excinfo.value)
        error_texts = [err["msg"] for err in excinfo.value.errors()]
        assert self._CANARY_SECRET not in message
        assert all(self._CANARY_SECRET not in text for text in error_texts)

    def test_unknown_env_error_does_not_leak_database_url(self):
        # Mirrors the orchestrator's own repro (§0.0): unknown `env` +
        # `secret_key` + `database_url` all explicitly set, `database_url`
        # last in declaration order.
        with pytest.raises(ValidationError) as excinfo:
            Settings(
                env="qa",
                secret_key="not-the-canary",
                database_url=self._CANARY_DATABASE_URL,
            )
        message = str(excinfo.value)
        error_texts = [err["msg"] for err in excinfo.value.errors()]
        assert self._CANARY_DB_MARKER not in message
        assert all(self._CANARY_DB_MARKER not in text for text in error_texts)

    def test_staging_guard_error_does_not_leak_database_url(self):
        # `_guard_staging`'s first check (dev secret_key) fires before the
        # CORS/diag_token/SQLite checks, so a real `secret_key` isn't even
        # needed here to reach a `ValidationError` — the dev default alone
        # (E12-R04 review B1) is enough, leaving `database_url` (the
        # canary) as the last explicitly-set field in declaration order.
        with pytest.raises(ValidationError) as excinfo:
            Settings(env="staging", database_url=self._CANARY_DATABASE_URL)
        message = str(excinfo.value)
        error_texts = [err["msg"] for err in excinfo.value.errors()]
        assert self._CANARY_DB_MARKER not in message
        assert all(self._CANARY_DB_MARKER not in text for text in error_texts)
