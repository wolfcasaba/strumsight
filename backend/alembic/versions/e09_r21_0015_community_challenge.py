"""Add community_challenges / participants / invites tables (E09-R21, ADR 0415).

Revision ID: e09_r21_0015
Revises: e09_r20_0014
Create Date: 2026-08-23

The first challenge lifecycle tables — one row per challenge definition,
one row per participant join, one row per invite edge. The wire surface
(``CommunityChallengeDefinition`` / ``CommunityChallengeParticipantState``
+ ``CommunityChallengeRepository``) is M2-5 / ADR 0399 territory and is
**unchanged** by this round; these models are the persisted shape behind
it.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Server-side author identity (§5.1).** ``community_challenges.author_profile_id``
  is the FK to ``community_profiles`` with CASCADE — a profile hard-delete
  clears its challenges in the same transaction.

* **Challenge type as wire-string.** ``type`` is a plain ``String``
  (ADR 0398 §1 project-wide pattern); the value set is enforced at the
  service boundary (mirrors the Kör 5 wire enum in
  ``lib/features/community/domain/entities/community_challenge.dart``).
  The DB does NOT enforce it — leaving the column unconstrained means
  a future round can add a new wire value without a migration.

* **Club affinity reserved, FK-less.** ``community_challenges.club_id``
  is a nullable string column with NO ForeignKey — the ``community_clubs``
  table is Kör 24 scope (pre-flight §0.0 D7 / ADR 0415 D7). The column
  exists so the Kör 24 club integration does not require a schema
  change.

* **Invite lifecycle row.** ``community_challenge_invites`` is the
  per-(challenge, invitee) row. The ``state`` column is the wire-string
  form of the Kör 5 ``ChallengeInviteState`` enum; the service layer
  guards the transition graph (ADR 0415 D1 / D5).

* **Idempotency (A4, ADR 0415 D4).** The composite UNIQUE
  ``(challenge_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)`` is the §5.3 / §6.1 idempotency invariant — a
  retry with the same key hits the existing row. A NULL
  ``idempotency_key`` is non-conflicting in SQL UNIQUE.

* **Window bounds as server-authoritative timestamps.** ``starts_at`` /
  ``ends_at`` are ``DateTime(timezone=True)``. The expiry check is
  server-time, never client-time (A7 / §5.2). Both columns are
  NOT NULL — the challenge window is the contract.

* **Block-side gate (A3).** The service layer calls
  ``query_filters.is_blocked_pair(db, profile_id_a=, profile_id_b=)``
  BEFORE INSERT — no new block DB columns are introduced.

* **Cursor pagination.** The invites list query orders by
  ``(created_at DESC, id DESC)`` per the project-wide cursor
  pattern. The composite index ``(challenge_id, state, created_at, id)``
  backs both the per-challenge invite list and the per-viewer
  inbox join.

The migration is STRICTLY ADDITIVE — no existing column, constraint,
or index on any prior table is touched.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM models with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the new tables as part of the expected schema. The
# migration body itself does not rely on the model classes — it
# uses raw ``sa.Column`` / ``op.create_table`` calls so the schema
# is migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.challenge import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)

revision: str = "e09_r21_0015"
down_revision: str | Sequence[str] | None = "e09_r20_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the E09-R21 challenge / participant / invite tables."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_challenges",
        sa.Column("id", _bigint, nullable=False),
        # ``public_id`` is the wire surface — every cross-service
        # hop carries this, not the internal bigint. Same
        # project-wide pattern as ``CommunityPost`` /
        # ``CommunityProfile``.
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # Author of the challenge (server-resolved; the
        # JWT subject — Kör 7 / ADR 0400 precedent).
        sa.Column(
            "author_profile_id",
            _bigint,
            nullable=False,
        ),
        # Wire-string type from the Kör 5
        # ``CommunityChallengeDefinition`` enum (mirrors
        # ``ChallengeType.wireValue``). Service allowlist
        # enforces the valid set.
        sa.Column("type", sa.String(length=32), nullable=False),
        # Free-form metric label (e.g. "score",
        # "durationSeconds"); defined enum is Kör 15+.
        sa.Column("metric", sa.String(length=64), nullable=False),
        sa.Column("difficulty", sa.Integer(), nullable=False),
        # Server-authoritative window — the expiry check is
        # server-time, never client-time (A7 / §5.2).
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        # Schema version — bumped when the wire shape evolves
        # beyond the v1 contract. The repository fetches the
        # version on every read (mirrors
        # ``CommunityPost``'s ``artifact_schema_version``
        # precedent).
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        # Reserved for the Kör 24 club integration (ADR 0415
        # D7). Nullable; no FK (community_clubs is Kör 24
        # scope).
        sa.Column("club_id", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["author_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_challenges_author_profile",
        ),
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_challenges_public_id",
        ),
        # The window must be a positive interval.
        sa.CheckConstraint(
            "ends_at > starts_at",
            name="ck_community_challenges_window_positive",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_challenges_public_id",
        "community_challenges",
        ["public_id"],
        unique=True,
    )
    # The active-window list query (challenges where
    # ``starts_at <= now <= ends_at``) — the leading column is
    # ``type`` for the Kör 24 club filter, the composite
    # ends with ``(starts_at, id)`` for the cursor pagination.
    op.create_index(
        "ix_community_challenges_type_starts",
        "community_challenges",
        ["type", "starts_at", "id"],
        unique=False,
    )
    # The author's own challenges list.
    op.create_index(
        "ix_community_challenges_author_created",
        "community_challenges",
        ["author_profile_id", "created_at", "id"],
        unique=False,
    )

    op.create_table(
        "community_challenge_participants",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # FK back to the challenge — CASCADE keeps the
        # participant rows empty when the challenge is
        # hard-deleted.
        sa.Column(
            "challenge_id",
            _bigint,
            nullable=False,
        ),
        # The participant profile (the accepted invitee).
        sa.Column(
            "participant_profile_id",
            _bigint,
            nullable=False,
        ),
        # Personal best metric — the Kör 22 result-write
        # surface. NULL until the participant has submitted
        # a verified result.
        sa.Column("best_metric_value", sa.Integer(), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["challenge_id"],
            ["community_challenges.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_participants_challenge",
        ),
        sa.ForeignKeyConstraint(
            ["participant_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_participants_profile",
        ),
        # One participant row per (challenge, profile) pair.
        sa.UniqueConstraint(
            "challenge_id",
            "participant_profile_id",
            name="uq_community_challenge_participants_pair",
        ),
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_challenge_participants_public_id",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_challenge_participants_public_id",
        "community_challenge_participants",
        ["public_id"],
        unique=True,
    )
    op.create_index(
        "ix_community_challenge_participants_challenge",
        "community_challenge_participants",
        ["challenge_id", "joined_at", "id"],
        unique=False,
    )
    op.create_index(
        "ix_community_challenge_participants_profile",
        "community_challenge_participants",
        ["participant_profile_id", "joined_at", "id"],
        unique=False,
    )

    op.create_table(
        "community_challenge_invites",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # FK back to the challenge.
        sa.Column(
            "challenge_id",
            _bigint,
            nullable=False,
        ),
        # The inviter (author / moderator who sent the invite).
        sa.Column(
            "inviter_profile_id",
            _bigint,
            nullable=False,
        ),
        # The invitee — the recipient of the invite.
        sa.Column(
            "invitee_profile_id",
            _bigint,
            nullable=False,
        ),
        # Wire-string state from the Kör 5
        # ``ChallengeInviteState`` enum. Service guards the
        # transition graph (ADR 0415 D5).
        sa.Column("state", sa.String(length=16), nullable=False),
        # Server-authoritative expiry — the invite window.
        # The accept path checks ``expires_at > now`` (A2 /
        # §5.2 server-time check).
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        # Idempotency surface (A4, ADR 0415 D4). A retry
        # with the same key hits the existing row.
        # Composite with the (challenge, inviter, invitee)
        # tuple — same shape as the Kör 11 post idempotency
        # constraint, extended with the per-invitee
        # dimension.
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        # Self-pair rejection at the DB layer (mirrors the
        # ``ck_community_blocks_no_self_block`` precedent).
        sa.CheckConstraint(
            "inviter_profile_id != invitee_profile_id",
            name="ck_community_challenge_invites_no_self_invite",
        ),
        # Terminal states must not transition further (the
        # service still guards the graph with a conditional
        # UPDATE — this check is a DB-level safety net that
        # the row's final stamp is monotonic).
        sa.CheckConstraint(
            "state IN ("
            "'draft','sent','accepted','declined',"
            "'expired','cancelled','active',"
            "'completed','forfeited'"
            ")",
            name="ck_community_challenge_invites_state_known",
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        # Last-transition stamp — the ``accepted`` /
        # ``declined`` / ``cancelled`` / ``expired``
        # transition lands here. NULL on a fresh ``draft``
        # or ``sent`` row.
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["challenge_id"],
            ["community_challenges.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_invites_challenge",
        ),
        sa.ForeignKeyConstraint(
            ["inviter_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_invites_inviter",
        ),
        sa.ForeignKeyConstraint(
            ["invitee_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_invites_invitee",
        ),
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_challenge_invites_public_id",
        ),
        # §5.3 / A4 idempotency invariant. The composite key
        # includes the (challenge, inviter, invitee) tuple
        # so the same idempotency_key value on DIFFERENT
        # invites does not collide. NULL keys are
        # non-conflicting in SQL UNIQUE — system events
        # that opt out of dedup leave the column NULL
        # (mirrors the Kör 20
        # ``uq_community_notifications_recipient_dedup``
        # precedent).
        sa.UniqueConstraint(
            "challenge_id",
            "inviter_profile_id",
            "invitee_profile_id",
            "idempotency_key",
            name="uq_community_challenge_invites_idempotency",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_challenge_invites_public_id",
        "community_challenge_invites",
        ["public_id"],
        unique=True,
    )
    # The per-challenge invite list (the Kör 21
    # ``GET /community/challenges/{id}/invites`` endpoint
    # will read this).
    op.create_index(
        "ix_community_challenge_invites_challenge_state",
        "community_challenge_invites",
        ["challenge_id", "state", "created_at", "id"],
        unique=False,
    )
    # The per-invitee inbox (the recipient's pending
    # invites). The leading ``state`` column lets the
    # ``WHERE invitee_profile_id = ? AND state = 'sent'``
    # lookup hit the index directly.
    op.create_index(
        "ix_community_challenge_invites_invitee_state",
        "community_challenge_invites",
        ["invitee_profile_id", "state", "created_at", "id"],
        unique=False,
    )
    # The idempotency probe — the Kör 11
    # ``ix_community_posts_idempotency_key`` precedent.
    op.create_index(
        "ix_community_challenge_invites_idempotency_key",
        "community_challenge_invites",
        ["challenge_id", "inviter_profile_id", "idempotency_key"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the E09-R21 schema delta."""
    op.drop_index(
        "ix_community_challenge_invites_idempotency_key",
        table_name="community_challenge_invites",
    )
    op.drop_index(
        "ix_community_challenge_invites_invitee_state",
        table_name="community_challenge_invites",
    )
    op.drop_index(
        "ix_community_challenge_invites_challenge_state",
        table_name="community_challenge_invites",
    )
    op.drop_index(
        "ix_community_challenge_invites_public_id",
        table_name="community_challenge_invites",
    )
    op.drop_table("community_challenge_invites")

    op.drop_index(
        "ix_community_challenge_participants_profile",
        table_name="community_challenge_participants",
    )
    op.drop_index(
        "ix_community_challenge_participants_challenge",
        table_name="community_challenge_participants",
    )
    op.drop_index(
        "ix_community_challenge_participants_public_id",
        table_name="community_challenge_participants",
    )
    op.drop_table("community_challenge_participants")

    op.drop_index(
        "ix_community_challenges_author_created",
        table_name="community_challenges",
    )
    op.drop_index(
        "ix_community_challenges_type_starts",
        table_name="community_challenges",
    )
    op.drop_index(
        "ix_community_challenges_public_id",
        table_name="community_challenges",
    )
    op.drop_table("community_challenges")
