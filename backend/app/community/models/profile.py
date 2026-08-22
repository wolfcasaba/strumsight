"""ORM models for the Community (Epic 9) module.

E09-R02, ADR 0396 §1–2. The schema follows the ``public UUID + bigint PK``
pair explicitly required by the brief §8 1. lépés:

* ``id``: BigInteger, autoincrement, **internal-only** — never serialized in
  API responses. This is a deliberate departure from the existing
  ``User`` / ``UserSettings`` Integer-PK pattern (ADR 0396 §1 indoklás):
  the Community surface publishes a public identifier only.
* ``public_id``: ``Uuid(as_uuid=True)`` (SQLAlchemy 2.0 dialect-portable,
  ``CHAR(32)`` on SQLite, native ``UUID`` on PostgreSQL), default
  ``uuid.uuid4``, ``unique=True, index=True``. A6 (public UUID is unique
  and non-sequential) lives here.

The 1:1 ``user_id`` / ``profile_id`` constraints are enforced at the
database level (``UNIQUE``), not at the application layer — ADR 0396 §2.
This is what A7 (user–profile 1:1 constraint kikényszerítve) measures.

There is no backfill here, and no ``get_or_create`` helper. Per ADR 0395
Következmények and ADR 0396 §5.1, profile rows are created only by an
explicit onboarding endpoint (a future Kör 6 scope item). This round ships
the schema and a flag-gated read/stub surface only.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityProfile(Base):
    """A user's Community profile — at most one per ``users`` row.

    The ``user_id`` unique constraint is what enforces the 1:1 invariant
    (A7) — DB-level, not application-level — and the matching
    ``ondelete="CASCADE"`` mirrors the existing ``user_settings`` rule so a
    parent ``users`` deletion cleans up its Community row in one transaction
    (round 120 / ADR 0060 §8).

    Profile creation is explicit and opt-in: there is no backfill, no
    implicit creation on user signup, and no ``get_or_create`` helper.
    """

    __tablename__ = "community_profiles"

    id: Mapped[int] = mapped_column(
        # BigInteger in production (PostgreSQL bigserial) but the SQLite
        # dialect does not auto-increment BIGINT PKs; variant to Integer keeps
        # the round-gate green while preserving the BigInteger identity on
        # PostgreSQL. ADR 0396 §1 keeps ``BigInteger`` as the canonical type.
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
    user_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    # Display-name is intentionally nullable: a profile row is created on
    # explicit onboarding (a future Kör 6 surface), and the display name is
    # filled in by the user at that point. A ``NOT NULL`` here would force
    # either a placeholder string ("") or a backfill — both forbidden by
    # the explicit-action invariant (ADR 0396 §5.1).
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    privacy_settings: Mapped["CommunityPrivacySettings"] = relationship(
        back_populates="profile",
        uselist=False,
        cascade="all, delete-orphan",
    )


class CommunityPrivacySettings(Base):
    """Per-profile privacy preferences — at most one per ``community_profiles`` row.

    The granular privacy taxonomy (which fields are public / follower-only /
    private) is Kör 6+ scope per ADR 0396 §2. This round ships the table
    skeleton + the 1:1 ``profile_id`` constraint; the ``updated_at`` column
    exists so the row is never empty in production (a "minimum-viable" row
    shape that the onboarding endpoint can later augment).
    """

    __tablename__ = "community_privacy_settings"

    id: Mapped[int] = mapped_column(
        # See CommunityProfile for the BigInteger/Integer-on-SQLite variant
        # rationale — same identity, same autoincrement-on-SQLite semantics.
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
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )

    profile: Mapped[CommunityProfile] = relationship(back_populates="privacy_settings")
