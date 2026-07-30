"""FastAPI application entrypoint.

Run locally:  uvicorn app.main:app --reload
Docs:         http://127.0.0.1:8000/docs
"""

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from alembic.config import Config as AlembicConfig
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from alembic.util.exc import CommandError
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError

from . import __version__
from .config import Settings, get_settings
from .database import Base, create_database_engine, create_session_factory
from .routers import auth, diagnostics
from .routers import settings as settings_router

_DEV_SECRET = Settings.model_fields["secret_key"].default
_DEV_DIAGNOSTICS_TOKEN = Settings.model_fields["diag_token"].default
_ALEMBIC_INI = Path(__file__).resolve().parents[1] / "alembic.ini"
_logger = logging.getLogger(__name__)


def _guard_prod(settings: Settings) -> None:
    """A misconfigured prod deploy must fail the BOOT, not serve traffic
    (round 120)."""
    if settings.env != "prod":
        return
    if settings.secret_key == _DEV_SECRET:
        raise RuntimeError(
            "STRUMSIGHT_ENV=prod requires a real secret key — "
            "set STRUMSIGHT_SECRET_KEY."
        )
    if "*" in settings.cors_origins:
        raise RuntimeError(
            "STRUMSIGHT_ENV=prod requires explicit CORS origins — "
            "set STRUMSIGHT_CORS_ORIGINS (wildcard refused)."
        )
    if settings.diagnostics_enabled and (
        not settings.diag_token.strip() or settings.diag_token == _DEV_DIAGNOSTICS_TOKEN
    ):
        raise RuntimeError(
            "Production diagnostics requires a non-empty, non-development "
            "diagnostics token."
        )
    if settings.database_url.startswith("sqlite") and not settings.allow_sqlite_in_prod:
        raise RuntimeError(
            "SQLite in production requires the explicit "
            "STRUMSIGHT_ALLOW_SQLITE=true escape hatch."
        )


def _readiness_failure(application: FastAPI) -> str | None:
    """Return a stable reason code without exposing configuration or DB errors."""
    runtime_settings: Settings = application.state.settings
    try:
        _guard_prod(runtime_settings)
    except RuntimeError:
        return "configuration_invalid"

    engine: Engine = application.state.database_engine
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
            current_heads = frozenset(
                MigrationContext.configure(connection).get_current_heads()
            )
    except SQLAlchemyError:
        return "database_unavailable"

    try:
        alembic_config = AlembicConfig(str(_ALEMBIC_INI))
        expected_heads = frozenset(
            ScriptDirectory.from_config(alembic_config).get_heads()
        )
    except (CommandError, OSError):
        return "migration_mismatch"

    if current_heads != expected_heads:
        return "migration_mismatch"
    return None


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    _guard_prod(settings)
    engine = create_database_engine(settings.database_url)
    session_factory = create_session_factory(engine)

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        try:
            # Explicit local-dev convenience. Production schema changes come
            # only from Alembic; DB outages are reported by readiness.
            if settings.env != "prod":
                try:
                    Base.metadata.create_all(bind=engine)
                except SQLAlchemyError:
                    _logger.exception("Development schema initialization failed")
            yield
        finally:
            engine.dispose()

    app = FastAPI(
        title="StrumSight Account API",
        version=__version__,
        summary="Optional login + cloud settings sync. Detection stays on-device.",
        lifespan=lifespan,
    )
    app.state.database_engine = engine
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        # Auth is a bearer token in the Authorization header, not cookies, so
        # credentials are not needed — and keeping this False lets the default
        # "*" origin stay valid (browsers reject "*" + credentials).
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth.router)
    app.include_router(settings_router.router)
    if settings.diagnostics_enabled:
        app.include_router(diagnostics.router)

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    @app.get("/health/live", tags=["meta"])
    def health_live() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/health/ready", tags=["meta"], response_model=None)
    def health_ready(request: Request) -> dict[str, str] | JSONResponse:
        reason = _readiness_failure(request.app)
        if reason is not None:
            return JSONResponse(
                status_code=503,
                content={"status": "not_ready", "reason": reason},
            )
        return {"status": "ready"}

    if settings.apk_download_enabled:

        @app.get("/download", tags=["meta"])
        def download_apk():
            """Serve the staged Lab APK over the diagnostics tunnel."""
            path = os.environ.get("STRUMSIGHT_APK_PATH", "")
            if not path or not os.path.isfile(path):
                raise HTTPException(status_code=404, detail="no APK staged")
            return FileResponse(
                path,
                media_type="application/vnd.android.package-archive",
                filename="strumsight-lab.apk",
            )

    return app


app = create_app()
