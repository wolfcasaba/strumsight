"""Block and mute lifecycle service — E09-R08, ADR 0402 §D1.

The service layer for the safety-relationships module is intentionally
narrow, mirroring :mod:`follow_service` (the §3 footprint):

* :func:`block` — write a row to ``community_blocks`` AND, in the
  same DB transaction, ``DELETE`` every active ``community_follows``
  edge in BOTH directions AND ``UPDATE status="blocked"`` on any
  ``community_follow_requests`` row in either direction. The
  transaction is the §5.1 D1 atomicity invariant — a partial commit
  would leave a follow edge visible to a profile that has just
  blocked (or been blocked by) its peer, the exact IDOR-shape the
  brief §9 names. Idempotent: a retry on the same pair returns
  the existing row.

* :func:`unblock` — ``DELETE`` the block row. Idempotent no-op if
  no row exists. §5.3 invariant: the previously removed follow is
  NOT recreated — the function does not touch
  ``community_follows`` at all.

* :func:`mute` / :func:`unmute` — ``INSERT`` / ``DELETE`` on
  ``community_mutes``. §5.2 invariant: the function is intentionally
  isolated from the follow-graph; no other table is touched and no
  signal is sent to the muted party.

* :func:`list_blocked` / :func:`list_muted` — cursor-paginated reads
  of the caller's own blocked / muted rows, the same opaque cursor
  shape as :func:`follow_service.list_followers` /
  :func:`follow_service.list_following`.

* :func:`is_blocked_pair` — re-exported for the §D4 pure-helper
  requirement. The actual implementation lives in
  :mod:`policies.query_filters`; this re-export keeps the
  ``from app.community.services.block_service import is_blocked_pair``
  call site stable if a future round prefers the service-layer
  surface for the pure predicate.

The service layer never raises for "already blocked" / "already
muted" — the brief §2.3 explicitly mandates idempotency at the
state-machine level (same precedent as :func:`follow_service.follow`
— ADR 0401 §6). HTTP-level errors come from the router.
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, select, tuple_
from sqlalchemy.orm import Session

from ..models.profile import CommunityProfile
from ..models.safety_relationships import CommunityBlock, CommunityMute
# `_existing_follow` / `_existing_request` are the private helpers in
# ``follow_service.py`` — the Kör 7 module deliberately keeps them
# module-private so the service layer's invariants stay scoped. We
# import them by name here (ADR 0402 §2.3 — explicit "importáld
# őket, ne írd újra").
from .follow_service import _existing_follow, _existing_request


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


class SelfBlockNotAllowed(Exception):
    """Self-block / self-mute — rejected at the DB layer via CHECK."""


# ---------------------------------------------------------------------------
# block — atomic transaction (ADR 0402 §D1)
# ---------------------------------------------------------------------------


def block(
    db: Session,
    *,
    blocker_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> CommunityBlock:
    """Create (or recycle) a block edge and synchronously close all
    follow-graph relations for the pair.

    The transaction (one ``db.flush()``):

    1. ``community_blocks`` — ``INSERT`` the new row (idempotent:
       a concurrent retry on the same pair returns the existing row
       without raising).
    2. ``community_follows`` — ``DELETE`` both edges
       (blocker → target AND target → blocker). The symmetry is
       intentional (ADR 0402 §D1): a block severs the relationship,
       not one direction — a surviving reverse edge would be a
       misleading residual even if the policy would hide it.
    3. ``community_follow_requests`` — ``UPDATE status="blocked"``
       for any ``requested`` row in either direction. The DB has
       no CHECK on ``status`` (ADR 0401 §4 — the value-set can
       grow without a migration), so the new terminal value lands
       without a schema change.

    Challenge-invite rows are NOT touched (ADR 0402 §D3 — the table
    does not exist yet, Kör 21 scope).
    """
    blocker = _resolve_profile_by_public_id(db, blocker_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if blocker is None:
        raise ValueError("blocker profile not found")
    if target is None:
        raise ValueError("target profile not found")
    if blocker.id == target.id:
        raise SelfBlockNotAllowed("cannot block yourself")

    existing = _existing_block(db, blocker_id=blocker.id, blocked_id=target.id)
    if existing is not None:
        return existing

    row = CommunityBlock(
        blocker_profile_id=blocker.id,
        blocked_profile_id=target.id,
    )
    db.add(row)

    # D1 step 2 — both directions of the active follow edge.
    for edge in (
        _existing_follow(db, follower_id=blocker.id, followed_id=target.id),
        _existing_follow(db, follower_id=target.id, followed_id=blocker.id),
    ):
        if edge is not None:
            db.delete(edge)

    # D1 step 3 — any pending request in either direction.
    now = _utcnow()
    for req in (
        _existing_request(db, requester_id=blocker.id, target_id=target.id),
        _existing_request(db, requester_id=target.id, target_id=blocker.id),
    ):
        if req is not None and req.status == "requested":
            req.status = "blocked"
            req.responded_at = now

    db.flush()
    return row


# ---------------------------------------------------------------------------
# unblock — DELETE only (ADR 0402 §5.3 invariant: do NOT restore follow)
# ---------------------------------------------------------------------------


def unblock(
    db: Session,
    *,
    blocker_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> bool:
    """Delete the block edge for the pair, if any.

    Idempotent: returns ``True`` if a row was deleted, ``False`` if
    no block existed for the pair. The §5.3 invariant — a previous
    ``community_follows`` edge is NOT restored — is enforced by
    construction: the function only touches ``community_blocks``.
    """
    blocker = _resolve_profile_by_public_id(db, blocker_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if blocker is None or target is None:
        # Idempotent on a missing peer — the caller never blocked
        # them, the call is a no-op.
        return False

    existing = _existing_block(db, blocker_id=blocker.id, blocked_id=target.id)
    if existing is None:
        return False
    db.delete(existing)
    db.flush()
    return True


# ---------------------------------------------------------------------------
# mute / unmute — isolated from the follow graph (ADR 0402 §5.2)
# ---------------------------------------------------------------------------


def mute(
    db: Session,
    *,
    muter_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> CommunityMute:
    """Create (or recycle) a mute edge.

    Idempotent at the row level — a concurrent retry on the same
    pair returns the existing row. NO follow-graph mutation, NO
    notification, NO other side effect (ADR 0402 §5.2).
    """
    muter = _resolve_profile_by_public_id(db, muter_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if muter is None:
        raise ValueError("muter profile not found")
    if target is None:
        raise ValueError("target profile not found")
    if muter.id == target.id:
        raise SelfBlockNotAllowed("cannot mute yourself")

    existing = _existing_mute(db, muter_id=muter.id, muted_id=target.id)
    if existing is not None:
        return existing

    row = CommunityMute(
        muter_profile_id=muter.id,
        muted_profile_id=target.id,
    )
    db.add(row)
    db.flush()
    return row


def unmute(
    db: Session,
    *,
    muter_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    idempotency_key: str,
) -> bool:
    """Delete the mute edge for the pair, if any. Idempotent."""
    muter = _resolve_profile_by_public_id(db, muter_public_id)
    target = _resolve_profile_by_public_id(db, target_public_id)
    if muter is None or target is None:
        return False

    existing = _existing_mute(db, muter_id=muter.id, muted_id=target.id)
    if existing is None:
        return False
    db.delete(existing)
    db.flush()
    return True


# ---------------------------------------------------------------------------
# Cursor pagination — mirrors follow_service's opaque cursor shape
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SafetyListPage:
    """A single page of block / mute rows.

    Mirrors :class:`follow_service.FollowListPage` — the public ids are
    opaque Community UUIDs, the cursor is opaque to the caller, and
    the next request sends the cursor back verbatim.
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


def list_blocked(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> SafetyListPage:
    """Return one page of profiles blocked by ``profile_public_id``.

    "Blocked by X" = rows where ``blocker_profile_id = X.id``
    (the rows that originate FROM X); the ``blocked_profile_id``
    on each row is the public-id of the blocked peer we enumerate.

    Ordering is ``(created_at DESC, id DESC)`` — the §D1 contract
    same as ``follow_service.list_followers``.
    """
    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        return SafetyListPage(public_ids=(), next_cursor=None)
    return _paginate_safety(
        db,
        model=CommunityBlock,
        owner_column=CommunityBlock.blocker_profile_id,
        peer_column=CommunityBlock.blocked_profile_id,
        owner_id=profile.id,
        cursor=cursor,
        limit=limit,
    )


def list_muted(
    db: Session,
    *,
    profile_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> SafetyListPage:
    """Return one page of profiles muted by ``profile_public_id``.

    Same shape and ordering as :func:`list_blocked`.
    """
    profile = _resolve_profile_by_public_id(db, profile_public_id)
    if profile is None:
        return SafetyListPage(public_ids=(), next_cursor=None)
    return _paginate_safety(
        db,
        model=CommunityMute,
        owner_column=CommunityMute.muter_profile_id,
        peer_column=CommunityMute.muted_profile_id,
        owner_id=profile.id,
        cursor=cursor,
        limit=limit,
    )


def _paginate_safety(
    db: Session,
    *,
    model,
    owner_column,
    peer_column,
    owner_id: int,
    cursor: str | None,
    limit: int,
) -> SafetyListPage:
    """Generic ORDER BY (created_at DESC, id DESC) pagination for
    block / mute rows. Mirrors :func:`follow_service._paginate_follows`.

    The ``owner_column`` is the "self" FK (``blocker_profile_id`` for
    "X's blocked list", ``muter_profile_id`` for "X's muted list").
    The ``peer_column`` is the FK whose ``public_id`` we emit in the
    page (the other party's id). The ``model`` carries the cursor's
    ``created_at`` / ``id`` columns.

    The page carries the peer's ``public_id`` — which is NOT on the
    row itself — so the helper joins once on ``community_profiles``
    to resolve it. The join is on a single ``IN`` predicate of
    length ``<= limit``, so the cost is bounded by the page size.
    """
    stmt = (
        select(peer_column, model.created_at, model.id)
        .where(owner_column == owner_id)
        .order_by(
            model.created_at.desc(),
            model.id.desc(),
        )
        .limit(limit + 1)
    )
    if cursor is not None:
        decoded = _decode_cursor(cursor)
        if decoded is not None:
            cursor_at, cursor_id = decoded
            stmt = stmt.where(
                tuple_(model.created_at, model.id)
                < tuple_(cursor_at, cursor_id)
            )

    rows = db.execute(stmt).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    # Translate peer FK -> public_id. The owner column stays the
    # same (the caller's own profile); only the peer's public_id
    # needs lookup.
    peer_ids = [row[0] for row in rows]
    public_by_internal: dict[int, uuid.UUID] = {}
    if peer_ids:
        peer_rows = db.execute(
            select(CommunityProfile.id, CommunityProfile.public_id).where(
                CommunityProfile.id.in_(peer_ids)
            )
        ).all()
        public_by_internal = {row[0]: row[1] for row in peer_rows}
    public_ids = tuple(public_by_internal[row[0]] for row in rows)
    next_cursor = None
    if has_more and rows:
        last_at, last_id = rows[-1][1], rows[-1][2]
        next_cursor = _encode_cursor(last_at, last_id)
    return SafetyListPage(public_ids=public_ids, next_cursor=next_cursor)


# ---------------------------------------------------------------------------
# Pure-helper re-export (ADR 0402 §D4)
# ---------------------------------------------------------------------------


# ``is_blocked_pair`` is the D4 pure-helper that a future club feature
# (Kör 24) will call. The canonical implementation lives in
# ``policies.query_filters``; re-exporting here keeps the service
# layer's surface aligned with the brief §2.3 "egyszerű blokk-kapcsolat"
# language and avoids forcing future club code to reach into the
# policies package directly.
from ..policies.query_filters import is_blocked_pair  # noqa: E402,F401


# ---------------------------------------------------------------------------
# Internal row lookups (private to this module)
# ---------------------------------------------------------------------------


def _existing_block(
    db: Session, *, blocker_id: int, blocked_id: int
) -> CommunityBlock | None:
    return (
        db.query(CommunityBlock)
        .filter(
            and_(
                CommunityBlock.blocker_profile_id == blocker_id,
                CommunityBlock.blocked_profile_id == blocked_id,
            )
        )
        .one_or_none()
    )


def _existing_mute(
    db: Session, *, muter_id: int, muted_id: int
) -> CommunityMute | None:
    return (
        db.query(CommunityMute)
        .filter(
            and_(
                CommunityMute.muter_profile_id == muter_id,
                CommunityMute.muted_profile_id == muted_id,
            )
        )
        .one_or_none()
    )


__all__ = [
    "SafetyListPage",
    "SelfBlockNotAllowed",
    "block",
    "is_blocked_pair",
    "list_blocked",
    "list_muted",
    "mute",
    "unblock",
    "unmute",
]
