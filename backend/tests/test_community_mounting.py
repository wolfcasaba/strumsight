"""E15-R12 -- Community router mounting + readiness wiring (ADR 0497).

Acceptance map (round brief §6):
  A1  test_a1_community_disabled_returns_404_route_not_registered
  A2  test_a2_all_thirteen_routers_are_mounted_and_authenticated_ones_require_auth
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

from pathlib import Path

from alembic.config import Config
from fastapi import FastAPI
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
# A2 — community_enabled=True (+ every sub-flag) mounts all 13 router
# modules; the authenticated ones reject an anonymous caller.
# ---------------------------------------------------------------------------

_ALL_THIRTEEN = {
    "bookmarks": ("get", "/community/bookmarks"),
    "challenges": ("post", "/community/challenges/{challenge_public_id}/invites"),
    "feed": ("get", "/community/feed"),
    "handles": ("get", "/community/handles/availability"),
    "leaderboards": ("get", "/community/leaderboards/{challenge_public_id}"),
    "moderation": ("get", "/community/moderation/cases"),
    "posts": ("post", "/community/posts"),
    "privacy": ("get", "/community/privacy/{profile_public_id}"),
    "profile": ("get", "/community/profiles/me"),
    "reports": ("post", "/community/reports"),
    "safety": ("get", "/community/blocked"),
    "search": ("get", "/community/profiles/search"),
    "social_graph": ("post", "/community/profiles/{public_id}/follow"),
}

# Endpoints known to enforce CurrentUser -- handles/privacy do not (a
# pre-existing gap, ADR 0400 Következmények (c) nyitott tartozás, out of
# this round's tilos zóna) so they are checked for EXISTENCE only, not for
# the 401/403 anonymous-rejection behaviour.
_AUTH_REQUIRED_PROBES = {
    "profile": ("get", "/community/profiles/me"),
    "feed": ("get", "/community/feed"),
    "safety": ("get", "/community/blocked"),
    "search": ("get", "/community/profiles/search?q=a"),
    "moderation": ("get", "/community/moderation/cases"),
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


def test_a2_all_thirteen_routers_are_mounted_and_authenticated_ones_require_auth():
    app = _app_with_shared_memory_db(_fully_open_settings())
    paths = app.openapi()["paths"]

    missing = [
        (name, method, path)
        for name, (method, path) in _ALL_THIRTEEN.items()
        if method not in paths.get(path, {})
    ]
    assert not missing, f"router(s) not mounted: {missing}"

    with TestClient(app) as client:
        for name, (method, path) in _AUTH_REQUIRED_PROBES.items():
            response = getattr(client, method)(path)
            assert response.status_code in (401, 403), (
                f"{name} route {method.upper()} {path} did not reject an "
                f"anonymous caller: got {response.status_code}"
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
