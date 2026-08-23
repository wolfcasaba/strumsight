"""Community safety router — E09-R08, ADR 0402.

Block / mute / list-blocked / list-muted endpoints. All authenticated
(``CurrentUser``); the POST endpoints take ``idempotency_key`` in the
JSON body and the DELETE endpoints take it as a query parameter (the
same ADR 0401 §1 convention used by ``unfollow`` /
``remove_follower`` — the Flutter ``api_client.dart::delete()``
carries no JSON body).

Endpoints:

* ``POST   /community/profiles/{public_id}/block`` — create a block
  (atomic transaction that closes follow edges + pending requests,
  ADR 0402 §D1).
* ``DELETE /community/profiles/{public_id}/block?idempotency_key=...`` —
  unblock (idempotent no-op if no block exists).
* ``POST   /community/profiles/{public_id}/mute`` — create a mute
  (no follow-graph mutation, no notification — §5.2).
* ``DELETE /community/profiles/{public_id}/mute?idempotency_key=...`` —
  unmute (idempotent).
* ``GET    /community/blocked?cursor=&limit=`` — the caller's own
  blocked profiles list.
* ``GET    /community/muted?cursor=&limit=`` — the caller's own muted
  profiles list.

The router is mounted by the test fixtures directly into a
self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched per ADR 0402 §5 /
brief §2.7 / §STOP-feltétel 1.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..services.block_service import (
    SelfBlockNotAllowed,
    block,
    list_blocked,
    list_muted,
    mute,
    unblock,
    unmute,
)

router = APIRouter(prefix="/community", tags=["community-safety"])


# ---------------------------------------------------------------------------
# Session factory seam — same pattern as routers/social_graph.py.
# ---------------------------------------------------------------------------


def _session_factory(request: Request) -> Iterator[Session]:
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "safety_commit", _default_commit)
    fn(db)


# ---------------------------------------------------------------------------
# Resolve the caller's community profile public_id (mirrors the
# pattern in routers/social_graph.py — the JWT subject is ``users.id``
# and the community module adds a 1:1 ``community_profiles`` row
# whose ``public_id`` is what the wire shape uses).
# ---------------------------------------------------------------------------


def _caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
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


# ---------------------------------------------------------------------------
# POST /community/profiles/{public_id}/block
# ---------------------------------------------------------------------------


@router.post(
    "/profiles/{public_id}/block",
    status_code=status.HTTP_200_OK,
)
def post_block(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Create a block edge for ``public_id`` (idempotent).

    Body shape::

        {"idempotency_key": "<string>"}

    Response::

        {"status": "blocked", "public_id": "<blocked peer's public_id>"}

    Idempotent at the row level: a retry returns the existing block
    row (same row, same public_id) — no 409, no exception.
    """
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            blocker_public_id = _caller_profile_public_id(db, current_user.id)
            row = block(
                db,
                blocker_public_id=blocker_public_id,
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except SelfBlockNotAllowed as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {
            "status": "blocked",
            "public_id": str(public_id),
            "block_public_id": str(row.public_id),
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/block   (unblock)
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/block",
    status_code=status.HTTP_200_OK,
)
def delete_block(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Remove a block edge (idempotent no-op if no block exists).

    The §5.3 invariant: a previous follow edge is NOT recreated by
    unblock — the two operations are independent.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            blocker_public_id = _caller_profile_public_id(db, current_user.id)
            deleted = unblock(
                db,
                blocker_public_id=blocker_public_id,
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {
            "status": "unblocked" if deleted else "noop",
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/profiles/{public_id}/mute
# ---------------------------------------------------------------------------


@router.post(
    "/profiles/{public_id}/mute",
    status_code=status.HTTP_200_OK,
)
def post_mute(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Create a mute edge for ``public_id`` (idempotent).

    §5.2 invariant: NO follow-graph mutation, NO notification to the
    muted party. The row exists, or it does not — that is the
    entire state machine.
    """
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            muter_public_id = _caller_profile_public_id(db, current_user.id)
            row = mute(
                db,
                muter_public_id=muter_public_id,
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except SelfBlockNotAllowed as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {
            "status": "muted",
            "public_id": str(public_id),
            "mute_public_id": str(row.public_id),
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/mute   (unmute)
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/mute",
    status_code=status.HTTP_200_OK,
)
def delete_mute(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Remove a mute edge (idempotent no-op if no mute exists)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            muter_public_id = _caller_profile_public_id(db, current_user.id)
            deleted = unmute(
                db,
                muter_public_id=muter_public_id,
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {
            "status": "unmuted" if deleted else "noop",
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/blocked   GET /community/muted
# ---------------------------------------------------------------------------


_SAFETY_LIST_DEFAULT_LIMIT = 50
_SAFETY_LIST_MAX_LIMIT = 200


@router.get(
    "/blocked",
    status_code=status.HTTP_200_OK,
)
def get_blocked(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_SAFETY_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_SAFETY_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of the caller's blocked profiles.

    Response::

        {"public_ids": [...], "next_cursor": ...}

    Same envelope shape as ``get_followers`` /
    ``get_following`` — the Flutter screen's list controller can
    reuse the decoder.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _caller_profile_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        page = list_blocked(
            db,
            profile_public_id=viewer_public_id,
            cursor=cursor,
            limit=limit,
        )
        return {
            "public_ids": [str(value) for value in page.public_ids],
            "next_cursor": page.next_cursor,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.get(
    "/muted",
    status_code=status.HTTP_200_OK,
)
def get_muted(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_SAFETY_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_SAFETY_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of the caller's muted profiles.

    Same envelope shape as ``get_blocked``.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            viewer_public_id = _caller_profile_public_id(db, current_user.id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        page = list_muted(
            db,
            profile_public_id=viewer_public_id,
            cursor=cursor,
            limit=limit,
        )
        return {
            "public_ids": [str(value) for value in page.public_ids],
            "next_cursor": page.next_cursor,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "delete_block",
    "delete_mute",
    "get_blocked",
    "get_muted",
    "post_block",
    "post_mute",
    "router",
]
