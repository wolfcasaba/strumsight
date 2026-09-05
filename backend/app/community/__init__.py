"""Community (Epic 9) backend module boundary.

E09-R02, ADR 0396; wired live E15-R12, ADR 0497. This module owns:

* the ``community_profiles`` / ``community_privacy_settings`` ORM models
  (BigInteger internal PK + ``Uuid`` public_id, see ADR 0396 §1),
* the Pydantic response contract that whitelists only ``public_id`` and never
  leaks the internal ``id`` (A2),
* a ``build_community_router`` factory that aggregates 15 of the 17 router
  modules behind ``settings.community_enabled`` (registration-level gate,
  ADR 0497 D1 — the module simply does not exist in the route table when
  off, no runtime 403) plus the sub-flags (D2), in the deterministic order
  D3 requires. ``handles`` and ``privacy`` are deliberately NOT aggregated
  (ADR 0497 D6): neither router requires authentication on any of its
  routes (measured: their 6 route-methods, out of 48 total, all answered
  an anonymous caller instead of 401/403 — see each router's own docstring
  for why auth is still pending), so mounting them would open a public
  write surface (handle takeover, privacy-setting tampering) ahead of
  their authz landing in a future round,
* a ``community_readiness_failure`` gate, called from ``main.py``'s
  ``/health/ready`` when the module is enabled (D4).

The acceptance points are spelled out in
``docs/rounds/e09-r02-backend-community-module-and-migration.md`` §6 (Kör 2)
and ``docs/rounds/e15-r12-backend-mounting-and-end-to-end.md`` §6 (Kör 12 —
the live wiring). The tests live in ``backend/tests/community/`` (Kör 2
module-boundary suite, untouched this round — ADR 0497 Következmények) and
``backend/tests/test_community_mounting.py`` / ``test_client_contract_parity.py``
(Kör 12).
"""

from __future__ import annotations

from pathlib import Path

from alembic.config import Config as AlembicConfig
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from alembic.util.exc import CommandError
from fastapi import APIRouter
from fastapi.routing import APIRoute
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

# ADR 0497 D2/D1: the write-method branch (POST/PUT/PATCH/DELETE) of the
# posts + comments + social-graph (follow-request) routers is a REGISTRATION-level
# gate on ``community_writes_enabled`` — same fail-closed strength as the
# top-level module flag (D1: "route-ok nem regisztrálódnak", not a runtime
# 403). GET/HEAD/OPTIONS on those same routers stay registered either way
# (A3 — "az írási ág nem elérhető, az olvasási igen"). The ``profile``
# router is deliberately NOT included in this gate: its two write routes
# (create/update the caller's own profile) are identity/onboarding, not
# the "post, comment, reaction, follow-request" content-write domain ADR
# 0395 §6 names, and E09-R06's ``backend/tests/community/test_profile_service.py``
# (tilos zóna, R4) already exercises them under ``community_enabled=True``
# alone — gating them here would turn that suite red.
_SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def _reads_only(router: APIRouter) -> APIRouter:
    """A copy of ``router`` carrying only its safe-method routes."""
    reads = APIRouter()
    reads.routes = [
        route
        for route in router.routes
        if isinstance(route, APIRoute) and route.methods <= _SAFE_METHODS
    ]
    return reads


def build_community_router(settings) -> APIRouter | None:
    """Aggregate 15 of the 17 Community router modules into one
    ``APIRouter``, or return ``None`` when the module is disabled.

    Registration-level gating (ADR 0497 D1): a disabled module — or a
    disabled sub-flag branch — never adds routes to the table, so the
    caller (``main.py``'s ``if settings.community_enabled:``, or this
    round's ``backend/tests/community/conftest.py``, unchanged) gets a
    plain 404 for anything that doesn't exist, never a runtime 403.

    ``handles`` and ``privacy`` are excluded fail-closed (ADR 0497 D6):
    both routers' own docstrings say their authz is a future round's job
    (``routers/handles.py:16-19,95,239-241`` — "internal endpoint, not
    yet exposed"/"auth lands in Kör 6"; ``routers/privacy.py:5-9,194-201``
    — "deliberately unmounted"/authz-policy "out of scope"), and measured
    behaviour confirms it: every one of their 6 route-methods answers an
    anonymous caller instead of 401/403 — including a ``PUT`` that
    overwrites another user's privacy visibility and a ``POST`` that
    claims a handle onto a raw internal ``community_profiles.id``. The
    client never calls either router (absent from
    ``docs/contracts/client-backend-endpoints.json``), so leaving them
    out costs no functionality and closes an authless write surface. This
    is a fail-closed default, not a permanent exclusion: mounting them is
    the job of the future round that lands their auth (ADR 0400
    Következmények (c)).

    Sub-flags (D2, independent of the master flag and of each other):

    * ``community_writes_enabled`` — gates the write-method routes of
      ``posts``, ``comments`` and ``social_graph`` (see ``_reads_only``
      above). A ``comments`` router 2026-09-05-én került a listára: a
      komment az ADR 0395 §6 írás-domainjének NEVESÍTETT tagja, és a
      service-e a Kör 12 óta tesztelt volt HTTP-felület nélkül. Not
      applied to ``bookmarks``/``challenges``/``moderation``/``reports``/
      ``safety``: none of those are named by ADR 0395 §6's write-domain
      list ("poszt, komment, reakció, follow-request"), and none are
      exercised through this factory by the tilos-zóna suite, so this
      round leaves their existing all-or-nothing-with-
      ``community_enabled`` behaviour as measured.
    * ``community_media_enabled`` — already self-gated inside
      ``services/media_upload_service.py`` (checked at every call site);
      no aggregated router exposes a dedicated media-upload HTTP surface
      yet, so there is nothing to conditionally mount here.
    * ``community_leaderboard_enabled`` — gates the whole ``leaderboards``
      router (an all-or-nothing competitive surface, not a read/write
      split).
    * ``community_clubs_enabled`` — gates the whole ``clubs`` router
      (an all-or-nothing surface, like ``leaderboards``). 2026-09-05 óta
      van mit kapuznia: a router addig HIÁNYZOTT, holott a
      ``club_service.py`` és a ``club_content_service.py`` a Kör 24 óta
      létezett és tesztelt volt.

    Router order is NOT alphabetical — it is the ADR 0497 D3 contract:
    ``search`` (a literal ``/community/profiles/search`` route) MUST be
    registered before ``profile`` (whose ``/community/profiles/{public_id}``
    is a single-segment catch-all at the same depth); FastAPI/Starlette
    matches routes in registration order, so registering ``profile``
    first would make it swallow ``GET /community/profiles/search`` as
    ``public_id="search"``. Every other aggregated router's prefix is
    unique, so ``profile`` is placed last as the general D3 rule (literal
    routes before the broadest param-collector) rather than reasoning
    about each pair individually.
    """
    if not settings.community_enabled:
        return None

    # Local imports so a disabled module never imports the router tree —
    # keeps ``app.community`` cheap to import for builds that never
    # enable Community (mirrors the pre-existing single-router pattern).
    # ``handles`` and ``privacy`` are deliberately NOT imported here — see
    # the docstring above (ADR 0497 D6).
    from .routers.bookmarks import router as bookmarks_router
    from .routers.challenges import router as challenges_router
    from .routers.clubs import router as clubs_router
    from .routers.comments import router as comments_router
    from .routers.feed import router as feed_router
    from .routers.leaderboards import router as leaderboards_router
    from .routers.moderation import router as moderation_router
    from .routers.notifications import router as notifications_router
    from .routers.posts import router as posts_router
    from .routers.profile import router as profile_router
    from .routers.reactions import router as reactions_router
    from .routers.reports import router as reports_router
    from .routers.safety import router as safety_router
    from .routers.search import router as search_router
    from .routers.social_graph import router as social_graph_router

    aggregate = APIRouter()
    writes_on = settings.community_writes_enabled

    aggregate.include_router(bookmarks_router)
    aggregate.include_router(challenges_router)
    # A `clubs` a `community_clubs_enabled` al-kapu alatt áll — egész
    # felület, nem olvas/ír bontás, mint a `leaderboards`. A kapu eddig
    # üresen állt („no clubs router exists yet"); 2026-09-05 óta van mit
    # kapuznia.
    if settings.community_clubs_enabled:
        aggregate.include_router(clubs_router)
    # A komment az ADR 0395 §6 írás-domainjének NEVESÍTETT tagja („poszt,
    # komment, reakció, follow-request"), ezért — a `posts` és a
    # `social_graph` mintájára — az írási ága a `community_writes_enabled`
    # regisztrációs kapuja alatt áll, az olvasási (GET) ág viszont a
    # kapu állásától függetlenül regisztrálódik.
    aggregate.include_router(
        comments_router if writes_on else _reads_only(comments_router)
    )
    aggregate.include_router(feed_router)
    if settings.community_leaderboard_enabled:
        aggregate.include_router(leaderboards_router)
    aggregate.include_router(moderation_router)
    # A `notifications` NEM áll a `community_writes_enabled` kapu alatt: az
    # olvasottra-jelölés és a beállítás-írás nem tagja az ADR 0395 §6
    # írás-domainjének („poszt, komment, reakció, follow-request"), és a
    # bookmarks/challenges/moderation/reports/safety routerek ugyanezen az
    # alapon maradtak all-or-nothing viszonyban a fő kapuval.
    aggregate.include_router(notifications_router)
    aggregate.include_router(posts_router if writes_on else _reads_only(posts_router))
    # A `reactions` az ADR 0395 §6 írás-domainjének NEVESÍTETT tagja
    # („poszt, komment, reakció, follow-request"), ezért a
    # `community_writes_enabled` regisztrációs kapuja alatt áll. Itt NEM a
    # `_reads_only` szűrőt használjuk, mint a `posts`/`comments` esetén: a
    # router MINDEN útvonala írás (PUT/DELETE), így a szűrt változat egy
    # ÜRES routert adna — a feltételes regisztráció mondja ki ugyanezt
    # olvashatóan. A reakció-számlálót a feed-elem továbbra is viszi, a
    # kapu állásától függetlenül: az olvasás nem ezen a felületen megy.
    if writes_on:
        aggregate.include_router(reactions_router)
    aggregate.include_router(reports_router)
    aggregate.include_router(safety_router)
    aggregate.include_router(search_router)  # before profile — D3
    aggregate.include_router(
        social_graph_router if writes_on else _reads_only(social_graph_router)
    )
    aggregate.include_router(profile_router)  # last — D3

    return aggregate


def community_readiness_failure(
    engine: Engine,
    settings,
    alembic_ini: Path,
) -> str | None:
    """Analogous to ``main.py._readiness_failure``, scoped to the Community
    migration chain. Called from ``main.py``'s ``_readiness_failure`` when
    ``settings.community_enabled`` is true (E15-R12, ADR 0497 D4) — after
    the base checks pass, so a disabled-Community deploy's readiness verdict
    is unaffected and the ``community_requires_postgres`` reason is reached
    on its own, not shadowed by an unrelated base-check failure (round
    brief §0.0 R5).

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
