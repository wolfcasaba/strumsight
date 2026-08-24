"""Add community_challenge_results table (E09-R22, ADR 0417).

Revision ID: e09_r22_0016
Revises: e09_r21_0015
Create Date: 2026-08-24

The verified-result submission surface — one row per participant's
submitted challenge result. The table is the persistence side of the
Kör 5 ``submitResult`` repository contract; the server is the sole
authority on the ``verification_state`` and on the
``community_challenge_participants.best_metric_value`` projection
(D5).

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the service and the tests pin):

* **Server-side author of the decision (§5.1, D2).** ``verification_state``
  is a wire-string form of the 5-value enum
  (``pending|verified|unverified|rejected|review``), guarded by a CHECK
  constraint that lists the known values. The service layer decides
  the value — a client NEVER supplies a ``verified`` or ``rank`` field
  on the request payload (the §5.1 / §6.1 forged-verified cell).

* **Replay-dedup (A1, D2).** ``UNIQUE(participant_id, source_event_id)``
  is the §A1 acceptance-criterion surface — a replay lands on the
  same row via ``IntegrityError`` + re-read (mirrors the Kör 11
  ``post_service.create_post`` / Kör 21
  ``challenge_invite_service.create_invite`` precedent).

* **Server-issued nonce + TTL (§5.4, D3).** ``nonce`` is a server-
  generated ``uuid4`` stamp on the FIRST processing attempt; the
  client never sends or sees it. ``nonce_expires_at`` is the
  bookkeeping TTL — a FÉLBEN-maradt (``pending``/``review``) beküldés,
  whose döntés nem születik meg a TTL-en belül, véglegesen lejárt a
  nonce-on; the A4 cell a szervizen keresztül fabrikál egy ilyen sort
  és méri a lejárat utáni újrapróbálkozást.

* **Idempotency-key witness.** ``idempotency_key`` mirrors the Kör 5
  wire field — it is the HTTP-szintű retry-biztonság (the
  ``source_event_id`` a domain-szintű replay-dedup, see D2).

* **Best-metric projection (D5, D6).** The
  ``community_challenge_participants.best_metric_value`` column is NOT
  on this table — it is the MÁR meglévő Kör 21 column that this
  service WRITES via a conditional UPDATE in the same transaction
  (a verified döntés után, type-szerinti first-vs-best policy). The
  Kör 21 ``challenge.py`` modell-fájl tilos zóna, de az oszlop
  létezik, és itt ÍRJUK először.

* **No raw audio / no PII (scope).** The metric is an ``int`` only;
  a future anomaly-triage round (Kör 24+) can layer reason-codes on
  top, but no raw signal lands in this row.

* **Migration is STRICTLY ADDITIVE.** No existing column / constraint
  / index on any prior table is touched.

The migration registers the ORM model with ``Base.metadata`` so
``alembic compare_metadata`` (round-12 migration-contract test)
sees the new table. The body itself uses raw ``sa.Column`` /
``op.create_table`` calls so the schema is migration-source-of-truth,
not ORM-derived autogenerate.
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
from app.community.models.challenge_result import (  # noqa: F401,E402 -- side-effect import registers ORM metadata
    CommunityChallengeResult,
)

revision: str = "e09_r22_0016"
down_revision: str | Sequence[str] | None = "e09_r21_0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the E09-R22 community_challenge_results table."""
    _bigint = sa.BigInteger().with_variant(sa.Integer(), "sqlite")

    op.create_table(
        "community_challenge_results",
        sa.Column("id", _bigint, nullable=False),
        # ``public_id`` is the wire surface — every cross-service
        # hop carries this, not the internal bigint. Same
        # project-wide pattern as ``CommunityPost`` /
        # ``CommunityProfile``.
        sa.Column("public_id", sa.Uuid(), nullable=False),
        # FK back to the participant row (the MÁR kijelölt írási
        # surface, ADR 0417 D5). CASCADE keeps result rows empty
        # when the participant is hard-deleted.
        sa.Column(
            "participant_id",
            _bigint,
            nullable=False,
        ),
        # Domain-side replay surface (A1, D2). The composite
        # unique key uses ``(participant_id, source_event_id)``
        # so the SAME local practice event cannot produce
        # multiple result rows. The ``idempotency_key`` is a
        # SEPARATE column for HTTP-szintű retry-biztonság.
        sa.Column("source_event_id", sa.String(length=128), nullable=False),
        # HTTP-szintű retry surface (D2 second clause).
        sa.Column("idempotency_key", sa.String(length=128), nullable=True),
        # The metric value (int). The structural range is
        # ``[0, 1_000_000]`` — the MÁR élő kliens-kontraktus
        # tükre (D4).
        sa.Column("metric_value", sa.Integer(), nullable=False),
        # The five-value wire-string enum; the service layer
        # is the sole authority (D1). The CHECK lists the
        # known values — a future round can add a value
        # without a migration by bumping the allowlist
        # check at the service boundary.
        sa.Column("verification_state", sa.String(length=16), nullable=False),
        # The audit reason-code — NULL on a freshly-inserted
        # ``pending`` row; populated on terminal
        # (``verified|unverified|rejected|review``) states
        # (A8).
        sa.Column("reason_code", sa.String(length=64), nullable=True),
        # Server-issued nonce (UUID4) — a stamp on the
        # row that the client never sees / never sends.
        sa.Column("nonce", sa.Uuid(), nullable=False),
        # Server-side TTL — a FÉLBEN maradt
        # ``pending|review`` beküldés ezen idő után
        # véglegesen lejárt; a lejárat-utáni
        # újrapróbálkozás a ``rejected``,
        # ``reason_code="nonce_expired"`` döntést kapja.
        sa.Column(
            "nonce_expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=False),
        # ``decided_at`` is NULL on a row that is still
        # ``pending``; it lands the moment the service
        # commits a terminal ``verified|unverified|
        # rejected|review`` decision.
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(
            ["participant_id"],
            ["community_challenge_participants.id"],
            ondelete="CASCADE",
            name="fk_community_challenge_results_participant",
        ),
        sa.UniqueConstraint(
            "public_id",
            name="uq_community_challenge_results_public_id",
        ),
        # §A1 / D2 replay-dedup invariant. The composite is
        # keyed on (participant, source_event_id) so the same
        # local practice event cannot produce multiple
        # result rows. ``source_event_id`` is NOT NULL —
        # every beküldés carries one (the Kör 5 repository
        # contract).
        sa.UniqueConstraint(
            "participant_id",
            "source_event_id",
            name="uq_community_challenge_results_replay",
        ),
        # DB-level defensive safety-net — the service still
        # guards the transition graph (a future round can
        # add a CHECK on ``decided_at`` being non-NULL for
        # terminal states). Mirrors the
        # ``ck_community_challenge_invites_state_known``
        # precedent.
        sa.CheckConstraint(
            "verification_state IN ("
            "'pending','verified','unverified',"
            "'rejected','review'"
            ")",
            name="ck_community_challenge_results_state_known",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_community_challenge_results_public_id",
        "community_challenge_results",
        ["public_id"],
        unique=True,
    )
    # The per-participant history (the future Kör 23
    # list endpoint will read this).
    op.create_index(
        "ix_community_challenge_results_participant_submitted",
        "community_challenge_results",
        ["participant_id", "submitted_at", "id"],
        unique=False,
    )
    # The replay probe — the §A1 / D2 unique-collision is
    # caught at INSERT time by the unique constraint; the
    # composite index is a non-unique probe that the
    # service can use for the IntegrityError → re-read
    # path WITHOUT a full table scan on a hot table.
    op.create_index(
        "ix_community_challenge_results_replay_probe",
        "community_challenge_results",
        ["participant_id", "source_event_id"],
        unique=False,
    )


def downgrade() -> None:
    """Reverse the E09-R22 schema delta."""
    op.drop_index(
        "ix_community_challenge_results_replay_probe",
        table_name="community_challenge_results",
    )
    op.drop_index(
        "ix_community_challenge_results_participant_submitted",
        table_name="community_challenge_results",
    )
    op.drop_index(
        "ix_community_challenge_results_public_id",
        table_name="community_challenge_results",
    )
    op.drop_table("community_challenge_results")
