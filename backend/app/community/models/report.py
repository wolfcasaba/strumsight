"""User-report ORM model — E09-R26, ADR 0414 §5.1.

One row per ``(reporter, target_type, target_id, category)`` quadruple.
The row's ``public_id`` is the ONLY wire-visible identifier — the
internal ``reporter_profile_id`` FK exists strictly for the moderation
queue (Kör 27 scope) and the rate-limit guard. It is NEVER returned to
any caller, NEVER embedded in any notification or post visibility
signal, and NEVER exposed via any response body (brief §5.1 — the
retaliation-risk guard).

The reporter-identity invariant has three DB-layer supports:

* The ``UNIQUE(dedup_key)`` constraint is the §6 A2 race protection:
  a concurrent retry on the same ``(reporter, target, category)`` tuple
  cannot land a second row — the service layer reads the existing row
  and returns it (the same idempotent-retry pattern as
  ``CommunityBlock`` / ``CommunityFollow``).

* The composite ``(reporter_profile_id, target_type, target_id,
  category)`` UNIQUE makes "duplicate report" structurally a no-op,
  independent of the caller's idempotency_key.

* The ``reporter_profile_id`` column is **internal-only** — it is a
  plain column with no public wire equivalent. The model exposes no
  ``reporter_public_id`` property; the public API response shape
  carries ``report_public_id`` only.

``target_type`` is a plain ``String`` (the project-wide value-set
pattern from ADR 0398 §1 — the value set is enforced at the Pydantic
layer, not the DB; the column carries ``server_default='post'`` so a
populated table stays safe). The Kör 26 scope uses ``'post'`` and
``'comment'``; future rounds may add ``'profile'`` etc.

``category`` is a plain ``String`` with no server default — the service
layer rejects empty / unknown values BEFORE the INSERT (the §6.1 A5
measure-matrix cell). The set is hard-coded in
:mod:`app.community.services.report_service` and mirrors the localized
list in the Flutter ``report_content_sheet``.

``extra_metadata_json`` is the §3 optional detail column. For
``'copyright'`` and ``'privacy'`` categories the Flutter sheet writes
a minimal evidence payload here (URL of the source, the date the
content was copied, etc.); for other categories the column is NULL.
The column is NEVER returned to the target party (the moderation queue
sees it; the reporter themselves see a sanitized "thanks" view).

The ``deleted_at`` column supports the §6 A4 "report against a deleted
target" invariant: the row is preserved for the moderation queue but
``target_exists`` becomes False; the service layer surfaces a
non-error response so the reporter's flow continues.

The composite ``(target_type, target_id, created_at, id)`` index
supports the Kör 27 moderation queue's cursor-paginated read path —
out of scope here, but the index is cheap and the contract is fixed.
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
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from ...database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class CommunityReport(Base):
    """A user-submitted content report — one row per (reporter, target, category).

    The wire shape is ``public_id`` only; the internal FK
    ``reporter_profile_id`` is the Kör 27 moderation queue's join surface
    and is the only place the reporter's identity is recorded.

    The §5.1 invariant — the reporter's identity NEVER leaks to the
    target — is enforced by **omission** at the model layer: no property,
    no relationship, no helper exposes the reporter's ``public_id`` or
    internal ``id`` to the wire. The service layer's response-sanitization
    helper is the second backstop.
    """

    __tablename__ = "community_reports"

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
    reporter_profile_id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        ForeignKey("community_profiles.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_type: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        server_default="post",
    )
    # The target's public_id (UUID). Stored as the textual UUID so the
    # table is portable across FK targets (posts, comments, profiles).
    # The moderation queue (Kör 27) joins on this column to look up the
    # target; this round never reads it back to the reporter.
    target_id: Mapped[str] = mapped_column(
        String(64),
        nullable=False,
    )
    category: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
    )
    # Optional detail — used only by ``copyright`` / ``privacy`` for
    # the minimal evidence payload. NULL for every other category.
    extra_metadata_json: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
    )
    # Computed at INSERT time by the service layer as
    # ``f"{reporter_public_id}:{target_type}:{target_id}:{category}"`` —
    # the §6 A2 dedup key. A second submit on the same triple cannot
    # land a second row (the UNIQUE catches it; the service layer
    # re-reads and returns the existing row).
    dedup_key: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    # Soft tombstone for the target — see §6 A4. A report against a
    # since-deleted target stays in the table for the moderation queue
    # but the service layer surfaces a non-error response so the
    # reporter's flow continues.
    target_deleted_at_submit: Mapped[bool] = mapped_column(
        default=False,
        server_default=text("0"),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint(
            "dedup_key",
            name="uq_community_reports_dedup_key",
        ),
        # The §6 A2 idempotency guard at the structural layer —
        # independent of the service-layer dedup-key. Even if a future
        # round changes the dedup-key format, this UNIQUE catches any
        # accidental double-insert on the same reporter-target-category
        # triple.
        UniqueConstraint(
            "reporter_profile_id",
            "target_type",
            "target_id",
            "category",
            name="uq_community_reports_reporter_target_category",
        ),
        Index(
            "ix_community_reports_target_created",
            "target_type",
            "target_id",
            "created_at",
            "id",
        ),
        Index(
            "ix_community_reports_reporter_created",
            "reporter_profile_id",
            "created_at",
            "id",
        ),
    )


__all__ = ["CommunityReport"]
