"""Test fixtures: a fresh in-memory database + TestClient per test."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.routers.auth import login_limiter, register_limiter


@pytest.fixture(autouse=True)
def _fresh_rate_limits():
    """The throttles are process-global; without a reset, the register calls
    the fixtures make would bleed across tests (round 120)."""
    login_limiter.reset()
    register_limiter.reset()
    yield


@pytest.fixture
def client():
    # A single shared in-memory SQLite connection (StaticPool) so every request
    # in the test sees the same schema/data; a fresh engine per test isolates
    # tests from one another.
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override_get_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def auth_headers(client):
    """Register a user and return ready-to-use Authorization headers."""
    resp = client.post(
        "/auth/register",
        json={"email": "player@strumsight.app", "password": "sixstrings"},
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
