"""SQLAlchemy ORM model for community challenge results (E09-R22,
ADR 0417).

The verified-result row — one row per participant's submitted
challenge result. The table is the persistence side of the Kör 5
``submitResult`` repository contract; the server is the sole
authority on the ``verification_state`` and on the
``community_challenge_participants.best_metric_value`` projection
(D5).

The model intentionally mirrors the Kör 21 ``CommunityChallengeInvite``
shape — wire-string allowlist ``verification_state`` + a CHECK
constraint listing the known values, plain ``String`` columns, and
the DB-level defensive safety net. The transition graph
(``pending → verified | unverified | rejected | review``) is
enforced at the service layer (``challenge_verification_service``)
through a single conditional UPDATE + rowcount check, NOT a
DB-level constraint — mirroring the Kör 21 invite state machine.

* **No client-issued state (§5.1).** The client NEVER carries
  ``verified`` or ``rank`` on the wire — the request body only has
  ``metric_value``, ``source_event_id`` and ``idempotency_key``.
  The reason-code is server-generated.

* **Replay-dedup (A1, D2).** ``UNIQUE(participant_id,
  source_event_id)`` is the load-bearing construct. A replay INSERT
  raises ``IntegrityError``; the service catches it and re-reads
  the original row (mirrors the Kör 11 ``post_service.create_post``
  pattern).

* **Server-issued nonce (D3).** ``nonce`` is a server-generated
  ``uuid4``; ``nonce_expires_at`` is the bookkeeping TTL the A4
  cell exercises.

* **Migration side-effect import.** Importing this module is
  load-bearing for the migration's ``Base.metadata`` registration
  (the round-12 migration-contract guard).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Wire-string vocabulary — mirrors the §3 5-value enum. The wire
# decoder on the Flutter side collapses unknown values to ``null``
# (the A3 measure-matrix cell of the Kör 5 contract), so the
# backend can add a new value without a breaking change.
# ---------------------------------------------------------------------------

CHALLENGE_RESULT_STATE_PENDING: str = "pending"
CHALLENGE_RESULT_STATE_VERIFIED: str = "verified"
CHALLENGE_RESULT_STATE_UNVERIFIED: str = "unverified"
CHALLENGE_RESULT_STATE_REJECTED: str = "rejected"
CHALLENGE_RESULT_STATE_REVIEW: str = "review"

CHALLENGE_RESULT_STATE_ALLOWLIST: frozenset[str] = frozenset(
    {
        CHALLENGE_RESULT_STATE_PENDING,
        CHALLENGE_RESULT_STATE_VERIFIED,
        CHALLENGE_RESULT_STATE_UNVERIFIED,
        CHALLENGE_RESULT_STATE_REJECTED,
        CHALLENGE_RESULT_STATE_REVIEW,
    }
)


def is_allowed_challenge_result_state(value: str) -> bool:
    """True when ``value`` is one of the 5 wire result states (D1)."""
    return value in CHALLENGE_RESULT_STATE_ALLOWLIST


# ---------------------------------------------------------------------------
# CommunityChallengeResult — one row per (participant, source_event_id).
# ---------------------------------------------------------------------------


class CommunityChallengeResult(Base):
    """A single verified-result submission row.

    Created by ``services.challenge_verification_service.submit_result``
    on the first INSERT attempt — a replay INSERT lands on the
    existing row via the §A1 ``UNIQUE(participant_id,
    source_event_id)`` surface (mirrors the Kör 11 post-create
    pattern).

    The row is mirrored onto ``community_challenge_participants`` via
    a conditional UPDATE inside ``challenge_verification_service``
    — the ``best_metric_value`` projection lives on the Kör 21
    participant row, never on this row.
    """

    __tablename__ = "community_challenge_results"

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
    participant_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_challenge_participants.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Domain-side replay surface (A1, D2). The composite
    # unique key uses ``(participant_id, source_event_id)``.
    source_event_id: Mapped[str] = mapped_column(
        String(length=128), nullable=False
    )
    # HTTP-szintű retry surface — same shape as the Kör 11
    # ``CommunityPost`` and Kör 21 ``CommunityChallengeInvite``
    # precedent.
    idempotency_key: Mapped[str | None] = mapped_column(
        String(length=128), nullable=True
    )
    # The metric value. The structural range is
    # ``[0, 1_000_000]`` — the MÁR élő kliens-kontraktus
    # tükre (D4, ``kCommunityChallengeMetricMinValue`` /
    # ``kCommunityChallengeMetricMaxValue``).
    metric_value: Mapped[int] = mapped_column(Integer, nullable=False)
    # The server-authoritative verification state.
    verification_state: Mapped[str] = mapped_column(
        String(length=16), nullable=False
    )
    # Audit reason-code — NULL on ``pending``; populated on
    # terminal states (A8). Values are short, machine-
    # readable identifiers (``metric_out_of_range``,
    # ``invite_not_active``, ``version_mismatch``,
    # ``nonce_expired``, ``already_submitted``, …).
    reason_code: Mapped[str | None] = mapped_column(
        String(length=64), nullable=True
    )
    # Server-issued nonce — stamped on the row at INSERT
    # time, never returned to the client (D3). The A4 cell
    # uses ``nonce_expires_at`` directly, fabrikálva a
    # service-en keresztül.
    nonce: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), nullable=False
    )
    # Server-side TTL. A ``pending`` / ``review`` row whose
    # döntés nem születik meg ezen idő előtt véglegesen
    # lejárt; a service a ``nonce_expires_at <= now``
    # check-kor ``rejected``, ``reason_code="nonce_expired"``
    # döntéssel tér vissza.
    nonce_expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    submitted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # ``decided_at`` is the terminal-state stamp. NULL on
    # ``pending`` rows; lands the moment the service
    # commits a ``verified | unverified | rejected | review``
    # decision.
    decided_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint(
            "public_id",
            name="uq_community_challenge_results_public_id",
        ),
        # §A1 / D2 replay-dedup — composite unique keyed on
        # (participant, source_event_id). The SAME local
        # practice event cannot produce multiple result
        # rows.
        UniqueConstraint(
            "participant_id",
            "source_event_id",
            name="uq_community_challenge_results_replay",
        ),
        # DB-level defensive safety net — the service
        # enforces the transition graph (D2) via a
        # conditional UPDATE + rowcount check; this CHECK
        # only ensures the row carries one of the five
        # known wire values.
        CheckConstraint(
            "verification_state IN ("
            "'pending','verified','unverified',"
            "'rejected','review'"
            ")",
            name="ck_community_challenge_results_state_known",
        ),
        # The per-participant history.
        Index(
            "ix_community_challenge_results_participant_submitted",
            "participant_id",
            "submitted_at",
            "id",
        ),
        # The replay probe — a non-unique composite index
        # the service uses for the IntegrityError → re-read
        # path (mirrors the Kör 21
        # ``ix_community_challenge_invites_idempotency_key``
        # precedent).
        Index(
            "ix_community_challenge_results_replay_probe",
            "participant_id",
            "source_event_id",
        ),
    )


__all__ = [
    "CHALLENGE_RESULT_STATE_ALLOWLIST",
    "CHALLENGE_RESULT_STATE_PENDING",
    "CHALLENGE_RESULT_STATE_REJECTED",
    "CHALLENGE_RESULT_STATE_REVIEW",
    "CHALLENGE_RESULT_STATE_UNVERIFIED",
    "CHALLENGE_RESULT_STATE_VERIFIED",
    "CommunityChallengeResult",
    "is_allowed_challenge_result_state",
]
