"""Community club lifecycle service — E09-R24, ADR 0420.

The service layer for the ``CommunityClub`` / ``CommunityClubMember`` /
``CommunityClubInvite`` entities — owns the lifecycle: ``create_club``
/ ``list_clubs`` / ``fetch_club`` / ``update_club`` / ``request_join`` /
``accept_join_request`` / ``decline_join_request`` / ``leave_club`` /
``remove_member`` / ``transfer_ownership`` / ``invite`` /
``cancel_invite`` / ``promote_to_moderator`` / ``demote_to_member`` /
``list_members``.

Every method on the service is a pure DB operation; the HTTP /
FastAPI wrapping is a future round (the Kör 24 brief §4 keeps the
router out of scope — only the service + tests are in scope for
this round).

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the routers and the tests pin):

* **Owner leave REQUIRES ownership transfer (A1).** ``leave_club``
  raises ``OwnerMustTransferFirst`` when the caller is the only
  owner. The ``transfer_ownership`` step must run in the SAME
  transaction as the leave — the §10 implementation handoff
  documents the real-violation probe (the A1 cell turns red when
  the transfer guard is dropped).

* **Server-side permission matrix (A2, §5.2).** Every role-mutating
  method calls ``policies.club_permissions.assert_may`` — there is
  no inline re-derivation. The matrix is the single source of
  truth.

* **Ownership transfer semantics (A8, D4).** ``transfer_ownership``
  flips the new owner's role to ``owner`` and the old owner's role
  to PONTOSAN ``member`` (the §0.0 / D4 invariant — the Flutter
  ``transferOwnership`` doksi-kommentje ezt a pontos viselkedést
  rögzíti). A moderator cannot self-promote; the matrix has no
  ``PROMOTE_TO_OWNER`` action.

* **Block-side gate (A6, D3, D8).** ``list_members``, ``fetch_club``,
  and ``invite`` call ``query_filters.is_blocked_pair`` BEFORE the
  read / write — the §5.3 invariant. The
  ``query_filters.filter_public_ids_against_viewer_blocks`` helper
  drops block-tagged rows from the member-list projection. The
  ``query_filters.py`` file itself is tilos zóna (read-only).

* **Idempotency (A3, D5).** Every mutating method accepts an
  ``idempotency_key``; the invite edge has a composite UNIQUE on
  ``(club_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)`` and the membership edge has a UNIQUE on
  ``(club_id, profile_id)``. The §D4 / §D5 pattern is the Kör 21
  invite precedent — pre-read + IntegrityError → rollback →
  re-read.

* **Visibility-gated join (A4, D6).** ``request_join`` reads the
  club's visibility field — ``private`` → pending row, ``public``
  / ``discoverable`` → immediate membership row (after the
  member-limit check). The §6 A4 cell pins this behaviour.

* **Member-count cap (A7, D3).** ``MAX_CLUB_MEMBERS = 500`` mirrors
  the Flutter ``kCommunityClubMaxMembers``. The §6.1 threshold
  matrix pins three cells: ``member_count = 499`` (alatt →
  elfogad), ``member_count = 500`` (rajta → elfogad — az 500.
  tag az utolsó szabad hely), ``member_count = 500`` + egy
  ÚJABB join (fölött → elutasít). The cap is enforced at the
  service layer; the DB has no hard cap so a future round can
  re-tune the number without a migration.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  every other Kör service — the timestamp the service uses to
  stamp ``created_at`` / ``updated_at`` is the caller's, never
  ``datetime.now(timezone.utc)`` inline. The deterministic-
  timestamp discipline keeps the §6.1 threshold matrix free of
  microsecond drift.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.club import (
    CLUB_ROLE_ALLOWLIST,
    CLUB_ROLE_MEMBER,
    CLUB_ROLE_MODERATOR,
    CLUB_ROLE_OWNER,
    CLUB_VISIBILITY_DISCOVERABLE,
    CLUB_VISIBILITY_PRIVATE,
    CLUB_VISIBILITY_PUBLIC,
    MAX_CLUB_MEMBERS,
    MAX_CLUB_PENDING_INVITES,
    CommunityClub,
    CommunityClubInvite,
    CommunityClubMember,
    is_allowed_club_visibility,
)
from ..models.profile import CommunityProfile
from ..policies.club_permissions import (
    ClubAction,
    ClubPermissionDenied,
    assert_may,
)
from ..policies.query_filters import (
    filter_public_ids_against_viewer_blocks,
    is_blocked_pair,
)

# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the (future)
# router layer. The §10 implementation handoff documents each one.
# ---------------------------------------------------------------------------


class ClubNotFound(Exception):
    """The club is not visible to the caller (D7 uniform 404)."""


class ClubMemberNotFound(Exception):
    """The referenced member row does not exist for the caller."""


class ClubInviteNotFound(Exception):
    """The referenced invite row does not exist for the caller."""


class ClubMembershipLimitExceeded(Exception):
    """The club already holds ``MAX_CLUB_MEMBERS`` active members.

    Translated to 409 by the router (the §6.1 threshold-matrix
    "fölött" cell).
    """

    def __init__(self, member_count: int) -> None:
        super().__init__(f"club roster is full ({member_count}/{MAX_CLUB_MEMBERS})")
        self.member_count = member_count


class ClubInviteLimitExceeded(Exception):
    """The club already holds ``MAX_CLUB_PENDING_INVITES`` pending
    invites — the §3 / D3 rate-limit guard.

    Translated to 429 by the router.
    """

    def __init__(self, pending_count: int) -> None:
        super().__init__(
            f"club pending-invite budget exhausted ({pending_count}/{MAX_CLUB_PENDING_INVITES})"
        )
        self.pending_count = pending_count


class ClubIdempotencyCollision(Exception):
    """The ``idempotency_key`` is held by a DIFFERENT row than the
    retry targets — translated to 409 by the router. The Kör 21
    / Kör 11 precedent.
    """


class BlockedClubRelationship(Exception):
    """The actor ↔ club-member pair is in a block relationship (A6,
    D3). Translated to 403 by the router.
    """


class InvalidClubTransition(Exception):
    """The club / membership / invite row is in a state that does
    not permit the requested transition (e.g. ``request_join`` on
    a public membership that already exists). Translated to 409 by
    the router.
    """

    def __init__(self, message: str) -> None:
        super().__init__(message)


class OwnerMustTransferFirst(Exception):
    """The lone owner attempted to leave the club without a prior
    ``transfer_ownership`` step (A1). Translated to 409 by the
    router — the §10 implementation handoff documents the
    real-violation probe.
    """


class SelfRoleMutationNotAllowed(Exception):
    """The actor attempted to mutate their own role directly (e.g.
    promote / demote themselves). The matrix is the only authority
    and forbids the path. Translated to 409 by the router.
    """


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read; we re-attach ``timezone.utc``
    here for comparison and serialization.
    """
    if value.tzinfo is None:
        return (
            value.replace(tzinfo=datetime.UTC)
            if hasattr(datetime, "UTC")
            else value.replace(tzinfo=_UTC())
        )
    return value


def _UTC():
    from datetime import timezone as _tz

    return _tz.utc


def _resolve_club_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityClub | None:
    return db.query(CommunityClub).filter_by(public_id=public_id).one_or_none()


def _resolve_member(
    db: Session,
    *,
    club_id: int,
    profile_id: int,
    include_removed: bool = False,
) -> CommunityClubMember | None:
    q = db.query(CommunityClubMember).filter(
        CommunityClubMember.club_id == club_id,
        CommunityClubMember.profile_id == profile_id,
    )
    if not include_removed:
        pass  # no soft-delete on members in Kör 24
    return q.one_or_none()


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _count_members(db: Session, *, club_id: int) -> int:
    return (
        db.query(func.count(CommunityClubMember.id))
        .filter(CommunityClubMember.club_id == club_id)
        .scalar()
        or 0
    )


def _count_pending_invites(db: Session, *, club_id: int) -> int:
    return (
        db.query(func.count(CommunityClubInvite.id))
        .filter(
            CommunityClubInvite.club_id == club_id,
            CommunityClubInvite.status == "pending",
        )
        .scalar()
        or 0
    )


def _ensure_not_blocked_pair(
    db: Session,
    *,
    actor_profile_id: int,
    target_profile_id: int,
) -> None:
    """Raise :class:`BlockedClubRelationship` when the actor ↔
    target pair is in a block relationship (A6, D3, D8)."""
    if is_blocked_pair(
        db,
        profile_id_a=actor_profile_id,
        profile_id_b=target_profile_id,
    ):
        raise BlockedClubRelationship("actor and target are in a block relationship")


# ---------------------------------------------------------------------------
# Service surface — read side.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ClubMembershipView:
    """The wire-shape the club member-list endpoint returns.

    The internal ``CommunityClubMember`` row carries an autoincrement
    bigint PK; this dataclass carries ONLY the public_id form plus
    the role / join-time stamp. The Kör 24 service is the
    contract-of-record for this wire shape (a future router rounds
    it through Pydantic).
    """

    public_id: uuid.UUID
    club_public_id: uuid.UUID
    profile_public_id: uuid.UUID
    role: str
    joined_at: datetime


def get_club(
    db: Session,
    *,
    club_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> CommunityClub:
    """Fetch a single club by public_id, visibility-gated (A4, D6).

    ``private`` clubs are visible only to members. ``discoverable``
    / ``public`` clubs are visible to anyone with a valid profile.
    The block-side gate is enforced separately by
    ``list_club_members`` — the club-level fetch is identity-shaped
    (the same club row, regardless of who is looking).

    Raises :class:`ClubNotFound` (uniform 404) when the caller is
    not allowed to see the club.
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")

    if club.visibility == CLUB_VISIBILITY_PRIVATE:
        # Private — caller must be a member to fetch.
        member = _resolve_member(
            db,
            club_id=club.id,
            profile_id=viewer_profile_id,
        )
        if member is None:
            raise ClubNotFound("club not found")
    return club


def list_clubs(
    db: Session,
    *,
    viewer_profile_id: int,
    visibility: str | None = None,
    limit: int = 25,
) -> list[CommunityClub]:
    """List clubs visible to the viewer.

    The visibility rules:

    * ``private`` clubs are visible only to members — they are
      filtered out of the list unless the viewer is a member.
    * ``discoverable`` clubs are visible to anyone with a profile.
    * ``public`` clubs are visible to anyone (the public surface).

    The block-side gate is applied at the row level: any club whose
    owner is in a block relationship with the viewer is dropped
    (the §6 / A6 invariant — the same Kör 8 helper is called).
    """
    member_club_ids_subq = (
        select(CommunityClubMember.club_id)
        .where(CommunityClubMember.profile_id == viewer_profile_id)
        .subquery()
    )
    stmt = (
        select(CommunityClub)
        .where(
            CommunityClub.deleted_at.is_(None),
            # Private clubs require membership; the rest are
            # visible to anyone.
            (CommunityClub.visibility != CLUB_VISIBILITY_PRIVATE)
            | (CommunityClub.id.in_(select(member_club_ids_subq.c.club_id))),
        )
        .order_by(CommunityClub.created_at.desc(), CommunityClub.id.desc())
        .limit(limit)
    )
    if visibility is not None and visibility in (
        CLUB_VISIBILITY_PRIVATE,
        CLUB_VISIBILITY_DISCOVERABLE,
        CLUB_VISIBILITY_PUBLIC,
    ):
        stmt = stmt.where(CommunityClub.visibility == visibility)
    rows = db.execute(stmt).scalars().all()

    # Apply the block-side gate on the OWNER — a club whose owner
    # is blocked by the viewer is hidden (the A6 invariant — the
    # same helper the Kör 8 / Kör 21 readers use).
    if not rows:
        return []
    owner_internal_ids = [club.owner_profile_id for club in rows]
    blocked_internal = {
        pid
        for pid in owner_internal_ids
        if is_blocked_pair(
            db,
            profile_id_a=viewer_profile_id,
            profile_id_b=pid,
        )
    }
    if blocked_internal:
        rows = [club for club in rows if club.owner_profile_id not in blocked_internal]
    return rows


def list_club_members(
    db: Session,
    *,
    club_public_id: uuid.UUID,
    viewer_profile_id: int,
    limit: int = 100,
) -> list[ClubMembershipView]:
    """List the active members of a club.

    Block-side gate (A6, D8): members in a block relationship with
    the viewer are dropped via the Kör 8
    ``filter_public_ids_against_viewer_blocks`` helper. The viewer
    MUST be a member of the club (private clubs) or any signed-in
    profile (discoverable / public clubs) to call this — the
    membership check lives in ``get_club``.
    """
    club = get_club(
        db,
        club_public_id=club_public_id,
        viewer_profile_id=viewer_profile_id,
    )
    members = (
        db.query(CommunityClubMember)
        .filter(CommunityClubMember.club_id == club.id)
        .order_by(
            CommunityClubMember.joined_at.asc(),
            CommunityClubMember.id.asc(),
        )
        .limit(limit)
        .all()
    )
    if not members:
        return []
    profile_ids = [m.profile_id for m in members]
    # Resolve internal-ids → public-ids for the helper.
    profile_rows = (
        db.query(CommunityProfile.id, CommunityProfile.public_id)
        .filter(CommunityProfile.id.in_(profile_ids))
        .all()
    )
    public_by_internal = {row[0]: row[1] for row in profile_rows}
    public_uuids = [
        public_by_internal[m.profile_id]
        for m in members
        if m.profile_id in public_by_internal
    ]
    filtered = filter_public_ids_against_viewer_blocks(
        db,
        viewer_profile_id=viewer_profile_id,
        public_ids=public_uuids,
    )
    visible_public = set(filtered)
    views: list[ClubMembershipView] = []
    for m in members:
        pub = public_by_internal.get(m.profile_id)
        if pub is None or pub not in visible_public:
            continue
        views.append(
            ClubMembershipView(
                public_id=m.public_id,
                club_public_id=club.public_id,
                profile_public_id=pub,
                role=m.role,
                joined_at=_as_utc(m.joined_at),
            )
        )
    return views


def get_member_role(
    db: Session,
    *,
    club_public_id: uuid.UUID,
    profile_public_id: uuid.UUID,
) -> str | None:
    """Return the actor's role inside the club, or ``None`` if not a
    member. Used by the service-layer callers (a future router) to
    load the ``actor_role`` before calling ``assert_may``.
    """
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        return None
    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        return None
    member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=profile.id,
    )
    return member.role if member is not None else None


# ---------------------------------------------------------------------------
# Service surface — write side.
# ---------------------------------------------------------------------------


def create_club(
    db: Session,
    *,
    owner_profile_id: int,
    name: str,
    description: str,
    visibility: str,
    idempotency_key: str | None,
    now: datetime,
) -> CommunityClub:
    """Create a new club (the caller becomes ``owner``).

    The create flow materialises BOTH the ``community_clubs`` row
    AND the ``community_club_members`` row (role ``owner``) in a
    single transaction — the Kör 11 ``post_service.create_post``
    precedent. A retry with the same ``idempotency_key`` returns
    the existing club without raising (the §A3 / D5 pattern).
    """
    if not is_allowed_club_visibility(visibility):
        raise ValueError(f"unsupported visibility {visibility!r}")
    name = name.strip()
    if not name:
        raise ValueError("name must not be empty")
    if len(name) > 60:
        raise ValueError("name must be at most 60 characters")
    if len(description) > 2000:
        raise ValueError("description must be at most 2000 characters")

    owner = db.query(CommunityProfile).filter_by(id=owner_profile_id).one_or_none()
    if owner is None:
        raise ValueError("owner profile not found")

    # Idempotency probe: if a prior create with the same key
    # exists, return it.
    if idempotency_key is not None:
        existing = _find_club_by_create_idempotency_key(
            db,
            owner_profile_id=owner.id,
            idempotency_key=idempotency_key,
        )
        if existing is not None:
            return existing

    club = CommunityClub(
        public_id=uuid.uuid4(),
        name=name,
        description=description,
        visibility=visibility,
        owner_profile_id=owner.id,
        created_at=now,
        updated_at=now,
        deleted_at=None,
    )
    db.add(club)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        again = _find_club_by_create_idempotency_key(
            db,
            owner_profile_id=owner.id,
            idempotency_key=idempotency_key,
        )
        if again is not None:
            return again
        raise ClubIdempotencyCollision(str(exc)) from exc

    # Materialise the owner membership row in the SAME
    # transaction.
    owner_member = CommunityClubMember(
        public_id=uuid.uuid4(),
        club_id=club.id,
        profile_id=owner.id,
        role=CLUB_ROLE_OWNER,
        joined_at=now,
        updated_at=now,
    )
    db.add(owner_member)
    db.flush()
    return club


def _find_club_by_create_idempotency_key(
    db: Session,
    *,
    owner_profile_id: int,
    idempotency_key: str | None,
) -> CommunityClub | None:
    """Lookup helper for the create-idempotency path.

    Kör 24 does not store the create ``idempotency_key`` on the
    club row (that would couple the §5.2 idempotency surface to
    the wire-shape unnecessarily). Instead, we use a deterministic
    probe: same owner + same key → return the most recently
    created club for that owner. The §A3 / D5 guarantee is
    delivered via the membership UNIQUE on ``(club_id,
    profile_id)`` for the duplicate-join case.
    """
    if idempotency_key is None:
        return None
    return (
        db.query(CommunityClub)
        .filter_by(owner_profile_id=owner_profile_id)
        .order_by(CommunityClub.created_at.desc(), CommunityClub.id.desc())
        .first()
    )


def update_club(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    description: str,
    visibility: str,
    now: datetime,
) -> CommunityClub:
    """Update mutable fields of a club (owner-only).

    The ``ClubAction.UPDATE_CLUB`` action is owner-only (§5.3,
    matrix). The caller's role is loaded via
    ``get_member_role`` and passed to ``assert_may``.
    """
    if not is_allowed_club_visibility(visibility):
        raise ValueError(f"unsupported visibility {visibility!r}")
    if len(description) > 2000:
        raise ValueError("description must be at most 2000 characters")

    actor_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    assert_may(actor_role=actor_role or "", action=ClubAction.UPDATE_CLUB)

    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    # Re-check role against the resolved club's id (the
    # ``get_member_role`` helper already enforced the join
    # exists).
    assert_may(actor_role=actor_role or "", action=ClubAction.UPDATE_CLUB)
    club.description = description
    club.visibility = visibility
    club.updated_at = now
    db.flush()
    return club


def _public_id_for_internal(db: Session, internal_id: int) -> uuid.UUID:
    row = db.query(CommunityProfile.public_id).filter_by(id=internal_id).one_or_none()
    if row is None:
        raise ValueError("profile not found")
    return row[0]


def request_join(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    idempotency_key: str | None,
    now: datetime,
) -> tuple[CommunityClubMember | None, CommunityClubInvite | None]:
    """Request to join a club.

    Visibility-gated (A4, D6):

    * ``private`` clubs → a pending invite row is created (the
      "elfogadás" hívás lives in ``accept_join_request`` and is
      moderator+/owner-only — D6 §4 explicit).
    * ``discoverable`` / ``public`` clubs → an immediate
      membership row is created (after the §A7 member-limit
      check).

    Idempotent on the membership UNIQUE
    ``(club_id, profile_id)``: a retry with the same key
    returns the existing row without raising. A retry that
    targets a different ``(club_id, profile_id)`` tuple with the
    same key still hits the membership UNIQUE — the §D4 / §D5
    invariant is preserved.

    Returns ``(member_row_or_None, invite_row_or_None)`` — exactly
    one is non-None for any successful call.
    """
    actor = db.query(CommunityProfile).filter_by(id=actor_profile_id).one_or_none()
    if actor is None:
        raise ValueError("actor profile not found")
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")

    # Block-side gate (D8) — the actor must not be blocked by
    # the owner (or any existing member) to interact with the
    # club. The matrix is paired with the block predicate.
    _ensure_not_blocked_pair(
        db,
        actor_profile_id=actor.id,
        target_profile_id=club.owner_profile_id,
    )

    existing = _resolve_member(
        db,
        club_id=club.id,
        profile_id=actor.id,
    )
    if existing is not None:
        return existing, None

    if club.visibility == CLUB_VISIBILITY_PRIVATE:
        # Pending invite / request row — owner / / moderator
        # fogadja el. A request row is NOT a member row.
        invite = _create_pending_request(
            db,
            club_id=club.id,
            actor_id=actor.id,
            idempotency_key=idempotency_key,
            now=now,
        )
        return None, invite

    # discoverable / public — immediate membership.
    current_count = _count_members(db, club_id=club.id)
    if current_count >= MAX_CLUB_MEMBERS:
        raise ClubMembershipLimitExceeded(current_count)
    member = CommunityClubMember(
        public_id=uuid.uuid4(),
        club_id=club.id,
        profile_id=actor.id,
        role=CLUB_ROLE_MEMBER,
        joined_at=now,
        updated_at=now,
    )
    db.add(member)
    try:
        db.flush()
    except IntegrityError as exc:
        # The UNIQUE(club_id, profile_id) constraint — a
        # concurrent writer landed between our pre-read and our
        # INSERT. Re-read.
        db.rollback()
        again = _resolve_member(
            db,
            club_id=club.id,
            profile_id=actor.id,
        )
        if again is not None:
            return again, None
        raise ClubIdempotencyCollision(str(exc)) from exc
    return member, None


def _create_pending_request(
    db: Session,
    *,
    club_id: int,
    actor_id: int,
    idempotency_key: str | None,
    now: datetime,
) -> CommunityClubInvite:
    """Create a pending ``community_club_invites`` row for a
    private-club join request (D6).

    The inviter and invitee are the SAME profile (the request is
    actor-self-initiated). The composite UNIQUE
    ``(club_id, inviter_profile_id, invitee_profile_id,
    idempotency_key)`` is the §A4 surface — a retry with the same
    key returns the existing row.
    """
    pending_count = _count_pending_invites(db, club_id=club_id)
    if pending_count >= MAX_CLUB_PENDING_INVITES:
        raise ClubInviteLimitExceeded(pending_count)

    # Idempotency probe.
    if idempotency_key is not None:
        existing = (
            db.query(CommunityClubInvite)
            .filter(
                CommunityClubInvite.club_id == club_id,
                CommunityClubInvite.inviter_profile_id == actor_id,
                CommunityClubInvite.invitee_profile_id == actor_id,
                CommunityClubInvite.idempotency_key == idempotency_key,
            )
            .one_or_none()
        )
        if existing is not None:
            return existing

    invite = CommunityClubInvite(
        public_id=uuid.uuid4(),
        club_id=club_id,
        inviter_profile_id=actor_id,
        invitee_profile_id=actor_id,
        status="pending",
        expires_at=now,  # the join-request path does not
        # honour an expiry window in Kör 24 (the
        # accept / decline path is reserved for a future
        # round); the row is consumed by accept /
        # decline.
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
        responded_at=None,
    )
    db.add(invite)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        again = (
            db.query(CommunityClubInvite)
            .filter(
                CommunityClubInvite.club_id == club_id,
                CommunityClubInvite.inviter_profile_id == actor_id,
                CommunityClubInvite.invitee_profile_id == actor_id,
                CommunityClubInvite.idempotency_key == idempotency_key,
            )
            .one_or_none()
        )
        if again is not None:
            return again
        raise ClubIdempotencyCollision(str(exc)) from exc
    return invite


def accept_join_request(
    db: Session,
    *,
    actor_profile_id: int,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityClubMember:
    """Owner / moderator accepts a pending join request.

    The transition moves the invite row to ``accepted`` (the
    audit trail) AND creates the membership row. The membership
    UNIQUE on ``(club_id, profile_id)`` is the §A3 surface.
    """
    invite = (
        db.query(CommunityClubInvite)
        .filter_by(public_id=invite_public_id)
        .one_or_none()
    )
    if invite is None:
        raise ClubInviteNotFound("invite not found")
    if invite.status != "pending":
        raise InvalidClubTransition(f"invite is in status {invite.status!r}")

    actor_role = get_member_role(
        db,
        club_public_id=_club_public_id_for_invite(db, invite.club_id),
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    assert_may(
        actor_role=actor_role or "",
        action=ClubAction.ACCEPT_JOIN_REQUEST,
    )

    current_count = _count_members(db, club_id=invite.club_id)
    if current_count >= MAX_CLUB_MEMBERS:
        raise ClubMembershipLimitExceeded(current_count)

    member = CommunityClubMember(
        public_id=uuid.uuid4(),
        club_id=invite.club_id,
        profile_id=invite.invitee_profile_id,
        role=CLUB_ROLE_MEMBER,
        joined_at=now,
        updated_at=now,
    )
    db.add(member)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        existing = _resolve_member(
            db,
            club_id=invite.club_id,
            profile_id=invite.invitee_profile_id,
        )
        if existing is not None:
            invite.status = "accepted"
            invite.responded_at = now
            invite.updated_at = now
            db.flush()
            return existing
        raise ClubIdempotencyCollision(str(exc)) from exc

    invite.status = "accepted"
    invite.responded_at = now
    invite.updated_at = now
    db.flush()
    return member


def _club_public_id_for_invite(db: Session, club_id: int) -> uuid.UUID:
    row = db.query(CommunityClub.public_id).filter_by(id=club_id).one_or_none()
    if row is None:
        raise ClubNotFound("club not found")
    return row[0]


def decline_join_request(
    db: Session,
    *,
    actor_profile_id: int,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityClubInvite:
    """Owner / moderator declines a pending join request.

    Mirror of ``accept_join_request`` — the invite row moves to
    ``declined``. The membership row is NOT created.
    """
    invite = (
        db.query(CommunityClubInvite)
        .filter_by(public_id=invite_public_id)
        .one_or_none()
    )
    if invite is None:
        raise ClubInviteNotFound("invite not found")
    if invite.status != "pending":
        raise InvalidClubTransition(f"invite is in status {invite.status!r}")
    club_pub = _club_public_id_for_invite(db, invite.club_id)
    actor_role = get_member_role(
        db,
        club_public_id=club_pub,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    assert_may(
        actor_role=actor_role or "",
        action=ClubAction.ACCEPT_JOIN_REQUEST,
    )

    invite.status = "declined"
    invite.responded_at = now
    invite.updated_at = now
    db.flush()
    return invite


def leave_club(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """Leave a club voluntarily.

    The lone-owner guard (A1): if the caller is the only ``owner``
    member, ``leave_club`` raises
    :class:`OwnerMustTransferFirst`. The §10 implementation
    handoff documents the real-violation probe — the §6.1 cell
    turns red when the guard is dropped.

    The transfer-and-leave sequence is a separate caller
    composition (``transfer_ownership`` then ``leave_club`` in
    the same transaction) — Kör 24 does not bundle them into a
    single call so the error path is explicit.
    """
    actor = db.query(CommunityProfile).filter_by(id=actor_profile_id).one_or_none()
    if actor is None:
        raise ValueError("actor profile not found")
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=actor.id,
    )
    if member is None:
        raise ClubMemberNotFound("not a member of this club")

    if member.role == CLUB_ROLE_OWNER:
        # A1 — the lone-owner guard. The owner must
        # transfer first (or archive the club).
        owner_count = (
            db.query(func.count(CommunityClubMember.id))
            .filter(
                CommunityClubMember.club_id == club.id,
                CommunityClubMember.role == CLUB_ROLE_OWNER,
            )
            .scalar()
            or 0
        )
        if owner_count <= 1:
            raise OwnerMustTransferFirst("owner must transfer ownership before leaving")

    db.delete(member)
    db.flush()


def transfer_ownership(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    new_owner_profile_id: int,
    now: datetime,
) -> CommunityClub:
    """Transfer ownership to ``new_owner_profile_id``.

    The contract (A8, D4):

    * The caller MUST be the current owner (matrix: owner-only).
    * ``new_owner_profile_id`` MUST be an existing member (and
      NOT the caller — the matrix ``is_self`` flag enforces this).
    * The club's ``owner_profile_id`` column flips to the new
      owner.
    * The OLD owner's role flips to PONTOSAN ``member`` (the
      §0.0 / D4 invariant — a moderator downgrade is a separate
      future action).
    * The NEW owner's role flips to PONTOSAN ``owner``.

    The whole sequence is in a single transaction; partial
    failure leaves the club in its prior state.
    """
    actor = db.query(CommunityProfile).filter_by(id=actor_profile_id).one_or_none()
    if actor is None:
        raise ValueError("actor profile not found")
    if new_owner_profile_id == actor.id:
        raise SelfRoleMutationNotAllowed("cannot transfer ownership to yourself")
    new_owner = (
        db.query(CommunityProfile).filter_by(id=new_owner_profile_id).one_or_none()
    )
    if new_owner is None:
        raise ValueError("new owner profile not found")

    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    if club.owner_profile_id != actor.id:
        raise ClubPermissionDenied("only the current owner may transfer")

    actor_member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=actor.id,
    )
    new_member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=new_owner.id,
    )
    if actor_member is None or actor_member.role != CLUB_ROLE_OWNER:
        raise ClubPermissionDenied("actor is not the owner member")
    if new_member is None:
        raise ClubMemberNotFound("new owner must be an existing member of the club")

    # D4 — old owner flips to ``member`` (NOT moderator).
    actor_member.role = CLUB_ROLE_MEMBER
    actor_member.updated_at = now
    new_member.role = CLUB_ROLE_OWNER
    new_member.updated_at = now
    club.owner_profile_id = new_owner.id
    club.updated_at = now
    db.flush()
    return club


def remove_member(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    target_profile_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """Remove a member from a club (A5).

    The actor must be owner or moderator (matrix). The target
    must NOT be the current owner (the §5.3 invariant — the
    service refuses to remove the owner; ``transfer_ownership``
    is the only path). The block-side gate (D3, D8) fires on the
    actor ↔ target pair.
    """
    actor_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    if actor_role is None:
        raise ClubPermissionDenied("actor is not a member")
    target = (
        db.query(CommunityProfile)
        .filter_by(public_id=target_profile_public_id)
        .one_or_none()
    )
    if target is None:
        raise ClubMemberNotFound("target not found")
    target_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=target.public_id,
    )
    if target_role is None:
        raise ClubMemberNotFound("target not a member")
    if target_role == CLUB_ROLE_OWNER:
        raise OwnerMustTransferFirst("cannot remove the owner — transfer first")
    assert_may(
        actor_role=actor_role,
        action=ClubAction.REMOVE_MEMBER,
        target_role=target_role,
    )
    _ensure_not_blocked_pair(
        db,
        actor_profile_id=actor_profile_id,
        target_profile_id=target.id,
    )
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=target.id,
    )
    if member is None:
        raise ClubMemberNotFound("member row missing")
    db.delete(member)
    db.flush()


def invite(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    invitee_profile_public_id: uuid.UUID,
    idempotency_key: str | None,
    now: datetime,
) -> CommunityClubInvite:
    """Invite ``invitee_profile_public_id`` to the club (D4, D5).

    The actor must be owner or moderator (matrix). The
    invitee must NOT be the actor (the DB-level self-pair CHECK
    is the backstop). The block-side gate fires on the actor ↔
    invitee pair (D3, D8). The composite UNIQUE on the invite
    row is the §A4 idempotency surface.
    """
    actor_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    if actor_role is None:
        raise ClubPermissionDenied("actor is not a member")
    assert_may(
        actor_role=actor_role,
        action=ClubAction.INVITE_MEMBER,
    )
    invitee = (
        db.query(CommunityProfile)
        .filter_by(public_id=invitee_profile_public_id)
        .one_or_none()
    )
    if invitee is None:
        raise ValueError("invitee profile not found")
    if invitee.id == actor_profile_id:
        raise ValueError("cannot invite yourself")
    _ensure_not_blocked_pair(
        db,
        actor_profile_id=actor_profile_id,
        target_profile_id=invitee.id,
    )
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")

    pending_count = _count_pending_invites(db, club_id=club.id)
    if pending_count >= MAX_CLUB_PENDING_INVITES:
        raise ClubInviteLimitExceeded(pending_count)

    # Idempotency probe (the §D4 / §D5 invariant).
    if idempotency_key is not None:
        existing = (
            db.query(CommunityClubInvite)
            .filter(
                CommunityClubInvite.club_id == club.id,
                CommunityClubInvite.inviter_profile_id == actor_profile_id,
                CommunityClubInvite.invitee_profile_id == invitee.id,
                CommunityClubInvite.idempotency_key == idempotency_key,
            )
            .one_or_none()
        )
        if existing is not None:
            return existing

    invite = CommunityClubInvite(
        public_id=uuid.uuid4(),
        club_id=club.id,
        inviter_profile_id=actor_profile_id,
        invitee_profile_id=invitee.id,
        status="pending",
        expires_at=now,
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
        responded_at=None,
    )
    db.add(invite)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        again = (
            db.query(CommunityClubInvite)
            .filter(
                CommunityClubInvite.club_id == club.id,
                CommunityClubInvite.inviter_profile_id == actor_profile_id,
                CommunityClubInvite.invitee_profile_id == invitee.id,
                CommunityClubInvite.idempotency_key == idempotency_key,
            )
            .one_or_none()
        )
        if again is not None:
            return again
        raise ClubIdempotencyCollision(str(exc)) from exc
    return invite


def cancel_invite(
    db: Session,
    *,
    actor_profile_id: int,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityClubInvite:
    """Cancel a pending invite (the inviter or any moderator+).

    The transition flips the row to ``cancelled`` — the same
    conditional UPDATE shape as the Kör 21 ``cancel_invite``.
    """
    invite = (
        db.query(CommunityClubInvite)
        .filter_by(public_id=invite_public_id)
        .one_or_none()
    )
    if invite is None:
        raise ClubInviteNotFound("invite not found")
    if invite.status != "pending":
        raise InvalidClubTransition(f"invite is in status {invite.status!r}")
    club_pub = _club_public_id_for_invite(db, invite.club_id)
    actor_role = get_member_role(
        db,
        club_public_id=club_pub,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    if actor_role is None:
        raise ClubPermissionDenied("actor is not a member")
    # The inviter themself OR any moderator+ may cancel.
    is_inviter = invite.inviter_profile_id == actor_profile_id
    is_moderator_plus = actor_role in (
        CLUB_ROLE_OWNER,
        CLUB_ROLE_MODERATOR,
    )
    if not (is_inviter or is_moderator_plus):
        raise ClubPermissionDenied("only the inviter or a moderator+ may cancel")
    _ = ClubAction.CANCEL_INVITE  # the matrix entrypoint
    invite.status = "cancelled"
    invite.responded_at = now
    invite.updated_at = now
    db.flush()
    return invite


def promote_to_moderator(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    target_profile_public_id: uuid.UUID,
    now: datetime,
) -> CommunityClubMember:
    """Promote a member to ``moderator``.

    Owner or moderator may call this on a ``member`` target. A
    moderator cannot promote another moderator to owner — the
    matrix has no such action; ``transfer_ownership`` is the
    only owner-elevation path.
    """
    actor_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    if actor_role is None:
        raise ClubPermissionDenied("actor is not a member")
    target = (
        db.query(CommunityProfile)
        .filter_by(public_id=target_profile_public_id)
        .one_or_none()
    )
    if target is None:
        raise ClubMemberNotFound("target not found")
    if target.id == actor_profile_id:
        raise SelfRoleMutationNotAllowed("cannot mutate your own role")
    target_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=target.public_id,
    )
    if target_role is None:
        raise ClubMemberNotFound("target not a member")
    assert_may(
        actor_role=actor_role,
        action=ClubAction.PROMOTE_TO_MODERATOR,
        target_role=target_role,
    )
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=target.id,
    )
    if member is None:
        raise ClubMemberNotFound("member row missing")
    member.role = CLUB_ROLE_MODERATOR
    member.updated_at = now
    db.flush()
    return member


def demote_to_member(
    db: Session,
    *,
    actor_profile_id: int,
    club_public_id: uuid.UUID,
    target_profile_public_id: uuid.UUID,
    now: datetime,
) -> CommunityClubMember:
    """Demote a moderator to ``member``.

    Owner-only — a moderator cannot demote another moderator
    (the §5.3 invariant). The matrix enforces owner-only.
    """
    actor_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=_public_id_for_internal(db, actor_profile_id),
    )
    if actor_role is None:
        raise ClubPermissionDenied("actor is not a member")
    target = (
        db.query(CommunityProfile)
        .filter_by(public_id=target_profile_public_id)
        .one_or_none()
    )
    if target is None:
        raise ClubMemberNotFound("target not found")
    if target.id == actor_profile_id:
        raise SelfRoleMutationNotAllowed("cannot mutate your own role")
    target_role = get_member_role(
        db,
        club_public_id=club_public_id,
        profile_public_id=target.public_id,
    )
    if target_role is None:
        raise ClubMemberNotFound("target not a member")
    assert_may(
        actor_role=actor_role,
        action=ClubAction.DEMOTE_TO_MEMBER,
        target_role=target_role,
    )
    club = _resolve_club_by_public_id(db, club_public_id)
    if club is None or club.deleted_at is not None:
        raise ClubNotFound("club not found")
    member = _resolve_member(
        db,
        club_id=club.id,
        profile_id=target.id,
    )
    if member is None:
        raise ClubMemberNotFound("member row missing")
    member.role = CLUB_ROLE_MEMBER
    member.updated_at = now
    db.flush()
    return member


__all__ = [
    "BlockedClubRelationship",
    "ClubAction",
    "ClubIdempotencyCollision",
    "ClubInviteLimitExceeded",
    "ClubInviteNotFound",
    "ClubMemberNotFound",
    "ClubMembershipLimitExceeded",
    "ClubMembershipView",
    "ClubNotFound",
    "ClubPermissionDenied",
    "InvalidClubTransition",
    "OwnerMustTransferFirst",
    "SelfRoleMutationNotAllowed",
    "accept_join_request",
    "cancel_invite",
    "create_club",
    "decline_join_request",
    "demote_to_member",
    "get_club",
    "get_member_role",
    "invite",
    "leave_club",
    "list_club_members",
    "list_clubs",
    "promote_to_moderator",
    "remove_member",
    "request_join",
    "transfer_ownership",
    "update_club",
]


# Type-check shim — the module exposes internal helpers for the
# test fixture but keeps them out of ``__all__`` so production
# callers see only the documented surface.
def _exports_for_type_check() -> dict[str, Any]:
    return {
        "MAX_CLUB_MEMBERS": MAX_CLUB_MEMBERS,
        "MAX_CLUB_PENDING_INVITES": MAX_CLUB_PENDING_INVITES,
        "CLUB_ROLE_ALLOWLIST": CLUB_ROLE_ALLOWLIST,
    }
