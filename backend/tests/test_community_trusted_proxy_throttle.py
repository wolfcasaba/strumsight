# strumsight:allow-secret-file — the only credential below is an invented
# test-fixture password; the file's PURPOSE is to exercise the Community
# routers' own rate-limit buckets.
"""R16 — the two Community routers with their OWN throttles adopt the R14
trusted-proxy rule.

R14 fixed the shared-bucket bug for the auth throttles only
(`app/routers/auth.py::_throttle` -> `app/client_ip.py`). The two Community
routers that carry process-local limiters of their own —
`app/community/routers/handles.py` (availability 30/min, handle change
5/hour) and `app/community/routers/search.py` (profile search 60/min) — kept
keying on the raw socket peer, so behind Caddy every caller of the deploy
shared ONE budget on those surfaces too. This file pins both halves of the
adopted rule, per router:

* a trusted peer's forwarded first hop IS the bucket key, so two phones
  behind the same reverse proxy do not share a budget;
* an untrusted peer's `X-Forwarded-For` is IGNORED, so rotating the header
  cannot buy a fresh budget (the E09-R03 review F1 measurement: 60/60
  requests slipped past a 30/min limit exactly that way).

Mirrors `backend/tests/test_trusted_proxy_throttle.py`: helper-level cells
first, then end-to-end cells that drive the real routers through a
`TestClient` whose socket peer the test chooses.
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.community.models.profile import CommunityProfile  # noqa: F401 — table
from app.community.routers import handles as handles_module
from app.community.routers import search as search_module
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db
from app.models import User
from app.security import create_access_token, hash_password

_PROXY = "172.18.0.1"
_DIRECT_PEER = "10.0.0.5"
_CLIENT_A = "203.0.113.7"
_CLIENT_B = "198.51.100.4"

# `admin` is on `handle_policy.RESERVED`, so the availability endpoint answers
# `reason="reserved"` from the policy alone — after the limiter, before any
# database access. That makes the router's bucket state the ONLY difference
# between the two outcomes this file asserts on (`reserved` = a slot was
# granted, `rate_limited` = the bucket was full).
_RESERVED_HANDLE = "admin"


def _settings(**overrides) -> Settings:
    defaults = dict(
        _env_file=None,
        database_url="sqlite://",
        community_enabled=True,
        trusted_proxy_ips=[],
    )
    defaults.update(overrides)
    return Settings(**defaults)


def _request(app: FastAPI, peer: str | None, forwarded: str | None) -> Request:
    """A bare ASGI scope carrying `app` — enough for a `_client_key` call."""
    headers = [(b"x-forwarded-for", forwarded.encode())] if forwarded else []
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/community/ping",
            "headers": headers,
            "client": (peer, 50000) if peer else None,
            "app": app,
        }
    )


def _app_with_settings(settings: Settings) -> FastAPI:
    app = FastAPI(title="Community Throttle Key Test App")
    app.state.settings = settings
    return app


@pytest.fixture(autouse=True)
def _fresh_community_rate_limits() -> Iterator[None]:
    """Both routers' limiters are process-global — without a reset they bleed
    across cells (the same rule `tests/conftest.py` applies to auth)."""
    handles_module.reset_rate_limiters()
    search_module.reset_rate_limiters()
    yield
    handles_module.reset_rate_limiters()
    search_module.reset_rate_limiters()


# ---------------------------------------------------------------------------
# The routers' own `_client_key` helpers
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "client_key",
    [handles_module._client_key, search_module._client_key],
    ids=["handles", "search"],
)
def test_router_key_ignores_a_forwarded_header_from_an_untrusted_peer(client_key):
    app = _app_with_settings(_settings(trusted_proxy_ips=[_PROXY]))
    assert client_key(_request(app, _DIRECT_PEER, _CLIENT_A)) == _DIRECT_PEER


@pytest.mark.parametrize(
    "client_key",
    [handles_module._client_key, search_module._client_key],
    ids=["handles", "search"],
)
def test_router_key_uses_the_first_forwarded_hop_from_a_trusted_peer(client_key):
    app = _app_with_settings(_settings(trusted_proxy_ips=[_PROXY]))
    key = client_key(_request(app, _PROXY, f"{_CLIENT_A}, {_PROXY}"))
    assert key == _CLIENT_A


@pytest.mark.parametrize(
    "client_key",
    [handles_module._client_key, search_module._client_key],
    ids=["handles", "search"],
)
def test_router_key_default_configuration_trusts_nobody(client_key):
    """The shipped default (`trusted_proxy_ips=[]`) keeps the exact
    socket-peer behaviour both routers had before R16."""
    app = _app_with_settings(_settings())
    assert client_key(_request(app, _PROXY, _CLIENT_A)) == _PROXY


# ---------------------------------------------------------------------------
# handles.py — GET /community/handles/availability (30/min)
# ---------------------------------------------------------------------------


def _handles_client(*, peer: str, trusted: list[str]) -> TestClient:
    app = _app_with_settings(_settings(trusted_proxy_ips=trusted))
    app.include_router(handles_module.router)
    return TestClient(app, client=(peer, 50000))


def _availability_reason(client: TestClient, forwarded: str) -> str:
    response = client.get(
        "/community/handles/availability",
        params={"handle": _RESERVED_HANDLE},
        headers={"X-Forwarded-For": forwarded},
    )
    assert response.status_code == 200, response.text
    return response.json()["reason"]


def test_handles_two_clients_behind_a_trusted_proxy_do_not_share_one_budget():
    """The fix: one phone exhausting the availability budget must not lock
    out every other phone behind the same reverse proxy."""
    with _handles_client(peer=_PROXY, trusted=[_PROXY]) as client:
        for _ in range(handles_module._AVAILABILITY_MAX):
            assert _availability_reason(client, _CLIENT_A) == "reserved"

        assert _availability_reason(client, _CLIENT_A) == "rate_limited"
        assert _availability_reason(client, _CLIENT_B) == "reserved"


def test_handles_header_from_an_untrusted_peer_cannot_buy_a_fresh_budget():
    """The anti-bypass half (E09-R03 review F1): rotating `X-Forwarded-For`
    from a peer that is NOT a configured proxy must not create new buckets."""
    with _handles_client(peer=_DIRECT_PEER, trusted=[]) as client:
        for attempt in range(handles_module._AVAILABILITY_MAX):
            assert _availability_reason(client, f"203.0.113.{attempt}") == "reserved"

        assert _availability_reason(client, "203.0.113.99") == "rate_limited"


# ---------------------------------------------------------------------------
# search.py — GET /community/profiles/search (60/min)
# ---------------------------------------------------------------------------

# The caller is authenticated but has NO community profile, so a granted slot
# ends in the router's own `404 caller has no community profile` and a refused
# one in `429`. Both outcomes are decided inside the router, one line apart
# (`_search_limiter.allow(_client_key(request))`), which is exactly the line
# under test — and it keeps this cell free of profile/search fixtures.
_SEARCH_GRANTED = 404
_SEARCH_REFUSED = 429


def _search_client(*, peer: str, trusted: list[str]) -> TestClient:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    enable_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    with session_factory() as db:
        db.add(
            User(
                email="r16-search@strumsight.app",
                hashed_password=hash_password("r16-fake-correct-horse"),
            )
        )
        db.commit()

    app = _app_with_settings(_settings(trusted_proxy_ips=trusted))
    app.state.database_engine = engine
    app.state.session_factory = session_factory
    app.include_router(search_module.router)

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app, client=(peer, 50000))


def _search_headers(forwarded: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {create_access_token(1)}",
        "X-Forwarded-For": forwarded,
    }


def _search_status(client: TestClient, forwarded: str) -> int:
    return client.get(
        "/community/profiles/search",
        params={"q": "strum"},
        headers=_search_headers(forwarded),
    ).status_code


def test_search_two_clients_behind_a_trusted_proxy_do_not_share_one_budget():
    with _search_client(peer=_PROXY, trusted=[_PROXY]) as client:
        for _ in range(search_module._SEARCH_MAX):
            assert _search_status(client, _CLIENT_A) == _SEARCH_GRANTED

        assert _search_status(client, _CLIENT_A) == _SEARCH_REFUSED
        assert _search_status(client, _CLIENT_B) == _SEARCH_GRANTED


def test_search_header_from_an_untrusted_peer_cannot_buy_a_fresh_budget():
    with _search_client(peer=_DIRECT_PEER, trusted=[]) as client:
        for attempt in range(search_module._SEARCH_MAX):
            assert _search_status(client, f"203.0.113.{attempt}") == _SEARCH_GRANTED

        assert _search_status(client, "203.0.113.99") == _SEARCH_REFUSED
