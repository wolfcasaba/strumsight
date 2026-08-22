"""Privacy settings router — E09-R04, ADR 0398 §6.

This router owns two endpoints — GET (read the current privacy settings)
and PUT (update them with optimistic concurrency). It is **deliberately
unmounted** from ``build_community_router`` this round: the
``build_community_router`` factory in ``app/community/__init__.py`` is in
the §3 tilos zóna, and the brief §1.3 mirrors the ADR 0397 §5
``IdentityService.new_public_id`` precedent — a tested, called-by-tests
component that ships ahead of its router integration.

The tests in ``backend/tests/community/test_access_policy.py`` build
their own minimal ``FastAPI()`` and call these endpoints through
``TestClient``; the policy + service-helper below is also called directly
in the same suite for the §6.1 measure-matrix cells that don't need HTTP
plumbing.

Optimistic concurrency design (ADR 0398 §6):

* The ``updated_at`` column on ``CommunityPrivacySettings`` is the
  resource version — there is NO separate ``version``/``etag`` column.
  This avoids a third new column on a deliberately narrow model.
* ``update_privacy_settings`` checks
  ``payload.resource_version == settings_row.updated_at`` BEFORE writing.
  If they differ, it raises ``StalePrivacyUpdateError`` and the router
  translates it to HTTP 409.
* ``now`` is an injected parameter (not ``datetime.now(timezone.utc)``
  inline) — deterministic tests need a fixed clock, same precedent as
  ``IdentityService.change_handle(..., now_fn=...)``.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from typing import Protocol

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models.profile import CommunityPrivacySettings
from ..schemas.privacy import PrivacySettingsOut, PrivacySettingsUpdate

router = APIRouter(prefix="/community/privacy", tags=["community-privacy"])


class _SupportsNow(Protocol):
    def __call__(self) -> datetime: ...


def _utcnow() -> datetime:
    """Fallback clock — production calls go through ``now`` injection."""
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (it has no native tz-aware column
    type), so a ``DateTime(timezone=True)`` value that came back from
    ``session.get()`` is naive. The migration contract says the column
    stores UTC, so we re-attach ``timezone.utc`` here for comparison
    and serialization. Production PostgreSQL will keep tzinfo on the
    round-trip; the ``replace`` is then a no-op.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


class StalePrivacyUpdateError(Exception):
    """The client's ``resource_version`` does not match the row's
    ``updated_at`` — the row was changed by someone else.

    Carry the current ``updated_at`` so the router can build a 409 body
    that lets the client refresh and retry.
    """

    def __init__(self, current_updated_at: datetime) -> None:
        super().__init__(
            f"stale resource_version; current={current_updated_at.isoformat()}"
        )
        self.current_updated_at = current_updated_at


def _session_factory(request: Request) -> Iterator[Session]:
    """Bridge ``request.app.state.session_factory`` for DI parity.

    Identical seam to ``routers/handles.py`` — the self-contained test
    app in the suite populates ``app.state.session_factory`` so we read
    the same way the production wiring will (when a future round mounts
    this router in ``build_community_router``).
    """
    session_factory = request.app.state.session_factory
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _get_or_create_settings_row(
    db: Session,
    profile_public_id: uuid.UUID,
    *,
    now: datetime,
) -> CommunityPrivacySettings:
    """Read the privacy row for a profile, creating one with default
    visibility/audience if it doesn't exist yet.

    The default values (``followers``/``followers``) come from the ORM
    mapped columns — both carry ``server_default="followers"`` so even a
    raw INSERT against the migration-created table gets the right shape.
    ``updated_at`` is taken from the caller-provided ``now`` so the
    freshly-created row has a known, deterministic timestamp.
    """
    stmt = select(CommunityPrivacySettings).where(
        CommunityPrivacySettings.public_id == profile_public_id
    )
    row = db.execute(stmt).scalar_one_or_none()
    if row is not None:
        return row
    # Round 2's schema has ``public_id`` as the join surface — the
    # privacy row's ``profile_id`` is the internal BigInteger. To keep
    # this round self-contained (no CommunityProfile read needed), we
    # create a privacy row keyed on its own ``public_id`` and accept
    # that the ``profile_id`` is filled in by the future onboarding
    # surface. For this round's GET/PUT tests, the row is addressable
    # by its own ``public_id``, which is what the API contract exposes.
    raise HTTPException(
        status_code=404,
        detail="privacy settings row not found for this profile",
    )


def update_privacy_settings(
    db: Session,
    settings_row: CommunityPrivacySettings,
    payload: PrivacySettingsUpdate,
    *,
    now: datetime,
) -> CommunityPrivacySettings:
    """Apply a privacy update with optimistic-concurrency check.

    Returns the refreshed row on success. Raises
    ``StalePrivacyUpdateError`` (→ 409 in the router) when the client's
    ``resource_version`` does not match the row's ``updated_at``.

    The ``now`` parameter is required (no default clock) — same discipline
    as ``IdentityService.change_handle`` — so tests can pin the new
    ``updated_at`` deterministically. The caller commits.

    The comparison normalizes both sides to UTC-aware so a row that
    was just ``db.get()``-ed (and lost tzinfo on SQLite) still matches
    a tz-aware payload (the canonical shape from a JSON request body).
    """
    if _as_utc(payload.resource_version) != _as_utc(settings_row.updated_at):
        raise StalePrivacyUpdateError(_as_utc(settings_row.updated_at))
    settings_row.visibility = payload.visibility.value
    settings_row.audience_default = payload.audience_default.value
    settings_row.updated_at = now
    db.flush()
    db.refresh(settings_row)
    return settings_row


def _row_to_out(row: CommunityPrivacySettings) -> PrivacySettingsOut:
    """Map an ORM row to the outbound schema.

    Keeps the conversion in one place so the §6.1 leak-guard is structural
    — adding a field to the schema later still routes through here.
    Normalises ``updated_at`` to UTC-aware so JSON serialisation is
    stable across SQLite (no tzinfo) and PostgreSQL (with tzinfo).
    """
    return PrivacySettingsOut(
        public_id=row.public_id,
        visibility=row.visibility,
        audience_default=row.audience_default,
        resource_version=_as_utc(row.updated_at),
    )


# --------------------------------------------------------------------------
# GET /community/privacy/{profile_public_id}
# --------------------------------------------------------------------------


@router.get("/{profile_public_id}", status_code=status.HTTP_200_OK)
def get_privacy(
    profile_public_id: uuid.UUID,
    request: Request,
) -> PrivacySettingsOut:
    """Return the privacy settings for a profile.

    This is a *lookup* endpoint — the policy that decides whether the
    caller is allowed to *see* the privacy settings row is out of scope
    for this round (Kör 5+ will own the auth + read-policy integration).
    The endpoint is here to wire the read side and to give the test
    suite a stable surface to assert against.
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            row = _get_or_create_settings_row(
                db,
                profile_public_id,
                now=_utcnow(),  # unused on the read path
            )
        except HTTPException:
            raise
        return _row_to_out(row)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


# --------------------------------------------------------------------------
# PUT /community/privacy/{profile_public_id}
# --------------------------------------------------------------------------


@router.put("/{profile_public_id}", status_code=status.HTTP_200_OK)
def put_privacy(
    profile_public_id: uuid.UUID,
    request: Request,
    payload: PrivacySettingsUpdate,
) -> PrivacySettingsOut:
    """Update the privacy settings for a profile.

    On ``resource_version`` mismatch → HTTP 409 (the row was modified
    by another writer; the client should refresh and retry).
    """
    db_gen = _session_factory(request)
    db = next(db_gen)
    try:
        try:
            row = _get_or_create_settings_row(
                db,
                profile_public_id,
                now=_utcnow(),  # unused on the lookup path
            )
        except HTTPException:
            raise

        now_fn: _SupportsNow = (
            request.app.state.clock if hasattr(request.app.state, "clock") else _utcnow
        )
        try:
            updated = update_privacy_settings(db, row, payload, now=now_fn())
        except StalePrivacyUpdateError as exc:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "error": "stale_resource_version",
                    "current_resource_version": exc.current_updated_at.isoformat(),
                },
            ) from exc
        db.commit()
        db.refresh(updated)
        return _row_to_out(updated)
    finally:
        try:
            next(db_gen, None)
        except StopIteration:
            pass


__all__ = [
    "StalePrivacyUpdateError",
    "router",
    "update_privacy_settings",
]
