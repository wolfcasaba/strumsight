"""Profile-posts read path — E17-R11.

The repository behind ``GET /community/profiles/{public_id}/posts``.
The Flutter ``CommunityFeedRepository`` contract has declared a
``profilePosts`` read since Kör 5 (``feed_repository.dart``), and the
Dart implementation threw ``UnimplementedError`` with a doc-comment
that said, correctly, that the server had "neither a route nor a
service". This module is that missing service.

**Why a third module next to ``following_feed`` and ``club_feed``.**
The three feeds share a row shape and a cursor discipline but differ
in the ONE predicate that decides which rows are candidates:

* following feed — ``profile_id IN (viewer's follow set)``
* club feed      — ``club_id = <club>``
* profile posts  — ``profile_id = <target>``

and, more importantly, in the GATE that runs before the query. The
profile gate is the Kör 4 ``CommunityAccessPolicy`` evaluated against
the TARGET profile's ``community_privacy_settings.visibility``; the
club gate is a membership probe. Fusing them into one function would
mean a single body branching on which gate to run — which is exactly
how a future edit silently applies the wrong gate to the wrong feed.

**What this module enforces (each one is a separate predicate, so a
real-violation probe can flip exactly one):**

1. **Uniform 404 (``ProfileNotVisible``).** Unknown profile, blocked
   pair (either direction), private profile, and followers-only
   profile the viewer does not follow all raise the SAME exception.
   The router turns it into one 404, so a caller cannot tell "no such
   profile" from "exists, you may not see it" (the §5.3 IDOR
   guarantee the post/club read paths already carry).

2. **Owner short-circuit.** A viewer reading their OWN posts sees
   every audience, including ``private`` — the same
   ``viewer_is_owner`` branch ``CommunityAccessPolicy`` takes.

3. **Per-row audience allowlist.** A follower sees ``public`` +
   ``followers``; a non-follower on a PUBLIC profile sees ``public``
   only. The allowlist is explicit, never a ``!= 'private'`` denylist
   (the F4 fix both sibling feeds carry): a future audience value
   added at the Pydantic layer must not leak through the SQL filter.

4. **Club posts are EXCLUDED (``club_id IS NULL``).** A post written
   into a club is club-scoped content: ``club_feed`` serves it only to
   that club's members. Letting it out through the author's profile
   list would hand every club post to anyone who can see the author —
   a leak the club-membership gate exists to prevent. The author's own
   profile list drops them too, so the two surfaces cannot disagree
   about who may see a club post.

5. **Moderation + soft-delete.** ``moderation_state == 'visible'`` and
   ``deleted_at IS NULL``, the Kör 11 invariants.

**Mute is deliberately NOT applied.** A mute hides an author from the
viewer's FEED; it is not a block. This endpoint is only ever reached
by explicitly opening that profile, so filtering here would answer a
direct question ("what has this person posted?") with a silent, empty
lie. The block filter — which IS a safety boundary — stays.

**Cursor.** The same opaque, HMAC-signed ``(created_at, id, version)``
token the two sibling feeds use, with its own version constant so the
three cursor namespaces cannot be crossed (a club cursor replayed
against this endpoint fails the version check and falls back to a
fresh first page).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Final

from sqlalchemy import select, tuple_
from sqlalchemy.orm import Session

from ..models.post import (
    MODERATION_STATE_VISIBLE,
    CommunityPost,
)
from ..models.profile import CommunityPrivacySettings, CommunityProfile
from ..models.social_graph import CommunityFollow
from ..policies.access_policy import (
    CommunityAccessPolicy,
    ProfileAccessLevel,
    ProfileVisibility,
    relationship_context_from_block_flag,
)
from ..policies.query_filters import is_blocked_pair

#: Static cursor version. Distinct from the following-feed and
#: club-feed constants so a token minted by one surface is rejected by
#: the others (the verifier compares the embedded version).
PROFILE_POSTS_CURSOR_VERSION: Final[int] = 1

#: Default page size when the client omits ``page_size``.
DEFAULT_PAGE_SIZE: Final[int] = 25

#: Hard upper bound on the page size, enforced here as well as in the
#: router (belt-and-braces, the ADR 0406 D7 fail-safe).
MAX_PAGE_SIZE: Final[int] = 50

#: The audience values a FOLLOWER (or a viewer of a public profile who
#: follows the author) may see. Explicit allowlist, never a denylist.
FOLLOWER_AUDIENCE_ALLOWLIST: Final[tuple[str, ...]] = ("public", "followers")

#: The audience values a non-follower may see on a PUBLIC profile.
PUBLIC_AUDIENCE_ALLOWLIST: Final[tuple[str, ...]] = ("public",)

#: Every audience — the owner's own view.
OWNER_AUDIENCE_ALLOWLIST: Final[tuple[str, ...]] = (
    "public",
    "followers",
    "private",
)

_CURSOR_TAG_BYTES: Final[int] = 32


class ProfileNotVisible(Exception):
    """The target profile's posts are not visible to this caller.

    Raised on every "not visible FOR YOU" branch — unknown profile,
    blocked pair, private profile, followers-only profile the viewer
    does not follow. The router maps it to a single 404 so the branches
    stay indistinguishable from outside (the D7 uniform-404 IDOR
    guarantee).
    """


@dataclass(frozen=True)
class ProfilePostRow:
    """One post row, shaped like the two sibling feeds' rows.

    Field-for-field identical to ``following_feed.FeedItemRow`` and
    ``club_feed.ClubFeedItemRow`` so ``post_projection.project_page``
    (which types its input structurally as ``PostRowLike``) renders
    this page with the same counters and viewer state as the feeds.
    """

    post_id: int
    post_public_id: uuid.UUID
    profile_id: int
    author_public_id: uuid.UUID
    audience: str
    body: str
    artifact_type: str | None
    artifact_schema_version: int | None
    artifact_payload: dict[str, object] | None
    moderation_state: str
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


@dataclass(frozen=True)
class ProfilePostsPage:
    """One cursor-paginated page of a profile's posts."""

    items: tuple[ProfilePostRow, ...]
    next_cursor: str | None


def _serialize_datetime(value: datetime) -> str:
    """ISO-8601 form for the cursor payload, always tz-qualified."""
    from datetime import timezone

    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _deserialize_datetime(raw: str) -> datetime:
    """Inverse of :func:`_serialize_datetime`."""
    parsed = datetime.fromisoformat(raw)
    if parsed.tzinfo is None:
        from datetime import timezone

        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _sign_cursor(
    cursor_secret: str,
    *,
    created_at: datetime,
    post_id: int,
) -> str:
    """Build the opaque continuation token for the LAST KEPT row."""
    payload = {
        "c": _serialize_datetime(created_at),
        "i": int(post_id),
        "v": int(PROFILE_POSTS_CURSOR_VERSION),
    }
    payload_bytes = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    signature = hmac.new(
        cursor_secret.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[:_CURSOR_TAG_BYTES]
    return (
        base64.urlsafe_b64encode(payload_bytes).decode("ascii")
        + "."
        + base64.urlsafe_b64encode(signature).decode("ascii")
    )


def _verify_cursor(cursor_secret: str, cursor: str) -> tuple[datetime, int] | None:
    """Validate the token; ``None`` on anything malformed or forged.

    The caller's policy on ``None`` is a fresh first page — the
    security boundary never passes an unverified cursor through to the
    query, and never answers a hostile token with a stack trace.
    """
    if "." not in cursor:
        return None
    payload_b64, signature_b64 = cursor.rsplit(".", 1)
    try:
        payload_bytes = base64.urlsafe_b64decode(payload_b64.encode("ascii"))
        signature = base64.urlsafe_b64decode(signature_b64.encode("ascii"))
    except (ValueError, TypeError):
        return None
    expected = hmac.new(
        cursor_secret.encode("utf-8"), payload_bytes, hashlib.sha256
    ).digest()[:_CURSOR_TAG_BYTES]
    if not hmac.compare_digest(signature, expected):
        return None
    try:
        payload = json.loads(payload_bytes.decode("utf-8"))
        if int(payload["v"]) != PROFILE_POSTS_CURSOR_VERSION:
            return None
        return _deserialize_datetime(str(payload["c"])), int(payload["i"])
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        return None


def _coerce_uuid(raw: object) -> uuid.UUID:
    """Coerce the driver-native ``Uuid`` return type to ``uuid.UUID``."""
    if isinstance(raw, uuid.UUID):
        return raw
    if isinstance(raw, str):
        return uuid.UUID(hex=raw)
    return uuid.UUID(str(raw))


def _coerce_datetime(raw: object) -> datetime:
    if isinstance(raw, datetime):
        return raw
    return datetime.fromisoformat(str(raw))


def _visibility_of(db: Session, profile_id: int) -> ProfileVisibility:
    """Read the target's profile visibility, defaulting to PRIVATE.

    A missing privacy row is the safe-default branch: the onboarding
    flow writes one in the same transaction as the profile, so a row
    without one is a broken invariant, and the safe reading of a
    broken invariant is "show nothing" (the ``follow_service._is_private``
    precedent).
    """
    row = (
        db.query(CommunityPrivacySettings.visibility)
        .filter(CommunityPrivacySettings.profile_id == profile_id)
        .one_or_none()
    )
    if row is None:
        return ProfileVisibility.PRIVATE
    try:
        return ProfileVisibility(str(row[0]))
    except ValueError:
        return ProfileVisibility.PRIVATE


def _is_follower(db: Session, *, follower_id: int, followed_id: int) -> bool:
    """``True`` when ``follower_id`` follows ``followed_id``."""
    row = (
        db.query(CommunityFollow.id)
        .filter(
            CommunityFollow.follower_profile_id == follower_id,
            CommunityFollow.followed_profile_id == followed_id,
        )
        .limit(1)
        .first()
    )
    return row is not None


def resolve_visible_target(
    db: Session,
    *,
    viewer_profile_id: int,
    target_public_id: uuid.UUID,
) -> tuple[int, tuple[str, ...]]:
    """Return ``(target internal id, audience allowlist)`` or raise.

    Exposed (not underscore-private) because it is the whole gate: a
    test can drive it directly and assert that each "not visible"
    branch raises the SAME :class:`ProfileNotVisible`, without going
    through the SQL page query.
    """
    target = (
        db.query(CommunityProfile).filter_by(public_id=target_public_id).one_or_none()
    )
    if target is None:
        raise ProfileNotVisible("profile not found")

    if int(target.id) == viewer_profile_id:
        return int(target.id), OWNER_AUDIENCE_ALLOWLIST

    blocked = is_blocked_pair(
        db,
        profile_id_a=viewer_profile_id,
        profile_id_b=int(target.id),
    )
    follower = _is_follower(
        db, follower_id=viewer_profile_id, followed_id=int(target.id)
    )
    relationship = relationship_context_from_block_flag(
        blocked=blocked,
        viewer_is_owner=False,
        is_follower=follower,
        is_club_member=False,
    )
    level = CommunityAccessPolicy().evaluate_profile_access(
        _visibility_of(db, int(target.id)), relationship
    )
    if level is not ProfileAccessLevel.FULL:
        # SUMMARY (blocked / private / followers-only-and-not-a-follower)
        # and NONE both mean "no post list for you" — one exception, so
        # the router cannot accidentally branch on the reason.
        raise ProfileNotVisible("profile not visible")

    allowlist = FOLLOWER_AUDIENCE_ALLOWLIST if follower else PUBLIC_AUDIENCE_ALLOWLIST
    return int(target.id), allowlist


def list_profile_posts(
    db: Session,
    *,
    viewer_profile_id: int,
    target_public_id: uuid.UUID,
    cursor: str | None,
    page_size: int,
    cursor_secret: str,
) -> ProfilePostsPage:
    """Return one cursor-paginated page of ``target_public_id``'s posts.

    Ordering is ``(created_at DESC, id DESC)`` — the same explainable,
    chronological sort the two sibling feeds use; no engagement signal
    reorders anything.

    ``next_cursor`` encodes the LAST RETURNED row, never a filtered-out
    one, so a hidden row's sort key cannot leak through the cursor
    channel.
    """
    if page_size < 1:
        page_size = 1
    if page_size > MAX_PAGE_SIZE:
        page_size = MAX_PAGE_SIZE

    target_id, audience_allowlist = resolve_visible_target(
        db,
        viewer_profile_id=viewer_profile_id,
        target_public_id=target_public_id,
    )

    decoded_cursor = _verify_cursor(cursor_secret, cursor) if cursor else None

    statement = (
        select(
            CommunityPost.id,
            CommunityPost.public_id,
            CommunityPost.profile_id,
            CommunityPost.audience,
            CommunityPost.body,
            CommunityPost.artifact_type,
            CommunityPost.artifact_schema_version,
            CommunityPost.artifact_payload,
            CommunityPost.moderation_state,
            CommunityPost.created_at,
            CommunityPost.updated_at,
            CommunityPost.deleted_at,
        )
        .where(
            CommunityPost.profile_id == target_id,
            CommunityPost.deleted_at.is_(None),
            CommunityPost.moderation_state == MODERATION_STATE_VISIBLE,
            CommunityPost.audience.in_(audience_allowlist),
            # Club-scoped content stays inside the club feed — see the
            # module docstring, point 4.
            CommunityPost.club_id.is_(None),
        )
        .order_by(
            CommunityPost.created_at.desc(),
            CommunityPost.id.desc(),
        )
        .limit(page_size + 1)
    )
    if decoded_cursor is not None:
        statement = statement.where(
            tuple_(CommunityPost.created_at, CommunityPost.id)
            < tuple_(decoded_cursor[0], decoded_cursor[1])
        )

    rows = db.execute(statement).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    if not rows:
        return ProfilePostsPage(items=(), next_cursor=None)

    author_public_id = _coerce_uuid(
        db.query(CommunityProfile.public_id)
        .filter(CommunityProfile.id == target_id)
        .one()[0]
    )

    items = tuple(
        ProfilePostRow(
            post_id=int(row.id),
            post_public_id=_coerce_uuid(row.public_id),
            profile_id=int(row.profile_id),
            author_public_id=author_public_id,
            audience=str(row.audience),
            body=str(row.body),
            artifact_type=row.artifact_type,
            artifact_schema_version=(
                int(row.artifact_schema_version)
                if row.artifact_schema_version is not None
                else None
            ),
            artifact_payload=row.artifact_payload,
            moderation_state=str(row.moderation_state),
            created_at=_coerce_datetime(row.created_at),
            updated_at=_coerce_datetime(row.updated_at),
            deleted_at=(
                _coerce_datetime(row.deleted_at) if row.deleted_at is not None else None
            ),
        )
        for row in rows
    )

    next_cursor: str | None = None
    if has_more:
        last = rows[-1]
        next_cursor = _sign_cursor(
            cursor_secret,
            created_at=_coerce_datetime(last.created_at),
            post_id=int(last.id),
        )
    return ProfilePostsPage(items=items, next_cursor=next_cursor)


__all__ = [
    "DEFAULT_PAGE_SIZE",
    "FOLLOWER_AUDIENCE_ALLOWLIST",
    "MAX_PAGE_SIZE",
    "OWNER_AUDIENCE_ALLOWLIST",
    "PROFILE_POSTS_CURSOR_VERSION",
    "PUBLIC_AUDIENCE_ALLOWLIST",
    "ProfileNotVisible",
    "ProfilePostRow",
    "ProfilePostsPage",
    "list_profile_posts",
    "resolve_visible_target",
]
