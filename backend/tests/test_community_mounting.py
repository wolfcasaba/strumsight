# strumsight:allow-secret-file — csak a _deploy_settings() fix teszt-fixture
# secret_key-je (`env=prod` readiness-mérésekhez kell egy 32+ karakteres
# string); NEM valódi hitelesítő. A fájl szintű jelölő szándékos a soron
# belüli helyett: a check_secrets.dart measured 2026-08-05 megjegyzése
# szerint a `ruff format` a `backend/tests` fán már egyszer újratördelt egy
# sorvégi jelölős sort, és a jelölő lecsúszott a fixture-ről.
"""E15-R12 -- Community router mounting + readiness wiring (ADR 0497).

Acceptance map (round brief §6):
  A1  test_a1_community_disabled_returns_404_route_not_registered
  A2  test_a2_all_eleven_routers_are_mounted_and_every_route_requires_auth_except_documented_exceptions
  A2b test_a2b_handles_and_privacy_routes_404_even_with_community_enabled
  A3  test_a3_writes_subflag_off_disables_write_routes_but_keeps_reads
      test_a3_leaderboard_subflag_off_omits_the_whole_router
      test_a3_profile_write_routes_are_not_gated_by_writes_subflag
  A4  test_a4_community_enabled_prod_sqlite_returns_community_requires_postgres
      test_a4_community_disabled_prod_sqlite_readiness_is_unaffected
  A8  test_a8_search_literal_route_is_not_shadowed_by_profile_param_route

This suite builds its OWN apps via ``app.main.create_app`` — it does NOT
touch ``backend/tests/community/**`` (tilos zóna, §0.0 R4).
"""

from __future__ import annotations

import re
from pathlib import Path

from alembic.config import Config
from fastapi import FastAPI
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from alembic import command
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys
from app.main import create_app

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_SCRIPTS = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    config = Config(str(_ALEMBIC_INI))
    config.set_main_option("script_location", str(_ALEMBIC_SCRIPTS))
    return config


def _app_with_shared_memory_db(settings: Settings) -> FastAPI:
    """``create_app``'s own dev-mode ``create_all`` runs against a
    closure-captured engine that a post-hoc ``app.state`` swap can't reach,
    and plain ``sqlite://`` (no ``StaticPool``) hands each FastAPI
    threadpool worker its own throwaway ``:memory:`` connection -- so a
    request can land on a thread that never saw the schema. Community
    routers read ``request.app.state.session_factory`` directly (they do
    not all go through the overridable ``get_db`` dependency the way
    ``tests/conftest.py``'s shared ``client`` fixture assumes), so the fix
    here is a real, already-schema'd ``StaticPool`` engine installed on
    ``app.state`` BEFORE the TestClient's lifespan runs. The original
    lifespan still creates its own (now-unused) throwaway engine; harmless.
    """
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    enable_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    app = create_app(settings)
    app.state.database_engine = engine
    app.state.session_factory = sessionmaker(
        bind=engine, autoflush=False, autocommit=False
    )
    return app


def _register(
    client: TestClient, email: str = "player@strumsight.app"
) -> dict[str, str]:
    resp = client.post(
        "/auth/register", json={"email": email, "password": "sixstrings"}
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# A1 — community_enabled=False -> the route table never carries /community/**
# ---------------------------------------------------------------------------


def test_a1_community_disabled_returns_404_route_not_registered():
    app = _app_with_shared_memory_db(
        Settings(database_url="sqlite://", community_enabled=False)
    )
    paths = app.openapi()["paths"]
    assert not any(path.startswith("/community") for path in paths)

    with TestClient(app) as client:
        headers = _register(client)
        response = client.get("/community/profiles/me", headers=headers)

    assert response.status_code == 404
    # Starlette's own generic 404 body -- proof this is "route absent", not
    # a handler-level 404 (e.g. profile.py's "profile_missing").
    assert response.json() == {"detail": "Not Found"}


# ---------------------------------------------------------------------------
# A2 — community_enabled=True (+ every sub-flag) mounts the 11 authenticated
# router modules (ADR 0497 D6 excludes handles/privacy, see A2b below); the
# EXHAUSTIVE set of mounted community route-methods -- read from app.routes,
# not a hand-picked sample -- rejects an anonymous caller, except a short,
# individually-justified exception list.
# ---------------------------------------------------------------------------

_ELEVEN_MOUNTED_ROUTERS = {
    "bookmarks": ("get", "/community/bookmarks"),
    "challenges": ("post", "/community/challenges/{challenge_public_id}/invites"),
    "feed": ("get", "/community/feed"),
    "leaderboards": ("get", "/community/leaderboards/{challenge_public_id}"),
    "moderation": ("get", "/community/moderation/cases"),
    "posts": ("post", "/community/posts"),
    "profile": ("get", "/community/profiles/me"),
    "reports": ("post", "/community/reports"),
    "safety": ("get", "/community/blocked"),
    "search": ("get", "/community/profiles/search"),
    "social_graph": ("post", "/community/profiles/{public_id}/follow"),
}

# ADR 0497 review M1: a hand-picked probe sample (5 of 48 route-methods, all
# of which happened to be authenticated) stayed green even though 8
# route-methods were reachable without auth -- the exact hidden-router class
# of bug this cell exists to catch (B1/B2). Every mounted route-method is
# now walked from ``app.routes`` and must reject an anonymous caller, with
# ONLY the two exceptions below -- each individually measured and justified,
# not a blanket carve-out for a router.
_ANONYMOUS_BY_DESIGN = {
    ("GET", "/community/ping"): (
        "trivial liveness probe: no request body, no query, no database "
        "read, no response field beyond a fixed status string -- the same "
        "shape as the top-level /health endpoints, which are also "
        "unauthenticated by design."
    ),
    ("GET", "/community/profiles/{public_id}"): (
        "pre-existing anonymous read (ADR 0400 Következmények (c) nyitott "
        "tartozás; M2 in docs/reviews/e15-r12-review.md). Measured: "
        "backend/tests/community/test_profile_service.py:351 (tilos zóna, "
        "unmodified) calls this exact route with NO Authorization header "
        "through the SAME build_community_router() factory this test "
        "exercises, and asserts 200 -- gating it here would turn that "
        "suite red, which A7 forbids. The client never calls this route "
        "(absent from docs/contracts/client-backend-endpoints.json), and "
        "the response schema (CommunityProfileOut, A2's own whitelist) "
        "never exposes the internal integer id, only public_id/"
        "display_name/created_at."
    ),
}


def _fully_open_settings() -> Settings:
    return Settings(
        database_url="sqlite://",
        community_enabled=True,
        community_writes_enabled=True,
        community_media_enabled=True,
        community_leaderboard_enabled=True,
        community_clubs_enabled=True,
    )


def _concrete_path(route: APIRoute) -> str:
    """Fill every ``{param}`` path segment with a syntactically-valid
    placeholder so the request reaches dependency resolution instead of
    404ing on an unmatched route. None of the 11 mounted routers use a
    typed Starlette path convertor (int/uuid/path) -- all path params are
    plain strings -- and FastAPI resolves the ``HTTPBearer`` auth
    dependency (``app/deps.py::get_current_user``) before the endpoint's
    own body/path values are parsed (measured: an unauthenticated
    ``POST /community/posts`` with no body still returns 403, not a
    body-validation 422), so an arbitrary placeholder is sufficient to
    probe auth alone.
    """
    return re.sub(r"\{[^}]+\}", "probe", route.path)


def test_a2_all_eleven_routers_are_mounted_and_every_route_requires_auth_except_documented_exceptions():
    app = _app_with_shared_memory_db(_fully_open_settings())
    paths = app.openapi()["paths"]

    missing = [
        (name, method, path)
        for name, (method, path) in _ELEVEN_MOUNTED_ROUTERS.items()
        if method not in paths.get(path, {})
    ]
    assert not missing, f"router(s) not mounted: {missing}"

    community_routes = [
        route
        for route in app.routes
        if isinstance(route, APIRoute) and route.path.startswith("/community")
    ]
    # Sanity floor so a future refactor that drops the whole tree silently
    # (e.g. an early ``return`` swallowing every ``include_router`` call)
    # cannot pass this test by vacuous truth.
    assert len(community_routes) >= 40, (
        f"expected >=40 mounted community route objects, got "
        f"{len(community_routes)} -- the aggregate looks incomplete"
    )

    with TestClient(app) as client:
        unexpectedly_open = []
        for route in community_routes:
            for method in route.methods - {"HEAD", "OPTIONS"}:
                if (method, route.path) in _ANONYMOUS_BY_DESIGN:
                    continue
                response = getattr(client, method.lower())(_concrete_path(route))
                if response.status_code not in (401, 403):
                    unexpectedly_open.append((method, route.path, response.status_code))
        assert not unexpectedly_open, (
            "route(s) reachable without auth and NOT on the documented "
            f"_ANONYMOUS_BY_DESIGN exception list: {unexpectedly_open}"
        )


# ---------------------------------------------------------------------------
# A2b — the two authless routers stay unreachable even when community_enabled
# is on (ADR 0497 D6): they are simply never aggregated, so their paths 404
# exactly like a fully-disabled module (A1), not a runtime 403.
# ---------------------------------------------------------------------------


def test_a2b_handles_and_privacy_routes_404_even_with_community_enabled():
    app = _app_with_shared_memory_db(_fully_open_settings())
    paths = app.openapi()["paths"]
    assert not any(path.startswith("/community/handles") for path in paths)
    assert not any(path.startswith("/community/privacy") for path in paths)

    with TestClient(app) as client:
        headers = _register(client)
        for method, path in (
            ("get", "/community/handles/availability?handle=alpha"),
            ("get", "/community/handles/probe"),
            ("post", "/community/handles/claim"),
            ("post", "/community/handles/change"),
            ("get", "/community/privacy/probe"),
            ("put", "/community/privacy/probe"),
        ):
            response = getattr(client, method)(path, headers=headers)
            assert response.status_code == 404, (
                f"{method.upper()} {path} should 404 (route never "
                f"registered), got {response.status_code}: {response.text}"
            )


# ---------------------------------------------------------------------------
# A3 — sub-flags gate independently of the master flag and of each other.
# ---------------------------------------------------------------------------


def test_a3_writes_subflag_off_disables_write_routes_but_keeps_reads():
    app = create_app(
        Settings(
            database_url="sqlite://",
            community_enabled=True,
            community_writes_enabled=False,
        )
    )
    paths = app.openapi()["paths"]

    # posts: the create route (POST /community/posts) is gone; the read
    # route (GET /community/posts/{public_id}) stays.
    assert "post" not in paths.get("/community/posts", {})
    assert "get" in paths.get("/community/posts/{public_id}", {})

    # social_graph: follow/unfollow (POST/DELETE) are gone; the follower /
    # following list reads stay.
    follow_ops = paths.get("/community/profiles/{public_id}/follow", {})
    assert "post" not in follow_ops
    assert "delete" not in follow_ops
    assert "get" in paths.get("/community/profiles/{public_id}/followers", {})
    assert "get" in paths.get("/community/profiles/{public_id}/following", {})


def test_a3_leaderboard_subflag_off_omits_the_whole_router():
    app = create_app(
        Settings(
            database_url="sqlite://",
            community_enabled=True,
            community_leaderboard_enabled=False,
        )
    )
    paths = app.openapi()["paths"]
    assert not any(path.startswith("/community/leaderboards") for path in paths)


def test_a3_profile_write_routes_are_not_gated_by_writes_subflag():
    """The profile router's own create/update routes are identity /
    onboarding, not the "poszt, komment, reakció, follow-request" write
    domain ADR 0395 §6 names -- and backend/tests/community/test_profile_service.py
    (tilos zóna) already exercises them under community_enabled=True alone.
    """
    app = create_app(
        Settings(
            database_url="sqlite://",
            community_enabled=True,
            community_writes_enabled=False,
        )
    )
    paths = app.openapi()["paths"]
    profile_me_ops = paths.get("/community/profiles/me", {})
    assert "post" in profile_me_ops
    assert "put" in profile_me_ops


# ---------------------------------------------------------------------------
# A4 — the readiness gate's community-specific branch (ADR 0497 D4).
# ---------------------------------------------------------------------------


def _deploy_settings(database_url: str, **overrides) -> Settings:
    defaults = dict(
        env="prod",
        secret_key="a-real-32-char-production-secret",
        cors_origins=["https://app.strumsight.example"],
        database_url=database_url,
        allow_sqlite_in_prod=True,
    )
    defaults.update(overrides)
    return Settings(**defaults)


def test_a4_community_enabled_prod_sqlite_returns_community_requires_postgres(
    tmp_path, monkeypatch
):
    database_url = f"sqlite:///{tmp_path / 'community-prod.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")

    app = create_app(_deploy_settings(database_url, community_enabled=True))
    with TestClient(app) as client:
        ready = client.get("/health/ready")

    assert ready.status_code == 503
    assert ready.json() == {
        "status": "not_ready",
        "reason": "community_requires_postgres",
    }


def test_a4_community_disabled_prod_sqlite_readiness_is_unaffected(
    tmp_path, monkeypatch
):
    database_url = f"sqlite:///{tmp_path / 'no-community-prod.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")

    app = create_app(_deploy_settings(database_url, community_enabled=False))
    with TestClient(app) as client:
        ready = client.get("/health/ready")

    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}


# ---------------------------------------------------------------------------
# A8 — deterministic aggregator order (ADR 0497 D3): search's literal
# /community/profiles/search must not be shadowed by profile's
# /community/profiles/{public_id} catch-all.
# ---------------------------------------------------------------------------


def test_a8_search_literal_route_is_not_shadowed_by_profile_param_route():
    app = _app_with_shared_memory_db(_fully_open_settings())
    with TestClient(app) as client:
        headers = _register(client)
        created = client.post(
            "/community/profiles/me",
            headers=headers,
            json={
                "handle": "alpha-searcher",
                "display_name": "Alpha Searcher",
                "visibility": "public",
                "audience_default": "public",
            },
        )
        assert created.status_code == 201, created.text
        response = client.get("/community/profiles/search?q=alpha", headers=headers)

    # A profile-shadowed request would hit read_profile's
    # `uuid.UUID(public_id)` parse of the literal string "search" and 400
    # with "invalid public_id" instead of reaching the search handler.
    assert response.status_code == 200, response.text
    assert "hits" in response.json()
