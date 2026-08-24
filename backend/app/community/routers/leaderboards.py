"""Community leaderboard router — E09-R23, ADR 0418 D6.

The HTTP surface for the verified-only leaderboard projection
and the opt-in toggle:

* ``GET   /community/leaderboards/{challenge_public_id}`` — paged
  leaderboard for one challenge, cursor pagination. The §A5 cell
  asserts multi-page stability. The challenge's own ``type``
  field decides whether the follow-graph filter applies
  (D4 / Kontextus 5) — there is no client-választható scope.
* ``GET   /community/leaderboards/{challenge_public_id}/me`` —
  the viewer's own rank. Returns 200 with a ``null``-shaped
  payload when the viewer is not in the projection
  (opt-out OR no verified result, A1 + A3). The Flutter UI-bekötés
  is a future round (D6 / Kontextus 6.).
* ``PUT   /community/leaderboards/opt-in`` — toggle the caller's
  own opt-in. The PRESENCE of a row in
  ``community_leaderboard_opt_ins`` is the authoritative signal
  (D2); the response is the echo (``"preferred_in"`` /
  ``"preferred_out"``).

The router follows the Kör 21 / Kör 22 pattern — own
``_session_factory`` / ``_commit_via`` DI seams, inline Pydantic
schemas with ``extra='forbid'``, and a request-scoped session.
It is NOT mounted by ``build_community_router`` (the §0.0
``allowed_paths`` does not include ``community/__init__.py``) —
the Kör 22 precedent (the ``challenges`` router is mounted by the
test fixture's own ``FastAPI()`` instance) is followed exactly.
The production wiring of this router is a future round's
``backend/app/main.py`` work.

All authenticated endpoints resolve the caller's community
profile public_id via the same
``_resolve_caller_profile_public_id`` helper shape as the Kör 22
``challenges.py`` router — the JWT subject is the authoritative
identity, never a body field (§5.1).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..services.leaderboard_service import (
    ChallengeNotFound,
    LeaderboardEntry,
    LeaderboardPage,
    get_leaderboard_page,
    get_own_rank,
    set_opt_in,
)

router = APIRouter(prefix="/community/leaderboards", tags=["community-leaderboards"])


# ---------------------------------------------------------------------------
# Session / commit seams — same pattern as the Kör 21 / 22 routers.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity."""
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


class _SupportsCommits(Protocol):
    """The HTTP endpoints commit through ``request.app.state`` so the
    test seam can override commit semantics without touching the
    service layer."""

    def __call__(self, db: Session) -> None: ...


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "leaderboards_commit", _default_commit)
    fn(db)


def _resolve_caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Resolve the caller's community profile public_id from their
    ``users.id`` (the JWT subject).

    Mirrors the Kör 22 ``_resolve_caller_profile_public_id`` helper.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


def _resolve_caller_profile_internal_id(db: Session, user_id: int) -> int:
    """Resolve the caller's internal ``community_profiles.id`` (PK).

    The service-layer ``set_opt_in`` reads by internal id (matches
    the FK column). Mirrors the Kör 22 ``actor_profile_id``
    resolution pattern.
    """
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT id FROM community_profiles WHERE user_id = :uid"),
        {"uid": user_id},
    ).first()
    if row is None:
        raise ValueError("caller has no community profile")
    return int(row[0])


def _now() -> datetime:
    """Server-time helper — mirrors the Kör 22 ``_now()``."""
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Pydantic schemas — ``extra='forbid'`` rejects any smuggled
# ``metric_value`` / ``rank`` / ``verification_state`` field (§5.1).
# ---------------------------------------------------------------------------


class LeaderboardEntryOut(BaseModel):
    """Wire shape for a single leaderboard entry.

    The internal ``id`` is NEVER serialised (the §6.1
    leak-guard). The ``rank`` is the dense rank assigned AT READ
    TIME — the row's position in the projection (1-based).
    """

    public_id: uuid.UUID
    rank: int
    display_name: str | None
    handle: str | None
    metric_value: int
    submitted_at: datetime
    verified_badge: bool


class LeaderboardPageOut(BaseModel):
    """Wire shape for a single leaderboard page."""

    entries: list[LeaderboardEntryOut]
    next_cursor: str | None


class OptInRequest(BaseModel):
    """Body shape for ``PUT /community/leaderboards/opt-in``.

    Only ``opted_in`` travels on the wire — the caller's profile
    is the JWT subject (server-resolved). ``extra='forbid'``
    rejects any smuggled ``public_id`` / ``profile_id`` field.
    """

    model_config = ConfigDict(extra="forbid")

    opted_in: bool


class OptInOut(BaseModel):
    """Wire shape for the opt-in echo."""

    state: str


class OwnRankOut(BaseModel):
    """Wire shape for ``GET .../me``.

    The ``entry`` is ``None`` when the viewer is not in the
    projection (opt-out OR no verified result, A1 + A3) — the
    Flutter UI renders an empty-rank state from the ``null``
    payload.
    """

    entry: LeaderboardEntryOut | None


# ---------------------------------------------------------------------------
# Internal helper — translate the service dataclass to the
# Pydantic wire shape.
# ---------------------------------------------------------------------------


def _entry_to_out(entry: LeaderboardEntry) -> LeaderboardEntryOut:
    return LeaderboardEntryOut(
        public_id=entry.public_id,
        rank=entry.rank,
        display_name=entry.display_name,
        handle=entry.handle,
        metric_value=entry.metric_value,
        submitted_at=entry.submitted_at,
        verified_badge=entry.verified_badge,
    )


def _page_to_out(page: LeaderboardPage) -> LeaderboardPageOut:
    return LeaderboardPageOut(
        entries=[_entry_to_out(entry) for entry in page.entries],
        next_cursor=page.next_cursor,
    )


# ---------------------------------------------------------------------------
# GET /community/leaderboards/{challenge_public_id}
# ---------------------------------------------------------------------------


@router.get(
    "/{challenge_public_id}",
    status_code=status.HTTP_200_OK,
)
def get_leaderboard(
    challenge_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
) -> LeaderboardPageOut:
    """Paged verified-only leaderboard for ``challenge_public_id``.

    Query params:
    * ``cursor`` — opaque cursor returned by the previous page;
      ``None`` on the first page.
    * ``limit`` — page size, ``[1, 100]`` (server-side bound).

    The §A3 opt-out filter excludes profiles WITHOUT a
    ``community_leaderboard_opt_ins`` row (D2). The §A4
    follow-graph filter applies only to ``type='friends'``
    challenges. The §A2 tie-breaker is the service-layer
    contract — the router does NOT re-sort.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                page = get_leaderboard_page(
                    db,
                    challenge_public_id=challenge_public_id,
                    viewer_profile_public_id=viewer_public_id,
                    cursor=cursor,
                    limit=limit,
                )
            except ChallengeNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
        except HTTPException:
            raise
        return _page_to_out(page)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/leaderboards/{challenge_public_id}/me
# ---------------------------------------------------------------------------


@router.get(
    "/{challenge_public_id}/me",
    status_code=status.HTTP_200_OK,
)
def get_own_rank_endpoint(
    challenge_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> OwnRankOut:
    """The viewer's own leaderboard entry for ``challenge_public_id``.

    Returns ``{entry: null}`` when the viewer is not in the
    projection (opt-out OR no verified result, A1 + A3). The
    Flutter UI-bekötés is a future round (D6 / Kontextus 6.).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                viewer_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                entry = get_own_rank(
                    db,
                    challenge_public_id=challenge_public_id,
                    viewer_profile_public_id=viewer_public_id,
                )
            except ChallengeNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
        except HTTPException:
            raise
        return OwnRankOut(entry=_entry_to_out(entry) if entry is not None else None)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# PUT /community/leaderboards/opt-in
# ---------------------------------------------------------------------------


@router.put(
    "/opt-in",
    status_code=status.HTTP_200_OK,
)
def put_opt_in(
    request: Request,
    current_user: CurrentUser,
    payload: OptInRequest,
) -> OptInOut:
    """Toggle the caller's leaderboard opt-in.

    Body shape::

        { "opted_in": <bool> }

    Returns ``{state: "opted_in" | "opted_out"}``. Idempotent
    (a second call with the same ``opted_in`` returns the same
    state without raising).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                profile_internal_id = _resolve_caller_profile_internal_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            state = set_opt_in(
                db,
                profile_id=profile_internal_id,
                opted_in=payload.opted_in,
                now=_now(),
            )
            _commit_via(request, db)
        except HTTPException:
            raise
        return OptInOut(state=state)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = ["router"]
