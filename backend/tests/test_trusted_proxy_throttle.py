# strumsight:allow-secret-file — every credential below is an invented test
# fixture; the file's PURPOSE is to exercise the login/register throttle.
"""R14 — trusted-proxy awareness for the auth throttles.

MEASURED problem (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.4):
behind Caddy the container sees the docker-bridge address for EVERY caller,
so the 10/min login and 5/min register budgets were shared by all users and
the resulting 429 surfaced in the app as a generic network error.

The fix must not become a bypass: `X-Forwarded-For` is caller-supplied, so
it counts ONLY when the direct socket peer is a configured trusted proxy.
These cells pin both halves — honoured from a trusted peer, ignored from an
untrusted one — plus the unchanged default configuration.
"""

from __future__ import annotations

import pytest
from fastapi import Request
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.client_ip import UNKNOWN_CLIENT, client_ip_for_throttle
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db
from app.main import create_app
from app.routers.auth import login_limiter, register_limiter

_PROXY = "172.18.0.1"
_DIRECT_PEER = "10.0.0.5"


def _request(peer: str | None, forwarded: str | None) -> Request:
    """A bare ASGI scope — enough for the helper, no app or socket needed."""
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded else []
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/auth/login",
            "headers": headers,
            "client": (peer, 50000) if peer else None,
        }
    )


def _settings(**overrides) -> Settings:
    defaults = dict(_env_file=None, database_url="sqlite://", trusted_proxy_ips=[])
    defaults.update(overrides)
    return Settings(**defaults)


@pytest.fixture
def proxy_client_factory():
    """A `TestClient` whose socket peer and app settings are both chosen by
    the test (`TestClient(..., client=)` sets `scope["client"]`)."""
    created: list[TestClient] = []

    def factory(*, peer: str, trusted: list[str]) -> TestClient:
        engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        enable_sqlite_foreign_keys(engine)
        Base.metadata.create_all(bind=engine)
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = create_app(_settings(trusted_proxy_ips=trusted))

        def override_get_db():
            db = session_factory()
            try:
                yield db
            finally:
                db.close()

        app.dependency_overrides[get_db] = override_get_db
        client = TestClient(app, client=(peer, 50000))
        created.append(client)
        return client

    yield factory
    for client in created:
        client.close()


# ---------------------------------------------------------------------------
# The helper itself
# ---------------------------------------------------------------------------


def test_untrusted_peer_keeps_its_own_address_even_with_a_forwarded_header():
    settings = _settings(trusted_proxy_ips=[_PROXY])
    key = client_ip_for_throttle(_request(_DIRECT_PEER, "203.0.113.7"), settings)
    assert key == _DIRECT_PEER


def test_trusted_peer_yields_the_first_forwarded_hop():
    settings = _settings(trusted_proxy_ips=[_PROXY])
    key = client_ip_for_throttle(_request(_PROXY, "203.0.113.7, 172.18.0.1"), settings)
    assert key == "203.0.113.7"


def test_trusted_peer_without_a_forwarded_header_falls_back_to_the_peer():
    settings = _settings(trusted_proxy_ips=[_PROXY])
    assert client_ip_for_throttle(_request(_PROXY, None), settings) == _PROXY


def test_trusted_peer_with_an_empty_first_hop_falls_back_to_the_peer():
    settings = _settings(trusted_proxy_ips=[_PROXY])
    assert (
        client_ip_for_throttle(_request(_PROXY, " , 203.0.113.7"), settings) == _PROXY
    )


def test_default_settings_trust_nobody_and_ignore_the_header():
    settings = _settings()
    assert settings.trusted_proxy_ips == []
    assert client_ip_for_throttle(_request(_PROXY, "203.0.113.7"), settings) == _PROXY


def test_missing_socket_peer_collapses_to_one_shared_bucket():
    settings = _settings(trusted_proxy_ips=[_PROXY])
    key = client_ip_for_throttle(_request(None, "203.0.113.7"), settings)
    assert key == UNKNOWN_CLIENT


# ---------------------------------------------------------------------------
# End-to-end: the throttle buckets a real request lands in
# ---------------------------------------------------------------------------


def test_header_from_an_untrusted_peer_cannot_buy_a_fresh_budget(
    proxy_client_factory,
):
    """The anti-bypass half: rotating `X-Forwarded-For` from a peer that is
    NOT a configured proxy must not create new buckets (E09-R03 review F1
    measured 60/60 requests slipping past a 30/min limit that way)."""
    client = proxy_client_factory(peer=_DIRECT_PEER, trusted=[])

    for attempt in range(login_limiter.max_attempts):
        response = client.post(
            "/auth/login",
            json={"email": "ghost@strumsight.app", "password": "wrong"},
            headers={"X-Forwarded-For": f"203.0.113.{attempt}"},
        )
        assert response.status_code == 401, response.text

    blocked = client.post(
        "/auth/login",
        json={"email": "ghost@strumsight.app", "password": "wrong"},
        headers={"X-Forwarded-For": "203.0.113.99"},
    )
    assert blocked.status_code == 429
    assert "Retry-After" in blocked.headers


def test_two_clients_behind_the_trusted_proxy_do_not_share_one_budget(
    proxy_client_factory,
):
    """The fix itself: one phone exhausting the login budget must not lock
    out every other phone behind the same reverse proxy."""
    client = proxy_client_factory(peer=_PROXY, trusted=[_PROXY])
    noisy = {"X-Forwarded-For": "203.0.113.7"}
    innocent = {"X-Forwarded-For": "198.51.100.4"}

    for _ in range(login_limiter.max_attempts):
        response = client.post(
            "/auth/login",
            json={"email": "ghost@strumsight.app", "password": "wrong"},
            headers=noisy,
        )
        assert response.status_code == 401, response.text

    assert (
        client.post(
            "/auth/login",
            json={"email": "ghost@strumsight.app", "password": "wrong"},
            headers=noisy,
        ).status_code
        == 429
    )
    assert (
        client.post(
            "/auth/login",
            json={"email": "ghost@strumsight.app", "password": "wrong"},
            headers=innocent,
        ).status_code
        == 401
    )


def test_register_budget_is_per_forwarded_client_too(proxy_client_factory):
    client = proxy_client_factory(peer=_PROXY, trusted=[_PROXY])
    noisy = {"X-Forwarded-For": "203.0.113.7"}

    for index in range(register_limiter.max_attempts):
        response = client.post(
            "/auth/register",
            json={"email": f"r14-{index}@strumsight.app", "password": "sixstrings"},
            headers=noisy,
        )
        assert response.status_code == 201, response.text

    assert (
        client.post(
            "/auth/register",
            json={"email": "r14-blocked@strumsight.app", "password": "sixstrings"},
            headers=noisy,
        ).status_code
        == 429
    )
    assert (
        client.post(
            "/auth/register",
            json={"email": "r14-other@strumsight.app", "password": "sixstrings"},
            headers={"X-Forwarded-For": "198.51.100.4"},
        ).status_code
        == 201
    )


def test_default_configuration_behaviour_is_unchanged(proxy_client_factory):
    """No trusted proxy configured (the shipped default): the socket peer is
    the bucket, exactly as before R14 — the budget is spent by the peer's own
    attempts and a forwarded header changes nothing either way."""
    client = proxy_client_factory(peer=_DIRECT_PEER, trusted=[])

    for _ in range(login_limiter.max_attempts):
        assert (
            client.post(
                "/auth/login",
                json={"email": "ghost@strumsight.app", "password": "wrong"},
            ).status_code
            == 401
        )
    assert (
        client.post(
            "/auth/login", json={"email": "ghost@strumsight.app", "password": "wrong"}
        ).status_code
        == 429
    )
