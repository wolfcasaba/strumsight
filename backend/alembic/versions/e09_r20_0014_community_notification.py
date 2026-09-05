"""Add community_notifications table (E09-R20, ADR 0414).

Revision ID: e09_r20_0014
Revises: e09_r19_0013
Create Date: 2026-08-23

The first notification-inbox table — one row per inbox item. The push
gateway is a separate concern (a provider-neutral interface that lives
in ``backend/app/community/notifications/push_gateway.py``); the
``community_notifications`` table is the inbox-side ground truth
(ADR 0414 §D1 — the inbox is the source of truth, push is delivery).

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Recipient + type + actor + entity.** The four content axes. The
  ``recipient_profile_id`` is the FK to ``community_profiles`` with
  CASCADE — a profile hard-delete clears its inbox in the same
  transaction (the project-wide pattern, ADR 0396 §1). The
  ``actor_profile_id`` is also a FK to ``community_profiles`` with
  CASCADE, but NULLABLE — system events (e.g. a moderation-decision
  notification, a security alert) have no actor.

* **Entity pointer (A5).** ``entity_type`` + ``entity_id`` carry the
  opaque route data the inbox tap-action reads. The pair is the
  aggregation key for the A2 reaction-burst window. Both columns
  are NULLABLE: a system event with no entity to point at leaves
  them NULL (a "purely informational" notification, the Kör 5 entity
  precedent).

* **Dedup key (A7).** A nullable string UNIQUE-constrained per
  ``(recipient_profile_id, dedup_key)``. A retry with the same
  ``dedup_key`` is rejected by the DB; the service catches
  ``IntegrityError`` and re-reads the existing row (the
  ``reaction_service.set_reaction`` pattern). A NULL ``dedup_key``
  is non-conflicting in SQL UNIQUE — system events that opt out of
  dedup pass through with NULL.

* **Aggregate count (A2).** A non-null integer default 1. The
  reaction-burst aggregation key is
  ``(recipient_profile_id, entity_type, entity_id)`` — the service
  scans the last 15 minutes and increments the count instead of
  inserting a new row (ADR 0414 §D3).

* **Read state.** A boolean ``is_read`` defaulting to false + a
  nullable ``read_at`` stamp. The mark-read service bumps both
  atomically (A3 race-test seam — the §6 / §6.1 measure-matrix
  pins consistency).

* **Localization keys (A1 payload redaction).** ``title_key`` and
  ``body_key`` are stored ON the row (not the localised text) — the
  push payload NEVER carries the localized text. The A1
  redaction invariant lives at the ``push_gateway`` boundary, but
  the row-level decision to store KEYS, not text, is what makes
  redaction structurally possible (the column doesn't exist for
  the payload to leak).

* **Cursor pagination.** The inbox list query orders by
  ``(created_at DESC, id DESC)`` per the project-wide
  ``(created_at, id)`` cursor pattern (Kör 8 / Kör 11 / Kör 13 /
  Kör 16). The composite index ``(recipient_profile_id,
  created_at, id)`` backs both the list and the unread-count
  aggregate.

The migration is STRICTLY ADDITIVE — no existing column, constraint,
or index on any prior table is touched. The single new table
``community_notifications`` is the entire E09-R20 schema delta.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the new table as part of the expected schema. The
# migration body itself does not rely on the model class — it
# uses raw ``sa.Column`` / ``op.create_table`` calls so the
# schema is migration-source-of-truth, not ORM-derived
# autogenerate.
from app.community.models.notification import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityNotification,
)

revision: str = "e09_r20_0014"
down_revision: str | Sequence[str] | None = "e09_r19_0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the E09-R20 ``community_notifications`` table."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_notifications",
        sa.Column("id", _bigint, nullable=False),
        # ``public_id`` is the wire surface — every cross-service
        # hop carries this, not the internal bigint. Same
        # project-wide pattern as ``CommunityPost`` /
        # ``CommunityProfile``.
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # Recipient — the inbox owner. CASCADE keeps the inbox
        # empty when the profile is hard-deleted.
        sa.Column(
            "recipient_profile_id",
            _bigint,
            nullable=False,
        ),
        # Actor — the profile that TRIGGERED the notification.
        # NULLABLE for system events (moderation-decision,
        # security-alert). CASCADE matches the recipient-side
        # semantics.
        sa.Column("actor_profile_id", _bigint, nullable=True),
        # Wire-string from the Kör 5 ``CommunityNotificationKind``
        # enum. The service allowlist (mirroring the Kör 15
        # ``REACTION_KIND_ALLOWLIST`` pattern) enforces the 10
        # valid values.
        sa.Column("type", sa.String(), nullable=False),
        # Localization keys — stored on the row, NOT localized
        # text. The push payload MUST NOT carry localised text
        # (A1 — privacy-sensitive redaction).
        sa.Column("title_key", sa.String(), nullable=False),
        sa.Column("body_key", sa.String(), nullable=True),
        # The entity pointer. ``entity_type`` carries the route
        # discriminator (``"post"``, ``"comment"``,
        # ``"follow_request"``, …); ``entity_id`` is the
        # stringified public_id of the entity. The pair is the
        # aggregation key for the A2 reaction-burst window.
        sa.Column("entity_type", sa.String(), nullable=True),
        sa.Column("entity_id", sa.String(length=64), nullable=True),
        # The A2 burst-aggregation count. Default 1; the service
        # increments instead of inserting for a new event in the
        # 15-minute window.
        sa.Column(
            "aggregate_count",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
        # Read state.
        sa.Column(
            "is_read",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        # A7 dedup key. UNIQUE per (recipient, dedup_key) — a
        # NULL dedup_key is non-conflicting in SQL.
        sa.Column("dedup_key", sa.String(length=128), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["recipient_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_notifications_recipient_profile",
        ),
        sa.ForeignKeyConstraint(
            ["actor_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_notifications_actor_profile",
        ),
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_notifications_public_id",
        ),
        # A7 idempotency surface.
        sa.UniqueConstraint(
            "recipient_profile_id",
            "dedup_key",
            name="uq_community_notifications_recipient_dedup",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    # The public-id wire surface — a single, unique index for the
    # ``WHERE public_id = ?`` lookup.
    op.create_index(
        "ix_community_notifications_public_id",
        "community_notifications",
        ["public_id"],
        unique=True,
    )
    # The inbox list + unread-count composite index. Backs
    # ``WHERE recipient_profile_id = ? ORDER BY created_at DESC,
    # id DESC`` (the project-wide cursor-pagination pattern) and
    # ``WHERE recipient_profile_id = ? AND is_read = 0`` (the
    # unread-count aggregate).
    op.create_index(
        "ix_community_notifications_recipient_created",
        "community_notifications",
        ["recipient_profile_id", "created_at", "id"],
        unique=False,
    )
    # The unread-count sub-aggregate — the (recipient, is_read)
    # sub-filter is hot on every inbox open.
    op.create_index(
        "ix_community_notifications_recipient_unread",
        "community_notifications",
        ["recipient_profile_id", "is_read"],
        unique=False,
    )
    # The A2 burst-aggregation lookup — a fresh reaction
    # searches for the (recipient, entity_type, entity_id) row
    # that is still inside the 15-minute window. The
    # ``recipient_profile_id`` leading column lets the planner
    # use the same access path as the inbox list.
    op.create_index(
        "ix_community_notifications_recipient_entity",
        "community_notifications",
        [
            "recipient_profile_id",
            "entity_type",
            "entity_id",
            "created_at",
        ],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the E09-R20 schema delta."""
    op.drop_index(
        "ix_community_notifications_recipient_entity",
        table_name="community_notifications",
    )
    op.drop_index(
        "ix_community_notifications_recipient_unread",
        table_name="community_notifications",
    )
    op.drop_index(
        "ix_community_notifications_recipient_created",
        table_name="community_notifications",
    )
    op.drop_index(
        "ix_community_notifications_public_id",
        table_name="community_notifications",
    )
    op.drop_table("community_notifications")
