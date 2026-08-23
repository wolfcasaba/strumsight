"""Pydantic request/response schemas for privacy settings — E09-R04, ADR 0398 §6.

The hard contract here is **whitelist-only**: the schemas enumerate their
fields explicitly and never derive them from an ORM class on a schema that
would otherwise leak the internal ``id`` (the same discipline as
``schemas/profile.py``). Beyond the whitelist rule, two extra constraints
make this round distinct:

* ``model_config = ConfigDict(extra="forbid")`` on the *update* schema — the
  client cannot smuggle extra fields into the request body, so the
  resource-version check can never be silently bypassed by an extra
  ``updated_at`` key.
* ``resource_version: datetime`` is the **optimistic-concurrency token**
  (ADR 0398 §6): the client sends the ``updated_at`` it last read, the
  service compares it to the row's current ``updated_at``, and rejects on
  mismatch with ``StalePrivacyUpdateError`` → HTTP 409. There is no
  separate ``version`` column on the table — the existing
  ``CommunityPrivacySettings.updated_at`` is the resource version, period.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from ..policies.access_policy import CommunityAudience, ProfileVisibility


class PrivacySettingsUpdate(BaseModel):
    """Inbound PUT body for the privacy settings endpoint.

    ``extra="forbid"`` is the security fence: a client cannot include
    arbitrary fields (e.g. a forged ``id``, a forged ``public_id``) and
    cannot "extend" the resource version with a parallel field. The
    fields below are the only ones the server accepts.
    """

    model_config = ConfigDict(extra="forbid")

    visibility: ProfileVisibility
    audience_default: CommunityAudience
    resource_version: datetime


class PrivacySettingsOut(BaseModel):
    """Outbound representation of the privacy settings row.

    Mirrors the whitelist discipline from ``schemas/profile.py``: only
    ``public_id`` + the two enum fields + ``resource_version`` (the row's
    ``updated_at``). The internal ``id`` is not listed here, and
    ``from_attributes=True`` is safe because the only ORM attributes on
    the row that match this schema's fields are the public ones.

    ``resource_version`` is what the client must echo back on the next
    PUT — the server uses it as the optimistic-concurrency token.
    """

    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    visibility: ProfileVisibility
    audience_default: CommunityAudience
    resource_version: datetime


__all__ = [
    "PrivacySettingsOut",
    "PrivacySettingsUpdate",
]
