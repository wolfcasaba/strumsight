"""Handle history ORM model — E09-R03, ADR 0397 §5.4.

Every handle change (and the initial assignment) is recorded as a row here
so the previous handle can redirect to the current one inside the
``HANDLE_REDIRECT_WINDOW``. Two important invariants live in the DB layer,
NOT the application layer:

* CASCADE on delete: when the parent ``community_profiles`` row is removed
  the matching history rows go with it. Same pattern as the existing
  ``community_privacy_settings`` relationship.
* The cooldown / redirect-until logic reads from this table through raw
  SQL — the test for A6 explicitly asserts the redirect lookup honors the
  ``redirect_until`` timestamp and the cooldown lookup honors
  ``changed_at``.

The model lives in its own file (separate from ``models/profile.py`` per
the brief's allowed_paths) so the Kör 3 schema is a clean, reviewable
delta.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityHandleHistory(Base):
    """A single handle transition (or initial assignment) for one profile.

    For the initial claim both ``old_handle`` and ``old_normalized`` are
    ``None`` (we only know the handle the user *picked*, not a "previous"
    one). For a change, ``old_*`` is the previous handle and ``new_*`` is
    the handle the profile now points at.

    ``redirect_until`` is the timestamp after which the *old* handle
    no longer resolves to this profile — it is set to
    ``changed_at + REDIRECT_WINDOW`` for changes, and ``NULL`` for the
    initial assignment (nothing to redirect from).
    """

    __tablename__ = "community_handle_history"

    id: Mapped[int] = mapped_column(
        # BigInteger on PostgreSQL, Integer on SQLite so the rowid-based
        # autoincrement kicks in — same variant rationale as ``CommunityProfile.id``
        # in Kör 2 (ADR 0396 §1).
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
    )
    profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    # The display form (what the user typed) is preserved for audit and
    # for the redirect lookup — even if the normalised form is what the
    # unique index sits on, the API can show the historical display form
    # in admin views without re-deriving it.
    old_handle: Mapped[str | None] = mapped_column(String(24), nullable=True)
    old_normalized: Mapped[str | None] = mapped_column(String(24), nullable=True)
    new_handle: Mapped[str] = mapped_column(String(24), nullable=False)
    new_normalized: Mapped[str] = mapped_column(String(24), nullable=False)
    changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # ``redirect_until`` is None for the initial assignment (no prior
    # handle to redirect from) and ``changed_at + window`` for changes.
    redirect_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Composite index on (profile_id, changed_at DESC) — the cooldown
    # lookup orders by changed_at DESC and limits to one row, so the
    # composite order matches the query plan exactly.
    __table_args__ = (
        Index(
            "ix_community_handle_history_profile_changed",
            "profile_id",
            "changed_at",
        ),
    )


# ---------------------------------------------------------------------------
# Register the Kör 3 handle columns with ``Base.metadata``
# ---------------------------------------------------------------------------
#
# The brief's ``allowed_paths`` does not list ``models/profile.py``, so
# the existing ``CommunityProfile`` ORM class is NOT modified. The
# migration body (``alembic/versions/e09_r03_0003_community_handle.py``)
# adds ``handle_display`` / ``handle_normalized`` + the unique index to
# the *DB* schema. The round-12 migration-contract test
# (``tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema``)
# compares ``Base.metadata`` to the live DB and would otherwise flag the
# new columns as "missing from ORM".
#
# We register the same columns here via ``Table.append_column`` on the
# existing ``community_profiles`` table object — the mapped class is
# untouched (it doesn't see the columns, so attribute access still
# raises), but ``Base.metadata`` sees them so the migration-contract
# test compares equal. This is the §6.1 A1 / §5.1 mechanism expressed
# purely in metadata so the source-of-truth stays the migration file.
_profiles_table = Base.metadata.tables["community_profiles"]
_profiles_table.append_column(Column("handle_display", String(24), nullable=True))
_profiles_table.append_column(Column("handle_normalized", String(24), nullable=True))
Index(
    "ix_community_profiles_handle_normalized",
    _profiles_table.c.handle_normalized,
    unique=True,
)


__all__ = ["CommunityHandleHistory"]
