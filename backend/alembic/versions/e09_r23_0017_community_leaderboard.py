"""Add community_leaderboard_opt_ins table (E09-R23, ADR 0418 D2).

Revision ID: e09_r23_0017
Revises: e09_r22_0016
Create Date: 2026-08-24

The leaderboard opt-in surface — one row per profile that has
explicitly opted in to leaderboard visibility. The PRESENCE of a
row is the opt-in signal (A3 / §5.3); a missing row excludes the
profile from any public-scope leaderboard.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Own table, not on the Kör 4 ``community_privacy_settings``
  row** (ADR 0418 D2). The Kör 4 table holds
  ``visibility`` / ``audience_default`` — orthogonal concepts to
  leaderboard participation. The two are kept separate so a user
  can have a public-visibility profile AND opt out of leaderboards
  (or vice versa).

* **One-row-per-profile (UNIQUE ``profile_id``).** A second
  INSERT for the same profile raises ``IntegrityError``; the
  service layer translates that to an idempotent return of the
  existing row (the same Kör 21 invite-idempotency pattern).

* **CASCADE on profile delete.** A profile hard-delete cleans up
  its opt-in row in the same transaction (mirrors the project-wide
  ``community_privacy_settings`` / ``community_challenge_invites``
  pattern).

* **Migration is STRICTLY ADDITIVE.** No existing column /
  constraint / index on any prior table is touched.

The migration registers the ORM model with ``Base.metadata`` so
``alembic compare_metadata`` (round-12 migration-contract test)
sees the new table as part of the expected schema. The body itself
uses raw ``sa.Column`` / ``op.create_table`` calls so the schema is
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
from app.community.models.leaderboard import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityLeaderboardOptIn,
)

revision: str = "e09_r23_0017"
down_revision: str | Sequence[str] | None = "e09_r22_0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the E09-R23 community_leaderboard_opt_ins table."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_leaderboard_opt_ins",
        sa.Column("id", _bigint, nullable=False),
        # ``public_id`` is the wire surface — every cross-service
        # hop carries this, not the internal bigint. Same
        # project-wide pattern as ``CommunityPost`` /
        # ``CommunityProfile`` / ``CommunityChallengeResult``.
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # FK back to the profile row (CASCADE keeps opt-ins empty
        # when the profile is hard-deleted). UNIQUE on
        # ``profile_id`` is the §D2 one-row-per-profile invariant
        # — it doubles as the §A3 lookup index.
        sa.Column(
            "profile_id",
            _bigint,
            nullable=False,
        ),
        # Audit timestamp — when the user flipped the opt-in bit.
        # The PRESENCE of a row is the opt-in signal; the column
        # exists for the §A3 audit trail only.
        sa.Column("opted_in_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["profile_id"],
            ["community_profiles.id"],
            ondelete="CASCADE",
            name="fk_community_leaderboard_opt_ins_profile",
        ),
        # §D2 / A3 one-row-per-profile invariant — a second
        # INSERT for the same profile raises ``IntegrityError``
        # which the service catches (idempotent return). The
        # ``public_id`` column's ``unique=True`` also creates a
        # unique constraint with the SQLAlchemy-default name —
        # both feed the model-vs-migration comparison.
        sa.UniqueConstraint(
            "profile_id",
            name="uq_community_leaderboard_opt_ins_profile",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_leaderboard_opt_ins_public_id",
        "community_leaderboard_opt_ins",
        ["public_id"],
        unique=True,
    )
    # The opt-in lookup index — the service checks "is this profile
    # opted in" with a single SELECT by ``profile_id``. UNIQUE so
    # the index doubles as the §D2 invariant.
    op.create_index(
        "ix_community_leaderboard_opt_ins_profile",
        "community_leaderboard_opt_ins",
        ["profile_id"],
        unique=True,
    )


def downgrade() -> None:
    """Reverse the E09-R23 schema delta."""
    op.drop_index(
        "ix_community_leaderboard_opt_ins_profile",
        table_name="community_leaderboard_opt_ins",
    )
    op.drop_index(
        "ix_community_leaderboard_opt_ins_public_id",
        table_name="community_leaderboard_opt_ins",
    )
    op.drop_table("community_leaderboard_opt_ins")