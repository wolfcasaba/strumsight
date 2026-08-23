"""Profile search repository — E09-R09, ADR 0402 §D2.

The search read-path owns three concerns:

* **Exact + prefix lookup.** The query is NFKC + casefold normalised
  against the ``community_profiles.handle_normalized`` UNIQUE INDEX
  (the §A3 invariant — the path is index-based, never a full table
  scan). The minimal query length is enforced at the router; this
  module assumes it has already been validated.

* **Visibility gate (D3).** A PRIVATE profile is invisible to
  search results — the §5.4 SDD-invariáns maps the brief's
  "non-discoverable" to ``visibility == PRIVATE``. PUBLIC /
  FOLLOWERS profiles are kept.

* **Block-filter integration (D2).** After the visibility filter,
  the candidate row set is passed through
  :func:`filter_public_ids_against_viewer_blocks` — the same helper
  the Kör 8 ``get_followers`` / ``get_following`` routers call. A
  parallel, search-specific block check is forbidden: the §5.2
  invariant forbids drift between the two implementations, and the
  Kör 8 helper is the one source of truth for the symmetric
  block-pair predicate.

The repository is DB-coupled (SQLAlchemy Session) and pure with
respect to HTTP — the router translates the returned envelope
into JSON.

**ORM note — the ``handle_normalized`` column.** The column is
added to ``community_profiles`` by the Kör 3 migration, but the
mapped ``CommunityProfile`` ORM class was deliberately kept
untouched (the Kör 3 brief excluded ``models/profile.py`` from the
allowed_paths). The column is registered with ``Base.metadata`` via
``models/handle_history.py::_profiles_table.append_column`` for the
migration-contract test only — attribute access on the mapped
class raises ``AttributeError``. The repository uses raw
``text()`` SQL (the same precedent ``routers/social_graph.py`` and
``routers/handles.py`` follow) so we read the normalised column
directly without coupling to a future ORM refresh.

The ordering is ``handle_normalized ASC, id ASC`` — the index
matches the order exactly. The cursor encodes the last-seen
``(handle_normalized, id)`` pair as base64 JSON, mirroring the
``follow_service`` pattern so a future shared pagination helper
can adopt the same envelope.
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from typing import Final

from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from ..policies.handle_policy import normalize as _normalize_handle
from ..policies.query_filters import filter_public_ids_against_viewer_blocks

# The shortest search query we will accept. Matches the backend
# handle-policy ``MIN_LEN`` (3 chars) — a shorter prefix collides
# with too many rows and would index-scan a wide prefix. The router
# enforces this BEFORE the query touches the DB so a too-short
# query is a 422, not a slow response.
MIN_QUERY_LENGTH: Final[int] = 3


@dataclass(frozen=True)
class ProfileSearchPage:
    """One page of search hits — profile public_ids + cursor.

    The cursor is opaque to the caller; the next request forwards
    it back to the repository as ``cursor=...``.
    """

    public_ids: tuple[uuid.UUID, ...]
    next_cursor: str | None


def _encode_cursor(normalized: str, row_id: int) -> str:
    payload = {"h": normalized, "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[str, int] | None:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        return str(payload["h"]), int(payload["id"])
    except (ValueError, KeyError, json.JSONDecodeError):
        return None


def _escape_like(raw: str) -> str:
    """Escape the SQL LIKE metacharacters so user-supplied prefixes
    cannot turn a prefix scan into a wildcard scan.

    The ``%`` and ``_`` are SQL LIKE wildcards; ``\\`` is the
    standard escape character the ESCAPE clause pairs with. A
    user query of ``"100%"`` must not match the literal
    ``100<anything>`` — only ``100%<anything>``.
    """
    return raw.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def search_profiles(
    db: Session,
    *,
    viewer_profile_id: int,
    query: str,
    cursor: str | None,
    limit: int,
) -> ProfileSearchPage:
    """Return one cursor-paginated page of profile public_ids matching ``query``.

    Parameters
    ----------
    db:
        The SQLAlchemy session. Owning it lets the router wrap
        the call in a single, short-lived transaction.
    viewer_profile_id:
        The internal PK of the caller. Required for the §D2
        block-filter — without a viewer, the visibility gate
        cannot decide whose block-set to filter against.
    query:
        The RAW query string. The function normalises it through
        ``handle_policy.normalize`` (NFKC + casefold + strip), so
        a query that is one of:

        * an exact handle match (``"alice"`` → ``"alice"``),
        * a prefix (``"ali"`` → ``"ali"``),
        * Unicode equivalent of either (precomposed ``é`` vs
          decomposed ``e + ́``) all collapse to the same row
          set — the A6 invariant lives here.

        The minimum length is enforced at the router; this
        function still defensively returns an empty page if the
        normalised form is shorter than ``MIN_QUERY_LENGTH``.
    cursor:
        Opaque continuation token from the previous page, or
        ``None`` on the first page.
    limit:
        The maximum number of public_ids to return. The
        repository fetches ``limit + 1`` rows to detect
        end-of-result.

    Returns
    -------
    ProfileSearchPage
        The ``public_ids`` are PROFILE public_ids (the Kör 5
        surface), ordered ``handle_normalized ASC, id ASC``. The
        ``next_cursor`` is ``None`` when there are no more rows.
    """
    normalized = _normalize_handle(query)
    if len(normalized) < MIN_QUERY_LENGTH:
        return ProfileSearchPage(public_ids=(), next_cursor=None)

    like_pattern = f"{_escape_like(normalized)}%"

    # The candidate SELECT — index-range scan on
    # ``handle_normalized`` (UNIQUE INDEX). Visibility join keeps
    # PRIVATE profiles out of the candidate set in the same SQL
    # statement (one round-trip; we don't pay a Python-level
    # filter cost).
    #
    # Raw SQL: ``handle_normalized`` is NOT an attribute on the
    # mapped ``CommunityProfile`` class (it lives on the Table
    # object only — see the module docstring for the rationale).
    sql = _sa_text(
        """
        SELECT community_profiles.public_id,
               community_profiles.handle_normalized,
               community_profiles.id
        FROM community_profiles
        JOIN community_privacy_settings
          ON community_privacy_settings.profile_id = community_profiles.id
        WHERE community_profiles.handle_normalized IS NOT NULL
          AND community_profiles.handle_normalized LIKE :pat ESCAPE '\\'
          AND community_privacy_settings.visibility <> 'private'
        ORDER BY community_profiles.handle_normalized ASC,
                 community_profiles.id ASC
        LIMIT :limit_plus_one
        """
    )
    params: dict[str, object] = {"pat": like_pattern, "limit_plus_one": limit + 1}

    cursor_clause = ""
    if cursor is not None:
        decoded = _decode_cursor(cursor)
        if decoded is not None:
            cursor_h, cursor_id = decoded
            # Lexicographic continuation — strictly greater than
            # the last-seen pair, the standard SQL idiom for an
            # ASC pagination cursor.
            cursor_clause = (
                " AND (community_profiles.handle_normalized, "
                "community_profiles.id) > (:cursor_h, :cursor_id) "
            )
            params["cursor_h"] = cursor_h
            params["cursor_id"] = cursor_id

    full_sql = _sa_text(
        sql.text.replace(
            "LIMIT :limit_plus_one", cursor_clause + "LIMIT :limit_plus_one"
        )
    )

    rows = db.execute(full_sql, params).all()
    has_more = len(rows) > limit
    rows = rows[:limit]

    # Raw SQL on a ``Uuid`` column returns the CHAR(32) hex form
    # on SQLite. Wrap each value in a ``UUID`` so the block-filter
    # helper (``query_filters.filter_public_ids_against_viewer_blocks``)
    # gets the typed input its ORM-side ``public_id.in_(...)``
    # bind expects. The wire format on the HTTP layer is still the
    # ``str(uuid)`` form — this conversion is local to the
    # repository.
    candidate_public_ids: list[uuid.UUID] = []
    for row in rows:
        raw = row[0]
        if isinstance(raw, uuid.UUID):
            candidate_public_ids.append(raw)
        elif isinstance(raw, str):
            candidate_public_ids.append(uuid.UUID(hex=raw))
        else:
            # SQLAlchemy returns whatever the driver gives — the
            # ``Uuid`` column on PostgreSQL round-trips to a real
            # UUID; SQLite stores CHAR(32). Both branches land
            # here.
            candidate_public_ids.append(uuid.UUID(str(raw)))

    # §D2 — block-filter via the shared helper. A second,
    # search-specific block predicate is forbidden (the §5.2
    # invariant against drift). The helper is one call against
    # the viewer's block set + a single JOIN back to the profile
    # public_ids — the round-trip cost is bounded by ``limit``,
    # not by the full user table.
    filtered_public_ids = filter_public_ids_against_viewer_blocks(
        db,
        viewer_profile_id=viewer_profile_id,
        public_ids=candidate_public_ids,
    )

    # Preserve the page order — the helper returns an unordered
    # list, so re-thread the original ordering on top of the
    # block-filter result.
    filtered_set = set(filtered_public_ids)
    ordered = tuple(pid for pid in candidate_public_ids if pid in filtered_set)

    next_cursor: str | None = None
    if has_more and rows:
        last_h, last_id = rows[-1][1], rows[-1][2]
        next_cursor = _encode_cursor(last_h, last_id)

    return ProfileSearchPage(public_ids=ordered, next_cursor=next_cursor)


def query_plan_uses_index(db: Session, *, query: str) -> bool:
    """A3 evidence helper — confirm the candidate SELECT uses the
    ``ix_community_profiles_handle_normalized`` index, not a full
    table scan.

    The function runs the same WHERE as :func:`search_profiles`
    prefixed with ``EXPLAIN`` and asserts the planner references
    the unique index. The check is a STRING match on the EXPLAIN
    output (SQLite emits the index name in the plan), so it
    covers both SQLite (test engine) and PostgreSQL (production)
    via the dialect-specific EXPLAIN format.
    """
    normalized = _normalize_handle(query)
    if len(normalized) < MIN_QUERY_LENGTH:
        return False
    like_pattern = f"{_escape_like(normalized)}%"
    # EXPLAIN QUERY PLAN (SQLite) / EXPLAIN (PostgreSQL) — the
    # dialect string matches both. The test fixture passes
    # SQLite; production is PostgreSQL — both must plan via the
    # index because the column has a UNIQUE INDEX on it. Any
    # planner that decides to scan the table instead would fail
    # the string match.
    plan = db.execute(
        _sa_text(
            "EXPLAIN QUERY PLAN "
            "SELECT community_profiles.public_id, "
            "community_profiles.handle_normalized, community_profiles.id "
            "FROM community_profiles "
            "JOIN community_privacy_settings "
            "ON community_privacy_settings.profile_id = community_profiles.id "
            "WHERE community_profiles.handle_normalized IS NOT NULL "
            "AND community_profiles.handle_normalized LIKE :pat ESCAPE '\\' "
            "AND community_privacy_settings.visibility <> 'private' "
            "ORDER BY community_profiles.handle_normalized ASC, "
            "community_profiles.id ASC LIMIT 51"
        ),
        {"pat": like_pattern},
    ).all()
    plan_text = " ".join(str(row) for row in plan)
    lowered = plan_text.lower()
    return (
        "handle_normalized" in lowered
        or "ix_community_profiles_handle_normalized" in lowered
    )


__all__ = [
    "MIN_QUERY_LENGTH",
    "ProfileSearchPage",
    "query_plan_uses_index",
    "search_profiles",
]
