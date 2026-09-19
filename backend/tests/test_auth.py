"""Auth flow: register, login, /me, and the failure paths."""

import bcrypt
import pytest

from app import security
from app.security import hash_password, verify_password


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_register_returns_token_and_creates_user(client):
    resp = client.post(
        "/auth/register",
        json={"email": "New@Example.com", "password": "sixstrings"},
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    assert token

    # The token works against /me and the email was normalised to lowercase.
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "new@example.com"


def test_register_duplicate_email_conflicts(client):
    body = {"email": "dup@example.com", "password": "sixstrings"}
    assert client.post("/auth/register", json=body).status_code == 201
    resp = client.post("/auth/register", json=body)
    assert resp.status_code == 409


def test_register_rejects_short_password(client):
    resp = client.post(
        "/auth/register", json={"email": "x@example.com", "password": "short"}
    )
    assert resp.status_code == 422


def test_register_and_login_accept_72_utf8_byte_password(client):
    password = "é" * 36
    assert len(password) == 36
    assert len(password.encode("utf-8")) == 72

    registered = client.post(
        "/auth/register",
        json={"email": "unicode72@example.com", "password": password},
    )
    logged_in = client.post(
        "/auth/login",
        json={"email": "unicode72@example.com", "password": password},
    )

    assert registered.status_code == 201, registered.text
    assert logged_in.status_code == 200, logged_in.text


def test_register_rejects_73_utf8_byte_password(client):
    password = ("é" * 36) + "a"
    assert len(password) == 37
    assert len(password.encode("utf-8")) == 73

    response = client.post(
        "/auth/register",
        json={"email": "unicode73@example.com", "password": password},
    )

    assert response.status_code == 422
    assert "72 UTF-8 bytes" in response.text


def test_hash_password_rejects_overlong_utf8_input():
    password = ("é" * 36) + "a"

    with pytest.raises(ValueError, match="72 UTF-8 bytes"):
        hash_password(password)


def test_production_cost_factor_hashes_and_verifies(production_password_hashing):
    """Pin the bcrypt work factor every deployment runs with.

    The suite itself hashes at a cheap cost — `tests/conftest.py` rebinds
    `app.security.PASSWORD_HASH_ROUNDS` for the pytest process only, because
    at the production cost the fixtures alone cost minutes. This test asks
    the `production_password_hashing` fixture to put the real value back, so
    the shipped cost factor is asserted (not merely assumed) and a hash minted
    at it still round-trips through `verify_password`.
    """
    assert production_password_hashing == 12
    assert security.PASSWORD_HASH_ROUNDS == 12

    hashed = hash_password("sixstrings")

    assert hashed.startswith("$2b$12$"), hashed[:7]
    assert verify_password("sixstrings", hashed) is True
    assert verify_password("wrong-password", hashed) is False


def test_verify_password_keeps_legacy_72_byte_truncation_compatibility():
    legacy_password = ("é" * 36) + "legacy-suffix"
    legacy_hash = bcrypt.hashpw(
        legacy_password.encode("utf-8")[:72],
        bcrypt.gensalt(),
    ).decode("utf-8")

    assert verify_password(legacy_password, legacy_hash) is True


def test_login_success_and_wrong_password(client):
    client.post(
        "/auth/register",
        json={"email": "log@example.com", "password": "sixstrings"},
    )

    ok = client.post(
        "/auth/login",
        json={"email": "log@example.com", "password": "sixstrings"},
    )
    assert ok.status_code == 200
    assert ok.json()["token_type"] == "bearer"

    bad = client.post(
        "/auth/login",
        json={"email": "log@example.com", "password": "wrongpass"},
    )
    assert bad.status_code == 401


def test_login_unknown_email(client):
    resp = client.post(
        "/auth/login",
        json={"email": "ghost@example.com", "password": "whatever1"},
    )
    assert resp.status_code == 401


def test_unknown_email_and_wrong_password_responses_are_byte_identical(client):
    client.post(
        "/auth/register",
        json={"email": "known@example.com", "password": "sixstrings"},
    )

    wrong_password = client.post(
        "/auth/login",
        json={"email": "known@example.com", "password": "wrongpass"},
    )
    unknown_email = client.post(
        "/auth/login",
        json={"email": "unknown@example.com", "password": "wrongpass"},
    )

    assert wrong_password.status_code == 401
    assert unknown_email.status_code == 401
    assert wrong_password.content == unknown_email.content


def test_me_requires_auth(client):
    assert client.get("/auth/me").status_code == 403  # no bearer at all
    bad = client.get("/auth/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert bad.status_code == 401
