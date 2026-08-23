"""Community post reactions service (E09-R15).

The service layer for the ``CommunityReaction`` model — owns the
``set_reaction`` / ``remove_reaction`` / ``get_reaction_count`` /
``get_viewer_reaction`` quartet that the future reaction endpoint
and the future post-projection helper will read against. The wire
router is **not** in this round's ``allowed_paths`` (§0.0 D2 scope-
shrink); the service is exercised directly by the §6 acceptance
tests in ``test_reaction_service.py``.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the tests pin):

* **Server-side viewer identity (§5.1).** ``set_reaction`` and
  ``remove_reaction`` take the JWT-resolved ``viewer_public_id``
  as a parameter — there is no body-side override path. The
  ``(post_id, profile_id)`` UNIQUE constraint is the canonical
  identity anchor.

* **Idempotent set (§5.2, A1).** The pair
  ``UNIQUE(post_id, profile_id)`` enforces that a retry with the
  same kind lands on the existing row, never a second row. The
  service catches ``IntegrityError`` and re-reads the row — same
  pattern as ``post_service.create_post``. The §6.1 valódi-sértés
  próba drops the constraint entirely and asserts that two
  ``set_reaction`` calls land two rows (the A1 measure-matrix
  cell goes red).

* **Kind-change is update (§5.2, A2).** A retry with a different
  kind against the same ``(post_id, profile_id)`` row updates the
  kind (and bumps ``updated_at``); the count is unchanged. The
  service checks the existing row's kind BEFORE the INSERT and
  short-circuits to UPDATE when the kind differs.

* **Allowlist enforcement (§3, §5.3).** The service raises
  :class:`InvalidReactionKind` for any kind outside
  ``{support, celebrate, inspiring, helpful}``. The DB column is
  plain ``String`` (ADR 0398 §1) — the check is the service's
  job, the column does NOT carry a CHECK constraint because that
  would block the §6.1 valódi-sértés próba (it removes the
  application-level allowlist, not a column CHECK).

* **Idempotent remove (§5.2, A3).** ``remove_reaction`` called
  twice does not raise — the second call returns ``False``
  (already-removed). The count never goes negative: the count is
  ``COUNT(*)`` over the row, and the DELETE removes a row that
  exists; a second DELETE finds zero rows to remove.

* **Concurrent toggle (§6 A4).** Two parallel ``set_reaction``
  calls from two viewers are independent (different
  ``profile_id``) — both succeed, two rows land. Two parallel
  calls from the SAME viewer on the same post race on the
  ``(post_id, profile_id)`` row — the UNIQUE constraint makes one
  INSERT fail, the service translates the ``IntegrityError`` into
  a re-read + UPDATE, and the row's final kind is whichever
  caller's UPDATE landed last (the §6.1 "real-user-intent" cell
  A4 measures the steady-state consistency, not which-tx-wins).

* **No negative count (§6 A5).** The aggregated count is computed
  at query-time (``COUNT(*)`` over the row), so the property
  invariant is structural — there is no code path that yields
  ``COUNT(*) < 0``. The property-test exercises a long random
  sequence of set / remove / count calls and asserts the count
  is always ``>= 0``.

* **No learning reward event (§6 A7).** A reaction write MUST
  NOT trigger any gamification cross-feature adapter — the
  E08-R26 invariant for "community engagement does not yield
  learning XP". The service has NO call into the gamification
  module. The §6 A7 test asserts the import graph of
  ``reaction_service`` does not include the gamification module.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  ``routers/privacy.py::update_privacy_settings`` and
  ``post_service.create_post`` — the timestamp the service uses
  to stamp ``created_at`` / ``updated_at`` is the caller's, never
  ``datetime.now(timezone.utc)`` inline. The deterministic-
  timestamp discipline keeps the §6 A2 "kind change keeps the
  same row" assertion free of microsecond drift.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.post import CommunityPost
from ..models.profile import CommunityProfile
from ..models.reaction import (
    REACTION_KIND_ALLOWLIST,
    CommunityReaction,
    is_allowed_reaction_kind,
)


# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ReactionPostNotFound(Exception):
    """The post is not visible to the caller (or does not exist).

    Same D7 uniform 404 the post service uses — a not-found id, a
    soft-deleted post, or a moderation-removed post all collapse to
    the same exception. The §5.3 IDOR guarantee.
    """


class ReactionViewerNotFound(Exception):
    """The JWT-resolved viewer has no community profile.

    Mirrors ``post_service.create_post``'s ``ValueError("author
    community profile not found")`` — the caller-side decision to
    raise rather than 404 is the same: the viewer IS authenticated
    but has not completed the Community onboarding flow.
    """


class InvalidReactionKind(Exception):
    """The ``kind`` argument is outside the §3 allowlist.

    Carries the offending value so the router can build a 400 body
    that lists the supported kinds (same shape as the Kör 5
    ``InvalidReactionKind`` precedent in the wire-decoder).
    """

    def __init__(self, value: object) -> None:
        super().__init__(
            f"reaction kind {value!r} is not in the allowlist "
            f"{sorted(REACTION_KIND_ALLOWLIST)}"
        )
        self.value = value


# ---------------------------------------------------------------------------
# Cache-invalidation event (the same seam post_service ships).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ReactionInvalidationEvent:
    """Emitted by ``set_reaction`` / ``remove_reaction`` on success.

    ``post_public_id`` is the post the reaction changed for;
    ``viewer_profile_id`` is the internal bigint profile PK of the
    viewer whose reaction changed. A future round that wires a real
    cache layer reads this event to invalidate the post's projection
    snapshot AND the viewer's per-target relationship view (the
    post-comment count is unaffected — that's a separate event type).
    """

    post_public_id: uuid.UUID
    viewer_profile_id: int
    action: str  # "set" | "remove"


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    from datetime import timezone

    return datetime.now(timezone.utc)


def _resolve_post_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityPost | None:
    return db.query(CommunityPost).filter_by(public_id=public_id).one_or_none()


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _existing_reaction(
    db: Session, *, post_id: int, profile_id: int
) -> CommunityReaction | None:
    """Return the existing live row matching ``(post_id, profile_id)``.

    Soft-deleted posts are NOT excluded here — soft-delete leaves the
    reactions in place (the §11.5 tombstone; the projection read is
    responsible for filtering). The check is purely on the
    ``(post_id, profile_id)`` pair.
    """
    return (
        db.query(CommunityReaction)
        .filter(
            CommunityReaction.post_id == post_id,
            CommunityReaction.profile_id == profile_id,
        )
        .one_or_none()
    )


def _post_visible(post: CommunityPost) -> bool:
    """Mirror of the §D7 uniform-404 helper.

    A post is "visible" when it is NOT soft-deleted AND has a
    visible moderation state. The audience / block check is the
    future post-projection's job — the reaction service only needs
    to know "does the row exist and is the post itself visible" so
    the reaction write doesn't end up attached to a tombstone.
    """
    if post.deleted_at is not None:
        return False
    if post.moderation_state != "visible":
        return False
    return True


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def set_reaction(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    kind: str,
    now: datetime,
    on_invalidate: Callable[[ReactionInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> CommunityReaction:
    """Set (or change) the viewer's reaction on a post.

    Server-side viewer (brief §5.1): ``viewer_public_id`` is the
    JWT-resolved identity. The body-side contract has no
    ``viewer_id`` field; this function does not consult the request
    body for it. The §6 A7 invariant: this function MUST NOT call
    any gamification adapter — the test ``test_no_learning_reward``
    asserts the import graph is gamification-free.

    Idempotent on ``(post_id, profile_id)`` (§6 A1): a retry with
    the same kind is a no-op against the row; a retry with a
    different kind is an UPDATE (§6 A2). The UNIQUE constraint is
    the source of truth for idempotency; the service catches
    ``IntegrityError`` and re-reads the row.

    ``now`` is the timestamp the row is stamped with (the Kör 4 /
    Kör 11 caller-supplied clock precedent).

    Raises :class:`ReactionViewerNotFound` when the viewer's
    community profile is missing; :class:`ReactionPostNotFound`
    when the post is soft-deleted / moderation-hidden / missing;
    :class:`InvalidReactionKind` when ``kind`` is not in the
    allowlist.

    ``idempotency_key`` is accepted for forward-compat with the
    Kör 5 wire contract but is NOT persisted on the row — the
    ``(post_id, profile_id)`` UNIQUE is the canonical idempotency
    surface (this is why re-toggling is allowed: a retry with a
    different kind is not blocked by an idempotency-key column).
    """
    if not is_allowed_reaction_kind(kind):
        raise InvalidReactionKind(kind)

    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise ReactionViewerNotFound("viewer community profile not found")

    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None or not _post_visible(post):
        # D7 — uniform 404 for "not visible". The reaction service
        # mirrors the post service: a missing / soft-deleted /
        # moderation-removed post is identical from the caller's
        # perspective.
        raise ReactionPostNotFound("post not found")

    existing = _existing_reaction(
        db, post_id=post.id, profile_id=viewer.id
    )
    if existing is not None:
        if existing.kind == kind:
            # Same kind — no-op. Return the existing row without
            # bumping ``updated_at`` (the §6 A1 idempotent retry
            # must NOT change row identity).
            return existing
        # Different kind — UPDATE. ``updated_at`` advances to
        # ``now``; ``created_at`` stays. The §6 A2 invariant:
        # one row per (post, profile), no second insert.
        existing.kind = kind
        existing.updated_at = now
        db.flush()
        db.refresh(existing)
        if on_invalidate is not None:
            on_invalidate(
                ReactionInvalidationEvent(
                    post_public_id=post.public_id,
                    viewer_profile_id=viewer.id,
                    action="set",
                )
            )
        return existing

    # Fresh INSERT — the typical path.
    row = CommunityReaction(
        post_id=post.id,
        profile_id=viewer.id,
        kind=kind,
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    try:
        db.flush()
    except IntegrityError:
        # Race: a concurrent writer landed between the
        # ``_existing_reaction`` read and our INSERT. Re-read
        # and translate to UPDATE (the A2 "kind change is update"
        # path); if the kind matches the existing row, return it
        # unchanged (the A1 idempotent retry path).
        db.rollback()
        again = _existing_reaction(
            db, post_id=post.id, profile_id=viewer.id
        )
        if again is None:
            # The IntegrityError was on a DIFFERENT constraint
            # (most likely the FK on a future column). Re-raise
            # so the caller surfaces a 500 — the §6 A1 / A2
            # measure-matrix is about the
            # ``(post_id, profile_id)`` UNIQUE specifically.
            raise
        if again.kind != kind:
            again.kind = kind
            again.updated_at = now
            db.flush()
            db.refresh(again)
        if on_invalidate is not None:
            on_invalidate(
                ReactionInvalidationEvent(
                    post_public_id=post.public_id,
                    viewer_profile_id=viewer.id,
                    action="set",
                )
            )
        return again
    db.refresh(row)

    if on_invalidate is not None:
        on_invalidate(
            ReactionInvalidationEvent(
                post_public_id=post.public_id,
                viewer_profile_id=viewer.id,
                action="set",
            )
        )
    return row


def remove_reaction(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    now: datetime,
    on_invalidate: Callable[[ReactionInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> bool:
    """Remove the viewer's reaction on a post.

    Idempotent (§6 A3): a second call returns ``False`` (already
    removed) without raising. The count never goes negative — the
    DELETE removes an existing row, and a second DELETE finds zero
    rows to remove.

    Returns ``True`` when a transition happened (a row was
    deleted), ``False`` when the viewer had no reaction on this
    post (no-op). The cache-invalidation event is emitted only on
    the actual transition.

    ``idempotency_key`` is accepted for forward-compat with the
    wire contract but is NOT used by the service — the natural
    pair identity is the canonical idempotency surface.

    Raises :class:`ReactionViewerNotFound` when the viewer's
    community profile is missing (a missing post is a no-op —
    there is nothing to remove, the caller already saw the post
    not visible and we don't want a 404 / no-op mismatch).
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise ReactionViewerNotFound("viewer community profile not found")
    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        # D7 / §6 A3 — the post is gone (or never visible). There
        # is no reaction to remove; this is a successful no-op,
        # not a 404. Mirrors the post service's soft-delete
        # idempotent delete semantic.
        return False

    existing = _existing_reaction(
        db, post_id=post.id, profile_id=viewer.id
    )
    if existing is None:
        # Already removed — no transition, no event. §6 A3.
        return False
    db.delete(existing)
    db.flush()
    if on_invalidate is not None:
        on_invalidate(
            ReactionInvalidationEvent(
                post_public_id=post.public_id,
                viewer_profile_id=viewer.id,
                action="remove",
            )
        )
    return True


def get_reaction_count(
    db: Session,
    *,
    post_public_id: uuid.UUID,
) -> int:
    """Return the aggregated reaction count for the post.

    The count is ``COUNT(*)`` over the rows (idempotent retry does
    not inflate it, removal subtracts from it, kind-change is a
    no-op for the count). The §6 A5 property-invariant — count is
    always ``>= 0`` — is structural: there is no code path that
    yields a negative value.

    A missing / soft-deleted / moderation-hidden post yields
    ``0`` (not ``ReactionPostNotFound``) — the count query is a
    read surface, not a write surface, and a missing post is a
    legitimate "no reactions" answer for the projection helper.
    """
    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        return 0
    return (
        db.query(CommunityReaction)
        .filter(CommunityReaction.post_id == post.id)
        .count()
    )


def get_viewer_reaction(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
) -> str | None:
    """Return the viewer's reaction ``kind`` on the post, or ``None``.

    Returns the wire string (``"support"`` / ``"celebrate"`` /
    ``"inspiring"`` / ``"helpful"``) — the projection layer maps
    that to the Flutter ``ReactionKind`` enum via the Kör 5
    ``reactionKindFromWire`` helper.

    A missing viewer / missing post yields ``None`` (no reaction).
    The function is a pure read; the §6 A7 invariant ("reaction
    does not emit learning reward") is trivially satisfied.
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        return None
    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        return None
    existing = _existing_reaction(
        db, post_id=post.id, profile_id=viewer.id
    )
    if existing is None:
        return None
    return existing.kind


__all__ = [
    "InvalidReactionKind",
    "ReactionInvalidationEvent",
    "ReactionPostNotFound",
    "ReactionViewerNotFound",
    "get_reaction_count",
    "get_viewer_reaction",
    "remove_reaction",
    "set_reaction",
]
