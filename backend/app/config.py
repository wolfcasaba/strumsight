"""Runtime configuration, loaded from environment / .env.

Every value has a dev-safe default so the backend boots with zero setup.
Override in production via real environment variables (NEVER commit secrets).
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="STRUMSIGHT_",
        extra="ignore",
    )

    # SECURITY: override in production. A fixed dev key keeps tokens stable
    # across reloads during local development.
    secret_key: str = "dev-insecure-change-me-in-production"
    algorithm: str = "HS256"
    access_token_expires_minutes: int = 60 * 24 * 14  # 14 days — mobile-friendly

    # SQLite by default (zero-config). Swap to Postgres in prod by setting
    # STRUMSIGHT_DATABASE_URL=postgresql+psycopg://user:pass@host/db
    database_url: str = "sqlite:///./strumsight.db"

    # CORS origins for the Flutter web/dev client. "*" is fine for dev.
    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
