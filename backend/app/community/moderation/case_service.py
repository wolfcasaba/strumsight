"""Moderation case service — E09-R27, ADR 0425.

The service layer for the moderation queue. Six public functions plus
two pure helpers, all DB-aware but with the FastAPI / HTTP layer
sealed out of the module:

* :func:`is_moderator` — D1, the moderator-identity source. A plain
  DB query against :class:`CommunityModerator`. Returns ``False``
  on any error (the A1 measure-matrix cell — a non-moderator user
  gets ``False`` and the router maps that to 403).

* :func:`get_or_create_case` — D2, the case-open seam. Idempotent
  on ``(target_type, target_id)``: a second call with the same
  pair returns the existing OPEN case; an ALL-CLOSED state (one
  closed case for that target, no live open case) opens a new
  case. The service-layer guard for the D2 "one open case per
  target" invariant.

* :func:`record_automation_signal` — D4, the automation-only
  path. NO ``to_state`` parameter — the destination state is
  computed inside the function body from the confidence /
  category inputs and restricted to the ``{"limited",
  "pending_review"}`` set. This is the A4 cell.

* :func:`apply_moderator_decision` — D4, the moderator-only path.
  The ONLY entry point to ``"removed"`` / ``"author_only"``
  states. The moderator identity is verified against the
  :class:`CommunityModerator` table inside the function body — a
  non-moderator caller raises :class:`NotAModeratorError` (the
  router maps that to 403).

* :func:`submit_appeal` — D6, the appeal-seam. Idempotent on
  ``case.appeal_state is None``: a second submission against a
  case with an existing appeal raises
  :class:`AppealAlreadySubmittedError`. The A5 measure-matrix
  cell.

* :func:`resolve_appeal` — D6, the appeal-resolve seam. Carries
  the verdict (``"upheld"`` / ``"overturned"``); ``upheld``
  reverts the case to ``visible``. The "independent review"
  operational rule from ADR 0425 §D6 lives in the runbook, not
  in code.

* :func:`content_visibility_for_state` — D7, the PURE visibility
  helper. No DB, no FastAPI — the A6 cell calls it directly.
  Returns one of ``"full"``, ``"limited"``, ``"hidden"``,
  ``"hidden_except_author"``.

* :func:`compute_priority_score` — D8, the priority formula.
  Three inputs (report-signal, automation-triage,
  account-history), documented weights, no fourth input.

The service layer is INTENTIONALLY INSERT-only against the
``community_moderation_actions`` table: there is no
``update_action`` or ``delete_action`` public function — the A3
measure-matrix cell exploits this absence.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Final

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models.moderation import (
    ACTION_TYPE_APPEAL_RESOLVED,
    ACTION_TYPE_APPEAL_SUBMITTED,
    ACTION_TYPE_AUTOMATION_SIGNAL,
    ACTION_TYPE_MODERATOR_DECISION,
    ACTOR_TYPE_AUTOMATION,
    ACTOR_TYPE_HUMAN_MODERATOR,
    APPEAL_STATE_RESOLVED,
    APPEAL_STATE_SUBMITTED,
    MODERATION_CASE_STATE_AUTHOR_ONLY,
    MODERATION_CASE_STATE_LIMITED,
    MODERATION_CASE_STATE_PENDING_REVIEW,
    MODERATION_CASE_STATE_REMOVED,
    MODERATION_CASE_STATE_VISIBLE,
    MODERATION_CASE_STATES,
    CommunityModerationAction,
    CommunityModerationCase,
    CommunityModerator,
)


# ---------------------------------------------------------------------------
# Module-level state machine — D3.
#
# Each key is the from-state, each value is the frozenset of allowed
# to-states. The graph encodes the §18.1 Dart enum transitions plus the
# ``removed → visible`` path that the appeal-upheld flow uses.
# ---------------------------------------------------------------------------

ALLOWED_TRANSITIONS: Final[dict[str, frozenset[str]]] = {
    MODERATION_CASE_STATE_VISIBLE: frozenset(
        {
            MODERATION_CASE_STATE_LIMITED,
            MODERATION_CASE_STATE_PENDING_REVIEW,
        }
    ),
    MODERATION_CASE_STATE_LIMITED: frozenset(
        {
            MODERATION_CASE_STATE_VISIBLE,
            MODERATION_CASE_STATE_PENDING_REVIEW,
            MODERATION_CASE_STATE_REMOVED,
            MODERATION_CASE_STATE_AUTHOR_ONLY,
        }
    ),
    MODERATION_CASE_STATE_PENDING_REVIEW: frozenset(
        {
            MODERATION_CASE_STATE_VISIBLE,
            MODERATION_CASE_STATE_LIMITED,
            MODERATION_CASE_STATE_REMOVED,
            MODERATION_CASE_STATE_AUTHOR_ONLY,
        }
    ),
    MODERATION_CASE_STATE_REMOVED: frozenset(
        # The ``removed → visible`` transition is RESERVED for the
        # appeal-upheld path (``resolve_appeal`` with verdict
        # ``"upheld"``) — a direct moderator decision calling
        # ``apply_moderator_decision`` with this pair is rejected by
        # the explicit guard below (the §6.1 measure-matrix A2
        # cell). ``removed → author_only`` is also allowed so a
        # moderator can narrow the visibility further (e.g. while
        # the appeal is in flight) without an irreversible step.
        {
            MODERATION_CASE_STATE_VISIBLE,
            MODERATION_CASE_STATE_AUTHOR_ONLY,
        }
    ),
    MODERATION_CASE_STATE_AUTHOR_ONLY: frozenset(
        {
            MODERATION_CASE_STATE_VISIBLE,
            MODERATION_CASE_STATE_REMOVED,
        }
    ),
}


# The "closed" set — a case in one of these states is NOT considered
# "open" for the D2 one-open-case-per-target invariant. The
# ``is_open`` column carries the same denormalized flag.
CLOSED_STATES: Final[frozenset[str]] = frozenset(
    {
        MODERATION_CASE_STATE_REMOVED,
        MODERATION_CASE_STATE_AUTHOR_ONLY,
    }
)


# ---------------------------------------------------------------------------
# D4 automation destination set — the ONLY states an automation
# signal may move a case into. NO ``to_state`` parameter on
# :func:`record_automation_signal`; the value is fixed inside the
# function body. A4 measure-matrix cell.
# ---------------------------------------------------------------------------

AUTOMATION_ALLOWED_TO_STATES: Final[frozenset[str]] = frozenset(
    {
        MODERATION_CASE_STATE_LIMITED,
        MODERATION_CASE_STATE_PENDING_REVIEW,
    }
)


# ---------------------------------------------------------------------------
# Priority-score formula — D8. Three documented inputs, no fourth.
# ---------------------------------------------------------------------------

# The weights are the implementer's engineering call; the inputs
# themselves are fixed by ADR 0425 §D8. The runbook
# (``docs/operations/community-moderation-runbook.md``) carries the
# rationale. All weights are non-negative; the score itself is a
# non-negative integer.
PRIORITY_WEIGHT_REPORT_COUNT: Final[int] = 5
PRIORITY_WEIGHT_AUTOMATION_CONFIDENCE: Final[int] = 40
PRIORITY_WEIGHT_ACCOUNT_HISTORY: Final[int] = 20


# ---------------------------------------------------------------------------
# Visibility literals — D7.
# ---------------------------------------------------------------------------

VISIBILITY_FULL: Final[str] = "full"
VISIBILITY_LIMITED: Final[str] = "limited"
VISIBILITY_HIDDEN: Final[str] = "hidden"
VISIBILITY_HIDDEN_EXCEPT_AUTHOR: Final[str] = "hidden_except_author"


# ---------------------------------------------------------------------------
# Exceptions — the router maps these to HTTP status codes.
# ---------------------------------------------------------------------------


class ModerationError(Exception):
    """Base class — every moderation-queue exception derives from this."""


class InvalidStateTransition(ModerationError, ValueError):
    """§6 A2 / D3 — the requested state transition is not in the
    :data:`ALLOWED_TRANSITIONS` graph.
    """


class AutomationCannotEnforce(ModerationError):
    """§6 A4 / D4 — an automation signal tried to move a case into a
    closed state (``removed`` / ``author_only``), which requires
    human review.
    """


class NotAModerator(ModerationError):
    """§6 A1 / D1 — the caller is not in the
    :class:`CommunityModerator` table.
    """


class AppealAlreadySubmitted(ModerationError):
    """§6 A5 / D6 — the case already carries an appeal in any state
    (submitted or resolved).
    """


class NoOpenAppeal(ModerationError):
    """§6 D6 — :func:`resolve_appeal` was called on a case with no
    live appeal.
    """


class CaseNotFound(ModerationError):
    """The case ``public_id`` does not resolve to a row."""


class InvalidAppealVerdict(ModerationError, ValueError):
    """The verdict string is not ``"upheld"`` or ``"overturned"``."""


# ---------------------------------------------------------------------------
# Wire-shape dataclass (the §5.1 retaliation-risk invariant from ADR 0422
# applies symmetrically here — the response shape MUST NOT include the
# reporter identity).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ModerationCaseSummary:
    """The §6 A1 / A7 wire shape — ``public_id``, target, state,
    priority, timestamps.

    The reporter identity is intentionally NOT a field. The response
    is built from the case row alone; the
    :class:`CommunityModerationAction` audit rows are returned
    separately, with their ``actor_user_id`` field set to ``None``
    for any ``actor_type = "automation"`` row.

    The class is deliberately frozen — a future maintainer who tries
    to add a mutable field like ``reporter_profile_id`` will fail the
    A7 test by structural absence.
    """

    case_public_id: uuid.UUID
    target_type: str
    target_id: str
    state: str
    appeal_state: str | None
    priority_score: int
    is_open: bool
    opened_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class ModerationActionSummary:
    """The wire shape of an action audit row.

    ``actor_user_id`` is NULL for ``actor_type = "automation"`` rows.
    The reporter identity (the Kör 26 ``CommunityReport`` side) is
    NEVER joined in here — only the actor who CARRIED OUT the
    moderation action is recorded.
    """

    action_public_id: uuid.UUID
    case_public_id: uuid.UUID
    action_type: str
    from_state: str | None
    to_state: str | None
    actor_type: str
    actor_user_id: int | None
    reason: str | None
    created_at: datetime


# ---------------------------------------------------------------------------
# D1 — moderator-identity lookup
# ---------------------------------------------------------------------------


def is_moderator(db: Session, user_id: int) -> bool:
    """Return ``True`` when ``user_id`` has a
    :class:`CommunityModerator` row.

    This is the ONLY function the router calls to authorize a
    moderation endpoint. The brief §4 tilos zóna forbids adding a
    ``role`` / ``is_admin`` column to ``User`` / ``CommunityProfile``,
    so this table is the unique source of truth.
    """
    row = (
        db.execute(
            select(CommunityModerator.id).where(
                CommunityModerator.user_id == user_id
            )
        )
        .first()
    )
    return row is not None


# ---------------------------------------------------------------------------
# D2 — get_or_create_case (the case-open seam)
# ---------------------------------------------------------------------------


def _target_author_profile_id(db: Session, target_type: str, target_id: str) -> int | None:
    """Resolve the target's owner-profile ``id`` for the D8
    account-history computation.

    Returns ``None`` when the target_type is unknown / not yet
    wired (D8 explicitly allows the third signal to be ``0``).
    """
    try:
        target_uuid = uuid.UUID(target_id)
    except (ValueError, TypeError):
        return None

    if target_type == "post":
        from ..models.post import CommunityPost

        row = db.execute(
            select(CommunityPost.profile_id).where(
                CommunityPost.public_id == target_uuid
            )
        ).first()
        return int(row[0]) if row is not None else None

    if target_type == "comment":
        from ..models.comment import CommunityComment

        row = db.execute(
            select(CommunityComment.author_profile_id).where(
                CommunityComment.public_id == target_uuid
            )
        ).first()
        return int(row[0]) if row is not None else None

    return None


def _report_signal(db: Session, target_type: str, target_id: str) -> int:
    """D8 #1 — the count of ``CommunityReport`` rows against this target."""
    from ..models.report import CommunityReport

    result = db.execute(
        select(func.count(CommunityReport.id)).where(
            CommunityReport.target_type == target_type,
            CommunityReport.target_id == target_id,
        )
    ).scalar()
    return int(result or 0)


def _account_history(db: Session, target_type: str, target_id: str) -> int:
    """D8 #3 — the count of CLOSED cases owned by the target's
    profile. ``0`` when the target profile cannot be resolved.
    """
    profile_id = _target_author_profile_id(db, target_type, target_id)
    if profile_id is None:
        return 0

    # ``author_profile_id`` is not stored on the case row (D2 / D7) —
    # we have to JOIN through the target tables to count the owner's
    # CLOSED cases. The two branches mirror
    # :func:`_target_author_profile_id`.
    if target_type == "post":
        from ..models.post import CommunityPost

        subq = select(CommunityPost.public_id).where(
            CommunityPost.profile_id == profile_id
        )
        count = db.execute(
            select(func.count(CommunityModerationCase.id)).where(
                CommunityModerationCase.target_type == "post",
                CommunityModerationCase.target_id.in_(subq),
                CommunityModerationCase.state.in_(list(CLOSED_STATES)),
            )
        ).scalar()
        return int(count or 0)

    if target_type == "comment":
        from ..models.comment import CommunityComment

        subq = select(CommunityComment.public_id).where(
            CommunityComment.author_profile_id == profile_id
        )
        count = db.execute(
            select(func.count(CommunityModerationCase.id)).where(
                CommunityModerationCase.target_type == "comment",
                CommunityModerationCase.target_id.in_(subq),
                CommunityModerationCase.state.in_(list(CLOSED_STATES)),
            )
        ).scalar()
        return int(count or 0)

    return 0


def compute_priority_score(
    db: Session,
    *,
    target_type: str,
    target_id: str,
    automation_confidence: float | None = None,
) -> int:
    """Compute the queue-priority score (D8).

    Three documented inputs:

    1. ``report_signal`` — count of ``CommunityReport`` rows against
       the target.
    2. ``automation_triage`` — the most recent automation confidence
       (or ``0`` when the caller has none yet — :func:`get_or_create_case`
       passes ``None``).
    3. ``account_history`` — count of CLOSED cases owned by the
       target's profile (or ``0`` when the target type is unknown).

    The weights are the implementer's engineering choice. The
    runbook (``docs/operations/community-moderation-runbook.md``)
    carries the rationale. The function is pure on its three inputs
    — it has no fourth documented input.
    """
    report_count = _report_signal(db, target_type, target_id)
    history = _account_history(db, target_type, target_id)
    triage = (
        int(round(automation_confidence * PRIORITY_WEIGHT_AUTOMATION_CONFIDENCE))
        if automation_confidence is not None
        else 0
    )
    return (
        report_count * PRIORITY_WEIGHT_REPORT_COUNT
        + triage
        + history * PRIORITY_WEIGHT_ACCOUNT_HISTORY
    )


def get_or_create_case(
    db: Session,
    *,
    target_type: str,
    target_id: str,
    now: datetime,
) -> CommunityModerationCase:
    """Open a case for ``(target_type, target_id)`` if none is open,
    else return the existing open case.

    The D2 invariant — at most ONE open case per target — is
    enforced here. The function:

    1. Looks up an existing OPEN case (any state NOT in
       :data:`CLOSED_STATES`).
    2. Returns it if present.
    3. Otherwise INSERTs a fresh case in state ``visible`` with
       ``is_open=True`` and a recomputed :func:`compute_priority_score`.

    The function does NOT raise on duplicate insert — a concurrent
    call wins the ``(target_type, target_id, is_open=True)`` race
    via the ``ix_community_moderation_cases_target_open`` index and
    the second caller re-reads the winner. The "duplicate open
    case" exception lives at the ``apply_moderator_decision`` /
    ``record_automation_signal`` call sites, not here.
    """
    existing = db.execute(
        select(CommunityModerationCase)
        .where(
            CommunityModerationCase.target_type == target_type,
            CommunityModerationCase.target_id == target_id,
            CommunityModerationCase.is_open.is_(True),
        )
        .order_by(CommunityModerationCase.opened_at.desc())
    ).scalars().first()
    if existing is not None:
        return existing

    row = CommunityModerationCase(
        target_type=target_type,
        target_id=target_id,
        state=MODERATION_CASE_STATE_VISIBLE,
        priority_score=compute_priority_score(
            db, target_type=target_type, target_id=target_id
        ),
        is_open=True,
        opened_at=now,
        updated_at=now,
    )
    db.add(row)
    db.flush()
    return row


# ---------------------------------------------------------------------------
# D4 — record_automation_signal
# ---------------------------------------------------------------------------


def record_automation_signal(
    db: Session,
    case: CommunityModerationCase,
    *,
    confidence: float,
    provider: str,
    provider_version: str,
    now: datetime,
) -> CommunityModerationCase:
    """Record an automation signal against ``case``.

    **NO ``to_state`` parameter** (D4 / A4). The destination state
    is computed inside the function body:

    * ``confidence >= 0.8`` → ``pending_review``.
    * ``confidence < 0.8`` → ``limited``.

    The destination is ALWAYS one of
    :data:`AUTOMATION_ALLOWED_TO_STATES`. A future maintainer who
    tries to widen the set will fail the A4 measure-matrix cell:
    the function literally cannot reach a CLOSED state.

    The function NEVER writes a row of ``action_type =
    "moderator_decision"``. The audit row is
    ``action_type = "automation_signal"`` with ``actor_type =
    "automation"`` and ``actor_user_id = None``.
    """
    if not (0.0 <= confidence <= 1.0):
        raise ValueError(f"confidence out of range: {confidence!r}")

    to_state = (
        MODERATION_CASE_STATE_PENDING_REVIEW
        if confidence >= 0.8
        else MODERATION_CASE_STATE_LIMITED
    )

    from_state = case.state
    if from_state not in ALLOWED_TRANSITIONS:
        raise InvalidStateTransition(
            f"case in unknown state: {from_state!r}"
        )
    if to_state not in ALLOWED_TRANSITIONS[from_state]:
        # The caller asked for an illegal transition; map that to
        # the D3 / A2 cell. An automation that wants ``removed``
        # lands here AND on the A4 cell — both must fire.
        raise InvalidStateTransition(
            f"automation cannot transition {from_state!r} → {to_state!r}"
        )
    if to_state not in AUTOMATION_ALLOWED_TO_STATES:
        # Defense-in-depth: even if a future maintainer broadens the
        # ``ALLOWED_TRANSITIONS`` graph for the from-state, this
        # explicit allowlist is the A4 gát. The §6.1 valódi-sértés
        # próba monkey-patches this allowlist to ``{"removed",
        # "limited", "pending_review"}`` and asserts the A4 cell
        # goes red.
        raise AutomationCannotEnforce(
            f"automation cannot transition into {to_state!r}"
        )

    case.state = to_state
    case.priority_score = compute_priority_score(
        db,
        target_type=case.target_type,
        target_id=case.target_id,
        automation_confidence=confidence,
    )
    case.updated_at = now

    _record_action(
        db,
        case=case,
        action_type=ACTION_TYPE_AUTOMATION_SIGNAL,
        from_state=from_state,
        to_state=to_state,
        actor_type=ACTOR_TYPE_AUTOMATION,
        actor_user_id=None,
        reason=None,
        evidence={
            "provider": provider,
            "provider_version": provider_version,
            "confidence": float(confidence),
        },
        now=now,
    )
    return case


# ---------------------------------------------------------------------------
# D4 — apply_moderator_decision (the ONLY path to closed states)
# ---------------------------------------------------------------------------


def apply_moderator_decision(
    db: Session,
    case: CommunityModerationCase,
    *,
    to_state: str,
    moderator_user_id: int,
    reason: str,
    now: datetime,
) -> CommunityModerationCase:
    """Apply a human moderator's decision.

    This is the ONLY function that may write ``state in {"removed",
    "author_only"}`` (D4 / §5.1). The ``moderator_user_id`` is
    verified against :class:`CommunityModerator` here — a
    non-moderator caller raises :class:`NotAModeratorError`, the
    case is NOT modified.
    """
    if not is_moderator(db, moderator_user_id):
        raise NotAModerator(
            f"user {moderator_user_id} is not a moderator"
        )
    if to_state not in MODERATION_CASE_STATES:
        raise InvalidStateTransition(
            f"unknown to_state: {to_state!r}"
        )

    from_state = case.state

    # §6.1 A2 — the ``removed → visible`` transition is RESERVED
    # for the appeal-upheld path (``resolve_appeal`` with verdict
    # ``"upheld"``). A direct moderator decision calling
    # ``apply_moderator_decision`` with this pair is rejected here
    # — it would silently bypass the appeal audit row.
    if (
        from_state == MODERATION_CASE_STATE_REMOVED
        and to_state == MODERATION_CASE_STATE_VISIBLE
    ):
        raise InvalidStateTransition(
            "removed → visible is reserved for appeal-upheld; "
            "use resolve_appeal with verdict='upheld' instead"
        )

    if to_state not in ALLOWED_TRANSITIONS[from_state]:
        raise InvalidStateTransition(
            f"moderator decision {from_state!r} → {to_state!r} is not allowed"
        )

    case.state = to_state
    # A case in a closed state is no longer "open" for the D2 one-
    # open-case-per-target invariant.
    case.is_open = to_state not in CLOSED_STATES
    case.priority_score = compute_priority_score(
        db, target_type=case.target_type, target_id=case.target_id
    )
    case.updated_at = now

    _record_action(
        db,
        case=case,
        action_type=ACTION_TYPE_MODERATOR_DECISION,
        from_state=from_state,
        to_state=to_state,
        actor_type=ACTOR_TYPE_HUMAN_MODERATOR,
        actor_user_id=moderator_user_id,
        reason=reason,
        evidence=None,
        now=now,
    )
    return case


# ---------------------------------------------------------------------------
# D6 — submit_appeal / resolve_appeal
# ---------------------------------------------------------------------------


def submit_appeal(
    db: Session,
    case: CommunityModerationCase,
    *,
    submitted_by_user_id: int,
    reason: str,
    now: datetime,
) -> CommunityModerationCase:
    """Submit an appeal against ``case``.

    A5 / D6 — the appeal is one-per-case. The function rejects a
    second submission when ``case.appeal_state is not None`` (the
    appeal is either in ``"submitted"`` or ``"resolved"`` state at
    that point).

    The appeal is recorded as a :class:`CommunityModerationAction`
    row of ``action_type = "appeal_submitted"``. The
    ``actor_user_id`` is the user's ``users.id`` (the same column
    the moderator decisions use — there is no separate "target
    author" identity on the case row).
    """
    if case.appeal_state is not None:
        raise AppealAlreadySubmitted(
            f"case {case.public_id} already has appeal_state={case.appeal_state!r}"
        )

    case.appeal_state = APPEAL_STATE_SUBMITTED
    case.updated_at = now

    _record_action(
        db,
        case=case,
        action_type=ACTION_TYPE_APPEAL_SUBMITTED,
        from_state=case.state,
        to_state=case.state,
        actor_type=ACTOR_TYPE_HUMAN_MODERATOR,
        actor_user_id=submitted_by_user_id,
        reason=reason,
        evidence=None,
        now=now,
    )
    return case


def resolve_appeal(
    db: Session,
    case: CommunityModerationCase,
    *,
    resolver_user_id: int,
    verdict: str,
    reason: str,
    now: datetime,
) -> CommunityModerationCase:
    """Resolve an appeal. ``verdict`` is ``"upheld"`` or
    ``"overturned"``.

    * ``upheld`` reverts the case to ``"visible"`` (the D6
      appeal-upheld recovery path).
    * ``overturned`` keeps the current state and just marks the
      appeal as resolved. The case stays closed.

    The "independent reviewer" rule from ADR 0425 §D6 lives in the
    runbook, NOT in code — every action row carries
    ``actor_user_id`` so the rule is auditable from the audit
    chain.
    """
    if verdict not in {"upheld", "overturned"}:
        raise InvalidAppealVerdict(
            f"verdict must be 'upheld' or 'overturned', got {verdict!r}"
        )
    if not is_moderator(db, resolver_user_id):
        raise NotAModerator(
            f"user {resolver_user_id} is not a moderator"
        )
    if case.appeal_state != APPEAL_STATE_SUBMITTED:
        raise NoOpenAppeal(
            f"case {case.public_id} has no live appeal (state={case.appeal_state!r})"
        )

    from_state = case.state
    if verdict == "upheld":
        # The D3 ``removed → visible`` path is reserved for the
        # appeal-upheld flow. ``overturned`` keeps the case in
        # its current state.
        case.state = MODERATION_CASE_STATE_VISIBLE
        # Re-open the case for the D2 one-open-case-per-target
        # invariant — an upheld appeal restores the target to the
        # queue in ``visible`` state.
        case.is_open = True

    case.appeal_state = APPEAL_STATE_RESOLVED
    case.updated_at = now

    _record_action(
        db,
        case=case,
        action_type=ACTION_TYPE_APPEAL_RESOLVED,
        from_state=from_state,
        to_state=case.state,
        actor_type=ACTOR_TYPE_HUMAN_MODERATOR,
        actor_user_id=resolver_user_id,
        reason=reason,
        evidence={"verdict": verdict},
        now=now,
    )
    return case


# ---------------------------------------------------------------------------
# D7 — content_visibility_for_state (PURE)
# ---------------------------------------------------------------------------


def content_visibility_for_state(state: str, *, viewer_is_author: bool) -> str:
    """Return the content-visibility level for ``state``.

    This is a PURE function — no DB, no FastAPI, no global state.
    The Kör 19 / Kör 16 / Kör 11 deferred-wiring pattern (ADR 0410 /
    0412) — the function exists and is tested today, a future
    wiring round will call it from the feed / post / comment
    routers.

    * ``visible`` → ``"full"`` (everyone).
    * ``limited`` → ``"limited"`` (visible with a client-side
      warning banner — the banner itself is a Flutter concern).
    * ``removed`` → ``"hidden"`` to the public; ``"hidden_except_author"``
      to the author themselves (the §18.1 "nem teljesen törölt"
      rule — the row stays in the DB, only the visibility narrows).
    * ``author_only`` → ``"hidden_except_author"`` to everyone.
    * ``pending_review`` → ``"full"`` (the review-along state is
      visible to the public until a moderator moves it).

    A6 measure-matrix cell — the function is called directly with
    every state value, no setup.
    """
    if state == MODERATION_CASE_STATE_VISIBLE:
        return VISIBILITY_FULL
    if state == MODERATION_CASE_STATE_LIMITED:
        return VISIBILITY_LIMITED
    if state == MODERATION_CASE_STATE_PENDING_REVIEW:
        return VISIBILITY_FULL
    if state == MODERATION_CASE_STATE_REMOVED:
        return VISIBILITY_HIDDEN_EXCEPT_AUTHOR if viewer_is_author else VISIBILITY_HIDDEN
    if state == MODERATION_CASE_STATE_AUTHOR_ONLY:
        return VISIBILITY_HIDDEN_EXCEPT_AUTHOR
    raise ValueError(f"unknown case state: {state!r}")


# ---------------------------------------------------------------------------
# Internal helper — the action audit INSERT.
# ---------------------------------------------------------------------------


def _record_action(
    db: Session,
    *,
    case: CommunityModerationCase,
    action_type: str,
    from_state: str | None,
    to_state: str | None,
    actor_type: str,
    actor_user_id: int | None,
    reason: str | None,
    evidence: dict[str, Any] | None,
    now: datetime,
) -> CommunityModerationAction:
    """Insert a single :class:`CommunityModerationAction` row.

    INSERT-only. There is intentionally NO public ``update_action``
    or ``delete_action`` function exported by this module — the
    A3 measure-matrix cell exploits that absence. The function is
    private to this module.
    """
    row = CommunityModerationAction(
        case_id=case.id,
        action_type=action_type,
        from_state=from_state,
        to_state=to_state,
        actor_type=actor_type,
        actor_user_id=actor_user_id,
        reason=reason,
        evidence_json=json.dumps(evidence, separators=(",", ":")) if evidence else None,
        created_at=now,
    )
    db.add(row)
    db.flush()
    return row


# ---------------------------------------------------------------------------
# Query helpers (read-only)
# ---------------------------------------------------------------------------


def get_case_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityModerationCase | None:
    """Resolve a case row by its wire-visible ``public_id``. Used by
    the router before every write.
    """
    return db.execute(
        select(CommunityModerationCase).where(
            CommunityModerationCase.public_id == public_id
        )
    ).scalars().first()


def list_case_actions(
    db: Session, case: CommunityModerationCase
) -> list[CommunityModerationAction]:
    """Return the case's audit rows, newest first."""
    return list(
        db.execute(
            select(CommunityModerationAction)
            .where(CommunityModerationAction.case_id == case.id)
            .order_by(
                CommunityModerationAction.created_at.desc(),
                CommunityModerationAction.id.desc(),
            )
        ).scalars()
    )


def list_open_cases(
    db: Session, *, limit: int = 100
) -> list[CommunityModerationCase]:
    """Return the queue — open cases ordered by priority, then
    opened_at. Used by the ``GET /moderation/cases`` endpoint.
    """
    return list(
        db.execute(
            select(CommunityModerationCase)
            .where(CommunityModerationCase.is_open.is_(True))
            .order_by(
                CommunityModerationCase.priority_score.desc(),
                CommunityModerationCase.opened_at.desc(),
                CommunityModerationCase.id.desc(),
            )
            .limit(limit)
        ).scalars()
    )


__all__ = [
    "ALLOWED_TRANSITIONS",
    "AppealAlreadySubmitted",
    "AutomationCannotEnforce",
    "AUTOMATION_ALLOWED_TO_STATES",
    "CaseNotFound",
    "CLOSED_STATES",
    "InvalidAppealVerdict",
    "InvalidStateTransition",
    "ModerationActionSummary",
    "ModerationCaseSummary",
    "ModerationError",
    "NoOpenAppeal",
    "NotAModerator",
    "PRIORITY_WEIGHT_ACCOUNT_HISTORY",
    "PRIORITY_WEIGHT_AUTOMATION_CONFIDENCE",
    "PRIORITY_WEIGHT_REPORT_COUNT",
    "VISIBILITY_FULL",
    "VISIBILITY_HIDDEN",
    "VISIBILITY_HIDDEN_EXCEPT_AUTHOR",
    "VISIBILITY_LIMITED",
    "apply_moderator_decision",
    "compute_priority_score",
    "content_visibility_for_state",
    "get_case_by_public_id",
    "get_or_create_case",
    "is_moderator",
    "list_case_actions",
    "list_open_cases",
    "record_automation_signal",
    "resolve_appeal",
    "submit_appeal",
]