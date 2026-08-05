"""Tests for the tutor proxy endpoints and service logic."""

# strumsight:allow-secret-file — a prod-misconfig fail-closed teszteknek fake
# hitelesitokre van szukseguk (secret_key/tutor_api_key fixture-ok); ezek
# szandekosan titok-alaku, de bizonyithatoan nem valos titkok. A fajl kivetelek
# fajlja, nem egy kivetelt tartalmazo fajl (ADR 0138, tool/ci/check_secrets.dart
# soronkenti jelolese torekeny a ruff format ujratordelesevel szemben, L113).

import logging

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.ratelimit import RateLimiter
from app.tutor.provider_gateway import (
    FakeProviderGateway,
)
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
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy.pool import StaticPool

    from app.database import Base, enable_sqlite_foreign_keys, get_db

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


def test_flag_off_no_endpoints():
    """Feature flag OFF ⇒ no tutor endpoints."""
    settings = Settings(tutor_enabled=False)
    app = create_app(settings)
    client = TestClient(app)

    # Tutor endpoints should not exist
    response = client.get("/tutor/capability")
    assert response.status_code == 404

    response = client.post("/tutor/turn", json={"message": "test"})
    assert response.status_code == 404


def test_schema_reject_extra_fields(tutor_client, tutor_auth_headers):
    """Schema rejects extra fields (extra="forbid")."""
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "extra_field": "not_allowed"},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 422


def test_request_size_below_limit(tutor_client, tutor_auth_headers):
    """Request size below limit is accepted."""
    # 50 bytes, limit is 100
    message = "x" * 50
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": message, "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_request_size_at_limit(tutor_client, tutor_auth_headers):
    """Request size at limit is accepted."""
    # Exactly 100 bytes
    message = "x" * 100
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": message, "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_request_size_above_limit(tutor_client, tutor_auth_headers):
    """Request size above limit is rejected."""
    # 101 bytes, limit is 100
    message = "x" * 101
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": message, "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 413
    assert "too large" in response.json()["detail"].lower()


def test_history_below_limit(tutor_client, tutor_auth_headers):
    """History below limit is accepted."""
    # 3 messages, limit is 5
    history = [
        {"role": "user", "content": "q1"},
        {"role": "assistant", "content": "a1"},
    ]
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": history, "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_history_at_limit(tutor_client, tutor_auth_headers):
    """History at limit is accepted."""
    # Exactly 5 messages
    history = [{"role": "user", "content": f"q{i}"} for i in range(5)]
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": history, "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_history_above_limit(tutor_client, tutor_auth_headers):
    """History above limit is rejected."""
    # 6 messages, limit is 5
    history = [{"role": "user", "content": f"q{i}"} for i in range(6)]
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": history, "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 413
    assert "too long" in response.json()["detail"].lower()


def test_context_below_limit(tutor_client, tutor_auth_headers):
    """Context below limit is accepted."""
    # 100 bytes, limit is 200
    context = "c" * 100
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": [], "context": context},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_context_at_limit(tutor_client, tutor_auth_headers):
    """Context at limit is accepted."""
    # Exactly 200 bytes
    context = "c" * 200
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": [], "context": context},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200


def test_context_above_limit(tutor_client, tutor_auth_headers):
    """Context above limit is rejected."""
    # 201 bytes, limit is 200
    context = "c" * 201
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": [], "context": context},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 413
    assert "too large" in response.json()["detail"].lower()


def test_output_below_limit(tutor_client, tutor_auth_headers):
    """Output below limit is not truncated."""
    # Gateway returns 40 bytes, limit is 50
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert len(reply.encode("utf-8")) == 40


def test_output_at_limit(tutor_settings, tmp_path):
    """Output at limit is not truncated."""
    # Configure gateway to return exactly 50 bytes
    settings = tutor_settings.model_copy(
        update={"database_url": f"sqlite:///{tmp_path / 'test.db'}"}
    )
    app = create_app(settings)
    gateway = FakeProviderGateway(response="A" * 50)
    registry = ProviderRegistry(
        allowed=tutor_settings.tutor_allowed_providers,
        provider=tutor_settings.tutor_provider,
        model=tutor_settings.tutor_model,
    )
    usage_guard = UsageGuard(
        rate_limiter=RateLimiter(
            max_attempts=tutor_settings.tutor_rate_limit_max,
            window_seconds=tutor_settings.tutor_rate_limit_window,
        ),
        daily_token_limit=tutor_settings.tutor_daily_token_limit,
    )
    limits = TutorLimits(
        max_request_bytes=tutor_settings.tutor_max_request_bytes,
        max_history_messages=tutor_settings.tutor_max_history_messages,
        max_context_bytes=tutor_settings.tutor_max_context_bytes,
        max_output_bytes=tutor_settings.tutor_max_output_bytes,
    )
    service = TutorService(
        gateway=gateway,
        registry=registry,
        api_key=tutor_settings.tutor_api_key,
        usage_guard=usage_guard,
        limits=limits,
    )
    set_service(service)

    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": "player@strumsight.app", "password": "sixstrings"},
        )
        assert register.status_code == 201, register.text
        auth_headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
        response = client.post(
            "/tutor/turn",
            json={"message": "test", "history": [], "context": ""},
            headers=auth_headers,
        )
        assert response.status_code == 200
        reply = response.json()["reply"]
        assert len(reply.encode("utf-8")) == 50


def test_output_above_limit(tutor_settings, tmp_path):
    """Output above limit is truncated."""
    # Configure gateway to return 100 bytes, limit is 50
    settings = tutor_settings.model_copy(
        update={"database_url": f"sqlite:///{tmp_path / 'test.db'}"}
    )
    app = create_app(settings)
    gateway = FakeProviderGateway(response="A" * 100)
    registry = ProviderRegistry(
        allowed=tutor_settings.tutor_allowed_providers,
        provider=tutor_settings.tutor_provider,
        model=tutor_settings.tutor_model,
    )
    usage_guard = UsageGuard(
        rate_limiter=RateLimiter(
            max_attempts=tutor_settings.tutor_rate_limit_max,
            window_seconds=tutor_settings.tutor_rate_limit_window,
        ),
        daily_token_limit=tutor_settings.tutor_daily_token_limit,
    )
    limits = TutorLimits(
        max_request_bytes=tutor_settings.tutor_max_request_bytes,
        max_history_messages=tutor_settings.tutor_max_history_messages,
        max_context_bytes=tutor_settings.tutor_max_context_bytes,
        max_output_bytes=tutor_settings.tutor_max_output_bytes,
    )
    service = TutorService(
        gateway=gateway,
        registry=registry,
        api_key=tutor_settings.tutor_api_key,
        usage_guard=usage_guard,
        limits=limits,
    )
    set_service(service)

    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": "player@strumsight.app", "password": "sixstrings"},
        )
        assert register.status_code == 201, register.text
        auth_headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
        response = client.post(
            "/tutor/turn",
            json={"message": "test", "history": [], "context": ""},
            headers=auth_headers,
        )
        assert response.status_code == 200
        reply = response.json()["reply"]
        assert len(reply.encode("utf-8")) == 50  # Truncated to limit


def test_provider_selection_from_config(tutor_settings):
    """Provider is selected from config, not client request."""
    registry = ProviderRegistry(
        allowed={"openai": ["gpt-4"], "anthropic": ["claude-3"]},
        provider="openai",
        model="gpt-4",
    )
    resolved = registry.resolve()
    assert resolved.name == "openai"
    assert resolved.model_id == "gpt-4"


def test_provider_not_in_allowlist():
    """Provider not in allowlist raises error."""
    registry = ProviderRegistry(
        allowed={"openai": ["gpt-4"]},
        provider="anthropic",
        model="claude-3",
    )
    with pytest.raises(Exception, match="not in allowlist"):
        registry.resolve()


def test_model_not_in_allowlist():
    """Model not in allowlist raises error."""
    registry = ProviderRegistry(
        allowed={"openai": ["gpt-4"]},
        provider="openai",
        model="gpt-3.5",
    )
    with pytest.raises(Exception, match="not allowed"):
        registry.resolve()


def test_secret_not_in_response(tutor_client, tutor_auth_headers):
    """Provider secret is not in the response."""
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "test", "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200
    response_text = response.text
    assert "test-key" not in response_text


def test_provider_timeout_normalized_error(tutor_settings, tmp_path):
    """Provider timeout is normalized to 504."""
    settings = tutor_settings.model_copy(
        update={"database_url": f"sqlite:///{tmp_path / 'test.db'}"}
    )
    app = create_app(settings)
    gateway = FakeProviderGateway(should_timeout=True)
    registry = ProviderRegistry(
        allowed=tutor_settings.tutor_allowed_providers,
        provider=tutor_settings.tutor_provider,
        model=tutor_settings.tutor_model,
    )
    usage_guard = UsageGuard(
        rate_limiter=RateLimiter(
            max_attempts=tutor_settings.tutor_rate_limit_max,
            window_seconds=tutor_settings.tutor_rate_limit_window,
        ),
        daily_token_limit=tutor_settings.tutor_daily_token_limit,
    )
    limits = TutorLimits(
        max_request_bytes=tutor_settings.tutor_max_request_bytes,
        max_history_messages=tutor_settings.tutor_max_history_messages,
        max_context_bytes=tutor_settings.tutor_max_context_bytes,
        max_output_bytes=tutor_settings.tutor_max_output_bytes,
    )
    service = TutorService(
        gateway=gateway,
        registry=registry,
        api_key=tutor_settings.tutor_api_key,
        usage_guard=usage_guard,
        limits=limits,
    )
    set_service(service)

    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": "player@strumsight.app", "password": "sixstrings"},
        )
        assert register.status_code == 201, register.text
        auth_headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
        response = client.post(
            "/tutor/turn",
            json={"message": "test", "history": [], "context": ""},
            headers=auth_headers,
        )
        assert response.status_code == 504
        assert "temporarily unavailable" in response.json()["detail"].lower()


def test_provider_error_normalized_error(tutor_settings, tmp_path):
    """Provider error is normalized to 502."""
    settings = tutor_settings.model_copy(
        update={"database_url": f"sqlite:///{tmp_path / 'test.db'}"}
    )
    app = create_app(settings)
    gateway = FakeProviderGateway(should_error=True)
    registry = ProviderRegistry(
        allowed=tutor_settings.tutor_allowed_providers,
        provider=tutor_settings.tutor_provider,
        model=tutor_settings.tutor_model,
    )
    usage_guard = UsageGuard(
        rate_limiter=RateLimiter(
            max_attempts=tutor_settings.tutor_rate_limit_max,
            window_seconds=tutor_settings.tutor_rate_limit_window,
        ),
        daily_token_limit=tutor_settings.tutor_daily_token_limit,
    )
    limits = TutorLimits(
        max_request_bytes=tutor_settings.tutor_max_request_bytes,
        max_history_messages=tutor_settings.tutor_max_history_messages,
        max_context_bytes=tutor_settings.tutor_max_context_bytes,
        max_output_bytes=tutor_settings.tutor_max_output_bytes,
    )
    service = TutorService(
        gateway=gateway,
        registry=registry,
        api_key=tutor_settings.tutor_api_key,
        usage_guard=usage_guard,
        limits=limits,
    )
    set_service(service)

    with TestClient(app) as client:
        register = client.post(
            "/auth/register",
            json={"email": "player@strumsight.app", "password": "sixstrings"},
        )
        assert register.status_code == 201, register.text
        auth_headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
        response = client.post(
            "/tutor/turn",
            json={"message": "test", "history": [], "context": ""},
            headers=auth_headers,
        )
        assert response.status_code == 502
        assert "returned an error" in response.json()["detail"].lower()


def test_no_prompt_in_log(tutor_client, tutor_auth_headers, caplog):
    """Log does not contain the prompt or secret."""
    secret_prompt = "secret-prompt-12345-unique-marker"

    with caplog.at_level(logging.DEBUG):
        response = tutor_client.post(
            "/tutor/turn",
            json={"message": secret_prompt, "history": [], "context": ""},
            headers=tutor_auth_headers,
        )

    assert response.status_code == 200
    # The log should not contain the prompt
    assert secret_prompt not in caplog.text
    # The log should not contain the API key
    assert "test-key" not in caplog.text


def test_fake_provider_contract_green(tutor_client, tutor_auth_headers):
    """Fake provider makes the contract green."""
    response = tutor_client.post(
        "/tutor/turn",
        json={"message": "What is a chord?", "history": [], "context": ""},
        headers=tutor_auth_headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert "reply" in data
    assert isinstance(data["reply"], str)
    assert len(data["reply"]) > 0


def test_capability_endpoint(tutor_client):
    """Capability endpoint returns metadata."""
    response = tutor_client.get("/tutor/capability")
    assert response.status_code == 200
    data = response.json()
    assert data["enabled"] is True
    assert data["version"] == "v1"
    assert data["streaming"] is False


def test_prod_misconfig_blocks_boot():
    """Prod with dev tutor API key blocks boot (fail-closed)."""
    with pytest.raises(RuntimeError, match="TUTOR_API_KEY"):
        create_app(
            Settings(
                env="prod",
                secret_key="real-prod-secret-key-12345",
                cors_origins=["https://example.com"],
                allow_sqlite_in_prod=True,
                tutor_enabled=True,
                tutor_api_key="dev-tutor-key",  # Dev default
            )
        )


def test_prod_without_tutor_enabled_boots():
    """Prod without tutor enabled boots successfully."""
    # Should not raise
    app = create_app(
        Settings(
            env="prod",
            secret_key="real-prod-secret-key-12345",
            cors_origins=["https://example.com"],
            allow_sqlite_in_prod=True,
            tutor_enabled=False,
            tutor_api_key="dev-tutor-key",  # Doesn't matter if tutor is disabled
        )
    )
    assert app is not None


def test_prod_with_real_tutor_key_boots():
    """Prod with real tutor API key boots successfully."""
    # Should not raise
    app = create_app(
        Settings(
            env="prod",
            secret_key="real-prod-secret-key-12345",
            cors_origins=["https://example.com"],
            allow_sqlite_in_prod=True,
            tutor_enabled=True,
            tutor_api_key="real-prod-tutor-key-12345",
        )
    )
    assert app is not None
