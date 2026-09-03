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
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError

from . import __version__
from .community import build_community_router, community_readiness_failure
from .config import Settings, get_settings
from .database import Base, create_database_engine, create_session_factory
from .routers import auth, diagnostics
from .routers import settings as settings_router

_DEV_SECRET = Settings.model_fields["secret_key"].default
_DEV_DIAGNOSTICS_TOKEN = Settings.model_fields["diag_token"].default
_DEV_TUTOR_KEY = Settings.model_fields["tutor_api_key"].default
_ALEMBIC_INI = Path(__file__).resolve().parents[1] / "alembic.ini"
_logger = logging.getLogger(__name__)

# ADR 0449 D1/D3: the gate is active only for the two deploy environments —
# dev/lab keep the create_all-based dev path unblocked (ADR 0060).
_TRAFFIC_GATE_ENVIRONMENTS = frozenset({"staging", "prod"})


class _NotReady(Exception):
    """Raised by `_traffic_gate` (a per-router dependency, not middleware —
    see its docstring for why) when the migration head doesn't match."""

    def __init__(self, reason: str) -> None:
        self.reason = reason


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
    if settings.tutor_enabled and (
        not settings.tutor_api_key.strip() or settings.tutor_api_key == _DEV_TUTOR_KEY
    ):
        raise RuntimeError(
            "Production tutor requires a non-empty, non-development API key — "
            "set STRUMSIGHT_TUTOR_API_KEY."
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

    # ADR 0497 D4: the Community gate runs AFTER the base checks pass, so
    # a disabled Community deploy's readiness verdict is untouched, and the
    # `community_requires_postgres` reason is reached on its own merits —
    # not shadowed by an unrelated base-check failure (round brief §0.0 R5).
    if runtime_settings.community_enabled:
        community_reason = community_readiness_failure(
            engine, runtime_settings, _ALEMBIC_INI
        )
        if community_reason is not None:
            return community_reason

    return None


def _traffic_gate(request: Request) -> None:
    """Readiness-driven traffic gate dependency (ADR 0449 D1-D3).

    A per-router `dependencies=[Depends(_traffic_gate)]`, not blanket HTTP
    middleware: middleware runs before routing, so it would 503 a path that
    isn't even registered (e.g. `/diagnostics` while
    `diagnostics_enabled=False` in prod) instead of letting FastAPI 404 it —
    that broke the existing `test_hardening.py::test_prod_defaults_do_not_register_lab_routes`
    (A7). Attached only to business routers, so `/health`, `/health/live`,
    `/health/ready` (defined directly on `app`, without this dependency)
    always stay reachable (D2), and a disabled surface keeps 404ing.
    """
    runtime_settings: Settings = request.app.state.settings
    if runtime_settings.env not in _TRAFFIC_GATE_ENVIRONMENTS:
        return
    reason = _readiness_failure(request.app)
    if reason is not None:
        raise _NotReady(reason)


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

    @app.exception_handler(_NotReady)
    async def _not_ready_handler(_request: Request, exc: _NotReady) -> JSONResponse:
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "reason": exc.reason},
        )

    _gated = [Depends(_traffic_gate)]
    app.include_router(auth.router, dependencies=_gated)
    app.include_router(settings_router.router, dependencies=_gated)
    if settings.diagnostics_enabled:
        app.include_router(diagnostics.router, dependencies=_gated)
    if settings.tutor_enabled:
        from .ratelimit import RateLimiter
        from .tutor.provider_gateway import FakeProviderGateway
        from .tutor.provider_registry import ProviderRegistry
        from .tutor.router import router as tutor_router
        from .tutor.router import set_service
        from .tutor.service import TutorLimits, TutorService
        from .tutor.usage import UsageGuard

        registry = ProviderRegistry(
            allowed=settings.tutor_allowed_providers,
            provider=settings.tutor_provider,
            model=settings.tutor_model,
        )
        gateway = FakeProviderGateway()
        usage_guard = UsageGuard(
            rate_limiter=RateLimiter(
                max_attempts=settings.tutor_rate_limit_max,
                window_seconds=settings.tutor_rate_limit_window,
            ),
            daily_token_limit=settings.tutor_daily_token_limit,
        )
        limits = TutorLimits(
            max_request_bytes=settings.tutor_max_request_bytes,
            max_history_messages=settings.tutor_max_history_messages,
            max_context_bytes=settings.tutor_max_context_bytes,
            max_output_bytes=settings.tutor_max_output_bytes,
        )
        service = TutorService(
            gateway=gateway,
            registry=registry,
            api_key=settings.tutor_api_key,
            usage_guard=usage_guard,
            limits=limits,
            timeout_seconds=settings.tutor_timeout_seconds,
        )
        set_service(service)
        app.include_router(tutor_router, dependencies=_gated)
    if settings.community_enabled:
        community_router = build_community_router(settings)
        if community_router is not None:
            app.include_router(community_router, dependencies=_gated)

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

        @app.get("/download", tags=["meta"], dependencies=_gated)
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
