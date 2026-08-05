"""Runtime configuration, loaded from environment / .env.

Every value has a dev-safe default so the backend boots with zero setup.
Override in production via real environment variables (NEVER commit secrets).
"""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEFAULT_DIAGNOSTICS_DIR = str(Path(__file__).resolve().parents[1] / "diagnostics_data")
BCRYPT_MAX_PASSWORD_BYTES = 72


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="STRUMSIGHT_",
        extra="ignore",
        populate_by_name=True,
    )

    # "dev" boots with zero setup; "prod" refuses to boot on insecure
    # defaults (round 120) — set STRUMSIGHT_ENV=prod on any public deploy.
    env: str = "dev"

    # SECURITY: override in production. A fixed dev key keeps tokens stable
    # across reloads during local development.
    secret_key: str = "dev-insecure-change-me-in-production"
    algorithm: str = "HS256"
    access_token_expires_minutes: int = 60 * 24 * 14  # 14 days — mobile-friendly

    # SQLite by default (zero-config). Swap to Postgres in prod by setting
    # STRUMSIGHT_DATABASE_URL=postgresql+psycopg://user:pass@host/db
    database_url: str = "sqlite:///./strumsight.db"
    allow_sqlite_in_prod: bool = Field(
        default=False,
        # Keep the explicit Settings(allow_sqlite_in_prod=...) kwarg through
        # populate_by_name while mapping the documented short env name exactly.
        validation_alias="STRUMSIGHT_ALLOW_SQLITE",
    )

    # CORS origins for the Flutter web/dev client. "*" is fine for dev.
    cors_origins: list[str] = ["*"]

    # Lab services stay zero-setup in dev, but are absent from production
    # unless explicitly enabled. The validator supplies environment-sensitive
    # defaults while preserving explicit kwargs and STRUMSIGHT_* overrides.
    diagnostics_enabled: bool = True
    apk_download_enabled: bool = True
    diag_token: str = "strumsight-lab-dev"
    diag_dir: str = _DEFAULT_DIAGNOSTICS_DIR

    # AI Tutor proxy (ADR 0131) — feature-flagged, config-driven provider selection.
    # The provider secret stays on the server; the client never sees it.
    tutor_enabled: bool = False
    tutor_provider: str = "fake"
    tutor_model: str = "fake-model"
    tutor_api_key: str = "dev-tutor-key"
    tutor_allowed_providers: dict[str, list[str]] = {"fake": ["fake-model"]}
    tutor_max_request_bytes: int = 4000
    tutor_max_history_messages: int = 20
    tutor_max_context_bytes: int = 8000
    tutor_max_output_bytes: int = 2000
    tutor_rate_limit_max: int = 30
    tutor_rate_limit_window: int = 60
    tutor_daily_token_limit: int = 50000
    tutor_timeout_seconds: float = 30.0

    # Tutor proxy (ADR 0131) — feature-flagged, config-driven provider selection.
    # The provider secret stays on the server; the client never sees it.
    tutor_enabled: bool = False
    tutor_provider: str = "fake"
    tutor_model: str = "fake-model"
    tutor_api_key: str = "dev-tutor-key"
    tutor_allowed_providers: dict[str, list[str]] = {"fake": ["fake-model"]}
    tutor_max_request_bytes: int = 4000
    tutor_max_history_messages: int = 20
    tutor_max_context_bytes: int = 8000
    tutor_max_output_bytes: int = 2000
    tutor_rate_limit_max: int = 30
    tutor_rate_limit_window: int = 60
    tutor_daily_token_limit: int = 50000
    tutor_timeout_seconds: float = 30.0

    @model_validator(mode="before")
    @classmethod
    def _default_lab_flags_for_environment(cls, values):
        if not isinstance(values, dict):
            return values
        resolved = dict(values)
        default_enabled = resolved.get("env", "dev") != "prod"
        resolved.setdefault("diagnostics_enabled", default_enabled)
        resolved.setdefault("apk_download_enabled", default_enabled)
        return resolved


@lru_cache
def get_settings() -> Settings:
    return Settings()
