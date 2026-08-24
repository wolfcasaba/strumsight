"""Community challenge verification service (E09-R22, ADR 0417).

The service layer for the verified-result submission pipeline — one
entry-point, ``submit_result``, that the router
(``routers/challenges.py::post_submit_result``) calls inside a single
transaction.

The service composes the §6 acceptance matrix from the pure-helper
``policies/integrity_policy.py`` predicates; every reject-path persists
a row with ``verification_state="rejected"`` and a structured
``reason_code`` (the §A8 audit invariant), every accept-path persists
a row with ``verification_state="verified"`` and conditionally
mirrors the new ``best_metric_value`` onto the Kör 21
``community_challenge_participants`` row.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the routers and the tests pin):

* **Server-side author identity (§5.1).** ``actor_profile_id`` is the
  JWT-resolved internal profile id; the request body NEVER carries
  an ``actor_id`` / ``verified`` / ``rank`` field (the Pydantic
  ``extra='forbid'`` is the FIRST defense, the service-level
  ``assert_no_client_issued_trust_state`` is the SECOND).

* **Server-side decision (§5.1, D2).** The ``verification_state`` is
  computed EXCLUSIVELY inside this service — never from the request
  body. A FÉLBEN maradt (``pending|review``) row a jövőben
  maradhat, de a MA szinkron flow azonnal terminál-döntésre jut.

* **Replay-dedup (A1, D2).** ``UNIQUE(participant_id,
  source_event_id)`` is the load-bearing construct. The service
  probes the existing row BEFORE the INSERT; a hit is the
  idempotency surface (mirrors the Kör 21 invite idempotency
  pattern in ``challenge_invite_service.create_invite``).

* **Nonce-TTL (A4, D3).** ``nonce`` is server-generated ``uuid4``;
  ``nonce_expires_at`` is the bookkeeping TTL — a stale
  ``pending|review`` row whose nonce lejárt, a lejárat-utáni
  beküldés a ``rejected`` + ``reason_code="nonce_expired"`` döntést
  kapja.

* **First-vs-best policy (A6, D6).** ``personalBest`` = best-of;
  every other type = first-wins. The conditional UPDATE mirrors
  onto ``community_challenge_participants.best_metric_value``.

* **Race-test seam (L421 / D2).** The replay-dedup probe sits at
  a ``_before_dedup_probe`` seam — the L421 measurement shows an
  INSERT-bound barrier fails to reproduce the race because the
  INSERT-time ``IntegrityError`` is too late; the seam here fires
  at the probe-AND-INSERT pair (mirrors
  ``challenge_invite_service._before_transition``).

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  Kör 11 ``post_service.create_post`` / Kör 21 invite — the
  timestamp the service uses is the caller's, never
  ``datetime.now(timezone.utc)`` inline.

The service does NOT commit. The router layer owns the commit
(``routers/challenges.py::_commit_via``); the service layer only
``flush()`` -es, so the test seam can wrap a barrier around the
INSERT boundary without a half-committed transaction.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.challenge import (
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from ..models.challenge_result import (
    CHALLENGE_RESULT_STATE_PENDING,
    CHALLENGE_RESULT_STATE_REJECTED,
    CHALLENGE_RESULT_STATE_REVIEW,
    CHALLENGE_RESULT_STATE_VERIFIED,
    CommunityChallengeResult,
)
from ..policies.integrity_policy import (
    NONCE_TTL_SECONDS,
    IntegrityDecision,
    assert_no_client_issued_trust_state,
    evaluate_first_vs_best_policy,
    evaluate_impossible_score,
    evaluate_invite_state,
    evaluate_metric_range,
    evaluate_nonce_expiry,
    evaluate_version,
    evaluate_window,
)

# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class ChallengeNotFound(Exception):
    """The challenge is not visible to the caller (D7 uniform 404)."""


class ChallengeParticipantNotFound(Exception):
    """The caller is not a participant of the challenge (D7 uniform
    404)."""


class ChallengeInviteNotFound(Exception):
    """The caller has no usable invite edge for the challenge (D7
    uniform 404)."""


# ---------------------------------------------------------------------------
# Trusted-field whitelist — the §A2 hard-coded mirror of the
# Pydantic request schema. Pydantic ``extra='forbid'`` is the FIRST
# defense; this whitelist is the SECOND defense (the §6.1 A2
# measure-matrix probe patches one of the two defenses and asserts
# the OTHER still fires).
# ---------------------------------------------------------------------------

_SUBMIT_RESULT_TRUSTED_PAYLOAD_KEYS: frozenset[str] = frozenset(
    {"metric_value", "source_event_id", "idempotency_key"}
)


# ---------------------------------------------------------------------------
# Race-test seam (L421, D2).
#
# The seam sits at the BOUNDARY between the replay-probe read and
# the INSERT — a barrier at this exact point reproduces the race
# because the two threads can sync at the dedup-probe read, then
# the second thread can land its INSERT while the first is still
# in its INSERT pipeline. The L421 measurement shows an INSERT-
# boundary barrier (or an entry-point barrier) FAILS to reproduce
# the race 7 / 10 attempts — the seam's location is the load-
# bearing invariant.
# ---------------------------------------------------------------------------

_BEFORE_DEDUP_LOCK = __import__("threading").Lock()
_before_dedup_probe: Callable[[], None] | None = None


def _install_before_dedup_probe(
    hook: Callable[[], None] | None,
) -> Callable[[], None] | None:
    """Install (or clear) the dedup-probe seam.

    The fixture installs a ``threading.Barrier.wait`` callable
    BEFORE the test starts and clears it on teardown. Returns the
    previous hook so the fixture can restore it explicitly.
    """
    global _before_dedup_probe
    with _BEFORE_DEDUP_LOCK:
        previous = _before_dedup_probe
        _before_dedup_probe = hook
        return previous


def _before_dedup_seam() -> None:
    """Run the installed seam callable — no-op in production.

    The seam is invoked at the BOUNDARY between the replay-probe
    read and the INSERT (the L421 measurement point). Production
    callers see no behaviour change.
    """
    with _BEFORE_DEDUP_LOCK:
        hook = _before_dedup_probe
    if hook is not None:
        hook()


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read; the migration contract says
    ``DateTime(timezone=True)`` columns store UTC. PostgreSQL keeps
    tzinfo on the round-trip; the ``replace`` is then a no-op.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _resolve_challenge_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityChallenge | None:
    return db.query(CommunityChallenge).filter_by(public_id=public_id).one_or_none()


def _resolve_participant(
    db: Session,
    *,
    challenge_id: int,
    participant_profile_id: int,
) -> CommunityChallengeParticipant | None:
    return (
        db.query(CommunityChallengeParticipant)
        .filter_by(
            challenge_id=challenge_id,
            participant_profile_id=participant_profile_id,
        )
        .one_or_none()
    )


def _resolve_invite_for_participant(
    db: Session,
    *,
    challenge_id: int,
    invitee_profile_id: int,
) -> CommunityChallengeInvite | None:
    """Return the most recent invite for ``(challenge, invitee)``.

    The Kör 21 invite state machine keeps the ``state`` in
    ``{accepted, active}`` as the "submission-allowed" set (D1).
    Terminal states (``declined | expired | cancelled | completed
    | forfeited``) are NOT a usable invite — the integrity-policy
    check rejects them.

    The helper accepts that the Kör 21 lifecycle MA ``accepted`` -
    ig jut (az ``active`` érték csak deklarált, 0
    hozzárendelés-hely a kódban — ADR 0417 Kontextus 2. pont);
    az értéket a ``state`` leolvasásával kapjuk, és a
    forward-compatible ``active`` a halmazban marad.
    """
    return (
        db.query(CommunityChallengeInvite)
        .filter_by(
            challenge_id=challenge_id,
            invitee_profile_id=invitee_profile_id,
        )
        .order_by(CommunityChallengeInvite.created_at.desc())
        .first()
    )


def _find_existing_result_by_replay_key(
    db: Session,
    *,
    participant_id: int,
    source_event_id: str,
) -> CommunityChallengeResult | None:
    """Return the row matching ``(participant_id, source_event_id)``.

    The composite UNIQUE on the table guarantees at most one row;
    the helper returns ``None`` on a fresh submission.
    """
    stmt = select(CommunityChallengeResult).where(
        CommunityChallengeResult.participant_id == participant_id,
        CommunityChallengeResult.source_event_id == source_event_id,
    )
    return db.execute(stmt).scalar_one_or_none()


def _terminal_state(value: str) -> bool:
    """``True`` for terminal result states (A1 idempotent replay)."""
    return value in {
        CHALLENGE_RESULT_STATE_VERIFIED,
        "unverified",
        CHALLENGE_RESULT_STATE_REJECTED,
        CHALLENGE_RESULT_STATE_REVIEW,
    }


def _build_new_result(
    db: Session,
    *,
    participant_id: int,
    source_event_id: str,
    idempotency_key: str | None,
    metric_value: int,
    nonce: uuid.UUID,
    nonce_expires_at: datetime,
    submitted_at: datetime,
) -> CommunityChallengeResult:
    """Build (in-session) a fresh ``CommunityChallengeResult`` row.

    The INSERT happens in :func:`_insert_result_with_replay_retry`
    so the ``IntegrityError``-on-replay path can attempt the
    re-read BEFORE returning the original row. The helper here
    only constructs the ORM row and ``add()`` -es it to the
    session — the actual flush is the caller's.
    """
    row = CommunityChallengeResult(
        participant_id=participant_id,
        source_event_id=source_event_id,
        idempotency_key=idempotency_key,
        metric_value=metric_value,
        verification_state=CHALLENGE_RESULT_STATE_PENDING,
        reason_code=None,
        nonce=nonce,
        nonce_expires_at=nonce_expires_at,
        submitted_at=submitted_at,
        decided_at=None,
    )
    db.add(row)
    return row


def _insert_result_with_replay_retry(
    db: Session,
    *,
    participant_id: int,
    source_event_id: str,
    idempotency_key: str | None,
    metric_value: int,
    nonce: uuid.UUID,
    nonce_expires_at: datetime,
    now: datetime,
) -> tuple[CommunityChallengeResult, bool]:
    """INSERT a fresh row, returning ``(row, was_fresh_insert)``.

    The "was_fresh_insert" boolean lets the caller distinguish
    between "row we just created" and "row we re-read on race".
    A ``False`` boolean means the INSERT lost to a concurrent
    writer — the row is the existing one.

    The composite UNIQUE on ``(participant_id, source_event_id)``
    is the §A1 surface; the ``IntegrityError``-on-collision
    catches the race; the helper re-reads the original row.
    """
    try:
        row = _build_new_result(
            db,
            participant_id=participant_id,
            source_event_id=source_event_id,
            idempotency_key=idempotency_key,
            metric_value=metric_value,
            nonce=nonce,
            nonce_expires_at=nonce_expires_at,
            submitted_at=now,
        )
        db.flush()
        return row, True
    except IntegrityError:
        db.rollback()
        existing = _find_existing_result_by_replay_key(
            db,
            participant_id=participant_id,
            source_event_id=source_event_id,
        )
        if existing is not None:
            return existing, False
        # The IntegrityError was on a DIFFERENT constraint
        # (most likely the FK chain). Re-raise so the caller
        # surfaces a 500 — the §A1 measure-matrix is about
        # the replay key specifically.
        raise


def _commit_decision(
    row: CommunityChallengeResult,
    *,
    decision: IntegrityDecision,
    now: datetime,
) -> None:
    """Apply a terminal decision to a row in-session.

    The pre-checks chain composes into a single ``IntegrityDecision``
    — when ``ok=True`` the row lands as ``verified`` (with no
    reason_code); when ``ok=False`` the row lands as ``rejected``
    with the structured ``reason_code`` (the §A8 audit
    invariant).
    """
    if decision.ok:
        row.verification_state = CHALLENGE_RESULT_STATE_VERIFIED
        row.reason_code = None
        row.decided_at = now
    else:
        row.verification_state = CHALLENGE_RESULT_STATE_REJECTED
        row.reason_code = decision.reason_code
        row.decided_at = now


def _conditionally_update_best_metric_value(
    db: Session,
    *,
    participant: CommunityChallengeParticipant,
    challenge: CommunityChallenge,
    new_value: int,
) -> None:
    """Apply the §D6 best-of / first-wins policy.

    * ``personalBest``: a new BEST value supersedes the previous
      one. The service performs the conditional UPDATE inside the
      same transaction.
    * Every other type: the FIRST verified row wins, the
      ``best_metric_value`` is set ONCE on the FIRST verified row
      via the same conditional UPDATE (an UPDATE on a row whose
      ``best_metric_value IS NULL`` covers the first-wins invariant).
      Subsequent verified rows never reach this helper because
      the §A6 ``evaluate_first_vs_best_policy`` rejected them
      earlier.

    Mirrors the Kör 21 conditional UPDATE on the
    ``community_challenge_invites`` state transition (the same
    ``WHERE id = :id AND state IN (...)`` + rowcount-check pattern).
    """
    from sqlalchemy import update as sa_update

    if challenge.type == "personalBest":
        # Best-of. Supersede on strictly-greater.
        db.execute(
            sa_update(CommunityChallengeParticipant)
            .where(
                CommunityChallengeParticipant.id == participant.id,
                CommunityChallengeParticipant.best_metric_value.is_(None),
            )
            .values(best_metric_value=new_value)
        )
        # If the first UPDATE missed (best_metric_value is not
        # NULL), try the supersede branch.
        db.execute(
            sa_update(CommunityChallengeParticipant)
            .where(
                CommunityChallengeParticipant.id == participant.id,
                CommunityChallengeParticipant.best_metric_value.is_not(None),
                CommunityChallengeParticipant.best_metric_value < new_value,
            )
            .values(best_metric_value=new_value)
        )
        return

    # Non-personalBest: first-wins.
    db.execute(
        sa_update(CommunityChallengeParticipant)
        .where(
            CommunityChallengeParticipant.id == participant.id,
            CommunityChallengeParticipant.best_metric_value.is_(None),
        )
        .values(best_metric_value=new_value)
    )


def _handle_replay(
    db: Session,
    *,
    existing: CommunityChallengeResult,
    now: datetime,
) -> CommunityChallengeResult:
    """A1 + A4 replay handler.

    Three branches:

    1. The existing row is in a TERMINAL state (``verified |
       unverified | rejected | review``) — replay is idempotent,
       the original row is returned untouched.
    2. The existing row is in ``pending`` / ``review`` and the
       nonce is in the past — the row is FLIPPED to ``rejected`` +
       ``reason_code="nonce_expired"`` and decided_at is stamped.
       The §A4 cell lands here.
    3. The existing row is in ``pending`` / ``review`` and the
       nonce is still valid — a concurrent submission is in
       flight; the helper returns the existing row untouched
       (the row will be re-decided by the original submitter
       downstream).

    The function never raises; the calling service returns the
    row as-is.
    """
    if _terminal_state(existing.verification_state):
        # A1 idempotent replay.
        return existing

    nonce_decision = evaluate_nonce_expiry(
        nonce_expires_at=existing.nonce_expires_at,
        now=now,
    )
    if not nonce_decision.ok:
        # A4 — stale nonce. Flip to rejected.
        existing.verification_state = CHALLENGE_RESULT_STATE_REJECTED
        existing.reason_code = nonce_decision.reason_code
        existing.decided_at = now
        db.flush()
        db.refresh(existing)
        return existing

    # Concurrent submission in flight. Return the existing
    # pending/review row untouched.
    return existing


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def submit_result(
    db: Session,
    *,
    actor_profile_id: int,
    challenge_public_id: uuid.UUID,
    submitted_version: int,
    source_event_id: str,
    metric_value: int,
    idempotency_key: str | None,
    submitted_payload_keys: set[str],
    now: datetime,
) -> CommunityChallengeResult:
    """Submit (or replay) a verified challenge result.

    The single-entry pipeline composed of:

    1. :func:`assert_no_client_issued_trust_state` — §A2 belt-and-
       braces: the Pydantic ``extra='forbid'`` is the first
       defense, this is the second. If the incoming payload
       carries any field outside the trusted whitelist
       (the §5.1 "metric / source-event-id / idempotency-key" set),
       the submission lands as ``rejected`` /
       ``reason_code="client_issued_trust_state"``.
    2. :func:`evaluate_metric_range` — §A3 numeric bound.
    3. Challenge resolution by ``public_id``; raises
       :class:`ChallengeNotFound` on miss (D7 uniform 404).
    4. :func:`evaluate_window` — §A7 server-time window check.
    5. :func:`evaluate_version` — §A5 first measure-matrix row.
    6. Participant resolution; raises
       :class:`ChallengeParticipantNotFound` on miss (D7 uniform
       404 — a non-participant must not learn the challenge from
       a 200-vs-404 split).
    7. Invite resolution; raises
       :class:`ChallengeInviteNotFound` on miss (D7 uniform 404).
    8. :func:`evaluate_invite_state` — §A5 second measure-matrix
       row. Reads ``invite.state`` (read-only, ADR 0417 D1).
    9. :func:`evaluate_impossible_score` — §A3 time-based
       physically-impossible detection.
    10. :func:`evaluate_first_vs_best_policy` — §A6 first-vs-best.
        Looks at ``participant.best_metric_value``.
    11. INSERT or replay-handle. The dedup probe runs at the
        ``_before_dedup_seam()`` boundary, BEFORE the INSERT
        attempt.
    12. Apply the final decision (verified / rejected) onto the
        row, then conditionally UPDATE
        ``community_challenge_participants.best_metric_value``.

    Every reject-path persists a row (the §A8 audit invariant):
    even ``client_issued_trust_state``, ``metric_out_of_range``,
    ``version_mismatch``, ``challenge_window_closed``,
    ``invite_not_active``, ``impossible_score``,
    ``already_submitted`` all land as ``verification_state=
    "rejected"`` + ``reason_code``.

    The service does NOT commit. The router layer owns the commit
    (``routers/challenges.py::_commit_via``).
    """
    nonce = uuid.uuid4()
    nonce_expires_at = now + timedelta(seconds=NONCE_TTL_SECONDS)

    # Resolution FIRST (§A8 audit invariant — every reject-path needs a
    # participant FK so the audit row can be persisted). The
    # challenge-by-public_id / participant-by-(challenge, profile) /
    # invite-by-(challenge, invitee) lookups are the load-bearing
    # resolves; if any of them miss, the service raises a domain
    # exception (D7 uniform 404 surface).
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    participant = _resolve_participant(
        db,
        challenge_id=challenge.id,
        participant_profile_id=actor_profile_id,
    )
    if participant is None:
        raise ChallengeParticipantNotFound(
            "caller is not a participant of this challenge"
        )
    invite = _resolve_invite_for_participant(
        db,
        challenge_id=challenge.id,
        invitee_profile_id=actor_profile_id,
    )
    if invite is None:
        raise ChallengeInviteNotFound("caller has no invite edge for this challenge")

    # Replay probe (§A1 idempotent + §A4 stale-nonce) — runs FIRST,
    # BEFORE the policy chain. A1 is short-circuit by design: a
    # replay of the SAME ``source_event_id`` returns the original
    # row untouched, regardless of the new metric_value /
    # version / window state. The policy chain only applies to
    # FRESH submissions.
    existing = _find_existing_result_by_replay_key(
        db,
        participant_id=participant.id,
        source_event_id=source_event_id,
    )
    if existing is not None:
        # Replay-race barrier (L421, D2). The seam sits
        # IMMEDIATELY before the conditional decision point so
        # a concurrent writer racing the same source_event_id is
        # caught at the SAME SQL decision point.
        _before_dedup_seam()
        return _handle_replay(db, existing=existing, now=now)

    # Policy chain (in §A-order — every rejected path STORES a row).
    # The chain is short-circuited: the first failing check freezes
    # the decision and subsequent checks are skipped (we want one
    # reason_code per row, not a cascade).
    decision_chain = assert_no_client_issued_trust_state(
        trusted_fields={
            "metric_value": None,
            "source_event_id": None,
            "idempotency_key": None,
        },
        incoming_fields=dict.fromkeys(submitted_payload_keys, None),
    )
    if decision_chain.ok:
        decision_chain = evaluate_metric_range(metric_value)
    if decision_chain.ok:
        decision_chain = evaluate_window(
            starts_at=challenge.starts_at,
            ends_at=challenge.ends_at,
            now=now,
        )
    if decision_chain.ok:
        decision_chain = evaluate_version(
            submitted_version=submitted_version,
            actual_version=challenge.version,
        )
    if decision_chain.ok:
        decision_chain = evaluate_invite_state(invite_state=invite.state)
    if decision_chain.ok:
        decision_chain = evaluate_impossible_score(
            metric_value=metric_value,
            metric=challenge.metric,
            starts_at=challenge.starts_at,
            ends_at=challenge.ends_at,
            now=now,
        )
    if decision_chain.ok:
        decision_chain = evaluate_first_vs_best_policy(
            challenge_type=challenge.type,
            existing_best=participant.best_metric_value,
            submitted_value=metric_value,
        )

    # INSERT boundary (L421, D2). The replay-probe ran earlier
    # at the top of the function — the seam is now between the
    # policy chain and the INSERT, so the barrier catches a
    # race where a concurrent writer inserted the same
    # source_event_id between the probe and the INSERT. The
    # ``IntegrityError`` retry inside the helper is the
    # fallback.
    _before_dedup_seam()

    if decision_chain.ok:
        # INSERT — with replay-race retry.
        row, _was_fresh = _insert_result_with_replay_retry(
            db,
            participant_id=participant.id,
            source_event_id=source_event_id,
            idempotency_key=idempotency_key,
            metric_value=metric_value,
            nonce=nonce,
            nonce_expires_at=nonce_expires_at,
            now=now,
        )
        _commit_decision(row, decision=decision_chain, now=now)
        _conditionally_update_best_metric_value(
            db,
            participant=participant,
            challenge=challenge,
            new_value=metric_value,
        )
        db.flush()
        db.refresh(row)
        return row

    # Reject-path. We still INSERT the row (the §A8 audit
    # invariant — every rejected attempt has a permanent
    # record). The replay-key UNIQUE catches the case where a
    # second submission arrives for the SAME source_event_id —
    # in that case the helper re-reads the existing rejected
    # row and returns it idempotently. ``challenge`` and
    # ``participant`` are guaranteed non-None by the resolution
    # phase at the top of the function (the D7 404 exceptions
    # propagate first).
    assert challenge is not None and participant is not None
    try:
        row, _was_fresh = _insert_result_with_replay_retry(
            db,
            participant_id=participant.id,
            source_event_id=source_event_id,
            idempotency_key=idempotency_key,
            metric_value=metric_value,
            nonce=nonce,
            nonce_expires_at=nonce_expires_at,
            now=now,
        )
    except IntegrityError:
        # Replay-race retry — the IntegrityError-on-INSERT
        # caught a concurrent writer. Re-read the existing row
        # and return it (A1 cell).
        db.rollback()
        existing = _find_existing_result_by_replay_key(
            db,
            participant_id=participant.id,
            source_event_id=source_event_id,
        )
        if existing is not None:
            return existing
        raise

    # We won the race. Apply the rejected decision.
    _commit_decision(row, decision=decision_chain, now=now)
    db.flush()
    db.refresh(row)
    return row


def fetch_result_for_participant(
    db: Session,
    *,
    actor_profile_id: int,
    challenge_public_id: uuid.UUID,
    source_event_id: str,
) -> CommunityChallengeResult | None:
    """Read a single result row by ``(challenge, participant,
    source_event_id)``.

    The D7 uniform 404 invariant: a non-participant viewer must
    not learn the result's verification_state from a 200-vs-404
    split. The helper raises :class:`ChallengeNotFound` /
    :class:`ChallengeParticipantNotFound` for the "not visible
    FOR YOU" branches.
    """
    challenge = _resolve_challenge_by_public_id(db, challenge_public_id)
    if challenge is None:
        raise ChallengeNotFound("challenge not found")
    participant = _resolve_participant(
        db,
        challenge_id=challenge.id,
        participant_profile_id=actor_profile_id,
    )
    if participant is None:
        raise ChallengeParticipantNotFound(
            "caller is not a participant of this challenge"
        )
    return _find_existing_result_by_replay_key(
        db,
        participant_id=participant.id,
        source_event_id=source_event_id,
    )


# ---------------------------------------------------------------------------
# Type-check shim — the module exposes ``_install_before_dedup_probe``
# for the test fixture but keeps it out of ``__all__`` so production
# callers see only the documented surface.
# ---------------------------------------------------------------------------


def _exports_for_type_check() -> dict[str, Any]:
    return {
        "_install_before_dedup_probe": _install_before_dedup_probe,
        "_before_dedup_seam": _before_dedup_seam,
    }


__all__ = [
    "ChallengeInviteNotFound",
    "ChallengeNotFound",
    "ChallengeParticipantNotFound",
    "fetch_result_for_participant",
    "submit_result",
]
