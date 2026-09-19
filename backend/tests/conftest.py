"""Test fixtures: a fresh in-memory database + TestClient per test."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import security
from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db
from app.main import create_app
from app.routers.auth import login_limiter, register_limiter

# ---------------------------------------------------------------------------
# Password-hashing cost — TEST PROCESS ONLY (round 25)
#
# MEASURED on the CI-class box: one bcrypt hash costs 0.271 s at the
# production cost factor (12) and 0.001 s at 4. The suite mints thousands of
# them — every fixture user, every `/auth/register`, every `/auth/login`
# against a real account. The three `test_club_service.py` A7 cells stage 499
# members each and measured 139 s / 139 s / 138 s: 417 s of pure key
# derivation out of a 15 min run that CI cancelled at 14 min 56 s of its
# 15 min limit.
#
# `app.security.PASSWORD_HASH_ROUNDS` is a module constant on purpose (never
# an environment / `Settings` knob), so a deployment cannot weaken it; only
# this pytest process rebinds it, below. Nothing else about hashing changes:
# same algorithm, same 72-byte guard, same `verify_password`.
#
# The production value keeps explicit coverage — the
# `production_password_hashing` fixture restores it for a single test and
# `tests/test_auth.py::test_production_cost_factor_hashes_and_verifies`
# pins it.
# ---------------------------------------------------------------------------
PRODUCTION_PASSWORD_HASH_ROUNDS = security.PASSWORD_HASH_ROUNDS
TEST_PASSWORD_HASH_ROUNDS = 4
security.PASSWORD_HASH_ROUNDS = TEST_PASSWORD_HASH_ROUNDS


@pytest.fixture
def production_password_hashing():
    """Run one test at the REAL production bcrypt cost factor."""
    security.PASSWORD_HASH_ROUNDS = PRODUCTION_PASSWORD_HASH_ROUNDS
    try:
        yield PRODUCTION_PASSWORD_HASH_ROUNDS
    finally:
        security.PASSWORD_HASH_ROUNDS = TEST_PASSWORD_HASH_ROUNDS


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
    enable_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = create_app(Settings(database_url="sqlite://"))

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
    engine.dispose()


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
