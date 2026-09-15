"""Community clubs router — the HTTP surface over
``services/club_service.py`` (E09-R24, ADR 0420 — the service landed
without a router; this module is the wire the Flutter
``CommunityClubRepository`` contract and the three club screens need).

Prefix ``/community/clubs``. Every route requires a JWT (``CurrentUser``)
and a community profile (a caller without one gets 404 — the Kör 7–22
convention). Write routes are registration-gated on
``community_writes_enabled`` by ``build_community_router`` (the posts /
social-graph ``_reads_only`` pattern), the whole router on
``community_clubs_enabled``.

Read side:

* ``GET  /community/clubs``                       — cursor page of the
  clubs visible to the caller (``private`` only when a member;
  ``discoverable`` / ``public`` for everyone; owner-block filtered).
  Query: ``cursor``, ``limit`` (``[1, 100]``, default 20),
  ``visibility``.
* ``GET  /community/clubs/{club_public_id}``      — one club (uniform
  404 for a private club the caller is not a member of).
* ``GET  /community/clubs/{club_public_id}/members`` — cursor page of
  the roster (block-filtered), oldest member first.
* ``GET  /community/clubs/{club_public_id}/join-requests`` — pending
  private-club join requests (moderator+ only).

Write side (the Flutter interface's verbs + the member-management
actions the service already models):

* ``POST   /community/clubs``                                  — create (201; caller = owner)
* ``PATCH  /community/clubs/{id}``                             — update description / visibility (owner)
* ``POST   /community/clubs/{id}/join``                        — join (public/discoverable) or
  request to join (private → pending request)
* ``POST   /community/clubs/{id}/leave``                       — leave (lone owner → 409)
* ``DELETE /community/clubs/{id}/members/{profile_public_id}`` — remove a member (moderator+)
* ``POST   /community/clubs/{id}/members/{profile_public_id}/promote`` — member → moderator
* ``POST   /community/clubs/{id}/members/{profile_public_id}/demote``  — moderator → member (owner)
* ``POST   /community/clubs/{id}/transfer-ownership``          — owner → member, target → owner
* ``POST   /community/clubs/{id}/invites``                     — invite a profile (moderator+, 201)
* ``DELETE /community/clubs/invites/{invite_public_id}``       — cancel an invite
* ``POST   /community/clubs/{id}/join-requests/{invite_public_id}/accept`` / ``.../decline``

Error taxonomy (service exception → status), the Kör 21 mapping:
``ClubNotFound`` / ``ClubMemberNotFound`` / ``ClubInviteNotFound`` → 404;
``ClubPermissionDenied`` / ``BlockedClubRelationship`` → 403;
``ClubMembershipLimitExceeded`` / ``InvalidClubTransition`` /
``OwnerMustTransferFirst`` / ``SelfRoleMutationNotAllowed`` /
``ClubIdempotencyCollision`` → 409; ``ClubInviteLimitExceeded`` → 429;
``ValueError`` (service-level input rejection) → 400. Club creation is
additionally rate-limited per caller (process-local ``RateLimiter``, the
``routers/search.py`` primitive; ``reset_rate_limiters`` is the test seam).

Wire shapes live in ``schemas/club.py`` — snake_case keys, public UUIDs
only, ``{"items": [...], "next_cursor": ...}`` page envelopes.
"""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...database import Base
from ...deps import CurrentUser
from ...ratelimit import RateLimiter
from ..models import handle_history  # noqa: F401  (registers handle_display)
from ..models.club import (
    CommunityClub,
    CommunityClubInvite,
    CommunityClubMember,
)
from ..models.profile import CommunityProfile
from ..policies.club_permissions import ClubPermissionDenied
from ..schemas.club import (
    CLUB_PAGE_SIZE_DEFAULT,
    CLUB_PAGE_SIZE_MAX,
    ClubActionRequest,
    ClubInviteOut,
    ClubInvitePage,
    ClubInviteRequest,
    ClubLeaveOut,
    ClubMemberOut,
    ClubMemberPage,
    ClubMemberRemovedOut,
    ClubOut,
    ClubPage,
    CreateClubRequest,
    TransferOwnershipRequest,
    UpdateClubRequest,
)
from ..services.club_service import (
    BlockedClubRelationship,
    ClubIdempotencyCollision,
    ClubInviteLimitExceeded,
    ClubInviteNotFound,
    ClubMemberNotFound,
    ClubMembershipLimitExceeded,
    ClubMembershipView,
    ClubNotFound,
    InvalidClubTransition,
    OwnerMustTransferFirst,
    SelfRoleMutationNotAllowed,
    accept_join_request,
    cancel_invite,
    create_club,
    decline_join_request,
    demote_to_member,
    get_club,
    invite,
    leave_club,
    list_club_members_page,
    list_clubs_page,
    list_pending_join_requests,
    promote_to_moderator,
    remove_member,
    request_join,
    transfer_ownership,
    update_club,
)

router = APIRouter(prefix="/community/clubs", tags=["community-clubs"])

_profiles_table = Base.metadata.tables["community_profiles"]

# ---------------------------------------------------------------------------
# Rate limiter — club creation, per caller (users.id). Process-local,
# same primitive + reset seam as ``routers/search.py``.
# ---------------------------------------------------------------------------

_CREATE_MAX = 10
_CREATE_WINDOW = 60.0
_create_limiter = RateLimiter(max_attempts=_CREATE_MAX, window_seconds=_CREATE_WINDOW)


def reset_rate_limiters() -> None:
    """Clear the club-create rate limiter — exposed for the test fixture."""
    _create_limiter.reset()


# ---------------------------------------------------------------------------
# Session / commit seams — the Kör 7–22 router pattern.
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
    def __call__(self, db: Session) -> None: ...


def _default_commit(db: Session) -> None:
    db.commit()


def _commit_via(request: Request, db: Session) -> None:
    fn: _SupportsCommits = getattr(request.app.state, "clubs_commit", _default_commit)
    fn(db)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


# ---------------------------------------------------------------------------
# Identity helpers.
# ---------------------------------------------------------------------------


def _caller_profile_id(db: Session, user_id: int) -> int:
    """``users.id`` (JWT subject) → ``community_profiles.id`` or 404."""
    row = db.execute(
        select(CommunityProfile.id).where(CommunityProfile.user_id == user_id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="caller has no community profile")
    return int(row[0])


def _profile_public_id(db: Session, internal_id: int) -> uuid.UUID:
    row = db.execute(
        select(CommunityProfile.public_id).where(CommunityProfile.id == internal_id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="profile not found")
    return row[0]


def _profile_internal_id(db: Session, public_id: uuid.UUID) -> int | None:
    row = db.execute(
        select(CommunityProfile.id).where(CommunityProfile.public_id == public_id)
    ).first()
    return None if row is None else int(row[0])


def _club_public_id(db: Session, club_internal_id: int) -> uuid.UUID:
    row = db.execute(
        select(CommunityClub.public_id).where(CommunityClub.id == club_internal_id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="club not found")
    return row[0]


# ---------------------------------------------------------------------------
# Error translation — one chokepoint so every endpoint maps the service
# taxonomy identically.
# ---------------------------------------------------------------------------


def _http_for(exc: Exception) -> HTTPException:
    if isinstance(exc, (ClubNotFound, ClubMemberNotFound, ClubInviteNotFound)):
        return HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, (ClubPermissionDenied, BlockedClubRelationship)):
        return HTTPException(status_code=403, detail=str(exc))
    if isinstance(exc, ClubInviteLimitExceeded):
        return HTTPException(status_code=429, detail=str(exc))
    if isinstance(exc, ClubMembershipLimitExceeded):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "club_roster_full", "member_count": exc.member_count},
        )
    if isinstance(exc, InvalidClubTransition):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "invalid_club_transition", "message": str(exc)},
        )
    if isinstance(exc, OwnerMustTransferFirst):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "owner_must_transfer_first", "message": str(exc)},
        )
    if isinstance(exc, SelfRoleMutationNotAllowed):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "self_role_mutation", "message": str(exc)},
        )
    if isinstance(exc, ClubIdempotencyCollision):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "idempotency_collision", "message": str(exc)},
        )
    if isinstance(exc, ValueError):
        return HTTPException(status_code=400, detail=str(exc))
    raise exc


_SERVICE_ERRORS = (
    ClubNotFound,
    ClubMemberNotFound,
    ClubInviteNotFound,
    ClubPermissionDenied,
    BlockedClubRelationship,
    ClubInviteLimitExceeded,
    ClubMembershipLimitExceeded,
    InvalidClubTransition,
    OwnerMustTransferFirst,
    SelfRoleMutationNotAllowed,
    ClubIdempotencyCollision,
    ValueError,
)


# ---------------------------------------------------------------------------
# Cursors — base64 JSON (the Kör 23 leaderboard pattern). A malformed
# token restarts the walk from the top instead of 500-ing.
# ---------------------------------------------------------------------------


def _encode_cursor(payload: dict) -> str:
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> dict | None:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def _decode_club_cursor(cursor: str | None) -> tuple[datetime, int] | None:
    if cursor is None:
        return None
    payload = _decode_cursor(cursor)
    if payload is None:
        return None
    try:
        return datetime.fromisoformat(payload["created_at"]), int(payload["id"])
    except (KeyError, TypeError, ValueError):
        return None


def _decode_member_cursor(cursor: str | None) -> tuple[datetime, uuid.UUID] | None:
    """The member cursor carries ``(joined_at, member public_id)`` —
    the service resolves the internal row id, so it never rides the
    wire."""
    if cursor is None:
        return None
    payload = _decode_cursor(cursor)
    if payload is None:
        return None
    try:
        joined_at = datetime.fromisoformat(payload["joined_at"])
        member_public_id = uuid.UUID(str(payload["public_id"]))
    except (KeyError, TypeError, ValueError):
        return None
    return joined_at, member_public_id


# ---------------------------------------------------------------------------
# Wire mappers.
# ---------------------------------------------------------------------------


def _club_to_out(
    db: Session, club: CommunityClub, *, viewer_profile_id: int
) -> ClubOut:
    member_count = int(
        db.execute(
            select(func.count(CommunityClubMember.id)).where(
                CommunityClubMember.club_id == club.id
            )
        ).scalar_one()
        or 0
    )
    my_member = db.execute(
        select(CommunityClubMember.role).where(
            CommunityClubMember.club_id == club.id,
            CommunityClubMember.profile_id == viewer_profile_id,
        )
    ).first()
    pending = None
    if my_member is None:
        pending = db.execute(
            select(CommunityClubInvite.id).where(
                CommunityClubInvite.club_id == club.id,
                CommunityClubInvite.inviter_profile_id == viewer_profile_id,
                CommunityClubInvite.invitee_profile_id == viewer_profile_id,
                CommunityClubInvite.status == "pending",
            )
        ).first()
    updated_at = _as_utc(club.updated_at)
    return ClubOut(
        public_id=club.public_id,
        name=club.name,
        description=club.description,
        visibility=club.visibility,
        tags=[],
        owner_public_id=_profile_public_id(db, club.owner_profile_id),
        member_count=max(1, member_count),
        my_role=None if my_member is None else my_member[0],
        join_request_pending=pending is not None,
        created_at=_as_utc(club.created_at),
        updated_at=updated_at,
        resource_version=updated_at,
    )


def _display_fields(
    db: Session, profile_public_ids: list[uuid.UUID]
) -> dict[uuid.UUID, tuple[str | None, str | None]]:
    if not profile_public_ids:
        return {}
    columns = [CommunityProfile.public_id, CommunityProfile.display_name]
    has_handle = "handle_display" in _profiles_table.c
    if has_handle:
        columns.append(_profiles_table.c.handle_display)
    rows = db.execute(
        select(*columns).where(CommunityProfile.public_id.in_(profile_public_ids))
    ).all()
    out: dict[uuid.UUID, tuple[str | None, str | None]] = {}
    for row in rows:
        handle = row[2] if has_handle else None
        out[row[0]] = (row[1], handle)
    return out


def _members_to_out(
    db: Session, views: list[ClubMembershipView]
) -> list[ClubMemberOut]:
    display = _display_fields(db, [v.profile_public_id for v in views])
    items: list[ClubMemberOut] = []
    for view in views:
        display_name, handle = display.get(view.profile_public_id, (None, None))
        items.append(
            ClubMemberOut(
                public_id=view.public_id,
                club_public_id=view.club_public_id,
                profile_public_id=view.profile_public_id,
                display_name=display_name,
                handle=handle,
                role=view.role,
                joined_at=_as_utc(view.joined_at),
            )
        )
    return items


def _member_row_to_out(db: Session, member: CommunityClubMember) -> ClubMemberOut:
    profile_public_id = _profile_public_id(db, member.profile_id)
    display_name, handle = _display_fields(db, [profile_public_id]).get(
        profile_public_id, (None, None)
    )
    return ClubMemberOut(
        public_id=member.public_id,
        club_public_id=_club_public_id(db, member.club_id),
        profile_public_id=profile_public_id,
        display_name=display_name,
        handle=handle,
        role=member.role,
        joined_at=_as_utc(member.joined_at),
    )


def _invite_to_out(db: Session, row: CommunityClubInvite) -> ClubInviteOut:
    return ClubInviteOut(
        public_id=row.public_id,
        club_public_id=_club_public_id(db, row.club_id),
        inviter_public_id=_profile_public_id(db, row.inviter_profile_id),
        invitee_public_id=_profile_public_id(db, row.invitee_profile_id),
        status=row.status,
        expires_at=_as_utc(row.expires_at),
        created_at=_as_utc(row.created_at),
        updated_at=_as_utc(row.updated_at),
        responded_at=None if row.responded_at is None else _as_utc(row.responded_at),
    )


# ---------------------------------------------------------------------------
# GET /community/clubs
# ---------------------------------------------------------------------------


@router.get("", status_code=status.HTTP_200_OK)
def get_clubs(
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    limit: int = Query(default=CLUB_PAGE_SIZE_DEFAULT, ge=1, le=CLUB_PAGE_SIZE_MAX),
    visibility: str | None = Query(default=None, max_length=16),
) -> ClubPage:
    """Cursor page of the clubs visible to the caller, newest first.

    Response: ``{"items": [ClubOut...], "next_cursor": "..."|null}``.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        viewer_profile_id = _caller_profile_id(db, current_user.id)
        page = list_clubs_page(
            db,
            viewer_profile_id=viewer_profile_id,
            visibility=visibility,
            limit=limit,
            before=_decode_club_cursor(cursor),
        )
        next_cursor = None
        if page.next_before is not None:
            created_at, row_id = page.next_before
            next_cursor = _encode_cursor(
                {"created_at": _as_utc(created_at).isoformat(), "id": row_id}
            )
        return ClubPage(
            items=[
                _club_to_out(db, club, viewer_profile_id=viewer_profile_id)
                for club in page.items
            ],
            next_cursor=next_cursor,
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/clubs
# ---------------------------------------------------------------------------


@router.post("", status_code=status.HTTP_201_CREATED)
def post_club(
    request: Request,
    current_user: CurrentUser,
    payload: CreateClubRequest,
) -> ClubOut:
    """Create a club — the caller becomes ``owner`` (server-side
    identity). Idempotent on ``idempotency_key`` (a replay returns the
    existing club). Rate-limited per caller (10/min → 429)."""
    if not _create_limiter.allow(str(current_user.id)):
        raise HTTPException(status_code=429, detail="rate limited")
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        owner_profile_id = _caller_profile_id(db, current_user.id)
        try:
            club = create_club(
                db,
                owner_profile_id=owner_profile_id,
                name=payload.name,
                description=payload.description,
                visibility=payload.visibility,
                idempotency_key=payload.idempotency_key,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _club_to_out(db, club, viewer_profile_id=owner_profile_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET / PATCH /community/clubs/{club_public_id}
# ---------------------------------------------------------------------------


@router.get("/{club_public_id}", status_code=status.HTTP_200_OK)
def get_club_endpoint(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
) -> ClubOut:
    """One club. A private club the caller is not a member of answers
    a uniform 404 (no existence oracle)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        viewer_profile_id = _caller_profile_id(db, current_user.id)
        try:
            club = get_club(
                db, club_public_id=club_public_id, viewer_profile_id=viewer_profile_id
            )
        except _SERVICE_ERRORS as exc:
            raise _http_for(exc) from exc
        return _club_to_out(db, club, viewer_profile_id=viewer_profile_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.patch("/{club_public_id}", status_code=status.HTTP_200_OK)
def patch_club(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: UpdateClubRequest,
) -> ClubOut:
    """Update ``description`` / ``visibility`` (owner-only → 403
    otherwise). ``resource_version`` (the ``updated_at`` echoed by a
    prior read) is an optimistic-concurrency check: a stale token
    answers 409."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            current = get_club(
                db, club_public_id=club_public_id, viewer_profile_id=actor_profile_id
            )
            if payload.resource_version is not None and _as_utc(
                payload.resource_version
            ) != _as_utc(current.updated_at):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "error": "stale_resource_version",
                        "resource_version": _as_utc(current.updated_at).isoformat(),
                    },
                )
            club = update_club(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                description=payload.description,
                visibility=payload.visibility,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _club_to_out(db, club, viewer_profile_id=actor_profile_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# POST /community/clubs/{club_public_id}/join  |  /leave
# ---------------------------------------------------------------------------


@router.post("/{club_public_id}/join", status_code=status.HTTP_200_OK)
def post_join_club(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubOut:
    """Join a ``public`` / ``discoverable`` club immediately, or file a
    pending join request on a ``private`` one. The response is the club
    as the caller now sees it (``my_role`` set, or
    ``join_request_pending: true``). Idempotent: a repeat returns the
    existing membership / request."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            request_join(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                idempotency_key=payload.idempotency_key if payload else None,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        club = db.execute(
            select(CommunityClub).where(CommunityClub.public_id == club_public_id)
        ).scalar_one()
        return _club_to_out(db, club, viewer_profile_id=actor_profile_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post("/{club_public_id}/leave", status_code=status.HTTP_200_OK)
def post_leave_club(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubLeaveOut:
    """Leave the club. The lone owner must transfer ownership first
    (409 ``owner_must_transfer_first``); a non-member answers 404."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            leave_club(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return ClubLeaveOut(club_public_id=club_public_id, left=True)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# GET /community/clubs/{club_public_id}/members
# ---------------------------------------------------------------------------


@router.get("/{club_public_id}/members", status_code=status.HTTP_200_OK)
def get_club_members(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    cursor: str | None = Query(default=None, max_length=512),
    limit: int = Query(default=CLUB_PAGE_SIZE_DEFAULT, ge=1, le=CLUB_PAGE_SIZE_MAX),
) -> ClubMemberPage:
    """Cursor page of the roster, oldest member first. Members in a
    block relationship with the caller are dropped. Same visibility
    rule as the club itself (private → members only)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        viewer_profile_id = _caller_profile_id(db, current_user.id)
        try:
            page = list_club_members_page(
                db,
                club_public_id=club_public_id,
                viewer_profile_id=viewer_profile_id,
                limit=limit,
                after=_decode_member_cursor(cursor),
            )
        except _SERVICE_ERRORS as exc:
            raise _http_for(exc) from exc
        next_cursor = None
        if page.next_after is not None:
            joined_at, member_public_id = page.next_after
            next_cursor = _encode_cursor(
                {
                    "joined_at": _as_utc(joined_at).isoformat(),
                    "public_id": str(member_public_id),
                }
            )
        return ClubMemberPage(
            items=_members_to_out(db, page.items), next_cursor=next_cursor
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Member management — DELETE / promote / demote / transfer.
# ---------------------------------------------------------------------------


@router.delete(
    "/{club_public_id}/members/{profile_public_id}", status_code=status.HTTP_200_OK
)
def delete_club_member(
    club_public_id: uuid.UUID,
    profile_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str | None = Query(default=None, max_length=128),
) -> ClubMemberRemovedOut:
    """Remove a member (owner / moderator; the owner cannot be removed
    — 409 ``owner_must_transfer_first``). The idempotency key rides the
    query string on DELETE (the Kör 21 transport rule)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            remove_member(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                target_profile_public_id=profile_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return ClubMemberRemovedOut(
            club_public_id=club_public_id, profile_public_id=profile_public_id
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post(
    "/{club_public_id}/members/{profile_public_id}/promote",
    status_code=status.HTTP_200_OK,
)
def post_promote_member(
    club_public_id: uuid.UUID,
    profile_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubMemberOut:
    """Promote a ``member`` to ``moderator`` (owner / moderator)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            member = promote_to_moderator(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                target_profile_public_id=profile_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _member_row_to_out(db, member)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post(
    "/{club_public_id}/members/{profile_public_id}/demote",
    status_code=status.HTTP_200_OK,
)
def post_demote_member(
    club_public_id: uuid.UUID,
    profile_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubMemberOut:
    """Demote a ``moderator`` to ``member`` (owner-only)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            member = demote_to_member(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                target_profile_public_id=profile_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _member_row_to_out(db, member)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post("/{club_public_id}/transfer-ownership", status_code=status.HTTP_200_OK)
def post_transfer_ownership(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: TransferOwnershipRequest,
) -> ClubOut:
    """Transfer ownership to an existing member (owner-only). The old
    owner becomes a plain ``member``."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        new_owner_id = _profile_internal_id(db, payload.new_owner_public_id)
        if new_owner_id is None:
            raise HTTPException(status_code=404, detail="new owner profile not found")
        try:
            club = transfer_ownership(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                new_owner_profile_id=new_owner_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _club_to_out(db, club, viewer_profile_id=actor_profile_id)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Invites — POST /{id}/invites, DELETE /invites/{invite_public_id}
# ---------------------------------------------------------------------------


@router.post("/{club_public_id}/invites", status_code=status.HTTP_201_CREATED)
def post_club_invite(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubInviteRequest,
) -> ClubInviteOut:
    """Invite a profile (owner / moderator). Blocked pairs → 403; the
    per-club pending-invite budget → 429. Idempotent on
    ``idempotency_key``."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            row = invite(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                invitee_profile_public_id=payload.invitee_public_id,
                idempotency_key=payload.idempotency_key,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _invite_to_out(db, row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.delete("/invites/{invite_public_id}", status_code=status.HTTP_200_OK)
def delete_club_invite(
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    idempotency_key: str | None = Query(default=None, max_length=128),
) -> ClubInviteOut:
    """Cancel a pending invite (the inviter or any moderator+)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            row = cancel_invite(
                db,
                actor_profile_id=actor_profile_id,
                invite_public_id=invite_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _invite_to_out(db, row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# ---------------------------------------------------------------------------
# Join requests (private clubs) — list / accept / decline.
# ---------------------------------------------------------------------------


@router.get("/{club_public_id}/join-requests", status_code=status.HTTP_200_OK)
def get_join_requests(
    club_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    limit: int = Query(default=CLUB_PAGE_SIZE_DEFAULT, ge=1, le=CLUB_PAGE_SIZE_MAX),
) -> ClubInvitePage:
    """Pending join requests on a private club (owner / moderator)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            rows = list_pending_join_requests(
                db,
                actor_profile_id=actor_profile_id,
                club_public_id=club_public_id,
                limit=limit,
            )
        except _SERVICE_ERRORS as exc:
            raise _http_for(exc) from exc
        return ClubInvitePage(
            items=[_invite_to_out(db, row) for row in rows], next_cursor=None
        )
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post(
    "/{club_public_id}/join-requests/{invite_public_id}/accept",
    status_code=status.HTTP_200_OK,
)
def post_accept_join_request(
    club_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubMemberOut:
    """Accept a pending join request (owner / moderator) — creates the
    membership row. A non-pending request → 409."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            _assert_invite_belongs_to_club(db, invite_public_id, club_public_id)
            member = accept_join_request(
                db,
                actor_profile_id=actor_profile_id,
                invite_public_id=invite_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _member_row_to_out(db, member)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


@router.post(
    "/{club_public_id}/join-requests/{invite_public_id}/decline",
    status_code=status.HTTP_200_OK,
)
def post_decline_join_request(
    club_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
    request: Request,
    current_user: CurrentUser,
    payload: ClubActionRequest | None = None,
) -> ClubInviteOut:
    """Decline a pending join request (owner / moderator)."""
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        actor_profile_id = _caller_profile_id(db, current_user.id)
        try:
            _assert_invite_belongs_to_club(db, invite_public_id, club_public_id)
            row = decline_join_request(
                db,
                actor_profile_id=actor_profile_id,
                invite_public_id=invite_public_id,
                now=_now(),
            )
        except _SERVICE_ERRORS as exc:
            db.rollback()
            raise _http_for(exc) from exc
        _commit_via(request, db)
        return _invite_to_out(db, row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


def _assert_invite_belongs_to_club(
    db: Session, invite_public_id: uuid.UUID, club_public_id: uuid.UUID
) -> None:
    """The URL's ``club_public_id`` and the invite's club must agree —
    otherwise a uniform 404 (no cross-club oracle)."""
    row = db.execute(
        select(CommunityClub.public_id)
        .join(CommunityClubInvite, CommunityClubInvite.club_id == CommunityClub.id)
        .where(CommunityClubInvite.public_id == invite_public_id)
    ).first()
    if row is None or row[0] != club_public_id:
        raise ClubInviteNotFound("invite not found")


__all__ = [
    "reset_rate_limiters",
    "router",
]
