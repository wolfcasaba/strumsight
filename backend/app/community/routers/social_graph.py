"""Community social-graph router — E09-R07, ADR 0401 §3, §5, §7.

This router exposes the follow / follow-request / follower-removal
HTTP endpoints. It is mounted in the test app through a separate
fixture (the brief §0.0 5. pont — the ``build_community_router``
factory in ``community/__init__.py`` is in the §3 tilos zóna, so
this round ships its own mount point in the test conftest).

Endpoints:

* ``POST /community/profiles/{public_id}/follow`` — public target
  ⇒ immediate follow; private target ⇒ pending request. Returns
  ``{"request_id": ..., "status": "following" | "requested"}``.
  Idempotent at the state-machine level (retry is success).
* ``POST /community/follow-requests/{request_id}/accept`` — accept
  a pending request (target-only). Returns the same shape as
  follow.
* ``POST /community/follow-requests/{request_id}/decline`` — decline
  a pending request (target-only).
* ``DELETE /community/profiles/{public_id}/follow`` — unfollow
  (active edge DELETE) OR cancel a pending request (UPDATE row to
  ``cancelled``). Idempotent no-op if neither exists. Returns
  ``{"outcome": "unfollowed" | "cancelled" | "noop"}``.
* ``DELETE /community/profiles/{public_id}/followers/{follower_id}`` —
  remove a follower. Idempotent no-op if not a follower.
* ``GET /community/profiles/{public_id}/followers?cursor=...&limit=...`` —
  cursor-paginated followers list.
* ``GET /community/profiles/{public_id}/following?cursor=...&limit=...`` —
  cursor-paginated following list.

All authenticated endpoints take an ``idempotency_key`` either in
the JSON body (POST endpoints) or as a query parameter (DELETE
endpoints — the Kör 5 ``api_client.dart``'s ``delete()`` does not
carry a JSON body, ADR 0401 §1 / §3).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..services.follow_service import (
    FollowRequestNotFound,
    SelfFollowNotAllowed,
    accept_follow_request,
    decline_follow_request,
    follow,
    list_followers,
    list_following,
    remove_follower,
    unfollow,
)

router = APIRouter(prefix="/community", tags=["community-social-graph"])


# ---------------------------------------------------------------------------
# Session factory seam — mirrors the Kör 3 / Kör 4 pattern.
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
    service layer (the §6.1 valódi-sértés próba uses this)."""

    def __call__(self, db: Session) -> None: ...


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn = getattr(request.app.state, "follow_commit", _default_commit)
    fn(db)


# ---------------------------------------------------------------------------
# POST /community/profiles/{public_id}/follow
# ---------------------------------------------------------------------------


@router.post(
    "/profiles/{public_id}/follow",
    status_code=status.HTTP_200_OK,
)
def post_follow(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Create (or recycle) a follow edge or a follow request.

    Body shape::

        {"idempotency_key": "<string>"}

    The response carries ``request_id`` (the public_id of the new
    row) and ``status`` (``"following"`` for an active edge,
    ``"requested"`` for a pending request).
    """
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            result = follow(
                db,
                follower_public_id=_caller_profile_public_id(db, current_user.id),
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except SelfFollowNotAllowed as exc:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {
            "request_id": str(result.request_id),
            "status": result.status,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/follow-requests/{request_id}/accept
# ---------------------------------------------------------------------------


@router.post(
    "/follow-requests/{request_id}/accept",
    status_code=status.HTTP_200_OK,
)
def post_accept_follow_request(
    request_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Accept an incoming follow request (target-only)."""
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            result = accept_follow_request(
                db,
                request_public_id=request_id,
                target_public_id=_caller_profile_public_id(db, current_user.id),
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except FollowRequestNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {
            "request_id": str(result.request_id),
            "status": result.status,
        }
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/follow-requests/{request_id}/decline
# ---------------------------------------------------------------------------


@router.post(
    "/follow-requests/{request_id}/decline",
    status_code=status.HTTP_200_OK,
)
def post_decline_follow_request(
    request_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: dict[str, object],
) -> dict[str, object]:
    """Decline an incoming follow request (target-only)."""
    idempotency_key = payload.get("idempotency_key")
    if not isinstance(idempotency_key, str) or not idempotency_key:
        raise HTTPException(status_code=400, detail="idempotency_key required")

    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            decline_follow_request(
                db,
                request_public_id=request_id,
                target_public_id=_caller_profile_public_id(db, current_user.id),
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except FollowRequestNotFound as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"status": "declined"}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/follow   (unfollow OR cancel)
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/follow",
    status_code=status.HTTP_200_OK,
)
def delete_follow(
    public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Unfollow a profile OR cancel a pending outgoing request.

    The function dispatches by the §3 three-branch contract: active
    edge → ``"unfollowed"``; pending request → ``"cancelled"``;
    otherwise → ``"noop"``. The response carries the chosen branch
    so the Flutter controller can decide whether the optimistic UI
    needs to roll back.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            outcome = unfollow(
                db,
                follower_public_id=_caller_profile_public_id(db, current_user.id),
                target_public_id=public_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"outcome": outcome}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/profiles/{public_id}/followers/{follower_id}
# ---------------------------------------------------------------------------


@router.delete(
    "/profiles/{public_id}/followers/{follower_id}",
    status_code=status.HTTP_200_OK,
)
def delete_follower(
    public_id: uuid.UUID,
    follower_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> dict[str, object]:
    """Remove a follower — the owner expels an unwanted follower.

    Only the OWNER may call this on their own profile id. The
    ownership check is at the application layer (the JWT-resolved
    profile MUST match the path ``{public_id}``).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            caller_public_id = _caller_profile_public_id(db, current_user.id)
            if caller_public_id != public_id:
                # 403 — the caller is not the owner. The path is
                # the resource; the JWT is the proof. A mismatch
                # is an authorization failure, not a missing row.
                raise HTTPException(
                    status_code=403,
                    detail="only the profile owner may remove followers",
                )
            remove_follower(
                db,
                owner_public_id=public_id,
                follower_public_id=follower_id,
                idempotency_key=idempotency_key,
            )
            _commit_via(request, db)
        except ValueError as exc:
            db.rollback()
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return {"status": "removed"}
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/profiles/{public_id}/followers
# GET /community/profiles/{public_id}/following
# ---------------------------------------------------------------------------


_FOLLOW_LIST_DEFAULT_LIMIT = 50
_FOLLOW_LIST_MAX_LIMIT = 200


@router.get(
    "/profiles/{public_id}/followers",
    status_code=status.HTTP_200_OK,
)
def get_followers(
    public_id: uuid.UUID,
    request: Request,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_FOLLOW_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_FOLLOW_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of followers."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        page = list_followers(
            db, profile_public_id=public_id, cursor=cursor, limit=limit
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
    "/profiles/{public_id}/following",
    status_code=status.HTTP_200_OK,
)
def get_following(
    public_id: uuid.UUID,
    request: Request,
    cursor: str | None = Query(default=None),
    limit: int = Query(
        default=_FOLLOW_LIST_DEFAULT_LIMIT,
        ge=1,
        le=_FOLLOW_LIST_MAX_LIMIT,
    ),
) -> dict[str, object]:
    """Return one cursor-paginated page of profiles the user follows."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        page = list_following(
            db, profile_public_id=public_id, cursor=cursor, limit=limit
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Resolve the caller's community profile public_id from their
    ``users.id`` (the JWT subject).

    Raises 404 when the user has no Community profile — the
    community onboarding flow (Kör 6, ADR 0400) owns this; the
    follow endpoints assume a profile exists.
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
        # SQLite returns CHAR(32) UUID columns as plain strings
        # through raw text() queries. Wrap the hex form as a UUID
        # so the rest of the service layer sees the type it expects.
        return uuid.UUID(hex=raw)
    return raw


__all__ = [
    "delete_follow",
    "delete_follower",
    "get_followers",
    "get_following",
    "post_accept_follow_request",
    "post_decline_follow_request",
    "post_follow",
    "router",
]
