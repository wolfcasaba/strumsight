"""Pydantic wire contracts for the Community clubs router.

The shapes mirror the Flutter ``CommunityClub`` entity
(``lib/features/community/domain/entities/community_club.dart``) field
for field, in the project-wide snake_case wire convention (the Kör 11
``PostOut`` / Kör 23 ``LeaderboardEntryOut`` precedent):

* ``public_id``       -> ``CommunityClub.id`` (``ContentId``)
* ``owner_public_id`` -> ``CommunityClub.ownerId`` (``PublicUserId``)
* ``member_count``    -> ``CommunityClub.memberCount`` (includes the owner)
* ``my_role``         -> ``CommunityClub.myRole`` (``null`` iff the viewer
  is NOT a member — the wire vocabulary is ``owner`` / ``moderator`` /
  ``member``)
* ``tags``            -> ``CommunityClub.tags`` (always ``[]`` today —
  the Kör 24 schema has no tag storage; the field exists so the client
  decoder never has to special-case a missing key)
* ``resource_version`` -> the ``updated_at`` optimistic-concurrency token
  the client echoes back on ``PATCH`` (the Kör 11 post precedent).

The internal integer ``id`` columns are never serialised (the §6.1
leak-guard); every identity on the wire is a public UUID.

The list envelope is the project-wide cursor page shape
``{"items": [...], "next_cursor": "..."|null}`` the Flutter
``CommunityPage`` decoder consumes (``decodeChallengeListPage`` in
``challenge_repository_impl.dart`` is the reference decoder).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

#: Wire vocabulary — mirrors ``models/club.py`` allowlists.
ClubVisibility = Literal["private", "discoverable", "public"]
ClubRole = Literal["owner", "moderator", "member"]
ClubInviteStatus = Literal["pending", "accepted", "cancelled", "declined", "expired"]

#: Page-size bounds for the two list endpoints.
CLUB_PAGE_SIZE_DEFAULT: int = 20
CLUB_PAGE_SIZE_MAX: int = 100

#: Validation bounds — the same numbers the Flutter ``CommunityClub``
#: factory and the ``community_clubs`` columns enforce.
CLUB_NAME_MAX_LENGTH: int = 60
CLUB_DESCRIPTION_MAX_LENGTH: int = 2000
CLUB_TAGS_MAX: int = 10
CLUB_TAG_MAX_LENGTH: int = 24


class CreateClubRequest(BaseModel):
    """Body shape for ``POST /community/clubs``.

    ``extra='forbid'`` rejects any smuggled ``owner_public_id`` /
    ``my_role`` / ``member_count`` — the owner is the JWT subject.
    ``tags`` is accepted for client-contract parity (the Flutter
    ``createClub`` sends it) and validated, but not persisted yet.
    """

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=CLUB_NAME_MAX_LENGTH)
    description: str = Field(default="", max_length=CLUB_DESCRIPTION_MAX_LENGTH)
    visibility: ClubVisibility = "private"
    tags: list[str] = Field(default_factory=list, max_length=CLUB_TAGS_MAX)
    idempotency_key: str | None = Field(default=None, max_length=128)


class UpdateClubRequest(BaseModel):
    """Body shape for ``PATCH /community/clubs/{club_public_id}``
    (owner-only). Mirrors the Flutter ``updateClub`` argument list."""

    model_config = ConfigDict(extra="forbid")

    description: str = Field(max_length=CLUB_DESCRIPTION_MAX_LENGTH)
    visibility: ClubVisibility
    tags: list[str] = Field(default_factory=list, max_length=CLUB_TAGS_MAX)
    resource_version: datetime | None = None
    idempotency_key: str | None = Field(default=None, max_length=128)


class ClubActionRequest(BaseModel):
    """Body shape for the membership actions (``join`` / ``leave`` /
    ``accept`` / ``decline``). The natural key rides the URL; the
    ``idempotency_key`` is optional (the Kör 21 invite precedent)."""

    model_config = ConfigDict(extra="forbid")

    idempotency_key: str | None = Field(default=None, max_length=128)


class ClubInviteRequest(BaseModel):
    """Body shape for ``POST /community/clubs/{club_public_id}/invites``."""

    model_config = ConfigDict(extra="forbid")

    invitee_public_id: uuid.UUID
    idempotency_key: str | None = Field(default=None, max_length=128)


class TransferOwnershipRequest(BaseModel):
    """Body shape for ``POST /community/clubs/{club_public_id}/transfer-ownership``."""

    model_config = ConfigDict(extra="forbid")

    new_owner_public_id: uuid.UUID
    idempotency_key: str | None = Field(default=None, max_length=128)


class ClubOut(BaseModel):
    """Wire shape for one club row (list item AND detail)."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    name: str
    description: str
    visibility: ClubVisibility
    tags: list[str] = Field(default_factory=list)
    owner_public_id: uuid.UUID
    member_count: int
    my_role: ClubRole | None = None
    #: ``True`` when the viewer has a pending join request on a
    #: private club (the D6 request flow) — lets the detail screen
    #: render "request sent" instead of a second Join button.
    join_request_pending: bool = False
    created_at: datetime
    updated_at: datetime
    resource_version: datetime


class ClubPage(BaseModel):
    """``GET /community/clubs`` envelope."""

    model_config = ConfigDict(extra="forbid")

    items: list[ClubOut]
    next_cursor: str | None = None


class ClubMemberOut(BaseModel):
    """Wire shape for one membership row (the Flutter
    ``ClubMemberRow`` projection plus the display fields the roster
    UI renders)."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    club_public_id: uuid.UUID
    profile_public_id: uuid.UUID
    display_name: str | None = None
    handle: str | None = None
    role: ClubRole
    joined_at: datetime


class ClubMemberPage(BaseModel):
    """``GET /community/clubs/{club_public_id}/members`` envelope."""

    model_config = ConfigDict(extra="forbid")

    items: list[ClubMemberOut]
    next_cursor: str | None = None


class ClubInviteOut(BaseModel):
    """Wire shape for one ``community_club_invites`` row — both the
    moderator-issued invite and the private-club join request use it
    (a join request is an invite whose inviter == invitee)."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    club_public_id: uuid.UUID
    inviter_public_id: uuid.UUID
    invitee_public_id: uuid.UUID
    status: ClubInviteStatus
    expires_at: datetime
    created_at: datetime
    updated_at: datetime
    responded_at: datetime | None = None


class ClubInvitePage(BaseModel):
    """``GET /community/clubs/{club_public_id}/join-requests`` envelope."""

    model_config = ConfigDict(extra="forbid")

    items: list[ClubInviteOut]
    next_cursor: str | None = None


class ClubLeaveOut(BaseModel):
    """``POST /community/clubs/{club_public_id}/leave`` response — the
    club may no longer be visible to the caller (a private club after
    leaving), so the response carries only the identity + verdict."""

    model_config = ConfigDict(extra="forbid")

    club_public_id: uuid.UUID
    left: bool = True


class ClubMemberRemovedOut(BaseModel):
    """``DELETE /community/clubs/{club_public_id}/members/{profile_public_id}``
    response."""

    model_config = ConfigDict(extra="forbid")

    club_public_id: uuid.UUID
    profile_public_id: uuid.UUID
    removed: bool = True


__all__ = [
    "CLUB_PAGE_SIZE_DEFAULT",
    "CLUB_PAGE_SIZE_MAX",
    "ClubActionRequest",
    "ClubInviteOut",
    "ClubInvitePage",
    "ClubInviteRequest",
    "ClubLeaveOut",
    "ClubMemberOut",
    "ClubMemberPage",
    "ClubMemberRemovedOut",
    "ClubOut",
    "ClubPage",
    "CreateClubRequest",
    "TransferOwnershipRequest",
    "UpdateClubRequest",
]
