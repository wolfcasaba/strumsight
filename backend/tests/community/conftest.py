"""Community-module test fixtures (E09-R02, ADR 0396).

The brief is explicit (§0.0 1. pont, ADR 0396 §3): this conftest builds its
own, **minimal** ``FastAPI()`` instance. It does NOT call
``app.main.create_app`` — the only consumer of ``build_community_router``
this round is the test app itself, and the live ``main.py`` is in the
forbidden zone (no ``allowed_paths`` entry, §3 tilos zóna).

The dependency seam (``get_db``) is overridden against this self-contained
app via ``dependency_overrides[get_db]``, mirroring the existing
``backend/tests/conftest.py`` pattern (round 120).
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.community import build_community_router
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db


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


def _build_app(settings: Settings) -> tuple[FastAPI, object]:
    """Build the self-contained Community test app.

    Returns the FastAPI instance and the SQLAlchemy session factory bound
    to the in-memory engine. The session factory is also stored on
    ``app.state`` so that any router using
    ``request.app.state.session_factory`` (the same seam as production,
    see ``app/database.py::get_db``) can read it.
    """
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    app = FastAPI(title="Community Test App")
    app.state.database_engine = engine
    app.state.session_factory = session_factory
    app.state.settings = settings

    router = build_community_router(settings)
    if router is not None:
        app.include_router(router)
    return app, session_factory


@pytest.fixture
def community_app_enabled() -> Iterator[tuple[FastAPI, object]]:
    """Build a Community-enabled test app (the typical, working surface)."""
    settings = Settings(community_enabled=True)
    app, session_factory = _build_app(settings)
    try:
        yield app, session_factory
    finally:
        Base.metadata.drop_all(bind=app.state.database_engine)
        app.state.database_engine.dispose()


@pytest.fixture
def community_client_enabled() -> Iterator[TestClient]:
    """``TestClient`` with the Community router mounted (``community_enabled=True``)."""
    settings = Settings(community_enabled=True)
    app, session_factory = _build_app(settings)

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
            Base.metadata.drop_all(bind=app.state.database_engine)
            app.state.database_engine.dispose()


@pytest.fixture
def community_client_disabled() -> Iterator[TestClient]:
    """``TestClient`` with the Community router ABSENT (``community_enabled=False``).

    The factory returns ``None`` so ``app.include_router`` is never called —
    this is exactly the A5 contract: the router is not mounted, the
    endpoints do not exist, not "404 from inside the router".
    """
    settings = Settings(community_enabled=False)
    app, session_factory = _build_app(settings)

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
            Base.metadata.drop_all(bind=app.state.database_engine)
            app.state.database_engine.dispose()


@pytest.fixture
def community_settings_enabled() -> Settings:
    return Settings(community_enabled=True)


@pytest.fixture
def community_settings_disabled() -> Settings:
    return Settings(community_enabled=False)
