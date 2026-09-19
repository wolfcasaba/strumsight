"""Wire schemas for the Community challenge READ surface — WP-H4
(2026-09-06).

A ``routers/challenges.py`` a Kör 21/22 óta csak írást vitt; a három
olvasási útvonalat (lista, részlet, saját részvétel) a kliens MÁR
hívta — és 404-et kapott. Ez a modul a wire-alak, amit a
``challenge_repository_impl.dart`` dekódere MÁR elvár:

* ``ChallengeOut`` mezőnevei a ``decodeChallengeDefinition``
  olvasott kulcsai (``public_id``, ``type``, ``metric``,
  ``difficulty``, ``starts_at``, ``ends_at``, ``author_public_id``,
  ``version``, ``club_id``),
* ``ChallengePage`` a ``decodeChallengeListPage`` alakja
  (``items`` + ``next_cursor``),
* ``MyParticipationOut`` a ``decodeParticipantOrNull`` burkolója
  (``participant``: objektum vagy ``null``) — a Kör 23
  ``OwnRankOut`` precedense.

**Leak-guard.** Egyik sémában sincs belső ``id`` /
``author_profile_id`` / ``challenge_id`` mező. A séma a
whitelist — nem a modell egy ``from_attributes`` másolata —, így
egy jövőbeli oszlop nem kerül ki magától a wire-re (ADR 0396 §1 A2).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

__all__ = [
    "ChallengeOut",
    "ChallengePageOut",
    "ChallengeParticipationOut",
    "MyParticipationOut",
]


class ChallengeOut(BaseModel):
    """Egy kihívás-definíció a néző szemszögéből."""

    model_config = ConfigDict(extra="forbid")

    public_id: uuid.UUID
    author_public_id: uuid.UUID
    #: Wire-sztring típus (a Kör 5 ``ChallengeType`` öt értéke). A
    #: kliens dekódere az ISMERETLEN értéket hibának veszi — ezért a
    #: szerver soha nem ad ki allowlisten kívüli értéket.
    type: str
    metric: str
    difficulty: int
    starts_at: datetime
    ends_at: datetime
    version: int
    #: A klub public_id-jának sztring-alakja, vagy ``None``. SOHA nem
    #: a belső PK — l. a ``challenge_query_service`` „club_id
    #: konvenció" szakaszát.
    club_id: str | None = None


class ChallengePageOut(BaseModel):
    """Egy oldalnyi kihívás.

    ``next_cursor`` CSAK akkor nem ``None``, ha tényleg van még sor —
    a service a ``limit + 1``-edik sor létéből dönt. Így a kliens
    lapozója nem kér le egy üres záró-oldalt (a „halted vs
    continued" cella).
    """

    model_config = ConfigDict(extra="forbid")

    items: list[ChallengeOut]
    next_cursor: str | None = None


class ChallengeParticipationOut(BaseModel):
    """A néző SAJÁT részvétel-állapota egy kihíváson."""

    model_config = ConfigDict(extra="forbid")

    participant_public_id: uuid.UUID
    #: A meghívás-sor wire-állapota (a Kör 21 kilenc érték egyike).
    invite_state: str
    #: A résztvevő-sor személyes csúcsa; ``None``, amíg nincs
    #: hitelesített eredmény (a Kör 22 „ellenőrzés folyamatban"
    #: állapot — SOHA nem 0, mert az eredményt ÁLLÍTANA).
    best_metric_value: int | None = None


class MyParticipationOut(BaseModel):
    """A ``GET /community/challenges/{id}/me`` burkolója.

    ``participant`` ``None``, ha a nézőnek nincs sem résztvevő-, sem
    meghívás-sora. A burkoló azért van, hogy a „nincs részvétel"
    válasz 200 legyen és NE 404 — a 404 a „nincs ilyen kihívás
    (vagy nem látod)" jelentést viszi, a kettő nem mosható össze.
    """

    model_config = ConfigDict(extra="forbid")

    participant: ChallengeParticipationOut | None = None
