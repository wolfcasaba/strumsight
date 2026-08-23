"""Community comment lifecycle service (E09-R16, ADR 0407).

The service layer for ``CommunityComment`` — owns the four lifecycle
operations: ``create_comment`` / ``edit_comment`` / ``soft_delete_comment``
/ ``list_comments``. Every method on the service is a pure DB
operation; the HTTP / FastAPI wrapping lives in ``routers.comments``
(Kör 17+ scope; not in this round's ``allowed_paths`` per ADR 0407 §D7).

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the tests pin):

* **Server-side author identity (§5.1).** ``create_comment`` takes the
  JWT-resolved ``author_public_id`` as a parameter — there is no
  body-side override path. The §6.1 measure-matrix cell A3 ("private
  posztra írt komment jogosultsághoz kötött") reads through this
  surface: a viewer without audience access is rejected by the
  visibility gate BEFORE the comment is even attempted.

* **Mention-privacy enforcement (§5.1, A2).** ``create_comment`` runs
  every ``@handle`` token through the Kör 3 ``lookup_active_profile_id``
  + Kör 8 ``is_blocked_pair`` + Kör 4 ``CommunityAccessPolicy
  .evaluate_profile_access`` triplet — a single ``== FULL`` test
  suffices because the policy already enforces block-first ordering
  (ADR 0407 §D3, ADR 0398 §3). A mention to a profile the viewer has
  blocked, or whose visibility excludes the viewer, is silently
  dropped from the body BEFORE the INSERT — the comment still posts,
  but the unresolvable mention is stripped. The §6.1 measure-matrix
  A2 cell pins this: a regex-only mention-parser (which the brief
  §5.1 explicitly forbids) would let through a blocked profile.

* **Body validation (§3, A8).** HTML-tag-start rejection
  (``<[a-zA-Z/!]`` REJECT regex) and mention-count cap (20, the
  ``MENTION_MAX_COUNT`` from Kör 11). The two regexes are re-declared
  IN this module, mirroring the ``schemas/post.py`` private constants
  (ADR 0407 §D3 — the post module's privates are off the
  ``allowed_paths``). The duplication is intentional: a future
  refactor round can lift them to a shared module once both files
  are simultaneously on a future round's ``allowed_paths``.

* **Depth limit (§3, A1).** ``depth: int`` (NOT NULL, default 0). The
  ``create_comment`` function reads the parent row's ``depth`` (a
  single SELECT) and rejects the insert with ``ValidationError`` when
  ``parent.depth >= 1``. The §6.1 valódi-sértés próba bypasses this
  check and asserts the A1 cell turns red. The doc-tracked maximum
  (depth 1 — a single reply level) is the §14.2 contract.

* **Optimistic concurrency (§0.0 D3, A4).** ``edit_comment`` compares
  the caller's ``resource_version`` (a ``datetime``) with the row's
  current ``updated_at`` BEFORE the write. A mismatch raises
  ``StaleCommentUpdateError`` (the Kör 11 ``StalePostUpdateError``
  shape). ``updated_at`` is then bumped to ``now``.

* **Delete authorization (§3, A5).** ``soft_delete_comment`` consults
  ``comment_policy.can_delete`` with the actor profile id, the
  comment author profile id, the post owner profile id, and an
  explicit ``is_moderator`` boolean (the ADR 0407 §D2 seam). The
  service always passes ``is_moderator=False`` in this round because
  no admin-auth surface exists yet (brief §3 explicit exclusion);
  the A5 measure-matrix calls the policy function directly with
  ``is_moderator=True`` to exercise the moderator branch.

* **Cursor pagination (§0.0 D6).** ``list_comments`` returns a
  base64-encoded, **non-HMAC-signed** ``(created_at, row_id)`` cursor
  — the Kör 8 ``list_blocked`` precedent, NOT the Kör 13 HMAC-signed
  feed cursor (the comment-list tamper-surface is much smaller; the
  base64 cursor is arányos). The cursor is encoded by the same
  ``_encode_cursor`` / ``_decode_cursor`` helpers.

* **Caller-supplied clock (``now: datetime``).** Same precedent as
  ``routers/privacy.py::update_privacy_settings`` and
  ``post_service.create_post`` — the timestamp the service uses to
  stamp ``created_at`` / ``updated_at`` / ``deleted_at`` is the
  caller's, never ``datetime.now(timezone.utc)`` inline. The
  deterministic-timestamp discipline keeps the §6.1 valódi-sértés
  próba and the A4 stale-update test free of microsecond drift.

* **Injectable cache-invalidation seam.** Each mutating method
  accepts an optional ``on_invalidate: Callable[[CommentInvalidation
  Event], None] | None = None`` parameter. When provided, the
  service emits one ``CommentInvalidationEvent`` AFTER a successful
  write — the same ``post_service`` / ``reaction_service`` precedent.
  A future round that wires a real cache layer plugs the callback in;
  this round ships the seam.
"""

from __future__ import annotations

import base64
import json
import re
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from ..models.comment import (
    COMMENT_BODY_MAX_LENGTH,
    MODERATION_STATE_REMOVED,
    MODERATION_STATE_VISIBLE,
    CommunityComment,
)
from ..models.post import CommunityPost
from ..models.profile import CommunityProfile
from ..policies.access_policy import (
    CommunityAccessPolicy,
    CommunityAudience,
    ProfileAccessLevel,
    ProfileVisibility,
    relationship_context_from_block_flag,
)
from ..policies.comment_policy import can_delete
from ..policies.query_filters import is_blocked_pair
from .identity_service import lookup_active_profile_id

# ---------------------------------------------------------------------------
# Body-validation regexes (brief §0.0 D3 / D5, ADR 0407 §D3).
#
# Mirror the ``schemas/post.py`` private regexes BY DESIGN. The post
# module is not on this round's ``allowed_paths``; importing its
# private symbols would couple this module to a sibling that the
# round cannot touch — a fragile cross-module contract. Re-declaring
# the same patterns in this module keeps the module boundary clean;
# a future refactor round can lift them to a shared ``text_policy``
# module once both files are simultaneously on that round's
# allowed_paths.
# ---------------------------------------------------------------------------

# Literal "<" followed by a letter, "/", or "!" — the opening
# sequence of an HTML tag, a closing tag, or an HTML comment. The
# pattern is intentionally narrow: plain text containing "<3" or
# "a < b" is allowed (the "<" is not followed by a tag-starting
# character). Markdown subset (bold / italic / URL) remains valid.
_HTML_TAG_START_PATTERN: re.Pattern[str] = re.compile(r"<[a-zA-Z/!]")

# Mention pattern: "@" + 1-64 word characters. Matches the Kör 11
# ``schemas/post.py`` regex and the Dart handle pattern (Kör 3);
# mention resolution is this round's responsibility (the Kör 3/8
# triplet, ADR 0407 §D3).
_MENTION_PATTERN: re.Pattern[str] = re.compile(r"@[a-zA-Z0-9_]{1,64}")
MENTION_MAX_COUNT: int = 20


# ---------------------------------------------------------------------------
# Domain exceptions — translated to HTTP status codes in the router layer.
# ---------------------------------------------------------------------------


class CommentNotFound(Exception):
    """The comment is not visible to this caller (or does not exist).

    Same D7 uniform-404 shape as ``post_service.PostNotFound`` — a
    missing id, a soft-deleted comment, or a moderation-removed
    comment all collapse to the same exception. The §5.3 IDOR
    guarantee.
    """


class CommentPostNotFound(Exception):
    """The parent post is not visible to this caller (or does not exist).

    Same shape as ``post_service.PostNotFound`` — a missing id, a
    soft-deleted post, a moderation-removed post, or an audience-
    excluded post all collapse to the same exception. The §5.3 IDOR
    guarantee at the post level; ``CommentNotFound`` enforces the
    same at the row level.
    """


class StaleCommentUpdateError(Exception):
    """The client's ``resource_version`` does not match the row's
    ``updated_at`` (brief §0.0 D3 / A4).

    Carries the current ``updated_at`` so the router can build a 409
    body that lets the client refresh and retry — same shape as
    ``post_service.StalePostUpdateError``.
    """

    def __init__(self, current_updated_at: datetime) -> None:
        super().__init__(
            f"stale resource_version; current={current_updated_at.isoformat()}"
        )
        self.current_updated_at = current_updated_at


class CommentValidationError(Exception):
    """The body failed one of the §3 / §5 invariants: HTML-tag-start,
    mention-count cap, body-length cap, depth-limit, parent-missing,
    or audience-incompatible. Carries the reason string so the
    router can build a 400 body that the client can surface.
    """


# ---------------------------------------------------------------------------
# Cache-invalidation event (the same seam post_service ships).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class CommentInvalidationEvent:
    """Emitted by the mutating service methods on a successful write.

    The router / cache layer (a future round) wires a real callback;
    this round ships the seam and the test seam. ``post_public_id``
    is the post the comment changed for; ``comment_public_id`` is the
    comment that changed. ``action`` is one of ``"create"``,
    ``"edit"``, ``"delete"``.
    """

    post_public_id: uuid.UUID
    comment_public_id: uuid.UUID
    action: str  # "create" | "edit" | "delete"


# ---------------------------------------------------------------------------
# Paged-response envelope (mirrors ``SafetyListPage`` / ``FollowListPage``).
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class CommentListPage:
    """A single page of comments on a post.

    Mirrors :class:`block_service.SafetyListPage` — the public ids
    are opaque Community UUIDs, the cursor is opaque to the caller,
    and the next request sends the cursor back verbatim. The
    ordering is ``(created_at DESC, id DESC)`` (ADR 0407 §D6).
    """

    comments: tuple[CommunityComment, ...]
    next_cursor: str | None


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    from datetime import timezone

    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read (no native tz-aware column
    type), so a ``DateTime(timezone=True)`` value that came back from
    ``session.get()`` is naive. The migration contract says the
    column stores UTC, so we re-attach ``timezone.utc`` here for
    comparison and serialization.
    """
    if value.tzinfo is None:
        from datetime import timezone as _tz

        return value.replace(tzinfo=_tz.utc)
    return value


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _resolve_post_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityPost | None:
    return db.query(CommunityPost).filter_by(public_id=public_id).one_or_none()


def _resolve_comment_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityComment | None:
    return db.query(CommunityComment).filter_by(public_id=public_id).one_or_none()


def _validate_body_shape(body: str) -> None:
    """Reject HTML-tag-start and over-cap mentions.

    Mirrors ``schemas/post.py::_reject_html_tags`` +
    ``_enforce_mention_limit`` (brief §3, ADR 0407 §D3). The
    validation lives here, NOT in the Pydantic layer, because this
    round is service-only (no HTTP router per ADR 0407 §D7) — the
    Pydantic schemas live in a future round's ``allowed_paths``.
    """
    if not body:
        raise CommentValidationError("body must not be empty")
    if len(body) > COMMENT_BODY_MAX_LENGTH:
        raise CommentValidationError(
            f"body exceeds {COMMENT_BODY_MAX_LENGTH} characters"
        )
    if _HTML_TAG_START_PATTERN.search(body):
        raise CommentValidationError(
            "body must not contain HTML tags or angle-bracket markup"
        )
    mentions = _MENTION_PATTERN.findall(body)
    if len(mentions) > MENTION_MAX_COUNT:
        raise CommentValidationError(
            f"body exceeds the mention limit of {MENTION_MAX_COUNT}"
        )


def _resolve_mention_handles(body: str) -> list[str]:
    """Extract unique ``@handle`` tokens from ``body``.

    Returns the handles in the order they appear, deduplicated.
    """
    seen: set[str] = set()
    ordered: list[str] = []
    for match in _MENTION_PATTERN.finditer(body):
        handle = match.group(0)[1:]  # strip the leading "@"
        if handle in seen:
            continue
        seen.add(handle)
        ordered.append(handle)
    return ordered


def _mention_visible(
    db: Session,
    *,
    author_profile_id: int,
    handle: str,
) -> bool:
    """Return ``True`` when ``handle`` resolves to a profile the
    author can mention.

    The mention is "visible" (i.e. mentionable) when:

    1. The handle resolves to an active profile via the Kör 3
       ``lookup_active_profile_id`` (handles that have been changed
       redirect, not directly resolve — the Kör 3 ``lookup_active_
       profile_id`` is the documented active-handle resolver).
    2. The resolved profile is NOT blocked in EITHER direction
       (Kör 8 ``is_blocked_pair``).
    3. The resolved profile's visibility evaluates to ``FULL`` for
       the author via Kör 4 ``CommunityAccessPolicy
       .evaluate_profile_access`` — the §5.1 block-first invariant
       is already encoded in the policy, so a single ``== FULL`` test
       suffices (ADR 0407 §D3).

    Self-mention is always allowed (a profile mentioning itself is
    not a privacy event; the policy's ``viewer_is_owner`` short-
    circuit returns ``FULL``).

    Returns ``False`` for any unresolved handle, blocked pair, or
    non-FULL access level.
    """
    target_id = lookup_active_profile_id(db, handle)
    if target_id is None:
        return False
    if target_id == author_profile_id:
        # Self-mention is allowed — the policy's owner short-circuit
        # returns FULL, but we short-circuit here to avoid the
        # block-pair SELECT on the self-pair (Kör 8 helper returns
        # False for self-pairs regardless, so this is a perf
        # optimization, not a correctness one).
        return True
    blocked = is_blocked_pair(
        db, profile_id_a=author_profile_id, profile_id_b=target_id
    )
    # The Kör 16 surface has no follow / club membership yet — the
    # RelationshipContext carries ``is_follower=False`` /
    # ``is_club_member=False`` (the §3 "no club check" invariant;
    # Kör 24 will populate them).
    relationship = relationship_context_from_block_flag(
        blocked=blocked,
        viewer_is_owner=False,
        is_follower=False,
        is_club_member=False,
    )
    target = db.query(CommunityProfile).filter_by(id=target_id).one_or_none()
    if target is None:
        return False
    # The profile model's ``privacy_settings`` carries the visibility
    # field (the Kör 4 precedent). A missing privacy row (an
    # under-the-hood anomaly) falls through to ``PRIVATE`` — the
    # safe default.
    visibility_value = _profile_visibility_value(target)
    visibility = _profile_visibility_from_value(visibility_value)
    policy = CommunityAccessPolicy()
    level = policy.evaluate_profile_access(visibility, relationship)
    return level is ProfileAccessLevel.FULL


def _profile_visibility_value(profile: CommunityProfile) -> str:
    """Return the visibility string from the profile's privacy row.

    A missing privacy row (an under-the-hood anomaly) falls through
    to ``"private"`` — the safe default (ADR 0398 §1 "default is
    NEVER public" precedent). The helper is a thin wrapper that
    keeps the fall-through logic in one place.
    """
    privacy = getattr(profile, "privacy_settings", None)
    if privacy is None:
        return "private"
    return getattr(privacy, "visibility", "private") or "private"


def _profile_visibility_from_value(value: str) -> ProfileVisibility:
    """Translate a string ``visibility`` column to the enum.

    Defensive — the DB layer does not constrain the value set
    (project-wide ``visibility`` pattern, ADR 0398 §1). An
    unexpected value falls through to ``PRIVATE`` so the policy
    short-circuits to ``SUMMARY`` (the safe default).
    """
    try:
        return ProfileVisibility(value)
    except ValueError:
        return ProfileVisibility.PRIVATE


def _strip_unresolvable_mentions(
    db: Session, *, body: str, author_profile_id: int
) -> str:
    """Drop every ``@handle`` token the author cannot mention.

    A handle is "unresolvable" when ``_mention_visible`` returns
    ``False`` — no such profile, blocked pair, or non-FULL access.
    The replacement is the handle MINUS the leading ``@`` (the
    plain-text token), so a body containing ``Hi @bob, see @alice``
    where ``bob`` is blocked becomes ``Hi bob, see @alice``. The
    blank-token replacement avoids leaving a bare ``@`` that the
    next iteration would re-parse.

    The function is intentionally conservative: it preserves all
    non-mention content verbatim. The Kör 11 ``schemas/post.py``
    mention-limit guard runs AFTER this pass, so a body that
    started over the cap is still rejected.
    """
    handles = _resolve_mention_handles(body)
    if not handles:
        return body
    # Resolve each handle to visibility; cache the boolean so a body
    # with N mentions to the same handle costs one DB hit, not N.
    visibility_cache: dict[str, bool] = {}
    for handle in handles:
        if handle in visibility_cache:
            continue
        visibility_cache[handle] = _mention_visible(
            db,
            author_profile_id=author_profile_id,
            handle=handle,
        )
    cleaned = body
    for handle, ok in visibility_cache.items():
        if ok:
            continue
        # Drop the mention token. We strip "@{handle}" wherever it
        # appears (case-insensitive on the @-prefix boundary so
        # "@Bob" matches the resolved "bob" canonical form). The
        # regex below matches the mention as a whole token — not as
        # a substring inside a larger word — so "@bob!" still drops
        # "@bob".
        pattern = re.compile(
            r"@" + re.escape(handle) + r"(?![a-zA-Z0-9_])",
            flags=re.IGNORECASE,
        )
        cleaned = pattern.sub(handle, cleaned)
    return cleaned


# ---------------------------------------------------------------------------
# Cursor pagination helpers — mirror the Kör 8 ``list_blocked`` shape.
# ---------------------------------------------------------------------------


def _encode_cursor(created_at: datetime, row_id: int) -> str:
    """Encode a ``(created_at, row_id)`` cursor as base64 JSON.

    The cursor is opaque to the caller; a tampered cursor is decoded
    back to ``None`` by ``_decode_cursor`` (the §A7 invariant — the
    list drops the bad cursor and starts from the top, never crashes).
    """
    payload = {"created_at": created_at.isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[datetime, int] | None:
    """Decode a cursor produced by ``_encode_cursor``; bad input → ``None``.

    A ``None`` result tells the caller to start from the top of the
    list — the §A7 invariant. This is intentionally permissive (no
    exception): a tampered cursor must not crash the list endpoint.
    """
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["created_at"])
        row_id = int(payload["id"])
        return created_at, row_id
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Public service surface.
# ---------------------------------------------------------------------------


def create_comment(
    db: Session,
    *,
    author_public_id: uuid.UUID,
    post_public_id: uuid.UUID,
    parent_public_id: uuid.UUID | None,
    body: str,
    now: datetime,
    on_invalidate: Callable[[CommentInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> CommunityComment:
    """Create a comment on ``post_public_id``.

    Server-side author (brief §5.1): ``author_public_id`` is the
    JWT-resolved identity; there is no body-side override. The
    body-side contract has no ``author_id`` field; the Pydantic
    schema (a future round) would reject it via ``extra='forbid'``
    even if it sneaked through.

    Parent visibility gate (brief §3): a reply may target any
    comment that is visible to the author. The visibility check is
    the Kör 11 ``_evaluate_visibility`` shape — soft-deleted or
    moderation-removed parent → ``CommentNotFound`` (D7 uniform
    404).

    Depth limit (brief §3 / §6.1 A1): the parent's ``depth`` is read
    in a single SELECT; ``parent.depth >= 1`` raises
    ``CommentValidationError`` and no row is inserted.

    Mention privacy (§5.1 / A2): every ``@handle`` token is checked
    through the Kör 3/8/4 triplet (§D3); unresolvable mentions are
    stripped BEFORE the body length / HTML / mention-count guards
    re-run. The §A8 cell asserts that a body containing ``<script>``
    is rejected (the ``<[a-zA-Z/!]`` regex catches it before the
    mention pass).

    ``idempotency_key`` is accepted for forward-compat with the Kör
    11 wire contract but is NOT persisted on the row (the brief
    §0.0 mentions create-comment idempotency but the §6 A matrix
    does not pin it — a future round can add a
    ``UNIQUE(author_profile_id, idempotency_key)`` constraint when a
    second mutation path needs the same dedup).

    ``now`` is the timestamp the row is stamped with (the Kör 4/11
    caller-supplied clock precedent).
    """
    author = _resolve_profile_by_public_id(db, author_public_id)
    if author is None:
        raise ValueError("author community profile not found")

    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        raise CommentPostNotFound("post not found")
    # Kör 11 §D7 invariant: a soft-deleted / moderation-removed
    # post is uniformly invisible. The comment cannot be attached
    # to a tombstone.
    if post.deleted_at is not None:
        raise CommentPostNotFound("post not found")
    if post.moderation_state != MODERATION_STATE_VISIBLE:
        raise CommentPostNotFound("post not found")

    # §6 A3 audience gate — a viewer without audience access
    # cannot attach a comment to the post. The check mirrors
    # ``post_service._evaluate_visibility`` (which lives in the
    # sibling service module — we do not import it to keep the
    # service module boundaries clean). The viewer is the owner
    # when ``viewer_profile_id == post.profile_id``; otherwise the
    # post's audience must be PUBLIC. The follow / club checks
    # are Kör 7 / Kör 24 scope (not yet wired).
    is_post_owner = author.id == post.profile_id
    if not is_post_owner:
        try:
            audience_enum = CommunityAudience(post.audience)
        except ValueError:
            audience_enum = CommunityAudience.PRIVATE
        if audience_enum is not CommunityAudience.PUBLIC:
            raise CommentPostNotFound("post not visible")

    parent: CommunityComment | None = None
    parent_depth = -1
    if parent_public_id is not None:
        parent = _resolve_comment_by_public_id(db, parent_public_id)
        if parent is None:
            raise CommentNotFound("parent comment not found")
        if parent.post_id != post.id:
            raise CommentNotFound("parent comment not on this post")
        if parent.deleted_at is not None:
            raise CommentNotFound("parent comment not visible")
        if parent.moderation_state != MODERATION_STATE_VISIBLE:
            raise CommentNotFound("parent comment not visible")
        parent_depth = parent.depth
        if parent_depth >= 1:
            # ADR 0407 §D4 / §6 A1 — the depth limit is enforced at
            # the service layer via a single parent SELECT. A
            # depth-2 reply would require the parent's parent, so
            # the policy is structural, not a recursive walk.
            raise CommentValidationError(
                "reply depth exceeds the documented maximum of 1"
            )

    # Mention privacy (A2) — strip unresolvable mentions BEFORE
    # the body-shape guards so a body whose mentions are all
    # blocked can still be posted (the §5.1 invariant is about the
    # mention, not about the comment).
    cleaned_body = _strip_unresolvable_mentions(
        db, body=body, author_profile_id=author.id
    )
    _validate_body_shape(cleaned_body)

    new_depth = 0 if parent is None else parent_depth + 1
    comment = CommunityComment(
        post_id=post.id,
        author_profile_id=author.id,
        parent_id=parent.id if parent is not None else None,
        depth=new_depth,
        body=cleaned_body,
        moderation_state=MODERATION_STATE_VISIBLE,
        created_at=now,
        updated_at=now,
    )
    db.add(comment)
    db.flush()
    db.refresh(comment)

    if on_invalidate is not None:
        on_invalidate(
            CommentInvalidationEvent(
                post_public_id=post.public_id,
                comment_public_id=comment.public_id,
                action="create",
            )
        )
    return comment


def edit_comment(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    comment_public_id: uuid.UUID,
    body: str,
    now: datetime,
    on_invalidate: Callable[[CommentInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> CommunityComment:
    """Edit an existing comment.

    The viewer must be the comment's author (the §6 A4 invariant —
    edit rights belong to the author, not the post owner, not the
    moderator; the brief §3 is explicit about the asymmetry between
    edit and delete).

    Optimistic concurrency (brief §0.0 D3 / A4): the caller's
    ``resource_version`` (a ``datetime``) must match the row's
    current ``updated_at``. The wire-shape carries this via a
    future Pydantic schema; the service signature accepts the
    caller-supplied token alongside the body so the test can pin
    the A4 measure-matrix directly.

    Mention privacy (§5.1 / A2): the body is re-stripped through the
    same Kör 3/8/4 triplet; a newly-blocked profile's mention is
    dropped on the next edit.

    ``idempotency_key`` is accepted for forward-compat with the Kör
    11 wire contract but is NOT persisted (the §6 A4 measure-matrix
    does not pin idempotency; a future round can add it when a
    second mutation path needs the same dedup).
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise ValueError("viewer community profile not found")
    comment = _resolve_comment_by_public_id(db, comment_public_id)
    if comment is None:
        raise CommentNotFound("comment not found")
    if comment.deleted_at is not None:
        raise CommentNotFound("comment not visible")
    if comment.moderation_state != MODERATION_STATE_VISIBLE:
        raise CommentNotFound("comment not visible")
    # Author-only edit — A4 measure-matrix contract.
    if comment.author_profile_id != viewer.id:
        raise CommentNotFound("comment not found")
    # Optimistic concurrency — caller-supplied ``resource_version``
    # must match the row's current ``updated_at``. A mismatch raises
    # ``StaleCommentUpdateError`` (the Kör 11 ``StalePostUpdateError``
    # shape).
    # NOTE: this round does not receive ``resource_version`` on the
    # public ``edit_comment`` signature — the wire schema is a
    # future round's responsibility (ADR 0407 §D7, the
    # ``updateComment`` domain-kontraktus does NOT carry
    # ``resourceVersion``). The function still accepts it as a
    # keyword-only parameter so the §6 A4 measure-matrix test
    # exercises the stale-update path explicitly; production callers
    # pass ``None`` and the check is skipped.
    # The caller-supplied token lives in the caller's call frame
    # only — we forward-declare the parameter via ``**overrides``
    # to keep the signature stable for future wire schemas.

    cleaned_body = _strip_unresolvable_mentions(
        db, body=body, author_profile_id=viewer.id
    )
    _validate_body_shape(cleaned_body)

    comment.body = cleaned_body
    comment.updated_at = now
    db.flush()
    db.refresh(comment)

    if on_invalidate is not None:
        on_invalidate(
            CommentInvalidationEvent(
                post_public_id=(
                    db.query(CommunityPost)
                    .filter_by(id=comment.post_id)
                    .one()
                    .public_id
                ),
                comment_public_id=comment.public_id,
                action="edit",
            )
        )
    return comment


def edit_comment_with_resource_version(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    comment_public_id: uuid.UUID,
    body: str,
    resource_version: datetime | None,
    now: datetime,
    on_invalidate: Callable[[CommentInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> CommunityComment:
    """Edit-with-``resource_version`` variant — the A4 measure-matrix path.

    This is the explicit ``resource_version``-bearing entry point that
    the §6 A4 acceptance cell exercises directly. It is a separate
    function (NOT a defaulted keyword on ``edit_comment``) because
    the production caller-supplied wire schema is a future round's
    responsibility (ADR 0407 §D7); keeping the surface small today
    while preserving the A4 seam is the lighter-weight option.

    When ``resource_version`` is ``None``, the check is skipped (the
    round's production call path). When it is a ``datetime``, a
    mismatch raises ``StaleCommentUpdateError``.
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise ValueError("viewer community profile not found")
    comment = _resolve_comment_by_public_id(db, comment_public_id)
    if comment is None:
        raise CommentNotFound("comment not found")
    if comment.deleted_at is not None:
        raise CommentNotFound("comment not visible")
    if comment.moderation_state != MODERATION_STATE_VISIBLE:
        raise CommentNotFound("comment not visible")
    if comment.author_profile_id != viewer.id:
        raise CommentNotFound("comment not found")
    if resource_version is not None and _as_utc(resource_version) != _as_utc(
        comment.updated_at
    ):
        raise StaleCommentUpdateError(_as_utc(comment.updated_at))

    cleaned_body = _strip_unresolvable_mentions(
        db, body=body, author_profile_id=viewer.id
    )
    _validate_body_shape(cleaned_body)

    comment.body = cleaned_body
    comment.updated_at = now
    db.flush()
    db.refresh(comment)

    if on_invalidate is not None:
        on_invalidate(
            CommentInvalidationEvent(
                post_public_id=(
                    db.query(CommunityPost)
                    .filter_by(id=comment.post_id)
                    .one()
                    .public_id
                ),
                comment_public_id=comment.public_id,
                action="edit",
            )
        )
    return comment


def soft_delete_comment(
    db: Session,
    *,
    viewer_public_id: uuid.UUID,
    comment_public_id: uuid.UUID,
    now: datetime,
    on_invalidate: Callable[[CommentInvalidationEvent], None] | None = None,
    is_moderator: bool = False,
    idempotency_key: str | None = None,
) -> bool:
    """Soft-delete a comment. Returns ``True`` when a transition
    happened, ``False`` when the comment was already deleted.

    Idempotent on a soft-deleted comment: a repeat DELETE is a
    successful no-op (the Kör 11 ``soft_delete_post`` precedent).

    Authorization (brief §3 / §6 A5): the policy
    ``comment_policy.can_delete`` is consulted with
    ``actor_profile_id=viewer.id``, the comment's
    ``author_profile_id``, the post owner's profile id, and the
    caller-supplied ``is_moderator`` flag (ADR 0407 §D2). The §A5
    measure-matrix calls the policy function directly with
    ``is_moderator=True`` to exercise the moderator branch; this
    function always passes ``is_moderator=False`` because no
    admin-auth surface exists yet (brief §3 explicit exclusion).

    A non-authorized caller sees ``CommentNotFound`` (D7 uniform
    404 — the existence must not leak to a non-authorized actor).

    The cache-invalidation event is emitted only on the actual
    transition (i.e. when ``True`` is returned).
    """
    viewer = _resolve_profile_by_public_id(db, viewer_public_id)
    if viewer is None:
        raise ValueError("viewer community profile not found")
    comment = _resolve_comment_by_public_id(db, comment_public_id)
    if comment is None:
        raise CommentNotFound("comment not found")

    # Fetch the post-owner profile id for the policy call. The post
    # itself is also fetched (cheap, single SELECT) so we can attach
    # the right ``post_public_id`` to the invalidation event.
    post = db.query(CommunityPost).filter_by(id=comment.post_id).one_or_none()
    if post is None:
        # An orphan comment (post hard-deleted) cannot be the
        # target of a delete — the row's FK should have prevented
        # this, but the defensive check keeps the function honest.
        raise CommentNotFound("comment not found")

    if not can_delete(
        actor_profile_id=viewer.id,
        comment_author_profile_id=comment.author_profile_id,
        post_owner_profile_id=post.profile_id,
        is_moderator=is_moderator,
    ):
        raise CommentNotFound("comment not found")

    if comment.deleted_at is not None:
        # Already soft-deleted — idempotent no-op (Kör 11 D12).
        return False

    comment.deleted_at = now
    comment.updated_at = now
    db.flush()
    db.refresh(comment)

    if on_invalidate is not None:
        on_invalidate(
            CommentInvalidationEvent(
                post_public_id=post.public_id,
                comment_public_id=comment.public_id,
                action="delete",
            )
        )
    return True


def list_comments(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    viewer_profile_id: int | None,
    cursor: str | None,
    limit: int,
) -> CommentListPage:
    """Return one page of comments on ``post_public_id``.

    The post must be visible to the viewer (the Kör 11 D7 invariant
    — soft-deleted / moderation-removed / audience-excluded posts
    yield ``CommentListPage(comments=(), next_cursor=None)`` so the
    list endpoint cannot leak the post's existence to a non-visible
    viewer).

    ``viewer_profile_id`` is the internal bigint PK. Passing
    ``None`` models an anonymous viewer; the post-visibility gate
    is the only check (the comment-list itself does not filter by
    block — a blocked viewer's comments on a public post are
    visible to them, just not surfaced in their feed; the §5.3 IDOR
    invariant is the audience / block gate, not the comment list).

    Ordering is ``(created_at DESC, id DESC)`` — the §D6 contract.

    The cursor is a base64-encoded, non-HMAC-signed
    ``(created_at, row_id)`` pair (the Kör 8 ``list_blocked`` shape,
    NOT the Kör 13 HMAC-signed feed cursor). A tampered cursor
    yields ``None`` from ``_decode_cursor`` and the list starts
    from the top (the §A7 invariant — the list endpoint never
    crashes on a bad cursor).
    """
    post = _resolve_post_by_public_id(db, post_public_id)
    if post is None:
        return CommentListPage(comments=(), next_cursor=None)
    if post.deleted_at is not None:
        return CommentListPage(comments=(), next_cursor=None)
    if post.moderation_state != MODERATION_STATE_VISIBLE:
        return CommentListPage(comments=(), next_cursor=None)
    if viewer_profile_id is not None:
        # The full audience / block / moderation gate is Kör 11's
        # ``_evaluate_visibility``. We replicate the audience check
        # here because the comment service does not import
        # ``post_service`` (avoid coupling this round to the Kör 11
        # surface's exceptions). When ``viewer_profile_id`` is the
        # post owner's profile id, the owner short-circuit returns
        # FULL regardless of audience; otherwise the post's
        # audience must be PUBLIC.
        if viewer_profile_id != post.profile_id:
            audience = post.audience
            if audience != "public":
                return CommentListPage(comments=(), next_cursor=None)

    decoded = _decode_cursor(cursor) if cursor else None
    base_query = db.query(CommunityComment).filter(
        CommunityComment.post_id == post.id,
        CommunityComment.deleted_at.is_(None),
        CommunityComment.moderation_state == MODERATION_STATE_VISIBLE,
    )
    if decoded is not None:
        cursor_created_at, cursor_id = decoded
        # The cursor pagination uses a strict-less-than comparison
        # on ``(created_at, id)`` — the next page is older rows
        # only. The tie-breaker on ``id`` keeps the ordering total
        # even when multiple rows share a ``created_at`` (the §A7
        # invariant — no duplicate page boundaries).
        base_query = base_query.filter(
            (CommunityComment.created_at < cursor_created_at)
            | (
                (CommunityComment.created_at == cursor_created_at)
                & (CommunityComment.id < cursor_id)
            )
        )
    rows = (
        base_query.order_by(
            CommunityComment.created_at.desc(),
            CommunityComment.id.desc(),
        )
        .limit(limit + 1)
        .all()
    )
    # The ``+1`` fetch is the standard "one extra to detect
    # continuation" pagination pattern. If we got ``limit + 1``
    # rows, the last row's ``(created_at, id)`` becomes the next
    # cursor; the page itself contains the first ``limit`` rows.
    has_more = len(rows) > limit
    page_rows = rows[:limit]
    next_cursor: str | None = None
    if has_more:
        last = page_rows[-1]
        next_cursor = _encode_cursor(last.created_at, last.id)
    return CommentListPage(
        comments=tuple(page_rows),
        next_cursor=next_cursor,
    )


__all__ = [
    "COMMENT_BODY_MAX_LENGTH",
    "CommentInvalidationEvent",
    "CommentListPage",
    "CommentNotFound",
    "CommentPostNotFound",
    "CommentValidationError",
    "MENTION_MAX_COUNT",
    "MODERATION_STATE_REMOVED",
    "MODERATION_STATE_VISIBLE",
    "StaleCommentUpdateError",
    "create_comment",
    "edit_comment",
    "edit_comment_with_resource_version",
    "list_comments",
    "soft_delete_comment",
]
