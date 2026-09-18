"""A poszt-sorok KÖZÖS wire-projekciója (2026-09-05).

**Miért közös modul.** A számlálókat, a néző-állapotot és a sor → wire-elem
leképezést eredetileg a ``routers/feed.py`` privát helyi függvényei
végezték. Amikor a klub-feed és a kitűzött posztok felülete is megszületett,
két út kínálkozott:

1. a klub-router importálja a feed-router privát ``_``-függvényeit, vagy
2. a klub-router megismétli a lekérdezéseket.

Mindkettő ugyanahhoz a hibaosztályhoz vezet: a komment-számláló „törölt nem
számít bele" szabálya EGY helyen javulna, a másikon nem — és a két felület
ugyanarra a posztra más számot mutatna. A projekció ezért saját modul, és
mindkét router ezt hívja.

**A sor típusa szándékosan strukturális.** A ``following_feed.FeedItemRow`` és
a ``club_feed.ClubFeedItemRow`` mezőről mezőre azonos (a ``club_feed``
docstringje ki is mondja: „mirrors the Kör 13 ``FeedItemRow`` so the same
schema layer can render either feed"). Egy közös ősosztály bevezetése a két
dataclass átírását jelentené; a :class:`PostRowLike` protokoll ugyanazt a
garanciát adja anélkül, hogy a meglévő típusokhoz hozzányúlnánk.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from sqlalchemy import text as _sa_text
from sqlalchemy.orm import Session

from .schemas.feed import FeedPostItem


class PostRowLike(Protocol):
    """A két feed-sor közös alakja — strukturálisan, nem öröklés útján."""

    post_id: int
    post_public_id: uuid.UUID
    author_public_id: uuid.UUID
    audience: str
    body: str
    artifact_type: str | None
    artifact_schema_version: int | None
    artifact_payload: dict[str, Any] | None
    moderation_state: str
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


@dataclass(frozen=True)
class SimplePostRow:
    """A :class:`PostRowLike` alak egy ORM ``CommunityPost`` sorból.

    Akkor kell, amikor egy service NEM teljes feed-sort ad vissza — a
    ``list_club_pinned`` például négy mezőt hoz (poszt, szerző, törzs,
    kitűzés ideje), mert a kitűzés tényét méri, nem a poszt teljes
    állapotát. A hívó ebből és a poszt saját sorából állítja elő a
    projektálható alakot, így a kitűzött poszt UGYANAZON az úton kap
    számlálót és néző-állapotot, mint a feed elemei — nem kitalált
    nullákkal.
    """

    post_id: int
    post_public_id: uuid.UUID
    author_public_id: uuid.UUID
    audience: str
    body: str
    artifact_type: str | None
    artifact_schema_version: int | None
    artifact_payload: dict[str, Any] | None
    moderation_state: str
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None


def interaction_counts(
    db: Session, post_ids: list[int]
) -> dict[int, tuple[int, int, int]]:
    """Reakció / komment / könyvjelző szám poszt-azonosítónként.

    HÁROM csoportosított lekérdezés az OLDALRA, nem poszt-onként három —
    egy 50-es oldalon az N+1 alak 150 kört jelentene. Üres oldalon egy
    lekérdezés sem fut.
    """
    if not post_ids:
        return {}
    counts: dict[int, tuple[int, int, int]] = {pid: (0, 0, 0) for pid in post_ids}
    placeholders = ", ".join(f":p{i}" for i in range(len(post_ids)))
    params = {f"p{i}": pid for i, pid in enumerate(post_ids)}

    def _grouped(sql: str) -> dict[int, int]:
        return {
            int(r[0]): int(r[1]) for r in db.execute(_sa_text(sql), params).fetchall()
        }

    reactions = _grouped(
        "SELECT post_id, COUNT(*) FROM community_reactions "
        f"WHERE post_id IN ({placeholders}) GROUP BY post_id"
    )
    # A törölt és a nem látható komment NEM számít bele — különben a
    # kártya többet ígérne, mint amennyit a komment-lista megnyitva ad.
    comments = _grouped(
        "SELECT post_id, COUNT(*) FROM community_comments "
        f"WHERE post_id IN ({placeholders}) AND deleted_at IS NULL "
        "AND moderation_state = 'visible' GROUP BY post_id"
    )
    bookmarks = _grouped(
        "SELECT post_id, COUNT(*) FROM community_bookmarks "
        f"WHERE post_id IN ({placeholders}) GROUP BY post_id"
    )
    for pid in post_ids:
        counts[pid] = (
            reactions.get(pid, 0),
            comments.get(pid, 0),
            bookmarks.get(pid, 0),
        )
    return counts


def viewer_state(
    db: Session, viewer_profile_id: int, post_ids: list[int]
) -> dict[int, tuple[bool, str | None]]:
    """A NÉZŐ saját könyvjelzője és reakciója poszt-azonosítónként.

    Külön a számlálóktól, mert néző-függő: ugyanaz a poszt más
    felhasználónak MÁS értéket ad, ezért sosem oszthatja a cache-t.
    """
    if not post_ids:
        return {}
    placeholders = ", ".join(f":p{i}" for i in range(len(post_ids)))
    params: dict[str, object] = {f"p{i}": pid for i, pid in enumerate(post_ids)}
    params["viewer"] = viewer_profile_id
    bookmarked = {
        int(r[0])
        for r in db.execute(
            _sa_text(
                "SELECT post_id FROM community_bookmarks "
                f"WHERE profile_id = :viewer AND post_id IN ({placeholders})"
            ),
            params,
        ).fetchall()
    }
    reactions = {
        int(r[0]): str(r[1])
        for r in db.execute(
            _sa_text(
                "SELECT post_id, kind FROM community_reactions "
                f"WHERE profile_id = :viewer AND post_id IN ({placeholders})"
            ),
            params,
        ).fetchall()
    }
    return {pid: (pid in bookmarked, reactions.get(pid)) for pid in post_ids}


def row_to_item(
    row: PostRowLike,
    counts: tuple[int, int, int] = (0, 0, 0),
    viewer: tuple[bool, str | None] = (False, None),
    *,
    club_id: int | None = None,
) -> FeedPostItem:
    """Egy feed-sor → wire-elem.

    Központosítva, hogy a leak-guard (belső id SOSEM megy ki) strukturális
    legyen: egy új mező felvétele is ezen az egy helyen megy át.
    """
    return FeedPostItem(
        public_id=row.post_public_id,
        author_public_id=row.author_public_id,
        audience=row.audience,  # type: ignore[arg-type]
        club_id=club_id,
        body=row.body,
        artifact_type=row.artifact_type,
        artifact_schema_version=row.artifact_schema_version,
        artifact_payload=row.artifact_payload,
        moderation_state=row.moderation_state,  # type: ignore[arg-type]
        reaction_count=counts[0],
        comment_count=counts[1],
        bookmark_count=counts[2],
        viewer_bookmarked=viewer[0],
        viewer_reaction=viewer[1],
        created_at=row.created_at,
        resource_version=row.updated_at,
        deleted_at=row.deleted_at,
    )


def project_page(
    db: Session,
    rows: list[PostRowLike],
    *,
    viewer_profile_id: int,
    club_id: int | None = None,
) -> list[FeedPostItem]:
    """Egy teljes oldal projekciója — a három lépés EGY helyen.

    Ezt hívja a following-feed, a klub-feed és a kitűzött posztok felülete
    is, így a számláló-szemantika nem tud szétcsúszni közöttük.
    """
    post_ids = [row.post_id for row in rows]
    counts = interaction_counts(db, post_ids)
    viewer = viewer_state(db, viewer_profile_id, post_ids)
    return [
        row_to_item(
            row,
            counts.get(row.post_id, (0, 0, 0)),
            viewer.get(row.post_id, (False, None)),
            club_id=club_id,
        )
        for row in rows
    ]


__all__ = [
    "PostRowLike",
    "SimplePostRow",
    "interaction_counts",
    "project_page",
    "row_to_item",
    "viewer_state",
]
