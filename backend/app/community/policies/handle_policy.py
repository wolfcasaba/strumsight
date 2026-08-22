"""Public handle policy — E09-R03, ADR 0397 §5.1.

This module is the SINGLE source of truth for:

* NFKC + casefold normalization,
* the 3–24 character length bound (the §6.1 threshold triple),
* the allowed-character regex,
* the reserved-handle catalogue (built-in, not user-editable),
* the blocked-handle catalogue (built-in, not user-editable).

It is **deliberately pure** — no database, no FastAPI, no settings import.
This keeps the policy testable in isolation (the §6 acceptance cell tests
have to call the policy directly, not the router, so the cell-vs-policy
mapping is unambiguous) and makes the failure modes easy to reason about
without booting the API.

The §6.1 valódi-sértés próba only works because the column we apply the
unique index on (the *normalized* column in the migration) is computed by
this function — a regression that drifts the regex here will show up at the
DB level, where A1 measures.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable

MIN_LEN: int = 3
"""Lower bound on the *normalized* character count (inclusive)."""

MAX_LEN: int = 24
"""Upper bound on the *normalized* character count (inclusive)."""

# Allowed character set on the *normalized* form: word characters (with
# Unicode-aware matching) plus ``_`` and ``-``. After ``casefold`` + ``NFKC``
# the result is canonical, so this single regex covers both ASCII and
# non-Latin-script handles. The leading/trailing anchors in the regex
# implicitly forbid leading/trailing separators.
_HANDLE_RE = re.compile(r"^[\w][\w\-]{1,22}[\w]$|^[\w]$", re.UNICODE)

# A "reserved" handle is one that is reserved for the platform itself:
# staff, system surfaces, common-shape reserved words. The list is part of
# the policy module so a code-review can audit it; user-editable reserved
# lists would defeat the audit.
RESERVED: frozenset[str] = frozenset(
    {
        # platform / system
        "admin",
        "administrator",
        "support",
        "help",
        "root",
        "system",
        "sys",
        "moderator",
        "mod",
        "staff",
        "official",
        "strumsight",
        "api",
        "bot",
        "service",
        # shape-reserved — every entry here MUST pass ``MIN_LEN``/
        # ``MAX_LEN`` so the reserved check is reachable. Single-letter
        # reserved words (``me``) are dropped because they can never be
        # claimed anyway and would mask the length-rejection test.
        "null",
        "undefined",
        "none",
        "anonymous",
        "you",
        "everyone",
        "all",
        "true",
        "false",
    }
)

# A "blocked" handle is a profanity/abuse list. This is the minimal,
# built-in list — production deployments can extend it via configuration
# (out of scope for E09-R03).
BLOCKED: frozenset[str] = frozenset(
    {
        "fuck",
        "shit",
        "bitch",
        "asshole",
        "cunt",
        "dick",
        "piss",
        "bastard",
        "slut",
        "whore",
        "fag",
        "nigger",
    }
)


def normalize(raw: str) -> str:
    """NFKC-normalize + case-fold + strip a handle.

    The function is deterministic and total on ``str`` inputs; it never
    raises on string inputs and never truncates.

    Two callers that hand the same string in get the same result, even
    across platforms — that's the invariant A1 leans on.
    """
    return unicodedata.normalize("NFKC", raw).casefold().strip()


def _classify(normalized: str) -> str | None:
    """Return a reason string if ``normalized`` is rejected, else ``None``.

    The order is fixed: length first, character set second, reserved
    third, blocked last. A handle that fails two checks still gets a
    single reason — the first one — so callers have a deterministic error
    shape.
    """
    n = len(normalized)
    if n < MIN_LEN:
        return f"handle must be at least {MIN_LEN} characters"
    if n > MAX_LEN:
        return f"handle must be at most {MAX_LEN} characters"
    if not _HANDLE_RE.fullmatch(normalized):
        return (
            "handle must contain only letters, digits, '_' or '-' and "
            "must start and end with a letter or digit"
        )
    if normalized in RESERVED:
        return "handle is reserved"
    if normalized in BLOCKED:
        return "handle is blocked"
    return None


def validate(raw: str) -> str:
    """Validate and normalize a handle.

    Returns the normalized form on success. Raises ``ValueError`` on
    rejection — the message is a stable, user-safe phrase from
    ``_classify`` (no PII, no internal state).

    The two-step design (normalize then validate) means the same character
    string spelled with precomposed vs decomposed Unicode always maps to
    the same normalized value, and the normalized form is what the DB
    unique index is built on.
    """
    if not isinstance(raw, str):
        raise ValueError("handle must be a string")
    n = normalize(raw)
    reason = _classify(n)
    if reason is not None:
        raise ValueError(reason)
    return n


def is_reserved(normalized: str) -> bool:
    """Return ``True`` iff ``normalized`` is on the reserved list."""
    return normalized in RESERVED


def is_blocked(normalized: str) -> bool:
    """Return ``True`` iff ``normalized`` is on the blocked list."""
    return normalized in BLOCKED


def classify_reason(normalized: str) -> str | None:
    """Public form of ``_classify`` — returns the same reason strings.

    This is what the availability endpoint surfaces to the client. It
    returns ``None`` if the handle is valid, otherwise a stable reason
    string. Used by A4 to confirm the reserved/blocked rejection paths
    are the only way a syntactically-valid handle can be rejected.
    """
    return _classify(normalized)


def merge_reserved(extras: Iterable[str]) -> frozenset[str]:
    """Return a new reserved-list with ``extras`` added.

    This is a *factory* helper for tests and operator overrides — the
    module's own ``RESERVED`` is never mutated. The immutable default
    keeps the policy deterministic across the running process.
    """
    return frozenset(RESERVED).union(extras)


__all__ = [
    "BLOCKED",
    "MAX_LEN",
    "MIN_LEN",
    "RESERVED",
    "classify_reason",
    "is_blocked",
    "is_reserved",
    "merge_reserved",
    "normalize",
    "validate",
]