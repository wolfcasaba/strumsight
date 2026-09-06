"""Wire schemas for the Community club surface.

A ``services/club_service.py`` és a ``services/club_content_service.py`` a
Kör 24 óta létezik és tesztelt, HTTP-router nélkül. A ``ClubMembershipView``
docstringje ki is mondja: „a future router rounds it through Pydantic" — ez
az a router. A hiány következménye a Flutter-oldalon látszott: a
``CommunityClubRepository`` kilenc metódusának nem volt mit hívnia, ezért a
``ClubListScreen`` / ``ClubDetailScreen`` / ``ClubMemberManagementScreen``
elérhetetlen maradt.

**MÉRT SZERZŐDÉS-RÉS, amit ez a séma NEM hidal át.** A kliens
``CommunityClub`` entitása ``tags`` listát hordoz, és a
``createClub`` / ``updateClub`` metódusa is kér ilyet — a
``community_clubs`` táblában viszont **nincs tags oszlop** (grep-pel mérve,
2026-09-05), és sem a ``create_club``, sem az ``update_club`` service nem
fogad ilyen paramétert. A séma ezért NEM vesz fel ``tags`` mezőt: egy üres
listát visszaadó mező azt hazudná, hogy a címkézés működik, csak épp
mindenkinek üres. A kliens-oldali bekötés ezt ``known_gap``-ként rögzíti, és
a címkézés felvétele külön kör (séma-migráció + service + router együtt).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

#: A klub-lista lapmérete. A service ``limit``-alapú (nem kurzoros), ezért a
#: lapozás egyelőre egyoldalas — l. a router ``next_cursor`` megjegyzését.
CLUB_PAGE_SIZE_DEFAULT = 25
CLUB_PAGE_SIZE_MAX = 100
CLUB_MEMBER_PAGE_SIZE_MAX = 200


class ClubOut(BaseModel):
    """Egy klub a néző szemszögéből."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    name: str
    description: str
    visibility: str
    owner_public_id: uuid.UUID
    #: A tagok száma — a lista-végpont a klubonkénti COUNT-ból tölti, hogy a
    #: kliensnek ne kelljen minden sorhoz külön kérést indítania.
    member_count: int
    #: A NÉZŐ szerepe ebben a klubban (``None``, ha nem tag). Ez teszi
    #: eldönthetővé a UI-nak, hogy „csatlakozás" vagy „kilépés" gombot rajzol.
    my_role: str | None = None
    created_at: datetime
    #: Optimista konkurencia token (``updated_at``) — a poszt- és
    #: komment-felület precedense.
    resource_version: datetime


class ClubPage(BaseModel):
    """Egy oldalnyi klub.

    ``next_cursor`` MA MINDIG ``None``: a ``list_clubs`` service
    ``limit``-alapú, kurzort nem ad. A mező azért van itt, hogy a kliens
    lapozó-kódja ne változzon, amikor a service kurzorosra vált — akkor a
    router csak kitölti.
    """

    model_config = ConfigDict(extra="forbid")

    items: list[ClubOut]
    next_cursor: str | None = None


class ClubMemberOut(BaseModel):
    """Egy tagsági sor — a ``ClubMembershipView`` Pydantic alakja."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    club_public_id: uuid.UUID
    profile_public_id: uuid.UUID
    role: str
    joined_at: datetime


class ClubMemberPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[ClubMemberOut]
    next_cursor: str | None = None


class CreateClubRequest(BaseModel):
    """Törzs a ``POST /community/clubs`` híváshoz."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(..., min_length=1, max_length=60)
    description: str = Field(default="", max_length=500)
    #: A megengedett értékeket a SERVICE ismeri; a séma csak hosszt korlátoz,
    #: hogy az érvényesség egy helyen dőljön el.
    visibility: str = Field(..., min_length=1, max_length=32)
    idempotency_key: str | None = Field(default=None, max_length=128)


class UpdateClubRequest(BaseModel):
    """Törzs a ``PATCH /community/clubs/{id}`` híváshoz."""

    model_config = ConfigDict(extra="forbid")

    description: str = Field(default="", max_length=500)
    visibility: str = Field(..., min_length=1, max_length=32)
    idempotency_key: str | None = Field(default=None, max_length=128)


class IdempotentRequest(BaseModel):
    """Törzs a mellékhatás-hívásokhoz, amiknek csak kulcs kell."""

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=128)


class TargetProfileRequest(BaseModel):
    """Törzs a másik felhasználót megnevező hívásokhoz (meghívás, eltávolítás,
    tulajdonos-átadás)."""

    model_config = ConfigDict(extra="forbid")

    target_public_id: uuid.UUID
    idempotency_key: str | None = Field(default=None, max_length=128)


__all__ = [
    "CLUB_MEMBER_PAGE_SIZE_MAX",
    "CLUB_PAGE_SIZE_DEFAULT",
    "CLUB_PAGE_SIZE_MAX",
    "ClubMemberOut",
    "ClubMemberPage",
    "ClubOut",
    "ClubPage",
    "CreateClubRequest",
    "IdempotentRequest",
    "TargetProfileRequest",
    "UpdateClubRequest",
]
