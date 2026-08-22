"""Community-module test fixtures (E09-R02, ADR 0396; E09-R06, ADR 0400).

The brief is explicit (§0.0 1. pont, ADR 0396 §3): this conftest builds its
own, **minimal** ``FastAPI()`` instance. It does NOT call
``app.main.create_app`` — the only consumer of ``build_community_router``
this round is the test app itself, and the live ``main.py`` is in the
forbidden zone (no ``allowed_paths`` entry, §3 tilos zóna).

The dependency seam (``get_db``) is overridden against this self-contained
app via ``dependency_overrides[get_db]``, mirroring the existing
``backend/tests/conftest.py`` pattern (round 120). The ``CurrentUser``
chain (``app.deps``) reads from the same ``get_db`` seam, so the E09-R06
authenticated endpoints see the same session the test seeded.

E09-R06 adds the ``community_auth_headers`` / ``make_authenticated_user``
helpers: a tiny, self-contained "register a user and return
``Authorization: Bearer <token>``" pair, anchored to the Community test
session's own ``session_factory`` so the test does not depend on the
top-level ``/auth/register`` endpoint (which is not on the Community
router — only the community router is mounted).
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.community import build_community_router
# Importing ``handle_history`` is load-bearing: the Kör 3 schema adds
# ``handle_display`` / ``handle_normalized`` to ``Base.metadata`` at
# import-time (the ORM class is untouched, the columns live on the
# ``Table`` object only — see the file for the rationale). Without
# this import, ``Base.metadata.create_all`` would build a
# ``community_profiles`` table without the handle columns and the
# E09-R06 service-level ``assign_handle`` UPDATE would fail with
# ``no such column: handle_display``.
from app.community.models import handle_history  # noqa: F401
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db
from app.models import User
from app.security import create_access_token, hash_password


def _make_test_engine():
    """Fresh, in-memory SQLite engine per test (StaticPool keeps the schema
    shared across the requests inside one test)."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    enable_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    return engine


def _build_app(engine, session_factory, settings: Settings) -> FastAPI:
    """Build the self-contained Community test app around a SHARED engine.

    The engine / session_factory pair is owned by the caller (the
    ``community_enabled`` fixture below) so the ``community_auth_headers``
    fixture can seed a User row in the same in-memory database the
    TestClient's requests will see.
    """
    app = FastAPI(title="Community Test App")
    app.state.database_engine = engine
    app.state.session_factory = session_factory
    app.state.settings = settings

    router = build_community_router(settings)
    if router is not None:
        app.include_router(router)
    return app


@pytest.fixture
def community_enabled() -> Iterator[tuple[FastAPI, sessionmaker]]:
    """Build a Community-enabled test app + share the session factory.

    Returns ``(app, session_factory)`` so tests that need to seed data
    BEFORE issuing requests can do so against the same in-memory engine
    the TestClient uses.
    """
    settings = Settings(community_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    try:
        yield app, session_factory
    finally:
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture
def community_app_enabled(community_enabled) -> Iterator[tuple[FastAPI, object]]:
    """Build a Community-enabled test app (the typical, working surface).

    Kept as a separate fixture name to preserve the round-2 test imports.
    """
    app, session_factory = community_enabled
    yield app, session_factory


@pytest.fixture
def community_client_enabled(community_enabled) -> Iterator[TestClient]:
    """``TestClient`` with the Community router mounted (``community_enabled=True``)."""
    app, session_factory = community_enabled

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        try:
            yield client
        finally:
            app.dependency_overrides.clear()


@pytest.fixture
def community_client_disabled() -> Iterator[TestClient]:
    """``TestClient`` with the Community router ABSENT (``community_enabled=False``).

    The factory returns ``None`` so ``app.include_router`` is never called —
    this is exactly the A5 contract: the router is not mounted, the
    endpoints do not exist, not "404 from inside the router".
    """
    settings = Settings(community_enabled=False)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as client:
        try:
            yield client
        finally:
            app.dependency_overrides.clear()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture
def community_settings_enabled() -> Settings:
    return Settings(community_enabled=True)


@pytest.fixture
def community_settings_disabled() -> Settings:
    return Settings(community_enabled=False)


# ---------------------------------------------------------------------------
# E09-R06 — authenticated-test helpers (ADR 0400 §2.4, brief §2.4)
#
# The two NEW endpoints (``POST`` / ``PUT /community/profiles/me``) require
# a JWT. The Community test app mounts only the community router, so the
# top-level ``/auth/register`` endpoint is not in scope. Instead the helper
# creates a ``User`` row directly against the test session (mirroring what
# ``routers/auth.py::register`` does, minus the rate limiter) and issues a
# token through the shared ``create_access_token`` — the same path the
# production ``/auth/register`` uses, so the JWT signature is exactly what
# the production ``CurrentUser`` resolver expects.
# ---------------------------------------------------------------------------


def make_authenticated_user(
    session_factory,
    *,
    email: str = "player-1@strumsight.app",
    password: str = "sixstrings",
) -> tuple[User, dict[str, str]]:
    """Create a User row in the Community test session and return
    ``(user, authorization_headers)``.

    The function opens its own short-lived session against the test
    engine. The User row lives in the same in-memory database the
    TestClient's requests will see (because the engine is shared
    through the ``community_enabled`` fixture), so the subsequent
    ``POST /community/profiles/me`` can resolve ``current_user.id`` to
    the row we just wrote.
    """
    session: Session = session_factory()
    try:
        user = User(
            email=email,
            hashed_password=hash_password(password),
        )
        session.add(user)
        session.commit()
        session.refresh(user)
        token = create_access_token(user.id)
        return user, {"Authorization": f"Bearer {token}"}
    finally:
        session.close()


@pytest.fixture
def community_auth_headers(community_client_enabled, community_enabled):
    """``Authorization: Bearer <token>`` for a freshly-registered user.

    Depends on both the TestClient fixture and the underlying
    ``community_enabled`` pair (the latter to share the session
    factory). The User row is written against the shared in-memory
    engine so the subsequent request from the TestClient can resolve
    the ``CurrentUser``.
    """
    _, session_factory = community_enabled
    _, headers = make_authenticated_user(session_factory)
    return headers


@pytest.fixture
def community_two_auth_headers(community_client_enabled, community_enabled):
    """Two independent ``Authorization: Bearer <token>`` headers.

    The §6.1 measure-matrix "two concurrent creates, both succeed" cell
    needs two separate user identities. The pair lives in the same
    shared in-memory engine as the TestClient.
    """
    _, session_factory = community_enabled
    _, headers_a = make_authenticated_user(
        session_factory, email="player-a@strumsight.app"
    )
    _, headers_b = make_authenticated_user(
        session_factory, email="player-b@strumsight.app"
    )
    return headers_a, headers_b
