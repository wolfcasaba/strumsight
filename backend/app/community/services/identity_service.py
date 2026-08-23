"""Identity service — E09-R03, ADR 0397 §5.1, §5.2, §5.4.

The three responsibilities of this module are isolated so each can be
unit-tested without booting the rest of the stack:

1. ``PublicIdGenerator`` — the §5.2 *stable, non-guessable* public ID
   requirement. The default implementation is backed by ``secrets``
   (cryptographically secure random), so the UUID v4 cannot be predicted
   from any other field on the row. A ``from_callable`` factory lets tests
   substitute a deterministic source.
2. Handle assignment + change — §5.1 (DB-uniqueness on the *normalized*
   form, NOT the application-level "check-then-insert" anti-pattern) and
   §5.4 (cooldown + redirect window).
3. Lookup — the active handle resolves to a profile; an old handle
   resolves to its redirect target while the redirect window is open.

The DB-level uniqueness is enforced by the unique index on
``community_profiles.handle_normalized`` (the migration). The application
layer raises ``HandleAlreadyClaimed`` only after the DB rejected the
write — never as a *pre-check*. This is the §6.1 measure-matrix row 5
failure mode.
"""

from __future__ import annotations

import secrets
import uuid
from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from typing import Protocol

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

HANDLE_COOLDOWN: timedelta = timedelta(days=14)
"""How long a profile must wait between handle changes."""

HANDLE_REDIRECT_WINDOW: timedelta = timedelta(days=30)
"""How long the old handle keeps redirecting to the new one."""

REDIRECT_WINDOW_ATTR = "redirect_until"
COOLDOWN_LOOKUP_ST = "changed_at"


class _SupportsNowUTC(Protocol):
    def __call__(self) -> datetime: ...


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _secrets_uuid4() -> uuid.UUID:
    """Cryptographically secure UUID v4 — never derive from the internal id.

    The bit layout mirrors ``uuid.uuid4`` (version 4, variant 1), but the
    entropy comes from ``secrets.randbits(128)`` so the value cannot be
    predicted from any other public field. The §6.1 measure-matrix row 2
    ("a public ID az ``id`` bigint stringgé alakítva") is the regression
    this default defends against.
    """
    return uuid.UUID(int=secrets.randbits(128), version=4)


class PublicIdGenerator:
    """Injectable UUID v4 generator.

    The default constructor uses a secrets-backed random source. Tests
    pass a deterministic function through ``__init__`` (or
    ``from_callable``) so a single round can assert exact values without
    mocking the ``uuid`` module globally.
    """

    def __init__(self, generator: Callable[[], uuid.UUID] | None = None) -> None:
        self._generator: Callable[[], uuid.UUID] = generator or _secrets_uuid4

    def __call__(self) -> uuid.UUID:
        return self._generator()

    @classmethod
    def from_callable(cls, fn: Callable[[], uuid.UUID]) -> "PublicIdGenerator":
        return cls(generator=fn)


class HandleAlreadyClaimed(Exception):
    """The DB rejected the handle as a duplicate (unique index hit)."""


class CooldownActive(Exception):
    """The profile tried to change handles inside ``HANDLE_COOLDOWN``."""


def _query_one(
    db: Session,
    sql: str,
    params: dict[str, object],
) -> tuple | None:
    """Run a query and return the first tuple or ``None``.

    Thin wrapper over ``text()`` so the callers don't need to know the
    SQLAlchemy 2.0 ``session.execute().first()`` shape.
    """
    return db.execute(text(sql), params).first()


def _coerce_datetime(value: object) -> datetime | None:
    """Coerce a DB-returned datetime to ``datetime``.

    SQLite returns ``DateTime`` columns as ``str`` through ``text()``
    queries (only ORM-mapped columns get auto-conversion). The service
    uses raw SQL, so the caller would otherwise see strings. This helper
    normalizes both paths to a real ``datetime`` and accepts ``None``
    for empty cells.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        parsed = datetime.fromisoformat(value)
        # SQLite drops tzinfo on round-trip; the migration column is
        # ``DateTime(timezone=True)`` so re-attach UTC.
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    raise TypeError(f"cannot coerce {type(value).__name__} to datetime")


def is_handle_available(
    db: Session,
    normalized: str,
    *,
    exclude_profile_id: int | None = None,
) -> bool:
    """Return ``True`` if no profile currently owns ``normalized``.

    This is the **availability** check (read-only, used by the API to
    return a friendly answer). It is NOT the enforcement — the unique
    index on ``community_profiles.handle_normalized`` is. The application
    check exists so the endpoint can answer "taken" instead of letting
    callers discover it through a 500 on insert.
    """
    if exclude_profile_id is None:
        row = _query_one(
            db,
            "SELECT 1 FROM community_profiles WHERE handle_normalized = :n LIMIT 1",
            {"n": normalized},
        )
    else:
        row = _query_one(
            db,
            "SELECT 1 FROM community_profiles "
            "WHERE handle_normalized = :n AND id != :pid LIMIT 1",
            {"n": normalized, "pid": exclude_profile_id},
        )
    return row is None


def assign_handle(
    db: Session,
    profile_id: int,
    display: str,
    normalized: str,
) -> None:
    """Set a handle on a profile.

    The unique index on ``handle_normalized`` is the enforcement. A
    duplicate raises ``HandleAlreadyClaimed`` after the DB rejects the
    write — this is the §5.1 anti-pattern guard.

    The handle-history row is written here too (initial assignment,
    ``old_handle``/``old_normalized`` ``NULL``, ``redirect_until`` NULL)
    so the lookup path can answer "no active history row" uniformly.

    The function does NOT commit. The caller commits — typically via
    ``commit_with_uniqueness_check`` — so the ``IntegrityError`` ->
    ``HandleAlreadyClaimed`` translation happens at a single chokepoint.
    The UPDATE on the unique index raises ``IntegrityError`` immediately
    on the wire, so the write *cannot* land before the rejection; we
    catch and translate here for caller convenience.
    """
    now = _utcnow()
    try:
        db.execute(
            text(
                "UPDATE community_profiles "
                "SET handle_display = :d, handle_normalized = :n "
                "WHERE id = :id"
            ),
            {"d": display, "n": normalized, "id": profile_id},
        )
        db.execute(
            text(
                "INSERT INTO community_handle_history "
                "(id, profile_id, old_handle, old_normalized, "
                "new_handle, new_normalized, changed_at, redirect_until) "
                "VALUES (:id, :pid, NULL, NULL, :nh, :nn, :at, NULL)"
            ),
            {
                "id": None,
                "pid": profile_id,
                "nh": display,
                "nn": normalized,
                "at": now,
            },
        )
    except IntegrityError as exc:
        db.rollback()
        raise HandleAlreadyClaimed(str(exc)) from exc


def change_handle(
    db: Session,
    profile_id: int,
    new_display: str,
    new_normalized: str,
    *,
    now_fn: _SupportsNowUTC | None = None,
) -> None:
    """Change a handle with cooldown enforcement + history recording.

    The cooldown lookup reads the most recent history row for the
    profile (the initial assignment also counts — the rule is "no two
    handle-related writes within ``HANDLE_COOLDOWN``"). If the gap from
    the last action is shorter than ``HANDLE_COOLDOWN`` the change is
    rejected with ``CooldownActive``. The history row's
    ``redirect_until`` is set to ``now + HANDLE_REDIRECT_WINDOW`` so
    the old handle keeps resolving to this profile for the redirect
    window (A6).

    Like ``assign_handle``, the function does NOT commit. The UPDATE on
    ``community_profiles.handle_normalized`` raises ``IntegrityError``
    immediately on conflict, and the function catches + translates.
    """
    now = (now_fn or _utcnow)()
    last = _query_one(
        db,
        "SELECT changed_at FROM community_handle_history "
        "WHERE profile_id = :pid "
        "ORDER BY changed_at DESC LIMIT 1",
        {"pid": profile_id},
    )
    if last is not None:
        last_changed = _coerce_datetime(last[0])
        assert last_changed is not None
        if now - last_changed < HANDLE_COOLDOWN:
            raise CooldownActive(
                f"handle change cooldown active; next change allowed at "
                f"{(last_changed + HANDLE_COOLDOWN).isoformat()}"
            )

    current = _query_one(
        db,
        "SELECT handle_display, handle_normalized FROM community_profiles "
        "WHERE id = :id",
        {"id": profile_id},
    )
    old_display = current[0] if current else None
    old_normalized = current[1] if current else None

    try:
        db.execute(
            text(
                "UPDATE community_profiles "
                "SET handle_display = :d, handle_normalized = :n "
                "WHERE id = :id"
            ),
            {"d": new_display, "n": new_normalized, "id": profile_id},
        )
        db.execute(
            text(
                "INSERT INTO community_handle_history "
                "(id, profile_id, old_handle, old_normalized, "
                "new_handle, new_normalized, changed_at, redirect_until) "
                "VALUES (:id, :pid, :oh, :on, :nh, :nn, :at, :ru)"
            ),
            {
                "id": None,
                "pid": profile_id,
                "oh": old_display,
                "on": old_normalized,
                "nh": new_display,
                "nn": new_normalized,
                "at": now,
                "ru": now + HANDLE_REDIRECT_WINDOW,
            },
        )
    except IntegrityError as exc:
        db.rollback()
        raise HandleAlreadyClaimed(str(exc)) from exc


def lookup_active_profile_id(db: Session, normalized: str) -> int | None:
    """Return the profile id that currently owns ``normalized`` or ``None``."""
    row = _query_one(
        db,
        "SELECT id FROM community_profiles WHERE handle_normalized = :n LIMIT 1",
        {"n": normalized},
    )
    return None if row is None else int(row[0])


def lookup_redirect_target(
    db: Session,
    old_normalized: str,
    *,
    now_fn: _SupportsNowUTC | None = None,
) -> int | None:
    """Return the profile id that ``old_normalized`` should redirect to.

    The most recent history row where ``old_normalized`` matches and
    ``redirect_until`` is still in the future wins. If the redirect
    window has passed (or no history row exists), the function returns
    ``None`` and the API answers 404.
    """
    now = (now_fn or _utcnow)()
    row = _query_one(
        db,
        "SELECT profile_id FROM community_handle_history "
        "WHERE old_normalized = :n AND redirect_until IS NOT NULL "
        "AND redirect_until > :now "
        "ORDER BY changed_at DESC LIMIT 1",
        {"n": old_normalized, "now": now},
    )
    return None if row is None else int(row[0])


def commit_with_uniqueness_check(db: Session) -> None:
    """Commit the session and convert a DB uniqueness error.

    The unique index on ``community_profiles.handle_normalized`` is the
    enforcement; this helper exists so the router doesn't repeat the
    ``IntegrityError`` -> ``HandleAlreadyClaimed`` translation.
    """
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HandleAlreadyClaimed(str(exc)) from exc


__all__ = [
    "CooldownActive",
    "HANDLE_COOLDOWN",
    "HANDLE_REDIRECT_WINDOW",
    "HandleAlreadyClaimed",
    "PublicIdGenerator",
    "assign_handle",
    "change_handle",
    "commit_with_uniqueness_check",
    "is_handle_available",
    "lookup_active_profile_id",
    "lookup_redirect_target",
]
