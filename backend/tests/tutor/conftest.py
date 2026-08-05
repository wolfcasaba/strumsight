"""Shared fixtures for tutor tests."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.database import Base, enable_sqlite_foreign_keys, get_db
from app.main import create_app
from app.ratelimit import RateLimiter
from app.tutor.provider_gateway import FakeProviderGateway
from app.tutor.provider_registry import ProviderRegistry
from app.tutor.router import set_service
from app.tutor.service import TutorLimits, TutorService
from app.tutor.usage import UsageGuard


@pytest.fixture
def tutor_settings():
    """Settings with tutor enabled."""
    return Settings(
        tutor_enabled=True,
        tutor_provider="fake",
        tutor_model="fake-model",
        tutor_api_key="test-key",
        tutor_allowed_providers={"fake": ["fake-model"]},
        tutor_max_request_bytes=100,
        tutor_max_history_messages=5,
        tutor_max_context_bytes=200,
        tutor_max_output_bytes=50,
        tutor_rate_limit_max=3,
        tutor_rate_limit_window=60,
        tutor_daily_token_limit=1000,
    )


@pytest.fixture
def tutor_client(tutor_settings):
    """TestClient with tutor service configured and fresh database."""
    # Create a fresh in-memory database for each test
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    enable_sqlite_foreign_keys(engine)
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    # Use sqlite:// to avoid file-based database
    settings_with_sqlite = Settings(
        env=tutor_settings.env,
        secret_key=tutor_settings.secret_key,
        algorithm=tutor_settings.algorithm,
        access_token_expires_minutes=tutor_settings.access_token_expires_minutes,
        database_url="sqlite://",
        allow_sqlite_in_prod=tutor_settings.allow_sqlite_in_prod,
        cors_origins=tutor_settings.cors_origins,
        diagnostics_enabled=tutor_settings.diagnostics_enabled,
        apk_download_enabled=tutor_settings.apk_download_enabled,
        diag_token=tutor_settings.diag_token,
        diag_dir=tutor_settings.diag_dir,
        tutor_enabled=tutor_settings.tutor_enabled,
        tutor_provider=tutor_settings.tutor_provider,
        tutor_model=tutor_settings.tutor_model,
        tutor_api_key=tutor_settings.tutor_api_key,
        tutor_allowed_providers=tutor_settings.tutor_allowed_providers,
        tutor_max_request_bytes=tutor_settings.tutor_max_request_bytes,
        tutor_max_history_messages=tutor_settings.tutor_max_history_messages,
        tutor_max_context_bytes=tutor_settings.tutor_max_context_bytes,
        tutor_max_output_bytes=tutor_settings.tutor_max_output_bytes,
        tutor_rate_limit_max=tutor_settings.tutor_rate_limit_max,
        tutor_rate_limit_window=tutor_settings.tutor_rate_limit_window,
        tutor_daily_token_limit=tutor_settings.tutor_daily_token_limit,
        tutor_timeout_seconds=tutor_settings.tutor_timeout_seconds,
    )

    app = create_app(settings_with_sqlite)

    # Override the database dependency
    def override_get_db():
        db = TestingSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    # Configure the tutor service
    gateway = FakeProviderGateway(response="A" * 40)  # 40 bytes, under 50 limit
    registry = ProviderRegistry(
        allowed=settings_with_sqlite.tutor_allowed_providers,
        provider=settings_with_sqlite.tutor_provider,
        model=settings_with_sqlite.tutor_model,
    )
    usage_guard = UsageGuard(
        rate_limiter=RateLimiter(
            max_attempts=settings_with_sqlite.tutor_rate_limit_max,
            window_seconds=settings_with_sqlite.tutor_rate_limit_window,
        ),
        daily_token_limit=settings_with_sqlite.tutor_daily_token_limit,
    )
    limits = TutorLimits(
        max_request_bytes=settings_with_sqlite.tutor_max_request_bytes,
        max_history_messages=settings_with_sqlite.tutor_max_history_messages,
        max_context_bytes=settings_with_sqlite.tutor_max_context_bytes,
        max_output_bytes=settings_with_sqlite.tutor_max_output_bytes,
    )
    service = TutorService(
        gateway=gateway,
        registry=registry,
        api_key=settings_with_sqlite.tutor_api_key,
        usage_guard=usage_guard,
        limits=limits,
    )
    set_service(service)

    with TestClient(app) as client:
        yield client

    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)
    engine.dispose()


@pytest.fixture
def tutor_auth_headers(tutor_client):
    """Register a user and return ready-to-use Authorization headers for tutor_client."""
    resp = tutor_client.post(
        "/auth/register",
        json={"email": "player@strumsight.app", "password": "sixstrings"},
    )
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
