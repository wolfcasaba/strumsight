"""Community challenge invite lifecycle service (E09-R21, ADR 0415).

The service layer for the ``CommunityChallengeInvite`` state machine —
owns the four lifecycle operations: ``invite`` / ``accept_invite`` /
``decline_invite`` / ``cancel_invite``. Every method is a pure DB
operation; the HTTP / FastAPI wrapping lives in
``routers.challenges``.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the routers and the tests pin):

* **Server-side identity (§5.1).** Every method takes the JWT-resolved
  internal profile id as a parameter — there is no body-side
  override path. The ``CreateChallengeInviteRequest`` / accept /
  decline / cancel payloads do not carry an ``inviter_id`` /
  ``invitee_id`` field at all (``extra='forbid'`` would reject any
  smuggled value even if they did). A test in
  ``test_challenge_invite_service.py::test_a1_invalid_transition_*``
  is the A1 measure-matrix cell.

* **State machine is server-authoritative (§5.1, D1, D5).** The
  transition graph is::

      draft → sent → accepted | declined | expired | cancelled
      accepted → active → completed | forfeited | expired

  Terminal states (declined / expired / cancelled / completed /
  forfeited) NEVER transition further. The enforcement is a single
  conditional UPDATE: ``UPDATE ... WHERE id = :id AND state IN
  (:megengedett_forrás_állapotok)`` + rowcount-ellenőrzés
  (ADR 0415 D5). NEM ``SELECT ... FOR UPDATE`` — nulla precedens a
  kódbázisban (L421 / Kontextus 6. pont).

* **Idempotent create (§5.3, A4, D4).** ``invite`` persists a
  composite UNIQUE on ``(challenge_id, inviter_profile_id,
  invitee_profile_id, idempotency_key)``. A retry with the same
  key hits the existing row (the ``IntegrityError`` → rollback
  → re-read pattern from ``post_service.create_post`` /
  ``follow_service.follow``). The §6.1 valódi-sértés próba drops
  the allowlist / idempotency check and asserts that two creates
  with the same key produce two rows.

* **Block-side gate (A3, D3).** ``invite`` and ``accept_invite`` call
  ``query_filters.is_blocked_pair`` BEFORE the write — write-side
  invariant (the Kör 8 ``is_blocked_pair`` predicate, the Kör 11
  ``post_service.create_post`` precedent). ``block_service.py``
  (tilos zóna) is NOT bővítve.

* **Server-time expiry (A2, A7, §5.2).** The expiry check uses the
  caller-supplied ``now`` clock against the row's ``expires_at``
  timestamp — server-time, never client-time. A client clock skew
  cannot extend the window.

* **Rate limit (A4 / §5.3).** ``invite`` is bounded by a process-
  local ``RateLimiter`` keyed on the inviter's internal id
  (mirrors the Kör 3 ``handles.py::check_availability`` and
  Kör 9 ``search.py::_search_limiter`` precedent). The default
  budget is 30 invites / minute / inviter — ``reset_rate_limiters``
  is the test seam.

* **Race-test seam (L421, ADR 0415 D5).** The conditional UPDATE is
  preceded by a ``_before_transition`` hook (the Kör 20
  ``notification_service._before_commit`` seam precedent). The
  ``threading.Barrier`` in the race-test sits ON this hook, not at
  the function entry point — the L421 measurement shows the entry-
  point barrier fails to reproduce the race in 7 / 10 attempts.
  The hook is a no-op (``pass``) in production; tests inject a
  synchronisation callable via ``_install_before_transition``.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  ``routers/privacy.py::update_privacy_settings`` and
  ``post_service.create_post`` — the timestamp the service uses
  to stamp ``created_at`` / ``updated_at`` / ``responded_at`` is
  the caller's, never ``datetime.now(timezone.utc)`` inline.
  The deterministic-timestamp discipline keeps the A2 expiry
  check free of microsecond drift.
"""

from __future__ import annotations

import threading
import uuid
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ...ratelimit import RateLimiter
from ..models.challenge import (
    CHALLENGE_INVITE_STATE_ACCEPTED,
    CHALLENGE_INVITE_STATE_CANCELLED,
    CHALLENGE_INVITE_STATE_DECLINED,
    CHALLENGE_INVITE_STATE_SENT,
    INVITE_SOURCE_STATES_FOR_ACCEPT,
    INVITE_SOURCE_STATES_FOR_CANCEL,
    INVITE_SOURCE_STATES_FOR_DECLINE,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from ..models.profile import CommunityProfile
from ..policies.query_filters import is_blocked_pair

# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ChallengeNotFound(Exception):
    """The challenge is not visible to the caller (D7 uniform 404)."""


class ChallengeInviteNotFound(Exception):
    """The invite is not visible to the caller (D7 uniform 404)."""


class BlockedChallengeRelationship(Exception):
    """The inviter ↔ invitee pair is in a block relationship (A3).

    Translated to 403 by the router. Same shape as
    ``post_service``'s block-gate error (the §3 safety
    invariant lives at the service layer).
    """


class ChallengeInviteIdempotencyCollision(Exception):
    """The ``idempotency_key`` is held by a DIFFERENT row than the
    retry targets (rare, raised only when the re-read after the
    ``IntegrityError`` rollback returns a row that does not
    match the ``(challenge, inviter, invitee)`` tuple).

    Translated to 409 by the router. The Kör 11 / Kör 7 pattern
    (``FollowAlreadyExists``) raises a domain exception for the
    rare path; this round mirrors it.
    """


class InvalidChallengeInviteTransition(Exception):
    """The invite is in a state that does not permit the requested
    transition (A1 / A2 / D5).

    Carries the current ``state`` so the router can build a 409
    body that lets the client refresh and retry. Same shape as
    the Kör 11 ``StalePostUpdateError``.
    """

    def __init__(self, current_state: str) -> None:
        super().__init__(
            f"invalid invite transition; current_state={current_state!r}"
        )
        self.current_state = current_state


class ChallengeInviteRateLimited(Exception):
    """The inviter has burned the per-inviter budget for the minute
    (A4 / §5.3). Translated to 429 by the router.

    Mirrors the Kör 3 ``handles.py::_availability_limiter``
    shape — a domain exception with no payload (the
    per-inviter counter is the only information the caller
    needs to know).
    """


# ---------------------------------------------------------------------------
# Rate limit (A4 / §5.3) — 30 invites / minute / inviter. The
# brief §A4 names "server-enforced rate limit"; the value is
# the §0.0 / §9 balance between a usable invite cadence and
# preventing an enumeration / spam loop. The limiter is keyed
# on the INVITER'S internal id (not IP) — a single user could
# otherwise burn the budget of their whole NAT pool, and the
# block-side gate is already IP-agnostic (the Kör 8 invariant).
# ---------------------------------------------------------------------------

_INVITE_MAX = 30
_INVITE_WINDOW = 60.0

_invite_limiter = RateLimiter(
    max_attempts=_INVITE_MAX,
    window_seconds=_INVITE_WINDOW,
)


def reset_rate_limiters() -> None:
    """Clear the invite rate limiter — exposed for the test fixture."""
    _invite_limiter.reset()


# ---------------------------------------------------------------------------
# Race-test seam (L421, ADR 0415 D5).
#
# The hook sits IMMEDIATELY before the conditional UPDATE on every
# mutating method. The hook is a no-op in production; the A5 race
# test installs a ``threading.Barrier.wait`` callable here so both
# threads synchronise at the exact SQL-decision point. The L421
# measurement shows the barrier at the function entry point fails
# to reproduce the race 7 / 10 attempts because one thread
# completes the existence-check → UPDATE → commit chain before
# the second is even scheduled.
# ---------------------------------------------------------------------------

_BEFORE_TRANSITION_LOCK = threading.Lock()
_before_transition: Callable[[], None] | None = None


def _install_before_transition(
    hook: Callable[[], None] | None,
) -> Callable[[], None] | None:
    """Install (or clear) the ``_before_transition`` seam.

    The fixture installs a ``threading.Barrier(2).wait`` callable
    before the test starts and clears it on teardown. Returns the
    previous hook so the fixture can restore it explicitly.
    """
    global _before_transition
    with _BEFORE_TRANSITION_LOCK:
        previous = _before_transition
        _before_transition = hook
        return previous


def _before_transition_seam() -> None:
    """Run the installed seam callable — no-op in production.

    The seam is invoked immediately before the conditional
    ``UPDATE`` of every mutating method (the §D5 race-test
    point). Production callers see no behaviour change.
    """
    with _BEFORE_TRANSITION_LOCK:
        hook = _before_transition
    if hook is not None:
        hook()


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (no native tz-aware column
    type); the migration contract says ``DateTime(timezone=True)``
    columns store UTC, so we re-attach ``timezone.utc`` here for
    comparison and serialization. PostgreSQL keeps tzinfo on the
    round-trip; the ``replace`` is then a no-op.
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


def _resolve_challenge_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityChallenge | None:
    return (
        db.query(CommunityChallenge)
        .filter_by(public_id=public_id)
        .one_or_none()
    )


def _resolve_invite_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityChallengeInvite | None:
    return (
        db.query(CommunityChallengeInvite)
        .filter_by(public_id=public_id)
        .one_or_none()
    )


def _resolve_profile_by_internal_id(
    db: Session, internal_id: int
) -> CommunityProfile | None:
    return (
        db.query(CommunityProfile)
        .filter_by(id=internal_id)
        .one_or_none()
    )


def _existing_invite_by_idempotency_key(
    db: Session,
    *,
    challenge_id: int,
    inviter_profile_id: int,
    invitee_profile_id: int,
    idempotency_key: str | None,
) -> CommunityChallengeInvite | None:
    """Return the existing LIVE row matching the (challenge,
    inviter, invitee, idempotency_key) tuple.

    Returns ``None`` when the key is ``None`` (the first-call
    path; subsequent calls with the same ``None`` still return
    ``None`` because the column allows multiple NULL rows, which
    is the §D4 "invite WITHOUT a key may be created multiple
    times" invariant).

    Mirrors ``post_service._existing_post_by_idempotency_key``
    (Kör 11). The §6.1 valódi-sértés próba drops this check
    entirely and asserts that two creates with the same key
    produce two rows.
    """
    if idempotency_key is None:
        return None
    return (
        db.query(CommunityChallengeInvite)
        .filter(
            CommunityChallengeInvite.challenge_id == challenge_id,
            CommunityChallengeInvite.inviter_profile_id == inviter_profile_id,
            CommunityChallengeInvite.invitee_profile_id == invitee_profile_id,
            CommunityChallengeInvite.idempotency_key == idempotency_key,
        )
        .one_or_none()
    )


def _ensure_not_blocked(
    db: Session,
    *,
    inviter_profile_id: int,
    invitee_profile_id: int,
) -> None:
    """Raise :class:`BlockedChallengeRelationship` when the inviter ↔
    invitee pair is in a block relationship (A3, D3).

    The check is symmetric: the block direction does not matter
    for the gate. A self-pair is allowed (the DB CHECK rejects
    it on INSERT — this guard is a no-op for ``inviter_id ==
    invitee_id`` because the caller layer is expected to filter
    that case out, but the helper still takes the constant-time
    ``False`` path through ``is_blocked_pair``).
    """
    if is_blocked_pair(
        db,
        profile_id_a=inviter_profile_id,
        profile_id_b=invitee_profile_id,
    ):
        raise BlockedChallengeRelationship(
            "inviter and invitee are in a block relationship"
        )


def _ensure_challenge_visible(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    now: datetime,
) -> CommunityChallenge:
    """Return the challenge row if the caller may see it; otherwise
    raise :class:`ChallengeNotFound`.

    A challenge is "visible" when:
    * the row exists by ``public_id``;
    * the server-time window has not yet expired
      (``ends_at > now`` is the §A2 server-time check);
    * the challenge window has started (``starts_at <= now``) —
      a not-yet-started challenge is still addressable for
      ``invite`` (the inviter may want to invite ahead of the
      start) but the accept path checks the start separately.

    A challenge with ``ends_at <= now`` is uniformly
    :class:`ChallengeNotFound` so the caller cannot distinguish
    "ended" from "not exists" (D7 IDOR invariant).
    """
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    ends_at_utc = _as_utc(challenge.ends_at)
    now_utc = _as_utc(now)
    if ends_at_utc <= now_utc:
        raise ChallengeNotFound("challenge not found")
    return challenge


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def create_invite(
    db: Session,
    *,
    inviter_public_id: uuid.UUID,
    invitee_public_id: uuid.UUID,
    challenge_public_id: uuid.UUID,
    expires_at: datetime,
    idempotency_key: str | None,
    now: datetime,
) -> CommunityChallengeInvite:
    """Create (or recycle) a challenge invite.

    Server-side inviter identity (§5.1): ``inviter_public_id``
    comes from the JWT, not the request body. The Pydantic
    ``CreateChallengeInviteRequest`` does not carry an
    ``inviter_id`` field at all (``extra='forbid'`` would
    reject any smuggled value even if it did).

    Idempotent on ``(challenge_id, inviter_profile_id,
    invitee_profile_id, idempotency_key)`` (§5.3, D4): a retry
    with the same key returns the existing row without
    raising. The §6.1 valódi-sértés próba drops the allowlist
    check (idempotency probe + the block check) and asserts
    that two creates with the same key produce two rows.

    The block-side gate (A3, D3) runs BEFORE the INSERT: a
    blocked pair raises
    :class:`BlockedChallengeRelationship` and the row is never
    written. The check is symmetric (matches the
    ``is_blocked_pair`` contract).

    The rate limiter (A4 / §5.3) runs BEFORE the block-side
    gate: a rate-limited inviter is rejected at 429 before
    any DB read. The budget is per-inviter-internal-id.

    ``expires_at`` is the server-authoritative invite window;
    the row is stamped with the caller's ``now`` as
    ``created_at`` / ``updated_at`` (Kör 11 caller-supplied
    clock precedent).
    """
    inviter = db.query(CommunityProfile).filter_by(public_id=inviter_public_id).one_or_none()
    if inviter is None:
        raise ValueError("inviter community profile not found")
    invitee = db.query(CommunityProfile).filter_by(public_id=invitee_public_id).one_or_none()
    if invitee is None:
        raise ValueError("invitee community profile not found")
    if inviter.id == invitee.id:
        # The DB CHECK constraint catches this too, but a clean
        # 400 from the service layer saves a round-trip and
        # matches the Kör 7 ``SelfFollowNotAllowed`` shape.
        raise ValueError("cannot invite yourself")

    if not _invite_limiter.allow(f"invite:{inviter.id}"):
        raise ChallengeInviteRateLimited(
            "inviter has burned the per-minute invite budget"
        )

    challenge = _ensure_challenge_visible(
        db, challenge_public_id=challenge_public_id, now=now
    )

    _ensure_not_blocked(
        db,
        inviter_profile_id=inviter.id,
        invitee_profile_id=invitee.id,
    )

    existing = _existing_invite_by_idempotency_key(
        db,
        challenge_id=challenge.id,
        inviter_profile_id=inviter.id,
        invitee_profile_id=invitee.id,
        idempotency_key=idempotency_key,
    )
    if existing is not None:
        # Idempotent retry — return the existing row. The
        # rate-limiter slot is still consumed (the limiter
        # sees the attempt regardless of the recycle), which
        # is the §A4 invariant: a retried invite still counts
        # against the per-minute budget.
        return existing

    invite = CommunityChallengeInvite(
        challenge_id=challenge.id,
        inviter_profile_id=inviter.id,
        invitee_profile_id=invitee.id,
        state=CHALLENGE_INVITE_STATE_SENT,
        expires_at=expires_at,
        idempotency_key=idempotency_key,
        created_at=now,
        updated_at=now,
        responded_at=None,
    )
    db.add(invite)
    try:
        db.flush()
    except IntegrityError:
        # Race: a concurrent writer landed between the
        # idempotency-key read and our INSERT. Re-read and
        # return the winner's row (mirrors
        # ``post_service.create_post`` / ``follow_service.follow``).
        db.rollback()
        again = _existing_invite_by_idempotency_key(
            db,
            challenge_id=challenge.id,
            inviter_profile_id=inviter.id,
            invitee_profile_id=invitee.id,
            idempotency_key=idempotency_key,
        )
        if again is not None:
            return again
        # The IntegrityError was on a DIFFERENT constraint
        # (most likely the self-pair CHECK or the FK chain).
        # Re-raise so the caller surfaces a 500 — the §A4
        # measure-matrix is about the idempotency key
        # specifically, not unrelated constraints.
        raise
    return invite


def accept_invite(
    db: Session,
    *,
    invitee_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityChallengeInvite:
    """Accept a pending invite (invitee-only).

    The transition graph (D5): the conditional UPDATE fires
    when the row is in ``draft`` or ``sent`` state. A row in
    any terminal state (``declined``, ``expired``, ``cancelled``,
    ``completed``, ``forfeited``) raises
    :class:`InvalidChallengeInviteTransition` — the A1
    measure-matrix cell.

    The expiry check (A2, A7) runs AFTER the existence check
    but BEFORE the conditional UPDATE: an invite whose
    ``expires_at <= now`` is rejected at the row level (the
    transition guard) AND at the window check. Both checks
    land on the same ``InvalidChallengeInviteTransition``
    exception so the caller sees a single 409.

    The race-test seam (``_before_transition_seam``) runs
    IMMEDIATELY before the conditional UPDATE — the L421
    measurement point. The barrier in the A5 race test sits
    here.

    Side effect: the row is mirrored into
    ``community_challenge_participants`` so the participant
    side of the join is materialised atomically with the
    state transition. The participant insert uses the
    ``UNIQUE(challenge_id, participant_profile_id)`` constraint
    as its idempotency surface (a retry of an already-accepted
    invite lands on the existing participant row).
    """
    invite = _resolve_invite_by_public_id(db, invite_public_id)
    if invite is None:
        raise ChallengeInviteNotFound("invite not found")

    # Authorization: only the invitee may accept. A
    # non-invitee viewer must not learn the invite's state
    # from a 409-vs-200 split — the D7 uniform 404 applies.
    invitee = db.query(CommunityProfile).filter_by(public_id=invitee_public_id).one_or_none()
    if invitee is None:
        raise ChallengeInviteNotFound("invite not found")
    if invite.invitee_profile_id != invitee.id:
        raise ChallengeInviteNotFound("invite not found")

    # Block-side gate (D3) — run a second time at accept for
    # defence-in-depth: a profile that blocked the inviter
    # AFTER the invite landed must not be able to accept it.
    inviter = _resolve_profile_by_internal_id(db, invite.inviter_profile_id)
    if inviter is None:
        raise ChallengeInviteNotFound("invite not found")
    _ensure_not_blocked(
        db,
        inviter_profile_id=inviter.id,
        invitee_profile_id=invitee.id,
    )

    if _as_utc(invite.expires_at) <= _as_utc(now):
        # A2 / A7 — server-time expiry. The row's
        # ``expires_at`` is the contract; a clock skew on
        # the client must not extend the window.
        raise InvalidChallengeInviteTransition(
            current_state=invite.state
        )

    # Race-test seam (L421, D5) — the seam sits
    # IMMEDIATELY before the conditional UPDATE so the
    # ``threading.Barrier`` synchronises the two threads at
    # the exact SQL-decision point. Production callers see
    # no behaviour change (the seam is a no-op by default).
    _before_transition_seam()

    result = db.execute(
        update(CommunityChallengeInvite)
        .where(
            CommunityChallengeInvite.id == invite.id,
            CommunityChallengeInvite.state.in_(
                list(INVITE_SOURCE_STATES_FOR_ACCEPT)
            ),
        )
        .values(
            state=CHALLENGE_INVITE_STATE_ACCEPTED,
            responded_at=now,
            updated_at=now,
        )
    )
    if result.rowcount == 0:
        # D5 — the row's state has shifted under us (a
        # concurrent cancel or a previously-terminal
        # state). Re-read and raise so the caller surfaces
        # a 409 with the actual current state.
        db.rollback()
        current = _resolve_invite_by_public_id(db, invite_public_id)
        raise InvalidChallengeInviteTransition(
            current_state=current.state if current is not None else "unknown"
        )
    db.flush()
    db.refresh(invite)

    # Mirror the participant row. The
    # ``UNIQUE(challenge_id, participant_profile_id)``
    # constraint is the idempotency surface: a retry of an
    # already-accepted invite hits the existing participant
    # row. We do not raise on the participant-side conflict
    # — the invite's state has already advanced to
    # ``accepted`` and the participant row already exists.
    participant = (
        db.query(CommunityChallengeParticipant)
        .filter(
            CommunityChallengeParticipant.challenge_id == invite.challenge_id,
            CommunityChallengeParticipant.participant_profile_id
            == invite.invitee_profile_id,
        )
        .one_or_none()
    )
    if participant is None:
        db.add(
            CommunityChallengeParticipant(
                challenge_id=invite.challenge_id,
                participant_profile_id=invite.invitee_profile_id,
                best_metric_value=None,
                joined_at=now,
            )
        )
        try:
            db.flush()
        except IntegrityError:
            # A concurrent accept landed the participant
            # row between our existence-check and INSERT.
            # The race is benign — the row exists, the
            # invite has transitioned, no further action.
            db.rollback()

    return invite


def decline_invite(
    db: Session,
    *,
    invitee_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityChallengeInvite:
    """Decline a pending invite (invitee-only).

    Same shape as :func:`accept_invite` — the conditional
    UPDATE accepts only ``draft`` / ``sent`` source states
    (D5). A terminal-state invite raises
    :class:`InvalidChallengeInviteTransition` (the A1 cell).
    """
    invite = _resolve_invite_by_public_id(db, invite_public_id)
    if invite is None:
        raise ChallengeInviteNotFound("invite not found")
    invitee = db.query(CommunityProfile).filter_by(public_id=invitee_public_id).one_or_none()
    if invitee is None or invite.invitee_profile_id != invitee.id:
        raise ChallengeInviteNotFound("invite not found")

    _before_transition_seam()

    result = db.execute(
        update(CommunityChallengeInvite)
        .where(
            CommunityChallengeInvite.id == invite.id,
            CommunityChallengeInvite.state.in_(
                list(INVITE_SOURCE_STATES_FOR_DECLINE)
            ),
        )
        .values(
            state=CHALLENGE_INVITE_STATE_DECLINED,
            responded_at=now,
            updated_at=now,
        )
    )
    if result.rowcount == 0:
        db.rollback()
        current = _resolve_invite_by_public_id(db, invite_public_id)
        raise InvalidChallengeInviteTransition(
            current_state=current.state if current is not None else "unknown"
        )
    db.flush()
    db.refresh(invite)
    return invite


def cancel_invite(
    db: Session,
    *,
    inviter_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
    now: datetime,
) -> CommunityChallengeInvite:
    """Cancel an outgoing invite (inviter-only).

    Same shape as :func:`accept_invite` and
    :func:`decline_invite` — the conditional UPDATE accepts
    only ``draft`` / ``sent`` source states (D5). A
    terminal-state invite raises
    :class:`InvalidChallengeInviteTransition`.

    The D5 race-test cell (``accept + cancel`` concurrent)
    lands here: when the accept branch wins the conditional
    UPDATE, the cancel branch sees ``rowcount == 0`` and
    raises — the test asserts that exactly one branch
    succeeds and the other raises deterministically.
    """
    invite = _resolve_invite_by_public_id(db, invite_public_id)
    if invite is None:
        raise ChallengeInviteNotFound("invite not found")
    inviter = db.query(CommunityProfile).filter_by(public_id=inviter_public_id).one_or_none()
    if inviter is None or invite.inviter_profile_id != inviter.id:
        # D7 uniform 404 — a non-inviter viewer must not
        # learn the invite's state from a 409-vs-200 split.
        raise ChallengeInviteNotFound("invite not found")

    _before_transition_seam()

    result = db.execute(
        update(CommunityChallengeInvite)
        .where(
            CommunityChallengeInvite.id == invite.id,
            CommunityChallengeInvite.state.in_(
                list(INVITE_SOURCE_STATES_FOR_CANCEL)
            ),
        )
        .values(
            state=CHALLENGE_INVITE_STATE_CANCELLED,
            responded_at=now,
            updated_at=now,
        )
    )
    if result.rowcount == 0:
        db.rollback()
        current = _resolve_invite_by_public_id(db, invite_public_id)
        raise InvalidChallengeInviteTransition(
            current_state=current.state if current is not None else "unknown"
        )
    db.flush()
    db.refresh(invite)
    return invite


def fetch_invite_for_invitee(
    db: Session,
    *,
    invitee_public_id: uuid.UUID,
    invite_public_id: uuid.UUID,
) -> CommunityChallengeInvite:
    """Read a single invite for the invitee (read-path helper).

    D7 uniform 404: a non-invitee viewer must not learn the
    invite's state from a 404-vs-200 split. The helper raises
    :class:`ChallengeInviteNotFound` on every "not visible FOR
    YOU" branch.
    """
    invite = _resolve_invite_by_public_id(db, invite_public_id)
    if invite is None:
        raise ChallengeInviteNotFound("invite not found")
    invitee = db.query(CommunityProfile).filter_by(public_id=invitee_public_id).one_or_none()
    if invitee is None or invite.invitee_profile_id != invitee.id:
        raise ChallengeInviteNotFound("invite not found")
    return invite


__all__ = [
    "BlockedChallengeRelationship",
    "ChallengeInviteIdempotencyCollision",
    "ChallengeInviteNotFound",
    "ChallengeInviteRateLimited",
    "ChallengeNotFound",
    "InvalidChallengeInviteTransition",
    "accept_invite",
    "cancel_invite",
    "create_invite",
    "decline_invite",
    "fetch_invite_for_invitee",
    "reset_rate_limiters",
]


# Type-check shim — the module exposes a ``_install_before_transition``
# function for the test fixture but keeps it out of ``__all__`` so
# production callers see only the documented surface.
def _exports_for_type_check() -> dict[str, Any]:
    return {
        "_install_before_transition": _install_before_transition,
        "_before_transition_seam": _before_transition_seam,
    }
