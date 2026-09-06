"""Wire schemas for the Community notification inbox.

A ``notifications/notification_service.py`` a Kör 20 óta létezik és tesztelt
(``backend/tests/community/test_notification_service.py``), HTTP-router
nélkül. Ugyanaz a rés, amit a komment-router 2026-09-05-én zárt be a maga
domainjében: a Flutter-oldali ``CommunityNotificationRepository`` öt
metódusának nem volt mit hívnia, ezért a ``CommunityNotificationsScreen``
elérhetetlen maradt.

A wire-alak a modell mezőit tükrözi, de KIZÁRÓLAG opaque ``public_id``-kal —
a belső ``community_notifications.id`` és a ``recipient_profile_id`` sosem
hagyja el a szervert (ugyanaz a leak-guard, amit a poszt- és komment-séma
dokumentál).

**A ``title_key`` / ``body_key`` szándékosan KULCS, nem kész szöveg.** A
lokalizáció a kliensé: a szerver nem tudja, milyen nyelven fut az app, és
egy szerver-oldalon fordított cím a nyelvváltásnál elavulna. A kliens az
ARB-ból oldja fel.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

#: Az inbox lapmérete. A router a felső határra VÁG, nem 422-t ad — ugyanaz
#: a fail-safe, amit a feed- és a komment-router dokumentál.
NOTIFICATION_PAGE_SIZE_DEFAULT = 25
NOTIFICATION_PAGE_SIZE_MAX = 100


class NotificationOut(BaseModel):
    """Egy értesítés az inboxban."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    #: ``None``, ha rendszer-értesítés (nincs cselekvő felhasználó).
    actor_public_id: uuid.UUID | None = None
    type: str
    #: Lokalizációs KULCS, nem kész szöveg — l. a modul docstringjét.
    title_key: str
    body_key: str | None = None
    #: A hivatkozott tartalom típusa és opaque azonosítója (pl. ``post``),
    #: amiből a kliens a mélylinket építi.
    entity_type: str | None = None
    entity_id: str | None = None
    #: Összevont értesítéseknél hány esemény tartozik ide (>= 1).
    aggregate_count: int
    is_read: bool
    read_at: datetime | None = None
    created_at: datetime


class NotificationInboxPageOut(BaseModel):
    """Egy oldalnyi értesítés, kurzoros lapozással."""

    model_config = ConfigDict(extra="forbid")

    items: list[NotificationOut]
    next_cursor: str | None = None
    #: Az olvasatlanok száma a TELJES inboxban, nem csak ezen az oldalon —
    #: a kliens ebből rajzolja a jelvényt anélkül, hogy végiglapozná.
    unread_count: int


class MarkReadRequest(BaseModel):
    """Törzs a ``POST .../read`` és a ``POST .../read-up-to`` hívásokhoz."""

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=128)


class NotificationPreferencesOut(BaseModel):
    """Kategória → szint leképezés."""

    model_config = ConfigDict(extra="forbid")

    preferences: dict[str, str]


class SetPreferenceRequest(BaseModel):
    """Egyetlen kategória szintjének állítása.

    A megengedett kategóriák és szintek halmazát a SERVICE ismeri; a séma
    csak a hosszt korlátozza, hogy az érvényesség EGY helyen dőljön el.
    """

    model_config = ConfigDict(extra="forbid")

    category: str = Field(..., min_length=1, max_length=64)
    level: str = Field(..., min_length=1, max_length=32)
    idempotency_key: str | None = Field(default=None, max_length=128)


__all__ = [
    "NOTIFICATION_PAGE_SIZE_DEFAULT",
    "NOTIFICATION_PAGE_SIZE_MAX",
    "MarkReadRequest",
    "NotificationInboxPageOut",
    "NotificationOut",
    "NotificationPreferencesOut",
    "SetPreferenceRequest",
]
