"""Wire contract for the Community media router (WP-H5).

Every response goes through :class:`MediaOut`, so the leak-guard is
structural: the internal ``id``, the bucket-side ``object_key`` and the
owning ``profile_id`` have no field to travel on. What a caller learns
about a media row is exactly this whitelist.

The request models use ``extra="forbid"`` — the project-wide discipline
(``schemas/post.py``, ``schemas/artifacts.py``): a client that smuggles
an ``owner_id`` / ``profile_id`` / ``processing_state`` field into the
body is rejected at parse time rather than having the field silently
ignored.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class MediaOut(BaseModel):
    """The only shape a media row takes on the wire.

    Deliberately absent (ADR 0410 D5 / the §5.3 IDOR discipline):

    * ``id`` — the internal BigInteger PK.
    * ``object_key`` — the storage-side path. Knowing it would let a
      caller correlate rows across profiles and would leak the owning
      profile's internal id, which the key is derived from.
    * ``profile_id`` — the owner's internal id. The owner is expressed
      as ``owner_public_id`` instead.
    * ``moderation_*`` — the audit columns are moderator-facing state,
      not author-facing.
    """

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    owner_public_id: uuid.UUID
    content_type: str
    size_bytes: int
    duration_ms: int | None
    processing_state: str
    post_public_id: uuid.UUID | None
    created_at: datetime


class AttachMediaRequest(BaseModel):
    """Body of ``POST /community/media/{public_id}/attach``.

    The media's audience is *inherited* from the post it hangs on, so
    attaching is the moment a private upload becomes visible to anyone
    else. The only field is the post; the owner comes from the JWT.
    """

    model_config = ConfigDict(extra="forbid")

    post_public_id: uuid.UUID


class ReviewMediaRequest(BaseModel):
    """Body of ``POST /community/media/{public_id}/review`` — the human
    review gate (ADR 0412 D5).

    ``decision`` is the literal pair ``moderation.media_moderation.
    resolve_review`` accepts. There is no "auto-approve" value: the
    invariant that only a human moves a row to ``ready`` is what this
    endpoint exists to preserve.
    """

    model_config = ConfigDict(extra="forbid")

    decision: str


__all__ = ["AttachMediaRequest", "MediaOut", "ReviewMediaRequest"]
