# strumsight:allow-secret-file — every credential below is an invented test
# fixture; the file's PURPOSE is to exercise failed-credential handling.
"""R14 — operator diagnostics for failed logins, WITHOUT weakening the 401.

`docs/ui/apk-functionality-audit-2026-09-06.md` §5.4 could not decide, from
the live docker log alone, whether a `POST /auth/login 401` meant "no such
account" or "wrong password" — the response is deliberately uniform, and
nothing server-side recorded which branch fired. R14 adds ONE structured
INFO record per failure.

The two invariants these cells hold apart:

* the record carries the reason, the throttle bucket and a one-way e-mail
  fingerprint — never the address itself, never the password;
* the HTTP response is byte-identical to the pre-R14 one, so the uniform
  401 keeps the registered-address set private.
"""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path

import pytest
from alembic.config import Config

from alembic import command

_LOGGER_NAME = "app.routers.auth"
_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_EMAIL = "player@strumsight.app"
_UNKNOWN_EMAIL = "ghost@strumsight.app"


def _fingerprint(email: str) -> str:
    return hashlib.sha256(email.lower().encode("utf-8")).hexdigest()[:12]


@pytest.fixture
def auth_logs(caplog):
    caplog.set_level(logging.INFO, logger=_LOGGER_NAME)
    return caplog


def _records(caplog) -> list[logging.LogRecord]:
    return [r for r in caplog.records if r.name == _LOGGER_NAME]


def test_unknown_email_login_logs_the_reason_without_the_address(client, auth_logs):
    response = client.post(
        "/auth/login", json={"email": _UNKNOWN_EMAIL, "password": "wrong"}
    )

    assert response.status_code == 401
    records = _records(auth_logs)
    assert len(records) == 1
    message = records[0].getMessage()
    assert "auth.login_failed" in message
    assert "reason=unknown_email" in message
    assert f"email_hash={_fingerprint(_UNKNOWN_EMAIL)}" in message
    assert "client=" in message
    # The e-mail, its local part and the password never appear — in the
    # rendered message or in any raw argument.
    haystack = message + repr(records[0].args)
    assert _UNKNOWN_EMAIL not in haystack
    assert "ghost" not in haystack
    assert "wrong" not in haystack


def test_bad_password_login_is_distinguishable_server_side(
    client, auth_headers, auth_logs
):
    """`auth_headers` registers `player@strumsight.app` first, so this is the
    OTHER branch of the same uniform 401."""
    auth_logs.clear()

    response = client.post(
        "/auth/login", json={"email": _EMAIL, "password": "not-the-password"}
    )

    assert response.status_code == 401
    records = _records(auth_logs)
    assert len(records) == 1
    message = records[0].getMessage()
    assert "reason=bad_password" in message
    assert f"email_hash={_fingerprint(_EMAIL)}" in message
    assert _EMAIL not in message
    assert "not-the-password" not in message


def test_the_401_response_is_identical_for_both_failure_reasons(
    client, auth_headers, auth_logs
):
    """The whole point: the operator can tell the two apart, the caller
    cannot. Status, body and headers must match byte for byte."""
    unknown = client.post(
        "/auth/login", json={"email": _UNKNOWN_EMAIL, "password": "wrong"}
    )
    bad_password = client.post(
        "/auth/login", json={"email": _EMAIL, "password": "not-the-password"}
    )

    assert unknown.status_code == bad_password.status_code == 401
    assert unknown.content == bad_password.content
    assert unknown.json() == {"detail": "Incorrect email or password"}
    volatile = {"date", "server", "content-length"}
    assert {
        k.lower(): v for k, v in unknown.headers.items() if k.lower() not in volatile
    } == {
        k.lower(): v
        for k, v in bad_password.headers.items()
        if k.lower() not in volatile
    }


def test_successful_login_logs_nothing(client, auth_headers, auth_logs):
    auth_logs.clear()

    response = client.post(
        "/auth/login", json={"email": _EMAIL, "password": "sixstrings"}
    )

    assert response.status_code == 200
    assert _records(auth_logs) == []


def test_register_conflict_logs_the_reason_without_the_address(
    client, auth_headers, auth_logs
):
    auth_logs.clear()

    response = client.post(
        "/auth/register", json={"email": _EMAIL, "password": "another-password"}
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "An account with this email already exists"}
    records = _records(auth_logs)
    assert len(records) == 1
    message = records[0].getMessage()
    assert "auth.register_conflict" in message
    assert "reason=email_exists" in message
    assert f"email_hash={_fingerprint(_EMAIL)}" in message
    assert _EMAIL not in message
    assert "another-password" not in message


def test_the_logged_client_is_the_throttle_bucket_key(client, auth_logs):
    """`client=` must be the same key the limiter counts under, so a 429 and
    the failures that led to it can be correlated in one log window. The
    conftest `TestClient` peer is `testclient`."""
    client.post("/auth/login", json={"email": _UNKNOWN_EMAIL, "password": "wrong"})

    message = _records(auth_logs)[0].getMessage()
    assert "client=testclient" in message


def test_an_in_process_migration_does_not_silence_the_diagnostics(
    tmp_path, monkeypatch
):
    """MEASURED trap (R14): `alembic/env.py` configures logging with
    `logging.config.fileConfig`, whose DEFAULT `disable_existing_loggers=True`
    switches off every logger not named in `alembic.ini` — `app.routers.auth`
    among them. One in-process `alembic upgrade` then silenced these
    diagnostics for the rest of the process, which is exactly how this whole
    feature would become a no-op nobody notices. Found by the full suite:
    five cells above went red only when a migration test ran first.

    `fileConfig` also REPLACES the root handlers, so `caplog`'s handler is
    saved and restored here — the cell measures the logger's `disabled`
    state, not pytest's capture plumbing.
    """
    logger = logging.getLogger(_LOGGER_NAME)
    assert logger.disabled is False, "precondition: the logger starts enabled"

    monkeypatch.setenv(
        "STRUMSIGHT_DATABASE_URL", f"sqlite:///{tmp_path / 'alembic-logging.db'}"
    )
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    root = logging.getLogger()
    saved_handlers = root.handlers[:]
    saved_level = root.level
    try:
        command.upgrade(config, "head")
    finally:
        root.handlers[:] = saved_handlers
        root.setLevel(saved_level)

    assert logger.disabled is False, (
        "alembic's fileConfig disabled the auth logger — pass "
        "disable_existing_loggers=False in backend/alembic/env.py"
    )


def test_the_records_are_info_level_not_warnings(client, auth_logs):
    """Failed logins are routine; an INFO record keeps `docker compose logs
    api` readable and does not page anyone."""
    client.post("/auth/login", json={"email": _UNKNOWN_EMAIL, "password": "wrong"})

    assert [r.levelno for r in _records(auth_logs)] == [logging.INFO]
