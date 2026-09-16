"""Értesítés-kibocsátás a VALÓDI community-eseményekre (2026-09-05).

**Miért született.** A ``notification_service.create_notification`` a Kör 20
óta létezik és tesztelt, de a teljes ``backend/app/`` fában SEMMI nem hívta
(grep-pel mérve). Az inbox tehát szerkezetileg üres volt: a service, a
2026-09-05-én megírt router és a Flutter-repository együtt is mindig üres
listát adott volna. A csővezeték hibátlan volt — nem volt, ami betáplálja.

Ez a modul a hiányzó betáplálás. Nem hoz új üzleti szabályt: az összevonás,
a dedup, a láthatóság és a blokk-szűrés mind a service-ben él.

**Három szabály, amit ez a modul tart be:**

1. **A kibocsátás SOSEM buktathatja el az elsődleges műveletet.** Egy
   komment akkor is létrejön, ha az értesítés nem. A hívás ezért
   SAVEPOINT-ban fut (``begin_nested``): ha elhasal, csak az értesítés
   gördül vissza, a komment nem — és a session sem marad használhatatlan
   állapotban.

2. **Csak a VÁRT kivételt nyeljük el.** A hiányzó profil és az érvénytelen
   típus ismert, kezelhető ág. Bármi más továbbmegy: egy `try/except
   Exception` itt pontosan az a néma no-op osztály lenne, amit a projekt
   build-jegyzete külön nevesít.

3. **Magának senki nem kap értesítést.** A saját posztod kommentelése vagy
   a saját posztodra adott reakció nem esemény — az inbox tele lenne a
   felhasználó SAJÁT tevékenységével, és az olvasatlan-jelvény
   használhatatlan lenne.

**A ``title_key`` KULCS, nem szöveg.** A szerver nem tudja, milyen nyelven
fut az app. A kulcsok alakja a Flutter ``CommunityNotificationItem``
követelménye szerint ``^[a-z][A-Za-z0-9_]*$`` — egy pontokkal tagolt kulcs
a kliens-oldali entitáson elhasalna.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy.orm import Session

from ..models.notification import (
    NOTIFICATION_TYPE_CLUB_INVITE,
    NOTIFICATION_TYPE_COMMENT,
    NOTIFICATION_TYPE_FOLLOW_ACCEPTED,
    NOTIFICATION_TYPE_FOLLOW_REQUEST,
    NOTIFICATION_TYPE_REACTION_SUMMARY,
)
from ..models.post import CommunityPost
from ..models.profile import CommunityProfile
from .notification_service import (
    InvalidNotificationType,
    NotificationActorNotFound,
    NotificationProfileNotFound,
    create_notification,
)

#: A várt, kezelhető kibocsátási hibák. Minden MÁS kivétel továbbmegy.
_EXPECTED_EMIT_FAILURES = (
    NotificationProfileNotFound,
    NotificationActorNotFound,
    InvalidNotificationType,
)

# A kulcsok pontosan azok, amiket a Flutter
# ``community_notifications_screen.dart::_lookupKey`` felold — lowerCamelCase,
# az ARB-katalógus (``lib/l10n/features/community_*.arb``) neveivel azonosak.
#
# MÉRT csapda (2026-09-05): a képernyő az ismeretlen kulcsot NEM hibaként
# kezeli, hanem magát a kulcs-stringet írja ki („so the UI never crashes on a
# future-round key"). Egy snake_case kulcs tehát nem hibaüzenetet adott volna,
# hanem a felhasználó képernyőjén megjelenő
# ``community_notification_comment_title`` szöveget. A fail-safe elnyelte
# volna az eltérést — ezért kell a kulcsoknak BÁJTRA egyezniük.
TITLE_KEY_COMMENT = "communityNotificationCommentTitle"
TITLE_KEY_REACTION_SUMMARY = "communityNotificationReactionSummaryTitle"
TITLE_KEY_FOLLOW_REQUEST = "communityNotificationFollowRequestTitle"
TITLE_KEY_FOLLOW_ACCEPTED = "communityNotificationFollowAcceptedTitle"
TITLE_KEY_CLUB_INVITE = "communityNotificationClubInviteTitle"


def _post_author_public_id(db: Session, post_public_id: uuid.UUID) -> uuid.UUID | None:
    """A poszt szerzőjének ``public_id``-ja, vagy ``None``.

    ORM-en át, NEM nyers SQL-lel: a ``public_id`` ``Uuid`` típusú oszlop, és
    a string-összehasonlítás dialektusfüggően nem illeszkedik (SQLite-on
    némán üres eredményt ad — pontosan az a néma hiba, amit el akarunk
    kerülni).

    ``None`` akkor, ha a poszt nincs meg; az értesítés ilyenkor kimarad. A
    poszt LÉTEZÉSÉT a hívó felület már ellenőrizte.
    """
    row = (
        db.query(CommunityProfile.public_id)
        .join(CommunityPost, CommunityPost.profile_id == CommunityProfile.id)
        .filter(CommunityPost.public_id == post_public_id)
        .first()
    )
    if row is None:
        return None
    raw = row[0]
    return uuid.UUID(hex=raw) if isinstance(raw, str) else raw


def _emit(db: Session, **kwargs: object) -> None:
    """A ``create_notification`` hívása SAVEPOINT-ban, várt hibák elnyelésével.

    A SAVEPOINT a lényeg: enélkül egy elhasalt értesítés a session-t is
    használhatatlan állapotban hagyná, és az elsődleges művelet commitja
    is elbukna — pontosan az, amit az 1. szabály tilt.
    """
    try:
        with db.begin_nested():
            create_notification(db, **kwargs)  # type: ignore[arg-type]
    except _EXPECTED_EMIT_FAILURES:
        # A címzettnek nincs community-profilja, vagy a típus nem
        # megengedett. Egyik sem az elsődleges művelet hibája.
        return


def notify_post_commented(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """A poszt szerzőjének értesítése egy új kommentről.

    ÖSSZEVONT (``aggregate=True``): egy heves beszélgetés alatt tíz komment
    EGY inbox-tételt ad, tízes számlálóval — nem tíz külön sort. Enélkül a
    jelvény percek alatt használhatatlanná válna.
    """
    author = _post_author_public_id(db, post_public_id)
    if author is None or author == actor_public_id:
        # A saját posztod kommentelése nem esemény.
        return
    _emit(
        db,
        recipient_public_id=author,
        notification_type=NOTIFICATION_TYPE_COMMENT,
        title_key=TITLE_KEY_COMMENT,
        body_key=None,
        actor_public_id=actor_public_id,
        entity_type="post",
        entity_id=str(post_public_id),
        dedup_key=None,
        aggregate=True,
        now=now,
    )


def notify_post_reaction(
    db: Session,
    *,
    post_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """A poszt szerzőjének értesítése egy reakcióról.

    A típus neve — ``reaction_summary`` — magát a szándékot mondja ki: a
    reakciók ÖSSZEVONVA érkeznek. Egy poszt, ami tíz reakciót kap, egy
    tételt ad tízes számlálóval.

    A fajta-váltás (``support`` → ``celebrate``) is ide fut, és ez helyes:
    a szerző szempontjából ugyanaz az esemény történt — valaki reagált —,
    és az összevonás miatt nem keletkezik második tétel.
    """
    author = _post_author_public_id(db, post_public_id)
    if author is None or author == actor_public_id:
        return
    _emit(
        db,
        recipient_public_id=author,
        notification_type=NOTIFICATION_TYPE_REACTION_SUMMARY,
        title_key=TITLE_KEY_REACTION_SUMMARY,
        body_key=None,
        actor_public_id=actor_public_id,
        entity_type="post",
        entity_id=str(post_public_id),
        dedup_key=None,
        aggregate=True,
        now=now,
    )


def notify_follow_request(
    db: Session,
    *,
    target_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """A cél felhasználó értesítése egy követés-kérelemről.

    NEM összevont, DEDUPLIKÁLT: ugyanattól a személytől érkező második
    kérelem nem ad új tételt. Egy összevont számláló itt félrevezetne — a
    „3 követés-kérelem Anitától" nem értelmes állítás.
    """
    if target_public_id == actor_public_id:
        return
    _emit(
        db,
        recipient_public_id=target_public_id,
        notification_type=NOTIFICATION_TYPE_FOLLOW_REQUEST,
        title_key=TITLE_KEY_FOLLOW_REQUEST,
        body_key=None,
        actor_public_id=actor_public_id,
        entity_type="profile",
        entity_id=str(actor_public_id),
        dedup_key=f"follow_request:{actor_public_id}:{target_public_id}",
        aggregate=False,
        now=now,
    )


def notify_follow_accepted(
    db: Session,
    *,
    target_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """A kérelmező értesítése arról, hogy elfogadták."""
    if target_public_id == actor_public_id:
        return
    _emit(
        db,
        recipient_public_id=target_public_id,
        notification_type=NOTIFICATION_TYPE_FOLLOW_ACCEPTED,
        title_key=TITLE_KEY_FOLLOW_ACCEPTED,
        body_key=None,
        actor_public_id=actor_public_id,
        entity_type="profile",
        entity_id=str(actor_public_id),
        dedup_key=f"follow_accepted:{actor_public_id}:{target_public_id}",
        aggregate=False,
        now=now,
    )


def notify_follow_accepted_by_request(
    db: Session,
    *,
    request_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """Az elfogadás értesítése a KÉRELEM azonosítójából.

    Az elfogadó végpont csak a kérelem azonosítóját ismeri; a címzett a
    kérelmező. A feloldás ezért itt történik, egy helyen — a routernek nem
    kell a követés-modellt ismernie.
    """
    from ..models.social_graph import CommunityFollowRequest

    row = (
        db.query(CommunityProfile.public_id)
        .join(
            CommunityFollowRequest,
            CommunityFollowRequest.requester_profile_id == CommunityProfile.id,
        )
        .filter(CommunityFollowRequest.public_id == request_public_id)
        .first()
    )
    if row is None:
        return
    raw = row[0]
    requester = uuid.UUID(hex=raw) if isinstance(raw, str) else raw
    notify_follow_accepted(
        db, target_public_id=requester, actor_public_id=actor_public_id, now=now
    )


def notify_club_invite(
    db: Session,
    *,
    club_public_id: uuid.UUID,
    target_public_id: uuid.UUID,
    actor_public_id: uuid.UUID,
    now: datetime,
) -> None:
    """A meghívott értesítése egy klub-meghívóról.

    DEDUPLIKÁLT a ``(klub, meghívott)`` páron: egy újraküldött meghívó nem
    ad második tételt.
    """
    if target_public_id == actor_public_id:
        return
    _emit(
        db,
        recipient_public_id=target_public_id,
        notification_type=NOTIFICATION_TYPE_CLUB_INVITE,
        title_key=TITLE_KEY_CLUB_INVITE,
        body_key=None,
        actor_public_id=actor_public_id,
        entity_type="club",
        entity_id=str(club_public_id),
        dedup_key=f"club_invite:{club_public_id}:{target_public_id}",
        aggregate=False,
        now=now,
    )


__all__ = [
    "TITLE_KEY_CLUB_INVITE",
    "TITLE_KEY_COMMENT",
    "TITLE_KEY_FOLLOW_ACCEPTED",
    "TITLE_KEY_FOLLOW_REQUEST",
    "TITLE_KEY_REACTION_SUMMARY",
    "notify_club_invite",
    "notify_follow_accepted",
    "notify_follow_accepted_by_request",
    "notify_follow_request",
    "notify_post_commented",
    "notify_post_reaction",
]
