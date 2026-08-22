"""Community (Epic 9) backend module boundary.

E09-R02, ADR 0396. This module owns:

* the ``community_profiles`` / ``community_privacy_settings`` ORM models
  (BigInteger internal PK + ``Uuid`` public_id, see ADR 0396 §1),
* the Pydantic response contract that whitelists only ``public_id`` and never
  leaks the internal ``id`` (A2),
* a router that registers itself conditionally based on
  ``settings.community_enabled``,
* a ``build_community_router`` factory and a ``community_readiness_failure``
  gate — both self-contained here so the live ``backend/app/main.py`` does
  NOT need to be touched this round. Wiring the router into
  ``create_app()`` and ``/health/ready`` is a future round's job per
  ADR 0395 Következmények 3. pont and ADR 0396 §3–4.

The acceptance points are spelled out in
``docs/rounds/e09-r02-backend-community-module-and-migration.md`` §6. The
tests live in ``backend/tests/community/``.
"""

from __future__ import annotations

from pathlib import Path

from alembic.config import Config as AlembicConfig
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from alembic.util.exc import CommandError
from fastapi import APIRouter
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError

# Re-export the ORM models so that ``Base.metadata`` discovers them as soon as
# the module is imported — this is what Alembic's ``env.py`` relies on for
# autogenerate parity.
from .models.profile import CommunityPrivacySettings, CommunityProfile
from .schemas.profile import CommunityPrivacySettingsOut, CommunityProfileOut

__all__ = [
    "CommunityPrivacySettings",
    "CommunityPrivacySettingsOut",
    "CommunityProfile",
    "CommunityProfileOut",
    "build_community_router",
    "community_readiness_failure",
]


def build_community_router(settings) -> APIRouter | None:
    """Return the Community router only when the module is enabled.

    Mirrors ``main.py``'s ``if settings.tutor_enabled: app.include_router(...)``
    pattern, but lives entirely inside the community module so this round
    never has to touch the forbidden ``backend/app/main.py``. Wiring this
    into the live ``create_app()`` app is a future round's job
    (ADR 0395 Következmények 3. pont) — this function's only consumer THIS
    round is ``backend/tests/community/conftest.py``'s own, self-contained
    test app.
    """
    if not settings.community_enabled:
        return None
    # Local import so that the factory returns None (no router import) when
    # the module is disabled — keeps ``app.community`` cheap to import even
    # for builds that never enable Community.
    from .routers.profile import router as community_router

    return community_router


def community_readiness_failure(
    engine: Engine,
    settings,
    alembic_ini: Path,
) -> str | None:
    """Analogous to ``main.py._readiness_failure``, scoped to the Community
    migration chain. Not wired into ``/health/ready`` this round (that call
    site is ``main.py``, out of scope) — a future round's job per ADR 0396
    §4 / ADR 0395 Következmények 2. pont.

    Fail-closed ordering:

    1. ``community_enabled`` AND ``env == "prod"`` AND not
       ``community_postgres_ready`` -> ``"community_requires_postgres"``.
    2. Unable to connect -> ``"database_unavailable"``.
    3. ``alembic`` scripts unreachable or heads missing
       -> ``"migration_mismatch"``.
    4. ``current_heads`` != ``expected_heads`` -> ``"migration_mismatch"``.
    5. Healthy -> ``None``.
    """
    if (
        settings.community_enabled
        and getattr(settings, "env", "dev") == "prod"
        and not settings.community_postgres_ready
    ):
        return "community_requires_postgres"

    try:
        with engine.connect() as connection:
            current_heads: frozenset[str | None] = frozenset(
                MigrationContext.configure(connection).get_current_heads()
            )
    except SQLAlchemyError:
        return "database_unavailable"

    try:
        expected_heads: frozenset[str | None] = frozenset(
            ScriptDirectory.from_config(AlembicConfig(str(alembic_ini))).get_heads()
        )
    except (CommandError, OSError):
        return "migration_mismatch"

    return None if current_heads == expected_heads else "migration_mismatch"
