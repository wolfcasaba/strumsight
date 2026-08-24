"""Moderation queue, enforcement and appeal ORM models — E09-R27, ADR 0425.

Three tables land here, each representing one of the §D-decisions:

* :class:`CommunityModerator` — D1, the moderator-identity source.
  Separate table on purpose: ``User`` / ``CommunityProfile`` are in
  the brief's forbidden zone, so a ``role`` / ``is_admin`` column
  there would have been an H3 halt (ADR 0087 §2). This table is the
  ONLY path to site-wide moderator privileges. A future round that
  needs admin-grade access reads it via the ``user_id`` lookup.

* :class:`CommunityModerationCase` — D2/D3/D6/D8, the case row.
  Plain ``String`` ``state`` and ``appeal_state`` columns (ADR 0398 §1,
  the project-wide plain-String value-set pattern). ``target_type`` /
  ``target_id`` mirror :class:`CommunityReport`'s shape (Kör 26, ADR
  0422 §5.1) so the queue read-path join reuses the existing composite
  index. ``priority_score`` is a non-negative ``Integer`` (D8) — the
  formula itself lives in the service layer.

* :class:`CommunityModerationAction` — D5, the immutable audit row.
  No ``updated_at`` column — the missing column is the structural
  signal that the row never receives an UPDATE. The
  ``case_service.py`` module deliberately exports no
  ``update_action`` / ``delete_action`` function (A3 measure-matrix).

**§6.1 valódi-sértés próba (D4, brief §6.1):** the
:func:`community.case_service.record_automation_signal` function has
NO ``to_state`` parameter — the destination state is fixed inside
the function body to ``{"limited", "pending_review"}``, and any
attempt by the caller to expand the set will fail the A4 cell.

The three tables deliberately have NO relationship() back to
:class:`CommunityProfile` from the reporter side (the ``reporter``
identity is NOT stored on the case row — only on the
``CommunityReport`` rows it joins via ``target_type`` + ``target_id``
when it needs to compute ``account-history``, D7). The §5.1
retaliation-risk invariant from ADR 0422 is structural: the case
has no reporter FK at all.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# State / appeal / actor / action-type literals — the value sets are
# enforced at the service layer (ADR 0398 §1), NOT at the DB.
# ---------------------------------------------------------------------------

# Case state — five snake_case values mirroring the §18.1 Dart
# ``ModerationState`` enum (visible / limited / pendingReview /
# removed / authorOnly). D3.
MODERATION_CASE_STATE_VISIBLE: str = "visible"
MODERATION_CASE_STATE_LIMITED: str = "limited"
MODERATION_CASE_STATE_PENDING_REVIEW: str = "pending_review"
MODERATION_CASE_STATE_REMOVED: str = "removed"
MODERATION_CASE_STATE_AUTHOR_ONLY: str = "author_only"

MODERATION_CASE_STATES: frozenset[str] = frozenset(
    {
        MODERATION_CASE_STATE_VISIBLE,
        MODERATION_CASE_STATE_LIMITED,
        MODERATION_CASE_STATE_PENDING_REVIEW,
        MODERATION_CASE_STATE_REMOVED,
        MODERATION_CASE_STATE_AUTHOR_ONLY,
    }
)

# Appeal state — NULL → "submitted" → "resolved". D6.
APPEAL_STATE_SUBMITTED: str = "submitted"
APPEAL_STATE_RESOLVED: str = "resolved"

# Actor type — D5. "automation" signals have actor_user_id NULL;
# "human_moderator" actions always carry a non-null moderator_user_id.
ACTOR_TYPE_AUTOMATION: str = "automation"
ACTOR_TYPE_HUMAN_MODERATOR: str = "human_moderator"

# Action type — D5.
ACTION_TYPE_AUTOMATION_SIGNAL: str = "automation_signal"
ACTION_TYPE_MODERATOR_DECISION: str = "moderator_decision"
ACTION_TYPE_APPEAL_SUBMITTED: str = "appeal_submitted"
ACTION_TYPE_APPEAL_RESOLVED: str = "appeal_resolved"


class CommunityModerator(Base):
    """Site-wide moderator identity — D1.

    The table is intentionally narrow: a ``user_id`` FK, a
    ``granted_at`` timestamp, and an audit ``granted_by_user_id``
    (NULL when the row was created by a seed / migration).

    The FK ``users.id`` is the auth-ladder join surface; the router
    does ``db.query(CommunityModerator).filter_by(user_id=
    current_user.id).one_or_none()`` and treats ``None`` as 403
    (A1 measure-matrix cell).

    ``ondelete="CASCADE"`` mirrors the existing ``User``-anchored
    tables so a future user deletion cleans up its moderator grant in
    one transaction (the round-120 / ADR 0060 §8 precedent).
    """

    __tablename__ = "community_moderators"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
    )
    # Audit — who granted. NULL for seed / migration. NOT a ForeignKey:
    # the row must survive the deletion of the granting user (the
    # Kör 19 ``reviewer_id`` precedent — ADR 0412 §D5).
    granted_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=True,
    )

    __table_args__ = (
        Index(
            "ix_community_moderators_user_id",
            "user_id",
            unique=True,
        ),
    )


class CommunityModerationCase(Base):
    """A moderation case row — D2/D3/D6/D8.

    The row carries:

    * ``public_id`` — the wire-visible identifier.
    * ``target_type`` + ``target_id`` — the case is keyed on the pair
      (mirrors ``CommunityReport``'s shape). The pair has NO FK so
      the target can be a post / comment / profile / media (the Kör 26
      ADR 0422 §5.1 precedent).
    * ``state`` — one of the five :data:`MODERATION_CASE_STATES`.
    * ``appeal_state`` — NULL / "submitted" / "resolved". The
      "single appeal per case" invariant (A5) lives here.
    * ``priority_score`` — the queue-priority number (D8). Recomputed
      by :func:`get_or_create_case` and
      :func:`record_automation_signal`; the formula lives in the
      service layer (the column is the persistence).
    * ``is_open`` — a denormalized, indexable flag set to ``False``
      only when ``state in {"removed", "author_only"}`` AND no live
      appeal exists. The "one open case per target" invariant (D2) is
      enforced via this column + a service-layer guard.
    * ``opened_at`` / ``updated_at`` — timestamps.

    The table has NO reporter FK (§5.1 retaliation-risk invariant
    from ADR 0422 D2 — the case is NOT a target-view response).
    """

    __tablename__ = "community_moderation_cases"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        unique=True,
        index=True,
        default=uuid.uuid4,
        nullable=False,
    )
    target_type: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
    )
    target_id: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
    )
    state: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=MODERATION_CASE_STATE_VISIBLE,
        server_default=MODERATION_CASE_STATE_VISIBLE,
    )
    appeal_state: Mapped[str | None] = mapped_column(
        String(32),
        nullable=True,
    )
    priority_score: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
    )
    is_open: Mapped[bool] = mapped_column(
        # Stored as Integer 0/1 with a default — see
        # :class:`CommunityReport.target_deleted_at_submit` for the
        # same Boolean/0-1 pattern.
        nullable=False,
        default=True,
        server_default="1",
    )
    opened_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )

    __table_args__ = (
        # The queue-priority read path — Kör 27 case list ordered by
        # descending priority then opened_at.
        Index(
            "ix_community_moderation_cases_priority",
            "is_open",
            "priority_score",
            "opened_at",
            "id",
        ),
        # The "find existing open case for this target" read path —
        # the D2 one-open-case-per-target invariant.
        Index(
            "ix_community_moderation_cases_target_open",
            "target_type",
            "target_id",
            "is_open",
        ),
    )


class CommunityModerationAction(Base):
    """An immutable audit row — D5.

    Each row is INSERT-only. The :mod:`community.moderation.case_service`
    module exports no ``update_action`` / ``delete_action`` function;
    the A3 measure-matrix cell exploits this absence by reading
    ``hasattr(case_service, "update_action") is False`` directly.

    The wire-visible identifier is ``public_id``; the row's internal
    ``id`` is the join surface for downstream tooling. ``actor_user_id``
    is NULL when ``actor_type = "automation"`` and is the
    moderator's ``users.id`` otherwise (D4 / D5).

    ``from_state`` / ``to_state`` are NULL for non-state-changing
    actions (e.g. ``appeal_submitted`` from a ``visible`` case carries
    ``from_state = "visible"`` and ``to_state = "visible"`` — the
    appeal is a parallel flow, not a state transition).
    """

    __tablename__ = "community_moderation_actions"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    public_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        unique=True,
        index=True,
        default=uuid.uuid4,
        nullable=False,
    )
    case_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_moderation_cases.id", ondelete="CASCADE"),
        nullable=False,
    )
    action_type: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
    )
    from_state: Mapped[str | None] = mapped_column(
        String(32),
        nullable=True,
    )
    to_state: Mapped[str | None] = mapped_column(
        String(32),
        nullable=True,
    )
    actor_type: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
    )
    actor_user_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=True,
    )
    reason: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )
    # A structured evidence payload — for ``automation_signal`` rows
    # this carries ``{"provider": "...", "provider_version": "...",
    # "confidence": 0.0..1.0}``; for ``appeal_*`` rows it carries the
    # appeal verdict (``"upheld"`` / ``"overturned"``); for
    # ``moderator_decision`` rows it is NULL (the decision is in the
    # reason / from_state / to_state triple).
    evidence_json: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        nullable=False,
    )
    # NOTE: no ``updated_at`` column. A3 — the absence is the
    # structural signal that the row never receives an UPDATE.

    __table_args__ = (
        # The case-history read path — newest first within a case.
        Index(
            "ix_community_moderation_actions_case_created",
            "case_id",
            "created_at",
            "id",
        ),
    )


__all__ = [
    "ACTION_TYPE_APPEAL_RESOLVED",
    "ACTION_TYPE_APPEAL_SUBMITTED",
    "ACTION_TYPE_AUTOMATION_SIGNAL",
    "ACTION_TYPE_MODERATOR_DECISION",
    "ACTOR_TYPE_AUTOMATION",
    "ACTOR_TYPE_HUMAN_MODERATOR",
    "APPEAL_STATE_RESOLVED",
    "APPEAL_STATE_SUBMITTED",
    "CommunityModerationAction",
    "CommunityModerationCase",
    "CommunityModerator",
    "MODERATION_CASE_STATE_AUTHOR_ONLY",
    "MODERATION_CASE_STATE_LIMITED",
    "MODERATION_CASE_STATE_PENDING_REVIEW",
    "MODERATION_CASE_STATE_REMOVED",
    "MODERATION_CASE_STATE_VISIBLE",
    "MODERATION_CASE_STATES",
]
