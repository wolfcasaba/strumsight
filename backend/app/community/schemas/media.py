"""Wire shapes for the Community media endpoints (javító sáv R27).

One outbound descriptor, reused by all three surfaces (the upload
response, the owner's read, and the ``media`` list embedded in every
post / feed item), so a field can only be added in one place.

The descriptor deliberately carries NO internal ids, no filesystem path
and no digest: the client addresses media by ``public_id`` and fetches
bytes from ``GET /community/media/{public_id}``. Exposing the content
digest would turn the store into an oracle ("does anyone else have this
exact file?"), which is a cross-user inference the wire has no reason to
allow.

``state`` and ``rejection_code`` are the two fields the client renders
directly — the state literals are exactly the vocabulary
``CommunityMediaProcessingState`` already models on the Dart side, and
the rejection code is a stable machine token the client maps to a
localized string (never a server-authored sentence).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

MediaStateLiteral = Literal[
    "pending",
    "scanning",
    "transcoding",
    "review",
    "ready",
    "rejected",
    "deleted",
]

MediaKindLiteral = Literal["image", "audio", "unknown"]


class MediaOut(BaseModel):
    """One media object as the client sees it."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    kind: MediaKindLiteral
    state: MediaStateLiteral
    #: Machine-readable rejection reason; ``None`` unless ``state`` is
    #: ``rejected``. The client maps the token to a localized message.
    rejection_code: str | None = None
    #: The media type of the STORED bytes — the server's own verdict
    #: after re-encoding, never the uploader's claim.
    content_type: str
    #: Size of the stored bytes; 0 before the transcode lands.
    size_bytes: int = 0
    width: int | None = None
    height: int | None = None
    duration_ms: int | None = None
    created_at: datetime


class MediaDeleteResult(BaseModel):
    """``DELETE /community/media/{public_id}`` answer."""

    model_config = ConfigDict(extra="forbid")

    status: Literal["deleted", "noop"]


def media_to_out(row) -> MediaOut:
    """Map a ``CommunityMediaUpload`` row to the wire descriptor.

    Centralised so the leak-guard (no internal id, no path, no digest on
    the wire) stays structural: a new column reaches the client only by
    being added here.
    """
    return MediaOut(
        public_id=row.public_id,
        kind=row.kind,  # type: ignore[arg-type]
        state=row.state,  # type: ignore[arg-type]
        rejection_code=row.rejection_code,
        content_type=row.content_type,
        size_bytes=row.size_bytes or 0,
        width=row.width,
        height=row.height,
        duration_ms=row.duration_ms,
        created_at=row.created_at,
    )


__all__ = [
    "MediaDeleteResult",
    "MediaKindLiteral",
    "MediaOut",
    "MediaStateLiteral",
    "media_to_out",
]
