"""Az értesítés-kibocsátás mérése a VALÓDI eseményeken.

MÉRT hiány (2026-09-05): a ``create_notification`` a Kör 20 óta létezett és
tesztelt volt, de a teljes ``backend/app/`` fában SEMMI nem hívta. Az inbox
tehát szerkezetileg üres volt — a service, a router és a Flutter-repository
együtt is mindig üres listát adott volna.

Ez a modul azt méri, hogy a komment / reakció / klub-meghívó TÉNYLEGESEN
inbox-tételt szül, a végponton keresztül — nem az emitter-függvényt hívja
közvetlenül. A service saját szabályait (összevonás, dedup, láthatóság) a
``test_notification_service.py`` méri; itt a BEKÖTÉS a tárgy.
"""

from __future__ import annotations

import json
import pathlib
import uuid

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

from app.community.models.club import CommunityClub  # noqa: F401
from app.community.models.comment import CommunityComment  # noqa: F401
from app.community.models.notification import CommunityNotification  # noqa: F401
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.notifications import emitters
from app.community.notifications.notification_service import (
    NotificationProfileNotFound,
)
from app.config import Settings
from app.database import Base


def _profile_public_id(session_factory, email: str) -> uuid.UUID:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.commit()
        return profile.public_id
    finally:
        db.close()


@pytest.fixture
def emission_client():
    """Minden érintett kapu BE: írás + klubok."""
    settings = Settings(
        community_enabled=True,
        community_writes_enabled=True,
        community_clubs_enabled=True,
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, author = make_authenticated_user(
            session_factory, email="author@strumsight.app"
        )
        _, other = make_authenticated_user(
            session_factory, email="other@strumsight.app"
        )
        _profile_public_id(session_factory, "author@strumsight.app")
        other_public = _profile_public_id(session_factory, "other@strumsight.app")
        try:
            yield client, author, other, other_public
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _create_post(client, headers, *, key: str) -> str:
    response = client.post(
        "/community/posts",
        headers=headers,
        json={"audience": "public", "body": "poszt", "idempotency_key": key},
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


def _author_public_id(client, headers) -> str:
    """A hívó saját profiljának `public_id`-ja — a felületről, nem a DB-ből."""
    response = client.get("/community/profiles/me", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()["public_id"]


def _inbox(client, headers) -> dict:
    response = client.get("/community/notifications", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


class TestCommentEmission:
    def test_d1_a_comment_reaches_the_post_author_inbox(self, emission_client):
        client, author, other, _ = emission_client
        post_id = _create_post(client, author, key="p-1")

        created = client.post(
            f"/community/posts/{post_id}/comments",
            headers=other,
            json={"body": "szép", "idempotency_key": "c-1"},
        )
        assert created.status_code == 201, created.text

        inbox = _inbox(client, author)
        assert inbox["unread_count"] == 1
        item = inbox["items"][0]
        assert item["type"] == "comment"
        assert item["entity_type"] == "post"
        assert item["entity_id"] == post_id
        assert item["is_read"] is False

    def test_d2_commenting_on_your_own_post_notifies_nobody(self, emission_client):
        """A saját posztod kommentelése nem esemény.

        Enélkül az inbox tele lenne a felhasználó SAJÁT tevékenységével, és
        az olvasatlan-jelvény használhatatlan lenne. A D1 a kontroll: ott
        UGYANEZ a hívás ad tételt, csak másik szerzővel.
        """
        client, author, _, _ = emission_client
        post_id = _create_post(client, author, key="p-2")

        client.post(
            f"/community/posts/{post_id}/comments",
            headers=author,
            json={"body": "magamnak", "idempotency_key": "c-2"},
        )

        assert _inbox(client, author)["items"] == []

    def test_d3_a_burst_of_comments_aggregates_into_one_item(self, emission_client):
        """Tíz komment EGY tétel, nem tíz sor.

        Enélkül egy élénk beszélgetés percek alatt elárasztaná az inboxot.
        """
        client, author, other, _ = emission_client
        post_id = _create_post(client, author, key="p-3")

        for i in range(3):
            client.post(
                f"/community/posts/{post_id}/comments",
                headers=other,
                json={"body": f"komment {i}", "idempotency_key": f"c-3-{i}"},
            )

        inbox = _inbox(client, author)
        assert len(inbox["items"]) == 1
        assert inbox["items"][0]["aggregate_count"] == 3
        # A jelvény EGYET mutat: a felhasználónak egy beszélgetése van,
        # nem három elintéznivalója.
        assert inbox["unread_count"] == 1


class TestReactionEmission:
    def test_d4_a_reaction_reaches_the_author_and_a_kind_change_does_not_duplicate(
        self, emission_client
    ):
        """A fajta-váltás nem szül második tételt.

        A szerző szempontjából ugyanaz történt — valaki reagált. Két tétel
        azt sugallná, hogy két ember reagált.
        """
        client, author, other, _ = emission_client
        post_id = _create_post(client, author, key="p-4")

        client.put(
            f"/community/posts/{post_id}/reaction",
            headers=other,
            json={"kind": "support"},
        )
        client.put(
            f"/community/posts/{post_id}/reaction",
            headers=other,
            json={"kind": "celebrate"},
        )

        inbox = _inbox(client, author)
        assert len(inbox["items"]) == 1
        assert inbox["items"][0]["type"] == "reaction_summary"

    def test_d5_reacting_to_your_own_post_notifies_nobody(self, emission_client):
        client, author, _, _ = emission_client
        post_id = _create_post(client, author, key="p-5")

        client.put(
            f"/community/posts/{post_id}/reaction",
            headers=author,
            json={"kind": "support"},
        )

        assert _inbox(client, author)["items"] == []


class TestClubInviteEmission:
    def test_d6_an_invite_reaches_the_invitee_and_is_deduplicated(
        self, emission_client
    ):
        """A meghívó nélkül a meghívott SOSEM tudna róla.

        A klub-lista csak a saját klubjait mutatja, tehát egy függő meghívó
        a felületen sehol nem jelenne meg.
        """
        client, author, other, other_public = emission_client
        club = client.post(
            "/community/clubs",
            headers=author,
            json={
                "name": "A klub",
                "description": "",
                "visibility": "public",
                "idempotency_key": "club-1",
            },
        )
        assert club.status_code == 201, club.text
        club_public_id = club.json()["public_id"]

        for i in range(2):
            client.post(
                f"/community/clubs/{club_public_id}/invites",
                headers=author,
                json={
                    "target_public_id": str(other_public),
                    "idempotency_key": f"inv-{i}",
                },
            )

        inbox = _inbox(client, other)
        # DEDUPLIKÁLT: az újraküldött meghívó nem ad második tételt.
        assert len(inbox["items"]) == 1
        assert inbox["items"][0]["type"] == "club_invite"
        assert inbox["items"][0]["entity_id"] == club_public_id


class TestFollowEmission:
    """A követés-kérelem és az elfogadás értesítése.

    A fixture profiljainak nincs adatvédelmi soruk, és a `follow_service`
    ilyenkor PRIVÁTNAK tekinti a profilt (biztonságos alapérték, ADR 0398
    §5) — a követés tehát KÉRELMET szül, nem azonnali élt.
    """

    def test_d8_a_follow_request_reaches_the_target(self, emission_client):
        client, author, other, _ = emission_client
        author_public = _author_public_id(client, author)

        requested = client.post(
            f"/community/profiles/{author_public}/follow",
            headers=other,
            json={"idempotency_key": "f-1"},
        )
        assert requested.status_code == 200, requested.text
        assert requested.json()["status"] == "requested"

        inbox = _inbox(client, author)
        assert len(inbox["items"]) == 1
        assert inbox["items"][0]["type"] == "follow_request"

    def test_d9_accepting_notifies_the_requester(self, emission_client):
        """Az elfogadás értesítése nélkül a kérelmező SOSEM tudná meg.

        A felületen nincs olyan lista, ami a saját kimenő kérelmei
        állapotát mutatná.
        """
        client, author, other, _ = emission_client
        author_public = _author_public_id(client, author)
        requested = client.post(
            f"/community/profiles/{author_public}/follow",
            headers=other,
            json={"idempotency_key": "f-2"},
        )
        request_id = requested.json()["request_id"]

        accepted = client.post(
            f"/community/follow-requests/{request_id}/accept",
            headers=author,
            json={"idempotency_key": "a-1"},
        )
        assert accepted.status_code == 200, accepted.text

        inbox = _inbox(client, other)
        assert len(inbox["items"]) == 1
        assert inbox["items"][0]["type"] == "follow_accepted"

    def test_d10_a_repeated_request_does_not_duplicate(self, emission_client):
        client, author, other, _ = emission_client
        author_public = _author_public_id(client, author)

        for i in range(2):
            client.post(
                f"/community/profiles/{author_public}/follow",
                headers=other,
                json={"idempotency_key": f"f-3-{i}"},
            )

        assert len(_inbox(client, author)["items"]) == 1


class TestTitleKeysResolveOnTheClient:
    """A kibocsátott `title_key` LÉTEZIK a kliens ARB-katalógusában.

    MÉRT csapda: a `community_notifications_screen.dart::_lookupKey` az
    ismeretlen kulcsot NEM hibaként kezeli, hanem magát a kulcs-stringet
    írja ki („so the UI never crashes on a future-round key"). Egy elgépelt
    vagy rossz alakú kulcs tehát nem hibaüzenetet adna, hanem a felhasználó
    képernyőjén megjelenő nyers kulcsot — a fail-safe elnyelné az eltérést.
    Ez a cella az egyetlen hely, ahol az eltérés láthatóvá válik.
    """

    def test_d11_every_emitted_title_key_exists_in_the_client_catalogue(self):
        arb_path = (
            pathlib.Path(__file__).resolve().parents[3]
            / "lib"
            / "l10n"
            / "features"
            / "community_en.arb"
        )
        assert arb_path.is_file(), f"az ARB-katalógus nincs meg: {arb_path}"
        catalogue = json.loads(arb_path.read_text(encoding="utf-8"))

        emitted = {
            emitters.TITLE_KEY_COMMENT,
            emitters.TITLE_KEY_REACTION_SUMMARY,
            emitters.TITLE_KEY_FOLLOW_REQUEST,
            emitters.TITLE_KEY_FOLLOW_ACCEPTED,
            emitters.TITLE_KEY_CLUB_INVITE,
        }
        missing = sorted(key for key in emitted if key not in catalogue)
        assert not missing, (
            f"a kliens nem tudja feloldani ezeket a kulcsokat: {missing}"
        )


class TestEmissionNeverBreaksThePrimaryAction:
    def test_d7_a_failing_emission_still_creates_the_comment(
        self, emission_client, monkeypatch
    ):
        """A kibocsátás bukása NEM buktathatja el a kommentet.

        A SAVEPOINT ezt védi: enélkül az elhasalt értesítés a session-t is
        használhatatlan állapotban hagyná, és a komment commitja is
        elbukna. A kontroll a D1 — ott ugyanez a hívás értesítést IS ad.
        """
        client, author, other, _ = emission_client
        post_id = _create_post(client, author, key="p-7")

        def _boom(*args, **kwargs):
            raise NotificationProfileNotFound("szimulált hiba")

        monkeypatch.setattr(emitters, "create_notification", _boom)

        created = client.post(
            f"/community/posts/{post_id}/comments",
            headers=other,
            json={"body": "megmarad", "idempotency_key": "c-7"},
        )

        assert created.status_code == 201, created.text
        # A komment TÉNYLEGESEN ott van a listában — nem csak a válasz volt 201.
        listed = client.get(f"/community/posts/{post_id}/comments", headers=other)
        assert listed.status_code == 200, listed.text
        assert [item["body"] for item in listed.json()["items"]] == ["megmarad"]
        # Értesítés viszont nem keletkezett.
        assert _inbox(client, author)["items"] == []
