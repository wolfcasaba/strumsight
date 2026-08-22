"""Follow lifecycle service — E09-R07, ADR 0401 §3–6, §6.

The service layer for the social-graph is intentionally narrow:

* ``follow()`` — public profile ⇒ write a row to ``community_follows``;
  private profile ⇒ write a row to ``community_follow_requests`` with
  status ``requested``. Idempotent: a retry on the same pair (already
  following OR already requested) returns the existing row's id
  without raising — the §6.1 A2 race protection lives at the DB
  layer (the ``UNIQUE`` constraints); the application layer only
  translates ``IntegrityError`` → domain exception when the DB
  rejects an unexpected shape (the same ``commit_with_uniqueness_check``
  pattern from ``identity_service``).

* ``accept_follow_request()`` / ``decline_follow_request()`` — flip
  the request row to ``accepted`` / ``declined``. On accept, also
  write the matching follow edge in the same transaction. Idempotent:
  a retry on the same request id that is already in the target state
  returns success, not 409 — the §6.1 "retry must not lose the
  result" invariant.

* ``unfollow()`` — DELETE on ``community_follows`` for the active
  edge. If no active edge exists BUT a ``requested`` request row
  exists from the caller to the target, the service flips it to
  ``cancelled`` (the §3 cancel branch — "cancel" is the existing
  unfollow call, NOT a separate domain method).

* ``remove_follower()`` — DELETE on the reverse edge (a follower
  removing themselves as a follower of the owner). Does NOT
  block — the §5.3 invariant: the two are independent.

* ``list_followers()`` / ``list_following()`` — cursor-paginated
  reads, ordered ``(created_at DESC, id DESC)`` per the §7 contract.
  The opaque cursor encodes the last-seen ``(created_at, id)`` pair.

The DB layer is the enforcement; the service layer is the
orchestration + the ``IntegrityError`` → domain-exception
translation, modelled after ``identity_service.commit_with_uniqueness_check``
(ADR 0397 §5.1) but with its own, follow-specific exception type
(``FollowAlreadyExists``) so a future ``HandleAlreadyClaimed``
reuse is impossible to confuse.
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.profile import CommunityProfile
from ..models.social_graph import CommunityFollow, CommunityFollowRequest
from ..policies.access_policy import ProfileVisibility


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class FollowAlreadyExists(Exception):
    """A follow edge or request already exists for this pair — DB-level
    uniqueness hit, translated from ``IntegrityError``."""


class SelfFollowNotAllowed(Exception):
    """Self-follow / self-request — rejected at the DB layer via CHECK."""


class FollowRequestNotFound(Exception):
    """The referenced request id does not exist (or is not in the
    expected state)."""


@dataclass(frozen=True)
class FollowResult:
    """The outcome of a ``follow()`` call.

    ``request_id`` is the public_id of either the new
    ``community_follows`` row (public profile path) OR the new
    ``community_follow_requests`` row (private profile path) —
    the caller distinguishes the two cases via ``status``.
    """

    request_id: uuid.UUID
    status: str  # "following" (active follow) | "requested" (pending request)


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _is_private(target: CommunityProfile) -> bool:
    """A profile is private if its privacy row's visibility is PRIVATE.

    Falls back to ``True`` when the privacy row is missing — the
    safe default (ADR 0398 §5). The Kör 4 default visibility is
    ``followers`` so a missing privacy row in production is rare
    but tests / pre-onboarding fixtures still benefit from a safe
    fallback.
    """
    settings = target.privacy_settings
    if settings is None:
        return True
    visibility = settings.visibility
    if isinstance(visibility, ProfileVisibility):
        return visibility is ProfileVisibility.PRIVATE
    return visibility == ProfileVisibility.PRIVATE.value


def _existing_follow(
    db: Session, *, follower_id: int, followed_id: int
) -> CommunityFollow | None:
    return (
        db.query(CommunityFollow)
        .filter(
            and_(
                CommunityFollow.follower_profile_id == follower_id,
                CommunityFollow.followed_profile_id == followed_id,
            )
        )
        .one_or_none()
    )


def _existing_request(
    db: Session, *, requester_id: int, target_id: int
) -> CommunityFollowRequest | None:
    return (
        db.query(CommunityFollowRequest)
        .filter(
            and_(
                CommunityFollowRequest.requester_profile_id == requester_id,
                CommunityFollowRequest.target_profile_id == target_id,
            )
        )
        .one_or_none()
    )


def follow(
    db: Session,
    *,
    follower_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> FollowResult:
    """Create (or recycle) a follow edge or a follow request.

    Public target ⇒ ``community_follows`` row (status ``"following"``).
    Private target ⇒ ``community_follow_requests`` row with status
    ``"requested"``.

    Idempotent at the state-machine level (ADR 0401 §6): if the
    pair already has an active follow OR a pending ``requested``
    request, the function returns the existing row's public id
    without raising — a network retry on the same idempotency
    key MUST NOT fail.
    """
    follower = _resolve_profile_by_public_id(db, follower_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if follower is None:
        raise ValueError("follower profile not found")
    if target is None:
        raise ValueError("target profile not found")
    if follower.id == target.id:
        raise SelfFollowNotAllowed("cannot follow yourself")

    if not _is_private(target):
        # Public target — write the follow edge if missing.
        existing = _existing_follow(
            db, follower_id=follower.id, followed_id=target.id
        )
        if existing is not None:
            return FollowResult(
                request_id=existing.public_id, status="following"
            )
        edge = CommunityFollow(
            follower_profile_id=follower.id,
            followed_profile_id=target.id,
        )
        db.add(edge)
        try:
            db.flush()
        except IntegrityError as exc:
            db.rollback()
            # A concurrent writer won the race — re-read and return.
            again = _existing_follow(
                db, follower_id=follower.id, followed_id=target.id
            )
            if again is not None:
                return FollowResult(
                    request_id=again.public_id, status="following"
                )
            raise FollowAlreadyExists(str(exc)) from exc
        return FollowResult(request_id=edge.public_id, status="following")

    # Private target — write the request row (recycle if present).
    existing_request = _existing_request(
        db, requester_id=follower.id, target_id=target.id
    )
    if existing_request is not None:
        if existing_request.status == "requested":
            return FollowResult(
                request_id=existing_request.public_id, status="requested"
            )
        # Decline / cancel / accepted-anywhere-else path — recycle
        # back to ``requested`` so the caller re-tries cleanly. The
        # unique constraint is on the pair, not on the status, so
        # an UPDATE here is the only path that lands.
        existing_request.status = "requested"
        existing_request.responded_at = None
        db.flush()
        return FollowResult(
            request_id=existing_request.public_id, status="requested"
        )

    request = CommunityFollowRequest(
        requester_profile_id=follower.id,
        target_profile_id=target.id,
        status="requested",
    )
    db.add(request)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        again = _existing_request(
            db, requester_id=follower.id, target_id=target.id
        )
        if again is not None:
            return FollowResult(
                request_id=again.public_id, status="requested"
            )
        raise FollowAlreadyExists(str(exc)) from exc
    return FollowResult(request_id=request.public_id, status="requested")


def accept_follow_request(
    db: Session,
    *,
    request_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> FollowResult:
    """Accept a follow request — flip status to ``accepted`` and
    write the matching follow edge.

    Idempotent: if the request is already ``accepted``, return
    success (the follow edge either exists or is created).
    """
    target = _resolve_profile_by_public_id(db, target_public_id)
    if target is None:
        raise ValueError("target profile not found")
    request = (
        db.query(CommunityFollowRequest)
        .filter_by(public_id=request_public_id)
        .one_or_none()
    )
    if request is None:
        raise FollowRequestNotFound("follow request not found")
    if request.target_profile_id != target.id:
        # The caller is not the request's target — refuse. The DB
        # CHECK constraint does not enforce this (only self-targeting),
        # so the service layer is the chokepoint.
        raise FollowRequestNotFound("follow request not for this profile")

    if request.status == "accepted":
        # Already accepted — write the follow edge if missing and
        # return. The DB-level UNIQUE on (follower, followed) means
        # a duplicate INSERT raises IntegrityError; the
        # post-INSERT read collapses it.
        edge = _existing_follow(
            db,
            follower_id=request.requester_profile_id,
            followed_id=request.target_profile_id,
        )
        if edge is None:
            edge = CommunityFollow(
                follower_profile_id=request.requester_profile_id,
                followed_profile_id=request.target_profile_id,
            )
            db.add(edge)
            try:
                db.flush()
            except IntegrityError:
                db.rollback()
        return FollowResult(request_id=request.public_id, status="accepted")

    if request.status != "requested":
        # Declined / cancelled — refuse. The owner must wait for the
        # caller to re-request.
        raise FollowRequestNotFound(
            f"follow request is in terminal state '{request.status}'"
        )

    request.status = "accepted"
    request.responded_at = _utcnow()
    edge = _existing_follow(
        db,
        follower_id=request.requester_profile_id,
        followed_id=request.target_profile_id,
    )
    if edge is None:
        edge = CommunityFollow(
            follower_profile_id=request.requester_profile_id,
            followed_profile_id=request.target_profile_id,
        )
        db.add(edge)
        try:
            db.flush()
        except IntegrityError:
            db.rollback()
    return FollowResult(request_id=request.public_id, status="accepted")


def decline_follow_request(
    db: Session,
    *,
    request_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> None:
    """Decline a follow request — flip status to ``declined``.

    Idempotent: a retry on an already-declined request returns
    success (no-op).
    """
    target = _resolve_profile_by_public_id(db, target_public_id)
    if target is None:
        raise ValueError("target profile not found")
    request = (
        db.query(CommunityFollowRequest)
        .filter_by(public_id=request_public_id)
        .one_or_none()
    )
    if request is None:
        raise FollowRequestNotFound("follow request not found")
    if request.target_profile_id != target.id:
        raise FollowRequestNotFound("follow request not for this profile")
    if request.status == "declined":
        return None
    if request.status == "accepted":
        # Already accepted — refusing to decline would be the
        # Kör 11 §6.1 IDOR regression. Raise so the caller knows.
        raise FollowRequestNotFound(
            "follow request is already accepted; cannot decline"
        )
    request.status = "declined"
    request.responded_at = _utcnow()
    db.flush()
    return None


def unfollow(
    db: Session,
    *,
    follower_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> str:
    """Unfollow (or cancel an outgoing pending request).

    Three branches, in order (ADR 0401 §3):

    1. Active follow edge exists → DELETE it (return ``"unfollowed"``).
    2. Pending ``requested`` row from caller to target → UPDATE
       status to ``"cancelled"`` (return ``"cancelled"``).
    3. Otherwise → idempotent no-op (return ``"noop"``).

    The HTTP response carries the returned string so the Flutter
    controller can decide whether to refresh the UI optimistically
    (the §5.2 invariant: the optimistic UI is only valid on the
    active-edge branch).
    """
    follower = _resolve_profile_by_public_id(db, follower_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if follower is None or target is None:
        # Idempotent on a missing peer — the caller was already
        # not following them (or never was).
        return "noop"

    edge = _existing_follow(
        db, follower_id=follower.id, followed_id=target.id
    )
    if edge is not None:
        db.delete(edge)
        db.flush()
        return "unfollowed"

    request = _existing_request(
        db, requester_id=follower.id, target_id=target.id
    )
    if request is not None and request.status == "requested":
        request.status = "cancelled"
        request.responded_at = _utcnow()
        db.flush()
        return "cancelled"
    return "noop"


def remove_follower(
    db: Session,
    *,
    owner_public_id: uuid.UUID,
    follower_public_id: uuid.UUID,
    idempotency_key: str,
) -> None:
    """Remove a follower — the owner expels an unwanted follower
    (SDD §10.3, brief §5.3). Does NOT block.

    Idempotent: removing a non-follower returns success.
    """
    owner = _resolve_profile_by_public_id(db, owner_public_id)
    follower = _resolve_profile_by_public_id(db, follower_public_id)
    if owner is None or follower is None:
        return None
    edge = _existing_follow(
        db, follower_id=follower.id, followed_id=owner.id
    )
    if edge is None:
        return None
    db.delete(edge)
    db.flush()
    return None


# ---------------------------------------------------------------------------
# Cursor pagination — opaque (created_at, id) pair, base64-encoded JSON.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FollowListPage:
    """A single page of follow / follower rows.

    The public ids are the opaque Community UUIDs — the controller
    translates them to domain ``PublicUserId`` values. The ``cursor``
    is opaque to the caller too; the next page request sends it back
    through the repository layer.
    """

    public_ids: tuple[uuid.UUID, ...]
    next_cursor: str | None


def _encode_cursor(created_at: datetime, row_id: int) -> str:
    payload = {"created_at": created_at.isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[datetime, int] | None:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["created_at"])
        row_id = int(payload["id"])
        return created_at, row_id
    except (ValueError, KeyError, json.JSONDecodeError):
        return None


def list_followers(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> FollowListPage:
    """Return one page of followers of ``profile_public_id``.

    Ordering is ``(created_at DESC, id DESC)`` per ADR 0401 §7.
    """
    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        return FollowListPage(public_ids=(), next_cursor=None)
    return _paginate_follows(
        db,
        target_column=CommunityFollow.follower_profile_id,
        owner_id=profile.id,
        cursor=cursor,
        limit=limit,
    )


def list_following(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> FollowListPage:
    """Return one page of profiles ``profile_public_id`` follows."""
    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        return FollowListPage(public_ids=(), next_cursor=None)
    return _paginate_follows(
        db,
        target_column=CommunityFollow.followed_profile_id,
        owner_id=profile.id,
        cursor=cursor,
        limit=limit,
    )


def _paginate_follows(
    db: Session,
    *,
    target_column,
    owner_id: int,
    cursor: str | None,
    limit: int,
) -> FollowListPage:
    """Generic ORDER BY (created_at DESC, id DESC) pagination.

    The ``target_column`` is the "user we want to enumerate" FK:
    ``follower_profile_id`` for "followers of X" lists,
    ``followed_profile_id`` for "X follows" lists. The cursor's
    ``(created_at, id)`` pair is the last row of the previous page;
    we want strictly less than that pair. SQLAlchemy's
    ``tuple_(created_at, id) < (cursor_at, cursor_id)`` is the standard
    lexicographic comparator and is DB-portable.
    """
    stmt = (
        select(
            CommunityFollow.public_id,
            CommunityFollow.created_at,
            CommunityFollow.id,
        )
        .where(target_column == owner_id)
        .order_by(
            CommunityFollow.created_at.desc(),
            CommunityFollow.id.desc(),
        )
        .limit(limit + 1)  # one extra to detect "more"
    )
    if cursor is not None:
        decoded = _decode_cursor(cursor)
        if decoded is not None:
            cursor_at, cursor_id = decoded
            stmt = stmt.where(
                tuple_(CommunityFollow.created_at, CommunityFollow.id)
                < tuple_(cursor_at, cursor_id)
            )

    rows = db.execute(stmt).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    public_ids = tuple(row[0] for row in rows)
    next_cursor = None
    if has_more and rows:
        last_at, last_id = rows[-1][1], rows[-1][2]
        next_cursor = _encode_cursor(last_at, last_id)
    return FollowListPage(public_ids=public_ids, next_cursor=next_cursor)


__all__ = [
    "FollowAlreadyExists",
    "FollowListPage",
    "FollowRequestNotFound",
    "FollowResult",
    "SelfFollowNotAllowed",
    "accept_follow_request",
    "decline_follow_request",
    "follow",
    "list_followers",
    "list_following",
    "remove_follower",
    "unfollow",
]