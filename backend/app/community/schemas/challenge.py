"""Pydantic wire contracts for the Community challenge READ endpoints
(``GET /community/challenges``, ``GET /community/challenges/{id}``,
``GET /community/challenges/{id}/me``).

The shapes are the exact field set the Flutter
``HttpCommunityChallengeRepository`` decoders parse
(``lib/features/community/data/repositories/challenge_repository_impl.dart``
— ``decodeChallengeDefinition`` / ``decodeChallengeListPage`` /
``decodeParticipant``):

* definition: ``public_id`` / ``type`` / ``metric`` / ``difficulty`` /
  ``starts_at`` / ``ends_at`` / ``author_public_id`` / ``version`` /
  ``club_id`` (string|null);
* list envelope: ``{"items": [...], "next_cursor": "..."|null}``;
* participation: ``{"participant": null | {"participant_public_id",
  "invite_state", "best_metric_value"}}``.

The write-side schemas (invite / result bodies) stay inline in
``routers/challenges.py`` (the Kör 21 / Kör 22 layout) — this module
only adds the read-side contract the client was already coded against.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

#: ``window`` filter vocabulary for ``GET /community/challenges`` —
#: the Flutter ``CommunityChallengeRepository.listChallenges`` doc
#: names exactly these three window states.
ChallengeWindow = Literal["active", "upcoming", "ended"]

#: Page-size bounds — the same ``[1, 100]`` / default 20 pair the
#: Kör 23 leaderboard endpoint uses.
CHALLENGE_PAGE_SIZE_DEFAULT: int = 20
CHALLENGE_PAGE_SIZE_MAX: int = 100


class ChallengeDefinitionOut(BaseModel):
    """One challenge definition on the wire (list item AND detail)."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    author_public_id: uuid.UUID
    type: str
    metric: str
    difficulty: int
    starts_at: datetime
    ends_at: datetime
    version: int = 1
    club_id: str | None = None
    #: Number of accepted participants — informational for the list
    #: card; the client decoder ignores unknown keys.
    participant_count: int = 0
    created_at: datetime
    updated_at: datetime


class ChallengePage(BaseModel):
    """``GET /community/challenges`` envelope."""

    model_config = ConfigDict(extra="forbid")

    items: list[ChallengeDefinitionOut]
    next_cursor: str | None = None


class ChallengeParticipantOut(BaseModel):
    """The caller's own participation summary for one challenge.

    ``invite_state`` uses the Kör 5 ``ChallengeInviteState`` wire
    vocabulary (``draft`` / ``sent`` / ``accepted`` / ``declined`` /
    ``expired`` / ``cancelled`` / ``active`` / ``completed`` /
    ``forfeited``). A materialised participant row maps to ``active``
    while the window is open and ``completed`` once it has closed;
    an invite without a participant row reports the invite's own
    state.
    """

    model_config = ConfigDict(extra="forbid")

    participant_public_id: uuid.UUID
    challenge_public_id: uuid.UUID
    invite_state: str
    best_metric_value: int | None = None
    joined_at: datetime | None = None
    invite_public_id: uuid.UUID | None = None


class ChallengeParticipationOut(BaseModel):
    """``GET /community/challenges/{id}/me`` envelope — ``participant``
    is ``null`` when the caller has no relationship with the
    challenge (the Flutter ``decodeParticipantOrNull`` contract)."""

    model_config = ConfigDict(extra="forbid")

    participant: ChallengeParticipantOut | None = Field(default=None)


__all__ = [
    "CHALLENGE_PAGE_SIZE_DEFAULT",
    "CHALLENGE_PAGE_SIZE_MAX",
    "ChallengeDefinitionOut",
    "ChallengePage",
    "ChallengeParticipantOut",
    "ChallengeParticipationOut",
    "ChallengeWindow",
]
