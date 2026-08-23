"""Pydantic schemas for Community posts (E09-R11, ADR 0405).

The wire shape for the create / get / patch / soft-delete endpoints.
Two design choices govern every model in this module:

* **Server-side author identity.** The ``CreatePostRequest`` schema
  does NOT carry any author / profile identifier — the author is
  always the JWT subject, resolved in the router layer (brief §5.1,
  ADR 0405 §D1). A client cannot impersonate another user even if
  the request body smuggles an ``author_id`` field: the Pydantic
  ``ConfigDict(extra='forbid')`` rejects unknown fields at parse
  time, and the service layer would ignore them even if the schema
  didn't.

* **Artifact is optional and validated via the Kör 10 contract.**
  When present, the ``artifact`` field is fed through
  ``schemas.artifacts.parse_share_artifact`` which returns a
  ``ShareArtifactEnvelope`` whose discriminator and field whitelist
  are validated at parse time (ADR 0404, brief §0.0 D10). The
  service layer then mirrors the validated envelope's
  ``.artifact.type`` and ``.artifact.schema_version`` into the typed
  sibling columns so the Kör 13 feed query can filter / facet
  without re-parsing JSON. The ``payload``-side mirror lives in the
  service layer — the schema only owns the inbound validation.

The markdown / HTML body validation (brief §0.0 D5) is a
REJECT-only regex: any literal ``<`` followed by a letter, ``/``,
or ``!`` (the start of a tag, a closing tag, or an HTML comment) is
rejected at parse time. There is no sanitisation library in the
project (``grep -rn 'bleach\\|markdown' requirements*.txt`` →
empty) and adding one would be out of scope.

The mention limit (brief §0.0 D9) caps the number of ``@handle``
tokens per post (regex-based — the regex matches the documented
handle pattern; mention resolution is Kör 14 scope).
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from ..models.post import POST_BODY_MAX_LENGTH
from ..policies.access_policy import CommunityAudience
from .artifacts import ShareArtifactEnvelope, parse_share_artifact

# ---------------------------------------------------------------------------
# Body-validation regexes (brief §0.0 D5, D9).
# ---------------------------------------------------------------------------

# Literal "<" followed by a letter, "/", or "!" — the opening
# sequence of an HTML tag, a closing tag, or an HTML comment. The
# pattern is intentionally narrow: plain text containing "<3" or
# "a < b" is allowed (the "<" is not followed by a tag-starting
# character). Markdown subset (bold / italic / URL) remains valid.
_HTML_TAG_START_PATTERN: re.Pattern[str] = re.compile(r"<[a-zA-Z/!]")

# Mention pattern: "@" + 1-64 word characters. Matches the Dart
# handle pattern (Kör 3); mention resolution is Kör 14 scope.
_MENTION_PATTERN: re.Pattern[str] = re.compile(r"@[a-zA-Z0-9_]{1,64}")
MENTION_MAX_COUNT: int = 20


def _validate_artifact(
    value: dict[str, Any] | None,
) -> dict[str, Any] | None:
    """Shared validator for the optional artifact field.

    Raises ``pydantic.ValidationError`` (which Pydantic re-raises
    from the calling validator) on unknown discriminator, unknown
    ``schema_version``, or extra field. Returns the raw dict —
    the service layer will re-parse the validated payload to read
    the typed fields.
    """
    if value is None:
        return None
    envelope: ShareArtifactEnvelope = parse_share_artifact(value)
    # Round-trip through ``model_dump`` to strip any pydantic
    # extras that are not part of the wire shape — the service
    # layer will re-parse the JSON when persisting to the
    # ``artifact_payload`` JSON column.
    return envelope.model_dump(mode="json")


def _reject_html_tags(value: str | None) -> str | None:
    """Reject any literal HTML-tag start (brief §0.0 D5)."""
    if value is None:
        return None
    if _HTML_TAG_START_PATTERN.search(value):
        raise ValueError("body must not contain HTML tags or angle-bracket markup")
    return value


def _enforce_mention_limit(value: str | None) -> str | None:
    """Cap the per-post mention count (brief §0.0 D9)."""
    if value is None:
        return None
    mentions = _MENTION_PATTERN.findall(value)
    if len(mentions) > MENTION_MAX_COUNT:
        raise ValueError(f"body exceeds the mention limit of {MENTION_MAX_COUNT}")
    return value


class CreatePostRequest(BaseModel):
    """Inbound shape for ``POST /community/posts``.

    Note the absence of any author / profile identifier — the author
    is the JWT subject, resolved in the router layer. A request body
    that smuggles an ``author_id`` (or any other unknown field) is
    rejected by ``extra='forbid'`` at parse time.
    """

    model_config = ConfigDict(extra="forbid")

    audience: CommunityAudience
    body: Annotated[str, Field(min_length=1, max_length=POST_BODY_MAX_LENGTH)]
    # Optional ``club_id`` — the column exists on the row (brief
    # §0.0 D6) but the value is not yet constrained by membership
    # (Kör 24). Nullable; absent in the JSON body means "no club".
    club_id: int | None = Field(default=None, ge=1)
    # Artifact payload — the validated ``ShareArtifactEnvelope`` is
    # computed at parse time via ``parse_share_artifact`` (ADR 0404,
    # brief §0.0 D10). Unknown discriminators, unknown
    # ``schema_version``, and extra fields are rejected here.
    artifact: dict[str, Any] | None = None
    idempotency_key: str | None = Field(default=None, min_length=1, max_length=128)

    @field_validator("body")
    @classmethod
    def _v_body_html(cls, value: str) -> str:
        return _reject_html_tags(value)  # type: ignore[return-value]

    @field_validator("body")
    @classmethod
    def _v_body_mentions(cls, value: str) -> str:
        return _enforce_mention_limit(value)  # type: ignore[return-value]

    @field_validator("artifact")
    @classmethod
    def _v_artifact(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        return _validate_artifact(value)


class PatchPostRequest(BaseModel):
    """Inbound shape for ``PATCH /community/posts/{id}``.

    All fields are optional — the endpoint only writes the fields
    the client supplied. The ``resource_version`` token is REQUIRED
    (the optimistic-concurrency check; brief §0.0 D3, ADR 0398 §6
    precedent).

    The same ``extra='forbid'`` and ``_reject_html_tags`` discipline
    applies — a client cannot smuggle an ``author_id`` override or
    inject HTML through the patch path either.

    Note: passing ``artifact: null`` EXPLICITLY clears the
    post's artifact. Passing no ``artifact`` key at all leaves the
    existing value intact. The router / service layer distinguishes
    the two via Pydantic's ``model_fields_set``.
    """

    model_config = ConfigDict(extra="forbid")

    audience: CommunityAudience | None = None
    body: (
        Annotated[str, Field(min_length=1, max_length=POST_BODY_MAX_LENGTH)] | None
    ) = None
    artifact: dict[str, Any] | None = None
    resource_version: datetime

    @field_validator("body")
    @classmethod
    def _v_body_html(cls, value: str | None) -> str | None:
        return _reject_html_tags(value)

    @field_validator("body")
    @classmethod
    def _v_body_mentions(cls, value: str | None) -> str | None:
        return _enforce_mention_limit(value)

    @field_validator("artifact")
    @classmethod
    def _v_artifact(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        return _validate_artifact(value)


class PostOut(BaseModel):
    """Outbound shape for the post lifecycle endpoints.

    The internal ``id`` and ``profile_id`` are deliberately NOT in
    this schema — the wire shape only ever carries public
    identifiers (ADR 0396 §1 invariant). ``resource_version`` is the
    ``updated_at`` timestamp the client must echo back on PATCH.

    The artifact fields mirror the validated envelope's
    ``.artifact.type`` / ``.artifact.schema_version`` and the
    round-tripped JSON payload, so the Flutter controller can
    re-hydrate the discriminated union without re-fetching.
    """

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID = Field(..., description="The post's public UUID.")
    author_public_id: uuid.UUID = Field(
        ..., description="The public_id of the post's author."
    )
    audience: CommunityAudience
    club_id: int | None = None
    body: str
    artifact_type: str | None = None
    artifact_schema_version: int | None = None
    artifact_payload: dict[str, Any] | None = None
    moderation_state: Literal["visible", "removed"]
    created_at: datetime
    resource_version: datetime
    deleted_at: datetime | None = None


__all__ = [
    "CreatePostRequest",
    "MENTION_MAX_COUNT",
    "PatchPostRequest",
    "PostOut",
]
