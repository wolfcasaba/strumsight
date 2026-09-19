"""Attaching uploaded media to a post (javító sáv R27).

Kept out of ``post_service`` so the validation rules live next to the
pipeline that produced the rows they check.

Three rules, all enforced server-side at publish time, none of them
trusting the client:

1. **Ownership.** Every id must resolve to a row owned by the POST's
   author. A caller who guesses (or is handed) someone else's media
   public_id gets the same error as a caller who invents one — the
   uniform-404 discipline again, one level down.
2. **State.** Only ``ready`` media attaches. Attaching a ``pending`` or
   ``rejected`` row would publish a post whose attachment can never
   render, and attaching a ``review`` row would publish content the
   operator deliberately parked.
3. **Single owner post.** A media row already attached to another post
   cannot be re-attached: the descriptor is embedded in a post's wire
   shape, so sharing one row between two posts would let deleting one
   post's media silently blank the other's.

The count cap keeps a single post from turning into an album (and keeps
the feed projection's batched read bounded).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models.media_upload import MEDIA_STATE_READY, CommunityMediaUpload

#: Maximum attachments per post.
MAX_MEDIA_PER_POST: int = 4


class MediaAttachmentInvalid(ValueError):
    """One of the supplied media ids failed a publish-time rule.

    A ``ValueError`` subclass so the existing ``routers/posts.py``
    ``except ValueError -> 400`` branch handles it without a new except
    arm (and so a direct service caller sees the same class it already
    catches).
    """


def attach_media_to_post(
    db: Session,
    *,
    post_id: int,
    owner_profile_id: int,
    media_public_ids: list[uuid.UUID],
    now: datetime,
) -> list[CommunityMediaUpload]:
    """Bind ``media_public_ids`` to ``post_id``, in the given order.

    Returns the attached rows in attachment order. Raises
    :class:`MediaAttachmentInvalid` on any rule violation — and does so
    BEFORE mutating any row, so a partially-valid list attaches nothing.
    """
    if not media_public_ids:
        return []
    if len(media_public_ids) > MAX_MEDIA_PER_POST:
        raise MediaAttachmentInvalid(
            f"a post carries at most {MAX_MEDIA_PER_POST} media attachments"
        )
    if len(set(media_public_ids)) != len(media_public_ids):
        raise MediaAttachmentInvalid("duplicate media id in the attachment list")

    rows = {
        row.public_id: row
        for row in db.execute(
            select(CommunityMediaUpload).where(
                CommunityMediaUpload.public_id.in_(media_public_ids)
            )
        ).scalars()
    }
    ordered: list[CommunityMediaUpload] = []
    for public_id in media_public_ids:
        row = rows.get(public_id)
        # Unknown / not-yours / not-ready collapse to ONE message: the
        # attach surface must not become an existence oracle for another
        # account's media ids.
        if (
            row is None
            or row.profile_id != owner_profile_id
            or row.state != MEDIA_STATE_READY
        ):
            raise MediaAttachmentInvalid("media attachment is not available")
        if row.post_id is not None and row.post_id != post_id:
            raise MediaAttachmentInvalid("media is already attached to a post")
        ordered.append(row)

    for position, row in enumerate(ordered):
        row.post_id = post_id
        row.attach_position = position
        row.updated_at = now
    db.flush()
    return ordered


def media_for_posts(
    db: Session,
    post_ids: list[int],
) -> dict[int, list[CommunityMediaUpload]]:
    """Batched "attachments for these posts", in attachment order.

    One query for the whole page — the N+1 the feed projection would
    otherwise grow. Only ``ready`` rows are returned: a post whose
    attachment was deleted or rejected after publication simply shows no
    media, rather than a broken descriptor.
    """
    if not post_ids:
        return {}
    stmt = (
        select(CommunityMediaUpload)
        .where(
            CommunityMediaUpload.post_id.in_(post_ids),
            CommunityMediaUpload.state == MEDIA_STATE_READY,
        )
        .order_by(
            CommunityMediaUpload.post_id,
            CommunityMediaUpload.attach_position,
            CommunityMediaUpload.id,
        )
    )
    grouped: dict[int, list[CommunityMediaUpload]] = {}
    for row in db.execute(stmt).scalars():
        grouped.setdefault(int(row.post_id or 0), []).append(row)
    return grouped


__all__ = [
    "MAX_MEDIA_PER_POST",
    "MediaAttachmentInvalid",
    "attach_media_to_post",
    "media_for_posts",
]
