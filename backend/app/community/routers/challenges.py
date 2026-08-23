"""Community challenge invite router — E09-R21, ADR 0415.

The HTTP surface for the challenge invite lifecycle:

* ``POST   /community/challenges/{challenge_public_id}/invites`` —
  create (or recycle) an invite. Server-side inviter (the JWT
  subject). Idempotent on ``idempotency_key`` (§5.3, D4).
  Block-side gate (A3, D3) and rate-limit gate (A4 / §5.3)
  run BEFORE the INSERT.
* ``POST   /community/challenges/invites/{invite_public_id}/accept`` —
  accept a pending invite (invitee-only). The conditional
  UPDATE guards the state graph (D5).
* ``POST   /community/challenges/invites/{invite_public_id}/decline`` —
  decline a pending invite (invitee-only). Same conditional
  UPDATE shape.
* ``DELETE /community/challenges/invites/{invite_public_id}`` —
  cancel an outgoing invite (inviter-only). Same conditional
  UPDATE shape — the D5 race-test cell.

There is NO "challenge definition creation" endpoint in this
round (the §0.0 D6 scope-shrink / ADR 0415 §D6): the router
only exposes the invite-lifecycle endpoints. The
``community_challenges`` rows are seeded by the test fixtures
or by a future round's admin surface; the service is still
the single chokepoint for all writes.

All authenticated endpoints take ``idempotency_key`` either in
the JSON body (POST endpoints) or as a query parameter
(DELETE endpoints — the Kör 7 ``api_client.dart``'s ``delete()``
does not carry a JSON body, ADR 0401 §1 / §3). The body-side
``inviter_id`` / ``invitee_id`` / ``invite_id`` fields are NOT
carried by the Pydantic schemas (``extra='forbid'`` rejects any
smuggled value).

The router is mounted by the test fixtures directly into a
self-contained ``FastAPI()`` — the production
``build_community_router`` factory stays untouched (the Kör 7–20
pattern; the §3 tilos-zóna discipline).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from ...deps import CurrentUser
from ..services.challenge_invite_service import (
    BlockedChallengeRelationship,
    ChallengeInviteNotFound,
    ChallengeInviteRateLimited,
    ChallengeNotFound,
    InvalidChallengeInviteTransition,
    accept_invite,
    cancel_invite,
    create_invite,
    decline_invite,
)

router = APIRouter(prefix="/community/challenges", tags=["community-challenges"])


# ---------------------------------------------------------------------------
# Session / commit seams — same pattern as the Kör 7–20 routers.
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
    fn = getattr(request.app.state, "challenges_commit", _default_commit)
    fn(db)


def _resolve_caller_profile_public_id(db: Session, user_id: int) -> uuid.UUID:
    """Resolve the caller's community profile public_id from their
    ``users.id`` (the JWT subject).

    Mirrors the Kör 7 ``_caller_profile_public_id`` pattern. The
    router endpoints that take a target profile id (the create
    invite path) read the caller's public_id from this helper;
    the endpoints that take an invite id (accept / decline /
    cancel) read the invitee's / inviter's identity off the
    invite row.
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


def _resolve_profile_public_id_by_internal_id(
    db: Session, internal_id: int
) -> uuid.UUID:
    """Translate an internal ``community_profiles.id`` (PK) to its
    public_id (the wire surface)."""
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_profiles WHERE id = :pid"),
        {"pid": internal_id},
    ).first()
    if row is None:
        raise ValueError("profile not found")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


# ---------------------------------------------------------------------------
# Pydantic schemas — ``extra='forbid'`` rejects any smuggled
# ``inviter_id`` / ``invitee_id`` / ``invite_id`` field (§5.1).
# ---------------------------------------------------------------------------


class CreateChallengeInviteRequest(BaseModel):
    """Body shape for ``POST /community/challenges/{id}/invites``.

    Only the ``invitee_public_id`` and the ``idempotency_key``
    travel on the wire — the ``inviter_public_id`` is the
    JWT subject (server-resolved), never a body field. The
    optional ``expires_in_seconds`` lets the client cap the
    invite window; the default is 14 days (the same horizon
    the Kör 7 follow-request cooldown uses).
    """

    model_config = ConfigDict(extra="forbid")

    invitee_public_id: uuid.UUID
    idempotency_key: str | None = None
    expires_in_seconds: int | None = None


class ChallengeInviteActionRequest(BaseModel):
    """Body shape for ``POST .../accept`` and ``POST .../decline``.

    The endpoints are idempotent on the invite's CURRENT
    state — a retry of an already-accepted invite returns
    200 (the row is already in the target state). The
    ``idempotency_key`` is optional; the natural-key
    identity (the ``invite_public_id`` in the URL) is the
    canonical idempotency surface for these transitions.
    """

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = None


class ChallengeInviteOut(BaseModel):
    """Wire shape for a single invite row.

    The internal ``id`` is NEVER serialised (the §6.1
    leak-guard). The ``responded_at`` is NULL on a fresh
    ``draft`` / ``sent`` row.
    """

    public_id: uuid.UUID
    challenge_public_id: uuid.UUID
    inviter_public_id: uuid.UUID
    invitee_public_id: uuid.UUID
    state: str
    expires_at: datetime
    created_at: datetime
    updated_at: datetime
    responded_at: datetime | None = None


def _invite_to_out_from_session(
    db: Session, invite
) -> ChallengeInviteOut:
    """Map a ``CommunityChallengeInvite`` ORM row + session to its
    wire shape, resolving the FK public_ids through the
    request-scoped session.

    Mirrors ``_row_to_out`` in ``routers/posts.py`` — every
    public_id on the wire is resolved through a session
    query, never carried on the ORM relationship.
    """
    challenge_pub = _resolve_challenge_public_id_from_session(db, invite)
    inviter_pub = _resolve_profile_public_id_by_internal_id(db, invite.inviter_profile_id)
    invitee_pub = _resolve_profile_public_id_by_internal_id(db, invite.invitee_profile_id)
    return ChallengeInviteOut(
        public_id=invite.public_id,
        challenge_public_id=challenge_pub,
        inviter_public_id=inviter_pub,
        invitee_public_id=invitee_pub,
        state=invite.state,
        expires_at=invite.expires_at,
        created_at=invite.created_at,
        updated_at=invite.updated_at,
        responded_at=invite.responded_at,
    )


def _resolve_challenge_public_id_from_session(
    db: Session, invite
) -> uuid.UUID:
    """Resolve the challenge public_id from the request session."""
    from sqlalchemy import text as _sa_text

    row = db.execute(
        _sa_text("SELECT public_id FROM community_challenges WHERE id = :id"),
        {"id": invite.challenge_id},
    ).first()
    if row is None:
        raise ValueError("invite references a non-existent challenge")
    raw = row[0]
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return raw


# ---------------------------------------------------------------------------
# Default invite-window helper — the 14-day horizon matches the
# Kör 7 follow-request cooldown.
# ---------------------------------------------------------------------------

_DEFAULT_INVITE_WINDOW_DAYS = 14
_MAX_INVITE_WINDOW_DAYS = 90


def _resolve_expires_at(
    *,
    now: datetime,
    expires_in_seconds: int | None,
) -> datetime:
    """Translate the body-side ``expires_in_seconds`` to an
    absolute UTC timestamp.

    The default window is 14 days (the Kör 7 follow-request
    cooldown); the maximum is 90 days — a longer window is
    rejected at the router with 422.
    """
    seconds = (
        expires_in_seconds
        if expires_in_seconds is not None
        else _DEFAULT_INVITE_WINDOW_DAYS * 24 * 60 * 60
    )
    if seconds <= 0:
        raise HTTPException(
            status_code=422,
            detail="expires_in_seconds must be positive",
        )
    if seconds > _MAX_INVITE_WINDOW_DAYS * 24 * 60 * 60:
        raise HTTPException(
            status_code=422,
            detail=(
                f"expires_in_seconds exceeds the {_MAX_INVITE_WINDOW_DAYS}-day "
                "maximum invite window"
            ),
        )
    return now + timedelta(seconds=seconds)


def _now() -> datetime:
    """Server-time helper — mirrors ``routers/posts.datetime_now``.

    Kept as a function (not a module-level constant) so a test
    seam can override ``app.state.clock`` the same way
    ``routers/privacy.py`` does.
    """
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# POST /community/challenges/{challenge_public_id}/invites
# ---------------------------------------------------------------------------


@router.post(
    "/{challenge_public_id}/invites",
    status_code=status.HTTP_201_CREATED,
)
def post_create_invite(
    challenge_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: CreateChallengeInviteRequest,
) -> ChallengeInviteOut:
    """Create (or recycle) a challenge invite.

    The inviter is the JWT subject (D1 server-side identity);
    the invitee and the idempotency key travel on the wire.
    The block-side gate (A3, D3) and the rate-limit gate
    (A4 / §5.3) run BEFORE the INSERT.

    Body shape::

        {
          "invitee_public_id": "<uuid>",
          "idempotency_key": "<string>",
          "expires_in_seconds": <int>   // optional, default 14 days
        }

    The response carries the invite's wire shape (public_id,
    state, expires_at, …). A retry with the same
    ``idempotency_key`` returns the existing row (200) — the
    §A4 idempotency invariant.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                inviter_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            now = _now()
            try:
                expires_at = _resolve_expires_at(
                    now=now,
                    expires_in_seconds=payload.expires_in_seconds,
                )
            except HTTPException:
                db.rollback()
                raise
            try:
                invite = create_invite(
                    db,
                    inviter_public_id=inviter_public_id,
                    invitee_public_id=payload.invitee_public_id,
                    challenge_public_id=challenge_public_id,
                    expires_at=expires_at,
                    idempotency_key=payload.idempotency_key,
                    now=now,
                )
            except BlockedChallengeRelationship as exc:
                db.rollback()
                raise HTTPException(status_code=403, detail=str(exc)) from exc
            except ChallengeInviteRateLimited as exc:
                db.rollback()
                raise HTTPException(status_code=429, detail=str(exc)) from exc
            except ChallengeNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except ValueError as exc:
                db.rollback()
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/challenges/invites/{invite_public_id}/accept
# ---------------------------------------------------------------------------


@router.post(
    "/invites/{invite_public_id}/accept",
    status_code=status.HTTP_200_OK,
)
def post_accept_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ChallengeInviteActionRequest | None = None,
) -> ChallengeInviteOut:
    """Accept a pending invite (invitee-only).

    Body shape is optional (the natural-key identity is the
    invite_public_id in the URL). The conditional UPDATE
    guards the state graph (D5) — a terminal-state invite
    raises :class:`InvalidChallengeInviteTransition` and the
    router returns 409.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                invitee_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = accept_invite(
                    db,
                    invitee_public_id=invitee_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except BlockedChallengeRelationship as exc:
                db.rollback()
                raise HTTPException(status_code=403, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/challenges/invites/{invite_public_id}/decline
# ---------------------------------------------------------------------------


@router.post(
    "/invites/{invite_public_id}/decline",
    status_code=status.HTTP_200_OK,
)
def post_decline_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ChallengeInviteActionRequest | None = None,
) -> ChallengeInviteOut:
    """Decline a pending invite (invitee-only)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                invitee_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = decline_invite(
                    db,
                    invitee_public_id=invitee_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# DELETE /community/challenges/invites/{invite_public_id}   (cancel)
# ---------------------------------------------------------------------------


@router.delete(
    "/invites/{invite_public_id}",
    status_code=status.HTTP_200_OK,
)
def delete_cancel_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str = Query(..., min_length=1),
) -> ChallengeInviteOut:
    """Cancel an outgoing invite (inviter-only).

    The idempotency key rides the URL on DELETE — the
    Kör 7 ``api_client.dart`` ``delete()`` transport carries
    no JSON body (ADR 0401 §1).

    The D5 race-test cell (concurrent accept + cancel from
    two devices) lands here: the conditional UPDATE accepts
    only ``draft`` / ``sent`` source states, so when the
    accept branch wins, the cancel branch sees ``rowcount ==
    0`` and the router returns 409. The test asserts that
    exactly one branch succeeds and the other raises
    deterministically.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            try:
                inviter_public_id = _resolve_caller_profile_public_id(
                    db, current_user.id
                )
            except ValueError as exc:
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            try:
                invite = cancel_invite(
                    db,
                    inviter_public_id=inviter_public_id,
                    invite_public_id=invite_public_id,
                    now=_now(),
                )
            except ChallengeInviteNotFound as exc:
                db.rollback()
                raise HTTPException(status_code=404, detail=str(exc)) from exc
            except InvalidChallengeInviteTransition as exc:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "invalid_invite_transition",
                        "current_state": exc.current_state,
                    },
                ) from exc
            _commit_via(request, db)
        except HTTPException:
            raise
        return _invite_to_out_from_session(db, invite)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "router",
]
