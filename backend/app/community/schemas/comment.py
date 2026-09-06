"""Wire schemas for the Community comment surface.

The service layer (``services/comment_service.py``) has existed and been
tested since Kör 12 (``backend/tests/community/test_comment_service.py``);
what was missing until 2026-09-05 was the HTTP surface above it. Its absence
is what left the Flutter ``CommentsScreen`` unreachable: the client's
``CommunityPostRepository.comments`` / ``createComment`` / ``updateComment``
/ ``deleteComment`` had no endpoint to call.

Shape decisions follow the Kör 11 post schemas verbatim:

* ``extra="forbid"`` — a client cannot smuggle an undocumented field
  through the body and accidentally reach a different code path;
* the wire identity is always the opaque ``public_id`` UUID, never the
  internal ``community_comments.id`` (the leak-guard the post schema
  documents at ``schemas/post.py``);
* ``resource_version`` is the ``updated_at`` timestamp, echoed back on
  PATCH for optimistic concurrency — the same token the post surface uses.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

# A hossz-korlát EGYETLEN forrása a modell-modul — a séma NEM deklarál
# másodikat. Egy külön konstans itt némán elcsúszhatna a DB-oszlop
# hosszától, és a wire-validáció a szolgáltatásétól eltérő határt húzna.
from ..models.comment import COMMENT_BODY_MAX_LENGTH

#: Page-size bounds for ``GET .../comments``. The router clamps above the
#: maximum rather than returning 422 — the same belt-and-braces choice the
#: feed router documents (§0.0 D7 fail-safe).
COMMENT_PAGE_SIZE_DEFAULT = 25
COMMENT_PAGE_SIZE_MAX = 100


class CommentOut(BaseModel):
    """One comment as the client sees it."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    post_public_id: uuid.UUID
    author_public_id: uuid.UUID
    parent_public_id: uuid.UUID | None = None
    depth: int
    body: str
    moderation_state: str
    created_at: datetime
    #: The optimistic-concurrency token (``updated_at``), echoed back on
    #: PATCH — the Kör 11 ``PostOut.resource_version`` precedent.
    resource_version: datetime
    deleted_at: datetime | None = None


class CommentPage(BaseModel):
    """One cursor-paginated page of a post's comments.

    ``next_cursor`` is ``None`` on the last page; otherwise it is the
    opaque token the client forwards verbatim as the next request's
    ``cursor``. The ordering is ``(created_at DESC, id DESC)``
    (ADR 0407 §D6), owned by the service layer.
    """

    model_config = ConfigDict(extra="forbid")

    items: list[CommentOut]
    next_cursor: str | None = None


class CreateCommentRequest(BaseModel):
    """Inbound shape for ``POST /community/posts/{id}/comments``."""

    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=COMMENT_BODY_MAX_LENGTH)
    #: ``None`` ⇒ a top-level comment; otherwise the parent's public id.
    #: The depth limit is enforced by the service, not here.
    parent_public_id: uuid.UUID | None = None
    #: Client-generated idempotency key. The service uses the natural-key
    #: identity as the canonical surface; the key makes a retried request
    #: unambiguous.
    idempotency_key: str | None = Field(default=None, max_length=128)


class PatchCommentRequest(BaseModel):
    """Inbound shape for ``PATCH /community/comments/{id}``."""

    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=COMMENT_BODY_MAX_LENGTH)
    #: The ``resource_version`` the client last saw. ``None`` means "no
    #: concurrency check" — the service treats it as a blind write, which
    #: is why the client always sends it.
    resource_version: datetime | None = None
    idempotency_key: str | None = Field(default=None, max_length=128)


__all__ = [
    "COMMENT_BODY_MAX_LENGTH",
    "COMMENT_PAGE_SIZE_DEFAULT",
    "COMMENT_PAGE_SIZE_MAX",
    "CommentOut",
    "CommentPage",
    "CreateCommentRequest",
    "PatchCommentRequest",
]
