"""Pydantic response schemas for the Community module.

E09-R02, ADR 0396 §2. The hard contract here is **whitelist-only**: these
schemas enumerate the fields they expose and never derive them from an ORM
class via ``from_attributes=True`` on a schema that includes the internal
``id`` column. That is the exact A2 failure mode the §6.1 measure-matrix
names — the leak guard is structural, not behavioral.

Only ``public_id`` crosses the API boundary; the internal ``id`` (BigInteger
PK) is never listed here, so a future regression that passes the ORM row
directly through ``model_dump`` cannot leak it.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class CommunityProfileOut(BaseModel):
    """Public-facing profile response.

    The ``display_name`` field is exposed as ``Optional[str]`` to match the
    nullable DB column (ADR 0396 §2 — the column stays nullable because
    creation is explicit-onboarding, Kör 6+).
    """

    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    display_name: Optional[str] = None
    created_at: datetime


class CommunityPrivacySettingsOut(BaseModel):
    """Public-facing privacy-settings response.

    Mirrors ``CommunityProfileOut`` discipline: only ``public_id`` and
    explicit, documented fields. Granular privacy toggles (which fields are
    public / follower-only / private) are Kör 6+ scope.
    """

    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    updated_at: datetime
