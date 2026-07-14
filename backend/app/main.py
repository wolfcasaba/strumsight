"""FastAPI application entrypoint.

Run locally:  uvicorn app.main:app --reload
Docs:         http://127.0.0.1:8000/docs
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from . import __version__
from .config import Settings, get_settings
from .database import Base, engine
from .routers import auth, diagnostics, settings as settings_router

_DEV_SECRET = Settings.model_fields["secret_key"].default


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


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    _guard_prod(settings)
    # Dev convenience: create tables on boot. Production should use migrations
    # (Alembic) instead — see backend/README.md.
    Base.metadata.create_all(bind=engine)

    app = FastAPI(
        title="StrumSight Account API",
        version=__version__,
        summary="Optional login + cloud settings sync. Detection stays on-device.",
    )
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
    app.include_router(diagnostics.router)

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    @app.get("/download", tags=["meta"])
    def download_apk():
        """Serve the staged Lab-mode APK for easy on-phone install over the
        (already-authorized) diagnostics tunnel — set STRUMSIGHT_APK_PATH on the
        box. Generic (points at a file), no secret in the code."""
        import os

        from fastapi.responses import FileResponse
        path = os.environ.get("STRUMSIGHT_APK_PATH", "")
        if not path or not os.path.isfile(path):
            raise HTTPException(status_code=404, detail="no APK staged")
        return FileResponse(path, media_type="application/vnd.android.package-archive",
                            filename="strumsight-lab.apk")

    return app


app = create_app()
