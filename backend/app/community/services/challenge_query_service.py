"""Community challenge READ service — WP-H4 (2026-09-06).

**Miért született.** A ``routers/challenges.py`` a Kör 21/22 óta öt
útvonalat visz, és MIND írás (``POST`` ×4, ``DELETE`` ×1): nem volt
egyetlen olyan felület sem, ami egy kihívást vissza tudott volna
olvasni. A következmény MÉRT volt:

* a ``docs/contracts/client-backend-endpoints.json`` három
  ``known_gap`` sort vitt (lista, részlet, saját részvétel) — a
  kliens HÍVTA ezeket a végpontokat, és 404-et kapott,
* a ``community_challenges_screen.dart`` a
  ``challengeControllerProvider``-en át ``listChallenges``-t hív:
  a képernyő SOSEM tudott sort mutatni,
* a ``club_detail_screen.dart`` ``clubChallengesProvider``-e egy
  őszinte „nem tudjuk" állapotot adott vissza, mert nem volt mit
  kérdeznie.

Ez a modul a HÁROM olvasási művelet egyetlen üzleti helye — a router
csak session-seam, azonosító-feloldás és wire-alak (a Kör 24 klub-
router precedense).

**A láthatóság a SZERVERÉ (§5.1, ADR 0398).** Egy kihívás akkor és
csak akkor látható a nézőnek, ha az alábbiak KÖZÜL legalább egy áll,
ÉS a szerzővel nincs blokk-viszonyban:

1. **saját viszony** — a néző a szerző, VAGY résztvevő
   (``community_challenge_participants`` sor), VAGY van rá meghívása
   (``community_challenge_invites`` sor bármelyik irányban);
2. **klub-hatókör** — a kihívás ``club_id``-t visz, és a klub nem
   olyan ``private`` klub, aminek a néző nem tagja;
3. **globális** — ``club_id IS NULL`` ÉS a típus
   ``dailyCommunity`` / ``periodicGlobal``.

Ami EGYIKBE sem esik (``friends`` / ``personalBest`` / klub nélküli
``club`` típus idegen szemmel), az NEM látható. A fail-closed irány
szándékos: egy baráti kihívás a meghívottak ügye, nem a nyilvánosságé.

**Ismeretlen vs. rejtett megkülönbözhetetlen (leak-guard).** Mindkét
eset ugyanaz a :class:`ChallengeNotFound` → ugyanaz a 404, ugyanazzal
a szöveggel. A hívó nem tudja megállapítani, hogy a public_id nem
létezik, vagy csak nem az övé — ez a §6.1 IDOR-cella.

**``club_id`` konvenció (D7 kibontása).** A ``community_challenges``
``club_id`` oszlopa nullable ``String``, FK NÉLKÜL (a Kör 21 modell
„reserved for Kör 24 club integration" mezője), és 2026-09-06-ig SEMMI
nem írta (grep: a két service-teszt ``club_id=None``-t ad). Ez a modul
mondja ki a konvenciót: a mező a klub **public_id**-jának
sztring-alakja — soha nem a belső PK. Egy belső id itt azonnali
azonosító-szivárgás lenne (ADR 0396 §1 A2), és a mező kifelé is megy a
wire-en.

**Kurzor (a projekt-szintű minta).** ``(created_at DESC, id DESC)``,
base64-be kódolt JSON — a ``leaderboard_service`` / ``post_service``
alakja. Egy sérült kurzor a lista ELEJÉRŐL indul újra (a Kör 21/23
precedens), nem hibázik: a lapozó kliens így nem ragad be.

Nincs séma-változás és nincs migráció: minden olvasás a meglévő
három táblán megy.
"""

from __future__ import annotations

import base64
import json
import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from ..models.challenge import (
    CHALLENGE_TYPE_DAILY_COMMUNITY,
    CHALLENGE_TYPE_PERIODIC_GLOBAL,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from ..models.club import (
    CLUB_VISIBILITY_PRIVATE,
    CommunityClub,
    CommunityClubMember,
)
from ..models.profile import CommunityProfile
from ..policies.query_filters import list_block_pairs_for_viewer

#: A ``club_id IS NULL`` mellett is bárkinek látható típusok. A
#: ``friends`` / ``personalBest`` / (klub nélküli) ``club`` SZÁNDÉKOSAN
#: nincs itt: azok csak a saját viszonyon át látszanak.
GLOBAL_CHALLENGE_TYPES: frozenset[str] = frozenset(
    {CHALLENGE_TYPE_DAILY_COMMUNITY, CHALLENGE_TYPE_PERIODIC_GLOBAL}
)

#: Ablak-szűrő wire-értékek. Ismeretlen érték = nincs szűrés (a
#: router 422-t ad rá, hogy a néma elnyelés hibaosztálya ne
#: keletkezzen újra — l. a klub-repository D2 cellát).
CHALLENGE_STATUS_ACTIVE: str = "active"
CHALLENGE_STATUS_UPCOMING: str = "upcoming"
CHALLENGE_STATUS_ENDED: str = "ended"

CHALLENGE_STATUS_ALLOWLIST: frozenset[str] = frozenset(
    {CHALLENGE_STATUS_ACTIVE, CHALLENGE_STATUS_UPCOMING, CHALLENGE_STATUS_ENDED}
)

#: Lapméret-korlátok. A kliens ``limit``-et küld (a Kör 21
#: ``listChallenges`` már így hívott), a szerver vág.
CHALLENGE_PAGE_SIZE_DEFAULT: int = 20
CHALLENGE_PAGE_SIZE_MAX: int = 100


class ChallengeNotFound(Exception):
    """Ismeretlen VAGY a néző elől rejtett kihívás — a kettő
    megkülönbözhetetlen (leak-guard)."""


def is_allowed_challenge_status(value: str) -> bool:
    """True, ha ``value`` a három ablak-szűrő érték egyike."""
    return value in CHALLENGE_STATUS_ALLOWLIST


# ---------------------------------------------------------------------------
# Kurzor — (created_at DESC, id DESC), base64(JSON).
# ---------------------------------------------------------------------------


def _encode_cursor(*, created_at: datetime, row_id: int) -> str:
    payload = {"created_at": created_at.isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[datetime, int] | None:
    """``(created_at, id)`` vagy ``None`` sérült kurzorra.

    A ``None`` a hívó jelzése, hogy a lista elejéről indul — a Kör
    21/23 precedens. Egy 400-as válasz itt beragasztaná a lapozót.
    """
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        return datetime.fromisoformat(payload["created_at"]), int(payload["id"])
    except (ValueError, KeyError, TypeError, json.JSONDecodeError, UnicodeDecodeError):
        return None


# ---------------------------------------------------------------------------
# Kifelé menő nézetek — a router Pydantic-ba csomagolja őket.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ChallengeView:
    """Egy kihívás wire-alakja. CSAK public_id-k — a belső
    ``id`` / ``author_profile_id`` soha nem hagyja el a szervert."""

    public_id: uuid.UUID
    author_public_id: uuid.UUID
    type: str
    metric: str
    difficulty: int
    starts_at: datetime
    ends_at: datetime
    version: int
    club_id: str | None


@dataclass(frozen=True)
class ChallengePage:
    """Egy oldalnyi kihívás + a következő oldal opaque kurzora."""

    items: tuple[ChallengeView, ...]
    next_cursor: str | None


@dataclass(frozen=True)
class ParticipationView:
    """A NÉZŐ saját részvétel-állapota egy kihíváson.

    ``invite_state`` a meghívás-sor állapota; ha nincs meghívás-sor,
    de van résztvevő-sor, az állapot ``accepted`` (a résztvevő-sor
    csak elfogadásból keletkezhet — ``accept_invite``).
    """

    participant_public_id: uuid.UUID
    invite_state: str
    best_metric_value: int | None


# ---------------------------------------------------------------------------
# Belső feloldók.
# ---------------------------------------------------------------------------


def _hidden_private_club_ids(db: Session, *, viewer_profile_id: int) -> list[str]:
    """Azon ``private`` klubok public_id-sztringjei, amiknek a néző NEM tagja.

    Ez a lista a klub-hatókörű kihívások NEGATÍV szűrője. Azért
    negatív (és nem „a látható klubok" pozitív listája), mert a
    privát klubok a kisebbség: a lekérdezés egy körben, korlátos
    halmazzal dolgozik. Egy ISMERETLEN (nem létező klubra mutató)
    ``club_id`` nem esik ebbe a halmazba, tehát látható marad — ott
    nincs mit szivárogtatni, a védendő eset a privát klub.
    """
    member_club_ids = select(CommunityClubMember.club_id).where(
        CommunityClubMember.profile_id == viewer_profile_id
    )
    stmt = select(CommunityClub.public_id).where(
        CommunityClub.visibility == CLUB_VISIBILITY_PRIVATE,
        CommunityClub.id.notin_(member_club_ids),
    )
    return [str(row[0]) for row in db.execute(stmt).all()]


def _visibility_predicate(db: Session, *, viewer_profile_id: int):
    """A §5.1 láthatósági feltétel SQL-alakja.

    Egy helyen él, mert mind a három olvasási művelet ugyanazt
    használja — egy második, kézzel másolt változat pontosan az a
    hibaosztály lenne, amit a ``query_filters`` modul docstringje
    „elfelejtett endpoint"-ként nevez meg.
    """
    own_participation = select(CommunityChallengeParticipant.challenge_id).where(
        CommunityChallengeParticipant.participant_profile_id == viewer_profile_id
    )
    own_invite = select(CommunityChallengeInvite.challenge_id).where(
        or_(
            CommunityChallengeInvite.inviter_profile_id == viewer_profile_id,
            CommunityChallengeInvite.invitee_profile_id == viewer_profile_id,
        )
    )
    hidden_clubs = _hidden_private_club_ids(db, viewer_profile_id=viewer_profile_id)

    club_branch = CommunityChallenge.club_id.isnot(None)
    if hidden_clubs:
        club_branch = and_(
            club_branch,
            CommunityChallenge.club_id.notin_(hidden_clubs),
        )

    return or_(
        CommunityChallenge.author_profile_id == viewer_profile_id,
        CommunityChallenge.id.in_(own_participation),
        CommunityChallenge.id.in_(own_invite),
        club_branch,
        and_(
            CommunityChallenge.club_id.is_(None),
            CommunityChallenge.type.in_(sorted(GLOBAL_CHALLENGE_TYPES)),
        ),
    )


def _blocked_author_predicate(db: Session, *, viewer_profile_id: int):
    """A blokkolt szerzők kizárása, vagy ``None``, ha nincs blokk.

    A blokk-halmaz EGY lekérdezés (``list_block_pairs_for_viewer``),
    nem soronkénti predikátum — a Kör 8 lapszintű minta.
    """
    blocked = list_block_pairs_for_viewer(db, viewer_profile_id=viewer_profile_id)
    if not blocked:
        return None
    return CommunityChallenge.author_profile_id.notin_(sorted(blocked))


def _status_predicate(*, status_filter: str | None, now: datetime):
    if status_filter == CHALLENGE_STATUS_ACTIVE:
        return and_(
            CommunityChallenge.starts_at <= now, CommunityChallenge.ends_at >= now
        )
    if status_filter == CHALLENGE_STATUS_UPCOMING:
        return CommunityChallenge.starts_at > now
    if status_filter == CHALLENGE_STATUS_ENDED:
        return CommunityChallenge.ends_at < now
    return None


def _author_public_ids(db: Session, rows: list[CommunityChallenge]) -> dict[int, uuid.UUID]:
    """Szerző belső id → public_id, EGY lekérdezésben.

    Soronkénti feloldás egy 100 elemű oldalon 100 kört jelentene —
    a Kör 24 klub-router ``_member_count`` per-sor hívása a
    precedens, amit itt szándékosan NEM ismétlünk meg.
    """
    if not rows:
        return {}
    ids = {row.author_profile_id for row in rows}
    result = db.execute(
        select(CommunityProfile.id, CommunityProfile.public_id).where(
            CommunityProfile.id.in_(sorted(ids))
        )
    ).all()
    return {int(internal_id): public_id for internal_id, public_id in result}


def _to_view(row: CommunityChallenge, author_public_id: uuid.UUID) -> ChallengeView:
    return ChallengeView(
        public_id=row.public_id,
        author_public_id=author_public_id,
        type=row.type,
        metric=row.metric,
        difficulty=row.difficulty,
        starts_at=row.starts_at,
        ends_at=row.ends_at,
        version=row.version,
        club_id=row.club_id,
    )


def _page_from_rows(db: Session, rows: list[CommunityChallenge], *, limit: int) -> ChallengePage:
    """Sorok → oldal. A ``limit + 1``-edik sor LÉTE a következő oldal
    jelzése — a ``next_cursor`` csak akkor keletkezik, ha tényleg van
    még mit kérni. Enélkül a kliens egy üres oldalt kérne le a
    lista végén (a „halted vs continued" cella)."""
    has_more = len(rows) > limit
    page_rows = rows[:limit]
    authors = _author_public_ids(db, page_rows)
    items = tuple(
        _to_view(row, authors[row.author_profile_id])
        for row in page_rows
        if row.author_profile_id in authors
    )
    next_cursor = (
        _encode_cursor(created_at=page_rows[-1].created_at, row_id=page_rows[-1].id)
        if has_more and page_rows
        else None
    )
    return ChallengePage(items=items, next_cursor=next_cursor)


# ---------------------------------------------------------------------------
# Nyilvános műveletek.
# ---------------------------------------------------------------------------


def list_challenges(
    db: Session,
    *,
    viewer_profile_id: int,
    now: datetime,
    cursor: str | None = None,
    limit: int = CHALLENGE_PAGE_SIZE_DEFAULT,
    status_filter: str | None = None,
    club_public_id: uuid.UUID | None = None,
) -> ChallengePage:
    """A néző számára LÁTHATÓ kihívások egy oldala.

    A rendezés ``(created_at DESC, id DESC)``; a lapozás opaque
    kurzorral megy. A ``status_filter`` a szerver-idejű ablakra
    szűr (``active`` / ``upcoming`` / ``ended``) — a kliens órája
    soha nem dönt (A7 / §5.2).
    """
    bounded_limit = max(1, min(limit, CHALLENGE_PAGE_SIZE_MAX))
    stmt = select(CommunityChallenge).where(
        _visibility_predicate(db, viewer_profile_id=viewer_profile_id)
    )
    blocked_predicate = _blocked_author_predicate(
        db, viewer_profile_id=viewer_profile_id
    )
    if blocked_predicate is not None:
        stmt = stmt.where(blocked_predicate)
    status_predicate = _status_predicate(status_filter=status_filter, now=now)
    if status_predicate is not None:
        stmt = stmt.where(status_predicate)
    if club_public_id is not None:
        stmt = stmt.where(CommunityChallenge.club_id == str(club_public_id))
    if cursor is not None:
        decoded = _decode_cursor(cursor)
        if decoded is not None:
            cursor_created_at, cursor_id = decoded
            stmt = stmt.where(
                or_(
                    CommunityChallenge.created_at < cursor_created_at,
                    and_(
                        CommunityChallenge.created_at == cursor_created_at,
                        CommunityChallenge.id < cursor_id,
                    ),
                )
            )
    stmt = stmt.order_by(
        CommunityChallenge.created_at.desc(), CommunityChallenge.id.desc()
    ).limit(bounded_limit + 1)
    rows = list(db.execute(stmt).scalars().all())
    return _page_from_rows(db, rows, limit=bounded_limit)


def get_challenge(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> ChallengeView:
    """Egy kihívás részletei, ha a néző láthatja.

    Ismeretlen és rejtett egyaránt :class:`ChallengeNotFound` — a
    hívó a kettőt nem tudja megkülönböztetni.
    """
    stmt = select(CommunityChallenge).where(
        CommunityChallenge.public_id == challenge_public_id,
        _visibility_predicate(db, viewer_profile_id=viewer_profile_id),
    )
    blocked_predicate = _blocked_author_predicate(
        db, viewer_profile_id=viewer_profile_id
    )
    if blocked_predicate is not None:
        stmt = stmt.where(blocked_predicate)
    row = db.execute(stmt).scalars().first()
    if row is None:
        raise ChallengeNotFound("challenge not found")
    authors = _author_public_ids(db, [row])
    author_public_id = authors.get(row.author_profile_id)
    if author_public_id is None:  # pragma: no cover — az FK garantálja
        raise ChallengeNotFound("challenge not found")
    return _to_view(row, author_public_id)


def get_my_participation(
    db: Session,
    *,
    challenge_public_id: uuid.UUID,
    viewer_profile_id: int,
) -> ParticipationView | None:
    """A néző SAJÁT részvétel-/eredmény-állapota.

    ``None``, ha a nézőnek nincs sem résztvevő-, sem meghívás-sora
    ezen a kihíváson. A kihívás láthatóságát ugyanaz a predikátum
    dönti el, mint a részlet-végpontét — egy nem látható kihívásra
    404 megy, nem ``null`` (különben a ``null`` vs 404 különbség
    elárulná a rejtett sor LÉTÉT).
    """
    view = get_challenge(
        db,
        challenge_public_id=challenge_public_id,
        viewer_profile_id=viewer_profile_id,
    )
    challenge_id = db.execute(
        select(CommunityChallenge.id).where(
            CommunityChallenge.public_id == view.public_id
        )
    ).scalar_one()

    viewer_public_id = db.execute(
        select(CommunityProfile.public_id).where(
            CommunityProfile.id == viewer_profile_id
        )
    ).scalar_one_or_none()
    if viewer_public_id is None:  # pragma: no cover — a hívó feloldotta
        return None

    participant = db.execute(
        select(CommunityChallengeParticipant).where(
            CommunityChallengeParticipant.challenge_id == challenge_id,
            CommunityChallengeParticipant.participant_profile_id == viewer_profile_id,
        )
    ).scalars().first()

    invite = db.execute(
        select(CommunityChallengeInvite)
        .where(
            CommunityChallengeInvite.challenge_id == challenge_id,
            CommunityChallengeInvite.invitee_profile_id == viewer_profile_id,
        )
        .order_by(
            CommunityChallengeInvite.created_at.desc(),
            CommunityChallengeInvite.id.desc(),
        )
    ).scalars().first()

    if participant is None and invite is None:
        return None

    if invite is not None:
        invite_state = invite.state
    else:
        # Résztvevő-sor meghívás nélkül: a sor CSAK elfogadásból
        # keletkezhet (``accept_invite``), tehát az állapot
        # ``accepted``. Ez a mező NEM találgatás — a résztvevő-sor
        # létezése maga az elfogadás bizonyítéka.
        invite_state = "accepted"

    return ParticipationView(
        participant_public_id=viewer_public_id,
        invite_state=invite_state,
        best_metric_value=None if participant is None else participant.best_metric_value,
    )


__all__ = [
    "CHALLENGE_PAGE_SIZE_DEFAULT",
    "CHALLENGE_PAGE_SIZE_MAX",
    "CHALLENGE_STATUS_ACTIVE",
    "CHALLENGE_STATUS_ALLOWLIST",
    "CHALLENGE_STATUS_ENDED",
    "CHALLENGE_STATUS_UPCOMING",
    "ChallengeNotFound",
    "ChallengePage",
    "ChallengeView",
    "GLOBAL_CHALLENGE_TYPES",
    "ParticipationView",
    "get_challenge",
    "get_my_participation",
    "is_allowed_challenge_status",
    "list_challenges",
]
