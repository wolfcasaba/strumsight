"""Composition-root contract for the tutor provider (R23).

Before this round `main.py` built a `FakeProviderGateway()` unconditionally,
so `STRUMSIGHT_TUTOR_PROVIDER` was decorative: a live deploy with a real key
still answered from the canned fake. These tests pin the three properties that
replaced it — the fake stays the default, a real provider is actually
constructed, and a real provider without a usable key refuses to boot.
"""

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.tutor.provider_gateway import (
    AnthropicProviderGateway,
    FakeProviderGateway,
    OpenAiProviderGateway,
)

_REAL_KEY = "not-the-dev-default-key"


def _settings(**overrides) -> Settings:
    base = {
        "_env_file": None,
        "database_url": "sqlite://",
        "tutor_enabled": True,
    }
    base.update(overrides)
    return Settings(**base)


def _anthropic_settings(**overrides) -> Settings:
    fields = {
        "tutor_provider": "anthropic",
        "tutor_model": "claude-sonnet-5",
        "tutor_allowed_providers": {"anthropic": ["claude-sonnet-5"]},
        "tutor_api_key": _REAL_KEY,
    }
    fields.update(overrides)
    return _settings(**fields)


# --- which gateway gets built -------------------------------------------------


def test_default_configuration_still_composes_the_fake_gateway() -> None:
    """An unconfigured deploy never opens a provider socket."""
    app = create_app(_settings())
    assert isinstance(app.state.tutor_gateway, FakeProviderGateway)


def test_anthropic_provider_composes_the_anthropic_gateway() -> None:
    """The configured provider actually reaches the wire adapter."""
    app = create_app(_anthropic_settings())
    assert isinstance(app.state.tutor_gateway, AnthropicProviderGateway)


def test_openai_provider_composes_the_openai_gateway() -> None:
    """The adapter shipped by E99-R07 is reachable from configuration too."""
    app = create_app(
        _settings(
            tutor_provider="openai",
            tutor_model="gpt-x",
            tutor_allowed_providers={"openai": ["gpt-x"]},
            tutor_api_key=_REAL_KEY,
        )
    )
    assert isinstance(app.state.tutor_gateway, OpenAiProviderGateway)


# --- fail-closed boot guards --------------------------------------------------


@pytest.mark.parametrize(
    "api_key",
    ["dev-tutor-key", "", "   "],
    ids=["dev_default", "empty", "blank"],
)
def test_real_provider_without_a_usable_key_refuses_to_boot(api_key: str) -> None:
    """Fail-closed in EVERY environment, not only under STRUMSIGHT_ENV=prod."""
    with pytest.raises(RuntimeError, match="TUTOR_API_KEY"):
        create_app(_anthropic_settings(tutor_api_key=api_key))


def test_unknown_provider_refuses_to_boot() -> None:
    """A typo must not silently degrade to the canned fake."""
    with pytest.raises(RuntimeError, match="STRUMSIGHT_TUTOR_PROVIDER"):
        create_app(
            _settings(
                tutor_provider="anthropik",
                tutor_model="claude-sonnet-5",
                tutor_allowed_providers={"anthropik": ["claude-sonnet-5"]},
                tutor_api_key=_REAL_KEY,
            )
        )


def test_model_outside_the_allowlist_refuses_to_boot() -> None:
    """The allowlist miss used to surface as a 500 on the first real turn."""
    with pytest.raises(RuntimeError, match="ALLOWED_PROVIDERS"):
        create_app(
            _anthropic_settings(tutor_allowed_providers={"anthropic": ["other-model"]})
        )


def test_a_disabled_tutor_ignores_the_provider_configuration() -> None:
    """The flag is the outermost gate — a dark tutor never blocks a boot."""
    app = create_app(
        _settings(
            tutor_enabled=False,
            tutor_provider="anthropik",
            tutor_api_key="dev-tutor-key",
        )
    )
    assert not hasattr(app.state, "tutor_gateway")


# --- capability honesty -------------------------------------------------------


def test_capability_reports_the_configured_provider_and_model() -> None:
    """An operator can verify the flip from outside the container."""
    with TestClient(create_app(_anthropic_settings())) as client:
        response = client.get("/tutor/capability")

    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "anthropic"
    assert body["model"] == "claude-sonnet-5"
    assert body["enabled"] is True
    assert body["version"] == "v1"
    assert _REAL_KEY not in response.text


def test_capability_reports_the_fake_provider_when_unconfigured() -> None:
    """The honest answer for a default deploy is `fake`, not a plausible model."""
    with TestClient(create_app(_settings())) as client:
        body = client.get("/tutor/capability").json()

    assert body["provider"] == "fake"
    assert body["model"] == "fake-model"
