"""Add community_clubs / community_club_members / community_club_invites tables (E09-R24, ADR 0420).

Revision ID: e09_r24_0018
Revises: e09_r23_0017
Create Date: 2026-08-24

The first concrete schema for the ``CommunityClub`` domain (the Kör 5 /
ADR 0399 entity has been wire-side for three rounds; this round gives it
a persisted shape). Three new tables:

* ``community_clubs`` — one row per club definition (name, description,
  visibility, owner, create_idempotency_key).
* ``community_club_members`` — one row per (club, profile) join with
  the role (owner / moderator / member). The DB-level UNIQUE on
  ``(club_id, profile_id)`` is the A3 (duplicate-join) enforcement.
* ``community_club_invites`` — one row per invite edge. Idempotent on
  ``(club_id, inviter_profile_id, invitee_profile_id,
  idempotency_key)`` — the Kör 21 invite pattern.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Wire-string vocabulary.** ``visibility```` carries one of the three
  ``ClubVisibility`` wire values; the ``role`` column on the member row
  carries one of the three ``ClubRole`` wire values. DB-level CHECKs
  list the known values as a defensive safety net; the service is the
  canonical allowlist.

* **Idempotency (A3, D5, F1).** The composite UNIQUE on
  ``community_club_members`` ``(club_id, profile_id)`` is the
  §A3 duplicate-join enforcement. ``community_club_invites`` has a
  UNIQUE on the (club, inviter, invitee, idempotency_key) tuple —
  the §D4 idempotency surface (mirrors the Kör 21 invite precedent).
  ``community_clubs`` carries a nullable ``create_idempotency_key``
  column with a composite UNIQUE on
  ``(owner_profile_id, create_idempotency_key)`` — the §F1
  create-side idempotency surface (the Kör 24 round 1 helper only
  filtered by owner, breaking the multi-club-ownership path).

* **Cascade on profile / club delete.** A profile hard-delete cleans up
  its membership / invite / ownership rows in the same transaction
  (mirrors the project-wide ``community_follows`` /
  ``community_challenge_invites`` precedent). A club hard-delete cleans
  up its member / invite rows.

* **Migration is STRICTLY ADDITIVE.** No existing column / constraint /
  index on any prior table is touched (the Kör 11
  ``community_posts.club_id`` and Kör 21 ``community_challenges.club_id``
  columns stay as-is — the Kör 25 FK work is a future round).

The migration registers the ORM model with ``Base.metadata`` so
``alembic compare_metadata`` (round-12 migration-contract test) sees the
new tables as part of the expected schema. The body itself uses raw
``sa.Column`` / ``op.create_table`` calls so the schema is
migration-source-of-truth, not ORM-derived autogenerate.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# Register the ORM model with ``Base.metadata`` so
# ``alembic compare_metadata`` (round-12 migration-contract test)
# sees the new tables as part of the expected schema. The
# migration body itself does not rely on the model classes — it
# uses raw ``sa.Column`` / ``op.create_table`` calls so the schema
# is migration-source-of-truth, not ORM-derived autogenerate.
from app.community.models.club import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityClub,
    CommunityClubInvite,
    CommunityClubMember,
)

revision: str = "e09_r24_0018"
down_revision: str | Sequence[str] | None = "e09_r23_0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# SQLite-shared variant — same BigInteger / Integer-on-SQLite seam as
# the rest of the community module (ADR 0396 §1).
_bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")


def upgrade() -> None:
    """Create the E09-R24 community_clubs / community_club_members /
    community_club_invites tables."""

    # ---------------------------------------------------------------------
    # community_clubs
    # ---------------------------------------------------------------------
    op.create_table(
        "community_clubs",
        sa.Column("id", _bigint, nullable=False),
        # ``public_id`` is the wire surface (D1).
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # Name is short (≤ 60 chars in the Flutter factory).
        sa.Column("name", sa.String(length=60), nullable=False),
        # No ``server_default`` on ``description`` — the column is
        # ``NOT NULL`` and the service always sets the value
        # explicitly (the ``create_club`` / ``update_club`` paths
        # accept ``description: str`` as a required arg). The empty-
        # string default is a Python-side ``default=""`` on the ORM
        # for ORM-managed inserts. A DB-level ``DEFAULT ''`` would
        # also be redundant; we deliberately omit it so the migration
        # and the ORM column declaration agree on schema (alembic's
        # autogenerate-compare on this column is a known empty-string
        # trap — see ADR 0420 §4).
        sa.Column(
            "description",
            sa.String(length=2000),
            nullable=False,
        ),
        # ``visibility`` is one of the three ``ClubVisibility`` wire
        # values (private / discoverable / public).
        sa.Column(
            "visibility",
            sa.String(length=16),
            nullable=False,
            server_default="private",
        ),
        # Owner FK — A1 invariant's last-resort guard. CASCADE on
        # profile delete cleans up the club row when the owner is
        # hard-deleted.
        sa.Column("owner_profile_id", _bigint, nullable=False),
        # §F1 fix — persist the create ``idempotency_key`` so the
        # probe can match on ``(owner_profile_id, key)`` exactly
        # (the Kör 24 round 1 helper only filtered by owner and
        # returned the most-recent club, breaking the
        # multi-club-ownership path). Mirrors the invite-side
        # ``community_club_invites.idempotency_key`` shape: nullable
        # String(128); the composite UNIQUE allows multiple NULLs
        # so callers that omit the key are never blocked.
        sa.Column(
            "create_idempotency_key",
            sa.String(length=128),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["owner_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_clubs_owner",
        ),
        # §D1 — wire identity (UUID).
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_clubs_public_id",
        ),
        # §F1 — create-idempotency surface (the D5 pattern, club-
        # side). The probe helper ``_find_club_by_create_idempotency_key``
        # matches on this tuple exactly. SQL UNIQUE treats NULLs
        # as distinct, so omitting ``create_idempotency_key``
        # (NULL) does NOT block the owner's subsequent clubs.
        sa.UniqueConstraint(
            "owner_profile_id",
            "create_idempotency_key",
            name="uq_community_clubs_create_idempotency",
        ),
        # DB-level safety net for the wire vocabulary.
        sa.CheckConstraint(
            "visibility IN ('private','discoverable','public')",
            name="ck_community_clubs_visibility_known",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_clubs_public_id",
        "community_clubs",
        ["public_id"],
        unique=True,
    )
    # The list index — the active-clubs feed orders by
    # ``(created_at DESC, id DESC)`` and filters by visibility.
    op.create_index(
        "ix_community_clubs_visibility_created",
        "community_clubs",
        ["visibility", "created_at", "id"],
    )
    # The owner-lookup index — used by the ``leave_club``
    # ownership-transfer step.
    op.create_index(
        "ix_community_clubs_owner",
        "community_clubs",
        ["owner_profile_id"],
    )
    # §F1 — the create-idempotency probe index.
    op.create_index(
        "ix_community_clubs_create_idempotency_key",
        "community_clubs",
        ["owner_profile_id", "create_idempotency_key"],
    )

    # ---------------------------------------------------------------------
    # community_club_members
    # ---------------------------------------------------------------------
    op.create_table(
        "community_club_members",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("club_id", _bigint, nullable=False),
        sa.Column("profile_id", _bigint, nullable=False),
        # Wire-string role (owner / moderator / member).
        sa.Column(
            "role",
            sa.String(length=16),
            nullable=False,
            server_default="member",
        ),
        sa.Column("joined_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["club_id"],
            ["community_clubs.id"],
            ondelete="CASCADE",
            name="fk_community_club_members_club",
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_club_members_profile",
        ),
        # §D1 — wire identity.
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_club_members_public_id",
        ),
        # §A3 / D5 — duplicate-join enforcement.
        sa.UniqueConstraint(
            "club_id",
            "profile_id",
            name="uq_community_club_members_pair",
        ),
        # Wire vocabulary safety net.
        sa.CheckConstraint(
            "role IN ('owner','moderator','member')",
            name="ck_community_club_members_role_known",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_club_members_public_id",
        "community_club_members",
        ["public_id"],
        unique=True,
    )
    # The member-list query orders by ``(joined_at ASC, id ASC)``.
    op.create_index(
        "ix_community_club_members_club_joined",
        "community_club_members",
        ["club_id", "joined_at", "id"],
    )
    # Per-profile clubs-list index.
    op.create_index(
        "ix_community_club_members_profile",
        "community_club_members",
        ["profile_id", "joined_at", "id"],
    )

    # ---------------------------------------------------------------------
    # community_club_invites
    # ---------------------------------------------------------------------
    op.create_table(
        "community_club_invites",
        sa.Column("id", _bigint, nullable=False),
        sa.Column("public_id", sa.Uuid(), nullable=False),
        sa.Column("club_id", _bigint, nullable=False),
        sa.Column("inviter_profile_id", _bigint, nullable=False),
        sa.Column("invitee_profile_id", _bigint, nullable=False),
        # Wire-string status (pending / accepted / cancelled /
        # declined / expired). Kör 24 only models ``pending`` and
        # ``accepted``; the rest are reserved for future rounds.
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default="pending",
        ),
        # Server-authoritative expiry.
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        # Idempotency surface — Kör 21 pattern.
        sa.Column(
            "idempotency_key",
            sa.String(length=128),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("responded_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["club_id"],
            ["community_clubs.id"],
            ondelete="CASCADE",
            name="fk_community_club_invites_club",
        ),
        sa.ForeignKeyConstraint(
            ["inviter_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_club_invites_inviter",
        ),
        sa.ForeignKeyConstraint(
            ["invitee_profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_club_invites_invitee",
        ),
        # §D1 — wire identity.
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_club_invites_public_id",
        ),
        # §D4 / D5 — idempotency surface.
        sa.UniqueConstraint(
            "club_id",
            "inviter_profile_id",
            "invitee_profile_id",
            "idempotency_key",
            name="uq_community_club_invites_idempotency",
        ),
        # NOTE: no self-pair CHECK here. The Kör 24 ``request_join``
        # path for a ``private`` club creates a row where
        # ``inviter_profile_id == invitee_profile_id`` (the actor
        # requests to join their own club — see ADR 0420 D6). The
        # service layer rejects self-invites on the ``invite`` path
        # (the non-join-request call) by raising ``ValueError`` —
        # see ``club_service.invite``.
        sa.CheckConstraint(
            "status IN ('pending','accepted','cancelled','declined','expired')",
            name="ck_community_club_invites_status_known",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_club_invites_public_id",
        "community_club_invites",
        ["public_id"],
        unique=True,
    )
    # Per-club pending-invites index.
    op.create_index(
        "ix_community_club_invites_club_status",
        "community_club_invites",
        ["club_id", "status", "created_at", "id"],
    )
    # Per-invitee inbox.
    op.create_index(
        "ix_community_club_invites_invitee_status",
        "community_club_invites",
        ["invitee_profile_id", "status", "created_at", "id"],
    )
    # The idempotency probe.
    op.create_index(
        "ix_community_club_invites_idempotency_key",
        "community_club_invites",
        ["club_id", "inviter_profile_id", "idempotency_key"],
    )


def downgrade() -> None:
    """Reverse the E09-R24 schema delta."""
    # Drop invites first (depends on clubs + profiles).
    op.drop_index(
        "ix_community_club_invites_idempotency_key",
        table_name="community_club_invites",
    )
    op.drop_index(
        "ix_community_club_invites_invitee_status",
        table_name="community_club_invites",
    )
    op.drop_index(
        "ix_community_club_invites_club_status",
        table_name="community_club_invites",
    )
    op.drop_index(
        "ix_community_club_invites_public_id",
        table_name="community_club_invites",
    )
    op.drop_table("community_club_invites")

    # Members next (depends on clubs + profiles).
    op.drop_index(
        "ix_community_club_members_profile",
        table_name="community_club_members",
    )
    op.drop_index(
        "ix_community_club_members_club_joined",
        table_name="community_club_members",
    )
    op.drop_index(
        "ix_community_club_members_public_id",
        table_name="community_club_members",
    )
    op.drop_table("community_club_members")

    # Clubs last.
    op.drop_index(
        "ix_community_clubs_create_idempotency_key",
        table_name="community_clubs",
    )
    op.drop_index(
        "ix_community_clubs_owner",
        table_name="community_clubs",
    )
    op.drop_index(
        "ix_community_clubs_visibility_created",
        table_name="community_clubs",
    )
    op.drop_index(
        "ix_community_clubs_public_id",
        table_name="community_clubs",
    )
    op.drop_table("community_clubs")