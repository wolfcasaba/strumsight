"""SQLAlchemy ORM model for Community posts (E09-R11, ADR 0405).

The first real content-endpoint surface in the Community module —
post lifecycle (create / get / patch / soft-delete) is owned by the
Kör 11 service; the row shape is here.

The schema follows the project-wide ``public UUID + bigint PK``
pattern (ADR 0396 §1) and reuses every existing convention:

* ``id`` is BigInteger internally; the SQLite variant flips to
  Integer so in-memory test engines autoincrement reliably (the same
  ``BigInteger().with_variant(Integer, 'sqlite')`` seam used by
  CommunityProfile / CommunityPrivacySettings / the Kör 5–8 follow /
  safety tables).

* ``public_id`` is ``Uuid(as_uuid=True)``, ``unique=True``,
  ``index=True``, default ``uuid.uuid4``. The wire shape only ever
  carries this — the internal ``id`` is the join surface.

* ``profile_id`` is the internal FK to ``community_profiles.id``,
  ``ondelete='CASCADE'``. A profile deletion cleans up its posts in
  the same transaction (the Kör 5 follow-graph precedent).

* ``audience`` is a plain ``String`` per the project-wide
  ``visibility`` / ``audience_default`` pattern (ADR 0398 §1). The
  value set is enforced at the Pydantic / domain layer; the DB does
  NOT constrain it (``server_default='public'`` keeps a populated
  table safe).

* ``club_id`` is a nullable BigInteger with **NO** ForeignKey — the
  ``community_clubs`` table is Kör 24 scope (pre-flight §0.0 D6).
  This round only reserves the column.

* ``body`` is ``String(5000)`` matching the Pydantic ``max_length``
  (brief §0.0 D9). The DB length is a defensive bound, not the
  primary validation — the request layer is.

* Artifact columns (``artifact_type``, ``artifact_schema_version``,
  ``artifact_payload``) are NULLABLE: the post may be text-only.
  ``artifact_payload`` is the JSON-encoded validated envelope from
  ``schemas/artifacts.parse_share_artifact`` (ADR 0404, brief
  §0.0 D10). The typed sibling columns mirror the validated
  envelope's ``.type`` / ``.schema_version`` so the Kör 13 feed query
  can filter / facet without re-parsing JSON.

* ``moderation_state`` is a plain ``String`` with
  ``server_default='visible'``. The active moderation workflow is
  Kör 27/28 scope (brief §0.0 D8); Kör 11 GET/PATCH/DELETE treats
  anything != ``'visible'`` as the D7 uniform 404.

* ``idempotency_key`` is a nullable ``String``. The pair
  ``UNIQUE(profile_id, idempotency_key)`` is the brief §0.0 D4
  idempotency invariant: a retry with the SAME key hits the existing
  row, a post WITHOUT a key remains allowed (SQLite allows multiple
  NULLs in a UNIQUE column). The shared
  ``community_idempotency_records`` table is a future round's call
  when a SECOND endpoint needs the same dedup.

* ``created_at`` / ``updated_at`` are ``DateTime(timezone=True)``.
  ``updated_at`` doubles as the resource-version token (ADR 0398 §6
  precedent: Kör 4's privacy row uses the same single-column
  optimistic-concurrency pattern; brief §0.0 D3 — NO separate
  ``version`` column).

* ``deleted_at`` is the soft-delete tombstone (brief §5.3, D7
  uniform 404).

Importing this module is load-bearing for the migration's
side-effect import: it registers the table with ``Base.metadata`` so
``alembic compare_metadata`` (the round-12 migration-contract guard)
sees the table as part of the expected schema.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# Body length cap, mirrored in Pydantic through ``Field(max_length=...)``.
# Pre-flight §0.0 D9 records the choice as the §3 "body-limit" szó
# szerinti kielégítéséhez szükséges konkrét szám.
POST_BODY_MAX_LENGTH: int = 5000

# Two-value moderation field (pre-flight §0.0 D8). The active
# workflow is Kör 27/28 scope; Kör 11 only consumes the field, never
# writes a value other than the default.
MODERATION_STATE_VISIBLE: str = "visible"
MODERATION_STATE_REMOVED: str = "removed"


class CommunityPost(Base):
    """A single piece of Community content.

    Lifecycle is owned by ``services.post_service``; the model here
    is the persisted shape. There is **no** back-relationship to
    ``CommunityProfile`` from Kör 2 — the foreign-key join is
    ad-hoc per query (the Kör 13 feed will introduce a real
    relationship once the pagination shape is decided).
    """

    __tablename__ = "community_posts"

    id: Mapped[int] = mapped_column(
        # Same BigInteger / Integer-on-SQLite variant rationale as
        # ``CommunityProfile`` (ADR 0396 §1).
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
        nullable=False,
    )
    audience: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default="public",
        server_default="public",
    )
    # ``club_id`` is a nullable BigInteger with NO ForeignKey — the
    # ``community_clubs`` table is Kör 24 scope (pre-flight §0.0 D6).
    # We intentionally do NOT add ``ForeignKey(...)`` here.
    club_id: Mapped[int | None] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        nullable=True,
    )
    body: Mapped[str] = mapped_column(
        String(length=POST_BODY_MAX_LENGTH),
        nullable=False,
    )
    # Artifact columns — NULL when the post is text-only.
    artifact_type: Mapped[str | None] = mapped_column(String, nullable=True)
    artifact_schema_version: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    artifact_payload: Mapped[dict[str, Any] | None] = mapped_column(
        JSON, nullable=True
    )
    moderation_state: Mapped[str] = mapped_column(
        String,
        nullable=False,
        default=MODERATION_STATE_VISIBLE,
        server_default=MODERATION_STATE_VISIBLE,
    )
    idempotency_key: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # ``updated_at`` doubles as the resource-version token. There is
    # NO separate ``version`` column (pre-flight §0.0 D3,
    # ADR 0398 §6 — the Kör 4 privacy-row precedent).
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow,
        onupdate=_utcnow,
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


__all__ = [
    "CommunityPost",
    "MODERATION_STATE_REMOVED",
    "MODERATION_STATE_VISIBLE",
    "POST_BODY_MAX_LENGTH",
]
