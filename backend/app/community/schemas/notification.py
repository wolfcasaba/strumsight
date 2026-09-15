"""Pydantic wire contracts for the Community notification inbox
(``/community/notifications/**``, E09-R20 service surface — ADR 0414
§D3; HTTP router landed in the 2026-09-15 production-wiring round).

The shapes are the exact field set the Flutter
``HttpCommunityNotificationRepository`` decoders parse
(``lib/features/community/data/repositories/notification_repository_impl.dart``
— ``decodeInboxPage`` / ``decodeNotificationOrNull`` /
``decodePreferences``):

* inbox row: ``public_id`` / ``type`` / ``title_key`` / ``body_key``
  (string|null) / ``related_content_id`` (string|null — the A5
  deleted-entity path suppresses it to ``null``; the Dart decoder reads
  ``related_content_id`` FIRST and falls back to ``entity_id``, so the
  server emits the primary name) / ``is_read`` / ``created_at``;
* list envelope: ``{"items": [...], "next_cursor": "..."|null}`` (the
  ``ChallengePage`` / ``ClubPage`` precedent);
* preferences: a BARE ``{category: level}`` map (the Dart decoder
  accepts either the bare map or a ``{"preferences": {...}}`` envelope;
  the bare map is the ``notification_service.get_preferences`` return
  shape verbatim, so nothing is wrapped);
* mutation bodies carry the optional client ``idempotency_key`` the
  Kör 7+ mutations all send — the natural key (``recipient``,
  ``notification``) is the real idempotency surface, so the key is
  accepted and passed through, never required.

Internal ``id`` / ``recipient_profile_id`` / ``actor_profile_id`` never
reach the wire (ADR 0396 §1) — every outbound model here is
``extra="forbid"`` and enumerates public fields only.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

#: Page-size bounds — the same ``[1, 100]`` / default 20 pair the
#: challenge / club list endpoints use.
NOTIFICATION_PAGE_SIZE_DEFAULT: int = 20
NOTIFICATION_PAGE_SIZE_MAX: int = 100

#: The three preference levels ``notification_service.set_preference``
#: accepts (``inApp`` is the default for an unset category).
NotificationPreferenceLevel = Literal["inApp", "push", "disabled"]


class NotificationOut(BaseModel):
    """One inbox row — the ``CommunityNotificationItem`` wire shape."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    type: str
    title_key: str
    body_key: str | None = None
    related_content_id: str | None = None
    is_read: bool
    created_at: datetime


class NotificationPage(BaseModel):
    """``GET /community/notifications`` envelope."""

    model_config = ConfigDict(extra="forbid")

    items: list[NotificationOut]
    next_cursor: str | None = None


class MarkReadRequest(BaseModel):
    """``POST /community/notifications/{public_id}/read`` body."""

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=128)


class MarkAllReadRequest(BaseModel):
    """``POST /community/notifications/read-all`` body — the cutoff is
    the public id of the LAST item the user has seen."""

    model_config = ConfigDict(extra="forbid")

    up_to_public_id: uuid.UUID
    idempotency_key: str | None = Field(default=None, max_length=128)


class MarkReadOut(BaseModel):
    """Mutation verdict for mark-read — ``read`` on the actual
    transition, ``noop`` on an idempotent retry (the ``DELETE
    /community/posts/{id}`` ``deleted``/``noop`` precedent)."""

    model_config = ConfigDict(extra="forbid")

    status: Literal["read", "noop"]


class MarkAllReadOut(BaseModel):
    """Bulk mark-read verdict plus the number of rows transitioned
    (``0`` is a legitimate "nothing to do" answer)."""

    model_config = ConfigDict(extra="forbid")

    status: Literal["read", "noop"]
    count: int


class PreferenceUpdateRequest(BaseModel):
    """``PUT /community/notifications/preferences/{category}`` body."""

    model_config = ConfigDict(extra="forbid")

    level: NotificationPreferenceLevel
    idempotency_key: str | None = Field(default=None, max_length=128)


__all__ = [
    "NOTIFICATION_PAGE_SIZE_DEFAULT",
    "NOTIFICATION_PAGE_SIZE_MAX",
    "MarkAllReadOut",
    "MarkAllReadRequest",
    "MarkReadOut",
    "MarkReadRequest",
    "NotificationOut",
    "NotificationPage",
    "NotificationPreferenceLevel",
    "PreferenceUpdateRequest",
]
