"""Pydantic response and request schemas for the Community module.

E09-R02 (ADR 0396 §2) introduced the whitelist-only response shape.
E09-R06 (ADR 0400 §2–3) extends it with:

* ``CommunityProfileCreate`` — the **create** request body for
  ``POST /community/profiles/me`` (``handle``, ``display_name``,
  ``visibility``, ``audience_default``).
* ``CommunityProfileUpdate`` — the **update** request body for
  ``PUT /community/profiles/me`` (only ``display_name``; privacy is a
  separate endpoint, ADR 0400 §3).
* ``handle: Optional[str] = None`` added to ``CommunityProfileOut`` —
  backwards-compatible (existing readers ignore the new key, new
  readers still see the old keys).

The hard contract on the request schemas is **whitelist-only with
``extra="forbid"``** (mirror of the Kör 4 ``PrivacySettingsUpdate``
discipline, ADR 0398 §6 / ADR 0400 §5.4): a client cannot smuggle a
``user_id`` / ``profile_id`` field into the body — the payload's
identity is always the ``CurrentUser`` from the auth-ladder. The
``user_id`` / ``profile_id`` keys would never be used by the server,
but accepting them silently would mask a future regression that
accidentally started reading them; rejecting them at parse-time is
the A8 / §5.4 cell of the §6.1 measure-matrix.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from ..policies.access_policy import CommunityAudience, ProfileVisibility

# ``display_name`` length cap mirrors the Flutter domain
# ``CommunityProfile.displayName`` validation (40 characters). The
# service layer ALSO trims + length-checks, but having the cap on the
# request schema means an oversized value never reaches the
# application code at all — the 422 happens at parse-time.
_DISPLAY_NAME_MAX_LENGTH = 40


class CommunityProfileOut(BaseModel):
    """Public-facing profile response.

    The ``display_name`` field is exposed as ``Optional[str]`` to match the
    nullable DB column (ADR 0396 §2 — the column stays nullable because
    creation is explicit-onboarding, Kör 6+).

    E09-R06 adds the optional ``handle`` field. The ORM has TWO
    handle columns (``handle_display`` and ``handle_normalized``)
    — the public response exposes the user-facing ``handle_display``
    value under the shorter wire key ``handle``. The mapping is done
    at the router layer (the only writer of this response today) by
    building the response dict explicitly; Pydantic parses the dict
    and validates the field shapes.
    """

    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    display_name: Optional[str] = None
    created_at: datetime
    handle: Optional[str] = None


class CommunityPrivacySettingsOut(BaseModel):
    """Public-facing privacy-settings response.

    Mirrors ``CommunityProfileOut`` discipline: only ``public_id`` and
    explicit, documented fields. Granular privacy toggles (which fields are
    public / follower-only / private) are Kör 6+ scope.
    """

    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    updated_at: datetime


class CommunityProfileCreate(BaseModel):
    """Inbound POST body for ``POST /community/profiles/me``.

    ``extra="forbid"`` rejects a payload that smuggles a
    ``user_id`` / ``profile_id`` / ``public_id`` / ``handle_display`` /
    ``handle_normalized`` / ``handle_changed_at`` field — the server
    identity comes from the ``CurrentUser`` only, never from the body
    (ADR 0400 §5.4, brief §5.4, A8 measure-matrix row "payload can
    override the CurrentUser").
    """

    model_config = ConfigDict(extra="forbid")

    handle: str = Field(
        ...,
        min_length=1,
        max_length=64,
        description=(
            "The raw (un-normalized) handle. The service applies the "
            "NFKC + casefold normalization before the DB unique-index "
            "check; structural pre-validation runs on the trimmed "
            "input here only so a too-long payload never reaches the "
            "application code."
        ),
    )
    display_name: str = Field(
        ...,
        min_length=1,
        max_length=_DISPLAY_NAME_MAX_LENGTH,
    )
    visibility: ProfileVisibility
    audience_default: CommunityAudience


class CommunityProfileUpdate(BaseModel):
    """Inbound PUT body for ``PUT /community/profiles/me``.

    ``extra="forbid"`` for the same reason as
    ``CommunityProfileCreate``: no field of this body identifies the
    row — the row is the caller's own profile, resolved from
    ``CurrentUser``.

    Privacy is intentionally NOT in this schema (ADR 0400 §3): the
    ``privacy.py`` endpoint (Kör 4) owns the privacy update. A
    privacy-step in the edit-mode UI is also explicitly out of scope
    (brief §5.2 / ADR 0400 §3).
    """

    model_config = ConfigDict(extra="forbid")

    display_name: str = Field(
        ...,
        min_length=1,
        max_length=_DISPLAY_NAME_MAX_LENGTH,
    )


__all__ = [
    "CommunityPrivacySettingsOut",
    "CommunityProfileCreate",
    "CommunityProfileOut",
    "CommunityProfileUpdate",
]
