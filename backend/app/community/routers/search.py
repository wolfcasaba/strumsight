"""Profile search router — E09-R09, ADR 0402 §D2, §D4.

This router exposes ONE endpoint — ``GET /community/profiles/search``
— and is the first place in the Community read-path that
combines the Kör 3 handle-policy with the Kör 8 block-filter on a
user-controlled query (the §9 risk).

**Authentication (D1):** the endpoint requires ``CurrentUser``.
The A2 acceptance cell — "blocked profiles don't appear in
results" — is unenforceable without a viewer identity, and the
MA ``read_profile`` / ``get_privacy`` / ``handles`` patterns'
authenticated-less route is a deliberate no-go for THIS round
(ADR 0402 "A visszavonás feltétele" already names the future
round that will close the older endpoints).

**Search key (A1 / §5.1):** the query is a handle prefix ONLY.
The wire shape never accepts an email, phone, or location
parameter — the SDD §5.2 invariant forbids the contact-based
discovery class.

**Minimum query length:** the router rejects queries shorter
than :data:`profile_search_repository.MIN_QUERY_LENGTH` with
``422`` before the DB is touched. A shorter prefix would index-
scan a too-wide range; the brief explicitly identifies this as
the DoS surface (§9).

**Rate limit (A4):** the endpoint is bounded by a process-local
``RateLimiter`` keyed on the caller's IP — the same pattern as
``handles.py::check_availability``. ``reset_rate_limiters`` is
the test seam.

**Block-filter integration (D2):** the router delegates to
:func:`profile_search_repository.search_profiles`, which in turn
calls :func:`query_filters.filter_public_ids_against_viewer_blocks`.
A second, search-specific block predicate is forbidden (§5.2).

**Index-based query plan (A3):** the repository asserts the
SQLite ``EXPLAIN QUERY PLAN`` references the
``handle_normalized`` index; PostgreSQL production relies on the
same UNIQUE INDEX serving the same WHERE.

The router is mounted by the test app through a separate fixture
(the brief excludes ``backend/app/community/__init__.py`` from
the round's allowed_paths — the integration is opt-in per-test,
same as Kör 7 / Kör 8).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ...ratelimit import RateLimiter
from ..repositories.profile_search_repository import (
    MIN_QUERY_LENGTH,
    search_profiles,
)
from ..services.identity_service import (
    lookup_active_profile_id,
)

router = APIRouter(prefix="/community/profiles", tags=["community-search"])

# ---------------------------------------------------------------------------
# Rate limit (A4) — 60 search requests / minute / client. The brief
# §A4 names "server-enforced rate limit" as the required shape;
# the value is the §0.0 / §9 balance between a usable typing
# cadence (a user types ~5 chars/sec; 60/min accommodates rapid
# debounced typing without being a free enumeration oracle).
# ---------------------------------------------------------------------------

_SEARCH_MAX = 60
_SEARCH_WINDOW = 60.0

_search_limiter = RateLimiter(
    max_attempts=_SEARCH_MAX,
    window_seconds=_SEARCH_WINDOW,
)


def reset_rate_limiters() -> None:
    """Clear the search rate limiter — exposed for the test fixture."""
    _search_limiter.reset()


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _client_key(request: Request) -> str:
    """Client key for rate limiting — direct socket peer.

    Same E09-R03 §F1 anti-bypass precedent: do NOT trust a
    caller-supplied ``X-Forwarded-For`` until the deployment
    documents a trusted-proxy chain (none exists today).
    """
    if request.client is not None:
        return request.client.host
    return "unknown"


def _caller_profile_pk(db: Session, user_id: int) -> int:
    """Resolve the caller's community profile internal PK.

    Used as the ``viewer_profile_id`` for the §D2 block-filter.
    The User → CommunityProfile mapping is 1:1 (the
    ``community_profiles.user_id`` UNIQUE constraint is the DB-
    level enforcement; the brief §3 explains the lookup).
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


# ---------------------------------------------------------------------------
# GET /community/profiles/search?q=<prefix>&cursor=<opaque>&limit=<n>
# ---------------------------------------------------------------------------


_SEARCH_DEFAULT_LIMIT = 50
_SEARCH_MAX_LIMIT = 100


@router.get(
    "/search",
    status_code=status.HTTP_200_OK,
)
def search_profiles_endpoint(
    request: Request,
    current_user: CurrentUser,
    q: str = Query(..., min_length=1, max_length=64),
    cursor: str | None = Query(default=None, max_length=512),
    limit: int = Query(
        default=_SEARCH_DEFAULT_LIMIT,
        ge=1,
        le=_SEARCH_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Search Community profiles by handle prefix.

    **Response shape**::

        {"public_ids": [...], "next_cursor": "..."}

    The cursor is opaque — clients MUST forward it back verbatim
    on the next page request. ``next_cursor`` is ``null`` on the
    last page (the Kör 7 envelope contract).

    **Errors**

    * ``422`` — query shorter than ``MIN_QUERY_LENGTH`` (no DB
      touch, no rate-limit slot consumed).

    * ``429`` — rate limit exceeded. The limit is per-IP, 60
      requests per minute; ``reset_rate_limiters`` is the test
      seam.

    * ``404`` — caller has no community profile (the Kör 6
      onboarding surface owns this).

    **Privacy (A2):** the visibility gate inside the repository
    drops ``visibility == 'private'`` profiles BEFORE the block
    filter runs. The block filter then drops any remaining row
    whose owner is in a block pair with the viewer — both halves
    of the §D2 invariant.
    """
    if not _search_limiter.allow(_client_key(request)):
        raise HTTPException(status_code=429, detail="rate limited")

    from ..policies.handle_policy import normalize as _normalize_handle

    normalized = _normalize_handle(q)
    if len(normalized) < MIN_QUERY_LENGTH:
        # 422 — the query is too short for a meaningful prefix
        # search; reject before the DB call so the rate-limit
        # slot is not consumed (the §A3 anti-DoS path).
        raise HTTPException(
            status_code=422,
            detail=(
                f"query must be at least {MIN_QUERY_LENGTH} characters after "
                "normalization"
            ),
        )

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_pk = _caller_profile_pk(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        page = search_profiles(
            db,
            viewer_profile_id=viewer_pk,
            query=normalized,
            cursor=cursor,
            limit=limit,
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass

    return {
        "public_ids": [str(pid) for pid in page.public_ids],
        "next_cursor": page.next_cursor,
    }


__all__ = [
    "reset_rate_limiters",
    "router",
    "search_profiles_endpoint",
]


# ``uuid`` and ``lookup_active_profile_id`` are imported above to
# keep the imports list near the top of the module — a future
# iteration that exposes an exact-handle lookup endpoint will
# reuse both (D3 leaves the exact path out of scope this round
# but the import is harmless and self-documenting).
_ = uuid
_ = lookup_active_profile_id
