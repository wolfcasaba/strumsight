"""User-report service layer — E09-R26, ADR 0422 §5.1.

The service layer for the report module is intentionally narrow:

* :func:`submit_report` — INSERT (or recycle) a row in
  ``community_reports``. Idempotent on the ``(reporter, target_type,
  target_id, category)`` quadruple via the §6 A2 dedup-key. Rate-limit
  guarded (§6 A6). Returns a **sanitized** envelope — the
  ``reporter_public_id`` is never in the response.

* :func:`target_exists` — light-weight probe that respects the
  soft-delete tombstone (``deleted_at IS NULL``). Used by the §6 A4
  "report against a deleted target" handler — the row is still
  inserted (the moderation queue (Kör 27) needs it), but
  ``target_deleted_at_submit`` is set so the report pipeline knows
  the target was already gone at submit time.

* :func:`build_sanitized_response` — the §5.1 invariant helper. Takes
  a ``CommunityReport`` ORM row and returns the wire-shape dict with
  only the public-id and the target-triple. The ``reporter_profile_id``
  is intentionally NEVER read.

The category set is hard-coded here and mirrored in the Flutter
``report_content_sheet`` localized list. Adding a category requires a
DB migration (the value set is not a CHECK on the column), so the
service-layer guard is the primary backstop and the DB is the safety
net. The §6 A5 cell points at the service-layer rejection.

The rate limit is in-memory per process (a single dict keyed on
``reporter_profile_id`` with a sliding 1-hour window). The §6 A6
contract is "no more than N reports per hour per reporter" — a
distributed rate limiter is a future round's call (the brief §3
"engineer-side" note); the in-process limiter is enough for the
single-process dev loop and the test suite.
"""

from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.profile import CommunityProfile
from ..models.report import CommunityReport

# ---------------------------------------------------------------------------
# Category set — the §6 A5 contract. Mirrored in the Flutter
# ``report_content_sheet`` localized list.
# ---------------------------------------------------------------------------

# The category strings are wire-stable — a future round that adds a
# category must update BOTH this set AND the Flutter sheet's category
# list AND the §6.1 measure-matrix test. The Hungarian translations
# live in ``community_hu.arb``; the English text in ``community_en.arb``.
#
# ``self_harm_concern`` is special-cased at the Flutter layer (the
# approved-safety-copy invariant, brief §5.3) — the service layer
# treats it identically to every other category.
REPORT_CATEGORIES: frozenset[str] = frozenset(
    {
        "spam",
        "harassment",
        "hate_speech",
        "violence",
        "sexual_content",
        "self_harm_concern",
        "copyright",
        "privacy",
        "misinformation",
        "other",
    }
)

# The §3 minimal-evidence categories — these accept the optional
# ``extra_metadata_json`` payload from the Flutter sheet (a URL, a
# date). For every other category the field is FORCED to NULL at the
# service layer (the response-sanitization helper also strips it).
EVIDENCE_CATEGORIES: frozenset[str] = frozenset({"copyright", "privacy"})

# ---------------------------------------------------------------------------
# Rate limit (brief §6 A6)
# ---------------------------------------------------------------------------

# 12 reports per hour per reporter — the §6 A6 contract. The cap is
# intentionally generous (a real harassment campaign could legitimately
# surface a dozen pieces of content in an hour) but still bounds the
# "report-spam" abuse pattern. The router surfaces a 429 when the
# cap is exceeded.
REPORT_RATE_LIMIT_MAX = 12
REPORT_RATE_LIMIT_WINDOW_SECONDS = 3600

# ---------------------------------------------------------------------------
# extra_metadata payload cap (brief §3, F2 review fix)
# ---------------------------------------------------------------------------

# The §3 minimal-evidence payload — a small JSON dict with a URL, a
# date, etc. We enforce BOTH a key-count cap (a cheap pre-check that
# bounds pathological dicts before the JSON encoder runs) AND a
# serialized-length cap on the JSON-encoded payload. A future round
# that widens the §3 contract should widen these caps in lockstep.
#
# The router is intentionally untyped (it accepts an untyped ``dict``
# payload and forwards as-is); the service layer is the SOLE
# enforcement point. Oversize payloads raise :class:`InvalidExtraMetadata`
# — the router maps that to HTTP 400 — instead of being truncated to
# invalid JSON.
EXTRA_METADATA_MAX_KEYS = 16
EXTRA_METADATA_MAX_ENCODED_LEN = 2048

# Per-process rate-limit state. The brief §3 calls this out as the
# "engineer-side" note — a distributed limiter (Redis / DB-backed) is
# a future round's call. Tests get a fresh state via
# :func:`reset_rate_limit_state` (the test fixture calls it).
_rate_limit_state: dict[int, list[float]] = {}


def reset_rate_limit_state() -> None:
    """Clear the in-process rate-limit state.

    Called by the test fixture so each test gets a clean slate. NOT
    part of the production API surface — the router never calls this.
    """
    _rate_limit_state.clear()


# ---------------------------------------------------------------------------
# Custom exceptions — the router maps them to HTTP status codes.
# ---------------------------------------------------------------------------


class InvalidCategory(ValueError):
    """§6 A5 — empty or unknown category rejected at the service layer."""


class InvalidExtraMetadata(ValueError):
    """F2 — the optional ``extra_metadata`` payload exceeded the
    service-layer cap (key count or serialized JSON length).

    The service layer is the SOLE enforcement point — the router
    accepts an untyped ``dict`` payload and forwards as-is. A too-
    large payload is rejected explicitly (mapped to HTTP 400 by the
    router) instead of being silently truncated to invalid JSON.
    """


class RateLimitExceeded(Exception):
    """§6 A6 — caller exceeded the per-hour report cap."""


# ---------------------------------------------------------------------------
# Wire-shape dataclass — the §5.1 retaliation-risk invariant
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ReportSubmissionResult:
    """The §5.1 sanitized wire shape — ``report_public_id`` only.

    The reporter's identity (both the internal FK and the public id)
    is intentionally NOT a field on this dataclass. The router must
    never extend this with ``reporter_public_id`` — the §5.1
    retaliation-risk invariant depends on the type-system making the
    omission structurally obvious.
    """

    report_public_id: uuid.UUID
    target_type: str
    target_id: str
    category: str
    created_at: object  # datetime — kept opaque so the router stays naive
    deduplicated: bool


# ---------------------------------------------------------------------------
# Resolution helpers
# ---------------------------------------------------------------------------


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _dedup_key(
    reporter_profile_id: int,
    target_type: str,
    target_id: str,
    category: str,
) -> str:
    """Compute the §6 A2 dedup key.

    The format is deliberately a plain string concatenation — the
    UNIQUE constraint catches a collision regardless of separator
    choice, and the structural ``(reporter, target_type, target_id,
    category)`` UNIQUE in the model is the format-independent
    backstop.
    """
    return f"{reporter_profile_id}:{target_type}:{target_id}:{category}"


# ---------------------------------------------------------------------------
# Target-existence probe (§6 A4)
# ---------------------------------------------------------------------------


def target_exists(
    db: Session,
    *,
    target_type: str,
    target_id: str,
) -> bool:
    """Return ``True`` if ``(target_type, target_id)`` exists and is
    not soft-deleted.

    The probe is intentionally lenient: an unknown ``target_type``
    string returns ``False`` (the moderation queue (Kör 27) can
    classify it later — the report row is preserved regardless).

    For ``"post"`` the probe joins ``community_posts`` on
    ``public_id`` and checks ``deleted_at IS NULL`` (the §6 A4
    soft-delete tombstone, brief §5.3 D7).

    For ``"comment"`` the probe mirrors the post logic against
    ``community_comments``.

    A future round can extend the dispatch with ``"profile"`` /
    ``"club_post"`` / etc. without touching the report pipeline.
    """
    if target_type == "post":
        from ..models.post import CommunityPost

        row = (
            db.query(CommunityPost)
            .filter(CommunityPost.public_id == uuid.UUID(target_id))
            .one_or_none()
        )
        if row is None:
            return False
        return row.deleted_at is None

    if target_type == "comment":
        from ..models.comment import CommunityComment

        row = (
            db.query(CommunityComment)
            .filter(CommunityComment.public_id == uuid.UUID(target_id))
            .one_or_none()
        )
        if row is None:
            return False
        return row.deleted_at is None

    return False


# ---------------------------------------------------------------------------
# Rate-limit guard (§6 A6)
# ---------------------------------------------------------------------------


def _check_rate_limit(reporter_profile_id: int) -> None:
    """Raise :class:`RateLimitExceeded` if the reporter is over the
    §6 A6 hourly cap.

    The window is a sliding 1-hour list of submit timestamps — old
    entries are dropped on each call. The state is in-process; the
    test fixture clears it between tests.
    """
    now = time.monotonic()
    window_start = now - REPORT_RATE_LIMIT_WINDOW_SECONDS
    timestamps = [
        ts
        for ts in _rate_limit_state.get(reporter_profile_id, ())
        if ts >= window_start
    ]
    if len(timestamps) >= REPORT_RATE_LIMIT_MAX:
        raise RateLimitExceeded(
            f"reporter exceeded {REPORT_RATE_LIMIT_MAX} reports per hour"
        )
    timestamps.append(now)
    _rate_limit_state[reporter_profile_id] = timestamps


# ---------------------------------------------------------------------------
# Sanitized-response builder (§5.1)
# ---------------------------------------------------------------------------


def build_sanitized_response(
    row: CommunityReport,
    *,
    deduplicated: bool,
) -> dict[str, object]:
    """Build the §5.1 wire-shape dict from a report row.

    The function returns ONLY the wire-safe fields:

    * ``report_public_id`` — the row's UUID.
    * ``target_type`` / ``target_id`` — the target the report
      references (the reporter already knows these).
    * ``category`` — the category string.
    * ``created_at`` — ISO-8601 UTC timestamp.
    * ``deduplicated`` — ``True`` if the call recycled an existing
      row, ``False`` if it was a fresh INSERT. The Flutter sheet
      uses the flag to decide whether to show the "thanks for
      reporting" view (the A3 immediate-safety-shortcut follow-up).

    The function NEVER reads the reporter identity column. The §5.1
    invariant is enforced at this exact function — a future maintainer
    who tries to add a ``"reporter_public_id"`` key here will fail
    the §6 A1 test.
    """
    return {
        "report_public_id": str(row.public_id),
        "target_type": row.target_type,
        "target_id": row.target_id,
        "category": row.category,
        "created_at": row.created_at.isoformat(),
        "deduplicated": deduplicated,
    }


# ---------------------------------------------------------------------------
# submit_report — the §5.1 / §6 A2 / §6 A4 / §6 A5 / §6 A6 entry point
# ---------------------------------------------------------------------------


def submit_report(
    db: Session,
    *,
    reporter_public_id: uuid.UUID,
    target_type: str,
    target_id: str,
    category: str,
    extra_metadata: dict[str, object] | None = None,
) -> ReportSubmissionResult:
    """Submit (or recycle) a report row.

    The function:

    1. Validates ``category`` against :data:`REPORT_CATEGORIES` —
       raises :class:`InvalidCategory` for empty / unknown values
       (§6 A5). The validation happens BEFORE the rate-limit check so
       a misbehaving caller cannot bypass the cap by sending unknown
       categories.

    2. Resolves the reporter's internal ``profile.id`` from the
       ``reporter_public_id`` — raises ``ValueError`` if the caller
       has no community profile (the router maps this to 404).

    3. Calls :func:`_check_rate_limit` (§6 A6).

    4. Computes ``dedup_key`` and probes for an existing row on the
       same ``(reporter, target_type, target_id, category)``
       quadruple. If present, returns it with ``deduplicated=True``
       (§6 A2). No row is INSERTed on the dedup path.

    5. Probes ``target_exists`` (§6 A4). The row is INSERTed either
       way — the moderation queue (Kör 27) needs it — but the
       ``target_deleted_at_submit`` flag is set so the queue can
       classify it as "report against already-removed content".

    6. INSERTs the row with the optional ``extra_metadata_json``
       payload (only for ``EVIDENCE_CATEGORIES``; the field is
       forced to NULL otherwise — the response-sanitization helper
       strips it from the wire shape regardless).

    7. Returns the sanitized :class:`ReportSubmissionResult`.

    The function NEVER returns the reporter's identity. The §5.1
    invariant is structural at the dataclass level — there is no
    field to leak.
    """
    # Step 1 — category validation (§6 A5).
    if not category or category not in REPORT_CATEGORIES:
        raise InvalidCategory(f"unknown report category: {category!r}")

    # Step 2 — resolve the reporter's internal id.
    reporter = _resolve_profile_by_public_id(db, reporter_public_id)
    if reporter is None:
        raise ValueError("reporter profile not found")

    # Step 3 — rate-limit guard (§6 A6). Validates BEFORE the
    # existence probe so a misbehaving caller cannot use unknown
    # target ids to spam.
    _check_rate_limit(reporter.id)

    # Step 4 — dedup probe (§6 A2).
    dedup = _dedup_key(reporter.id, target_type, target_id, category)
    existing = _existing_report(db, dedup_key=dedup)
    if existing is not None:
        return ReportSubmissionResult(
            report_public_id=existing.public_id,
            target_type=existing.target_type,
            target_id=existing.target_id,
            category=existing.category,
            created_at=existing.created_at,
            deduplicated=True,
        )

    # Step 5 — target-existence probe (§6 A4). Soft-deleted targets
    # are still reported (the moderation queue needs the row), but
    # the flag is set so the queue knows the target was gone at
    # submit time.
    target_was_present = target_exists(db, target_type=target_type, target_id=target_id)

    # Step 6 — INSERT.
    metadata_json = None
    if extra_metadata and category in EVIDENCE_CATEGORIES:
        # The §3 minimal-evidence payload — a small JSON dict with a
        # URL, a date, etc. The F2 review fix: oversize inputs are
        # rejected with :class:`InvalidExtraMetadata` instead of being
        # silently truncated (``encoded[:2048]`` could leave a half-
        # quoted string in the DB). The service layer is the SOLE
        # enforcement point — the router is intentionally untyped and
        # does NOT cap the body.
        if len(extra_metadata) > EXTRA_METADATA_MAX_KEYS:
            raise InvalidExtraMetadata(
                f"extra_metadata has too many keys "
                f"({len(extra_metadata)} > {EXTRA_METADATA_MAX_KEYS})"
            )
        encoded = json.dumps(extra_metadata, separators=(",", ":"))
        if len(encoded) > EXTRA_METADATA_MAX_ENCODED_LEN:
            raise InvalidExtraMetadata(
                f"extra_metadata serialized length {len(encoded)} "
                f"exceeds {EXTRA_METADATA_MAX_ENCODED_LEN}"
            )
        metadata_json = encoded

    row = CommunityReport(
        reporter_profile_id=reporter.id,
        target_type=target_type,
        target_id=target_id,
        category=category,
        extra_metadata_json=metadata_json,
        dedup_key=dedup,
        target_deleted_at_submit=not target_was_present,
    )
    db.add(row)
    try:
        db.flush()
    except IntegrityError:
        # Concurrent writer won the race on the dedup_key UNIQUE.
        # Roll back, re-read, return the existing row — the same
        # idempotent-retry pattern as ``CommunityBlock`` / Kör 7
        # ``CommunityFollow``.
        db.rollback()
        again = _existing_report(db, dedup_key=dedup)
        if again is not None:
            return ReportSubmissionResult(
                report_public_id=again.public_id,
                target_type=again.target_type,
                target_id=again.target_id,
                category=again.category,
                created_at=again.created_at,
                deduplicated=True,
            )
        raise

    return ReportSubmissionResult(
        report_public_id=row.public_id,
        target_type=row.target_type,
        target_id=row.target_id,
        category=row.category,
        created_at=row.created_at,
        deduplicated=False,
    )


# ---------------------------------------------------------------------------
# Internal row lookup (private to this module)
# ---------------------------------------------------------------------------


def _existing_report(db: Session, *, dedup_key: str) -> CommunityReport | None:
    return (
        db.query(CommunityReport)
        .filter(CommunityReport.dedup_key == dedup_key)
        .one_or_none()
    )


__all__ = [
    "EVIDENCE_CATEGORIES",
    "EXTRA_METADATA_MAX_ENCODED_LEN",
    "EXTRA_METADATA_MAX_KEYS",
    "InvalidCategory",
    "InvalidExtraMetadata",
    "RateLimitExceeded",
    "REPORT_CATEGORIES",
    "REPORT_RATE_LIMIT_MAX",
    "REPORT_RATE_LIMIT_WINDOW_SECONDS",
    "ReportSubmissionResult",
    "build_sanitized_response",
    "reset_rate_limit_state",
    "submit_report",
    "target_exists",
]
