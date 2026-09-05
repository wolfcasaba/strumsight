"""End-to-end mérés a klub-router végpontjaira.

MÉRT hiány (2026-09-05): a ``services/club_service.py`` a Kör 24 óta létezik
és tesztelt, és a ``ClubMembershipView`` docstringje ki is mondja, hogy „a
future router rounds it through Pydantic" — az a router SOSEM készült el. A
Flutter-oldali ``CommunityClubRepository`` kilenc metódusa így végpont nélkül
állt, és a három klub-képernyő elérhetetlen maradt.

Ez a modul a VALÓDI HTTP-felületet méri, nem a service-t — annak megvan a
saját sora (``test_club_service.py``). Amit itt mérünk: a wire-alak
(leak-guard + a néző saját szerepe), a kivétel → státusz leképezés, és a
``community_clubs_enabled`` regisztrációs kapu.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok: a `_make_test_engine()` a `Base.metadata`-ból
# hozza létre a táblákat.
from app.community import build_community_router
from app.community.models.club import CommunityClub  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.services.club_content_service import pin_post
from app.config import Settings
from app.database import Base


def _profile_for(session_factory, email: str) -> uuid.UUID:
    """Community-profil a megadott e-mailű felhasználóhoz."""
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
def clubs_client():
    """Klub-kapuval BEKAPCSOLT app + két hitelesített, profillal rendelkező user."""
    settings = Settings(community_enabled=True, community_clubs_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, owner_headers = make_authenticated_user(
            session_factory, email="owner@strumsight.app"
        )
        _, other_headers = make_authenticated_user(
            session_factory, email="other@strumsight.app"
        )
        owner_public = _profile_for(session_factory, "owner@strumsight.app")
        other_public = _profile_for(session_factory, "other@strumsight.app")
        try:
            yield client, owner_headers, other_headers, owner_public, other_public
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _create_club(client, headers, *, name="A klub", visibility="public") -> dict:
    response = client.post(
        "/community/clubs",
        headers=headers,
        json={
            "name": name,
            "description": "leírás",
            "visibility": visibility,
            "idempotency_key": f"club-{name}",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


class TestClubRouterEndToEnd:
    def test_a1_create_returns_201_with_the_leak_guarded_shape(self, clubs_client):
        client, owner, _, owner_public, _ = clubs_client

        club = _create_club(client, owner)

        assert uuid.UUID(club["public_id"])
        assert club["name"] == "A klub"
        assert club["owner_public_id"] == str(owner_public)
        # Leak-guard: belső id és owner_profile_id NEM megy ki.
        assert "id" not in club
        assert "owner_profile_id" not in club
        # A létrehozó azonnal tag — a `my_role` a service-ből jön.
        assert club["my_role"] is not None
        assert club["member_count"] >= 1

    def test_a2_list_shows_the_club_to_the_owner(self, clubs_client):
        client, owner, _, _, _ = clubs_client
        created = _create_club(client, owner)

        response = client.get("/community/clubs", headers=owner)

        assert response.status_code == 200, response.text
        page = response.json()
        assert created["public_id"] in [item["public_id"] for item in page["items"]]
        # A service `limit`-alapú, nem kurzoros — a mező jelen van, de üres.
        assert page["next_cursor"] is None

    def test_a3_my_role_is_per_viewer_not_a_global_field(self, clubs_client):
        """A `my_role` a NÉZŐRE vonatkozik, nem a klub tulajdonsága.

        Ez a cella azt a hibaosztályt fogja, amit a posts-router F2 javító
        köre mért: ott a szerző-azonosítót a HÍVÓÉBÓL oldották fel. Itt a
        veszély ugyanaz — ha a `my_role` a klub sorából jönne, minden néző
        a tulajdonos szerepét látná.
        """
        client, owner, other, _, _ = clubs_client
        created = _create_club(client, owner, visibility="public")

        as_owner = client.get(
            f"/community/clubs/{created['public_id']}", headers=owner
        ).json()
        as_other = client.get(
            f"/community/clubs/{created['public_id']}", headers=other
        ).json()

        assert as_owner["my_role"] is not None
        assert as_other["my_role"] is None
        # A klub AZONOS — csak a néző szerepe különbözik.
        assert as_owner["public_id"] == as_other["public_id"]
        assert as_owner["member_count"] == as_other["member_count"]

    def test_a4_member_list_carries_only_public_ids(self, clubs_client):
        client, owner, _, owner_public, _ = clubs_client
        created = _create_club(client, owner)

        response = client.get(
            f"/community/clubs/{created['public_id']}/members", headers=owner
        )

        assert response.status_code == 200, response.text
        items = response.json()["items"]
        assert len(items) >= 1
        row = items[0]
        assert row["profile_public_id"] == str(owner_public)
        assert row["role"]
        assert "profile_id" not in row
        assert "club_id" not in row

    def test_a5_join_reports_what_actually_happened(self, clubs_client):
        """A válasz megkülönbözteti a TAGSÁGOT a FÜGGŐ KÉRELEMTŐL.

        A kettő összemosása az „optimista jelölés" hibaosztálya lenne: a UI
        csatlakozottnak mutatná a felhasználót, miközben csak kérelem ment be.
        """
        client, owner, other, _, _ = clubs_client
        created = _create_club(client, owner, visibility="public")

        response = client.post(
            f"/community/clubs/{created['public_id']}/join", headers=other, json={}
        )

        assert response.status_code == 200, response.text
        assert response.json()["outcome"] in {"joined", "requested", "unchanged"}

    def test_a6_an_unknown_club_is_404_not_500(self, clubs_client):
        client, owner, _, _, _ = clubs_client

        response = client.get(f"/community/clubs/{uuid.uuid4()}", headers=owner)

        assert response.status_code == 404, response.text

    def test_a7_a_caller_without_a_community_profile_is_404(self):
        settings = Settings(community_enabled=True, community_clubs_enabled=True)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        try:
            with TestClient(app) as client:
                _, headers = make_authenticated_user(session_factory)

                response = client.get("/community/clubs", headers=headers)

                assert response.status_code == 404, response.text
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_a8_an_undocumented_body_field_is_refused(self, clubs_client):
        client, owner, _, _, _ = clubs_client

        response = client.post(
            "/community/clubs",
            headers=owner,
            json={"name": "X", "visibility": "public", "owner_profile_id": 1},
        )

        assert response.status_code == 422, response.text


@pytest.fixture
def club_feed_client():
    """Klub-kapu + ÍRÁS-kapu + VALÓDI kurzus-aláíró kulcs.

    A klub-feed HMAC-cel írja alá a kurzort, és FAIL-CLOSED módon 503-at ad
    a fejlesztői alapértékre. A teszt ezért valódi kulcsot ad — nem kerüli
    meg az őrt.
    """
    settings = Settings(
        community_enabled=True,
        community_clubs_enabled=True,
        community_writes_enabled=True,
        secret_key="a-real-32-char-test-secret-key-value",
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, owner_headers = make_authenticated_user(
            session_factory, email="owner@strumsight.app"
        )
        _profile_for(session_factory, "owner@strumsight.app")
        try:
            yield client, owner_headers, session_factory
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _internal_club_id(session_factory, public_id: str) -> int:
    db = session_factory()
    try:
        row = (
            db.query(CommunityClub)
            .filter(CommunityClub.public_id == uuid.UUID(public_id))
            .first()
        )
        assert row is not None
        return int(row.id)
    finally:
        db.close()


def _owner_profile_pk(session_factory) -> int:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"),
                {"e": "owner@strumsight.app"},
            ).first()[0]
        )
        profile = (
            db.query(CommunityProfile)
            .filter(CommunityProfile.user_id == user_id)
            .first()
        )
        assert profile is not None
        return int(profile.id)
    finally:
        db.close()


def _club_post(client, headers, *, club_id: int, key: str) -> str:
    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "klub-poszt",
            "club_id": club_id,
            "idempotency_key": key,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


class TestClubFeedEndpoint:
    """A `GET /community/clubs/{id}/feed` — a `list_club_feed` service
    HTTP-felülete, a KÖZÖS poszt-projekcióval."""

    def test_a13_the_club_feed_carries_full_items_with_counts(self, club_feed_client):
        client, owner, session_factory = club_feed_client
        club = _create_club(client, owner)
        club_id = _internal_club_id(session_factory, club["public_id"])
        post_public_id = _club_post(client, owner, club_id=club_id, key="cp-1")

        response = client.get(
            f"/community/clubs/{club['public_id']}/feed", headers=owner
        )

        assert response.status_code == 200, response.text
        items = response.json()["items"]
        assert [item["public_id"] for item in items] == [post_public_id]
        item = items[0]
        # A klub-feed UGYANAZT a wire-alakot adja, mint a következés-feed —
        # számlálóstul, néző-állapotostul. A nulla itt IGAZ (nincs
        # interakció), és ez a kontroll az A14-hez.
        assert item["reaction_count"] == 0
        assert item["comment_count"] == 0
        assert item["viewer_reaction"] is None
        assert "resource_version" in item

    def test_a14_the_club_feed_counts_reflect_real_interactions(self, club_feed_client):
        """A közös projekció a klub-feeden IS valódi számot ad.

        Ez a cella zárja azt, hogy a klub-router külön úton, kitalált
        nullákkal töltse a számlálókat.
        """
        client, owner, session_factory = club_feed_client
        club = _create_club(client, owner)
        club_id = _internal_club_id(session_factory, club["public_id"])
        post_public_id = _club_post(client, owner, club_id=club_id, key="cp-2")

        reacted = client.put(
            f"/community/posts/{post_public_id}/reaction",
            headers=owner,
            json={"kind": "support"},
        )
        assert reacted.status_code == 200, reacted.text

        item = client.get(
            f"/community/clubs/{club['public_id']}/feed", headers=owner
        ).json()["items"][0]

        assert item["reaction_count"] == 1
        assert item["viewer_reaction"] == "support"

    def test_a15_a_pinned_post_is_a_full_item_not_a_four_field_stub(
        self, club_feed_client
    ):
        """A kitűzött poszt UGYANOLYAN teljes elem, mint a feedé.

        Egy szűkebb alak arra kényszerítené a klienst, hogy nullákat
        rajzoljon a kitűzött poszt alá, miközben a feedben ugyanaz a poszt
        a valódi számokat mutatja.
        """
        client, owner, session_factory = club_feed_client
        club = _create_club(client, owner)
        club_id = _internal_club_id(session_factory, club["public_id"])
        post_public_id = _club_post(client, owner, club_id=club_id, key="cp-3")
        client.put(
            f"/community/posts/{post_public_id}/reaction",
            headers=owner,
            json={"kind": "celebrate"},
        )
        db = session_factory()
        try:
            pin_post(
                db,
                actor_profile_id=_owner_profile_pk(session_factory),
                club_public_id=uuid.UUID(club["public_id"]),
                post_public_id=uuid.UUID(post_public_id),
                now=datetime.now(timezone.utc),
            )
            db.commit()
        finally:
            db.close()

        response = client.get(
            f"/community/clubs/{club['public_id']}/pinned", headers=owner
        )

        assert response.status_code == 200, response.text
        items = response.json()["items"]
        assert len(items) == 1
        item = items[0]
        assert item["public_id"] == post_public_id
        assert item["reaction_count"] == 1
        assert item["viewer_reaction"] == "celebrate"
        assert item["moderation_state"] == "visible"
        # NINCS lapozás: a kitűzhető posztok száma korlátos.
        assert "next_cursor" not in response.json()


class TestClubPinnedEndpoint:
    """A `GET /community/clubs/{id}/pinned` — a `list_club_pinned` service
    HTTP-felülete.

    A service a Kör 24 óta létezik és tesztelt; router nélkül a Flutter
    `CommunityFeedRepository.clubPinned` metódusának nem volt mit hívnia.
    """

    def test_a11_a_member_sees_the_pinned_posts(self, clubs_client):
        client, owner, _, _, _ = clubs_client
        created = _create_club(client, owner)

        response = client.get(
            f"/community/clubs/{created['public_id']}/pinned", headers=owner
        )

        assert response.status_code == 200, response.text
        body = response.json()
        # Frissen létrehozott klub: még nincs kitűzött poszt. Ez a
        # kontroll-cella — az üres lista IGAZ, és nélküle az A12 nem
        # bizonyítaná, hogy a 404 a tagságról szól.
        assert body["items"] == []
        # NINCS `next_cursor`: a kitűzhető posztok száma korlátos, a lista
        # definíció szerint egyoldalas.
        assert "next_cursor" not in body

    def test_a12_a_non_member_gets_404_not_403(self, clubs_client):
        """A nem tag 404-et kap, nem 403-at.

        Egy 403 elárulná, hogy a klub létezik, csak nem látható —
        ugyanaz a leak-guard, amit a komment-lista üres oldala visz. A
        kontroll az A11: ugyanez az útvonal a TAGNAK 200-at ad.
        """
        client, owner, other, _, _ = clubs_client
        created = _create_club(client, owner, visibility="private")

        response = client.get(
            f"/community/clubs/{created['public_id']}/pinned", headers=other
        )

        assert response.status_code == 404, response.text


class TestClubsGate:
    """A `community_clubs_enabled` REGISZTRÁCIÓS kapu."""

    def _paths(self, *, clubs_enabled: bool) -> set[str]:
        settings = Settings(
            community_enabled=True, community_clubs_enabled=clubs_enabled
        )
        router = build_community_router(settings)
        assert router is not None
        return {route.path for route in router.routes}

    def test_a9_club_routes_are_absent_when_the_gate_is_off(self):
        on = self._paths(clubs_enabled=True)
        off = self._paths(clubs_enabled=False)

        assert "/community/clubs" in on
        # Kapu KI: a route-ok NEM regisztrálódnak — 404, nem futásidejű 403.
        assert "/community/clubs" not in off
        assert not any(path.startswith("/community/clubs") for path in off)

    def test_a10_the_other_routers_are_unaffected_by_the_clubs_gate(self):
        on = self._paths(clubs_enabled=True)
        off = self._paths(clubs_enabled=False)

        # A kapu KIZÁRÓLAG a klub-felületet mozdítja: minden más útvonal
        # mindkét álláson ott van.
        non_club_on = {p for p in on if not p.startswith("/community/clubs")}
        assert non_club_on == off
